pub const ValueType = enum {
    int,
    float,
    // string,
    boolean,
};

pub const Value = union(ValueType) {
    int: i64,
    float: f64,
    // string: []const u8,
    boolean: bool,
};
