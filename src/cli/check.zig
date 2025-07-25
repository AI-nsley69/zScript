const std = @import("std");
const lib = @import("../lib.zig");
const utils = @import("../utils.zig");
const zli = @import("zli");

const builtin = @import("builtin");

pub fn register(allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(allocator, .{
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

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

fn check(ctx: zli.CommandContext) !void {
    const gpa, const is_debug = comptime gpa: {
        break :gpa switch (builtin.mode) {
            .Debug => .{ debug_allocator.allocator(), true },
            else => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        const has_leak = debug_allocator.deinit();
        if (has_leak == .leak) {
            std.log.debug("Leak detected after freeing allocator.", .{});
        }
    };

    const file = std.fs.cwd().openFile(ctx.positional_args[0], .{}) catch |err| {
        try utils.printFileError(std.io.getStdErr().writer(), err, ctx.positional_args[0]);
        std.process.exit(1);
    };

    const contents = file.readToEndAlloc(gpa, 1 << 24) catch |err| {
        try utils.printFileError(std.io.getStdErr().writer(), err, ctx.positional_args[0]);
        std.process.exit(1);
    };
    defer gpa.free(contents);

    const out = std.io.getStdOut().writer();

    const tokens, const token_info, const arena = try lib.tokenize(gpa, out, contents, .{});
    defer arena.deinit();

    const parsed = try lib.parse(gpa, out, tokens, token_info, .{ .file = ctx.positional_args[0] });
    defer parsed.arena.deinit();
}
