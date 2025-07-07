const std = @import("std");
const ast = @import("ast.zig");
const scanner = @import("scanner.zig");
const vm = @import("vm.zig");

const Expression = ast.Expression;
const ExpressionValue = ast.ExpressionValue;
const Stmt = ast.Stmt;
const Program = ast.Program;
const Token = scanner.Token;
const TokenType = scanner.TokenType;
const Value = vm.Value;

pub const ParseError = error{
    ExpressionExpected,
};

const Parser = @This();

tokens: std.ArrayListUnmanaged(Token),
current: usize = 0,
errors: std.ArrayListUnmanaged([]const u8) = std.ArrayListUnmanaged([]const u8){},
allocator: std.mem.Allocator = undefined,

pub fn parse(self: *Parser, alloc: std.mem.Allocator) !Program {
    var arena = std.heap.ArenaAllocator.init(alloc);
    self.allocator = arena.allocator();
    var statements = std.ArrayListUnmanaged(Stmt){};
    while (!self.isEof()) {
        const stmt = try self.declaration();
        try statements.append(self.allocator, stmt);
    }

    return .{
        .arena = arena,
        .stmts = statements,
    };
}

fn declaration(self: *Parser) !Stmt {
    return try self.statement();
}

fn statement(self: *Parser) !Stmt {
    return .{ .expr = try self.expression() };
}

fn expression(self: *Parser) !Expression {
    return try self.assignment();
}

fn assignment(self: *Parser) !Expression {
    const expr = try self.logicalOr();
    // TODO, implement assignment
    return expr;
}

fn logicalOr(self: *Parser) !Expression {
    const lhs = try self.logicalAnd();
    // TODO: Implement checking for or
    return lhs;
}

fn logicalAnd(self: *Parser) !Expression {
    const lhs = try self.equality();
    // TODO: Implement checking for and
    return lhs;
}

fn equality(self: *Parser) !Expression {
    const lhs = try self.comparison();
    // TODO: Implement checking for neq and eq
    return lhs;
}

fn comparison(self: *Parser) !Expression {
    const lhs = try self.term();
    // TODO: Implement checking for comparisons
    return lhs;
}

fn term(self: *Parser) !Expression {
    var expr = try self.factor();

    // TODO: Implement for sub
    while (self.match(.add)) {
        const lhs = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(lhs);
        lhs.* = expr;

        const op = self.previous().type;

        const rhs = try self.allocator.create(Expression);
        errdefer self.allocator.destroy(rhs);
        rhs.* = try self.factor();

        expr.lhs = .{ .expr = lhs };
        expr.operand = op;
        expr.rhs = .{ .expr = rhs };
        // expr = lhs.*;
    }
    return expr;
}

fn factor(self: *Parser) !Expression {
    const lhs = try self.unary();
    // TODO: implement checking for terms
    return lhs;
}

fn unary(self: *Parser) !Expression {
    // TODO: check for ! and subtract

    return self.call();
}

fn call(self: *Parser) !Expression {
    const lhs = try self.primary();
    // TODO: implement checking for calls
    return lhs;
}

fn primary(self: *Parser) !Expression {
    if (self.match(.number)) {
        const value = try std.fmt.parseInt(i64, self.previous().value, 0);
        return .{ .lhs = .{ .literal = .{ .int = value } } };
    }

    std.log.debug("Token found at primary: {any}", .{self.peek().type});
    return ParseError.ExpressionExpected;
}

fn match(self: *Parser, token: TokenType) bool {
    if (!self.check(token)) {
        return false;
    }

    _ = self.advance();
    return true;
}

fn consume(self: *Parser, token: TokenType, err_msg: []const u8) !Token {
    if (self.check(token)) {
        return advance();
    }

    // TODO: Implement error handling
    _ = err_msg;
    return error.ParserError;
}

fn check(self: *Parser, token: TokenType) bool {
    if (self.isEof()) {
        return false;
    }
    return self.peek().type == token;
}

fn advance(self: *Parser) Token {
    if (!self.isEof()) {
        self.current += 1;
    }

    return self.previous();
}

fn isEof(self: *Parser) bool {
    return self.peek().type == .eof;
}

fn peek(self: *Parser) Token {
    return self.tokens.items[self.current];
}

fn previous(self: *Parser) Token {
    return self.tokens.items[self.current - 1];
}
