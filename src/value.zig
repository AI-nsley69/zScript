pub const ValueType = enum {
    int,
    float,
    boolean,
};

pub const Value = union(ValueType) {
    int: i64,
    float: f64,
    boolean: bool,
};
