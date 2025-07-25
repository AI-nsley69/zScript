const std = @import("std");
const Vm = @import("vm.zig");
const Val = @import("value.zig");

const tracy = @import("tracy");

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

pub fn init(gpa: Allocator) !*Gc {
    const gc = try gpa.create(Gc);
    gc.* = .{
        .gpa = gpa,
        .marked = std.AutoHashMap(usize, void).init(gpa),
    };

    return gc;
}

pub fn deinit(self: *Gc) void {
    log.debug("Deallocating {d} bytes, from {d} elements", .{ self.allocated_bytes, self.allocated.items.len });
    for (self.allocated.items) |item| {
        _ = self.free(item, null);
    }
    self.allocated.deinit(self.gpa);
    self.marked.deinit();
    self.gpa.destroy(self);
}

pub fn markRoots(self: *Gc, vm: *Vm) !void {
    const tr = tracy.trace(@src());
    defer tr.end();
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
    const tr = tracy.trace(@src());
    defer tr.end();
    // If there's nothing on the heap, then exit.
    if (self.allocated.items.len < 1) return;

    var idx_to_remove = std.ArrayListUnmanaged(usize){};
    defer idx_to_remove.deinit(self.gpa);

    for (0..self.allocated.items.len) |i| {
        const elem = self.allocated.items[i];

        const ptr = switch (elem) {
            .boolean, .float, .int => unreachable,
            .string => @intFromPtr(elem.string.ptr),
        };
        if (self.marked.contains(ptr)) continue;
        try idx_to_remove.append(self.gpa, i);
    }

    // Deallocate found indexes
    var freed_bytes: usize = 0;
    for (idx_to_remove.items) |elem| {
        freed_bytes += self.free(self.allocated.items[elem], elem);
        _ = self.allocated.swapRemove(elem);
    }

    self.allocated_bytes -= freed_bytes;
    if (self.allocated_bytes >= self.size_threshold) self.size_threshold *= 2;
    self.marked.clearRetainingCapacity();
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
