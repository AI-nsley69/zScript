const std = @import("std");
const lib = @import("./lib.zig");

const expect = std.testing.expect;

test "Integer Arithmetic" {
    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/int_arithmetic.zs";
    const val = try lib.run(gpa, @embedFile(file), .{ .file = file });
    try expect(val != null);
    try expect(val.? == .int);
    try expect(val.?.int == 6);
    // Test for potential leaks
    const has_leak = debug_gpa.deinit();
    try expect(has_leak == .ok);
}

test "Float Arithmetic" {
    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/float_arithmetic.zs";
    const val = try lib.run(gpa, @embedFile(file), .{ .file = file });
    try expect(val != null);
    try expect(val.? == .float);
    try expect(val.?.float == 1.5);
    // Test for potential leaks
    const has_leak = debug_gpa.deinit();
    try expect(has_leak == .ok);
}
