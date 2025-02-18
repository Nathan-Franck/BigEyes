const std = @import("std");
const zglfw = @import("zglfw");
const zopengl = @import("zopengl");
const GameGraph = @import("game").GameGraph;
const runtime = @import("node_graph").new_runtime;
const game = @import("game");
const zgpu = @import("zgpu");
const zgui = @import("zgui");
const Vec4 = @import("utils").Vec4;
const zmath = @import("zmath");

const wgpu = zgpu.wgpu;
const math = std.math;
const assert = std.debug.assert;

const content_dir = @import("build_options").content_dir;

const types = game.types;

const Vertex = struct {
    position: Vec4,
    normal: Vec4,
};

const Instance = struct {
    position: Vec4,
    rotation: Vec4,
    scale: Vec4,
};

const vertex_attributes = [_]wgpu.VertexAttribute{ .{
    .format = .float32x4,
    .offset = @offsetOf(Vertex, "position"),
    .shader_location = 0,
}, .{
    .format = .float32x4,
    .offset = @offsetOf(Vertex, "normal"),
    .shader_location = 1,
} };

const instance_attributes = [_]wgpu.VertexAttribute{ .{
    .format = .float32x4,
    .offset = @offsetOf(Instance, "position"),
    .shader_location = 10,
}, .{
    .format = .float32x4,
    .offset = @offsetOf(Instance, "rotation"),
    .shader_location = 11,
}, .{
    .format = .float32x4,
    .offset = @offsetOf(Instance, "scale"),
    .shader_location = 12,
} };

// zig fmt: off
const wgsl_vs =
\\  @group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;
\\
\\  struct Vertex {
\\      @location(0) position: vec4<f32>,
\\      @location(1) normal: vec4<f32>,
\\  }
\\
\\  struct Instance {
\\      @location(10) position: vec4<f32>,
\\      @location(11) rotation: vec4<f32>,
\\      @location(12) scale: vec4<f32>,
\\  }
\\
\\  struct Fragment {
\\      @builtin(position) position: vec4<f32>,
\\      @location(0) normal: vec4<f32>,
\\  }
\\
\\  mat4 matrix_from_instance(instance: Instance) -> mat4x4<f32> {
\\     // Convert quaternion to rotation matrix
\\     var x: f32 = rotation.x, y = rotation.y, z = rotation.z, w = rotation.w;
\\     var rotationMatrix: mat3x3<f32> = mat3x3(
\\         1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y),
\\         2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x),
\\         2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)
\\     );
\\     
\\     // Scale the rotation matrix
\\     var scaledRotation: mat3x3<f32> = mat3x3(
\\         rotationMatrix[0] * scale.x,
\\         rotationMatrix[1] * scale.y,
\\         rotationMatrix[2] * scale.z
\\     );
\\     
\\     // Expand scaledRotation into a mat4
\\     var transform: mat4x4 = mat4x4(
\\         vec4(scaledRotation[0], 0.0),
\\         vec4(scaledRotation[1], 0.0),
\\         vec4(scaledRotation[2], 0.0),
\\         position
\\     );
\\     return transform;
\\  }
\\
\\  @vertex fn main(vertex: Vertex, instance: Instance) -> Fragment {
\\      // WebGPU mat4x4 are column vectors - TODO might be a bug for me once this actually runs...
\\      var fragment: Fragment;
\\      var instance_mat: mat4x4<f32> = matrix_from_instance(instance);
\\      fragment.position = vec4(vertex.position, 1.0) * instance_mat * object_to_clip;
\\      fragment.normal = vertex.normal;
\\      return fragment;
\\  }
;
const wgsl_fs =
\\  struct Fragment {
\\      @location(0) normal: vec4<f32>,
\\  }
\\  struct Screen {
\\      @location(0) color: vec4<f32>,
\\  }
\\
\\  @fragment fn main(fragment: Fragment) -> Screen {
\\      final_normal: vec4<f32> = vec4(normalize(fragment.normal.xyz), 0);
\\      var screen: Screen;
\\      screen.color = vec4(final_normal.xyz * 0.5 + 0.5, 1);
\\      return screen;
\\  }
// zig fmt: on
;

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

        const vertex_buffers = [_]wgpu.VertexBufferLayout{ .{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }, .{
            .array_stride = @sizeOf(Instance),
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
                .topology = .triangle_list,
                .strip_index_format = .uint32,
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
            .size = @sizeOf(zmath.Mat),
        },
    });

    // Create a depth texture and its 'view'.
    const depth = createDepthTexture(gctx);

    return .{
        .window = window,
        .gctx = gctx,
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

const Dimension = struct {
    width: f32,
    height: f32,
};

fn calculateDimensions(gctx: *zgpu.GraphicsContext) Dimension {
    const width = @as(f32, @floatFromInt(gctx.swapchain_descriptor.width));
    const height = @as(f32, @floatFromInt(gctx.swapchain_descriptor.height));
    const delta = math.sign(
        @as(i32, @bitCast(gctx.swapchain_descriptor.width)) - @as(i32, @bitCast(gctx.swapchain_descriptor.height)),
    );
    return switch (delta) {
        -1 => .{ .width = 2.0, .height = 2 * width / height },
        0 => .{ .width = 2.0, .height = 2.0 },
        1 => .{ .width = 2 * height / width, .height = 2.0 },
        else => unreachable,
    };
}

fn createDepthTexture(gctx: *zgpu.GraphicsContext) struct {
    texture: zgpu.TextureHandle,
    view: zgpu.TextureViewHandle,
} {
    const texture = gctx.createTexture(.{
        .usage = .{ .render_attachment = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = gctx.swapchain_descriptor.width,
            .height = gctx.swapchain_descriptor.height,
            .depth_or_array_layers = 1,
        },
        .format = .depth32_float,
        .mip_level_count = 1,
        .sample_count = 1,
    });
    const view = gctx.createTextureView(texture, .{});
    return .{ .texture = texture, .view = view };
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
