const std = @import("std");
const Builder = std.build.Builder;
const fs = std.fs;

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn build(
    b: *Builder,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Step {
    const exe = b.addExecutable(.{
        .name = "snake",
        .root_source_file = .{ .path = thisDir() ++ "/src/main.zig" },
        .main_mod_path = .{ .path = thisDir() },
        .target = target,
        .optimize = optimize,
    });
    if (exe.target.isWindows()) {
        try exe.addVcpkgPaths(.dynamic);
        if (exe.vcpkg_bin_path) |path| {
            std.debug.print("vcpkg_bin_path: {s}\n", .{path});
            const sdl2dll_path = try std.fs.path.join(b.allocator, &[_][]const u8{ path, "SDL2.dll" });
            const install_sdl = b.addInstallBinFile(.{ .path = sdl2dll_path }, "SDL2.dll");
            exe.step.dependOn(&install_sdl.step);
            std.debug.print("sdl2dll_path: {s}\n", .{sdl2dll_path});
        }
        exe.subsystem = .Windows;
        exe.linkSystemLibrary("Shell32");
    }
    exe.addIncludePath(.{ .path = thisDir() ++ "/src/c" });
    exe.addIncludePath(.{ .path = thisDir() ++ "/lib/gl2/include" });
    exe.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/src/c/gl2_impl.c" }, .flags = &.{ "-std=c99", "-D_CRT_SECURE_NO_WARNINGS", "-Ilib/gl2/include" } });
    if (exe.target.isDarwin()) {
        exe.addIncludePath(.{ .path = thisDir() ++ "/opt/homebrew/include" });
        exe.addLibraryPath(.{ .path = thisDir() ++ "/opt/homebrew/lib" });
        exe.linkFramework("OpenGL");
    } else if (exe.target.isWindows()) {
        exe.linkSystemLibrary("opengl32");
    } else {
        exe.linkSystemLibrary("gl");
    }
    exe.linkSystemLibrary("SDL2");
    exe.linkLibC();
    const install_artifact = b.addInstallArtifact(exe, .{});

    const zmath_pkg = @import("../../libs/zig-gamedev/libs/zmath/build.zig").package(b, exe.target, exe.optimize, .{});
    zmath_pkg.link(exe);
    exe.addModule("subdiv", b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/../../libs/subdiv/subdiv.zig" },
        .dependencies = &.{
            .{ .name = "zmath", .module = zmath_pkg.zmath },
        },
    }));

    return &install_artifact.step;
}
