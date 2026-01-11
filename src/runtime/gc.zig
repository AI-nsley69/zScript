const std = @import("std");
const zs = @import("../lib.zig");
const tracy = @import("tracy");

const Bytecode = zs.Backend.Bytecode;
const Vm = zs.Runtime.Vm;
const Val = zs.Runtime.Value;

const Value = Val.Value;
const ValueType = Val.ValueType;

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.gc);

pub const Error = error{
    MaxHeapSizeReached,
};

const Errors = (Error || std.mem.Allocator.Error || Val.ConvertError);

const min_heap_size = 1 << 20; // Initialize heap to 1MiB
// const min_heap_size = 400;
const max_heap_size = 2 << 30; // Set max heap size to 2 GiB
const heap_size_multiplier = 2;

const Gc = @This();

gpa: Allocator,
cursor: u64 = 0,
heap: []u8,
vm: ?Vm = null,

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
    log.debug("Final heap size: {d}b", .{self.cursor});
    log.debug("TODO: Discard object schema & functions", .{});

    self.gpa.free(self.heap);
    gpa.destroy(self);
}

// fn next(self: *Gc) ?*Val.BoxedHeader {
//     if (self.cursor >= self.heap.len) return null;
//     const offset = @sizeOf(Val.BoxedHeader);
//     const ptr = self.heap[self.cursor .. self.cursor + offset].ptr;
//     const header_ptr: *Val.BoxedHeader = @ptrCast(@alignCast(ptr));

//     return header_ptr;
// }

fn collectValueList(self: *Gc, list: std.ArrayListUnmanaged(Value)) Errors!void {
    for (0..list.items.len) |idx| {
        const item = list.items[idx];
        if (item != .boxed) continue;
        if (item.boxed.kind != .moved) {
            try self.move(item.boxed);
        }
        const header_ptr: *Val.BoxedHeader = @ptrFromInt(item.boxed.ptr_or_size);
        list.items[idx].boxed = header_ptr;
    }
}

fn collectValueSlice(self: *Gc, slice: []Value) Errors!void {
    for (0..slice.len) |idx| {
        const item = slice[idx];
        if (item != .boxed) continue;
        if (item.boxed.kind != .moved) {
            try self.move(item.boxed);
        }
        const header_ptr: *Val.BoxedHeader = @ptrFromInt(item.boxed.ptr_or_size);
        slice[idx].boxed = header_ptr;
    }
}

fn collect(self: *Gc) Errors!void {
    const current_heap = self.heap;
    const current_size = current_heap.len;
    const current_cursor = self.cursor;
    const new_heap = try self.gpa.alignedAlloc(u8, std.mem.Alignment.of(Val.BoxedHeader), current_size * heap_size_multiplier);
    // VM should be set after parsing + compilation, just double the current heap size and copy it to the new heap
    log.debug("Handle collection when doing parsing / compiling", .{});
    if (self.vm == null) {
        @memcpy(new_heap[0..current_size], self.heap);
        self.heap = new_heap;
        self.gpa.free(current_heap);
        return;
    }
    // If not, we need to collect the garbage
    self.cursor = 0;
    self.heap = new_heap;

    log.debug("Handle collection for call stack, etc", .{});
    try self.collectValueList(self.vm.?.registers);
    try self.collectValueList(self.vm.?.reg_stack);
    try self.collectValueList(self.vm.?.param_stack);
    try self.collectValueSlice(self.vm.?.constants);
    log.debug("Collected {d} bytes", .{current_cursor - self.cursor});
    log.debug("TODO: Maybe shrink heap if usage is low", .{});
    self.alignCursor();
}

fn move(self: *Gc, header: *Val.BoxedHeader) Errors!void {
    const new_header: *Val.BoxedHeader = val: switch (header.kind) {
        .object => {
            const val: Value = .{ .boxed = header };
            const obj = try val.asObj();

            const fields: []Value = obj.fields[0..obj.schema.fields_count];
            for (0..obj.schema.fields_count) |idx| {
                const item = obj.fields[idx];
                if (item != .boxed) continue;

                try self.move(item.boxed);
                const new_field: *Val.BoxedHeader = @ptrFromInt(item.boxed.ptr_or_size);
                fields[idx] = .{ .boxed = new_field };
            }

            const new_val = try self.allocObject(obj);
            break :val new_val.boxed;
        },
        .string => {
            const val: Value = .{ .boxed = header };
            const str = try val.asString(self);
            const new_val = try self.allocString(str);
            break :val new_val.boxed;
        },
        .moved => break :val header,
    };

    header.* = .{ .kind = .moved, .ptr_or_size = @intCast(@intFromPtr(new_header)) };
}

fn alignCursor(self: *Gc) void {
    self.cursor = std.mem.Alignment.of(Val.BoxedHeader).forward(self.cursor);
}

fn allocHeader(self: *Gc, header: Val.BoxedHeader) Errors!*Val.BoxedHeader {
    self.alignCursor();
    const size = @sizeOf(Val.BoxedHeader);
    if (self.cursor + size >= self.heap.len) {
        try self.collect();
    }
    // Get pointer
    const ptr = self.heap[self.cursor..].ptr;
    const header_ptr: *Val.BoxedHeader = @ptrCast(@alignCast(ptr));
    header_ptr.* = header;
    // Increment cursor
    self.cursor += @sizeOf(Val.BoxedHeader);

    return header_ptr;
}

pub fn allocObject(self: *Gc, object: Val.Object) Errors!Value {
    const header: Val.BoxedHeader = .{
        .kind = .object,
        .ptr_or_size = @intCast(@intFromPtr(object.schema)),
    };
    const header_ptr = try self.allocHeader(header);

    self.alignCursor();
    const offset = object.schema.fields_count;
    const size = @sizeOf(Value) * offset;
    if (self.cursor + size >= self.heap.len) {
        try self.collect();
    }

    const heap_ptr = self.heap[self.cursor..].ptr;
    const values: [*]Value = @ptrCast(@alignCast(heap_ptr));
    @memcpy(values[0..offset], object.fields);

    self.cursor += size;

    return .{
        .boxed = header_ptr,
    };
}

pub fn allocString(self: *Gc, string: []const u8) Errors!Value {
    const header: Val.BoxedHeader = .{
        .kind = .string,
        .ptr_or_size = @truncate(string.len),
    };
    const header_ptr = try self.allocHeader(header);

    self.alignCursor();
    const offset = string.len;
    if (self.cursor + offset >= self.heap.len) {
        try self.collect();
    }

    @memcpy(self.heap[self.cursor .. self.cursor + offset], string);
    self.cursor += offset;
    return .{
        .boxed = header_ptr,
    };
}

pub fn allocStringCount(self: *Gc, count: u62) Errors!Value {
    const header: Val.BoxedHeader = .{
        .kind = .string,
        .ptr_or_size = count,
    };
    const header_ptr = try self.allocHeader(header);

    self.alignCursor();
    if (self.cursor + count >= self.heap.len) {
        try self.collect();
    }

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
