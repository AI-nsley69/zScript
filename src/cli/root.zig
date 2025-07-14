const std = @import("std");
const main = @import("../main.zig");
const zli = @import("zli");
const Flag = zli.Flag;

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

const ast_dump: Flag = .{ .name = "ast", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Dump AST tree" };
const asm_dump: Flag = .{ .name = "asm", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Dump asm instructions" };
const optimize: Flag = .{ .name = "optimize", .shortcut = "O", .type = .Bool, .default_value = .{ .Bool = false }, .description = "Apply optimization [WIP]" };

fn run(ctx: zli.CommandContext) !void {
    // Test files for development

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const file = try std.fs.cwd().openFile(ctx.positional_args[0], .{});

    const contents = try file.readToEndAlloc(allocator, 1 << 24);
    defer allocator.free(contents);

    std.log.debug("Source: {s}", .{contents});

    const res = try main.run(allocator, contents, .{
        .file = ctx.positional_args[0],
        .printAsm = ctx.flag("asm", bool),
        .printAst = ctx.flag("ast", bool),
        .optimize = ctx.flag("optimize", bool),
    });

    std.log.debug("Return val: {?}", .{res});
}
