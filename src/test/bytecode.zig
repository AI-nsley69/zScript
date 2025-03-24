const std = @import("std");
const interpreter = @import("../bytecode/interpreter.zig");

pub fn fib(alloc: std.mem.Allocator, instructions: *std.ArrayListUnmanaged(u8), n: u8) !void {
    try instructions.*.appendSlice(alloc, &[_]u8{
        // Setup
        @intFromEnum(interpreter.OpCodes.LOAD_IMMEDIATE), 0x01, 0x00, 0x00, // a
        @intFromEnum(interpreter.OpCodes.LOAD_IMMEDIATE), 0x02, 0x00, 0x01, // b
        @intFromEnum(interpreter.OpCodes.LOAD_IMMEDIATE), 0x03, 0x00, 0x00, // tmp value
        @intFromEnum(interpreter.OpCodes.LOAD_IMMEDIATE), 0x04, 0x00, 0x00, // Accumulator
        @intFromEnum(interpreter.OpCodes.LOAD_IMMEDIATE), 0x05, 0x00, 0x01, // Increment value
        @intFromEnum(interpreter.OpCodes.LOAD_IMMEDIATE), 0x06, 0x00, n, // n -> number in sequence - 1
        @intFromEnum(interpreter.OpCodes.LOAD_IMMEDIATE), 0x07, 0x00, 0x14, // Jump address
        // Loop
        @intFromEnum(interpreter.OpCodes.ADD), 0x03, 0x01, 0x02, // 0x14
        @intFromEnum(interpreter.OpCodes.ADD), 0x04, 0x04, 0x05, // Add increment reg to accumulator
        @intFromEnum(interpreter.OpCodes.ADD), 0x02, 0x01, 0x00, // Copy a to b
        @intFromEnum(interpreter.OpCodes.ADD), 0x01, 0x03, 0x00, // Copy tmp to a
        @intFromEnum(interpreter.OpCodes.BRANCH_IF_NOT_EQUAL), 0x07, 0x04, 0x06, // Branch if value not equal
        // Break out of the loop
        @intFromEnum(interpreter.OpCodes.HALT), 0x00, 0x00, 0x00, // Halt execution
    });
}
