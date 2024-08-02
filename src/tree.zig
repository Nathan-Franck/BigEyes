const std = @import("std");
const math = std.math;
const zm = @import("./zmath/main.zig");
const Allocator = std.mem.Allocator;

pub const Vec4 = @Vector(4, f32);
pub const Quat = Vec4;

fn flattenAngle(unnormalized_angle: f32, rate: f32) f32 {
    var angle = unnormalized_angle;
    if (rate <= 0) {
        return angle;
    }
    while (angle < 0) angle += 360;
    while (angle > 360) angle -= 360;
    const offset: f32 = if (angle > 90.0) 180 else 0;
    return ((angle - offset) *
        (1 - rate) + offset);
}

pub const SmoothCurve = struct {
    y_values: []const f32,
    x_range: [2]f32,

    pub fn sample(self: SmoothCurve, t: f32) f32 {
        const normalized_t = (t - self.x_range[0]) / (self.x_range[1] - self.x_range[0]);
        const clamped_t = std.math.clamp(normalized_t, 0, 1);
        const index_float = clamped_t * @as(f32, @floatFromInt(self.y_values.len - 1));
        const index_low = @as(usize, @intFromFloat(std.math.floor(index_float)));
        const index_high = @as(usize, @intFromFloat(std.math.ceil(index_float)));
        const frac = index_float - @as(f32, @floatFromInt(index_low));
        return self.y_values[index_low] * (1 - frac) + self.y_values[index_high] * frac;
    }
};

pub const DepthDefinition = struct {
    split_amount: f32,
    flatness: f32,
    size: f32,
    height_spread: f32,
    branch_pitch: f32,
    branch_roll: f32,
    height_to_growth: SmoothCurve,
};

pub const Settings = struct {
    start_size: f32,
    start_growth: f32,
    depth_definitions: []const DepthDefinition,
};

pub const MeshSettings = struct {
    thickness: f32,
    leaves: struct {
        split_depth: usize,
        length: f32,
        breadth: f32,
    },
    growth_to_thickness: SmoothCurve,
};

pub const Node = struct {
    size: f32,
    position: Vec4,
    rotation: Quat,
    split_height: f32,
    growth: f32,
    split_depth: usize,
};

pub const GenQueueItem = struct {
    node: Node,
    parent_index: ?usize,
};

pub const Skeleton = struct {
    nodes: std.ArrayList(Node),
    node_to_primary_child_index: std.ArrayList(?usize),
};

pub fn generateStructure(allocator: Allocator, settings: Settings) !Skeleton {
    const start_node = Node{
        .size = settings.start_size,
        .position = zm.loadArr3(.{ 0, 0, 0 }),
        .rotation = Quat{ 0, 0, 0, 1 },
        .split_height = 0,
        .growth = settings.start_growth,
        .split_depth = 0,
    };

    var generation_queue = std.ArrayList(GenQueueItem).init(allocator);

    var nodes = std.ArrayList(Node).init(allocator);
    var node_to_primary_child_index = std.ArrayList(?usize).init(allocator);

    try generation_queue.append(GenQueueItem{ .node = start_node, .parent_index = null });

    while (generation_queue.popOrNull()) |gen_item| {
        const node_index = nodes.items.len;
        try nodes.append(gen_item.node);
        try node_to_primary_child_index.append(null);

        if (gen_item.parent_index) |parent_index| {
            node_to_primary_child_index.items[parent_index] = node_index;
        }

        // Branch spawning
        var current_depth: usize = 0;
        for (settings.depth_definitions) |depth_definition| {
            defer current_depth += 1;

            if (gen_item.node.split_depth < current_depth) {
                const split_amount: usize = @intFromFloat(depth_definition.split_amount * gen_item.node.growth);
                const split_depth = gen_item.node.split_depth + 1;

                // Main branch extension
                {
                    const growth = math.clamp(depth_definition.height_to_growth.sample(0), 0, 1);
                    const forward = zm.rotate(
                        gen_item.node.rotation,
                        zm.loadArr3(.{ 0, 0, gen_item.node.size * gen_item.node.growth }),
                    );
                    try generation_queue.append(GenQueueItem{
                        .node = Node{
                            .position = gen_item.node.position + forward,
                            .rotation = zm.qmul(
                                gen_item.node.rotation,
                                zm.quatFromNormAxisAngle(
                                    zm.loadArr3(.{ 0, 0, 1 }),
                                    depth_definition.branch_roll,
                                ),
                            ),
                            .size = gen_item.node.size * depth_definition.size,
                            .split_height = if (split_depth == 1) 0 else gen_item.node.split_height,
                            .growth = growth,
                            .split_depth = split_depth,
                        },
                        .parent_index = node_index,
                    });
                }

                // Tangential branches
                var split_index: usize = 0;
                while (split_index < split_amount) {
                    defer split_index += 1;

                    const split_height = @as(f32, @floatFromInt(split_index)) / @as(f32, @floatFromInt(split_amount));
                    const growth = math.clamp(depth_definition.height_to_growth.sample(split_height * gen_item.node.growth), 0, 1);
                    try generation_queue.append(GenQueueItem{
                        .node = Node{
                            .position = gen_item.node.position + zm.rotate(gen_item.node.rotation, zm.loadArr3(.{ 0, 0, gen_item.node.size * gen_item.node.growth * (1 - split_height * depth_definition.height_spread) })),
                            .rotation = zm.qmul(
                                gen_item.node.rotation,
                                zm.qmul(
                                    zm.quatFromNormAxisAngle(zm.loadArr3(.{ 0, 0, 1 }), depth_definition.branch_roll +
                                        flattenAngle(@as(f32, @floatFromInt(split_index)) * 6.283 * 0.618, depth_definition.flatness)),
                                    zm.quatFromNormAxisAngle(zm.loadArr3(.{ 0, 1, 0 }), depth_definition.branch_pitch),
                                ),
                            ),
                            .size = gen_item.node.size * depth_definition.size,
                            .growth = growth,
                            .split_height = if (split_depth == 1) split_height else gen_item.node.split_height,
                            .split_depth = split_depth,
                        },
                        .parent_index = node_index,
                    });
                }
                break;
            }
        }
    }

    return Skeleton{
        .nodes = nodes,
        .node_to_primary_child_index = node_to_primary_child_index,
    };
}

