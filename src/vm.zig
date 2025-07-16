const std = @import("std");
const debug = @import("debug.zig");
const Value = @import("value.zig").Value;

pub const OpCodes = enum(u8) {
    @"return",
    halt,
    noop,
    copy,
    load_int,
    load_float,
    load_bool,
    add,
    sub,
    mult,
    divide,
    jump,
    jump_eql,
    jump_neq,
    eql,
    neq,
    less_than,
    lte,
    greater_than,
    gte,
    xor,
    @"and",
    not,
    @"or",
};

pub const Frame = struct {
    body: []u8,
    ip: usize = 0,
    caller: ?*Frame = null,
    result: ?*Value,
};

pub const Error = error{
    MismatchedTypes,
    Unknown,
};

pub const RegisterSize = u16;

// pub const RegisterSize = std.math.maxInt(u16);

const Vm = @This();

allocator: std.mem.Allocator,
trace: bool = true,
instructions: std.io.FixedBufferStream([]u8),
constants: []Value,
registers: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
return_value: ?Value = null,

pub fn init(allocator: std.mem.Allocator, instructions: []u8, constants: []Value) !Vm {
    var vm: Vm = .{
        .allocator = allocator,
        .instructions = std.io.fixedBufferStream(instructions),
        .constants = constants,
    };

    try vm.registers.ensureUnusedCapacity(allocator, 256);
    for (0..256) |_| {
        try vm.registers.append(allocator, Value{ .int = 0 });
    }

    return vm;
}

pub fn deinit(self: *Vm) void {
    self.registers.deinit(self.allocator);
}

fn has_next(self: *Vm) bool {
    const ip = self.instructions.getPos() catch false;
    const end = self.instructions.getEndPos() catch false;
    return ip < end;
}

fn getReader(self: *Vm) std.io.FixedBufferStream([]u8).Reader {
    return self.instructions.reader();
}

fn next(self: *Vm) u8 {
    if (!self.has_next()) return @intFromEnum(OpCodes.halt);
    const in = self.getReader();
    return in.readByte() catch @intFromEnum(OpCodes.halt);
}

fn nextOp(self: *Vm) OpCodes {
    return @enumFromInt(self.next());
}

fn addRegister(self: *Vm, index: RegisterSize) !void {
    while (index >= self.registers.items.len) {
        try self.registers.append(self.allocator, Value{ .int = 0 });
    }
}

fn getRegister(self: *Vm, index: u8) Value {
    self.addRegister(index) catch {};
    return self.registers.items[index];
}

fn setRegister(self: *Vm, index: u8, value: Value) void {
    self.addRegister(index) catch {};
    self.registers.items[index] = value;
}

pub fn run(self: *Vm) !void {
    const opcode: OpCodes = self.nextOp();
    return blk: switch (opcode) {
        .copy => {
            try self.copy();
            continue :blk self.nextOp();
        },
        .add => {
            try self.add();
            continue :blk self.nextOp();
        },
        .sub => {
            try self.sub();
            continue :blk self.nextOp();
        },
        .mult => {
            try self.mul();
            continue :blk self.nextOp();
        },
        .divide => {
            try self.div();
            continue :blk self.nextOp();
        },
        .@"or" => {
            try self.logicalOr();
            continue :blk self.nextOp();
        },
        .@"and" => {
            try self.logicalAnd();
            continue :blk self.nextOp();
        },
        .eql => {
            try self.eql();
            continue :blk self.nextOp();
        },
        .neq => {
            try self.neq();
            continue :blk self.nextOp();
        },
        .less_than => {
            try self.lt();
            continue :blk self.nextOp();
        },
        .lte => {
            try self.lte();
            continue :blk self.nextOp();
        },
        .greater_than => {
            try self.gt();
            continue :blk self.nextOp();
        },
        .gte => {
            try self.gte();
            continue :blk self.nextOp();
        },
        .jump_eql => {
            try self.jeq();
            continue :blk self.nextOp();
        },
        .jump_neq => {
            try self.jne();
            continue :blk self.nextOp();
        },
        .jump => {
            try self.jmp();
            continue :blk self.nextOp();
        },
        .load_int => {
            try self.loadInt();
            continue :blk self.nextOp();
        },
        .load_float => {
            try self.loadFloat();
            continue :blk self.nextOp();
        },
        .load_bool => {
            try self.loadBool();
            continue :blk self.nextOp();
        },
        .@"return" => {
            try self.ret();
            continue :blk self.nextOp();
        },
        .halt => return,
        .noop => {
            continue :blk self.nextOp();
        },
        else => return Error.Unknown,
    };
}

fn ret(self: *Vm) !void {
    self.return_value = self.getRegister(self.next());
}

fn copy(self: *Vm) !void {
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
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn neq(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    const res = switch (fst) {
        .boolean => if (snd == .boolean) fst.boolean != snd.boolean else false,
        .float => if (snd == .float) fst.float != snd.float else false,
        .int => if (snd == .int) fst.int != snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn lt(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    const res = try switch (fst) {
        .boolean => Error.MismatchedTypes,
        .float => if (snd == .float) fst.float < snd.float else false,
        .int => if (snd == .int) fst.int < snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn lte(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    const res = try switch (fst) {
        .boolean => Error.MismatchedTypes,
        .float => if (snd == .float) fst.float <= snd.float else false,
        .int => if (snd == .int) fst.int <= snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn gt(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    const res = try switch (fst) {
        .boolean => Error.MismatchedTypes,
        .float => if (snd == .float) fst.float > snd.float else false,
        .int => if (snd == .int) fst.int > snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn gte(self: *Vm) !void {
    const dst = self.next();
    const fst = self.getRegister(self.next());
    const snd = self.getRegister(self.next());

    const res = try switch (fst) {
        .boolean => Error.MismatchedTypes,
        .float => if (snd == .float) fst.float >= snd.float else false,
        .int => if (snd == .int) fst.int >= snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn jeq(self: *Vm) !void {
    const isEql = self.getRegister(self.next());
    if (isEql != .boolean) return;
    if (!isEql.boolean) return;

    const ip = try self.getReader().readInt(u16, .big);
    try self.instructions.seekTo(ip);
}

fn jne(self: *Vm) !void {
    const isEql = self.getRegister(self.next());
    if (isEql != .boolean) return;
    if (isEql.boolean) return;

    const ip = try self.getReader().readInt(u16, .big);
    try self.instructions.seekTo(ip);
}

fn jmp(self: *Vm) !void {
    const ip = try self.getReader().readInt(u16, .big);
    try self.instructions.seekTo(ip);
}

fn loadBool(self: *Vm) !void {
    const dst = self.next();
    const val = self.next() == 1;
    self.setRegister(dst, .{ .boolean = val });
}

fn loadFloat(self: *Vm) !void {
    const dst = self.next();
    const val = try self.getReader().readInt(u64, .big);
    self.setRegister(dst, .{ .float = @bitCast(val) });
}

fn loadInt(self: *Vm) !void {
    const dst = self.next();
    const val = try self.getReader().readInt(u64, .big);
    self.setRegister(dst, .{ .int = @bitCast(val) });
}
