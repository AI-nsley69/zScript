const std = @import("std");
const Lexer = @import("lexer.zig");
const Bytecode = @import("bytecode.zig");
const Vm = @import("vm.zig");
const Ast = @import("ast.zig");
const Value = @import("value.zig").Value;

const TokenType = Lexer.TokenType;
const OpCodes = Bytecode.OpCodes;
// const Frame = Bytecode.Frame;
// const RegisterSize = Bytecode.RegisterSize;

const Error = error{
    OutOfRegisters,
    OutOfConstants,
    InvalidJmpTarget,
    Unknown,
};

const CompilerFrame = struct {
    name: []const u8,
    ip: usize = 0,
    instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    reg_ptr: u8 = 1,
};

const Errors = (Error || std.mem.Allocator.Error);

pub const CompilerOutput = struct {
    const Self = @This();
    frames: []*Bytecode.Frame,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.frames) |frame| {
            allocator.free(frame.*.body);
        }
        allocator.free(self.frames);
    }
};

const Compiler = @This();

allocator: std.mem.Allocator,
ast: Ast.Program,
comp_frames: std.ArrayListUnmanaged(*CompilerFrame) = std.ArrayListUnmanaged(*CompilerFrame){},
frame_ptr: usize = 0,
variables: std.StringHashMapUnmanaged(u8) = std.StringHashMapUnmanaged(u8){},
functions: std.StringHashMapUnmanaged(u8) = std.StringHashMapUnmanaged(u8){},
err_msg: ?[]u8 = null,

fn current(self: *Compiler) *CompilerFrame {
    return self.comp_frames.items[self.frame_ptr];
}

fn getOut(self: *Compiler) std.ArrayListUnmanaged(u8).Writer {
    return self.current().instructions.writer(self.allocator);
}

pub fn compile(self: *Compiler) Errors!CompilerOutput {
    defer self.variables.deinit(self.allocator);
    defer self.comp_frames.deinit(self.allocator);
    // Create a pseudo main function for initial frame
    var no_params: [0]*Ast.Variable = .{};
    var empty_block: [0]Ast.Statement = .{};
    const no_body: Ast.Statement = .{ .node = .{ .block = .{ .statements = &empty_block } } };
    var main_func: Ast.Function = .{ .name = "main", .params = &no_params, .body = no_body };

    try self.functions.put(self.allocator, "main", 0);
    // Compile the actual frame
    const final_dst = try self.compileFrame(self.ast.statements.items, &main_func);
    // Emit return instruction at the end
    try self.getOut().writeAll(&.{ @intFromEnum(OpCodes.@"return"), final_dst });
    // Convert all comp frames to vm frames
    var frames: std.ArrayListUnmanaged(*Bytecode.Frame) = std.ArrayListUnmanaged(*Bytecode.Frame){};
    for (self.comp_frames.items) |compilerFrame| {
        const frame = try self.allocator.create(Bytecode.Frame);
        frame.* = .{ .name = compilerFrame.name, .body = try compilerFrame.instructions.toOwnedSlice(self.allocator), .reg_size = compilerFrame.reg_ptr };
        try frames.append(self.allocator, frame);
    }

    return .{ .frames = try frames.toOwnedSlice(self.allocator) };
}

pub fn compileFrame(self: *Compiler, target: []Ast.Statement, func: *Ast.Function) Errors!u8 {
    const previous_frame = self.frame_ptr;
    // Setup a new frame
    const compilerFrame = try self.allocator.create(CompilerFrame);
    compilerFrame.* = .{ .name = func.name };
    try self.comp_frames.append(self.allocator, compilerFrame);

    self.frame_ptr = self.comp_frames.items.len - 1;
    // Compile the new frame
    const out = self.getOut();
    // Load the parameters for the function (if exists)
    const reversed = try self.allocator.dupe(*Ast.Variable, func.params);
    defer self.allocator.free(reversed);
    std.mem.reverse(*Ast.Variable, reversed);
    for (reversed) |param| {
        try out.writeAll(&.{ @intFromEnum(OpCodes.load_param), try self.variable(param) });
    }
    // Compile the statements
    var final_dst: u8 = 0;
    for (target) |elem| {
        final_dst = try self.statement(elem);
    }
    self.frame_ptr = previous_frame;

    return final_dst;
}

fn statement(self: *Compiler, target: Ast.Statement) Errors!u8 {
    const node = target.node;
    return switch (node) {
        .expression => try self.expression(node.expression, null),
        .conditional => try self.conditional(node.conditional),
        .block => {
            var dst: u8 = 0;
            for (node.block.statements) |stmt| {
                dst = try self.statement(stmt);
            }
            return dst;
        },
        .loop => try self.loop(node.loop),
        .function => try self.function(node.function),
        .@"return" => try self.@"return"(node.@"return"),
    };
}

