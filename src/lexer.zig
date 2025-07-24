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
    assign,
    left_paren,
    right_paren,
    left_bracket,
    right_bracket,
    semi_colon,
    var_declaration,
    fn_declaration,
    @"return",
    comma,
    identifier,
    if_stmt,
    else_stmt,
    while_stmt,
    for_stmt,
    eql,
    neq,
    less_than,
    lte,
    greater_than,
    gte,
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
    var token: Token = self.scanToken();
    while (token.tag != .eof and token.tag != .err) : (token = self.scanToken()) {
        try self.tokenInfo.append(self.arena.allocator(), self.makeTokenInfo(token));
        token.idx = self.tokenInfo.items.len - 1;
        try self.tokens.append(self.arena.allocator(), token);
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

inline fn peek(self: *Lexer) u8 {
    return self.source[self.current] * @intFromBool(!self.isAtEnd());
}

inline fn peekNext(self: *Lexer) u8 {
    return self.source[self.current + 1] * @intFromBool(!self.isAtEnd());
}

fn matchFull(self: *Lexer, comptime expected: []const u8) bool {
    const start = self.current;
    if (self.source[self.current - 1] != expected[0]) return false;

    inline for (expected[1..]) |c| {
        if (!self.match(c)) {
            // Move back current if it doesn't match the full string
            self.current = start;
            return false;
        }
    }

    return true;
}

inline fn match(self: *Lexer, expected: u8) bool {
    const condition = !self.isAtEnd() and self.source[self.current] == expected;
    self.current += 1 * @intFromBool(condition);
    return condition;
}

fn scanToken(self: *Lexer) Token {
    self.trimWhitespace();
    if (self.isAtEnd()) return self.makeToken(.eof, self.current);

    const start = self.current;
    const c: u8 = self.advance();

    switch (c) {
        '0'...'9' => return self.number(start),
        '+' => return self.makeToken(.add, start),
        '-' => return self.makeToken(.sub, start),
        '*' => return self.makeToken(.mul, start),
        '/' => return self.makeToken(.div, start),
        '(' => return self.makeToken(.left_paren, start),
        ')' => return self.makeToken(.right_paren, start),
        '{' => return self.makeToken(.left_bracket, start),
        '}' => return self.makeToken(.right_bracket, start),
        ';' => return self.makeToken(.semi_colon, start),
        ',' => return self.makeToken(.comma, start),
        '=' => {
            if (self.match('=')) {
                return self.makeToken(.eql, self.current - 2);
            }

            return self.makeToken(.assign, start);
        },
        '!' => {
            if (self.match('=')) {
                return self.makeToken(.neq, self.current - 2);
            }

            const msg = std.fmt.allocPrint(self.arena.allocator(), "Unknown token '{s}'", .{[_]u8{c}}) catch "Unable to create msg";
            return reportError(msg);
        },
        '<' => {
            if (self.match('=')) {
                return self.makeToken(.lte, start);
            }

            return self.makeToken(.less_than, start);
        },
        '>' => {
            const op: TokenType = if (self.match('=')) .gte else .greater_than;
            return self.makeToken(op, start);
        },
        '|' => {
            if (!self.match(c)) {
                const msg = std.fmt.allocPrint(self.arena.allocator(), "Expected token '{s}', found: '{s}'", .{ [_]u8{c}, [_]u8{self.peek()} }) catch "Unable to create msg";
                return reportError(msg);
            }

            return self.makeToken(.logical_or, start);
        },
        '&' => {
            if (!self.match(c)) {
                const msg = std.fmt.allocPrint(self.arena.allocator(), "Expected token '{s}', found: '{s}'", .{ [_]u8{c}, [_]u8{self.peek()} }) catch "Unable to create msg";
                return reportError(msg);
            }

            return self.makeToken(.logical_and, start);
        },
        'a'...'z', 'A'...'Z' => return self.alpha(start),
        else => {
            const msg = std.fmt.allocPrint(self.arena.allocator(), "Unknown token '{s}'", .{[_]u8{c}}) catch "Unable to create msg";
            return reportError(msg);
        },
    }
}

fn takeWhile(self: *Lexer, comptime prec: anytype) usize {
    const start = self.current - 1;
    while (prec(self.peek())) {
        _ = self.advance();
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
    _ = self.takeWhile(isDigit);

    if (self.peek() == '.' and isDigit(self.peekNext())) {
        _ = self.advance();
        _ = self.takeWhile(isDigit);
    }

    return self.makeToken(.number, start);
}

fn alpha(self: *Lexer, start: usize) Token {
    if (self.matchFull("true")) {
        return self.makeToken(.bool, start);
    }

    if (self.matchFull("false")) {
        return self.makeToken(.bool, start);
    }

    if (self.matchFull("mut")) {
        return self.makeToken(.var_declaration, start);
    }

    if (self.matchFull("immut")) {
        return self.makeToken(.var_declaration, start);
    }

    if (self.matchFull("if")) {
        return self.makeToken(.if_stmt, start);
    }

    if (self.matchFull("while")) {
        return self.makeToken(.while_stmt, start);
    }

    if (self.matchFull("for")) {
        return self.makeToken(.for_stmt, start);
    }

    if (self.matchFull("fn")) {
        return self.makeToken(.fn_declaration, start);
    }

    if (self.matchFull("return")) {
        return self.makeToken(.@"return", start);
    }

    return self.makeToken(.identifier, self.takeWhile(isAlpha));
}

fn reportError(msg: []const u8) Token {
    return .{ .tag = .err, .span = msg };
}

fn makeTokenInfo(self: *Lexer, token: Token) TokenInfo {
    return .{ .line = self.line, .pos = self.current - self.line_pos, .len = token.span.len, .line_source = self.getLineSource() };
}

fn makeToken(self: *Lexer, tokenType: TokenType, start: usize) Token {
    return .{ .tag = tokenType, .span = self.source[start..self.current] };
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
