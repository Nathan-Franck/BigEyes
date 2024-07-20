const zm = @import("zmath/main.zig");
const std = @import("std");
const Vec = zm.Vec;

pub const Triangle = struct {
    a: zm.Vec,
    b: zm.Vec,
    c: zm.Vec,
};

pub const Ray = struct {
    position: zm.Vec,
    normal: zm.Vec,
};

pub const Bounds = struct {
    min: Vec,
    max: Vec,
};

const epsilon = 0.00001;

pub fn dot(a: zm.Vec, b: zm.Vec) f32 {
    const mult = a * b;
    return mult[0] + mult[1] + mult[2];
}

pub fn rayTriangleIntersection(ray: Ray, triangle: Triangle) ?struct { distance: f32 } {
    const edge1 = triangle.b - triangle.a;
    const edge2 = triangle.c - triangle.a;
    const h = zm.cross3(ray.normal, edge2);
    const a = dot(edge1, h);
    if (a > -epsilon and a < epsilon) {
        return null;
    }
    const f = 1.0 / a;
    const s = ray.position - triangle.a;
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
        .a = Vec{ 0, 0, 0, 0 },
        .b = Vec{ 1, 0, 0, 0 },
        .c = Vec{ 0, 1, 0, 0 },
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
    std.debug.print("tmin: {any}, tmax: {any}\n", .{ tmin, tmax });
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

pub const GridTraversal = struct {
    current: Vec,
    step: Vec,
    tDelta: Vec,
    tMax: Vec,
    end: Vec,

    pub fn init(start: Vec, end: Vec) GridTraversal {
        const dir = end - start;

        const step = @select(f32, dir > @as(Vec, @splat(0)), @as(Vec, @splat(1)), @as(Vec, @splat(-1)));

        const tDelta = @select(f32, dir != @as(Vec, @splat(0)), @abs(@as(Vec, @splat(1)) / dir), @as(Vec, @splat(std.math.inf(f32))));

        const startFloor = @floor(start);
        const tMax = @select(f32, step > @as(Vec, @splat(0)), (startFloor + @as(Vec, @splat(1)) - start) * tDelta, (start - startFloor) * tDelta);

        return GridTraversal{
            .current = @floor(start),
            .step = step,
            .tDelta = tDelta,
            .tMax = tMax,
            .end = end,
        };
    }

    pub fn next(self: *GridTraversal) ?Vec {
        if (@reduce(.And, @abs(self.current - @floor(self.end)) < @as(Vec, @splat(epsilon)))) {
            return null;
        }

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
        const update_x = @select(f32, mask_x, @as(Vec, @Vector(4, f32){ 1, 0, 0, 0 }), @as(Vec, @splat(0)));
        const update_y = @select(f32, mask_y, @as(Vec, @Vector(4, f32){ 0, 1, 0, 0 }), @as(Vec, @splat(0)));
        const update_z = @select(f32, mask_z, @as(Vec, @Vector(4, f32){ 0, 0, 1, 0 }), @as(Vec, @splat(0)));

        const update = update_x + update_y + update_z;

        self.current += self.step * update;
        self.tMax += self.tDelta * update;

        return result;
    }
};
test "Grid Traversal Iterator" {
    const start = Vec{ 0, 0, 0, 0 };
    const end = Vec{ 5, 3, 2, 0 };
    var traversal = GridTraversal.init(start, end);

    while (traversal.next()) |cell| {
        std.debug.print("Visiting cell: ({d}, {d}, {d})\n", .{ cell[0], cell[1], cell[2] });
    }
}
