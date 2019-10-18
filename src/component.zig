const std = @import("std");
const TypeInfo = @import("builtin").TypeInfo;
const TypeId = @import("builtin").TypeId;
const assert = std.debug.assert;
const helpers = @import("helpers.zig");

pub const OutputInfo = struct {
    name: []const u8,
    output_type: type,
};

pub fn Component(comptime State: type) type {
    assert(@hasDecl(State, "new"));
    assert(@typeOf(State.new) == fn () State);
    assert(@hasDecl(State, "Inputs"));
    assert(@typeOf(State.Inputs) == type);
    assert(@hasDecl(State, "Properties"));
    assert(@typeOf(State.Properties) == type);

    const ComponentWrapper = struct {
        const Nil = struct {
            internal_state: State,

            pub const Inputs = State.Inputs;
            pub const Properties = State.Properties;

            const Self = @This();

            pub fn state(this: *Self) *State {
                return &this.internal_state;
            }

            pub fn new() Self {
                return Self{ .internal_state = State.new() };
            }

            pub fn output(comptime name_: []const u8, comptime get_: var) type {
                return Outputs(name_, get_, @This());
            }

            pub fn info() comptime [0]OutputInfo {
                return [_]OutputInfo{};
            }
        };

        fn get_type(comptime val: TypeInfo.FnArg) type {
            return val.arg_type.?;
        }

        fn Outputs(comptime name: []const u8, comptime get: var, comptime Rest: type) type {
            const get_typeinfo = @typeInfo(@typeOf(get));
            switch (get_typeinfo) {
                TypeId.Fn, TypeId.BoundFn => |info| {
                    if (info.return_type == null) @panic("Invalid type for `get` function");

                    const args: [3]type = helpers.map(type, info.args, get_type);
                    assert(args[0] == *State);
                    assert(args[1] == State.Inputs);
                    assert(args[2] == State.Properties);
                },
                else => {
                    @panic("Invalid type for `get` function");
                },
            }
            return struct {
                rest: Rest,

                pub const Inputs = State.Inputs;
                pub const Properties = State.Properties;

                const Self = @This();

                const Rest: type = Rest;

                pub fn new() Self {
                    return Self{
                        .rest = Rest.new(),
                    };
                }

                pub fn state(this: *Self) *State {
                    return this.rest.state();
                }

                pub fn output(comptime name_: []const u8, comptime get_: var) type {
                    return Outputs(name_, get_, @This());
                }

                pub fn info() comptime [@typeOf(Rest.info).ReturnType.len + 1]OutputInfo {
                    const info_list = [1]OutputInfo{OutputInfo{ .name = name, .output_type = @typeOf(get).ReturnType }};
                    return Rest.info() ++ info_list;
                }
            };
        }
    };

    return ComponentWrapper.Nil;
}

pub fn ComponentUnion(comptime T: type) type {
    assert(@hasDecl(T, "Value"));
    assert(@typeOf(T.Value) == type);

    return struct {
        value: T,

        const Self = @This();

        fn get_max_input_count() comptime_int {
            var max = 0;
            inline for (@typeInfo(T).Union.fields) |field| {
                const num_inputs = @typeInfo(field.Inputs).Struct.fields.len;
                if (num_inputs > max) max = num_inputs;
            }
            return max;
        }

        pub const MAX_INPUT_COUNT = get_max_input_count();

        pub const ValueKind = @TagType(T.Value);
        pub const ValueInfo = struct {
            name: []const u8,
            kind: ValueKind,
        };

        pub const ComponentKind = @TagType(T);
        pub const ComponentInfo = struct {
            name: []const u8,
            variant: ComponentKind,
        };

        fn union_tag_for(comptime Enum: type, comptime Ty: type) @TagType(Enum) {
            comptime {
                var out: ?@TagType(Enum) = null;

                inline for (@typeInfo(Enum).Union.fields) |field| {
                    if (field.field_type == Ty) {
                        if (out != null) {
                            @compileError("Union " ++ @typeName(Enum) ++ " contains type " ++ @typeName(Ty) ++ " more than once (second field: " ++ field.name ++ ")");
                        }
                        out = @intToEnum(@TagType(Enum), field.enum_field.?.value);
                    }
                }

                if (out) |tag| {
                    return tag;
                } else {
                    @compileError("Union " ++ @typeName(Enum) ++ " doesn't contain type " ++ @typeName(Ty));
                }
            }
        }

        fn to_input_list(comptime Variant: type) [@typeInfo(Variant).Struct.fields.len]ValueInfo {
            var out: [@typeInfo(Variant).Struct.fields.len]ValueInfo = undefined;

            inline for (@typeInfo(Variant).Struct.fields) |field, i| {
                out[i] = ValueInfo{ .name = field.name, .kind = union_tag_for(T.Value, field.field_type) };
            }

            return out;
        }

        pub fn components() [@typeInfo(T).Union.fields.len]ComponentInfo {
            var out: [@typeInfo(T).Union.fields.len]ComponentInfo = undefined;

            inline for (@typeInfo(T).Union.fields) |field, i| {
                out[i] = ComponentInfo{
                    .name = field.name,
                    .variant = @intToEnum(ComponentKind, field.enum_field.?.value),
                };
            }

            return out;
        }

        pub fn inputs(this: *const Self) []const ValueInfo {
            inline for (@typeInfo(T).Union.fields) |field| {
                if (@enumToInt(this.value) == field.enum_field.?.value) {
                    return to_input_list(field.field_type.Inputs)[0..];
                }
            }

            unreachable;
        }

        fn outputinfo_to_valueinfo(comptime info: OutputInfo) ValueInfo {
            return ValueInfo{
                .name = info.name,
                .kind = union_tag_for(T.Value, info.output_type),
            };
        }

        pub fn outputs(this: *const Self) []const ValueInfo {
            inline for (@typeInfo(T).Union.fields) |field| {
                if (@enumToInt(this.value) == field.enum_field.?.value) {
                    return helpers.map(ValueInfo, field.field_type.info(), outputinfo_to_valueinfo)[0..];
                }
            }

            unreachable;
        }

        pub fn make(variant: ComponentKind) Self {
            inline for (@typeInfo(T).Union.fields) |field, i| {
                if (variant == @intToEnum(ComponentKind, field.enum_field.?.value)) {
                    return Self{ .value = @unionInit(T, field.name, field.field_type.new()) };
                }
            }

            unreachable;
        }
    };
}
