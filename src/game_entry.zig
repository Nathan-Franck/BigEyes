const game = @import("./game/game.zig");
const std = @import("std");

pub export fn gameInit() void {
    game.interface.init();
}

pub export fn gameUpdate(inputs: *const game.NodeGraph.PartialSystemInputs, outputs: *game.NodeGraph.SystemOutputs) void {
    outputs.* = (game.interface.updateNodeGraph(inputs.*) catch unreachable).outputs;
}
