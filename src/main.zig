const std = @import("std");
const lib = @import("lib.zig");
const cli = @import("cli/root.zig");
const builtin = @import("builtin");

var debug_gpa: std.heap.DebugAllocator(.{}) = .init;

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
test "Addition" {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = alloc.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }

    const src = "1 + 1 + 1;";
    const res = try lib.run(gpa, src, .{});
    try expect(res != null);
    try expect(res.?.int == 3);
}

test "Arithmetic" {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = alloc.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }
    const src = "1 * 2 - 4 / 2 + 1;";
    const res = try lib.run(gpa, src, .{});
    try expect(res != null);
    try expect(res.?.int == 1);
}

test "Float" {
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = alloc.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }
    const src = "1.5 + 1.5;";
    const res = try lib.run(gpa, src, .{});
    try expect(res != null);
    try expect(res.?.float == 3.0);
}
