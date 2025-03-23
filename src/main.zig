const std = @import("std");
const bytecode = @import("bytecode/bytecode.zig");
const interpreter = @import("bytecode/interpreter.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var instance = interpreter.Interpreter{ .instructions = std.ArrayList(u8).init(allocator), .lines = std.ArrayList(usize).init(allocator), .constants = std.ArrayList(bytecode.Value).init(allocator) };
    defer instance.deinit();

    const val: bytecode.Value = 100;
    const const_idx = try instance.add_constant(val, 123);
    try instance.add_instruction(&[_]u8{ @intFromEnum(bytecode.OpCodes.CONSTANT), const_idx }, 123);

    try instance.add_instruction(&[_]u8{@intFromEnum(bytecode.OpCodes.RETURN)}, 123);

    instance.dump(&allocator);

    return;
}
