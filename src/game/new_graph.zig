const std = @import("std");
const Runtime = @import("node_graph").new_runtime.Runtime;
const DirtyableFields = @import("node_graph").new_runtime.DirtyableFields;
const types = @import("utils").types;
const config = @import("resources").config;
const zmath = @import("zmath");
const game = @import("../game.zig");
const graph_nodes = game.graph_nodes;

pub const GameGraph = Runtime.build(struct {
    pub const Store = struct {
        last_time: u64 = 0,
        orbit_camera: types.OrbitCamera,
        player: types.Player,
        forest_chunk_cache: config.ForestSpawner.ChunkCache,
    };
    pub const Inputs = struct {
        time: u64,
        render_resolution: types.PixelPoint,
        orbit_speed: f32,
        input: types.Input,
        selected_camera: types.SelectedCamera,
        player_settings: types.PlayerSettings,
        bounce: bool,
        size_multiplier: f32,
    };
    pub const Outputs = struct {
        skybox: types.ProcessedCubeMap,
        models: []const types.GameModel,
        screen_space_mesh: types.ScreenspaceMesh,
        model_instances: []const types.ModelInstances,
        terrain_mesh: types.GreyboxMesh,
        terrain_instance: types.ModelInstances,
        world_matrix: zmath.Mat,
    };
    pub fn GraphInputs(inputs: type) type {
        _ = inputs;
        return struct {
            fn poll() void {}
        };
    }
    pub fn GraphOutputs(outputs: type) type {
        _ = outputs;
        return struct {
            fn poll() void {}
        };
    }
    pub fn update(
        rt: *Runtime,
        inputs: GraphInputs(Inputs),
        outputs: GraphOutputs(Outputs),
        store: DirtyableFields(Store),
    ) struct {
        store: DirtyableFields(Store),
    } {
        const getResources = rt.node(@src(), graph_nodes.getResources, .{});
        outputs.submit(.{
            .skybox = getResources.skybox,
        });
        const timing = rt.node(@src(), graph_nodes.timing, .{
            .time = inputs.poll(.time),
            .last_time = store.last_time,
        });
        const calculateTerrainDensityInfluenceRange = rt.node(@src(), graph_nodes.calculateTerrainDensityInfluenceRange, .{
            .size_multiplier = inputs.size_multiplier,
        });
        const orbit = rt.node(@src(), graph_nodes.orbit, .{
            .delta_time = timing.delta_time,
            .render_resolution = inputs.poll(.render_resolution),
            .orbit_speed = inputs.poll(.orbit_speed),
            .input = inputs.poll(.input),
            .orbit_camera = store.orbit_camera,
            .selected_camera = inputs.poll(.selected_camera),
            .player_settings = inputs.poll(.player_settings),
            .player = store.player,
            .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
        });
        outputs.submit(.{
            .world_matrix = orbit.world_matrix,
        });
        const displayTrees = rt.node(@src(), graph_nodes.displayTrees, .{
            .cutout_leaf = getResources.cutout_leaf,
            .trees = getResources.trees,
        });
        const animateMeshes = rt.node(@src(), graph_nodes.animateMeshes, .{
            .models = getResources.models,
            .seconds_since_start = timing.seconds_since_start,
        });
        outputs.submit(.{
            .models = .{
                .raw = std.mem.concat(rt.allocator, types.GameModel, &.{
                    getResources.models.raw,
                    animateMeshes.models.raw,
                    displayTrees.models.raw,
                }) catch unreachable,
                .is_dirty = true,
            },
        });
        const displayForest = rt.node(@src(), graph_nodes.displayForest, .{
            .forest_chunk_cache = store.forest_chunk_cache,
            .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
        });
        const displayBike = rt.node(@src(), graph_nodes.displayBike, .{
            .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
            .seconds_since_start = timing.seconds_since_start,
            .model_transforms = getResources.model_transforms,
            .bounce = inputs.poll(.bounce),
        });
        outputs.submit(.{
            .model_instances = .{
                .raw = std.mem.concat(rt.allocator, types.ModelInstances, &.{
                    displayForest.model_instances.raw,
                    displayBike.model_instances.raw,
                }) catch unreachable,
                .is_dirty = true,
            },
        });
        const displayTerrain = rt.node(@src(), graph_nodes.displayTerrain, .{
            .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
        });
        outputs.submit(.{
            .terrain_mesh = displayTerrain.terrain_mesh,
            .terrain_instance = displayTerrain.terrain_instance,
        });
        const getScreenspaceMesh = rt.node(@src(), graph_nodes.getScreenspaceMesh, .{
            .camera_position = orbit.camera_position,
            .world_matrix = orbit.world_matrix,
        });
        outputs.submit(.{
            .screen_space_mesh = getScreenspaceMesh.screen_space_mesh,
        });
        return .{
            .orbit_camera = orbit.orbit_camera,
            .last_time = timing.last_time,
            .player = orbit.player,
            .forest_chunk_cache = displayForest.forest_chunk_cache,
        };
    }
});
