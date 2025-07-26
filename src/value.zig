const std = @import("std");
const Gc = @import("gc.zig");
const Bytecode = @import("bytecode.zig");

pub const Error = error{
    InvalidType,
};

pub const Object = struct {
    fields: std.StringHashMap(Value),
    functions: []Bytecode.Function,
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
};
