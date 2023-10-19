const std = @import("std");

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn addModule(
    b: *std.Build,
    exe: *std.Build.CompileStep,
    deps: struct { zmath: *std.build.Module },
) void {
    exe.addModule("subdiv", b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/subdiv.zig" },
        .dependencies = &.{
            .{ .name = "zmath", .module = deps.zmath },
        },
    }));
}
