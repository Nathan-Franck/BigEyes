const std = @import("std");

const zmath = @import("zmath");
const zbullet = @import("zbullet");

// Hey! You can totally create code before the build starts! Consider this for pulling tags out from Blender exports!
const gen = @import("generated");
const _ = gen.GeneratedData;

const node_graph = @import("node_graph");
const utils = @import("utils");
const resources = @import("resources");

const CoordIterator = utils.CoordIterator;
const Bounds = utils.Bounds;
const Coord = utils.Coord;
const Vec2 = utils.Vec2;
const Vec4 = utils.Vec4;
const Image = utils.Image;
const mesh_helper = utils.mesh_helper;
const raytrace = utils.raytrace;
const subdiv = utils.subdiv;
const tree = utils.tree;
const vec_math = utils.vec_math;
const print = std.debug.print;
const queryable = node_graph.utils_node.queryable;
const mesh_loader = resources.mesh_loader;
const config = resources.config;
const Forest = config.Forest;
const TerrainSampler = config.TerrainSampler;

pub const types = @import("utils").types;
pub const GameGraph = @import("game/graph.zig").GameGraph;

pub fn init(allocator: std.mem.Allocator) void {
    zbullet.init(allocator);
    graph_nodes.forest_chunk_cache = config.ForestSpawner.ChunkCache.init(allocator);
}

