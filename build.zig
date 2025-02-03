const std = @import("std");
const content_dir = "src/content/";

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
                const full_path = try std.fmt.allocPrint(self.allocator, content_dir ++ "/{s}.blend", .{blend_path});

                var man = b.graph.cache.obtain();
                defer man.deinit();
                _ = try man.addFile(full_path, null);
                if (try step.cacheHit(&man)) {
                    _ = man.final();
                    continue;
                }

                std.debug.print("Working on {s}", .{blend_path});
                var timer = try std.time.Timer.start();
                const res = try std.process.Child.run(.{
                    .allocator = self.allocator,
                    .cwd = try std.process.getCwdAlloc(self.allocator),
                    .argv = &[_][]const u8{
                        "blender",
                        full_path,
                        "--background",
                        "--python",
                        std.fmt.allocPrint(self.allocator, "{s}/{s}.py", .{ content_dir, blend_export.script_path }) catch @panic("OOM"),
                    },
                });
                std.debug.print("stdout: {s}\n", .{res.stdout});
                if (res.stderr.len > 0) {
                    std.debug.print("stderr: {s}\n", .{res.stderr});
                    return error.ExportFailed;
                }

                _ = man.final();
                try man.writeManifest();

                const ns = timer.read();
                std.debug.print("Process took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
                export_count += 1;
            };
        if (export_count > 0) {
            std.debug.print("Exported {d} meshes\n", .{export_count});
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

    const zbullet = b.dependency("zbullet", .{});
    const zmath = b.dependency("zmath", .{});

    // Tests (default)
    {
        const main_tests = b.addTest(.{ .root_source_file = .{ .cwd_relative = "src/tests.zig" } });
        main_tests.root_module.addImport("zmath", zmath.module("root"));
        const run_unit_tests = b.addRunArtifact(main_tests);
        const test_step = b.step("test", "run tests");
        test_step.dependOn(&run_unit_tests.step);
        b.default_step.dependOn(test_step);
    }

    // Typescript definitions
    {
        const exe = b.addExecutable(.{
            .name = "build_types",
            .root_source_file = .{ .cwd_relative = "src/tool_game_build_type_definitions.zig" },
            .target = target,
            .optimize = optimize,
        });
        exe.step.dependOn(&export_meshes.step);

        exe.root_module.addImport("zmath", zmath.module("root"));

        const install_artifact = b.addInstallArtifact(exe, .{});
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&install_artifact.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_cmd.step.dependOn(&install_artifact.step);

        const run_step = b.step("build_types", "Build the typescript types for use from the frontend");
        run_step.dependOn(&run_cmd.step);
    }

    // Check
    {
        const exe_check = b.addExecutable(.{
            .target = target,
            .optimize = optimize,
            .name = "check_exe",
            // .root_source_file = b.path("src/glfw_entry.zig"),
            .root_source_file = b.path("src/wasm_entry.zig"),
            // .root_source_file = b.path("src/test_perf.zig"),
        });
        exe_check.root_module.addImport("zmath", zmath.module("root"));
        exe_check.root_module.addImport("zbullet", zbullet.module("root"));

        const check = b.step("check", "Check if wasm compiles");
        check.dependOn(&exe_check.step);
    }

    // Exe glfw
    {
        const resources_lib = resources_lib: {
            const resources_lib = b.addSharedLibrary(.{
                .name = "resources",
                .root_source_file = b.path("src/resources_entry.zig"),
                .target = target,
                .optimize = optimize,
            });
            resources_lib.root_module.addImport("zmath", zmath.module("root"));
            resources_lib.root_module.addImport("zbullet", zbullet.module("root"));

            const install_lib = b.addInstallArtifact(resources_lib, .{ .dest_dir = .{ .override = .{ .custom = "../bin" } } });
            break :resources_lib install_lib;
        };
        const game_lib = game_lib: {
            const game_lib = b.addSharedLibrary(.{
                .name = "game",
                .root_source_file = b.path("src/game_entry.zig"),
                .target = target,
                .optimize = optimize,
            });
            game_lib.root_module.addImport("zmath", zmath.module("root"));
            game_lib.root_module.addImport("zbullet", zbullet.module("root"));
            game_lib.linkSystemLibrary("resources");
            game_lib.addLibraryPath(b.path("bin"));

            const install_lib = b.addInstallArtifact(game_lib, .{ .dest_dir = .{ .override = .{ .custom = "../bin" } } });
            install_lib.step.dependOn(&resources_lib.step);
            break :game_lib install_lib;
        };

        var exe = b.addExecutable(.{
            .name = "game_exe",
            .root_source_file = b.path("src/glfw_entry.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("zmath", zmath.module("root"));
        exe.root_module.addImport("zbullet", zbullet.module("root"));
        exe.linkLibrary(zbullet.artifact("cbullet"));

        // Link against the DLL
        exe.linkSystemLibrary("game");
        exe.addLibraryPath(b.path("bin"));

        const zglfw = b.dependency("zglfw", .{ .target = target });
        exe.root_module.addImport("zglfw", zglfw.module("root"));
        exe.linkLibrary(zglfw.artifact("glfw"));

        const zopengl = b.dependency("zopengl", .{});
        exe.root_module.addImport("zopengl", zopengl.module("root"));

        exe.step.dependOn(&export_meshes.step);

        const install_artifact = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "../bin" } } });
        install_artifact.step.dependOn(&game_lib.step);
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

    // Wasm
    {
        var exe = b.addExecutable(.{
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = optimize,
            .name = "game",
            .root_source_file = b.path("src/wasm_entry.zig"),
        });

        const gen = b.addWriteFile("generated.zig",
            \\pub const GeneratedData = struct {
            \\    pub const version = "1.0.0";
            \\    pub const buildTime = @as(i64, @intCast(@typeInfo(u64).Int.bits));
            \\    pub const constants = [_][]const u8{
            \\        "value1",
            \\        "value2",
            \\        "value3",
            \\    };
            \\};
        );
        const gen_module = b.addModule("generated", .{
            .root_source_file = .{ .generated = .{ .file = &gen.generated_directory, .up = 0, .sub_path = gen.files.items[0].sub_path } },
        });
        exe.root_module.addImport("generated", gen_module);

        exe.root_module.addImport("zbullet", zbullet.module("root"));
        exe.root_module.addImport("zmath", zmath.module("root"));

        exe.entry = .disabled;
        exe.rdynamic = true;
        exe.stack_size = std.wasm.page_size * 128;

        exe.step.dependOn(&export_meshes.step);

        const install_artifact = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "../bin" } } });
        const install_step = b.step("wasm", "build wasm entrypoint");
        install_step.dependOn(&install_artifact.step);
    }

    // Test Perf in Terminal
    {
        const exe = b.addExecutable(.{
            .name = "test_perf",
            .root_source_file = .{ .cwd_relative = "src/test_perf.zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("zmath", zmath.module("root"));

        exe.step.dependOn(&export_meshes.step);

        const install_artifact = b.addInstallArtifact(exe, .{});
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&install_artifact.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_cmd.step.dependOn(&install_artifact.step);

        // const install_step = b.step("test_perf", "build an exe");
        // install_step.dependOn(&install_artifact.step);

        const run_step = b.step("test_perf", "run the perf");
        run_step.dependOn(&run_cmd.step);
    }
}
