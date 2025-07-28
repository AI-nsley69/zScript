const std = @import("std");
const Runtime = @import("vm.zig");
const Lexer = @import("lexer.zig");
const Parser = @import("parser.zig");
const val = @import("value.zig");

const Value = val.Value;
const ObjectValue = val.Object;

const TokenType = Lexer.TokenType;
const TokenData = Lexer.TokenData;
const VariableMetaData = Parser.VariableMetaData;

// Expressions

const ExpressionType = enum {
    call,
    variable,
    infix,
    unary,
    literal,
    native_call,
    new_object,
    property_access,
};

pub const ExpressionValue = union(ExpressionType) {
    call: *Call,
    variable: *Variable,
    infix: *Infix,
    unary: *Unary,
    literal: Value,
    native_call: *NativeCall,
    new_object: NewObject,
    property_access: *PropertyAccess,
};

pub const PropertyAccess = struct {
    root: Expression,
    field: Expression,
    assignment: ?Expression,
};

pub const NewObject = struct {
    name: []const u8,
    params: []Expression,
};

pub const Call = struct {
    callee: Expression,
    args: []Expression,
};

pub const NativeCall = struct {
    args: []Expression,
    idx: usize,
};

pub const Variable = struct {
    name: []const u8,
    initializer: ?Expression,
};

pub const Infix = struct {
    lhs: Expression,
    op: TokenType,
    rhs: Expression,
};

pub const Unary = struct {
    op: TokenType,
    rhs: Expression,
};

pub const Expression = struct {
    node: ExpressionValue,
    src: TokenData,
};

// Statements

const StatementType = enum {
    conditional,
    expression,
    block,
    loop,
    function,
    @"return",
    object,
};

pub const StatementValue = union(StatementType) {
    conditional: *Conditional,
    expression: Expression,
    block: Block,
    loop: *Loop,
    function: *Function,
    @"return": Return,
    object: *Object,
};

pub const Object = struct {
    name: []const u8,
    properties: std.StringArrayHashMapUnmanaged(?Expression),
    functions: []Statement,
};

pub const Return = struct {
    value: ?Expression,
};

pub const Function = struct {
    name: []const u8,
    params: []*Variable,
    body: Statement,
};

pub const Loop = struct {
    initializer: ?Expression,
    condition: Expression,
    post: ?Expression,
    body: Statement,
};

pub const Block = struct {
    statements: []Statement,
};

pub const Conditional = struct {
    expression: Expression,
    body: Statement,
    otherwise: ?Statement,
};

pub const Statement = struct {
    node: StatementValue,
};

pub const Program = struct {
    statements: std.ArrayListUnmanaged(Statement),
    variables: std.StringHashMapUnmanaged(VariableMetaData),
    objects: std.StringHashMapUnmanaged(ObjectValue.Schema),
    arena: std.heap.ArenaAllocator,
};

// Expression helpers

pub fn createPropertyAccess(gpa: std.mem.Allocator, root: Expression, field: Expression, assignment: ?Expression, src: TokenData) !Expression {
    const prop_access = try gpa.create(PropertyAccess);
    prop_access.* = .{ .root = root, .field = field, .assignment = assignment };

    return .{
        .node = .{ .property_access = prop_access },
        .src = src,
    };
}

pub fn createNewObject(name: []const u8, params: []Expression, src: TokenData) !Expression {
    const obj: NewObject = .{
        .name = name,
        .params = params,
    };

    return .{
        .node = .{ .new_object = obj },
        .src = src,
    };
}

pub fn createCallExpression(allocator: std.mem.Allocator, callee: Expression, args: []Expression, src: TokenData) !Expression {
    const call = try allocator.create(Call);
    call.* = .{
        .callee = callee,
        .args = args,
    };

    return .{
        .node = .{ .call = call },
        .src = src,
    };
}

pub fn createNativeCallExpression(allocator: std.mem.Allocator, args: []Expression, idx: usize, src: TokenData) !Expression {
    const call = try allocator.create(NativeCall);
    call.* = .{
        .args = args,
        .idx = idx,
    };

    return .{
        .node = .{ .native_call = call },
        .src = src,
    };
}

pub fn createVariable(allocator: std.mem.Allocator, init: ?Expression, name: []const u8, src: TokenData) !Expression {
    const variable = try allocator.create(Variable);
    errdefer allocator.destroy(variable);
    variable.* = .{ .initializer = init, .name = name };

    return .{
        .node = .{ .variable = variable },
        .src = src,
    };
}

pub fn createInfix(allocator: std.mem.Allocator, op: TokenType, lhs: Expression, rhs: Expression, src: TokenData) !Expression {
    const infix = try allocator.create(Infix);
    errdefer allocator.destroy(infix);
    infix.* = .{ .op = op, .lhs = lhs, .rhs = rhs };

    return .{
        .node = .{ .infix = infix },
        .src = src,
    };
}

pub fn createUnary(allocator: std.mem.Allocator, op: TokenType, rhs: Expression, src: TokenData) !Expression {
    const unary = try allocator.create(Unary);
    errdefer allocator.destroy(unary);
    unary.* = .{ .op = op, .rhs = rhs };

    return .{
        .node = .{ .unary = unary },
        .src = src,
    };
}

pub fn createLiteral(value: Value, src: TokenData) !Expression {
    return .{
        .node = .{ .literal = value },
        .src = src,
    };
}

// Statement helpers

pub fn createConditional(allocator: std.mem.Allocator, expr: Expression, body: Statement, otherwise: ?Statement) !Statement {
    const conditional = try allocator.create(Conditional);
    conditional.* = .{
        .expression = expr,
        .body = body,
        .otherwise = otherwise,
    };

    return .{
        .node = .{ .conditional = conditional },
    };
}

pub fn createLoop(allocator: std.mem.Allocator, initializer: ?Expression, condition: Expression, post: ?Expression, body: Statement) !Statement {
    const loop = try allocator.create(Loop);
    loop.* = .{
        .body = body,
        .condition = condition,
        .initializer = initializer,
        .post = post,
    };

    return .{
        .node = .{ .loop = loop },
    };
}

pub fn createExpressionStatement(expr: Expression) !Statement {
    return .{
        .node = .{ .expression = expr },
    };
}

pub fn createBlockStatement(stmts: []Statement) !Statement {
    const block: Block = .{ .statements = stmts };
    return .{
        .node = .{ .block = block },
    };
}

pub fn createFunction(allocator: std.mem.Allocator, name: []const u8, body: Statement, params: []*Variable) !Statement {
    const func = try allocator.create(Function);
    func.* = .{
        .name = name,
        .body = body,
        .params = params,
    };

    return .{
        .node = .{ .function = func },
    };
}

pub fn createReturn(expr: ?Expression) !Statement {
    const ret: Return = .{
        .value = expr,
    };

    return .{
        .node = .{ .@"return" = ret },
    };
}

pub fn createObject(gpa: std.mem.Allocator, name: []const u8, properties: std.StringArrayHashMapUnmanaged(?Expression), functions: []Statement) !Statement {
    const obj = try gpa.create(Object);
    obj.* = .{
        .name = name,
        .properties = properties,
        .functions = functions,
    };

    return .{
        .node = .{ .object = obj },
    };
}
