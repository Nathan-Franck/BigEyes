const std = @import("std");
const zm = @import("zmath");
const Stamp = @import("../Stamp.zig");
const Vec4 = @import("../forest.zig").Vec4;
const tree = @import("../tree.zig");

pub const Forest = @import("../forest.zig").Forest(32);

pub const ForestSpawner = Forest.spawner(ForestSettings);

pub const TerrainSpawner = Forest.spawner(struct {
    pub const Hemisphere = Forest.Tree{
        .density_tier = -1,
        .likelihood = 1,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const BigHemisphere = Forest.Tree{
        .density_tier = 2,
        .likelihood = 1,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
});

pub const TerrainStamps = struct {
    pub const Hemisphere: Stamp = blk: {
        @setEvalBranchQuota(100000);
        const resolution = .{ .x = 16, .y = 16 };
        var heights: [resolution.x * resolution.y]f32 = undefined;
        for (0..resolution.y) |y| {
            for (0..resolution.x) |x| {
                const v = Vec4{ @floatFromInt(x), @floatFromInt(y), 0, 0 } /
                    zm.splat(Vec4, @floatFromInt(@max(resolution.x, resolution.y))) -
                    zm.splat(Vec4, 0.5);
                heights[x + y * resolution.x] = @max(
                    0,
                    std.math.sqrt(
                        1 - std.math.pow(f32, zm.length2(v)[0] * 2, 2),
                    ),
                ) * 0.5;
            }
        }
        const heights_static = heights;
        break :blk .{
            .resolution = resolution,
            .heights = &heights_static,
            .size = 1,
        };
    };
    pub const BigHemisphere: Stamp = blk: {
        @setEvalBranchQuota(100000);
        const resolution = .{ .x = 32, .y = 32 };
        var heights: [resolution.x * resolution.y]f32 = undefined;
        for (0..resolution.y) |y| {
            for (0..resolution.x) |x| {
                const v = Vec4{ @floatFromInt(x), @floatFromInt(y), 0, 0 } /
                    zm.splat(Vec4, @floatFromInt(@max(resolution.x, resolution.y))) -
                    zm.splat(Vec4, 0.5);
                heights[x + y * resolution.x] = @max(
                    0,
                    std.math.sqrt(
                        1 - std.math.pow(f32, zm.length2(v)[0] * 2, 2),
                    ),
                ) * 1.5;
            }
        }
        const heights_static = heights;
        break :blk .{
            .resolution = resolution,
            .heights = &heights_static,
            .size = 3,
        };
    };
};
pub const ForestSettings = struct {
    pub const grass1 = Forest.Tree{
        .density_tier = -2,
        .likelihood = 0.1,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const grass2 = Forest.Tree{
        .density_tier = -2,
        .likelihood = 0.05,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const little_tree = Forest.Tree{
        .density_tier = 1,
        .likelihood = 1,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
    };
    pub const big_tree = Forest.Tree{
        .density_tier = 2,
        .likelihood = 1,
        .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        .spawn_radii = &[_]Forest.Tree.SpawnRadius{
            .{
                .tree = &little_tree,
                .radius = 10,
                .likelihood = 1,
            },
        },
    };
};
pub const Trees = struct {
    const Settings = tree.Settings;
    const DepthDefinition = tree.DepthDefinition;
    const MeshSettings = tree.MeshSettings;
    const math = std.math;

    pub const big_tree = .{
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
    pub const little_tree = .{
        .structure = Settings{
            .start_size = 0.6,
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
            },
        },
        .mesh = MeshSettings{
            .thickness = 0.05,
            .leaves = .{
                .split_depth = 3,
                .length = 2.0,
                .breadth = 1.0,
            },
            .growth_to_thickness = .{
                .y_values = &.{ 0.0025, 0.035 },
                .x_range = .{ 0.0, 1.0 },
            },
        },
    };
    pub const grass1 = .{
        .structure = Settings{
            .start_size = 0.3,
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
            },
        },
        .mesh = MeshSettings{
            .thickness = 0.05,
            .leaves = .{
                .split_depth = 2,
                .length = 2.0,
                .breadth = 1.0,
            },
            .growth_to_thickness = .{
                .y_values = &.{ 0.0025, 0.035 },
                .x_range = .{ 0.0, 1.0 },
            },
        },
    };
    pub const grass2 = .{
        .structure = Settings{
            .start_size = 0.2,
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
            },
        },
        .mesh = MeshSettings{
            .thickness = 0.05,
            .leaves = .{
                .split_depth = 1,
                .length = 2.0,
                .breadth = 1.0,
            },
            .growth_to_thickness = .{
                .y_values = &.{ 0.0025, 0.035 },
                .x_range = .{ 0.0, 1.0 },
            },
        },
    };
};
