const std = @import("std");
const interpreter = @import("interpreter.zig");

pub const OpCodes = enum(u8) {
    HALT,
    NOP,
    LOAD_IMMEDIATE,
    LOAD_WORD,
    STORE_WORD,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    JUMP,
    BRANCH_IF_EQUAL,
    XOR,
    AND,
    OR,
};

pub const Value = f64;
