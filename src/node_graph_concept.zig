const std = @import("std");

/// Takes a Node type and calls the run function on it, returning the result of output.
/// This makes using nodes as pure functions more ergonomic.
pub fn callNode(node: anytype) @TypeOf(node).Definition.Output {
    const output = @TypeOf(node).Definition.run(node.input);
    return output;
}

fn Node(InputDefinition: type) type {
    return struct {
        pub const Definition = InputDefinition;

        in: Definition.Input,
        out: Definition.Output = undefined,
    };
}

fn GraphInput(InputDefinition: type) InputDefinition {
    return undefined;
}

fn GraphStore(InputDefinition: type) type {
    return struct {
        pub const Definition = InputDefinition;

        pub const Input = reference_fields: {
            var fields: []const std.builtin.Type.StructField = &.{};
            for (@typeInfo(Definition).Struct.fields) |field| {
                fields = fields ++ .{std.builtin.Type.StructField{
                    .name = field.name,
                    .type = @Type(std.builtin.Type{ .Pointer = .{
                        .size = .One,
                        .is_const = true,
                        .child = field.type,
                        .is_volatile = false,
                        .address_space = .generic,
                        .sentinel = null,
                        .alignment = 0,
                        .is_allowzero = false,
                    } }),
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field.type),
                }};
            }
            break :reference_fields @Type(std.builtin.Type{ .Struct = .{
                .layout = .auto,
                .fields = fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };

        pub const out: Definition = undefined;
    };
}

fn linkFields(T: type, fields_to_link: anytype) T {
    switch (@typeInfo(
        @TypeOf(fields_to_link),
    )) {
        else => @compileError("Expected pointer type"),
        .Pointer => |pointer| switch (@typeInfo(pointer.child)) {
            else => @compileError("Expected struct type"),
            .Struct => |s| {
                var result: T = undefined;
                inline for (s.fields) |field| {
                    @field(result, field.name) = &@field(fields_to_link, field.name);
                }
                return result;
            },
        },
    }
}

// test "Graph Node Idea" {
pub fn main() void {
    const EatCheese = struct {
        pub const Input = struct {
            thinger: *const u32,
            munch_speed: *const f32,
        };
        pub const Output = struct { cheese_type: []const u8, taste_signature: u8, munch_speed: f32 };
        pub fn run(input: Input) Output {
            _ = input;
            return Output{
                .cheese_type = "guda",
                .taste_signature = '%',
                .munch_speed = 1.0,
            };
        }
    };

    const FeelFull = struct {
        pub const Input = struct { cheese_type: *const []const u8, taste_signature: *const u8, munch_speed: *const f32 };
        pub const Output = struct { is_full: bool };
        pub fn run(input: Input) Output {
            if (std.mem.eql(u8, input.cheese_type.*, "guda")) {
                return Output{ .is_full = true };
            } else {
                return Output{ .is_full = false };
            }
        }
    };

    // Declare a graph of nodes to run later...
    const Graph = struct {
        pub const input = GraphInput(struct { thinger: u32 });
        pub const nodes = struct {
            pub const eat_cheese = Node(EatCheese){ .in = .{ .thinger = &input.thinger, .munch_speed = &store.out.munch_speed } };
            pub const feel_full = Node(FeelFull){ .in = .{
                .cheese_type = &eat_cheese.out.cheese_type,
                .taste_signature = &eat_cheese.out.taste_signature,
                .munch_speed = &eat_cheese.out.munch_speed,
            } };
        };

        // These two definitions for store and next_store need to be seperate since otherwise there's a dependency loop :/
        pub const store = GraphStore(struct {
            munch_speed: f32,
        });
        pub const next_store = store.Input{
            .munch_speed = &nodes.eat_cheese.out.munch_speed,
        };
        // Easiest to just keep them side-by-side and hope that I won't go crazy with refactoring!

        pub const output = .{ .munch_speed = &nodes.feel_full.out.is_full };
    };

    std.debug.print("{any}\n", .{Graph.next_store});

    // Or, just call the nodes inline!
    var eat_cheese_result = EatCheese.run(.{ .thinger = &0, .munch_speed = &0.0 });
    const feel_full_result = FeelFull.run(
        linkFields(FeelFull.Input, &eat_cheese_result),
    );

    std.debug.print("{any}\n", .{feel_full_result.is_full});
}
