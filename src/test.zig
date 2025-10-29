const std = @import("std");
const lib = @import("./lib.zig");

const expect = std.testing.expect;

fn expectNoLeak(gpa: std.heap.DebugAllocator(.{})) !void {
    var debug_gpa = gpa;
    const check = debug_gpa.deinit();
    try expect(check != .leak);
}

test "Integer Arithmetic" {
    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/int_arithmetic.zs";
    const val = try lib.run(gpa, @embedFile(file), .{ .file = file });
    try expect(val != null);
    try expect(val.? == .int);
    try expect(val.?.int == 6);
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
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
    try expectNoLeak(debug_gpa);
}

test "Integer Zero Division" {
    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/int_zero_div.zs";
    const val = lib.run(gpa, @embedFile(file), .{ .file = file });
    // Function throws error on zero div
    try expect(val == error.UnsupportedOperation);
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Float Zero Division" {
    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/float_zero_div.zs";
    const val = lib.run(gpa, @embedFile(file), .{ .file = file });
    // Function throws error on zero div
    try expect(val == error.UnsupportedOperation);
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Recursion Overflow" {
    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/recursion_overflow.zs";
    const val = lib.run(gpa, @embedFile(file), .{ .file = file });
    // Function throws error stack overflow (max call depth > current call stack depth)
    try expect(val == error.StackOverflow);
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Recursion With Base Case" {
    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/recursion_no_overflow.zs";
    const val = try lib.run(gpa, @embedFile(file), .{ .file = file });
    try expect(val != null);
    try expect(val.? == .int);
    try expect(val.?.int == 2);
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Undefined variable" {
    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/undefined_variable.zs";
    const val = lib.run(gpa, @embedFile(file), .{ .file = file });
    try expect(val == error.UndefinedVariable);
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Constant Assignment" {
    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/const_assignment.zs";
    const val = lib.run(gpa, @embedFile(file), .{ .file = file });
    try expect(val == error.ConstAssignment);
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}
