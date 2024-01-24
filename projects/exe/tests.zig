const std = @import("std");

test "load mesh" {
    const allocator = std.testing.allocator;
    _ = try @import("./MeshLoader.zig").getMeshes(allocator);
}
