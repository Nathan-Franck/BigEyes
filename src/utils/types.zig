const std = @import("std");

const zm = @import("zmath");

const forest = @import("../utils.zig").forest;
const Vec2 = @import("../utils.zig").Vec2;
const Vec4 = @import("../utils.zig").Vec4;
const Image = @import("../utils.zig").Image;
const mesh_helper = @import("../utils.zig").mesh_helper;
const raytrace = @import("../utils.zig").raytrace;
const subdiv = @import("../utils.zig").subdiv;
const tree = @import("../utils.zig").tree;
const Armature = @import("../utils.zig").BlendMeshSpec.Armature;

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

pub const Input = struct {
    mouse_delta: Vec4,
    movement: struct {
        left: ?u64,
        right: ?u64,
        forward: ?u64,
        backward: ?u64,
    },
};

pub const SelectedCamera = enum {
    orbit,
    first_person,
};

pub const PlayerSettings = struct {
    movement_speed: f32,
    look_speed: f32,
};

pub const OrbitCamera = struct {
    position: zm.Vec,
    rotation: zm.Vec,
    track_distance: f32,
};

pub const Player = struct {
    position: Vec4,
    euler_rotation: Vec4,
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
