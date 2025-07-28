const std = @import("std");
const Ast = @import("ast.zig");
const Lexer = @import("lexer.zig");
const Vm = @import("vm.zig");
const val = @import("value.zig");
const Native = @import("native.zig");

const tracy = @import("tracy");

const Object = val.Object;
const Value = val.Value;
const ValueType = val.ValueType;

const Expression = Ast.Expression;
const ExpressionValue = Ast.ExpressionValue;
const Infix = Ast.Infix;
const Statement = Ast.Statement;
const Program = Ast.Program;
const Token = Lexer.Token;
const TokenData = Lexer.TokenData;
const TokenType = Lexer.TokenType;

const log = std.log.scoped(.parser);

pub const VariableMetaData = struct {
    scope: []const u8 = "",
    mutable: bool = false,
    is_param: bool = false,
    type: ?ValueType = null,
};

pub const FunctionMetadata = struct {
    params: usize,
    return_type: ?ValueType = null,
};

pub const Error = error{
    ExpressionExpected,
    UnexpectedToken,
    Undefined,
    InvalidArguments,
};

const Errors = (Error || std.mem.Allocator.Error || std.fmt.ParseIntError || std.fmt.ParseFloatError || Native.Error);

const Parser = @This();

allocator: std.mem.Allocator = undefined,
tokens: std.MultiArrayList(Token) = undefined,
current: usize = 0,

variables: std.StringHashMapUnmanaged(VariableMetaData) = std.StringHashMapUnmanaged(VariableMetaData){},
functions: std.StringHashMapUnmanaged(FunctionMetadata) = std.StringHashMapUnmanaged(FunctionMetadata){},
objects: std.StringHashMapUnmanaged(*const Object.Schema) = std.StringHashMapUnmanaged(*const Object.Schema){},

errors: std.MultiArrayList(Token) = std.MultiArrayList(Token){},

current_func: []const u8 = "main",

const dummy_stmt = Statement{ .node = .{ .expression = .{ .node = .{ .literal = .{ .boolean = false } }, .src = TokenData{ .tag = .err, .span = "" } } } };

pub fn parse(self: *Parser, alloc: std.mem.Allocator, tokens: std.MultiArrayList(Token)) Errors!Program {
    const tr = tracy.trace(@src());
    defer tr.end();

    log.debug("Parsing tokens..", .{});
    var arena = std.heap.ArenaAllocator.init(alloc);
    self.allocator = arena.allocator();
    self.tokens = tokens;
    var statements = std.ArrayListUnmanaged(Statement){};
    while (!self.isEof() and self.errors.items(.data).len < 1) {
        // Proceeds with parsing until then, then prints the errors and goes on
        const stmt = self.declaration() catch dummy_stmt;
        try statements.append(self.allocator, stmt);
    }

    // Tear down functions, since their metadata is no longer needed after parsing
    self.functions.deinit(self.allocator);

    return .{
        .arena = arena,
        .variables = self.variables,
        .statements = statements,
        .objects = self.objects,
    };
}

fn declaration(self: *Parser) Errors!Statement {
    if (self.match(.var_declaration)) return try Ast.createExpressionStatement(try self.variableDeclaration());
    if (self.match(.fn_declaration)) return try self.functionDeclaration();
    if (self.match(.obj_declaration)) return try self.objectDeclaration();
    return try self.statement();
}

fn variableDeclaration(self: *Parser) Errors!Expression {
    const var_decl = self.previous();
    const name = try self.consume(.identifier, "Expected variable name.");
    _ = try self.consume(.assign, "Expected '=' after variable declaration.");
    const init = try self.expression();
    _ = try self.consume(.semi_colon, "Expected ';' after expression.");
    // Add metadata for variable
    _ = try self.variables.fetchPut(self.allocator, name.span, .{ .scope = self.current_func, .mutable = std.mem.eql(u8, var_decl.span, "mut"), .type = null });

    return try Ast.createVariable(self.allocator, init, name.span, var_decl);
}

