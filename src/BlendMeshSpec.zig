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
    },
},