const std = @import("std");
const Runtime = @import("vm.zig");
const Lexer = @import("lexer.zig");

const Value = Runtime.Value;
const TokenType = Lexer.TokenType;
const Token = Lexer.Token;

pub const ExpressionType = enum {
    infix,
    literal,
};

pub const ExpressionValue = union(ExpressionType) {
    infix: *Infix,
    literal: Value,
};

pub const Infix = struct {
    lhs: Expression,
    op: TokenType,
    rhs: Expression,
};

pub const Expression = struct {
    node: ExpressionValue,
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