fn conditional(self: *Compiler, target: *Ast.Conditional) Errors!u8 {
    const out = self.getOut();
    const frame = self.current();
    // Ast.Conditional expression
    const cmp = try self.expression(target.expression, null);
    if (frame.instructions.items.len > std.math.maxInt(u16)) {
        try self.reportError("Invalid jump target");
        return Error.InvalidJmpTarget;
    }
    try out.writeAll(&.{ @intFromEnum(OpCodes.jump_neq), cmp });
    try out.writeInt(u16, 0, .big);
    // Compile bytecode to jump over the 'then' body
    const current_ip = frame.instructions.items.len - 1;
    const body = try self.statement(target.body);
    const target_ip = frame.instructions.items.len;
    // Patch the bytecode with the new target to jump to
    frame.instructions.items[current_ip - 1] = @truncate((target_ip & 0xff00) >> 8);
    frame.instructions.items[current_ip] = @truncate(target_ip);

    // TODO: Implement else for if-statements
    // if (target.otherwise) |else_blk| {
    //     if (self.instructions.items.len > std.math.maxInt(u16)) {
    //         try self.reportError("Invalid jump target");
    //         return Error.InvalidJmpTarget;
    //     }
    //     const else_ip: u16 = @truncate(self.instructions.items.len + 3);
    //     try out.writeByte(@intFromEnum(opcodes.jump));
    //     try out.writeInt(u16, else_ip);
    //     _ = try self.statement(else_blk);
    // }

    return body;
}

fn loop(self: *Compiler, target: *Ast.Loop) Errors!u8 {
    const frame = self.current();
    const out = self.getOut();
    // Compile initializer if there is one (for-loop)
    if (target.initializer) |init| {
        _ = try self.expression(init, null);
    }
    // Compile condition expression
    const start_ip = frame.instructions.items.len;
    const cmp = try self.expression(target.condition, null);
    if (frame.instructions.items.len > std.math.maxInt(u16)) {
        try self.reportError("Invalid jump target");
        return Error.InvalidJmpTarget;
    }
    try out.writeAll(&.{ @intFromEnum(OpCodes.jump_neq), cmp });
    try out.writeInt(u16, 0, .big);
    const current_ip = frame.instructions.items.len - 1;
    const body = try self.statement(target.body);
    // Compile initializer if there is one (for-loop)
    if (target.post) |post| {
        _ = try self.expression(post, null);
    }
    // Jump to the start of the loop
    try out.writeByte(@intFromEnum(OpCodes.jump));
    try out.writeInt(u16, @truncate(start_ip), .big);
    // Patch the bytecode with the new target to jump to
    const target_ip = frame.instructions.items.len;
    frame.instructions.items[current_ip - 1] = @truncate((target_ip & 0xff00) >> 8);
    frame.instructions.items[current_ip] = @truncate(target_ip);

    return body;
}

fn function(self: *Compiler, target: *Ast.Function) Errors!u8 {
    const dst = try self.allocateRegister();
    // Ast.Function always parses a body after it
    const func_body = target.body.node.block.statements;
    _ = try self.compileFrame(func_body, target);
    return dst;
}

fn @"return"(self: *Compiler, target: Ast.Return) Errors!u8 {
    const dst = if (target.value != null) try self.expression(target.value.?, null) else 0;
    try self.getOut().writeAll(&.{ @intFromEnum(OpCodes.@"return"), dst });
    return dst;
}

fn expression(self: *Compiler, target: Ast.Expression, dst_reg: ?u8) Errors!u8 {
    const node = target.node;
    return switch (target.node) {
        .infix => try self.infix(node.infix, dst_reg),
        .unary => try self.unary(node.unary, dst_reg),
        .literal => try self.literal(node.literal, dst_reg),
        .variable => try self.variable(node.variable),
        .call => try self.call(node.call),
    };
}

fn opcode(target: TokenType) !u8 {
    const op: OpCodes = switch (target) {
        .add => OpCodes.add,
        .sub => OpCodes.sub,
        .mul => OpCodes.mult,
        .div => OpCodes.divide,
        .logical_and => OpCodes.@"and",
        .logical_or => OpCodes.@"or",
        .eql => OpCodes.eql,
        .neq => OpCodes.neq,
        .less_than => OpCodes.less_than,
        .lte => OpCodes.lte,
        .greater_than => OpCodes.greater_than,
        .gte => OpCodes.gte,
        else => return Error.Unknown,
    };
    return @intFromEnum(op);
}

