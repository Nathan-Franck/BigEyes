const std = @import("std");
const subdiv = @import("./subdiv.zig");
const mesh_helper = @import("./mesh_helper.zig");
const BlendMeshSpec = @import("./BlendMeshSpec.zig");
const BlendAnimatedMeshSpec = @import("./BlendAnimatedMeshSpec.zig");

pub const Vertex = struct {
    position: [3]f32,
    color: [3]f32,
    normal: [3]f32,
};

pub const Node = struct {
    name: []const u8,
    type: []const u8,
    parent: ?[]const u8,
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
    mesh: ?struct {
        vertices: []Vertex,
        indices: []u32,
    },
};

const hexColors = [_][3]f32{
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 1.0 },
    .{ 1.0, 1.0, 0.0 },
    .{ 1.0, 0.0, 1.0 },
    .{ 0.0, 1.0, 1.0 },
};

pub fn getNodesFromJSON(allocator: std.mem.Allocator, json_data: []const u8) ![]const Node {
    var scanner = std.json.Scanner.initCompleteInput(allocator, json_data);
    defer scanner.deinit();

    var diagnostics = std.json.Diagnostics{};
    scanner.enableDiagnostics(&diagnostics);

    const mesh_input_data = std.json.parseFromTokenSource(BlendMeshSpec, allocator, &scanner, .{}) catch |err| {
        // const wasm_entry = @import("./wasm_entry.zig");
        // wasm_entry.dumpDebugLogFmt("Something in here isn't parsing right: {s}\nError: {any}\n", .{
        //     json_data[0..@intCast(diagnostics.getByteOffset())],
        //     err,
        // });
        return err;
    };

    var meshes = std.ArrayList(Node).init(allocator);
    for (mesh_input_data.value.nodes) |node| {
        try meshes.append(.{
            .name = node.name,
            .type = node.type,
            .parent = node.parent,
            .position = node.position,
            .rotation = node.rotation,
            .scale = node.scale,
            .mesh = if (node.mesh) |mesh| .{
                .vertices = vertices: {
                    const vertices = mesh_helper.decodeVertexDataFromHexidecimal(allocator, mesh.vertices);
                    const normals = mesh_helper.Polygon(.Face).calculateNormals(allocator, vertices, mesh.polygons);
                    var result = std.ArrayList(Vertex).init(allocator);
                    for (vertices, 0..) |point, i| {
                        try result.append(Vertex{
                            .position = @as([4]f32, point)[0..3].*,
                            .color = hexColors[i % hexColors.len],
                            .normal = @as([4]f32, normals[i])[0..3].*,
                        });
                    }
                    break :vertices result.items;
                },
                .indices = mesh_helper.Polygon(.Face).toTriangleIndices(allocator, mesh.polygons),
            } else null,
        });
    }
    return meshes.items;
}

pub fn getAnimatedMeshesFromJSON(allocator: std.mem.Allocator, json_data: []const u8) !std.ArrayList(Node) {
    const mesh_input_data = try std.json.parseFromSlice(BlendAnimatedMeshSpec, allocator, json_data, .{});
    var meshes = std.ArrayList(Node).init(allocator);
    for (mesh_input_data.value.meshes) |input_data| {
        try meshes.append(.{
            .label = input_data.name,
            .vertices = vertices: {
                const normals = mesh_helper.Polygon(.Face).calculateNormals(allocator, input_data.vertices, input_data.polygons);
                var vertices = std.ArrayList(Vertex).init(allocator);
                for (input_data.vertices, 0..) |point, i| {
                    try vertices.append(Vertex{
                        .position = @as([4]f32, point)[0..3].*,
                        .color = hexColors[i % hexColors.len],
                        .normal = @as([4]f32, normals[i])[0..3].*,
                    });
                }
                break :vertices vertices.items;
            },
            .indices = mesh_helper.Polygon(.Face).toTriangles(allocator, input_data.polygons),
        });
    }
    return meshes;
}
