const runtime = @import("../graph_runtime.zig");

pub const blueprint = runtime.Blueprint{
    .nodes = &[_]runtime.NodeGraphBlueprintEntry{
        .{
            .name = "getResources",
            .function = "getResources",
            .input_links = &[_]runtime.InputLink{},
        },
        .{
            .name = "orbit",
            .function = "orbit",
            .input_links = &[_]runtime.InputLink{
                .{ .field = "render_resolution", .source = .{ .input_field = "render_resolution" } },
                .{ .field = "orbit_speed", .source = .{ .input_field = "orbit_speed" } },
                .{ .field = "input", .source = .{ .input_field = "input" } },
                .{ .field = "orbit_camera", .source = .{ .store_field = "orbit_camera" } },
            },
        },
        .{
            .name = "displayTree",
            .function = "displayTree",
            .input_links = &[_]runtime.InputLink{
                .{ .field = "cutout_leaf", .source = .{ .node = .{ .name = "getResources", .field = "cutout_leaf" } } },
                .{ .field = "tree", .source = .{ .node = .{ .name = "getResources", .field = "tree" } } },
            },
        },
        .{
            .name = "displayForest",
            .function = "displayForest",
            .input_links = &[_]runtime.InputLink{},
        },
        .{
            .name = "getScreenspaceMesh",
            .function = "getScreenspaceMesh",
            .input_links = &[_]runtime.InputLink{
                .{ .field = "camera_position", .source = .{ .node = .{ .name = "orbit", .field = "camera_position" } } },
                .{ .field = "world_matrix", .source = .{ .node = .{ .name = "orbit", .field = "world_matrix" } } },
            },
        },
        // .{
        //     .name = "changeSettings",
        //     .function = "changeSettings",
        //     .input_links = &[_]runtime.InputLink{
        //         .{ .field = "user_changes", .source = .{ .input_field = "user_changes" } },
        //         .{ .field = "settings", .source = .{ .store_field = "settings" } },
        //     },
        // },
    },

    .store = &[_]runtime.SystemSink{
        .{ .output_node = "orbit", .output_field = "orbit_camera", .system_field = "orbit_camera" },
        // .{ .output_node = "changeSettings", .output_field = "settings", .system_field = "settings" },
    },
    .output = &[_]runtime.SystemSink{
        .{ .output_node = "getResources", .output_field = "skybox", .system_field = "skybox" },
        .{ .output_node = "getScreenspaceMesh", .output_field = "screen_space_mesh", .system_field = "screen_space_mesh" },
        .{ .output_node = "displayTree", .output_field = "meshes", .system_field = "meshes" },
        .{ .output_node = "displayForest", .output_field = "forest_data", .system_field = "forest_data" },
        .{ .output_node = "orbit", .output_field = "world_matrix", .system_field = "world_matrix" },
    },
};
