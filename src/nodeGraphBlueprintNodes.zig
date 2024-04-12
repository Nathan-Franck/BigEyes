const std = @import("std");
const NodeGraphBlueprintEntry = @import("./interactiveNodeBuilderBlueprint.zig").NodeGraphBlueprintEntry;
const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;
const utils = @import("./nodeUtils.zig");

allocator: std.mem.Allocator,

pub const MouseButton = enum {
    left,
    middle,
    right,
};

pub const ExternalMouseEvent = union(enum) {
    mouse_down: struct { location: GraphLocation, button: MouseButton },
    mouse_up: struct { location: GraphLocation, button: MouseButton },
    mouse_move: GraphLocation,
    mouse_wheel: struct { x: u32, y: u32, z: u32 },
};

pub const GroupingEvent = union(enum) {
    group: struct { node_names: []const []const u8 },
    ungroup: struct { node_names: []const []const u8 },
};

pub const KeyboardModifiers = struct {
    shift: bool,
    control: bool,
    alt: bool,
    super: bool,
};

pub const GraphLocation = struct {
    x: u32,
    y: u32,
};

pub const ExternalNodeEvent = struct {
    mouse_event: ExternalMouseEvent,
    node_name: []const u8,
};

pub const ContextMenuNodeOption = enum {
    delete,
    duplicate,
    copy,
};

pub const ContextMenuOption = enum {
    @"new...",
    paste,
};

// TODO: Implement group formatting / grouping, more necessary when I have a tonne of nodes.
// pub const GroupFormatting = enum {
//     horizontal,
//     vertical,
// };

pub const NodeEvent = union(enum) {
    create: struct { graph_location: GraphLocation, node_name: []const u8, node_type: []const u8 },
    delete: struct { node_name: []const u8 },
    duplicate: struct { node_name: []const u8 },
    copy: struct { node_name: []const u8 },
    paste: GraphLocation,
    // group: struct { node_names: []const []const u8, formatting: GroupFormatting },
};

pub const ExternalContextEvent = union(enum) {
    option_selected: []const u8,
};

pub const ContextState = struct {
    open: bool,
    selected_node: ?[]const u8 = null,
    location: GraphLocation,
    options: []const []const u8 = &.{},
};

pub const InteractionState = struct {
    node_selection: []const []const u8,
    box_selection: ?struct {
        start: GraphLocation,
        end: GraphLocation,
    } = null,
    wiggle: ?struct {
        node: []const u8,
        location: GraphLocation,
    } = null,
    clipboard: ?[]const NodeGraphBlueprintEntry = null,
};

fn selectionToNodes(
    allocator: std.mem.Allocator,
    all_nodes: []const NodeGraphBlueprintEntry,
    selection: []const []const u8,
) ![]const NodeGraphBlueprintEntry {
    const result = try allocator.alloc(NodeGraphBlueprintEntry, selection.len);
    for (result, 0..) |*item, index| {
        const existing_node = for (all_nodes) |node| {
            if (std.mem.eql(u8, selection[index], node.name))
                break node;
        } else @panic("gold tease");
        item.* = existing_node;
    }
    return result;
}

fn pasteNodesUnique(
    allocator: std.mem.Allocator,
    existing_nodes: []const NodeGraphBlueprintEntry,
    new_nodes: []const NodeGraphBlueprintEntry,
) ![]const NodeGraphBlueprintEntry {
    const unique_nodes = try allocator.alloc(NodeGraphBlueprintEntry, new_nodes.len);
    for (unique_nodes, 0..) |*unique_node, index| {
        const new_node = new_nodes[index];
        const existing_name = base_name: {
            var split_iter = std.mem.split(u8, new_node.name, "#");
            break :base_name split_iter.first();
        };
        var counter: u32 = 1;
        var name_candidate = existing_name;
        while (not_unique: {
            for (existing_nodes) |node| {
                if (std.mem.eql(u8, node.name, name_candidate))
                    break :not_unique true;
            } else for (unique_nodes[0..index]) |node| {
                if (std.mem.eql(u8, node.name, name_candidate))
                    break :not_unique true;
            } else break :not_unique false;
        }) {
            name_candidate = try std.fmt.allocPrint(allocator, "{s}#{d}", .{ existing_name, counter });
            counter += 1;
        }
        unique_node.* = new_node;
        unique_node.*.name = name_candidate;
    }
    return try std.mem.concat(allocator, NodeGraphBlueprintEntry, &.{ existing_nodes, unique_nodes });
}

