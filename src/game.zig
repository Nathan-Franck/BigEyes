const std = @import("std");
const graph = @import("./graph_runtime.zig");
const typeDefinitions = @import("./type_definitions.zig");

const subdiv = @import("./subdiv.zig");
const mesh_helper = @import("./mesh_helper.zig");
const MeshSpec = @import("./MeshSpec.zig");
const zm = @import("./zmath/main.zig");
const wasm_entry = @import("./wasm_entry.zig");
const utils = @import("./utils.zig");

pub const Mesh = struct {
    label: []const u8,
    indices: []const u32,
    position: []const f32,
    // color: []f32,
    normal: []const f32,
};

pub const SubdivAnimationMesh = struct {
    label: []const u8,
    polygons: []const subdiv.Face,
    quads_by_subdiv: []const []const subdiv.Quad,
    indices: []const u32,
    frames: []const []const zm.Vec,
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

pub const interface = struct {
    var node_graph: NodeGraph = undefined;

    pub fn init() void {
        node_graph = try NodeGraph.init(.{
            .allocator = std.heap.page_allocator,
            .store = .{
                .settings = .{
                    .orbit_speed = 0.01,
                    .render_resolution = .{ .x = 0, .y = 0 },
                    .subdiv_level = 1,
                },
                .orbit_camera = .{
                    .position = .{ 0, 0, 0, 1 },
                    .rotation = .{ 0, 0, 0, 1 },
                    .track_distance = 20,
                },
                .some_numbers = blk: {
                    var some_numbers = std.ArrayList(u32).init(std.heap.page_allocator);
                    some_numbers.appendSlice(&.{ 0, 1, 2 }) catch unreachable;
                    break :blk some_numbers;
                },
            },
        });
    }

    pub fn updateNodeGraph(
        inputs: NodeGraph.SystemInputs,
    ) !struct {
        outputs: NodeGraph.SystemOutputs,
    } {
        return .{
            .outputs = try node_graph.update(inputs),
        };
    }

    const NodeGraph = graph.NodeGraph(
        graph.Blueprint{
            .nodes = &[_]graph.NodeGraphBlueprintEntry{
                .{
                    .name = "getResources",
                    .function = "getResources",
                    .input_links = &[_]graph.InputLink{
                        .{ .field = "settings", .source = .{ .node = .{ .name = "changeSettings", .field = "settings" } } },
                    },
                },
                .{
                    .name = "game",
                    .function = "game",
                    .input_links = &[_]graph.InputLink{
                        .{ .field = "resources", .source = .{ .node = .{ .name = "getResources", .field = "resources" } } },
                        .{ .field = "settings", .source = .{ .node = .{ .name = "changeSettings", .field = "settings" } } },
                        .{ .field = "game_time_ms", .source = .{ .input_field = "game_time_ms" } },
                        .{ .field = "input", .source = .{ .input_field = "input" } },
                        .{ .field = "orbit_camera", .source = .{ .store_field = "orbit_camera" } },
                        .{ .field = "some_numbers", .source = .{ .store_field = "some_numbers" } },
                    },
                },
                .{
                    .name = "changeSettings",
                    .function = "changeSettings",
                    .input_links = &[_]graph.InputLink{
                        .{ .field = "user_changes", .source = .{ .input_field = "user_changes" } },
                        .{ .field = "settings", .source = .{ .store_field = "settings" } },
                    },
                },
            },
            .store = &[_]graph.SystemSink{
                .{ .output_node = "game", .output_field = "orbit_camera", .system_field = "orbit_camera" },
                .{ .output_node = "game", .output_field = "some_numbers", .system_field = "some_numbers" },
                .{ .output_node = "changeSettings", .output_field = "settings", .system_field = "settings" },
            },
            .output = &[_]graph.SystemSink{
                .{ .output_node = "game", .output_field = "current_cat_mesh", .system_field = "current_cat_mesh" },
                .{ .output_node = "game", .output_field = "orbit_camera", .system_field = "orbit_camera" },
                .{ .output_node = "game", .output_field = "world_matrix", .system_field = "world_matrix" },
            },
        },
        struct {
            const QuadMeshHelper = mesh_helper.Polygon(.Quad);

            const PixelPoint = struct { x: u32, y: u32 };

            const OrbitCamera = struct {
                position: zm.Vec,
                rotation: zm.Vec,
                track_distance: f32,
            };

            pub const Resources = struct {
                cat: SubdivAnimationMesh,
            };

            pub const Settings = struct {
                orbit_speed: f32,
                subdiv_level: u8,
                render_resolution: PixelPoint,
            };

            pub fn changeSettings(props: struct {
                settings: Settings,
                user_changes: ?union(enum) {
                    resolution_update: PixelPoint,
                    subdiv_level_update: u8,
                },
            }) !struct { settings: Settings } {
                var settings = props.settings;
                if (props.user_changes) |c| {
                    switch (c) {
                        .resolution_update => |resolution| {
                            settings.render_resolution = resolution;
                        },
                        .subdiv_level_update => |level| {
                            settings.subdiv_level = level;
                        },
                    }
                }

                return .{
                    .settings = settings,
                };
            }

            pub fn getResources(arena: *std.heap.ArenaAllocator, props: struct {
                settings: Settings,
            }) !struct {
                resources: Resources,
            } {
                const allocator = arena.allocator();

                const mesh_input_data = blk: {
                    const json_data = @embedFile("content/Cat.blend.json");
                    break :blk std.json.parseFromSliceLeaky(MeshSpec, allocator, json_data, .{}) catch unreachable;
                };
                const input_data = mesh_input_data.meshes[0];
                const quads_by_subdiv = blk: {
                    const encoded_vertices = input_data.frame_to_vertices[0];
                    const input_vertices = mesh_helper.flipYZ(
                        arena.allocator(),
                        mesh_helper.decodeVertexDataFromHexidecimal(
                            arena.allocator(),
                            encoded_vertices,
                        ),
                    );
                    var quads_by_subdiv = std.ArrayList([]const subdiv.Quad).init(allocator);
                    var mesh_result = try subdiv.Polygon(.Face).cmcSubdiv(arena.allocator(), input_vertices, input_data.polygons);
                    try quads_by_subdiv.append(mesh_result.quads);
                    var subdiv_count: u32 = 0;
                    while (subdiv_count < props.settings.subdiv_level) {
                        mesh_result = try subdiv.Polygon(.Quad).cmcSubdiv(arena.allocator(), mesh_result.points, mesh_result.quads);
                        subdiv_count += 1;
                        try quads_by_subdiv.append(mesh_result.quads);
                    }
                    break :blk quads_by_subdiv.items;
                };
                var frames = std.ArrayList([]const zm.Vec).init(allocator);
                for (input_data.frame_to_vertices) |encoded_vertices| {
                    try frames.append(mesh_helper.flipYZ(
                        allocator,
                        mesh_helper.decodeVertexDataFromHexidecimal(
                            arena.allocator(),
                            encoded_vertices,
                        ),
                    ));
                }

                return .{
                    .resources = .{
                        .cat = SubdivAnimationMesh{
                            .label = input_data.name,
                            .indices = QuadMeshHelper.toTriangleIndices(allocator, quads_by_subdiv[quads_by_subdiv.len - 1]),
                            .quads_by_subdiv = quads_by_subdiv,
                            .polygons = input_data.polygons,
                            .frames = frames.items,
                            .frame_rate = 24,
                        },
                    },
                };
            }

            pub fn game(
                arena: *std.heap.ArenaAllocator,
                props: struct {
                    settings: Settings,
                    resources: Resources,
                    game_time_ms: u64,
                    input: ?struct { mouse_delta: zm.Vec },

                    orbit_camera: *OrbitCamera,
                    some_numbers: *std.ArrayList(u32),
                },
            ) !struct {
                current_cat_mesh: Mesh,
                world_matrix: zm.Mat,
            } {
                if (props.input) |found_input| {
                    props.orbit_camera.rotation = props.orbit_camera.rotation +
                        found_input.mouse_delta *
                        @as(zm.Vec, @splat(-props.settings.orbit_speed));
                }
                const current_frame_index = @mod(
                    props.game_time_ms * props.resources.cat.frame_rate / 1000,
                    props.resources.cat.frames.len,
                );
                const current_frame = props.resources.cat.frames[@intCast(current_frame_index)];
                const current_cat_mesh = subdiv_mesh: {
                    const allocator = arena.allocator();
                    const input_vertices = current_frame;
                    const input_data = props.resources.cat;
                    const quads_by_subdiv = props.resources.cat.quads_by_subdiv;
                    var mesh_result = try subdiv.Polygon(.Face).cmcSubdivOnlyPoints(allocator, input_vertices, input_data.polygons);
                    var subdiv_count: u32 = 0;
                    while (subdiv_count < props.settings.subdiv_level) {
                        mesh_result = try subdiv.Polygon(.Quad).cmcSubdivOnlyPoints(allocator, mesh_result, quads_by_subdiv[subdiv_count]);
                        subdiv_count += 1;
                    }
                    break :subdiv_mesh Mesh{
                        .label = "cat",
                        .indices = props.resources.cat.indices,
                        .position = mesh_helper.pointsToFloatSlice(allocator, mesh_result),
                        .normal = mesh_helper.pointsToFloatSlice(
                            allocator,
                            QuadMeshHelper.calculateNormals(arena.allocator(), mesh_result, quads_by_subdiv[quads_by_subdiv.len - 1]),
                        ),
                    };
                };
                try props.some_numbers.append(props.some_numbers.items[props.some_numbers.items.len - 1] + 1);
                wasm_entry.dumpDebugLog(try std.fmt.allocPrint(arena.allocator(), "{any}", .{props.some_numbers.items}));
                return .{
                    .current_cat_mesh = current_cat_mesh,
                    .world_matrix = zm.mul(
                        zm.mul(
                            zm.translationV(props.orbit_camera.position),
                            zm.mul(
                                zm.mul(
                                    zm.matFromRollPitchYaw(0, props.orbit_camera.rotation[0], 0),
                                    zm.matFromRollPitchYaw(props.orbit_camera.rotation[1], 0, 0),
                                ),
                                zm.translationV(zm.loadArr3(.{ 0.0, 0.0, props.orbit_camera.track_distance })),
                            ),
                        ),
                        zm.perspectiveFovLh(
                            0.25 * 3.14151,
                            @as(f32, @floatFromInt(props.settings.render_resolution.x)) /
                                @as(f32, @floatFromInt(props.settings.render_resolution.y)),
                            0.1,
                            500,
                        ),
                    ),
                };
            }
        },
    );
};
