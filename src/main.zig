const std = @import("std");
const bytecode = @import("bytecode/bytecode.zig");
const interpreter = @import("bytecode/interpreter.zig");
const debug = @import("bytecode/debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var instance = interpreter.Interpreter{};
    @memset(&instance.registers, 0);
    defer instance.deinit(allocator);

    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(bytecode.OpCodes.LOAD_IMMEDIATE), 0x01, 0x00, 0x01 });

    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(bytecode.OpCodes.LOAD_IMMEDIATE), 0x02, 0x00, 0x44 });

    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(bytecode.OpCodes.ADD), 0x03, 0x01, 0x02 });

    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(bytecode.OpCodes.HALT), 0x00, 0x00, 0x00 });

    // instance.dump(&allocator);
    var disasm = debug.Dissassembler{ .instructions = instance.instructions };
    const stdin = std.io.getStdIn();
    const writer = stdin.writer();

    while (disasm.has_next()) {
        try disasm.dissassembleNextInstruction(writer);
    }

    var result: interpreter.InterpretResult = .OK;
    while (result == .OK) {
        result = instance.run();
        // std.debug.print("Run result: {any}\n", .{result});
    }

    std.log.info("Program exited with: {any}\n", .{result});

    std.log.debug("Register dump: {any}", .{instance.registers});

    return;
}
