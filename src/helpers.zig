const std = @import("std");
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

pub fn UnionVariant(comptime TagType: type) type {
    return struct {
        name: []const u8,
        tag: TagType,
    };
}

pub fn union_variant_for(comptime Union: type, comptime Ty: type) @TagType(Union) {
    comptime {
        var out: ?@TagType(Union) = null;

        inline for (@typeInfo(Union).Union.fields) |field| {
            if (field.field_type == Ty) {
                if (out != null) {
                    @compileError("Union " ++ @typeName(Union) ++ " contains type " ++ @typeName(Ty) ++ " more than once (second field: " ++ field.name ++ ")");
                }
                out = @intToEnum(@TagType(Union), field.enum_field.?.value);
            }
        }

        if (out) |tag| {
            return tag;
        } else {
            @compileError("Union " ++ @typeName(Union) ++ " doesn't contain type " ++ @typeName(Ty));
        }
    }
}

pub fn union_field_for(comptime Union: type, comptime Ty: type) []const u8 {
    comptime {
        var out: ?[]const u8 = null;

        inline for (@typeInfo(Union).Union.fields) |field| {
            if (field.field_type == Ty) {
                if (out != null) {
                    @compileError("Union " ++ @typeName(Union) ++ " contains type " ++ @typeName(Ty) ++ " more than once (second field: " ++ field.name ++ ")");
                }
                out = field.name;
            }
        }

        if (out) |tag| {
            return tag;
        } else {
            @compileError("Union " ++ @typeName(Union) ++ " doesn't contain type " ++ @typeName(Ty));
        }
    }
}
pub fn to_union(comptime Union: type, value: var) Union {
    return @unionInit(Union, union_variant_for(Union, @typeOf(value)).name, value);
}

pub fn from_union(comptime Type: type, union_: var) Type {
    return try_from_union(Type, union_).?;
}

pub fn try_from_union(comptime Type: type, union_: var) ?Type {
    const itag = comptime union_variant_for(@typeOf(union_), Type);
    const vname = comptime union_field_for(@typeOf(union_), Type);

    if (@enumToInt(union_) == @enumToInt(itag)) {
        return @field(union_, vname);
    } else {
        return null;
    }
}

test "comptime" {
    const Test = union(enum) {
        A: u32,
        B: u16,
    };

    std.testing.expect(try_from_union(u32, Test{ .A = 5 }).? == 5);
}
