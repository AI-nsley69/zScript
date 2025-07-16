const std = @import("std");
const Lexer = @import("lexer.zig");
const Vm = @import("vm.zig");
const Ast = @import("ast.zig");
const Value = @import("value.zig").Value;

const Program = Ast.Program;
const Statement = Ast.Statement;
const Conditional = Ast.Conditional;
const Loop = Ast.Loop;
const Expression = Ast.Expression;
const ExpressionValue = Ast.ExpressionValue;
const Infix = Ast.Infix;
const Unary = Ast.Unary;
const Variable = Ast.Variable;
const TokenType = Lexer.TokenType;

const Error = error{
    OutOfRegisters,
    OutOfConstants,
    InvalidJmpTarget,
    Unknown,
};

const Errors = (Error || std.mem.Allocator.Error);

pub const CompilerOutput = struct {
    const Self = @This();
    instructions: []u8,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.instructions);
    }
};

const Compiler = @This();

allocator: std.mem.Allocator,
ast: Program,
instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
constants: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
variables: std.StringHashMapUnmanaged(u8) = std.StringHashMapUnmanaged(u8){},
ptr: usize = 0,
reg_ptr: u8 = 1,
err_msg: ?[]u8 = null,

const opcodes = Vm.OpCodes;

pub fn compile(self: *Compiler) Errors!CompilerOutput {
    defer self.variables.deinit(self.allocator);
    const out = try self.getOut();

    const statements = self.ast.statements.items;
    var final_dst: u8 = 0;
    for (statements) |elem| {
        final_dst = try self.statement(elem);
    }

    // Emit halt instruction at the end
    try out.writeAll(&.{ @intFromEnum(opcodes.@"return"), final_dst });

    return .{
        .instructions = try self.instructions.toOwnedSlice(self.allocator),
    };
}

fn getOut(self: *Compiler) !std.ArrayListUnmanaged(u8).Writer {
    return self.instructions.writer(self.allocator);
}

fn statement(self: *Compiler, target: Statement) Errors!u8 {
    const node = target.node;
    return switch (node) {
        .expression => try self.expression(node.expression, null),
        .conditional => try self.conditional(node.conditional),
        .block => {
            var dst: u8 = undefined;
            for (node.block.statements) |stmt| {
                dst = try self.statement(stmt);
            }

            return dst;
        },
        .loop => try self.loop(node.loop),
    };
}

