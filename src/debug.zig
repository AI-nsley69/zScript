const std = @import("std");
const Vm = @import("vm.zig");
const types = @import("ast.zig");
const Lexer = @import("lexer.zig");

const TokenType = Lexer.TokenType;

const Stmt = types.Stmt;
const Program = types.Program;
const Expression = types.Expression;
const ExpressionValue = types.ExpressionValue;
const Infix = types.Infix;
const Value = Vm.Value;

fn codeToString(opcode: Vm.OpCodes) []const u8 {
    return switch (opcode) {
        .RET => "ret",
        .HALT => "halt",
        .NOP => "nop",
        .MOV => "mov",
        .LOAD_IMMEDIATE => "li",
        .LOAD_WORD => "lw",
        .STORE_WORD => "sw",
        .ADD => "add",
        .ADD_IMMEDIATE => "addi",
        .SUBTRACT => "sub",
        .SUBTRACT_IMMEDIATE => "subi",
        .MULTIPLY => "mul",
        .MULTIPLY_IMMEDIATE => "muli",
        .DIVIDE => "div",
        .DIVIDE_IMMEDIATE => "divi",
        .JUMP => "jmp",
        .BRANCH_IF_EQUAL => "beq",
        .BRANCH_IF_NOT_EQUAL => "bne",
        .XOR => "xor",
        .AND => "and",
        .NOT => "not",
        .OR => "or",
    };
}

pub const Disassembler = struct {
    const Self = @This();

    ip: u32 = 0,
    instructions: std.ArrayListUnmanaged(u8),

    fn next(self: *Self) u8 {
        std.debug.assert(self.ip < self.instructions.items.len);
        const instruction = self.instructions.items[self.ip];
        self.ip += 1;
        return instruction;
    }

    pub fn has_next(self: *Self) bool {
        return self.ip < self.instructions.items.len;
    }

    pub fn disassembleNextInstruction(self: *Self, writer: std.fs.File.Writer) !void {
        const opcode: Vm.OpCodes = @enumFromInt(self.next());
        const name = codeToString(opcode);

        switch (opcode) {
            // no arg
            .NOP, .HALT => try writer.print("[{x:0>6}] {s}\n", .{ self.ip - 1, name }),
            // 1x reg with imm arg
            .ADD_IMMEDIATE, .SUBTRACT_IMMEDIATE, .MULTIPLY_IMMEDIATE, .DIVIDE_IMMEDIATE => {
                const reg = self.next();
                const imm: u16 = @as(u16, self.next()) << 8 | self.next();
                try writer.print("[{x:0>6}] {s} r{d} #{d}\n", .{ self.ip - 1, name, reg, imm });
            },
            // 1x reg arg
            .JUMP, .RET => {
                try writer.print("[{x:0>6}] {s} r{d}\n", .{ self.ip - 1, name, self.next() });
            },
            .LOAD_IMMEDIATE => {
                try writer.print("[{x:0>6}] {s} r{d} c{d}\n", .{ self.ip - 1, name, self.next(), self.next() });
            },
            // 2x reg arg
            .LOAD_WORD, .STORE_WORD, .MOV => {
                try writer.print("[{x:0>6}] {s} r{d} r{d}\n", .{ self.ip - 1, name, self.next(), self.next() });
            },
            // 3x reg arg
            .ADD, .SUBTRACT, .MULTIPLY, .DIVIDE, .BRANCH_IF_EQUAL, .BRANCH_IF_NOT_EQUAL, .XOR, .AND, .NOT, .OR => {
                try writer.print("[{x:0>6}] {s} r{d} r{d} r{d}\n", .{ self.ip - 1, name, self.next(), self.next(), self.next() });
            },
        }
    }

    pub fn disassemble(self: *Disassembler, writer: std.fs.File.Writer) !void {
        while (self.has_next()) {
            try self.disassembleNextInstruction(writer);
        }
    }
};

pub const Ast = struct {
    const Self = @This();
    writer: std.fs.File.Writer,
    allocator: std.mem.Allocator,
    const indent_step = 2;

    pub fn print(self: *Self, input: Program) !void {
        const indent_msg = try self.allocator.alloc(u8, indent_step);
        defer self.allocator.free(indent_msg);
        @memset(indent_msg, ' ');

        const list = input.stmts.items;
        try self.writer.print("(program)\n", .{});
        for (list) |stmt| {
            try self.writer.print("{s}stmt:\n", .{indent_msg});
            switch (stmt.expr.node) {
                .infix => try self.printExpression(stmt.expr, indent_step * 2),
                .literal => try self.printLiteral(stmt.expr.node.literal, indent_step * 2),
            }
        }
        // self.io.("{any}", .{input});
    }

    fn printExpression(self: *Self, expr: Expression, indent: usize) !void {
        const indent_msg = try self.allocator.alloc(u8, indent);
        defer self.allocator.free(indent_msg);
        @memset(indent_msg, ' ');

        const node = expr.node;
        try self.writer.print("{s}expr:\n", .{indent_msg});
        // switch (node) {
        //     .infix => try self.printExpression(node, indent + indent_step),
        //     .literal => {
        //         try self.printLiteral(node.literal, indent + indent_step);
        //         return;
        //     },
        // }

        const infix = node.infix.*;
        const lhs = infix.lhs;
        switch (lhs.node) {
            .infix => try self.printExpression(lhs, indent + indent_step),
            .literal => try self.printLiteral(lhs.node.literal, indent + indent_step),
        }

        const op = infix.op;
        try self.printOperand(op, indent + indent_step);

        const rhs = infix.rhs;
        switch (rhs.node) {
            .infix => try self.printExpression(rhs, indent + indent_step),
            .literal => try self.printLiteral(rhs.node.literal, indent + indent_step),
        }
    }

    fn printLiteral(self: *Self, value: Value, indent: usize) !void {
        const indent_msg = try self.allocator.alloc(u8, indent);
        defer self.allocator.free(indent_msg);
        @memset(indent_msg, ' ');

        return switch (value) {
            .int => try self.writer.print("{s}lit: {d}\n", .{ indent_msg, value.int }),
            .float => try self.writer.print("{s}lit: {d}\n", .{ indent_msg, value.float }),
            .string => try self.writer.print("{s}lit: {s}\n", .{ indent_msg, value.string }),
            .boolean => try self.writer.print("{s}lit: {any}\n", .{ indent_msg, value.boolean }),
        };
    }

    fn printOperand(self: *Self, op: TokenType, indent: usize) !void {
        const indent_msg = try self.allocator.alloc(u8, indent);
        defer self.allocator.free(indent_msg);
        @memset(indent_msg, ' ');

        try self.writer.print("{s}op: {s}\n", .{ indent_msg, @tagName(op) });
    }
};
