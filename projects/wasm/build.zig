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

    const zmath_pkg = @import("zmath").package(b, static_lib.target, static_lib.optimize, .{});

    const subdiv = b.addModule("subdiv", .{
        .root_source_file = .{ .path = thisDir() ++ "/../../libs/subdiv/subdiv.zig" },
        .imports = &.{
            .{ .name = "zmath", .module = zmath_pkg.zmath },
        },
    });

    zmath_pkg.link(static_lib);
    static_lib.addImport("subdiv", subdiv);

    var install = b.addInstallArtifact(static_lib, .{});
    return &install.step;
}
