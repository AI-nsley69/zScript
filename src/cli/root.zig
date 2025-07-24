const std = @import("std");
const builtin = @import("builtin");
const lib = @import("../lib.zig");
const zli = @import("zli");
const ansi = @import("ansi_term");

const Flag = zli.Flag;
const format = ansi.format;

const version = @import("version.zig");

pub fn build(allocator: std.mem.Allocator) !*zli.Command {
    const root = try zli.Command.init(allocator, .{
        .name = "zScript",
        .description = "Yet another programming language",
    }, run);
    try root.addFlag(ast_dump);
    try root.addFlag(asm_dump);
    try root.addFlag(optimize);
    try root.addPositionalArg(.{
        .name = "source",
        .required = true,
        .description = "Source file to be executed",
    });

    try root.addCommands(&.{
        try version.register(allocator),
    });

    return root;
}

fn showHelp(ctx: zli.CommandContext) !void {
    try ctx.command.printHelp();
}

const ast_dump: Flag = .{ .name = "print-ast", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Dump AST tree" };
const asm_dump: Flag = .{ .name = "print-bytecode", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Dump asm instructions" };
const optimize: Flag = .{ .name = "disable-optimization", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Disable optimizations" };

const fileErrors = (std.fs.File.ReadError || std.fs.File.OpenError || std.posix.FlockError || std.mem.Allocator.Error);

fn printFileError(out: std.fs.File.Writer, err: fileErrors, file: []const u8) !void {
    try format.updateStyle(out, .{ .font_style = .{ .bold = true }, .foreground = .Red }, null);
    try out.writeAll("Error: ");
    try format.updateStyle(out, .{ .font_style = .{ .bold = true } }, null);
    switch (err) {
        error.AccessDenied => {
            try out.writeAll("Permission denied: ");
        },
        error.FileNotFound => {
            try out.writeAll("File not found: ");
        },
        error.IsDir => {
            try out.writeAll("Source is a directory: ");
        },
        else => {
            try out.print("{any}: ", .{err});
        },
    }
    try format.resetStyle(out);
    try out.writeAll(file);
    try out.writeAll("\n");
    std.process.exit(1);
}

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

fn run(ctx: zli.CommandContext) !void {
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug => .{ debug_allocator.allocator(), true },
            else => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        const check = debug_allocator.deinit();
        if (check == .leak) {
            std.log.debug("Leak detected after freeing allocator.", .{});
        }
    };

    const file = std.fs.cwd().openFile(ctx.positional_args[0], .{}) catch |err| {
        try printFileError(std.io.getStdErr().writer(), err, ctx.positional_args[0]);
        std.process.exit(1);
    };

    const contents = file.readToEndAlloc(gpa, 1 << 24) catch |err| {
        try printFileError(std.io.getStdErr().writer(), err, ctx.positional_args[0]);
        std.process.exit(1);
    };
    defer gpa.free(contents);

    std.log.debug("Source: {s}\n", .{contents});

    const res = try lib.run(gpa, contents, .{
        .file = ctx.positional_args[0],
        .print_asm = ctx.flag("print-bytecode", bool),
        .print_ast = ctx.flag("print-ast", bool),
        .do_not_optimize = ctx.flag("disable-optimization", bool),
    });

    std.log.debug("Return val: {?}\n", .{res});
}
