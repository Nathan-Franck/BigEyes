const std = @import("std");
const wasm_entry = @import("../wasm_entry.zig");
const graph_runtime = @import("../graph_runtime.zig");
const Queryable = @import("../utils.zig").Queryable;
const subdiv = @import("../subdiv.zig");
const Image = @import("../Image.zig");
const raytrace = @import("../raytrace.zig");
const mesh_helper = @import("../mesh_helper.zig");
const zm = @import("zmath");
const tree = @import("../tree.zig");
const Bounds = @import("../forest.zig").Bounds;
const Coord = @import("../forest.zig").Coord;
const Vec2 = @import("../forest.zig").Vec2;
const Vec4 = @import("../forest.zig").Vec4;
const CoordIterator = @import("../CoordIterator.zig");
const Stamp = @import("../Stamp.zig");

const game = struct {
    pub const graph = @import("./graph.zig");
    pub const types = @import("./types.zig");
    pub const config = @import("./config.zig");
};
const Forest = game.config.Forest;
const TerrainSampler = game.config.TerrainSampler;

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
                    .look_speed = 0.004,
                    .movement_speed = 0.8,
                },
                .render_resolution = .{ .x = 0, .y = 0 },
            },
            .store = .{
                .last_time = 0,
                .forest_chunk_cache = game.config.ForestSpawner.ChunkCache.init(std.heap.page_allocator),
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
};

pub const NodeGraph = graph_runtime.NodeGraph(
    game.graph.blueprint,
    graph_nodes,
);

