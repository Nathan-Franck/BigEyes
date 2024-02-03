pub const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;

pub const MouseButton = enum {
    left,
    middle,
    right,
};

pub const MouseEvent = union(enum) {
    mouse_down: struct { x: f32, y: f32, button: MouseButton },
    mouse_up: struct { x: f32, y: f32, button: MouseButton },
    mouse_move: struct { x: f32, y: f32 },
    mouse_wheel: struct { x: f32, y: f32, z: f32 },
};

pub const NodeEvent = union(enum) {
    mouse_down: struct { x: f32, y: f32, button: MouseButton, node_name: []const u8 },
    mouse_up: struct { x: f32, y: f32, button: MouseButton, node_name: []const u8 },
    mouse_move: struct { x: f32, y: f32, node_name: []const u8 },
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

pub const ContextEvent = union(enum) {
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

pub fn EnumToStrings(comptime enum_t: type) []const []const u8 {
    var options: []const []const u8 = &.{};
    for (@typeInfo(enum_t).Enum.fields) |field| {
        options = options ++ .{field.name};
    }
    return options;
}

pub const ContextMenuInteraction = struct {
    const Events = union(enum) {
        mouse_event: MouseEvent,
        node_event: NodeEvent,
        context_event: ContextEvent,
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
        return if (self.event) |event| switch (event) {
            else => default,
            .node_event => |node_event| switch (node_event) {
                else => default,
                .mouse_down => |mouse_down| switch (mouse_down.button) {
                    else => default,
                    .right => .{ .unused_event = null, .context_menu = .{
                        .open = true,
                        .location = .{ .x = mouse_down.x, .y = mouse_down.y },
                        .options = comptime EnumToStrings(ContextMenuNodeOption),
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
                        .options = comptime EnumToStrings(ContextMenuOption),
                    } },
                },
            },
        } else default;
    }
};

const std = @import("std");

test "basic" {
    const result = ContextMenuInteraction{
        .event = .{ .node_event = .{ .mouse_down = .{ .x = 0, .y = 0, .button = MouseButton.right, .node_name = "test" } } },
        .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{} },
    }.process();
    try std.testing.expectEqual(result.context_menu.open, true);
    std.debug.print("\n{s}\n", .{result.context_menu.options});
}
