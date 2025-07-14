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
};

const Errors = (Error || std.mem.Allocator.Error);

const Compiler = @This();

allocator: std.mem.Allocator,
ast: Program,
instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
constants: std.ArrayListUnmanaged(Vm.Value) = std.ArrayListUnmanaged(Vm.Value){},
ptr: usize = 0,
reg_ptr: u8 = 1,
hadErr: bool = false,
panicMode: bool = false,

const opcodes = Vm.OpCodes;

pub fn compile(self: *Compiler) !bool {
    const statements = self.ast.stmts.items;
    var final_dst: u8 = 0;
    for (statements) |elem| {
        final_dst = try self.statement(elem);
    }

    // Emit halt instruction at the end
    try self.emitBytes(@intFromEnum(opcodes.RET), final_dst);

    return !self.hadErr;
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
    const op = switch (target.op) {
        .add => opcodes.ADD,
        .sub => opcodes.SUBTRACT,
        .mul => opcodes.MULTIPLY,
        .div => opcodes.DIVIDE,
        else => opcodes.NOP,
    };
    return @intFromEnum(op);
}

fn infix(self: *Compiler, target: *Infix) Errors!u8 {
    const lhs = try self.expression(target.lhs);
    const rhs = try self.expression(target.rhs);
    const dst = try self.allocateRegister();
    const op = self.opcode(target.op);
    try self.emitBytes(op, dst);
    try self.emitBytes(lhs, rhs);
    return dst;
}

fn unary(self: *Compiler, target: *Unary) Errors!u8 {
    const zero_reg = 0x00;
    const rhs = try self.expression(target.rhs);
    const dst = try self.allocateRegister();
    const op = self.opcode(target.op);
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
        // TODO: Report error on the compiler
        return Error.OutOfRegisters;
    }
    self.reg_ptr += 1;
    return self.reg_ptr - 1;
}

fn addConstant(self: *Compiler, value: Vm.Value) !u8 {
    try self.constants.append(self.allocator, value);
    if (self.constants.items.len >= std.math.maxInt(u8)) {
        self.hadErr = true;
        self.panicMode = true;
        return 0;
    }
    const ret: u8 = @intCast(self.constants.items.len - 1);
    return ret;
}

fn err(self: *Compiler, token: Lexer.Token, msg: []const u8) void {
    if (self.panicMode) return;
    std.log.err("[line {d}] {s}", .{ token.line, msg });
    self.hadErr = true;
    self.panicMode = true;
}

fn emitBytes(self: *Compiler, byte1: u8, byte2: u8) !void {
    try self.emitByte(byte1);
    try self.emitByte(byte2);
}

fn emitByte(self: *Compiler, byte: u8) !void {
    try self.instructions.append(self.allocator, byte);
}
