const game = @import("./game/game.zig");
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const defins = game.nodes;
    const influence_ranges = try defins.calculateTerrainDensityInfluenceRange(allocator, .{});
    var timer = try std.time.Timer.start();
    const result = try defins.displayTerrain(allocator, .{
        .tier_index_to_influence_range = influence_ranges.tier_index_to_influence_range,
    });
    const time = timer.read() / 1_000_000;
    std.debug.print("Hi! {any} in time {d}\n", .{ result.terrain_mesh.position.len, time });
}
