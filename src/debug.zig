const std = @import("std");
const Bytecode = @import("bytecode.zig");
const Vm = @import("vm.zig");
const Compiler = @import("compiler.zig");
const types = @import("ast.zig");
const Lexer = @import("lexer.zig");
const Val = @import("value.zig");
const Gc = @import("gc.zig");

const TokenType = Lexer.TokenType;

const Value = Val.Value;

const Writer = std.io.Writer;

const CompilerOutput = Compiler.CompilerOutput;

const Statement = types.Statement;
const Program = types.Program;
const Expression = types.Expression;
const ExpressionValue = types.ExpressionValue;
const Infix = types.Infix;
const Unary = types.Unary;
const Variable = types.Variable;

fn codeToString(opcode: Bytecode.OpCodes) []const u8 {
    return switch (opcode) {
        .@"return" => "RETURN",
        .halt => "HALT",
        .noop => "NOOP",
        .copy => "COPY",
        .load_bool => "LOAD_BOOL",
        .load_float => "LOAD_FLOAT",
        .load_int => "LOAD_INT",
        .load_const => "LOAD_CONST",
        .object_field_id => "OBJ_FIELD_ID",
        .object_method_id => "OBJ_METHOD_ID",
        .object_get => "OBJ_GET",
        .object_set => "OBJ_SET",
        .load_param => "LOAD_PARAM",
        .store_param => "STORE_PARAM",
        .call => "CALL",
        .method_call => "METHOD_CALL",
        .native_call => "NATIVE_CALL",
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

fn valueToString(gpa: std.mem.Allocator, value: Value) ![]u8 {
    return switch (value) {
        .int => std.fmt.allocPrint(gpa, "(int){d}", .{value.int}),
        .float => std.fmt.allocPrint(gpa, "(float){d}", .{value.float}),
        .boolean => std.fmt.allocPrint(gpa, "(bool){any}", .{value.boolean}),
    };
}

pub fn disassembleNextInstruction(writer: *Writer, reader: *std.io.Reader) !void {
    const pos = reader.seek;
    const opcode: Bytecode.OpCodes = @enumFromInt(try reader.takeByte());
    const name = codeToString(opcode);

    switch (opcode) {
        // no arg
        .noop, .halt => try writer.print("  [{x:0>6}] {s}\n", .{ pos, name }),
        // 1x reg with imm arg
        .jump_eql, .jump_neq => {
            const reg = try reader.takeByte();
            const imm: u16 = try reader.takeInt(u16, .big);
            try writer.print("  [{x:0>6}] {s} ${d} #{x}\n", .{ pos, name, reg, imm });
        },
        // imm arg
        .jump => {
            const imm: u16 = try reader.takeInt(u16, .big);
            try writer.print("  [{x:0>6}] {s} #{x}\n", .{ pos, name, imm });
        },
        // 1x reg arg
        .@"return", .load_param, .store_param, .call, .native_call => {
            try writer.print("  [{x:0>6}] {s} ${d}\n", .{ pos, name, try reader.takeByte() });
        },
        .load_bool => {
            const dst = try reader.takeByte();
            const val = try reader.takeByte() == 1;
            try writer.print("  [{x:0>6}] {s} ${d} {}\n", .{ pos, name, dst, val });
        },
        .load_float => {
            const dst = try reader.takeByte();
            const val = try reader.takeInt(u64, .big);
            try writer.print("  [{x:0>6}] {s} ${d} {d}\n", .{ pos, name, dst, @as(f64, @bitCast(val)) });
        },
        .load_int => {
            const dst = try reader.takeByte();
            const val = try reader.takeInt(u64, .big);
            try writer.print("  [{x:0>6}] {s} ${d} {d}\n", .{ pos, name, dst, @as(i64, @bitCast(val)) });
        },
        // 2x reg arg
        .copy, .load_const, .method_call => {
            try writer.print("  [{x:0>6}] {s} ${d} ${d}\n", .{ pos, name, try reader.takeByte(), try reader.takeByte() });
        },
        // 3x reg arg
        .add, .sub, .mult, .divide, .xor, .@"and", .not, .@"or", .eql, .neq, .less_than, .lte, .greater_than, .gte, .object_get, .object_set, .object_field_id, .object_method_id => {
            try writer.print("  [{x:0>6}] {s} ${d} ${d} ${d}\n", .{ pos, name, try reader.takeByte(), try reader.takeByte(), try reader.takeByte() });
        },
    }
}

pub fn disassemble(output: CompilerOutput, writer: *Writer) !void {
    for (output.frames) |frame| {
        var instructions = std.io.Reader.fixed(frame.body);
        try writer.print("{s}:\n", .{frame.name});
        while (true) {
            disassembleNextInstruction(writer, &instructions) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
        }
    }
}

fn createIndent(gpa: std.mem.Allocator, indent_step: u64) ![]u8 {
    const indent_msg = try gpa.alloc(u8, indent_step);
    errdefer gpa.free(indent_msg);
    @memset(indent_msg, ' ');
    return indent_msg;
}

const Errors = (std.mem.Allocator.Error || std.io.Writer.Error || Val.ConvertError || Gc.Error);

pub const Ast = struct {
    const Self = @This();
    writer: *std.io.Writer,
    gpa: std.mem.Allocator,
    gc: *Gc = undefined,
    const indent_step = 2;

    pub fn print(self: *Self, input: Program) !void {
        const gc = try Gc.init(self.gpa);
        self.gc = gc;
        defer gc.deinit(self.gpa);

        const indent_msg = try createIndent(self.gpa, indent_step);
        defer self.gpa.free(indent_msg);

        const list = input.statements.items;
        try self.writer.print("(program)\n", .{});
        for (list) |stmt| {
            try self.printStatement(stmt, indent_step);
        }
    }

    fn printStatement(self: *Self, stmt: Statement, indent: u64) !void {
        const indent_msg = try createIndent(self.gpa, indent);
        defer self.gpa.free(indent_msg);
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
            .loop => {
                const loop = node.loop.*;
                try self.writer.print("{s}loop:\n", .{indent_msg});
                if (loop.initializer != null) try self.printExpressionHelper(loop.initializer.?, indent + indent_step);
                try self.printExpressionHelper(loop.condition, indent + indent_step);
                if (loop.post != null) try self.printExpressionHelper(loop.post.?, indent + indent_step);
                try self.printStatement(loop.body, indent + indent_step);
            },
            .function => {
                try self.writer.print("{s}fn:\n", .{indent_msg});
                try self.writer.print("  {s}name: {s}\n", .{ indent_msg, node.function.*.name });
                try self.printStatement(node.function.*.body, indent + indent_step);
            },
            .@"return" => {
                const val = node.@"return".value;
                try self.writer.print("{s}return:\n", .{indent_msg});
                if (val != null) try self.printExpressionHelper(val.?, indent + indent_step);
            },
            else => unreachable,
        }
    }

    fn printExpressionHelper(self: *Self, expr: Expression, indent: u64) Errors!void {
        const node = expr.node;
        return switch (node) {
            .infix => try self.printInfix(node.infix, indent),
            .literal => try self.printLiteral(node.literal, indent),
            .unary => try self.printUnary(node.unary, indent),
            .variable => try self.printVariable(node.variable, indent),
            // TODO: Implement AST dump for call
            .call, .native_call, .new_object, .field_access, .method_call => {
                std.log.debug("Implement AST Dump for call, native call, new object, property access, method call", .{});
            },
        };
    }

    fn printInfix(self: *Self, infix: *Infix, indent: u64) !void {
        const indent_msg = try createIndent(self.gpa, indent);
        defer self.gpa.free(indent_msg);
        try self.writer.print("{s}infix:\n", .{indent_msg});

        const lhs = infix.lhs;
        try self.printExpressionHelper(lhs, indent + indent_step);

        const op = infix.op;
        try self.printOperand(op, indent + indent_step);

        const rhs = infix.rhs;
        try self.printExpressionHelper(rhs, indent + indent_step);
    }

    fn printUnary(self: *Self, unary: *Unary, indent: u64) !void {
        const indent_msg = try createIndent(self.gpa, indent);
        defer self.gpa.free(indent_msg);
        try self.writer.print("{s}unary:\n", .{indent_msg});

        const op = unary.op;
        try self.printOperand(op, indent + indent_step);

        const rhs = unary.rhs;
        try self.printExpressionHelper(rhs, indent + indent_step);
    }

    fn printLiteral(self: *Self, value: Value, indent: u64) !void {
        const indent_msg = try createIndent(self.gpa, indent);
        defer self.gpa.free(indent_msg);

        return switch (value) {
            .int => try self.writer.print("{s}lit: {d}\n", .{ indent_msg, value.int }),
            .float => try self.writer.print("{s}lit: {d}\n", .{ indent_msg, value.float }),
            .boolean => try self.writer.print("{s}lit: {any}\n", .{ indent_msg, value.boolean }),
            .boxed => {
                switch (value.boxed.kind) {
                    .string => try self.writer.print("{s}boxed: {s}\n", .{ indent_msg, try Value.asString(value, self.gc) }),
                    else => {
                        std.log.debug("Not implemented objs yet", .{});
                        unreachable;
                    },
                }
            },
        };
    }

    fn printVariable(self: *Self, variable: *Variable, indent: u64) !void {
        var indent_msg = try createIndent(self.gpa, indent);
        defer self.gpa.free(indent_msg);

        try self.writer.print("{s}var:\n", .{indent_msg});

        indent_msg = try createIndent(self.gpa, indent + indent_step);
        try self.writer.print("{s}name: {s}\n", .{ indent_msg, variable.name });

        if (variable.initializer) |init| {
            try self.writer.print("{s}init:\n", .{indent_msg});
            try self.printExpressionHelper(init, indent + indent_step * 2);
        }
    }

    fn printOperand(self: *Self, op: TokenType, indent: u64) !void {
        const indent_msg = try self.gpa.alloc(u8, indent);
        defer self.gpa.free(indent_msg);
        @memset(indent_msg, ' ');

        try self.writer.print("{s}op: {s}\n", .{ indent_msg, @tagName(op) });
    }
};
