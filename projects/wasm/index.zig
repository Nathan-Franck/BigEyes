const std = @import("std");
const subdiv = @import("subdiv");

export fn testSubdiv() void {
    var allocator = std.heap.page_allocator;
    var points = [_]subdiv.Point{
        subdiv.Point{ -1.0, 1.0, 1.0, 1.0 },
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
    var result = subdiv.Subdiv(true).cmcSubdiv(
        allocator,
        &points,
        &faces,
    ) catch @panic("subdiv.Subdiv.cmcSubdiv");
    _ = result;
    // return inp * 2;
}
