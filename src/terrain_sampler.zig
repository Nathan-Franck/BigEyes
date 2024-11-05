const std = @import("std");
const Stamp = @import("./Stamp.zig");
const Vec2 = @import("./forest.zig").Vec2;
const Bounds = @import("./forest.zig").Bounds;

pub fn TerrainSampler(
    TerrainSpawner: type,
    TerrainStamps: type,
) type {
    return struct {
        const length = TerrainSpawner.density_tiers.len;
        tier_index_to_influence_range: [length]f32,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            var tier_index_to_influence_range: [length]f32 = undefined;
            for (TerrainSpawner.density_tiers, 0..) |maybe_tier, tier_index|
                tier_index_to_influence_range[tier_index] = if (maybe_tier) |tier| blk: {
                    var trees = std.AutoArrayHashMap(TerrainSpawner.TreeId, void).init(allocator);
                    for (tier.tree_range) |maybe_tree_id| if (maybe_tree_id) |tree_id| {
                        const enum_tree_id: TerrainSpawner.TreeId = @enumFromInt(tree_id);
                        try trees.put(enum_tree_id, {});
                    } else continue;
                    const Stamps = @typeInfo(TerrainStamps).@"struct".decls;
                    var index_to_stamp_data: [Stamps.len]Stamp = undefined;
                    inline for (Stamps, 0..) |decl, stamp_index| {
                        index_to_stamp_data[stamp_index] = @field(TerrainStamps, decl.name);
                    }
                    var max_size: f32 = 0;
                    for (trees.keys()) |tree_index| {
                        const size = index_to_stamp_data[@intFromEnum(tree_index)].size;
                        max_size = @max(max_size, size);
                    }
                    break :blk max_size;
                } else 0;
            return .{
                .tier_index_to_influence_range = tier_index_to_influence_range,
            };
        }

        const Self = @This();

        pub fn loadCache(
            source: @This(),
            terrain_chunk_cache: *TerrainSpawner.ChunkCache,
        ) struct {
            source: Self,
            terrain_chunk_cache: *TerrainSpawner.ChunkCache,
            pub fn sample(
                cached: @This(),
                allocator: std.mem.Allocator,
                pos_2d: Vec2,
            ) !f32 {
                return cached.source.sample(allocator, cached.terrain_chunk_cache, pos_2d);
            }
        } {
            return .{
                .source = source,
                .terrain_chunk_cache = terrain_chunk_cache,
            };
        }

        pub fn sample(
            self: *const @This(),
            allocator: std.mem.Allocator,
            terrain_chunk_cache: *TerrainSpawner.ChunkCache,
            pos_2d: Vec2,
        ) !f32 {
            const bounds = blk: {
                var bounds: [TerrainSpawner.density_tiers.len]Bounds = undefined;
                for (self.tier_index_to_influence_range, 0..) |influence_range, tier_index| {
                    const size_2d = @as(Vec2, @splat(influence_range));
                    bounds[tier_index] = Bounds{
                        .min = pos_2d - size_2d * @as(Vec2, @splat(0.5)),
                        .size = size_2d,
                    };
                }
                break :blk bounds;
            };

            const spawns = try TerrainSpawner.gatherSpawnsInBoundsPerTier(
                allocator,
                terrain_chunk_cache,
                &bounds,
            );

            const Stamps = @typeInfo(TerrainStamps).@"struct".decls;
            var index_to_stamp_data: [Stamps.len]Stamp = undefined;
            inline for (Stamps, 0..) |decl, stamp_index| {
                index_to_stamp_data[stamp_index] = @field(TerrainStamps, decl.name);
            }

            var height: f32 = 0;
            for (spawns) |spawn| {
                const stamp = index_to_stamp_data[spawn.id];
                if (stamp.getHeight(spawn.position, pos_2d)) |stamp_height|
                    height = @max(height, stamp_height);
            }

            return height;
        }
    };
}