pub const graph_nodes = struct {
    pub fn terrain(
        arena: std.mem.Allocator,
        props: struct { size_multiplier: f32 },
    ) !struct {
        sampler: TerrainSampler,
    } {
        return .{
            .sampler = try TerrainSampler.init(arena, .{
                .size_multiplier = props.size_multiplier,
            }),
        };
    }

    pub fn getResources(arena: std.mem.Allocator, _: struct {}) !types.Resources {
        _ = arena;
        var res: types.Resources = undefined;
        resources.getResources(&res);
        return res;
    }

    var start: u64 = 0;
    pub fn timing(
        props: struct {
            time: u64,
        },
    ) struct {
        realtime: types.Timing,
        low_update: types.Timing,
    } {
        if (start == 0) start = props.time;
        const delta_time = @as(f32, @floatFromInt(props.time - last_time)) / 1000.0;
        const seconds_since_start = @as(f32, @floatFromInt(props.time - start)) / 1000.0;
        const low_update_rate = 15;
        const low_update_seconds_since_start = @floor(seconds_since_start * low_update_rate) / @as(f32, @floatFromInt(low_update_rate));
        last_time = props.time;
        return .{
            .realtime = .{
                .delta = delta_time,
                .seconds_since_start = seconds_since_start,
            },
            .low_update = .{
                .delta = 1000.0 / @as(f32, @floatFromInt(low_update_rate)),
                .seconds_since_start = low_update_seconds_since_start,
            },
        };
    }

    pub fn light(props: struct {}) struct { sun: types.DirectionalLight } {
        _ = props;
        const light_position = Vec4{ 20.0, 20.0, 20.0, 1.0 };
        const light_target = Vec4{ 0.0, 0.0, 0.0, 1.0 };
        const light_up = Vec4{ 0.0, 1.0, 0.0, 0.0 };
        const view = zmath.lookAtLh(light_position, light_target, light_up);
        const projection = zmath.orthographicLh(15.0, 15.0, 0.1, 50.0);
        return .{
            .sun = .{
                .view = view,
                .projection = projection,
                .direction = light_target - light_position,
                .view_projection = zmath.mul(view, projection),
            },
        };
    }

    pub fn shadow(arena: std.mem.Allocator, props: struct {
        light: types.DirectionalLight,
        all_models: []const types.GameModel,
        all_instances: []const types.ModelInstances,
        last_all_models: []const types.GameModel,
        last_all_instances: []const types.ModelInstances,
    }) !struct {} {
        var model_lookup = std.StringHashMap(types.GameModel).init(arena);
        for (props.all_models) |model| {
            try model_lookup.put(model.label, model);
        }
        for (props.last_all_instances, props.all_instances) |last_instances, instances| {
            const edits = utils.diff(types.Instance, arena, last_instances.instances, instances.instances);
            for (edits) |edit| {
                const referenced_instances = switch (edit.kind) {
                    .equal => continue,
                    .insert => instances,
                    .delete => last_instances,
                };
                for (edit.range.start..edit.range.end) |i| {
                    const instance_to_light = zmath.mul(
                        referenced_instances.instances[i].toMatrix(),
                        props.light.view_projection,
                    );
                    _ = instance_to_light;
                }
            }
        }
        return undefined;
    }

    var last_time: u64 = 0;

    pub fn orbit(
        arena: std.mem.Allocator,
        props: struct {
            timing: queryable.Value(types.Timing),
            orbit_speed: f32,
            render_resolution: types.PixelPoint,
            input: types.Input,
            orbit_camera: *types.OrbitCamera,
            selected_camera: types.SelectedCamera,
            player_settings: types.PlayerSettings,
            player: *types.Player,
            terrain_sampler: TerrainSampler,
        },
    ) !struct {
        camera_position: Vec4,
        world_matrix: zmath.Mat,
        exit: bool,
        lock_mouse: bool,
    } {
        const fov_y_degrees: f32 = 90;
        switch (props.selected_camera) {
            .orbit => {
                if (props.input.mouse.left_click)
                    props.orbit_camera.rotation = props.orbit_camera.rotation +
                        props.input.mouse.delta *
                            zmath.splat(Vec4, -props.orbit_speed);
                const projection_matrix = zmath.perspectiveFovLh(
                    fov_y_degrees * std.math.pi / 180,
                    @as(f32, @floatFromInt(props.render_resolution.x)) /
                        @as(f32, @floatFromInt(props.render_resolution.y)),
                    0.1,
                    500,
                );
                const view_matrix = location: {
                    const t = zmath.translationV(props.orbit_camera.position);
                    const r = .{
                        .y = zmath.matFromRollPitchYaw(0, props.orbit_camera.rotation[0], 0),
                        .x = zmath.matFromRollPitchYaw(props.orbit_camera.rotation[1], 0, 0),
                    };
                    const offset = zmath.translationV(zmath.loadArr3(.{ 0.0, 0.0, props.orbit_camera.track_distance }));
                    break :location zmath.mul(t, zmath.mul(zmath.mul(r.y, r.x), offset));
                };

                return .{
                    .exit = false,
                    .lock_mouse = false,
                    .camera_position = zmath.mul(Vec4{ 0, 0, 0, 1 }, zmath.inverse(view_matrix)),
                    .world_matrix = zmath.mul(
                        view_matrix,
                        projection_matrix,
                    ),
                };
            },
            .first_person => {
                if (props.input.mouse.left_click)
                    props.player.euler_rotation = props.player.euler_rotation +
                        props.input.mouse.delta *
                            zmath.splat(Vec4, -props.player_settings.look_speed);

                const rotation_matrix = zmath.matFromRollPitchYaw(
                    props.player.euler_rotation[1],
                    props.player.euler_rotation[0],
                    0,
                );

                const right = Vec4{ 1, 0, 0, 0 };
                const forward = Vec4{ 0, 0, 1, 0 };

                var horizontal_movement = Vec4{ 0, 0, 0, 0 };
                const movement = props.input.movement;

                if (movement.left) {
                    horizontal_movement = horizontal_movement - right;
                } else if (movement.right) {
                    horizontal_movement = horizontal_movement + right;
                }

                var vertical_movement = Vec4{ 0, 0, 0, 0 };
                if (movement.forward) {
                    vertical_movement = vertical_movement + forward;
                } else if (movement.backward) {
                    vertical_movement = vertical_movement - forward;
                }

                const combined_movement = horizontal_movement + vertical_movement;

                if (zmath.length3(combined_movement)[0] > 0.001) {
                    const final_movement = blk: {
                        const world_direction = zmath.mul(zmath.normalize3(combined_movement), rotation_matrix);
                        const movement_delta: Vec4 = @splat(props.player_settings.movement_speed * props.timing.get().delta);
                        break :blk world_direction * movement_delta;
                    };

                    var new_position = props.player.position;
                    new_position += final_movement;

                    var terrain_chunk_cache = config.TerrainSpawner.ChunkCache.init(arena);
                    const terrain_height = try props.terrain_sampler
                        .loadCache(&terrain_chunk_cache)
                        .sample(arena, Vec2{ new_position[0], new_position[2] });

                    new_position[1] = terrain_height + 0.3;

                    props.player.position = new_position;
                }

                const view_projection = zmath.perspectiveFovLh(
                    fov_y_degrees * std.math.pi / 180,
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
                    .exit = props.input.escape,
                    .lock_mouse = true,
                    .camera_position = zmath.mul(Vec4{ 0, 0, 0, 1 }, zmath.inverse(location)),
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
    ) !struct { screen_space_mesh: types.ScreenspaceMesh } {
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

    var forest_chunk_cache: config.ForestSpawner.ChunkCache = undefined;

    pub fn displayForest(
        arena: std.mem.Allocator,
        props: struct {
            terrain_sampler: TerrainSampler,
        },
    ) !struct {
        model_instances: []const types.ModelInstances,
    } {
        var terrain_chunk_cache = config.TerrainSpawner.ChunkCache.init(arena);
        const terrain_sampler = props.terrain_sampler.loadCache(&terrain_chunk_cache);

        const spawns = try config.ForestSpawner.gatherSpawnsInBounds(
            arena,
            &forest_chunk_cache,
            config.demo_terrain_bounds,
        );

        var tree_to_instance_list = try arena.alloc(std.ArrayList(types.Instance), config.ForestSpawner.length);
        for (tree_to_instance_list) |*instances| {
            instances.* = std.ArrayList(types.Instance).init(arena);
        }
        for (spawns) |spawn| {
            const pos_2d = Vec2{ spawn.position[0], spawn.position[1] };
            const height = try terrain_sampler.sample(arena, pos_2d);
            try tree_to_instance_list[spawn.id].append(.{
                .position = .{ spawn.position[0], height, spawn.position[1], 1 },
                .rotation = zmath.qidentity(),
                .scale = .{ 1, 1, 1, 0 },
            });
        }
        const instances_items = try arena.alloc(types.ModelInstances, config.ForestSpawner.length);
        for (instances_items, @typeInfo(config.ForestSettings).@"struct".decls, tree_to_instance_list) |*instances, decl, instance_list| {
            instances.* = .{
                .label = decl.name,
                .instances = instance_list.items,
            };
        }

        return .{
            .model_instances = instances_items,
        };
    }

    pub fn displayBike(
        arena: std.mem.Allocator,
        props: struct {
            timing: queryable.Value(types.Timing),
            model_transforms: std.StringHashMap(zmath.Mat),
            terrain_sampler: TerrainSampler,
            bounce: bool,
        },
    ) !struct {
        model_instances: []const types.ModelInstances,
    } {
        var world = zbullet.initWorld();
        world.setGravity(&.{ 0, 9.81, 0 });
        world.addBody(zbullet.initBody(
            1,
            &zmath.matToArr43(zmath.translation(0, 0, 0)),
            zbullet.initBoxShape(&.{ 1, 1, 1 }).asShape(),
        ));
        for (0..100) |_| {
            _ = world.stepSimulation(1, .{});
        }
        for (0..@intCast(world.getNumBodies())) |body_index| {
            const body = world.getBody(@intCast(body_index));
            const transform = object_to_world: {
                var transform: [12]f32 = undefined;
                body.getGraphicsWorldTransform(&transform);
                break :object_to_world zmath.loadMat43(transform[0..]);
            };
            print("Hello! There's some bodies!! {any}\n", .{transform});
        }

        var terrain_chunk_cache = config.TerrainSpawner.ChunkCache.init(arena);

        const terrain_sampler = props.terrain_sampler.loadCache(&terrain_chunk_cache);
        _ = terrain_sampler;

        var instances = std.ArrayList(types.ModelInstances).init(arena);
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
                .instances = try arena.dupe(types.Instance, &.{.{
                    .position = zmath.loadArr3w(zmath.vecToArr3(transform[3] + entry.offset), 1),
                    .rotation = zmath.matToQuat(transform),
                    .scale = .{
                        zmath.length3(transform[0])[0],
                        zmath.length3(transform[1])[0],
                        zmath.length3(transform[2])[0],
                        0,
                    },
                }}),
            });
        }

        return .{ .model_instances = instances.items };
    }

    /// Take all models, pull out the animatable ones, write them out after animating and subdividing them
    pub fn animateMeshes(
        arena: std.mem.Allocator,
        props: struct {
            timing: types.Timing,
            models: []const types.GameModel,
        },
    ) !struct {
        models: []const types.GameModel,
    } {
        var models = std.ArrayList(types.GameModel).init(arena);
        for (props.models) |model| {
            for (model.meshes) |mesh|
                switch (mesh) {
                    .subdiv => |subdiv_mesh| {
                        const faces = subdiv_mesh.base_faces;
                        const positions = try arena.dupe(Vec4, subdiv_mesh.base_positions);
                        for (subdiv_mesh.base_bone_indices, positions) |i, *position| {
                            const bone_index: usize = @intCast(i);
                            const bone = subdiv_mesh.armature.bones[bone_index];
                            const animation = subdiv_mesh.armature.animation;
                            const fps = 12;
                            const inter_frame = props.timing.seconds_since_start * fps;
                            const frame: usize = @intFromFloat(inter_frame);
                            const animated_bone = .{
                                animation[frame % animation.len].bones[bone_index],
                                animation[(frame + 1) % animation.len].bones[bone_index],
                            };
                            const lerp = inter_frame - @as(f32, @floatFromInt(frame));
                            position.* = zmath.mul(
                                zmath.mul(
                                    position.*,
                                    zmath.inverse(
                                        vec_math.translationRotationScaleToMatrix(
                                            bone.rest.position,
                                            bone.rest.rotation,
                                            bone.rest.scale,
                                        ),
                                    ),
                                ),
                                vec_math.translationRotationScaleToMatrix(
                                    zmath.lerp(animated_bone[0].position, animated_bone[1].position, lerp),
                                    zmath.slerp(animated_bone[0].rotation, animated_bone[1].rotation, lerp),
                                    zmath.lerp(animated_bone[0].scale, animated_bone[1].scale, lerp),
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
                            .meshes = try arena.dupe(types.GameMesh, &[_]types.GameMesh{.{
                                .greybox = types.GreyboxMesh{
                                    .color = .{ 0.2, 0.2, 0.7, 1 },
                                    .indices = subdiv_mesh.top_indices,
                                    .position = subdiv_result,
                                    .normal = mesh_helper.Polygon(.Quad).calculateNormals(arena, subdiv_result, subdiv_mesh.quads_per_subdiv[subdiv_levels - 1]),
                                },
                            }}),
                        });
                    },
                    else => {},
                };
        }
        return .{ .models = models.items };
    }

    pub fn displayTrees(
        arena: std.mem.Allocator,
        props: struct {
            cutout_leaf: Image.Processed,
            trees: []const types.TreeMesh,
        },
    ) !struct {
        models: []const types.GameModel,
    } {
        var models = std.ArrayList(types.GameModel).init(arena);
        for (props.trees) |tree_mesh| {
            try models.append(.{
                .label = tree_mesh.label,
                .meshes = try arena.dupe(types.GameMesh, &.{
                    .{ .greybox = .{
                        .color = .{ 0.4, 0.3, 0.2, 1 },
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
        terrain_mesh: types.GreyboxMesh,
        terrain_instance: types.ModelInstances,
    } {
        var terrain_chunk_cache = config.TerrainSpawner.ChunkCache.init(arena);
        try terrain_chunk_cache.ensureTotalCapacity(256);
        const terrain_sampler = props.terrain_sampler.loadCache(&terrain_chunk_cache);

        const terrain_resolution = 512;
        // const terrain_resolution = 255;
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
                    const span = config.demo_terrain_bounds.size / res;
                    const coord: Vec2 = @floatFromInt(vertex_coord);
                    break :pos_2d config.demo_terrain_bounds.min + (span * coord);
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
                    const quad_corner = quad_coord +% quad_corners[quad_index];
                    quad[quad_index] = @intCast(quad_corner[0] + quad_corner[1] * vertex_iterator.width());
                }
                quads[index] = quad;
            }
            break :blk quads;
        };
        const indices = mesh_helper.Polygon(.Quad).toTriangleIndices(arena, quads);
        const normals = mesh_helper.Polygon(.Quad).calculateNormals(arena, positions, quads);

        return .{
            .terrain_mesh = types.GreyboxMesh{
                .color = .{ 0.9, 0.9, 0.9, 0.9 },
                .indices = indices,
                .position = positions,
                .normal = normals,
            },
            .terrain_instance = types.ModelInstances{
                .label = "terrain",
                .instances = try arena.dupe(types.Instance, &.{.{
                    .position = .{ 0, 0, 0, 1 },
                    .rotation = zmath.qidentity(),
                    .scale = .{ 1, 1, 1, 0 },
                }}),
            },
        };
    }
};
