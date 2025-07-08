const std = @import("std");
const zli = @import("zli");

const Flag = zli.Flag;

const Scanner = @import("../scanner.zig");
const Ast = @import("../ast.zig");
const Parser = @import("../parser.zig");
const Compiler = @import("../compiler.zig");
const Vm = @import("../vm.zig");
const Debug = @import("../debug.zig");
const bytecode_test = @import("../test/bytecode.zig");

pub fn build(allocator: std.mem.Allocator) !*zli.Command {
    const root = try zli.Command.init(allocator, .{
        .name = "zScript",
        .description = "Yet another programming language",
    }, run);
    try root.addFlag(ast_dump);
    try root.addFlag(asm_dump);
    try root.addPositionalArg(.{
        .name = "source",
        .required = true,
        .description = "Source file to be executed",
    });

    // try root.addCommands(&.{
    //     try run.register(allocator),
    //     try version.register(allocator),
    // });

    return root;
}

fn showHelp(ctx: zli.CommandContext) !void {
    try ctx.command.printHelp();
}

const ast_dump: Flag = .{ .name = "ast", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Dump AST tree" };
const asm_dump: Flag = .{ .name = "asm", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Dump asm instructions" };

fn printErr(allocator: std.mem.Allocator, writer: std.fs.File.Writer, token: Scanner.Token, src_file: []const u8, msg: []const u8) !void {
    const err_msg = try std.fmt.allocPrint(allocator, "{s}:{d}:{d}: error: {s}\n", .{ src_file, token.line, token.pos, msg });
    defer allocator.free(err_msg);
    try writer.writeAll(err_msg);

    const source_aligned = try std.fmt.allocPrint(allocator, "  {s}\n", .{token.line_source});
    defer allocator.free(source_aligned);
    try writer.writeAll(source_aligned);

    const ptr_msg = try allocator.alloc(u8, 2 + token.line_source.len + 1);
    defer allocator.free(ptr_msg);
    @memset(ptr_msg, ' ');
    // std.debug.print("{s}\n", .{token.line_source});
    ptr_msg[token.pos + 1] = '^';
    ptr_msg[ptr_msg.len - 1] = '\n';
    try writer.writeAll(ptr_msg);
}

fn run(ctx: zli.CommandContext) !void {
    // Test files for development

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const file = try std.fs.cwd().openFile(ctx.positional_args[0], .{});

    const contents = try file.readToEndAlloc(allocator, 1 << 24);
    defer allocator.free(contents);

    std.log.debug("Source: {s}", .{contents});

    var scanner = Scanner{ .source = contents, .arena = std.heap.ArenaAllocator.init(allocator) };
    const tokens = try scanner.scan();
    defer scanner.deinit();

    const writer = std.io.getStdOut().writer();

    // for (tokens.items) |token| {
    //     if (token.type != .err) continue;
    //     try printErr(allocator, std.io.getStdErr().writer(), token, ctx.positional_args[0], token.value);
    //     std.process.exit(1);
    // }

    var parser = Parser{ .tokens = tokens };
    const parsed = try parser.parse(allocator);
    defer parsed.arena.deinit();

    const parser_errors = parser.errors.items;
    if (parser_errors.len > 0) {
        for (parser_errors) |err| {
            try printErr(allocator, std.io.getStdErr().writer(), err, ctx.positional_args[0], err.value);
        }
        std.process.exit(1);
    }

    if (ctx.flag("ast", bool)) {
        var ast = Debug.Ast{ .writer = writer, .allocator = allocator };
        try ast.print(parsed);
    }

    var compiler = Compiler{ .allocator = allocator, .ast = parsed };

    const successful = try compiler.compile();
    if (!successful) {
        try writer.writeAll("[err] AST -> Bytecode");
        std.process.exit(1);
    }
    // std.debug.print("Compiler success: {any}\n", .{successful});

    if (ctx.flag("asm", bool)) {
        var disasm = Debug.Disassembler{ .instructions = compiler.instructions };
        try disasm.disassemble(writer);
    }

    var instance = Vm{ .instructions = compiler.instructions, .constants = compiler.constants };
    defer instance.deinit(allocator);

    var result: Vm.InterpretResult = .OK;
    while (result == .OK) {
        result = instance.run();
    }

    std.log.info("Program exited with: {any}\n", .{result});
    if (instance.return_value) |ret_val| std.log.info("Return value: {}", .{ret_val});
}
