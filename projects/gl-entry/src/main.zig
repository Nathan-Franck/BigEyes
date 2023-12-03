const std = @import("std");
const panic = std.debug.panic;
const c_allocator = std.heap.c_allocator;
const rand = std.rand;
const builtin = @import("builtin");
const zmath = @import("zmath");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("gl2_impl.h");
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("SDL2/SDL_opengl.h");
});

extern fn gladLoadGL() callconv(.C) c_int; // init OpenGL function pointers on Windows and Linux

export fn WinMain() callconv(.C) c_int {
    main() catch return 1; // TODO report error
    return 0;
}

var sdl_window: *c.SDL_Window = undefined;

fn identityM3() [9]f32 {
    return [9]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
    };
}

fn translateM3(tx: f32, ty: f32) [9]f32 {
    return [9]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        tx,  ty,  1.0,
    };
}

fn scaleM3(sx: f32, sy: f32) [9]f32 {
    return [9]f32{
        sx,  0.0, 0.0,
        0.0, sy,  0.0,
        0.0, 0.0, 1.0,
    };
}

fn rotateM3(angle: f32) [9]f32 {
    const si = @sin(angle);
    const co = @cos(angle);
    return [9]f32{
        co,  si,  0.0,
        -si, co,  0.0,
        0.0, 0.0, 1.0,
    };
}

fn multiplyM3(m0: [9]f32, m1: [9]f32) [9]f32 {
    var m = [_]f32{0.0} ** 9;
    const nums = [_]usize{ 0, 1, 2 };
    for (nums) |i| {
        for (nums) |j| {
            for (nums) |k| {
                m[3 * j + i] += m0[3 * j + k] * m1[3 * k + i];
            }
        }
    }
    return m;
}

fn initGlShader(kind: c.GLenum, source: []const u8) !c.GLuint {
    const shader_id = c.glCreateShader(kind);
    const source_ptr: ?[*]const u8 = source.ptr;
    const source_len: c.GLint = @intCast(source.len);
    c.glShaderSource(shader_id, 1, &source_ptr, &source_len);
    c.glCompileShader(shader_id);

    var ok: c.GLint = undefined;
    c.glGetShaderiv(shader_id, c.GL_COMPILE_STATUS, &ok);
    if (ok != 0) return shader_id;

    var error_size: c.GLint = undefined;
    c.glGetShaderiv(shader_id, c.GL_INFO_LOG_LENGTH, &error_size);

    const message = try c_allocator.alloc(u8, @intCast(error_size));
    c.glGetShaderInfoLog(shader_id, error_size, &error_size, message.ptr);
    panic("Error compiling {any} shader:\n{s}\n", .{ kind, message });
}

fn makeShader(vert_src: []const u8, frag_src: []const u8) !c.GLuint {
    var ok: c.GLint = undefined;

    const vert_shader = try initGlShader(c.GL_VERTEX_SHADER, vert_src);
    const frag_shader = try initGlShader(c.GL_FRAGMENT_SHADER, frag_src);
    const program = c.glCreateProgram();
    c.glAttachShader(program, vert_shader);
    c.glAttachShader(program, frag_shader);
    c.glLinkProgram(program);

    c.glGetProgramiv(program, c.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        var error_size: c.GLint = undefined;
        c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &error_size);
        const message = try c_allocator.alloc(u8, @intCast(error_size));
        c.glGetProgramInfoLog(program, error_size, &error_size, message.ptr);
        panic("Error linking shader program: {s}\n", .{message});
    }

    c.glDetachShader(program, vert_shader);
    c.glDetachShader(program, frag_shader);
    c.glDeleteShader(vert_shader);
    c.glDeleteShader(frag_shader);

    return program;
}

var default_shader: c.GLuint = undefined;
var transform_loc: c.GLint = undefined;
var color_loc: c.GLint = undefined;

fn initGL() void {
    default_shader = makeShader(
        \\uniform mat4 transform;
        \\attribute vec3 position;
        \\void main() {
        \\    gl_Position = transform * vec4(position, 1.0);
        \\}
    ,
        \\uniform vec3 color;
        \\void main() {
        \\    gl_FragColor = vec4(color, 1.0);
        \\}
    ) catch 0;
    c.glUseProgram(default_shader);
    transform_loc = c.glGetUniformLocation(default_shader, "transform");
    color_loc = c.glGetUniformLocation(default_shader, "color");
}

