const std = @import("std");

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

pub const BlueprintLoader = struct {
    recieved_blueprint: ?Blueprint,
    existing_blueprint: Blueprint,
    fn process(self: @This()) struct { blueprint: Blueprint } {
        if (self.recieved_blueprint) |update| {
            return update;
        } else {
            return self.existing_blueprint;
        }
    }
};

pub fn apply(source_data: anytype) struct {
    source_data: @TypeOf(source_data),
    pub fn withFields(self: @This(), field_changes: anytype) @TypeOf(source_data) {
        switch (@typeInfo(@TypeOf(self.source_data))) {
            .Struct => |structInfo| {
                var result = self.source_data;
                inline for (structInfo.fields) |field| {
                    if (@hasField(@TypeOf(field_changes), field.name))
                        @field(result, field.name) = @field(field_changes, field.name);
                }
                return result;
            },
            else => {
                @compileError("Can't merge non-struct types");
            },
        }
    }
} {
    return .{ .source_data = source_data };
}

/// Takes any type that has fields and returns a list of the field names as strings.
/// NOTE: Required to run at comptime from the callsite.
pub fn FieldNamesToStrings(comptime with_fields: type) []const []const u8 {
    var options: []const []const u8 = &.{};
    for (std.meta.fields(with_fields)) |field| {
        options = options ++ .{field.name};
    }
    return options;
}

pub const ContextMenuInteraction = struct {
    context_menu: ContextState,
    event: union(enum) {
        mouse_event: ExternalMouseEvent,
        external_node_event: ExternalNodeEvent,
        context_event: ExternalContextEvent,
    };
    fn process(self: @This()) struct {
        context_menu: ContextState,
        unused_event: union(enum) {
            mouse_event: ExternalMouseEvent,
            external_node_event: ExternalNodeEvent,
            node_event: NodeEvent,
        }
    } {
        const default = .{
            .context_menu = self.context_menu,
            .unused_event = self.event,
        };
        return if (self.event) |event| switch (event) {
            .context_event => |context_event| switch (context_event) {
                .option_selected => .{
                    .context_menu = apply(self.context_menu).withFields(.{ .open = false }),
                    .node_event = if (std.meta.stringToEnum(ContextMenuOption, context_event.option_selected)) |option| switch (option) {
                        .paste => .{ .paste = self.context_menu.location },
                        .@"new..." => unreachable, // TODO: Implement new node creation.
                    } else if (self.context_menu.selected_node) |selected_node| if (std.meta.stringToEnum(ContextMenuNodeOption, context_event.option_selected)) |option| switch (option) {
                        .delete => .{ .delete = .{ .node_name = selected_node } },
                        .duplicate => .{ .duplicate = .{ .node_name = selected_node } },
                        .copy => .{ .copy = .{ .node_name = selected_node } },
                    } else null else null,
                },
            },
            .node_event => |node_event| switch (node_event.mouse_event) {
                else => default,
                .mouse_down => |mouse_down| switch (mouse_down.button) {
                    else => default,
                    .right => .{ .context_menu = .{
                        .open = true,
                        .selected_node = node_event.node_name,
                        .location = mouse_down.location,
                        .options = comptime FieldNamesToStrings(ContextMenuNodeOption),
                    } },
                },
            },
            .mouse_event => |mouse_event| switch (mouse_event) {
                else => default,
                .mouse_down => |mouse_down| switch (mouse_down.button) {
                    else => default,
                    .left => .{ .context_menu = apply(self.context_menu).withFields(.{ .open = false }) },
                    .right => .{ .context_menu = .{
                        .open = true,
                        .location = mouse_down.location,
                        .options = comptime FieldNamesToStrings(ContextMenuOption),
                    } },
                },
            },
        } else default;
    }
};

pub fn myFn(this: u32) u32 {
    _ = this; // autofix
    unreachable;
}

test "basic" {
    const node: ContextMenuInteraction = .{
        .event = .{ .node_event = .{
            .node_name = "test",
            .mouse_event = .{ .mouse_down = .{ .location = .{ .x = 0, .y = 0 }, .button = MouseButton.right } },
        } },
        .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{} },
    };
    const output = node.process();
    try std.testing.expectEqual(output.context_menu.open, true);
    std.debug.print("\n{s}\n", .{output.context_menu.options});
    std.debug.print("\n{any}\n", .{@TypeOf(myFn)});
}
