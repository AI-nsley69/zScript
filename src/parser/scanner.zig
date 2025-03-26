const std = @import("std");

pub const TokenType = enum { number, add, eof, err };

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    line: usize,
};

fn isDigit(char: u8) bool {
    return '0' <= char and char <= '9';
}

pub const Scanner = struct {
    source: []const u8,
    start: usize = 0,
    current: usize = 0,
    line: usize = 1,
    tokens: std.ArrayListUnmanaged(Token) = std.ArrayListUnmanaged(Token){},

    const Self = @This();

    pub fn scan(self: *Self, allocator: std.mem.Allocator) !std.ArrayListUnmanaged(Token) {
        while (true) {
            const token = self.scanToken();
            try self.tokens.append(allocator, token);
            if (token.type == .eof or token.type == .err) break;
        }

        return self.tokens;
    }

    fn isAtEnd(self: *Self) bool {
        return self.current >= self.source.len;
    }

    fn advance(self: *Self) u8 {
        self.current += 1;
        return self.source[self.current - 1];
    }

    fn peek(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current + 1];
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;
        self.current += 1;
        return true;
    }

    fn scanToken(self: *Self) Token {
        self.trimWhitespace();
        self.start = self.current;

        if (self.isAtEnd()) return self.makeToken(.eof);

        const c: u8 = self.advance();

        switch (c) {
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => return self.number(),
            '+' => return self.makeToken(.add),
            else => return self.makeError("Unrecognized token: " ++ [_]u8{c}),
        }
    }

    fn trimWhitespace(self: *Self) void {
        while (!self.isAtEnd()) {
            switch (self.peek()) {
                ' ', '\r', '\t' => {
                    _ = self.advance();
                    continue;
                },
                '\n' => {
                    self.line += 1;
                    continue;
                },
                else => return,
            }
        }
    }

    fn number(self: *Self) Token {
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

    fn makeError(self: *Self, msg: []const u8) Token {
        return Token{ .type = .err, .value = msg, .line = self.line };
    }

    fn makeToken(self: *Self, tokenType: TokenType) Token {
        return Token{
            .type = tokenType,
            .value = self.source[self.start..self.current],
            .line = self.line,
        };
    }
};
