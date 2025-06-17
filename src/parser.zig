const std = @import("std");
const ast = @import("ast.zig");
const scanner = @import("scanner.zig");
const vm = @import("vm.zig");

const Expression = ast.Expression;
const Token = scanner.Token;
const TokenType = scanner.TokenType;
const Value = vm.Value;

const Parser = @This();

tokens: std.ArrayListUnmanaged(Token),
current: usize = 0,

pub fn parse(self: *Parser, alloc: std.mem.Allocator) !Expression {
    _ = self;
    _ = alloc;

    return Expression{ .lhs = ast.ExpressionValue{ .literal = Value{ .int = 0 } } };
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
