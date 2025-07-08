const std = @import("std");
const Scanner = @import("scanner.zig");
const Ast = @import("ast.zig");
const Parser = @import("parser.zig");
const Compiler = @import("compiler.zig");
const Vm = @import("vm.zig");
const Debug = @import("debug.zig");
const utils = @import("utils.zig");

const cli = @import("cli/root.zig");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    var root = try cli.build(allocator);
    defer root.deinit();

    try root.execute(.{});

    return;
}

pub const runOpts = struct {
    file: []const u8 = "",
    printAsm: bool = false,
    printAst: bool = false,
};

pub fn run(allocator: std.mem.Allocator, src: []const u8, opt: runOpts) !?Vm.Value {
    var scanner = Scanner{ .source = src, .arena = std.heap.ArenaAllocator.init(allocator) };
    const tokens = try scanner.scan();
    defer scanner.deinit();

    const writer = std.io.getStdOut().writer();

    var parser = Parser{ .tokens = tokens };
    const parsed = try parser.parse(allocator);
    defer parsed.arena.deinit();

    const parser_errors = parser.errors.items;
    if (parser_errors.len > 0) {
        for (parser_errors) |err| {
            try utils.printErr(allocator, std.io.getStdErr().writer(), err, opt.file, err.value);
        }
        return null;
    }

    if (opt.printAst) {
        var ast = Debug.Ast{ .writer = writer, .allocator = allocator };
        try ast.print(parsed);
    }

    var compiler = Compiler{ .allocator = allocator, .ast = parsed };

    const successful = try compiler.compile();
    if (!successful) {
        try writer.writeAll("[err] AST -> Bytecode");
        return null;
    }
    // std.debug.print("Compiler success: {any}\n", .{successful});

    if (opt.printAsm) {
        var disasm = Debug.Disassembler{ .instructions = compiler.instructions };
        try disasm.disassemble(writer);
    }

    var instance = Vm{ .instructions = compiler.instructions, .constants = compiler.constants };
    defer instance.deinit(allocator);

    try instance.run();

    if (instance.return_value) |ret_val| std.log.info("Return value: {}", .{ret_val});

    return instance.return_value;
}

test "Addition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    const src = @embedFile("test/001_addition.zs");
    const res = try run(allocator, src, .{});
    try std.testing.expect(res == .HALT);
}

test "Arithmetic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }
    const src = @embedFile("test/002_arithmetic.zs");
    const res = try run(allocator, src, .{});
    try std.testing.expect(res == .HALT);
}

test "Float" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }
    const src = @embedFile("test/003_float.zs");
    const res = try run(allocator, src, .{});
    try std.testing.expect(res == .HALT);
}
