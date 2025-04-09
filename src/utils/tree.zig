const std = @import("std");
const zm = @import("zmath");
const utils = @import("../utils.zig");

const math = std.math;
const Allocator = std.mem.Allocator;

pub const Vec4 = @Vector(4, f32);
pub const Vec2 = @Vector(2, f32);
pub const Quat = Vec4;

fn flattenAngle(unnormalized_angle: f32, rate: f32) f32 {
    var angle = unnormalized_angle;
    if (rate <= 0) {
        return angle;
    }
    while (angle < 0) angle += math.pi * 2.0;
    while (angle > math.pi * 2.0) angle -= math.pi * 2.0;
    const offset: f32 = if (angle > math.pi / 2.0) math.pi else 0;
    return ((angle - offset) *
        (1 - rate) + offset);
}

pub const DepthDefinition = struct {
    split_amount: f32,
    flatness: f32,
    size: f32,
    height_spread: f32,
    branch_pitch: f32,
    branch_roll: f32,
    height_to_growth: utils.SmoothCurve,
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
    growth_to_thickness: utils.SmoothCurve,
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
    nodes: []const Node,
    node_to_primary_child_index: []const ?usize,
};

pub fn generateStructure(allocator: Allocator, settings: Settings) !Skeleton {
    const start_node = Node{
        .size = settings.start_size,
        .position = .{ 0, 0, 0, 1 },
        .rotation = zm.quatFromAxisAngle(zm.loadArr3(.{ -1, 0, 0 }), 90.0 * math.rad_per_deg),
        .split_height = 0,
        .growth = settings.start_growth,
        .split_depth = 0,
    };

    var generation_queue = std.ArrayList(GenQueueItem).init(allocator);

    var nodes = std.ArrayList(Node).init(allocator);
    var node_to_primary_child_index = std.ArrayList(?usize).init(allocator);

    try generation_queue.append(.{ .node = start_node, .parent_index = null });

    while (generation_queue.pop()) |gen_item| {
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

            if (gen_item.node.split_depth <= current_depth) {
                const split_amount: usize = @intFromFloat(depth_definition.split_amount * gen_item.node.growth);
                const split_depth = gen_item.node.split_depth + 1;

                // Main branch extension
                {
                    const growth = math.clamp(depth_definition.height_to_growth.sample(0), 0, 1);
                    const forward = zm.rotate(
                        gen_item.node.rotation,
                        zm.loadArr3(.{ 0, 0, gen_item.node.size * gen_item.node.growth }),
                    );
                    try generation_queue.append(.{
                        .node = .{
                            .position = gen_item.node.position + forward,
                            .rotation = zm.qmul(
                                zm.quatFromNormAxisAngle(
                                    zm.loadArr3(.{ 0, 0, 1 }),
                                    depth_definition.branch_roll,
                                ),
                                gen_item.node.rotation,
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
                while (split_index < split_amount) : (split_index += 1) {
                    const split_height = @as(f32, @floatFromInt(split_index)) / @as(f32, @floatFromInt(split_amount));
                    const growth = math.clamp(depth_definition.height_to_growth.sample(split_height * gen_item.node.growth), 0, 1);
                    try generation_queue.append(.{
                        .node = .{
                            .position = gen_item.node.position + zm.rotate(gen_item.node.rotation, zm.loadArr3(.{ 0, 0, gen_item.node.size * gen_item.node.growth * (1 - split_height * depth_definition.height_spread) })),
                            .rotation = zm.qmul(
                                zm.qmul(
                                    zm.quatFromNormAxisAngle(zm.loadArr3(.{ 0, 1, 0 }), depth_definition.branch_pitch),
                                    zm.quatFromNormAxisAngle(zm.loadArr3(.{ 0, 0, 1 }), depth_definition.branch_roll +
                                        flattenAngle(@as(f32, @floatFromInt(split_index)) * 3.1419 * 2 * 1.618, depth_definition.flatness)),
                                ),
                                gen_item.node.rotation,
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
        .nodes = nodes.items,
        .node_to_primary_child_index = node_to_primary_child_index.items,
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
    vertices: std.MultiArrayList(struct {
        position: Vec4,
        uv: Vec2,
        normal: Vec4,
        split_height: f32,
    }),
    triangles: []u32,
};

pub fn generateTaperedWood(allocator: Allocator, skeleton: Skeleton, settings: MeshSettings) !Mesh {
    const vertex_count = skeleton.nodes.len * 8;
    const triangle_count = skeleton.nodes.len * 6 * 6;

    var mesh = Mesh{
        .vertices = .{},
        .triangles = try allocator.alloc(u32, triangle_count),
    };
    try mesh.vertices.resize(allocator, vertex_count);

    var node_index: usize = 0;
    for (skeleton.nodes) |parent| {
        if (parent.split_depth != settings.leaves.split_depth) {
            const child_index = skeleton.node_to_primary_child_index[node_index];
            const child = if (child_index) |idx| skeleton.nodes[idx] else parent;
            const grandchild_index = if (child_index) |idx| skeleton.node_to_primary_child_index[idx] else null;
            const grandchild = if (grandchild_index) |idx| skeleton.nodes[idx] else child;

            const height = parent.size * parent.growth;
            const parent_size = zm.lerpV(child.size, parent.size, parent.growth) * settings.thickness;
            const child_size = zm.lerpV(grandchild.size, child.size, child.growth) * settings.thickness;

            const vertices = [_]Vec4{
                Vec4{ 0.5 * child_size, 0.5 * child_size, height, 1 },
                Vec4{ -0.5 * child_size, 0.5 * child_size, height, 1 },
                Vec4{ -0.5 * child_size, -0.5 * child_size, height, 1 },
                Vec4{ 0.5 * child_size, -0.5 * child_size, height, 1 },
                Vec4{ 0.5 * parent_size, 0.5 * parent_size, 0, 1 },
                Vec4{ -0.5 * parent_size, 0.5 * parent_size, 0, 1 },
                Vec4{ -0.5 * parent_size, -0.5 * parent_size, 0, 1 },
                Vec4{ 0.5 * parent_size, -0.5 * parent_size, 0, 1 },
            };

            const vertex_offset = node_index * 8;
            for (vertices, bark_normals, vertex_offset..) |vertex, bark_normal, i| {
                const slice = mesh.vertices.slice();
                slice.items(.position)[i] = zm.mul(
                    vertex,
                    zm.mul(
                        zm.matFromQuat(parent.rotation),
                        zm.translationV(parent.position),
                    ),
                );
                slice.items(.normal)[i] = zm.normalize3(zm.rotate(parent.rotation, bark_normal));
                slice.items(.split_height)[i] = parent.split_height;
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
    const vertex_count = skeleton.nodes.len * 4;
    const triangle_count = skeleton.nodes.len * 6;

    var mesh = Mesh{
        .vertices = .{},
        .triangles = try allocator.alloc(u32, triangle_count),
    };
    try mesh.vertices.resize(allocator, vertex_count);

    var node_index: usize = 0;
    for (skeleton.nodes) |node| {
        if (node.split_depth == settings.leaves.split_depth) {
            const length = node.size * settings.leaves.length;
            const breadth = node.size * settings.leaves.breadth;

            const uvs = [_]Vec2{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 } };
            const vertices = blk: {
                var result: [4]Vec4 = undefined;
                inline for (uvs, 0..) |uv, index| {
                    result[index] = Vec4{ std.math.lerp(-1, 1, uv[0]) * breadth, 0, std.math.lerp(1, 0, uv[1]) * length, 1 };
                }
                break :blk result;
            };

            const vertex_offset = node_index * 4;
            for (vertices, uvs, leaf_normals, vertex_offset..) |vertex, input_uv, leaf_normal, i| {
                const slice = mesh.vertices.slice();
                slice.items(.position)[i] = zm.mul(
                    vertex,
                    zm.mul(
                        zm.matFromQuat(node.rotation),
                        zm.translationV(node.position),
                    ),
                );
                slice.items(.uv)[i] = input_uv;
                slice.items(.normal)[i] = zm.normalize3(zm.rotate(node.rotation, leaf_normal));
                slice.items(.split_height)[i] = node.split_height;
            }

            const triangle_offset = node_index * leaf_triangles.len;
            for (leaf_triangles, 0..) |triangle, i| {
                mesh.triangles[triangle_offset + i] = @intCast(triangle + vertex_offset);
            }
            node_index += 1;
        }
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
                .flatness = 0.0,
                .size = 0.4,
                .height_spread = 0.6,
                .branch_pitch = 50.0 * math.rad_per_deg,
                .branch_roll = 90.0 * math.rad_per_deg,
                .height_to_growth = .{
                    .y_values = &.{ 1.0, 1.0, 0.0 },
                    .x_range = .{ 0.0, 1.0 },
                },
            },
            .{
                .split_amount = 6,
                .flatness = 0.3,
                .size = 0.45,
                .height_spread = 0.8,
                .branch_pitch = 60.0 * math.rad_per_deg,
                .branch_roll = 90.0 * math.rad_per_deg,
                .height_to_growth = .{
                    .y_values = &.{ 1.0, 1.0, 0.0 },
                    .x_range = .{ 0.0, 1.0 },
                },
            },
            .{
                .split_amount = 10,
                .flatness = 0.0,
                .size = 0.5,
                .height_spread = 0.8,
                .branch_pitch = 40.0 * math.rad_per_deg,
                .branch_roll = 90.0 * math.rad_per_deg,
                .height_to_growth = .{
                    .y_values = &.{ 1.0, 1.0, 0.0 },
                    .x_range = .{ 0.0, 1.0 },
                },
            },
            .{
                .split_amount = 10,
                .flatness = 0.0,
                .size = 0.6,
                .height_spread = 0.8,
                .branch_pitch = 40.0 * math.rad_per_deg,
                .branch_roll = 90.0 * math.rad_per_deg,
                .height_to_growth = .{
                    .y_values = &.{ 0.5, 0.8, 1.0, 0.8, 0.5 },
                    .x_range = .{ 0.0, 0.5 },
                },
            },
        },
    },
    .mesh = MeshSettings{
        .thickness = 0.05,
        .leaves = .{
            .split_depth = 4,
            .length = 1.4,
            .breadth = 0.7,
        },
        .growth_to_thickness = .{
            .y_values = &.{ 0.0025, 0.035 },
            .x_range = .{ 0.0, 1.0 },
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

    // std.debug.print("{any}", .{skeleton.nodes});
}
