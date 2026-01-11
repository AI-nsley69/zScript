const std = @import("std");
const Ast = @import("ast.zig");
const Lexer = @import("lexer.zig");
const Vm = @import("vm.zig");
const Gc = @import("gc.zig");
const Val = @import("value.zig");
const Native = @import("native.zig");

const tracy = @import("tracy");

const Object = Val.Object;
const Value = Val.Value;
const ValueType = Val.ValueType;

const Expression = Ast.Expression;
const ExpressionValue = Ast.ExpressionValue;
const Infix = Ast.Infix.create;
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
    params: u64,
    return_type: ?ValueType = null,
};

pub const Error = error{
    ExpressionExpected,
    UnexpectedToken,
    Undefined,
    InvalidArguments,
};

const Errors = (Error || std.mem.Allocator.Error || std.fmt.ParseIntError || std.fmt.ParseFloatError || Native.Error || Val.ConvertError);

const Parser = @This();

gpa: std.mem.Allocator = undefined,
gc: *Gc = undefined,
tokens: std.MultiArrayList(Token) = undefined,
current: u64 = 0,

variables: std.StringHashMapUnmanaged(VariableMetaData) = std.StringHashMapUnmanaged(VariableMetaData){},
functions: std.StringHashMapUnmanaged(FunctionMetadata) = std.StringHashMapUnmanaged(FunctionMetadata){},
objects: std.StringHashMapUnmanaged(*const Object.Schema) = std.StringHashMapUnmanaged(*const Object.Schema){},

errors: std.MultiArrayList(Token) = std.MultiArrayList(Token){},

current_func: []const u8 = "main",

const dummy_stmt = Statement{ .node = .{ .expression = .{ .node = .{ .literal = .{ .boolean = false } }, .src = TokenData{ .tag = .err, .span = "" } } } };

pub fn parse(self: *Parser, alloc: std.mem.Allocator, gc: *Gc, tokens: std.MultiArrayList(Token)) Errors!Program {
    const tr = tracy.trace(@src());
    defer tr.end();

    log.debug("Parsing tokens..", .{});
    var arena = std.heap.ArenaAllocator.init(alloc);
    self.gpa = arena.allocator();
    self.gc = gc;
    self.tokens = tokens;
    var statements = std.ArrayListUnmanaged(Statement){};
    while (!self.isEof() and self.errors.items(.data).len < 1) {
        // Proceeds with parsing until then, then prints the errors and goes on
        const stmt = self.declaration() catch dummy_stmt;
        try statements.append(self.gpa, stmt);
    }

    // Tear down functions, since their metadata is no longer needed after parsing
    self.functions.deinit(self.gpa);

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
    _ = try self.variables.fetchPut(self.gpa, name.span, .{ .scope = self.current_func, .mutable = std.mem.eql(u8, var_decl.span, "mut"), .type = null });
    return try Ast.Variable.create(self.gpa, init, name.span, var_decl);
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
        try self.variables.put(self.gpa, self.previous().span, metadata);
        const param = try Ast.Variable.create(self.gpa, null, self.previous().span, self.previous());

        try params.append(self.gpa, param.node.variable);
        _ = self.consume(.comma, "Expected ',' after function parameter") catch {
            // Remove last error since it can either be comma or right paren
            if (self.match(.right_paren)) {
                _ = self.errors.pop();
                break;
            }
        };
    }

    if (self.previous().tag != .right_paren) {
        _ = try self.consume(.right_paren, "Expected ')' after function parameters");
    }
    // Add function metadata
    try self.functions.put(self.gpa, name.span, .{ .params = params.items.len });
    // Parse function body
    _ = try self.consume(.left_bracket, "Expected '{'");
    const body = try self.block();

    return try Ast.Function.create(self.gpa, name.span, body, try params.toOwnedSlice(self.gpa));
}

