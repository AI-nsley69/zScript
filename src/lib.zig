const std = @import("std");
pub const Frontend = @import("frontend/frontend.zig");
pub const Backend = @import("backend/backend.zig");
pub const Runtime = @import("runtime/runtime.zig");
pub const Debug = @import("debug.zig");
const utils = @import("utils.zig");

const Lexer = Frontend.Lexer;
const Ast = Frontend.Ast;
const Parser = Frontend.Parser;
const Optimizer = Frontend.Optimizer;

const Compiler = Backend.Compiler;

const Gc = Runtime.Gc;
const Vm = Runtime.Vm;
const Value = Runtime.Value.Value;

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

const TokenizerResult = struct {
    std.MultiArrayList(Lexer.Token),
    Lexer,
};

pub fn tokenize(gpa: Allocator, out: *Writer, src: []const u8, opt: runOpts) !TokenizerResult {
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

const ParseResult = struct {
    data: Ast.Program,
    err: std.MultiArrayList(Lexer.Token),
};

pub fn parse(gpa: Allocator, out: *Writer, gc: *Gc, tokens: std.MultiArrayList(Lexer.Token), opt: runOpts) !ParseResult {
    var parser = Parser{};
    var parsed = try parser.parse(gpa, gc, tokens);
    errdefer parsed.arena.deinit();

    if (!opt.do_not_optimize) {
        var optimizer = Optimizer{};
        parsed = try optimizer.optimizeAst(gpa, parsed);
    }

    if (opt.print_ast) {
        var ast = Debug.Ast{ .writer = out, .gpa = gpa };
        ast.print(parsed) catch {};
    }

    return .{ .data = parsed, .err = parser.errors };
}

const CompilerResult = struct {
    data: ?Compiler.CompilerOutput,
    err: ?[]u8,
};

pub fn compile(gpa: Allocator, out: *Writer, gc: *Gc, parsed: Ast.Program, opt: runOpts) !CompilerResult {
    var compiler = Compiler{ .gpa = gpa, .gc = gc, .ast = parsed };
    const compiled = compiler.compile() catch {
        return .{ .data = null, .err = compiler.err_msg };
    };
    errdefer compiled.deinit(gpa);

    if (opt.print_asm) {
        Debug.disassemble(compiled, out) catch {};
    }

    return .{ .data = compiled, .err = null };
}

pub const Result = struct {
    parse_err: std.MultiArrayList(Lexer.Token),
    lexer: Lexer,
    compile_err: ?[]u8 = null,
    runtime_err: ?[]u8 = null,
    value: ?Value = null,

    pub fn deinit(self: Result, gpa: Allocator) void {
        if (self.compile_err != null) {
            gpa.free(self.compile_err.?);
        }
    }
};

pub fn run(writer: *Writer, gpa: std.mem.Allocator, src: []const u8, opt: runOpts) !Result {
    var result: Result = undefined;
    // Source -> Tokens
    const tokens, var lexer = try tokenize(gpa, writer, src, opt);
    result.lexer = lexer;
    defer lexer.deinit();
    result.tokenize = .{ tokens, lexer };

    var gc = try Gc.init(gpa);
    defer gc.deinit(gpa);

    // Tokens -> Ast
    const parsed = try parse(gpa, writer, gc, tokens, opt);
    defer parsed.data.arena.deinit();
    result.parse_err = parsed.err;
    if (parsed.err.len > 0) {
        return result;
    }

    // Ast -> Bytecode
    var compiled = try compile(gpa, writer, gc, parsed.data, opt);
    defer if (compiled.data != null) compiled.data.?.deinit(gpa);
    result.compile_err = compiled.err;
    if (compiled.err != null) {
        return result;
    }

    // Bytecode execution
    var vm = try Vm.init(gc, compiled.data.?);
    gc.vm = vm; // Set the vm struct for collection
    defer vm.deinit();
    vm.run() catch |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    };

    log.debug("VM result: {any}", .{vm.result});
    result.value = vm.result;
    return result;
}
