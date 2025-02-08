const std = @import("std");
const game = @import("../game.zig");
const types = @import("resources").types;
const config = @import("resources").config;
const graph_nodes = game.graph_nodes;
const builtin = std.builtin;

fn declareInputs(fields: anytype) type {
    _ = fields;
    return struct {};
}

fn declareOutputs(fields: anytype) type {
    _ = fields;
    return struct {};
}

fn declareStore(fields: anytype) type {
    _ = fields;
    return struct {};
}

fn AllocatorFirstParam(t: type) bool {
    const fn_params = fnParams(t);
    return switch (fn_params.len) {
        1 => false,
        2 => true,
        else => @compileError("Unsupported node function parameters"),
    };
}

fn fnParams(t: type) []const std.builtin.Type.Fn.Param {
    return @typeInfo(t).@"fn".params;
}

fn NodeInputs(@"fn": anytype) type {
    const fn_params = fnParams(@TypeOf(@"fn"));
    return fn_params[if (AllocatorFirstParam(@TypeOf(@"fn"))) 1 else 0].type.?;
}

fn NodeOutputs(@"fn": anytype) type {
    const fn_return = @typeInfo(@TypeOf(@"fn")).@"fn".return_type.?;
    return switch (@typeInfo(fn_return)) {
        else => fn_return,
        .error_union => |e| e.payload,
    };
}

fn node(comptime src: std.builtin.SourceLocation, @"fn": anytype, fields: NodeInputs(@"fn")) NodeOutputs(@"fn") {
    _ = src;
    @compileLog(fnParams(@TypeOf(@"fn")));
    const fn_output = @call(.auto, @"fn", comptime if (AllocatorFirstParam(@TypeOf(@"fn")))
        .{ std.heap.page_allocator, fields }
    else
        .{fields});
    return switch (@typeInfo(@TypeOf(fn_output))) {
        else => fn_output,
        .error_union => try fn_output,
    };
}

/// Meta-function that take multiple input slices and concatenate into a single output slice
fn concat(slice_inputs: anytype) type {
    _ = slice_inputs;
}

pub fn gameBlueprint(
    inputs: struct {
        time: u64,
        render_resolution: types.PixelPoint,
        orbit_speed: f32,
        input: types.Input,
        selected_camera: types.SelectedCamera,
        player_settings: types.PlayerSettings,
        bounce: bool,
        size_multiplier: f32,
    },
    store: struct {
        last_time: u64,
        orbit_camera: types.OrbitCamera,
        player: types.Player,
        forest_chunk_cache: config.ForestSpawner.ChunkCache,
    },
) bool {
    const getResources = node(@src(), graph_nodes.getResources, .{});
    const timing = node(@src(), graph_nodes.timing, .{
        .time = inputs.time,
        .last_time = store.last_time,
    });
    const calculateTerrainDensityInfluenceRange = node(@src(), graph_nodes.calculateTerrainDensityInfluenceRange, .{
        .size_multiplier = inputs.size_multiplier,
    });
    const orbit = node(@src(), graph_nodes.orbit, .{
        .delta_time = timing.delta_time,
        .render_resolution = inputs.render_resolution,
        .orbit_speed = inputs.orbit_speed,
        .input = inputs.input,
        .orbit_camera = store.orbit_camera,
        .selected_camera = inputs.selected_camera,
        .player_settings = inputs.player_settings,
        .player = store.player,
        .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
    });
    const displayTrees = node(@src(), graph_nodes.displayTrees, .{
        .cutout_leaf = getResources.cutout_leaf,
        .trees = getResources.trees,
    });
    const animateMeshes = node(@src(), graph_nodes.animateMeshes, .{
        .models = getResources.models,
        .seconds_since_start = timing.seconds_since_start,
    });
    const displayForest = node(@src(), graph_nodes.displayForest, .{
        .forest_chunk_cache = store.forest_chunk_cache,
        .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
    });
    const displayBike = node(@src(), graph_nodes.displayBike, .{
        .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
        .seconds_since_start = timing.seconds_since_start,
        .model_transforms = getResources.model_transforms,
        .bounce = inputs.bounce,
    });
    const displayTerrain = node(@src(), graph_nodes.displayTerrain, .{
        .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
    });
    const getScreenspaceMesh = node(@src(), graph_nodes.getScreenspaceMesh, .{
        .camera_position = orbit.camera_position,
        .world_matrix = orbit.world_matrix,
    });
    _ = .{
        .store = .{
            .orbit_camera = orbit.orbit_camera,
            .last_time = timing.last_time,
            .player = orbit.player,
            .forest_chunk_cache = displayForest.forest_chunk_cache,
        },
        .output = .{
            .skybox = getResources.skybox,
            .models = concat(.{ getResources.models, animateMeshes.models, displayTrees.models }),
            .screen_space_mesh = getScreenspaceMesh.screen_space_mesh,
            .model_instances = concat(.{ displayForest.model_instances, displayBike.model_instances }),
            .terrain_mesh = displayTerrain.terrain_mesh,
            .terrain_instance = displayTerrain.terrain_instance,
            .world_matrix = orbit.world_matrix,
        },
    };

    return true;
}
