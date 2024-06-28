const std = @import("std");
const graph_runtime = @import("./graph_runtime.zig");
const node_graph_blueprint = @import("./interactive_node_builder_blueprint.zig");
const typeDefinitions = @import("./type_definitions.zig");

const subdiv = @import("./subdiv.zig");
const MeshHelper = @import("./MeshHelper.zig");
const MeshSpec = @import("./MeshSpec.zig");
const zmath = @import("./zmath/main.zig");
const wasm_entry = @import("./wasm_entry.zig");
const utils = @import("./utils.zig");

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
    pub fn getResources() !struct { meshes: []Mesh } {
        const allocator = std.heap.page_allocator;
        const json_data = @embedFile("content/Cat.blend.json");
        const mesh_input_data = std.json.parseFromSlice(MeshSpec, allocator, json_data, .{}) catch |err| {
            // std.debug.print("Failed to parse JSON: {}", .{err});
            wasm_entry.dumpDebugLog(std.fmt.allocPrint(allocator, "Failed to parse JSON: {}", .{err}) catch unreachable);
            return err;
        };
        var meshes = std.ArrayList(Mesh).init(allocator);
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        for (mesh_input_data.value.meshes) |input_data| {
            const vertices = MeshHelper.decodeVertexDataFromHexidecimal(arena.allocator(), input_data.frame_to_vertices[10]);
            const flipped_vertices = MeshHelper.flipYZ(arena.allocator(), vertices);
            try meshes.append(mesh: {
                const input_vertices = flipped_vertices; // input_data.vertices
                var mesh_result = try subdiv.Polygon(.Face).cmcSubdiv(arena.allocator(), input_vertices, input_data.polygons);
                var subdiv_count: u32 = 0;
                while (subdiv_count < 1) {
                    mesh_result = try subdiv.Polygon(.Quad).cmcSubdiv(arena.allocator(), mesh_result.points, mesh_result.quads);
                    subdiv_count += 1;
                }
                const mesh_helper = MeshHelper.Polygon(.Quad);
                break :mesh .{
                    .label = input_data.name,
                    .indices = mesh_helper.toTriangleIndices(allocator, mesh_result.quads),
                    .position = MeshHelper.pointsToFloatSlice(allocator, mesh_result.points),
                    .normals = MeshHelper.pointsToFloatSlice(
                        allocator,
                        mesh_helper.calculateNormals(arena.allocator(), mesh_result.points, mesh_result.quads),
                    ),
                };
            });
        }
        return .{
            .meshes = meshes.items,
        };
    }

    const Axis = struct {
        x: f32,
        y: f32,
        z: f32,
    };
    const OrbitCamera = struct {
        position: zmath.Vec,
        rotation: zmath.Vec,
        track_distance: f32,
    };
    const PixelPoint = struct { x: u32, y: u32 };
    const MyNodeGraph = graph_runtime.NodeGraph(
        struct {
            allocator: std.mem.Allocator,
            pub const Settings = struct {
                orbit_speed: f32,
                render_resolution: PixelPoint,
            };
            pub fn changeSettings(self: @This(), props: struct {
                settings: Settings,
                user_changes: ?union(enum) {
                    resolution_update: PixelPoint,
                },
            }) !struct { settings: Settings } {
                var settings = props.settings;
                if (props.user_changes) |c| {
                    switch (c) {
                        .resolution_update => |resolution| {
                            settings.render_resolution = resolution;
                        },
                    }
                }

                return .{
                    .settings = settings,
                };
            }
            pub fn game(self: @This(), props: struct {
                settings: Settings,
                game_time_seconds: ?f32,
                input: ?struct { mouse_delta: zmath.Vec },
                orbit_camera: OrbitCamera,
            }) !struct {
                orbit_camera: OrbitCamera,
                world_matrix: zmath.Mat,
            } {
                wasm_entry.dumpDebugLog(try std.fmt.allocPrint(self.allocator, "{}", .{props.settings.orbit_speed}));
                const orbit_camera: OrbitCamera = if (props.input) |found_input|
                    utils.copyWith(props.orbit_camera, .{
                        .rotation = props.orbit_camera.rotation +
                            found_input.mouse_delta *
                            @as(zmath.Vec, @splat(-props.settings.orbit_speed)),
                    })
                else
                    props.orbit_camera;
                return .{
                    .orbit_camera = orbit_camera,
                    .world_matrix = zmath.mul(
                        zmath.mul(
                            zmath.translationV(orbit_camera.position),
                            zmath.mul(
                                zmath.mul(
                                    zmath.matFromRollPitchYaw(0, orbit_camera.rotation[0], 0),
                                    zmath.matFromRollPitchYaw(orbit_camera.rotation[1], 0, 0),
                                ),
                                zmath.translationV(zmath.loadArr3(.{ 0.0, 0.0, orbit_camera.track_distance })),
                            ),
                        ),
                        zmath.perspectiveFovLh(
                            0.25 * 3.141569,
                            @as(f32, @floatFromInt(props.settings.render_resolution.x)) /
                                @as(f32, @floatFromInt(props.settings.render_resolution.y)),
                            0.1,
                            500,
                        ),
                    ),
                };
            }
        },
        node_graph_blueprint.Blueprint{
            .nodes = &[_]node_graph_blueprint.NodeGraphBlueprintEntry{
                .{
                    .name = "game",
                    .function = "game",
                    .input_links = &[_]node_graph_blueprint.InputLink{
                        .{ .field = "game_time_seconds", .source = .{ .input_field = "game_time_seconds" } },
                        .{ .field = "input", .source = .{ .input_field = "input" } },
                        .{ .field = "settings", .source = .{ .node = .{ .name = "changeSettings", .field = "settings" } } },
                        .{ .field = "orbit_camera", .source = .{ .store_field = "orbit_camera" } },
                    },
                },
                .{
                    .name = "changeSettings",
                    .function = "changeSettings",
                    .input_links = &[_]node_graph_blueprint.InputLink{
                        .{ .field = "user_changes", .source = .{ .input_field = "user_changes" } },
                        .{ .field = "settings", .source = .{ .store_field = "settings" } },
                    },
                },
            },
            .store = &[_]node_graph_blueprint.SystemSink{
                .{ .output_node = "game", .output_field = "orbit_camera", .system_field = "orbit_camera" },
                .{ .output_node = "changeSettings", .output_field = "settings", .system_field = "settings" },
            },
            .output = &[_]node_graph_blueprint.SystemSink{
                .{ .output_node = "game", .output_field = "orbit_camera", .system_field = "orbit_camera" },
                .{ .output_node = "game", .output_field = "world_matrix", .system_field = "world_matrix" },
            },
        },
    );

    var previous_outputs_hash: u32 = 0;
    var my_node_graph = MyNodeGraph{
        .allocator = std.heap.page_allocator,
        .store = .{
            .settings = .{
                .orbit_speed = 0.01,
                .render_resolution = .{ .x = 0, .y = 0 },
            },
            .orbit_camera = .{
                .position = .{ 0, 0, 0, 1 },
                .rotation = .{ 0, 0, 0, 1 },
                .track_distance = 20,
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
        const send_outputs = true;
        // blk: {
        //     var hasher = std.hash.Adler32.init();
        //     std.hash.autoHashStrat(&hasher, outputs, .DeepRecursive);
        //     defer previous_outputs_hash = hasher.final();
        //     break :blk hasher.final() != previous_outputs_hash;
        // };
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
    return @Type(std.builtin.Type{ .Enum = .{
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
