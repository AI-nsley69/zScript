const std = @import("std");
const interpreter = @import("interpreter.zig");
const bytecode = @import("bytecode.zig");

pub fn fmtInstruction(allocator: *std.mem.Allocator, input: *[]const u8, pointer: usize, line: usize) []const u8 {
    return std.fmt.allocPrint(allocator.*, "[{x:0>4} -> L{d}] {s}", .{ pointer, line, input.* }) catch "Unable to format instruction.";
}

pub fn constantInstruction(allocator: *std.mem.Allocator, val: bytecode.Value, pointer: usize, line: usize) []const u8 {
    var instruction_str: []const u8 = std.fmt.allocPrint(allocator.*, "CONST #{d}", .{val}) catch return "Unable to format instruction.";
    return fmtInstruction(allocator, &instruction_str, pointer, line);
}
