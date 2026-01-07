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
    field_access,
    method_call,
};

pub const ExpressionValue = union(ExpressionType) {
    call: *Call,
    variable: *Variable,
    infix: *Infix,
    unary: *Unary,
    literal: Value,
    native_call: *NativeCall,
    new_object: NewObject,
    field_access: *FieldAccess,
    method_call: *MethodCall,
};

pub const MethodCall = struct {
    root: Expression,
    method: Expression,
    args: []Expression,

    pub fn create(gpa: std.mem.Allocator, root: Expression, method: Expression, args: []Expression, src: TokenData) !Expression {
        const call = try gpa.create(MethodCall);
        call.* = .{ .root = root, .method = method, .args = args };

        return .{
            .node = .{ .method_call = call },
            .src = src,
        };
    }
};

pub const FieldAccess = struct {
    root: Expression,
    field: Expression,
    assignment: ?Expression,

    pub fn create(gpa: std.mem.Allocator, root: Expression, field: Expression, assignment: ?Expression, src: TokenData) !Expression {
        const prop_access = try gpa.create(FieldAccess);
        prop_access.* = .{ .root = root, .field = field, .assignment = assignment };

        return .{
            .node = .{ .field_access = prop_access },
            .src = src,
        };
    }
};

pub const NewObject = struct {
    name: []const u8,
    params: []Expression,

    pub fn create(name: []const u8, params: []Expression, src: TokenData) !Expression {
        const obj: NewObject = .{
            .name = name,
            .params = params,
        };

        return .{
            .node = .{ .new_object = obj },
            .src = src,
        };
    }
};

pub const Call = struct {
    callee: Expression,
    args: []Expression,

    pub fn create(gpa: std.mem.Allocator, callee: Expression, args: []Expression, src: TokenData) !Expression {
        const call = try gpa.create(Call);
        call.* = .{
            .callee = callee,
            .args = args,
        };

        return .{
            .node = .{ .call = call },
            .src = src,
        };
    }
};

pub const NativeCall = struct {
    args: []Expression,
    idx: u64,

    pub fn create(gpa: std.mem.Allocator, args: []Expression, idx: u64, src: TokenData) !Expression {
        const call = try gpa.create(NativeCall);
        call.* = .{
            .args = args,
            .idx = idx,
        };

        return .{
            .node = .{ .native_call = call },
            .src = src,
        };
    }
};

pub const Variable = struct {
    name: []const u8,
    initializer: ?Expression,

    pub fn create(gpa: std.mem.Allocator, init: ?Expression, name: []const u8, src: TokenData) !Expression {
        const variable = try gpa.create(Variable);
        errdefer gpa.destroy(variable);
        variable.* = .{ .initializer = init, .name = name };

        return .{
            .node = .{ .variable = variable },
            .src = src,
        };
    }
};

pub const Infix = struct {
    lhs: Expression,
    op: TokenType,
    rhs: Expression,

    pub fn create(gpa: std.mem.Allocator, op: TokenType, lhs: Expression, rhs: Expression, src: TokenData) !Expression {
        const infix = try gpa.create(Infix);
        errdefer gpa.destroy(infix);
        infix.* = .{ .op = op, .lhs = lhs, .rhs = rhs };

        return .{
            .node = .{ .infix = infix },
            .src = src,
        };
    }
};

pub const Unary = struct {
    op: TokenType,
    rhs: Expression,

    pub fn create(gpa: std.mem.Allocator, op: TokenType, rhs: Expression, src: TokenData) !Expression {
        const unary = try gpa.create(Unary);
        errdefer gpa.destroy(unary);
        unary.* = .{ .op = op, .rhs = rhs };

        return .{
            .node = .{ .unary = unary },
            .src = src,
        };
    }
};

pub const Literal = struct {
    pub fn create(value: Value, src: TokenData) !Expression {
        return .{
            .node = .{ .literal = value },
            .src = src,
        };
    }
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

    pub fn create(gpa: std.mem.Allocator, name: []const u8, properties: std.StringArrayHashMapUnmanaged(?Expression), functions: []Statement) !Statement {
        const obj = try gpa.create(Object);
        obj.* = .{ .name = name, .properties = properties, .functions = functions };
        return .{ .node = .{ .object = obj } };
    }
};

pub const Return = struct {
    value: ?Expression,

    pub fn create(expr: ?Expression) !Statement {
        const ret: Return = .{ .value = expr };
        return .{ .node = .{ .@"return" = ret } };
    }
};

pub const Function = struct {
    name: []const u8,
    params: []*Variable,
    body: Statement,

    pub fn create(gpa: std.mem.Allocator, name: []const u8, body: Statement, params: []*Variable) !Statement {
        const func = try gpa.create(Function);
        func.* = .{ .name = name, .body = body, .params = params };
        return .{ .node = .{ .function = func } };
    }
};

pub const Loop = struct {
    initializer: ?Expression,
    condition: Expression,
    post: ?Expression,
    body: Statement,

    pub fn create(gpa: std.mem.Allocator, initializer: ?Expression, condition: Expression, post: ?Expression, body: Statement) !Statement {
        const loop = try gpa.create(Loop);
        loop.* = .{ .body = body, .condition = condition, .initializer = initializer, .post = post };
        return .{ .node = .{ .loop = loop } };
    }
};

pub const Block = struct {
    statements: []Statement,

    pub fn create(stmts: []Statement) !Statement {
        return .{ .node = .{ .block = .{ .statements = stmts } } };
    }
};

pub const Conditional = struct {
    expression: Expression,
    body: Statement,
    otherwise: ?Statement,

    pub fn create(gpa: std.mem.Allocator, expr: Expression, body: Statement, otherwise: ?Statement) !Statement {
        const conditional = try gpa.create(Conditional);
        conditional.* = .{ .expression = expr, .body = body, .otherwise = otherwise };
        return .{ .node = .{ .conditional = conditional } };
    }
};

pub const Statement = struct {
    node: StatementValue,
};

pub fn createExpressionStatement(expr: Expression) !Statement {
    return .{ .node = .{ .expression = expr } };
}

pub const Program = struct {
    statements: std.ArrayListUnmanaged(Statement),
    variables: std.StringHashMapUnmanaged(VariableMetaData),
    objects: std.StringHashMapUnmanaged(*const ObjectValue.Schema),
    arena: std.heap.ArenaAllocator,
};
