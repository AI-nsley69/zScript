const runtime = @import("vm.zig");
const scanner = @import("scanner.zig");

pub const ExpressionType = enum {
    expr,
    literal,
};

pub const ExpressionValue = union(ExpressionType) {
    expr: *Expression,
    literal: runtime.Value,
};

pub const Operands = enum {
    Add,
    Subtract,
    Divide,
    Multiply,
};

pub const Expression = struct {
    lhs: ExpressionValue,
    operand: ?Operands,
    rhs: ?ExpressionValue,
};
