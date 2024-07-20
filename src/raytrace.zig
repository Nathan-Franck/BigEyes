const zm = @import("zmath/main.zig");

pub const Triangle = struct {
    a: zm.Vec,
    b: zm.Vec,
    c: zm.Vec,
};
pub const Ray = struct {
    position: zm.Vec,
    normal: zm.Vec,
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
