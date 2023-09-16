const std = @import("std");
const zsdl = @import("libs/zig-gamedev/libs/zsdl/build.zig");
const zopengl = @import("libs/zig-gamedev/libs/zopengl/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const zsdl_pkg = zsdl.package(b, target, optimize, .{});
    const zopengl_pkg = zopengl.package(b, target, optimize, .{ .options = .{ .api = .raw } });

    zsdl_pkg.link(exe);
    zopengl_pkg.link(exe);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
