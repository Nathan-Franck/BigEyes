const std = @import("std");

pub const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;

pub const MouseButton = enum {
    left,
    middle,
    right,
};

pub const ExternalMouseEvent = union(enum) {
    mouse_down: struct { x: f32, y: f32, button: MouseButton },
    mouse_up: struct { x: f32, y: f32, button: MouseButton },
    mouse_move: struct { x: f32, y: f32 },
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
    create: struct { x: f32, y: f32, node_name: []const u8, node_type: []const u8 },
    delete: struct { node_name: []const u8 },
    duplicate: struct { node_name: []const u8 },
    copy: struct { node_name: []const u8 },
    paste: struct { x: f32, y: f32 },
    // group: struct { node_names: []const []const u8, formatting: GroupFormatting },
};

pub const ExternalContextEvent = union(enum) {
    option_selected: []const u8,
};

pub const ContextState = struct {
    open: bool,
    location: struct { x: f32, y: f32 },
    options: []const []const u8,
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
    const Events = union(enum) {
        mouse_event: ExternalMouseEvent,
        node_event: ExternalNodeEvent,
        context_event: ExternalContextEvent,
    };
    context_menu: ContextState,
    event: ?Events,
    fn process(self: @This()) struct {
        context_menu: ContextState,
        unused_event: ?Events,
        node_event: ?NodeEvent,
    } {
        const default = .{
            .context_menu = self.context_menu,
            .unused_event = self.event,
            .node_event = null,
        };
        return if (self.event) |event| switch (event) {
            .context_event => |context_event| switch (context_event) {
                .option_selected => .{
                    .unused_event = null,
                    .context_menu = apply(self.context_menu).withFields(.{ .open = false }),
                    .node_event = null,
                },
            },
            .node_event => |node_event| switch (node_event.mouse_event) {
                else => default,
                .mouse_down => |mouse_down| switch (mouse_down.button) {
                    else => default,
                    .right => .{ .unused_event = null, .node_event = null, .context_menu = .{
                        .open = true,
                        .location = .{ .x = mouse_down.x, .y = mouse_down.y },
                        .options = comptime FieldNamesToStrings(ContextMenuNodeOption),
                    } },
                },
            },
            .mouse_event => |mouse_event| switch (mouse_event) {
                else => default,
                .mouse_down => |mouse_down| switch (mouse_down.button) {
                    else => default,
                    .left => .{
                        .node_event = null,
                        .unused_event = null,
                        .context_menu = apply(self.context_menu).withFields(.{ .open = false }),
                    },
                    .right => .{ .unused_event = null, .node_event = null, .context_menu = .{
                        .open = true,
                        .location = .{ .x = mouse_down.x, .y = mouse_down.y },
                        .options = comptime FieldNamesToStrings(ContextMenuOption),
                    } },
                },
            },
        } else default;
    }
};

test "basic" {
    const node: ContextMenuInteraction = .{
        .event = .{ .node_event = .{ .node_name = "test", .mouse_event = .{ .mouse_down = .{ .x = 0, .y = 0, .button = MouseButton.right } } } },
        .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{} },
    };
    const output = node.process();
    try std.testing.expectEqual(output.context_menu.open, true);
    std.debug.print("\n{s}\n", .{output.context_menu.options});
}
