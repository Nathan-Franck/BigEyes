const std = @import("std");
const graph_runtime = @import("../graph_runtime.zig");
const utils = @import("../utils.zig");
const subdiv = @import("../subdiv.zig");
const Image = @import("../Image.zig");
const raytrace = @import("../raytrace.zig");
const mesh_helper = @import("../mesh_helper.zig");
const MeshSpec = @import("../MeshSpec.zig");
const zm = @import("zmath");
const tree = @import("../tree.zig");
const Forest = @import("../forest.zig").Forest(16);
const Bounds = @import("../forest.zig").Bounds;
const Coord = @import("../forest.zig").Coord;
const Vec2 = @import("../forest.zig").Vec2;
const wasm_entry = @import("../wasm_entry.zig");
const CoordIterator = @import("../CoordIterator.zig");

const game = struct {
    pub const graph = @import("./graph.zig");
    pub const types = @import("./types.zig");
};

const ForestSpawner = Forest.spawner(ForestSettings);
const TerrainSpawner = Forest.spawner(struct {
    pub const Hemisphere = Forest.Tree{
        .density_tier = 1,
        .likelihood = 1,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
});

test "thinger" {
    const definitions = interface.NodeGraph.Definitions;
    _ = try definitions.calculateTerrainDensityInfluenceRange(std.testing.allocator, .{});
}
pub const InterfaceEnum = std.meta.DeclEnum(interface);
pub const interface = struct {
    var node_graph: NodeGraph = undefined;

    pub fn init() void {
        node_graph = try NodeGraph.init(.{
            .allocator = std.heap.page_allocator,
            .inputs = .{
                .input = null,
                .orbit_speed = 0.01,
                .render_resolution = .{ .x = 0, .y = 0 },
            },
            .store = .{
                .forest_chunk_cache = ForestSpawner.ChunkCache.init(std.heap.page_allocator),
                .terrain_chunk_cache = TerrainSpawner.ChunkCache.init(std.heap.page_allocator),
                .orbit_camera = .{
                    .position = .{ 0, -0.75, 0, 1 },
                    .rotation = .{ 0, 0, 0, 1 },
                    .track_distance = 2,
                },
            },
        });
    }

    pub fn updateNodeGraph(
        inputs: NodeGraph.PartialSystemInputs,
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

                var trees = std.ArrayList(game.types.TreeMesh).init(allocator);
                inline for (@typeInfo(ForestSettings).@"struct".decls) |decl| {
                    const tree_blueprint = @field(Trees, decl.name);
                    const tree_skeleton = try tree.generateStructure(allocator, tree_blueprint.structure);
                    const bark_mesh = try tree.generateTaperedWood(allocator, tree_skeleton, tree_blueprint.mesh);
                    const leaf_mesh = try tree.generateLeaves(allocator, tree_skeleton, tree_blueprint.mesh);
                    const bounds = raytrace.Bounds.encompassBounds(
                        raytrace.Bounds.encompassPoints(bark_mesh.vertices),
                        raytrace.Bounds.encompassPoints(leaf_mesh.vertices),
                    );
                    try trees.append(game.types.TreeMesh{
                        .label = decl.name,
                        .skeleton = tree_skeleton,
                        .bark_mesh = bark_mesh,
                        .leaf_mesh = leaf_mesh,
                        .bounds = bounds,
                    });
                }

                return game.types.Resources{
                    .skybox = skybox,
                    .cutout_leaf = cutout_leaf,
                    .trees = trees.items,
                };
            }

            pub fn orbit(
                props: struct {
                    orbit_speed: f32,
                    render_resolution: struct { x: i32, y: i32 },
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
                        @as(zm.Vec, @splat(-props.orbit_speed));
                }
                const view_projection = zm.perspectiveFovLh(
                    0.25 * 3.14151,
                    @as(f32, @floatFromInt(props.render_resolution.x)) /
                        @as(f32, @floatFromInt(props.render_resolution.y)),
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
                props: struct {
                    forest_chunk_cache: *ForestSpawner.ChunkCache,
                },
            ) !struct {
                forest_data: []const game.types.ModelInstances,
            } {
                const bounds = Bounds{
                    .min = .{ -4, -4 },
                    .size = .{ 8, 8 },
                };
                const spawns = try ForestSpawner.gatherSpawnsInBounds(allocator, props.forest_chunk_cache, bounds);
                var instances = try allocator.alloc(std.ArrayList(Vec4), ForestSpawner.length);
                for (instances) |*instance| {
                    instance.* = std.ArrayList(Vec4).init(allocator);
                }
                for (spawns) |spawn| {
                    try instances[spawn.id].append(spawn.position);
                }
                const instances_items = try allocator.alloc(game.types.ModelInstances, ForestSpawner.length);
                const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
                for (instances_items, @typeInfo(ForestSettings).@"struct".decls, 0..) |*instance, decl, i| {
                    instance.* = .{
                        .label = decl.name,
                        .positions = PointFlattener.convert(allocator, instances[i].items),
                    };
                }

                return .{
                    .forest_data = instances_items,
                };
            }

            pub fn displayTrees(
                allocator: std.mem.Allocator,
                props: struct {
                    cutout_leaf: Image.Processed,
                    trees: []game.types.TreeMesh,
                },
            ) !struct {
                models: []const game.types.GameModel,
            } {
                const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
                const UvFlattener = mesh_helper.VecSliceFlattener(2, 2);
                var models = std.ArrayList(game.types.GameModel).init(allocator);
                for (props.trees) |tree_mesh| {
                    try models.append(.{
                        .label = tree_mesh.label,
                        .meshes = try allocator.dupe(game.types.GameMesh, &.{
                            .{ .greybox = .{
                                .indices = tree_mesh.bark_mesh.triangles,
                                .normal = PointFlattener.convert(allocator, tree_mesh.bark_mesh.normals),
                                .position = PointFlattener.convert(allocator, tree_mesh.bark_mesh.vertices),
                            } },
                            .{ .textured = .{
                                .diffuse_alpha = props.cutout_leaf,
                                .indices = tree_mesh.leaf_mesh.triangles,
                                .normal = PointFlattener.convert(allocator, tree_mesh.leaf_mesh.normals),
                                .position = PointFlattener.convert(allocator, tree_mesh.leaf_mesh.vertices),
                                .uv = UvFlattener.convert(allocator, tree_mesh.leaf_mesh.uvs),
                            } },
                        }),
                    });
                }
                return .{
                    .models = models.items,
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

            const Stamp = struct {
                // Starting on the assumption that all stamps are centered, so no offset is needed
                size: f32,
                resolution: struct { x: u32, y: u32 },
                heights: []const f32,
                // mask: []f32, // Do we need a mask?
            };
            const TerrainStamps = struct {
                pub const Hemisphere: Stamp = blk: {
                    @setEvalBranchQuota(10000);
                    const resolution = .{ .x = 16, .y = 16 };
                    var heights: [resolution.x * resolution.y]f32 = undefined;
                    for (0..resolution.y) |y| {
                        for (0..resolution.x) |x| {
                            const v = Vec4{ @floatFromInt(x), @floatFromInt(y), 0, 0 } /
                                @as(Vec4, @splat(@floatFromInt(@max(resolution.x, resolution.y)))) -
                                @as(Vec4, @splat(0.5));
                            heights[x + y * resolution.x] = @max(1 - zm.length2(v)[0] * 2, 0);
                        }
                    }
                    const heights_static = heights;
                    break :blk .{
                        .resolution = resolution,
                        .heights = &heights_static,
                        .size = 1,
                    };
                };
            };

            pub fn sampleTerrainStamps(
                allocator: std.mem.Allocator,
                terrain_chunk_cache: *TerrainSpawner.ChunkCache,
                tier_index_to_influence_range: []const f32,
                pos_2d: Vec2,
            ) !f32 {
                const bounds = blk: {
                    var bounds = try allocator.alloc(Bounds, tier_index_to_influence_range.len);
                    for (tier_index_to_influence_range, 0..) |influence_range, tier_index| {
                        const size_2d = @as(Vec2, @splat(influence_range));
                        bounds[tier_index] = Bounds{ .min = pos_2d - size_2d * @as(Vec2, @splat(0.5)), .size = size_2d };
                    }
                    break :blk bounds;
                };
                const spawns = try TerrainSpawner.gatherSpawnsInBoundsPerTier(allocator, terrain_chunk_cache, bounds);

                var height: f32 = 0;
                const Stamps = @typeInfo(TerrainStamps).@"struct".decls;
                var index_to_stamp_data: [Stamps.len]Stamp = undefined;
                inline for (Stamps, 0..) |decl, stamp_index| {
                    index_to_stamp_data[stamp_index] = @field(TerrainStamps, decl.name);
                }

                for (spawns) |spawn| {
                    const stamp = index_to_stamp_data[spawn.id];
                    const spawn_pos = Vec2{ spawn.position[0], spawn.position[2] };
                    const rel_pos = (pos_2d - spawn_pos) / @as(Vec2, @splat(stamp.size));

                    const stamp_x = @as(u32, @intFromFloat((rel_pos[0] + 0.5) * @as(f32, @floatFromInt(stamp.resolution.x - 1))));
                    const stamp_y = @as(u32, @intFromFloat((rel_pos[1] + 0.5) * @as(f32, @floatFromInt(stamp.resolution.y - 1))));
                    if (stamp_x < 0 or stamp_x >= stamp.resolution.x or
                        stamp_y < 0 or stamp_y >= stamp.resolution.y)
                    {
                        continue;
                    }

                    const stamp_height = stamp.heights[stamp_x + stamp_y * stamp.resolution.x];

                    height = @max(height, stamp_height);
                }

                return height;
            }

            pub fn calculateTerrainDensityInfluenceRange(
                allocator: std.mem.Allocator,
                _: struct {},
            ) !struct {
                tier_index_to_influence_range: []const f32,
            } {
                wasm_entry.dumpDebugLogFmt("Calculating terrain density influence range", .{});
                var tier_index_to_influence_range = std.ArrayList(f32).init(allocator);
                for (TerrainSpawner.density_tiers) |maybe_tier| if (maybe_tier) |tier| {
                    wasm_entry.dumpDebugLogFmt("Calculating influence range for tier {d}", .{tier.density});
                    try tier_index_to_influence_range.append(blk: {
                        var trees = std.AutoArrayHashMap(TerrainSpawner.TreeId, void).init(allocator);
                        for (tier.tree_range) |maybe_tree_id| if (maybe_tree_id) |tree_id| {
                            const enum_tree_id: TerrainSpawner.TreeId = @enumFromInt(tree_id);
                            try trees.put(enum_tree_id, {});
                        } else continue;
                        const Stamps = @typeInfo(TerrainStamps).@"struct".decls;
                        var index_to_stamp_data: [Stamps.len]Stamp = undefined;
                        inline for (Stamps, 0..) |decl, stamp_index| {
                            index_to_stamp_data[stamp_index] = @field(TerrainStamps, decl.name);
                        }
                        var max_size: f32 = 0;
                        for (trees.keys()) |tree_index| {
                            const size = index_to_stamp_data[@intFromEnum(tree_index)].size;
                            max_size = @max(max_size, size);
                        }
                        break :blk max_size;
                    });
                };

                return .{
                    .tier_index_to_influence_range = tier_index_to_influence_range.items,
                };
            }

            pub noinline fn displayTerrain(
                allocator: std.mem.Allocator,
                props: struct {
                    tier_index_to_influence_range: []const f32,
                    terrain_chunk_cache: *TerrainSpawner.ChunkCache,
                },
            ) !struct {
                terrain_mesh: game.types.GreyboxMesh,
                terrain_instance: game.types.ModelInstances,
            } {
                const bounds = Bounds{
                    .min = .{ -4, -4 },
                    .size = .{ 8, 8 },
                };
                const terrain_resolution = 512;

                var vertex_iterator = CoordIterator.init(@splat(0), @splat(terrain_resolution + 1));
                var positions = std.ArrayList(Vec4).init(allocator);
                while (vertex_iterator.next()) |vertex_coord| {
                    const pos_2d: Vec2 = bounds.min +
                        @as(Vec2, @floatFromInt(vertex_coord)) *
                        bounds.size /
                        @as(Vec2, @splat(terrain_resolution));
                    const height = try sampleTerrainStamps(
                        allocator,
                        props.terrain_chunk_cache,
                        props.tier_index_to_influence_range,
                        pos_2d,
                    );
                    const vertex: Vec4 = .{
                        pos_2d[0],
                        height,
                        pos_2d[1],
                        1,
                    };
                    try positions.append(vertex);
                }
                var quad_iterator = CoordIterator.init(@splat(0), @splat(terrain_resolution));
                var quads = std.ArrayList([4]u32).init(allocator);
                while (quad_iterator.next()) |quad_coord| {
                    const quad_corners = &[_]Coord{
                        .{ 0, 0 },
                        .{ 1, 0 },
                        .{ 1, 1 },
                        .{ 0, 1 },
                    };
                    var quad: [4]u32 = undefined;
                    inline for (0..4) |quad_index| {
                        const quad_corner = quad_coord + quad_corners[quad_index];
                        quad[quad_index] = @intCast(quad_corner[0] + quad_corner[1] * vertex_iterator.width());
                    }
                    try quads.append(quad);
                }
                _ = .{
                    props,
                    bounds,
                    // &spawner,
                };
                const normals = mesh_helper.Polygon(.Quad).calculateNormals(allocator, positions.items, quads.items);
                const indices = mesh_helper.Polygon(.Quad).toTriangleIndices(allocator, quads.items);
                const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
                return .{
                    .terrain_mesh = game.types.GreyboxMesh{
                        .indices = indices,
                        .position = PointFlattener.convert(allocator, positions.items),
                        .normal = PointFlattener.convert(allocator, normals),
                    },
                    .terrain_instance = game.types.ModelInstances{
                        .label = "terrain",
                        .positions = PointFlattener.convert(allocator, &.{.{ 0, 0, 0, 0 }}),
                    },
                };
            }
        },
    );
};
const Vec4 = @Vector(4, f32);
const ForestSettings = struct {
    pub const grass1 = Forest.Tree{
        .density_tier = -2,
        .likelihood = 0.1,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const grass2 = Forest.Tree{
        .density_tier = -2,
        .likelihood = 0.05,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const little_tree = Forest.Tree{
        .density_tier = 1,
        .likelihood = 1,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const big_tree = Forest.Tree{
        .density_tier = 2,
        .likelihood = 1,
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
    pub const little_tree = .{
        .structure = Settings{
            .start_size = 0.6,
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
    pub const grass1 = .{
        .structure = Settings{
            .start_size = 0.3,
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
            },
        },
        .mesh = MeshSettings{
            .thickness = 0.05,
            .leaves = .{
                .split_depth = 2,
                .length = 2.0,
                .breadth = 1.0,
            },
            .growth_to_thickness = .{
                .y_values = &.{ 0.0025, 0.035 },
                .x_range = .{ 0.0, 1.0 },
            },
        },
    };
    pub const grass2 = .{
        .structure = Settings{
            .start_size = 0.2,
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
            },
        },
        .mesh = MeshSettings{
            .thickness = 0.05,
            .leaves = .{
                .split_depth = 1,
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
