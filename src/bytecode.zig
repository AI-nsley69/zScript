const std = @import("std");
const Value = @import("value.zig").Value;

pub const OpCodes = enum(u8) {
    @"return",
    halt,
    noop,
    copy,
    load_int,
    load_float,
    load_bool,
    load_const,
    load_param,
    store_param,
    call,
    native_call,
    add,
    sub,
    mult,
    divide,
    jump,
    jump_eql,
    jump_neq,
    eql,
    neq,
    less_than,
    lte,
    greater_than,
    gte,
    xor,
    @"and",
    not,
    @"or",
};

pub const RegisterSize = u16;

pub const Function = struct {
    name: []const u8,
    body: []u8,
    reg_size: RegisterSize,
};
