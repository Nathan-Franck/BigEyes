const Image = @import("../Image.zig");
const mesh_helper = @import("../mesh_helper.zig");
const subdiv = @import("../subdiv.zig");
const tree = @import("../tree.zig");
const zm = @import("../zmath/main.zig");

pub const GreyboxMesh = struct {
    label: []const u8,
    indices: []const u32,
    position: []const f32,
    normal: []const f32,
};

pub const TextureMesh = struct {
    label: []const u8,
    diffuse_alpha: Image.Processed,
    indices: []const u32,
    position: []const f32,
    uv: []const f32,
    normal: []const f32,
};

pub const GameMesh = union(enum) {
    greybox: GreyboxMesh,
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
    skeleton: tree.Skeleton,
    leaf_mesh: tree.Mesh,
    bark_mesh: tree.Mesh,
};

pub const Resources = struct {
    skybox: []Image.Processed,
    cutout_leaf: Image.Processed,
    tree: TreeMesh,
};

pub const Settings = struct {
    orbit_speed: f32,
    subdiv_level: u8,
    should_raytrace: bool,
    render_resolution: PixelPoint,
};
