const std = @import("std");
const runtime = @import("vm.zig");
const scanner = @import("scanner.zig");

const Value = runtime.Value;
const TokenType = scanner.TokenType;

pub const ExpressionType = enum {
    expr,
    literal,
};

pub const ExpressionValue = union(ExpressionType) {
    expr: *Expression,
    literal: Value,
};

pub const Expression = struct {
    lhs: ExpressionValue,
    operand: ?TokenType = null,
    rhs: ?ExpressionValue = null,
};

pub const StmtType = enum {
    expr,
};

pub const Stmt = union(StmtType) {
    expr: Expression,
};

pub const Program = struct {
    stmts: *std.ArrayListUnmanaged(Stmt),
    arena: std.heap.ArenaAllocator,
};
