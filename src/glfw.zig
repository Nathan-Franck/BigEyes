const std = @import("std");
const zglfw = @import("zglfw");
const zopengl = @import("zopengl");
const GameGraph = @import("game").GameGraph;
const runtime = @import("node_graph").new_runtime;
const game = @import("game");
const zgpu = @import("zgpu");
const zgui = @import("zgui");

const types = game.types;

pub fn initGLFW(allocator: std.mem.Allocator, window: *zglfw.Window) void {
    const gctx = try zgpu.GraphicsContext.create(
        allocator,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{},
    );
    errdefer gctx.destroy(allocator);

    zgui.init(allocator);
    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };
    const font_normal = zgui.io.addFontFromFile(
        content_dir ++ "Roboto-Medium.ttf",
        math.floor(20.0 * scale_factor),
    );
    assert(zgui.io.getFont(0) == font_normal);

    // This needs to be called *after* adding your custom fonts.
    zgui.backend.init(
        window,
        gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );

    const style = zgui.getStyle();

    style.window_min_size = .{ 320.0, 240.0 };
    style.window_border_size = 8.0;
    style.scrollbar_size = 6.0;
    {
        var color = style.getColor(.scrollbar_grab);
        color[1] = 0.8;
        style.setColor(.scrollbar_grab, color);
    }
    style.scaleAllSizes(scale_factor);

    // Create a bind group layout needed for our render pipeline.
    const bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true }, .uniform, true, 0),
    });
    defer gctx.releaseResource(bind_group_layout);

    const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});
    defer gctx.releaseResource(pipeline_layout);

    const pipeline = pipline: {
        const vs_module = zgpu.createWgslShaderModule(gctx.device, wgsl_vs, "vs");
        defer vs_module.release();

        const fs_module = zgpu.createWgslShaderModule(gctx.device, wgsl_fs, "fs");
        defer fs_module.release();

        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]wgpu.VertexAttribute{ .{
            .format = .float32x2,
            .offset = @offsetOf(Vertex, "position"),
            .shader_location = 0,
        }, .{
            .format = .float32,
            .offset = @offsetOf(Vertex, "side"),
            .shader_location = 1,
        } };

        const instance_attributes = [_]wgpu.VertexAttribute{ .{
            .format = .float32,
            .offset = @offsetOf(Pill, "width"),
            .shader_location = 10,
        }, .{
            .format = .float32,
            .offset = @offsetOf(Pill, "length"),
            .shader_location = 11,
        }, .{
            .format = .float32,
            .offset = @offsetOf(Pill, "angle"),
            .shader_location = 12,
        }, .{
            .format = .float32x2,
            .offset = @offsetOf(Pill, "position"),
            .shader_location = 13,
        }, .{
            .format = .float32x4,
            .offset = @offsetOf(Pill, "start_color"),
            .shader_location = 14,
        }, .{
            .format = .float32x4,
            .offset = @offsetOf(Pill, "end_color"),
            .shader_location = 15,
        } };

        const vertex_buffers = [_]wgpu.VertexBufferLayout{ .{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }, .{
            .array_stride = @sizeOf(Pill),
            .step_mode = .instance,
            .attribute_count = instance_attributes.len,
            .attributes = &instance_attributes,
        } };

        const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
            .vertex = wgpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = wgpu.PrimitiveState{
                .front_face = .ccw,
                .cull_mode = .back,
                .topology = .triangle_strip,
                .strip_index_format = .uint16,
            },
            .depth_stencil = &wgpu.DepthStencilState{
                .format = .depth32_float,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .fragment = &wgpu.FragmentState{
                .module = fs_module,
                .entry_point = "main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
        };
        break :pipline gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    };

    const bind_group = gctx.createBindGroup(bind_group_layout, &.{
        .{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0,
            .size = @sizeOf(zm.Mat),
        },
    });

    // Create a depth texture and its 'view'.
    const depth = createDepthTexture(gctx);

    return .{
        .window = window,
        .gctx = gctx,
        .pills = std.ArrayList(Pill).init(allocator),
        .vertex_count = 0,
        .dimension = calculateDimensions(gctx),
        .pipeline = pipeline,
        .vertex_buffer = .{},
        .index_buffer = .{},
        .instance_buffer = .{},
        .bind_group = bind_group,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
    };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try zglfw.init();
    defer zglfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    zglfw.windowHint(.context_version_major, gl_major);
    zglfw.windowHint(.context_version_minor, gl_minor);
    zglfw.windowHint(.opengl_profile, .opengl_core_profile);
    zglfw.windowHint(.opengl_forward_compat, true);
    zglfw.windowHint(.client_api, .opengl_api);
    zglfw.windowHint(.doublebuffer, true);

    const window = try zglfw.Window.create(600, 600, "zig-gamedev: minimal_glfw_gl", null);
    defer window.destroy();

    zglfw.makeContextCurrent(window);

    try zopengl.loadCoreProfile(zglfw.getProcAddress, gl_major, gl_minor);

    const gl = zopengl.bindings;

    zglfw.swapInterval(1);

    game.init(allocator);
    var game_graph = game.GameGraph.withHooks(poll, submit).init(
        allocator,
        .{
            .orbit_camera = types.OrbitCamera{ .position = .{ 0, 0, 0, 1 }, .rotation = .{ 0, 0, 0, 1 }, .track_distance = 2 },
            .player = types.Player{ .position = .{ 0, 0, 0, 1 }, .euler_rotation = .{ 0, 0, 0, 0 } },
        },
    );

    while (!window.shouldClose()) {
        zglfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.2, 0.4, 0.4, 1.0 });

        game_graph.update();

        window.swapBuffers();
    }
}

// Provide inputs to the back-end from the user, disk and network.
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

// Recieve state changes back to the front-end to show to user.
fn submit(comptime field_tag: GameGraph.OutputTag, value: std.meta.fieldInfo(GameGraph.Outputs, field_tag).type) void {
    _ = value;
    // std.debug.print("Got something back for field, {s}! {any}\n", .{ @tagName(field_tag), value });
}
