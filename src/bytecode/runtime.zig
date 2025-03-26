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
    ip: u64 = 0,
    instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    constants: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
    registers: [256]Value = undefined,

    const Self = @This();

    pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        self.instructions.deinit(alloc);
        self.constants.deinit(alloc);
    }

    pub fn has_next(self: *Self) bool {
        return self.ip < self.instructions.items.len;
    }

    fn next(self: *Self) u8 {
        std.debug.assert(self.ip < self.instructions.items.len);
        self.ip += 1;
        return self.instructions.items[self.ip - 1];
    }

    fn getRegister(self: *Self, index: u8) Value {
        return self.registers[index];
    }

    fn setRegister(self: *Self, index: u8, value: Value) void {
        self.registers[index] = value;
    }

    pub fn run(self: *Self) InterpretResult {
        if (!self.has_next()) return .HALT;

        const opcode: OpCodes = @enumFromInt(self.next());

        return switch (opcode) {
            .MOV => return self.mov(),
            .ADD => return self.add(),
            .LOAD_IMMEDIATE => return self.loadConst(),
            .HALT => .HALT,
            else => .RUNTIME_ERR,
        };
    }

    fn mov(self: *Self) InterpretResult {
        self.setRegister(self.next(), self.getRegister(self.next()));
        return .OK;
    }

    fn add(self: *Self) InterpretResult {
        const dst = self.next();
        const val: Value = self.getRegister(self.next()) + self.getRegister(self.next());
        self.setRegister(dst, val);
        return .OK;
    }

    fn loadConst(self: *Self) InterpretResult {
        const dst = self.next();
        const const_idx = self.next();
        self.setRegister(dst, self.constants.items[const_idx]);
        return .OK;
    }
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
