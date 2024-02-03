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

/// Required to run at comptime from the callsite.
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
    } {
        const default = .{
            .context_menu = self.context_menu,
            .unused_event = self.event,
        };
        return if (inputs.event) |event| switch (event) {
            .context_event => |context_event| switch (context_event) {
                .option_selected => .{ .unused_event = null, .context_menu = .{
                    .open = false,
                    .location = inputs.context_menu.location,
                    .options = inputs.context_menu.options,
                } },
            },
            .node_event => |node_event| switch (node_event.mouse_event) {
                else => default,
                .mouse_down => |mouse_down| switch (mouse_down.button) {
                    else => default,
                    .right => .{ .unused_event = null, .context_menu = .{
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
                    .left => .{ .unused_event = null, .context_menu = .{
                        .open = false,
                        .location = self.context_menu.location,
                        .options = &.{},
                    } },
                    .right => .{ .unused_event = null, .context_menu = .{
                        .open = true,
                        .location = .{ .x = mouse_down.x, .y = mouse_down.y },
                        .options = comptime FieldNamesToStrings(ContextMenuOption),
                    } },
                },
            },
        } else default;
    }
};

const std = @import("std");

test "basic" {

        .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{} },
    }.process();
    try std.testing.expectEqual(result.context_menu.open, true);
    std.debug.print("\n{s}\n", .{result.context_menu.options});
}
