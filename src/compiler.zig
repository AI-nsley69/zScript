const std = @import("std");
const Lexer = @import("lexer.zig");
const Bytecode = @import("bytecode.zig");
const Gc = @import("gc.zig");
const Vm = @import("vm.zig");
const Ast = @import("ast.zig");
const Val = @import("value.zig");
const tracy = @import("tracy");

const log = std.log.scoped(.compiler);

const Value = Val.Value;
const Object = Val.Object;

const TokenType = Lexer.TokenType;
const OpCodes = Bytecode.OpCodes;

pub const Error = error{
    OutOfRegisters,
    OutOfConstants,
    InvalidJmpTarget,
    EvaluationFailed,
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
    objects: std.StringArrayHashMapUnmanaged(Value),

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.frames) |frame| {
            allocator.free(frame.body);
        }
        allocator.free(self.frames);
        self.objects.deinit(allocator);
    }
};

const Compiler = @This();

allocator: std.mem.Allocator,
gc: *Gc,
ast: Ast.Program,

comp_frames: std.ArrayListUnmanaged(CompilerFrame) = std.ArrayListUnmanaged(CompilerFrame){},
frame_idx: usize = 0,

variables: std.ArrayListUnmanaged(std.StringHashMapUnmanaged(u8)) = std.ArrayListUnmanaged(std.StringHashMapUnmanaged(u8)){},
functions: std.StringHashMapUnmanaged(u8) = std.StringHashMapUnmanaged(u8){},
constants: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},

objects: std.StringArrayHashMapUnmanaged(Value) = std.StringArrayHashMapUnmanaged(Value){},

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
    popped.?.deinit(self.allocator);
}

fn getVariableDst(self: *Compiler, name: []const u8) ?u8 {
    // Find the variable in the scope, starting from the back.
    for (self.variables.items) |var_scope| {
        if (!var_scope.contains(name)) continue;
        return var_scope.get(name).?;
    }

    return null;
}

inline fn getOut(self: *Compiler) std.ArrayListUnmanaged(u8).Writer {
    return self.current().instructions.writer(self.allocator);
}

pub fn compile(self: *Compiler) Errors!CompilerOutput {
    const tr = tracy.trace(@src());
    defer tr.end();
    log.debug("Compiling bytecode..", .{});
    defer {
        self.variables.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.comp_frames.deinit(self.allocator);
    }
    // Create a pseudo main function for initial frame
    const main_body: Ast.Statement = try Ast.Block.create(self.ast.statements.items);
    const main_func = try Ast.Function.create(self.allocator, "main", main_body, &.{});
    defer self.allocator.destroy(main_func.node.function);

    try self.functions.put(self.allocator, "main", 0);

    try self.variables.append(self.allocator, .{});
    defer self.destroyScope();
    // Compile the actual frame
    const final_dst = try self.compileFrame(main_func.node.function);
    // Emit return instruction at the end
    try self.getOut().writeAll(&.{ @intFromEnum(OpCodes.@"return"), final_dst });
    // Convert all comp frames to vm frames
    var frames = std.ArrayListUnmanaged(Bytecode.Function){};
    for (self.comp_frames.items) |compilerFrame| {
        var instructions = compilerFrame.instructions;
        try frames.append(self.allocator, .{ .name = compilerFrame.name, .body = try instructions.toOwnedSlice(self.allocator), .reg_size = compilerFrame.reg_idx });
    }

    log.debug("Finished compilation with {d} functions & {d} constants", .{ frames.items.len, self.constants.items.len });

    return .{
        .frames = try frames.toOwnedSlice(self.allocator),
        .constants = try self.constants.toOwnedSlice(self.allocator),
        .objects = self.objects,
    };
}

pub fn compileFrame(self: *Compiler, func: *Ast.Function) Errors!u8 {
    const previous_frame = self.frame_idx;
    defer self.frame_idx = previous_frame;
    // Setup a new frame
    try self.comp_frames.append(self.allocator, .{ .name = func.name });
    self.frame_idx = self.comp_frames.items.len - 1;
    // Compile the new frame
    const out = self.getOut();
    for (func.params) |param| {
        try out.writeAll(&.{ @intFromEnum(OpCodes.load_param), try self.variable(param) });
    }

    const stmts = func.body.node.block.statements;
    // Compile the statements
    var final_dst: u8 = 0;
    for (stmts) |elem| {
        final_dst = try self.statement(elem);
    }

    return final_dst;
}

