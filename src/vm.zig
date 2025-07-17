const std = @import("std");
const debug = @import("debug.zig");
const Compiler = @import("compiler.zig");
const Value = @import("value.zig").Value;

const CompilerOutput = Compiler.CompilerOutput;

pub const OpCodes = enum(u8) {
    @"return",
    halt,
    noop,
    copy,
    load_int,
    load_float,
    load_bool,
    load_param,
    store_param,
    call,
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
    name: []const u8,
    body: []u8,
    ip: usize = 0,
    call_dst: u8 = 0,
    caller: ?usize = null,
    result: ?Value = null,
    reg_size: RegisterSize,
};

pub const Error = error{
    MismatchedTypes,
    InvalidParameter,
    Unknown,
};

pub const RegisterSize = u16;

const Vm = @This();

allocator: std.mem.Allocator,
trace: bool = true,
frames: []*Frame,
frame: usize = 0,
registers: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
param_stack: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
reg_stack: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
call_stack: std.ArrayListUnmanaged(*Frame) = std.ArrayListUnmanaged(*Frame){},
result: ?Value = null,

pub fn init(allocator: std.mem.Allocator, compiled: CompilerOutput) !Vm {
    var vm: Vm = .{
        .allocator = allocator,
        .frames = compiled.frames,
    };

    const main = try allocator.create(Frame);
    const frame = vm.frames[vm.frame].*;
    main.* = .{
        .body = frame.body,
        .reg_size = frame.reg_size,
        .name = frame.name,
    };
    try vm.call_stack.append(allocator, main);

    try vm.registers.ensureUnusedCapacity(allocator, 256);
    for (0..256) |_| {
        try vm.registers.append(allocator, Value{ .int = 0 });
    }

    return vm;
}

pub fn deinit(self: *Vm) void {
    self.registers.deinit(self.allocator);
}

fn current(self: *Vm) *Frame {
    return self.call_stack.items[self.call_stack.items.len - 1];
}

fn next(self: *Vm) !u8 {
    if (self.call_stack.items.len == 0) return error.EndOfStream;
    if (self.current().ip >= self.current().body.len) return error.EndOfStream;
    self.current().ip += 1;
    return self.current().body[self.current().ip - 1];
}

fn nextOp(self: *Vm) !OpCodes {
    const op: OpCodes = @enumFromInt(try self.next());
    std.debug.print("Next op: {s}\n", .{@tagName(op)});
    return op;
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
    // Values to be discarded goes into reg0
    if (index == 0) return;

    self.addRegister(index) catch {};
    self.registers.items[index] = value;
}

pub fn run(self: *Vm) !void {
    const opcode: OpCodes = try self.nextOp();
    return blk: switch (opcode) {
        .copy => {
            try self.copy();
            continue :blk try self.nextOp();
        },
        .add => {
            try self.add();
            continue :blk try self.nextOp();
        },
        .sub => {
            try self.sub();
            continue :blk try self.nextOp();
        },
        .mult => {
            try self.mul();
            continue :blk try self.nextOp();
        },
        .divide => {
            try self.div();
            continue :blk try self.nextOp();
        },
        .@"or" => {
            try self.logicalOr();
            continue :blk try self.nextOp();
        },
        .@"and" => {
            try self.logicalAnd();
            continue :blk try self.nextOp();
        },
        .eql => {
            try self.eql();
            continue :blk try self.nextOp();
        },
        .neq => {
            try self.neq();
            continue :blk try self.nextOp();
        },
        .less_than => {
            try self.lt();
            continue :blk try self.nextOp();
        },
        .lte => {
            try self.lte();
            continue :blk try self.nextOp();
        },
        .greater_than => {
            try self.gt();
            continue :blk try self.nextOp();
        },
        .gte => {
            try self.gte();
            continue :blk try self.nextOp();
        },
        .jump_eql => {
            try self.jeq();
            continue :blk try self.nextOp();
        },
        .jump_neq => {
            try self.jne();
            continue :blk try self.nextOp();
        },
        .jump => {
            try self.jmp();
            continue :blk try self.nextOp();
        },
        .load_int => {
            try self.loadInt();
            continue :blk try self.nextOp();
        },
        .load_float => {
            try self.loadFloat();
            continue :blk try self.nextOp();
        },
        .load_bool => {
            try self.loadBool();
            continue :blk try self.nextOp();
        },
        .load_param => {
            try self.loadParam();
            continue :blk try self.nextOp();
        },
        .store_param => {
            try self.storeParam();
            continue :blk try self.nextOp();
        },
        .@"return" => {
            try self.ret();
            continue :blk try self.nextOp();
        },
        .call => {
            try self.call();
            continue :blk try self.nextOp();
        },
        .halt => return,
        .noop => {
            continue :blk try self.nextOp();
        },
        else => return Error.Unknown,
    };
}

fn ret(self: *Vm) !void {
    const res = self.getRegister(try self.next());
    const popped_frame = self.call_stack.pop();
    // Set the final result if there is no more caller
    if (self.current().caller == null or popped_frame == null) {
        self.result = res;
        return error.EndOfStream;
    }
    var frame = popped_frame.?.*;
    frame.result = res;

    // Update current caller
    const caller = frame.caller;
    self.frame = if (caller != null) caller.? else 0;

    // Get back the values from the reg stack
    @memcpy(self.registers.items[1..self.current().reg_size], self.reg_stack.items[self.reg_stack.items.len - (self.current().reg_size - 1) ..]);
    self.reg_stack.items.len -= self.current().reg_size - 1;
    // std.debug.print("Setting return value {any} in {d}\n", .{ res, self.current().call_dst });
    // Set the return value
    self.setRegister(self.current().call_dst, res);
}

