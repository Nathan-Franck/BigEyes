pub const InputLink = struct {
    field: []const u8,
    source: union(enum) {
        node: struct {
            name: []const u8,
            field: []const u8,
        },
        input_field: []const u8,
        store_field: []const u8,
    },
};

pub const NodeGraphBlueprintEntry = struct {
    name: []const u8,
    function: []const u8,
    input_links: []const InputLink,
};

pub const SystemSink = struct {
    output_node: []const u8,
    output_field: []const u8,
    system_field: []const u8,
};

pub const Blueprint = struct {
    nodes: []const NodeGraphBlueprintEntry,
    store: []const SystemSink,
    output: []const SystemSink,
};

pub const node_graph_blueprint: Blueprint = .{
    .nodes = &.{
        // .{
        //     .name = "AllResources",
        //     .function = "AllResources",
        //     .input_links = &.{},
        // },
        .{
            .name = "BlueprintLoader",
            .function = "BlueprintLoader",
            .input_links = &.{
                .{ .field = "recieved_blueprint", .source = .{ .input_field = "recieved_blueprint" } },
                .{ .field = "existing_blueprint", .source = .{ .store_field = "blueprint" } },
            },
        },
        .{
            .name = "ContextMenuInteraction",
            .function = "ContextMenuInteraction",
            .input_links = &.{
                .{ .field = "event", .source = .{ .input_field = "event" } },
                .{ .field = "context_menu", .source = .{ .store_field = "context_menu" } },
            },
        },
        .{
            .name = "NodeInteraction",
            .function = "NodeInteraction",
            .input_links = &.{
                .{ .field = "keyboard_modifiers", .source = .{ .input_field = "keyboard_modifiers" } },
                .{ .field = "interaction_state", .source = .{ .store_field = "interaction_state" } },
                .{ .field = "blueprint", .source = .{ .node = .{ .name = "BlueprintLoader", .field = "blueprint" } } },
                .{ .field = "event", .source = .{ .node = .{ .name = "ContextMenuInteraction", .field = "event" } } },
            },
        },
        .{
            .name = "CameraControls",
            .function = "CameraControls",
            .input_links = &.{
                .{
                    .field = "keyboard_modifiers",
                    .source = .{ .input_field = "keyboard_modifiers" },
                },
                .{
                    .field = "camera",
                    .source = .{ .store_field = "camera" },
                },
                .{
                    .field = "event",
                    .source = .{ .node = .{ .field = "event", .name = "NodeInteraction" } },
                },
            },
        },
        .{
            .name = "NodeFormatting",
            .function = "NodeFormatting",
            .input_links = &.{
                .{ .field = "node_dimensions", .source = .{ .store_field = "node_dimensions" } },
                .{ .field = "post_render_event", .source = .{ .input_field = "post_render_event" } },
                .{ .field = "event", .source = .{ .node = .{ .field = "event", .name = "ContextMenuInteraction" } } },
                .{ .field = "blueprint", .source = .{ .node = .{ .field = "blueprint", .name = "NodeInteraction" } } },
            },
        },
        // .{
        //     .name = "DomRenderer",
        //     .function = "DomRenderer",
        //     .input_links = &.{
        //         .{
        //             .field = "previous_blueprint",
        //             .source = .{ .store_field = "blueprint" },
        //         },
        //         .{
        //             .field = "current_blueprint",
        //             .source = .{ .node = .{ .field = "blueprint", .name = "NodeFormatting" } },
        //         },
        //         .{
        //             .field = "camera",
        //             .source = .{ .node = .{ .field = "camera", .name = "CameraControls" } },
        //         },
        //         .{
        //             .field = "context_menu",
        //             .source = .{ .node = .{ .field = "context_menu", .name = "ContextMenuInteraction" } },
        //         },
        //     },
        // },
    },
    .store = &.{
        .{ .system_field = "context_menu", .output_node = "ContextMenuInteraction", .output_field = "context_menu" },
        // .{ .system_field = "active_node", .output_node = "NodeInteraction", .output_field = "active_node" },
        .{ .system_field = "camera", .output_node = "CameraControls", .output_field = "camera" },
        .{ .system_field = "blueprint", .output_node = "NodeInteraction", .output_field = "blueprint" },
        .{ .system_field = "interaction_state", .output_node = "NodeInteraction", .output_field = "interaction_state" },
        .{ .system_field = "node_dimensions", .output_node = "NodeFormatting", .output_field = "node_dimensions" },
    },
    .output = &.{
        // .{ .system_field = "smile_test", .output_node = "AllResources", .output_field = "smile_test" },
        .{ .system_field = "event", .output_node = "ContextMenuInteraction", .output_field = "event" },
        .{ .system_field = "blueprint", .output_node = "NodeInteraction", .output_field = "blueprint" },
        .{ .system_field = "camera", .output_node = "CameraControls", .output_field = "camera" },
        .{ .system_field = "context_menu", .output_node = "ContextMenuInteraction", .output_field = "context_menu" },
        .{ .system_field = "node_coords", .output_node = "NodeFormatting", .output_field = "node_coords" },
        // .{ .system_field = "render_event", .output_node = "DomRenderer", .output_field = "render_event" },
    },
};

test "InputLink to Json" {
    const std = @import("std");
    const allocator = std.heap.page_allocator;
    const inputLink: InputLink = .{
        .field = "input",
        .source = .{ .node = .{
            .name = "test",
            .field = "input",
        } },
    };
    const json = try std.json.stringifyAlloc(allocator, inputLink, .{});
    _ = json;
    _ = node_graph_blueprint;
    // std.debug.print("json: {s}\n", .{json});
    // expect(json).toBe(`{"node":{"from":"test","output_field":"output","field":"input"}}`);
}
