const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const game = @import("./game/game.zig");

pub fn main() !void {
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

    {
        const allocator = std.heap.page_allocator;
        const NodeGraph = game.NodeGraph;
        var node_graph = try NodeGraph.init(.{
            .allocator = allocator,
            .inputs = game.graph_inputs,
            .store = game.graph_store,
        });
        const result = try node_graph.update(.{});
        if (result.skybox) |skybox| {
            std.debug.print("Found skybox!\n", .{});
            _ = skybox;
        }
        node_graph.deinit();
    }

    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.2, 0.4, 0.4, 1.0 });

        window.swapBuffers();
    }
}
