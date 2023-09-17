const std = @import("std");
const math = std.math;
const ArrayList = std.ArrayList;

pub const Point = @Vector(3, f32);
pub const Face = [4]u32;
pub const Mesh = struct { points: []const Point, faces: []const Face };
const EdgesFace = struct {
    point1: u32,
    point2: u32,
    face1: u32,
    face2: u32,
    centerPoint: Point,
};
const PointEx = struct {
    p: Point,
    n: u32,
};

fn getFacePoints(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Face) ![]Point {
    var facePoints = try ArrayList(Point).initCapacity(allocator, inputFaces.len);
    for (inputFaces) |face| {
        var facePoint = Point{ 0, 0, 0 };
        for (face) |pointNum| {
            facePoint += inputPoints[pointNum];
        }
        facePoint /= @splat(@as(f32, @floatFromInt(face.len)));
        try facePoints.append(facePoint);
    }
    return facePoints.toOwnedSlice();
}

fn centerPoint(p1: Point, p2: Point) Point {
    return (p1 + p2) / @as(Point, @splat(@as(f32, @floatCast(2))));
}

fn getEdgesFaces(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Face) ![]const EdgesFace {
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
                var swap = point1;
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
    var numEdges = edges.items.len;
    var eIndex: usize = 0;
    var mergedEdges = try ArrayList([4]u32).initCapacity(allocator, numEdges);
    while (eIndex < numEdges) : (eIndex += 1) {
        var e1 = edges.items[eIndex];
        if (eIndex < numEdges - 1) {
            var e2 = edges.items[eIndex + 1];
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
        var p1 = inputPoints[me[0]];
        var p2 = inputPoints[me[1]];
        try edgesCenters.append(EdgesFace{
            .point1 = me[0],
            .point2 = me[1],
            .face1 = me[2],
            .face2 = me[3],
            .centerPoint = centerPoint(p1, p2),
        });
    }
    return edgesCenters.items;
}

fn getEdgePoints(allocator: std.mem.Allocator, edgesFaces: []const EdgesFace, facePoints: []const Point) ![]Point {
    var edgePoints = try ArrayList(Point).initCapacity(allocator, edgesFaces.len);
    for (edgesFaces) |edge| {
        var cp = edge.centerPoint;
        var fp1 = facePoints[edge.face1];
        var fp2 = if (edge.face2 == std.math.maxInt(u32))
            fp1
        else
            facePoints[edge.face2];
        var cfp = centerPoint(fp1, fp2);
        try edgePoints.append(centerPoint(cp, cfp));
    }
    return edgePoints.toOwnedSlice();
}

fn getAvgFacePoints(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Face, facePoints: []const Point) ![]Point {
    var tempPoints = try ArrayList(PointEx).initCapacity(allocator, inputPoints.len);
    for (inputPoints) |_| {
        try tempPoints.append(PointEx{ .p = Point{ 0, 0, 0 }, .n = 0 });
    }
    for (inputFaces, 0..) |face, faceNum| {
        var fp = facePoints[faceNum];
        for (face) |pointNum| {
            var tp = tempPoints.items[pointNum].p;
            tempPoints.items[pointNum].p = tp + fp;
            tempPoints.items[pointNum].n += 1;
        }
    }
    var avgFacePoints = try ArrayList(Point).initCapacity(allocator, tempPoints.items.len);
    for (tempPoints.items) |tp| {
        try avgFacePoints.append(tp.p / @as(Point, @splat(@as(f32, @floatFromInt(tp.n)))));
    }
    return avgFacePoints.toOwnedSlice();
}

fn getAvgMidEdges(allocator: std.mem.Allocator, inputPoints: []const Point, edgesFaces: []const EdgesFace) ![]Point {
    var tempPoints = try ArrayList(PointEx).initCapacity(allocator, inputPoints.len);
    for (inputPoints) |_| {
        try tempPoints.append(PointEx{ .p = Point{ 0, 0, 0 }, .n = 0 });
    }
    for (edgesFaces) |edge| {
        for ([_]u32{ edge.point1, edge.point2 }) |pointNum| {
            var tp = tempPoints.items[pointNum].p;
            tempPoints.items[pointNum].p = tp + edge.centerPoint;
            tempPoints.items[pointNum].n += 1;
        }
    }
    var avgMidEdges = try ArrayList(Point).initCapacity(allocator, tempPoints.items.len);
    for (tempPoints.items) |tp| {
        try avgMidEdges.append(tp.p / @as(Point, @splat(@as(f32, @floatFromInt(tp.n)))));
    }
    return avgMidEdges.toOwnedSlice();
}

fn getPointsFaces(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Face) ![]u32 {
    var pointsFaces = try ArrayList(u32).initCapacity(allocator, inputPoints.len);
    for (inputPoints) |_| {
        try pointsFaces.append(0);
    }
    for (inputFaces) |face| {
        for (face) |pointNum| {
            pointsFaces.items[pointNum] += 1;
        }
    }
    return pointsFaces.toOwnedSlice();
}

fn getNewPoints(allocator: std.mem.Allocator, inputPoints: []const Point, pointsFaces: []const u32, avgFacePoints: []const Point, avgMidEdges: []const Point) ![]Point {
    var newPoints = try ArrayList(Point).initCapacity(allocator, inputPoints.len);
    for (inputPoints, 0..) |point, pointNum| {
        var n = @as(f32, @floatFromInt(pointsFaces[pointNum]));
        var m1 = @max(n - 3, 0) / n;
        var m2 = 1.0 / n;
        var m3 = 2.0 / n;
        std.debug.print("{}, {}, {}\n", .{ m1, m2, m3 });
        var p1 = point * @as(Point, @splat(m1));
        var afp = avgFacePoints[pointNum];
        var p2 = afp * @as(Point, @splat(m2));
        var ame = avgMidEdges[pointNum];
        var p3 = ame * @as(Point, @splat(m3));
        var p4 = p1 + p2;
        try newPoints.append(p4 + p3);
    }
    return newPoints.toOwnedSlice();
}

fn switchNums(pointNums: [2]u32) [2]u32 {
    if (pointNums[0] < pointNums[1]) {
        return pointNums;
    }
    return [_]u32{ pointNums[1], pointNums[0] };
}

pub fn cmcSubdiv(allocator: std.mem.Allocator, inputPoints: []const Point, inputFaces: []const Face) !Mesh {
    var facePoints = try getFacePoints(allocator, inputPoints, inputFaces);
    var edgesFaces = try getEdgesFaces(allocator, inputPoints, inputFaces);
    var edgePoints = try getEdgePoints(allocator, edgesFaces, facePoints);
    var avgFacePoints = try getAvgFacePoints(allocator, inputPoints, inputFaces, facePoints);
    var avgMidEdges = try getAvgMidEdges(allocator, inputPoints, edgesFaces);
    var pointsFaces = try getPointsFaces(allocator, inputPoints, inputFaces);
    var initialNewPoints = try getNewPoints(allocator, inputPoints, pointsFaces, avgFacePoints, avgMidEdges);
    var facePointNums = try ArrayList(u32).initCapacity(allocator, facePoints.len);
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
        var point1 = edgeFace.point1;
        var point2 = edgeFace.point2;
        var edgePoint = edgePoints[edgeNum];
        try newPoints.append(edgePoint);
        try edgePointNums.put(switchNums([2]u32{ point1, point2 }), @as(u32, @intCast(nextPointNum)));
        nextPointNum += 1;
    }
    var newFaces = try ArrayList(Face).initCapacity(allocator, inputFaces.len);
    for (inputFaces, 0..) |oldFace, oldFaceNum| {
        if (oldFace.len == 4) {
            var a = oldFace[0];
            var b = oldFace[1];
            var c = oldFace[2];
            var d = oldFace[3];
            var facePointAbcd = facePointNums.items[oldFaceNum];
            var edgePointAb = edgePointNums.get(switchNums([2]u32{ a, b })).?;
            var edgePointDa = edgePointNums.get(switchNums([2]u32{ d, a })).?;
            var edgePointBc = edgePointNums.get(switchNums([2]u32{ b, c })).?;
            var edgePointCd = edgePointNums.get(switchNums([2]u32{ c, d })).?;
            try newFaces.append(.{ a, edgePointAb, facePointAbcd, edgePointDa });
            try newFaces.append(.{ b, edgePointBc, facePointAbcd, edgePointAb });
            try newFaces.append(.{ c, edgePointCd, facePointAbcd, edgePointBc });
            try newFaces.append(.{ d, edgePointDa, facePointAbcd, edgePointCd });
        }
    }
    return .{ .points = try newPoints.toOwnedSlice(), .faces = try newFaces.toOwnedSlice() };
}

