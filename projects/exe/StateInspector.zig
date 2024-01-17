const std = @import("std");
const zgui = @import("zgui");

pub fn inspect(s: anytype, allocator: std.mem.Allocator) !void {
    _ = zgui.begin("State Inspector", .{});
    defer zgui.end();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // TODO: Filter box at the top (parameter name or contents)
    try inspectStruct(s, arena.allocator());
}

fn inspectStruct(s: anytype, allocator: std.mem.Allocator) !void {
    inline for (@typeInfo(@TypeOf(s)).Struct.fields) |field| {
        const value = @field(s, field.name);
        try inspectField(field, value, allocator);
    }
}

fn inspectArray(array: anytype, allocator: std.mem.Allocator) !void {
    for (array) |value| {
        try inspectField(.{ .name = "item", .type = @TypeOf(value) }, value, allocator);
    }
}

fn inspectField(field: anytype, value: anytype, allocator: std.mem.Allocator) !void {
    switch (@typeInfo(field.type)) {
        .Struct => {
            var orig_list = std.ArrayList(u8).init(allocator);
            try orig_list.appendSlice(field.name);
            const sentinel_slice = try orig_list.toOwnedSliceSentinel(0);
            if (zgui.collapsingHeader(sentinel_slice, .{})) {
                zgui.indent(.{});
                defer zgui.unindent(.{});
                try inspectStruct(value, allocator);
            }
        },
        .Array => {
            var orig_list = std.ArrayList(u8).init(allocator);
            try orig_list.appendSlice(field.name);
            const sentinel_slice = try orig_list.toOwnedSliceSentinel(0);
            if (zgui.collapsingHeader(sentinel_slice, .{})) {
                zgui.indent(.{});
                defer zgui.unindent(.{});
                try inspectArray(value, allocator);
            }
        },
        else => {
            zgui.text("{s} ({any}) = {any}", .{ field.name, field.type, value });
        },
    }
}
