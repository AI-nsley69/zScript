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
    operand: ?TokenType,
    rhs: ?ExpressionValue,
};

pub const StmtType = enum {
    Expression,
};

pub const Stmt = union(StmtType) {
    Expression: Expression,
};