fn compileObjectFrame(self: *Compiler, func: *Ast.Function) Errors!Bytecode.Function {
    const previous_frame = self.frame_idx;
    defer self.frame_idx = previous_frame;
    // Create new scope for the variable
    try self.variables.append(self.allocator, .{});
    defer self.destroyScope();
    // Setup a new frame
    try self.comp_frames.append(self.allocator, .{ .name = func.name });
    self.frame_idx = self.comp_frames.items.len - 1;
    // Compile new frame
    const out = self.getOut();
    // Setup self variable in scope
    const dst = try self.allocateRegister();
    try self.scope().put(self.allocator, "self", dst);
    try out.writeAll(&.{ @intFromEnum(OpCodes.load_param), dst });

    var final_dst: u8 = 0;
    for (func.body.node.block.statements) |stmt| {
        final_dst = try self.statement(stmt);
    }

    const comp_frame = self.comp_frames.pop();
    var instructions = comp_frame.?.instructions;
    return .{ .name = comp_frame.?.name, .body = try instructions.toOwnedSlice(self.allocator), .reg_size = comp_frame.?.reg_idx };
}

fn statement(self: *Compiler, target: Ast.Statement) Errors!u8 {
    const node = target.node;
    return switch (node) {
        .expression => try self.expression(node.expression, null),
        .conditional => try self.conditional(node.conditional),
        .block => {
            var dst: u8 = 0;
            try self.variables.append(self.allocator, .{});
            defer self.destroyScope();
            for (node.block.statements) |stmt| {
                dst = try self.statement(stmt);
            }
            return dst;
        },
        .loop => try self.loop(node.loop),
        .function => try self.function(node.function),
        .@"return" => try self.@"return"(node.@"return"),
        .object => try self.object(node.object),
    };
}

fn conditional(self: *Compiler, target: *Ast.Conditional) Errors!u8 {
    const out = self.getOut();
    const frame = self.current();

    try self.variables.append(self.allocator, .{});
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

    try self.variables.append(self.allocator, .{});
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
    try self.variables.append(self.allocator, .{});
    defer self.destroyScope();
    // Ast.Function always parses a body after it
    _ = try self.compileFrame(target);
    return dst;
}

fn @"return"(self: *Compiler, target: Ast.Return) Errors!u8 {
    const dst = if (target.value != null) try self.expression(target.value.?, null) else 0;
    try self.getOut().writeAll(&.{ @intFromEnum(OpCodes.@"return"), dst });
    return dst;
}

fn object(self: *Compiler, target: *Ast.Object) Errors!u8 {
    try self.variables.append(self.allocator, .{});
    defer self.destroyScope();

    var field_values = std.ArrayListUnmanaged(Value){};
    var field_it = target.properties.iterator();
    var next = field_it.next();
    while (next != null) : (next = field_it.next()) {
        // const field_name = next.?.key_ptr;
        const field_expression = next.?.value_ptr;
        log.debug("TODO: Uninitialized fields as null values.", .{});
        const value: Value = if (field_expression.* != null) try eval(field_expression.*.?) else .{ .int = 0 };
        try field_values.append(self.gc.gpa, value);
    }

    var functions = std.ArrayListUnmanaged(Bytecode.Function){};
    log.debug("TODO: Create functions for objects", .{});
    for (target.functions) |func| {
        const node = func.node.function;
        try functions.append(self.allocator, try self.compileObjectFrame(node));
    }

    const obj = try self.gc.gpa.create(Object);
    obj.* = .{
        .fields = (try field_values.toOwnedSlice(self.gc.gpa)).ptr,
        .functions = try functions.toOwnedSlice(self.gc.gpa),
        .schema = self.ast.objects.get(target.name).?,
    };

    const obj_val: Value = .{ .object = obj };
    try self.objects.put(self.gc.gpa, target.name, obj_val);
    try self.gc.allocated.append(self.gc.gpa, obj_val);
    // @panic("Not implemented");
    return 0;
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
        .new_object => try self.newObject(node.new_object, dst_reg),
        .field_access => try self.propertyAccess(node.field_access, dst_reg),
        .method_call => try self.methodCall(node.method_call, dst_reg),
    };
}

