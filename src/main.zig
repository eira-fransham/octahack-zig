const std = @import("std");
const TypeInfo = @import("builtin").TypeInfo;
const TypeId = @import("builtin").TypeId;
const assert = std.debug.assert;

const testing = std.testing;

// TODO: Maybe have audio just be the instantaneous i32, so that way we can combine
//       LFOs and synths.
const Audio = struct {};
const Midi = struct {};

fn child(comptime info: TypeInfo) type {
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

fn to_array(comptime slice: var) [slice.len]child(@typeInfo(@typeOf(slice))) {
    var out: [slice.len]child(@typeInfo(@typeOf(slice))) = undefined;
    inline for (slice) |val, i| {
        out[i] = val;
    }
    return out;
}

fn map(comptime Out: type, comptime array: var, comptime map_fn: fn (child(@typeInfo(@typeOf(array)))) Out) [array.len]Out {
    var out: [array.len]Out = undefined;
    inline for (array) |val, i| {
        out[i] = map_fn(val);
    }
    return out;
}

const OutputInfo = struct {
    name: []const u8,
    output_type: type,
};

fn Component(comptime State: type) type {
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

                    const args: [3]type = map(type, info.args, get_type);
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

const Something = struct {
    my_field: u8,

    const Inputs = struct {
        audio: Audio,
        midi: Midi,
    };
    const Properties = struct {
        foo: u8,
    };

    const Self = @This();

    pub fn new() Self {
        return @This(){
            .my_field = 0,
        };
    }

    fn get_audio(self: *Self, inputs: Inputs, properties: Properties) Audio {
        @panic("unimplemented");
    }

    fn get_midi(self: *Self, inputs: Inputs, properties: Properties) Midi {
        @panic("unimplemented");
    }
};

fn equal(a: var, b: var) bool {
    switch (@typeInfo(@typeOf(a))) {
        TypeId.Array => {
            if (a.len != b.len) {
                return false;
            }
            for (a) |a_val, i| {
                if (!equal(a_val, b[i])) {
                    return false;
                }
            }
        },
        TypeId.Pointer => |info| {
            if (info.size == @typeOf(info).Size.Slice) {
                if (a.len != b.len) {
                    return false;
                }
                for (a) |a_val, i| {
                    if (!equal(a_val, b[i])) {
                        return false;
                    }
                }
            } else {
                return a == b;
            }
        },
        TypeId.Struct => |info| {
            inline for (info.fields) |field| {
                if (!equal(@field(a, field.name), @field(b, field.name))) {
                    return false;
                }
            }
        },
        else => {
            return a == b;
        },
    }

    return true;
}

const Element = union(enum) {
    Index: comptime_int,
    Field: []const u8,
};

const Expected = struct {
    expected: []const u8,
    found: []const u8,
};

const EqualFailure = struct {
    path: []const Element,
    expected: ?Expected,

    const Self = @This();

    fn msg(comptime this: Self) []const u8 {
        var out: []const u8 = "assertion failed at `this";
        for (this.path) |piece| {
            switch (piece) {
                Element.Index => |i| {
                    out = out ++ "[" ++ "some index" ++ "]";
                },
                Element.Field => |name| {
                    out = out ++ "." ++ name;
                },
            }
        }
        out = out ++ "`";
        if (this.expected) |expected| {
            out = out ++ ". Expected: " ++ expected.expected ++ ", found " ++ expected.found;
        }
        return out;
    }
};

fn does_not_match(comptime a: var, comptime b: var) ?EqualFailure {
    switch (@typeInfo(@typeOf(a))) {
        TypeId.Array => |info| {
            if (a.len != b.len) {
                return EqualFailure{ .path = ([_]Element{})[0..], .expected = null };
            }
            inline for (a) |a_val, i| {
                if (info.child == u8) {
                    if (a_val != b[i]) {
                        return EqualFailure{ .path = ([_]Element{})[0..], .expected = Expected{ .expected = b, .found = .a } };
                    }
                } else {
                    if (does_not_match(a_val, b[i])) |fail| {
                        return EqualFailure{ .path = ([_]Element{Element{ .Index = i }} ++ to_array(fail.path))[0..], .expected = fail.expected };
                    }
                }
            }
        },
        TypeId.Pointer => |info| {
            if (info.size == @typeOf(info).Size.Slice) {
                if (a.len != b.len) {
                    if (info.child == u8) {
                        return EqualFailure{ .path = ([_]Element{})[0..], .expected = Expected{ .expected = b, .found = a } };
                    } else {
                        return EqualFailure{ .path = ([_]Element{})[0..], .expected = null };
                    }
                }
                inline for (a) |a_val, i| {
                    if (info.child == u8) {
                        if (a_val != b[i]) {
                            return EqualFailure{ .path = ([_]Element{})[0..], .expected = Expected{ .expected = b, .found = a } };
                        }
                    } else {
                        if (does_not_match(a_val, b[i])) |fail| {
                            return EqualFailure{ .path = ([_]Element{Element{ .Index = i }} ++ to_array(fail.path))[0..], .expected = fail.expected };
                        }
                    }
                }
            } else {
                return a == b;
            }
        },
        TypeId.Struct => |info| {
            inline for (info.fields) |field| {
                if (does_not_match(@field(a, field.name), @field(b, field.name))) |fail| {
                    return EqualFailure{ .path = ([_]Element{Element{ .Field = field.name }} ++ to_array(fail.path))[0..], .expected = fail.expected };
                }
            }
        },
        else => {
            if (a != b) {
                return EqualFailure{ .path = ([_]Element{})[0..], .expected = null };
            }
        },
    }

    return null;
}

fn ComponentUnion(comptime T: type) type {
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
                    return map(ValueInfo, field.field_type.info(), outputinfo_to_valueinfo)[0..];
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

const SomethingComponent = Component(Something).output("audio", Something.get_audio).output("midi", Something.get_midi);
const OctahackComponent = ComponentUnion(union(enum) {
    Something: SomethingComponent,

    const Value = union(enum) {
        Audio: Audio,
        Midi: Midi,
    };
});

fn make_null(comptime T: type) T {
    assert(@typeId(T) == TypeId.Array);
    assert(@typeId(T.Child) == TypeId.Optional);

    var out: T = undefined;
    
    inline for (out) |*val| {
        *val = null;
    }
   
    return out;
}

fn Track(comptime num_components: comptime_int, comptime Component: type) type {
    return struct {
        const ComponentSpecifier = union(enum) {
            Component: struct {
                tag: usize,
                index: usize,
            },
            Self,
        };
        const Wire = struct {
            component: ComponentSpecifier,
            output_id: usize,
        };
        const WireArray = [Component.MAX_INPUT_COUNT]?Wire;
        const TaggedComponent = struct {
            tag: usize,
            value: Component,
            wiring: WireArray,
        };

        components: [num_components]?TaggedComponent,
        current_tag: usize,

        fn next_id(this: *Self) usize {
            const out = this.current_tag;
            this.current_tag += 1;
            return out;
        }

        pub fn new_component(this: *Self, index: usize, tag: Component.ComponentKind) void {
            const tag = this.next_id();
            components[index] = TaggedComponent {
                .tag = tag,
                // TODO: Default wiring. Possibilities:
                //       - Search backwards through components until finding the first same-typed
                //         output for each input
                //       - The same, but with each input opting in/out from having a default wiring
                //         at all
                //       - Some generic and convenient way for components to specify preferred wirings
                //         (f.e. by output name?)
                // TODO: Wiring for properties (for LFOs etc).
                .wiring = make_null(WireArray),
                .value = Component.new(tag),
            };
        }
    };
}

test "Component" {
    const expected = [2]OutputInfo{ OutputInfo{ .name = "audio", .output_type = Audio }, OutputInfo{ .name = "midi", .output_type = Midi } };
    if (does_not_match(SomethingComponent.info(), expected)) |fail| {
        @compileError(fail.msg());
    }

    var my_comp = SomethingComponent.new();
    my_comp.state().my_field = 1;
    testing.expect(my_comp.state().my_field == 1);
}

test "ComponentUnion" {
    comptime {
        if (does_not_match(OctahackComponent.components(), [1]OctahackComponent.ComponentInfo{OctahackComponent.ComponentInfo{ .name = "Something", .variant = OctahackComponent.ComponentKind.Something }})) |fail| {
            @compileError(fail.msg());
        }

        const my_comp = OctahackComponent.make(OctahackComponent.ComponentKind.Something);

        const anything = my_comp.inputs();
        const anything_else = my_comp.outputs();
    }
}
