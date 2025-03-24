const std = @import("std");
const interpreter = @import("bytecode/interpreter.zig");
const debug = @import("bytecode/debug.zig");
const bytecode_test = @import("test/bytecode.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var instance = interpreter.Interpreter{};
    @memset(&instance.registers, 0);
    defer instance.deinit(allocator);

    try bytecode_test.fib(allocator, &instance.instructions, 10);
    std.log.debug("Instructions dump: {any}", .{instance.instructions.items});
    // instance.dump(&allocator);
    var disasm = debug.Disassembler{ .instructions = instance.instructions };
    const stdin = std.io.getStdIn();
    const writer = stdin.writer();

    while (disasm.has_next()) {
        try disasm.disassembleNextInstruction(writer);
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
