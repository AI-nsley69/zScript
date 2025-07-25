const std = @import("std");
const Bytecode = @import("bytecode.zig");
const Debug = @import("debug.zig");
const Compiler = @import("compiler.zig");
const Gc = @import("gc.zig");

const Value = @import("value.zig").Value;
const Native = @import("native.zig");
const ValueType = @import("value.zig").ValueType;

const OpCodes = Bytecode.OpCodes;
const Function = Bytecode.Function;
const RegisterSize = Bytecode.RegisterSize;
const CompilerOutput = Compiler.CompilerOutput;

pub const Error = error{
    MismatchedTypes,
    InvalidParameter,
    UnsupportedOperation,
    Unknown,
};

pub const Frame = struct {
    ip: usize = 0,
    metadata: usize, // Metadata
};

const max_call_depth = std.math.maxInt(u16);

const Vm = @This();

gc: *Gc,

functions: []Function,
constants: []Value,
// Holds the currently used registers
registers: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
// Stack for parameters
param_stack: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
// Stack for registers
reg_stack: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
// Stack holding the call info, such as return register, ip on call, etc
call_stack: std.ArrayListUnmanaged(Frame) = std.ArrayListUnmanaged(Frame){},

result: ?Value = null,

pub fn init(gc: *Gc, compiled: CompilerOutput) !Vm {
    var vm: Vm = .{
        .gc = gc,
        .functions = compiled.frames,
        .constants = compiled.constants,
    };

    const main: Frame = .{ .metadata = 0 };
    try vm.call_stack.append(gc.gpa, main);

    try vm.registers.ensureUnusedCapacity(gc.gpa, 256);
    for (0..256) |_| {
        try vm.registers.append(gc.gpa, Value{ .int = 0 });
    }

    return vm;
}

pub fn deinit(self: *Vm) void {
    self.registers.deinit(self.gc.gpa);
    self.reg_stack.deinit(self.gc.gpa);
    self.call_stack.deinit(self.gc.gpa);
    self.param_stack.deinit(self.gc.gpa);

    self.gc.gpa.free(self.constants);
}

pub fn metadata(self: *Vm) *Function {
    return &self.functions[self.current().metadata];
}

pub fn current(self: *Vm) *Frame {
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
    if (self.gc.allocated_bytes >= self.gc.size_threshold) {
        try self.gc.markRoots(self);
        try self.gc.sweep();
    }
    const op: OpCodes = @enumFromInt(try self.next());
    // std.debug.print("Next op: {s}\n", .{@tagName(op)});
    return op;
}

fn nextReg(self: *Vm) !Value {
    return self.getRegister(try self.next());
}

