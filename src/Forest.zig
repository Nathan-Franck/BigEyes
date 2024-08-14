const std = @import("std");
const zm = @import("./zmath/main.zig");
const util = .{
    .tree = @import("./tree.zig"),
};

const Vec4 = @Vector(4, f32);

pub fn Forest(Prefab: type, comptime chunk_size: i32) type {
    return struct {
        pub const Tree = struct {
            pub const SpawnRadius = struct {
                tree: *const Tree,
                radius: f32,
                likelihood: f32,
            };
            spawn_radii: ?[]const SpawnRadius = null,
            prefab: Prefab,
            density_tier: i32,
            likelihood: f32,
            scale_range: util.tree.SmoothCurve,
        };

        pub const Spawn = struct {
            prefab: *const Prefab,
            position: Vec4,
            rotation: Vec4,
            scale: f32,
        };

        fn spawner(ForestSettings: type) type {
            const trees = unpack: {
                const decls: []const std.builtin.Type.Declaration = @typeInfo(ForestSettings).Struct.decls;
                var trees: [decls.len]Tree = undefined;
                for (decls, 0..) |decl_definition, i| {
                    trees[i] = @field(ForestSettings, decl_definition.name);
                }
                break :unpack trees;
            };
            const density_tiers = calc: {
                var min_tier: i32 = trees[0].density_tier;
                var max_tier: i32 = trees[0].density_tier;
                for (trees[1..]) |tree| {
                    min_tier = @min(min_tier, tree.density_tier);
                    max_tier = @max(max_tier, tree.density_tier);
                }
                const tier_len = max_tier - min_tier + 1;
                var tiers: [tier_len][]const Tree = undefined;
                for (&tiers, 0..) |*tier, tier_index| {
                    var tier_contents: []const Tree = &.{};
                    for (trees) |tree| {
                        if (tree.density_tier == @as(i32, tier_index) + min_tier) {
                            tier_contents = tier_contents ++ .{tree};
                        }
                    }
                    tier.* = tier_contents;
                }
                break :calc tiers;
            };
            _ = density_tiers; // autofix

            // if (true) @compileError(std.fmt.comptimePrint("{any}", .{density_tiers}));

            const total_likelihood = calc: {
                var total: f32 = 0;
                for (trees) |tree|
                    total += tree.likelihood;
                break :calc @max(total, 1);
            };
            const quantization = 128;
            const tree_range = calc: {
                var range: [quantization]?*const Tree = .{null} ** quantization;
                var current_tree_index: u32 = 0;
                var accum_likelihood: f32 = trees[current_tree_index].likelihood;
                var next_transition: i32 = @as(i32, @intFromFloat(accum_likelihood / total_likelihood * quantization));
                for (&range, 0..) |*cell, cell_index| {
                    cell.* = if (current_tree_index >= trees.len)
                        null
                    else
                        &trees[current_tree_index];
                    if (cell_index >= next_transition) {
                        current_tree_index += 1;
                        accum_likelihood = if (current_tree_index >= trees.len)
                            total_likelihood
                        else
                            accum_likelihood + trees[current_tree_index].likelihood;
                        next_transition = @as(i32, @intFromFloat(accum_likelihood / total_likelihood * quantization));
                    }
                }
                break :calc range;
            };

            return struct {
                pub const Chunk = [chunk_size][chunk_size]?Spawn;
                pub const Chunks = std.AutoHashMap(Coord, Chunk);
                pub const Coord = struct {
                    x: i32,
                    y: i32,
                    density_tier: i32,
                };
                pub const Bounds = struct {
                    x: f32,
                    y: f32,
                };

                const context = {};
                const rng = std.Random.DefaultPrng;
                const hashFn = std.hash_map.getAutoHashFn(struct { Coord, u32 }, @TypeOf(context));

                chunks: Chunks,

                pub fn gatherCollection(allocator: std.mem.Allocator, bounds: zm.Vec) []const Prefab {
                    _ = allocator; // autofix
                    _ = bounds; // autofix
                }

                pub fn getChunk(self: *@This(), coord: Coord) !*const Chunk {
                    const chunk_entry = try self.chunks.getOrPut(coord);
                    if (chunk_entry.found_existing) {
                        std.debug.print("Already here!", .{});
                        return chunk_entry.value_ptr;
                    }

                    const spacing = std.math.pow(f32, 2.0, @floatFromInt(coord.density_tier));
                    const offset = .{
                        .x = @as(f32, @floatFromInt(coord.x)) * spacing * chunk_size,
                        .z = @as(f32, @floatFromInt(coord.y)) * spacing * chunk_size,
                    };
                    var rand = .{
                        .spawn = rng.init(hashFn(context, .{ coord, 0 })),
                        .position = rng.init(hashFn(context, .{ coord, 1 })),
                        .rotation = rng.init(hashFn(context, .{ coord, 2 })),
                        .scale = rng.init(hashFn(context, .{ coord, 3 })),
                    };
                    const chunk: *Chunk = chunk_entry.value_ptr;
                    for (chunk, 0..) |*row, y| {
                        for (row, 0..) |*item, x| {
                            item.* = if (tree_range[
                                rand.spawn.random().intRangeLessThan(usize, 0, quantization)
                            ]) |tree|
                                Spawn{
                                    .prefab = &tree.prefab,
                                    .position = zm.loadArr3(.{
                                        offset.x + (@as(f32, @floatFromInt(x)) + rand.position.random().float(f32)) * spacing,
                                        0, // TODO - conform to a heightmap?
                                        offset.z + (@as(f32, @floatFromInt(y)) + rand.position.random().float(f32)) * spacing,
                                    }),
                                    .rotation = zm.quatFromAxisAngle(
                                        zm.loadArr3(.{ 0, 1, 0 }),
                                        rand.rotation.random().float(f32) * 360 * std.math.rad_per_deg,
                                    ),
                                    .scale = tree.scale_range.sample(rand.scale.random().float(f32)),
                                }
                            else
                                null;
                        }
                    }
                    return chunk;
                }
            };
        }
    };
}