fn call(self: *Vm) !void {
    const frame_idx = try self.next();
    // Setup call dst
    const dst = try self.next();

    self.current().call_dst = dst;
    const frame = self.frames[frame_idx];
    const new_call = try self.allocator.create(Frame);
    new_call.* = .{
        .body = frame.body,
        .caller = self.call_stack.items.len - 1,
        .ip = 0,
        .name = frame.name,
        .reg_size = frame.reg_size,
    };

    try self.call_stack.append(self.allocator, new_call);

    // Push registers to the stack
    try self.reg_stack.appendSlice(self.allocator, self.registers.items[1..self.current().reg_size]);
    // Update to new caller
    self.frame = frame_idx;
}

fn copy(self: *Vm) !void {
    const src = try self.next();
    const dst = try self.next();
    self.setRegister(src, self.getRegister(dst));
}

fn add(self: *Vm) !void {
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

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
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

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
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

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
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

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
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

    if (fst != .boolean or snd != .boolean) return Error.MismatchedTypes;
    self.setRegister(dst, .{ .boolean = fst.boolean and snd.boolean });
}

fn logicalOr(self: *Vm) !void {
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

    if (fst != .boolean or snd != .boolean) return Error.MismatchedTypes;
    self.setRegister(dst, .{ .boolean = fst.boolean or snd.boolean });
}

fn eql(self: *Vm) !void {
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

    const res: bool = switch (fst) {
        .boolean => if (snd == .boolean) fst.boolean == snd.boolean else false,
        .float => if (snd == .float) fst.float == snd.float else false,
        .int => if (snd == .int) fst.int == snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn neq(self: *Vm) !void {
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

    const res = switch (fst) {
        .boolean => if (snd == .boolean) fst.boolean != snd.boolean else false,
        .float => if (snd == .float) fst.float != snd.float else false,
        .int => if (snd == .int) fst.int != snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn lt(self: *Vm) !void {
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

    const res = try switch (fst) {
        .boolean => Error.MismatchedTypes,
        .float => if (snd == .float) fst.float < snd.float else false,
        .int => if (snd == .int) fst.int < snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn lte(self: *Vm) !void {
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

    const res = try switch (fst) {
        .boolean => Error.MismatchedTypes,
        .float => if (snd == .float) fst.float <= snd.float else false,
        .int => if (snd == .int) fst.int <= snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn gt(self: *Vm) !void {
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

    const res = try switch (fst) {
        .boolean => Error.MismatchedTypes,
        .float => if (snd == .float) fst.float > snd.float else false,
        .int => if (snd == .int) fst.int > snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn gte(self: *Vm) !void {
    const dst = try self.next();
    const fst = self.getRegister(try self.next());
    const snd = self.getRegister(try self.next());

    const res = try switch (fst) {
        .boolean => Error.MismatchedTypes,
        .float => if (snd == .float) fst.float >= snd.float else false,
        .int => if (snd == .int) fst.int >= snd.int else false,
    };

    self.setRegister(dst, .{ .boolean = res });
}

fn jeq(self: *Vm) !void {
    const isEql = self.getRegister(try self.next());
    if (isEql != .boolean) return;
    if (!isEql.boolean) return;

    const buf = self.current().body[self.current().ip .. self.current().ip + 2];
    const ip = std.mem.readInt(u16, buf[0..2], .big);
    self.current().ip = ip;
}

fn jne(self: *Vm) !void {
    const isEql = self.getRegister(try self.next());
    if (isEql != .boolean) return;
    if (isEql.boolean) return;

    const buf = self.current().body[self.current().ip .. self.current().ip + 2];
    const ip = std.mem.readInt(u16, buf[0..2], .big);
    self.current().ip = ip;
}

fn jmp(self: *Vm) !void {
    const buf = self.current().body[self.current().ip .. self.current().ip + 2];
    const ip = std.mem.readInt(u16, buf[0..2], .big);
    self.current().ip = ip;
}

fn loadBool(self: *Vm) !void {
    const dst = try self.next();
    const val = try self.next() == 1;
    self.setRegister(dst, .{ .boolean = val });
}

fn loadParam(self: *Vm) !void {
    const dst = try self.next();
    const val = self.param_stack.pop();
    if (val == null) {
        return Error.InvalidParameter;
    }
    self.setRegister(dst, val.?);
}

fn storeParam(self: *Vm) !void {
    const src = try self.next();
    try self.param_stack.append(self.allocator, self.getRegister(src));
}

fn loadFloat(self: *Vm) !void {
    const dst = try self.next();
    var buf = self.current().body[self.current().ip .. self.current().ip + 8];
    self.current().ip += 8;
    const val = std.mem.readInt(u64, buf[0..8], .big);
    self.setRegister(dst, .{ .float = @bitCast(val) });
}

fn loadInt(self: *Vm) !void {
    const dst = try self.next();
    var buf = self.current().body[self.current().ip .. self.current().ip + 8];
    self.current().ip += 8;
    const val = std.mem.readInt(u64, buf[0..8], .big);
    self.setRegister(dst, .{ .int = @bitCast(val) });
}
