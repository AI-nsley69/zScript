const std = @import("std");
const Ast = @import("ast.zig");
const Vm = @import("vm.zig");

const Program = Ast.Program;
const Stmt = Ast.Stmt;
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

    var stmts = std.ArrayListUnmanaged(Stmt){};

    for (program.stmts.items) |stmt| {
        try stmts.append(self.allocator, .{ .expr = try self.constantFold(stmt.expr) });
    }

    errdefer arena.deinit();
    defer program.arena.deinit();

    return .{ .arena = arena, .stmts = stmts };
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
                        .int => .{ .int = @divExact(lhs.int, rhs.int) },
                        .float => .{ .float = @divExact(lhs.float, rhs.float) },
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
    };
}

fn constantFold(self: *Optimizer, expr: Expression) !Expression {
    if (self.isFoldable(expr)) {
        return try Ast.createLiteral(try self.eval(expr), expr.src);
    } else {
        switch (expr.node) {
            .infix => {
                const infix = expr.node.infix.*;
                var lhs = infix.lhs;
                if (self.isFoldable(infix.lhs)) {
                    lhs = try Ast.createLiteral(try self.eval(lhs), expr.src);
                }

                var rhs = infix.rhs;
                if (self.isFoldable(infix.rhs)) {
                    rhs = try Ast.createLiteral(try self.eval(rhs), expr.src);
                }

                return try Ast.createInfix(self.allocator, infix.op, lhs, rhs, expr.src);
            },

            .unary => return expr,
            .literal => return expr,
        }
    }
}
