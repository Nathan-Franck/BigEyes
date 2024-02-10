const std = @import("std");
const subdiv = @import("subdiv");
const MeshHelper = @import("./MeshHelper.zig");
const MeshSpec = @import("./MeshSpec.zig");

pub const Vertex = struct {
    position: [3]f32,
    color: [3]f32,
    normal: [3]f32,
};

pub const Mesh = struct {
    label: []const u8,
    vertices: []Vertex,
    indices: []u32,
};

const hexColors = [_][3]f32{
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 1.0 },
    .{ 1.0, 1.0, 0.0 },
    .{ 1.0, 0.0, 1.0 },
    .{ 0.0, 1.0, 1.0 },
};

pub fn getMeshes(allocator: std.mem.Allocator) !std.ArrayList(Mesh) {
    const json_data = @embedFile("content/Cat.blend.json");
    const mesh_input_data = std.json.parseFromSlice(MeshSpec, allocator, json_data, .{}) catch |err| {
        std.log.err("Failed to parse JSON: {}", .{err});
        return err;
    };
    var meshes = std.ArrayList(Mesh).init(allocator);
    const perform_subdiv_pass = false;
    for (mesh_input_data.value.meshes) |input_data| {
        const flipped_vertices = MeshHelper.flipYZ(allocator, input_data.vertices);
        try meshes.append(mesh: {
            if (!perform_subdiv_pass) {
                break :mesh .{
                    .label = input_data.name,
                    .vertices = vertices: {
                        const normals = MeshHelper.Polygon(.Face).calculateNormals(allocator, flipped_vertices, input_data.polygons);
                        var vertices = std.ArrayList(Vertex).init(allocator);
                        for (flipped_vertices, 0..) |point, i| {
                            try vertices.append(Vertex{
                                .position = @as([4]f32, point)[0..3].*,
                                .color = hexColors[i % hexColors.len],
                                .normal = @as([4]f32, normals[i])[0..3].*,
                            });
                        }
                        break :vertices vertices.items;
                    },
                    .indices = MeshHelper.Polygon(.Face).toTriangles(allocator, input_data.polygons),
                };
            } else {
                var result = try subdiv.Polygon(.Face).cmcSubdiv(allocator, flipped_vertices, input_data.polygons);
                var subdiv_count: u32 = 1;
                while (subdiv_count < 3) {
                    result = try subdiv.Polygon(.Quad).cmcSubdiv(allocator, result.points, result.quads);
                    subdiv_count += 1;
                }
                const vertices = vertices: {
                    const normals = MeshHelper.Polygon(.Quad).calculateNormals(allocator, result.points, result.quads);
                    var vertices = std.ArrayList(Vertex).init(allocator);
                    for (result.points, 0..) |point, i| {
                        try vertices.append(Vertex{
                            .position = @as([4]f32, point)[0..3].*,
                            .color = hexColors[i % hexColors.len],
                            .normal = @as([4]f32, normals[i])[0..3].*,
                        });
                    }
                    break :vertices vertices.items;
                };
                break :mesh .{
                    .label = input_data.name,
                    .vertices = vertices,
                    .indices = MeshHelper.Polygon(.Quad).toTriangles(allocator, result.quads),
                };
            }
        });
    }
    return meshes;
}
