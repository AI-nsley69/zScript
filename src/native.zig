const std = @import("std");
const Value = @import("value.zig").Value;
const Gc = @import("gc.zig");

pub const Error = error{
    UnknownFunction,
};

pub const Context = struct {
    params: []Value,
};

pub const NativeFn = struct {
    params: u64,
    run: *const fn (Context, *Gc) void,
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

fn print(ctx: Context, gc: *Gc) void {
    var out_buf: [1024]u8 = undefined;
    var out = std.fs.File.stdout().writer(&out_buf).interface;
    const value = ctx.params[0];
    switch (value) {
        .int => out.print("{d}\n", .{value.int}) catch {},
        .float => out.print("{d}\n", .{value.float}) catch {},
        .boolean => out.print("{any}\n", .{value.boolean}) catch {},
        .boxed => {
            switch (value.boxed.kind) {
                .string => out.print("{s}\n", .{Value.asString(value, gc) catch "N/A"}) catch {},
                else => {
                    std.log.debug("Unhandled value type!", .{});
                    unreachable;
                },
            }
        },
    }
    out.flush() catch {};
}

pub const printFn: NativeFn = .{ .params = 1, .run = &print };
