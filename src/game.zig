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
    normal: []const f32,
};

pub const BakedAnimationMesh = struct {
    pub const Frame = struct {
        normal: []const f32,
        position: []const f32,
    };
    label: []const u8,
    indices: []const u32,
    frames: []const Frame,
    frame_rate: u32,
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
                _ = self;
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
            pub const Resources = struct {
                cat: BakedAnimationMesh,
            };

            pub fn getResources(self: @This(), props: struct {
                load_the_data: bool,
            }) !struct {
                resources: Resources,
            } {
                const allocator = self.allocator;
                _ = props;

                const max_subdiv = 1;

                const json_data = @embedFile("content/Cat.blend.json");
                const mesh_input_data = std.json.parseFromSlice(MeshSpec, allocator, json_data, .{}) catch |err| {
                    // std.debug.print("Failed to parse JSON: {}", .{err});
                    wasm_entry.dumpDebugLog(std.fmt.allocPrint(allocator, "Failed to parse JSON: {}", .{err}) catch unreachable);
                    return err;
                };
                var arena = std.heap.ArenaAllocator.init(allocator);
                defer arena.deinit();
                const mesh_helper = MeshHelper.Polygon(.Quad);
                const input_data = mesh_input_data.value.meshes[0];
                const quads_by_subdiv = blk: {
                    const encoded_vertices = input_data.frame_to_vertices[0];
                    const input_vertices = MeshHelper.flipYZ(
                        arena.allocator(),
                        MeshHelper.decodeVertexDataFromHexidecimal(
                            arena.allocator(),
                            encoded_vertices,
                        ),
                    );
                    var quads_by_subdiv: [max_subdiv + 1][]const subdiv.Quad = undefined;
                    var mesh_result = try subdiv.Polygon(.Face).cmcSubdiv(arena.allocator(), input_vertices, input_data.polygons);
                    quads_by_subdiv[0] = mesh_result.quads;
                    var subdiv_count: u32 = 0;
                    while (subdiv_count < max_subdiv) {
                        mesh_result = try subdiv.Polygon(.Quad).cmcSubdiv(arena.allocator(), mesh_result.points, mesh_result.quads);
                        subdiv_count += 1;
                        quads_by_subdiv[subdiv_count] = mesh_result.quads;
                    }
                    break :blk quads_by_subdiv;
                };
                var frames = std.ArrayList(BakedAnimationMesh.Frame).init(self.allocator);
                for (input_data.frame_to_vertices) |encoded_vertices| {
                    try frames.append(blk: {
                        const input_vertices = MeshHelper.flipYZ(
                            self.allocator,
                            MeshHelper.decodeVertexDataFromHexidecimal(
                                arena.allocator(),
                                encoded_vertices,
                            ),
                        );
                        var mesh_result = try subdiv.Polygon(.Face).cmcSubdivOnlyPoints(self.allocator, input_vertices, input_data.polygons);
                        var subdiv_count: u32 = 0;
                        while (subdiv_count < max_subdiv) {
                            mesh_result = try subdiv.Polygon(.Quad).cmcSubdivOnlyPoints(self.allocator, mesh_result, quads_by_subdiv[subdiv_count]);
                            subdiv_count += 1;
                        }
                        break :blk BakedAnimationMesh.Frame{
                            .position = MeshHelper.pointsToFloatSlice(allocator, mesh_result),
                            .normal = MeshHelper.pointsToFloatSlice(
                                allocator,
                                mesh_helper.calculateNormals(arena.allocator(), mesh_result, quads_by_subdiv[quads_by_subdiv.len - 1]),
                            ),
                        };
                    });
                }

                return .{
                    .resources = .{
                        .cat = .{
                            .label = input_data.name,
                            .indices = mesh_helper.toTriangleIndices(self.allocator, quads_by_subdiv[quads_by_subdiv.len - 1]),
                            .frames = frames.items,
                            .frame_rate = 24,
                        },
                    },
                };
            }
            pub fn game(
                self: @This(),
                props: struct {
                    settings: Settings,
                    resources: Resources,
                    game_time_ms: f32, // WHY IS THIS NOT ACCEPTING INTEGERS
                    input: ?struct { mouse_delta: zmath.Vec },
                    orbit_camera: OrbitCamera,
                },
            ) !struct {
                orbit_camera: OrbitCamera,
                current_cat_mesh: Mesh,
                world_matrix: zmath.Mat,
            } {
                _ = self;

                const orbit_camera: OrbitCamera = if (props.input) |found_input|
                    utils.copyWith(props.orbit_camera, .{
                        .rotation = props.orbit_camera.rotation +
                            found_input.mouse_delta *
                            @as(zmath.Vec, @splat(-props.settings.orbit_speed)),
                    })
                else
                    props.orbit_camera;
                // const current_frame_index = @mod(
                //     props.game_time_ms * props.resources.cat.frame_rate / 1000,
                //     props.resources.cat.frames.len,
                // );
                const current_frame_index = 0;
                const current_frame = props.resources.cat.frames[current_frame_index];
                return .{
                    .orbit_camera = orbit_camera,
                    .current_cat_mesh = Mesh{
                        .label = "cat",
                        .indices = props.resources.cat.indices,
                        .position = current_frame.position,
                        .normal = current_frame.normal,
                    },
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
                    .name = "getResources",
                    .function = "getResources",
                    .input_links = &[_]node_graph_blueprint.InputLink{
                        .{ .field = "load_the_data", .source = .{ .input_field = "load_the_data" } },
                    },
                },
                .{
                    .name = "game",
                    .function = "game",
                    .input_links = &[_]node_graph_blueprint.InputLink{
                        .{ .field = "game_time_ms", .source = .{ .input_field = "game_time_ms" } },
                        .{ .field = "input", .source = .{ .input_field = "input" } },
                        .{ .field = "resources", .source = .{ .node = .{ .name = "getResources", .field = "resources" } } },
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
                .{ .output_node = "game", .output_field = "current_cat_mesh", .system_field = "current_cat_mesh" },
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