// test "Ascii Forest" {
pub fn main() !void {
    const Ascii = struct {
        character: u8,
    };
    const AsciiForest = Forest(Ascii, 5);
    const Spawner = AsciiForest.spawner(struct {
        pub const little_tree = AsciiForest.Tree{
            .prefab = .{ .character = 'i' },
            .density_tier = -3,
            .likelihood = 0.20,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        };
        pub const little_tree2 = AsciiForest.Tree{
            .prefab = .{ .character = 'j' },
            .density_tier = -2,
            .likelihood = 0.20,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        };
        pub const little_tree3 = AsciiForest.Tree{
            .prefab = .{ .character = 'k' },
            .density_tier = 3,
            .likelihood = 0.20,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        };
        pub const big_tree = AsciiForest.Tree{
            .prefab = .{ .character = 'T' },
            .density_tier = 7,
            .likelihood = 0.05,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
            .spawn_radii = &[_]AsciiForest.Tree.SpawnRadius{
                .{
                    .tree = &little_tree,
                    .radius = 10,
                    .likelihood = 1,
                },
            },
        };
    });

    const allocator = std.heap.page_allocator;
    var spawner: Spawner = .{ .chunks = Spawner.Chunks.init(allocator) };
    const chunks: []const *const Spawner.Chunk = &.{
        try spawner.getChunk(.{ .x = 0, .y = 0, .density_tier = 8 }),
        try spawner.getChunk(.{ .x = 0, .y = 0, .density_tier = 8 }),
    };

    // const collection = Spawner.gatherCollection();

    for (chunks) |chunk| {
        std.debug.print("another chunk\n", .{});
        for (chunk) |row| {
            var line_data = std.ArrayList(u8).init(allocator);
            for (row) |maybe_item| {
                try line_data.appendSlice(&.{
                    if (maybe_item) |item| item.prefab.character else '_',
                    ' ',
                });
            }
            std.debug.print("{s}\n", .{line_data.items});
        }
    }

    // TODO - Spawn trees and Display in a large grid, that shows all density tiers together with random offsets 🌲

}
