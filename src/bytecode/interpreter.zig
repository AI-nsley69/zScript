const std = @import("std");
const bytecode = @import("bytecode.zig");
const debug = @import("debug.zig");

pub const InterpretResult = enum { OK, COMPILE_ERR, RUNTIME_ERR, HALT };

const InterpreterError = error{};

pub const Interpreter = struct {
    trace: bool = true,
    instruction_pointer: u32 = 0,
    instructions: std.ArrayList(u8),
    constants: std.ArrayList(bytecode.Value),
    registers: [256]u8 = undefined,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.instructions.deinit();
        self.constants.deinit();
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

    pub fn run(self: *Self, alloc: *std.mem.Allocator) InterpretResult {
        if (!self.has_next()) return .HALT;

        var instruction: []const u8 = self.advance();
        if (self.trace) {
            std.debug.print("{s}\n", .{debug.dissambleInstruction(alloc, &instruction, self.instruction_pointer - 4)});
        }
        const op_code: bytecode.OpCodes = @enumFromInt(instruction[0]);

        return switch (op_code) {
            .HALT => InterpretResult.HALT,
            else => .COMPILE_ERR,
        };
    }

    pub fn dump(self: *Self, alloc: *std.mem.Allocator) void {
        const current_ip = self.instruction_pointer;
        while (self.has_next()) {
            var instruction: []const u8 = self.advance();
            std.debug.print("{s}\n", .{debug.dissambleInstruction(alloc, &instruction, self.instruction_pointer - 4)});
        }
        self.instruction_pointer = current_ip;
    }
};
