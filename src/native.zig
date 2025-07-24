const std = @import("std");
const Value = @import("value.zig").Value;

pub const Error = error{
    UnknownFunction,
};

const Errors = (Error || std.mem.Allocator.Error);

pub fn idxToFn(idx: u8) Error!*const fn (Value) void {
    return switch (idx) {
        0 => &print,
        else => Error.UnknownFunction,
    };
}

pub fn nameToIdx(name: []const u8) u8 {
    if (std.mem.eql(u8, name, "print")) return 0;

    return 0;
}

pub fn print(value: Value) void {
    const out = std.io.getStdOut().writer();
    return switch (value) {
        .int => out.print("{d}\n", .{value.int}),
        .float => out.print("{d}\n", .{value.float}),
        .boolean => out.print("{any}\n", .{value.boolean}),
    } catch {};
}
