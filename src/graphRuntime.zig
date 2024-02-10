// Takes the graph blueprint and the node function definitions, building a runtime graph
const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");

fn Build(graph: Blueprint, node_definitions: anytype) void {
    _ = graph;
    _ = node_definitions;
}

test "Build" {
    const result = Build(node_graph_blueprint, NodeDefinitions);
    _ = result;
}
