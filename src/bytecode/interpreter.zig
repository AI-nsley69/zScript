const std = @import("std");
const bytecode = @import("bytecode.zig");
const debug = @import("debug.zig");

pub const InterpretResult = enum { OK, COMPILE_ERR, RUNTIME_ERR };

pub const Interpreter = struct {
    ip: usize = 0,
    instructions: std.ArrayList(u8),
    lines: std.ArrayList(usize),
    constants: std.ArrayList(bytecode.Value),

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.instructions.deinit();
        self.lines.deinit();
        self.constants.deinit();
    }

    pub fn add_instruction(self: *Self, ops: []const u8, line: usize) !void {
        try self.instructions.appendSlice(ops);
        try self.lines.append(line);
    }

    pub fn add_constant(self: *Self, val: bytecode.Value, line: usize) !u8 {
        // TODO: convert the usize value to u8 numbers, and read them in later on.
        std.debug.assert(self.constants.items.len < 254);
        try self.constants.append(val);
        try self.lines.append(line);
        return @intCast(self.constants.items.len - 1);
    }

    fn has_next(self: *Self) bool {
        return self.ip < self.instructions.items.len;
    }

    fn next(self: *Self) u8 {
        const item = self.instructions.items[self.ip];
        self.ip += 1;
        return item;
    }

    pub fn decode(self: *Self) []const u8 {
        const op: bytecode.OpCodes = @enumFromInt(self.next());

        return switch (op) {
            .CONSTANT => &[_]u8{ @intFromEnum(op), self.next() },
            else => &[_]u8{@intFromEnum(op)},
        };
    }

    pub fn dump(self: *Self, alloc: *std.mem.Allocator) void {
        while (self.has_next()) {
            const start_ip = self.ip + 1;
            const current_line = self.lines.items[self.ip + 1];
            const instruction = self.decode();
            const op: bytecode.OpCodes = @enumFromInt(instruction[0]);

            const debug_str: []const u8 = op_switch: switch (op) {
                .CONSTANT => {
                    const val_idx = instruction[1];
                    const val: bytecode.Value = self.constants.items[val_idx];
                    break :op_switch debug.constantInstruction(alloc, val, start_ip, current_line);
                },
                .RETURN => {
                    var instruction_str: []const u8 = "RET";
                    break :op_switch debug.fmtInstruction(alloc, &instruction_str, start_ip, current_line);
                },
            };

            std.debug.print("{s}\n", .{debug_str});
        }
    }
};
