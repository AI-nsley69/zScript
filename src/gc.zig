const std = @import("std");
const Bytecode = @import("bytecode.zig");
const Vm = @import("vm.zig");
const Val = @import("value.zig");

const tracy = @import("tracy");

const Value = Val.Value;
const ValueType = Val.ValueType;

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.gc);

const min_heap_size = 1 << 20; // Initialize heap to 1MiB
const max_heap_size = 2 << 30; // Set max heap size to 2 GiB

const Gc = @This();

gpa: Allocator,
cursor: u64 = 0,
heap: []u8,

pub fn init(gpa: Allocator) !*Gc {
    // Init itself as a pointer
    const gc = try gpa.create(Gc);
    // Create the heap
    const allocator = std.heap.page_allocator;
    const heap = try allocator.alignedAlloc(u8, std.mem.Alignment.of(Val.BoxedHeader), min_heap_size);
    gc.* = .{
        .gpa = allocator,
        .heap = heap,
    };

    return gc;
}

pub fn deinit(self: *Gc, gpa: Allocator) void {
    self.gpa.free(self.heap);
    gpa.destroy(self);
}

// pub fn markRoots(self: *Gc, vm: *Vm) !void {
//     const tr = tracy.trace(@src());
//     defer tr.end();
//     for (1..vm.metadata().reg_size) |i| {
//         const value = vm.registers.items[i];
//         try self.markValue(value);
//     }

//     log.debug("TODO: Mark registers & params in stack.", .{});
//     for (vm.reg_stack.items) |reg| {
//         try self.markValue(reg);
//     }

//     for (vm.param_stack.items) |param| {
//         try self.markValue(param);
//     }

//     for (vm.constants) |constant| {
//         try self.markValue(constant);
//     }
//     log.debug("Marked {d} roots.", .{self.marked.capacity()});
// }

// fn markValue(self: *Gc, value: Value) !void {
//     switch (value) {
//         // No heap allocations done for these values
//         .int, .float, .boolean => {},
//         .string => try self.marked.put(@intFromPtr(value.string.ptr), undefined),
//         .object => {
//             // Mark the fields and their values
//             var field_ptr: [*:0]const u8 = value.object.schema.fields;
//             // Calculate field len
//             var field_len: u64 = 0;
//             while (field_ptr[0] != 0) {
//                 const field = std.mem.span(field_ptr);
//                 field_ptr += field.len + 1;
//                 field_len += 1;
//             }
//             // Mark each field
//             for (value.object.fields[0..field_len]) |field| {
//                 try self.markValue(field);
//             }
//             // Mark self as used
//             try self.marked.put(@intFromPtr(value.object), undefined);
//         },
//     }
// }

// pub fn sweep(self: *Gc) !void {
//     const tr = tracy.trace(@src());
//     defer tr.end();
//     // If there's nothing on the heap, then exit.
//     if (self.allocated.items.len < 1) return;

//     var idx_to_remove = std.ArrayListUnmanaged(u64){};
//     defer idx_to_remove.deinit(self.gpa);

//     for (0..self.allocated.items.len) |i| {
//         const elem = self.allocated.items[i];

//         const ptr = switch (elem) {
//             .boolean, .float, .int => unreachable,
//             .string => @intFromPtr(elem.string.ptr),
//             .object => @intFromPtr(elem.object),
//         };
//         if (self.marked.contains(ptr)) continue;
//         try idx_to_remove.append(self.gpa, i);
//     }

//     // Deallocate found indexes
//     var freed_bytes: u64 = 0;
//     for (idx_to_remove.items) |elem| {
//         freed_bytes += self.free(self.allocated.items[elem], elem);
//         _ = self.allocated.swapRemove(elem);
//     }

//     self.allocated_bytes -= freed_bytes;
//     if (self.allocated_bytes >= self.size_threshold) self.size_threshold *= 2;
//     self.marked.clearRetainingCapacity();
// }

// pub fn alloc(self: *Gc, value_type: ValueType, count: u64, alignt) !Value {
//     const ptr = self.heap[self.cursor..].ptr;
//     const val: Value = val: switch (value_type) {
//         // Non-heap items do not need to allocated
//         .int, .float, .boolean => unreachable,
//         // Items on the heapl
//         .string => {
//             const str = try self.gpa.alloc(u8, count);
//             self.allocated_bytes += count;
//             break :val .{ .string = str };
//         },
//         .object => unreachable,
//     };
//     return val;
// }

fn alignCursor(self: *Gc) void {
    self.cursor = std.mem.Alignment.of(Val.BoxedHeader).forward(self.cursor);
}

fn allocHeader(self: *Gc, header: Val.BoxedHeader) *Val.BoxedHeader {
    log.debug("TODO: Implement alloc check, move & collect", .{});
    // Get pointer
    self.alignCursor();
    const ptr = self.heap[self.cursor..].ptr;
    const header_ptr: *Val.BoxedHeader = @ptrCast(@alignCast(ptr));
    header_ptr.* = header;
    // Increment cursor
    self.cursor += @sizeOf(Val.BoxedHeader);

    return header_ptr;
}

pub fn allocObject(self: *Gc, object: Val.Object) Value {
    const header: Val.BoxedHeader = .{
        .kind = .object,
        .ptr_or_size = @intCast(@intFromPtr(object.schema)),
    };
    const header_ptr = self.allocHeader(header);

    self.alignCursor();
    const heap_ptr = self.heap[self.cursor..].ptr;
    const values: [*]Value = @ptrCast(@alignCast(heap_ptr));
    const offset = object.schema.fields_count;
    @memcpy(values[0..offset], object.fields);
    self.cursor += @sizeOf(Value) * offset;

    return .{
        .boxed = header_ptr,
    };
}

pub fn allocString(self: *Gc, string: []const u8) Value {
    const header: Val.BoxedHeader = .{
        .kind = .string,
        .ptr_or_size = @truncate(string.len),
    };
    const header_ptr = self.allocHeader(header);

    self.alignCursor();
    const offset = string.len;
    @memcpy(self.heap[self.cursor .. self.cursor + offset], string);
    self.cursor += offset;
    return .{
        .boxed = header_ptr,
    };
}

pub fn allocStringCount(self: *Gc, count: u62) Value {
    const header: Val.BoxedHeader = .{
        .kind = .string,
        .ptr_or_size = count,
    };
    const header_ptr = self.allocHeader(header);

    self.alignCursor();
    self.cursor += count;

    return .{
        .boxed = header_ptr,
    };
}

// pub fn dupe(self: *Gc, value: Value) !Value {
//     const val: Value = val: switch (value) {
//         // Should never be on the heap
//         .boolean, .int, .float => unreachable,
//         .string => {
//             const str = try self.gpa.dupe(u8, value.string);
//             self.allocated_bytes += str.len;
//             break :val .{ .string = str };
//         },
//         .object => {
//             const old = value.object;
//             // Reuse the old functions
//             const functions = old.functions;
//             const fields = try old.fields.clone(self.gpa);

//             const it = fields.iterator();
//             var next = it.next();
//             while (next != null) : (next = it.next()) {
//                 self.allocated_bytes += next.?.key_ptr.len;
//             }

//             break :val .{ .object = .{
//                 .fields = fields,
//                 .functions = functions,
//             } };
//         },
//     };
//     try self.allocated.append(self.gpa, val);
//     return val;
// }
