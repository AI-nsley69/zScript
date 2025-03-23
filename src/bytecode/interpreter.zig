const std = @import("std");
const bytecode = @import("bytecode.zig");
const debug = @import("debug.zig");

pub const InterpretResult = enum { OK, COMPILE_ERR, RUNTIME_ERR, HALT };

const InterpreterError = error{};

pub const Interpreter = struct {
    trace: bool = true,
    instruction_pointer: u32 = 0,
    instructions: std.ArrayListUnmanaged(u8) = std.ArrayListUnmanaged(u8){},
    constants: std.ArrayListUnmanaged(bytecode.Value) = std.ArrayListUnmanaged(bytecode.Value){},
    registers: [256]u32 = undefined,

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

    fn getRegister(self: *Self, index: u8) u32 {
        return self.registers[index];
    }

    fn setRegister(self: *Self, index: u8, value: u32) void {
        self.registers[index] = value;
    }

    pub fn run(self: *Self) InterpretResult {
        if (!self.has_next()) return .HALT;

        const instruction: []const u8 = self.advance();
        // if (self.trace) {
        //     std.debug.print("{s}\n", .{debug.dissambleInstruction(alloc, &instruction, self.instruction_pointer - 4)});
        // }
        const op_code: bytecode.OpCodes = @enumFromInt(instruction[0]);

        return switch (op_code) {
            .ADD => {
                const res: u32 = self.getRegister(instruction[2]) + self.getRegister(instruction[3]);
                self.setRegister(instruction[1], res);
                return InterpretResult.OK;
            },
            .LOAD_IMMEDIATE => {
                const imm: u16 = @as(u16, instruction[2]) << 8 | instruction[3];
                self.setRegister(instruction[1], imm);
                return InterpretResult.OK;
            },
            .HALT => InterpretResult.HALT,
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
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(bytecode.OpCodes.LOAD_IMMEDIATE), 0x01, 0x00, 0x01 });
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(bytecode.OpCodes.LOAD_IMMEDIATE), 0x02, 0x00, 0x02 });
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(bytecode.OpCodes.ADD), 0x03, 0x01, 0x02 });
    try instance.instructions.appendSlice(allocator, &[_]u8{ @intFromEnum(bytecode.OpCodes.HALT), 0x00, 0x00, 0x00 });

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
