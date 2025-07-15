const std = @import("std");
const Ast = @import("ast.zig");
const Lexer = @import("lexer.zig");
const Vm = @import("vm.zig");
const Value = @import("value.zig").Value;

const Expression = Ast.Expression;
const ExpressionValue = Ast.ExpressionValue;
const Infix = Ast.Infix;
const Statement = Ast.Statement;
const Program = Ast.Program;
const Token = Lexer.Token;
const TokenType = Lexer.TokenType;

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

const dummy_Statement = Statement{ .node = .{ .expression = .{ .node = .{ .literal = .{ .boolean = false } }, .src = Token{ .tag = .err, .span = "" } } } };

pub fn parse(self: *Parser, alloc: std.mem.Allocator) Errors!Program {
    var arena = std.heap.ArenaAllocator.init(alloc);
    self.allocator = arena.allocator();
    var statements = std.ArrayListUnmanaged(Statement){};
    while (!self.isEof() and self.errors.items.len < 1) {
        const stmt = self.declaration() catch dummy_Statement;
        try statements.append(self.allocator, stmt);
    }

    return .{
        .arena = arena,
        .statements = statements,
    };
}

fn declaration(self: *Parser) Errors!Statement {
    if (self.match(.var_declaration)) return try Ast.createExpressionStatement(try self.variableDeclaration());
    return try self.statement();
}

fn statement(self: *Parser) Errors!Statement {
    if (self.match(.if_stmt)) return try self.ifStatement();
    if (self.match(.left_bracket)) return try self.block();
    const expr = try self.expression();
    _ = try self.consume(.semi_colon, "Expected semi-colon after expression.");
    return Ast.createExpressionStatement(expr);
}

fn ifStatement(self: *Parser) Errors!Statement {
    _ = try self.consume(.left_paren, "Expected left parentheses after if-statement.");
    const condition = try self.expression();
    _ = try self.consume(.right_paren, "Expected right parentheses after if-statement.");
    const body = try self.statement();

    var otherwise: ?Statement = null;
    if (self.match(.else_stmt)) {
        otherwise = try self.statement();
    }

    return try Ast.createConditional(self.allocator, condition, body, otherwise);
}

fn block(self: *Parser) Errors!Statement {
    var stmts = std.ArrayListUnmanaged(Statement){};

    while (!self.check(.right_bracket) and !self.isEof()) {
        try stmts.append(self.allocator, try self.declaration());
    }

    _ = try self.consume(.right_bracket, "Expected end of block.");

    return try Ast.createBlockStatement(try stmts.toOwnedSlice(self.allocator));
}

fn variableDeclaration(self: *Parser) Errors!Expression {
    const name = try self.consume(.identifier, "Expected variable name.");
    _ = try self.consume(.assign, "Expected assignment: '='");
    const init = try self.expression();
    _ = try self.consume(.semi_colon, "Expected semi-colon after expression.");
    return Ast.createVariable(self.allocator, init, name.span, true, self.previous());
}

fn expression(self: *Parser) Errors!Expression {
    const expr = try self.assignment();
    return expr;
}

fn assignment(self: *Parser) Errors!Expression {
    var expr = try self.logicalOr();
    if (self.match(.assign)) {
        const op = self.previous().tag;
        const rhs = try self.logicalOr();

        expr = try Ast.createInfix(self.allocator, op, expr, rhs, self.previous());
    }
    return expr;
}

fn logicalOr(self: *Parser) Errors!Expression {
    var expr = try self.logicalAnd();
    if (self.match(.logical_or)) {
        const op = self.previous().tag;
        const rhs = try self.logicalAnd();

        expr = try Ast.createInfix(self.allocator, op, expr, rhs, self.previous());
    }
    return expr;
}

fn logicalAnd(self: *Parser) Errors!Expression {
    var expr = try self.equality();
    if (self.match(.logical_and)) {
        const op = self.previous().tag;
        const rhs = try self.equality();

        expr = try Ast.createInfix(self.allocator, op, expr, rhs, self.previous());
    }
    return expr;
}

fn equality(self: *Parser) Errors!Expression {
    var expr = try self.comparison();
    // TODO: implement not assign
    while (self.match(.eql)) {
        const op = self.previous().tag;
        const rhs = try self.comparison();

        expr = try Ast.createInfix(self.allocator, op, expr, rhs, self.previous());
    }
    return expr;
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
    if (self.match(.bool)) {
        // Lexer only spits out bool token if 'true' or 'false' is found
        const val = std.mem.eql(u8, "true", self.previous().span);
        return Ast.createLiteral(.{ .boolean = val }, self.previous());
    }

    if (self.match(.number)) {
        const str_val = self.previous().span;
        if (std.mem.containsAtLeast(u8, str_val, 1, ".")) {
            const value = try std.fmt.parseFloat(f64, str_val);
            return Ast.createLiteral(.{ .float = value }, self.previous());
        }
        const value = try std.fmt.parseInt(i64, str_val, 0);
        return Ast.createLiteral(.{ .int = value }, self.previous());
    }

    if (self.match(.identifier)) {
        return Ast.createVariable(self.allocator, null, self.previous().span, false, self.previous());
    }

    if (self.match(.left_paren)) {
        const expr = try self.expression();
        _ = try self.consume(.right_paren, "Expected closing bracket");
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

fn consume(self: *Parser, token: TokenType, err_msg: []const u8) !Token {
    if (self.check(token)) {
        return self.advance();
    }

    try self.err(err_msg);
    return Error.UnexpectedToken;
}

fn err(self: *Parser, err_msg: []const u8) !void {
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