const BlueprintLoaderInputs = struct {
    recieved_blueprint: ?Blueprint,
    existing_blueprint: Blueprint,
};
pub fn BlueprintLoader(input: BlueprintLoaderInputs) struct { blueprint: Blueprint } {
    if (input.recieved_blueprint) |update| {
        return .{ .blueprint = update };
    } else {
        return .{ .blueprint = input.existing_blueprint };
    }
}

pub fn ContextMenuInteraction(input: struct {
    context_menu: ContextState,
    event: ?union(enum) {
        mouse_event: ExternalMouseEvent,
        external_node_event: ExternalNodeEvent,
        context_event: ExternalContextEvent,
    },
}) struct {
    context_menu: ContextState,
    event: ?union(enum) {
        mouse_event: ExternalMouseEvent,
        external_node_event: ExternalNodeEvent,
        node_event: NodeEvent,
        grouping_event: GroupingEvent,
    } = null,
} {
    const default = .{
        .context_menu = input.context_menu,
        .event = utils.eventTransform(utils.NodeOutputEventType(ContextMenuInteraction), input.event),
    };
    return if (input.event) |event| switch (event) {
        .external_node_event => |node_event| switch (node_event.mouse_event) {
            else => default,
            .mouse_down => |mouse_down| switch (mouse_down.button) {
                else => default,
                .left => .{ .context_menu = utils.copyWith(input.context_menu, .{ .open = false }) },
                .right => .{ .context_menu = .{
                    .open = true,
                    .selected_node = node_event.node_name,
                    .location = mouse_down.location,
                    .options = comptime utils.fieldNamesToStrings(ContextMenuNodeOption),
                } },
            },
        },
        .mouse_event => |mouse_event| switch (mouse_event) {
            else => default,
            .mouse_down => |mouse_down| switch (mouse_down.button) {
                else => default,
                .left => .{ .context_menu = utils.copyWith(input.context_menu, .{ .open = false }) },
                .right => .{ .context_menu = .{
                    .open = true,
                    .location = mouse_down.location,
                    .options = comptime utils.fieldNamesToStrings(ContextMenuOption),
                } },
            },
        },
        .context_event => |context_event| switch (context_event) {
            .option_selected => result: {
                const menu_option_selected = std.meta.stringToEnum(ContextMenuOption, context_event.option_selected);
                const menu_node_option_selected = std.meta.stringToEnum(ContextMenuNodeOption, context_event.option_selected);
                break :result .{
                    .context_menu = utils.copyWith(input.context_menu, .{ .open = false }),
                    .event = if (menu_option_selected) |option| switch (option) {
                        .paste => .{ .node_event = .{ .paste = input.context_menu.location } },
                        .@"new..." => @panic("tardy spy"), // TODO: Implement new node creation.
                    } else if (menu_node_option_selected) |option| if (input.context_menu.selected_node) |selected_node| switch (option) {
                        .delete => .{ .node_event = .{ .delete = .{ .node_name = selected_node } } },
                        .duplicate => .{ .node_event = .{ .duplicate = .{ .node_name = selected_node } } },
                        .copy => .{ .node_event = .{ .copy = .{ .node_name = selected_node } } },
                    } else @panic("minty stair") else @panic("ritzy grace"), // TODO: Do I want this to crash or fail gracefully? Maybe float some error event up that an error message system can present the user?
                };
            },
        },
    } else default;
}

