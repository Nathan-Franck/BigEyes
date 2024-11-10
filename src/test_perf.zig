const game = @import("./game/game.zig");
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const defins = game.nodes;
    const influence_ranges = try defins.calculateTerrainDensityInfluenceRange(allocator, .{});
    {
        var timer = try std.time.Timer.start();
        const result = try defins.displayTerrain(allocator, .{
            .terrain_sampler = influence_ranges.terrain_sampler,
        });
        const time = timer.read() / 1_000_000;
        std.debug.print("Hi! {any} in time {d}\n", .{ result.terrain_mesh.position.len, time });
    }

    {
        var timer = try std.time.Timer.start();
        defer {
            const time = timer.read() / 1_000_000;
            std.debug.print("Part #2! time {d}\n", .{time});
        }
        game.interface.init();
        _ = try game.interface.updateNodeGraph(.{});
    }
}
