const std = @import("std");
const Gc = @import("gc.zig");
const Bytecode = @import("bytecode.zig");

pub const Error = error{
    InvalidType,
    UnknownField,
};

pub const Object = struct {
    pub const Schema = struct {
        fields_count: u64,
        fields: [*:0]const u8,
        methods: [*:0]const u8,
        functions: [*]Bytecode.Function,

        pub fn getFieldIndex(self: *const Schema, name: []const u8) ?u64 {
            var ptr: [*:0]const u8 = self.fields;
            var idx: u64 = 0;
            while (ptr[0] != 0) {
                const field = std.mem.span(ptr);
                if (std.mem.eql(u8, field, name)) {
                    return idx;
                }
                ptr += field.len + 1; // skip over the field data, as well as its sentinel
                idx += 1;
            }
            return null;
        }

        pub fn getMethodIndex(self: *const Schema, name: []const u8) ?u64 {
            var ptr: [*:0]const u8 = self.methods;
            var idx: u64 = 0;
            while (ptr[0] != 0) {
                const method = std.mem.span(ptr);
                if (std.mem.eql(u8, method, name)) {
                    return idx;
                }
                ptr += method.len + 1; // skip over the field data, as well as its sentinel
                idx += 1;
            }
            return null;
        }
    };
    fields: [*]Value,
    schema: *const Schema,
};

pub const BoxedHeader = packed struct(u64) {
    /// if `kind == .string`, this is the length of the string in bytes.
    /// if `kind == .object`, this is a pointer to the object's schema.
    /// if `kind == .moved`, this is a pointer to the boxed value's new location.
    ptr_or_size: u62,
    kind: enum(u2) {
        string,
        object,
        moved,
    },
};

pub const ConvertError = error{ NoSpaceLeft, InvalidType, UnknownField };

pub const ValueType = enum { int, float, boolean, boxed };
pub const Value = union(ValueType) {
    int: i64,
    float: f64,
    boolean: bool,
    boxed: *BoxedHeader,

    // Helper functions
    pub fn asInt(value: Value) !i64 {
        if (value != .int) return Error.InvalidType;
        return value.int;
    }

    pub fn asFloat(value: Value) !f64 {
        if (value != .float) return Error.InvalidType;
        return value.float;
    }

    pub fn asBool(value: Value) !bool {
        if (value != .boolean) return Error.InvalidType;
        return value.boolean;
    }

    pub fn asString(value: Value, gc: *Gc) ![]u8 {
        return switch (value) {
            .int => {
                const num = try Value.asInt(value);
                const count = std.fmt.count("{d}", .{num});
                const val = gc.allocStringCount(@intCast(count));
                const str: []u8 = try Value.asString(val, gc);
                _ = try std.fmt.bufPrint(str, "{d}", .{num});
                return str;
            },
            .float => {
                const num = try Value.asFloat(value);
                const count = std.fmt.count("{d}", .{num});
                const val = gc.allocStringCount(@intCast(count));
                const str: []u8 = try Value.asString(val, gc);
                _ = try std.fmt.bufPrint(str, "{d}", .{num});
                return str;
            },
            .boolean => {
                const boolean = try Value.asBool(value);
                const count = std.fmt.count("{}", .{boolean});
                const val = gc.allocStringCount(@intCast(count));
                const str: []u8 = try Value.asString(val, gc);
                _ = try std.fmt.bufPrint(str, "{}", .{boolean});
                return str;
            },
            .boxed => {
                switch (value.boxed.kind) {
                    .string => {
                        return Value.unboxString(value.boxed);
                    },
                    .object => {
                        std.log.debug("Implement object -> string conversion", .{});
                        unreachable;
                    },
                    else => {
                        unreachable;
                    },
                }
            },
        };
    }

    // Value unboxing
    fn unboxString(header: *BoxedHeader) []u8 {
        std.debug.assert(header.kind == .string);
        const size = header.ptr_or_size;
        var ptr: [*]u8 = @ptrCast(header[1..1]);
        return ptr[0..size];
    }

    pub fn asObj(value: Value) !Object {
        if (value != .boxed) return Error.InvalidType;
        if (value.boxed.kind != .object) return Error.InvalidType;
        return Value.unboxObject(value.boxed);
    }

    fn unboxObject(header: *BoxedHeader) Object {
        std.debug.assert(header.kind == .object);
        const schema: *const Object.Schema = @ptrFromInt(header.ptr_or_size);
        const ptr: [*]Value = @ptrCast(header[1..1]);
        return .{ .fields = ptr, .schema = schema };
    }
};