pub fn NodeInteraction(self: @This(), input: struct {
    keyboard_modifiers: KeyboardModifiers,
    interaction_state: InteractionState,
    blueprint: Blueprint,
    event: ?union(enum) {
        mouse_event: ExternalMouseEvent,
        external_node_event: ExternalNodeEvent,
        node_event: NodeEvent,
    },
}) !struct {
    interaction_state: InteractionState,
    blueprint: Blueprint,
    event: ?union(enum) {
        mouse_event: ExternalMouseEvent,
        external_node_event: ExternalNodeEvent,
    } = null,
} {
    const selection = input.interaction_state.node_selection;
    const default = .{
        .interaction_state = input.interaction_state,
        .blueprint = input.blueprint,
        .event = utils.eventTransform(utils.NodeOutputEventType(NodeInteraction), input.event),
    };
    return if (input.event) |event|
        if (input.keyboard_modifiers.shift)
            switch (event) {
                else => default,
                .external_node_event => |node_event| switch (node_event.mouse_event) {
                    else => default,
                    .mouse_down => .{ .blueprint = input.blueprint, .interaction_state = utils.copyWith(input.interaction_state, .{
                        .node_selection = if (for (selection, 0..) |item, index| (if (std.mem.eql(
                            u8,
                            item,
                            node_event.node_name,
                        )) break index) else null) |index| try std.mem.concat(self.allocator, []const u8, &.{
                            selection[0..index],
                            selection[index + 1 ..],
                        }) else try std.mem.concat(self.allocator, []const u8, &.{
                            selection,
                            &.{node_event.node_name},
                        }),
                    }) },
                },
            }
        else switch (event) {
            else => default,
            .external_node_event => |node_event| switch (node_event.mouse_event) {
                else => default,
                .mouse_down => .{ .blueprint = input.blueprint, .interaction_state = utils.copyWith(input.interaction_state, .{
                    .node_selection = try std.mem.concat(self.allocator, []const u8, &.{&.{node_event.node_name}}),
                }) },
            },
            .node_event => |node_event| switch (node_event) {
                .create => @panic("drear size"), // TODO: Implement new node creation.
                .copy => |copy| .{ .blueprint = input.blueprint, .interaction_state = utils.copyWith(input.interaction_state, .{
                    .clipboard = try selectionToNodes(self.allocator, input.blueprint.nodes, if (selection.len > 0) selection else &.{copy.node_name}),
                }) },
                .paste => if (input.interaction_state.clipboard) |clipboard| .{ .interaction_state = input.interaction_state, .blueprint = utils.copyWith(input.blueprint, .{
                    .nodes = try pasteNodesUnique(self.allocator, input.blueprint.nodes, clipboard),
                }) } else default,
                .duplicate => |duplicate| .{
                    .interaction_state = input.interaction_state,
                    .blueprint = utils.copyWith(input.blueprint, .{
                        .nodes = concat: {
                            const to_duplicate = if (selection.len > 0) selection else &.{duplicate.node_name};
                            const new_nodes = try selectionToNodes(self.allocator, input.blueprint.nodes, to_duplicate);
                            break :concat try pasteNodesUnique(self.allocator, input.blueprint.nodes, new_nodes);
                        },
                    }),
                },
                .delete => |delete| .{
                    .interaction_state = input.interaction_state,
                    .blueprint = utils.copyWith(input.blueprint, .{
                        .nodes = filter: {
                            const to_remove = if (selection.len > 0) selection else &.{delete.node_name};
                            var result = std.ArrayList(NodeGraphBlueprintEntry).init(self.allocator);
                            for (input.blueprint.nodes) |node|
                                if (selection: {
                                    for (to_remove) |item|
                                        if (std.mem.eql(u8, item, node.name))
                                            break :selection null;
                                    break :selection node;
                                }) |selected|
                                    try result.append(selected);
                            break :filter result.items;
                            // _ = delete;
                            // break :filter &[_]NodeGraphBlueprintEntry{};
                        },
                    }),
                },
            },
        }
    else
        default;
}

const NodeRenderStatsEvent = union(enum) {
    node_dimensions: []const NodeData(PixelDimensions),
};
const PixelCoord = struct { x: u32, y: u32 };
const PixelDimensions = struct { width: u32, height: u32 };

fn NodeData(T: type) type {
    return struct {
        node: []const u8,
        data: T,
    };
}

pub fn NodeFormatting(
    self: @This(),
    input: struct {
        blueprint: Blueprint,
        node_dimensions: []const NodeData(PixelDimensions),
        post_render_event: ?NodeRenderStatsEvent,
        event: ?GroupingEvent,
    },
) !struct {
    node_coords: []const NodeData(PixelCoord),
    node_dimensions: []const NodeData(PixelDimensions),
} {
    var node_coords = std.ArrayList(NodeData(PixelCoord)).init(self.allocator);
    var node_dimensions = std.ArrayList(NodeData(PixelDimensions)).init(self.allocator);
    try node_dimensions.appendSlice(input.node_dimensions);
    if (input.post_render_event) |post_render_event| {
        switch (post_render_event) {
            // else => {}, Only one case right now TODO more cases? Or just clear the union!
            .node_dimensions => |node_dimensions_event| for (node_dimensions_event) |update|
                if (!replaced_existing: for (node_dimensions.items) |*existing| {
                    if (std.mem.eql(u8, existing.node, update.node)) {
                        existing.data = update.data;
                        break :replaced_existing true;
                    }
                } else false) {
                    try node_dimensions.append(update);
                },
        }
    }
    // TEMP - Grid of nodes until there's actual relationships between nodes to represent
    {
        var x: u32 = 0;
        var y: u32 = 0;
        var pixelMaxHeight: u32 = 0;
        const pixelSpacing = 10;
        const pixelMaxWidth = 500;
        for (node_dimensions.items) |dimension| {
            try node_coords.append(.{ .node = dimension.node, .data = .{
                .x = x,
                .y = y,
            } });
            pixelMaxHeight = @max(pixelMaxHeight, dimension.data.height);
            x += dimension.data.width + pixelSpacing;
            if (x > pixelMaxWidth) {
                x = 0;
                y += pixelMaxHeight + pixelSpacing;
                pixelMaxHeight = 0;
            }
        }
    }

    return .{
        .node_coords = node_coords.items,
        .node_dimensions = node_dimensions.items,
    };
}

