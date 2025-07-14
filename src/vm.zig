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
    JMP_EQL,
    JMP_NEQ,
    BRANCH_IF_EQUAL,
    BRANCH_IF_NOT_EQUAL,
    XOR,
    AND,
    NOT,
    OR,
    EQL,
    NEQ,
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

// pub const RegisterSize = std.math.maxInt(u16);

const Vm = @This();

trace: bool = true,
ip: u64 = 0,
instructions: []u8,
constants: []Value,
registers: [256]Value = undefined,
return_value: ?Value = null,

fn has_next(self: *Vm) bool {
    return self.ip < self.instructions.len;
}

fn next(self: *Vm) u8 {
    if (self.ip >= self.instructions.len) return @intFromEnum(OpCodes.HALT);
    self.ip += 1;
    return self.instructions[self.ip - 1];
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
        .OR => {
            try self.logicalOr();
            continue :blk self.nextOp();
        },
        .AND => {
            try self.logicalAnd();
            continue :blk self.nextOp();
        },
        .EQL => {
            try self.eql();
            continue :blk self.nextOp();
        },
        .NEQ => {
            try self.neq();
            continue :blk self.nextOp();
        },
        .JMP_EQL => {
            try self.jeq();
            continue :blk self.nextOp();
        },
        .JMP_NEQ => {
            try self.jne();
            continue :blk self.nextOp();
        },
        .JUMP => {
            try self.jmp();
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
        .NOP => {
            continue :blk self.nextOp();
        },
        else => return Error.Unknown,
    };
}

fn ret(self: *Vm) !void {
    self.return_value = self.getRegister(self.next());
}

fn mov(self: *Vm) !void {
    const src = self.next();
    const dst = self.next();
    self.setRegister(src, self.getRegister(dst));
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
            self.setRegister(dst, .{ .int = @divFloor(fst.int, snd.int) });
        },
        .float => {
            if (snd != .float) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .float = @divFloor(fst.float, snd.float) });
        },
        .string => return Error.Unknown,
        .boolean => return Error.Unknown,
    };
}

fn logicalAnd(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    if (fst != .boolean or snd != .boolean) return Error.MismatchedTypes;
    self.setRegister(dst, .{ .boolean = fst.boolean and snd.boolean });
}

fn logicalOr(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    if (fst != .boolean or snd != .boolean) return Error.MismatchedTypes;
    self.setRegister(dst, .{ .boolean = fst.boolean or snd.boolean });
}

fn eql(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    const res: bool = switch (fst) {
        .boolean => if (snd == .boolean) fst.boolean == snd.boolean else false,
        .float => if (snd == .float) fst.float == snd.float else false,
        .int => if (snd == .int) fst.int == snd.int else false,
        .string => if (snd == .string) std.mem.eql(u8, fst.string, snd.string) else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn neq(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    const res: bool = switch (fst) {
        .boolean => if (snd == .boolean) fst.boolean != snd.boolean else false,
        .float => if (snd == .float) fst.float != snd.float else false,
        .int => if (snd == .int) fst.int != snd.int else false,
        .string => if (snd == .string) !std.mem.eql(u8, fst.string, snd.string) else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn jeq(self: *Vm) !void {
    const isEql = self.getRegister(self.next());
    if (isEql != .boolean) return;
    if (!isEql.boolean) return;

    self.ip = @as(u16, self.next()) << 8 | self.next();
}

fn jne(self: *Vm) !void {
    const isEql = self.getRegister(self.next());
    if (isEql != .boolean) return;
    if (isEql.boolean) return;

    self.ip = @as(u16, self.next()) << 8 | self.next();
}

fn jmp(self: *Vm) !void {
    self.ip = @as(u16, self.next()) << 8 | self.next();
}

fn loadConst(self: *Vm) !void {
    const dst = self.next();
    const const_idx = self.next();
    self.setRegister(dst, self.constants[const_idx]);
}
