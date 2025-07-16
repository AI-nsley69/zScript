const std = @import("std");
const Lexer = @import("lexer.zig");
const Ast = @import("ast.zig");
const Parser = @import("parser.zig");
const Optimizer = @import("optimizer.zig");
const Compiler = @import("compiler.zig");
const Vm = @import("vm.zig");
const Debug = @import("debug.zig");
const utils = @import("utils.zig");
const Value = @import("value.zig").Value;

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
    printTokens: bool = false,
    optimize: bool = false,
};

pub fn run(allocator: std.mem.Allocator, src: []const u8, opt: runOpts) !?Value {
    var lexer = Lexer{ .source = src, .arena = std.heap.ArenaAllocator.init(allocator) };
    const tokens = try lexer.scan();
    defer lexer.deinit();

    const writer = std.io.getStdOut().writer();

    if (opt.printTokens) {
        for (tokens.items) |token| {
            try writer.print("{s}, ", .{@tagName(token.tag)});
        }

        try writer.writeAll("\n");
    }

    var parser = Parser{ .tokens = tokens };
    var parsed = try parser.parse(allocator);
    defer parsed.arena.deinit();

    const parser_errors = parser.errors.items;
    if (parser_errors.len > 0) {
        for (parser_errors) |err| {
            const err_writer = std.io.getStdErr().writer();
            const tokenInfo = lexer.tokenInfo.items[err.idx];
            try utils.printParseError(allocator, err_writer, err, tokenInfo, opt.file, err.span);
        }
        return null;
    }

    if (opt.optimize) {
        var optimizer = Optimizer{};
        parsed = try optimizer.optimize(allocator, parsed);
    }

    if (opt.printAst) {
        var ast = Debug.Ast{ .writer = writer, .allocator = allocator };
        ast.print(parsed) catch {};
    }

    var compiler = Compiler{ .allocator = allocator, .ast = parsed };

    var compiled = compiler.compile() catch {
        const stderr = std.io.getStdErr().writer();
        try utils.printCompileErr(stderr, compiler.err_msg.?);
        return null;
    };
    defer compiled.deinit(allocator);

    if (opt.printAsm) {
        Debug.disassemble(compiled, writer) catch {};
    }

    var vm = try Vm.init(allocator, compiled.instructions, compiled.constants);
    defer vm.deinit();
    try vm.run();

    return vm.return_value;
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

    const src = "1 + 1 + 1;";
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
    const src = "1 * 2 - 4 / 2 + 1;";
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
    const src = "1.5 + 1.5;";
    const res = try run(allocator, src, .{});
    try expect(res != null);
    try expect(res.?.float == 3.0);
}
