const std = @import("std");
const mecha = @import("mecha");

pub const program = mecha.many(binaryExpression, .{});

const expression = mecha.oneOf(.{
    binaryExpression,
    literal,
});

// const expression = mecha.combine(.{
//     mecha.oneOf(.{
//         binaryExpression,
//         literal,
//     }),
//     mecha.ascii.char(';').discard(),
// });

const binaryExpression = mecha.combine(.{
    literal,
    binaryOperand,
    literal,
});

const binaryOperand = mecha.oneOf(.{
    mecha.ascii.char('+'),
});

const literal = mecha.oneOf(.{
    mecha.int(u64, .{ .parse_sign = false }),
});

test "Simple expression" {
    const alloc = std.testing.allocator;

    try program.parse(alloc, "1 + 2;");
}
