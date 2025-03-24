const std = @import("std");
const debug = @import("debug.zig");

pub const OpCodes = enum(u8) {
    HALT,
    NOP,
    MOV,
    LOAD_IMMEDIATE,
    LOAD_WORD,
    STORE_WORD,
    ADD,
    ADD_IMMEDIATE,
    SUBTRACT,
    SUBTRACT_IMMEDIATE,
    MULTIPLY,
    MULTIPLY_IMMEDIATE,
    DIVIDE,
    DIVIDE_IMMEDIATE,
    JUMP,
    BRANCH_IF_EQUAL,
    BRANCH_IF_NOT_EQUAL,
    XOR,
    AND,
    NOT,
    OR,
};

pub const InterpretResult = enum { OK, COMPILE_ERR, RUNTIME_ERR, HALT };

pub const Value = u64;

pub const Assembler = struct {
    allocator: std.mem.Allocator,
    instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    // reg_idx: u8 = 0,
    const Self = @This();

    pub fn createRaw(self: *Self, opcode: OpCodes, arg0: u8, arg1: u8, arg2: u8) !void {
        try self.instructions.appendSlice(self.allocator, &[_]u8{ @intFromEnum(opcode), arg0, arg1, arg2 });
    }

    pub fn createNoArg(self: *Self, opcode: OpCodes) !void {
        try self.createRaw(opcode, 0x00, 0x00, 0x00);
    }

    pub fn createSingleRegImm(self: *Self, opcode: OpCodes, arg0: u8, arg1: u16) !void {
        const imm_upper: u8 = @intCast(arg1 >> 8);
        const imm_lower: u8 = @intCast(arg1);
        try self.createRaw(opcode, arg0, imm_upper, imm_lower);
    }

    pub fn createSingleReg(self: *Self, opcode: OpCodes, arg0: u8) !void {
        try self.createRaw(opcode, opcode, arg0, 0x00, 0x00);
    }

    pub fn createDoubleReg(self: *Self, opcode: OpCodes, arg0: u8, arg1: u8) !void {
        try self.createRaw(opcode, arg0, arg1, 0x00);
    }
};

pub const Interpreter = struct {
    trace: bool = true,
    instruction_pointer: u64 = 0,
    instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    constants: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
    registers: [256]Value = undefined,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        self.instructions.deinit(alloc);
        self.constants.deinit(alloc);
    }

    pub fn has_next(self: *Self) bool {
        return self.instruction_pointer < self.instructions.items.len;
    }

    fn advance(self: *Self) []u8 {
        std.debug.assert(self.instruction_pointer < self.instructions.items.len);
        const instruction = self.instructions.items[self.instruction_pointer .. self.instruction_pointer + 4];
        self.instruction_pointer += 4;
        return instruction;
    }

    fn getRegister(self: *Self, index: u8) Value {
        return self.registers[index];
    }

    fn setRegister(self: *Self, index: u8, value: Value) void {
        self.registers[index] = value;
    }

    pub fn run(self: *Self) InterpretResult {
        if (!self.has_next()) return .HALT;

        const instruction: []const u8 = self.advance();
        // if (self.trace) {
        //     std.debug.print("{s}\n", .{debug.dissambleInstruction(alloc, &instruction, self.instruction_pointer - 4)});
        // }
        const op_code: OpCodes = @enumFromInt(instruction[0]);
        const arg0 = instruction[1];
        const arg1 = instruction[2];
        const arg2 = instruction[3];

        return switch (op_code) {
            .MOV => {
                self.setRegister(arg0, self.getRegister(arg1));
                return .OK;
            },
            .ADD => {
                const res: Value = self.getRegister(arg1) + self.getRegister(arg2);
                self.setRegister(arg0, res);
                return .OK;
            },
            .ADD_IMMEDIATE => {
                const imm: u16 = @as(u16, arg1) << 8 | arg2;
                const res: Value = self.getRegister(arg0) + @as(Value, imm);
                self.setRegister(arg0, res);
                return .OK;
            },
            .SUBTRACT => {
                const res: Value = self.getRegister(arg1) - self.getRegister(arg2);
                self.setRegister(arg0, res);
                return .OK;
            },
            .MULTIPLY => {
                const res: Value = self.getRegister(arg1) * self.getRegister(arg2);
                self.setRegister(arg0, res);
                return .OK;
            },
            .DIVIDE => {
                const lhs = self.getRegister(arg1);
                const rhs = self.getRegister(arg2);
                if (rhs == 0) return .RUNTIME_ERR;
                const res: Value = lhs / rhs;
                self.setRegister(arg0, res);
                return .OK;
            },
            .LOAD_IMMEDIATE => {
                const imm: u16 = @as(u16, arg1) << 8 | arg2;
                self.setRegister(arg0, imm);
                return .OK;
            },
            .BRANCH_IF_NOT_EQUAL => {
                const isNotEql: bool = self.getRegister(arg1) != self.getRegister(arg2);
                if (!isNotEql) return .OK;
                self.instruction_pointer = self.getRegister(arg0);
                return .OK;
            },
            .HALT => .HALT,
            else => .COMPILE_ERR,
        };
    }

    // pub fn dump(self: *Self, alloc: *std.mem.Allocator) void {
    //     const current_ip = self.instruction_pointer;
    //     while (self.has_next()) {
    //         var instruction: []const u8 = self.advance();
    //         std.debug.print("{s}\n", .{debug.dissambleInstruction(alloc, &instruction, self.instruction_pointer - 4)});
    //     }
    //     self.instruction_pointer = current_ip;
    // }
};

test "Simple addition bytecode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var instance = Interpreter{};
    @memset(&instance.registers, 0);
    defer instance.deinit(allocator);
    // Load code into the interpreter
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(OpCodes.LOAD_IMMEDIATE), 0x01, 0x00, 0x01 });
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(OpCodes.LOAD_IMMEDIATE), 0x02, 0x00, 0x02 });
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(OpCodes.ADD), 0x03, 0x01, 0x02 });
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(OpCodes.HALT), 0x00, 0x00, 0x00 });

    // Post load imm in r1
    var result = instance.run();
    try std.testing.expect(result == .OK);
    try std.testing.expect(instance.registers[1] == 0x01);
    // Post load imm in r2
    result = instance.run();
    try std.testing.expect(result == .OK);
    try std.testing.expect(instance.registers[2] == 0x02);
    // Post addition
    result = instance.run();
    try std.testing.expect(result == .OK);
    try std.testing.expect(instance.registers[3] == 0x03);
    // Post halt
    result = instance.run();
    try std.testing.expect(result == .HALT);
}
