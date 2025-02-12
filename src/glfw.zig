const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const GameGraph = @import("game").GameGraph;
const runtime = @import("node_graph").new_runtime;
const game = @import("game");

const types = game.types;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);

    const window = try glfw.Window.create(600, 600, "zig-gamedev: minimal_glfw_gl", null);
    defer window.destroy();

    glfw.makeContextCurrent(window);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    const gl = zopengl.bindings;

    glfw.swapInterval(1);

    var game_graph = game.GameGraph.withHooks(poll, submit).init(
        allocator,
        .{
            .orbit_camera = types.OrbitCamera{ .position = .{ 0, 0, 0, 1 }, .rotation = .{ 0, 0, 0, 1 }, .track_distance = 2 },
            .player = types.Player{ .position = .{ 0, 0, 0, 1 }, .euler_rotation = .{ 0, 0, 0, 0 } },
        },
    );

    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.2, 0.4, 0.4, 1.0 });

        game_graph.update();

        window.swapBuffers();
    }
}

fn poll(comptime field_tag: GameGraph.InputTag) std.meta.fieldInfo(GameGraph.Inputs, field_tag).type {
    return switch (field_tag) {
        .time => 0,
        .render_resolution => .{ .x = 0, .y = 0 },
        .orbit_speed => 1,
        .input => .{ .mouse_delta = .{ 0, 0, 0, 0 }, .movement = .{ .left = null, .right = null, .forward = null, .backward = null } },
        .selected_camera => .orbit,
        .player_settings => .{ .movement_speed = 0.01, .look_speed = 0.01 },
        .bounce => false,
        .size_multiplier => 1,
    };
}

fn submit(comptime field_tag: GameGraph.OutputTag, value: std.meta.fieldInfo(GameGraph.Outputs, field_tag).type) void {
    _ = value;
    unreachable;
}
