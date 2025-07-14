const std = @import("std");
const Ast = @import("ast.zig");
const Vm = @import("vm.zig");

const Program = Ast.Program;
const Statement = Ast.Statement;
const Expression = Ast.Expression;
const Value = Vm.Value;

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
        const node = stmt.node;
        if (node != .expression) continue;
        const expr = try self.constantFold(node.expression);
        try stmts.append(self.allocator, try Ast.createExpressionStatement(expr));
    }

    errdefer arena.deinit();
    defer program.arena.deinit();

    return .{ .arena = arena, .statements = stmts };
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
                .string => false,
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
