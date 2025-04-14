const std = @import("std");
const Dirtyable = @import("node_graph").Dirtyable;
const utils = @import("utils");
const config = @import("resources").config;
const zmath = @import("zmath");
const game = @import("../game.zig");
const dizzy = @import("dizzy");
const graph_nodes = game.graph_nodes;

const types = utils.types;

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
        screen_space_mesh: types.ScreenspaceMesh,
        skybox: types.ProcessedCubeMap,
        shadow_update_bounds: []const utils.Bounds,
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

/// Take a bunch of Dirtyable inputs and put them together into a single Dirtyable, where it's dirty if any is dirty
pub fn concatDirty(arena: std.mem.Allocator, T: type, inputs: []const Dirtyable([]const T)) Dirtyable([]const T) {
    var to_concat: std.ArrayList([]const T) = .init(arena);
    var is_dirty = false;
    for (inputs) |input| {
        to_concat.append(input.raw) catch unreachable;
        if (input.is_dirty)
            is_dirty = true;
    }
    return .{
        .raw = std.mem.concat(arena, T, to_concat.items) catch unreachable,
        .is_dirty = is_dirty,
    };
}

pub fn diff(T: type, arena: std.mem.Allocator, a: []const T, b: []const T) []const dizzy.Edit {
    const scratch_len = 4 * (a.len + b.len) + 2;
    const scratch = arena.alloc(u32, scratch_len) catch unreachable;
    const differ = dizzy.SliceDiffer(T, struct {
        pub fn eql(_: @This(), _a: T, _b: T) bool {
            return std.meta.eql(_a, _b);
        }
    });
    var edits = std.ArrayListUnmanaged(dizzy.Edit){};
    differ.diff(arena, &edits, a, b, scratch) catch unreachable;
    return edits.items;
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
        const timing = rt.node(@src(), graph_nodes.timing, .{}, .{
            .time = frontend.poll(.time),
        });
        const animate_meshes = rt.node(@src(), graph_nodes.animateMeshes, .{}, .{
            .models = resources.models,
            .seconds_since_start = timing.seconds_since_start,
        });
        const display_bike = rt.node(@src(), graph_nodes.displayBike, .{}, .{
            .terrain_sampler = terrain.sampler,
            .seconds_since_start = timing.seconds_since_start,
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

        const changed_models = concatChanged(rt.frame_arena.allocator(), types.GameModel, model_sources);
        const all_models = concatDirty(rt.frame_arena.allocator(), types.GameModel, model_sources);
        const instance_sources = &.{
            forest.model_instances,
            display_bike.model_instances,
        };
        const changed_instances = concatChanged(rt.frame_arena.allocator(), types.ModelInstances, instance_sources);
        const all_instances = concatDirty(rt.frame_arena.allocator(), types.ModelInstances, instance_sources);
        const shadow_update_bounds = blk: {
            var model_lookup = std.StringHashMap(types.GameModel).init(rt.frame_arena.allocator());
            for (all_models.raw) |model| {
                model_lookup.put(model.label, model) catch unreachable;
            }
            for (store.all_instances.raw, all_instances.raw) |store_instances, instances| {
                _ = diff(types.Instance, rt.frame_arena.allocator(), store_instances.instances, instances.instances);
            }

            break :blk null;
        };

        frontend.submit(.{
            .shadow_update_bounds = shadow_update_bounds,
            .models = changed_models,
            .model_instances = changed_instances,
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
            .terrain_sampler = terrain.sampler,
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
            .all_instances = all_instances,
            .all_models = all_models,
        };
    }
});
