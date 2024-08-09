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

    const Trees = struct {
        pub const little_tree = AsciiForest.Tree{
            .prefab = .{ .character = 'i' },
        };
        pub const big_tree = AsciiForest.Tree{
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

    // I'm a little sad that my variable id's go away once packed into a tuple :/
    const typeInfo: std.builtin.Type = @typeInfo(Trees);
    const decls = typeInfo.Struct.decls;

    std.debug.print("fields are {any}\n", .{decls});

    // TODO - Spawn trees and Display in a large grid, that shows all density tiers together with random offsets 🌲

}
