const std = @import("std");
const subdiv = @import("./subdiv.zig");
const nodes = @import("./nodes.zig");

export fn allocUint8(length: u32) [*]const u8 {
    const slice = std.heap.page_allocator.alloc(u8, length) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

extern fn messageFromWasm(source_pointer: [*]const u8, source_len: usize) void;

extern fn errorFromWasm(source_pointer: [*]const u8, source_len: usize) void;

fn dumpMessage(source: []const u8) void {
    messageFromWasm(source.ptr, source.len);
}

fn dumpError(source: []const u8) void {
    errorFromWasm(source.ptr, source.len);
}

fn callWithJsonErr(name_ptr: [*]const u8, name_len: usize, args_ptr: [*]const u8, args_len: usize) !void {
    const allocator = std.heap.page_allocator;
    const name: []const u8 = name_ptr[0..name_len];
    const args_string: []const u8 = args_ptr[0..args_len];
    const case = std.meta.stringToEnum(nodes.NodesEnum, name) orelse {
        dumpError(try std.fmt.allocPrint(allocator, "unknown function: {s}\n", .{name}));
        return;
    };
    switch (case) {
        inline else => |fn_name| {
            const func = @field(nodes.Nodes, @tagName(fn_name));
            const args = try std.json.parseFromSlice(nodes.Args(func), allocator, args_string, .{});
            const result = try @call(.auto, func, args.value);
            dumpMessage(try std.json.stringifyAlloc(allocator, result, .{}));
        },
    }
}

export fn callWithJson(name_ptr: [*]const u8, name_len: usize, args_ptr: [*]const u8, args_len: usize) void {
    const allocator = std.heap.page_allocator;
    callWithJsonErr(name_ptr, name_len, args_ptr, args_len) catch |err| {
        dumpError(std.fmt.allocPrint(allocator, "error: {?}\n", .{err}) catch unreachable);
        return;
    };
}