fn conditional(self: *Compiler, target: *Conditional) Errors!u8 {
    const out = try self.getOut();
    const cmp = try self.expression(target.expression, null);
    if (self.instructions.items.len > std.math.maxInt(u16)) {
        try self.reportError("Invalid jump target");
        return Error.InvalidJmpTarget;
    }
    try out.writeAll(&.{ @intFromEnum(opcodes.jump_neq), cmp });
    try out.writeInt(u16, 0, .big);
    const current_ip = self.instructions.items.len - 1;
    const body = try self.statement(target.body);
    const target_ip = self.instructions.items.len;
    // Patch the bytecode with the new target to jump to
    self.instructions.items[current_ip - 1] = @truncate((target_ip & 0xff00) >> 8);
    self.instructions.items[current_ip] = @truncate(target_ip);

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

fn loop(self: *Compiler, target: *Loop) Errors!u8 {
    const out = try self.getOut();
    if (target.initializer) |init| {
        _ = try self.expression(init, null);
    }
    const start_ip = self.instructions.items.len;
    const cmp = try self.expression(target.condition, null);
    if (self.instructions.items.len > std.math.maxInt(u16)) {
        try self.reportError("Invalid jump target");
        return Error.InvalidJmpTarget;
    }
    try out.writeAll(&.{ @intFromEnum(opcodes.jump_neq), cmp });
    try out.writeInt(u16, 0, .big);
    const current_ip = self.instructions.items.len - 1;
    const body = try self.statement(target.body);
    if (target.post) |post| {
        _ = try self.expression(post, null);
    }
    // Jump to the start of the loop
    try out.writeByte(@intFromEnum(opcodes.jump));
    try out.writeInt(u16, @truncate(start_ip), .big);
    // Patch the bytecode with the new target to jump to
    const target_ip = self.instructions.items.len;
    self.instructions.items[current_ip - 1] = @truncate((target_ip & 0xff00) >> 8);
    self.instructions.items[current_ip] = @truncate(target_ip);

    return body;
}

fn expression(self: *Compiler, target: Expression, dst_reg: ?u8) Errors!u8 {
    const node = target.node;
    return switch (target.node) {
        .infix => try self.infix(node.infix, dst_reg),
        .unary => try self.unary(node.unary, dst_reg),
        .literal => try self.literal(node.literal, dst_reg),
        .variable => try self.variable(node.variable),
    };
}

fn opcode(target: TokenType) u8 {
    const op = switch (target) {
        .add => opcodes.add,
        .sub => opcodes.sub,
        .mul => opcodes.mult,
        .div => opcodes.divide,
        .logical_and => opcodes.@"and",
        .logical_or => opcodes.@"or",
        .eql => opcodes.eql,
        .neq => opcodes.neq,
        .less_than => opcodes.less_than,
        .lte => opcodes.lte,
        .greater_than => opcodes.greater_than,
        .gte => opcodes.gte,
        else => opcodes.noop,
    };
    return @intFromEnum(op);
}

fn variable(self: *Compiler, target: *Variable) Errors!u8 {
    if (self.variables.contains(target.name)) {
        return self.variables.get(target.name).?;
    }
    const dst = try self.allocateRegister();
    _ = try self.variables.fetchPut(self.allocator, target.name, dst);
    if (target.initializer == null) {
        const msg = try std.fmt.allocPrint(self.allocator, "Undefined variable: '{s}'", .{target.name});
        try self.reportError(msg);
        return Error.Unknown;
    }
    _ = try self.expression(target.initializer.?, dst);

    // try self.emitBytes(@intFromEnum(opcodes.copy), dst);
    // try self.emitByte(expr);

    return dst;
}

fn infix(self: *Compiler, target: *Infix, dst_reg: ?u8) Errors!u8 {
    if (target.op == .assign) return try self.assignment(target);

    const out = try self.getOut();

    const lhs = try self.expression(target.lhs, null);
    const rhs = try self.expression(target.rhs, null);
    const dst = if (dst_reg == null) try self.allocateRegister() else dst_reg.?;
    const op = opcode(target.op);

    try out.writeAll(&.{ op, dst, lhs, rhs });
    return dst;
}

fn assignment(self: *Compiler, target: *Infix) Errors!u8 {
    const target_var = target.lhs.node.variable;
    if (self.ast.variables.get(target_var.*.name)) |metadata| {
        if (!metadata.mutable) {
            const msg = try std.fmt.allocPrint(self.allocator, "Invalid assignment to immutable variable '{s}'", .{target_var.*.name});
            try self.reportError(msg);
            return Error.Unknown;
        }
    }
    const lhs = try self.variable(target_var);
    _ = try self.expression(target.rhs, lhs);

    return lhs;
}

fn unary(self: *Compiler, target: *Unary, dst_reg: ?u8) Errors!u8 {
    const zero_reg = 0x00;
    const out = try self.getOut();
    const rhs = try self.expression(target.rhs, null);
    const dst = if (dst_reg == null) try self.allocateRegister() else dst_reg.?;
    const op = opcode(target.op);
    try out.writeAll(&.{ op, dst, zero_reg, rhs });
    return dst;
}

fn literal(self: *Compiler, val: Value, dst_reg: ?u8) Errors!u8 {
    const dst = if (dst_reg == null) try self.allocateRegister() else dst_reg.?;
    const out = try self.getOut();
    switch (val) {
        .boolean => {
            try out.writeAll(&.{ @intFromEnum(opcodes.load_bool), dst, @intFromBool(val.boolean) });
        },
        .float => {
            try out.writeAll(&.{ @intFromEnum(opcodes.load_float), dst });
            try out.writeInt(u64, @bitCast(val.float), .big);
        },
        .int => {
            try out.writeAll(&.{ @intFromEnum(opcodes.load_int), dst });
            try out.writeInt(u64, @bitCast(val.int), .big);
        },
    }
    return dst;
}

fn allocateRegister(self: *Compiler) Errors!u8 {
    if (self.reg_ptr >= std.math.maxInt(u8)) {
        try self.reportError("Out of registers");
        return Error.OutOfRegisters;
    }
    self.reg_ptr += 1;
    return self.reg_ptr - 1;
}

fn addConstant(self: *Compiler, value: Value) Errors!u8 {
    if (self.constants.items.len >= std.math.maxInt(u8)) {
        try self.reportError("Out of constants");
        return Error.OutOfConstants;
    }
    try self.constants.append(self.allocator, value);
    const ret: u8 = @intCast(self.constants.items.len - 1);
    return ret;
}

fn reportError(self: *Compiler, msg: []const u8) Errors!void {
    const err_msg = try self.allocator.dupe(u8, msg);
    errdefer self.allocator.free(err_msg);
    self.err_msg = err_msg;
}
