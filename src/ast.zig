const std = @import("std");
const Runtime = @import("vm.zig");
const Lexer = @import("lexer.zig");

const Value = Runtime.Value;
const TokenType = Lexer.TokenType;
const Token = Lexer.Token;

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
    src: Token,
};

pub const StmtType = enum {
    expr,
};

pub const Stmt = union(StmtType) {
    expr: Expression,
};

pub const Program = struct {
    stmts: std.ArrayListUnmanaged(Stmt),
    arena: std.heap.ArenaAllocator,
};
