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
    left_paren,
    right_paren,
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
        't' => {
            const curr = self.current - 1;
            const true_str = self.source[curr .. curr + 4];
            if (!std.mem.eql(u8, true_str, "true")) {
                const msg = std.fmt.allocPrint(self.arena.allocator(), "Unknown token '{s}'", .{[_]u8{c}}) catch "Unable to create msg";
                return self.makeError(msg);
            }
            self.current = curr + 4;
            return self.makeToken(.bool, curr);
        },
        'f' => {
            const curr = self.current - 1;
            const false_str = self.source[curr .. curr + 5];
            if (!std.mem.eql(u8, false_str, "false")) {
                const msg = std.fmt.allocPrint(self.arena.allocator(), "Unknown token '{s}'", .{[_]u8{c}}) catch "Unable to create msg";
                return self.makeError(msg);
            }
            self.current = curr + 5;
            return self.makeToken(.bool, curr);
        },
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
