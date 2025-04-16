const std = @import("std");

const zm = @import("zmath");
const utils = @import("../utils.zig");

const forest = utils.forest;
const Vec2 = utils.Vec2;
const Vec4 = utils.Vec4;
const Image = utils.Image;
const mesh_helper = utils.mesh_helper;
const raytrace = utils.raytrace;
const subdiv = utils.subdiv;
const tree = utils.tree;
const Armature = utils.BlendMeshSpec.Armature;
const vec_math = utils.vec_math;

pub const Point = @Vector(4, f32);
pub const Face = []const u32;
pub const Quad = [4]u32;

pub const GreyboxMesh = struct {
    color: Vec4,
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

pub const ScreenspaceMesh = struct {
    indices: []const u32,
    uvs: []const Vec2,
    normals: []const Vec4,
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

pub const DirectionalLight = struct {
    view: zm.Mat,
    projection: zm.Mat,
    view_projection: zm.Mat,
    direction: Vec4,
};

pub const PixelPoint = struct { x: u32, y: u32 };

pub const Timing = struct {
    delta: f32,
    seconds_since_start: f32,
};

pub const Input = struct {
    escape: bool,
    mouse: struct {
        delta: Vec4,
        left_click: bool,
        right_click: bool,
        middle_click: bool,
    },
    movement: struct {
        left: bool,
        right: bool,
        forward: bool,
        backward: bool,
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

pub const Instance = struct {
    position: Vec4,
    rotation: Vec4,
    scale: Vec4,

    pub fn toMatrix(self: @This()) zm.Mat {
        return vec_math.translationRotationScaleToMatrix(
            self.position,
            self.rotation,
            self.scale,
        );
    }
};

pub const ModelInstances = struct {
    label: []const u8,
    instances: []const Instance,
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
