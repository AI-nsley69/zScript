const std = @import("std");
const lib = @import("./lib.zig");

const expect = std.testing.expect;

fn expectNoLeak(gpa: std.heap.DebugAllocator(.{})) !void {
    var debug_gpa = gpa;
    const check = debug_gpa.deinit();
    try expect(check != .leak);
}

test "Integer Arithmetic" {
    var stdout = std.fs.File.stdout();
    var writer = stdout.writerStreaming(&.{}).interface;

    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/int_arithmetic.zs";
    const res = try lib.run(&writer, gpa, @embedFile(file), .{ .file = file });
    const val = res.value;

    try expect(val != null);
    try expect(val.? == .int);
    try expect(val.?.int == 6);
    // Cleanup
    res.deinit(gpa);
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Float Arithmetic" {
    var stdout = std.fs.File.stdout();
    var writer = stdout.writerStreaming(&.{}).interface;

    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/float_arithmetic.zs";
    const res = try lib.run(&writer, gpa, @embedFile(file), .{ .file = file });
    const val = res.value;

    try expect(val != null);
    try expect(val.? == .float);
    try expect(val.?.float == 1.5);
    // Cleanup
    res.deinit(gpa);
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Integer Zero Division" {
    var stdout = std.fs.File.stdout();
    var writer = stdout.writerStreaming(&.{}).interface;

    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/int_zero_div.zs";
    const res = lib.run(&writer, gpa, @embedFile(file), .{ .file = file });
    // Function throws error on zero div
    try expect(res == error.UnsupportedOperation);

    try writer.flush();
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Float Zero Division" {
    var stdout = std.fs.File.stdout();
    var writer = stdout.writerStreaming(&.{}).interface;

    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/float_zero_div.zs";
    const res = lib.run(&writer, gpa, @embedFile(file), .{ .file = file });
    // Function throws error on zero div
    try expect(res == error.UnsupportedOperation);
    try writer.flush();
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Recursion Overflow" {
    var stdout = std.fs.File.stdout();
    var writer = stdout.writerStreaming(&.{}).interface;

    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/recursion_overflow.zs";
    const res = lib.run(&writer, gpa, @embedFile(file), .{ .file = file });
    // Function throws error stack overflow (max call depth > current call stack depth)
    try expect(res == error.StackOverflow);
    try writer.flush();
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Recursion With Base Case" {
    var stdout = std.fs.File.stdout();
    var writer = stdout.writerStreaming(&.{}).interface;

    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/recursion_no_overflow.zs";
    const res = try lib.run(&writer, gpa, @embedFile(file), .{ .file = file });
    const val = res.value;

    try expect(val != null);
    try expect(val.? == .int);
    try expect(val.?.int == 2);

    // Cleanup
    res.deinit(gpa);
    try writer.flush();
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Undefined variable" {
    var stdout = std.fs.File.stdout();
    var writer = stdout.writerStreaming(&.{}).interface;

    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/undefined_variable.zs";
    const res = try lib.run(&writer, gpa, @embedFile(file), .{ .file = file });

    try expect(res.compile != null);
    try expect(res.compile.?.err != null);
    try expect(res.compile.?.err.?.len > 0);
    // Cleanup
    res.deinit(gpa);
    try writer.flush();
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}

test "Constant Assignment" {
    var stdout = std.fs.File.stdout();
    var writer = stdout.writerStreaming(&.{}).interface;

    var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_gpa.allocator();

    const file = "./tests/const_assignment.zs";
    const res = try lib.run(&writer, gpa, @embedFile(file), .{ .file = file });

    try expect(res.compile != null);
    try expect(res.compile.?.err != null);
    try expect(res.compile.?.err.?.len > 0);
    // Cleanup
    res.deinit(gpa);
    try writer.flush();
    // Test for potential leaks
    try expectNoLeak(debug_gpa);
}
