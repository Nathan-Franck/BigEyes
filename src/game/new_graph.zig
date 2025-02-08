const std = @import("std");
const game = @import("../game.zig");
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

fn MappedFields(t: type, map: fn (in: type) type) type {
    var f: []const std.builtin.Type.StructField = &.{};
    for (@typeInfo(t).@"struct".fields) |field| {
        const new_t = map(field.type);
        f = f ++ .{std.builtin.Type.StructField{
            .name = field.name,
            .type = new_t,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(new_t),
        }};
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = f,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn Node(src: std.builtin.SourceLocation, @"fn": anytype, fields: anytype) type {
    _ = .{ src, fields };
    const fn_return = @typeInfo(@TypeOf(@"fn")).@"fn".return_type.?;

    const util = struct {
        fn InnerType(t: type) type {
            return struct { hi: t };
        }
    };
    const t = switch (@typeInfo(fn_return)) {
        .error_union => |e| e.payload,
        .@"struct" => fn_return,
        else => @compileError("unsupported type"),
    };
    const f = MappedFields(t, util.InnerType);

    return f;
}
fn node(comptime src: std.builtin.SourceLocation, @"fn": anytype, fields: anytype) Node(src, @"fn", fields) {
    return .{};
}
/// Meta-function that take multiple input slices and concatenate into a single output slice
fn concat(slice_inputs: anytype) type {
    _ = slice_inputs;
}

pub fn gameBlueprint() bool {
    const inputs = declareInputs(enum { time, last_time });
    const store = declareStore(enum { orbit_camera, player, forest_chunk_cache });
    const getResources = node(graph_nodes.getResources, .{});
    const timing = node(graph_nodes.timing, .{
        // .time = inputs.time,
        // .last_time = inputs.last_time,
    });
    const calculateTerrainDensityInfluenceRange = node(graph_nodes.calculateTerrainDensityInfluenceRange, .{
        // .size_multiplier = inputs.size_multiplier,
    });
    const orbit = node(graph_nodes.orbit, .{
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
    const displayTrees = node(graph_nodes.displayTrees, .{
        .cutout_leaf = getResources.cutout_leaf,
        .trees = getResources.trees,
    });
    const animateMeshes = node(graph_nodes.animateMeshes, .{
        .models = getResources.models,
        .seconds_since_start = timing.seconds_since_start,
    });
    const displayForest = node(graph_nodes.displayForest, .{
        .forest_chunk_cache = store.forest_chunk_cache,
        .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
    });
    const displayBike = node(graph_nodes.displayBike, .{
        .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
        .seconds_since_start = timing.seconds_since_start,
        .model_transforms = getResources.model_transforms,
        .bounce = inputs.bounce,
    });
    const displayTerrain = node(graph_nodes.displayTerrain, .{
        .terrain_sampler = calculateTerrainDensityInfluenceRange.terrain_sampler,
    });
    const getScreenspaceMesh = node(graph_nodes.getScreenspaceMesh, .{
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
