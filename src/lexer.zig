const std = @import("std");

pub const TokenType = enum {
    number,
    add,
    sub,
    mul,
    div,
    left_paren,
    right_paren,
    eof,
    err,
};

pub const Token = struct {
    tag: TokenType,
    span: []const u8,
    // TODO: move these to a seperate token info list
    line: usize,
    pos: usize,
    line_source: []const u8,
};

fn isDigit(char: u8) bool {
    return '0' <= char and char <= '9';
}

const Lexer = @This();

source: []const u8,
current: usize = 0,
line: usize = 1,
line_pos: usize = 0,
tokens: std.ArrayListUnmanaged(Token) = std.ArrayListUnmanaged(Token){},
arena: std.heap.ArenaAllocator,

pub fn scan(self: *Lexer) !std.ArrayListUnmanaged(Token) {
    while (true) {
        const token = self.scanToken();
        try self.tokens.append(self.arena.allocator(), token);
        if (token.tag == .eof or token.tag == .err) break;
    }

    return self.tokens;
}

pub fn deinit(self: *Lexer) void {
    self.tokens.deinit(self.arena.allocator());
    self.arena.deinit();
}

fn isAtEnd(self: *Lexer) bool {
    return self.current >= self.source.len;
}

fn advance(self: *Lexer) u8 {
    self.current += 1;
    return self.source[self.current - 1];
}

fn peek(self: *Lexer) u8 {
    if (self.isAtEnd()) return 0;
    return self.source[self.current];
}

fn peekNext(self: *Lexer) u8 {
    if (self.isAtEnd()) return 0;
    return self.source[self.current + 1];
}

fn match(self: *Lexer, expected: u8) bool {
    if (self.isAtEnd()) return false;
    if (self.source[self.current] != expected) return false;
    self.current += 1;
    return true;
}

fn scanToken(self: *Lexer) Token {
    self.trimWhitespace();

    if (self.isAtEnd()) return self.makeToken(.eof, self.current);

    const c: u8 = self.advance();

    switch (c) {
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => return self.number(self.current - 1),
        '+' => return self.makeToken(.add, self.current - 1),
        '-' => return self.makeToken(.sub, self.current - 1),
        '*' => return self.makeToken(.mul, self.current - 1),
        '/' => return self.makeToken(.div, self.current - 1),
        '(' => return self.makeToken(.left_paren, self.current - 1),
        ')' => return self.makeToken(.right_paren, self.current - 1),
        else => {
            const msg = std.fmt.allocPrint(self.arena.allocator(), "Unknown token '{s}'", .{[_]u8{c}}) catch "Unable to create msg";
            return self.makeError(msg);
        },
    }
}

fn trimWhitespace(self: *Lexer) void {
    while (!self.isAtEnd()) {
        switch (self.peek()) {
            ' ', '\r', '\t' => {
                _ = self.advance();
                continue;
            },
            '\n' => {
                self.line += 1;
                self.line_pos = self.current;
                continue;
            },
            else => return,
        }
    }
}

fn number(self: *Lexer, start: usize) Token {
    while (isDigit(self.peek())) {
        _ = self.advance();
    }

    if (self.peek() == '.' and isDigit(self.peekNext())) {
        _ = self.advance();
        while (isDigit(self.peek())) {
            _ = self.advance();
        }
    }

    return self.makeToken(.number, start);
}

fn makeError(self: *Lexer, msg: []const u8) Token {
    return Token{
        .tag = .err,
        .span = msg,
        .line = self.line,
        .pos = self.current - self.line_pos,
        .line_source = self.getLineSource(),
    };
}

fn makeToken(self: *Lexer, tokenType: TokenType, start: usize) Token {
    return Token{
        .tag = tokenType,
        .span = self.source[start..self.current],
        .line = self.line,
        .pos = self.current - self.line_pos,
        .line_source = self.getLineSource(),
    };
}

fn getLineSource(self: *Lexer) []const u8 {
    var current = self.line_pos;
    var c = self.source[current];
    const endPos = while (true) {
        current += 1;
        if (c == '\n' or self.source.len == current) break current;
        c = self.source[current];
    };

    return self.source[self.line_pos..endPos];
}
