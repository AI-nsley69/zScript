pub const Error = error{
    InvalidType,
};

pub const ValueType = enum {
    int,
    float,
    boolean,
    string,
};

pub const Value = union(ValueType) {
    int: i64,
    float: f64,
    boolean: bool,
    string: []u8,

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

    pub fn asString(value: Value) ![]u8 {
        if (value != .string) return Error.InvalidType;
        return value.string;
    }
};
