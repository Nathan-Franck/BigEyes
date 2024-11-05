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
const CoordIterator = @import("../CoordIterator.zig");
const wasm_entry = @import("../wasm_entry.zig");

const game = struct {
    pub const graph = @import("./graph.zig");
    pub const types = @import("./types.zig");
};

const ForestSpawner = Forest.spawner(ForestSettings);
const TerrainSpawner = Forest.spawner(struct {
    pub const Hemisphere = Forest.Tree{
        .density_tier = -1,
        .likelihood = 1,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const BigHemisphere = Forest.Tree{
        .density_tier = 2,
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
                .time = 0,
                .input = .{
                    .mouse_delta = .{ 0, 0, 0, 0 },
                    .movement = .{
                        .left = null,
                        .right = null,
                        .forward = null,
                        .backward = null,
                    },
                },
                .orbit_speed = 0.01,
                .selected_camera = .orbit,
                .player_settings = .{
                    .look_speed = 0.01,
                    .movement_speed = 0.8,
                },
                .render_resolution = .{ .x = 0, .y = 0 },
            },
            .store = .{
                .last_time = 0,
                .forest_chunk_cache = ForestSpawner.ChunkCache.init(std.heap.page_allocator),
                .player = .{
                    .position = .{ 0, -0.75, 0, 1 },
                    .euler_rotation = .{ 0, 0, 0, 1 },
                },
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
                allocator: std.mem.Allocator,
                props: struct {
                    time: u64,
                    last_time: u64,
                    orbit_speed: f32,
                    render_resolution: struct { x: i32, y: i32 },
                    input: struct {
                        mouse_delta: zm.Vec,
                        movement: struct {
                            left: ?u64,
                            right: ?u64,
                            forward: ?u64,
                            backward: ?u64,
                        },
                    },
                    orbit_camera: *game.types.OrbitCamera,
                    selected_camera: enum { orbit, first_person },
                    player_settings: struct { movement_speed: f32, look_speed: f32 },
                    player: *struct { position: Vec4, euler_rotation: Vec4 },
                    tier_index_to_influence_range: [TerrainSpawner.density_tiers.len]f32,
                },
            ) !struct {
                camera_position: Vec4,
                world_matrix: zm.Mat,
                last_time: u64,
            } {
                switch (props.selected_camera) {
                    .orbit => {
                        props.orbit_camera.rotation = props.orbit_camera.rotation +
                            props.input.mouse_delta *
                            zm.splat(Vec4, -props.orbit_speed);
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
                            .last_time = props.time,
                            .camera_position = zm.mul(zm.inverse(location), Vec4{ 0, 0, 0, 1 }),
                            .world_matrix = zm.mul(
                                location,
                                view_projection,
                            ),
                        };
                    },
                    .first_person => {

                        // Update rotation based on mouse input
                        props.player.euler_rotation = props.player.euler_rotation +
                            props.input.mouse_delta *
                            zm.splat(Vec4, -props.player_settings.look_speed);

                        // Create rotation matrix for movement direction
                        const rotation_matrix = zm.matFromRollPitchYaw(-props.player.euler_rotation[1], -props.player.euler_rotation[0], 0);

                        // Process horizontal movement (left/right)
                        const right = Vec4{ 1, 0, 0, 0 };
                        var horizontal_movement = Vec4{ 0, 0, 0, 0 };
                        const movement = props.input.movement;

                        if (movement.left != null and movement.right != null) {
                            // Both keys pressed, use most recent
                            if (movement.left.? > movement.right.?) {
                                horizontal_movement = horizontal_movement - right;
                            } else {
                                horizontal_movement = horizontal_movement + right;
                            }
                        } else if (movement.left != null) {
                            horizontal_movement = horizontal_movement - right;
                        } else if (movement.right != null) {
                            horizontal_movement = horizontal_movement + right;
                        }

                        // Process vertical movement (forward/backward)
                        const forward = Vec4{ 0, 0, 1, 0 };
                        var vertical_movement = Vec4{ 0, 0, 0, 0 };
                        if (movement.forward != null and movement.backward != null) {
                            // Both keys pressed, use most recent
                            if (movement.forward.? > movement.backward.?) {
                                vertical_movement = vertical_movement + forward;
                            } else {
                                vertical_movement = vertical_movement - forward;
                            }
                        } else if (movement.forward != null) {
                            vertical_movement = vertical_movement + forward;
                        } else if (movement.backward != null) {
                            vertical_movement = vertical_movement - forward;
                        }

                        // Combine movements
                        const combined_movement = horizontal_movement + vertical_movement;

                        if (zm.length3(combined_movement)[0] > 0.001) {
                            const delta_time = @as(f32, @floatFromInt(props.time - props.last_time)) / 1000.0;
                            const final_movement = zm.mul(
                                zm.normalize3(combined_movement),
                                rotation_matrix,
                            ) * zm.splat(Vec4, props.player_settings.movement_speed * delta_time);

                            var new_position = props.player.position;
                            new_position[0] += final_movement[0];
                            new_position[2] += final_movement[2];

                            var terrain_chunk_cache = TerrainSpawner.ChunkCache.init(allocator);
                            const terrain_height = try sampleTerrainStamps(
                                allocator,
                                &terrain_chunk_cache,
                                props.tier_index_to_influence_range,
                                Vec2{ new_position[0], new_position[2] },
                            );
                            new_position[1] = terrain_height + 1.2; // Add eye height offset
                            props.player.position = new_position;
                        }

                        // Create view matrix
                        const view_projection = zm.perspectiveFovLh(
                            0.25 * 3.14151,
                            @as(f32, @floatFromInt(props.render_resolution.x)) /
                                @as(f32, @floatFromInt(props.render_resolution.y)),
                            0.1,
                            500,
                        );

                        const location = zm.mul(
                            zm.translationV(-props.player.position),
                            zm.inverse(rotation_matrix),
                        );

                        return .{
                            .last_time = props.time,
                            .camera_position = zm.mul(zm.inverse(location), Vec4{ 0, 0, 0, 1 }),
                            .world_matrix = zm.mul(
                                location,
                                view_projection,
                            ),
                        };
                    },
                }
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
                    tier_index_to_influence_range: [TerrainSpawner.density_tiers.len]f32,
                },
            ) !struct {
                forest_data: []const game.types.ModelInstances,
            } {
                const spawns = try ForestSpawner.gatherSpawnsInBounds(
                    allocator,
                    props.forest_chunk_cache,
                    demo_terrain_bounds,
                );
                var instances = try allocator.alloc(std.ArrayList(Vec4), ForestSpawner.length);
                for (instances) |*instance| {
                    instance.* = std.ArrayList(Vec4).init(allocator);
                }
                var terrain_chunk_cache = TerrainSpawner.ChunkCache.init(allocator);
                for (spawns) |spawn| {
                    const pos_2d = Vec2{ spawn.position[0], spawn.position[1] };
                    const height = try sampleTerrainStamps(
                        allocator,
                        &terrain_chunk_cache,
                        props.tier_index_to_influence_range,
                        pos_2d,
                    );
                    const position = Vec4{ spawn.position[0], height, spawn.position[1], 1 };
                    try instances[spawn.id].append(position);
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

            fn raytraceCell(
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
                const safe_check = false; // Don't do this check since we know that it's fine
                inline fn sample(self: @This(), coord: Coord) f32 {
                    if (safe_check) {
                        if (coord[0] < 0 or coord[1] < 0 or coord[0] >= self.resolution.x or coord[1] >= self.resolution.y)
                            return 0;
                    }
                    const index = @as(usize, @intCast(coord[0] + coord[1] * @as(i32, @intCast(self.resolution.x))));
                    return self.heights[index];
                }

                fn getHeight(
                    stamp: @This(),
                    spawn_pos: Vec2,
                    pos_2d: Vec2,
                ) ?f32 {
                    const rel_pos = (pos_2d - spawn_pos) / @as(Vec2, @splat(stamp.size));
                    const stamp_pos = (rel_pos + @as(Vec2, @splat(0.5))) * Vec2{
                        @floatFromInt(stamp.resolution.x - 1),
                        @floatFromInt(stamp.resolution.y - 1),
                    };

                    if (@reduce(.Or, stamp_pos < @as(Vec2, @splat(1))) or
                        @reduce(.Or, stamp_pos >= @as(Vec2, @splat(@floatFromInt(stamp.resolution.x - 1)))))
                    {
                        return null;
                    }
                    const pos0 = @floor(stamp_pos);
                    const pos_int: Coord = @intFromFloat(pos0);
                    const fract = stamp_pos - pos0;

                    const h00 = stamp.sample(pos_int + Coord{ 0, 0 });
                    const h10 = stamp.sample(pos_int + Coord{ 1, 0 });
                    const h01 = stamp.sample(pos_int + Coord{ 0, 1 });
                    const h11 = stamp.sample(pos_int + Coord{ 1, 1 });

                    // Interpolate using vector operations
                    const h0 = h00 * (1 - fract[0]) + h10 * fract[0];
                    const h1 = h01 * (1 - fract[0]) + h11 * fract[0];
                    const stamp_height = h0 * (1 - fract[1]) + h1 * fract[1];
                    return stamp_height;
                }
            };
            const TerrainStamps = struct {
                pub const Hemisphere: Stamp = blk: {
                    @setEvalBranchQuota(100000);
                    const resolution = .{ .x = 16, .y = 16 };
                    var heights: [resolution.x * resolution.y]f32 = undefined;
                    for (0..resolution.y) |y| {
                        for (0..resolution.x) |x| {
                            const v = Vec4{ @floatFromInt(x), @floatFromInt(y), 0, 0 } /
                                zm.splat(Vec4, @floatFromInt(@max(resolution.x, resolution.y))) -
                                zm.splat(Vec4, 0.5);
                            heights[x + y * resolution.x] = @max(
                                0,
                                std.math.sqrt(
                                    1 - std.math.pow(f32, zm.length2(v)[0] * 2, 2),
                                ),
                            ) * 0.5;
                        }
                    }
                    const heights_static = heights;
                    break :blk .{
                        .resolution = resolution,
                        .heights = &heights_static,
                        .size = 1,
                    };
                };
                pub const BigHemisphere: Stamp = blk: {
                    @setEvalBranchQuota(100000);
                    const resolution = .{ .x = 32, .y = 32 };
                    var heights: [resolution.x * resolution.y]f32 = undefined;
                    for (0..resolution.y) |y| {
                        for (0..resolution.x) |x| {
                            const v = Vec4{ @floatFromInt(x), @floatFromInt(y), 0, 0 } /
                                zm.splat(Vec4, @floatFromInt(@max(resolution.x, resolution.y))) -
                                zm.splat(Vec4, 0.5);
                            heights[x + y * resolution.x] = @max(
                                0,
                                std.math.sqrt(
                                    1 - std.math.pow(f32, zm.length2(v)[0] * 2, 2),
                                ),
                            ) * 1.5;
                        }
                    }
                    const heights_static = heights;
                    break :blk .{
                        .resolution = resolution,
                        .heights = &heights_static,
                        .size = 3,
                    };
                };
            };

            pub fn sampleTerrainStamps(
                allocator: std.mem.Allocator,
                terrain_chunk_cache: *TerrainSpawner.ChunkCache,
                tier_index_to_influence_range: [TerrainSpawner.density_tiers.len]f32,
                pos_2d: Vec2,
            ) !f32 {
                const bounds = blk: {
                    var bounds: [tier_index_to_influence_range.len]Bounds = undefined;
                    for (tier_index_to_influence_range, 0..) |influence_range, tier_index| {
                        const size_2d = @as(Vec2, @splat(influence_range));
                        bounds[tier_index] = Bounds{
                            .min = pos_2d - size_2d * @as(Vec2, @splat(0.5)),
                            .size = size_2d,
                        };
                    }
                    break :blk bounds;
                };

                const spawns = try TerrainSpawner.gatherSpawnsInBoundsPerTier(
                    allocator,
                    terrain_chunk_cache,
                    &bounds,
                );
                var height: f32 = 0;
                const Stamps = @typeInfo(TerrainStamps).@"struct".decls;
                var index_to_stamp_data: [Stamps.len]Stamp = undefined;
                inline for (Stamps, 0..) |decl, stamp_index| {
                    index_to_stamp_data[stamp_index] = @field(TerrainStamps, decl.name);
                }

                for (spawns) |spawn| {
                    const stamp = index_to_stamp_data[spawn.id];
                    if (stamp.getHeight(spawn.position, pos_2d)) |stamp_height|
                        height = @max(height, stamp_height);
                }

                return height;
            }

            pub fn calculateTerrainDensityInfluenceRange(
                allocator: std.mem.Allocator,
                _: struct {},
            ) !struct {
                tier_index_to_influence_range: [TerrainSpawner.density_tiers.len]f32,
            } {
                var tier_index_to_influence_range = std.ArrayList(f32).init(allocator);
                for (TerrainSpawner.density_tiers) |maybe_tier|
                    try tier_index_to_influence_range.append(if (maybe_tier) |tier| blk: {
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
                    } else 0);

                wasm_entry.dumpDebugLogFmt("Tier influence {any}\n", .{tier_index_to_influence_range.items});
                const pos_2d = Vec2{ 0, 0 };
                const bounds = blk: {
                    var bounds = try allocator.alloc(Bounds, tier_index_to_influence_range.items.len);
                    for (tier_index_to_influence_range.items, 0..) |influence_range, tier_index| {
                        const size_2d = @as(Vec2, @splat(influence_range));
                        bounds[tier_index] = Bounds{
                            .min = pos_2d - size_2d * @as(Vec2, @splat(0.5)),
                            .size = size_2d,
                        };
                    }
                    wasm_entry.dumpDebugLogFmt("Bounds {any}\n", .{bounds});
                    break :blk bounds;
                };
                _ = bounds;
                return .{
                    .tier_index_to_influence_range = tier_index_to_influence_range.items[0..TerrainSpawner.density_tiers.len].*,
                };
            }

            const demo_terrain_bounds = Bounds{
                .min = .{ -16, -16 },
                .size = .{ 32, 32 },
            };
            pub fn displayTerrain(
                allocator: std.mem.Allocator,
                props: struct {
                    tier_index_to_influence_range: [TerrainSpawner.density_tiers.len]f32,
                },
            ) !struct {
                terrain_mesh: game.types.GreyboxMesh,
                terrain_instance: game.types.ModelInstances,
            } {
                var terrain_chunk_cache = TerrainSpawner.ChunkCache.init(allocator);
                try terrain_chunk_cache.ensureTotalCapacity(256);
                // const terrain_resolution = 512;
                const terrain_resolution = 128;

                var vertex_iterator = CoordIterator.init(@splat(0), @splat(terrain_resolution + 1));
                var positions = std.ArrayList(Vec4).init(allocator);
                while (vertex_iterator.next()) |vertex_coord| {
                    var stack_allocator = std.heap.stackFallback(1024, allocator); // TODO: Calculate how big the stack should be, maybe should OOM so that I know when we went to slow-mode (Super cool that one line can save 100ms for a 512*512 terrain)
                    // var buffer: [4096]u8 = undefined;
                    // var stack_allocator = std.heap.FixedBufferAllocator.init(&buffer);
                    const pos_2d: Vec2 = demo_terrain_bounds.min +
                        @as(Vec2, @floatFromInt(vertex_coord)) *
                        demo_terrain_bounds.size /
                        @as(Vec2, @splat(terrain_resolution));
                    const height = try sampleTerrainStamps(
                        stack_allocator.get(),
                        &terrain_chunk_cache,
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
