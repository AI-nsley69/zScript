const std = @import("std");
const Vm = @import("vm.zig");
const Compiler = @import("compiler.zig");
const types = @import("ast.zig");
const Lexer = @import("lexer.zig");
const Value = @import("value.zig").Value;

const TokenType = Lexer.TokenType;

const CompilerOutput = Compiler.CompilerOutput;

const Statement = types.Statement;
const Program = types.Program;
const Expression = types.Expression;
const ExpressionValue = types.ExpressionValue;
const Infix = types.Infix;
const Unary = types.Unary;
const Variable = types.Variable;

fn codeToString(opcode: Vm.OpCodes) []const u8 {
    return switch (opcode) {
        .@"return" => "RETURN",
        .halt => "HALT",
        .noop => "NOOP",
        .copy => "COPY",
        .load_bool => "LOAD_BOOL",
        .load_float => "LOAD_FLOAT",
        .load_int => "LOAD_INT",
        .add => "ADD",
        .sub => "SUBTRACT",
        .mult => "MULT",
        .divide => "DIV",
        .jump => "JUMP",
        .jump_eql => "JUMP_EQL",
        .jump_neq => "JUMP_NEQ",
        .eql => "EQL",
        .neq => "NEQ",
        .less_than => "LT",
        .lte => "LTE",
        .greater_than => "GT",
        .gte => "GTE",
        .xor => "XOR",
        .@"and" => "AND",
        .not => "NOT",
        .@"or" => "OR",
    };
}

fn valueToString(allocator: std.mem.Allocator, value: Value) ![]u8 {
    return switch (value) {
        .int => std.fmt.allocPrint(allocator, "(int){d}", .{value.int}),
        .float => std.fmt.allocPrint(allocator, "(float){d}", .{value.float}),
        .boolean => std.fmt.allocPrint(allocator, "(bool){any}", .{value.boolean}),
    };
}

fn disassembleNextInstruction(writer: std.fs.File.Writer, instructions: *std.io.FixedBufferStream([]u8)) !void {
    const pos = try instructions.getPos();
    const in = instructions.reader();
    const opcode: Vm.OpCodes = @enumFromInt(try in.readByte());
    const name = codeToString(opcode);

    switch (opcode) {
        // no arg
        .noop, .halt => try writer.print("[{x:0>6}] {s}\n", .{ pos, name }),
        // 1x reg with imm arg
        .jump_eql, .jump_neq => {
            const reg = try in.readByte();
            const imm: u16 = try in.readInt(u16, .big);
            try writer.print("[{x:0>6}] {s} ${d} #{x}\n", .{ pos, name, reg, imm });
        },
        // imm arg
        .jump => {
            const imm: u16 = try in.readInt(u16, .big);
            try writer.print("[{x:0>6}] {s} #{x}\n", .{ pos, name, imm });
        },
        // 1x reg arg
        .@"return" => {
            try writer.print("[{x:0>6}] {s} ${d}\n", .{ pos, name, try in.readByte() });
        },
        .load_bool => {
            const dst = try in.readByte();
            const val = try in.readByte() == 1;
            try writer.print("[{x:0>6}] {s} ${d} {}\n", .{ pos, name, dst, val });
        },
        .load_float => {
            const dst = try in.readByte();
            const val = try in.readInt(u64, .big);
            try writer.print("[{x:0>6}] {s} ${d} {d}\n", .{ pos, name, dst, @as(f64, @bitCast(val)) });
        },
        .load_int => {
            const dst = try in.readByte();
            const val = try in.readInt(u64, .big);
            try writer.print("[{x:0>6}] {s} ${d} {d}\n", .{ pos, name, dst, @as(i64, @bitCast(val)) });
        },
        // 2x reg arg
        .copy => {
            try writer.print("[{x:0>6}] {s} ${d} ${d}\n", .{ pos, name, try in.readByte(), try in.readByte() });
        },
        // 3x reg arg
        .add, .sub, .mult, .divide, .xor, .@"and", .not, .@"or", .eql, .neq, .less_than, .lte, .greater_than, .gte => {
            try writer.print("[{x:0>6}] {s} ${d} ${d} ${d}\n", .{ pos, name, try in.readByte(), try in.readByte(), try in.readByte() });
        },
    }
}

pub fn disassemble(output: CompilerOutput, writer: std.fs.File.Writer) !void {
    var instructions = std.io.fixedBufferStream(output.instructions);
    while (true) {
        disassembleNextInstruction(writer, &instructions) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
    }
}

