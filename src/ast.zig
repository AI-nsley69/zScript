const std = @import("std");
const Runtime = @import("vm.zig");
const Lexer = @import("lexer.zig");

const Value = Runtime.Value;
const TokenType = Lexer.TokenType;
const Token = Lexer.Token;

const ExpressionType = enum {
    variable,
    infix,
    unary,
    literal,
};

pub const ExpressionValue = union(ExpressionType) {
    variable: *Variable,
    infix: *Infix,
    unary: *Unary,
    literal: Value,
};

pub const Variable = struct {
    mutable: bool,
    name: []const u8,
    initializer: ?Expression,
};

pub const Infix = struct {
    lhs: Expression,
    op: TokenType,
    rhs: Expression,
};

pub const Unary = struct {
    op: TokenType,
    rhs: Expression,
};

pub const Expression = struct {
    node: ExpressionValue,
    src: Token,
};

const StatementType = enum {
    conditional,
    expression,
    block,
};

pub const StatementValue = union(StatementType) {
    conditional: *Conditional,
    expression: Expression,
    block: Block,
};

pub const Block = struct {
    statements: []Statement,
};

pub const Conditional = struct {
    expression: Expression,
    body: Statement,
    otherwise: ?Statement,
};

pub const Statement = struct {
    node: StatementValue,
};

pub const Program = struct {
    statements: std.ArrayListUnmanaged(Statement),
    arena: std.heap.ArenaAllocator,
};

// Expression helpers

pub fn createVariable(allocator: std.mem.Allocator, init: ?Expression, name: []const u8, mutable: bool, src: Token) !Expression {
    const variable = try allocator.create(Variable);
    errdefer allocator.destroy(variable);
    variable.* = .{ .initializer = init, .mutable = mutable, .name = name };

    return .{
        .node = .{ .variable = variable },
        .src = src,
    };
}

pub fn createInfix(allocator: std.mem.Allocator, op: TokenType, lhs: Expression, rhs: Expression, src: Token) !Expression {
    const infix = try allocator.create(Infix);
    errdefer allocator.destroy(infix);
    infix.* = .{ .op = op, .lhs = lhs, .rhs = rhs };

    return .{
        .node = .{ .infix = infix },
        .src = src,
    };
}

pub fn createUnary(allocator: std.mem.Allocator, op: TokenType, rhs: Expression, src: Token) !Expression {
    const unary = try allocator.create(Unary);
    errdefer allocator.destroy(unary);
    unary.* = .{ .op = op, .rhs = rhs };

    return .{
        .node = .{ .unary = unary },
        .src = src,
    };
}

pub fn createLiteral(value: Value, src: Token) !Expression {
    return .{
        .node = .{ .literal = value },
        .src = src,
    };
}

// Statement helpers

pub fn createConditional(allocator: std.mem.Allocator, expr: Expression, body: Statement, otherwise: ?Statement) !Statement {
    const conditional = try allocator.create(Conditional);
    conditional.* = .{
        .expression = expr,
        .body = body,
        .otherwise = otherwise,
    };

    return .{
        .node = .{ .conditional = conditional },
    };
}

pub fn createExpressionStatement(expr: Expression) !Statement {
    return .{
        .node = .{ .expression = expr },
    };
}

pub fn createBlockStatement(stmts: []Statement) !Statement {
    const block: Block = .{ .statements = stmts };
    return .{
        .node = .{ .block = block },
    };
}