// fn drawGame(alpha: f32) void {
//     var width: c_int = undefined;
//     var height: c_int = undefined;
//     c.SDL_GL_GetDrawableSize(sdl_window, &width, &height);
//     c.glViewport(0, 0, width, height);
//     c.glClearColor(1.0, 1.0, 1.0, 1.0);
//     c.glClear(c.GL_COLOR_BUFFER_BIT);

//     // background
//     c.glBindBuffer(c.GL_ARRAY_BUFFER, rect_vertex_buffer);

//     var transform = zmath.identity();
//     c.glEnableVertexAttribArray(0); // position
//     c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2 * @sizeOf(f32), null);
//     c.glUniformMatrix3fv(transform_loc, 1, c.GL_FALSE, &transform[0]);
//     c.glUniform3f(color_loc, 0.3, 0.3, 0.5);
//     c.glDrawArrays(c.GL_QUADS, 0, 4);

//     // sprite types
//     c.glBindBuffer(c.GL_ARRAY_BUFFER, sprite_vertex_buffer);
//     c.glEnableVertexAttribArray(0); // position
//     c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2 * @sizeOf(f32), null);
//     for ([_]usize{ 0, 1, 2, 3 }) |s| {
//         var i: usize = 0;
//         while (i <= draw_detail) : (i += 1) {
//             const angle = @as(f32, @floatFromInt(i)) / draw_detail * std.math.pi;
//             vertex_buffer[2 * i + 0] = @cos(angle);
//             vertex_buffer[2 * i + 1] = @sin(angle);
//             vertex_buffer[2 * (draw_detail + 1 + i) + 0] = -@cos(angle);
//             vertex_buffer[2 * (draw_detail + 1 + i) + 1] = -@sin(angle) - 2;
//             if (s == 1) { // head
//                 vertex_buffer[2 * i + 1] += 2 * alpha - 2;
//             } else if (s == 2) { // tail
//                 vertex_buffer[2 * (draw_detail + 1 + i) + 1] += if (game.snake.eaten) 2 else 2 * alpha;
//             } else if (s == 3) { // food
//                 vertex_buffer[2 * (draw_detail + 1 + i) + 1] += 2;
//             }
//         }
//         c.glBufferSubData(c.GL_ARRAY_BUFFER, @intCast(s * vertex_buffer.len * @sizeOf(f32)), vertex_buffer.len * @sizeOf(f32), &vertex_buffer[0]);
//     }
//     const n = 2 * (draw_detail + 1);

//     // snake
//     c.glUniform3f(color_loc, 0.3, 0.7, 0.1);
//     const snake = &game.snake;
//     var it = snake.iter();
//     while (it.next()) |s| {
//         const i = (it.i + N - 1) % N;
//         const stype: i32 = if (i == snake.tail) 2 else if (i == snake.head) 1 else 0;
//         const x: f32 = @floatFromInt(s.x);
//         const y: f32 = @floatFromInt(s.y);
//         const translation = translateM3(2 * x - Game.width + 1, 2 * y - Game.height + 1);
//         const rt: f32 = switch (s.dir) {
//             .up => 0,
//             .down => 2,
//             .left => 1,
//             .right => 3,
//         };
//         const rotation = rotateM3(rt / 2.0 * std.math.pi);
//         const tmp = multiplyM3(translation, scale);
//         const transform = multiplyM3(rotation, tmp);
//         c.glUniformMatrix3fv(transform_loc, 1, c.GL_FALSE, &transform[0]);

//         c.glDrawArrays(c.GL_TRIANGLE_FAN, stype * n, n);
//     }

//     // food
//     if (!game.gameover) {
//         c.glUniform3f(color_loc, 1.0, 0.2, 0.0);
//         const x: f32 = @floatFromInt(game.food_x);
//         const y: f32 = @floatFromInt(game.food_y);
//         const translation = translateM3(2 * x - Game.width + 1, 2 * y - Game.height + 1);
//         var transform = multiplyM3(translation, scale);
//         c.glUniformMatrix3fv(transform_loc, 1, c.GL_FALSE, &transform[0]);
//         c.glDrawArrays(c.GL_TRIANGLE_FAN, 3 * n, n);
//     }

