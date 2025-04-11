const std = @import("std");
const Dirtyable = @import("node_graph").Dirtyable;
const types = @import("utils").types;
const config = @import("resources").config;
const zmath = @import("zmath");
const game = @import("../game.zig");
const graph_nodes = game.graph_nodes;

const Runtime = @import("node_graph").Runtime(struct {
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
        screen_space_mesh: types.ScreenspaceMesh,
        skybox: types.ProcessedCubeMap,
        models: []const types.GameModel,
        model_instances: []const types.ModelInstances,
        terrain_mesh: types.GreyboxMesh,
        terrain_instance: types.ModelInstances,
        world_matrix: zmath.Mat,
        camera_position: zmath.Vec,
    };
});

pub fn concatChanged(arena: std.mem.Allocator, T: type, inputs: []const Dirtyable([]const T)) []const T {
    for (inputs) |input| {
        if (input.is_dirty) break;
    } else return &.{};
    var to_concat: std.ArrayList([]const T) = .init(arena);
    for (inputs) |input| {
        if (input.is_dirty) {
            to_concat.append(input.raw) catch unreachable;
        }
    }
    return std.mem.concat(arena, T, to_concat.items) catch unreachable;
}

pub const GameGraph = Runtime.build(struct {
    pub fn init(allocator: std.mem.Allocator) void {
        game.init(allocator);
    }
    pub fn update(
        rt: *Runtime,
        frontend: anytype,
        store: Runtime.Store,
    ) Runtime.Store {

        // This stuff could exist outside of this graph probably, since it doesn't take any inputs,
        // but because it's here, means that I could change my mind later!
        // TODO - Make resources load pngs and .blend.json files from disk instead of embedding, to help compile times!
        const get_resources = rt.node(@src(), graph_nodes.getResources, .{}, .{});
        // TODO - just combine with resources, unless I really want to have some sliders show show off
        const display_trees = rt.node(@src(), graph_nodes.displayTrees, .{}, .{
            .cutout_leaf = get_resources.cutout_leaf,
            .trees = get_resources.trees,
        });
        frontend.submitDirty(.{
            .skybox = get_resources.skybox,
        });

        // Behold - all the things the game loop can do BEFORE user input, that we can compute without needing to know what the user will do!
        // Terrain things below!
        const calculate_terrain_density_influence_range = rt.node(@src(), graph_nodes.calculateTerrainDensityInfluenceRange, .{}, .{
            .size_multiplier = frontend.poll(.size_multiplier),
        });
        const display_forest = rt.node(@src(), graph_nodes.displayForest, .{}, .{
            .terrain_sampler = calculate_terrain_density_influence_range.terrain_sampler,
        });
        const display_terrain = rt.node(@src(), graph_nodes.displayTerrain, .{}, .{
            .terrain_sampler = calculate_terrain_density_influence_range.terrain_sampler,
        });
        // Animated things below!
        const timing = rt.node(@src(), graph_nodes.timing, .{}, .{
            .time = frontend.poll(.time),
        });
        const animate_meshes = rt.node(@src(), graph_nodes.animateMeshes, .{}, .{
            .models = get_resources.models,
            .seconds_since_start = timing.seconds_since_start,
        });
        const display_bike = rt.node(@src(), graph_nodes.displayBike, .{}, .{
            .terrain_sampler = calculate_terrain_density_influence_range.terrain_sampler,
            .seconds_since_start = timing.seconds_since_start,
            .model_transforms = get_resources.model_transforms,
            .bounce = frontend.poll(.bounce),
        });
        frontend.submitDirty(.{
            .terrain_mesh = display_terrain.terrain_mesh,
            .terrain_instance = display_terrain.terrain_instance,
        });
        frontend.submit(.{
            .models = concatChanged(rt.frame_arena.allocator(), types.GameModel, &.{
                get_resources.models,
                animate_meshes.models,
                display_trees.models,
            }),
            .model_instances = concatChanged(rt.frame_arena.allocator(), types.ModelInstances, &.{
                display_forest.model_instances,
                display_bike.model_instances,
            }),
        });

        // Polling user input! (We can do it late, which should lead to lower latency!)
        const orbit = rt.node(@src(), graph_nodes.orbit, .{ .checkOutputEquality = true }, .{
            .delta_time = timing.delta_time,
            .render_resolution = frontend.poll(.render_resolution),
            .orbit_speed = frontend.poll(.orbit_speed),
            .input = frontend.poll(.input),
            .orbit_camera = store.orbit_camera,
            .selected_camera = frontend.poll(.selected_camera),
            .player_settings = frontend.poll(.player_settings),
            .player = store.player,
            .terrain_sampler = calculate_terrain_density_influence_range.terrain_sampler,
        });

        const get_screenspace_mesh = rt.node(@src(), graph_nodes.getScreenspaceMesh, .{}, .{
            .camera_position = orbit.camera_position,
            .world_matrix = orbit.world_matrix,
        });
        frontend.submitDirty(.{
            .world_matrix = orbit.world_matrix,
            .camera_position = orbit.camera_position,
            .screen_space_mesh = get_screenspace_mesh.screen_space_mesh,
        });

        return .{
            .orbit_camera = orbit.orbit_camera,
            .player = orbit.player,
        };
    }
});
