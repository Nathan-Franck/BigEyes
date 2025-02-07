const std = @import("std");

comptime {
    _ = @import("game");
    _ = @import("./test_perf.zig");
    // _ = @import("./graph_runtime.zig");
}