//     c.SDL_GL_SwapWindow(sdl_window);
// }

fn sdlEventWatch(userdata: ?*anyopaque, sdl_event: [*c]c.SDL_Event) callconv(.C) c_int {
    _ = userdata;
    if (sdl_event.*.type == c.SDL_WINDOWEVENT and
        sdl_event.*.window.event == c.SDL_WINDOWEVENT_RESIZED)
    {
        // drawGame(1.0); // draw while resizing
        return 0; // handled
    }
    return 1;
}

const subdiv = @import("subdiv");

pub fn main() !void {
    std.debug.print("Press ESC to quit\n", .{});
    const allocator = std.heap.page_allocator;
    var points = [_]subdiv.Point{
        subdiv.Point{ -1.0, 1.0, 1.0, 1.0 },
        subdiv.Point{ -1.0, -1.0, 1.0, 1.0 },
        subdiv.Point{ 1.0, -1.0, 1.0, 1.0 },
        subdiv.Point{ 1.0, 1.0, 1.0, 1.0 },
        subdiv.Point{ -1.0, 1.0, -1.0, 1.0 },
        subdiv.Point{ -1.0, -1.0, -1.0, 1.0 },
    };
    var faces = [_]subdiv.Face{
        &[_]u32{ 0, 1, 2, 3 },
        &[_]u32{ 0, 1, 5, 4 },
    };
    const result = try subdiv.Subdiv(true).cmcSubdiv(
        allocator,
        &points,
        &faces,
    );

    try std.testing.expectEqual(result.points.len, 15);
    try std.testing.expectEqual(result.quads.len, 8);
    for (result.quads) |face| {
        for (face) |pointNum| {
            try std.testing.expect(pointNum >= 0);
            try std.testing.expect(pointNum < 15);
        }
    }

    std.debug.print("Hello, world!\n", .{});

    const video_width: i32 = 1024;
    const video_height: i32 = 640;

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLEBUFFERS, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLESAMPLES, 4);

    sdl_window = c.SDL_CreateWindow("Snake", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, video_width, video_height, c.SDL_WINDOW_OPENGL |
        c.SDL_WINDOW_RESIZABLE |
        c.SDL_WINDOW_ALLOW_HIGHDPI) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(sdl_window);

    const gl_context = c.SDL_GL_CreateContext(sdl_window); // TODO: handle error
    defer c.SDL_GL_DeleteContext(gl_context);

    if (builtin.os.tag == .windows or builtin.os.tag == .linux) {
        _ = gladLoadGL();
    }

    _ = c.SDL_GL_SetSwapInterval(1);

    c.SDL_AddEventWatch(sdlEventWatch, null);

    initGL();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const mesh = mesh: {

        // Load seperately a json file with the polygon data, should be called *.gltf.json
        const polygonJSON = json: {
            const content_dir = @import("build_options").content_dir;
            const json_data = std.fs.cwd().readFileAlloc(arena.allocator(), content_dir ++ "cat.blend.json", 512 * 1024 * 1024) catch |err| {
                std.log.err("Failed to read JSON file: {}", .{err});
                return err;
            };
            const Config = []const struct {
                name: []const u8,
                polygons: []const subdiv.Face,
                vertices: []const subdiv.Point,
                shapeKeys: []struct { name: []const u8, vertices: []const subdiv.Point },
            };
            break :json std.json.parseFromSlice(Config, arena.allocator(), json_data, .{}) catch |err| {
                std.log.err("Failed to parse JSON: {}", .{err});
                return err;
            };
        };
        _ = polygonJSON;
        break :mesh;
    };
    _ = mesh;

    var quit = false;
    std.debug.print("Press ESC to quit\n", .{});
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => quit = true,
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == c.SDLK_ESCAPE) quit = true;
                    switch (event.key.keysym.sym) {
                        // c.SDLK_UP => game.addNextInput(.up),
                        // c.SDLK_DOWN => game.addNextInput(.down),
                        // c.SDLK_RIGHT => game.addNextInput(.right),
                        // c.SDLK_LEFT => game.addNextInput(.left),
                        else => {},
                    }
                },
                else => {},
            }
        }
        std.debug.print("Game loop\n", .{});
        // if (game.gameover) alpha = 1.0;
        // drawGame(alpha);
    }
}
