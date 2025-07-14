const std = @import("std");
const Ast = @import("ast.zig");
const Lexer = @import("lexer.zig");
const Vm = @import("vm.zig");

const Expression = Ast.Expression;
const ExpressionValue = Ast.ExpressionValue;
const Infix = Ast.Infix;
const Stmt = Ast.Stmt;
const Program = Ast.Program;
const Token = Lexer.Token;
const TokenType = Lexer.TokenType;
const Value = Vm.Value;

pub const Error = error{
    ExpressionExpected,
    UnexpectedToken,
};

const Errors = (Error || std.mem.Allocator.Error || std.fmt.ParseIntError || std.fmt.ParseFloatError);

const Parser = @This();

tokens: std.ArrayListUnmanaged(Token),
current: usize = 0,
errors: std.ArrayListUnmanaged(Token) = std.ArrayListUnmanaged(Token){},
allocator: std.mem.Allocator = undefined,

const dummy_stmt = Stmt{ .expr = .{ .node = .{ .literal = .{ .boolean = false } }, .src = Token{ .tag = .err, .span = "" } } };

pub fn parse(self: *Parser, alloc: std.mem.Allocator) Errors!Program {
    var arena = std.heap.ArenaAllocator.init(alloc);
    self.allocator = arena.allocator();
    var statements = std.ArrayListUnmanaged(Stmt){};
    while (!self.isEof() and self.errors.items.len < 1) {
        const stmt = self.declaration() catch dummy_stmt;
        try statements.append(self.allocator, stmt);
    }

    return .{
        .arena = arena,
        .stmts = statements,
    };
}

fn declaration(self: *Parser) Errors!Stmt {
    return try self.statement();
}

fn statement(self: *Parser) Errors!Stmt {
    return .{ .expr = try self.expression() };
}

fn expression(self: *Parser) Errors!Expression {
    return try self.assignment();
}

fn assignment(self: *Parser) Errors!Expression {
    const expr = try self.logicalOr();
    // TODO, implement assignment
    return expr;
}

fn logicalOr(self: *Parser) Errors!Expression {
    const lhs = try self.logicalAnd();
    // TODO: Implement checking for or
    return lhs;
}

fn logicalAnd(self: *Parser) Errors!Expression {
    const lhs = try self.equality();
    // TODO: Implement checking for and
    return lhs;
}

fn equality(self: *Parser) Errors!Expression {
    const lhs = try self.comparison();
    // TODO: Implement checking for neq and eq
    return lhs;
}

fn comparison(self: *Parser) Errors!Expression {
    const lhs = try self.term();
    // TODO: Implement checking for comparisons
    return lhs;
}

fn term(self: *Parser) Errors!Expression {
    var expr = try self.factor();
    while (self.match(.add) or self.match(.sub)) {
        const op = self.previous().tag;
        const rhs = try self.factor();

        expr = try Ast.createInfix(self.allocator, op, expr, rhs, self.previous());
    }
    return expr;
}

fn factor(self: *Parser) Errors!Expression {
    var expr = try self.unary();
    while (self.match(.mul) or self.match(.div)) {
        const op = self.previous().tag;
        const rhs = try self.unary();

        expr = try Ast.createInfix(self.allocator, op, expr, rhs, self.previous());
    }
    return expr;
}

fn unary(self: *Parser) Errors!Expression {
    // TODO: check for !
    if (self.match(.sub)) {
        const op = self.previous().tag;
        const rhs = try self.unary();

        return Ast.createUnary(self.allocator, op, rhs, self.previous());
    }

    return self.call();
}

fn call(self: *Parser) Errors!Expression {
    const lhs = try self.primary();
    // TODO: implement checking for calls
    return lhs;
}

fn primary(self: *Parser) Errors!Expression {
    if (self.match(.number)) {
        const str_val = self.previous().span;
        if (std.mem.containsAtLeast(u8, str_val, 1, ".")) {
            const value = try std.fmt.parseFloat(f64, str_val);
            return Ast.createLiteral(.{ .float = value }, self.previous());
        }
        const value = try std.fmt.parseInt(i64, str_val, 0);
        return Ast.createLiteral(.{ .int = value }, self.previous());
    }

    if (self.match(.left_paren)) {
        const expr = try self.expression();
        const err_msg = try self.allocator.dupe(u8, "Expected closing bracket");
        _ = try self.consume(.right_paren, err_msg);
        return expr;
    }

    const token = self.peek();
    const err_msg = try std.fmt.allocPrint(self.allocator, "Expected expression, found: {s}", .{token.span});
    // errdefer self.allocator.free(err_msg);
    try self.err(err_msg);
    return Error.ExpressionExpected;
}

fn match(self: *Parser, token: TokenType) bool {
    if (!self.check(token)) {
        return false;
    }

    _ = self.advance();
    return true;
}

fn consume(self: *Parser, token: TokenType, err_msg: []u8) !Token {
    if (self.check(token)) {
        return self.advance();
    }

    try self.err(err_msg);
    return Error.UnexpectedToken;
}

fn err(self: *Parser, err_msg: []u8) !void {
    const tkn = self.peek();
    try self.errors.append(self.allocator, .{ .tag = .err, .span = err_msg, .idx = tkn.idx });
}

fn check(self: *Parser, token: TokenType) bool {
    if (self.isEof()) {
        return false;
    }
    return self.peek().tag == token;
}

fn advance(self: *Parser) Token {
    if (!self.isEof()) {
        self.current += 1;
    }

    return self.previous();
}

fn isEof(self: *Parser) bool {
    return self.peek().tag == .eof;
}

fn peek(self: *Parser) Token {
    return self.tokens.items[self.current];
}

fn previous(self: *Parser) Token {
    return self.tokens.items[self.current - 1];
}
