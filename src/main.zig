const std = @import("std");
const TypeInfo = @import("builtin").TypeInfo;
const TypeId = @import("builtin").TypeId;
const helpers = @import("helpers.zig");
const assert = std.debug.assert;
const component = @import("component.zig");
const Component = component.Component;
const ComponentUnion = component.ComponentUnion;
const OutputInfo = component.OutputInfo;

// TODO: Maybe have audio just be the instantaneous i32, so that way we can combine
//       LFOs and synths.
const Audio = struct {};
const Midi = struct {};

const Something = struct {
    my_field: u8,

    pub const Inputs = struct {
        audio: Audio,
        midi: Midi,
    };
    pub const Properties = struct {
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
                        return EqualFailure{ .path = ([_]Element{Element{ .Index = i }} ++ helpers.to_array(fail.path))[0..], .expected = fail.expected };
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
                            return EqualFailure{ .path = ([_]Element{Element{ .Index = i }} ++ helpers.to_array(fail.path))[0..], .expected = fail.expected };
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
                    return EqualFailure{ .path = ([_]Element{Element{ .Field = field.name }} ++ helpers.to_array(fail.path))[0..], .expected = fail.expected };
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

const SomethingComponent = Component(Something).output("audio", Something.get_audio).output("midi", Something.get_midi);
const OctahackComponent = ComponentUnion(union(enum) {
    Something: SomethingComponent,

    pub const Value = union(enum) {
        Audio: Audio,
        Midi: Midi,
    };

    pub const Inputs = union(enum) {
        Something: SomethingComponent.Inputs,
    };
    pub const Properties = union {
        Something: SomethingComponent.Properties,
    };
});

fn make_null(comptime T: type) T {
    assert(@typeId(T) == TypeId.Array);
    assert(@typeId(T.Child) == TypeId.Optional);

    var out: T = undefined;
    comptime {
        var i = 0;
        while (i < T.len) : (i += 1) {
            out[i] = null;
        }
    }

    return out;
}

fn Rack(comptime num_components: comptime_int, comptime Inputs: type, comptime Outputs: type, comptime InnerComponent: type) type {
    return struct {
        const Self = @This();
        const WireInternal = union(enum) {
            Component: struct {
                tag: usize,
                index: usize,
                output_id: usize,
            },
            Self: usize,
        };
        const WireArray = [InnerComponent.MAX_INPUT_COUNT]?WireInternal;
        const TaggedComponent = struct {
            tag: usize,
            value: InnerComponent,
            wiring: WireArray,
        };

        pub const WireEnd = union(enum) {
            Component: struct {
                index: usize,
                // input ID for input wire end, output ID for output wire end
                id: usize,
            },
            Self: usize,
        };

        components: [num_components]?TaggedComponent,
        output_wires: [@memberCount(Outputs)]?WireInternal,
        current_tag: usize,

        fn next_id(this: *Self) usize {
            const out = this.current_tag;
            this.current_tag += 1;
            return out;
        }

        fn get_input(this: *Self, index: usize, inputs: *const Inputs, properties: *const [num_components]?InnerComponent.Properties) InnerComponent.Inputs {
            var input_array: [InnerComponent.MAX_INPUT_COUNT]InnerComponent.Value = undefined;
            const comp = this.components[index] orelse @panic("unimplemented");
            const inputs_ = comp.value.inputs();
            for (inputs_) |input, i| {
                input_array[i] = this.get_component_output(comp.wiring[i] orelse @panic("unimplemented"), inputs, properties) orelse @panic("unimplemented");
            }

            return comp.value.make_input(input_array[0..inputs_.len]);
        }

        fn get_component_output(this: *Self, read_wire: WireInternal, inputs: *const Inputs, properties: *const [num_components]?InnerComponent.Properties) ?InnerComponent.Value {
            switch (read_wire) {
                WireInternal.Component => |c| {
                    const comp = if (this.components[c.index]) |*i| i else return null;
                    if (comp.tag != c.tag) return null;

                    // TODO: Lazily generate inputs, since we don't necessarily need every input
                    //       for every output
                    // TODO: Cache outputs to allow circular wiring
                    return comp.value.get_output(c.output_id, this.get_input(c.index, inputs, properties), properties[c.index].?);
                },
                WireInternal.Self => |input_id| {
                    inline for (@typeInfo(Inputs).Struct.fields) |field, i| {
                        if (i == input_id) return helpers.to_union(InnerComponent.Value, @field(inputs, field.name));
                    }
                },
            }

            @panic("unimplemented");
        }

        pub fn new() Self {
            return @This(){
                .components = make_null([num_components]?TaggedComponent),
                .output_wires = make_null([@memberCount(Outputs)]?WireInternal),
                .current_tag = 0,
            };
        }

        pub fn wire(input: WireEnd, output: WireEnd) void {
            @panic("unimplemented");
        }

        pub fn outputs(this: *Self, inputs: Inputs, properties: [num_components]?InnerComponent.Properties) Outputs {
            const internal = struct {
                fn or_child(comptime T: type) type {
                    return if (@typeId(T) == TypeId.Optional) T.Child else T;
                }
            };

            var out: Outputs = undefined;
            inline for (@typeInfo(Outputs).Struct.fields) |field, i| {
                if (this.output_wires[i]) |out_wire| {
                    const maybe_out_val = this.get_component_output(out_wire, &inputs, &properties);
                    if (maybe_out_val) |out_val| {
                        @field(out, field.name) = helpers.from_union(internal.or_child(field.field_type), out_val);
                        continue;
                    }
                }

                if (@typeId(field.field_type) == TypeId.Optional) {
                    @field(out, field.name) = null;
                } else {
                    @panic("Unimplemented");
                }
            }
            return out;
        }

        pub fn new_component(this: *Self, index: usize, tag: InnerComponent.ComponentKind) void {
            const tag = this.next_id();
            components[index] = TaggedComponent{
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
                .value = InnerComponent.new(tag),
            };
        }
    };
}

test "Component" {
    const expected = [2]OutputInfo{ OutputInfo{ .name = "midi", .output_type = Midi }, OutputInfo{ .name = "audio", .output_type = Audio } };
    if (does_not_match(SomethingComponent.info(), expected)) |fail| {
        @compileError(fail.msg());
    }

    var my_comp = SomethingComponent.new();
    my_comp.state().my_field = 1;
    std.testing.expect(my_comp.state().my_field == 1);
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

test "Rack" {
    comptime {
        const Inputs = struct {
            audio: Audio,
            midi: Midi,
        };
        const Outputs = struct {
            audio: Audio,
            midi: Midi,
        };
        const MyRack = Rack(8, Inputs, Outputs, OctahackComponent);
        const outputs = MyRack.new().outputs(Inputs{ .audio = Audio{}, .midi = Midi{} }, make_null([8]?OctahackComponent.Properties));
    }
}
