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

        input: Definition.Input,
        output: Definition.Output = undefined,
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

test "Graph Node Idea" {
    const EatCheese = struct {
        pub const Input = struct {};

        pub const Output = struct {
            cheese_type: []const u8,
            taste_signature: u8,
            munch_speed: f32,
        };

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
        pub const Input = struct {
            cheese_type: *const []const u8,
            taste_signature: *const u8,
            munch_speed: *f32,
        };

        pub const Output = struct {
            success: bool,
        };

        pub fn run(input: Input) Output {
            if (std.mem.eql(u8, input.cheese_type.*, "guda")) {
                return .{ .success = true };
            } else {
                return .{ .success = false };
            }
        }
    };

    // Declare a graph of nodes to run later...
    const Graph = struct {
        pub var eat_cheese = Node(EatCheese){ .input = .{} };
        pub var feel_full = Node(FeelFull){ .input = .{
            .cheese_type = &eat_cheese.output.cheese_type,
            .taste_signature = &eat_cheese.output.taste_signature,
            .munch_speed = &eat_cheese.output.munch_speed,
        } };
    };

    std.debug.print("{any}\n", .{Graph.feel_full});

    // Or, just call the nodes inline!
    var eat_cheese_result = EatCheese.run(.{});
    const feel_full_result = FeelFull.run(
        linkFields(FeelFull.Input, &eat_cheese_result),
    );

    std.debug.print("{any}\n", .{feel_full_result.success});
}