test "getFacePoints" {
    var allocator = std.heap.page_allocator;
    var points = [_]Point{
        Point{ -1.0, 1.0, 1.0 },
        Point{ -1.0, -1.0, 1.0 },
        Point{ 1.0, -1.0, 1.0 },
        Point{ 1.0, 1.0, 1.0 },
        Point{ -1.0, 1.0, -1.0 },
        Point{ -1.0, -1.0, -1.0 },
    };
    var faces = [_]Face{
        .{ 0, 1, 2, 3 },
        .{ 0, 1, 5, 4 },
    };
    var result = try getFacePoints(
        allocator,
        &points,
        &faces,
    );

    var expected = [_]Point{
        Point{ 0.0, 0.0, 1.0 },
        Point{ -1.0, 0.0, 0.0 },
    };

    try std.testing.expectEqual(expected.len, result.len);
    for (expected, 0..) |expectedPoint, i| {
        try std.testing.expectEqual(expectedPoint, result[i]);
    }
}

test "getEdgesFaces" {
    var allocator = std.heap.page_allocator;
    var points = [_]Point{
        Point{ -1.0, 1.0, 1.0 },
        Point{ -1.0, -1.0, 1.0 },
        Point{ 1.0, -1.0, 1.0 },
        Point{ 1.0, 1.0, 1.0 },
        Point{ -1.0, 1.0, -1.0 },
        Point{ -1.0, -1.0, -1.0 },
    };
    var faces = [_]Face{
        .{ 0, 1, 2, 3 },
        .{ 0, 1, 5, 4 },
    };
    var result = try getEdgesFaces(
        allocator,
        &points,
        &faces,
    );

    try std.testing.expectEqual(EdgesFace{ .point1 = 0, .point2 = 1, .face1 = 0, .face2 = 1, .centerPoint = .{ -1.0, 0.0, 1.0 } }, result[0]);
    try std.testing.expectEqual(EdgesFace{ .point1 = 0, .point2 = 3, .face1 = 0, .face2 = std.math.maxInt(u32), .centerPoint = .{ 0.0, 1.0, 1.0 } }, result[1]);
    try std.testing.expectEqual(EdgesFace{ .point1 = 0, .point2 = 4, .face1 = 1, .face2 = std.math.maxInt(u32), .centerPoint = .{ -1.0, 1.0, 0.0 } }, result[2]);
    try std.testing.expectEqual(EdgesFace{ .point1 = 1, .point2 = 2, .face1 = 0, .face2 = std.math.maxInt(u32), .centerPoint = .{ 0.0, -1.0, 1.0 } }, result[3]);
    try std.testing.expectEqual(EdgesFace{ .point1 = 1, .point2 = 5, .face1 = 1, .face2 = std.math.maxInt(u32), .centerPoint = .{ -1.0, -1.0, 0.0 } }, result[4]);
    try std.testing.expectEqual(EdgesFace{ .point1 = 2, .point2 = 3, .face1 = 0, .face2 = std.math.maxInt(u32), .centerPoint = .{ 1.0, 0.0, 1.0 } }, result[5]);
    try std.testing.expectEqual(EdgesFace{ .point1 = 4, .point2 = 5, .face1 = 1, .face2 = std.math.maxInt(u32), .centerPoint = .{ -1.0, 0.0, -1.0 } }, result[6]);
}

