const std = @import("std");
const zmath = @import("zmath");
const vm = @import("./vec_math.zig");

pub const Point = @Vector(4, f32);
pub const Face = []const u32;
pub const Quad = [4]u32;

fn hexToFloat(hex_str: []const u8) f32 {
    var bytes: [4]u8 = undefined;
    _ = std.fmt.hexToBytes(&bytes, hex_str) catch unreachable;
    return @as(f32, @bitCast(bytes));
}

pub fn decodeVertexDataFromHexidecimal(allocator: std.mem.Allocator, hex_str: []const u8) []const Point {
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

pub fn flipYZ(allocator: std.mem.Allocator, points: []const Point) []const Point {
    var flipped = std.ArrayList(Point).init(allocator);
    for (points) |point| {
        flipped.append(flipYZSingle(point)) catch unreachable;
    }
    return flipped.items;
}

pub fn flipYZSingle(point: Point) Point {
    return Point{ point[0], -point[2], point[1], point[3] };
}

pub fn VecSliceFlattener(comptime options: struct {
    vec_size: u32,
    sample_size: u32,
    element_type: ?type = null,
}) type {
    const ElementType = if (options.element_type) |element_type| element_type else @Vector(options.vec_size, f32);
    const SubField = if (options.element_type) |element_type| std.meta.FieldEnum(element_type) else void;
    return struct {
        pub fn convert(allocator: std.mem.Allocator, points: []const ElementType, sub_field: SubField) []const f32 {
            var float_slice = allocator.alloc(f32, points.len * options.sample_size) catch unreachable;
            for (points, 0..) |point, index| {
                const point_data = @field(point, sub_field);
                std.mem.copyForwards(
                    f32,
                    float_slice[index * options.sample_size .. (index + 1) * options.sample_size],
                    @as([options.vec_size]f32, point_data)[0..options.sample_size],
                );
            }
            return float_slice;
        }
    };
}

pub fn flattenMatrices(allocator: std.mem.Allocator, points: []const zmath.Mat) []const f32 {
    const sample_size = 16; // 4x4 Matrix
    var float_slice = allocator.alloc(f32, points.len * sample_size) catch unreachable;
    for (points, 0..) |point, index| {
        const location = index * sample_size;
        for (point, 0..) |row, row_index| {
            std.mem.copyForwards(
                f32,
                float_slice[location + row_index * 4 .. location + (row_index + 1) * 4],
                @as([4]f32, row)[0..4],
            );
        }
    }
    return float_slice;
}

pub fn Polygon(comptime poly_selection: enum { Quad, Face }) type {
    const Poly = switch (poly_selection) {
        .Quad => Quad,
        .Face => Face,
    };
    return struct {
        pub noinline fn calculateNormals(
            allocator: std.mem.Allocator,
            points: []const Point,
            polygons: []const Poly,
        ) []const Point {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            const max_polys_per_vertex = 8;
            var vertex_to_poly = arena.allocator().alloc([max_polys_per_vertex]*const Poly, points.len) catch unreachable;
            const vertex_to_poly_len = arena.allocator().alloc(u8, points.len) catch unreachable;
            for (vertex_to_poly_len) |*len| {
                len.* = 0;
            }
            for (polygons) |*polygon| {
                for (polygon.*) |vertex| {
                    const len = &vertex_to_poly_len[vertex];
                    if (len.* < max_polys_per_vertex) {
                        vertex_to_poly[vertex][len.*] = polygon;
                        len.* += 1;
                    }
                }
            }
            var normals = std.ArrayList(Point).init(allocator);
            for (0..points.len) |i| {
                normals.append(average_normal: {
                    const local_polys = vertex_to_poly[i];
                    const len = vertex_to_poly_len[i];
                    var average_normal = Point{ 0, 0, 0, 0 };
                    for (0..len) |poly_index| {
                        var poly_normal = Point{ 0, 0, 0, 0 };
                        const poly = local_polys[poly_index];
                        for (2..poly.len) |j| {
                            poly_normal -= zmath.cross3(
                                points[poly.*[j - 1]] - points[poly.*[0]],
                                points[poly.*[j]] - points[poly.*[0]],
                            );
                        }
                        average_normal += zmath.normalize3(poly_normal);
                    }
                    break :average_normal vm.div(
                        average_normal,
                        @splat(@floatFromInt(vertex_to_poly_len[i])),
                    );
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