fn variable(self: *Compiler, target: *Ast.Variable) Errors!u8 {
    const metadata = self.ast.variables.get(target.name);
    if (metadata == null) {
        const msg = try std.fmt.allocPrint(self.allocator, "Undefined variable: '{s}'", .{target.name});
        try self.reportError(msg);
        return Error.Unknown;
    }
    // Check if variable exists in current scope
    if (self.variables.contains(target.name) and std.mem.eql(u8, metadata.?.scope, self.current().name)) {
        return self.variables.get(target.name).?;
    }
    const dst = try self.allocateRegister();
    _ = try self.variables.fetchPut(self.allocator, target.name, dst);
    if (target.initializer == null) {
        // Ast.Return destination if the variable is a function parameter
        if (metadata.?.is_param) return dst;
        const msg = try std.fmt.allocPrint(self.allocator, "Undefined variable: '{s}'", .{target.name});
        try self.reportError(msg);
        return Error.Unknown;
    }
    _ = try self.expression(target.initializer.?, dst);

    return dst;
}

fn call(self: *Compiler, target: *Ast.Call) Errors!u8 {
    const out = self.getOut();

    const node = target.*;
    const call_expr = node.callee.node;
    const func_name = call_expr.variable.*.name;
    // Compile store instructions for all parameters
    for (node.args) |arg| {
        const arg_dst = try self.expression(arg, null);
        try out.writeAll(&.{ @intFromEnum(OpCodes.store_param), arg_dst });
    }
    // Find the frame target
    var frame_idx: ?u8 = self.functions.get(func_name);
    if (frame_idx == null) {
        frame_idx = @truncate(self.functions.size);
        try self.functions.put(self.allocator, func_name, frame_idx.?);
    }

    const dst = try self.allocateRegister();
    // Finalize the call instruction
    try out.writeAll(&.{ @intFromEnum(OpCodes.call), frame_idx.?, dst });
    return dst;
}

fn infix(self: *Compiler, target: *Ast.Infix, dst_reg: ?u8) Errors!u8 {
    if (target.op == .assign) return try self.assignment(target);
    const lhs = try self.expression(target.lhs, null);
    const rhs = try self.expression(target.rhs, null);
    const dst = if (dst_reg == null) try self.allocateRegister() else dst_reg.?;
    const op = try opcode(target.op);
    try self.getOut().writeAll(&.{ op, dst, lhs, rhs });
    return dst;
}

fn assignment(self: *Compiler, target: *Ast.Infix) Errors!u8 {
    const target_var = target.lhs.node.variable;
    if (self.ast.variables.get(target_var.*.name)) |metadata| {
        if (!metadata.mutable) {
            const msg = try std.fmt.allocPrint(self.allocator, "Invalid assignment to immutable variable '{s}'", .{target_var.*.name});
            try self.reportError(msg);
            return Error.Unknown;
        }
    }
    const lhs = try self.variable(target_var);
    const rhs = try self.expression(target.rhs, lhs);
    if (target.rhs.node == .variable) {
        try self.getOut().writeAll(&.{ @intFromEnum(OpCodes.copy), lhs, rhs });
    }

    return lhs;
}

fn unary(self: *Compiler, target: *Ast.Unary, dst_reg: ?u8) Errors!u8 {
    const zero_reg = 0x00;
    const rhs = try self.expression(target.rhs, null);
    const dst = if (dst_reg == null) try self.allocateRegister() else dst_reg.?;
    const op = try opcode(target.op);
    try self.getOut().writeAll(&.{ op, dst, zero_reg, rhs });
    return dst;
}

fn literal(self: *Compiler, val: Value, dst_reg: ?u8) Errors!u8 {
    const dst = if (dst_reg == null) try self.allocateRegister() else dst_reg.?;
    const out = self.getOut();
    switch (val) {
        .boolean => try out.writeAll(&.{ @intFromEnum(OpCodes.load_bool), dst, @intFromBool(val.boolean) }),
        .float => {
            try out.writeAll(&.{ @intFromEnum(OpCodes.load_float), dst });
            try out.writeInt(u64, @bitCast(val.float), .big);
        },
        .int => {
            try out.writeAll(&.{ @intFromEnum(OpCodes.load_int), dst });
            try out.writeInt(u64, @bitCast(val.int), .big);
        },
    }
    return dst;
}

fn allocateRegister(self: *Compiler) Errors!u8 {
    var frame = self.current();
    if (frame.reg_ptr >= std.math.maxInt(u8)) {
        try self.reportError("Out of registers");
        return Error.OutOfRegisters;
    }
    frame.reg_ptr += 1;
    return frame.reg_ptr - 1;
}

fn reportError(self: *Compiler, msg: []const u8) Errors!void {
    const err_msg = try self.allocator.dupe(u8, msg);
    errdefer self.allocator.free(err_msg);
    self.err_msg = err_msg;
}