fn functionDeclaration(self: *Parser) Errors!Statement {
    const name = try self.consume(.identifier, "Expected function name.");
    _ = try self.consume(.left_paren, "Expected '(' after function declaration.");

    const prev_func = self.current_func;
    defer self.current_func = prev_func;
    self.current_func = name.span;

    var params = std.ArrayListUnmanaged(*Ast.Variable){};
    while (self.match(.identifier)) {
        const metadata: VariableMetaData = .{ .scope = name.span, .mutable = false, .is_param = true, .type = null };
        try self.variables.put(self.allocator, self.previous().span, metadata);

        const param = try Ast.createVariable(self.allocator, null, self.previous().span, self.previous());

        try params.append(self.allocator, param.node.variable);
        _ = self.consume(.comma, "Expected ',' after function parameter") catch {
            // Remove last error since it can either be comma or right paren
            if (self.match(.right_paren)) {
                _ = self.errors.pop();
                break;
            }
        };
    }
    _ = try self.consume(.right_paren, "Expected ')' after function parameters");
    // Add function metadata
    try self.functions.put(self.allocator, name.span, .{ .params = params.items.len });
    // Parse function body
    _ = try self.consume(.left_bracket, "Expected '{'");
    const body = try self.block();

    return try Ast.createFunction(self.allocator, name.span, body, try params.toOwnedSlice(self.allocator));
}

fn objectDeclaration(self: *Parser) Errors!Statement {
    const name = try self.consume(.identifier, "Expected object name.");
    _ = try self.consume(.left_bracket, "Expected '{' after object declaration.");

    var fields = std.StringArrayHashMapUnmanaged(?Expression){};
    var functions = std.ArrayListUnmanaged(Statement){};
    while (!self.match(.right_bracket)) {
        if (self.match(.dot)) { // Check for properties
            const field_name = try self.consume(.identifier, "Expected property name");
            const expr = if (self.match(.assign)) try self.expression() else null;
            try fields.put(self.allocator, field_name.span, expr);
            _ = try self.consume(.comma, "Expected ',' after object field");
        } else if (self.match(.fn_declaration)) { // Check for functions
            try functions.append(self.allocator, try self.functionDeclaration());
        } else {
            // Break if no functions or properties are defined
            break;
        }
    }

    if (self.previous().tag != .right_bracket) {
        try self.reportError("Expected '}' after object declaration.");
    }

    var packed_len: usize = 0;
    for (fields.keys()) |key| {
        packed_len += key.len + 1;
    }

    var packed_fields: std.ArrayListUnmanaged(u8) = try .initCapacity(self.allocator, packed_len + 1);
    errdefer packed_fields.deinit(self.allocator);
    for (fields.keys()) |key| {
        packed_fields.appendSliceAssumeCapacity(key);
        packed_fields.appendAssumeCapacity(0);
    }

    const schema = try self.allocator.create(Object.Schema);
    schema.* = .{ .fields = try packed_fields.toOwnedSliceSentinel(self.allocator, 0) };
    try self.objects.put(self.allocator, name.span, schema);

    return Ast.createObject(self.allocator, name.span, fields, try functions.toOwnedSlice(self.allocator));
}

fn statement(self: *Parser) Errors!Statement {
    if (self.match(.for_stmt)) return try self.forStatement();
    if (self.match(.if_stmt)) return try self.ifStatement();
    if (self.match(.@"return")) return try self.returnStatement();
    if (self.match(.while_stmt)) return try self.whileStatement();
    if (self.match(.left_bracket)) return try self.block();
    const expr = try self.expression();
    _ = try self.consume(.semi_colon, "Expected ';' after expression.");
    return Ast.createExpressionStatement(expr);
}

fn ifStatement(self: *Parser) Errors!Statement {
    _ = try self.consume(.left_paren, "Expected '(' after if-statement.");
    const condition = try self.expression();
    _ = try self.consume(.right_paren, "Expected ')' after if-statement.");
    const body = try self.statement();

    var otherwise: ?Statement = null;
    if (self.match(.else_stmt)) {
        otherwise = try self.statement();
    }

    return try Ast.createConditional(self.allocator, condition, body, otherwise);
}

fn returnStatement(self: *Parser) Errors!Statement {
    const expr: ?Expression = if (self.check(.semi_colon)) null else try self.expression();
    _ = try self.consume(.semi_colon, "Expected ';' after return.");
    return try Ast.createReturn(expr);
}

