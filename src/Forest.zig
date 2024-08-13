const std = @import("std");
const zm = @import("./zmath/main.zig");

const Vec4 = @Vector(4, f32);

pub fn Forest(Prefab: type, comptime chunk_size: i32) type {
    return struct {
        pub const Tree = struct {
            pub const SpawnRadius = struct {
                tree: *const Tree,
                radius: f32,
                likelihood_change: f32,
            };
            spawn_radius: ?[]const SpawnRadius = null,
            prefab: Prefab,
            likelihood: f32,
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
                    depth: i32,
                };

                const context = {};
                const rng = std.Random.DefaultPrng;
                const hashFn = std.hash_map.getAutoHashFn(struct { Coord, u32 }, @TypeOf(context));

                chunks: Chunks,
                const coord_indices = enum {
                    X,
                    Y,
                    Z,
                };

                pub fn getChunk(coord: Coord) Chunk {
                    const spacing = std.math.pow(f32, 2.0, @floatFromInt(coord.depth));
                    const offset = .{
                        .x = @as(f32, @floatFromInt(coord.x)) * spacing * chunk_size,
                        .z = @as(f32, @floatFromInt(coord.y)) * spacing * chunk_size,
                    };
                    var rand = .{
                        .spawn = rng.init(hashFn(context, .{ coord, 0 })),
                        .position = rng.init(hashFn(context, .{ coord, 1 })),
                        .rotation = rng.init(hashFn(context, .{ coord, 2 })),
                    };
                    var chunk: Chunk = undefined;
                    for (&chunk, 0..) |*row, y| {
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
                                        rand.rotation.random().float(f32) * std.math.pi * 2,
                                    ),
                                    .scale = undefined,
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
    const Trees = struct {
        pub const little_tree = AsciiForest.Tree{
            .likelihood = 0.20,
            .prefab = .{ .character = 'i' },
        };
        pub const big_tree = AsciiForest.Tree{
            .likelihood = 0.05,
            .prefab = .{ .character = '&' },
            .spawn_radius = &[_]AsciiForest.Tree.SpawnRadius{
                .{
                    .tree = &little_tree,
                    .radius = 10,
                    .likelihood_change = 1,
                },
            },
        };
    };
    const Spawner = AsciiForest.spawner(Trees);

    const chunk = Spawner.getChunk(.{ .x = 0, .y = 0, .depth = 8 });

    const allocator = std.heap.page_allocator;
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

    // TODO - Spawn trees and Display in a large grid, that shows all density tiers together with random offsets 🌲

}
