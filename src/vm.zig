const std = @import("std");
const debug = @import("debug.zig");

pub const OpCodes = enum(u8) {
    RET,
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

pub const ValueType = enum {
    int,
    float,
    string,
    boolean,
};

pub const Value = union(ValueType) {
    int: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
};

const Vm = @This();

trace: bool = true,
ip: u64 = 0,
instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
constants: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
registers: [256]Value = undefined,
return_value: ?Value = null,

pub fn deinit(self: *Vm, alloc: std.mem.Allocator) void {
    self.instructions.deinit(alloc);
    self.constants.deinit(alloc);
}

pub fn has_next(self: *Vm) bool {
    return self.ip < self.instructions.items.len;
}

fn next(self: *Vm) u8 {
    std.debug.assert(self.ip < self.instructions.items.len);
    self.ip += 1;
    return self.instructions.items[self.ip - 1];
}

fn getRegister(self: *Vm, index: u8) Value {
    return self.registers[index];
}

fn setRegister(self: *Vm, index: u8, value: Value) void {
    self.registers[index] = value;
}

pub fn run(self: *Vm) InterpretResult {
    if (!self.has_next()) return .HALT;

    const opcode: OpCodes = @enumFromInt(self.next());

    return switch (opcode) {
        .MOV => return self.mov(),
        .ADD => return self.add(),
        .LOAD_IMMEDIATE => return self.loadConst(),
        .RET => return self.ret(),
        else => .RUNTIME_ERR,
    };
}

fn ret(self: *Vm) InterpretResult {
    self.return_value = self.getRegister(self.next());
    return .HALT;
}

fn mov(self: *Vm) InterpretResult {
    self.setRegister(self.next(), self.getRegister(self.next()));
    return .OK;
}

fn add(self: *Vm) InterpretResult {
    const dst = self.next();
    const a = self.getRegister(self.next());
    const b = self.getRegister(self.next());

    return switch (a) {
        .int => self.addInt(dst, a, b),
        .float => self.addFloat(dst, a, b),
        .string => return .RUNTIME_ERR,
        .boolean => return .RUNTIME_ERR,
    };
}

inline fn addInt(self: *Vm, dst: u8, fst: Value, snd: Value) InterpretResult {
    if (snd != .int) {
        return .RUNTIME_ERR;
    }
    const res = Value{ .int = fst.int + snd.int };
    self.setRegister(dst, res);
    return .OK;
}

inline fn addFloat(self: *Vm, dst: u8, fst: Value, snd: Value) InterpretResult {
    if (snd != .float) {
        return .RUNTIME_ERR;
    }
    const res = Value{ .float = fst.float + snd.float };
    self.setRegister(dst, res);
    return .OK;
}

fn loadConst(self: *Vm) InterpretResult {
    const dst = self.next();
    const const_idx = self.next();
    self.setRegister(dst, self.constants.items[const_idx]);
    return .OK;
}

test "Simple addition bytecode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var instance = Vm{};
    @memset(&instance.registers, 0);
    defer instance.deinit(allocator);
    // Load code into the interpreter
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(OpCodes.LOAD_IMMEDIATE), 0x01, 0x00, 0x01 });
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(OpCodes.LOAD_IMMEDIATE), 0x02, 0x00, 0x02 });
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(OpCodes.ADD), 0x03, 0x01, 0x02 });
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(OpCodes.RET), 0x00, 0x00, 0x00 });

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
    try std.testing.expect(result == .RET);
}
