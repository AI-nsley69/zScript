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

fn nextOp(self: *Vm) OpCodes {
    return @enumFromInt(self.next());
}

fn getRegister(self: *Vm, index: u8) Value {
    return self.registers[index];
}

fn setRegister(self: *Vm, index: u8, value: Value) void {
    self.registers[index] = value;
}

pub fn run(self: *Vm) InterpretResult {
    if (!self.has_next()) return .HALT;

    const opcode: OpCodes = self.nextOp();

    return blk: switch (opcode) {
        .MOV => {
            const res = self.mov();
            if (res != .OK) return res;
            continue :blk self.nextOp();
        },
        .ADD => {
            const res = self.add();
            if (res != .OK) return res;
            continue :blk self.nextOp();
        },
        .SUBTRACT => {
            const res = self.sub();
            if (res != .OK) return res;
            continue :blk self.nextOp();
        },
        .MULTIPLY => {
            const res = self.mul();
            if (res != .OK) return res;
            continue :blk self.nextOp();
        },
        .DIVIDE => {
            const res = self.div();
            if (res != .OK) return res;
            continue :blk self.nextOp();
        },
        .LOAD_IMMEDIATE => {
            const res = self.loadConst();
            if (res != .OK) return res;
            continue :blk self.nextOp();
        },
        .RET => {
            const res = self.ret();
            if (res != .OK) return res;
            continue :blk self.nextOp();
        },
        else => return .RUNTIME_ERR,
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
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    return switch (fst) {
        .int => {
            if (snd != .int) return .RUNTIME_ERR;
            self.setRegister(dst, .{ .int = fst.int + snd.int });
            return .OK;
        },
        .float => {
            if (snd != .float) return .RUNTIME_ERR;
            self.setRegister(dst, .{ .float = fst.float + snd.float });
            return .OK;
        },
        .string => return .RUNTIME_ERR,
        .boolean => return .RUNTIME_ERR,
    };
}

fn sub(self: *Vm) InterpretResult {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    return switch (fst) {
        .int => {
            if (snd != .int) return .RUNTIME_ERR;
            self.setRegister(dst, .{ .int = fst.int - snd.int });
            return .OK;
        },
        .float => {
            if (snd != .float) return .RUNTIME_ERR;
            self.setRegister(dst, .{ .float = fst.float - snd.float });
            return .OK;
        },
        .string => return .RUNTIME_ERR,
        .boolean => return .RUNTIME_ERR,
    };
}

fn mul(self: *Vm) InterpretResult {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    return switch (fst) {
        .int => {
            if (snd != .int) return .RUNTIME_ERR;
            self.setRegister(dst, .{ .int = fst.int * snd.int });
            return .OK;
        },
        .float => {
            if (snd != .float) return .RUNTIME_ERR;
            self.setRegister(dst, .{ .float = fst.float * snd.float });
            return .OK;
        },
        .string => return .RUNTIME_ERR,
        .boolean => return .RUNTIME_ERR,
    };
}

fn div(self: *Vm) InterpretResult {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    return switch (fst) {
        .int => {
            if (snd != .int) return .RUNTIME_ERR;
            self.setRegister(dst, .{ .int = @divExact(fst.int, snd.int) });
            return .OK;
        },
        .float => {
            if (snd != .float) return .RUNTIME_ERR;
            self.setRegister(dst, .{ .float = @divExact(fst.float, snd.float) });
            return .OK;
        },
        .string => return .RUNTIME_ERR,
        .boolean => return .RUNTIME_ERR,
    };
}

fn loadConst(self: *Vm) InterpretResult {
    const dst = self.next();
    const const_idx = self.next();
    self.setRegister(dst, self.constants.items[const_idx]);
    return .OK;
}
