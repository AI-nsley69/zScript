const std = @import("std");
const scanner = @import("scanner.zig");
const runtime = @import("vm.zig");

const Compiler = @This();

allocator: std.mem.Allocator,
tokens: std.ArrayListUnmanaged(scanner.Token),
instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
constants: std.ArrayListUnmanaged(runtime.Value) = std.ArrayListUnmanaged(runtime.Value){},
ptr: usize = 0,
reg_ptr: u8 = 1,
hadErr: bool = false,
panicMode: bool = false,
deferred: u8 = 0,

const opcodes = runtime.OpCodes;

const Precedence = enum(u8) {
    NONE,
    ASSIGNMENT, // =
    OR, // or
    AND, // and
    EQUALITY, // == !=
    COMPARISON, // < > <= >=
    TERM, // + -
    FACTOR, // * /
    UNARY, // ! -
    CALL, // . ()
    PRIMARY,
};

const Rule = struct {
    prefix: ?*const fn (*Compiler) anyerror!u8,
    infix: ?*const fn (*Compiler) anyerror!u8,
    prec: Precedence,
};

pub fn compile(self: *Compiler) !bool {
    // try self.advance();
    _ = try self.expression();

    // Emit halt instruction at the end
    try self.emitByte(@intFromEnum(opcodes.HALT));
    try self.consume(.eof, "Expect end of expression.");
    return !self.hadErr;
}

fn next(self: *Compiler) scanner.Token {
    self.ptr += 1;
    return self.peek();
}

fn previous(self: *Compiler) scanner.Token {
    std.debug.assert(self.ptr > 0);
    return self.tokens.items[self.ptr - 1];
}

fn peek(self: *Compiler) scanner.Token {
    if (self.ptr >= self.tokens.items.len) return self.tokens.items[self.tokens.items.len - 1];
    return self.tokens.items[self.ptr];
}

fn advance(self: *Compiler) !void {
    if (self.next().type != .err) {
        std.debug.print("Advanced to: {any}\n", .{self.peek().type});
        return;
    }

    self.err(self.peek(), self.peek().value);
}

fn consume(self: *Compiler, token: scanner.TokenType, msg: []const u8) !void {
    if (self.peek().type == token) {
        try self.advance();
        return;
    }

    self.err(self.peek(), msg);
}

fn allocateRegister(self: *Compiler) u8 {
    self.reg_ptr += 1;
    return self.reg_ptr - 1;
}

fn addConstant(self: *Compiler, value: i64) !u8 {
    try self.constants.append(self.allocator, runtime.Value{ .int = value });
    if (self.constants.items.len > std.math.maxInt(u8)) {
        self.err(self.previous(), "Out of capacity!");
        return 0;
    }
    const ret: u8 = @intCast(self.constants.items.len - 1);
    return ret;
}

fn expression(self: *Compiler) !u8 {
    const ret = try self.parsePrecedence(.ASSIGNMENT);

    return ret;
}

fn parsePrecedence(self: *Compiler, prec: Precedence) !u8 {
    try self.advance();
    const tokenType = self.previous().type;
    std.debug.print("Prefix for: {any}\n", .{self.previous().type});
    const prefixFn = getRule(tokenType).prefix;
    if (prefixFn == null) {
        self.err(self.peek(), "Expected expression");
        return 0;
    }

    var infixSrc: u8 = 0xFF;
    while (@intFromEnum(prec) <= @intFromEnum(getRule(self.peek().type).prec)) {
        try self.advance();
        const infixFn = getRule(self.previous().type).infix;
        std.debug.print("Infix for: {any}\n", .{self.previous().type});
        if (infixFn == null) continue;
        infixSrc = try infixFn.?(self);
    }

    const prefixOut = try prefixFn.?(self);
    if (self.deferred == 0) return prefixOut;

    const op = self.deferred;
    try self.emitBytes(op, self.allocateRegister());
    try self.emitBytes(self.reg_ptr - 2, self.reg_ptr - 3);
    self.deferred = 0;

    return prefixOut;
}

fn getRule(tokenType: scanner.TokenType) Rule {
    return switch (tokenType) {
        .number => return Rule{ .prefix = &Compiler.number, .infix = null, .prec = .NONE },
        .add => Rule{ .prefix = null, .infix = &Compiler.binary, .prec = .TERM },
        else => Rule{ .prefix = null, .infix = null, .prec = .NONE },
    };
}

fn binary(self: *Compiler) !u8 {
    const optype = self.previous().type;

    const rule = getRule(optype);
    _ = try self.parsePrecedence(rule.prec);

    return switch (optype) {
        .add => {
            self.deferEmit(@intFromEnum(opcodes.ADD));
            return 0;
        },
        else => {
            self.err(self.peek(), "Unknown operation type");
            return 0;
        },
    };
}

fn number(self: *Compiler) !u8 {
    std.debug.print("str to int: {any}\n", .{self.previous().type});
    const value: i64 = try std.fmt.parseInt(i64, self.previous().value, 10);
    const dst = self.allocateRegister();
    const const_idx = try self.addConstant(value);

    try self.emitBytes(@intFromEnum(opcodes.LOAD_IMMEDIATE), dst);
    // Load the const index into the allocated register
    try self.emitByte(const_idx);

    return dst;
}

fn err(self: *Compiler, token: scanner.Token, msg: []const u8) void {
    if (self.panicMode) return;
    std.log.err("[line {d}] {s}", .{ token.line, msg });
    self.hadErr = true;
    self.panicMode = true;
}

fn deferEmit(self: *Compiler, byte: u8) void {
    self.deferred = byte;
}

fn emitBytes(self: *Compiler, byte1: u8, byte2: u8) !void {
    try self.emitByte(byte1);
    try self.emitByte(byte2);
}

fn emitByte(self: *Compiler, byte: u8) !void {
    try self.instructions.append(self.allocator, byte);
}
