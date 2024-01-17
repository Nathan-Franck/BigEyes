const std = @import("std");
const zgui = @import("zgui");

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

    const visibilityStructure = buildFilterVisibilityStructure(.{ .type = @TypeOf(s), .name = "State" }, std.mem.trimRight(u8, filter_buffer, &.{0}));

    if (visibilityStructure) |vs| {
        inline for (@typeInfo(@TypeOf(s)).Struct.fields) |field| {
            const v = @field(s, field.name);
            const field_visibility = @field(vs, field.name);
            try inspectField(field, v, field_visibility, arena.allocator());
        }
    }
}

fn setFields(source: anytype, changes: anytype) @TypeOf(source) {
    switch (@typeInfo(@TypeOf(source))) {
        .Struct => |structInfo| {
            var result: @TypeOf(source) = undefined;
            inline for (structInfo.fields) |field| {
                @field(result, field.name) = if (@hasField(@TypeOf(changes), field.name))
                    @field(changes, field.name)
                else
                    @field(source, field.name);
            }
            return result;
        },
        else => {
            @compileError("Can't merge non-struct types");
        },
    }
}

fn VisibilityStructure(comptime State: type) type {
    switch (@typeInfo(State)) {
        .Struct => |structInfo| {
            var result_fields: []const std.builtin.Type.StructField = &.{};
            inline for (structInfo.fields) |field| {
                result_fields = result_fields ++ .{setFields(field, .{
                    .type = VisibilityStructure(field.type),
                })};
            }
            return @Type(.{ .Optional = .{ .child = @Type(.{ .Struct = setFields(structInfo, .{
                .fields = result_fields,
            }) }) } });
        },
        .Array => {
            return bool;
        },
        else => {
            return bool;
        },
    }
}

fn buildFilterVisibilityStructure(info: anytype, search: []const u8) VisibilityStructure(info.type) {
    const text_match = std.mem.startsWith(u8, info.name, search) or search.len == 0;
    switch (@typeInfo(info.type)) {
        .Struct => |structInfo| {
            var visible = false;
            var result: @typeInfo(VisibilityStructure(info.type)).Optional.child = undefined;
            inline for (structInfo.fields) |field| {
                const field_visibility = buildFilterVisibilityStructure(field, search);
                switch (@typeInfo(@TypeOf(field_visibility))) {
                    .Optional => {
                        if (field_visibility) |_| {
                            visible = true;
                        }
                    },
                    .Bool => {
                        if (field_visibility) {
                            visible = true;
                        }
                    },
                    else => {},
                }
                @field(result, field.name) = field_visibility;
            }
            if (visible or text_match) {
                return result;
            } else {
                return null;
            }
        },
        else => {
            return text_match;
        },
    }
}

fn inspectField(info: anytype, value: anytype, visibilityStructure: anytype, allocator: std.mem.Allocator) !void {
    switch (@typeInfo(info.type)) {
        .Struct => |structInfo| {
            var orig_list = std.ArrayList(u8).init(allocator);
            try orig_list.appendSlice(info.name);
            const sentinel_slice = try orig_list.toOwnedSliceSentinel(0);
            if (visibilityStructure) |vs| {
                if (zgui.collapsingHeader(sentinel_slice, .{})) {
                    zgui.indent(.{});
                    defer zgui.unindent(.{});
                    inline for (structInfo.fields) |field| {
                        const v = @field(value, field.name);
                        const field_visibility = @field(vs, field.name);
                        try inspectField(field, v, field_visibility, allocator);
                    }
                }
            }
        },
        .Array => |arrayInfo| {
            var orig_list = std.ArrayList(u8).init(allocator);
            try orig_list.appendSlice(info.name);
            const sentinel_slice = try orig_list.toOwnedSliceSentinel(0);
            if (visibilityStructure) {
                if (zgui.collapsingHeader(sentinel_slice, .{})) {
                    zgui.indent(.{});
                    defer zgui.unindent(.{});
                    for (value) |element| {
                        try inspectField(.{ .name = "item", .type = arrayInfo.child }, element, true, allocator);
                    }
                }
            }
        },
        else => {
            if (visibilityStructure) {
                zgui.text("{s} ({any}) = {any}", .{ info.name, info.type, value });
            }
        },
    }
}
