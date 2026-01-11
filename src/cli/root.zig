const std = @import("std");
const builtin = @import("builtin");
const lib = @import("../lib.zig");
const utils = @import("../utils.zig");
const zli = @import("zli");
const ansi = @import("ansi_term");

const Flag = zli.Flag;
const format = ansi.format;

const version_cmd = @import("version.zig");
const check_cmd = @import("check.zig");

const ast_dump: Flag = .{ .name = "print-ast", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Dump AST tree" };
const asm_dump: Flag = .{ .name = "print-bytecode", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Dump asm instructions" };
const optimize: Flag = .{ .name = "disable-optimization", .type = .Bool, .default_value = .{ .Bool = true }, .description = "Disable optimizations" };

pub fn build(writer: *std.io.Writer, gpa: std.mem.Allocator) !*zli.Command {
    const root = try zli.Command.init(writer, gpa, .{
        .name = "zScript",
        .description = "Yet another programming language",
    }, run);

    try root.addCommands(&.{
        try version_cmd.register(writer, gpa),
        try check_cmd.register(writer, gpa),
    });

    try root.addFlag(ast_dump);
    try root.addFlag(asm_dump);
    try root.addFlag(optimize);
    try root.addPositionalArg(.{
        .name = "source",
        .required = true,
        .description = "Source file to be executed",
    });

    return root;
}

fn showHelp(ctx: zli.CommandContext) !void {
    try ctx.command.printHelp();
}

var debug_gpa: std.heap.DebugAllocator(.{}) = .init;
fn run(ctx: zli.CommandContext) !void {
    const gpa, const is_debug = comptime gpa: {
        break :gpa switch (builtin.mode) {
            .Debug => .{ debug_gpa.allocator(), true },
            else => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        const check = debug_gpa.deinit();
        if (check == .leak) {
            std.log.debug("Leak detected after freeing gpa.", .{});
        }
    };
    var stderr_buf: [1024]u8 = undefined;
    var stderr = std.fs.File.stderr().writer(&stderr_buf);
    var stderr_writer = &stderr.interface;

    const file = std.fs.cwd().openFile(ctx.positional_args[0], .{}) catch |err| {
        try utils.printFileError(stderr_writer, err, ctx.positional_args[0]);
        try stderr_writer.flush();
        std.process.exit(1);
    };

    const contents = file.readToEndAlloc(gpa, 1 << 24) catch |err| {
        try utils.printFileError(stderr_writer, err, ctx.positional_args[0]);
        try stderr_writer.flush();
        std.process.exit(1);
    };
    defer gpa.free(contents);

    var res = try lib.run(ctx.writer, gpa, contents, .{
        .file = ctx.positional_args[0],
        .print_asm = ctx.flag("print-bytecode", bool),
        .print_ast = ctx.flag("print-ast", bool),
        .do_not_optimize = ctx.flag("disable-optimization", bool),
    });
    defer res.deinit(gpa);

    if (res.parse_err.len > 0) {
        var next_err = res.parse_err.pop();
        while (next_err != null) : (next_err = res.parse_err.pop()) {
            try utils.printParseError(gpa, stderr_writer, res.lexer, next_err.?, ctx.positional_args[0]);
        }
    }

    if (res.compile_err != null) {
        try utils.printCompileErr(stderr_writer, res.compile_err.?);
    }
}
