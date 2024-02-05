const std = @import("std");
const NodeGraphBlueprintEntry = @import("./interactiveNodeBuilderBlueprint.zig").NodeGraphBlueprintEntry;

pub const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;

pub const MouseButton = enum {
    left,
    middle,
    right,
};

pub const GraphLocation = struct {
    x: f32,
    y: f32,
};

pub const ExternalMouseEvent = union(enum) {
    mouse_down: struct { location: GraphLocation, button: MouseButton },
    mouse_up: struct { location: GraphLocation, button: MouseButton },
    mouse_move: GraphLocation,
    mouse_wheel: struct { x: f32, y: f32, z: f32 },
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
    create: struct { graphLocation: GraphLocation, node_name: []const u8, node_type: []const u8 },
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

pub fn copyWith(source_data: anytype, field_changes: anytype) @TypeOf(source_data) {
    switch (@typeInfo(@TypeOf(source_data))) {
        else => @compileError("Can't merge non-struct types"),
        .Struct => |struct_info| {
            var result = source_data;
            inline for (struct_info.fields) |field| {
                if (@hasField(@TypeOf(field_changes), field.name))
                    @field(result, field.name) = @field(field_changes, field.name);
            }
            return result;
        },
    }
}

pub fn NodeOutputEventType(node_process_function: anytype) type {
    const node_process_function_info = @typeInfo(@TypeOf(node_process_function));
    if (node_process_function_info != .Fn) {
        @compileError("node_process_function must be a function, found '" ++ @typeName(node_process_function) ++ "'");
    }
    var return_type = node_process_function_info.Fn.return_type.?;
    if (@typeInfo(return_type) == .ErrorUnion) {
        return_type = @typeInfo(return_type).ErrorUnion.payload;
    }
    const event_field_info = std.meta.fieldInfo(return_type, .event);
    return event_field_info.type;
}

pub fn NodeInputEventType(node_process_function: anytype) type {
    const node_process_function_info = @typeInfo(@TypeOf(node_process_function));
    if (node_process_function_info != .Fn) {
        @compileError("node_process_function must be a function, found '" ++ @typeName(node_process_function) ++ "'");
    }
    const params = node_process_function_info.Fn.params;
    const event_field_info = std.meta.fieldInfo(params[params.len - 1].type.?, .event);
    return event_field_info.type;
}

pub fn eventTransform(target_event_type: type, source_event: anytype) target_event_type {
    const source_info = @typeInfo(@TypeOf(source_event));
    if (source_info != .Optional) {
        @compileError("source_event must be an optional union type (?union(enum){}), found '" ++ @typeName(source_event) ++ "'");
    }
    const source_optional_info = @typeInfo(source_info.Optional.child);
    if (source_optional_info != .Union) {
        @compileError("source_event must be an optional union type (?union(enum){}), found '" ++ @typeName(source_event) ++ "'");
    }
    const target_info = @typeInfo(target_event_type);
    if (target_info != .Optional) {
        @compileError("target_event_type must be an optional union type (?union(enum){}), found '" ++ @typeName(target_event_type) ++ "'");
    }
    const target_optional_info = @typeInfo(target_info.Optional.child);
    if (target_optional_info != .Union) {
        @compileError("target_event_type must be an optional union type (?union(enum){}), found '" ++ @typeName(target_event_type) ++ "'");
    }
    if (source_event) |source_not_null| {
        const field_index = @intFromEnum(source_not_null);
        inline for (source_optional_info.Union.fields, 0..) |source_field, i| {
            if (i == field_index) {
                const source = @field(source_not_null, source_field.name);
                inline for (target_optional_info.Union.fields, 0..) |target_field, j| {
                    _ = j; // autofix
                    const equal_names = comptime std.mem.eql(u8, source_field.name, target_field.name);
                    const equal_types = source_field.type == target_field.type;
                    if (equal_names and equal_types) {
                        return @unionInit(target_info.Optional.child, target_field.name, source);
                    } else if (equal_names and !equal_types) {
                        @compileError(std.fmt.comptimePrint("source and target field types do not match: {any} {any}", .{ target_field.type, source_field.type }));
                    } else if (equal_types and !equal_names) {
                        @compileError("source and target field names do not match: " ++ target_field.name ++ " " ++ source_field.name);
                    }
                }
            }
        }
    }
    return null;
}

/// Takes any type that has fields and returns a list of the field names as strings.
/// NOTE: Required to run at comptime from the callsite.
pub fn fieldNamesToStrings(comptime with_fields: type) []const []const u8 {
    var options: []const []const u8 = &.{};
    for (std.meta.fields(with_fields)) |field| {
        options = options ++ .{field.name};
    }
    return options;
}

fn BlueprintLoader(input: struct {
    recieved_blueprint: ?Blueprint,
    existing_blueprint: Blueprint,
}) struct { blueprint: Blueprint } {
    if (input.recieved_blueprint) |update| {
        return update;
    } else {
        return input.existing_blueprint;
    }
}

fn ContextMenuInteraction(input: struct {
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
    } = null,
} {
    const default = .{
        .context_menu = input.context_menu,
        .event = eventTransform(NodeOutputEventType(ContextMenuInteraction), input.event),
    };
    return if (input.event) |event| switch (event) {
        .external_node_event => |node_event| switch (node_event.mouse_event) {
            else => default,
            .mouse_down => |mouse_down| switch (mouse_down.button) {
                else => default,
                .right => .{ .context_menu = .{
                    .open = true,
                    .selected_node = node_event.node_name,
                    .location = mouse_down.location,
                    .options = comptime fieldNamesToStrings(ContextMenuNodeOption),
                } },
            },
        },
        .mouse_event => |mouse_event| switch (mouse_event) {
            else => default,
            .mouse_down => |mouse_down| switch (mouse_down.button) {
                else => default,
                .left => .{ .context_menu = copyWith(input.context_menu, .{ .open = false }) },
                .right => .{ .context_menu = .{
                    .open = true,
                    .location = mouse_down.location,
                    .options = comptime fieldNamesToStrings(ContextMenuOption),
                } },
            },
        },
        .context_event => |context_event| switch (context_event) {
            .option_selected => result: {
                const menu_option_selected = std.meta.stringToEnum(ContextMenuOption, context_event.option_selected);
                const menu_node_option_selected = std.meta.stringToEnum(ContextMenuNodeOption, context_event.option_selected);
                break :result .{
                    .context_menu = copyWith(input.context_menu, .{ .open = false }),
                    .event = if (menu_option_selected) |option| switch (option) {
                        .paste => .{ .node_event = .{ .paste = input.context_menu.location } },
                        .@"new..." => unreachable, // TODO: Implement new node creation.
                    } else if (menu_node_option_selected) |option| if (input.context_menu.selected_node) |selected_node| switch (option) {
                        .delete => .{ .node_event = .{ .delete = .{ .node_name = selected_node } } },
                        .duplicate => .{ .node_event = .{ .duplicate = .{ .node_name = selected_node } } },
                        .copy => .{ .node_event = .{ .copy = .{ .node_name = selected_node } } },
                    } else unreachable else unreachable, // TODO: Do I want this to crash or fail gracefully? Maybe float some error event up that an error message system can present the user?
                };
            },
        },
    } else default;
}

pub const KeyboardModifiers = struct {
    shift: bool,
    control: bool,
    alt: bool,
    super: bool,
};

pub const InteractionState = struct {
    node_selection: []const []const u8,
    box_selection: ?struct {
        start: GraphLocation,
        end: GraphLocation,
    },
    wiggle: ?struct {
        node: []const u8,
        location: GraphLocation,
    },
};

fn NodeInteraction(
    allocator: std.mem.Allocator,
    input: struct {
        keyboard_modifiers: KeyboardModifiers,
        interaction_state: InteractionState,
        blueprint: Blueprint,
        event: ?union(enum) {
            mouse_event: ExternalMouseEvent,
            external_node_event: ExternalNodeEvent,
            node_event: NodeEvent,
        },
    },
) !struct {
    interaction_state: InteractionState,
    blueprint: Blueprint,
    event: ?union(enum) {
        mouse_event: ExternalMouseEvent,
        external_node_event: ExternalNodeEvent,
    } = null,
} {
    const default = .{
        .interaction_state = input.interaction_state,
        .blueprint = input.blueprint,
        .event = eventTransform(NodeOutputEventType(NodeInteraction), input.event),
    };
    if (input.keyboard_modifiers.shift) {
        return if (input.event) |event| switch (event) {
            else => default,
            .external_node_event => |node_event| switch (node_event.mouse_event) {
                else => default,
                .mouse_down => .{
                    .blueprint = input.blueprint,
                    .interaction_state = copyWith(input.interaction_state, .{
                        .node_selection = if (for (input.interaction_state.node_selection, 0..) |item, index| (if (std.meta.eql(
                            item,
                            node_event.node_name,
                        )) break index) else null) |index| try std.mem.concat(allocator, []const u8, &.{
                            input.interaction_state.node_selection[0..index],
                            input.interaction_state.node_selection[index + 1 ..],
                        }) else try std.mem.concat(allocator, []const u8, &.{
                            input.interaction_state.node_selection,
                            &.{node_event.node_name},
                        }),
                    }),
                },
            },
        } else default;
    } else {
        return if (input.event) |event| switch (event) {
            else => default,
            .external_node_event => |node_event| switch (node_event.mouse_event) {
                else => default,
                .mouse_down => .{
                    .blueprint = input.blueprint,
                    .interaction_state = copyWith(input.interaction_state, .{
                        .node_selection = try std.mem.concat(allocator, []const u8, &.{&.{node_event.node_name}}),
                    }),
                },
            },
            .node_event => |node_event| switch (node_event) {
                else => default,
                .delete => .{
                    .interaction_state = input.interaction_state,
                    .blueprint = copyWith(input.blueprint, .{
                        .nodes = for (input.blueprint.nodes, 0..) |node, index| (if (std.meta.eql(
                            if (node.name) |name| name else node.function,
                            node_event.delete.node_name,
                        )) break try std.mem.concat(allocator, NodeGraphBlueprintEntry, &.{
                            input.blueprint.nodes[0..index],
                            input.blueprint.nodes[index + 1 ..],
                        })) else input.blueprint.nodes,
                    }),
                },
            },
        } else default;
    }
}

test "delete node from context menu" {
    const allocator = std.heap.page_allocator;
    const first_output = ContextMenuInteraction(.{
        .event = .{ .context_event = .{ .option_selected = "delete" } },
        .context_menu = .{
            .open = false,
            .location = .{ .x = 0, .y = 0 },
            .options = &.{},
            .selected_node = "test",
        },
    });
    const second_output = try NodeInteraction(allocator, .{
        .event = eventTransform(NodeInputEventType(NodeInteraction), first_output.event),
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

test "select node" {
    const allocator = std.heap.page_allocator;
    const first_output = ContextMenuInteraction(.{
        .event = .{ .external_node_event = .{ .node_name = "test", .mouse_event = .{ .mouse_down = .{ .location = .{ .x = 0, .y = 0 }, .button = MouseButton.left } } } },
        .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{}, .selected_node = "test" },
    });
    const second_output = try NodeInteraction(allocator, .{
        .event = eventTransform(NodeInputEventType(NodeInteraction), first_output.event),
        .interaction_state = .{ .node_selection = &.{"something_else"}, .wiggle = null, .box_selection = null },
        .blueprint = .{ .nodes = &.{
            .{ .name = "test", .function = "test", .input_links = &.{} },
            .{ .name = "something_else", .function = "test", .input_links = &.{} },
        }, .store = &.{}, .output = &.{} },
        .keyboard_modifiers = .{ .shift = true, .control = false, .alt = false, .super = false },
    });
    try std.testing.expectEqual(second_output.interaction_state.node_selection.len, 2);
    try std.testing.expectEqual(second_output.interaction_state.node_selection[0], "something_else");
}

test "deselect node" {
    const allocator = std.heap.page_allocator;
    const first_output = ContextMenuInteraction(.{
        .event = .{ .external_node_event = .{ .node_name = "test", .mouse_event = .{ .mouse_down = .{ .location = .{ .x = 0, .y = 0 }, .button = MouseButton.left } } } },
        .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{}, .selected_node = "test" },
    });
    const second_output = try NodeInteraction(allocator, .{
        .event = eventTransform(NodeInputEventType(NodeInteraction), first_output.event),
        .interaction_state = .{ .node_selection = &.{ "test", "something_else" }, .wiggle = null, .box_selection = null },
        .blueprint = .{ .nodes = &.{.{ .name = "test", .function = "test", .input_links = &.{} }}, .store = &.{}, .output = &.{} },
        .keyboard_modifiers = .{ .shift = true, .control = false, .alt = false, .super = false },
    });
    try std.testing.expectEqual(second_output.interaction_state.node_selection.len, 1);
    try std.testing.expectEqual(second_output.interaction_state.node_selection[0], "something_else");
}
