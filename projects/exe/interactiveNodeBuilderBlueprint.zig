pub const SystemSource = struct {
    system_field: ?[]const u8 = null, // if null, assume system field is the same as input field.
    input_field: []const u8,
};

pub const InputLink = union(enum) {
    node: struct {
        name: []const u8,
        output_field: ?[]const u8 = null, // if null, assume output field is the same as input field.
        input_field: []const u8,
    },
    external: SystemSource,
    store: SystemSource,
};

pub const NodeGraphBlueprintEntry = struct {
    name: ?[]const u8 = null, // if null, assume name is function name.
    function: []const u8,
    input_links: []const InputLink,
};

pub const SystemSink = struct {
    output_node: []const u8,
    output_field: ?[]const u8 = null, // if null, assume output field is the same as system field.
    system_field: []const u8,
};

pub const Blueprint = struct {
    nodes: []const NodeGraphBlueprintEntry,
    store: []const SystemSink,
    external: []const SystemSink,
};

pub const node_graph_blueprint: Blueprint = .{
    .nodes = .{
        .{
            .function = "graphLoader",
            .input_links = .{
                .{ .external = .{ .input_field = "graph_update" } },
                .{ .store = .{ .input_field = "blueprint" } },
            },
        },
        .{
            .function = "contextMenuInteraction",
            .input_links = .{
                .{ .external = .{ .input_field = "mouse_event" } },
                .{ .external = .{ .input_field = "node_event" } },
                .{ .external = .{ .input_field = "context_event" } },
                .{ .store = .{ .input_field = "context_menu" } },
            },
        },
        .{
            .function = "nodeInteraction",
            .input_links = .{
                .{ .external = .{ .input_field = "keyboard_modifiers" } },
                .{ .store = .{ .input_field = "active_node" } },
                .{ .node = .{ .name = "graphLoader", .input_field = "blueprint" } },
                .{ .node = .{ .name = "contextMenuInteraction", .output_field = "unused_mouse_event", .input_field = "mouse_event" } },
                .{ .node = .{ .name = "contextMenuInteraction", .output_field = "unused_node_event", .input_field = "node_event" } },
            },
        },
        .{
            .function = "cameraControls",
            .input_links = .{
                .{ .external = .{ .input_field = "keyboard_modifiers" } },
                .{ .store = .{ .input_field = "camera" } },
                .{ .node = .{ .name = "nodeInteraction", .output_field = "unused_mouse_event", .input_field = "mouse_event" } },
            },
        },
        .{
            .function = "nodeFormatting",
            .input_links = .{
                .{ .node = .{ .name = "contextMenuInteraction", .input_field = "grouping_event" } },
                .{ .node = .{ .name = "nodeInteraction", .input_field = "blueprint" } },
            },
        },
        .{
            .function = "dom_renderer",
            .input_links = .{
                .{ .store = .{ .system_field = "blueprint", .input_field = "previous_blueprint" } },
                .{ .node = .{ .name = "nodeFormatting", .input_field = "current_blueprint" } },
                .{ .node = .{ .name = "cameraControls", .input_field = "camera" } },
                .{ .node = .{ .name = "contextMenuInteraction", .input_field = "context_menu" } },
            },
        },
    },
    .store = .{
        .{ .output_node = "contextMenuInteraction", .system_field = "context_menu" },
        .{ .output_node = "nodeInteraction", .system_field = "active_node" },
        .{ .output_node = "cameraControls", .system_field = "camera" },
        .{ .output_node = "nodeFormatting", .system_field = "blueprint" },
    },
    .external = .{
        .{ .output_node = "dom_renderer", .system_field = "render_event" },
        .{ .output_node = "???", .output_field = "???", .system_field = "blueprint_update" },
    },
};
