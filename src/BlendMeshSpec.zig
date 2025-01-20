const mesh_helper = @import("./mesh_helper.zig");

framerate: u32,
nodes: []const struct {
    name: []const u8,
    type: []const u8,
    parent: ?[]const u8,
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
    mesh: ?struct {
        polygons: []const mesh_helper.Face,
        vertices: []const u8, // hexidecimal-encoding of Point type
    } = null,
    armature: ?struct {
        bones: []const struct {
            name: []const u8,
            parent: ?[]const u8,
            rest_position: [3]f32,
            rest_rotation: [3]f32,
            rest_scale: [3]f32,
        },
        animation: []const struct {
            frame: u32,
            bones: []const struct {
                position: [3]f32,
                rotation: [3]f32,
                scale: [3]f32,
            },
        },
    } = null,
},
