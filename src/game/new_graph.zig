const std = @import("std");
const Runtime = @import("node_graph").new_runtime.Runtime;
const DirtyableFields = @import("node_graph").new_runtime.DirtyableFields;
const GraphStore = @import("node_graph").new_runtime.GraphStore;
const GraphOutputs = @import("node_graph").new_runtime.GraphOutputs;
const GraphInputs = @import("node_graph").new_runtime.GraphInputs;
const types = @import("utils").types;
const config = @import("resources").config;
const zmath = @import("zmath");
const game = @import("../game.zig");
const graph_nodes = game.graph_nodes;

pub const GameGraph = Runtime.build(struct {
    pub const Store = struct {
        orbit_camera: types.OrbitCamera,
        player: types.Player,
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
    pub fn update(
        rt: *Runtime,
        inputs: GraphInputs(Inputs),
        outputs: GraphOutputs(Outputs),
        store: GraphStore(Store),
    ) GraphStore(Store) {
        // This stuff could exist outside of this graph probably, since it doesn't take any inputs,
        // but because it's here, means that I could change my mind later!
        // TODO - Make resources load pngs and .blend.json files from disk instead of embedding, to help compile times!
        const get_resources = rt.node(@src(), graph_nodes.getResources, .{});
        // TODO - just combine with resources, unless I really want to have some sliders show show off
        const display_trees = rt.node(@src(), graph_nodes.displayTrees, .{
            .cutout_leaf = get_resources.cutout_leaf,
            .trees = get_resources.trees,
        });
        outputs.submit(.{
            .skybox = get_resources.skybox,
        });

        // Behold - all the things the game loop can do BEFORE user input, that we can compute without needing to know what the user will do!
        // Terrain things below!
        const calculate_terrain_density_influence_range = rt.node(@src(), graph_nodes.calculateTerrainDensityInfluenceRange, .{
            .size_multiplier = inputs.poll(.size_multiplier),
        });
        const display_forest = rt.node(@src(), graph_nodes.displayForest, .{
            .terrain_sampler = calculate_terrain_density_influence_range.terrain_sampler,
        });
        const display_terrain = rt.node(@src(), graph_nodes.displayTerrain, .{
            .terrain_sampler = calculate_terrain_density_influence_range.terrain_sampler,
        });
        // Animated things below!
        const timing = rt.node(@src(), graph_nodes.timing, .{
            .time = inputs.poll(.time),
        });
        const animate_meshes = rt.node(@src(), graph_nodes.animateMeshes, .{
            .models = get_resources.models,
            .seconds_since_start = timing.seconds_since_start,
        });
        const display_bike = rt.node(@src(), graph_nodes.displayBike, .{
            .terrain_sampler = calculate_terrain_density_influence_range.terrain_sampler,
            .seconds_since_start = timing.seconds_since_start,
            .model_transforms = get_resources.model_transforms,
            .bounce = inputs.poll(.bounce),
        });
        outputs.submit(.{
            .terrain_mesh = display_terrain.terrain_mesh,
            .terrain_instance = display_terrain.terrain_instance,
            .models = .{
                .raw = std.mem.concat(rt.allocator, types.GameModel, &.{
                    get_resources.models.raw,
                    animate_meshes.models.raw,
                    display_trees.models.raw,
                }) catch unreachable,
                .is_dirty = true,
            },
            .model_instances = .{
                .raw = std.mem.concat(rt.allocator, types.ModelInstances, &.{
                    display_forest.model_instances.raw,
                    display_bike.model_instances.raw,
                }) catch unreachable,
                .is_dirty = true,
            },
        });

        // Polling user input! (We can do it late, which should lead to lower latency!)
        const orbit = rt.node(@src(), graph_nodes.orbit, .{
            .delta_time = timing.delta_time,
            .render_resolution = inputs.poll(.render_resolution),
            .orbit_speed = inputs.poll(.orbit_speed),
            .input = inputs.poll(.input),
            .orbit_camera = store.orbit_camera,
            .selected_camera = inputs.poll(.selected_camera),
            .player_settings = inputs.poll(.player_settings),
            .player = store.player,
            .terrain_sampler = calculate_terrain_density_influence_range.terrain_sampler,
        });

        const get_screenspace_mesh = rt.node(@src(), graph_nodes.getScreenspaceMesh, .{
            .camera_position = orbit.camera_position,
            .world_matrix = orbit.world_matrix,
        });
        outputs.submit(.{
            .world_matrix = orbit.world_matrix,
            .screen_space_mesh = get_screenspace_mesh.screen_space_mesh,
        });

        return .{
            .orbit_camera = store.orbit_camera,
            .player = store.player,
        };
    }
});
