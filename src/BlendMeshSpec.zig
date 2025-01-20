const mesh_helper = @import("./mesh_helper.zig");
const Vec4 = @import("./forest.zig").Vec4;

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
    armature: ?struct {
        bones: []const struct {
            name: []const u8,
            parent: ?[]const u8,
            rest_position: Vec4,
            rest_rotation: Vec4,
            rest_scale: Vec4,
        },
        animation: []const struct {
            frame: u32,
            bones: []const struct {
                position: Vec4,
                rotation: Vec4,
                scale: Vec4,
            },
        },
    } = null,
},
