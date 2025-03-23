const std = @import("std");
const interpreter = @import("interpreter.zig");

pub const OpCodes = enum(u8) {
    CONSTANT,
    RETURN,
};

pub const Value = f64;