const Camera = struct {}; // TODO: implement camera controls

pub fn CameraControls(input: struct {
    keyboard_modifiers: KeyboardModifiers,
    camera: Camera,
    event: ?union(enum) {
        mouse_event: ExternalMouseEvent,
    },
}) struct {
    camera: Camera,
} {
    // TODO - Actually take in the mouse events to move the camera around!
    return .{ .camera = input.camera };
}

const RenderEvent = struct {
    something_changed: bool,
}; // TODO: implement render event

pub fn DomRenderer(input: struct {
    previous_blueprint: Blueprint,
    current_blueprint: Blueprint,
    camera: Camera,
    context_menu: ContextState,
}) struct {
    render_event: ?RenderEvent,
} {
    const something_changed = !std.meta.eql(input.previous_blueprint, input.current_blueprint);
    return if (something_changed)
        .{ .render_event = .{ .something_changed = true } }
    else
        .{ .render_event = null };
}

test "map expression" {
    var allocator = std.heap.page_allocator;
    const start_data = try std.mem.concat(allocator, i32, &.{&.{ 1, 2, 3, 4 }});

    // Whole thing is a giant expression, which is fun, but also a bit of a mess.
    const result_data = if (allocator.alloc(struct { my_number: i32 }, start_data.len)) |result| for (result, 0..) |*item, index| {
        item.* = .{ .my_number = start_data[index] };
    } else result else |err| return err;

    // Use a labeled block, we can label this one as a 'map' which helps with readability.
    const result_data2 = map: {
        const result = try allocator.alloc(struct { my_number: i32 }, start_data.len);
        for (result, 0..) |*item, index| item.* = .{ .my_number = start_data[index] };
        break :map result;
    };

    // Simpler(?), but less efficient (?), use a std.ArrayList to append items to.
    const result_data3 = map: {
        var result = std.ArrayList(struct { my_number: i32 }).init(allocator);
        for (start_data) |item| try result.append(.{ .my_number = item });
        break :map result.items;
    };

    try std.testing.expectEqual(result_data[0].my_number, 1);
    try std.testing.expectEqual(result_data2[2].my_number, 3);
    try std.testing.expectEqual(result_data3.len, 4);
}

test "filter expression" {
    const allocator = std.heap.page_allocator;
    const start_data = try std.mem.concat(allocator, i32, &.{&.{ 1, 2, 3, 4 }});

    // Can't make a giant expression, just use an ArrayList in a nicely labeled block for maximum readability.
    const result_data = filter: {
        var result = std.ArrayList(i32).init(allocator);
        for (start_data) |item| if (@mod(item, 2) == 0) try result.append(item);
        break :filter result.items;
    };

    try std.testing.expectEqual(result_data.len, 2);
}

test "delete node from context menu" {
    const allocator = std.heap.page_allocator;
    const instance = @This(){ .allocator = allocator };
    const first_output = ContextMenuInteraction(.{
        .event = .{ .context_event = .{ .option_selected = "delete" } },
        .context_menu = .{
            .open = false,
            .location = .{ .x = 0, .y = 0 },
            .options = &.{},
            .selected_node = "test",
        },
    });
    const second_output = try instance.NodeInteraction(.{
        .event = utils.eventTransform(utils.NodeInputEventType(NodeInteraction), first_output.event),
        .interaction_state = .{
            .node_selection = &.{"test"},
            .wiggle = null,
            .box_selection = null,
        },
        .blueprint = .{
            .nodes = &.{.{ .name = "test", .function = "test", .input_links = &.{} }},
            .store = &.{},
            .output = &.{},
        },
        .keyboard_modifiers = .{ .shift = false, .control = false, .alt = false, .super = false },
    });
    try std.testing.expectEqual(second_output.blueprint.nodes.len, 0);
}

