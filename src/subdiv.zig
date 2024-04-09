const std = @import("std");
const ArrayList = std.ArrayList;

pub const Point = @Vector(4, f32);
pub const Face = []const u32;
pub const Quad = [4]u32;
pub const Mesh = struct { points: []const Point, quads: []const Quad };
const EdgesFace = struct {
    points: struct { u32, u32 },
    faces: struct { u32, u32 },
    centerPoint: Point,
};
const PointEx = struct {
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
        fn getFacePoints(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Poly) ![]Point {
            var facePoints = try ArrayList(Point).initCapacity(allocator, inputFaces.len);
            for (inputFaces) |face| {
                var facePoint = Point{ 0, 0, 0, 1 };
                for (face) |pointNum| {
                    facePoint += inputPoints[pointNum];
                }
                facePoint /= @splat(@as(f32, @floatFromInt(face.len)));
                try facePoints.append(facePoint);
            }
            return facePoints.items;
        }

        fn centerPoint(p1: Point, p2: Point) Point {
            return (p1 + p2) / @as(Point, @splat(@as(f32, @floatCast(2))));
        }

        fn getEdgesFaces(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Poly) ![]const EdgesFace {
            var edges = try ArrayList([3]u32).initCapacity(allocator, inputFaces.len * 4);
            for (inputFaces, 0..) |face, faceNum| {
                const numPoints = face.len;
                for (face, 0..) |pointNum, pointIndex| {
                    var point1 = pointNum;
                    var point2: u32 = if (pointIndex < numPoints - 1)
                        face[pointIndex + 1]
                    else
                        face[0];
                    if (point1 > point2) {
                        const swap = point1;
                        point1 = point2;
                        point2 = swap;
                    }
                    try edges.append([3]u32{ point1, point2, @as(u32, @intCast(faceNum)) });
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
            const numEdges = edges.items.len;
            var eIndex: usize = 0;
            var mergedEdges = try ArrayList([4]u32).initCapacity(allocator, numEdges);
            while (eIndex < numEdges) : (eIndex += 1) {
                const e1 = edges.items[eIndex];
                if (eIndex < numEdges - 1) {
                    const e2 = edges.items[eIndex + 1];
                    if (e1[0] == e2[0] and e1[1] == e2[1]) {
                        try mergedEdges.append([4]u32{ e1[0], e1[1], e1[2], e2[2] });
                        eIndex += 1;
                    } else {
                        try mergedEdges.append([4]u32{ e1[0], e1[1], e1[2], std.math.maxInt(u32) });
                    }
                } else {
                    try mergedEdges.append([4]u32{ e1[0], e1[1], e1[2], std.math.maxInt(u32) });
                }
            }
            var edgesCenters = try ArrayList(EdgesFace).initCapacity(allocator, mergedEdges.items.len);
            for (mergedEdges.items) |me| {
                const p1 = inputPoints[me[0]];
                const p2 = inputPoints[me[1]];
                try edgesCenters.append(EdgesFace{
                    .points = .{ me[0], me[1] },
                    .faces = .{ me[2], me[3] },
                    .centerPoint = centerPoint(p1, p2),
                });
            }
            return edgesCenters.items;
        }

        fn getEdgePoints(allocator: std.mem.Allocator, edgesFaces: []const EdgesFace, facePoints: []const Point) ![]Point {
            var edgePoints = try ArrayList(Point).initCapacity(allocator, edgesFaces.len);
            for (edgesFaces) |edge| {
                const cp = edge.centerPoint;
                const fp1 = facePoints[edge.faces[0]];
                const fp2 = if (edge.faces[1] == std.math.maxInt(u32))
                    fp1
                else
                    facePoints[edge.faces[1]];
                const cfp = centerPoint(fp1, fp2);
                try edgePoints.append(centerPoint(cp, cfp));
            }
            return edgePoints.items;
        }

        fn getAvgFacePoints(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Poly, facePoints: []const Point) ![]Point {
            var tempPoints = try ArrayList(PointEx).initCapacity(allocator, inputPoints.len);
            for (inputPoints) |_| {
                try tempPoints.append(PointEx{ .p = Point{ 0, 0, 0, 1 }, .n = 0 });
            }
            for (inputFaces, 0..) |face, faceNum| {
                const fp = facePoints[faceNum];
                for (face) |pointNum| {
                    const tp = tempPoints.items[pointNum].p;
                    tempPoints.items[pointNum].p = tp + fp;
                    tempPoints.items[pointNum].n += 1;
                }
            }
            var avgFacePoints = try ArrayList(Point).initCapacity(allocator, tempPoints.items.len);
            for (tempPoints.items) |tp| {
                try avgFacePoints.append(tp.p / @as(Point, @splat(@as(f32, @floatFromInt(tp.n)))));
            }
            return avgFacePoints.items;
        }

        fn getAvgMidEdges(allocator: std.mem.Allocator, inputPoints: []const Point, edgesFaces: []const EdgesFace) ![]Point {
            var tempPoints = try ArrayList(PointEx).initCapacity(allocator, inputPoints.len);
            for (inputPoints) |_| {
                try tempPoints.append(PointEx{ .p = Point{ 0, 0, 0, 1 }, .n = 0 });
            }
            for (edgesFaces) |edge| {
                for ([_]u32{ edge.points[0], edge.points[1] }) |pointNum| {
                    const tp = tempPoints.items[pointNum].p;
                    tempPoints.items[pointNum].p = tp + edge.centerPoint;
                    tempPoints.items[pointNum].n += 1;
                }
            }
            var avgMidEdges = try ArrayList(Point).initCapacity(allocator, tempPoints.items.len);
            for (tempPoints.items) |tp| {
                try avgMidEdges.append(tp.p / @as(Point, @splat(@as(f32, @floatFromInt(tp.n)))));
            }
            return avgMidEdges.items;
        }

        fn getPointsFaces(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Poly) ![]u32 {
            var pointsFaces = try ArrayList(u32).initCapacity(allocator, inputPoints.len);
            for (inputPoints) |_| {
                try pointsFaces.append(0);
            }
            for (inputFaces) |face| {
                for (face) |pointNum| {
                    pointsFaces.items[pointNum] += 1;
                }
            }
            return pointsFaces.items;
        }

        fn getNewPoints(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Poly, facePoints: []const Point, edgesFaces: []const EdgesFace) ![]Point {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            const avgFacePoints = try getAvgFacePoints(arena.allocator(), inputPoints, inputFaces, facePoints);
            const avgMidEdges = try getAvgMidEdges(arena.allocator(), inputPoints, edgesFaces);
            const pointsFaces = try getPointsFaces(arena.allocator(), inputPoints, inputFaces);
            var newPoints = try ArrayList(Point).initCapacity(allocator, inputPoints.len);
            for (inputPoints, 0..) |point, pointNum| {
                const n = @as(f32, @floatFromInt(pointsFaces[pointNum]));
                const m1 = @max(n - 3, 0) / n;
                const m2 = 1.0 / n;
                const m3 = 2.0 / n;
                const p1 = point * @as(Point, @splat(m1));
                const afp = avgFacePoints[pointNum];
                const p2 = afp * @as(Point, @splat(m2));
                const ame = avgMidEdges[pointNum];
                const p3 = ame * @as(Point, @splat(m3));
                const p4 = p1 + p2;
                try newPoints.append(p4 + p3);
            }
            return newPoints.items;
        }

        fn switchNums(pointNums: [2]u32) [2]u32 {
            if (pointNums[0] < pointNums[1]) {
                return pointNums;
            }
            return [_]u32{ pointNums[1], pointNums[0] };
        }

        pub fn cmcSubdiv(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Poly) !Mesh {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            const facePoints = try getFacePoints(arena.allocator(), inputPoints, inputFaces);
            const edgesFaces = try getEdgesFaces(arena.allocator(), inputPoints, inputFaces);
            const edgePoints = try getEdgePoints(arena.allocator(), edgesFaces, facePoints);
            const initialNewPoints = try getNewPoints(arena.allocator(), inputPoints, inputFaces, facePoints, edgesFaces);
            var facePointNums = try ArrayList(u32).initCapacity(arena.allocator(), facePoints.len);
            var newPoints = try ArrayList(Point).initCapacity(arena.allocator(), initialNewPoints.len);
            try newPoints.appendSlice(initialNewPoints);
            var nextPointNum = newPoints.items.len;
            for (facePoints) |facePoint| {
                try newPoints.append(facePoint);
                try facePointNums.append(@as(u32, @intCast(nextPointNum)));
                nextPointNum += 1;
            }
            var edgePointNums = std.AutoHashMap([2]u32, u32).init(allocator);
            for (edgesFaces, 0..) |edgeFace, edgeNum| {
                const point1, const point2 = edgeFace.points;
                const edgePoint = edgePoints[edgeNum];
                try newPoints.append(edgePoint);
                try edgePointNums.put(switchNums([2]u32{ point1, point2 }), @as(u32, @intCast(nextPointNum)));
                nextPointNum += 1;
            }
            var newFaces = try ArrayList(Quad).initCapacity(allocator, inputFaces.len);
            for (inputFaces, 0..) |oldFace, oldFaceNum| {
                for (0..oldFace.len) |pointIndex| {
                    const nextPointIndex = if (pointIndex == oldFace.len - 1) 0 else pointIndex + 1;
                    const prevPointIndex = if (pointIndex == 0) oldFace.len - 1 else pointIndex - 1;
                    const a = oldFace[pointIndex];
                    const b = oldFace[nextPointIndex];
                    const z = oldFace[prevPointIndex];
                    const facePointAbcdZ = facePointNums.items[oldFaceNum];
                    const edgePointAb = edgePointNums.get(switchNums([2]u32{ a, b })).?;
                    const edgePointZa = edgePointNums.get(switchNums([2]u32{ z, a })).?;
                    try newFaces.append([_]u32{ a, edgePointAb, facePointAbcdZ, edgePointZa });
                }
            }
            return .{ .points = newPoints.items, .quads = newFaces.items };
        }

        pub fn cmcSubdivOnlyPoints(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Poly) ![]const Point {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            const facePoints = try getFacePoints(arena.allocator(), inputPoints, inputFaces);
            const edgesFaces = try getEdgesFaces(arena.allocator(), inputPoints, inputFaces);
            const edgePoints = try getEdgePoints(arena.allocator(), edgesFaces, facePoints);
            const initialNewPoints = try getNewPoints(arena.allocator(), inputPoints, inputFaces, facePoints, edgesFaces);
            var facePointNums = try ArrayList(u32).initCapacity(arena.allocator(), facePoints.len);
            var newPoints = try ArrayList(Point).initCapacity(allocator, initialNewPoints.len);
            try newPoints.appendSlice(initialNewPoints);
            var nextPointNum = newPoints.items.len;
            for (facePoints) |facePoint| {
                try newPoints.append(facePoint);
                try facePointNums.append(@as(u32, @intCast(nextPointNum)));
                nextPointNum += 1;
            }
            var edgePointNums = std.AutoHashMap([2]u32, u32).init(allocator);
            for (edgesFaces, 0..) |edgeFace, edgeNum| {
                const point1 = edgeFace.point1;
                const point2 = edgeFace.point2;
                const edgePoint = edgePoints[edgeNum];
                try newPoints.append(edgePoint);
                try edgePointNums.put(switchNums([2]u32{ point1, point2 }), @as(u32, @intCast(nextPointNum)));
                nextPointNum += 1;
            }
            return newPoints.items;
        }
    };
}

// test "getFacePoints" {
//     std.debug.print("Hello!", .{});
//     const allocator = std.heap.page_allocator;
//     var points = [_]Point{
//         Point{ -1.0, 1.0, 1.0, 1.0 },
//         Point{ -1.0, -1.0, 1.0, 1.0 },
//         Point{ 1.0, -1.0, 1.0, 1.0 },
//         Point{ 1.0, 1.0, 1.0, 1.0 },
//         Point{ -1.0, 1.0, -1.0, 1.0 },
//         Point{ -1.0, -1.0, -1.0, 1.0 },
//     };
//     var faces = [_]Face{
//         &[_]u32{ 0, 1, 2, 3 },
//         &[_]u32{ 0, 1, 5, 4 },
//     };
//     const result = try Polygon(.Face).getFacePoints(
//         allocator,
//         &points,
//         &faces,
//     );

//     const expected = [_]Point{
//         Point{ 0.0, 0.0, 1.0, 1.0 },
//         Point{ -1.0, 0.0, 0.0, 1.0 },
//     };

//     try std.testing.expectEqual(expected.len, result.len);
//     for (expected, 0..) |expectedPoint, i| {
//         try std.testing.expectEqual(expectedPoint, result[i]);
//     }
// }

// test "getEdgesFaces" {
//     const allocator = std.heap.page_allocator;
//     var points = [_]Point{
//         Point{ -1.0, 1.0, 1.0, 1.0 },
//         Point{ -1.0, -1.0, 1.0, 1.0 },
//         Point{ 1.0, -1.0, 1.0, 1.0 },
//         Point{ 1.0, 1.0, 1.0, 1.0 },
//         Point{ -1.0, 1.0, -1.0, 1.0 },
//         Point{ -1.0, -1.0, -1.0, 1.0 },
//     };
//     var faces = [_]Face{
//         &[_]u32{ 0, 1, 2, 3 },
//         &[_]u32{ 0, 1, 5, 4 },
//     };
//     const result = try Polygon(.Face).getEdgesFaces(
//         allocator,
//         &points,
//         &faces,
//     );

//     try std.testing.expectEqual(EdgesFace{ .point1 = 0, .point2 = 1, .face1 = 0, .face2 = 1, .centerPoint = .{ -1.0, 0.0, 1.0 } }, result[0]);
//     try std.testing.expectEqual(EdgesFace{ .point1 = 0, .point2 = 3, .face1 = 0, .face2 = std.math.maxInt(u32), .centerPoint = .{ 0.0, 1.0, 1.0 } }, result[1]);
//     try std.testing.expectEqual(EdgesFace{ .point1 = 0, .point2 = 4, .face1 = 1, .face2 = std.math.maxInt(u32), .centerPoint = .{ -1.0, 1.0, 0.0 } }, result[2]);
//     try std.testing.expectEqual(EdgesFace{ .point1 = 1, .point2 = 2, .face1 = 0, .face2 = std.math.maxInt(u32), .centerPoint = .{ 0.0, -1.0, 1.0 } }, result[3]);
//     try std.testing.expectEqual(EdgesFace{ .point1 = 1, .point2 = 5, .face1 = 1, .face2 = std.math.maxInt(u32), .centerPoint = .{ -1.0, -1.0, 0.0 } }, result[4]);
//     try std.testing.expectEqual(EdgesFace{ .point1 = 2, .point2 = 3, .face1 = 0, .face2 = std.math.maxInt(u32), .centerPoint = .{ 1.0, 0.0, 1.0 } }, result[5]);
//     try std.testing.expectEqual(EdgesFace{ .point1 = 4, .point2 = 5, .face1 = 1, .face2 = std.math.maxInt(u32), .centerPoint = .{ -1.0, 0.0, -1.0 } }, result[6]);
// }

// test "getPointsFaces" {
//     const allocator = std.heap.page_allocator;
//     var points = [_]Point{
//         Point{ -1.0, 1.0, 1.0, 1.0 },
//         Point{ -1.0, -1.0, 1.0, 1.0 },
//         Point{ 1.0, -1.0, 1.0, 1.0 },
//         Point{ 1.0, 1.0, 1.0, 1.0 },
//         Point{ -1.0, 1.0, -1.0, 1.0 },
//         Point{ -1.0, -1.0, -1.0, 1.0 },
//     };
//     var faces = [_]Face{
//         &[_]u32{ 0, 1, 2, 3 },
//         &[_]u32{ 0, 1, 5, 4 },
//     };
//     const result = try Polygon(.Face).getPointsFaces(
//         allocator,
//         &points,
//         &faces,
//     );

//     _ = result;
// }

// test "cmcSubdiv" {
//     const allocator = std.heap.page_allocator;
//     var points = [_]Point{
//         Point{ -1.0, 1.0, 1.0, 1.0 },
//         Point{ -1.0, -1.0, 1.0, 1.0 },
//         Point{ 1.0, -1.0, 1.0, 1.0 },
//         Point{ 1.0, 1.0, 1.0, 1.0 },
//         Point{ -1.0, 1.0, -1.0, 1.0 },
//         Point{ -1.0, -1.0, -1.0, 1.0 },
//     };
//     var faces = [_]Face{
//         &[_]u32{ 0, 1, 2, 3 },
//         &[_]u32{ 0, 1, 5, 4 },
//     };
//     const result = try Polygon(.Face).cmcSubdiv(
//         allocator,
//         &points,
//         &faces,
//     );

//     try std.testing.expectEqual(result.points.len, 15);
//     try std.testing.expectEqual(result.quads.len, 8);
//     for (result.quads) |face| {
//         for (face) |pointNum| {
//             try std.testing.expect(pointNum >= 0);
//             try std.testing.expect(pointNum < 15);
//         }
//     }
// }
