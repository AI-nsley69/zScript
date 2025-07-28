const std = @import("std");
const Lexer = @import("lexer.zig");
const Bytecode = @import("bytecode.zig");
const Gc = @import("gc.zig");
const Vm = @import("vm.zig");
const Ast = @import("ast.zig");
const Value = @import("value.zig").Value;

const tracy = @import("tracy");

const log = std.log.scoped(.compiler);

const TokenType = Lexer.TokenType;
const OpCodes = Bytecode.OpCodes;

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
    reg_idx: u8 = 1,
};

const Errors = (Error || std.mem.Allocator.Error);

pub const CompilerOutput = struct {
    const Self = @This();
    frames: []Bytecode.Function,
    constants: []Value,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.frames) |frame| {
            allocator.free(frame.body);
        }
        allocator.free(self.frames);
    }
};

const Compiler = @This();

gpa: std.mem.Allocator,
gc: *Gc,
ast: Ast.Program,

comp_frames: std.ArrayListUnmanaged(CompilerFrame) = std.ArrayListUnmanaged(CompilerFrame){},
frame_idx: usize = 0,

variables: std.ArrayListUnmanaged(std.StringHashMapUnmanaged(u8)) = std.ArrayListUnmanaged(std.StringHashMapUnmanaged(u8)){},
functions: std.StringHashMapUnmanaged(u8) = std.StringHashMapUnmanaged(u8){},
constants: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},

err_msg: ?[]u8 = null,

inline fn current(self: *Compiler) *CompilerFrame {
    return &self.comp_frames.items[self.frame_idx];
}

inline fn scope(self: *Compiler) *std.StringHashMapUnmanaged(u8) {
    return &self.variables.items[self.variables.items.len - 1];
}

inline fn destroyScope(self: *Compiler) void {
    var popped = self.variables.pop();
    if (popped == null) return;
    popped.?.deinit(self.gpa);
}

inline fn getOut(self: *Compiler) std.ArrayListUnmanaged(u8).Writer {
    return self.current().instructions.writer(self.gpa);
}

pub fn compile(self: *Compiler) Errors!CompilerOutput {
    const tr = tracy.trace(@src());
    defer tr.end();
    log.debug("Compiling bytecode..", .{});
    defer {
        self.variables.deinit(self.gpa);
        self.functions.deinit(self.gpa);
        self.comp_frames.deinit(self.gpa);
    }
    // Create a pseudo main function for initial frame
    const no_body: Ast.Statement = .{ .node = .{ .block = .{ .statements = &.{} } } };
    var main_func: Ast.Function = .{ .name = "main", .params = &.{}, .body = no_body };

    try self.functions.put(self.gpa, "main", 0);

    try self.variables.append(self.gpa, .{});
    defer self.destroyScope();
    // Compile the actual frame
    const final_dst = try self.compileFrame(self.ast.statements.items, &main_func);
    // Emit return instruction at the end
    try self.getOut().writeAll(&.{ @intFromEnum(OpCodes.@"return"), final_dst });
    // Convert all comp frames to vm frames
    var frames = std.ArrayListUnmanaged(Bytecode.Function){};
    for (self.comp_frames.items) |compilerFrame| {
        var instructions = compilerFrame.instructions;
        try frames.append(self.gpa, .{ .name = compilerFrame.name, .body = try instructions.toOwnedSlice(self.gpa), .reg_size = compilerFrame.reg_idx });
    }

    log.debug("Finished compilation with {d} functions & {d} constants", .{ frames.items.len, self.constants.items.len });

    return .{
        .frames = try frames.toOwnedSlice(self.gpa),
        .constants = try self.constants.toOwnedSlice(self.gpa),
    };
}

pub fn compileFrame(self: *Compiler, target: []Ast.Statement, func: *Ast.Function) Errors!u8 {
    const previous_frame = self.frame_idx;
    defer self.frame_idx = previous_frame;
    // Setup a new frame
    try self.comp_frames.append(self.gpa, .{ .name = func.name });
    self.frame_idx = self.comp_frames.items.len - 1;
    // Compile the new frame
    const out = self.getOut();
    // Load the parameters for the function (if exists)
    const reversed = try self.gpa.dupe(*Ast.Variable, func.params);
    defer self.gpa.free(reversed);
    std.mem.reverse(*Ast.Variable, reversed);
    for (reversed) |param| {
        try out.writeAll(&.{ @intFromEnum(OpCodes.load_param), try self.variable(param) });
    }
    // Compile the statements
    var final_dst: u8 = 0;
    for (target) |elem| {
        final_dst = try self.statement(elem);
    }

    return final_dst;
}

