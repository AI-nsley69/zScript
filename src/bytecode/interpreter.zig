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
                std.debug.print("{d}\n", .{res});
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
