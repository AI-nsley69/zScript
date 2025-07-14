const std = @import("std");
const Lexer = @import("lexer.zig");
const ansi = @import("ansi_term");
const format = ansi.format;

const TokenInfo = Lexer.TokenInfo;
const Allocator = std.mem.Allocator;
const Writer = std.fs.File.Writer;

pub fn printErr(allocator: Allocator, writer: Writer, tokenInfo: TokenInfo, src_file: []const u8, msg: []const u8) !void {
    // Print source file with line and position
    try format.updateStyle(writer, .{ .font_style = .{ .bold = true } }, null);
    const src_msg = try std.fmt.allocPrint(allocator, "{s}:{d}:{d}: ", .{ src_file, tokenInfo.line, tokenInfo.pos });
    defer allocator.free(src_msg);
    try writer.writeAll(src_msg);
    // Print the "error" label
    try format.updateStyle(writer, .{ .font_style = .{ .bold = true }, .foreground = .Red }, null);
    try writer.writeAll("error: ");
    // Print the message itself
    try format.updateStyle(writer, .{ .font_style = .{ .bold = true } }, null);
    try writer.writeAll(msg);
    try writer.writeAll("\n");
    try format.resetStyle(writer);
    // Print the source line indented
    const source_aligned = try std.fmt.allocPrint(allocator, "  {s}\n", .{tokenInfo.line_source});
    defer allocator.free(source_aligned);
    try writer.writeAll(source_aligned);
    // Print a pointer to where the error occured
    const ptr_msg = try allocator.alloc(u8, 2 + tokenInfo.line_source.len + 1);
    defer allocator.free(ptr_msg);
    @memset(ptr_msg, ' ');
    ptr_msg[tokenInfo.pos + 1] = '^';
    ptr_msg[ptr_msg.len - 1] = '\n';
    try format.updateStyle(writer, .{ .foreground = .Green }, null);
    try writer.writeAll(ptr_msg);
    try format.resetStyle(writer);
}
