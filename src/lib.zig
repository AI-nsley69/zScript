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

pub fn parse(gpa: Allocator, out: *Writer, gc: *Gc, tokens: std.MultiArrayList(Lexer.Token), opt: runOpts) !Ast.Program {
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

    return parsed;
}

const CompilerResult = struct {
    data: ?Compiler.CompilerOutput,
    err: ?[]u8 = null,
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
    lexer: Lexer,
    parse_err: []Lexer.Token,
    compile_err: ?[]u8 = null,
    runtime_err: ?[]u8 = null,
    value: ?Value = null,
    // Used for deinit'ing values
    parse_arena: std.heap.ArenaAllocator,

    pub fn deinit(self: Result, gpa: Allocator) void {
        self.parse_arena.deinit();
        gpa.free(self.parse_err);
        if (self.compile_err != null) {
            gpa.free(self.compile_err.?);
        }
    }
};

pub fn run(writer: *Writer, gpa: std.mem.Allocator, src: []const u8, opt: runOpts) !Result {
    // Source -> Tokens
    const tokens, var lexer = try tokenize(gpa, writer, src, opt);
    defer lexer.deinit();

    var gc = try Gc.init(gpa);
    defer gc.deinit(gpa);

    // Tokens -> Ast
    const parsed = try parse(gpa, writer, gc, tokens, opt);
    errdefer parsed.arena.deinit();

    var result: Result = .{
        .lexer = lexer,
        .parse_err = parsed.errors,
        .parse_arena = parsed.arena,
    };
    if (result.parse_err.len > 0) {
        return result;
    }

    // Ast -> Bytecode
    var compiled = try compile(gpa, writer, gc, parsed, opt);
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
