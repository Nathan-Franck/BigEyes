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
        return @select(
            f32,
            @Vector(4, bool){ true, true, true, false },
            self.max - self.min,
            Vec{ 1, 1, 1, 1 },
        );
    }
    pub fn scale(self: Bounds, factor: f32) Bounds {
        return Bounds{ .min = self.min * factor, .max = self.max * factor };
    }
    pub fn toBoundsSpace(self: Bounds, point: Vec) Vec {
        return (point - self.min) / self.size();
    }
};

const epsilon = 0.00001;

pub inline fn dot(a: zm.Vec, b: zm.Vec) f32 {
    return @reduce(.Add, a * b);
}

pub fn rayTriangleIntersection(ray: Ray, triangle: Triangle) f32 {
    const edge1 = triangle[1] - triangle[0];
    const edge2 = triangle[2] - triangle[0];
    const h = zm.cross3(ray.normal, edge2);
    const a = dot(edge1, h);
    if (a > -epsilon and a < epsilon) {
        return std.math.inf(f32);
    }
    const f = 1.0 / a;
    const s = ray.position - triangle[0];
    const u = f * dot(s, h);
    if (u < 0.0 or u > 1.0) {
        return std.math.inf(f32);
    }
    const q = zm.cross3(s, edge1);
    const v = f * dot(ray.normal, q);
    if (v < 0.0 or u + v > 1.0) {
        return std.math.inf(f32);
    }
    const t = f * dot(edge2, q);
    if (t > epsilon) {
        return t;
    }
    return std.math.inf(f32);
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
    try std.testing.expectEqualDeep(10.0, result);
}