const bark_normals = [_]zm.Vec{
    zm.loadArr3(.{ 0.5, 0.5, 0 }),
    zm.loadArr3(.{ -0.5, 0.5, 0 }),
    zm.loadArr3(.{ -0.5, -0.5, 0 }),
    zm.loadArr3(.{ 0.5, -0.5, 0 }),
    zm.loadArr3(.{ 0.5, 0.5, 0 }),
    zm.loadArr3(.{ -0.5, 0.5, 0 }),
    zm.loadArr3(.{ -0.5, -0.5, 0 }),
    zm.loadArr3(.{ 0.5, -0.5, 0 }),
};

const bark_triangles = [_]u32{
    0, 1, 2, 2, 3, 0, // Bottom
    6, 5, 4, 4, 7, 6, // Top
    2, 1, 5, 5, 6, 2, // Left
    0, 3, 4, 4, 3, 7, // Right
    3, 2, 6, 6, 7, 3, // Back
    1, 0, 4, 4, 5, 1, // Forward
};

const leaf_triangles = [_]u32{ 0, 1, 2, 2, 3, 0 };

const leaf_normals = [_]zm.Vec{
    zm.loadArr3(.{ 0, 1, 0 }),
    zm.loadArr3(.{ -0.2, 0.8, 0 }),
    zm.loadArr3(.{ 0, 1, 0 }),
    zm.loadArr3(.{ 0.2, 0.8, 0 }),
};

pub const Mesh = struct {
    vertices: []Vec4,
    normals: []Vec4,
    split_height: []f32,
    triangles: []u32,
};

pub fn generateTaperedWood(allocator: Allocator, skeleton: Skeleton, settings: MeshSettings) !Mesh {
    const vertex_count = skeleton.nodes.items.len * 8;
    const triangle_count = skeleton.nodes.items.len * 6 * 6;

    var mesh = Mesh{
        .vertices = try allocator.alloc(Vec4, vertex_count),
        .normals = try allocator.alloc(Vec4, vertex_count),
        .split_height = try allocator.alloc(f32, vertex_count),
        .triangles = try allocator.alloc(u32, triangle_count),
    };

    var node_index: usize = 0;
    for (skeleton.nodes.items) |parent| {
        if (parent.split_depth != settings.leaves.split_depth) {
            const child_index = skeleton.node_to_primary_child_index.items[node_index];
            const child = if (child_index) |idx| skeleton.nodes.items[idx] else parent;
            const grandchild_index = if (child_index) |idx| skeleton.node_to_primary_child_index.items[idx] else null;
            const grandchild = if (grandchild_index) |idx| skeleton.nodes.items[idx] else child;

            const height = parent.size * parent.growth;
            const parent_size = zm.lerpV(child.size, parent.size, parent.growth) * settings.thickness;
            const child_size = zm.lerpV(grandchild.size, child.size, child.growth) * settings.thickness;

            const vertices = [_]Vec4{
                Vec4{ 0.5 * parent_size, 0.5 * parent_size, 0, 1 },
                Vec4{ -0.5 * parent_size, 0.5 * parent_size, 0, 1 },
                Vec4{ -0.5 * parent_size, -0.5 * parent_size, 0, 1 },
                Vec4{ 0.5 * parent_size, -0.5 * parent_size, 0, 1 },
                Vec4{ 0.5 * child_size, 0.5 * child_size, height, 1 },
                Vec4{ -0.5 * child_size, 0.5 * child_size, height, 1 },
                Vec4{ -0.5 * child_size, -0.5 * child_size, height, 1 },
                Vec4{ 0.5 * child_size, -0.5 * child_size, height, 1 },
            };

            const vertex_offset = node_index * 8;
            for (vertices, 0..) |vertex, i| {
                mesh.vertices[vertex_offset + i] = zm.mul(
                    zm.mul(
                        zm.translationV(parent.position),
                        zm.matFromQuat(parent.rotation),
                    ),
                    vertex,
                );
                mesh.normals[vertex_offset + i] = zm.normalize3(zm.rotate(parent.rotation, bark_normals[i]));
                mesh.split_height[vertex_offset + i] = parent.split_height;
            }

            const triangle_offset = node_index * bark_triangles.len;
            for (bark_triangles, 0..) |triangle, i| {
                mesh.triangles[triangle_offset + i] = @intCast(triangle + vertex_offset);
            }
        }
        node_index += 1;
    }

    return mesh;
}