fn whileStatement(self: *Parser) Errors!Statement {
    _ = try self.consume(.left_paren, "Expected '(' after while-statement.");
    const condition = try self.expression();
    _ = try self.consume(.right_paren, "Expected ')' after while-statement.");
    const body = try self.statement();

    return try Ast.createLoop(self.allocator, null, condition, null, body);
}

fn forStatement(self: *Parser) Errors!Statement {
    _ = try self.consume(.left_paren, "Expected '(' after for-statement.");
    // Try to parse a variable, else expression
    const init = if (self.match(.var_declaration)) try self.variableDeclaration() else try self.expression();
    const condition = try self.expression();
    _ = try self.consume(.semi_colon, "Expected ';' after expression.");
    const post_loop = try self.expression();
    _ = try self.consume(.right_paren, "Expected ')' after for-statement.");
    const body = try self.statement();

    return try Ast.createLoop(self.allocator, init, condition, post_loop, body);
}

fn block(self: *Parser) Errors!Statement {
    var stmts = std.ArrayListUnmanaged(Statement){};

    while (!self.check(.right_bracket) and !self.isEof()) {
        try stmts.append(self.allocator, try self.declaration());
    }

    _ = try self.consume(.right_bracket, "Expected '}'");

    return try Ast.createBlockStatement(try stmts.toOwnedSlice(self.allocator));
}

fn expression(self: *Parser) Errors!Expression {
    return try self.assignment();
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
    while (self.match(.eql) or self.match(.neq)) {
        const op = self.previous().tag;
        const rhs = try self.comparison();

        expr = try Ast.createInfix(self.allocator, op, expr, rhs, self.previous());
    }
    return expr;
}

fn comparison(self: *Parser) Errors!Expression {
    var expr = try self.term();
    while (self.match(.less_than) or self.match(.lte) or self.match(.greater_than) or self.match(.gte)) {
        const op = self.previous().tag;
        const rhs = try self.term();

        expr = try Ast.createInfix(self.allocator, op, expr, rhs, self.previous());
    }
    return expr;
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

    return self.new();
}

fn new(self: *Parser) Errors!Expression {
    if (self.match(.new_obj)) {
        const src = self.previous();
        const name = try self.consume(.identifier, "Expected object name after 'new'");
        _ = try self.consume(.left_paren, "Expected '(' after new object creation.");
        log.debug("TODO: Implement new object params.", .{});
        _ = try self.consume(.right_paren, "Expected ')§' after new object creation.");

        const dummy_arr: []Expression = &[0]Expression{};
        return Ast.createNewObject(name.span, dummy_arr, src);
    }

    return self.nativeCall();
}

fn nativeCall(self: *Parser) Errors!Expression {
    if (self.match(.native_fn)) {
        const src = self.previous();
        const idx: u8 = Native.nameToIdx(src.span);
        _ = try self.consume(.left_paren, "Expected '('after native function call.");

        var args = std.ArrayListUnmanaged(Expression){};
        if (!self.check(.right_paren)) {
            try args.append(self.allocator, try self.expression());
            while (self.match(.comma)) {
                try args.append(self.allocator, try self.expression());
            }
        }

        const params = (try Native.idxToFn(idx)).params;
        // Ensure call args == function params
        if (params != args.items.len) {
            const err_msg = try std.fmt.allocPrint(self.allocator, "Expected {d} arguments, found {d}", .{ params, args.items.len });
            try self.reportError(err_msg);
            return Error.InvalidArguments;
        }

        _ = try self.consume(.right_paren, "Expected ')' after native function call.");

        return try Ast.createNativeCallExpression(self.allocator, try args.toOwnedSlice(self.allocator), idx, src);
    }

    return self.call();
}

fn call(self: *Parser) Errors!Expression {
    var expr = try self.dot();

    while (true) {
        if (self.match(.left_paren)) {
            expr = try self.finishCall(expr);
        } else {
            break;
        }
    }

    return expr;
}

fn dot(self: *Parser) Errors!Expression {
    const root = try self.primary();

    if (self.match(.dot)) {
        const field_tkn = try self.consume(.identifier, "Expected expression after '.'");
        const field_str = try self.allocator.alloc(u8, field_tkn.span.len);
        @memcpy(field_str, field_tkn.span);
        const field = try Ast.createLiteral(.{ .string = field_str }, self.peek());
        const prop_assignment: ?Expression = if (self.match(.assign)) try self.expression() else null;
        return try Ast.createPropertyAccess(self.allocator, root, field, prop_assignment, self.previous());
    }

    return root;
}

