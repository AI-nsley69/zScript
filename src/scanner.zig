const std = @import("std");

pub const TokenType = enum {
    number,
    add,
    sub,
    mul,
    div,
    eof,
    err,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    line: usize,
    pos: usize,
    line_source: []const u8,
};

fn isDigit(char: u8) bool {
    return '0' <= char and char <= '9';
}

const Scanner = @This();

source: []const u8,
start: usize = 0,
current: usize = 0,
line: usize = 1,
line_pos: usize = 0,
tokens: std.ArrayListUnmanaged(Token) = std.ArrayListUnmanaged(Token){},
arena: std.heap.ArenaAllocator,

pub fn scan(self: *Scanner) !std.ArrayListUnmanaged(Token) {
    while (true) {
        const token = self.scanToken();
        try self.tokens.append(self.arena.allocator(), token);
        if (token.type == .eof or token.type == .err) break;
    }

    return self.tokens;
}

pub fn deinit(self: *Scanner) void {
    self.tokens.deinit(self.arena.allocator());
    self.arena.deinit();
}

fn isAtEnd(self: *Scanner) bool {
    return self.current >= self.source.len;
}

fn advance(self: *Scanner) u8 {
    self.current += 1;
    return self.source[self.current - 1];
}

fn peek(self: *Scanner) u8 {
    if (self.isAtEnd()) return 0;
    return self.source[self.current];
}

fn peekNext(self: *Scanner) u8 {
    if (self.isAtEnd()) return 0;
    return self.source[self.current + 1];
}

fn match(self: *Scanner, expected: u8) bool {
    if (self.isAtEnd()) return false;
    if (self.source[self.current] != expected) return false;
    self.current += 1;
    return true;
}

fn scanToken(self: *Scanner) Token {
    self.trimWhitespace();
    self.start = self.current;

    if (self.isAtEnd()) return self.makeToken(.eof);

    const c: u8 = self.advance();

    switch (c) {
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => return self.number(),
        '+' => return self.makeToken(.add),
        '-' => return self.makeToken(.sub),
        '*' => return self.makeToken(.mul),
        '/' => return self.makeToken(.div),
        else => {
            const msg = std.fmt.allocPrint(self.arena.allocator(), "Unrecognized token: {s}", .{[_]u8{c}}) catch "Unable to create msg";
            return self.makeError(msg);
        },
    }
}

fn trimWhitespace(self: *Scanner) void {
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

fn number(self: *Scanner) Token {
    while (isDigit(self.peek())) {
        _ = self.advance();
    }

    if (self.peek() == '.' and isDigit(self.peekNext())) {
        _ = self.advance();
        while (isDigit(self.peek())) {
            _ = self.advance();
        }
    }

    return self.makeToken(.number);
}

fn makeError(self: *Scanner, msg: []const u8) Token {
    return Token{
        .type = .err,
        .value = msg,
        .line = self.line,
        .pos = self.current - self.line_pos,
        .line_source = self.getLineSource(),
    };
}

fn makeToken(self: *Scanner, tokenType: TokenType) Token {
    return Token{
        .type = tokenType,
        .value = self.source[self.start..self.current],
        .line = self.line,
        .pos = self.current - self.line_pos,
        .line_source = self.getLineSource(),
    };
}

fn getLineSource(self: *Scanner) []const u8 {
    var current = self.line_pos;
    var c = self.source[current];
    const endPos = while (true) {
        current += 1;
        if (c == '\n' or self.source.len == current) break current;
        c = self.source[current];
    };

    return self.source[self.line_pos..endPos];
}
