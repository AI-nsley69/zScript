const std = @import("std");
const tracy = @import("tracy");

const log = std.log.scoped(.lexer);

pub const TokenType = enum {
    number,
    bool,
    string,
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
    obj_declaration,
    obj_self,
    new_obj,
    native_fn,
    @"return",
    comma,
    dot,
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

pub const TokenData = struct {
    tag: TokenType,
    span: []const u8,
};

pub const TokenInfo = struct {
    line: u64,
    pos: u64,
};

pub const Token = struct {
    data: TokenData,
    info: TokenInfo,
};

const Lexer = @This();

gpa: std.mem.Allocator,

buf: []const u8,
current: u64 = 0,

line: u64 = 1,
line_pos: u64 = 0,

tokens: std.MultiArrayList(Token) = std.MultiArrayList(Token){},

pub fn init(buffer: []const u8, gpa: std.mem.Allocator) Lexer {
    // Skip the UTF-8 BOM if present.
    return .{
        .buf = buffer,
        .current = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0,
        .gpa = gpa,
    };
}

pub fn deinit(self: *Lexer) void {
    for (self.tokens.items(.data)) |token| {
        if (token.tag != .err) continue;
        self.gpa.free(token.span);
    }
    self.tokens.deinit(self.gpa);
}

pub fn scan(self: *Lexer) !std.MultiArrayList(Token) {
    const tr = tracy.trace(@src());
    defer tr.end();

    log.debug("Tokenizing source..", .{});

    var token = self.scanToken();
    while (token.tag != .eof and token.tag != .err) : (token = self.scanToken()) {
        try self.tokens.append(self.gpa, .{ .data = token, .info = self.makeTokenInfo() });
    }

    try self.tokens.append(self.gpa, .{ .data = token, .info = self.makeTokenInfo() });

    log.debug("Tokenized src with {d} tokens", .{self.tokens.items(.data).len});

    return self.tokens;
}

fn isAtEnd(self: *Lexer) bool {
    return self.current >= self.buf.len;
}

fn advance(self: *Lexer) u8 {
    self.current += 1;
    return self.buf[self.current - 1];
}

fn peek(self: *Lexer) u8 {
    if (self.isAtEnd()) {
        return 0;
    }
    return self.buf[self.current];
}

fn peekNext(self: *Lexer) u8 {
    if (self.isAtEnd()) {
        return 0;
    }
    return self.buf[self.current + 1];
}

fn matchFull(self: *Lexer, comptime expected: []const u8) bool {
    const start = self.current;
    if (self.buf[self.current - 1] != expected[0]) return false;

    inline for (expected[1..]) |c| {
        if (!self.match(c)) {
            // Move back current if it doesn't match the full string
            self.current = start;
            return false;
        }
    }

    return true;
}

fn match(self: *Lexer, comptime expected: u8) bool {
    const condition = !self.isAtEnd() and self.buf[self.current] == expected;
    self.current += 1 * @intFromBool(condition);
    return condition;
}

fn scanToken(self: *Lexer) TokenData {
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
        '.' => return self.makeToken(.dot, start),
        '=' => {
            const op: TokenType = if (self.match('=')) .eql else .assign;
            return self.makeToken(op, start);
        },
        '!' => {
            if (self.match('=')) {
                return self.makeToken(.neq, start);
            }

            const msg = std.fmt.allocPrint(self.gpa, "Unknown token '{s}'", .{[1]u8{c}}) catch "Unable to create msg";
            return reportError(msg);
        },
        '<' => {
            const op: TokenType = if (self.match('=')) .lte else .less_than;
            return self.makeToken(op, start);
        },
        '>' => {
            const op: TokenType = if (self.match('=')) .gte else .greater_than;
            return self.makeToken(op, start);
        },
        '|' => {
            if (!self.match('|')) {
                const msg = std.fmt.allocPrint(self.gpa, "Expected token '{s}', found: '{s}'", .{ [_]u8{c}, [_]u8{self.peek()} }) catch "Unable to create msg";
                return reportError(msg);
            }

            return self.makeToken(.logical_or, start);
        },
        '&' => {
            if (!self.match('&')) {
                const msg = std.fmt.allocPrint(self.gpa, "Expected token '{s}', found: '{s}'", .{ [_]u8{c}, [_]u8{self.peek()} }) catch "Unable to create msg";
                return reportError(msg);
            }

            return self.makeToken(.logical_and, start);
        },
        '"' => {
            _ = self.takeWhile(isNotQuote);
            // Stops at '"', jump over the trailing quote
            self.current += 1;
            return self.makeToken(.string, start);
        },
        'a'...'z', 'A'...'Z' => return self.alpha(start),
        else => {
            const msg = std.fmt.allocPrint(self.gpa, "Unknown token '{s}'", .{[_]u8{c}}) catch "Unable to create msg";
            return reportError(msg);
        },
    }
}

fn takeWhile(self: *Lexer, comptime prec: anytype) u64 {
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

fn number(self: *Lexer, start: u64) TokenData {
    _ = self.takeWhile(isDigit);

    if (self.peek() == '.' and isDigit(self.peekNext())) {
        _ = self.advance();
        _ = self.takeWhile(isDigit);
    }

    return self.makeToken(.number, start);
}

const keywords = std.StaticStringMap(TokenType).initComptime(&.{
    &.{ "true", .bool },
    &.{ "false", .bool },
    &.{ "mut", .var_declaration },
    &.{ "immut", .var_declaration },
    &.{ "fn", .fn_declaration },
    &.{ "object", .obj_declaration },
    &.{ "self", .obj_self },
    &.{ "new", .new_obj },
    &.{ "if", .if_stmt },
    &.{ "while", .while_stmt },
    &.{ "for", .for_stmt },
    &.{ "return", .@"return" },
    // Native functions
    &.{ "print", .native_fn },
});

fn alpha(self: *Lexer, start: u64) TokenData {
    const name = self.buf[self.takeWhile(isAlpha)..self.current];
    const op: TokenType = keywords.get(name) orelse .identifier;
    return self.makeToken(op, start);
}

fn isAlpha(char: u8) bool {
    return ('a' <= char and char <= 'z') or ('A' <= char and char <= 'Z');
}

fn isDigit(char: u8) bool {
    return '0' <= char and char <= '9';
}

fn isNotQuote(char: u8) bool {
    return char != '"';
}

fn reportError(msg: []const u8) TokenData {
    return .{ .tag = .err, .span = msg };
}

fn makeTokenInfo(self: *Lexer) TokenInfo {
    return .{ .line = self.line, .pos = self.current - self.line_pos };
}

fn makeToken(self: *Lexer, tokenType: TokenType, start: u64) TokenData {
    return .{ .tag = tokenType, .span = self.buf[start..self.current] };
}

pub fn getLineSource(self: *Lexer, info: TokenInfo) []const u8 {
    var current = info.line - 1;
    // If next line is just an empty line, return empty string
    if (current >= self.buf.len) return "";
    var c = self.buf[current];
    const endPos = while (true) : (c = self.buf[current]) {
        current += 1;
        if (c == '\n' or current == self.buf.len) break current;
    };

    return self.buf[info.line - 1 .. endPos];
}