fn objectDeclaration(self: *Parser) Errors!Statement {
    const name = try self.consume(.identifier, "Expected object name.");
    _ = try self.consume(.left_bracket, "Expected '{' after object declaration.");

    var fields = std.StringArrayHashMapUnmanaged(?Expression){};
    var methods = std.ArrayListUnmanaged(Statement){};
    while (!self.match(.right_bracket)) {
        if (self.match(.dot)) { // Check for properties
            const field_name = try self.consume(.identifier, "Expected property name");
            const expr = if (self.match(.assign)) try self.expression() else null;
            try fields.put(self.gpa, field_name.span, expr);
            _ = try self.consume(.comma, "Expected ',' after object field");
        } else if (self.match(.fn_declaration)) { // Check for functions
            try methods.append(self.gpa, try self.functionDeclaration());
        } else {
            // Break if no functions or properties are defined
            break;
        }
    }

    if (self.previous().tag != .right_bracket) {
        try self.reportError("Expected '}' after object declaration.");
    }
    // Create packed fields
    var packed_field_count: u64 = 0;
    for (fields.keys()) |key| {
        packed_field_count += key.len + 1;
    }
    var packed_fields: std.ArrayListUnmanaged(u8) = try .initCapacity(self.gpa, packed_field_count + 1);
    errdefer packed_fields.deinit(self.gpa);
    for (fields.keys()) |key| {
        packed_fields.appendSliceAssumeCapacity(key);
        packed_fields.appendAssumeCapacity(0);
    }
    // Create packed methods
    var packed_method_count: u64 = 0;
    for (methods.items) |method| {
        packed_method_count += method.node.function.name.len + 1;
    }
    var packed_methods: std.ArrayListUnmanaged(u8) = try .initCapacity(self.gpa, packed_method_count + 1);
    errdefer packed_fields.deinit(self.gpa);
    for (methods.items) |method| {
        packed_methods.appendSliceAssumeCapacity(method.node.function.name);
        packed_methods.appendAssumeCapacity(0);
    }

    const functions = try methods.toOwnedSlice(self.gpa);

    const schema = try self.gpa.create(Object.Schema);
    schema.* = .{
        .fields_count = packed_field_count,
        .fields = try packed_fields.toOwnedSliceSentinel(self.gpa, 0),
        .methods = try packed_methods.toOwnedSliceSentinel(self.gpa, 0),
        .functions = undefined,
    };
    try self.objects.put(self.gpa, name.span, schema);

    return Ast.Object.create(self.gpa, name.span, fields, functions);
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
    return try Ast.Conditional.create(self.gpa, condition, body, otherwise);
}

fn returnStatement(self: *Parser) Errors!Statement {
    const expr: ?Expression = if (self.check(.semi_colon)) null else try self.expression();
    _ = try self.consume(.semi_colon, "Expected ';' after return.");
    return try Ast.Return.create(expr);
}

fn whileStatement(self: *Parser) Errors!Statement {
    _ = try self.consume(.left_paren, "Expected '(' after while-statement.");
    const condition = try self.expression();
    _ = try self.consume(.right_paren, "Expected ')' after while-statement.");
    const body = try self.statement();

    return try Ast.Loop.create(self.gpa, null, condition, null, body);
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

    return try Ast.Loop.create(self.gpa, init, condition, post_loop, body);
}

fn block(self: *Parser) Errors!Statement {
    var stmts = std.ArrayListUnmanaged(Statement){};

    while (!self.check(.right_bracket) and !self.isEof()) {
        try stmts.append(self.gpa, try self.declaration());
    }

    _ = try self.consume(.right_bracket, "Expected '}'");

    return try Ast.Block.create(try stmts.toOwnedSlice(self.gpa));
}

fn expression(self: *Parser) Errors!Expression {
    return try self.assignment();
}

