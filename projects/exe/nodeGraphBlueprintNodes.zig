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
    fn process(inputs: struct {
        recieved_blueprint: ?Blueprint,
        existing_blueprint: Blueprint,
    }) struct { blueprint: Blueprint } {
        if (inputs.recieved_blueprint) |update| {
            return update;
        } else {
            return inputs.existing_blueprint;
        }
    }
};

pub const ContextMenuInteraction = struct {
    const Events = union(enum) {
        mouse_event: MouseEvent,
        node_event: NodeEvent,
        context_event: ContextEvent,
    };
    fn process(inputs: struct {
        context_menu: ContextState,
        event: ?Events,
    }) struct {
        context_menu: ContextState,
        unused_event: ?Events,
    } {
        if (inputs.event) |event| switch (event) {
            else => {},
            .mouse_event => |mouse_event| switch (mouse_event) {
                else => {},
                .mouse_down => |evt| {
                    switch (evt.button) {
                        else => {},
                        .left => return .{
                            .unused_event = null,
                            .context_menu = .{
                                .open = false,
                                .location = inputs.context_menu.location,
                                .options = &.{},
                            },
                        },
                        .right => return .{
                            .unused_event = null,
                            .context_menu = .{
                                .open = true,
                                .location = .{ .x = evt.x, .y = evt.y },
                                .options = comptime options: {
                                    var options: []const []const u8 = &.{};
                                    for (@typeInfo(ContextMenuNodeOption).Enum.fields) |field| {
                                        options = options ++ .{field.name};
                                    }
                                    break :options options;
                                },
                            },
                        },
                    }
                },
            },
            .node_event => |node_event| switch (node_event) {
                else => {},
                .mouse_down => |evt| {
                    switch (evt.button) {
                        else => {},
                        .right => return .{
                            .unused_event = null,
                            .context_menu = .{
                                .open = true,
                                .location = .{ .x = evt.x, .y = evt.y },
                                .options = comptime options: {
                                    var options: []const []const u8 = &.{};
                                    for (@typeInfo(ContextMenuOption).Enum.fields) |field| {
                                        options = options ++ .{field.name};
                                    }
                                    break :options options;
                                },
                            },
                        },
                    }
                },
            },
        };

        return .{
            .context_menu = inputs.context_menu,
            .unused_event = inputs.event,
        };
    }
};

const std = @import("std");

test "basic" {
    const result = ContextMenuInteraction.process(.{
        .event = .{ .node_event = .{ .mouse_down = .{ .x = 0, .y = 0, .button = MouseButton.right, .node_name = "test" } } },
        .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 }, .options = &.{} },
    });
    try std.testing.expectEqual(result.context_menu.open, true);
    std.debug.print("\n{s}\n", .{result.context_menu.options});
}
