const std = @import("std");
const zs = @import("../lib.zig");

const Ast = zs.Frontend.Ast;
const Compiler = zs.Backend.Compiler;
const Vm = zs.Runtime.Vm;
const Value = zs.Runtime.Value.Value;

const Program = Ast.Program;
const Statement = Ast.Statement;
const Expression = Ast.Expression;

pub const Error = error{
    UnsupportedValue,
};

const Errors = (Error || std.mem.Allocator.Error || Compiler.Error);

const Optimizer = @This();

gpa: std.mem.Allocator = undefined,

pub fn optimizeAst(self: *Optimizer, gpa: std.mem.Allocator, program: Program) !Program {
    var arena = std.heap.ArenaAllocator.init(gpa);
    self.gpa = arena.allocator();

    var stmts = std.ArrayListUnmanaged(Statement){};
    for (program.statements.items) |stmt| {
        const constant_fold = try self.optimizeStatement(stmt, constantFold);
        // TODO: Peephole (On bytecode-level)
        // TODO: Function inlining
        // TODO: Loop unrolling
        // TODO: Dead code elimination
        try stmts.append(self.gpa, constant_fold);
    }
    errdefer arena.deinit();
    defer program.arena.deinit();

    return .{ .arena = arena, .statements = stmts, .variables = try program.variables.clone(self.gpa), .objects = try program.objects.clone(self.gpa) };
}

fn optimizeStatement(self: *Optimizer, stmt: Statement, comptime optimizeExpression: fn (*Optimizer, Expression) Errors!Expression) !Statement {
    const node = stmt.node;
    switch (node) {
        .expression => {
            const expr = try optimizeExpression(self, node.expression);
            return try Ast.createExpressionStatement(expr);
        },
        .conditional => {
            const conditional = node.conditional.*;
            const expr = try optimizeExpression(self, conditional.expression);
            const body = try self.optimizeStatement(conditional.body, optimizeExpression);
            const otherwise = if (conditional.otherwise != null) try self.optimizeStatement(conditional.otherwise.?, optimizeExpression) else null;
            return try Ast.Conditional.create(self.gpa, expr, body, otherwise);
        },
        .block => {
            const block = node.block;
            var new_stmts = std.ArrayListUnmanaged(Statement){};
            for (block.statements) |block_stmt| {
                try new_stmts.append(self.gpa, try self.optimizeStatement(block_stmt, optimizeExpression));
            }

            return try Ast.Block.create(try new_stmts.toOwnedSlice(self.gpa));
        },
        .loop => {
            const loop = node.loop.*;
            var init: ?Expression = null;
            if (loop.initializer != null) {
                init = try optimizeExpression(self, loop.initializer.?);
            }
            const cond = try optimizeExpression(self, loop.condition);
            var post: ?Expression = null;
            if (loop.post != null) {
                post = try optimizeExpression(self, loop.post.?);
            }
            const body = try self.optimizeStatement(loop.body, optimizeExpression);
            return try Ast.Loop.create(self.gpa, init, cond, post, body);
        },
        .function => {
            const func = node.function.*;
            const body = try self.optimizeStatement(func.body, optimizeExpression);

            return try Ast.Function.create(self.gpa, try self.gpa.dupe(u8, func.name), body, try self.gpa.dupe(*Ast.Variable, func.params));
        },
        .@"return" => {
            const ret = node.@"return";
            if (ret.value == null) return try Ast.Return.create(null);
            return try Ast.Return.create(try optimizeExpression(self, ret.value.?));
        },
        else => unreachable,
    }
}

fn isFoldable(self: *Optimizer, expr: Expression) bool {
    const node = expr.node;
    return switch (node) {
        .infix => self.isFoldable(node.infix.*.lhs) and self.isFoldable(node.infix.*.rhs),
        .unary => self.isFoldable(node.unary.*.rhs),
        .literal => {
            return switch (node.literal) {
                .boolean => false,
                .float => true,
                .int => true,
                .boxed => false,
            };
        },
        else => false,
    };
}

fn constantFold(self: *Optimizer, expr: Expression) !Expression {
    if (self.isFoldable(expr)) {
        return try Ast.Literal.create(try Compiler.eval(expr), expr.src);
    }
    switch (expr.node) {
        .infix => {
            const infix = expr.node.infix.*;
            const lhs = try self.constantFold(infix.lhs);
            const rhs = try self.constantFold(infix.rhs);

            return try Ast.Infix.create(self.gpa, infix.op, lhs, rhs, expr.src);
        },

        .unary => {
            const unary = expr.node.unary.*;
            const rhs = try self.constantFold(unary.rhs);

            return try Ast.Unary.create(self.gpa, unary.op, rhs, expr.src);
        },
        .literal => return expr,
        .variable => {
            const variable = expr.node.variable.*;
            if (variable.initializer == null) return expr;
            const init = try self.constantFold(variable.initializer.?);

            return try Ast.Variable.create(self.gpa, init, variable.name, expr.src);
        },
        .call => {
            const call = expr.node.call.*;
            var params = std.ArrayListUnmanaged(Expression){};
            for (call.args) |arg| {
                try params.append(self.gpa, try self.constantFold(arg));
            }
            // Duplicate the callee node
            const old_callee = call.callee.node.variable.*;
            const callee = try Ast.Variable.create(self.gpa, old_callee.initializer, old_callee.name, call.callee.src);
            return Ast.Call.create(self.gpa, callee, try params.toOwnedSlice(self.gpa), expr.src);
        },
        .native_call => {
            const call = expr.node.native_call.*;
            var params = std.ArrayListUnmanaged(Expression){};
            for (call.args) |arg| {
                try params.append(self.gpa, try self.constantFold(arg));
            }
            // Duplicate the callee node
            return Ast.NativeCall.create(self.gpa, try params.toOwnedSlice(self.gpa), call.idx, expr.src);
        },
        else => unreachable,
    }
}
