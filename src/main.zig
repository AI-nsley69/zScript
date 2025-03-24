const std = @import("std");
const parser = @import("parser/parser.zig");
const runtime = @import("bytecode/runtime.zig");
const debug = @import("bytecode/debug.zig");
const bytecode_test = @import("test/bytecode.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const parse = try parser.program.parse(allocator, "1 + 1;");
    switch (parse.value) {
        .err => return error.OtherError,
        .ok => std.debug.print("{any}\n", .{parse.value.ok}),
    }
    // _ = parse;

    // var assembler = runtime.Assembler{ .allocator = allocator };
    // try bytecode_test.fib(&assembler, 10);

    // var instance = runtime.Interpreter{ .instructions = assembler.instructions };
    // @memset(&instance.registers, 0);
    // defer instance.deinit(allocator);

    // var disasm = debug.Disassembler{ .instructions = instance.instructions };
    // const stdin = std.io.getStdIn();
    // const writer = stdin.writer();

    // while (disasm.has_next()) {
    //     try disasm.disassembleNextInstruction(writer);
    // }

    // var result: runtime.InterpretResult = .OK;
    // while (result == .OK) {
    //     result = instance.run();
    // }

    // std.log.info("Program exited with: {any}\n", .{result});
    // std.log.debug("Register dump: {any}", .{instance.registers});

    return;
}
