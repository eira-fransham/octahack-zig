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

pub fn union_variant_for(comptime Union: type, comptime Ty: type) UnionVariant(@TagType(Union)) {
    comptime {
        var out: ?UnionVariant(@TagType(Union)) = null;

        inline for (@typeInfo(Union).Union.fields) |field| {
            if (field.field_type == Ty) {
                if (out != null) {
                    @compileError("Union " ++ @typeName(Union) ++ " contains type " ++ @typeName(Ty) ++ " more than once (second field: " ++ field.name ++ ")");
                }
                out = UnionVariant(@TagType(Union)){
                    .name = field.name,
                    .tag = @intToEnum(@TagType(Union), field.enum_field.?.value),
                };
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
    const variant = comptime union_variant_for(@typeOf(union_), Type);
    const itag = comptime @enumToInt(variant.tag);
    const vname = comptime variant.name;

    if (@enumToInt(union_) == itag) {
        return @field(union_, vname);
    } else {
        return null;
    }
}
