const std = @import("std");
const embed_content_dir = "src/resources/content/";
const content_dir = "content/";
const print = std.debug.print;

const ExportMeshes = struct {
    const BlendExport = struct {
        script_path: []const u8,
        blend_paths: []const []const u8,
    };
    allocator: std.mem.Allocator,
    blend_exports: []const BlendExport,
    step: std.Build.Step,
    pub fn create(b: *std.Build, blend_exports: []const BlendExport) *@This() {
        const self = b.allocator.create(@This()) catch @panic("OOM");
        self.* = .{
            .allocator = b.allocator,
            .blend_exports = blend_exports,
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "export_meshes",
                .owner = b,
                .makeFn = exportMeshes,
            }),
        };
        return self;
    }
    fn exportMeshes(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const self = @as(*ExportMeshes, @fieldParentPtr("step", step));

        var b = step.owner;

        var export_count: u32 = 0;

        for (self.blend_exports) |blend_export|
            for (blend_export.blend_paths) |blend_path| {
                const full_path = try std.fmt.allocPrint(self.allocator, embed_content_dir ++ "/{s}.blend", .{blend_path});

                var man = b.graph.cache.obtain();
                defer man.deinit();
                _ = try man.addFile(full_path, null);
                if (try step.cacheHit(&man)) {
                    _ = man.final();
                    continue;
                }

                print("Working on {s}", .{blend_path});
                var timer = try std.time.Timer.start();
                const res = try std.process.Child.run(.{
                    .allocator = self.allocator,
                    .cwd = try std.process.getCwdAlloc(self.allocator),
                    .argv = &[_][]const u8{
                        "blender",
                        full_path,
                        "--background",
                        "--python",
                        std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ embed_content_dir, blend_export.script_path }) catch unreachable,
                    },
                });
                print("stdout: {s}\n", .{res.stdout});
                if (res.stderr.len > 0) {
                    print("stderr: {s}\n", .{res.stderr});
                    return error.ExportFailed;
                }

                _ = man.final();
                try man.writeManifest();

                const ns = timer.read();
                print("Process took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
                export_count += 1;
            };
        if (export_count > 0) {
            print("Exported {d} meshes\n", .{export_count});
        }
    }
};

pub fn build(
    b: *std.Build,
) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const export_meshes = ExportMeshes.create(b, &.{
        .{ .script_path = "blend-to-json", .blend_paths = &.{
            "ebike",
            "Sonic (rough)",
        } },
    });

    const zglfw = b.dependency("zglfw", .{ .target = target, .x11 = false });
    const zgpu = b.dependency("zgpu", .{ .target = target });
    const zgui = b.dependency("zgui", .{ .target = target, .backend = .glfw_wgpu });
    const zbullet = b.dependency("zbullet", .{});
    const zmath = b.dependency("zmath", .{});
    const utils = b.createModule(.{
        .root_source_file = b.path("src/utils.zig"),
        .imports = &.{
            .{ .name = "zmath", .module = zmath.module("root") },
        },
    });
    const node_graph = b.createModule(.{
        .root_source_file = b.path("src/node_graph.zig"),
        .imports = &.{
            .{ .name = "utils", .module = utils },
        },
    });
    const resources = b.createModule(.{
        .root_source_file = b.path("src/resources.zig"),
        .imports = &.{
            .{ .name = "zmath", .module = zmath.module("root") },
            .{ .name = "utils", .module = utils },
        },
    });
    const game = b.createModule(.{
        .root_source_file = b.path("src/game.zig"),
        .imports = &.{
            .{ .name = "zmath", .module = zmath.module("root") },
            .{ .name = "zbullet", .module = zbullet.module("root") },
            .{ .name = "node_graph", .module = node_graph },
            .{ .name = "resources", .module = resources },
            .{ .name = "utils", .module = utils },
        },
    });

    // Tests (default)
    {
        const main_tests = b.addTest(.{ .root_source_file = .{ .cwd_relative = "src/tests.zig" } });
        main_tests.root_module.addImport("zmath", zmath.module("root"));
        const run_unit_tests = b.addRunArtifact(main_tests);
        const test_step = b.step("test", "run tests");
        test_step.dependOn(&run_unit_tests.step);
        b.default_step.dependOn(test_step);
    }

    // // Check
    // {
    //     const check = b.addExecutable(.{
    //         .target = target,
    //         .optimize = optimize,
    //         .name = "check_exe",
    //         .root_source_file = b.path("src/glfw.zig"),
    //         // .root_source_file = b.path("src/game/wasm_entry.zig"),
    //         // .root_source_file = b.path("src/test_perf.zig"),
    //     });
    //     @import("zgpu").addLibraryPathsTo(check);

    //     check.root_module.addImport("game", game);
    //     check.root_module.addImport("utils", utils);
    //     check.root_module.addImport("zmath", zmath.module("root"));
    //     check.root_module.addImport("node_graph", node_graph);
    //     check.root_module.addImport("zglfw", zglfw.module("root"));
    //     check.root_module.addImport("zgpu", zgpu.module("root"));
    //     check.root_module.addImport("zgui", zgui.module("root"));

    //     check.linkSystemLibrary("X11");

    //     check.linkLibrary(zglfw.artifact("glfw"));
    //     check.linkLibrary(zgpu.artifact("zdawn"));
    //     check.linkLibrary(zgui.artifact("imgui"));
    //     check.linkLibrary(zbullet.artifact("cbullet"));

    //     const check_options = b.addOptions();
    //     check.root_module.addOptions("build_options", check_options);
    //     check_options.addOption([]const u8, "content_dir", content_dir);

    //     const check_step = b.step("check", "Check if wasm compiles");
    //     check_step.dependOn(&check.step);
    // }

    // Exe glfw
    {
        var exe = b.addExecutable(.{
            .name = "game_exe",
            .root_source_file = b.path("src/glfw.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe.use_llvm = false;

        // @import("zgpu").addLibraryPathsTo(exe);

        exe.root_module.addImport("game", game);
        exe.root_module.addImport("utils", utils);
        exe.root_module.addImport("resources", resources);
        exe.root_module.addImport("zmath", zmath.module("root"));
        exe.root_module.addImport("node_graph", node_graph);
        exe.root_module.addImport("zglfw", zglfw.module("root"));
        exe.root_module.addImport("zgpu", zgpu.module("root"));
        exe.root_module.addImport("zgui", zgui.module("root"));

        // exe.linkSystemLibrary("X11");

        // exe.linkLibrary(zglfw.artifact("glfw"));
        // exe.linkLibrary(zgpu.artifact("zdawn"));
        // exe.linkLibrary(zgui.artifact("imgui"));
        // exe.linkLibrary(zbullet.artifact("cbullet"));

        exe.step.dependOn(&export_meshes.step);

        const exe_options = b.addOptions();
        exe.root_module.addOptions("build_options", exe_options);
        exe_options.addOption([]const u8, "content_dir", content_dir);

        const install_artifact = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "../bin" } } });
        const install_step = b.step("glfw", "build glfw entrypoint");
        install_step.dependOn(&install_artifact.step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&install_artifact.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_cmd.step.dependOn(&install_artifact.step);
        const run_step = b.step("glfw-run", "run the glfw entrypoint");
        run_step.dependOn(&run_cmd.step);
    }
}
