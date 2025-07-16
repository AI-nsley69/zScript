const std = @import("std");
const Ast = @import("ast.zig");
const Vm = @import("vm.zig");
const Value = @import("value.zig").Value;

const Program = Ast.Program;
const Statement = Ast.Statement;
const Expression = Ast.Expression;

pub const Error = error{
    UnsupportedValue,
};

const Optimizer = @This();

allocator: std.mem.Allocator = undefined,

pub fn optimize(self: *Optimizer, allocator: std.mem.Allocator, program: Program) !Program {
    var arena = std.heap.ArenaAllocator.init(allocator);
    self.allocator = arena.allocator();

    var stmts = std.ArrayListUnmanaged(Statement){};
    for (program.statements.items) |stmt| {
        try stmts.append(self.allocator, try self.optimizeStatement(stmt));
    }
    errdefer arena.deinit();
    defer program.arena.deinit();

    return .{ .arena = arena, .statements = stmts };
}

fn optimizeStatement(self: *Optimizer, stmt: Statement) !Statement {
    const node = stmt.node;
    switch (node) {
        .expression => {
            const expr = try self.constantFold(node.expression);
            return try Ast.createExpressionStatement(expr);
        },
        .conditional => {
            const conditional = node.conditional.*;
            const expr = try self.constantFold(conditional.expression);
            const body = try self.optimizeStatement(conditional.body);
            const otherwise = if (conditional.otherwise != null) try self.optimizeStatement(conditional.otherwise.?) else null;
            return try Ast.createConditional(self.allocator, expr, body, otherwise);
        },
        .block => {
            const block = node.block;
            var new_stmts = std.ArrayListUnmanaged(Statement){};
            for (block.statements) |block_stmt| {
                try new_stmts.append(self.allocator, try self.optimizeStatement(block_stmt));
            }

            return try Ast.createBlockStatement(try new_stmts.toOwnedSlice(self.allocator));
        },
        else => return stmt,
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
            };
        },
        .variable => false,
    };
}

fn eval(self: *Optimizer, expr: Expression) !Value {
    const node = expr.node;
    return switch (node) {
        .infix => {
            const infix = node.infix.*;
            const lhs = try self.eval(infix.lhs);
            const rhs = try self.eval(infix.rhs);

            return switch (infix.op) {
                .add => {
                    return switch (lhs) {
                        .int => .{ .int = lhs.int + rhs.int },
                        .float => .{ .float = lhs.float + rhs.float },
                        else => Error.UnsupportedValue,
                    };
                },
                .sub => {
                    return switch (lhs) {
                        .int => .{ .int = lhs.int - rhs.int },
                        .float => .{ .float = lhs.float - rhs.float },
                        else => Error.UnsupportedValue,
                    };
                },
                .mul => {
                    return switch (lhs) {
                        .int => .{ .int = lhs.int * rhs.int },
                        .float => .{ .float = lhs.float * rhs.float },
                        else => Error.UnsupportedValue,
                    };
                },
                .div => {
                    return switch (lhs) {
                        .int => .{ .int = @divFloor(lhs.int, rhs.int) },
                        .float => .{ .float = @divFloor(lhs.float, rhs.float) },
                        else => Error.UnsupportedValue,
                    };
                },
                else => Error.UnsupportedValue,
            };
        },
        .unary => {
            return try self.eval(expr.node.unary.*.rhs);
        },

        .literal => return expr.node.literal,
        else => Error.UnsupportedValue,
    };
}

fn constantFold(self: *Optimizer, expr: Expression) !Expression {
    if (self.isFoldable(expr)) {
        return try Ast.createLiteral(try self.eval(expr), expr.src);
    } else {
        switch (expr.node) {
            .infix => {
                const infix = expr.node.infix.*;
                const lhs = try self.constantFold(infix.lhs);

                const rhs = try self.constantFold(infix.rhs);

                return try Ast.createInfix(self.allocator, infix.op, lhs, rhs, expr.src);
            },

            .unary => {
                const unary = expr.node.unary.*;
                const rhs = try self.constantFold(unary.rhs);
                return try Ast.createUnary(self.allocator, unary.op, rhs, expr.src);
            },
            .literal => return expr,
            .variable => {
                const variable = expr.node.variable.*;
                if (variable.initializer == null) return expr;
                const init = try self.constantFold(variable.initializer.?);

                return try Ast.createVariable(self.allocator, init, variable.name, variable.mutable, expr.src);
            },
        }
    }
}
