const std = @import("std");
const zmath = @import("zmath");

pub const Point = zmath.Vec;
pub const Face = []const u32;
pub const Quad = [4]u32;
const PolyType = enum {
    Quad,
    Face,
};

pub fn calculateNormals(
    comptime poly_type: PolyType,
    allocator: std.mem.Allocator,
    points: []const Point,
    polygons: []const switch (poly_type) {
        .Quad => Quad,
        .Face => Face,
    },
) []const Point {
    const Poly = @typeInfo(@TypeOf(polygons)).Pointer.child;
    var vertexToPoly = std.AutoHashMap(u32, std.ArrayList(Poly)).init(allocator);
    for (polygons) |polygon| {
        for (polygon) |vertex| {
            var polysList = if (vertexToPoly.get(vertex)) |existing| existing else std.ArrayList(Poly).init(allocator);
            polysList.append(polygon) catch unreachable;
            vertexToPoly.put(vertex, polysList) catch unreachable;
        }
    }
    var normals = std.ArrayList(Point).init(allocator);
    for (points, 0..) |_, i| {
        normals.append(if (vertexToPoly.get(@intCast(i))) |local_polys| average_normal: {
            var average_normal = Point{ 0, 0, 0, 0 };
            for (local_polys.items) |poly| {
                var poly_normal = Point{ 0, 0, 0, 0 };
                for (poly[1..], 1..) |_, j| {
                    poly_normal -= zmath.cross3(points[poly[j - 1]] - points[poly[0]], points[poly[j]] - points[poly[0]]);
                }
                average_normal += zmath.normalize3(poly_normal) / @as(@Vector(4, f32), @splat(@floatFromInt(local_polys.items.len)));
            }
            break :average_normal average_normal;
        } else Point{ 0, 0, 0, 0 }) catch unreachable;
    }
    return normals.items;
}

pub fn flipYZ(allocator: std.mem.Allocator, points: []const Point) []const Point {
    var flipped = std.ArrayList(Point).init(allocator);
    for (points) |point| {
        flipped.append(Point{ point[0], -point[2], point[1], point[3] }) catch unreachable;
    }
    return flipped.items;
}

pub fn polygonToTris(
    comptime poly_type: PolyType,
    allocator: std.mem.Allocator,
    polygons: []const switch (poly_type) {
        .Quad => Quad,
        .Face => Face,
    },
) []u32 {
    var indices = std.ArrayList(u32).init(allocator);
    for (polygons) |polygon| {
        for (polygon[1..], 1..) |_, i| {
            indices.append(polygon[0]) catch unreachable;
            indices.append(polygon[i - 1]) catch unreachable;
            indices.append(polygon[i]) catch unreachable;
        }
    }
    return indices.items;
}

pub fn quadToTris(allocator: std.mem.Allocator, quads: []const Quad) []u32 {
    var indices = std.ArrayList(u32).init(allocator);
    for (quads) |face| {
        try indices.append(face[1]);
        try indices.append(face[2]);
        try indices.append(face[0]);
        try indices.append(face[2]);
        try indices.append(face[0]);
        try indices.append(face[3]);
    }
    return indices.items;
}
