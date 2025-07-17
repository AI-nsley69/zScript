const std = @import("std");
const Runtime = @import("vm.zig");
const Lexer = @import("lexer.zig");
const Parser = @import("parser.zig");
const Value = @import("value.zig").Value;

const TokenType = Lexer.TokenType;
const Token = Lexer.Token;
const VariableMetaData = Parser.VariableMetaData;

const ExpressionType = enum {
    call,
    variable,
    infix,
    unary,
    literal,
};

pub const ExpressionValue = union(ExpressionType) {
    call: *Call,
    variable: *Variable,
    infix: *Infix,
    unary: *Unary,
    literal: Value,
};

pub const Call = struct {
    callee: Expression,
    args: []Expression,
};

pub const Variable = struct {
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
    loop,
    function,
    @"return",
};

pub const StatementValue = union(StatementType) {
    conditional: *Conditional,
    expression: Expression,
    block: Block,
    loop: *Loop,
    function: *Function,
    @"return": Return,
};

pub const Return = struct {
    value: ?Expression,
};

pub const Function = struct {
    name: []const u8,
    params: []*Variable,
    body: Statement,
};

pub const Loop = struct {
    initializer: ?Expression,
    condition: Expression,
    post: ?Expression,
    body: Statement,
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
    variables: std.StringHashMapUnmanaged(VariableMetaData),
    arena: std.heap.ArenaAllocator,
};

// Expression helpers

pub fn createCallExpression(allocator: std.mem.Allocator, callee: Expression, args: []Expression, src: Token) !Expression {
    const call = try allocator.create(Call);
    call.* = .{
        .callee = callee,
        .args = args,
    };

    return .{
        .node = .{ .call = call },
        .src = src,
    };
}

pub fn createVariable(allocator: std.mem.Allocator, init: ?Expression, name: []const u8, src: Token) !Expression {
    const variable = try allocator.create(Variable);
    errdefer allocator.destroy(variable);
    variable.* = .{ .initializer = init, .name = name };

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

pub fn createLoop(allocator: std.mem.Allocator, initializer: ?Expression, condition: Expression, post: ?Expression, body: Statement) !Statement {
    const loop = try allocator.create(Loop);
    loop.* = .{
        .body = body,
        .condition = condition,
        .initializer = initializer,
        .post = post,
    };

    return .{
        .node = .{ .loop = loop },
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

pub fn createFunction(allocator: std.mem.Allocator, name: []const u8, body: Statement, params: []*Variable) !Statement {
    const func = try allocator.create(Function);
    func.* = .{
        .name = name,
        .body = body,
        .params = params,
    };

    return .{
        .node = .{ .function = func },
    };
}

pub fn createReturn(expr: ?Expression) !Statement {
    const ret: Return = .{
        .value = expr,
    };

    return .{
        .node = .{ .@"return" = ret },
    };
}
