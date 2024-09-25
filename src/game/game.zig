const std = @import("std");
const graph_runtime = @import("../graph_runtime.zig");
const utils = @import("../utils.zig");
const subdiv = @import("../subdiv.zig");
const Image = @import("../Image.zig");
const raytrace = @import("../raytrace.zig");
const mesh_helper = @import("../mesh_helper.zig");
const MeshSpec = @import("../MeshSpec.zig");
const zm = @import("../zmath/main.zig");
const tree = @import("../tree.zig");
const Forest = @import("../forest.zig").Forest(16);
const Bounds = @import("../forest.zig").Bounds;
const Coord = @import("../forest.zig").Coord;
const Vec2 = @import("../forest.zig").Vec2;
const wasm_entry = @import("../wasm_entry.zig");

const game = struct {
    pub const graph = @import("./graph.zig");
    pub const types = @import("./types.zig");
};

pub const InterfaceEnum = std.meta.DeclEnum(interface);
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
                    .track_distance = 5,
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

    const NodeGraph = graph_runtime.NodeGraph(
        game.graph.blueprint,
        struct {

            // TODO: Just take in optional values as input into the graph, so that this node isn't needed, obviously it's a waste of space.
            pub fn changeSettings(props: struct {
                settings: *game.types.Settings,
                user_changes: ?union(enum) {
                    resolution_update: game.types.PixelPoint,
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

            pub fn getResources(allocator: std.mem.Allocator, _: struct {}) !game.types.Resources {
                const skybox = blk: {
                    var images: game.types.ProcessedCubeMap = undefined;
                    inline for (@typeInfo(game.types.ProcessedCubeMap).@"struct".fields) |field| {
                        const image_png = @embedFile("../content/cloudy skybox/" ++ field.name ++ ".png");
                        const image_data = try Image.loadPngAndProcess(allocator, image_png);
                        @field(images, field.name) = image_data;
                    }
                    break :blk images;
                };

                const cutout_leaf = blk: {
                    const diffuse = try Image.loadPng(allocator, @embedFile("../content/manitoba maple/diffuse.png"));
                    const alpha = try Image.loadPng(allocator, @embedFile("../content/manitoba maple/alpha.png"));
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

                return game.types.Resources{
                    .skybox = skybox,
                    .cutout_leaf = cutout_leaf,
                    .tree = .{
                        .skeleton = tree_skeleton,
                        .bark_mesh = try tree.generateTaperedWood(allocator, tree_skeleton, Trees.big_tree.mesh),
                        .leaf_mesh = try tree.generateLeaves(allocator, tree_skeleton, Trees.big_tree.mesh),
                    },
                };
            }

            pub fn orbit(
                props: struct {
                    settings: game.types.Settings,
                    input: ?struct { mouse_delta: zm.Vec },
                    orbit_camera: *game.types.OrbitCamera,
                },
            ) !struct {
                camera_position: Vec4,
                world_matrix: zm.Mat,
            } {
                if (props.input) |found_input| {
                    props.orbit_camera.rotation = props.orbit_camera.rotation +
                        found_input.mouse_delta *
                        @as(zm.Vec, @splat(-props.settings.orbit_speed));
                }
                const view_projection = zm.perspectiveFovLh(
                    0.25 * 3.14151,
                    @as(f32, @floatFromInt(props.settings.render_resolution.x)) /
                        @as(f32, @floatFromInt(props.settings.render_resolution.y)),
                    0.1,
                    500,
                );
                const location = zm.mul(
                    zm.translationV(props.orbit_camera.position),
                    zm.mul(
                        zm.mul(
                            zm.matFromRollPitchYaw(0, props.orbit_camera.rotation[0], 0),
                            zm.matFromRollPitchYaw(props.orbit_camera.rotation[1], 0, 0),
                        ),
                        zm.translationV(zm.loadArr3(.{ 0.0, 0.0, props.orbit_camera.track_distance })),
                    ),
                );

                return .{
                    .camera_position = zm.mul(zm.inverse(location), Vec4{ 0, 0, 0, 1 }),
                    .world_matrix = zm.mul(
                        location,
                        view_projection,
                    ),
                };
            }

            pub fn getScreenspaceMesh(
                allocator: std.mem.Allocator,
                props: struct {
                    camera_position: Vec4,
                    world_matrix: zm.Mat,
                },
            ) !struct { screen_space_mesh: struct {
                indices: []const u32,
                uvs: []const f32,
                normals: []const f32,
            } } {
                const inverse_view_projection = zm.inverse(props.world_matrix);
                var normals: [4]Vec4 = undefined;
                for (
                    &normals,
                    [_]Vec4{
                        Vec4{ -1, -1, 1, 1 },
                        Vec4{ 1, -1, 1, 1 },
                        Vec4{ 1, 1, 1, 1 },
                        Vec4{ -1, 1, 1, 1 },
                    },
                ) |*normal, screen_position| {
                    const world_position = zm.mul(screen_position, inverse_view_projection);
                    wasm_entry.dumpDebugLogFmt("{any}", .{world_position});
                    normal.* = zm.normalize3(
                        world_position - props.camera_position,
                    );
                }
                const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
                const UvFlattener = mesh_helper.VecSliceFlattener(2, 2);
                return .{ .screen_space_mesh = .{
                    .indices = try allocator.dupe(u32, &.{
                        0, 1, 2,
                        2, 3, 0,
                    }),
                    .uvs = UvFlattener.convert(allocator, &.{
                        Vec2{ 0, 0 },
                        Vec2{ 1, 0 },
                        Vec2{ 1, 1 },
                        Vec2{ 0, 1 },
                    }),
                    .normals = PointFlattener.convert(allocator, &normals),
                } };
            }

            pub fn displayForest(
                allocator: std.mem.Allocator,
                _: struct {},
            ) !struct {
                forest_data: []const []const f32,
            } {
                const Spawner = Forest.spawner(ForestSettings);
                var spawner: Spawner = Spawner.init(allocator);
                const bounds = Bounds{
                    .min = .{ -4, -4 },
                    .size = .{ 8, 8 },
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
                    .forest_data = instances_items,
                };
            }

            pub fn displayTree(
                allocator: std.mem.Allocator,
                props: struct {
                    cutout_leaf: Image.Processed,
                    tree: game.types.TreeMesh,
                },
            ) !struct {
                meshes: []const game.types.GameMesh,
            } {
                const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
                const UvFlattener = mesh_helper.VecSliceFlattener(2, 2);
                var meshes = std.ArrayList(game.types.GameMesh).init(allocator);
                try meshes.appendSlice(&.{
                    .{ .greybox = .{
                        .label = "bark",
                        .indices = props.tree.bark_mesh.triangles,
                        .normal = PointFlattener.convert(allocator, props.tree.bark_mesh.normals),
                        .position = PointFlattener.convert(allocator, props.tree.bark_mesh.vertices),
                    } },
                    .{ .textured = .{
                        .label = "leaf",
                        .diffuse_alpha = props.cutout_leaf,
                        .indices = props.tree.leaf_mesh.triangles,
                        .normal = PointFlattener.convert(allocator, props.tree.leaf_mesh.normals),
                        .position = PointFlattener.convert(allocator, props.tree.leaf_mesh.vertices),
                        .uv = UvFlattener.convert(allocator, props.tree.leaf_mesh.uvs),
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
