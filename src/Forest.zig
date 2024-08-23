const std = @import("std");
const zm = @import("./zmath/main.zig");
const util = .{
    .tree = @import("./tree.zig"),
};

const Vec4 = @Vector(4, f32);
const Vec2 = @Vector(2, f32);
const Coord = @Vector(2, i32);
const Bounds = struct {
    min: Vec2,
    size: Vec2,
};

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
            const DensityCoord = struct {
                x: i32,
                y: i32,
                density_tier: i32,
            };
            const ChunkType = [chunk_size][chunk_size]?Spawn;
            const ChunksType = std.AutoHashMap(DensityCoord, ChunkType);

            const quantization = 128;

            // const Bounds = struct {
            //     x: f32,
            //     y: f32,
            // };

            const DensityTier = struct {
                const context = {};
                const rng = std.Random.DefaultPrng;
                const hashFn = std.hash_map.getAutoHashFn(struct { DensityCoord, u32 }, @TypeOf(context));

                density: i32,
                trees: []const Tree,
                tree_range: [quantization]?*const Tree,

                pub fn getSpacing(self: @This()) f32 {
                    return std.math.pow(f32, 2.0, @floatFromInt(self.density));
                }

                pub fn getChunk(self: *const @This(), coord: struct { x: i32, y: i32 }) !ChunkType {
                    const spacing = self.getSpacing();
                    const offset = .{
                        .x = @as(f32, @floatFromInt(coord.x)) * spacing * chunk_size,
                        .z = @as(f32, @floatFromInt(coord.y)) * spacing * chunk_size,
                    };
                    const hash_coord: DensityCoord = .{ .x = coord.x, .y = coord.y, .density_tier = self.density };
                    var rand = .{
                        .spawn = rng.init(hashFn(context, .{ hash_coord, 0 })),
                        .position = rng.init(hashFn(context, .{ hash_coord, 1 })),
                        .rotation = rng.init(hashFn(context, .{ hash_coord, 2 })),
                        .scale = rng.init(hashFn(context, .{ hash_coord, 3 })),
                    };
                    var chunk: ChunkType = undefined;
                    for (&chunk, 0..) |*row, y| {
                        for (row, 0..) |*item, x| {
                            item.* = if (self.tree_range[
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

            const density_tiers, const min_tier = density_tiers: {
                const trees = unpack: {
                    const decls: []const std.builtin.Type.Declaration = @typeInfo(ForestSettings).Struct.decls;
                    var trees: [decls.len]Tree = undefined;
                    for (decls, 0..) |decl_definition, i| {
                        trees[i] = @field(ForestSettings, decl_definition.name);
                    }
                    break :unpack trees;
                };
                var min_tier: i32 = trees[0].density_tier;
                var max_tier: i32 = trees[0].density_tier;
                for (trees[1..]) |tree| {
                    min_tier = @min(min_tier, tree.density_tier);
                    max_tier = @max(max_tier, tree.density_tier);
                }
                const tier_len = max_tier - min_tier + 1;
                var tiers: [tier_len]?DensityTier = undefined;
                for (&tiers, 0..) |*tier, tier_index| {
                    var tier_trees: []const Tree = &.{};
                    const density_tier = @as(i32, tier_index) + min_tier;
                    for (trees) |tree| {
                        if (tree.density_tier == density_tier) {
                            tier_trees = tier_trees ++ .{tree};
                        }
                    }
                    tier.* = if (tier_trees.len == 0) null else tier: {
                        const total_likelihood = total_likelihood: {
                            var total: f32 = 0;
                            for (tier_trees) |tree|
                                total += tree.likelihood;
                            break :total_likelihood @max(total, 1);
                        };
                        const tree_range = tree_range: {
                            var range: [quantization]?*const Tree = .{null} ** quantization;
                            var current_tree_index: u32 = 0;
                            var accum_likelihood: f32 = tier_trees[current_tree_index].likelihood;
                            var next_transition: i32 = @as(i32, @intFromFloat(accum_likelihood / total_likelihood * quantization));
                            for (&range, 0..) |*cell, cell_index| {
                                cell.* = if (current_tree_index >= tier_trees.len)
                                    null
                                else
                                    &tier_trees[current_tree_index];
                                if (cell_index >= next_transition) {
                                    current_tree_index += 1;
                                    accum_likelihood = if (current_tree_index >= tier_trees.len)
                                        total_likelihood
                                    else
                                        accum_likelihood + tier_trees[current_tree_index].likelihood;
                                    next_transition = @as(i32, @intFromFloat(accum_likelihood / total_likelihood * quantization));
                                }
                            }
                            break :tree_range range;
                        };
                        break :tier .{
                            .trees = tier_trees,
                            .density = density_tier,
                            .tree_range = tree_range,
                        };
                    };
                }
                break :density_tiers .{ tiers, min_tier };
            };

            // if (true) @compileError(std.fmt.comptimePrint("{any}", .{density_tiers}));

            return struct {
                const Chunks = ChunksType;
                const Chunk = ChunkType;

                chunks: Chunks,

                pub fn densityTierToIndex(density_tier: i32) usize {
                    return @intCast(density_tier - min_tier);
                }

                const CoordIterator = struct {
                    current: Coord,
                    min_coord: Coord,
                    max_coord: Coord,
                    fn init(min_coord: Coord, max_coord: Coord) @This() {
                        return .{
                            .current = min_coord,
                            .min_coord = min_coord,
                            .max_coord = max_coord,
                        };
                    }
                    fn next(self: *@This()) ?Coord {
                        self.current[0] += 1;
                        if (self.current[0] > self.max_coord[0]) {
                            self.current[0] = self.min_coord[0];
                            self.current[1] += 1;
                            if (self.current[1] > self.max_coord[1])
                                return null;
                        }
                        return self.current;
                    }
                };

                pub fn gatherSpawnsInBounds(self: *@This(), allocator: std.mem.Allocator, bounds: Bounds) ![]const Spawn {
                    var spawns = std.ArrayList(Spawn).init(allocator);
                    for (density_tiers) |density_tier| {
                        if (density_tier) |tier| {
                            const coord_span = tier.getSpacing();
                            const chunk_span = coord_span * chunk_size;
                            var chunk_coords = CoordIterator.init(
                                @intFromFloat(@floor(bounds.min / @as(Vec2, @splat(chunk_span)))),
                                @intFromFloat(@ceil((bounds.min + bounds.size) / @as(Vec2, @splat(chunk_span)))),
                            );
                            while (chunk_coords.next()) |chunk_coord| {
                                const chunk = try self.getChunk(.{
                                    .x = chunk_coord[0],
                                    .y = chunk_coord[1],
                                    .density_tier = tier.density,
                                });
                                const chunk_offset: Vec2 = @floatFromInt(chunk_coord * @as(Coord, @splat(chunk_size)));
                                var coords = CoordIterator.init(
                                    std.math.clamp(
                                        @as(Coord, @intFromFloat(@floor((bounds.min - chunk_offset) / @as(Vec2, @splat(coord_span))))),
                                        @as(Coord, @splat(0)),
                                        @as(Coord, @splat(chunk_size - 1)),
                                    ),
                                    std.math.clamp(
                                        @as(Coord, @intFromFloat(@ceil((bounds.min - chunk_offset + bounds.size) / @as(Vec2, @splat(coord_span))))),
                                        @as(Coord, @splat(0)),
                                        @as(Coord, @splat(chunk_size - 1)),
                                    ),
                                );
                                while (coords.next()) |coord| {
                                    if (chunk[@intCast(coord[0])][@intCast(coord[1])]) |spawn|
                                        try spawns.append(spawn);
                                }
                            }
                        }
                    }
                    return spawns.items;
                }

                pub fn getChunk(self: *@This(), density_coord: DensityCoord) !*const ChunkType {
                    const chunk_entry = try self.chunks.getOrPut(density_coord);
                    if (chunk_entry.found_existing) {
                        return chunk_entry.value_ptr;
                    }
                    const density_tier = &density_tiers[densityTierToIndex(density_coord.density_tier)];
                    return if (density_tier.*) |*tier| calc_and_cache: {
                        const chunk = try tier.getChunk(.{ .x = density_coord.x, .y = density_coord.y });
                        chunk_entry.value_ptr.* = chunk;
                        break :calc_and_cache chunk_entry.value_ptr;
                    } else @panic("Tried to access a chunk from a tier that isn't defined!");
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
        try spawner.getChunk(.{ .x = 0, .y = 0, .density_tier = -2 }),
        try spawner.getChunk(.{ .x = 0, .y = 0, .density_tier = -2 }),
    };

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

    // Spawn trees and Display in a large grid, that shows all density tiers together with random offsets 🌲
    const bounds = Bounds{
        .min = .{ -20, -20 },
        .size = .{ 40, 40 },
    };
    const spawns = try spawner.gatherSpawnsInBounds(allocator, bounds);

    const world_size = .{ .width = 128, .height = 64 };
    var world: [world_size.height][world_size.width]u8 = .{.{' '} ** world_size.width} ** world_size.height;
    for (spawns) |spawn| {
        const location: Coord = std.math.clamp(
            @as(Coord, @intFromFloat(@floor(
                (Vec2{ spawn.position[0], spawn.position[2] } - bounds.min) /
                    bounds.size *
                    Vec2{ world_size.width, world_size.height },
            ))),
            @as(Coord, @splat(0)),
            Coord{ world_size.width - 1, world_size.height - 1 },
        );
        world[@intCast(location[1])][@intCast(location[0])] = spawn.prefab.character;
    }

    for (world) |row| {
        std.debug.print("{s}\n", .{row});
    }
}