fn assignment(self: *Parser) Errors!Expression {
    var expr = try self.logicalOr();
    if (self.match(.assign)) {
        const op = self.previous().tag;
        const rhs = try self.logicalOr();

        expr = try Ast.Infix.create(self.gpa, op, expr, rhs, self.previous());
    }
    return expr;
}

fn logicalOr(self: *Parser) Errors!Expression {
    var expr = try self.logicalAnd();
    if (self.match(.logical_or)) {
        const op = self.previous().tag;
        const rhs = try self.logicalAnd();

        expr = try Ast.Infix.create(self.gpa, op, expr, rhs, self.previous());
    }
    return expr;
}

fn logicalAnd(self: *Parser) Errors!Expression {
    var expr = try self.equality();
    if (self.match(.logical_and)) {
        const op = self.previous().tag;
        const rhs = try self.equality();

        expr = try Ast.Infix.create(self.gpa, op, expr, rhs, self.previous());
    }
    return expr;
}

fn equality(self: *Parser) Errors!Expression {
    var expr = try self.comparison();
    while (self.match(.eql) or self.match(.neq)) {
        const op = self.previous().tag;
        const rhs = try self.comparison();

        expr = try Ast.Infix.create(self.gpa, op, expr, rhs, self.previous());
    }
    return expr;
}

fn comparison(self: *Parser) Errors!Expression {
    var expr = try self.term();
    while (self.match(.less_than) or self.match(.lte) or self.match(.greater_than) or self.match(.gte)) {
        const op = self.previous().tag;
        const rhs = try self.term();

        expr = try Ast.Infix.create(self.gpa, op, expr, rhs, self.previous());
    }
    return expr;
}

fn term(self: *Parser) Errors!Expression {
    var expr = try self.factor();
    while (self.match(.add) or self.match(.sub)) {
        const op = self.previous().tag;
        const rhs = try self.factor();

        expr = try Ast.Infix.create(self.gpa, op, expr, rhs, self.previous());
    }
    return expr;
}

fn factor(self: *Parser) Errors!Expression {
    var expr = try self.unary();
    while (self.match(.mul) or self.match(.div)) {
        const op = self.previous().tag;
        const rhs = try self.unary();

        expr = try Ast.Infix.create(self.gpa, op, expr, rhs, self.previous());
    }
    return expr;
}

fn unary(self: *Parser) Errors!Expression {
    // TODO: check for !
    if (self.match(.sub)) {
        const op = self.previous().tag;
        const rhs = try self.unary();

        return Ast.Unary.create(self.gpa, op, rhs, self.previous());
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
        return Ast.NewObject.create(name.span, dummy_arr, src);
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
            try args.append(self.gpa, try self.expression());
            while (self.match(.comma)) {
                try args.append(self.gpa, try self.expression());
            }
        }

        const params = (try Native.idxToFn(idx)).params;
        // Ensure call args == function params
        if (params != args.items.len) {
            const err_msg = try std.fmt.allocPrint(self.gpa, "Expected {d} arguments, found {d}", .{ params, args.items.len });
            try self.reportError(err_msg);
            return Error.InvalidArguments;
        }

        _ = try self.consume(.right_paren, "Expected ')' after native function call.");

        return try Ast.NativeCall.create(self.gpa, try args.toOwnedSlice(self.gpa), idx, src);
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
        if (self.match(.left_paren)) {
            return try self.finishObjectCall(root, field_tkn);
        }

        const field = try Ast.Literal.create(self.gc.allocString(field_tkn.span), self.peek());
        const prop_assignment: ?Expression = if (self.match(.assign)) try self.expression() else null;
        return try Ast.FieldAccess.create(self.gpa, root, field, prop_assignment, self.previous());
    }

    return root;
}

