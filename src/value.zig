const std = @import("std");
const Gc = @import("gc.zig");
const Bytecode = @import("bytecode.zig");

pub const Error = error{
    InvalidType,
    UnknownField,
};

pub const Object = struct {
    pub const Schema = struct {
        fields: [*:0]const u8,

        pub fn getIndex(self: *const Schema, name: []const u8) ?usize {
            var ptr: [*:0]const u8 = self.fields;
            var idx: usize = 0;
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
    };
    fields: [*]Value,
    functions: []Bytecode.Function,
    schema: *const Schema,
};

pub const ValueType = enum { int, float, boolean, string, object };
pub const Value = union(ValueType) {
    int: i64,
    float: f64,
    boolean: bool,
    string: []u8,
    object: *Object,

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

    pub fn asString(gc: *Gc, value: Value) ![]u8 {
        return switch (value) {
            .int => {
                const num = try Value.asInt(value);
                const count = std.fmt.count("{d}", .{num});
                const str = try gc.alloc(.string, count);
                _ = try std.fmt.bufPrint(str.string, "{d}", .{num});
                return str.string;
            },
            .float => {
                const num = try Value.asFloat(value);
                const count = std.fmt.count("{d}", .{num});
                const str = try gc.alloc(.string, count);
                _ = try std.fmt.bufPrint(str.string, "{d}", .{num});
                return str.string;
            },
            .boolean => {
                const boolean = try Value.asBool(value);
                const count = std.fmt.count("{}", .{boolean});
                const str = try gc.alloc(.string, count);
                _ = try std.fmt.bufPrint(str.string, "{}", .{boolean});
                return str.string;
            },
            .string => value.string,
            else => {
                std.log.debug("Implement object -> string conversion", .{});
                unreachable;
            },
        };
    }

    pub fn asObj(value: Value) !*Object {
        if (value != .object) return Error.InvalidType;
        return value.object;
    }

    // Memory helpers
    pub fn deinit(self: *Value, gc: *Gc) usize {
        return switch (self.*) {
            // Non-heap values
            .int, .float, .boolean => 0,
            .string => {
                defer gc.gpa.free(self.string);
                return self.string.len * 8;
            },
            .object => {
                var freed: usize = 0;

                // Free the field values
                var ptr: [*:0]const u8 = self.object.schema.fields;
                var len: usize = 0;
                while (ptr[0] != 0) {
                    const field = std.mem.span(ptr);
                    ptr += field.len + 1; // skip over the field data, as well as its sentinel
                    len += 1;
                }
                gc.gpa.free(self.object.fields[0..len]);
                freed += len;
                // Free the functions
                freed += @sizeOf([]Bytecode.Function) * self.object.functions.len;
                gc.gpa.free(self.object.functions);
                gc.gpa.destroy(self.object);
                return freed;
            },
        };
    }
};
