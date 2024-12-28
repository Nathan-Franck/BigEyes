const std = @import("std");

const content_dir = "src/content/";

const ExportMeshes = struct {
    allocator: std.mem.Allocator,
    files: []const []const u8,

    step: std.Build.Step,
    pub fn create(b: *std.Build, files: []const []const u8) *@This() {
        const self = b.allocator.create(@This()) catch @panic("OOM");
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
    fn exportMeshes(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const self = @as(*ExportMeshes, @fieldParentPtr("step", step));

        var b = step.owner;

        var export_count: u32 = 0;

        for (self.files) |file| {
            const full_path = try std.fmt.allocPrint(self.allocator, content_dir ++ "/{s}.blend", .{file});

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
            const res = try std.process.Child.run(.{
                .allocator = self.allocator,
                .cwd = try std.process.getCwdAlloc(self.allocator),
                .argv = &[_][]const u8{
                    "blender",
                    full_path,
                    "--background",
                    "--python",
                    content_dir ++ "/blend-to-json.py",
                },
            });
            std.debug.print("stdout: {s}\n", .{res.stdout});
            if (res.stderr.len > 0) {
                std.debug.print("stderr: {s}\n", .{res.stderr});
                return error.ExportFailed;
            }
            const ns = timer.read();
            std.debug.print("Process took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
            export_count += 1;
        }
        if (export_count > 0) {
            std.debug.print("Exported {d} meshes\n", .{export_count});
        }
    }
};

// fn GenerateTypescripTypes(interface: anytype) type {
//     return struct {
//         allocator: std.mem.Allocator,
//         folder_path: []const u8,
//         file_name: []const u8,
//         step: std.Build.Step,
//         pub fn create(b: *std.Build, folder_path: []const u8, file_name: []const u8) *@This() {
//             const self = b.allocator.create(@This()) catch @panic("OOM");
//             self.* = .{
//                 .allocator = b.allocator,
//                 .folder_path = folder_path,
//                 .file_name = file_name,
//                 .step = std.Build.Step.init(.{
//                     .id = .custom,
//                     .name = "export_meshes",
//                     .owner = b,
//                     .makeFn = doStep,
//                 }),
//             };
//             return self;
//         }
//         pub fn doStep(step: *std.Build.Step, prog_node: *std.Progress.Node) anyerror!void {
//             _ = prog_node;

//             const self = @fieldParentPtr(@This(), "step", step);

//             const typescriptTypeOf = @import("src/typeDefinitions.zig").typescriptTypeOf;

//             const typeInfo = comptime typescriptTypeOf(interface, .{ .first = true });
//             const contents = "export type WasmInterface = " ++ typeInfo;
//             const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.folder_path, self.file_name });
//             std.fs.cwd().makeDir(self.folder_path) catch {};
//             std.fs.cwd().deleteFile(file_path) catch {};
//             const file = try std.fs.cwd().createFile(file_path, .{});
//             try file.writeAll(contents);
//         }
//     };
// }

pub fn build(
    b: *std.Build,
) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const export_meshes = ExportMeshes.create(b, &.{"ebike"});

    // Tests (default)
    {
        const main_tests = b.addTest(.{ .root_source_file = .{ .cwd_relative = "src/tests.zig" } });
        const zmath = b.dependency("zmath", .{});
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

        const zmath = b.dependency("zmath", .{});
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
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = optimize,
            .name = "check_exe",
            .root_source_file = b.path("src/wasm_entry.zig"),
            // .root_source_file = b.path("src/test_perf.zig"),
        });
        const zmath = b.dependency("zmath", .{});
        exe_check.root_module.addImport("zmath", zmath.module("root"));

        const check = b.step("check", "Check if wasm compiles");
        check.dependOn(&exe_check.step);
    }

    // Wasm
    {
        var exe = b.addExecutable(.{
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = optimize,
            .name = "game",
            .root_source_file = b.path("src/wasm_entry.zig"),
        });

        const zmath = b.dependency("zmath", .{});
        exe.root_module.addImport("zmath", zmath.module("root"));

        // Latest wasm hack - https://github.com/ringtailsoftware/zig-wasm-audio-framebuffer/blob/master/build.zig
        exe.entry = .disabled;
        exe.rdynamic = true;

        // // <https://github.com/ziglang/zig/issues/8633>
        // exe.global_base = 6560;
        // exe.import_memory = true;
        exe.stack_size = std.wasm.page_size * 128;
        // exe.use_llvm = false;

        // // Number of pages reserved for heap memory.
        // // This must match the number of pages used in script.js.
        // const number_of_pages = 4;
        // exe.initial_memory = std.wasm.page_size * number_of_pages;
        // exe.max_memory = std.wasm.page_size * number_of_pages;

        exe.step.dependOn(&export_meshes.step);
        // exe.step.dependOn(&generate_typescript_types.step);

        const install_artifact = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "../bin" } } });
        const install_step = b.step("wasm", "build a wasm");
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

        const zmath = b.dependency("zmath", .{});
        exe.root_module.addImport("zmath", zmath.module("root"));

        exe.step.dependOn(&export_meshes.step);
        // Windows hax
        exe.want_lto = false;
        // exe.use_llvm = false;
        // if (exe.optimize == .ReleaseFast)
        //     exe.strip = true;

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

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
