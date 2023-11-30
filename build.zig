const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const gl_entry_step = b.step("gl-entry", "build gl-entry");
    gl_entry_step.dependOn(try @import("projects/gl-entry/build.zig").build(b, target, optimize));
    const exe_step = b.step("exe", "build an exe");
    exe_step.dependOn(try @import("projects/exe/build.zig").build(b, target, optimize));
    const wasm_step = b.step("wasm", "build a wasm");
    wasm_step.dependOn(try @import("projects/wasm/build.zig").build(b));
}
