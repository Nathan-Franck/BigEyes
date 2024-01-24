const std = @import("std");
const content_dir = "content/";

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
            const ns = timer.read();
            std.debug.print("Process took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
            export_count += 1;
        }
        if (export_count > 0) {
            std.debug.print("Exported {d} meshes\n", .{export_count});
        }
    }
};

/// Represents any JSON value, potentially containing other JSON values.
/// A .float value may be an approximation of the original value.
/// Arbitrary precision numbers can be represented by .number_string values.
pub const ObjectMap = std.StringArrayHashMap(Value);
pub const Array = std.ArrayList(Value);
pub const Value = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    number_string: []const u8,
    string: []const u8,
    array: Array,
    object: ObjectMap,

    pub fn parseFromNumberSlice(s: []const u8) Value {
        if (!std.json.isNumberFormattedLikeAnInteger(s)) {
            const f = std.fmt.parseFloat(f64, s) catch unreachable;
            if (std.math.isFinite(f)) {
                return Value{ .float = f };
            } else {
                return Value{ .number_string = s };
            }
        }
        if (std.fmt.parseInt(i64, s, 10)) |i| {
            return Value{ .integer = i };
        } else |e| {
            switch (e) {
                error.Overflow => return Value{ .number_string = s },
                error.InvalidCharacter => unreachable,
            }
        }
    }

    pub fn dump(self: Value) void {
        std.debug.getStderrMutex().lock();
        defer std.debug.getStderrMutex().unlock();

        const stderr = std.io.getStdErr().writer();
        // std.json.stringify(self, .{}, stderr) catch return;

        var str = std.json.WriteStream(std.fs.File.Writer, .assumed_correct).init(undefined, stderr, .{});
        str.write(self) catch return;
    }

    pub fn jsonStringify(value: @This(), jws: *std.json.WriteStream(std.fs.File.Writer, .assumed_correct)) !void {
        switch (value) {
            .null => try jws.write(null),
            .bool => |inner| try jws.write(inner),
            .integer => |inner| try jws.write(inner),
            .float => |inner| try jws.write(inner),
            .number_string => |inner| try jws.print("{s}", .{inner}),
            .string => |inner| try jws.write(inner),
            .array => |inner| {
                jws.stream.print(".{{ ", .{}) catch unreachable;
                jws.indent_level += 1;
                jws.next_punctuation = .none;
                for (inner.items) |x| {
                    try jws.write(x);
                    jws.next_punctuation = .comma;
                }
                try jws.stream.writeByte('}');
                jws.indent_level -= 1;
                jws.next_punctuation = .comma;
            },
            .object => |inner| {
                jws.stream.print(".{{ ", .{}) catch unreachable;
                jws.indent_level += 1;
                var it = inner.iterator();
                jws.next_punctuation = .none;

                while (it.next()) |entry| {
                    jws.stream.print(".{s} = ", .{entry.key_ptr.*}) catch unreachable;
                    try jws.write(entry.value_ptr.*);
                    jws.next_punctuation = .none;
                }
                jws.indent_level -= 1;
                try jws.stream.writeByte('}');
            },
        }
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!@This() {
        // The grammar of the stack is:
        //  (.array | .object .string)*
        var stack = Array.init(allocator);
        defer stack.deinit();

        while (true) {
            // Assert the stack grammar at the top of the stack.
            std.debug.assert(stack.items.len == 0 or
                stack.items[stack.items.len - 1] == .array or
                (stack.items[stack.items.len - 2] == .object and stack.items[stack.items.len - 1] == .string));

            switch (try source.nextAllocMax(allocator, .alloc_always, options.max_value_len.?)) {
                .allocated_string => |s| {
                    return try handleCompleteValue(&stack, allocator, source, Value{ .string = s }, options) orelse continue;
                },
                .allocated_number => |slice| {
                    return try handleCompleteValue(&stack, allocator, source, Value.parseFromNumberSlice(slice), options) orelse continue;
                },

                .null => return try handleCompleteValue(&stack, allocator, source, .null, options) orelse continue,
                .true => return try handleCompleteValue(&stack, allocator, source, Value{ .bool = true }, options) orelse continue,
                .false => return try handleCompleteValue(&stack, allocator, source, Value{ .bool = false }, options) orelse continue,

                .object_begin => {
                    switch (try source.nextAllocMax(allocator, .alloc_always, options.max_value_len.?)) {
                        .object_end => return try handleCompleteValue(&stack, allocator, source, Value{ .object = ObjectMap.init(allocator) }, options) orelse continue,
                        .allocated_string => |key| {
                            try stack.appendSlice(&[_]Value{
                                Value{ .object = ObjectMap.init(allocator) },
                                Value{ .string = key },
                            });
                        },
                        else => unreachable,
                    }
                },
                .array_begin => {
                    try stack.append(Value{ .array = Array.init(allocator) });
                },
                .array_end => return try handleCompleteValue(&stack, allocator, source, stack.pop(), options) orelse continue,

                else => unreachable,
            }
        }
    }

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: Value, options: std.json.ParseOptions) !@This() {
        _ = allocator;
        _ = options;
        return source;
    }
};