fn finishCall(self: *Parser, callee: Expression) Errors!Expression {
    const src = self.previous();
    const name = callee.node.variable.name;
    const metadata = self.functions.get(name);
    if (metadata == null) {
        const err_msg = try std.fmt.allocPrint(self.allocator, "Undefined function: '{s}'", .{name});
        try self.reportError(err_msg);
        return Error.Undefined;
    }

    var args = std.ArrayListUnmanaged(Expression){};
    if (!self.check(.right_paren)) {
        try args.append(self.allocator, try self.expression());
        while (self.match(.comma)) {
            try args.append(self.allocator, try self.expression());
        }
    }

    if (args.items.len != metadata.?.params) {
        const err_msg = try std.fmt.allocPrint(self.allocator, "Expected {d} arguments, found {d}", .{ metadata.?.params, args.items.len });
        try self.reportError(err_msg);
        return Error.InvalidArguments;
    }

    _ = try self.consume(.right_paren, "Expected ')' after call arguments");

    return try Ast.createCallExpression(self.allocator, callee, try args.toOwnedSlice(self.allocator), src);
}

fn primary(self: *Parser) Errors!Expression {
    if (self.match(.bool)) {
        // Lexer only spits out bool token if 'true' or 'false' is found
        const bool_val = std.mem.eql(u8, "true", self.previous().span);
        return Ast.createLiteral(.{ .boolean = bool_val }, self.previous());
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

    if (self.match(.string)) {
        const value = self.previous().span;
        const str = try self.allocator.alloc(u8, value.len - 2);
        @memcpy(str, value[1 .. value.len - 1]);
        return Ast.createLiteral(.{ .string = str }, self.previous());
    }

    if (self.match(.obj_self)) {
        const root = self.previous();
        var name = root.span;
        while (self.match(.dot)) {
            _ = try self.consume(.identifier, "Expected identifier");
            const nested_name = self.previous().span;
            var new_name = try self.allocator.alloc(u8, name.len + nested_name.len);
            @memcpy(new_name[0..name.len], name);
            @memcpy(new_name[name.len..], nested_name);
            self.allocator.free(name);
            name = new_name;
        }
        return Ast.createVariable(self.allocator, null, name, self.previous());
    }

    if (self.match(.identifier)) {
        return Ast.createVariable(self.allocator, null, self.previous().span, self.previous());
    }

    if (self.match(.left_paren)) {
        const expr = try self.expression();
        _ = try self.consume(.right_paren, "Expected ')'");
        return expr;
    }

    const token = self.peek();
    const err_msg = try std.fmt.allocPrint(self.allocator, "Expected expression, found: {s}", .{token.span});
    // errdefer self.allocator.free(err_msg);
    try self.reportError(err_msg);
    return Error.ExpressionExpected;
}

fn match(self: *Parser, token: TokenType) bool {
    if (!self.check(token)) {
        return false;
    }

    _ = self.advance();
    return true;
}

fn consume(self: *Parser, token: TokenType, err_msg: []const u8) !TokenData {
    if (self.check(token)) {
        return self.advance();
    }

    try self.reportError(err_msg);
    return Error.UnexpectedToken;
}

fn reportError(self: *Parser, err_msg: []const u8) !void {
    const tkn = self.tokens.get(self.current);
    const err_tkn: Token = .{ .data = .{ .span = err_msg, .tag = tkn.data.tag }, .info = .{ .line = tkn.info.line, .pos = tkn.info.pos } };
    try self.errors.append(self.allocator, err_tkn);
}

fn check(self: *Parser, token: TokenType) bool {
    if (self.isEof()) {
        return false;
    }
    return self.peek().tag == token;
}

fn advance(self: *Parser) TokenData {
    if (!self.isEof()) {
        self.current += 1;
    }

    return self.previous();
}

fn isEof(self: *Parser) bool {
    return self.peek().tag == .eof;
}

fn peek(self: *Parser) TokenData {
    return self.tokens.items(.data)[self.current];
}

fn previous(self: *Parser) TokenData {
    return self.tokens.items(.data)[self.current - 1];
}
