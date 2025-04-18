const std = @import("std");
const scanner = @import("scanner.zig");
const compiler = @import("compiler.zig");
const runtime = @import("runtime.zig");
const debug = @import("debug.zig");
const bytecode_test = @import("test/bytecode.zig");

// Test files for development
const addition = @embedFile("test/001_addition.zs");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var s = scanner.Scanner{ .source = addition };

    var tokens = try s.scan(allocator);
    defer tokens.deinit(allocator);
    std.debug.print("{any}\n", .{tokens.items});
    var c = compiler.Compiler{ .allocator = allocator, .tokens = tokens };

    const successful = try c.compile();
    std.debug.print("Compiler success: {any}\n", .{successful});
    // _ = parse;

    // var assembler = runtime.Assembler{ .allocator = allocator };
    // try bytecode_test.fib(&assembler, 10);

    var disasm = debug.Disassembler{ .instructions = c.instructions };
    const stdin = std.io.getStdIn();
    const writer = stdin.writer();

    while (disasm.has_next()) {
        try disasm.disassembleNextInstruction(writer);
    }

    var instance = runtime.Interpreter{ .instructions = c.instructions, .constants = c.constants };
    defer instance.deinit(allocator);

    var result: runtime.InterpretResult = .OK;
    while (result == .OK) {
        result = instance.run();
    }

    std.log.info("Program exited with: {any}\n", .{result});
    std.log.debug("Register dump: {any}\n", .{instance.registers});
    std.log.debug("Constants dump: {any}\n", .{instance.constants});

    return;
}
