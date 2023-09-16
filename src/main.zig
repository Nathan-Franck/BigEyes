const std = @import("std");
const sdl = @import("zsdl");
const gl = @import("zopengl");

pub fn main() !void {
    _ = sdl.setHint(sdl.hint_windows_dpi_awareness, "system");

    try sdl.init(.{ .audio = true, .video = true });
    defer sdl.quit();

    const gl_major = 3;
    const gl_minor = 3;
    try sdl.gl.setAttribute(.context_profile_mask, @intFromEnum(sdl.gl.Profile.core));
    try sdl.gl.setAttribute(.context_major_version, gl_major);
    try sdl.gl.setAttribute(.context_minor_version, gl_minor);
    try sdl.gl.setAttribute(.context_flags, @as(i32, @bitCast(sdl.gl.ContextFlags{ .forward_compatible = true })));

    const window = try sdl.Window.create(
        "zig-gamedev: minimal_sdl_gl",
        sdl.Window.pos_undefined,
        sdl.Window.pos_undefined,
        600,
        600,
        .{ .opengl = true, .allow_highdpi = true },
    );
    defer window.destroy();

    const gl_context = try sdl.gl.createContext(window);
    defer sdl.gl.deleteContext(gl_context);

    try sdl.gl.makeCurrent(window, gl_context);
    try sdl.gl.setSwapInterval(0);

    try gl.loadCoreProfile(sdl.gl.getProcAddress, gl_major, gl_minor);

    {
        var w: i32 = undefined;
        var h: i32 = undefined;

        try window.getSize(&w, &h);
        std.debug.print("Window size is {d}x{d}\n", .{ w, h });

        sdl.gl.getDrawableSize(window, &w, &h);
        std.debug.print("Drawable size is {d}x{d}\n", .{ w, h });
    }

    const triangle = .{
        .points = [_]f32{
            -0.5, -0.5, 0.0,
            0.5,  -0.5, 0.0,
            0.0,  0.5,  0.0,
        },
        .colors = [_][3]f32{
            .{ 1.0, 0.0, 0.0 },
            .{ 0.0, 1.0, 0.0 },
            .{ 0.0, 0.0, 1.0 },
        },
        .faces = [_][3]u8{
            .{ 0, 1, 2 },
        },
    };

    main_loop: while (true) {
        var event: sdl.Event = undefined;
        while (sdl.pollEvent(&event)) {
            if (event.type == .quit) {
                break :main_loop;
            } else if (event.type == .keydown) {
                if (event.key.keysym.sym == .escape) break :main_loop;
            }
        }
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.2, 0.4, 0.8, 1.0 });

        // Draw example triangle
        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LESS);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        // gl.begin(gl.TRIANGLES);
        // for (triangle.faces) |face| {
        //     for (face) |index| {
        //         const point = triangle.points[index];
        //         const color = triangle.colors[index];
        //         gl.color3fv(&color);
        //         gl.vertex3fv(&point);
        //     }
        // }
        // gl.end();

        // Use buffers instead

        var vbo: c_uint = undefined;
        gl.genBuffers(1, &vbo);
        defer gl.deleteBuffers(1, &vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);

        gl.bufferData(gl.ARRAY_BUFFER, @as(isize, triangle.points.len) * @sizeOf(f32), @ptrCast(&triangle.points), gl.STATIC_DRAW);

        // gl.enableVertexAttribArray(0);
        // gl.vertexAttribPointer(0, 3, gl.FLOAT, 0, 0, null);

        // var cbo: [*c]c_uint = undefined;
        // gl.genBuffers(1, cbo);
        // defer gl.deleteBuffers(1, cbo);
        // gl.bindBuffer(gl.ARRAY_BUFFER, cbo.*);

        // gl.bufferData(gl.ARRAY_BUFFER, @as(u64, triangle.colors.len) * @sizeOf(f32), &triangle.colors, gl.STATIC_DRAW);

        // gl.enableVertexAttribArray(1);
        // gl.vertexAttribPointer(1, 3, gl.FLOAT, 0, 0, null);

        // var ibo: [*c]c_uint = undefined;
        // gl.genBuffers(1, ibo);
        // defer gl.deleteBuffers(1, ibo);
        // gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo.*);

        // gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @as(u64, triangle.faces.len) * @sizeOf(u8), &triangle.faces, gl.STATIC_DRAW);

        // gl.drawElements(gl.TRIANGLES, @as(i32, triangle.faces.len) * 3, gl.UNSIGNED_BYTE, null);

        sdl.gl.swapWindow(window);
    }
}
