const std = @import("std");
const zli = @import("zli");

const build_zig_zon = @import("build.zig.zon");

pub fn register(allocator: std.mem.Allocator) !*zli.Command {
    return zli.Command.init(allocator, .{
        .name = "version",
        .shortcut = "v",
        .description = "Show CLI version",
    }, show);
}

fn show(ctx: zli.CommandContext) !void {
    _ = ctx;
    std.debug.print("{s}\n", .{version() orelse "(unknown version)"});
}

// https://renerocks.ai/blog/2025-04-27--version-in-zig/
fn version() ?[]const u8 {
    var it = std.mem.splitScalar(u8, build_zig_zon.contents, '\n');
    while (it.next()) |line_untrimmed| {
        const line = std.mem.trim(u8, line_untrimmed, " \t\n\r");
        if (std.mem.startsWith(u8, line, ".version")) {
            var tokenizer = std.mem.tokenizeAny(u8, line[".version".len..], " \"=");
            return tokenizer.next();
        }
    }
    return null;
}
