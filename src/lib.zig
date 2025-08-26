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
const Writer = std.io.Writer;

const log = std.log.scoped(.lib);

pub const runOpts = struct {
    file: []const u8 = "",
    print_asm: bool = false,
    print_ast: bool = false,
    print_tokens: bool = false,
    do_not_optimize: bool = true,
};

const TokenizerOutput = struct {
    std.MultiArrayList(Lexer.Token),
    Lexer,
};

pub fn tokenize(gpa: Allocator, out: *Writer, src: []const u8, opt: runOpts) !TokenizerOutput {
    var lexer = Lexer.init(src, gpa);
    errdefer lexer.deinit();
    const tokens = try lexer.scan();

    if (opt.print_tokens) {
        for (tokens.items(.data)) |token| {
            try out.print("{s}, ", .{@tagName(token.tag)});
        }

        try out.writeAll("\n");
    }
    return .{ tokens, lexer };
}

pub fn parse(gpa: Allocator, out: *Writer, lexer: Lexer, tokens: std.MultiArrayList(Lexer.Token), opt: runOpts) !Ast.Program {
    var parser = Parser{};
    var parsed = try parser.parse(gpa, tokens);
    errdefer parsed.arena.deinit();

    var had_err: bool = false;
    var next_error = parser.errors.pop();
    while (next_error != null) : (next_error = parser.errors.pop()) {
        had_err = true;
        var err_writer = std.fs.File.stderr().writer(&.{}).interface;
        try utils.printParseError(gpa, &err_writer, lexer, next_error.?, opt.file);
    }
    if (had_err) return error.ParseError;

    if (!opt.do_not_optimize) {
        var optimizer = Optimizer{};
        parsed = try optimizer.optimizeAst(gpa, parsed);
    }

    if (opt.print_ast) {
        var ast = Debug.Ast{ .writer = out, .gpa = gpa };
        ast.print(parsed) catch {};
    }

    return parsed;
}

pub fn compile(gpa: Allocator, out: *Writer, gc: *Gc, parsed: Ast.Program, opt: runOpts) !Compiler.CompilerOutput {
    var compiler = Compiler{ .gpa = gpa, .gc = gc, .ast = parsed };
    const compiled = compiler.compile() catch |err| {
        var stderr = std.fs.File.stderr().writer(&.{}).interface;
        try utils.printCompileErr(&stderr, compiler.err_msg.?);
        gpa.free(compiler.err_msg.?); // Free the message after writing it
        return err;
    };
    errdefer compiled.deinit(gpa);

    if (opt.print_asm) {
        Debug.disassemble(compiled, out) catch {};
    }

    return compiled;
}

pub fn run(gpa: std.mem.Allocator, src: []const u8, opt: runOpts) !?Value {
    var out = std.fs.File.stdout().writer(&.{}).interface;
    // Source -> Tokens
    const tokens, var lexer = try tokenize(gpa, &out, src, opt);
    defer lexer.deinit();

    // Tokens -> Ast
    const parsed = try parse(gpa, &out, lexer, tokens, opt);
    defer parsed.arena.deinit();

    var gc = try Gc.init(gpa);
    defer gc.deinit();
    // Ast -> Bytecode
    var compiled = try compile(gpa, &out, gc, parsed, opt);
    defer compiled.deinit(gpa);

    // Bytecode execution
    var vm = try Vm.init(gc, compiled);
    defer vm.deinit();
    vm.run() catch |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    };

    log.debug("VM result: {any}", .{vm.result});

    return vm.result;
}
