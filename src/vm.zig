const std = @import("std");
const Bytecode = @import("bytecode.zig");
const Debug = @import("debug.zig");
const Compiler = @import("compiler.zig");
const Value = @import("value.zig").Value;
const ValueType = @import("value.zig").ValueType;

const OpCodes = Bytecode.OpCodes;
const Function = Bytecode.Function;
const RegisterSize = Bytecode.RegisterSize;
const CompilerOutput = Compiler.CompilerOutput;

pub const Error = error{
    MismatchedTypes,
    InvalidParameter,
    Unknown,
};

pub const Frame = struct {
    ip: usize = 0,
    metadata: usize, // Metadata
};

const Vm = @This();

allocator: std.mem.Allocator,

functions: []Function,
// Holds the currently used registers
registers: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
// Stack for parameters
param_stack: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
// Stack for registers
reg_stack: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
// Stack holding the call info, such as return register, ip on call, etc
call_stack: std.ArrayListUnmanaged(Frame) = std.ArrayListUnmanaged(Frame){},

result: ?Value = null,

pub fn init(allocator: std.mem.Allocator, compiled: CompilerOutput) !Vm {
    var vm: Vm = .{
        .allocator = allocator,
        .functions = compiled.frames,
    };

    const main: Frame = .{ .metadata = 0 };
    try vm.call_stack.append(allocator, main);

    try vm.registers.ensureUnusedCapacity(allocator, 256);
    for (0..256) |_| {
        try vm.registers.append(allocator, Value{ .int = 0 });
    }

    return vm;
}

pub fn deinit(self: *Vm) void {
    self.registers.deinit(self.allocator);
    self.reg_stack.deinit(self.allocator);
    self.call_stack.deinit(self.allocator);
    self.param_stack.deinit(self.allocator);
}

fn metadata(self: *Vm) *Function {
    return &self.functions[self.current().metadata];
}

fn current(self: *Vm) *Frame {
    return &self.call_stack.items[self.call_stack.items.len - 1];
}

fn next(self: *Vm) !u8 {
    if (self.call_stack.items.len == 0) return error.EndOfStream;
    if (self.current().ip >= self.metadata().body.len) return error.EndOfStream;
    const insn = self.metadata().body[self.current().ip];
    self.current().ip += 1;
    return insn;
}

fn readInt(self: *Vm, comptime T: type) T {
    const sections = @divFloor(@typeInfo(T).int.bits, 8);
    const buf = self.metadata().body[self.current().ip .. self.current().ip + sections];
    self.current().ip += buf.len;
    return std.mem.readInt(T, buf[0..sections], .big);
}

fn nextOp(self: *Vm) !OpCodes {
    const op: OpCodes = @enumFromInt(try self.next());
    // std.debug.print("Next op: {s}\n", .{@tagName(op)});
    return op;
}

