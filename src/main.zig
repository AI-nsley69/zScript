const std = @import("std");

const cli = @import("cli/root.zig");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    var root = try cli.build(allocator);
    defer root.deinit();

    try root.execute(.{});
    // std.log.debug("Register dump: {any}\n", .{instance.registers});
    // std.log.debug("Constants dump: {any}\n", .{instance.constants});

    return;
}
