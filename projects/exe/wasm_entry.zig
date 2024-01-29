const std = @import("std");
const subdiv = @import("subdiv");

extern fn messageFromWasm(source_pointer: [*]const u8, source_len: u32) void;

export fn testSubdiv(inp: u32) void {
    _ = inp;
    const allocator = std.heap.page_allocator;
    var points = [_]subdiv.Point{
        subdiv.Point{ -1.1, 1.0, 1.0, 1.0 },
        subdiv.Point{ -1.0, -1.0, 1.0, 1.0 },
        subdiv.Point{ 1.0, -1.0, 1.0, 1.0 },
        subdiv.Point{ 1.0, 1.0, 1.0, 1.0 },
        subdiv.Point{ -1.0, 1.0, -1.0, 1.0 },
        subdiv.Point{ -1.0, -1.0, -1.0, 1.0 },
    };

    var faces = [_]subdiv.Face{
        &[_]u32{ 0, 1, 2, 3 },
        &[_]u32{ 0, 1, 5, 4 },
    };
    const result = subdiv.Polygon(.Face).cmcSubdiv(
        allocator,
        &points,
        &faces,
    ) catch @panic("subdiv.Subdiv.cmcSubdiv");
    const stringified_result = std.json.stringifyAlloc(allocator, result, .{}) catch @panic("std.json.stringifyAlloc");
    messageFromWasm(stringified_result.ptr, stringified_result.len);
}
