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
    print_asm: bool = false,
    print_ast: bool = false,
    print_tokens: bool = false,
    do_not_optimize: bool = false,
};

pub fn run(allocator: std.mem.Allocator, src: []const u8, opt: runOpts) !?Value {
    const writer = std.io.getStdOut().writer();
    // Source -> Tokens
    var lexer = Lexer{ .source = src, .arena = std.heap.ArenaAllocator.init(allocator) };
    const tokens = try lexer.scan();
    defer lexer.deinit();

    if (opt.print_tokens) {
        for (tokens.items) |token| {
            try writer.print("{s}, ", .{@tagName(token.tag)});
        }

        try writer.writeAll("\n");
    }

    // Tokens -> Ast
    var parser = Parser{};
    var parsed = try parser.parse(allocator, tokens);

    const parser_errors = parser.errors.items;
    for (parser_errors) |err| {
        const err_writer = std.io.getStdErr().writer();
        const tokenInfo = lexer.tokenInfo.items[err.idx];
        try utils.printParseError(allocator, err_writer, err, tokenInfo, opt.file, err.span);
    }
    if (parser_errors.len > 0) return null;

    if (!opt.do_not_optimize) {
        var optimizer = Optimizer{};
        parsed = try optimizer.optimizeAst(allocator, parsed);
    }
    defer parsed.arena.deinit();

    if (opt.print_ast) {
        var ast = Debug.Ast{ .writer = writer, .allocator = allocator };
        ast.print(parsed) catch {};
    }

    // Ast -> Bytecode
    var compiler = Compiler{ .allocator = allocator, .ast = parsed };
    var compiled = compiler.compile() catch {
        const stderr = std.io.getStdErr().writer();
        try utils.printCompileErr(stderr, compiler.err_msg.?);
        return null;
    };
    defer compiled.deinit(allocator);

    if (opt.print_asm) {
        Debug.disassemble(compiled, writer) catch {};
    }
    // Bytecode execution
    var vm = try Vm.init(allocator, compiled);
    defer vm.deinit();
    vm.run() catch |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    };

    return vm.result;
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
