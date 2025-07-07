const std = @import("std");
const Scanner = @import("scanner.zig");
const Ast = @import("ast.zig");
const Parser = @import("parser.zig");
const Compiler = @import("compiler.zig");
const Vm = @import("vm.zig");
const Debug = @import("debug.zig");
const bytecode_test = @import("test/bytecode.zig");

// Test files for development
const addition = @embedFile("test/001_addition.zs");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var s = Scanner{ .source = addition };

    var tokens = try s.scan(allocator);
    defer tokens.deinit(allocator);

    var p = Parser{ .tokens = tokens };
    const parsed = try p.parse(allocator);
    defer parsed.arena.deinit();

    var ast = Debug.Ast{ .writer = std.io.getStdOut().writer(), .allocator = allocator };
    try ast.print(parsed);
    // std.log.debug("{any}", .{parsed.stmts.*.items[0]});
    // std.debug.print("{any}\n", .{tokens.items});
    // var c = Compiler{ .allocator = allocator, .tokens = tokens };

    // const successful = try c.compile();
    // // std.debug.print("Compiler success: {any}\n", .{successful});
    // _ = successful;

    // // var assembler = runtime.Assembler{ .allocator = allocator };
    // // try bytecode_test.fib(&assembler, 10);

    // var disasm = Disassembler{ .instructions = c.instructions };
    // const stdin = std.io.getStdIn();
    // const writer = stdin.writer();

    // while (disasm.has_next()) {
    //     try disasm.disassembleNextInstruction(writer);
    // }

    // var instance = Vm{ .instructions = c.instructions, .constants = c.constants };
    // defer instance.deinit(allocator);

    // var result: Vm.InterpretResult = .OK;
    // while (result == .OK) {
    //     result = instance.run();
    // }

    // std.log.info("Program exited with: {any}\n", .{result});
    // std.log.debug("Register dump: {any}\n", .{instance.registers});
    // std.log.debug("Constants dump: {any}\n", .{instance.constants});

    return;
}
