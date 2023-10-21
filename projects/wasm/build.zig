const std = @import("std");

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn build(b: *std.Build) !*std.Build.Step {
    var static_lib = b.addSharedLibrary(.{
        .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        .optimize = .Debug,
        .name = "wasm",
        .root_source_file = .{ .path = thisDir() ++ "/index.zig" },
    });
    static_lib.rdynamic = true;

    const zmath_pkg = @import("../../libs/zig-gamedev/libs/zmath/build.zig").package(b, static_lib.target, static_lib.optimize, .{});
    zmath_pkg.link(static_lib);

    var path_first = thisDir() ++ "/../../libs/subdiv/subdiv.zig";
    static_lib.addModule("subdiv", b.createModule(.{
        .source_file = .{ .path = path_first },
        .dependencies = &.{
            .{ .name = "zmath", .module = zmath_pkg.zmath },
        },
    }));
    std.debug.print("path_first: {s}\n", .{path_first});

    var install = b.addInstallArtifact(static_lib, .{});
    return &install.step;
}
