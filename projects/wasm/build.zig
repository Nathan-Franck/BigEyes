const std = @import("std");

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn build(b: *std.Build) !*std.Build.Step {
    var static_lib = b.addSharedLibrary(.{
        .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        .optimize = .Debug,
        .name = "wasm",
        .root_source_file = .{ .path = thisDir() ++ "/webgl.zig" },
    });
    var install = b.addInstallArtifact(static_lib, .{});
    return &install.step;
}
