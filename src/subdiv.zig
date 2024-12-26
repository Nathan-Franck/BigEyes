const std = @import("std");
const vm = @import("./vec_math.zig");

const ArrayList = std.ArrayList;

pub const Point = @Vector(4, f32);
pub const Face = []const u32;
pub const Quad = [4]u32;
pub const Mesh = struct {
    points: []const Point,
    quads: []const Quad,
};
const EdgesFace = struct {
    points: struct { u32, u32 },
    faces: struct { u32, u32 },
    center_point: Point,
};
const Point_Ex = struct {
    p: Point,
    n: u32,
};

pub fn Polygon(comptime poly_selection: enum {
    Face,
    Quad,
}) type {
    return struct {
        const Poly = switch (poly_selection) {
            .Face => Face,
            .Quad => Quad,
        };
        fn getFacePoints(allocator: std.mem.Allocator, input_points: []const Point, input_faces: []const Poly) ![]Point {
            var face_points = try ArrayList(Point).initCapacity(allocator, input_faces.len);
            for (input_faces) |face| {
                var face_point = Point{ 0, 0, 0, 1 };
                for (face) |point_num| {
                    face_point += input_points[point_num];
                }
                face_point /= @splat(@as(f32, @floatFromInt(face.len)));
                try face_points.append(face_point);
            }
            return face_points.items;
        }

        fn centerPoint(p1: Point, p2: Point) Point {
            return vm.div(p1 + p2, @splat(2));
        }

        fn getEdgesFaces(allocator: std.mem.Allocator, input_points: []const Point, input_faces: []const Poly) ![]const EdgesFace {
            var edges = try ArrayList([3]u32).initCapacity(allocator, input_faces.len * 4);
            for (input_faces, 0..) |face, face_num| {
                const num_points = face.len;
                for (face, 0..) |point_num, point_index| {
                    var point1 = point_num;
                    var point2: u32 = if (point_index < num_points - 1)
                        face[point_index + 1]
                    else
                        face[0];
                    if (point1 > point2) {
                        const swap = point1;
                        point1 = point2;
                        point2 = swap;
                    }
                    try edges.append([3]u32{ point1, point2, @as(u32, @intCast(face_num)) });
                }
            }
            std.sort.block([3]u32, edges.items, {}, struct {
                fn sort(context: void, a: [3]u32, b: [3]u32) bool {
                    _ = context;
                    if (a[0] == b[0]) {
                        if (a[1] == b[1]) {
                            return a[2] < b[2];
                        }
                        return a[1] < b[1];
                    }
                    return a[0] < b[0];
                }
            }.sort);
            const num_edges = edges.items.len;
            var e_index: usize = 0;
            var merged_edges = try ArrayList([4]u32).initCapacity(allocator, num_edges);
            while (e_index < num_edges) : (e_index += 1) {
                const e1 = edges.items[e_index];
                if (e_index < num_edges - 1) {
                    const e2 = edges.items[e_index + 1];
                    if (e1[0] == e2[0] and e1[1] == e2[1]) {
                        try merged_edges.append([4]u32{ e1[0], e1[1], e1[2], e2[2] });
                        e_index += 1;
                    } else {
                        try merged_edges.append([4]u32{ e1[0], e1[1], e1[2], std.math.maxInt(u32) });
                    }
                } else {
                    try merged_edges.append([4]u32{ e1[0], e1[1], e1[2], std.math.maxInt(u32) });
                }
            }
            var edges_centers = try ArrayList(EdgesFace).initCapacity(allocator, merged_edges.items.len);
            for (merged_edges.items) |me| {
                const p1 = input_points[me[0]];
                const p2 = input_points[me[1]];
                try edges_centers.append(EdgesFace{
                    .points = .{ me[0], me[1] },
                    .faces = .{ me[2], me[3] },
                    .center_point = centerPoint(p1, p2),
                });
            }
            return edges_centers.items;
        }

        fn getEdgePoints(allocator: std.mem.Allocator, edges_faces: []const EdgesFace, face_points: []const Point) ![]Point {
            var edge_points = try ArrayList(Point).initCapacity(allocator, edges_faces.len);
            for (edges_faces) |edge| {
                const cp = edge.center_point;
                const fp1 = face_points[edge.faces[0]];
                const fp2 = if (edge.faces[1] == std.math.maxInt(u32))
                    fp1
                else
                    face_points[edge.faces[1]];
                const cfp = centerPoint(fp1, fp2);
                try edge_points.append(centerPoint(cp, cfp));
            }
            return edge_points.items;
        }

        fn getAvgFacePoints(allocator: std.mem.Allocator, input_points: []const Point, input_faces: []const Poly, face_points: []const Point) ![]Point {
            var temp_points = try ArrayList(Point_Ex).initCapacity(allocator, input_points.len);
            for (input_points) |_| {
                try temp_points.append(Point_Ex{ .p = Point{ 0, 0, 0, 1 }, .n = 0 });
            }
            for (input_faces, 0..) |face, face_num| {
                const fp = face_points[face_num];
                for (face) |point_num| {
                    const tp = temp_points.items[point_num].p;
                    temp_points.items[point_num].p = tp + fp;
                    temp_points.items[point_num].n += 1;
                }
            }
            var avg_face_points = try ArrayList(Point).initCapacity(allocator, temp_points.items.len);
            for (temp_points.items) |tp| {
                try avg_face_points.append(tp.p / @as(Point, @splat(@as(f32, @floatFromInt(tp.n)))));
            }
            return avg_face_points.items;
        }

        fn getAvgMidEdges(allocator: std.mem.Allocator, input_points: []const Point, edges_faces: []const EdgesFace) ![]Point {
            var temp_points = try ArrayList(Point_Ex).initCapacity(allocator, input_points.len);
            for (input_points) |_| {
                try temp_points.append(Point_Ex{ .p = Point{ 0, 0, 0, 1 }, .n = 0 });
            }
            for (edges_faces) |edge| {
                for ([_]u32{ edge.points[0], edge.points[1] }) |point_num| {
                    const tp = temp_points.items[point_num].p;
                    temp_points.items[point_num].p = tp + edge.center_point;
                    temp_points.items[point_num].n += 1;
                }
            }
            var avg_mid_edges = try ArrayList(Point).initCapacity(allocator, temp_points.items.len);
            for (temp_points.items) |tp| {
                try avg_mid_edges.append(tp.p / @as(Point, @splat(@as(f32, @floatFromInt(tp.n)))));
            }
            return avg_mid_edges.items;
        }

        fn getPointsFaces(allocator: std.mem.Allocator, input_points: []const Point, input_faces: []const Poly) ![]u32 {
            var points_faces = try ArrayList(u32).initCapacity(allocator, input_points.len);
            for (input_points) |_| {
                try points_faces.append(0);
            }
            for (input_faces) |face| {
                for (face) |point_num| {
                    points_faces.items[point_num] += 1;
                }
            }
            return points_faces.items;
        }

        fn getNewPoints(allocator: std.mem.Allocator, input_points: []const Point, input_faces: []const Poly, face_points: []const Point, edges_faces: []const EdgesFace) ![]Point {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            const avg_face_points = try getAvgFacePoints(arena.allocator(), input_points, input_faces, face_points);
            const avg_mid_edges = try getAvgMidEdges(arena.allocator(), input_points, edges_faces);
            const points_faces = try getPointsFaces(arena.allocator(), input_points, input_faces);
            var new_points = try ArrayList(Point).initCapacity(allocator, input_points.len);
            for (input_points, 0..) |point, point_num| {
                const n = @as(f32, @floatFromInt(points_faces[point_num]));
                const m1 = @max(n - 3, 0) / n;
                const m2 = 1.0 / n;
                const m3 = 2.0 / n;
                const p1 = point * @as(Point, @splat(m1));
                const afp = avg_face_points[point_num];
                const p2 = afp * @as(Point, @splat(m2));
                const ame = avg_mid_edges[point_num];
                const p3 = ame * @as(Point, @splat(m3));
                const p4 = p1 + p2;
                try new_points.append(p4 + p3);
            }
            return new_points.items;
        }

        fn switchNums(point_nums: [2]u32) [2]u32 {
            if (point_nums[0] < point_nums[1]) {
                return point_nums;
            }
            return [_]u32{ point_nums[1], point_nums[0] };
        }

        pub noinline fn cmcSubdiv(allocator: std.mem.Allocator, input_points: []const Point, input_faces: []const Poly) !Mesh {
            var arena = std.heap.ArenaAllocator.init(allocator);
            // defer arena.deinit();

            const face_points = try getFacePoints(arena.allocator(), input_points, input_faces);
            const edges_faces = try getEdgesFaces(arena.allocator(), input_points, input_faces);
            const edge_points = try getEdgePoints(arena.allocator(), edges_faces, face_points);
            const initial_new_points = try getNewPoints(arena.allocator(), input_points, input_faces, face_points, edges_faces);
            var face_point_nums = try ArrayList(u32).initCapacity(arena.allocator(), face_points.len);
            var new_points = try ArrayList(Point).initCapacity(allocator, initial_new_points.len);
            try new_points.appendSlice(initial_new_points);
            var next_point_num = new_points.items.len;
            for (face_points) |face_point| {
                try new_points.append(face_point);
                try face_point_nums.append(@as(u32, @intCast(next_point_num)));
                next_point_num += 1;
            }
            var edge_point_nums = std.AutoHashMap([2]u32, u32).init(arena.allocator());
            for (edges_faces, 0..) |edge_face, edge_num| {
                const point1, const point2 = edge_face.points;
                const edge_point = edge_points[edge_num];
                try new_points.append(edge_point);
                try edge_point_nums.put(switchNums([2]u32{ point1, point2 }), @as(u32, @intCast(next_point_num)));
                next_point_num += 1;
            }
            var new_quads = try ArrayList(Quad).initCapacity(allocator, input_faces.len);
            for (input_faces, 0..) |old_face, old_face_num| {
                for (0..old_face.len) |point_index| {
                    const next_point_index = if (point_index == old_face.len - 1) 0 else point_index + 1;
                    const prev_point_index = if (point_index == 0) old_face.len - 1 else point_index - 1;
                    const a = old_face[point_index];
                    const b = old_face[next_point_index];
                    const z = old_face[prev_point_index];
                    const face_point_abcd_z = face_point_nums.items[old_face_num];
                    const edge_point_ab = edge_point_nums.get(switchNums([2]u32{ a, b })).?;
                    const edge_point_za = edge_point_nums.get(switchNums([2]u32{ z, a })).?;
                    try new_quads.append([_]u32{ a, edge_point_ab, face_point_abcd_z, edge_point_za });
                }
            }
            return .{ .points = new_points.items, .quads = new_quads.items };
        }

        pub noinline fn cmcSubdivOnlyPoints(allocator: std.mem.Allocator, input_points: []const Point, input_faces: []const Poly) ![]const Point {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            const face_points = try getFacePoints(arena.allocator(), input_points, input_faces);
            const edges_faces = try getEdgesFaces(arena.allocator(), input_points, input_faces);
            const edge_points = try getEdgePoints(arena.allocator(), edges_faces, face_points);
            const initial_new_points = try getNewPoints(arena.allocator(), input_points, input_faces, face_points, edges_faces);
            var new_points = try ArrayList(Point).initCapacity(allocator, initial_new_points.len);
            try new_points.appendSlice(initial_new_points);
            try new_points.appendSlice(face_points);
            for (edges_faces, 0..) |_, edge_num| {
                const edge_point = edge_points[edge_num];
                try new_points.append(edge_point);
            }
            return new_points.items;
        }
    };
}
