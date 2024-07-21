const zm = @import("zmath/main.zig");
const std = @import("std");
const Vec = zm.Vec;

pub const Triangle = [3]zm.Vec;
pub const Ray = struct {
    position: zm.Vec,
    normal: zm.Vec,
};

pub const Bounds = struct {
    min: Vec,
    max: Vec,
    pub fn initEncompass(points: []const Vec) Bounds {
        var min = Vec{ std.math.inf(f32), std.math.inf(f32), std.math.inf(f32), 0 };
        var max = Vec{ -std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32), 0 };
        for (points) |point| {
            min = @min(min, point);
            max = @max(max, point);
        }
        return Bounds{ .min = min, .max = max };
    }
    pub fn size(self: Bounds) Vec {
        return self.max - self.min;
    }
    pub fn scale(self: Bounds, factor: f32) Bounds {
        return Bounds{ .min = self.min * factor, .max = self.max * factor };
    }
    pub fn toBoundsSpace(self: Bounds, point: Vec) Vec {
        return (point - self.min) / self.size();
    }
};

const epsilon = 0.00001;

pub fn dot(a: zm.Vec, b: zm.Vec) f32 {
    const mult = a * b;
    return mult[0] + mult[1] + mult[2];
}

pub fn rayTriangleIntersection(ray: Ray, triangle: Triangle) ?struct { distance: f32 } {
    const edge1 = triangle[1] - triangle[0];
    const edge2 = triangle[2] - triangle[0];
    const h = zm.cross3(ray.normal, edge2);
    const a = dot(edge1, h);
    if (a > -epsilon and a < epsilon) {
        return null;
    }
    const f = 1.0 / a;
    const s = ray.position - triangle[0];
    const u = f * dot(s, h);
    if (u < 0.0 or u > 1.0) {
        return null;
    }
    const q = zm.cross3(s, edge1);
    const v = f * dot(ray.normal, q);
    if (v < 0.0 or u + v > 1.0) {
        return null;
    }
    const t = f * dot(edge2, q);
    if (t > epsilon) {
        return .{ .distance = t };
    }
    return null;
}

test "Ray Triangle Intersection" {
    const ray = Ray{
        .position = Vec{ 0.5, 0.5, -10, 0 },
        .normal = Vec{ 0, 0, 1, 0 },
    };
    const triangle = Triangle{
        Vec{ 0, 0, 0, 0 },
        Vec{ 1, 0, 0, 0 },
        Vec{ 0, 1, 0, 0 },
    };
    const result = rayTriangleIntersection(ray, triangle);
    try std.testing.expectEqualDeep(10.0, result.?.distance);
}

pub fn rayBoundsIntersection(ray: Ray, bounds: Bounds) ?struct { entry_distance: f32, exit_distance: f32 } {
    const t1 = (bounds.min - ray.position) / ray.normal;
    const t2 = (bounds.max - ray.position) / ray.normal;
    const tmin = @max(@min(t1, t2), @as(Vec, @splat(0)));
    const tmax = @min(@max(t1, t2), @as(Vec, @splat(std.math.inf(f32))));
    if (@reduce(.Or, tmax < tmin)) {
        return null;
    }
    const entry_distance = @reduce(.Max, tmin);
    const exit_distance = @reduce(.Min, tmax);
    return .{ .entry_distance = entry_distance, .exit_distance = exit_distance };
}

test "Ray Bounds Intersection" {
    const ray = Ray{
        .position = Vec{ 0, 0, -2, 0 },
        .normal = Vec{ 0, 0, 1, 0 },
    };
    const bounds = Bounds{
        .min = Vec{ -1, -1, -1, 0 },
        .max = Vec{ 1, 1, 1, 0 },
    };
    const result = rayBoundsIntersection(ray, bounds);
    try std.testing.expectEqualDeep(1.0, result.?.entry_distance);
    try std.testing.expectEqualDeep(3.0, result.?.exit_distance);
}

const Coord = @Vector(3, usize);
const IntDir = @Vector(3, i32);