pub fn rayBoundsIntersection(ray: Ray, bounds: Bounds) ?struct { entry_distance: f32, exit_distance: f32 } {
    const t1 = (bounds.min - ray.position) / ray.normal;
    const t2 = (bounds.max - ray.position) / ray.normal;
    const tmin: @Vector(3, f32) = @as([4]f32, @max(
        @min(t1, t2),
        @as(Vec, @splat(0)),
    ))[0..3].*;
    const tmax: @Vector(3, f32) = @as([4]f32, @min(
        @max(t1, t2),
        @as(Vec, @splat(std.math.inf(f32))),
    ))[0..3].*;
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

const GridCoord = @Vector(3, usize);
const Coord = @Vector(4, i32);

pub const GridTriangleTraversal = struct {
    current: Coord,
    step: Coord,
    tDelta: Vec,
    tMax: Vec,
    end: Coord,

    pub fn init(uncapped_positions: [3]Vec) GridLineTraversal {
        const capped_positions: [3]Vec = undefined;
        for (uncapped_positions, 0..) |uncapped_position, i|
            capped_positions[i] = @max(uncapped_position, @as(Vec, @splat(0)));

        const dir = end - start;

        const step: Coord = @select(
            i32,
            dir > @as(Vec, @splat(0)),
            @as(Vec, @splat(1)),
            @as(Vec, @splat(-1)),
        );

        const tDelta = @abs(@as(Vec, @splat(1)) / dir);

        const startFloor = @floor(start);
        const tMax = @select(
            f32,
            step < @as(Coord, @splat(0)),
            (start - startFloor) * tDelta,
            (startFloor + @as(Vec, @splat(1)) - start) * tDelta,
        );

        return GridLineTraversal{
            .current = @intFromFloat(@floor(start)),
            .end = @intFromFloat(@floor(end)),
            .step = step,
            .tDelta = tDelta,
            .tMax = @select(
                f32,
                dir != @as(Vec, @splat(0)),
                tMax,
                comptime @as(Vec, @splat(std.math.inf(f32))),
            ),
        };
    }

    pub noinline fn next(self: *GridTriangleTraversal) ?GridCoord {
        if (@reduce(.And, (self.current - self.end) * self.step >= @as(Coord, @splat(0)))) {
            return null;
        }

        const x_smallest = self.tMax[0] <= self.tMax[1] and self.tMax[0] <= self.tMax[2];
        const y_smallest = self.tMax[1] <= self.tMax[0] and self.tMax[1] <= self.tMax[2];
        const z_smallest = self.tMax[2] <= self.tMax[0] and self.tMax[2] <= self.tMax[1];
        const smallest = @Vector(4, bool){ x_smallest, y_smallest, z_smallest, false };

        self.tMax = @select(
            f32,
            smallest,
            self.tMax + self.tDelta,
            self.tMax,
        );

        const result: GridCoord = @as([4]usize, @as(
            @Vector(4, usize),
            @intCast(self.current),
        ))[0..3].*;

        self.current += @select(
            i32,
            smallest,
            self.step,
            Coord{ 0, 0, 0, 0 },
        );

        return result;
    }
};

pub const GridLineTraversal = struct {
    current: Coord,
    step: Coord,
    tDelta: Vec,
    tMax: Vec,
    end: Coord,

    pub fn init(uncapped_start: Vec, uncapped_end: Vec) GridLineTraversal {
        const start = @max(uncapped_start, @as(Vec, @splat(0)));
        const end = @max(uncapped_end, @as(Vec, @splat(0)));
        const dir = end - start;

        const step: Coord = @select(
            i32,
            dir > @as(Vec, @splat(0)),
            @as(Vec, @splat(1)),
            @as(Vec, @splat(-1)),
        );

        const tDelta = @abs(@as(Vec, @splat(1)) / dir);

        const startFloor = @floor(start);
        const tMax = @select(
            f32,
            step < @as(Coord, @splat(0)),
            (start - startFloor) * tDelta,
            (startFloor + @as(Vec, @splat(1)) - start) * tDelta,
        );

        return GridLineTraversal{
            .current = @intFromFloat(@floor(start)),
            .end = @intFromFloat(@floor(end)),
            .step = step,
            .tDelta = tDelta,
            .tMax = @select(
                f32,
                dir != @as(Vec, @splat(0)),
                tMax,
                comptime @as(Vec, @splat(std.math.inf(f32))),
            ),
        };
    }

    pub noinline fn next(self: *GridLineTraversal) ?GridCoord {
        if (@reduce(.And, (self.current - self.end) * self.step >= @as(Coord, @splat(0)))) {
            return null;
        }

        const x_smallest = self.tMax[0] <= self.tMax[1] and self.tMax[0] <= self.tMax[2];
        const y_smallest = self.tMax[1] <= self.tMax[0] and self.tMax[1] <= self.tMax[2];
        const z_smallest = self.tMax[2] <= self.tMax[0] and self.tMax[2] <= self.tMax[1];
        const smallest = @Vector(4, bool){ x_smallest, y_smallest, z_smallest, false };

        self.tMax = @select(
            f32,
            smallest,
            self.tMax + self.tDelta,
            self.tMax,
        );

        const result: GridCoord = @as([4]usize, @as(
            @Vector(4, usize),
            @intCast(self.current),
        ))[0..3].*;

        self.current += @select(
            i32,
            smallest,
            self.step,
            Coord{ 0, 0, 0, 0 },
        );

        return result;
    }
};

test "Grid Traversal Iterator Straight Line" {
    const start = Vec{ 0.5, 0.5, 0.5, 0 };
    const end = Vec{ 5.0, 0.5, 0.5, 0 };
    var traversal = GridLineTraversal.init(start, end);

    var steps: u32 = 0;
    while (traversal.next()) |_| {
        steps += 1;
        if (steps > 10) {
            break;
        }
    }

    try std.testing.expectEqual(traversal.current, Coord{ 5, 0, 0, 0 });
}

test "Grid Traversal Iterator Diagonal Line" {
    const start = Vec{ 0, 0, 0, 0 };
    const end = Vec{ 6, 2, 0, 0 };
    var traversal = GridLineTraversal.init(start, end);

    var steps: u32 = 0;
    while (traversal.next()) |_| {
        steps += 1;
        if (steps > 10) {
            break;
        }
    }

    try std.testing.expectEqual(traversal.current, Coord{ 6, 2, 0, 0 });
}
test "Grid Traversal Iterator Diagonal Line (Backwards)" {
    const start = Vec{ 6, 2, 0, 0 };
    const end = Vec{ 0, 0, 0, 0 };
    var traversal = GridLineTraversal.init(start, end);

    var steps: u32 = 0;
    while (traversal.next()) |_| {
        steps += 1;
        if (steps > 10) {
            break;
        }
    }

    try std.testing.expectEqual(traversal.current, Coord{ 0, 0, 0, 0 });
}

test "Triangle in a Bin" {
    const my_triangle = Triangle{
        .{ 1, 1, 2, 0 },
        .{ 2, 1, 2, 0 },
        .{ 1, 2, 3, 0 },
    };
    const grid_bounds = GridBounds(16){
        // .bounds = .{ .min = .{ 0, 0, 0, 0 }, .max = .{ 4, 4, 4, 0 } },
        .bounds = Bounds.initEncompass(&my_triangle),
    };
    const allocator = std.heap.page_allocator;
    const triangles = &.{my_triangle};
    const bins = try grid_bounds.binTriangles(allocator, triangles);

    const ray: Ray = .{
        .position = .{ 1.3, 1.3, 0, 0 },
        .normal = .{ 0, 0, 1.0, 0 },
    };

    const result_triangle = find_triangle: {
        const bounding_box_test = rayBoundsIntersection(ray, grid_bounds.bounds);
        if (bounding_box_test) |bounding_box_hit| {
            const start = grid_bounds.transformPoint(ray.position);
            const end = grid_bounds.transformPoint(
                ray.position + ray.normal * @as(zm.Vec, @splat(bounding_box_hit.exit_distance)),
            );
            var traversal_iterator = GridLineTraversal.init(start, end);
            while (traversal_iterator.next()) |cell_coord| {
                const cell_index = GridBounds(16).coordToIndex(cell_coord);
                const cell = bins[cell_index];
                if (cell) |cell_triangles| {
                    for (cell_triangles.items) |triangle| {
                        const hit_distance = rayTriangleIntersection(ray, triangle.*);
                        if (hit_distance < 100)
                            break :find_triangle triangle;
                    }
                }
            }
        }
        unreachable;
    };

    _ = result_triangle;
}

pub fn GridBounds(grid_width: usize) type {
    return struct {
        pub const width = grid_width;
        pub const array_size = grid_width * grid_width * grid_width;
        bounds: Bounds,
        pub fn transformPoint(self: @This(), arg: zm.Vec) zm.Vec {
            return self.bounds.toBoundsSpace(arg) * @as(zm.Vec, @splat(width));
        }
        pub fn coordToIndex(coord: GridCoord) usize {
            return coord[0] + coord[1] * width + coord[2] * width * width;
        }

        // const RayTriangleBin = struct {
        //     triangles: std.ArrayList(*const Triangle),
        //     rays: std.ArrayList(*const Ray),
        // };

        // pub noinline fn binRaysAndTriangles(
        //     self: @This(),
        //     allocator: std.mem.Allocator,
        //     triangles: []const Triangle,
        //     rays: []const Ray,
        // ) !std.ArrayHashMap(GridCoord, *RayTriangleBin) {
        //     _ = self; // autofix
        //     _ = triangles; // autofix
        //     _ = rays; // autofix
        //     var bins = std.ArrayHashMap(GridCoord, *RayTriangleBin).init(allocator);

        //     _ = bins; // autofix
        // }

        pub noinline fn binTriangles(
            self: @This(),
            allocator: std.mem.Allocator,
            triangles: []const Triangle,
        ) ![]const ?*std.ArrayList(*const Triangle) {
            var bins = try allocator.alloc(?*std.ArrayList(*const Triangle), array_size);
            for (0..bins.len) |i|
                bins[i] = null;

            for (triangles) |*triangle| {
                const triangle_bounds = Bounds.initEncompass(triangle);
                const min: @Vector(4, usize) = @intFromFloat(@floor(self.transformPoint(triangle_bounds.min)));
                const max = @min(
                    @as(@Vector(4, usize), @intFromFloat(@floor(self.transformPoint(triangle_bounds.max)))) +
                        @as(@Vector(4, usize), @splat(1)),
                    @as(@Vector(4, usize), @splat(width - 1)),
                );

                for (min[2]..max[2]) |z|
                    for (min[1]..max[1]) |y|
                        for (min[0]..max[0]) |x| {
                            const index = coordToIndex(.{ x, y, z });
                            const bin = if (bins[index]) |bin| bin else blk: {
                                const T = std.ArrayList(*const Triangle);
                                const bin = &(try allocator.dupe(T, &.{T.init(allocator)}))[0];
                                bins[index] = bin;
                                break :blk bin;
                            };
                            try bin.append(triangle);
                        };
            }
            return bins;
        }
        pub fn voxelizeTriangles(self: @This(), triangles: []Triangle) [array_size]bool {
            var bins: [array_size]bool = .{false} ** array_size;
            for (triangles) |*triangle| {
                const triangle_bounds = Bounds.initEncompass(triangle);
                const min: @Vector(4, usize) = @intFromFloat(@floor(self.transformPoint(triangle_bounds.min)));
                const max: @Vector(4, usize) = @intFromFloat(@ceil(self.transformPoint(triangle_bounds.max)));
                for (min[2]..max[2] + 1) |z|
                    for (min[1]..max[1] + 1) |y|
                        for (min[0]..max[0] + 1) |x| {
                            const index = coordToIndex(.{ x, y, z });
                            bins[index] = true;
                        };
            }
            return bins;
        }
    };
}
