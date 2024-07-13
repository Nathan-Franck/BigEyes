const std = @import("std");
const zmath = @import("./zmath/main.zig");
const spec = @import("MeshSpec.zig");
const Point = spec.Point;
const Quad = spec.Quad;
const Face = spec.Face;

fn hexToFloat(hex_str: []const u8) f32 {
    var bytes: [4]u8 = undefined;
    _ = std.fmt.hexToBytes(&bytes, hex_str) catch unreachable;
    return @as(f32, @bitCast(bytes));
}

pub fn decodeVertexDataFromHexidecimal(allocator: std.mem.Allocator, hex_str: []const u8) []const spec.Point {
    var result = std.ArrayList(Point).init(allocator);
    var i: u32 = 0;
    while (i < hex_str.len) {
        result.append(Point{
            hexToFloat(hex_str[i + 0 .. i + 8]),
            hexToFloat(hex_str[i + 8 .. i + 16]),
            hexToFloat(hex_str[i + 16 .. i + 24]),
            1,
        }) catch unreachable;
        i += 24;
    }
    return result.items;
}

pub fn flipYZ(allocator: std.mem.Allocator, points: []const spec.Point) []const Point {
    var flipped = std.ArrayList(Point).init(allocator);
    for (points) |point| {
        flipped.append(Point{ point[0], -point[2], point[1], point[3] }) catch unreachable;
    }
    return flipped.items;
}

pub fn pointsToFloatSlice(allocator: std.mem.Allocator, points: []const spec.Point) []const f32 {
    var float_slice = allocator.alloc(f32, points.len * 3) catch unreachable;
    return for (points, 0..) |point, index| {
        std.mem.copyForwards(
            f32,
            float_slice[index * 3 .. index * 3 + 3],
            @as([4]f32, point)[0..3],
        );
    } else float_slice;
}

pub fn Polygon(comptime poly_selection: enum { Quad, Face }) type {
    const Poly = switch (poly_selection) {
        .Quad => Quad,
        .Face => Face,
    };
    return struct {
        pub fn calculateNormals(
            allocator: std.mem.Allocator,
            points: []const Point,
            polygons: []const Poly,
        ) []const Point {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            // var vertexToPoly = std.AutoHashMap(u32, *std.ArrayList(*const Poly)).init(arena.allocator());
            var vertexToPoly = arena.allocator().alloc(std.ArrayList(*const Poly), points.len) catch unreachable;
            for (vertexToPoly) |*list| {
                list.* = std.ArrayList(*const Poly).init(arena.allocator());
            }
            for (polygons) |*polygon| {
                for (polygon.*) |vertex| {
                    vertexToPoly[vertex].append(polygon) catch unreachable;
                }
            }
            var normals = std.ArrayList(Point).init(allocator);
            for (points, 0..) |_, i| {
                normals.append(average_normal: {
                    const local_polys = vertexToPoly[@intCast(i)];
                    var average_normal = Point{ 0, 0, 0, 0 };
                    for (local_polys.items) |poly| {
                        var poly_normal = Point{ 0, 0, 0, 0 };
                        for (poly.*[1..], 1..) |_, j| {
                            poly_normal -= zmath.cross3(
                                points[poly.*[j - 1]] - points[poly.*[0]],
                                points[poly.*[j]] - points[poly.*[0]],
                            );
                        }
                        average_normal += zmath.normalize3(poly_normal) / @as(
                            @Vector(4, f32),
                            @splat(@floatFromInt(local_polys.items.len)),
                        );
                    }
                    break :average_normal average_normal;
                }) catch unreachable;
            }
            return normals.items;
        }

        pub fn toTriangleIndices(
            allocator: std.mem.Allocator,
            polygons: []const Poly,
        ) []u32 {
            var indices = std.ArrayList(u32).init(allocator);
            for (polygons) |polygon| {
                for (polygon[1 .. polygon.len - 1], 1..) |_, i| {
                    indices.appendSlice(&.{
                        polygon[0],
                        polygon[i],
                        polygon[i + 1],
                    }) catch unreachable;
                }
            }
            return indices.items;
        }
    };
}
