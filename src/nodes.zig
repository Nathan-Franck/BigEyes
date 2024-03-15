const subdiv = @import("./subdiv.zig");
const std = @import("std");
const graphRuntime = @import("./graphRuntime.zig");
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;

const MyNodeGraph = graphRuntime.NodeGraph(
    NodeDefinitions,
    node_graph_blueprint,
);

pub const Nodes = struct {
    pub fn helloSlice(faces: []subdiv.Face) ![]subdiv.Face {
        const allocator = std.heap.page_allocator;
        return std.mem.concat(allocator, subdiv.Face, &.{ faces, &.{&.{ 4, 5, 6 }} });
    }

    pub fn testSubdiv(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        const allocator = std.heap.page_allocator;
        const result = try subdiv.Polygon(.Face).cmcSubdiv(
            allocator,
            points,
            faces,
        );
        return result;
    }
    pub fn testNodeGraph(inputs: MyNodeGraph.SystemInputs, store: MyNodeGraph.SystemStore) MyNodeGraph.SystemOutputs {
        const allocator = std.heap.page_allocator;
        var my_node_graph = MyNodeGraph{
            .allocator = allocator,
            .store = store,
        };
        const result_commands = try my_node_graph.update(inputs);
        return result_commands;
    }
};
pub const NodesEnum = DeclsToEnum(Nodes);

pub fn DeclsToEnum(comptime container: type) type {
    const info = @typeInfo(container);
    var enum_fields: []const std.builtin.Type.EnumField = &.{};
    for (info.Struct.decls, 0..) |struct_decl, i| {
        enum_fields = enum_fields ++ &[_]std.builtin.Type.EnumField{.{
            .name = struct_decl.name,
            .value = i,
        }};
    }
    return @Type(.{ .Enum = .{
        .tag_type = u32,
        .fields = enum_fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });
}
pub fn Args(comptime func: anytype) type {
    const ParamInfo = @typeInfo(@TypeOf(func)).Fn.params;
    var fields: []const std.builtin.Type.StructField = &.{};
    for (ParamInfo, 0..) |param_info, i| {
        fields = fields ++ &[_]std.builtin.Type.StructField{.{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = param_info.type.?,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(param_info.type.?),
        }};
    }
    return @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = true,
    } });
}
