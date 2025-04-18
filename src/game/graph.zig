const std = @import("std");
const Dirtyable = @import("node_graph").Dirtyable;
const utils = @import("utils");
const config = @import("resources").config;
const zmath = @import("zmath");
const game = @import("../game.zig");

const graph_nodes = game.graph_nodes;

const types = utils.types;
const vec_math = utils.vec_math;

const Runtime = @import("node_graph").Runtime(struct {
    pub const Store = struct {
        orbit_camera: types.OrbitCamera,
        player: types.Player,
        all_models: []const types.GameModel,
        all_instances: []const types.ModelInstances,
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
        lock_mouse: bool,
        exit: bool,
        screen_space_mesh: types.ScreenspaceMesh,
        skybox: types.ProcessedCubeMap,
        shadow_update_bounds: void,
        models: []const types.GameModel,
        model_instances: []const types.ModelInstances,
        terrain_mesh: types.GreyboxMesh,
        terrain_instance: types.ModelInstances,
        world_matrix: zmath.Mat,
        camera_position: zmath.Vec,
    };
});

/// take a bunch of Dirtyable inputs and put them together, only including dirty ones
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

/// Concat wrapped in a node function
pub fn concat(T: type) type {
    return struct {
        arena: std.mem.Allocator,
        pub fn update(self: @This(), inputs: []const []const T) struct { value: []const T } {
            return .{
                .value = std.mem.concat(self.arena, T, inputs) catch unreachable,
            };
        }
    };
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
        const resources = rt.node(@src(), graph_nodes.getResources, .{}, .{});
        // TODO - just combine with resources, unless I really want to have some sliders show show off
        const display_trees = rt.node(@src(), graph_nodes.displayTrees, .{}, .{
            .cutout_leaf = resources.cutout_leaf,
            .trees = resources.trees,
        });
        frontend.submitDirty(.{
            .skybox = resources.skybox,
        });

        const light = rt.node(@src(), graph_nodes.light, .{}, .{});

        // Behold - all the things the game loop can do BEFORE user input, that we can compute without needing to know what the user will do!
        // Terrain things below!
        const terrain = rt.node(@src(), graph_nodes.terrain, .{}, .{
            .size_multiplier = frontend.poll(.size_multiplier),
        });
        const forest = rt.node(@src(), graph_nodes.displayForest, .{}, .{
            .terrain_sampler = terrain.sampler,
        });
        const display_terrain = rt.node(@src(), graph_nodes.displayTerrain, .{}, .{
            .terrain_sampler = terrain.sampler,
        });
        // Animated things below!
        const timing = rt.node(@src(), graph_nodes.timing, .{ .check_output_equality = true }, .{
            .time = frontend.poll(.time),
        });
        const animate_meshes = rt.node(@src(), graph_nodes.animateMeshes, .{}, .{
            .timing = timing.low_update,
            .models = resources.models,
        });
        const display_bike = rt.node(@src(), graph_nodes.displayBike, .{}, .{
            .timing = timing.realtime,
            .terrain_sampler = terrain.sampler,
            .model_transforms = resources.model_transforms,
            .bounce = frontend.poll(.bounce),
        });
        frontend.submitDirty(.{
            .terrain_mesh = display_terrain.terrain_mesh,
            .terrain_instance = display_terrain.terrain_instance,
        });
        const model_sources = &.{
            resources.models,
            animate_meshes.models,
            display_trees.models,
        };

        const all_models = rt.node(@src(), concat(types.GameModel), .{}, model_sources);
        const instance_sources = &.{
            forest.model_instances,
            display_bike.model_instances,
        };
        const all_instances = rt.node(@src(), concat(types.ModelInstances), .{}, instance_sources);

        const shadow = rt.node(@src(), graph_nodes.shadow, .{}, .{
            .light = light.sun,
            .all_models = all_models,
            .last_all_models = store.all_models,
            .all_instances = all_instances,
            .last_all_instances = store.all_instances,
        });
        _ = shadow;

        frontend.submit(.{
            .models = concatChanged(rt.frame_arena.allocator(), types.GameModel, model_sources),
            .model_instances = concatChanged(rt.frame_arena.allocator(), types.ModelInstances, instance_sources),
        });

        // Polling user input! (We can do it late, which should lead to lower latency!)
        const orbit = rt.node(@src(), graph_nodes.orbit, .{ .check_output_equality = true }, .{
            .timing = timing.realtime,
            .render_resolution = frontend.poll(.render_resolution),
            .orbit_speed = frontend.poll(.orbit_speed),
            .input = frontend.poll(.input),
            .orbit_camera = store.orbit_camera,
            .selected_camera = frontend.poll(.selected_camera),
            .player_settings = frontend.poll(.player_settings),
            .player = store.player,
            .terrain_sampler = terrain.sampler,
        });

        const get_screenspace_mesh = rt.node(@src(), graph_nodes.getScreenspaceMesh, .{}, .{
            .camera_position = orbit.camera_position,
            .world_matrix = orbit.world_matrix,
        });
        frontend.submitDirty(.{
            .lock_mouse = orbit.lock_mouse,
            .exit = orbit.exit,
            .world_matrix = orbit.world_matrix,
            .camera_position = orbit.camera_position,
            .screen_space_mesh = get_screenspace_mesh.screen_space_mesh,
        });

        return .{
            .orbit_camera = orbit.orbit_camera,
            .player = orbit.player,
            .all_instances = all_instances,
            .all_models = all_models,
        };
    }
});
