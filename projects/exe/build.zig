const std = @import("std");
const content_dir = "content/";

const ExportMeshes = struct {
    allocator: std.mem.Allocator,
    files: []const []const u8,
    step: std.build.Step,
    pub fn create(b: *std.Build, files: []const []const u8) *ExportMeshes {
        var self = b.allocator.create(ExportMeshes) catch @panic("OOM");
        self.* = .{
            .allocator = b.allocator,
            .files = files,
            .step = std.build.Step.init(.{
                .id = .custom,
                .name = "export_meshes",
                .owner = b,
                .makeFn = exportMeshes,
            }),
        };
        return self;
    }
    fn exportMeshes(step: *std.build.Step, prog_node: *std.Progress.Node) !void {
        _ = prog_node;
        const self = @fieldParentPtr(ExportMeshes, "step", step);

        var b = step.owner;

        for (self.files) |file| {
            var full_path = try std.fmt.allocPrint(self.allocator, "content/{s}.blend", .{file});

            var man = b.cache.obtain();
            defer man.deinit();
            _ = try man.addFile(full_path, null);
            if (try step.cacheHit(&man)) {
                _ = man.final();
                continue;
            }
            _ = man.final();
            try man.writeManifest();

            std.debug.print("Working on {s}", .{file});
            var timer = try std.time.Timer.start();
            const res = try std.ChildProcess.run(.{
                .allocator = self.allocator,
                .argv = &[_][]const u8{
                    "blender",
                    full_path,
                    "--background",
                    "--python",
                    "content/custom-gltf.py",
                },
                .cwd = try std.process.getCwdAlloc(self.allocator),
            });
            std.debug.print("stdout: {s}\n", .{res.stdout});
            var ns = timer.read();
            std.debug.print("Process took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
        }
    }
};

pub fn build(b: *std.Build) !*std.Build.Step {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "triangle_wgpu",
        .root_source_file = .{ .path = thisDir() ++ "/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zgui_pkg = @import("../../libs/zig-gamedev/libs/zgui/build.zig").package(b, exe.target, exe.optimize, .{ .options = .{ .backend = .glfw_wgpu } });
    const zmath_pkg = @import("../../libs/zig-gamedev/libs/zmath/build.zig").package(b, exe.target, exe.optimize, .{});
    const zglfw_pkg = @import("../../libs/zig-gamedev/libs/zglfw/build.zig").package(b, exe.target, exe.optimize, .{ .options = .{ .shared = false } });
    const zpool_pkg = @import("../../libs/zig-gamedev/libs/zpool/build.zig").package(b, exe.target, exe.optimize, .{});
    const zgpu_pkg = @import("../../libs/zig-gamedev/libs/zgpu/build.zig").package(b, exe.target, exe.optimize, .{ .deps = .{ .zglfw = zglfw_pkg.zglfw, .zpool = zpool_pkg.zpool } });
    const zmesh_pkg = @import("../../libs/zig-gamedev/libs/zmesh/build.zig").package(b, exe.target, exe.optimize, .{});

    zgui_pkg.link(exe);
    zgpu_pkg.link(exe);
    zglfw_pkg.link(exe);
    zmath_pkg.link(exe);
    zmesh_pkg.link(exe);

    exe.addModule("subdiv", b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/../../libs/subdiv/subdiv.zig" },
        .dependencies = &.{
            .{ .name = "zmath", .module = zmath_pkg.zmath },
        },
    }));

    const export_meshes = ExportMeshes.create(b, &.{ "boss", "cube" });

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "content_dir", content_dir);

    const install_content_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/../../" ++ content_dir },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/" ++ content_dir,
    });
    exe.step.dependOn(&install_content_step.step);
    exe.step.dependOn(&export_meshes.step);

    // Windows hax
    exe.want_lto = false;
    if (exe.optimize == .ReleaseFast)
        exe.strip = true;

    // exe.single_threaded = true;

    // const install_lib_artifact = b.addInstallArtifact(zglfw_pkg.zglfw_c_cpp, .{});
    // const move_lib = b.addInstallBinFile(.{ .path = "zig-out/lib/zglfw.dll" }, "zglfw.dll");
    // move_lib.step.dependOn(&install_lib_artifact.step);
    // exe.step.dependOn(&move_lib.step);

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
