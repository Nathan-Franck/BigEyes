const std = @import("std");
const zm = @import("./zmath/main.zig");
const util = .{
    .tree = @import("./tree.zig"),
};

pub const Vec4 = @Vector(4, f32);

pub const Vec2 = @Vector(2, f32);

pub const Coord = @Vector(2, i32);

const CoordIterator = struct {
    current: Coord,
    min_coord: Coord,
    max_coord: Coord,

    fn init(min_coord: Coord, max_coord: Coord) @This() {
        return .{
            .current = .{ min_coord[0] - 1, min_coord[1] },
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

pub const Bounds = struct {
    min: Vec2,
    size: Vec2,
};

pub fn Forest(comptime chunk_size: i32) type {
    return struct {
        pub const Tree = struct {
            pub const SpawnRadius = struct {
                tree: *const Tree,
                radius: f32,
                likelihood: f32,
            };
            spawn_radii: ?[]const SpawnRadius = null,
            density_tier: i32,
            likelihood: f32,
            scale_range: util.tree.SmoothCurve,
        };

        pub fn spawner(ForestSettings: type) type {
            const DensityCoord = struct {
                x: i32,
                y: i32,
                density: i32,
            };
            const TreeId = std.meta.DeclEnum(ForestSettings);
            const Spawn = struct {
                id: TreeId,
                position: Vec4,
                rotation: Vec4,
                scale: f32,
            };
            const Chunk = [chunk_size][chunk_size]?Spawn;
            const ChunkCache = std.AutoHashMap(Coord, Chunk);

            const quantization = 128;

            const DensityTier = struct {
                const context = {};
                const rng = std.Random.DefaultPrng;
                const hashFn = std.hash_map.getAutoHashFn(struct { DensityCoord, u32 }, @TypeOf(context));

                cache: ChunkCache,

                density: i32,
                tree_range: [quantization]?TreeId,

                pub fn getSpan(self: @This()) f32 {
                    return std.math.pow(f32, 2.0, @floatFromInt(self.density));
                }

                pub fn intToFloatRange(i: u64) f32 {
                    return @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(std.math.maxInt(u64)));
                }

                pub fn getChunk(self: *@This(), trees: []const Tree, coord: Coord) !*const Chunk {
                    const chunk_entry = try self.cache.getOrPut(coord);
                    if (chunk_entry.found_existing) {
                        return chunk_entry.value_ptr;
                    }

                    const span = self.getSpan();
                    const chunk_offset = .{
                        .x = @as(f32, @floatFromInt(coord[0])) * span * chunk_size,
                        .z = @as(f32, @floatFromInt(coord[1])) * span * chunk_size,
                    };

                    for (chunk_entry.value_ptr, 0..) |*row, y| {
                        for (row, 0..) |*item, x| {
                            const hash_coord: DensityCoord = .{
                                .x = coord[0] * chunk_size + @as(i32, @intCast(x)),
                                .y = coord[1] * chunk_size + @as(i32, @intCast(y)),
                                .density = self.density,
                            };
                            const rand = .{
                                .spawn = hashFn(context, .{ hash_coord, 0 }),
                                .position_x = hashFn(context, .{ hash_coord, 1 }),
                                .position_y = hashFn(context, .{ hash_coord, 1 }),
                                .rotation = hashFn(context, .{ hash_coord, 2 }),
                                .scale = hashFn(context, .{ hash_coord, 3 }),
                            };
                            item.* = if (self.tree_range[
                                @intCast(rand.spawn % quantization)
                            ]) |tree_id| blk: {
                                const tree = trees[@intFromEnum(tree_id)];
                                break :blk Spawn{
                                    .id = tree_id,
                                    .position = zm.loadArr3(.{
                                        // chunk_offset.x + (@as(f32, @floatFromInt(x)) + intToFloatRange(rand.position_x)) * span,
                                        chunk_offset.x + @as(f32, @floatFromInt(x)) * span,
                                        0, // TODO - conform to a heightmap?
                                        // chunk_offset.z + (@as(f32, @floatFromInt(y)) + intToFloatRange(rand.position_y)) * span,
                                        chunk_offset.z + @as(f32, @floatFromInt(y)) * span,
                                    }),
                                    .rotation = zm.quatFromAxisAngle(
                                        zm.loadArr3(.{ 0, 1, 0 }),
                                        intToFloatRange(rand.rotation) * 360 * std.math.rad_per_deg,
                                    ),
                                    .scale = tree.scale_range.sample(intToFloatRange(rand.scale)),
                                };
                            } else null;
                        }
                    }

                    return chunk_entry.value_ptr;
                }
            };

            const trees = unpack: {
                const decls: []const std.builtin.Type.Declaration = @typeInfo(ForestSettings).@"struct".decls;
                var trees: [decls.len]Tree = undefined;
                for (decls, 0..) |decl_definition, i| {
                    trees[i] = @field(ForestSettings, decl_definition.name);
                }
                break :unpack trees;
            };

            const density_tiers, const min_tier = density_tiers: {
                var min_tier: i32 = trees[0].density_tier;
                var max_tier: i32 = trees[0].density_tier;
                for (trees[1..]) |tree| {
                    min_tier = @min(min_tier, tree.density_tier);
                    max_tier = @max(max_tier, tree.density_tier);
                }
                const tree_decls = @typeInfo(ForestSettings).@"struct".decls;
                const tier_len = max_tier - min_tier + 1;
                var tiers: [tier_len]?DensityTier = undefined;
                for (&tiers, 0..) |*tier, tier_index| {
                    var tier_tree_ids: []const TreeId = &.{};
                    const density_tier = @as(i32, tier_index) + min_tier;
                    for (tree_decls, 0..) |tree_decl, decl_index| {
                        const tree = @field(ForestSettings, tree_decl.name);
                        if (tree.density_tier == density_tier) {
                            tier_tree_ids = tier_tree_ids ++ .{@as(TreeId, @enumFromInt(decl_index))};
                        }
                    }
                    tier.* = if (tier_tree_ids.len == 0) null else tier: {
                        const total_likelihood = total_likelihood: {
                            var total: f32 = 0;
                            for (tier_tree_ids) |tree_id|
                                total += @field(ForestSettings, @tagName(tree_id)).likelihood;
                            break :total_likelihood @max(total, 1);
                        };
                        const tree_range = tree_range: {
                            var range: [quantization]?TreeId = .{null} ** quantization;
                            var current_tree_index: u32 = 0;
                            var accum_likelihood: f32 = @field(
                                ForestSettings,
                                @tagName(tier_tree_ids[current_tree_index]),
                            ).likelihood;
                            var next_transition: i32 = @as(i32, @intFromFloat(accum_likelihood / total_likelihood * quantization));
                            for (&range, 0..) |*cell, cell_index| {
                                cell.* = if (current_tree_index >= tier_tree_ids.len)
                                    null
                                else
                                    tier_tree_ids[current_tree_index];
                                if (cell_index >= next_transition) {
                                    current_tree_index += 1;
                                    accum_likelihood = if (current_tree_index >= tier_tree_ids.len)
                                        total_likelihood
                                    else
                                        accum_likelihood + @field(
                                            ForestSettings,
                                            @tagName(tier_tree_ids[current_tree_index]),
                                        ).likelihood;
                                    next_transition = @as(i32, @intFromFloat(accum_likelihood / total_likelihood * quantization));
                                }
                            }
                            break :tree_range range;
                        };
                        break :tier .{
                            .cache = undefined,
                            .density = density_tier,
                            .tree_range = tree_range,
                        };
                    };
                }
                break :density_tiers .{ tiers, min_tier };
            };

            return struct {
                pub const Settings = ForestSettings;
                trees: [trees.len]Tree,
                density_tiers: @TypeOf(density_tiers),

                pub fn init(allocator: std.mem.Allocator) @This() {
                    var result = @This(){
                        .trees = trees,
                        .density_tiers = density_tiers,
                    };
                    for (&result.density_tiers) |*maybe_density_tier| if (maybe_density_tier.*) |*density_tier| {
                        density_tier.cache = ChunkCache.init(allocator);
                    };
                    return result;
                }

                pub fn densityTierToIndex(density_tier: i32) usize {
                    return @intCast(density_tier - min_tier);
                }

                pub fn gatherSpawnsInBounds(self: *@This(), allocator: std.mem.Allocator, bounds: Bounds) ![]const Spawn {
                    var spawns = std.ArrayList(Spawn).init(allocator);
                    for (&self.density_tiers) |*maybe_density_tier| if (maybe_density_tier.*) |*density_tier| {
                        const coord_span: Vec2 = @splat(density_tier.getSpan());
                        const chunk_span = coord_span * @as(Vec2, @splat(chunk_size));
                        var chunk_coords = CoordIterator.init(
                            @intFromFloat(@floor(bounds.min / chunk_span)),
                            @intFromFloat(@ceil((bounds.min + bounds.size) / chunk_span)),
                        );
                        while (chunk_coords.next()) |chunk_coord| {
                            const chunk = try density_tier.getChunk(&self.trees, .{
                                chunk_coord[0],
                                chunk_coord[1],
                            });
                            const chunk_offset = @as(Vec2, @floatFromInt(chunk_coord)) * chunk_span;
                            const min: Coord = @splat(0);
                            const max: Coord = @splat(chunk_size - 1);
                            var coords = CoordIterator.init(
                                std.math.clamp(@as(Coord, @intFromFloat(@floor((bounds.min - chunk_offset) / coord_span))), min, max),
                                std.math.clamp(@as(Coord, @intFromFloat(@ceil((bounds.min - chunk_offset + bounds.size) / coord_span))), min, max),
                            );
                            while (coords.next()) |coord| if (chunk[@intCast(coord[1])][@intCast(coord[0])]) |spawn|
                                try spawns.append(spawn);
                        }
                    };
                    return spawns.items;
                }

                pub fn getChunk(self: *@This(), density_coord: DensityCoord) !*const Chunk {
                    const density_tier = &self.density_tiers[densityTierToIndex(density_coord.density)];
                    return if (density_tier.*) |*tier|
                        try tier.getChunk(.{ density_coord.x, density_coord.y })
                    else
                        @panic("Tried to access a chunk from a tier that isn't defined!");
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
    const AsciiForest = Forest(Ascii, 16);
    const Spawner = AsciiForest.spawner(struct {
        pub const grass1 = AsciiForest.Tree{
            .prefab = .{ .character = '`' },
            .density_tier = -2,
            .likelihood = 0.05,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        };
        pub const grass2 = AsciiForest.Tree{
            .prefab = .{ .character = ',' },
            .density_tier = -2,
            .likelihood = 0.05,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        };
        pub const little_tree = AsciiForest.Tree{
            .prefab = .{ .character = 't' },
            .density_tier = 1,
            .likelihood = 0.25,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        };
        pub const big_tree = AsciiForest.Tree{
            .prefab = .{ .character = 'T' },
            .density_tier = 2,
            .likelihood = 0.5,
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
    var spawner: Spawner = Spawner.init(allocator);

    // Spawn trees and Display in a large grid, that shows all density tiers together with random offsets 🌲
    const bounds = Bounds{
        .min = .{ -8, -8 },
        .size = .{ 16, 16 },
    };
    const spawns = try spawner.gatherSpawnsInBounds(allocator, bounds);

    const world_size = .{ .width = 128, .height = 64 };
    var world: [world_size.height][world_size.width]u8 = .{.{' '} ** world_size.width} ** world_size.height;
    for (spawns) |spawn| {
        const location: Coord = @intFromFloat(@floor(
            (Vec2{ spawn.position[0], spawn.position[2] } - bounds.min) /
                bounds.size *
                Vec2{ world_size.width, world_size.height },
        ));
        if (location[0] >= 0 and location[0] < world_size.width and
            location[1] >= 0 and location[1] < world_size.height)
            world[@intCast(location[1])][@intCast(location[0])] = spawn.prefab.character;
    }

    for (world) |row| {
        std.debug.print("{s}\n", .{row});
    }
}
