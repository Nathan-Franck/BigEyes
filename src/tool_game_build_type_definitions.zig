const std = @import("std");
const typescriptTypeOf = @import("type_definitions.zig").typescriptTypeOf;

pub fn main() !void {
    const interface = @import("./game.zig");
    const allocator = std.heap.page_allocator;
    try build_typescript_type(allocator, interface, "src", "../bin/game.d.ts");
}

pub fn build_typescript_type(allocator: std.mem.Allocator, interface: anytype, folder_path: []const u8, file_name: []const u8) !void {
    const typeInfo = comptime typescriptTypeOf(interface, .{ .first = true });
    const contents = "export type WasmInterface = " ++ typeInfo;
    const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ folder_path, file_name });
    std.fs.cwd().makeDir(folder_path) catch {};
    std.fs.cwd().deleteFile(file_path) catch {};
    const file = try std.fs.cwd().createFile(file_path, .{});
    try file.writeAll(contents);
    std.debug.print("Wrote file to {s}\n", .{file_path});
}
