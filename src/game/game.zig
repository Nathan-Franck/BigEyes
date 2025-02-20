const std = @import("std");

const zmath = @import("zmath");

// Hey! You can totally create code before the build starts!
const gen = @import("generated");
const _ = gen.GeneratedData;

const CoordIterator = @import("../CoordIterator.zig");
const Bounds = @import("../forest.zig").Bounds;
const Coord = @import("../forest.zig").Coord;
const Vec2 = @import("../forest.zig").Vec2;
const Vec4 = @import("../forest.zig").Vec4;
const graph_runtime = @import("../graph_runtime.zig");
const Image = @import("../Image.zig");
const mesh_helper = @import("../mesh_helper.zig");
const mesh_loader = @import("../mesh_loader.zig");
const raytrace = @import("../raytrace.zig");
const subdiv = @import("../subdiv.zig");
const tree = @import("../tree.zig");
const queryable = @import("../utils.zig").queryable;
const math = @import("../vec_math.zig");

pub const debugPrint = if (@import("builtin").target.cpu.arch.isWasm())
    @import("../wasm_entry.zig").dumpDebugLogFmt
else
    std.debug.print;

pub const game = struct {
    pub const graph = @import("./graph.zig");
    pub const types = @import("./types.zig");
    pub const config = @import("./config.zig");
};
const Forest = game.config.Forest;
const TerrainSampler = game.config.TerrainSampler;

pub const graph_inputs: NodeGraph.SystemInputs = .{
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
        .look_speed = 0.004,
        .movement_speed = 0.8,
    },
    .render_resolution = .{ .x = 0, .y = 0 },
    .size_multiplier = 1,
    .bounce = false,
};

pub const graph_store: NodeGraph.SystemStore = .{
    .last_time = 0,
    .forest_chunk_cache = game.config.ForestSpawner.ChunkCache.init(std.heap.page_allocator),
    .player = .{
        .position = .{ 0, -0.75, 0, 1 },
        .euler_rotation = .{ 0, 0, 0, 1 },
    },
    .orbit_camera = .{
        .position = .{ 0, -0.75, 0, 1 },
        .rotation = .{ 0, 0, 0, 1 },
        .track_distance = 10,
    },
};

