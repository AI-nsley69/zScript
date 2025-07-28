const std = @import("std");
const Lexer = @import("lexer.zig");
const Ast = @import("ast.zig");
const Parser = @import("parser.zig");
const Optimizer = @import("optimizer.zig");
const Compiler = @import("compiler.zig");
const Gc = @import("gc.zig");
const Vm = @import("vm.zig");
const Debug = @import("debug.zig");
const utils = @import("utils.zig");
const Value = @import("value.zig").Value;

const Allocator = std.mem.Allocator;
const Writer = std.fs.File.Writer;

pub const runOpts = struct {
    file: []const u8 = "",
    print_asm: bool = false,
    print_ast: bool = false,
    print_tokens: bool = false,
    do_not_optimize: bool = false,
};

const TokenizerOutput = struct {
    std.ArrayListUnmanaged(Lexer.Token),
    std.ArrayListUnmanaged(Lexer.TokenInfo),
    Lexer,
};

pub fn tokenize(gpa: Allocator, out: Writer, src: []const u8, opt: runOpts) !TokenizerOutput {
    var lexer = Lexer.init(src, gpa);
    errdefer lexer.deinit();
    const tokens = try lexer.scan();

    if (opt.print_tokens) {
        for (tokens.items) |token| {
            try out.print("{s}, ", .{@tagName(token.tag)});
        }

        try out.writeAll("\n");
    }
    return .{ tokens, lexer.tokenInfo, lexer };
}

pub fn parse(gpa: Allocator, out: Writer, tokens: std.ArrayListUnmanaged(Lexer.Token), token_info: std.ArrayListUnmanaged(Lexer.TokenInfo), opt: runOpts) !Ast.Program {
    var parser = Parser{};
    var parsed = try parser.parse(gpa, tokens);
    errdefer parsed.arena.deinit();

    const parser_errors = parser.errors.items;
    for (parser_errors) |err| {
        const err_writer = std.io.getStdErr().writer();
        const info = token_info.items[err.idx];
        try utils.printParseError(gpa, err_writer, err, info, opt.file, err.span);
    }
    if (parser_errors.len > 0) return error.ParseError;

    if (!opt.do_not_optimize) {
        var optimizer = Optimizer{};
        parsed = try optimizer.optimizeAst(gpa, parsed);
    }

    if (opt.print_ast) {
        var ast = Debug.Ast{ .writer = out, .allocator = gpa };
        ast.print(parsed) catch {};
    }

    return parsed;
}

pub fn compile(gpa: Allocator, out: Writer, gc: *Gc, parsed: Ast.Program, opt: runOpts) !Compiler.CompilerOutput {
    var compiler = Compiler{ .allocator = gpa, .gc = gc, .ast = parsed };
    const compiled = compiler.compile() catch {
        const stderr = std.io.getStdErr().writer();
        try utils.printCompileErr(stderr, compiler.err_msg.?);
        return error.CompileError;
    };
    errdefer compiled.deinit(gpa);

    if (opt.print_asm) {
        Debug.disassemble(compiled, out) catch {};
    }

    return compiled;
}

pub fn run(gpa: std.mem.Allocator, src: []const u8, opt: runOpts) !?Value {
    const out = std.io.getStdOut().writer();
    // Source -> Tokens
    const tokens, const token_info, var lexer = try tokenize(gpa, out, src, opt);
    defer lexer.deinit();

    // Tokens -> Ast
    const parsed = try parse(gpa, out, tokens, token_info, opt);
    defer parsed.arena.deinit();

    var gc = try Gc.init(gpa);
    defer gc.deinit();
    // Ast -> Bytecode
    var compiled = try compile(gpa, out, gc, parsed, opt);
    defer compiled.deinit(gpa);

    // Bytecode execution
    var vm = try Vm.init(gc, compiled);
    defer vm.deinit();
    vm.run() catch |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    };

    return vm.result;
}
