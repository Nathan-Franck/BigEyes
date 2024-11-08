const std = @import("std");
const zm = @import("zmath");
const util = .{
    .tree = @import("./tree.zig"),
};
pub const Vec4 = @Vector(4, f32);

pub const Vec2 = @Vector(2, f32);

pub const Bounds = struct {
    min: Vec2,
    size: Vec2,
};

// const wasm_entry = @import("./wasm_entry.zig");

pub const CoordIterator = @import("./CoordIterator.zig");
pub const Coord = CoordIterator.Coord;

pub fn Forest(comptime chunk_size: i32) type {
    return struct {
        pub const Tree = struct {
            pub const SpawnRadius = struct {
                tree: *const Tree,
                radius: f32,
                likelihood: f32,
            };
            spawn_radii: ?[]const SpawnRadius = null,
            density: i32,
            likelihood: f32,
            scale_range: util.tree.SmoothCurve,
        };

        pub fn spawner(ForestSettings: type) type {
            const local = struct {
                const DensityCoord = struct {
                    x: i32,
                    y: i32,
                    density: i32,
                };
                const TreeId = std.meta.DeclEnum(ForestSettings);
                const Spawn = struct {
                    id: u8,
                    position: Vec2,
                    rotation: Vec4,
                    scale: f32,
                };
                const Chunk = [chunk_size][chunk_size]?Spawn;
                const ChunkCache = std.AutoHashMap(DensityCoord, Chunk);
            };

            const quantization = 128;

            const trees = unpack: {
                const decls: []const std.builtin.Type.Declaration = @typeInfo(ForestSettings).@"struct".decls;
                var trees: [decls.len]Tree = undefined;
                for (decls, 0..) |decl_definition, i| {
                    trees[i] = @field(ForestSettings, decl_definition.name);
                }
                break :unpack trees;
            };

            const DensityTier = struct {
                const Self = @This();

                const context = {};
                const hashFn = std.hash_map.getAutoHashFn(struct { local.DensityCoord, u32 }, @TypeOf(context));

                density: i32,
                tree_range: [quantization]?u8,

                fn precalculate(
                    source: *const Self,
                ) Precalculated {
                    const span = std.math.pow(f32, 2.0, @floatFromInt(source.density));
                    const coord_span: Vec2 = @splat(span);
                    const chunk_span: Vec2 = coord_span * @as(Vec2, @splat(chunk_size));
                    return .{
                        .source = source,
                        .span = span,
                        .coord_span = coord_span,
                        .chunk_span = chunk_span,
                        .inverse_coord_span = @as(Vec2, @splat(1)) / coord_span,
                        .inverse_chunk_span = @as(Vec2, @splat(1)) / chunk_span,
                    };
                }

                const Precalculated = struct {
                    source: *const Self,

                    span: f32,
                    coord_span: Vec2,
                    chunk_span: Vec2,
                    inverse_coord_span: Vec2,
                    inverse_chunk_span: Vec2,

                    pub fn intToFloatRange(i: u64) f32 {
                        return @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(std.math.maxInt(u64)));
                    }

                    pub fn gatherSpawnsInBounds(
                        self: *const @This(),
                        chunk_cache: *local.ChunkCache,
                        bounds: Bounds,
                        spawns: *std.ArrayList(*const local.Spawn),
                    ) !void {
                        var chunk_coords = CoordIterator.init(
                            @intFromFloat(@floor(bounds.min * self.inverse_chunk_span)),
                            @intFromFloat(@ceil((bounds.min + bounds.size) * self.inverse_chunk_span)),
                        );
                        while (chunk_coords.next()) |chunk_coord| {
                            const chunk = try self.getChunk(chunk_cache, chunk_coord);
                            const chunk_offset = @as(Vec2, @floatFromInt(chunk_coord)) * self.chunk_span;
                            const min: Coord = @splat(0);
                            const max: Coord = @splat(chunk_size);
                            var coords = CoordIterator.init(
                                std.math.clamp(@as(Coord, @intFromFloat(@floor((bounds.min - chunk_offset) * self.inverse_coord_span))), min, max),
                                std.math.clamp(@as(Coord, @intFromFloat(@ceil((bounds.min - chunk_offset + bounds.size) * self.inverse_coord_span))), min, max),
                            );
                            while (coords.next()) |coord| if (chunk[@intCast(coord[1])][@intCast(coord[0])]) |*spawn| {
                                try spawns.append(spawn);
                            };
                        }
                    }

                    pub fn getChunk(
                        self: *const @This(),
                        cache: *local.ChunkCache,
                        coord: Coord,
                    ) !*local.Chunk {
                        const density = self.source.density;

                        const chunk = blk: {
                            const chunk_entry = try cache.getOrPut(local.DensityCoord{
                                .x = coord[0],
                                .y = coord[1],
                                .density = density,
                            });
                            if (chunk_entry.found_existing) {
                                return chunk_entry.value_ptr;
                            }
                            break :blk chunk_entry.value_ptr;
                        };
                        const chunk_offset = .{
                            .x = @as(f32, @floatFromInt(coord[0])) * self.span * chunk_size,
                            .z = @as(f32, @floatFromInt(coord[1])) * self.span * chunk_size,
                        };

                        for (chunk, 0..) |*row, y| {
                            for (row, 0..) |*item, x| {
                                const hash_coord: local.DensityCoord = .{
                                    .x = coord[0] * chunk_size + @as(i32, @intCast(x)),
                                    .y = coord[1] * chunk_size + @as(i32, @intCast(y)),
                                    .density = density,
                                };
                                const rand = .{
                                    .spawn = hashFn(context, .{ hash_coord, 0 }),
                                    .position_x = hashFn(context, .{ hash_coord, 1 }),
                                    .position_y = hashFn(context, .{ hash_coord, 1 }),
                                    .rotation = hashFn(context, .{ hash_coord, 2 }),
                                    .scale = hashFn(context, .{ hash_coord, 3 }),
                                };
                                item.* = if (self.source.tree_range[
                                    @intCast(rand.spawn % quantization)
                                ]) |tree_id| blk: {
                                    const tree = trees[tree_id];
                                    break :blk local.Spawn{
                                        .id = tree_id,
                                        .position = .{
                                            chunk_offset.x + (@as(f32, @floatFromInt(x)) + intToFloatRange(rand.position_x)) * self.span,
                                            chunk_offset.z + (@as(f32, @floatFromInt(y)) + intToFloatRange(rand.position_y)) * self.span,
                                        },
                                        .rotation = zm.quatFromAxisAngle(
                                            zm.loadArr3(.{ 0, 1, 0 }),
                                            intToFloatRange(rand.rotation) * 360 * std.math.rad_per_deg,
                                        ),
                                        .scale = tree.scale_range.sample(intToFloatRange(rand.scale)),
                                    };
                                } else null;
                            }
                        }

                        return chunk;
                    }
                };
            };

            const min_tier, const tier_len = blk: {
                var min_tier: i32 = trees[0].density;
                var max_tier: i32 = trees[0].density;
                for (trees[1..]) |tree| {
                    min_tier = @min(min_tier, tree.density);
                    max_tier = @max(max_tier, tree.density);
                }
                const tier_len = max_tier - min_tier + 1;
                break :blk .{ min_tier, tier_len };
            };

            return struct {
                pub const ChunkCache = local.ChunkCache;
                pub const Settings = ForestSettings;
                pub const length = trees.len;
                pub const TreeId = local.TreeId;
                pub const density_tiers: [tier_len]?DensityTier.Precalculated = blk: {
                    var tiers: [tier_len]?DensityTier.Precalculated = undefined;
                    for (&tiers, 0..) |*tier, tier_index| {
                        var tier_tree_ids: []const u32 = &.{};
                        const density = @as(i32, tier_index) + min_tier;
                        const tree_decls = @typeInfo(ForestSettings).@"struct".decls;
                        for (tree_decls, 0..) |tree_decl, decl_index| {
                            const tree = @field(ForestSettings, tree_decl.name);
                            if (tree.density == density) {
                                tier_tree_ids = tier_tree_ids ++ .{decl_index};
                            }
                        }
                        tier.* = if (tier_tree_ids.len == 0) null else tier: {
                            const density_tier = DensityTier{
                                .density = density,
                                .tree_range = tree_range: {
                                    var range: [quantization]?u8 = .{null} ** quantization;
                                    var current_tree_index: u32 = 0;
                                    var accum_likelihood: f32 = @field(
                                        ForestSettings,
                                        @typeInfo(ForestSettings).@"struct".decls[current_tree_index].name,
                                    ).likelihood;
                                    const total_likelihood = total_likelihood: {
                                        var total: f32 = 0;
                                        for (tier_tree_ids) |tree_id|
                                            total += @field(
                                                ForestSettings,
                                                @typeInfo(ForestSettings).@"struct".decls[tree_id].name,
                                            ).likelihood;
                                        break :total_likelihood @max(total, 1);
                                    };
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
                                                    @typeInfo(ForestSettings).@"struct".decls[current_tree_index].name,
                                                ).likelihood;
                                            next_transition = @as(i32, @intFromFloat(accum_likelihood / total_likelihood * quantization));
                                        }
                                    }
                                    break :tree_range range;
                                },
                            };
                            break :tier density_tier.precalculate();
                        };
                    }
                    break :blk tiers;
                };

                pub fn densityTierToIndex(density_tier: i32) usize {
                    return @intCast(density_tier - min_tier);
                }

                pub fn gatherSpawnsInBoundsPerTier(
                    allocator: std.mem.Allocator,
                    chunk_cache: *ChunkCache,
                    bounds: []const Bounds,
                ) ![]const *const local.Spawn {
                    var spawns = try std.ArrayList(*const local.Spawn).initCapacity(allocator, 16);
                    for (density_tiers, 0..) |maybe_density_tier, tier_index| if (maybe_density_tier) |density_tier| {
                        try density_tier.gatherSpawnsInBounds(
                            chunk_cache,
                            bounds[tier_index],
                            &spawns,
                        );
                    };
                    return spawns.items;
                }

                pub fn gatherSpawnsInBounds(allocator: std.mem.Allocator, chunk_cache: *ChunkCache, bounds: Bounds) ![]const *const local.Spawn {
                    var spawns = try std.ArrayList(*const local.Spawn).initCapacity(allocator, 16);
                    for (density_tiers) |maybe_density_tier| if (maybe_density_tier) |density_tier| {
                        try density_tier.gatherSpawnsInBounds(
                            chunk_cache,
                            bounds,
                            &spawns,
                        );
                    };
                    return spawns.items;
                }

                pub fn getChunk(self: *@This(), density_coord: local.DensityCoord) !*const local.Chunk {
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
    const AsciiForest = Forest(16);
    const Spawner = AsciiForest.spawner(struct {
        pub const grass1 = AsciiForest.Tree{
            .density = -2,
            .likelihood = 0.05,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        };
        pub const grass2 = AsciiForest.Tree{
            .density = -2,
            .likelihood = 0.05,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        };
        pub const little_tree = AsciiForest.Tree{
            .density = 1,
            .likelihood = 0.25,
            .scale_range = .{ .x_range = .{ 0, 1 }, .y_values = &.{ 0.8, 1.0 } },
        };
        pub const big_tree = AsciiForest.Tree{
            .density = 2,
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
    const AsciiTree = struct {
        character: u8,
    };
    const trees = [_]AsciiTree{
        .{ .character = '`' },
        .{ .character = ',' },
        .{ .character = 't' },
        .{ .character = 'T' },
    };

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
        const id = @intFromEnum(spawn.id);
        const character = trees[id].character;

        const location: Coord = @intFromFloat(@floor(
            (Vec2{ spawn.position[0], spawn.position[2] } - bounds.min) /
                bounds.size *
                Vec2{ world_size.width, world_size.height },
        ));
        if (location[0] >= 0 and location[0] < world_size.width and
            location[1] >= 0 and location[1] < world_size.height)
            world[@intCast(location[1])][@intCast(location[0])] = character;
    }

    for (world) |row| {
        std.debug.print("{s}\n", .{row});
    }
}
