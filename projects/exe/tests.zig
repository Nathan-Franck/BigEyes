const std = @import("std");

test "load mesh" {
    const allocator = std.testing.allocator;
    const result = try @import("./MeshLoader.zig").getMeshes(allocator);
    _ = result;
}
