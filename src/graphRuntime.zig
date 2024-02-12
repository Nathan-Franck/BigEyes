// Takes the graph blueprint and the node function definitions, building a runtime graph
const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");
const std = @import("std");

fn Build(graph: Blueprint, node_definitions: anytype) void {
    _ = node_definitions;
    for (graph.nodes) |node| {
        std.debug.print("Node: {s}\n", .{node.uniqueID()});
        for (node.input_links) |link| {
            switch (link) {
                .input => |input| {
                    std.debug.print("  Input: {s}\n", .{input.input_field});
                },
                .store => |store| {
                    std.debug.print("  Store: {s}\n", .{store.input_field});
                },
                .node => |input_node| {
                    std.debug.print("  Node: {s}\n", .{input_node.input_field});
                },
            }
        }
    }
}

test "Build" {
    const result = Build(node_graph_blueprint, NodeDefinitions);
    _ = result;
}
