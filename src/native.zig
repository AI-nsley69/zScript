const std = @import("std");
const Value = @import("value.zig").Value;

pub const Error = error{
    UnknownFunction,
};

pub const Context = struct {
    params: []Value,
};

pub const NativeFn = struct {
    params: usize,
    run: *const fn (Context) void,
};

const Errors = (Error || std.mem.Allocator.Error);

pub fn idxToFn(idx: u8) Error!NativeFn {
    return switch (idx) {
        0 => printFn,
        else => Error.UnknownFunction,
    };
}

pub fn nameToIdx(name: []const u8) u8 {
    if (std.mem.eql(u8, name, "print")) return 0;

    return 0;
}

fn print(ctx: Context) void {
    const out = std.io.getStdOut().writer();
    const value = ctx.params[0];
    return switch (value) {
        .int => out.print("{d}\n", .{value.int}),
        .float => out.print("{d}\n", .{value.float}),
        .boolean => out.print("{any}\n", .{value.boolean}),
        .string => out.print("{s}\n", .{value.string}),
    } catch {};
}

pub const printFn: NativeFn = .{ .params = 1, .run = &print };
