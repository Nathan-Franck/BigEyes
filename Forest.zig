const std = @import("std");

const Vec4 = @Vector(4, f32);

pub fn Forest(Prefab: type, comptime chunk_size: i32) type {
    return struct {
        pub const Settings = struct {
            pub const SpawnRadius = struct {
                setting: *const Settings(Prefab),
                radius: f32,
                likelihood_change: f32,
            };
            spawn_radius: []const SpawnRadius,
            prefab: Prefab,
        };

        pub const Spawn = struct {
            settings: *const Settings,
            position: Vec4,
            rotation: Vec4,
            scale: f32,
        };

        pub const Chunk = struct {
            spawns: [chunk_size][chunk_size]?Spawn,
        };

        pub const Data = struct {
            chunks: std.AutoHashMap(@Vector(i32, 3), Chunk),
        };
    };
}
