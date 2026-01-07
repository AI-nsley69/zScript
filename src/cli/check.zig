const std = @import("std");
const lib = @import("../lib.zig");
const Gc = @import("../gc.zig");
const utils = @import("../utils.zig");
const zli = @import("zli");

const builtin = @import("builtin");

pub fn register(writer: *std.io.Writer, gpa: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, gpa, .{
        .name = "check",
        // .shortcut = "ast",
        .description = "Verifies the ast",
    }, check);
    try cmd.addPositionalArg(.{
        .name = "source",
        .required = true,
        .description = "Source file to be executed",
    });
    return cmd;
}

var debug_gpa: std.heap.DebugAllocator(.{}) = .init;

fn check(ctx: zli.CommandContext) !void {
    const gpa, const is_debug = comptime gpa: {
        break :gpa switch (builtin.mode) {
            .Debug => .{ debug_gpa.allocator(), true },
            else => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        const has_leak = debug_gpa.deinit();
        if (has_leak == .leak) {
            std.log.debug("Leak detected after freeing gpa.", .{});
        }
    };

    var stderr = std.fs.File.stderr().writer(&.{}).interface;
    const file = std.fs.cwd().openFile(ctx.positional_args[0], .{}) catch |err| {
        try utils.printFileError(&stderr, err, ctx.positional_args[0]);
        std.process.exit(1);
    };

    const contents = file.readToEndAlloc(gpa, 1 << 24) catch |err| {
        try utils.printFileError(&stderr, err, ctx.positional_args[0]);
        std.process.exit(1);
    };
    defer gpa.free(contents);

    var gc = try Gc.init(gpa);
    defer gc.deinit(gpa);

    const tokens, var lexer = try lib.tokenize(gpa, ctx.writer, contents, .{});
    defer lexer.deinit();

    const parsed = try lib.parse(gpa, ctx.writer, gc, tokens, .{ .file = ctx.positional_args[0] });
    defer parsed.data.arena.deinit();
}