fn statement(self: *Compiler, target: Ast.Statement) Errors!u8 {
    const node = target.node;
    return switch (node) {
        .expression => try self.expression(node.expression, null),
        .conditional => try self.conditional(node.conditional),
        .block => {
            var dst: u8 = 0;
            try self.variables.append(self.gpa, .{});
            defer self.destroyScope();
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

    try self.variables.append(self.gpa, .{});
    defer self.destroyScope();
    // Ast.Conditional expression
    const cmp = try self.expression(target.expression, null);
    if (frame.instructions.items.len > std.math.maxInt(u16)) {
        log.debug("conditional -> out of instructions", .{});
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

    try self.variables.append(self.gpa, .{});
    defer self.destroyScope();
    // Compile initializer if there is one (for-loop)
    if (target.initializer) |init| {
        _ = try self.expression(init, null);
    }
    // Compile condition expression
    const start_ip = frame.instructions.items.len;
    const cmp = try self.expression(target.condition, null);
    if (frame.instructions.items.len > std.math.maxInt(u16)) {
        log.debug("loop -> out of instructions", .{});
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
    try self.variables.append(self.gpa, .{});
    defer self.destroyScope();
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
        .call => try self.call(node.call, dst_reg),
        .native_call => try self.nativeCall(node.native_call, dst_reg),
    };
}

fn variable(self: *Compiler, target: *Ast.Variable) Errors!u8 {
    const maybe_metadata = self.ast.variables.get(target.name);
    if (maybe_metadata == null) {
        log.debug("No available metadata", .{});
        const msg = try std.fmt.allocPrint(self.gpa, "Undefined variable: '{s}'", .{target.name});
        try self.reportError(msg);
        return Error.Unknown;
    }
    const metadata = maybe_metadata.?;
    // Find the variable in the scope
    for (self.variables.items) |var_scope| {
        if (!var_scope.contains(target.name)) continue;
        return var_scope.get(target.name).?;
    }
    const dst = try self.allocateRegister();

    try self.scope().put(self.gpa, target.name, dst);
    if (target.initializer == null) {
        // Ast.Return destination if the variable is a function parameter
        if (metadata.is_param) return dst;
        log.debug("Variable is not a parameter, nor does it have an initializer.", .{});
        const msg = try std.fmt.allocPrint(self.gpa, "Undefined variable: '{s}'", .{target.name});
        try self.reportError(msg);
        return Error.Unknown;
    }
    _ = try self.expression(target.initializer.?, dst);

    return dst;
}

fn call(self: *Compiler, target: *Ast.Call, dst_reg: ?u8) Errors!u8 {
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
        try self.functions.put(self.gpa, func_name, frame_idx.?);
    }

    const dst = dst_reg orelse try self.allocateRegister();
    // Finalize the call instruction
    try out.writeAll(&.{ @intFromEnum(OpCodes.call), frame_idx.? });
    try out.writeAll(&.{ @intFromEnum(OpCodes.copy), dst, 0x00 });
    return dst;
}

fn nativeCall(self: *Compiler, target: *Ast.NativeCall, dst_reg: ?u8) Errors!u8 {
    const out = self.getOut();
    const node = target.*;
    // Compile store instructions for all parameters
    for (node.args) |arg| {
        const arg_dst = try self.expression(arg, null);
        try out.writeAll(&.{ @intFromEnum(OpCodes.store_param), arg_dst });
    }

    const dst = dst_reg orelse try self.allocateRegister();
    // Finalize the call instruction
    try out.writeAll(&.{ @intFromEnum(OpCodes.native_call), @truncate(target.idx) });
    try out.writeAll(&.{ @intFromEnum(OpCodes.copy), dst, 0x00 });
    return dst;
}

fn infix(self: *Compiler, target: *Ast.Infix, dst_reg: ?u8) Errors!u8 {
    if (target.op == .assign) return try self.assignment(target);

    const lhs = try self.expression(target.lhs, null);
    const rhs = try self.expression(target.rhs, null);
    const dst = dst_reg orelse try self.allocateRegister();
    const op = try opcode(target.op);
    try self.getOut().writeAll(&.{ op, dst, lhs, rhs });
    return dst;
}

fn assignment(self: *Compiler, target: *Ast.Infix) Errors!u8 {
    const target_var = target.lhs.node.variable;
    if (self.ast.variables.get(target_var.*.name)) |metadata| {
        if (!metadata.mutable) {
            const msg = try std.fmt.allocPrint(self.gpa, "Invalid assignment to immutable variable '{s}'", .{target_var.*.name});
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
    const dst = dst_reg orelse try self.allocateRegister();
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
        .string => {
            const str = try self.gc.alloc(.string, val.string.len);
            @memcpy(str.string, val.string);
            try self.constants.append(self.gpa, str);
            const const_idx = self.constants.items.len - 1;
            try out.writeAll(&.{ @intFromEnum(OpCodes.load_const), dst, @truncate(const_idx) });
        },
    }
    return dst;
}

fn allocateRegister(self: *Compiler) Errors!u8 {
    var frame = self.current();
    if (frame.reg_idx >= std.math.maxInt(u8)) {
        @branchHint(.cold);
        try self.reportError("Out of registers");
        return Error.OutOfRegisters;
    }
    frame.reg_idx += 1;
    return frame.reg_idx - 1;
}

fn reportError(self: *Compiler, msg: []const u8) Errors!void {
    const err_msg = try self.gpa.dupe(u8, msg);
    errdefer self.gpa.free(err_msg);
    self.err_msg = err_msg;
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
