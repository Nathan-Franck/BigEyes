const std = @import("std");
const zmath = @import("zmath");

pub const Point = zmath.Vec;
pub const Face = []const u32;
pub const Quad = [4]u32;

pub fn calculateNormals(allocator: std.mem.Allocator, points: []const Point, quads: []const Quad) ![]const Point {
    var vertexToQuad = std.AutoHashMap(u32, std.ArrayList(*const [4]u32)).init(allocator);
    for (quads) |*quad| {
        for (quad) |vertex| {
            var quadsList = if (vertexToQuad.get(vertex)) |existing| existing else std.ArrayList(*const [4]u32).init(allocator);
            try quadsList.append(quad);
            try vertexToQuad.put(vertex, quadsList);
        }
    }
    var normals = std.ArrayList(Point).init(allocator);
    for (points, 0..) |_, i| {
        try normals.append(if (vertexToQuad.get(@intCast(i))) |local_quads| normal: {
            var normal = Point{ 0, 0, 0, 0 };
            for (local_quads.items) |quad| {
                const quad_normal = zmath.cross3(points[quad[0]] - points[quad[2]], points[quad[1]] - points[quad[2]]);
                normal += zmath.normalize3(quad_normal) / @as(@Vector(4, f32), @splat(@floatFromInt(local_quads.items.len)));
            }
            break :normal normal;
        } else Point{ 0, 0, 0, 0 });
    }
    return normals.items;
}
