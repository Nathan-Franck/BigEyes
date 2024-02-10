const std = @import("std");

test "json load" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const polygonJSON = json: {
        const json_data = std.fs.cwd().readFileAlloc(allocator, "content/cube.blend.json", 512 * 1024 * 1024) catch |err| {
            std.log.err("Failed to read JSON file: {}", .{err});
            return err;
        };
        const Config = []const struct {
            name: []const u8,
            polygons: []const []const u32,
            vertices: []const @Vector(3, f32),
        };
        break :json std.json.parseFromSlice(Config, allocator, json_data, .{}) catch |err| {
            std.log.err("Failed to parse JSON: {}", .{err});
            return err;
        };
    };
    try std.testing.expectEqual(polygonJSON.value.len, 1);
}
