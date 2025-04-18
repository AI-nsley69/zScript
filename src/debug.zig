const std = @import("std");
const runtime = @import("runtime.zig");

fn codeToString(opcode: runtime.OpCodes) []const u8 {
    return switch (opcode) {
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
    ip: u32 = 0,
    instructions: std.ArrayListUnmanaged(u8),

    const Self = @This();

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
        const opcode: runtime.OpCodes = @enumFromInt(self.next());
        const name = codeToString(opcode);

        switch (opcode) {
            // no arg
            .HALT, .NOP => try writer.print("[{x:0>6}] {s}\n", .{ self.ip - 1, name }),
            // 1x reg with imm arg
            .ADD_IMMEDIATE, .SUBTRACT_IMMEDIATE, .MULTIPLY_IMMEDIATE, .DIVIDE_IMMEDIATE => {
                const reg = self.next();
                const imm: u16 = @as(u16, self.next()) << 8 | self.next();
                try writer.print("[{x:0>6}] {s} r{d} #{d}\n", .{ self.ip - 1, name, reg, imm });
            },
            // 1x reg arg
            .JUMP => {
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
};
