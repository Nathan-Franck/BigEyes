pub const InputLink = union(enum) {
    node: struct {
        name: []const u8,
        output_field: ?[]const u8 = null, // if null, assume output field is the same as input field.
        input_field: []const u8,
    },
    parameter: struct {
        parameter_field: ?[]const u8 = null, // if null, assume parameter field is the same as input field.
        input_field: []const u8,
    },
};

pub const NodeGraphBlueprintEntry = struct {
    name: ?[]const u8 = null, // if null, assume name is function name.
    function: []const u8,
    input_links: []const InputLink,
};

pub const NodeGraphReturn = struct {
    output_node: []const u8,
    output_field: []const u8,
    return_field: []const u8,
};

pub const Blueprint = struct {
    nodes: []const NodeGraphBlueprintEntry,
    returns: []const NodeGraphReturn,
};

pub const node_graph_blueprint: Blueprint = .{
    .nodes = .{
        .{
            .function = "cameraControls",
            .input_links = .{
                .{ .parameter = .{ .input_field = "drag" } },
                .{ .parameter = .{ .input_field = "drag_end" } },
                .{ .parameter = .{ .input_field = "scroll" } },
                .{ .parameter = .{ .input_field = "keyboard_modifiers" } },
            },
        },
        .{
            .function = "contextMenuInteraction",
            .input_links = .{
                .{ .parameter = .{ .input_field = "node_right_click" } },
                .{ .parameter = .{ .input_field = "right_click" } },
                .{ .parameter = .{ .input_field = "context_click" } },
            },
        },
        .{
            .function = "nodeInteraction",
            .input_links = .{
                .{ .parameter = .{ .input_field = "drag" } },
                .{ .parameter = .{ .input_field = "drag_end" } },
                .{ .parameter = .{ .input_field = "node_drag" } },
                .{ .parameter = .{ .input_field = "node_drag_end" } },
                .{ .parameter = .{ .input_field = "node_clicked" } },
                .{ .parameter = .{ .input_field = "keyboard_modifiers" } },
            },
        },
        .{
            .function = "graphLoader",
            .input_links = .{
                .{ .parameter = .{ .input_field = "graph_update" } },
            },
        },
    },
    .returns = .{
        // UI update.
        .{
            .output_node = "???",
            .output_field = "???",
            .return_field = "dom_update",
        },
        // Network update.
        .{
            .output_node = "???",
            .output_field = "???",
            .return_field = "blueprint_update",
        },
    },
};
