const std = @import("std");
const Vector4 = @Vector(4, f32);
const Vector3 = @Vector(3, f32);

const array_size = 1_000_000;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var stdout = std.io.getStdOut().writer();

    const vec4_array = try allocator.alloc(Vector4, array_size);
    defer allocator.free(vec4_array);

    const vec3_array = try allocator.alloc(Vector3, array_size);
    defer allocator.free(vec3_array);

    // Initialize arrays
    for (vec4_array) |*v| {
        v.* = Vector4{ 1.0, 2.0, 3.0, 4.0 };
    }

    for (vec3_array) |*v| {
        v.* = Vector3{ 1.0, 2.0, 3.0 };
    }

    var vec4_duration: i128 = 0;
    var vec3_duration: i128 = 0;
    for (0..10) |_| {

        // Measure performance for Vector4
        var start_time = std.time.nanoTimestamp();
        for (vec4_array) |*v| {
            v.* = v.* + Vector4{ 1.0, 1.0, 1.0, 1.0 };
        }
        vec4_duration += std.time.nanoTimestamp() - start_time;

        // Measure performance for Vector3
        start_time = std.time.nanoTimestamp();
        for (vec3_array) |*v| {
            v.* = v.* + Vector3{ 1.0, 1.0, 1.0 };
        }
        vec3_duration += std.time.nanoTimestamp() - start_time;
    }

    // Print results
    try stdout.print("Vector4 operation time: {d} ns\n", .{vec4_duration});
    try stdout.print("Vector3 operation time: {d} ns\n", .{vec3_duration});
}
