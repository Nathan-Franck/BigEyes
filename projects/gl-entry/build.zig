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
            const sdl2dll_path = try std.fs.path.join(b.allocator, &[_][]const u8{ path, "SDL2.dll" });
            b.installBinFile(sdl2dll_path, "SDL2.dll");
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

    if (exe.target.isWindows()) {
        const outputresource = try std.mem.join(b.allocator, "", &[_][]const u8{ "-outputresource:", "zig-cache\\bin\\", exe.out_filename, ";1" });
        const mt_exe = "C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.18362.0\\x64\\mt.exe";
        const manifest_cmd = b.addSystemCommand(&[_][]const u8{ mt_exe, "-manifest", "app.manifest", outputresource });
        manifest_cmd.step.dependOn(b.getInstallStep());
        const manifest_step = b.step("manifest", "Embed manifest");
        manifest_step.dependOn(&manifest_cmd.step);
    }

    return &install_artifact.step;
}