test "delete node from context menu with a current selection" {
    const allocator = std.heap.page_allocator;
    const instance = @This(){ .allocator = allocator };
    const first_output = ContextMenuInteraction(.{
        .event = .{ .context_event = .{ .option_selected = "delete" } },
        .context_menu = .{
            .open = false,
            .location = .{ .x = 0, .y = 0 },
            .options = &.{},
            .selected_node = "test",
        },
    });
    const second_output = try instance.NodeInteraction(.{
        .event = utils.eventTransform(utils.NodeInputEventType(NodeInteraction), first_output.event),
        .interaction_state = .{
            .node_selection = &.{ "test", "something_else" },
            .wiggle = null,
            .box_selection = null,
        },
        .blueprint = .{
            .nodes = &.{
                .{ .name = "test", .function = "test", .input_links = &.{} },
                .{ .name = "something_else", .function = "test", .input_links = &.{} },
                .{ .name = "another", .function = "test", .input_links = &.{} },
            },
            .store = &.{},
            .output = &.{},
        },
        .keyboard_modifiers = .{ .shift = false, .control = false, .alt = false, .super = false },
    });
    try std.testing.expectEqual(second_output.blueprint.nodes.len, 1);
}

// test "select node" {
//     const allocator = std.heap.page_allocator;
//     const instance = @This(){ .allocator = allocator };
//     const first_output = ContextMenuInteraction(.{
//         .event = .{ .external_node_event = .{ .node_name = "test", .mouse_event = .{ .mouse_down = .{ .location = .{ .x = 0, .y = 0 }, .button = MouseButton.left } } } },
//         .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{}, .selected_node = "test" },
//     });
//     const second_output = try instance.NodeInteraction(.{
//         .event = utils.eventTransform(utils.NodeInputEventType(NodeInteraction), first_output.event),
//         .interaction_state = .{ .node_selection = &.{"something_else"}, .wiggle = null, .box_selection = null },
//         .blueprint = .{ .nodes = &.{
//             .{ .name = "test", .function = "test", .input_links = &.{} },
//             .{ .name = "something_else", .function = "test", .input_links = &.{} },
//         }, .store = &.{}, .output = &.{} },
//         .keyboard_modifiers = .{ .shift = true, .control = false, .alt = false, .super = false },
//     });
//     try std.testing.expectEqual(second_output.interaction_state.node_selection.len, 2);
//     try std.testing.expectEqual(second_output.interaction_state.node_selection[0], "something_else");
// }

// test "deselect node" {
//     const allocator = std.heap.page_allocator;
//     const instance = @This(){ .allocator = allocator };
//     const first_output = ContextMenuInteraction(.{
//         .event = .{ .external_node_event = .{ .node_name = "test", .mouse_event = .{ .mouse_down = .{
//             .location = .{ .x = 0, .y = 0 },
//             .button = MouseButton.left,
//         } } } },
//         .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{}, .selected_node = "test" },
//     });
//     const second_output = try instance.NodeInteraction(.{
//         .event = utils.eventTransform(utils.NodeInputEventType(NodeInteraction), first_output.event),
//         .interaction_state = .{ .node_selection = &.{ "test", "something_else" }, .wiggle = null, .box_selection = null },
//         .blueprint = .{
//             .nodes = &.{.{ .name = "test", .function = "test", .input_links = &.{} }},
//             .store = &.{},
//             .output = &.{},
//         },
//         .keyboard_modifiers = .{ .shift = true, .control = false, .alt = false, .super = false },
//     });
//     try std.testing.expectEqual(second_output.interaction_state.node_selection.len, 1);
//     try std.testing.expectEqual(second_output.interaction_state.node_selection[0], "something_else");
// }

test "duplicate node" {
    const allocator = std.heap.page_allocator;
    const instance = @This(){ .allocator = allocator };
    const first_output = ContextMenuInteraction(.{
        .event = .{ .context_event = .{ .option_selected = "duplicate" } },
        .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{}, .selected_node = "test" },
    });
    const second_output = try instance.NodeInteraction(.{
        .event = utils.eventTransform(utils.NodeInputEventType(NodeInteraction), first_output.event),
        .interaction_state = .{ .node_selection = &.{ "test#1", "test#2" }, .wiggle = null, .box_selection = null },
        .blueprint = .{ .nodes = &.{
            .{ .name = "test#1", .function = "test", .input_links = &.{} },
            .{ .name = "test#2", .function = "test", .input_links = &.{} },
        }, .store = &.{}, .output = &.{} },
        .keyboard_modifiers = .{ .shift = false, .control = false, .alt = false, .super = false },
    });
    try std.testing.expectEqual(second_output.blueprint.nodes.len, 4);
    try std.testing.expectEqualStrings(second_output.blueprint.nodes[2].name, "test");
    try std.testing.expectEqualStrings(second_output.blueprint.nodes[3].name, "test#3");
}
