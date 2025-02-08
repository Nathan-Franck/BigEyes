const std = @import("std");
const runtime = @import("../graph_runtime.zig");
const graph_nodes = @import("./game.zig").graph_functions;
const types = @import("./types.zig");
const builtin = std.builtin;

fn Inputs(fields: anytype) type {
    _ = fields;
    return struct {};
}
fn Outputs(fields: anytype) type {
    _ = fields;
    return struct {};
}
fn Store(fields: anytype) type {
    _ = fields;
    return struct {};
}
fn Node() type {
    return struct {};
}

fn node(@"fn": anytype, fields: anytype) Node(@typeInfo(@TypeOf(@"fn")).@"fn".return_type.?) {}

/// Meta-function that take multiple input slices and concatenate into a single output slice
fn concat(slice_inputs: anytype) Node(enum { combined }) {}

fn gameBlueprint(
    inputs: Inputs(enum { time, last_time }),
    store: Store(enum { orbit_camera, player, forest_chunk_cache }),
) Outputs(struct {}) {
    const getResources = node(@src(), graph_nodes.getResources, .{});
    const timing = node(@src(), graph_nodes.timing, .{
        .time = inputs.time,
        .last_time = inputs.last_time,
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
    return .{
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
}
