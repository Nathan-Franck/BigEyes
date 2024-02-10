pub const Point = @Vector(4, f32);
pub const Face = []const u32;
pub const Quad = [4]u32;

actions: []const struct {
    name: []const u8,
    fcurves: []const struct {
        data_path: []const u8,
        array_index: u32,
        keyframes: []const [2]f32,
    },
},
nodes: []const struct {
    name: []const u8,
    type: []const u8,
    parent: ?[]const u8,
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
},
armatures: []const struct {
    name: []const u8,
    bones: []const struct {
        name: []const u8,
        parent: ?[]const u8,
        position: [3]f32,
        rotation: [3]f32,
        scale: [3]f32,
    },
},
meshes: []const struct {
    name: []const u8,
    polygons: []const Face,
    vertices: []const Point,
    shapeKeys: []struct { name: []const u8, vertices: []const Point },
    vertexGroups: []const struct {
        name: []const u8,
        vertices: []const struct { index: u32, weight: f32 },
    },
},
