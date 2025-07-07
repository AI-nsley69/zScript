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

    std.log.debug("Source: {s}", .{addition});

    var s = Scanner{ .source = addition };

    var tokens = try s.scan(allocator);
    defer tokens.deinit(allocator);

    var p = Parser{ .tokens = tokens };
    const parsed = try p.parse(allocator);
    defer parsed.arena.deinit();

    // var ast = Debug.Ast{ .writer = std.io.getStdOut().writer(), .allocator = allocator };
    // try ast.print(parsed);

    var c = Compiler{ .allocator = allocator, .ast = parsed };

    const successful = try c.compile();
    std.debug.print("Compiler success: {any}\n", .{successful});

    var disasm = Debug.Disassembler{ .instructions = c.instructions };
    const stdout = std.io.getStdOut();
    const writer = stdout.writer();

    try disasm.disassemble(writer);

    var instance = Vm{ .instructions = c.instructions, .constants = c.constants };
    defer instance.deinit(allocator);

    var result: Vm.InterpretResult = .OK;
    while (result == .OK) {
        result = instance.run();
    }

    std.log.info("Program exited with: {any}\n", .{result});
    if (instance.return_value) |ret_val| std.log.info("Return value: {}", .{ret_val});
    // std.log.debug("Register dump: {any}\n", .{instance.registers});
    // std.log.debug("Constants dump: {any}\n", .{instance.constants});

    return;
}