pub fn generateLeaves(allocator: Allocator, skeleton: Skeleton, settings: MeshSettings) !Mesh {
    const vertex_count = skeleton.nodes.items.len * 4;
    const triangle_count = skeleton.nodes.items.len * 6;

    var mesh = Mesh{
        .vertices = try allocator.alloc(Vec4, vertex_count),
        .normals = try allocator.alloc(Vec4, vertex_count),
        .split_height = try allocator.alloc(f32, vertex_count),
        .triangles = try allocator.alloc(u32, triangle_count),
    };

    var node_index: usize = 0;
    for (skeleton.nodes.items) |node| {
        if (node.split_depth == settings.leaves.split_depth) {
            const length = node.size * settings.leaves.length;
            const breadth = node.size * settings.leaves.breadth;

            const vertices = [_]Vec4{
                Vec4{ 0, 0, 0, 1 },
                Vec4{ breadth * 0.4, breadth * 0.1, length * 0.5, 1 },
                Vec4{ 0, 0, length, 1 },
                Vec4{ breadth * -0.4, breadth * 0.1, length * 0.5, 1 },
            };

            const vertex_offset = node_index * 4;
            for (vertices, 0..) |vertex, i| {
                mesh.vertices[vertex_offset + i] = zm.mul(
                    zm.mul(
                        zm.translationV(node.position),
                        zm.matFromQuat(node.rotation),
                    ),
                    vertex,
                );
                mesh.normals[vertex_offset + i] = zm.normalize3(zm.rotate(node.rotation, leaf_normals[i]));
                mesh.split_height[vertex_offset + i] = node.split_height;
            }

            const triangle_offset = node_index * leaf_triangles.len;
            for (leaf_triangles, 0..) |triangle, i| {
                mesh.triangles[triangle_offset + i] = @intCast(triangle + vertex_offset);
            }
        }
        node_index += 1;
    }

    return mesh;
}

pub const diciduous = .{
    .structure = Settings{
        .start_size = 1,
        .start_growth = 1,
        .depth_definitions = &[_]DepthDefinition{
            .{
                .split_amount = 10,
                .flatness = 0,
                .size = 0.3,
                .height_spread = 0.8,
                .branch_pitch = 50,
                .branch_roll = 90,
                .height_to_growth = .{
                    .y_values = &.{ 0, 1 },
                    .x_range = .{ 0, 0.25 },
                },
            },
            .{
                .split_amount = 6,
                .flatness = 0.6,
                .size = 0.4,
                .height_spread = 0.8,
                .branch_pitch = 60 / 180 * math.pi,
                .branch_roll = 90 / 180 * math.pi,
                .height_to_growth = .{
                    .y_values = &.{ 0.5, 0.9, 1 },
                    .x_range = .{ 0, 0.5 },
                },
            },
            .{
                .split_amount = 10,
                .flatness = 0,
                .size = 0.4,
                .height_spread = 0.8,
                .branch_pitch = 40 / 180 * math.pi,
                .branch_roll = 90 / 180 * math.pi,
                .height_to_growth = .{
                    .y_values = &.{ 0.5, 0.8, 1, 0.8, 0.5 },
                    .x_range = .{ 0, 0.5 },
                },
            },
            .{
                .split_amount = 10,
                .flatness = 0,
                .size = 0.7,
                .height_spread = 0.8,
                .branch_pitch = 40 / 180 * math.pi,
                .branch_roll = 90 / 180 * math.pi,
                .height_to_growth = .{
                    .y_values = &.{ 0.5, 0.8, 1, 0.8, 0.5 },
                    .x_range = .{ 0, 0.5 },
                },
            },
        },
    },
    .mesh = MeshSettings{
        .thickness = 0.05,
        .leaves = .{
            .split_depth = 4,
            .length = 1,
            .breadth = 0.3,
        },
        .growth_to_thickness = .{
            .y_values = &.{ 0.0025, 0.035 },
            .x_range = .{ 0, 1 },
        },
    },
};

test "Build a tree" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const skeleton = try generateStructure(arena.allocator(), diciduous.structure);
    const bark_mesh = try generateTaperedWood(arena.allocator(), skeleton, diciduous.mesh);
    const leaf_mesh = try generateLeaves(arena.allocator(), skeleton, diciduous.mesh);

    _ = bark_mesh;
    _ = leaf_mesh;
}
