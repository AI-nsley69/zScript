const std = @import("std");
const zs = @import("lib.zig");
const ansi = @import("ansi_term");

const format = ansi.format;
const Style = ansi.style.Style;

const TokenData = zs.Frontend.Lexer.TokenData;
const Token = zs.Frontend.Lexer.Token;
const TokenInfo = zs.Frontend.Lexer.TokenInfo;
const Allocator = std.mem.Allocator;
const Writer = std.io.Writer;

pub const ErrorType = enum {
    ParseError,
    CompileError,
    RuntimeError,
};

pub const InternalError = struct {
    type: ErrorType,
    err_token: Token,
    token: ?Token = null,
    file: []const u8,
};

const boldStyle: Style = .{ .font_style = .{ .bold = true } };
const boldRedStyle: Style = .{ .font_style = .{ .bold = true }, .foreground = .Red };
const greenStyle: Style = .{ .foreground = .Green };

fn printSourcePosition(gpa: Allocator, writer: *Writer, err: InternalError) !void {
    const info = err.err_token.info;

    try format.updateStyle(writer, boldStyle, null);
    const src_msg = try std.fmt.allocPrint(gpa, "{s}:{d}:{d}: ", .{ err.file, info.line, info.pos });
    defer gpa.free(src_msg);
    try writer.writeAll(src_msg);
}

fn printErrorType(writer: *Writer, err: InternalError) !void {
    try format.updateStyle(writer, boldRedStyle, null);
    const msg = switch (err.type) {
        .ParseError => "error: ",
        .CompileError => "error: ",
        .RuntimeError => "runtime error: ",
    };
    try writer.writeAll(msg);
}

fn printTokenData(writer: *Writer, err: InternalError) !void {
    try format.updateStyle(writer, boldStyle, null);
    try writer.writeAll(err.err_token.data.span);
    try writer.writeAll("\n");
    try format.resetStyle(writer);
}

fn printLineSource(gpa: Allocator, writer: *Writer, line_source: []const u8) !void {
    const source_intended = try gpa.alloc(u8, line_source.len + 2);
    defer gpa.free(source_intended);
    @memcpy(source_intended[0..2], "  ");
    @memcpy(source_intended[2..], line_source);
    try writer.writeAll(source_intended);

    if (source_intended[source_intended.len - 1] != '\n') {
        try writer.writeAll("\n");
    }
}

fn printExpressionPointer(gpa: Allocator, writer: *Writer, err: InternalError, line_source: []const u8) !void {
    const info = err.err_token.info;
    // Indent + src + newline
    const ptr_msg = try gpa.alloc(u8, 2 + line_source.len + 1);
    defer gpa.free(ptr_msg);
    @memset(ptr_msg, ' ');

    std.log.debug("TODO: Get proper span of the AST node that errored", .{});
    std.debug.print("Span: {s}, pos: {d}\n", .{ err.token.?.data.span, err.token.?.info.pos });
    var start_pos = info.pos + 1;
    const end_pos = start_pos + 1;
    if (err.token != null) {
        const offset = err.token.?.data.span.len - 1;
        start_pos = start_pos - offset;
    }
    @memset(ptr_msg[start_pos..end_pos], '^');
    ptr_msg[ptr_msg.len - 1] = '\n';

    try format.updateStyle(writer, greenStyle, null);
    try writer.writeAll(ptr_msg);
    try format.resetStyle(writer);
}

pub fn printError(gpa: Allocator, writer: *Writer, lex: zs.Frontend.Lexer, err: InternalError) !void {
    var lexer = lex;

    try printSourcePosition(gpa, writer, err);
    try printErrorType(writer, err);
    try printTokenData(writer, err);

    const line_source = lexer.getLineSource(err.err_token.info);
    try printLineSource(gpa, writer, line_source);
    try printExpressionPointer(gpa, writer, err, line_source);
}

const fileErrors = (std.fs.File.ReadError || std.fs.File.OpenError || std.posix.FlockError || std.mem.Allocator.Error);

pub fn printFileError(out: *Writer, err: fileErrors, file: []const u8) !void {
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
}
