// Takes the graph blueprint and the node function definitions, building a runtime graph
const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");
const std = @import("std");

// const tester = struct {
//     fn nodeA(input: struct { this: u32, that: u32 }) struct { result: u32 } {
//         return .{ .result = input.this + input.that };
//     }

//     fn nodeB(input: struct { this: u32, that: u32 }) struct { result: u32 } {
//         return .{ .result = input.this + input.that };
//     }
// };

// const TesterBlueprint = Blueprint{
//     .nodes = &.{
//         .{ .name = "what" },
//     },
// };

fn Build(graph: Blueprint, node_definitions: anytype) void {
    _ = node_definitions;
    for (graph.nodes) |node| {
        std.debug.print("Node: {s}\n", .{node.uniqueID()});
    }
}

test "Build" {
    const result = Build(node_graph_blueprint, NodeDefinitions);
    _ = result;
}