fn handleCompleteValue(stack: *Array, allocator: std.mem.Allocator, source: anytype, value_: Value, options: std.json.ParseOptions) !?Value {
    if (stack.items.len == 0) return value_;
    var value = value_;
    while (true) {
        // Assert the stack grammar at the top of the stack.
        std.debug.assert(stack.items[stack.items.len - 1] == .array or
            (stack.items[stack.items.len - 2] == .object and stack.items[stack.items.len - 1] == .string));
        switch (stack.items[stack.items.len - 1]) {
            .string => |key| {
                // stack: [..., .object, .string]
                _ = stack.pop();

                // stack: [..., .object]
                var object = &stack.items[stack.items.len - 1].object;
                try object.put(key, value);

                // This is an invalid state to leave the stack in,
                // so we have to process the next token before we return.
                switch (try source.nextAllocMax(allocator, .alloc_always, options.max_value_len.?)) {
                    .object_end => {
                        // This object is complete.
                        value = stack.pop();
                        // Effectively recurse now that we have a complete value.
                        if (stack.items.len == 0) return value;
                        continue;
                    },
                    .allocated_string => |next_key| {
                        // We've got another key.
                        try stack.append(Value{ .string = next_key });
                        // stack: [..., .object, .string]
                        return null;
                    },
                    else => unreachable,
                }
            },
            .array => |*array| {
                // stack: [..., .array]
                try array.append(value);
                return null;
            },
            else => unreachable,
        }
    }
}

const MeshSpec = @import("./MeshSpec.zig");

pub fn parseJsonToData(allocator: std.mem.Allocator, path: []const u8) void {
    const json_data = std.fs.cwd().readFileAlloc(
        allocator,
        path,
        512 * 1024 * 1024,
    ) catch unreachable;
    const ast = std.json.parseFromSlice(Value, allocator, json_data, .{}) catch unreachable;
    const thinger: Value = ast.value;
    thinger.dump();
}

pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !void {
    const exe = b.addExecutable(.{
        .name = "triangle_wgpu",
        .root_source_file = .{ .path = thisDir() ++ "/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zgui_pkg = @import("zgui").package(b, target, optimize, .{ .options = .{ .backend = .glfw_wgpu } });
    const zmath_pkg = @import("zmath").package(b, target, optimize, .{});
    const zglfw_pkg = @import("zglfw").package(b, target, optimize, .{ .options = .{ .shared = false } });
    const zpool_pkg = @import("zpool").package(b, target, optimize, .{});
    const zgpu_pkg = @import("zgpu").package(b, target, optimize, .{ .deps = .{ .zglfw = zglfw_pkg, .zpool = zpool_pkg } });
    const zmesh_pkg = @import("zmesh").package(b, target, optimize, .{});
    const subdiv = b.addModule("subdiv", .{
        .root_source_file = .{ .path = thisDir() ++ "/../../libs/subdiv/subdiv.zig" },
        .imports = &.{
            .{ .name = "zmath", .module = zmath_pkg.zmath },
        },
    });
    parseJsonToData(b.allocator, "content/cat.blend.json");
    // const embedded_assets = embedded_assets: {
    //     const step = b.addOptions();
    //     step.addOption(MeshSpec, "meshes", );
    //     break :embedded_assets step.createModule();
    // };

    zgui_pkg.link(exe);
    zglfw_pkg.link(exe);
    zgpu_pkg.link(exe);
    zmath_pkg.link(exe);
    zmesh_pkg.link(exe);

    exe.root_module.addImport("subdiv", subdiv);
    // exe.root_module.addImport("embedded_assets", embedded_assets);

    const export_meshes = ExportMeshes.create(b, &.{ "boss", "cube", "cat", "RockLevel" });
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

    const main_tests = b.addTest(.{ .root_source_file = .{ .path = thisDir() ++ "/tests.zig" } });
    main_tests.root_module.addImport("subdiv", subdiv);
    // main_tests.root_module.addImport("embedded_assets", embedded_assets);
    zmath_pkg.link(main_tests);
    const test_step = b.step("exe-test", "run tests");
    test_step.dependOn(&main_tests.step);
    b.default_step.dependOn(test_step);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
