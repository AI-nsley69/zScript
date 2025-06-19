const std = @import("std");
const ast = @import("ast.zig");
const scanner = @import("scanner.zig");
const vm = @import("vm.zig");

const Expression = ast.Expression;
const Stmt = ast.Stmt;
const Token = scanner.Token;
const TokenType = scanner.TokenType;
const Value = vm.Value;

const Parser = @This();

tokens: std.ArrayListUnmanaged(Token),
current: usize = 0,
errors: std.ArrayListUnmanaged([]const u8),
allocator: std.mem.Allocator = undefined,

pub fn parse(self: *Parser, alloc: std.mem.Allocator) !std.MultiArrayList(Stmt) {
    self.allocator = alloc;
    var statements = std.MultiArrayList(Stmt);
    while (!self.isEof()) {
        try statements.append(self.allocator, try self.declaration());
    }
}

fn declaration(self: *Parser) !Stmt {
    return try self.statement();
}

fn statement(self: *Parser) !Stmt {
    return Stmt{ .Expression = try self.expression() };
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
    const lhs = self.factor();

    // TODO: Implement for sub
    while (self.match(TokenType.add)) {
        const op = self.previous();
        const rhs = self.factor();

        return Expression{
            .lhs = lhs,
            .operand = op,
            .rhs = rhs,
        };
    }
    return lhs;
}

fn match(self: *Parser, token: TokenType) bool {
    if (self.check(token)) {
        return false;
    }

    self.advance();
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

fn isEof(self: *Parser) void {
    return self.peek().type == .EOF;
}

fn peek(self: *Parser) Token {
    return self.tokens.items[self.current];
}

fn previous(self: *Parser) Token {
    return self.tokens.items[self.current - 1];
}
