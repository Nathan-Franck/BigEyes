const runtime = @import("../graph_runtime.zig");

pub const blueprint = runtime.Blueprint{
    .nodes = &[_]runtime.NodeGraphBlueprintEntry{
        .{ .name = "getResources", .function = "getResources", .input_links = &[_]runtime.InputLink{} },
        .{ .name = "timing", .function = "timing", .input_links = &[_]runtime.InputLink{
            .{ .field = "time", .source = .{
                .input_field = "time",
            } },
            .{ .field = "last_time", .source = .{
                .store_field = "last_time",
            } },
        } },
        .{ .name = "orbit", .function = "orbit", .input_links = &[_]runtime.InputLink{
            .{ .field = "delta_time", .source = .{
                .node = .{ .name = "timing", .field = "delta_time" },
            } },
            .{ .field = "render_resolution", .source = .{
                .input_field = "render_resolution",
            } },
            .{ .field = "orbit_speed", .source = .{
                .input_field = "orbit_speed",
            } },
            .{ .field = "input", .source = .{
                .input_field = "input",
            } },
            .{ .field = "orbit_camera", .source = .{
                .store_field = "orbit_camera",
            } },
            .{ .field = "selected_camera", .source = .{
                .input_field = "selected_camera",
            } },
            .{ .field = "player_settings", .source = .{
                .input_field = "player_settings",
            } },
            .{ .field = "player", .source = .{
                .store_field = "player",
            } },
            .{ .field = "terrain_sampler", .source = .{
                .node = .{ .name = "calculateTerrainDensityInfluenceRange", .field = "terrain_sampler" },
            } },
        } },
        .{ .name = "displayTrees", .function = "displayTrees", .input_links = &[_]runtime.InputLink{
            .{ .field = "cutout_leaf", .source = .{
                .node = .{ .name = "getResources", .field = "cutout_leaf" },
            } },
            .{ .field = "trees", .source = .{
                .node = .{ .name = "getResources", .field = "trees" },
            } },
        } },
        .{ .name = "displayForest", .function = "displayForest", .input_links = &[_]runtime.InputLink{
            .{ .field = "forest_chunk_cache", .source = .{
                .store_field = "forest_chunk_cache",
            } },
            .{ .field = "terrain_sampler", .source = .{
                .node = .{ .name = "calculateTerrainDensityInfluenceRange", .field = "terrain_sampler" },
            } },
        } },
        .{ .name = "displayBike", .function = "displayBike", .input_links = &[_]runtime.InputLink{
            .{ .field = "terrain_sampler", .source = .{
                .node = .{ .name = "calculateTerrainDensityInfluenceRange", .field = "terrain_sampler" },
            } },
            .{ .field = "seconds_since_start", .source = .{
                .node = .{ .name = "timing", .field = "seconds_since_start" },
            } },
            .{ .field = "model_transforms", .source = .{
                .node = .{ .name = "getResources", .field = "model_transforms" },
            } },
            .{ .field = "bounce", .source = .{ .input_field = "bounce" } },
        } },
        .{ .name = "displayTerrain", .function = "displayTerrain", .input_links = &[_]runtime.InputLink{
            .{ .field = "terrain_sampler", .source = .{
                .node = .{ .name = "calculateTerrainDensityInfluenceRange", .field = "terrain_sampler" },
            } },
        } },
        .{ .name = "calculateTerrainDensityInfluenceRange", .function = "calculateTerrainDensityInfluenceRange", .input_links = &[_]runtime.InputLink{
            .{ .field = "size_multiplier", .source = .{ .input_field = "size_multiplier" } },
        } },
        .{ .name = "getScreenspaceMesh", .function = "getScreenspaceMesh", .input_links = &[_]runtime.InputLink{
            .{ .field = "camera_position", .source = .{
                .node = .{ .name = "orbit", .field = "camera_position" },
            } },
            .{ .field = "world_matrix", .source = .{
                .node = .{ .name = "orbit", .field = "world_matrix" },
            } },
        } },
    },
    .store = &[_]runtime.SystemSink{
        .{ .output_node = "orbit", .output_field = "orbit_camera", .system_field = "orbit_camera" },
        .{ .output_node = "timing", .output_field = "last_time", .system_field = "last_time" },
        .{ .output_node = "orbit", .output_field = "player", .system_field = "player" },
        .{ .output_node = "displayForest", .output_field = "forest_chunk_cache", .system_field = "forest_chunk_cache" },
    },
    .output = &[_]runtime.SystemSink{
        .{ .output_node = "getResources", .output_field = "skybox", .system_field = "skybox" },
        .{ .output_node = "getResources", .output_field = "models", .system_field = "models" },
        .{ .output_node = "getScreenspaceMesh", .output_field = "screen_space_mesh", .system_field = "screen_space_mesh" },
        .{ .output_node = "displayTrees", .output_field = "models", .system_field = "models" },
        .{ .output_node = "displayForest", .output_field = "model_instances", .system_field = "model_instances" },
        .{ .output_node = "displayBike", .output_field = "model_instances", .system_field = "model_instances" },
        .{ .output_node = "displayTerrain", .output_field = "terrain_mesh", .system_field = "terrain_mesh" },
        .{ .output_node = "displayTerrain", .output_field = "terrain_instance", .system_field = "terrain_instance" },
        .{ .output_node = "orbit", .output_field = "world_matrix", .system_field = "world_matrix" },
    },
};
