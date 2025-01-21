const std = @import("std");

const zm = @import("zmath");

const forest = @import("../forest.zig");
const Vec2 = forest.Vec2;
const Vec4 = forest.Vec4;
const Image = @import("../Image.zig");
const mesh_helper = @import("../mesh_helper.zig");
const raytrace = @import("../raytrace.zig");
const subdiv = @import("../subdiv.zig");
const tree = @import("../tree.zig");
const Armature = @import("../BlendMeshSpec.zig").Armature;

pub const Point = @Vector(4, f32);
pub const Face = []const u32;
pub const Quad = [4]u32;

pub const GreyboxMesh = struct {
    indices: []const u32,
    position: []const Vec4,
    normal: []const Vec4,
};

pub const SubdivBoneMesh = struct {
    top_indices: []const u32,
    base_positions: []const Vec4,
    base_bone_indices: []const i8,
    base_faces: []const Face,
    quads_per_subdiv: []const []const Quad,
    armature: Armature,
};

pub const TextureMesh = struct {
    diffuse_alpha: Image.Processed,
    indices: []const u32,
    position: []const Vec4,
    uv: []const Vec2,
    normal: []const Vec4,
};

pub const GameMesh = union(enum) {
    greybox: GreyboxMesh,
    subdiv: SubdivBoneMesh,
    textured: TextureMesh,
};

pub const SubdivAnimationMesh = struct {
    polygons: []const subdiv.Face,
    quads_by_subdiv: []const []const subdiv.Quad,
    indices: []const u32,
    frames: []const []const zm.Vec,
    frame_rate: u32,
};

pub const QuadMeshHelper = mesh_helper.Polygon(.Quad);

pub const PixelPoint = struct { x: u32, y: u32 };

pub const OrbitCamera = struct {
    position: zm.Vec,
    rotation: zm.Vec,
    track_distance: f32,
};

pub const TreeMesh = struct {
    label: []const u8,
    bounds: raytrace.Bounds,
    skeleton: tree.Skeleton,
    leaf_mesh: tree.Mesh,
    bark_mesh: tree.Mesh,
};

pub const ModelInstances = struct {
    label: []const u8,
    positions: []const Vec4,
    rotations: []const Vec4,
    scales: []const Vec4,
};

pub const GameModel = struct {
    label: []const u8,
    meshes: []const GameMesh,
};

pub const ProcessedCubeMap = struct {
    nx: Image.Processed,
    ny: Image.Processed,
    nz: Image.Processed,
    px: Image.Processed,
    py: Image.Processed,
    pz: Image.Processed,
};

pub const Resources = struct {
    skybox: ProcessedCubeMap,
    cutout_leaf: Image.Processed,
    trees: []const TreeMesh,
    models: []const GameModel,
    model_transforms: std.StringHashMap(zm.Mat),
};
