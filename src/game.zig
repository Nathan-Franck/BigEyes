const std = @import("std");
const graph = @import("./graph_runtime.zig");

const utils = @import("./utils.zig");
const subdiv = @import("./subdiv.zig");
const Image = @import("./Image.zig");
const raytrace = @import("./raytrace.zig");
const mesh_helper = @import("./mesh_helper.zig");
const MeshSpec = @import("./MeshSpec.zig");
const zm = @import("./zmath/main.zig");
const tree = @import("./tree.zig");
const Forest = @import("./forest.zig").Forest(16);
const Bounds = @import("./forest.zig").Bounds;
const Coord = @import("./forest.zig").Coord;
const Vec2 = @import("./forest.zig").Vec2;
const wasm_entry = @import("./wasm_entry.zig");

pub const GreyboxMesh = struct {
    label: []const u8,
    indices: []const u32,
    position: []const f32,
    normal: []const f32,
};

pub const TextureMesh = struct {
    label: []const u8,
    diffuse_alpha: Image.Processed,
    indices: []const u32,
    position: []const f32,
    uv: []const f32,
    normal: []const f32,
};

pub const SubdivAnimationMesh = struct {
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

pub const InterfaceEnum = std.meta.DeclEnum(interface);

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
                    .subdiv_level = 0,
                    .should_raytrace = false,
                },
                .orbit_camera = .{
                    .position = .{ 0, -0.75, 0, 1 },
                    .rotation = .{ 0, 0, 0, 1 },
                    .track_distance = 1.5,
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
                    .input_links = &[_]graph.InputLink{},
                },
                .{
                    .name = "orbit",
                    .function = "orbit",
                    .input_links = &[_]graph.InputLink{
                        .{ .field = "settings", .source = .{ .node = .{ .name = "changeSettings", .field = "settings" } } },
                        .{ .field = "input", .source = .{ .input_field = "input" } },
                        .{ .field = "orbit_camera", .source = .{ .store_field = "orbit_camera" } },
                    },
                },
                .{
                    .name = "displayTree",
                    .function = "displayTree",
                    .input_links = &[_]graph.InputLink{
                        .{ .field = "resources", .source = .{ .node = .{ .name = "getResources", .field = "resources" } } },
                    },
                },
                .{
                    .name = "displayForest",
                    .function = "displayForest",
                    .input_links = &[_]graph.InputLink{
                        .{ .field = "resources", .source = .{ .node = .{ .name = "getResources", .field = "resources" } } },
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
                .{ .output_node = "orbit", .output_field = "orbit_camera", .system_field = "orbit_camera" },
                .{ .output_node = "changeSettings", .output_field = "settings", .system_field = "settings" },
            },
            .output = &[_]graph.SystemSink{
                .{ .output_node = "displayTree", .output_field = "meshes", .system_field = "meshes" },
                // .{ .output_node = "displayForest", .output_field = "skybox", .system_field = "skybox" },
                .{ .output_node = "displayForest", .output_field = "forest_data", .system_field = "forest_data" },
                .{ .output_node = "orbit", .output_field = "world_matrix", .system_field = "world_matrix" },
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

            pub const TreeMesh = struct {
                skeleton: tree.Skeleton,
                leaf_mesh: tree.Mesh,
                bark_mesh: tree.Mesh,
            };

            pub const Resources = struct {
                // skybox: []Image.Processed,
                cutout_leaf: Image.Processed,
                tree: struct {
                    skeleton: tree.Skeleton,
                    leaf_mesh: tree.Mesh,
                    bark_mesh: tree.Mesh,
                },
            };

            pub const Settings = struct {
                orbit_speed: f32,
                subdiv_level: u8,
                should_raytrace: bool,
                render_resolution: PixelPoint,
            };

            pub fn changeSettings(props: struct {
                settings: *Settings,
                user_changes: ?union(enum) {
                    resolution_update: PixelPoint,
                    subdiv_level_update: u8,
                    should_raytrace_update: bool,
                },
            }) !struct {} {
                if (props.user_changes) |c| {
                    switch (c) {
                        .resolution_update => |resolution| {
                            props.settings.render_resolution = resolution;
                        },
                        .subdiv_level_update => |level| {
                            props.settings.subdiv_level = level;
                        },
                        .should_raytrace_update => |should_raytrace| {
                            props.settings.should_raytrace = should_raytrace;
                        },
                    }
                }
                return .{};
            }

            pub fn getResources(allocator: std.mem.Allocator, _: struct {}) !struct {
                resources: Resources,
            } {
                // const skybox = blk: {
                //     var images = std.ArrayList(Image.Processed).init(allocator);
                //     inline for (.{
                //         "nx",
                //         "ny",
                //         "nz",
                //         "px",
                //         "py",
                //         "pz",
                //     }) |direction| {
                //         const image_png = @embedFile("content/cloudy skybox/" ++ direction ++ ".png");
                //         const image_data = try Image.loadPngAndProcess(allocator, image_png);
                //         try images.append(image_data);
                //     }
                //     break :blk images.items;
                // };

                const cutout_leaf = blk: {
                    const diffuse = try Image.loadPng(allocator, @embedFile("content/manitoba maple/diffuse.png"));
                    const alpha = try Image.loadPng(allocator, @embedFile("content/manitoba maple/alpha.png"));
                    const cutout_diffuse = .{
                        .width = diffuse.width,
                        .height = diffuse.height,
                        .pixels = try allocator.alloc(@TypeOf(diffuse.pixels[0]), diffuse.pixels.len),
                    };
                    for (cutout_diffuse.pixels, 0..) |*pixel, pixel_index| {
                        pixel.* = diffuse.pixels[pixel_index];
                        pixel.*.a = alpha.pixels[pixel_index].r;
                    }
                    break :blk try Image.processImageForGPU(allocator, cutout_diffuse);
                };

                const tree_skeleton = try tree.generateStructure(allocator, Trees.big_tree.structure);

                return .{
                    .resources = Resources{
                        // .skybox = skybox,
                        .cutout_leaf = cutout_leaf,
                        .tree = .{
                            .skeleton = tree_skeleton,
                            .bark_mesh = try tree.generateTaperedWood(allocator, tree_skeleton, Trees.big_tree.mesh),
                            .leaf_mesh = try tree.generateLeaves(allocator, tree_skeleton, Trees.big_tree.mesh),
                        },
                    },
                };
            }

            pub fn orbit(
                props: struct {
                    settings: Settings,
                    input: ?struct { mouse_delta: zm.Vec },
                    orbit_camera: *OrbitCamera,
                },
            ) !struct {
                world_matrix: zm.Mat,
            } {
                if (props.input) |found_input| {
                    props.orbit_camera.rotation = props.orbit_camera.rotation +
                        found_input.mouse_delta *
                        @as(zm.Vec, @splat(-props.settings.orbit_speed));
                }
                return .{
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

            pub fn displayForest(
                allocator: std.mem.Allocator,
                _: struct {
                    resources: Resources,
                },
            ) !struct {
                forest_data: []const []const f32,
                // skybox: []Image.Processed,
            } {
                const Spawner = Forest.spawner(ForestSettings);
                var spawner: Spawner = Spawner.init(allocator);
                const bounds = Bounds{
                    .min = .{ -8, -8 },
                    .size = .{ 16, 16 },
                };
                const spawns = try spawner.gatherSpawnsInBounds(allocator, bounds);
                var instances = try allocator.alloc(std.ArrayList(Vec4), spawner.trees.len);
                for (instances) |*instance| {
                    instance.* = std.ArrayList(Vec4).init(allocator);
                }
                for (spawns) |spawn| {
                    try instances[@intFromEnum(spawn.id)].append(spawn.position);
                }
                const instances_items = try allocator.alloc([]const f32, spawner.trees.len);
                const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
                for (instances_items, 0..) |*instance, i| {
                    instance.* = PointFlattener.convert(allocator, instances[i].items);
                }

                return .{
                    // .skybox = props.resources.skybox,
                    .forest_data = instances_items,
                };
            }

            const GameMesh = union(enum) {
                greybox: GreyboxMesh,
                textured: TextureMesh,
            };

            pub fn displayTree(
                allocator: std.mem.Allocator,
                props: struct {
                    resources: Resources,
                },
            ) !struct {
                meshes: []const GameMesh,
            } {
                const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
                const UvFlattener = mesh_helper.VecSliceFlattener(2, 2);
                var meshes = std.ArrayList(GameMesh).init(allocator);
                try meshes.appendSlice(&.{
                    .{
                        .greybox = .{
                            .label = "bark",
                            .indices = props.resources.tree.bark_mesh.triangles,
                            .normal = PointFlattener.convert(allocator, props.resources.tree.bark_mesh.normals),
                            .position = PointFlattener.convert(allocator, props.resources.tree.bark_mesh.vertices),
                        },
                    },
                    .{ .textured = .{
                        .label = "leaf",
                        .diffuse_alpha = props.resources.cutout_leaf,
                        .indices = props.resources.tree.leaf_mesh.triangles,
                        .normal = PointFlattener.convert(allocator, props.resources.tree.leaf_mesh.normals),
                        .position = PointFlattener.convert(allocator, props.resources.tree.leaf_mesh.vertices),
                        .uv = UvFlattener.convert(allocator, props.resources.tree.leaf_mesh.uvs),
                    } },
                });
                return .{
                    .meshes = meshes.items,
                };
            }

            noinline fn raytraceCell(
                ray: raytrace.Ray,
                cell: ?*std.ArrayList(*const raytrace.Triangle),
                closest_distance: *f32,
            ) void {
                if (cell) |cell_triangles| for (cell_triangles.items) |triangle| {
                    const hit_distance = raytrace.rayTriangleIntersection(ray, triangle.*);
                    closest_distance.* = @min(closest_distance.*, hit_distance);
                };
            }

            pub fn displayCat(
                allocator: std.mem.Allocator,
                props: struct {
                    settings: Settings,
                    resources: Resources,
                    game_time_ms: u64,
                },
            ) !struct {
                current_cat_mesh: TextureMesh,
            } {
                const source_mesh = props.resources.cat;
                const current_frame_index = @mod(
                    props.game_time_ms * source_mesh.frame_rate / 1000,
                    source_mesh.frames.len,
                );
                const current_frame = source_mesh.frames[@intCast(current_frame_index)];
                const subdiv_mesh = subdiv_mesh: {
                    var mesh_result = try subdiv.Polygon(.Face).cmcSubdivOnlyPoints(
                        allocator,
                        current_frame,
                        source_mesh.polygons,
                    );
                    var subdiv_count: u32 = 0;
                    while (subdiv_count < props.settings.subdiv_level) {
                        mesh_result = try subdiv.Polygon(.Quad).cmcSubdivOnlyPoints(
                            allocator,
                            mesh_result,
                            source_mesh.quads_by_subdiv[subdiv_count],
                        );
                        subdiv_count += 1;
                    }
                    break :subdiv_mesh .{
                        .indices = source_mesh.indices,
                        .positions = mesh_result,
                        .normals = QuadMeshHelper.calculateNormals(
                            allocator,
                            mesh_result,
                            source_mesh.quads_by_subdiv[source_mesh.quads_by_subdiv.len - 1],
                        ),
                    };
                };
                const color: []const @Vector(4, f32) = if (!props.settings.should_raytrace) &.{} else occlude: {
                    const positions = subdiv_mesh.positions;
                    const normals = subdiv_mesh.normals;

                    const triangles = build: {
                        var list = std.ArrayList(raytrace.Triangle).init(allocator);
                        for (0..source_mesh.indices.len / 3) |triangle_index| {
                            try list.append(.{
                                positions[source_mesh.indices[triangle_index * 3 + 0]],
                                positions[source_mesh.indices[triangle_index * 3 + 1]],
                                positions[source_mesh.indices[triangle_index * 3 + 2]],
                            });
                        }
                        break :build list.items;
                    };

                    var colors = std.ArrayList(zm.Vec).init(allocator);

                    const GridBounds = raytrace.GridBounds(16);
                    const grid_bounds = GridBounds{
                        .bounds = raytrace.Bounds.initEncompass(positions),
                    };
                    const bins = try grid_bounds.binTriangles(allocator, triangles);
                    for (positions, normals) |position, normal| {
                        var closest_distance = std.math.floatMax(f32);
                        const ray = .{
                            .position = position,
                            .normal = normal,
                        };
                        const bounding_box_test = raytrace.rayBoundsIntersection(ray, grid_bounds.bounds);
                        if (bounding_box_test) |bounding_box_hit| {
                            const start = grid_bounds.transformPoint(ray.position);
                            const end = grid_bounds.transformPoint(
                                ray.position + ray.normal * @as(zm.Vec, @splat(bounding_box_hit.exit_distance)),
                            );
                            var traversal_iterator = raytrace.GridTraversal.init(start, end);
                            while (traversal_iterator.next()) |cell_coord| {
                                const cell_index = GridBounds.coordToIndex(cell_coord);
                                const cell = bins[cell_index];
                                raytraceCell(ray, cell, &closest_distance);
                            }
                        }

                        try colors.append(if (closest_distance < 100)
                            zm.Vec{ 1.0, 1.0, 1.0, 1.0 }
                        else
                            zm.Vec{ 1.0, 0.0, 0.0, 1.0 });
                    }
                    break :occlude colors.items;
                };

                const final_mesh = TextureMesh{
                    .color = mesh_helper.pointsToFloatSlice(allocator, color),
                    .indices = subdiv_mesh.indices,
                    .normal = mesh_helper.pointsToFloatSlice(allocator, subdiv_mesh.normals),
                    .position = mesh_helper.pointsToFloatSlice(allocator, subdiv_mesh.positions),
                };

                return .{
                    .current_cat_mesh = final_mesh,
                };
            }
        },
    );
};
const Vec4 = @Vector(4, f32);
const ForestSettings = struct {
    pub const grass1 = Forest.Tree{
        .density_tier = -2,
        .likelihood = 0.05,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const grass2 = Forest.Tree{
        .density_tier = -2,
        .likelihood = 0.05,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const little_tree = Forest.Tree{
        .density_tier = 1,
        .likelihood = 0.25,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const big_tree = Forest.Tree{
        .density_tier = 2,
        .likelihood = 0.5,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        .spawn_radii = &[_]Forest.Tree.SpawnRadius{
            .{
                .tree = &little_tree,
                .radius = 10,
                .likelihood = 1,
            },
        },
    };
};
pub const Trees = struct {
    const Settings = tree.Settings;
    const DepthDefinition = tree.DepthDefinition;
    const MeshSettings = tree.MeshSettings;
    const math = std.math;

    pub const big_tree = .{
        .structure = Settings{
            .start_size = 1,
            .start_growth = 1,
            .depth_definitions = &[_]DepthDefinition{
                .{
                    .split_amount = 10,
                    .flatness = 0.0,
                    .size = 0.4,
                    .height_spread = 0.6,
                    .branch_pitch = 50.0 * math.rad_per_deg,
                    .branch_roll = 90.0 * math.rad_per_deg,
                    .height_to_growth = .{
                        .y_values = &.{ 1.0, 1.0, 0.0 },
                        .x_range = .{ 0.0, 1.0 },
                    },
                },
                .{
                    .split_amount = 6,
                    .flatness = 0.3,
                    .size = 0.45,
                    .height_spread = 0.8,
                    .branch_pitch = 60.0 * math.rad_per_deg,
                    .branch_roll = 90.0 * math.rad_per_deg,
                    .height_to_growth = .{
                        .y_values = &.{ 1.0, 1.0, 0.0 },
                        .x_range = .{ 0.0, 1.0 },
                    },
                },
                .{
                    .split_amount = 10,
                    .flatness = 0.0,
                    .size = 0.5,
                    .height_spread = 0.8,
                    .branch_pitch = 40.0 * math.rad_per_deg,
                    .branch_roll = 90.0 * math.rad_per_deg,
                    .height_to_growth = .{
                        .y_values = &.{ 1.0, 1.0, 0.0 },
                        .x_range = .{ 0.0, 1.0 },
                    },
                },
                .{
                    .split_amount = 10,
                    .flatness = 0.0,
                    .size = 0.6,
                    .height_spread = 0.8,
                    .branch_pitch = 40.0 * math.rad_per_deg,
                    .branch_roll = 90.0 * math.rad_per_deg,
                    .height_to_growth = .{
                        .y_values = &.{ 0.5, 0.8, 1.0, 0.8, 0.5 },
                        .x_range = .{ 0.0, 0.5 },
                    },
                },
            },
        },
        .mesh = MeshSettings{
            .thickness = 0.05,
            .leaves = .{
                .split_depth = 4,
                .length = 1.4,
                .breadth = 0.7,
            },
            .growth_to_thickness = .{
                .y_values = &.{ 0.0025, 0.035 },
                .x_range = .{ 0.0, 1.0 },
            },
        },
    };
    pub const litte_tree = .{
        .structure = Settings{
            .start_size = 1,
            .start_growth = 1,
            .depth_definitions = &[_]DepthDefinition{
                .{
                    .split_amount = 10,
                    .flatness = 0.0,
                    .size = 0.4,
                    .height_spread = 0.6,
                    .branch_pitch = 50.0 * math.rad_per_deg,
                    .branch_roll = 90.0 * math.rad_per_deg,
                    .height_to_growth = .{
                        .y_values = &.{ 1.0, 1.0, 0.0 },
                        .x_range = .{ 0.0, 1.0 },
                    },
                },
                .{
                    .split_amount = 6,
                    .flatness = 0.3,
                    .size = 0.45,
                    .height_spread = 0.8,
                    .branch_pitch = 60.0 * math.rad_per_deg,
                    .branch_roll = 90.0 * math.rad_per_deg,
                    .height_to_growth = .{
                        .y_values = &.{ 1.0, 1.0, 0.0 },
                        .x_range = .{ 0.0, 1.0 },
                    },
                },
                .{
                    .split_amount = 10,
                    .flatness = 0.0,
                    .size = 0.5,
                    .height_spread = 0.8,
                    .branch_pitch = 40.0 * math.rad_per_deg,
                    .branch_roll = 90.0 * math.rad_per_deg,
                    .height_to_growth = .{
                        .y_values = &.{ 1.0, 1.0, 0.0 },
                        .x_range = .{ 0.0, 1.0 },
                    },
                },
            },
        },
        .mesh = MeshSettings{
            .thickness = 0.05,
            .leaves = .{
                .split_depth = 3,
                .length = 2.0,
                .breadth = 1.0,
            },
            .growth_to_thickness = .{
                .y_values = &.{ 0.0025, 0.035 },
                .x_range = .{ 0.0, 1.0 },
            },
        },
    };
};
