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
        methods: [*:0]const u8,

        pub fn getFieldIndex(self: *const Schema, name: []const u8) ?usize {
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

        pub fn getMethodIndex(self: *const Schema, name: []const u8) ?usize {
            var ptr: [*:0]const u8 = self.methods;
            var idx: usize = 0;
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
    functions: [*]Bytecode.Function,
    schema: *const Schema,
};

pub const ValueType = enum { int, float, boolean, string, object };
pub const Value = union(ValueType) {
    int: i64,
    float: f64,
    boolean: bool,
    string: []u8,
    object: *Object,

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
                std.log.debug("TODO: Free field values", .{});
                // for (self.object.fields) |field| {
                //     freed += field.deinit(gc);
                // }
                // freed += @sizeOf([*]Value);
                // gc.gpa.free(self.object.fields);
                freed += @sizeOf([]Bytecode.Function) * self.object.functions.len;
                gc.gpa.free(self.object.functions);
                gc.gpa.destroy(self.object);
                return freed;
            },
        };
    }

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
                var field_ptr: [*:0]const u8 = self.object.schema.fields;
                var field_len: usize = 0;
                while (field_ptr[0] != 0) {
                    const field = std.mem.span(field_ptr);
                    field_ptr += field.len + 1; // skip over the field data, as well as its sentinel
                    freed += field.len + 1;
                    field_len += 1;
                }
                gc.gpa.free(self.object.fields[0..field_len]);
                var method_ptr: [*:0]const u8 = self.object.schema.methods;
                var method_len: usize = 0;
                while (method_ptr[0] != 0) {
                    const method = std.mem.span(method_ptr);
                    method_ptr += method.len + 1;
                    freed += method.len + 1;
                    method_len += 1;
                }
                for (self.object.functions[0..method_len]) |method| {
                    gc.gpa.free(method.body);
                }
                gc.gpa.free(self.object.functions[0..method_len]);
                gc.gpa.destroy(self.object);
                return freed;
            },
        };
    }
};
