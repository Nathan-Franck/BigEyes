const game = @import("./game/game.zig");
const std = @import("std");

test "performance" {
    const allocator = std.testing.allocator;
    const defins = game.graph_nodes;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer {
        _ = arena.reset(.retain_capacity);
        arena.deinit();
    }
    const influence_ranges = try defins.calculateTerrainDensityInfluenceRange(arena.allocator(), .{ .size_multiplier = 1 });
    {
        var timer = try std.time.Timer.start();
        const result = try defins.displayTerrain(arena.allocator(), .{
            .terrain_sampler = influence_ranges.terrain_sampler,
        });
        const time = timer.read() / 1_000_000;
        _ = time;
        _ = result;
        // std.debug.print("Hi! {any} in time {d}\n", .{ result.terrain_mesh.position.len, time });
    }

    {
        var timer = try std.time.Timer.start();
        defer {
            const time = timer.read() / 1_000_000;
            _ = time;
            // std.debug.print("Part #2! time {d}\n", .{time});
        }
        const NodeGraph = game.NodeGraph;
        var node_graph = try NodeGraph.init(.{
            .allocator = allocator,
            .inputs = game.graph_inputs,
            .store = game.graph_store,
        });
        _ = try node_graph.update(.{});
        node_graph.deinit();
    }
}
