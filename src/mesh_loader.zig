const std = @import("std");

const zmath = @import("zmath");

const BlendAnimatedMeshSpec = @import("./BlendAnimatedMeshSpec.zig");
const BlendMeshSpec = @import("./BlendMeshSpec.zig");
const mesh_helper = @import("./mesh_helper.zig");
const subdiv = @import("./subdiv.zig");
const game = @import("game/game.zig").game;
const debugPrint = @import("game/game.zig").debugPrint;
const Vec4 = @import("forest.zig").Vec4;

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

pub fn loadModelsFromBlends(
    arena: std.mem.Allocator,
    comptime blend_inputs: []const struct { model_name: []const u8, subdiv_level: u8 = 0 },
) !struct {
    models: std.ArrayList(game.types.GameModel),
    model_transforms: std.StringHashMap(zmath.Mat),
} {
    var models = std.ArrayList(game.types.GameModel).init(arena);
    var model_transforms = std.StringHashMap(zmath.Mat).init(arena);
    var armatures = std.StringHashMap(BlendMeshSpec.Armature).init(arena);
    inline for (blend_inputs) |blend_input| {
        const json_data = @embedFile(std.fmt.comptimePrint("content/{s}.blend.json", .{blend_input.model_name}));
        const blend = try loadBlendFromJson(arena, json_data);
        for (blend.nodes) |node| {
            if (node.armature) |armature| {
                try armatures.put(node.name, armature);
            }
            if (node.mesh) |mesh| {
                const positions = mesh_helper.decodeVertexDataFromHexidecimal(arena, mesh.vertices);
                const label = try std.mem.concat(arena, u8, &.{ blend_input.model_name, "_", node.name });
                if (blend_input.subdiv_level > 0) {
                    const faces = mesh.polygons;
                    var subdiv_result = try subdiv.Polygon(.Face).cmcSubdiv(arena, positions, faces);
                    var quads_per_subdiv = std.ArrayList([]const game.types.Quad).init(arena);
                    try quads_per_subdiv.append(subdiv_result.quads);
                    for (0..blend_input.subdiv_level - 1) |_| {
                        subdiv_result = try subdiv.Polygon(.Quad).cmcSubdiv(arena, subdiv_result.points, subdiv_result.quads);
                        try quads_per_subdiv.append(subdiv_result.quads);
                    }
                    const model: game.types.GameModel = .{
                        .label = label,
                        .meshes = try arena.dupe(game.types.GameMesh, &.{game.types.GameMesh{ .subdiv = .{
                            .armature = armatures.get(node.parent.?).?,
                            .top_indices = mesh_helper.Polygon(.Quad).toTriangleIndices(arena, subdiv_result.quads),
                            .base_positions = positions,
                            .base_bone_indices = mesh.bone_indices,
                            .base_faces = mesh.polygons,
                            .quads_per_subdiv = quads_per_subdiv.items,
                        } }}),
                    };
                    try models.append(model);
                } else {
                    const model: game.types.GameModel = .{
                        .label = label,
                        .meshes = try arena.dupe(game.types.GameMesh, &.{.{ .greybox = .{
                            .indices = mesh_helper.Polygon(.Face).toTriangleIndices(arena, mesh.polygons),

                            .normal = mesh_helper.Polygon(.Face).calculateNormals(arena, positions, mesh.polygons),
                            .position = positions,
                        } }}),
                    };
                    try models.append(model);
                }
                try model_transforms.put(
                    label,
                    translationRotationScaleToMatrix(
                        node.position,
                        node.rotation,
                        node.scale,
                    ),
                );
            }
        }
    }
    return .{
        .models = models,
        .model_transforms = model_transforms,
    };
}

pub fn translationRotationScaleToMatrix(translation: Vec4, rotation: Vec4, scale: Vec4) zmath.Mat {
    const t = zmath.translationV(translation);
    const r = zmath.matFromQuat(rotation);
    const s = zmath.scalingV(scale);
    return zmath.mul(t, zmath.mul(r, s));
}

pub fn loadBlendFromJson(allocator: std.mem.Allocator, json_data: []const u8) !BlendMeshSpec {
    var scanner = std.json.Scanner.initCompleteInput(allocator, json_data);
    defer scanner.deinit();

    var diagnostics = std.json.Diagnostics{};
    scanner.enableDiagnostics(&diagnostics);

    const mesh_input_data = std.json.parseFromTokenSource(BlendMeshSpec, allocator, &scanner, .{}) catch |err| {
        debugPrint("Something in here isn't parsing right: {s}\nError: {any}\n", .{
            json_data[0..@intCast(diagnostics.getByteOffset())],
            err,
        });
        return err;
    };

    return mesh_input_data.value;
}

pub fn getAnimatedMeshesFromJSON(allocator: std.mem.Allocator, json_data: []const u8) !std.ArrayList(Node) {
    const mesh_input_data = try std.json.parseFromSlice(BlendAnimatedMeshSpec, allocator, json_data, .{});
    var meshes = std.ArrayList(Node).init(allocator);
    for (mesh_input_data.value.meshes) |input_data| {
        try meshes.append(.{
            .name = input_data.name,
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
