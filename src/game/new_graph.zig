const std = @import("std");
const game = @import("../game.zig");
const utils = @import("utils");
const utils_node = @import("node_graph").utils_node;
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

fn isAllocatorFirstParam(t: type) bool {
    const params = fnParams(t);
    return switch (params.len) {
        1 => false,
        2 => true,
        else => @compileError("Unsupported node function parameters"),
    };
}

fn fnParams(t: type) []const std.builtin.Type.Fn.Param {
    return @typeInfo(t).@"fn".params;
}

fn ParamsToNodeProps(@"fn": type) type {
    const params = fnParams(@"fn");
    return params[if (isAllocatorFirstParam(@"fn")) 1 else 0].type.?;
}

fn NodeInputs(@"fn": anytype) type {
    const raw_props = ParamsToNodeProps(@TypeOf(@"fn"));
    var new_field: []const std.builtin.Type.StructField = &.{};
    for (@typeInfo(raw_props).@"struct".fields) |field| {
        const default = .{ field.type, @alignOf(field.type) };
        const new_t: type, const alignment: comptime_int = switch (@typeInfo(field.type)) {
            .@"struct" => blk: {
                if (utils_node.queryable.getSourceOrNull(field.type)) |t| {
                    break :blk .{ t, @alignOf(t) };
                } else {
                    break :blk default;
                }
            },
            .pointer => |pointer| if (!pointer.is_const) switch (pointer.size) {
                else => default,
                .One => .{ pointer.child, @alignOf(field.type) },
                .Slice => .{ []const pointer.child, @alignOf(field.type) },
            } else default,
            else => default,
        };
        new_field = new_field ++ .{std.builtin.Type.StructField{
            .name = field.name,
            .type = new_t,
            .default_value = null,
            .is_comptime = false,
            .alignment = alignment,
        }};
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = new_field,
        .decls = &.{},
        .is_tuple = false,
    } });
}
fn MutableProps(@"fn": anytype) type {
    const raw_props = ParamsToNodeProps(@TypeOf(@"fn"));
    var new_field: []const std.builtin.Type.StructField = &.{};
    for (@typeInfo(raw_props).@"struct".fields) |field| {
        const new_t: type, const alignment: comptime_int = switch (@typeInfo(field.type)) {
            .pointer => |pointer| if (!pointer.is_const) switch (pointer.size) {
                else => continue,
                .One => .{ pointer.child, @alignOf(pointer.child) },
                .Slice => .{ []const pointer.child, @alignOf(pointer.child) },
            } else continue,
            else => continue,
        };
        new_field = new_field ++ .{std.builtin.Type.StructField{
            .name = field.name,
            .type = new_t,
            .default_value = null,
            .is_comptime = false,
            .alignment = alignment,
        }};
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = new_field,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn NodeOutputs(@"fn": anytype) type {
    const MP = MutableProps(@"fn");
    const fn_return = @typeInfo(@TypeOf(@"fn")).@"fn".return_type.?;
    const raw_return = switch (@typeInfo(fn_return)) {
        else => fn_return,
        .error_union => |e| e.payload,
    };
    var new_fields = @typeInfo(raw_return).@"struct".fields;
    for (@typeInfo(MP).@"struct".fields) |mutable_field| {
        new_fields = new_fields ++ .{mutable_field};
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = new_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn node(comptime src: std.builtin.SourceLocation, @"fn": anytype, raw_props: NodeInputs(@"fn")) NodeOutputs(@"fn") {
    _ = src;
    const Props = ParamsToNodeProps(@TypeOf(@"fn"));
    var props: Props = undefined;
    var mutable_props: MutableProps(@"fn") = undefined;
    inline for (@typeInfo(@TypeOf(mutable_props)).@"struct".fields) |field| {
        @field(mutable_props, field.name) = @field(raw_props, field.name);
    }
    inline for (@typeInfo(Props).@"struct".fields) |prop| {
        const default = @field(raw_props, prop.name);
        @field(props, prop.name) = switch (@typeInfo(prop.type)) {
            .@"struct" => blk: {
                if (utils_node.queryable.getSourceOrNull(prop.type)) |t| {
                    var is_field_dirty = false; // TODO - Proper queryable change detection
                    var queried = true;
                    break :blk utils_node.queryable.Value(t).initQueryable(default, &is_field_dirty, &queried);
                } else {
                    break :blk default;
                }
            },
            .pointer => |pointer| if (!pointer.is_const) switch (pointer.size) {
                else => default,
                .One => &@field(mutable_props, prop.name),
                .Slice => &@field(raw_props, prop.name),
            } else default,
            else => default,
        };
    }
    const raw_fn_output = @call(.auto, @"fn", if (comptime isAllocatorFirstParam(@TypeOf(@"fn")))
        .{ std.heap.page_allocator, props }
    else
        .{props});
    const fn_output = switch (@typeInfo(@TypeOf(raw_fn_output))) {
        else => raw_fn_output,
        .error_union => raw_fn_output catch @panic("Error thrown in a node call!"),
    };
    var node_output: NodeOutputs(@"fn") = undefined;
    inline for (@typeInfo(@TypeOf(fn_output)).@"struct".fields) |field| {
        @field(node_output, field.name) = @field(fn_output, field.name);
    }
    inline for (@typeInfo(@TypeOf(mutable_props)).@"struct".fields) |field| {
        @field(node_output, field.name) = @field(mutable_props, field.name);
    }
    return node_output;
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