pub const InterfaceEnum = std.meta.DeclEnum(interface);
pub const interface = struct {
    var node_graph: NodeGraph = undefined;

    pub const getGraphJson = NodeGraph.getDisplayDefinition;

    pub fn init() void {
        node_graph = try NodeGraph.init(.{
            .allocator = std.heap.page_allocator,
            .inputs = graph_inputs,
            .store = graph_store,
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
};

pub const NodeGraph = graph_runtime.NodeGraph(
    game.graph.blueprint,
    graph_nodes,
);

pub const graph_nodes = struct {
    pub fn calculateTerrainDensityInfluenceRange(
        arena: std.mem.Allocator,
        props: struct { size_multiplier: f32 },
    ) !struct {
        terrain_sampler: TerrainSampler,
    } {
        return .{
            .terrain_sampler = try TerrainSampler.init(arena, .{
                .size_multiplier = props.size_multiplier,
            }),
        };
    }

    pub fn getResources(arena: std.mem.Allocator, _: struct {}) !game.types.Resources {
        const result = try mesh_loader.loadModelsFromBlends(arena, &.{
            .{ .model_name = "ebike" },
            .{ .model_name = "Sonic (rough)", .subdiv_level = 2 },
        });

        const skybox = blk: {
            var images: game.types.ProcessedCubeMap = undefined;
            inline for (@typeInfo(game.types.ProcessedCubeMap).@"struct".fields) |field| {
                const image_png = @embedFile("../content/cloudy skybox/" ++ field.name ++ ".png");
                const image_data = try Image.loadPngAndProcess(arena, image_png);
                @field(images, field.name) = image_data;
            }
            break :blk images;
        };

        const cutout_leaf = blk: {
            const diffuse = try Image.loadPng(arena, @embedFile("../content/manitoba maple/diffuse.png"));
            const alpha = try Image.loadPng(arena, @embedFile("../content/manitoba maple/alpha.png"));
            const cutout_diffuse = Image.Rgba32Image{
                .width = diffuse.width,
                .height = diffuse.height,
                .pixels = try arena.alloc(@TypeOf(diffuse.pixels[0]), diffuse.pixels.len),
            };
            for (cutout_diffuse.pixels, 0..) |*pixel, pixel_index| {
                pixel.* = diffuse.pixels[pixel_index];
                pixel.*.a = alpha.pixels[pixel_index].r;
            }
            break :blk try Image.processImageForGPU(arena, cutout_diffuse);
        };

        var trees = std.ArrayList(game.types.TreeMesh).init(arena);
        inline for (@typeInfo(game.config.ForestSettings).@"struct".decls) |decl| {
            const tree_blueprint = @field(game.config.Trees, decl.name);
            const tree_skeleton = try tree.generateStructure(arena, tree_blueprint.structure);
            const bark_mesh = try tree.generateTaperedWood(arena, tree_skeleton, tree_blueprint.mesh);
            const leaf_mesh = try tree.generateLeaves(arena, tree_skeleton, tree_blueprint.mesh);
            const bounds = raytrace.Bounds.encompassBounds(
                raytrace.Bounds.encompassPoints(bark_mesh.vertices.slice().items(.position)),
                raytrace.Bounds.encompassPoints(leaf_mesh.vertices.slice().items(.position)),
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
            .models = result.models.items,
            .model_transforms = result.model_transforms,
            .skybox = skybox,
            .cutout_leaf = cutout_leaf,
            .trees = trees.items,
        };
    }

    var start: u64 = 0;
    pub fn timing(props: struct {
        time: u64,
        last_time: u64,
    }) struct {
        last_time: u64,
        delta_time: f32,
        seconds_since_start: f32,
    } {
        if (start == 0) start = props.time;
        const delta_time = @as(f32, @floatFromInt(props.time - props.last_time)) / 1000.0;
        const seconds_since_start = @as(f32, @floatFromInt(props.time - start)) / 1000.0;
        return .{
            .last_time = props.time,
            .seconds_since_start = seconds_since_start,
            .delta_time = delta_time,
        };
    }

    pub fn orbit(
        arena: std.mem.Allocator,
        props: struct {
            delta_time: queryable.Value(f32),
            orbit_speed: f32,
            render_resolution: struct { x: i32, y: i32 },
            input: struct {
                mouse_delta: zmath.Vec,
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
            terrain_sampler: TerrainSampler,
        },
    ) !struct {
        camera_position: Vec4,
        world_matrix: zmath.Mat,
    } {
        switch (props.selected_camera) {
            .orbit => {
                props.orbit_camera.rotation = props.orbit_camera.rotation +
                    props.input.mouse_delta *
                    zmath.splat(Vec4, -props.orbit_speed);
                const view_projection = zmath.perspectiveFovLh(
                    0.25 * 3.14151,
                    @as(f32, @floatFromInt(props.render_resolution.x)) /
                        @as(f32, @floatFromInt(props.render_resolution.y)),
                    0.1,
                    500,
                );
                const location = location: {
                    const t = zmath.translationV(props.orbit_camera.position);
                    const r = .{
                        .y = zmath.matFromRollPitchYaw(0, props.orbit_camera.rotation[0], 0),
                        .x = zmath.matFromRollPitchYaw(props.orbit_camera.rotation[1], 0, 0),
                    };
                    const offset = zmath.translationV(zmath.loadArr3(.{ 0.0, 0.0, props.orbit_camera.track_distance }));
                    break :location zmath.mul(t, zmath.mul(zmath.mul(r.y, r.x), offset));
                };

                return .{
                    .camera_position = zmath.mul(zmath.inverse(location), Vec4{ 0, 0, 0, 1 }),
                    .world_matrix = zmath.mul(
                        location,
                        view_projection,
                    ),
                };
            },
            .first_person => {
                props.player.euler_rotation = props.player.euler_rotation +
                    props.input.mouse_delta *
                    zmath.splat(Vec4, -props.player_settings.look_speed);

                const rotation_matrix = zmath.matFromRollPitchYaw(
                    -props.player.euler_rotation[1],
                    -props.player.euler_rotation[0],
                    0,
                );

                const right = Vec4{ 1, 0, 0, 0 };
                const forward = Vec4{ 0, 0, 1, 0 };

                var horizontal_movement = Vec4{ 0, 0, 0, 0 };
                const movement = props.input.movement;

                if (movement.left != null and movement.right != null) {
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

                var vertical_movement = Vec4{ 0, 0, 0, 0 };
                if (movement.forward != null and movement.backward != null) {
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

                const combined_movement = horizontal_movement + vertical_movement;

                if (zmath.length3(combined_movement)[0] > 0.001) {
                    const final_movement = blk: {
                        const world_direction = zmath.mul(zmath.normalize3(combined_movement), rotation_matrix);
                        const movement_delta: Vec4 = @splat(props.player_settings.movement_speed * props.delta_time.get());
                        break :blk world_direction * movement_delta;
                    };

                    var new_position = props.player.position;
                    new_position += final_movement;

                    var terrain_chunk_cache = game.config.TerrainSpawner.ChunkCache.init(arena);
                    const terrain_height = try props.terrain_sampler
                        .loadCache(&terrain_chunk_cache)
                        .sample(arena, Vec2{ new_position[0], new_position[2] });

                    new_position[1] = terrain_height + 0.7;

                    props.player.position = new_position;
                }

                const view_projection = zmath.perspectiveFovLh(
                    0.25 * 3.14151,
                    @as(f32, @floatFromInt(props.render_resolution.x)) /
                        @as(f32, @floatFromInt(props.render_resolution.y)),
                    0.1,
                    500,
                );

                const location = zmath.mul(
                    zmath.translationV(-props.player.position),
                    zmath.inverse(rotation_matrix),
                );

                return .{
                    .camera_position = zmath.mul(zmath.inverse(location), Vec4{ 0, 0, 0, 1 }),
                    .world_matrix = zmath.mul(
                        location,
                        view_projection,
                    ),
                };
            },
        }
    }

    pub fn getScreenspaceMesh(
        arena: std.mem.Allocator,
        props: struct {
            camera_position: Vec4,
            world_matrix: zmath.Mat,
        },
    ) !struct { screen_space_mesh: struct {
        indices: []const u32,
        uvs: []const Vec2,
        normals: []const Vec4,
    } } {
        const inverse_view_projection = zmath.inverse(props.world_matrix);
        var normals: [4]Vec4 = undefined;
        for (
            &normals,
            [_]Vec4{
                .{ -1, -1, 1, 1 },
                .{ 1, -1, 1, 1 },
                .{ 1, 1, 1, 1 },
                .{ -1, 1, 1, 1 },
            },
        ) |*normal, screen_position| {
            const world_position = zmath.mul(screen_position, inverse_view_projection);
            normal.* = zmath.normalize3(
                world_position - props.camera_position,
            );
        }
        return .{ .screen_space_mesh = .{
            .indices = try arena.dupe(u32, &.{
                0, 1, 2,
                2, 3, 0,
            }),
            .uvs = try arena.dupe(Vec2, &.{
                .{ 0, 0 },
                .{ 1, 0 },
                .{ 1, 1 },
                .{ 0, 1 },
            }),
            .normals = try arena.dupe(Vec4, &normals),
        } };
    }

    pub fn displayForest(
        arena: std.mem.Allocator,
        props: struct {
            forest_chunk_cache: *game.config.ForestSpawner.ChunkCache,
            terrain_sampler: TerrainSampler,
        },
    ) !struct {
        model_instances: []const game.types.ModelInstances,
    } {
        var terrain_chunk_cache = game.config.TerrainSpawner.ChunkCache.init(arena);
        const terrain_sampler = props.terrain_sampler.loadCache(&terrain_chunk_cache);

        const spawns = try game.config.ForestSpawner.gatherSpawnsInBounds(
            arena,
            props.forest_chunk_cache,
            game.config.demo_terrain_bounds,
        );

        const InstanceEntry = struct { position: Vec4, rotation: Vec4, scale: Vec4 };
        var instances = try arena.alloc(std.ArrayList(InstanceEntry), game.config.ForestSpawner.length);
        for (instances) |*position| {
            position.* = std.ArrayList(InstanceEntry).init(arena);
        }
        for (spawns) |spawn| {
            const pos_2d = Vec2{ spawn.position[0], spawn.position[1] };
            const height = try terrain_sampler.sample(arena, pos_2d);
            try instances[spawn.id].append(.{
                .position = .{ spawn.position[0], height, spawn.position[1], 1 },
                .rotation = zmath.qidentity(),
                .scale = .{ 1, 1, 1, 0 },
            });
        }
        const instances_items = try arena.alloc(game.types.ModelInstances, game.config.ForestSpawner.length);
        for (instances_items, @typeInfo(game.config.ForestSettings).@"struct".decls, 0..) |*instance, decl, i| {
            instance.* = .{
                .label = decl.name,
                .positions = positions: {
                    const res = try arena.alloc(Vec4, instances[i].items.len);
                    for (instances[i].items, 0..) |entry, j| {
                        res[j] = entry.position;
                    } else break :positions res;
                },
                .rotations = rotations: {
                    const res = try arena.alloc(Vec4, instances[i].items.len);
                    for (instances[i].items, 0..) |entry, j| {
                        res[j] = entry.rotation;
                    } else break :rotations res;
                },
                .scales = scales: {
                    const res = try arena.alloc(Vec4, instances[i].items.len);
                    for (instances[i].items, 0..) |entry, j| {
                        res[j] = entry.scale;
                    } else break :scales res;
                },
            };
        }

        return .{
            .model_instances = instances_items,
        };
    }

    pub fn displayBike(
        arena: std.mem.Allocator,
        props: struct {
            seconds_since_start: queryable.Value(f32),
            model_transforms: std.StringHashMap(zmath.Mat),
            terrain_sampler: TerrainSampler,
            bounce: bool,
        },
    ) !struct {
        model_instances: []const game.types.ModelInstances,
    } {
        var terrain_chunk_cache = game.config.TerrainSpawner.ChunkCache.init(arena);
        const terrain_sampler = props.terrain_sampler.loadCache(&terrain_chunk_cache);
        _ = terrain_sampler;

        var instances = std.ArrayList(game.types.ModelInstances).init(arena);
        const Entry = struct { name: []const u8, offset: Vec4 };
        for (&[_]Entry{
            .{ .name = "Sonic (rough)_Cube", .offset = .{ 4, 0, 0, 0 } },
            .{ .name = "ebike_front-wheel", .offset = .{ 0, 0, 0, 0 } },
            .{ .name = "ebike_back-wheel", .offset = .{ 0, 0, 0, 0 } },
            .{ .name = "ebike_body", .offset = .{ 0, 0, 0, 0 } },
            .{ .name = "ebike_handlebars", .offset = .{ 0, 0, 0, 0 } },
            .{ .name = "ebike_shock", .offset = .{ 0, 0, 0, 0 } },
        }) |entry| {
            const label = entry.name;
            const transform = props.model_transforms.get(label).?;
            // const offset = if (props.bounce) offset: {
            //     const up = Vec4{ 0, 1, 0, 0 };
            //     const bounce: Vec4 = @splat(@sin(props.seconds_since_start.get()));
            //     break :offset up * bounce;
            // } else Vec4{ 0, 0, 0, 0 };
            try instances.append(.{
                .label = label,
                .positions = try arena.dupe(Vec4, &.{zmath.loadArr3w(zmath.vecToArr3(transform[3] + entry.offset), 1)}),
                .rotations = try arena.dupe(Vec4, &.{zmath.matToQuat(transform)}),
                .scales = try arena.dupe(Vec4, &.{.{ zmath.length3(transform[0])[0], zmath.length3(transform[1])[0], zmath.length3(transform[2])[0], 0 }}),
            });
        }

        return .{ .model_instances = instances.items };
    }

    /// Take all models, pull out the animatable ones, write them out after animating and subdividing them
    pub fn animateMeshes(
        arena: std.mem.Allocator,
        props: struct {
            seconds_since_start: f32,
            models: []const game.types.GameModel,
        },
    ) !struct {
        models: []const game.types.GameModel,
    } {
        var models = std.ArrayList(game.types.GameModel).init(arena);
        for (props.models) |model| {
            const mesh = model.meshes[0];
            switch (mesh) {
                .subdiv => |subdiv_mesh| {
                    const faces = subdiv_mesh.base_faces;
                    const positions = try arena.dupe(Vec4, subdiv_mesh.base_positions);
                    for (subdiv_mesh.base_bone_indices, positions) |i, *position| {
                        const bone_index: usize = @intCast(i);
                        const bone = subdiv_mesh.armature.bones[bone_index];
                        const animation = subdiv_mesh.armature.animation;
                        const fps = 12;
                        const inter_frame = props.seconds_since_start * fps;
                        const frame: usize = @intFromFloat(inter_frame);
                        const animated_bone = .{
                            animation[frame % animation.len].bones[bone_index],
                            animation[(frame + 1) % animation.len].bones[bone_index],
                        };
                        const lerp: Vec4 = @splat(inter_frame - @as(f32, @floatFromInt(frame)));
                        position.* = zmath.mul(
                            zmath.mul(
                                position.*,
                                zmath.inverse(
                                    mesh_loader.translationRotationScaleToMatrix(
                                        bone.rest.position,
                                        bone.rest.rotation,
                                        bone.rest.scale,
                                    ),
                                ),
                            ),
                            mesh_loader.translationRotationScaleToMatrix(
                                zmath.lerpV(animated_bone[0].position, animated_bone[1].position, lerp),
                                zmath.lerpV(animated_bone[0].rotation, animated_bone[1].rotation, lerp),
                                zmath.lerpV(animated_bone[0].scale, animated_bone[1].scale, lerp),
                            ),
                        );
                    }

                    var subdiv_result = try subdiv.Polygon(.Face).cmcSubdivOnlyPoints(arena, positions, faces);
                    const subdiv_levels = subdiv_mesh.quads_per_subdiv.len;
                    for (subdiv_mesh.quads_per_subdiv[0 .. subdiv_levels - 1]) |quads| {
                        subdiv_result = try subdiv.Polygon(.Quad).cmcSubdivOnlyPoints(arena, subdiv_result, quads);
                    }

                    try models.append(.{
                        .label = model.label,
                        .meshes = try arena.dupe(game.types.GameMesh, &[_]game.types.GameMesh{.{
                            .greybox = game.types.GreyboxMesh{
                                .indices = subdiv_mesh.top_indices,
                                .position = subdiv_result,
                                .normal = mesh_helper.Polygon(.Quad).calculateNormals(arena, subdiv_result, subdiv_mesh.quads_per_subdiv[subdiv_levels - 1]),
                            },
                        }}),
                    });
                },
                else => {},
            }
        }
        return .{ .models = models.items };
    }

    pub fn displayTrees(
        arena: std.mem.Allocator,
        props: struct {
            cutout_leaf: Image.Processed,
            trees: []const game.types.TreeMesh,
        },
    ) !struct {
        models: []const game.types.GameModel,
    } {
        var models = std.ArrayList(game.types.GameModel).init(arena);
        for (props.trees) |tree_mesh| {
            try models.append(.{
                .label = tree_mesh.label,
                .meshes = try arena.dupe(game.types.GameMesh, &.{
                    .{ .greybox = .{
                        .indices = tree_mesh.bark_mesh.triangles,
                        .normal = tree_mesh.bark_mesh.vertices.slice().items(.normal),
                        .position = tree_mesh.bark_mesh.vertices.slice().items(.position),
                    } },
                    .{ .textured = .{
                        .diffuse_alpha = props.cutout_leaf,
                        .indices = tree_mesh.leaf_mesh.triangles,
                        .normal = tree_mesh.leaf_mesh.vertices.slice().items(.normal),
                        .position = tree_mesh.leaf_mesh.vertices.slice().items(.position),
                        .uv = tree_mesh.leaf_mesh.vertices.slice().items(.uv),
                    } },
                }),
            });
        }
        return .{
            .models = models.items,
        };
    }

    pub noinline fn displayTerrain(
        arena: std.mem.Allocator,
        props: struct {
            terrain_sampler: TerrainSampler,
        },
    ) !struct {
        terrain_mesh: game.types.GreyboxMesh,
        terrain_instance: game.types.ModelInstances,
    } {
        var terrain_chunk_cache = game.config.TerrainSpawner.ChunkCache.init(arena);
        try terrain_chunk_cache.ensureTotalCapacity(256);
        const terrain_sampler = props.terrain_sampler.loadCache(&terrain_chunk_cache);

        // const terrain_resolution = 512;
        const terrain_resolution = 256;
        // const terrain_resolution = 128;

        var vertex_iterator = CoordIterator.init(@splat(0), @splat(terrain_resolution + 1));
        const positions = positions: {
            var positions = try arena.alloc(Vec4, vertex_iterator.total);
            var index: usize = 0;
            while (vertex_iterator.next()) |vertex_coord| : (index += 1) {
                // TODO: Calculate how big the stack should be, maybe should OOM so that I know when we went to slow-mode (Super cool that one line can save 100ms for a 512*512 terrain)
                var stack_arena = std.heap.stackFallback(1024, arena);

                const pos_2d: Vec2 = pos_2d: {
                    const res: Vec2 = @splat(terrain_resolution);
                    const span = game.config.demo_terrain_bounds.size / res;
                    const coord: Vec2 = @floatFromInt(vertex_coord);
                    break :pos_2d game.config.demo_terrain_bounds.min + (span * coord);
                };
                const height = try terrain_sampler.sample(stack_arena.get(), pos_2d);
                positions[index] = .{ pos_2d[0], height, pos_2d[1], 1 };
            }
            break :positions positions;
        };

        const quads = blk: {
            var quad_iterator = CoordIterator.init(@splat(0), @splat(terrain_resolution));
            var quads = try arena.alloc([4]u32, quad_iterator.total);
            var index: u32 = 0;
            while (quad_iterator.next()) |quad_coord| : (index += 1) {
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
                quads[index] = quad;
            }
            break :blk quads;
        };
        const indices = mesh_helper.Polygon(.Quad).toTriangleIndices(arena, quads);
        const normals = mesh_helper.Polygon(.Quad).calculateNormals(arena, positions, quads);

        return .{
            .terrain_mesh = game.types.GreyboxMesh{
                .indices = indices,
                .position = positions,
                .normal = normals,
            },
            .terrain_instance = game.types.ModelInstances{
                .label = "terrain",
                .positions = try arena.dupe(Vec4, &.{.{ 0, 0, 0, 1 }}),
                .rotations = try arena.dupe(Vec4, &.{zmath.qidentity()}),
                .scales = try arena.dupe(Vec4, &.{.{ 1, 1, 1, 0 }}),
            },
        };
    }
};