fn variable(self: *Compiler, target: *Ast.Variable) Errors!u8 {
    // Special case for handling `self` on objects.
    if (std.mem.eql(u8, target.name, "self")) {
        const initialized_dst = self.getVariableDst(target.name);
        if (initialized_dst != null) {
            return initialized_dst.?;
        }
        try self.reportError("Invalid usage of 'self'");
        return Error.Unknown;
    }

    const maybe_metadata = self.ast.variables.get(target.name);
    if (maybe_metadata == null) {
        log.debug("No available metadata", .{});
        const msg = try std.fmt.allocPrint(self.allocator, "Undefined variable: '{s}'", .{target.name});
        try self.reportError(msg);
        return Error.Unknown;
    }
    const metadata = maybe_metadata.?;
    // Find the variable in the scope
    const initialized_dst = self.getVariableDst(target.name);
    if (initialized_dst != null) {
        return initialized_dst.?;
    }
    const dst = try self.allocateRegister();

    try self.scope().put(self.allocator, target.name, dst);
    if (target.initializer == null) {
        // Ast.Return destination if the variable is a function parameter
        if (metadata.is_param) return dst;
        log.debug("Variable is not a parameter, nor does it have an initializer.", .{});
        const msg = try std.fmt.allocPrint(self.allocator, "Undefined variable: '{s}'", .{target.name});
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
        try self.functions.put(self.allocator, func_name, frame_idx.?);
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

fn newObject(self: *Compiler, target: Ast.NewObject, dst_reg: ?u8) Errors!u8 {
    const out = self.getOut();
    const obj = target.name;
    const val = self.objects.get(obj);
    if (val == null) {
        const msg = try std.fmt.allocPrint(self.allocator, "Undefined object '{s}'", .{obj});
        try self.reportError(msg);
        return Error.Unknown;
    }

    try self.constants.append(self.allocator, val.?);
    const const_idx = self.constants.items.len - 1;
    const dst = dst_reg orelse try self.allocateRegister();
    try out.writeAll(&.{ @intFromEnum(OpCodes.load_const), dst, @truncate(const_idx) });
    return dst;
}

fn propertyAccess(self: *Compiler, target: *Ast.FieldAccess, dst_reg: ?u8) Errors!u8 {
    const out = self.getOut();
    const op: OpCodes = if (target.assignment == null) .object_get else .object_set;
    log.debug("TODO: Cache field id if register still available in scope", .{});
    const root = try self.expression(target.root, null);
    // Codegen for field id
    const field = try self.expression(target.field, null);
    const field_dst = try self.allocateRegister();
    try out.writeAll(&.{ @intFromEnum(OpCodes.object_field_id), root, field, field_dst });
    // Set / get for field
    const dst = dst_reg orelse if (target.assignment != null) try self.expression(target.assignment.?, try self.allocateRegister()) else try self.allocateRegister();
    try out.writeAll(&.{ @intFromEnum(op), root, field_dst, dst });

    return dst;
}

fn methodCall(self: *Compiler, target: *Ast.MethodCall, dst_reg: ?u8) Errors!u8 {
    const out = self.getOut();

    const root = try self.expression(target.root, null);
    try out.writeAll(&.{ @intFromEnum(OpCodes.store_param), root });
    // TODO: Get method idx
    const method_idx = 0;
    const dst = dst_reg orelse try self.allocateRegister();
    try out.writeAll(&.{ @intFromEnum(OpCodes.method_call), root, method_idx, dst });

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
            try self.constants.append(self.allocator, str);
            const const_idx = self.constants.items.len - 1;
            try out.writeAll(&.{ @intFromEnum(OpCodes.load_const), dst, @truncate(const_idx) });
        },
        else => unreachable,
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
    const err_msg = try self.allocator.dupe(u8, msg);
    errdefer self.allocator.free(err_msg);
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

pub fn eval(expr: Ast.Expression) !Value {
    const node = expr.node;
    return switch (node) {
        .infix => {
            const infix_node = node.infix.*;
            const lhs = try eval(infix_node.lhs);
            const rhs = try eval(infix_node.rhs);

            return switch (infix_node.op) {
                .add => {
                    return switch (lhs) {
                        .int => .{ .int = lhs.int + rhs.int },
                        .float => .{ .float = lhs.float + rhs.float },
                        else => Error.EvaluationFailed,
                    };
                },
                .sub => {
                    return switch (lhs) {
                        .int => .{ .int = lhs.int - rhs.int },
                        .float => .{ .float = lhs.float - rhs.float },
                        else => Error.EvaluationFailed,
                    };
                },
                .mul => {
                    return switch (lhs) {
                        .int => .{ .int = lhs.int * rhs.int },
                        .float => .{ .float = lhs.float * rhs.float },
                        else => Error.EvaluationFailed,
                    };
                },
                .div => {
                    return switch (lhs) {
                        .int => .{ .int = @divFloor(lhs.int, rhs.int) },
                        .float => .{ .float = @divFloor(lhs.float, rhs.float) },
                        else => Error.EvaluationFailed,
                    };
                },
                else => Error.EvaluationFailed,
            };
        },
        .unary => {
            return try eval(expr.node.unary.*.rhs);
        },

        .literal => return expr.node.literal,
        else => Error.EvaluationFailed,
    };
}
