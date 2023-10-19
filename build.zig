const std = @import("std");

pub fn build(b: *std.Build) !void {
    const exe_step = b.step("exe", "build an exe");
    exe_step.dependOn(try @import("projects/exe/build.zig").build(b));
    const wasm_step = b.step("wasm", "build a wasm");
    wasm_step.dependOn(try @import("projects/wasm/build.zig").build(b));
}