pub const graph_nodes = struct {
    pub fn calculateTerrainDensityInfluenceRange(
        arena: std.mem.Allocator,
        _: struct {},
    ) !struct {
        terrain_sampler: TerrainSampler,
    } {
        return .{
            .terrain_sampler = try TerrainSampler.init(arena),
        };
    }

    pub fn getResources(arena: std.mem.Allocator, _: struct {}) !game.types.Resources {
        const bike_blend = blk: {
            const json_data = @embedFile("../content/ebike.blend.json");
            const mesh_loader = @import("../mesh_loader.zig");
            const nodes = try mesh_loader.getNodesFromJSON(arena, json_data);
            for (nodes) |mesh| {
                wasm_entry.dumpDebugLogFmt("a mesh! {s}\n", .{mesh.name});
            }
            break :blk nodes;
        };

        var models = std.ArrayList(game.types.GameModel).init(arena);
        var model_transforms = std.StringHashMap(zm.Mat).init(arena);
        for (bike_blend) |node|
            if (node.mesh) |mesh| {
                const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
                const vertices = try arena.alloc(Vec4, mesh.vertices.len);
                const normals = try arena.alloc(Vec4, mesh.vertices.len);
                for (mesh.vertices, 0..) |vertex, i| {
                    normals[i] = zm.loadArr3(vertex.normal);
                    vertices[i] = zm.loadArr3(vertex.position);
                }
                const model: game.types.GameModel = .{
                    .label = node.name,
                    .meshes = try arena.dupe(game.types.GameMesh, &.{.{ .greybox = .{
                        .indices = mesh.indices,
                        .normal = PointFlattener.convert(arena, normals),
                        .position = PointFlattener.convert(arena, vertices),
                    } }}),
                };
                const transform = zm.mul(
                    zm.mul(
                        zm.translationV(zm.loadArr3(node.position)),
                        zm.matFromRollPitchYawV(zm.loadArr3(node.rotation)),
                    ),
                    zm.scalingV(zm.loadArr3(node.scale)),
                );
                try models.append(model);
                try model_transforms.put(node.name, transform);
            };

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
            .models = models.items,
            .model_transforms = model_transforms,
            .skybox = skybox,
            .cutout_leaf = cutout_leaf,
            .trees = trees.items,
        };
    }

    pub fn timing(props: struct {
        time: u64,
        last_time: u64,
    }) struct {
        last_time: u64,
        delta_time: f32,
    } {
        const delta_time = @as(f32, @floatFromInt(props.time - props.last_time)) / 1000.0;
        return .{
            .last_time = props.time,
            .delta_time = delta_time,
        };
    }

    pub fn orbit(
        arena: std.mem.Allocator,
        props: struct {
            delta_time: Queryable.Value(f32),
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
            terrain_sampler: TerrainSampler,
        },
    ) !struct {
        camera_position: Vec4,
        world_matrix: zm.Mat,
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
                    .camera_position = zm.mul(zm.inverse(location), Vec4{ 0, 0, 0, 1 }),
                    .world_matrix = zm.mul(
                        location,
                        view_projection,
                    ),
                };
            },
            .first_person => {
                props.player.euler_rotation = props.player.euler_rotation +
                    props.input.mouse_delta *
                    zm.splat(Vec4, -props.player_settings.look_speed);

                const rotation_matrix = zm.matFromRollPitchYaw(-props.player.euler_rotation[1], -props.player.euler_rotation[0], 0);

                const right = Vec4{ 1, 0, 0, 0 };
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

                const forward = Vec4{ 0, 0, 1, 0 };
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

                if (zm.length3(combined_movement)[0] > 0.001) {
                    const final_movement = zm.mul(
                        zm.normalize3(combined_movement),
                        rotation_matrix,
                    ) * zm.splat(Vec4, props.player_settings.movement_speed * props.delta_time.get());

                    var new_position = props.player.position;
                    new_position += final_movement;

                    var terrain_chunk_cache = game.config.TerrainSpawner.ChunkCache.init(arena);
                    const terrain_height = try props.terrain_sampler
                        .loadCache(&terrain_chunk_cache)
                        .sample(arena, Vec2{ new_position[0], new_position[2] });

                    new_position[1] = terrain_height + 0.7;

                    props.player.position = new_position;
                }

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
        arena: std.mem.Allocator,
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
            .indices = try arena.dupe(u32, &.{
                0, 1, 2,
                2, 3, 0,
            }),
            .uvs = UvFlattener.convert(arena, &.{
                Vec2{ 0, 0 },
                Vec2{ 1, 0 },
                Vec2{ 1, 1 },
                Vec2{ 0, 1 },
            }),
            .normals = PointFlattener.convert(arena, &normals),
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

        var instances = try arena.alloc(std.ArrayList(Vec4), game.config.ForestSpawner.length);
        for (instances) |*instance| {
            instance.* = std.ArrayList(Vec4).init(arena);
        }
        for (spawns) |spawn| {
            const pos_2d = Vec2{ spawn.position[0], spawn.position[1] };
            const height = try terrain_sampler.sample(arena, pos_2d);
            const position = Vec4{ spawn.position[0], height, spawn.position[1], 1 };
            try instances[spawn.id].append(position);
        }
        const instances_items = try arena.alloc(game.types.ModelInstances, game.config.ForestSpawner.length);
        const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
        // const QuatFlattener = mesh_helper.VecSliceFlattener(4, 4);
        for (instances_items, @typeInfo(game.config.ForestSettings).@"struct".decls, 0..) |*instance, decl, i| {
            instance.* = .{
                .label = decl.name,
                .positions = PointFlattener.convert(arena, instances[i].items),
            };
        }

        return .{
            .model_instances = instances_items,
        };
    }

    fn Pick(@"struct": type, fields: []const std.meta.FieldEnum(@"struct")) type {
        var tuple_fields: [fields.len]std.builtin.Type.StructField = undefined;
        const temp_struct: @"struct" = undefined;
        if (tuple_fields.len > 0)
            inline for (fields, 0..) |field, i| {
                var buf: [1000]u8 = undefined;
                tuple_fields[i] = .{
                    .name = std.fmt.bufPrintZ(&buf, "{d}", .{i}) catch unreachable,
                    .type = @TypeOf(@field(temp_struct, @tagName(field))),
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
            };

        return @Type(.{
            .@"struct" = .{
                .is_tuple = true,
                .layout = .auto,
                .decls = &.{},
                .fields = &tuple_fields,
            },
        });
    }

    fn pick(
        data_struct: anytype,
        comptime fields: []const std.meta.FieldEnum(@TypeOf(data_struct)),
    ) Pick(@TypeOf(data_struct), fields) {
        var result: Pick(@TypeOf(data_struct), fields) = undefined;
        inline for (fields, 0..) |field, i| {
            result[i] = @field(data_struct, @tagName(field));
        }
        return result;
    }

    pub fn displayBike(
        arena: std.mem.Allocator,
        props: struct {
            model_transforms: std.StringHashMap(zm.Mat),
            terrain_sampler: TerrainSampler,
        },
    ) !struct {
        model_instances: []const game.types.ModelInstances,
    } {
        var terrain_chunk_cache = game.config.TerrainSpawner.ChunkCache.init(arena);
        const terrain_sampler = props.terrain_sampler.loadCache(&terrain_chunk_cache);
        _ = terrain_sampler;

        var instances = std.ArrayList(game.types.ModelInstances).init(arena);
        for (&[_][]const u8{
            "front-wheel",
            "back-wheel",
            "body",
            "handlebars",
            "shock",
        }) |label| {
            try instances.append(.{
                .label = label,
                .transforms = mesh_helper.flattenMatrices(
                    arena,
                    &.{props.model_transforms.get(label).?},
                ),
            });
        }

        return .{ .model_instances = instances.items };
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
        const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
        const UvFlattener = mesh_helper.VecSliceFlattener(2, 2);
        var models = std.ArrayList(game.types.GameModel).init(arena);
        for (props.trees) |tree_mesh| {
            try models.append(.{
                .label = tree_mesh.label,
                .meshes = try arena.dupe(game.types.GameMesh, &.{
                    .{ .greybox = .{
                        .indices = tree_mesh.bark_mesh.triangles,
                        .normal = PointFlattener.convert(arena, tree_mesh.bark_mesh.normals),
                        .position = PointFlattener.convert(arena, tree_mesh.bark_mesh.vertices),
                    } },
                    .{ .textured = .{
                        .diffuse_alpha = props.cutout_leaf,
                        .indices = tree_mesh.leaf_mesh.triangles,
                        .normal = PointFlattener.convert(arena, tree_mesh.leaf_mesh.normals),
                        .position = PointFlattener.convert(arena, tree_mesh.leaf_mesh.vertices),
                        .uv = UvFlattener.convert(arena, tree_mesh.leaf_mesh.uvs),
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

        const terrain_resolution = 512;
        // const terrain_resolution = 256;
        // const terrain_resolution = 128;

        var vertex_iterator = CoordIterator.init(@splat(0), @splat(terrain_resolution + 1));
        const positions = blk: {
            var positions = try arena.alloc(Vec4, vertex_iterator.total);
            var index: usize = 0;
            while (vertex_iterator.next()) |vertex_coord| : (index += 1) {
                // TODO: Calculate how big the stack should be, maybe should OOM so that I know when we went to slow-mode (Super cool that one line can save 100ms for a 512*512 terrain)
                var stack_arena = std.heap.stackFallback(1024, arena);

                const pos_2d: Vec2 = game.config.demo_terrain_bounds.min +
                    @as(Vec2, @floatFromInt(vertex_coord)) *
                    game.config.demo_terrain_bounds.size /
                    @as(Vec2, @splat(terrain_resolution));
                const height = try terrain_sampler.sample(stack_arena.get(), pos_2d);
                const vertex: Vec4 = .{ pos_2d[0], height, pos_2d[1], 1 };
                positions[index] = vertex;
            }
            break :blk positions;
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

        const PointFlattener = mesh_helper.VecSliceFlattener(4, 3);
        return .{
            .terrain_mesh = game.types.GreyboxMesh{
                .indices = indices,
                .position = PointFlattener.convert(arena, positions),
                .normal = PointFlattener.convert(arena, normals),
            },
            .terrain_instance = game.types.ModelInstances{
                .label = "terrain",
                .transforms = mesh_helper.flattenMatrices(arena, &.{zm.identity()}),
            },
        };
    }
};