fn finishObjectCall(self: *Parser, root: Expression, name: TokenData) Errors!Expression {
    log.debug("TODO: Add check for defined methods on objects.", .{});
    const src = self.previous();

    const method = try Ast.Literal.create(self.gc.allocString(name.span), self.peek());

    var args = std.ArrayListUnmanaged(Expression){};
    if (!self.check(.right_paren)) {
        try args.append(self.gpa, try self.expression());
        while (self.match(.comma)) {
            try args.append(self.gpa, try self.expression());
        }
    }

    _ = try self.consume(.right_paren, "Expected ')' after method call.");
    log.debug("TODO: Add check for obj call args == obj fn params", .{});

    return try Ast.MethodCall.create(self.gpa, root, method, try args.toOwnedSlice(self.gpa), src);
}

fn finishCall(self: *Parser, callee: Expression) Errors!Expression {
    const src = self.previous();
    const name = callee.node.variable.name;
    const metadata = self.functions.get(name);
    if (metadata == null) {
        const err_msg = try std.fmt.allocPrint(self.gpa, "Undefined function: '{s}'", .{name});
        try self.reportError(err_msg);
        return Error.Undefined;
    }

    var args = std.ArrayListUnmanaged(Expression){};
    if (!self.check(.right_paren)) {
        try args.append(self.gpa, try self.expression());
        while (self.match(.comma)) {
            try args.append(self.gpa, try self.expression());
        }
    }

    if (args.items.len != metadata.?.params) {
        const err_msg = try std.fmt.allocPrint(self.gpa, "Expected {d} arguments, found {d}", .{ metadata.?.params, args.items.len });
        try self.reportError(err_msg);
        return Error.InvalidArguments;
    }

    _ = try self.consume(.right_paren, "Expected ')' after call arguments");

    return try Ast.Call.create(self.gpa, callee, try args.toOwnedSlice(self.gpa), src);
}

fn primary(self: *Parser) Errors!Expression {
    if (self.match(.bool)) {
        // Lexer only spits out bool token if 'true' or 'false' is found
        const bool_val = std.mem.eql(u8, "true", self.previous().span);
        return Ast.Literal.create(.{ .boolean = bool_val }, self.previous());
    }

    if (self.match(.number)) {
        const str_val = self.previous().span;
        if (std.mem.containsAtLeast(u8, str_val, 1, ".")) {
            const value = try std.fmt.parseFloat(f64, str_val);
            return Ast.Literal.create(.{ .float = value }, self.previous());
        }
        const value = try std.fmt.parseInt(i64, str_val, 0);
        return Ast.Literal.create(.{ .int = value }, self.previous());
    }

    if (self.match(.string)) {
        const value = self.previous().span;
        const str_val = self.gc.allocStringCount(@truncate(value.len - 2));
        const str = try Value.asString(str_val, self.gc);
        @memcpy(str, value[1 .. value.len - 1]);
        return Ast.Literal.create(str_val, self.previous());
    }

    if (self.match(.obj_self)) {
        const root = self.previous();
        const name = root.span;
        return Ast.Variable.create(self.gpa, null, name, self.previous());
    }

    if (self.match(.obj_self)) {
        const root = self.previous();
        var name = root.span;
        while (self.match(.dot)) {
            _ = try self.consume(.identifier, "Expected identifier");
            const nested_name = self.previous().span;
            var new_name = try self.gpa.alloc(u8, name.len + nested_name.len);
            @memcpy(new_name[0..name.len], name);
            @memcpy(new_name[name.len..], nested_name);
            self.gpa.free(name);
            name = new_name;
        }
        return Ast.Variable.create(self.gpa, null, name, self.previous());
    }

    if (self.match(.identifier)) {
        return Ast.Variable.create(self.gpa, null, self.previous().span, self.previous());
    }

    if (self.match(.left_paren)) {
        const expr = try self.expression();
        _ = try self.consume(.right_paren, "Expected ')'");
        return expr;
    }

    const token = self.peek();
    const err_msg = try std.fmt.allocPrint(self.gpa, "Expected expression, found: {s}", .{token.span});
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
    try self.errors.append(self.gpa, err_tkn);
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
