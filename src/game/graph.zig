const runtime = @import("../graph_runtime.zig");

pub const blueprint = runtime.Blueprint{
    .nodes = &[_]runtime.NodeGraphBlueprintEntry{
        .{ .name = "getResources", .function = "getResources", .input_links = &[_]runtime.InputLink{} },
        .{ .name = "orbit", .function = "orbit", .input_links = &[_]runtime.InputLink{
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
        } },
        .{ .name = "displayTrees", .function = "displayTrees", .input_links = &[_]runtime.InputLink{
            .{ .field = "cutout_leaf", .source = .{
                .node = .{ .name = "getResources", .field = "cutout_leaf" },
            } },
            .{ .field = "trees", .source = .{
                .node = .{ .name = "getResources", .field = "trees" },
            } },
        } },
        .{ .name = "displayForest", .function = "displayForest", .input_links = &[_]runtime.InputLink{} },
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
    },
    .output = &[_]runtime.SystemSink{
        .{ .output_node = "getResources", .output_field = "skybox", .system_field = "skybox" },
        .{ .output_node = "getScreenspaceMesh", .output_field = "screen_space_mesh", .system_field = "screen_space_mesh" },
        .{ .output_node = "displayTrees", .output_field = "models", .system_field = "models" },
        .{ .output_node = "displayForest", .output_field = "forest_data", .system_field = "forest_data" },
        .{ .output_node = "orbit", .output_field = "world_matrix", .system_field = "world_matrix" },
    },
};

// const concept = @import("../node_graph_concept.zig");
// const Node = concept.Node;
// const something = struct {
//     pub const nodes = struct {
//         pub const get_resources = Node(GetResources){ .in = .{} };
//         pub const orbit = Node(Orbit){ .in = .{
//             .render_resolution = &input.render_resolution,
//             .orbit_speed = &input.orbit_speed,
//             .input = &input.input,
//             .orbit_camera = &store.out.orbit_camera,
//         } };
//         pub const display_tree = Node(DisplayTree){ .in = .{
//             .cutout_leaf = &get_resources.cutout_leaf,
//             .tree = &get_resources.tree,
//         } };
//         pub const display_forest = Node(DisplayForest){ .in = .{} };
//         pub const get_screenspace_mesh = Node(GetScreenspaceMesh){ .in = .{
//             .camera_position = &orbit.camera_position,
//             .world_matrix = &orbit.world_matrix,
//         } };
//     };
// };
