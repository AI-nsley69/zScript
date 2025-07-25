pub const Error = error{
    InvalidType,
};

pub const ValueType = enum {
    int,
    float,
    boolean,
};

pub const Value = union(ValueType) {
    int: i64,
    float: f64,
    boolean: bool,
    // string: *[]const u8,

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
};
