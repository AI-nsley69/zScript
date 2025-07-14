const std = @import("std");
const Lexer = @import("lexer.zig");
const Vm = @import("vm.zig");
const Ast = @import("ast.zig");

const Program = Ast.Program;
const Stmt = Ast.Stmt;
const Expression = Ast.Expression;
const ExpressionValue = Ast.ExpressionValue;
const Infix = Ast.Infix;
const Unary = Ast.Unary;
const Value = Vm.Value;
const TokenType = Lexer.TokenType;

const Error = error{
    OutOfRegisters,
    OutOfConstants,
};

const Errors = (Error || std.mem.Allocator.Error);

pub const CompilerOutput = struct {
    const Self = @This();
    instructions: []u8,
    constants: []Value,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.instructions);
        allocator.free(self.constants);
    }
};

const Compiler = @This();

allocator: std.mem.Allocator,
ast: Program,
instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
constants: std.ArrayListUnmanaged(Vm.Value) = std.ArrayListUnmanaged(Vm.Value){},
ptr: usize = 0,
reg_ptr: u8 = 1,
err_msg: ?[]u8 = null,

const opcodes = Vm.OpCodes;

pub fn compile(self: *Compiler) !CompilerOutput {
    const statements = self.ast.stmts.items;
    var final_dst: u8 = 0;
    for (statements) |elem| {
        final_dst = try self.statement(elem);
    }

    // Emit halt instruction at the end
    try self.emitBytes(@intFromEnum(opcodes.RET), final_dst);

    return .{
        .instructions = try self.instructions.toOwnedSlice(self.allocator),
        .constants = try self.constants.toOwnedSlice(self.allocator),
    };
}

fn statement(self: *Compiler, target: Stmt) !u8 {
    return try self.expression(target.expr);
}

fn expression(self: *Compiler, target: Expression) !u8 {
    const node = target.node;
    return switch (target.node) {
        .infix => try self.infix(node.infix),
        .unary => try self.unary(node.unary),
        .literal => try self.literal(node.literal),
    };
}

fn opcode(target: TokenType) u8 {
    const op = switch (target) {
        .add => opcodes.ADD,
        .sub => opcodes.SUBTRACT,
        .mul => opcodes.MULTIPLY,
        .div => opcodes.DIVIDE,
        .logical_and => opcodes.AND,
        .logical_or => opcodes.OR,
        else => opcodes.NOP,
    };
    return @intFromEnum(op);
}

fn infix(self: *Compiler, target: *Infix) Errors!u8 {
    const lhs = try self.expression(target.lhs);
    const rhs = try self.expression(target.rhs);
    const dst = try self.allocateRegister();
    const op = opcode(target.op);
    try self.emitBytes(op, dst);
    try self.emitBytes(lhs, rhs);
    return dst;
}

fn unary(self: *Compiler, target: *Unary) Errors!u8 {
    const zero_reg = 0x00;
    const rhs = try self.expression(target.rhs);
    const dst = try self.allocateRegister();
    const op = opcode(target.op);
    try self.emitBytes(op, dst);
    try self.emitBytes(zero_reg, rhs);
    return dst;
}

fn literal(self: *Compiler, val: Value) !u8 {
    const dst = try self.allocateRegister();
    const const_idx = try self.addConstant(val);
    try self.emitBytes(@intFromEnum(opcodes.LOAD_IMMEDIATE), dst);
    try self.emitByte(const_idx);
    return dst;
}

fn allocateRegister(self: *Compiler) !u8 {
    if (self.reg_ptr >= std.math.maxInt(u8)) {
        try self.err("Out of registers");
        return Error.OutOfRegisters;
    }
    self.reg_ptr += 1;
    return self.reg_ptr - 1;
}

fn addConstant(self: *Compiler, value: Vm.Value) !u8 {
    if (self.constants.items.len >= std.math.maxInt(u8)) {
        try self.err("Out of constants");
        return Error.OutOfConstants;
    }
    try self.constants.append(self.allocator, value);
    const ret: u8 = @intCast(self.constants.items.len - 1);
    return ret;
}

fn err(self: *Compiler, msg: []const u8) !void {
    const err_msg = try self.allocator.dupe(u8, msg);
    errdefer self.allocator.free(err_msg);
    self.err_msg = err_msg;
}

fn emitBytes(self: *Compiler, byte1: u8, byte2: u8) !void {
    try self.emitByte(byte1);
    try self.emitByte(byte2);
}

fn emitByte(self: *Compiler, byte: u8) !void {
    try self.instructions.append(self.allocator, byte);
}
