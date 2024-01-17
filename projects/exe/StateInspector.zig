const std = @import("std");
const zgui = @import("zgui");

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn inspect(self: *Self, s: anytype) !void {
    _ = zgui.begin("State Inspector", .{});
    defer zgui.end();

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    const buf = try arena.allocator().alloc(u8, 256);
    for (buf) |*c| {
        c.* = 0;
    }

    _ = zgui.inputText("Filter", .{
        .buf = buf,
        .flags = .{ .callback_edit = true },
        .callback = struct {
            fn callback(data: *zgui.InputTextCallbackData) i32 {
                std.debug.print("callback {s}\n", .{data.buf[0..@intCast(data.buf_text_len)]});
                return 0;
            }
        }.callback,
    });

    inline for (@typeInfo(@TypeOf(s)).Struct.fields) |field| {
        const v = @field(s, field.name);
        try inspectField(field, v, arena.allocator());
    }
}

fn inspectField(info: anytype, value: anytype, allocator: std.mem.Allocator) !void {
    switch (@typeInfo(@TypeOf(value))) {
        .Struct => |structInfo| {
            var orig_list = std.ArrayList(u8).init(allocator);
            try orig_list.appendSlice(info.name);
            const sentinel_slice = try orig_list.toOwnedSliceSentinel(0);
            if (zgui.collapsingHeader(sentinel_slice, .{})) {
                zgui.indent(.{});
                defer zgui.unindent(.{});
                inline for (structInfo.fields) |field| {
                    const v = @field(value, field.name);
                    try inspectField(field, v, allocator);
                }
            }
        },
        .Array => {
            var orig_list = std.ArrayList(u8).init(allocator);
            try orig_list.appendSlice(info.name);
            const sentinel_slice = try orig_list.toOwnedSliceSentinel(0);
            if (zgui.collapsingHeader(sentinel_slice, .{})) {
                zgui.indent(.{});
                defer zgui.unindent(.{});
                for (value) |element| {
                    try inspectField(.{ .name = "item", .type = @TypeOf(element) }, element, allocator);
                }
            }
        },
        else => {
            zgui.text("{s} ({any}) = {any}", .{ info.name, info.type, value });
        },
    }
}
