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
        };

        pub const Spawn = struct {
            tree: *const Tree,
            position: Vec4,
            rotation: Vec4,
            scale: f32,
        };

        pub const Chunk = [chunk_size][chunk_size]?Spawn;

        chunks: std.AutoHashMap(@Vector(3, i32), Chunk),
    };
}

test "Ascii Forest" {
    std.debug.print("{s}\n", .{"Hello!"});
    const Ascii = struct {
        character: u8,
    };
    const AsciiForest = Forest(Ascii, 5);

    const little_tree = AsciiForest.Tree{
        .prefab = .{ .character = 'i' },
    };
    const big_tree = AsciiForest.Tree{
        .prefab = .{ .character = '&' },
        .spawn_radius = &[_]AsciiForest.Tree.SpawnRadius{
            .{
                .tree = &little_tree,
                .radius = 10,
                .likelihood_change = 1,
            },
        },
    };
    const settings = &.{ little_tree, big_tree };
    _ = settings; // autofix
    std.debug.print("HI!\n", .{});
}
