const mesh_helper = @import("./mesh_helper.zig");
const zmath = @import("zmath");
const Vec4 = zmath.Vec;
const Mat = zmath.Mat;

pub const Armature = struct {
    bones: []const struct {
        name: []const u8,
        parent: ?[]const u8,
        rest: struct {
            position: Vec4,
            rotation: Vec4,
            scale: Vec4,
        },
    },
    animation: []const struct {
        frame: u32,
        bones: []const struct {
            position: Vec4,
            rotation: Vec4,
            scale: Vec4,
        },
    },
};

framerate: u32,
nodes: []const struct {
    name: []const u8,
    type: []const u8,
    parent: ?[]const u8,
    position: Vec4,
    rotation: Vec4,
    scale: Vec4,
    mesh: ?struct {
        polygons: []const mesh_helper.Face,
        vertices: []const u8, // hexidecimal-encoding of Point type
        bone_indices: []const i8,
    } = null,
    armature: ?Armature = null,
},