fn nextReg(self: *Vm) !Value {
    return self.getRegister(try self.next());
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
    const opcode: OpCodes = try self.nextOp();
    return blk: switch (opcode) {
        .copy => {
            self.setRegister(try self.next(), try self.nextReg());
            continue :blk try self.nextOp();
        },
        .add => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res: Value = switch (fst) {
                .int => if (snd == .int) .{ .int = fst.int + snd.int } else return Error.MismatchedTypes,
                .float => if (snd == .float) .{ .float = fst.float + snd.float } else return Error.MismatchedTypes,
                .boolean => return Error.Unknown,
            };
            self.setRegister(dst, res);
            continue :blk try self.nextOp();
        },
        .sub => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res: Value = switch (fst) {
                .int => if (snd == .int) .{ .int = fst.int - snd.int } else return Error.MismatchedTypes,
                .float => if (snd == .float) .{ .float = fst.float - snd.float } else return Error.MismatchedTypes,
                .boolean => return Error.Unknown,
            };
            self.setRegister(dst, res);
            continue :blk try self.nextOp();
        },
        .mult => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res: Value = switch (fst) {
                .int => if (snd == .int) .{ .int = fst.int * snd.int } else return Error.MismatchedTypes,
                .float => if (snd == .float) .{ .float = fst.float * snd.float } else return Error.MismatchedTypes,
                .boolean => return Error.Unknown,
            };
            self.setRegister(dst, res);
            continue :blk try self.nextOp();
        },
        .divide => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res: Value = switch (fst) {
                .int => if (snd == .int) .{ .int = @divFloor(fst.int, snd.int) } else return Error.MismatchedTypes,
                .float => if (snd == .float) .{ .float = @divFloor(fst.float, snd.float) } else return Error.MismatchedTypes,
                .boolean => return Error.Unknown,
            };
            self.setRegister(dst, res);
            continue :blk try self.nextOp();
        },
        .@"or" => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            if (fst != .boolean or snd != .boolean) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .boolean = fst.boolean or snd.boolean });
            continue :blk try self.nextOp();
        },
        .@"and" => {
            const dst = try self.next();
            const fst = self.getRegister(try self.next());
            const snd = try self.nextReg();
            if (fst != .boolean or snd != .boolean) return Error.MismatchedTypes;
            self.setRegister(dst, .{ .boolean = fst.boolean and snd.boolean });
            continue :blk try self.nextOp();
        },
        .eql => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res: bool = switch (fst) {
                .boolean => if (snd == .boolean) fst.boolean == snd.boolean else false,
                .float => if (snd == .float) fst.float == snd.float else false,
                .int => if (snd == .int) fst.int == snd.int else false,
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .neq => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = switch (fst) {
                .boolean => if (snd == .boolean) fst.boolean != snd.boolean else false,
                .float => if (snd == .float) fst.float != snd.float else false,
                .int => if (snd == .int) fst.int != snd.int else false,
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .less_than => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = try switch (fst) {
                .boolean => Error.MismatchedTypes,
                .float => if (snd == .float) fst.float < snd.float else false,
                .int => if (snd == .int) fst.int < snd.int else false,
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .lte => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = try switch (fst) {
                .boolean => Error.MismatchedTypes,
                .float => if (snd == .float) fst.float <= snd.float else false,
                .int => if (snd == .int) fst.int <= snd.int else false,
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .greater_than => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = try switch (fst) {
                .boolean => Error.MismatchedTypes,
                .float => if (snd == .float) fst.float > snd.float else false,
                .int => if (snd == .int) fst.int > snd.int else false,
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .gte => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = try switch (fst) {
                .boolean => Error.MismatchedTypes,
                .float => if (snd == .float) fst.float >= snd.float else false,
                .int => if (snd == .int) fst.int >= snd.int else false,
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .jump_eql => {
            const isEql = try self.nextReg();
            const ip = self.readInt(u16);
            if (isEql == .boolean and isEql.boolean) {
                self.current().ip = ip;
            }
            continue :blk try self.nextOp();
        },
        .jump_neq => {
            const isEql = try self.nextReg();
            const ip = self.readInt(u16);
            if (isEql == .boolean and !isEql.boolean) {
                self.current().ip = ip;
            }
            continue :blk try self.nextOp();
        },
        .jump => {
            self.current().ip = self.readInt(u16);
            continue :blk try self.nextOp();
        },
        .load_int => {
            self.setRegister(try self.next(), .{ .int = @bitCast(self.readInt(u64)) });
            continue :blk try self.nextOp();
        },
        .load_float => {
            self.setRegister(try self.next(), .{ .float = @bitCast(self.readInt(u64)) });
            continue :blk try self.nextOp();
        },
        .load_bool => {
            self.setRegister(try self.next(), .{ .boolean = try self.next() == 1 });
            continue :blk try self.nextOp();
        },
        .load_param => {
            const val = self.param_stack.pop();
            if (val == null) {
                return Error.InvalidParameter;
            }
            self.setRegister(try self.next(), val.?);
            continue :blk try self.nextOp();
        },
        .store_param => {
            const src = try self.next();
            try self.param_stack.append(self.allocator, self.getRegister(src));
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
    const dst = try self.next();
    const res = self.getRegister(dst);

    _ = self.call_stack.pop();
    // Set the final result if there is no more caller
    if (self.call_stack.items.len < 1) {
        @branchHint(.unlikely);
        self.result = res;
        return error.EndOfStream;
    }

    // Get back the values from the reg stack
    @memcpy(self.registers.items[1..self.metadata().reg_size], self.reg_stack.items[self.reg_stack.items.len - (self.metadata().reg_size - 1) ..]);
    self.reg_stack.items.len -= self.metadata().reg_size - 1;
    // Set the return value
    // std.debug.print("Returning {any}\n", .{res});
    self.setRegister(0x00, res);
}

fn call(self: *Vm) !void {
    const frame_idx = try self.next();

    // const dst = try self.next();
    // _ = dst;
    // self.current().dst_reg = dst;

    // Push registers to the stack
    try self.reg_stack.appendSlice(self.allocator, self.registers.items[1..self.metadata().reg_size]);
    // Construct a new call_frame and push it to the stack
    const new_call: Frame = .{ .metadata = frame_idx };
    try self.call_stack.append(self.allocator, new_call);
}
