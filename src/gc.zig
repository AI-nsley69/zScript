const std = @import("std");
const Vm = @import("vm.zig");

const Allocator = std.mem.Allocator;
const Value = Vm.Value;

const Gc = @This();

gpa: Allocator,

pub fn init(gpa: Allocator) !Gc {
    return .{
        .gpa = gpa,
    };
}

pub fn markRoots(self: *Gc, vm: *Vm) !void {
    for (1..vm.metadata().reg_size) |i| {
        const value = vm.registers.items[i];
        self.markValue(value);
    }
}

fn markValue(self: *Gc, value: Value) !void {
    _ = self;
    switch (value) {
        // No heap allocations done for these values
        .int, .float, .bool => {},
    }
}

pub fn alloc(self: *Gc, comptime T: anytype, count: usize) ![]T {
    return try self.gpa.alloc(T, count);
}
