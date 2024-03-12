const std = @import("std");
const content_dir = "src/content/";

const ExportMeshes = struct {
    allocator: std.mem.Allocator,
    files: []const []const u8,
    step: std.Build.Step,
    pub fn create(b: *std.Build, files: []const []const u8) *ExportMeshes {
        const self = b.allocator.create(ExportMeshes) catch @panic("OOM");
        self.* = .{
            .allocator = b.allocator,
            .files = files,
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "export_meshes",
                .owner = b,
                .makeFn = exportMeshes,
            }),
        };
        return self;
    }
    fn exportMeshes(step: *std.Build.Step, prog_node: *std.Progress.Node) !void {
        _ = prog_node;
        const self = @fieldParentPtr(ExportMeshes, "step", step);

        var b = step.owner;

        var export_count: u32 = 0;

        for (self.files) |file| {
            const full_path = try std.fmt.allocPrint(self.allocator, "content/{s}.blend", .{file});

            var man = b.graph.cache.obtain();
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
            const ns = timer.read();
            std.debug.print("Process took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
            export_count += 1;
        }
        if (export_count > 0) {
            std.debug.print("Exported {d} meshes\n", .{export_count});
        }
    }
};

pub fn build(
    b: *std.Build,
) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const export_meshes = ExportMeshes.create(b, &.{ "boss", "cube", "Cat", "RockLevel" });
    const zgui_pkg = @import("zgui").package(b, target, optimize, .{ .options = .{ .backend = .glfw_wgpu } });
    const zmath_pkg = @import("zmath").package(b, target, optimize, .{});
    const zglfw_pkg = @import("zglfw").package(b, target, optimize, .{ .options = .{ .shared = false } });
    const zpool_pkg = @import("zpool").package(b, target, optimize, .{});
    const zgpu_pkg = @import("zgpu").package(b, target, optimize, .{ .deps = .{ .zpool = zpool_pkg } });
    const zmesh_pkg = @import("zmesh").package(b, target, optimize, .{});

    // Tests (default)
    {
        // const main_tests = b.addTest(.{ .root_source_file = .{ .path = thisDir() ++ "/tests.zig" } });
        const main_tests = b.addTest(.{ .root_source_file = .{ .path = thisDir() ++ "/src/tests.zig" } });
        // main_tests.root_module.addImport("embedded_assets", embedded_assets);
        zmath_pkg.link(main_tests);
        const run_unit_tests = b.addRunArtifact(main_tests);
        const test_step = b.step("exe-test", "run tests");
        test_step.dependOn(&run_unit_tests.step);
        b.default_step.dependOn(test_step);
    }

    // Wasm
    {
        var exe = b.addExecutable(.{
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = .ReleaseSmall,
            .name = "game",
            .root_source_file = .{ .path = thisDir() ++ "/src/wasm_entry.zig" },
        });
        zmath_pkg.link(exe);

        // Latest wasm hack - https://github.com/ringtailsoftware/zig-wasm-audio-framebuffer/blob/master/build.zig
        exe.entry = .disabled;
        exe.rdynamic = true;

        // // <https://github.com/ziglang/zig/issues/8633>
        // exe.global_base = 6560;
        // exe.import_memory = true;
        // exe.stack_size = std.wasm.page_size;

        // // Number of pages reserved for heap memory.
        // // This must match the number of pages used in script.js.
        // const number_of_pages = 2;
        // exe.initial_memory = std.wasm.page_size * number_of_pages;
        // exe.max_memory = std.wasm.page_size * number_of_pages;

        // exe.step.dependOn(&export_meshes.step);

        const install_artifact = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "../web/bin" } } });
        const install_step = b.step("wasm", "build a wasm");
        install_step.dependOn(&install_artifact.step);
    }

    // Exe
    {
        const exe = b.addExecutable(.{
            .name = "triangle_wgpu",
            .root_source_file = .{ .path = thisDir() ++ "/src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        zgui_pkg.link(exe);
        zglfw_pkg.link(exe);
        zgpu_pkg.link(exe);
        zmath_pkg.link(exe);
        zmesh_pkg.link(exe);
        exe.step.dependOn(&export_meshes.step);
        // Windows hax
        exe.want_lto = false;
        // if (exe.optimize == .ReleaseFast)
        //     exe.strip = true;

        const install_artifact = b.addInstallArtifact(exe, .{});
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&install_artifact.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_cmd.step.dependOn(&install_artifact.step);

        const install_step = b.step("exe", "build an exe");
        install_step.dependOn(&install_artifact.step);

        const run_step = b.step("exe-run", "run the exe");
        run_step.dependOn(&run_cmd.step);
    }
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
