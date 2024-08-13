const std = @import("std");

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

        pub const Chunk = [chunk_size][chunk_size]?Spawn;

        chunks: std.AutoHashMap(@Vector(3, i32), Chunk),

        fn spawner(ForestSettings: type) type {
            const trees = unpack: {
                const decls: []const std.builtin.Type.Declaration = @typeInfo(ForestSettings).Struct.decls;
                var trees: []const Tree = &.{};
                for (decls) |decl_definition| {
                    const tree: Tree = @field(ForestSettings, decl_definition.name);
                    trees = trees ++ .{tree};
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
                var tree_range: [quantization]?*const Tree = .{null} ** quantization;
                var current_tree_index: u32 = 0;
                var accum_likelihood: f32 = trees[current_tree_index].likelihood;
                var next_transition: i32 = @as(i32, @intFromFloat(accum_likelihood / total_likelihood * quantization));
                for (&tree_range, 0..) |*cell, cell_index| {
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
                break :calc tree_range;
            };

            return struct {
                pub fn getChunk() Chunk {
                    var rand = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
                    _ = &rand; // autofix
                    var chunk: Chunk = undefined;
                    for (&chunk) |*row| {
                        for (row) |*item| {
                            const samp = tree_range[
                                @intCast(@mod(
                                    rand.next(),
                                    quantization,
                                ))
                            ];
                            item.* = if (samp) |tree|
                                Spawn{
                                    .prefab = &tree.prefab,
                                    .position = undefined,
                                    .rotation = undefined,
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
            .likelihood = 0.25,
            .prefab = .{ .character = 'i' },
        };
        pub const big_tree = AsciiForest.Tree{
            .likelihood = 0.25,
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
    const chunk = Spawner.getChunk();
    const allocator = std.heap.page_allocator;
    for (chunk) |row| {
        var line_data = std.ArrayList(u8).init(allocator);
        for (row) |maybe_item| {
            try line_data.append(if (maybe_item) |item| item.prefab.character else '_');
            try line_data.append(' ');
        }
        std.debug.print("{s}\n", .{line_data.items});
    }

    // TODO - Spawn trees and Display in a large grid, that shows all density tiers together with random offsets 🌲

}
