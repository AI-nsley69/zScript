const std = @import("std");
const debug = @import("debug.zig");

pub const OpCodes = enum(u8) {
    RET,
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

// pub const InterpretResult = enum { OK, COMPILE_ERR, RUNTIME_ERR, HALT };

pub const Error = error{
    MismatchedTypes,
    Unknown,
};

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

fn has_next(self: *Vm) bool {
    return self.ip < self.instructions.items.len;
}

fn next(self: *Vm) u8 {
    if (self.ip < self.instructions.items.len) return @intFromEnum(OpCodes.HALT);
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

pub fn run(self: *Vm) !void {
    if (!self.has_next()) return;

    const opcode: OpCodes = self.nextOp();

    return blk: switch (opcode) {
        .MOV => {
            try self.mov();
            continue :blk self.nextOp();
        },
        .ADD => {
            try self.add();
            continue :blk self.nextOp();
        },
        .SUBTRACT => {
            try self.sub();
            continue :blk self.nextOp();
        },
        .MULTIPLY => {
            try self.mul();
            continue :blk self.nextOp();
        },
        .DIVIDE => {
            try self.div();
            continue :blk self.nextOp();
        },
        .LOAD_IMMEDIATE => {
            try self.loadConst();
            continue :blk self.nextOp();
        },
        .RET => {
            try self.ret();
            continue :blk self.nextOp();
        },
        .HALT => return,
        else => return Error.Unknown,
    };
}

fn ret(self: *Vm) !void {
    self.return_value = self.getRegister(self.next());
}

fn mov(self: *Vm) !void {
    self.setRegister(self.next(), self.getRegister(self.next()));
}

fn add(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    return switch (fst) {
        .int => {
            if (snd != .int) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .int = fst.int + snd.int });
        },
        .float => {
            if (snd != .float) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .float = fst.float + snd.float });
        },
        .string => return Error.Unknown,
        .boolean => return Error.Unknown,
    };
}

fn sub(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    return switch (fst) {
        .int => {
            if (snd != .int) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .int = fst.int - snd.int });
        },
        .float => {
            if (snd != .float) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .float = fst.float - snd.float });
        },
        .string => return Error.Unknown,
        .boolean => return Error.Unknown,
    };
}

fn mul(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    return switch (fst) {
        .int => {
            if (snd != .int) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .int = fst.int * snd.int });
        },
        .float => {
            if (snd != .float) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .float = fst.float * snd.float });
        },
        .string => return Error.Unknown,
        .boolean => return Error.Unknown,
    };
}

fn div(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    return switch (fst) {
        .int => {
            if (snd != .int) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .int = @divExact(fst.int, snd.int) });
        },
        .float => {
            if (snd != .float) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .float = @divExact(fst.float, snd.float) });
        },
        .string => return Error.Unknown,
        .boolean => return Error.Unknown,
    };
}

fn loadConst(self: *Vm) !void {
    const dst = self.next();
    const const_idx = self.next();
    self.setRegister(dst, self.constants.items[const_idx]);
}
