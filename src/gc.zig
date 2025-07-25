const std = @import("std");
const Vm = @import("vm.zig");
const Val = @import("value.zig");
const Value = Val.Value;
const ValueType = Val.ValueType;

const log = std.log.scoped(.gc);

const Allocator = std.mem.Allocator;

const Gc = @This();

gpa: Allocator,
allocated_bytes: usize = 0,
size_threshold: usize = 1024 * 1024,
allocated: std.ArrayListUnmanaged(Value) = std.ArrayListUnmanaged(Value){},
marked: std.AutoHashMap(usize, void),

pub fn init(gpa: Allocator) !Gc {
    return .{
        .gpa = gpa,
        .marked = std.AutoHashMap(usize, void).init(gpa),
    };
}

pub fn deinit(self: *Gc) void {
    self.marked.deinit();
    log.debug("Deallocating {d} elements.", .{self.allocated.items.len});
    for (self.allocated.items) |elem| {
        _ = self.free(elem, null);
    }
    self.allocated.deinit(self.gpa);
}

pub fn markRoots(self: *Gc, vm: *Vm) !void {
    for (1..vm.metadata().reg_size) |i| {
        const value = vm.registers.items[i];
        try self.markValue(value);
    }

    for (vm.constants) |constant| {
        try self.markValue(constant);
    }
    log.debug("Marked {d} roots.", .{self.marked.capacity()});
}

fn markValue(self: *Gc, value: Value) !void {
    switch (value) {
        // No heap allocations done for these values
        .int, .float, .boolean => {},
        .string => try self.marked.put(@intFromPtr(value.string.ptr), undefined),
    }
}

pub fn sweep(self: *Gc) !void {
    // Traverse the list backwards to remove issues with removing items
    var removed_bytes: usize = 0;
    for (self.allocated.items.len - 1..0) |i| {
        const elem = self.allocated.items[i];

        const ptr = switch (elem) {
            .boolean, .float, .int => unreachable,
            .string => @intFromPtr(elem.string.ptr),
        };
        if (self.marked.contains(ptr)) continue;

        removed_bytes += self.free(elem, i);
    }
    log.debug("Removed {d} bytes", .{removed_bytes});
    self.allocated_bytes -= removed_bytes;
    if (self.allocated_bytes >= self.size_threshold) self.size_threshold *= 2;
}

fn free(self: *Gc, value: Value, idx: ?usize) usize {
    if (idx != null) _ = self.allocated.orderedRemove(idx.?);

    return blk: switch (value) {
        .boolean, .float, .int => unreachable,
        .string => {
            self.gpa.free(value.string);
            break :blk value.string.len * 8;
        },
    };
}

pub fn alloc(self: *Gc, value_type: ValueType, count: usize) !Value {
    const val: Value = val: switch (value_type) {
        // Non-heap items do not need to allocated
        .int, .float, .boolean => unreachable,
        // Items on the heapl
        .string => {
            const str = try self.gpa.alloc(u8, count);
            self.allocated_bytes += count;
            break :val .{ .string = str };
        },
    };
    try self.allocated.append(self.gpa, val);
    return val;
}