fn addRegister(self: *Vm, index: RegisterSize) !void {
    while (index >= self.registers.items.len) {
        try self.registers.append(self.gc.gpa, Value{ .int = 0 });
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
            const res: Value = val: switch (fst) {
                .int => .{ .int = try Value.asInt(fst) + try Value.asInt(snd) },
                .float => .{ .float = try Value.asFloat(fst) + try Value.asFloat(snd) },
                .boolean => return Error.UnsupportedOperation,
                .string => {
                    const fst_str = try Value.asString(self.gc, fst);
                    const snd_str = try Value.asString(self.gc, snd);
                    const new_str = try self.gc.alloc(.string, fst_str.len + snd_str.len);
                    @memcpy(new_str.string[0..fst_str.len], fst_str);
                    @memcpy(new_str.string[fst_str.len..], snd_str);
                    break :val new_str;
                },
            };
            self.setRegister(dst, res);
            continue :blk try self.nextOp();
        },
        .sub => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res: Value = switch (fst) {
                .int => .{ .int = try Value.asInt(fst) - try Value.asInt(snd) },
                .float => .{ .float = try Value.asFloat(fst) - try Value.asFloat(snd) },
                .boolean, .string => return Error.UnsupportedOperation,
            };
            self.setRegister(dst, res);
            continue :blk try self.nextOp();
        },
        .mult => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res: Value = switch (fst) {
                .int => .{ .int = try Value.asInt(fst) * try Value.asInt(snd) },
                .float => .{ .float = try Value.asFloat(fst) * try Value.asFloat(snd) },
                .boolean, .string => return Error.UnsupportedOperation,
            };
            self.setRegister(dst, res);
            continue :blk try self.nextOp();
        },
        .divide => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res: Value = switch (fst) {
                .int => .{ .int = @divFloor(try Value.asInt(fst), try Value.asInt(snd)) },
                .float => .{ .float = @divFloor(try Value.asFloat(fst), try Value.asFloat(snd)) },
                .boolean, .string => return Error.UnsupportedOperation,
            };
            self.setRegister(dst, res);
            continue :blk try self.nextOp();
        },
        .@"or" => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            self.setRegister(dst, .{ .boolean = try Value.asBool(fst) or try Value.asBool(snd) });
            continue :blk try self.nextOp();
        },
        .@"and" => {
            const dst = try self.next();
            const fst = self.getRegister(try self.next());
            const snd = try self.nextReg();
            self.setRegister(dst, .{ .boolean = try Value.asBool(fst) and try Value.asBool(snd) });
            continue :blk try self.nextOp();
        },
        .eql => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res: bool = switch (fst) {
                .boolean => try Value.asBool(fst) == try Value.asBool(snd),
                .float => try Value.asFloat(fst) == try Value.asFloat(snd),
                .int => try Value.asInt(fst) == try Value.asInt(snd),
                .string => std.mem.eql(u8, try Value.asString(self.gc, fst), try Value.asString(self.gc, snd)),
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .neq => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = switch (fst) {
                .boolean => try Value.asBool(fst) != try Value.asBool(snd),
                .float => try Value.asFloat(fst) != try Value.asFloat(snd),
                .int => try Value.asInt(fst) != try Value.asInt(snd),
                .string => !std.mem.eql(u8, try Value.asString(self.gc, fst), try Value.asString(self.gc, snd)),
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .less_than => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = try switch (fst) {
                .boolean, .string => Error.MismatchedTypes,
                .float => try Value.asFloat(fst) < try Value.asFloat(snd),
                .int => try Value.asInt(fst) < try Value.asInt(snd),
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .lte => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = try switch (fst) {
                .boolean, .string => Error.MismatchedTypes,
                .float => try Value.asFloat(fst) <= try Value.asFloat(snd),
                .int => try Value.asInt(fst) <= try Value.asInt(snd),
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .greater_than => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = try switch (fst) {
                .boolean, .string => Error.MismatchedTypes,
                .float => try Value.asFloat(fst) > try Value.asFloat(snd),
                .int => try Value.asInt(fst) > try Value.asInt(snd),
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .gte => {
            const dst = try self.next();
            const fst = try self.nextReg();
            const snd = try self.nextReg();
            const res = try switch (fst) {
                .boolean, .string => Error.MismatchedTypes,
                .float => try Value.asFloat(fst) >= try Value.asFloat(snd),
                .int => try Value.asInt(fst) >= try Value.asInt(snd),
            };
            self.setRegister(dst, .{ .boolean = res });
            continue :blk try self.nextOp();
        },
        .jump_eql => {
            const isEql = try self.nextReg();
            const ip = self.readInt(u16);
            if (try Value.asBool(isEql)) {
                self.current().ip = ip;
            }
            continue :blk try self.nextOp();
        },
        .jump_neq => {
            const isEql = try self.nextReg();
            const ip = self.readInt(u16);
            if (!(try Value.asBool(isEql))) {
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
        .load_const => {
            self.setRegister(try self.next(), self.constants[try self.next()]);
            continue :blk try self.nextOp();
        },
        .load_param => {
            const val = self.param_stack.pop();
            if (val == null) {
                @branchHint(.cold);
                return Error.InvalidParameter;
            }
            self.setRegister(try self.next(), val.?);
            continue :blk try self.nextOp();
        },
        .store_param => {
            const src = try self.next();
            try self.param_stack.append(self.gc.gpa, self.getRegister(src));
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
        .native_call => {
            const fn_idx = try self.next();

            const native_fn = try Native.idxToFn(fn_idx);
            const args = self.param_stack.items[self.param_stack.items.len - native_fn.params ..];
            defer self.param_stack.items.len -= native_fn.params;
            native_fn.run(.{ .params = args });

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
    self.setRegister(0x00, res);
}

fn call(self: *Vm) !void {
    const frame_idx = try self.next();

    if (self.call_stack.items.len >= max_call_depth) {
        @branchHint(.cold);
        @panic("Stack Overflow");
    }

    // Push registers to the stack
    try self.reg_stack.appendSlice(self.gc.gpa, self.registers.items[1..self.metadata().reg_size]);
    // Construct a new call_frame and push it to the stack
    const new_call: Frame = .{ .metadata = frame_idx };
    try self.call_stack.append(self.gc.gpa, new_call);
}
