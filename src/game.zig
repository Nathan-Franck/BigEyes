const std = @import("std");
const graph_runtime = @import("./graph_runtime.zig");
const NodeDefinitions = @import("./node_graph_blueprint_nodes.zig");
const node_graph_blueprint = @import("./interactive_node_builder_blueprint.zig").node_graph_blueprint;
const typeDefinitions = @import("./type_definitions.zig");

const subdiv = @import("./subdiv.zig");
const MeshLoader = @import("./MeshLoader.zig");

const MyNodeGraph = graph_runtime.NodeGraph(
    NodeDefinitions,
    node_graph_blueprint,
);

pub const interface = struct {
    pub fn getResources() ![]subdiv.Mesh {
        const allocator = std.heap.page_allocator;
        const meshes = try MeshLoader.getMeshes(allocator);
        return meshes.items;
    }

    var previous_outputs_hash: u32 = 0;
    var my_node_graph = MyNodeGraph{
        .allocator = std.heap.page_allocator,
        .store = .{
            .blueprint = .{
                .nodes = &.{},
                .output = &.{},
                .store = &.{},
            },
            .node_dimensions = &.{},
            .interaction_state = .{
                .node_selection = &.{},
            },
            .camera = .{},
            .context_menu = .{
                .open = false,
                .location = .{ .x = 0, .y = 0 },
                .options = &.{},
            },
        },
    };

    pub fn callNodeGraph(
        inputs: MyNodeGraph.SystemInputs,
    ) !struct {
        outputs: ?MyNodeGraph.SystemOutputs,
    } {
        const outputs = try my_node_graph.update(inputs);
        // const send_outputs = true;
        const send_outputs = blk: {
            var hasher = std.hash.Adler32.init();
            std.hash.autoHashStrat(&hasher, outputs, .DeepRecursive);
            defer previous_outputs_hash = hasher.final();
            break :blk hasher.final() != previous_outputs_hash;
        };
        return .{
            .outputs = if (send_outputs) outputs else null,
        };
    }
};

pub const InterfaceEnum = DeclsToEnum(interface);

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
        .layout = .auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = true,
    } });
}
