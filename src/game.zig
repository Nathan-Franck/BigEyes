const std = @import("std");
const graph_runtime = @import("./graph_runtime.zig");
const NodeDefinitions = @import("./node_graph_blueprint_nodes.zig");
const node_graph_blueprint = @import("./interactive_node_builder_blueprint.zig").node_graph_blueprint;
const typeDefinitions = @import("./type_definitions.zig");

const subdiv = @import("./subdiv.zig");
const MeshHelper = @import("./MeshHelper.zig");
const MeshSpec = @import("./MeshSpec.zig");
const zmath = @import("./zmath/main.zig");

const MyNodeGraph = graph_runtime.NodeGraph(
    NodeDefinitions,
    node_graph_blueprint,
);

pub const Mesh = struct {
    label: []const u8,
    indices: []const u32,
    position: []const f32,
    // color: []f32,
    normals: []const f32,
};

const hexColors = [_][3]f32{
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 1.0 },
    .{ 1.0, 1.0, 0.0 },
    .{ 1.0, 0.0, 1.0 },
    .{ 0.0, 1.0, 1.0 },
};

pub const interface = struct {
    pub fn getResources() !struct { world_matrix: zmath.Mat, meshes: []Mesh } {
        const allocator = std.heap.page_allocator;
        const json_data = @embedFile("content/Cat.blend.json");
        const mesh_input_data = std.json.parseFromSlice(MeshSpec, allocator, json_data, .{}) catch |err| {
            // std.debug.print("Failed to parse JSON: {}", .{err});
            return err;
        };
        var meshes = std.ArrayList(Mesh).init(allocator);
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        for (mesh_input_data.value.meshes) |input_data| {
            const flipped_vertices = MeshHelper.flipYZ(arena.allocator(), input_data.vertices);
            try meshes.append(mesh: {
                const input_vertices = flipped_vertices; // input_data.vertices
                var result = try subdiv.Polygon(.Face).cmcSubdiv(arena.allocator(), input_vertices, input_data.polygons);
                var subdiv_count: u32 = 0;
                while (subdiv_count < 1) {
                    result = try subdiv.Polygon(.Quad).cmcSubdiv(arena.allocator(), result.points, result.quads);
                    subdiv_count += 1;
                }
                const mesh_helper = MeshHelper.Polygon(.Quad);
                break :mesh .{
                    .label = input_data.name,
                    .indices = mesh_helper.toTriangleIndices(allocator, result.quads),
                    .position = MeshHelper.pointsToFloatSlice(allocator, result.points),
                    .normals = MeshHelper.pointsToFloatSlice(
                        allocator,
                        mesh_helper.calculateNormals(arena.allocator(), result.points, result.quads),
                    ),
                };
            });
        }
        return .{
            .world_matrix = zmath.mul(
                zmath.translationV(zmath.loadArr3(.{ 0, 0, 15 })),
                zmath.perspectiveFovLh(
                    0.25 * 3.14159,
                    @as(f32, @floatFromInt(1920)) / @as(f32, @floatFromInt(1080)),
                    0.1,
                    500.0,
                ),
            ),
            .meshes = meshes.items,
        };
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