pub const GridTraversal = struct {
    current: Coord,
    step: IntDir,
    tDelta: Vec,
    tMax: Vec,
    end: Coord,

    pub fn init(uncapped_start: Vec, uncapped_end: Vec) GridTraversal {
        const start = @max(uncapped_start, @as(Vec, @splat(0)));
        const end = @max(uncapped_end, @as(Vec, @splat(0)));
        const dir = end - start;

        const step: IntDir = @as([4]i32, @select(
            i32,
            dir > @as(Vec, @splat(0)),
            @as(Vec, @splat(1)),
            @as(Vec, @splat(-1)),
        ))[0..3].*;

        const tDelta = @select(
            f32,
            dir != @as(Vec, @splat(0)),
            @abs(@as(Vec, @splat(1)) / dir),
            @as(Vec, @splat(std.math.inf(f32))),
        );

        const startFloor = @floor(start);
        const tMax = @select(
            f32,
            @as([3]i32, step) ++ .{0} > @as(@Vector(4, i32), @splat(0)),
            (startFloor + @as(Vec, @splat(1)) - start) * tDelta,
            (start - startFloor) * tDelta,
        );

        return GridTraversal{
            .current = @intFromFloat(@floor(@as(@Vector(3, f32), @as([4]f32, start)[0..3].*))),
            .end = @intFromFloat(@floor(@as(@Vector(3, f32), @as([4]f32, end)[0..3].*))),
            .step = step,
            .tDelta = tDelta,
            .tMax = tMax,
        };
    }

    pub fn next(self: *GridTraversal) ?Coord {
        const wasm_entry = @import("./wasm_entry.zig");
        if (@reduce(.And, @abs(@as(IntDir, @intCast(self.current)) - @as(IntDir, @intCast(self.end)))) == 0) {
            return null;
        }
        wasm_entry.dumpDebugLogFmt(std.heap.page_allocator, "{any} {any}", .{ self.current, self.end }) catch unreachable;

        const result = self.current;

        // Calculate boolean comparisons directly from self.tMax
        const x_smallest = self.tMax[0] <= self.tMax[1] and self.tMax[0] <= self.tMax[2];
        const y_smallest = self.tMax[1] <= self.tMax[0] and self.tMax[1] <= self.tMax[2];
        const z_smallest = self.tMax[2] <= self.tMax[0] and self.tMax[2] <= self.tMax[1];

        // Cast to boolean vectors
        const mask_x = @as(@Vector(4, bool), @splat(x_smallest));
        const mask_y = @as(@Vector(4, bool), @splat(y_smallest));
        const mask_z = @as(@Vector(4, bool), @splat(z_smallest));

        // Use boolean vectors in @select
        const update_x = @select(i32, mask_x, @as(Vec, @Vector(4, f32){ 1, 0, 0, 0 }), @as(Vec, @splat(0)));
        const update_y = @select(i32, mask_y, @as(Vec, @Vector(4, f32){ 0, 1, 0, 0 }), @as(Vec, @splat(0)));
        const update_z = @select(i32, mask_z, @as(Vec, @Vector(4, f32){ 0, 0, 1, 0 }), @as(Vec, @splat(0)));

        const update = update_x + update_y + update_z;

        wasm_entry.dumpDebugLogFmt(std.heap.page_allocator, "Done?", .{}) catch unreachable;
        self.current += @intCast(self.step * @as(IntDir, @as([4]i32, update)[0..3].*));
        wasm_entry.dumpDebugLogFmt(std.heap.page_allocator, "Done!", .{}) catch unreachable;
        self.tMax += self.tDelta * @as(Vec, @floatFromInt(update));

        return result;
    }
};
test "Grid Traversal Iterator" {
    const start = Vec{ 0.5, 0.5, 0.5, 0 };
    const end = Vec{ 2.5, 2.5, 2.5, 0 };
    var traversal = GridTraversal.init(start, end);

    while (traversal.next()) |cell| {
        std.debug.print("Visiting cell: ({d}, {d}, {d})\n", .{ cell[0], cell[1], cell[2] });
    }
}

pub fn GridBounds(grid_width: usize) type {
    return struct {
        pub const width = grid_width;
        pub const array_size = grid_width * grid_width * grid_width;
        bounds: Bounds,
        pub fn transformPoint(self: @This(), arg: zm.Vec) zm.Vec {
            return self.bounds.toBoundsSpace(arg) * @as(zm.Vec, @splat(width));
        }
        pub fn coordToIndex(coord: Coord) usize {
            return coord[0] + coord[1] * width + coord[2] * width * width;
        }
        pub fn binTriangles(self: @This(), allocator: std.mem.Allocator, triangles: []Triangle) ![array_size]?*std.ArrayList(*Triangle) {
            var bins: [array_size]?*std.ArrayList(*Triangle) = .{null} ** array_size;
            for (triangles) |*triangle| {
                const triangle_bounds = Bounds.initEncompass(triangle);
                const min: @Vector(4, usize) = @intFromFloat(@floor(self.transformPoint(triangle_bounds.min)));
                const max: @Vector(4, usize) = @intFromFloat(@ceil(self.transformPoint(triangle_bounds.max)));
                for (min[2]..max[2]) |z|
                    for (min[1]..max[1]) |y|
                        for (min[0]..max[0]) |x| {
                            const index = coordToIndex(.{ x, y, z });
                            var bin = if (bins[index]) |bin| bin else blk: {
                                var bin = std.ArrayList(*Triangle).init(allocator);
                                bins[index] = &bin;
                                break :blk &bin;
                            };
                            try bin.append(triangle);
                        };
            }
            return bins;
        }
    };
}
