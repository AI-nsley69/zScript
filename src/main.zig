const std = @import("std");
const lib = @import("lib.zig");
const cli = @import("cli/root.zig");
const builtin = @import("builtin");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

// Function to strip unnecessary overhead when looking at performance of certain parts of the runtime.
fn benchmark() !void {
    _ = try lib.run(std.heap.smp_allocator, @embedFile("./bench.zs"), .{});
}

pub fn main() !void {
    // try benchmark();
    const gpa = std.heap.smp_allocator;
    var root = try cli.build(gpa);
    defer root.deinit();

    try root.execute(.{});

    return;
}

const expect = std.testing.expect;

// Import the tests from test-file
test {
    _ = @import("test.zig");
}
