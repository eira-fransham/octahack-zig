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
    pub const Properties = union(enum) {
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

fn Rack(comptime num_components: comptime_int, comptime InnerComponent: type) type {
    const Out = struct {
        const Self = @This();
        const Wire = union(enum) {
            Component: struct {
                tag: usize,
                index: usize,
                output_id: usize,
            },
            Self: usize,
        };
        const WireArray = [InnerComponent.MAX_INPUT_COUNT]?Wire;
        const TaggedComponent = struct {
            tag: usize,
            value: InnerComponent,
            wiring: WireArray,
        };

        pub const Inputs = struct {
            audio: Audio,
            midi: Midi,
        };
        pub const Properties = struct {};
        const OutputWires = struct {
            audio: ?Wire,
            midi: ?Wire,
        };
        components: [num_components]?TaggedComponent,
        outputs: OutputWires,
        current_tag: usize,

        fn next_id(this: *Self) usize {
            const out = this.current_tag;
            this.current_tag += 1;
            return out;
        }

        pub fn new() Self {
            return @This(){
                .components = make_null([num_components]?TaggedComponent),
                .outputs = OutputWires{ .audio = null, .midi = null },
                .current_tag = 0,
            };
        }

        fn get_output(this: *Self, wire: Wire, inputs: Inputs, properties: Properties) ?InnerComponent.Value {
            @panic("unimplemented");
        }

        fn get_audio(this: *Self, inputs: Inputs, properties: Properties) ?Audio {
            if (this.outputs.audio) |audio| {
                const maybe_out_val = this.get_output(audio, inputs, properties);
                if (maybe_out_val) |out_val| {
                    return helpers.try_from_union(Audio, out_val);
                } else {
                    return null;
                }
            } else {
                return null;
            }
        }

        fn get_midi(self: *Self, inputs: Inputs, properties: Properties) ?Midi {
            @panic("unimplemented");
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

    return Component(Out).output("audio", Out.get_audio).output("midi", Out.get_midi);
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
    const MyRack = Rack(8, OctahackComponent);
}
