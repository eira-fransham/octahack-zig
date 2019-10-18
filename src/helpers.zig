const TypeInfo = @import("builtin").TypeInfo;
const TypeId = @import("builtin").TypeId;

pub fn child(comptime info: TypeInfo) type {
    switch (info) {
        TypeId.Pointer => |i| {
            return i.child;
        },
        TypeId.Array => |i| {
            return i.child;
        },
        else => unreachable,
    }
}

pub fn to_array(comptime slice: var) [slice.len]child(@typeInfo(@typeOf(slice))) {
    var out: [slice.len]child(@typeInfo(@typeOf(slice))) = undefined;
    inline for (slice) |val, i| {
        out[i] = val;
    }
    return out;
}

pub fn map(comptime Out: type, comptime array: var, comptime map_fn: fn (child(@typeInfo(@typeOf(array)))) Out) [array.len]Out {
    var out: [array.len]Out = undefined;
    inline for (array) |val, i| {
        out[i] = map_fn(val);
    }
    return out;
}