fn createIndent(allocator: std.mem.Allocator, indent_step: usize) ![]u8 {
    const indent_msg = try allocator.alloc(u8, indent_step);
    errdefer allocator.free(indent_msg);
    @memset(indent_msg, ' ');
    return indent_msg;
}

const Errors = (std.mem.Allocator.Error || std.fs.File.WriteError);

pub const Ast = struct {
    const Self = @This();
    writer: std.fs.File.Writer,
    allocator: std.mem.Allocator,
    const indent_step = 2;

    pub fn print(self: *Self, input: Program) !void {
        const indent_msg = try createIndent(self.allocator, indent_step);
        defer self.allocator.free(indent_msg);

        const list = input.statements.items;
        try self.writer.print("(program)\n", .{});
        for (list) |stmt| {
            try self.printStatement(stmt, indent_step);
        }
    }

    fn printStatement(self: *Self, stmt: Statement, indent: usize) !void {
        const indent_msg = try createIndent(self.allocator, indent);
        defer self.allocator.free(indent_msg);
        const node = stmt.node;
        switch (node) {
            .expression => {
                try self.writer.print("{s}expression:\n", .{indent_msg});
                try self.printExpressionHelper(node.expression, indent + indent_step);
            },
            .conditional => {
                const conditional = node.conditional.*;
                try self.writer.print("{s}conditional:\n", .{indent_msg});
                try self.printExpressionHelper(conditional.expression, indent + indent_step);
                try self.printStatement(conditional.body, indent + indent_step);
                if (conditional.otherwise != null) try self.printStatement(conditional.otherwise.?, indent + indent_step);
            },
            .block => {
                try self.writer.print("{s}block:\n", .{indent_msg});
                for (node.block.statements) |block_stmt| {
                    try self.printStatement(block_stmt, indent + indent_step);
                }
            },
            else => return,
        }
    }

    fn printExpressionHelper(self: *Self, expr: Expression, indent: usize) Errors!void {
        const node = expr.node;
        return switch (node) {
            .infix => try self.printInfix(node.infix, indent),
            .literal => try self.printLiteral(node.literal, indent),
            .unary => try self.printUnary(node.unary, indent),
            .variable => try self.printVariable(node.variable, indent),
        };
    }

    fn printInfix(self: *Self, infix: *Infix, indent: usize) !void {
        const indent_msg = try createIndent(self.allocator, indent);
        defer self.allocator.free(indent_msg);
        try self.writer.print("{s}infix:\n", .{indent_msg});

        const lhs = infix.lhs;
        try self.printExpressionHelper(lhs, indent + indent_step);

        const op = infix.op;
        try self.printOperand(op, indent + indent_step);

        const rhs = infix.rhs;
        try self.printExpressionHelper(rhs, indent + indent_step);
    }

    fn printUnary(self: *Self, unary: *Unary, indent: usize) !void {
        const indent_msg = try createIndent(self.allocator, indent);
        defer self.allocator.free(indent_msg);
        try self.writer.print("{s}unary:\n", .{indent_msg});

        const op = unary.op;
        try self.printOperand(op, indent + indent_step);

        const rhs = unary.rhs;
        try self.printExpressionHelper(rhs, indent + indent_step);
    }

    fn printLiteral(self: *Self, value: Value, indent: usize) !void {
        const indent_msg = try createIndent(self.allocator, indent);
        defer self.allocator.free(indent_msg);

        return switch (value) {
            .int => try self.writer.print("{s}lit: {d}\n", .{ indent_msg, value.int }),
            .float => try self.writer.print("{s}lit: {d}\n", .{ indent_msg, value.float }),
            .boolean => try self.writer.print("{s}lit: {any}\n", .{ indent_msg, value.boolean }),
        };
    }

    fn printVariable(self: *Self, variable: *Variable, indent: usize) !void {
        var indent_msg = try createIndent(self.allocator, indent);
        defer self.allocator.free(indent_msg);

        try self.writer.print("{s}var:\n", .{indent_msg});

        indent_msg = try createIndent(self.allocator, indent + indent_step);
        try self.writer.print("{s}name: {s}\n", .{ indent_msg, variable.name });

        if (variable.initializer) |init| {
            try self.writer.print("{s}init:\n", .{indent_msg});
            try self.printExpressionHelper(init, indent + indent_step * 2);
        }
    }

    fn printOperand(self: *Self, op: TokenType, indent: usize) !void {
        const indent_msg = try self.allocator.alloc(u8, indent);
        defer self.allocator.free(indent_msg);
        @memset(indent_msg, ' ');

        try self.writer.print("{s}op: {s}\n", .{ indent_msg, @tagName(op) });
    }
};