test "getPointsFaces" {
    var allocator = std.heap.page_allocator;
    var points = [_]Point{
        Point{ -1.0, 1.0, 1.0 },
        Point{ -1.0, -1.0, 1.0 },
        Point{ 1.0, -1.0, 1.0 },
        Point{ 1.0, 1.0, 1.0 },
        Point{ -1.0, 1.0, -1.0 },
        Point{ -1.0, -1.0, -1.0 },
    };
    var faces = [_]Face{
        .{ 0, 1, 2, 3 },
        .{ 0, 1, 5, 4 },
    };
    var result = try getPointsFaces(
        allocator,
        &points,
        &faces,
    );

    _ = result;
}

test "getNewPoints" {
    var allocator = std.heap.page_allocator;
    var points = [_]Point{
        Point{ -1.0, 1.0, 1.0 },
        Point{ -1.0, -1.0, 1.0 },
        Point{ 1.0, -1.0, 1.0 },
        Point{ 1.0, 1.0, 1.0 },
        Point{ -1.0, 1.0, -1.0 },
        Point{ -1.0, -1.0, -1.0 },
    };
    var constFaces = [_]Face{
        .{ 0, 1, 2, 3 },
        .{ 0, 1, 5, 4 },
    };
    var pointFaces = try getPointsFaces(
        allocator,
        &points,
        &constFaces,
    );
    var facePoints = try getFacePoints(
        allocator,
        &points,
        &constFaces,
    );
    var edgesFaces = try getEdgesFaces(
        allocator,
        &points,
        &constFaces,
    );
    var avgFacePoints = try getAvgFacePoints(
        allocator,
        &points,
        &constFaces,
        facePoints,
    );
    var avgMidEdges = try getAvgMidEdges(
        allocator,
        &points,
        edgesFaces,
    );
    var result = try getNewPoints(
        allocator,
        &points,
        pointFaces,
        avgFacePoints,
        avgMidEdges,
    );

    _ = result;
}

test "cmcSubdiv" {
    var allocator = std.heap.page_allocator;
    var points = [_]Point{
        Point{ -1.0, 1.0, 1.0 },
        Point{ -1.0, -1.0, 1.0 },
        Point{ 1.0, -1.0, 1.0 },
        Point{ 1.0, 1.0, 1.0 },
        Point{ -1.0, 1.0, -1.0 },
        Point{ -1.0, -1.0, -1.0 },
    };
    var faces = [_]Face{
        .{ 0, 1, 2, 3 },
        .{ 0, 1, 5, 4 },
    };
    var result = try cmcSubdiv(
        allocator,
        &points,
        &faces,
    );

    std.debug.print("result: {any}\n", .{result});
    try std.testing.expectEqual(result.points.len, 15);
    try std.testing.expectEqual(result.faces.len, 8);
    for (result.faces) |face| {
        for (face) |pointNum| {
            try std.testing.expect(pointNum >= 0);
            try std.testing.expect(pointNum < 15);
        }
    }
}
