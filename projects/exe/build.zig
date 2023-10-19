const std = @import("std");
const content_dir = "content/";

fn exportMeshes(allocator: std.mem.Allocator, paths: []const []const u8) !void {
    for (paths) |path| {
        std.debug.print("Working on {s}", .{path});
        var timer = try std.time.Timer.start();
        const res = try std.ChildProcess.exec(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "blender",
                try std.fmt.allocPrint(allocator, "content/{s}.blend", .{path}),
                "--background",
                "--python",
                "content/custom-gltf.py",
            },
            .cwd = try std.process.getCwdAlloc(allocator),
        });
        std.debug.print("stdout: {s}\n", .{res.stdout});
        var ns = timer.read();
        std.debug.print("Process took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
    }
}

pub fn build(b: *std.Build) !*std.Build.Step {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "triangle_wgpu",
        .root_source_file = .{ .path = thisDir() ++ "/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();

    const zgui_pkg = @import("../../libs/zig-gamedev/libs/zgui/build.zig").package(b, exe.target, exe.optimize, .{ .options = .{ .backend = .glfw_wgpu } });
    const zmath_pkg = @import("../../libs/zig-gamedev/libs/zmath/build.zig").package(b, exe.target, exe.optimize, .{});
    const zglfw_pkg = @import("../../libs/zig-gamedev/libs/zglfw/build.zig").package(b, exe.target, exe.optimize, .{ .options = .{ .shared = true } });
    const zpool_pkg = @import("../../libs/zig-gamedev/libs/zpool/build.zig").package(b, exe.target, exe.optimize, .{});
    const zgpu_pkg = @import("../../libs/zig-gamedev/libs/zgpu/build.zig").package(b, exe.target, exe.optimize, .{ .deps = .{ .zglfw = zglfw_pkg.zglfw, .zpool = zpool_pkg.zpool } });
    const zmesh_pkg = @import("../../libs/zig-gamedev/libs/zmesh/build.zig").package(b, exe.target, exe.optimize, .{});

    zgui_pkg.link(exe);
    zgpu_pkg.link(exe);
    zglfw_pkg.link(exe);
    zmath_pkg.link(exe);
    zmesh_pkg.link(exe);

    @import("../../libs/subdiv/build.zig").addModule(b, exe, .{ .zmath = zmath_pkg.zmath });

    var allocator = std.heap.page_allocator;
    try exportMeshes(allocator, &.{"boss"});

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "content_dir", content_dir);

    const install_content_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/../../" ++ content_dir },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ content_dir,
    });
    exe.step.dependOn(&install_content_step.step);

    // Windows hax
    exe.want_lto = false;
    if (exe.optimize == .ReleaseFast)
        exe.strip = true;

    // exe.single_threaded = true;

    const install_artifact = b.addInstallArtifact(exe, .{});
    // const run_cmd = b.addRunArtifact(exe);
    // run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }
    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);

    return &install_artifact.step;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
