const std = @import("std");
const Lexer = @import("lexer.zig");
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
    var lexer = Lexer{ .source = src, .arena = std.heap.ArenaAllocator.init(allocator) };
    const tokens = try lexer.scan();
    defer lexer.deinit();

    const writer = std.io.getStdOut().writer();

    var parser = Parser{ .tokens = tokens };
    const parsed = try parser.parse(allocator);
    defer parsed.arena.deinit();

    const parser_errors = parser.errors.items;
    if (parser_errors.len > 0) {
        for (parser_errors) |err| {
            try utils.printErr(allocator, std.io.getStdErr().writer(), err, opt.file, err.span);
        }
        return null;
    }

    if (opt.printAst) {
        var ast = Debug.Ast{ .writer = writer, .allocator = allocator };
        ast.print(parsed) catch {};
    }

    var compiler = Compiler{ .allocator = allocator, .ast = parsed };

    const successful = try compiler.compile();
    if (!successful) {
        try writer.writeAll("[err] AST -> Bytecode");
        return null;
    }

    if (opt.printAsm) {
        var disasm = Debug.Disassembler{ .instructions = compiler.instructions };
        disasm.disassemble(writer) catch {};
    }

    var instance = Vm{ .instructions = compiler.instructions, .constants = compiler.constants };
    defer instance.deinit(allocator);
    try instance.run();

    return instance.return_value;
}

const expect = std.testing.expect;
test "Addition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }

    const src = "1 + 1 + 1";
    const res = try run(allocator, src, .{});
    try expect(res != null);
    try expect(res.?.int == 3);
}

test "Arithmetic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }
    const src = "1 * 2 - 4 / 2 + 1";
    const res = try run(allocator, src, .{});
    try expect(res != null);
    try expect(res.?.int == 1);
}

test "Float" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) expect(false) catch @panic("TEST FAIL");
    }
    const src = "1.5 + 1.5";
    const res = try run(allocator, src, .{});
    try expect(res != null);
    try expect(res.?.float == 3.0);
}
