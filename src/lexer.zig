const std = @import("std");

pub const TokenType = enum {
    number,
    bool,
    add,
    sub,
    mul,
    div,
    logical_or,
    logical_and,
    eql,
    left_paren,
    right_paren,
    semi_colon,
    var_declaration,
    identifier,
    eof,
    err,
};

pub const Token = struct {
    tag: TokenType,
    span: []const u8,
    idx: usize = 0, // Consider a better way to look up token info
};

pub const TokenInfo = struct {
    line: usize,
    pos: usize,
    len: usize,
    line_source: []const u8,
};

const Tokens = std.ArrayListUnmanaged(Token);

fn isAlpha(char: u8) bool {
    return ('a' <= char and char <= 'z') or ('A' <= char and char <= 'Z');
}

fn isDigit(char: u8) bool {
    return '0' <= char and char <= '9';
}

const Lexer = @This();

source: []const u8,
current: usize = 0,
line: usize = 1,
line_pos: usize = 0,
tokens: Tokens = Tokens{},
tokenInfo: std.ArrayListUnmanaged(TokenInfo) = std.ArrayListUnmanaged(TokenInfo){},
arena: std.heap.ArenaAllocator,

pub fn scan(self: *Lexer) !Tokens {
    while (true) {
        var token = self.scanToken();
        try self.tokenInfo.append(self.arena.allocator(), self.makeTokenInfo(token));
        token.idx = self.tokenInfo.items.len - 1;
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

fn matchFull(self: *Lexer, comptime expected: []const u8) bool {
    for (expected) |c| {
        if (self.match(c)) continue;
        return false;
    }

    return true;
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
        ';' => return self.makeToken(.semi_colon, self.current - 1),
        '=' => return self.makeToken(.eql, self.current - 1),
        '|' => {
            const start = self.current - 1;
            if (!self.match(c)) {
                const msg = std.fmt.allocPrint(self.arena.allocator(), "Expected token '{s}', found: '{s}'", .{ [_]u8{c}, [_]u8{self.peek()} }) catch "Unable to create msg";
                return self.makeError(msg);
            }

            return self.makeToken(.logical_or, start);
        },
        '&' => {
            const start = self.current - 1;
            if (!self.match(c)) {
                const msg = std.fmt.allocPrint(self.arena.allocator(), "Expected token '{s}', found: '{s}'", .{ [_]u8{c}, [_]u8{self.peek()} }) catch "Unable to create msg";
                return self.makeError(msg);
            }

            return self.makeToken(.logical_and, start);
        },
        'a'...'z', 'A'...'Z' => return self.alpha(c, self.current - 1),
        else => {
            const msg = std.fmt.allocPrint(self.arena.allocator(), "Unknown token '{s}'", .{[_]u8{c}}) catch "Unable to create msg";
            return self.makeError(msg);
        },
    }
}

fn takeWhile(self: *Lexer, comptime prec: anytype) !usize {
    const start = self.current - 1;
    var next = self.advance();
    while (prec(next)) {
        next = self.advance();
    }

    return start;
}

fn trimWhitespace(self: *Lexer) void {
    while (!self.isAtEnd()) {
        switch (self.peek()) {
            ' ', '\r', '\t' => {
                _ = self.advance();
                continue;
            },
            '\n' => {
                _ = self.advance();
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

fn alpha(self: *Lexer, current: u8, start: usize) Token {
    if (current == 't') {
        if (self.matchFull("rue")) {
            return self.makeToken(.bool, start);
        }
    }

    if (current == 'f') {
        if (self.matchFull("alse")) {
            return self.makeToken(.bool, start);
        }
    }

    if (current == 'm') {
        if (self.matchFull("ut")) {
            return self.makeToken(.var_declaration, start);
        }
    }

    if (current == 'i') {
        if (self.matchFull("mmut")) {
            return self.makeToken(.var_declaration, start);
        }
    }

    return self.makeToken(.identifier, try self.takeWhile(isAlpha));
}

fn makeError(self: *Lexer, msg: []const u8) Token {
    _ = self;
    return .{
        .tag = .err,
        .span = msg,
    };
}

fn makeTokenInfo(self: *Lexer, token: Token) TokenInfo {
    return .{
        .line = self.line,
        .pos = self.current - self.line_pos,
        .len = token.span.len,
        .line_source = self.getLineSource(),
    };
}

fn makeToken(self: *Lexer, tokenType: TokenType, start: usize) Token {
    return .{
        .tag = tokenType,
        .span = self.source[start..self.current],
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
