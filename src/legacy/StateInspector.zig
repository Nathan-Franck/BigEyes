const std = @import("std");
const zgui = @import("zgui");
const meta = @import("./MetaMaster.zig");

const Self = @This();

allocator: std.mem.Allocator,
var filter_buffer: []u8 = undefined;

pub fn init(allocator: std.mem.Allocator) !Self {
    filter_buffer = try allocator.alloc(u8, 256);
    for (filter_buffer) |*c| {
        c.* = 0;
    }
    return .{ .allocator = allocator };
}

pub fn inspect(self: *Self, s: anytype) !void {
    _ = zgui.begin("State Inspector", .{});
    defer zgui.end();

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    _ = zgui.inputText("Filter", .{
        .buf = filter_buffer,
        .flags = .{ .callback_edit = true, .auto_select_all = true, .always_overwrite = true },
        .callback = struct {
            fn callback(data: *zgui.InputTextCallbackData) i32 {
                for (filter_buffer) |*c| {
                    c.* = 0;
                }
                std.mem.copyForwards(u8, filter_buffer, data.buf[0..@intCast(data.buf_text_len)]);
                return 0;
            }
        }.callback,
    });

    const visibilityStructure = buildFilterVisibilityStructure(.{ .type = @TypeOf(s.*), .name = "State" }, std.mem.trimRight(u8, filter_buffer, &.{0}));

    if (visibilityStructure) |vs| {
        inline for (@typeInfo(@typeInfo(@TypeOf(s)).Pointer.child).Struct.fields) |field| {
            const v = &@field(s, field.name);
            const field_visibility = @field(vs, field.name);
            try inspectField(field, v, field_visibility, arena.allocator());
        }
    }
}

fn VisibilityStructure(comptime State: type) type {
    return switch (@typeInfo(State)) {
        .Struct => |structInfo| @Type(.{ .Optional = .{ .child = @Type(.{ .Struct = meta.merge(structInfo, .{
            .fields = fields: {
                var result: []const std.builtin.Type.StructField = &.{};
                inline for (structInfo.fields) |field| {
                    result = result ++ .{meta.merge(field, .{
                        .type = VisibilityStructure(field.type),
                    })};
                }
                break :fields result;
            },
        }) }) } }),
        .Array => bool,
        else => bool,
    };
}

fn buildFilterVisibilityStructure(info: anytype, search: []const u8) VisibilityStructure(info.type) {
    const text_match = std.mem.startsWith(u8, info.name, search) or search.len == 0;
    switch (@typeInfo(info.type)) {
        .Struct => |structInfo| {
            var any_field_visible = false;
            var result: @typeInfo(VisibilityStructure(info.type)).Optional.child = undefined;
            inline for (structInfo.fields) |field| {
                const field_visibility = buildFilterVisibilityStructure(field, search);
                if (!any_field_visible) any_field_visible = switch (@typeInfo(@TypeOf(field_visibility))) {
                    .Optional => field_visibility != null,
                    .Bool => field_visibility,
                    else => false,
                };
                @field(result, field.name) = field_visibility;
            }
            return if (any_field_visible or text_match) result else null;
        },
        else => {
            return text_match;
        },
    }
}

fn inspectField(info: anytype, value: anytype, visibilityStructure: anytype, allocator: std.mem.Allocator) !void {
    switch (@typeInfo(info.type)) {
        .Struct => |structInfo| {
            if (visibilityStructure) |vs| {
                var orig_list = std.ArrayList(u8).init(allocator);
                try orig_list.appendSlice(info.name);
                const sentinel_slice = try orig_list.toOwnedSliceSentinel(0);
                if (zgui.collapsingHeader(sentinel_slice, .{})) {
                    zgui.indent(.{});
                    defer zgui.unindent(.{});
                    inline for (structInfo.fields) |field| {
                        const v = &@field(value, field.name);
                        const field_visibility = @field(vs, field.name);
                        try inspectField(field, v, field_visibility, allocator);
                    }
                }
            }
        },
        .Array => |arrayInfo| {
            if (visibilityStructure) {
                var orig_list = std.ArrayList(u8).init(allocator);
                try orig_list.appendSlice(info.name);
                const sentinel_slice = try orig_list.toOwnedSliceSentinel(0);
                if (zgui.collapsingHeader(sentinel_slice, .{})) {
                    zgui.indent(.{});
                    defer zgui.unindent(.{});
                    for (value, 0..) |_, i| {
                        try inspectField(.{ .name = "item", .type = arrayInfo.child }, &value[i], true, allocator);
                    }
                }
            }
        },
        .Float => {
            if (visibilityStructure) {
                zgui.text("{s} ({any}) = {any}", .{ info.name, info.type, value });
                const text = try std.fmt.allocPrint(allocator, "{s}##{?}" ++ .{0}, .{ info.name, value });
                _ = zgui.inputFloat(text[0 .. text.len - 1 :0], .{ .v = value, .step = 0.1 });
            }
        },
        .Bool => {
            if (visibilityStructure) {
                _ = zgui.checkbox(info.name ++ " (bool)", .{ .v = value });
            }
        },
        else => {
            if (visibilityStructure) {
                zgui.text("{s} ({any}) = {any}", .{ info.name, info.type, value.* });
            }
        },
    }
}
