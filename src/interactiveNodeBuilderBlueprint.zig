pub const SystemSource = struct {
    system_field: ?[]const u8 = null, // if null, assume system field is the same as input field.
    input_field: []const u8,

    pub inline fn uniqueID(self: @This()) []const u8 {
        if (self.system_field) |system_field| {
            return system_field;
        }
        return self.input_field;
    }
};

pub const InputLink = union(enum) {
    node: struct {
        from: []const u8,
        output_field: ?[]const u8 = null, // if null, assume output field is the same as input field.
        input_field: []const u8,

        pub inline fn uniqueID(self: @This()) []const u8 {
            if (self.output_field) |name| {
                return name;
            }
            return self.input_field;
        }
    },
    input: SystemSource,
    store: SystemSource,
};

pub const NodeGraphBlueprintEntry = struct {
    name: ?[]const u8 = null, // if null, assume name is function name.
    function: []const u8,
    input_links: []const InputLink,

    pub inline fn uniqueID(self: @This()) []const u8 {
        if (self.name) |name| {
            return name;
        }
        return self.function;
    }
};

pub const SystemSink = struct {
    output_node: []const u8,
    output_field: ?[]const u8 = null, // if null, assume output field is the same as system field.
    system_field: []const u8,

    pub inline fn uniqueID(self: @This()) []const u8 {
        if (self.output_field) |output_field| {
            return output_field;
        }
        return self.system_field;
    }
};

pub const Blueprint = struct {
    nodes: []const NodeGraphBlueprintEntry,
    store: []const SystemSink,
    output: []const SystemSink,
};

pub const node_graph_blueprint: Blueprint = .{
    .nodes = &.{
        .{
            .function = "BlueprintLoader",
            .input_links = &.{
                .{ .input = .{ .input_field = "recieved_blueprint" } },
                .{ .store = .{ .system_field = "blueprint", .input_field = "existing_blueprint" } },
            },
        },
        .{
            .function = "ContextMenuInteraction",
            .input_links = &.{
                .{ .input = .{ .input_field = "event" } },
                .{ .store = .{ .input_field = "context_menu" } },
            },
        },
        .{
            .function = "NodeInteraction",
            .input_links = &.{
                .{ .input = .{ .input_field = "keyboard_modifiers" } },
                .{ .store = .{ .input_field = "interaction_state" } },
                .{ .node = .{ .input_field = "blueprint", .from = "BlueprintLoader" } },
                .{ .node = .{ .input_field = "event", .output_field = "event", .from = "ContextMenuInteraction" } },
            },
        },
        .{
            .function = "CameraControls",
            .input_links = &.{
                .{ .input = .{ .input_field = "keyboard_modifiers" } },
                .{ .store = .{ .input_field = "camera" } },
                .{ .node = .{ .input_field = "event", .output_field = "event", .from = "NodeInteraction" } },
            },
        },
        .{
            .function = "NodeFormatting",
            .input_links = &.{
                .{ .node = .{ .input_field = "event", .from = "ContextMenuInteraction" } },
                .{ .node = .{ .input_field = "blueprint", .from = "NodeInteraction" } },
            },
        },
        .{
            .function = "DomRenderer",
            .input_links = &.{
                .{ .store = .{ .input_field = "previous_blueprint", .system_field = "blueprint" } },
                .{ .node = .{ .input_field = "current_blueprint", .output_field = "blueprint", .from = "NodeFormatting" } },
                .{ .node = .{ .input_field = "camera", .from = "CameraControls" } },
                .{ .node = .{ .input_field = "context_menu", .from = "ContextMenuInteraction" } },
            },
        },
    },
    .store = &.{
        .{ .system_field = "context_menu", .output_node = "ContextMenuInteraction" },
        // .{ .system_field = "active_node", .output_node = "NodeInteraction" },
        .{ .system_field = "camera", .output_node = "CameraControls" },
        .{ .system_field = "blueprint", .output_node = "NodeFormatting" },
        .{ .system_field = "interaction_state", .output_node = "NodeInteraction" },
    },
    .output = &.{
        .{ .system_field = "render_event", .output_node = "DomRenderer" },
    },
};

test "InputLink to Json" {
    const std = @import("std");
    const allocator = std.heap.page_allocator;
    const inputLink: InputLink = .{
        .node = .{
            .from = "test",
            .output_field = "output",
            .input_field = "input",
        },
    };
    const json = try std.json.stringifyAlloc(allocator, inputLink, .{});
    std.debug.print("json: {s}\n", .{json});
    // expect(json).toBe(`{"node":{"from":"test","output_field":"output","input_field":"input"}}`);
}
