const std = @import("std");
const bytecode = @import("bytecode/bytecode.zig");
const interpreter = @import("bytecode/interpreter.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var instance = interpreter.Interpreter{
        .instructions = std.ArrayList(u8).init(allocator),
        .constants = std.ArrayList(bytecode.Value).init(allocator),
    };
    @memset(&instance.registers, 0);
    defer instance.deinit();

    try instance.instructions.appendSlice(&[_]u8{
        @intFromEnum(bytecode.OpCodes.LOAD_IMMEDIATE),
        0x01, // Register 1,
        0x00, // ->
        0x01, // 0x0001
    });

    try instance.instructions.appendSlice(&[_]u8{
        @intFromEnum(bytecode.OpCodes.LOAD_IMMEDIATE),
        0x02, // Register 2,
        0x00, // ->
        0x01, // 0x0001
    });

    try instance.instructions.appendSlice(&[_]u8{
        @intFromEnum(bytecode.OpCodes.HALT),
        0x00,
        0x00,
        0x00,
    });

    instance.dump(&allocator);

    // var result: interpreter.InterpretResult = undefined;
    // while (result == .OK) {
    //     result = instance.run(&allocator);
    //     std.debug.print("Run result: {any}\n", .{result});
    // }

    // std.log.info("Program exited with: {any}\n", .{result});

    return;
}
