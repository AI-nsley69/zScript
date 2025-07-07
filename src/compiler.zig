const std = @import("std");
const Scanner = @import("scanner.zig");
const Vm = @import("vm.zig");
const Ast = @import("ast.zig");

const Program = Ast.Program;
const Stmt = Ast.Stmt;
const Expression = Ast.Expression;

const Compiler = @This();

allocator: std.mem.Allocator,
// tokens: std.ArrayListUnmanaged(scanner.Token),
ast: Program,
instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
constants: std.ArrayListUnmanaged(Vm.Value) = std.ArrayListUnmanaged(Vm.Value){},
ptr: usize = 0,
reg_ptr: u8 = 1,
hadErr: bool = false,
panicMode: bool = false,

const opcodes = Vm.OpCodes;

pub fn compile(self: *Compiler) !bool {
    // try self.advance();
    // _ = try self.expression();

    const statements = self.ast.stmts.*.items;
    for (statements) |elem| {
        _ = try self.statement(elem);
    }

    // Emit halt instruction at the end
    try self.emitByte(@intFromEnum(opcodes.HALT));
    // try self.consume(.eof, "Expect end of expression.");
    return !self.hadErr;
}

fn statement(self: *Compiler, target: Stmt) !u8 {
    return try self.expression(target.expr);
}

fn expression(self: *Compiler, target: Expression) !u8 {
    const lhs = target.lhs;
    const lhs_dst = try switch (lhs) {
        .expr => self.expression(lhs.expr.*),
        .literal => {
            const dst = self.allocateRegister();
            const const_idx = try self.addConstant(lhs.literal);

            try self.emitBytes(@intFromEnum(opcodes.LOAD_IMMEDIATE), dst);
            // Load the const index into the allocated register
            try self.emitByte(const_idx);
            return dst;
        },
    };
    // Early return if it cannot load the destination
    if (lhs == .literal) return lhs_dst;

    const rhs = target.rhs;
    var rhs_dst: ?u8 = null;
    if (rhs) |expr| {
        rhs_dst = try switch (expr) {
            .expr => self.expression(expr.expr.*),
            .literal => {
                const dst = self.allocateRegister();
                const const_idx = try self.addConstant(expr.literal);

                try self.emitBytes(@intFromEnum(opcodes.LOAD_IMMEDIATE), dst);
                // Load the const index into the allocated register
                try self.emitByte(const_idx);
                return dst;
            },
        };
    }

    const dst = self.allocateRegister();
    if (target.operand == null) {
        self.hadErr = true;
        self.panicMode = true;
        return dst;
    }

    const opcode = switch (target.operand.?) {
        .add => opcodes.ADD,
        else => opcodes.NOP,
    };

    try self.emitBytes(@intFromEnum(opcode), dst);
    try self.emitBytes(lhs_dst, rhs_dst.?);
    return dst;
}

fn advance(self: *Compiler) !void {
    if (self.next().type != .err) {
        std.debug.print("Advanced to: {any}\n", .{self.peek().type});
        return;
    }

    self.err(self.peek(), self.peek().value);
}

fn consume(self: *Compiler, token: Scanner.TokenType, msg: []const u8) !void {
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

fn addConstant(self: *Compiler, value: Vm.Value) !u8 {
    try self.constants.append(self.allocator, value);
    if (self.constants.items.len > std.math.maxInt(u8)) {
        // self.err(self.previous(), "Out of capacity!");
        self.hadErr = true;
        self.panicMode = true;
        return 0;
    }
    const ret: u8 = @intCast(self.constants.items.len - 1);
    return ret;
}

// fn binary(self: *Compiler) !u8 {
//     const optype = self.previous().type;

//     const rule = getRule(optype);
//     _ = try self.parsePrecedence(rule.prec);

//     return switch (optype) {
//         .add => {
//             self.deferEmit(@intFromEnum(opcodes.ADD));
//             return 0;
//         },
//         else => {
//             self.err(self.peek(), "Unknown operation type");
//             return 0;
//         },
//     };
// }

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

fn err(self: *Compiler, token: Scanner.Token, msg: []const u8) void {
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
