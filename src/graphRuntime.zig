// Takes the graph blueprint and the node function definitions, building a runtime graph
const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");
const std = @import("std");

const Input = struct {
    name: []const u8,
    type: type,
};

fn Build(comptime graph: Blueprint, comptime node_definitions: anytype) void {
    const inputs = gather_system_inputs: {
        comptime var system_inputs: []const Input = &.{};
        inline for (graph.nodes) |node| {
            inline for (node.input_links) |link| {
                switch (link) {
                    else => {},
                    .input => |input| {
                        const field_name = if (input.system_field) |system_field| system_field else input.input_field;
                        const node_params = @typeInfo(@TypeOf(@field(node_definitions, node.uniqueID()))).Fn.params;
                        const field_type = comptime for (@typeInfo(node_params[node_params.len - 1].type.?).Struct.fields) |field|
                            if (std.mem.eql(u8, field.name, field_name)) break field.type else continue
                        else
                            unreachable;
                        system_inputs = comptime system_inputs ++ for (system_inputs) |system_input|
                            if (std.mem.eql(u8, system_input.name, input.input_field)) break .{} else continue
                        else
                            .{.{ .name = field_name, .type = field_type }};
                    },
                }
            }
        }
        break :gather_system_inputs system_inputs;
    };
    @compileLog("inputs: {}", inputs);
}

test "Build" {
    const result = Build(node_graph_blueprint, NodeDefinitions);
    _ = result;
}
