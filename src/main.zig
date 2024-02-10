const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zmath = @import("zmath");
const Vertex = @import("./MeshLoader.zig").Vertex;

const subdiv = @import("./subdiv.zig");

const window_title = "zig-gamedev: triangle (wgpu)";

// zig fmt: off
const wgsl_vs =
\\  @group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;
\\  struct VertexOut {
\\      @builtin(position) position_clip: vec4<f32>,
\\      @location(0) color: vec3<f32>,
\\      @location(1) normal: vec3<f32>,
\\  }
\\  @vertex fn main(
\\      @location(0) position: vec3<f32>,
\\      @location(1) color: vec3<f32>,
\\      @location(2) normal: vec3<f32>,
\\  ) -> VertexOut {
\\      var output: VertexOut;
\\      output.position_clip = vec4(position, 1.0) * object_to_clip;
\\      output.color = color;
\\      output.normal = normal;
\\      return output;
\\  }
;
const wgsl_fs =
\\  @fragment fn main(
\\      @location(0) color: vec3<f32>,
\\      @location(1) normal: vec3<f32>,
\\  ) -> @location(0) vec4<f32> {
\\      return vec4((normal + vec3(1.0, 1.0, 1.0)) / 2.0, 1.0);
\\  }
// zig fmt: on
;

const Model = struct {
    label: []const u8,
    vert_count: u32,
    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,
};

const DemoState = struct {
    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    models: std.ArrayList(Model),

    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,
};

fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !DemoState {
    const gctx = try zgpu.GraphicsContext.create(allocator, window, .{});

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

        const vertex_attributes = [_]wgpu.VertexAttribute{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "color"), .shader_location = 1 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "normal"), .shader_location = 2 },
        };
        const vertex_buffers = [_]wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};

        const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
            .vertex = wgpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = wgpu.PrimitiveState{
                .front_face = .ccw,
                .cull_mode = .none,
                .topology = .triangle_list,
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

    const bind_group = gctx.createBindGroup(bind_group_layout, &[_]zgpu.BindGroupEntryInfo{.{
        .binding = 0,
        .buffer_handle = gctx.uniforms.buffer,
        .offset = 0,
        .size = @sizeOf(zmath.Mat),
    }});

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const meshes = try @import("./MeshLoader.zig").getMeshes(arena.allocator());

    var models = std.ArrayList(Model).init(allocator);
    for (meshes.items) |mesh| {

        // Create a vertex buffer.
        const vertex_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = mesh.vertices.len * @sizeOf(Vertex),
        });
        gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, mesh.vertices[0..]);

        // Create an index buffer.
        const index_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .index = true },
            .size = mesh.indices.len * @sizeOf(u32),
        });
        gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, u32, mesh.indices[0..]);

        try models.append(.{
            .label = try allocator.dupe(u8, mesh.label),
            .vert_count = @intCast(mesh.indices.len),
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
        });
    }

    // Create a depth texture and its 'view'.
    const depth = createDepthTexture(gctx);

    return DemoState{
        .gctx = gctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .models = models,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
    };
}

fn deinit(allocator: std.mem.Allocator, demo: *DemoState) void {
    demo.gctx.destroy(allocator);
    demo.models.deinit();
    demo.* = undefined;
}

fn update(demo: *DemoState, allocator: std.mem.Allocator) !void {
    _ = allocator; // autofix
    zgui.backend.newFrame(
        demo.gctx.swapchain_descriptor.width,
        demo.gctx.swapchain_descriptor.height,
    );
    // zgui.showDemoWindow(null);
    try stateInspector.inspect(&state);
}

const Instance = struct {
    object_to_world: zmath.Mat,
    mesh: subdiv.Mesh,
};

fn draw(demo: *DemoState) void {
    const gctx = demo.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;
    const t = @as(f32, @floatCast(gctx.stats.time));
    _ = t;

    const cam_world_to_view = zmath.mul(
        zmath.inverse(zmath.matFromRollPitchYawV(zmath.loadArr3(state.camera_view.rotation))),
        zmath.inverse(zmath.translationV(zmath.loadArr3(state.camera_view.translation))),
    );
    const cam_view_to_clip = zmath.perspectiveFovLh(
        0.25 * math.pi,
        @as(f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height)),
        0.1,
        500.0,
    );
    const cam_world_to_clip = zmath.mul(cam_world_to_view, cam_view_to_clip);

    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        pass: {
            const pipeline = gctx.lookupResource(demo.pipeline) orelse break :pass;
            const bind_group = gctx.lookupResource(demo.bind_group) orelse break :pass;
            const depth_view = gctx.lookupResource(demo.depth_texture_view) orelse break :pass;

            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .clear,
                .store_op = .store,
            }};
            const depth_attachment = wgpu.RenderPassDepthStencilAttachment{
                .view = depth_view,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_clear_value = 1.0,
            };
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
                .depth_stencil_attachment = &depth_attachment,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            pass.setPipeline(pipeline);

            for (demo.models.items) |model| {
                // std.debug.print("Drawing model: {s}\n", .{model.label});

                const vb_info = gctx.lookupResourceInfo(model.vertex_buffer) orelse break :pass;
                const ib_info = gctx.lookupResourceInfo(model.index_buffer) orelse break :pass;
                pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
                pass.setIndexBuffer(ib_info.gpuobj.?, .uint32, 0, ib_info.size);

                // Draw model.
                const object_to_world = zmath.identity(); //zmath.mul(zmath.rotationY(0.75 * 0), zmath.translation(1.0, 0.0, 0.0));
                const object_to_clip = zmath.mul(object_to_world, cam_world_to_clip);

                const mem = gctx.uniformsAllocate(zmath.Mat, 1);
                mem.slice[0] = zmath.transpose(object_to_clip);

                pass.setBindGroup(0, bind_group, &.{mem.offset});
                pass.drawIndexed(model.vert_count, 1, 0, 0, 0);
            }
        }
        {
            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .load,
                .store_op = .store,
            }};
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            zgui.backend.draw(pass);
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gctx.submit(&.{commands});

    if (gctx.present() == .swap_chain_resized) {
        // Release old depth texture.
        gctx.releaseResource(demo.depth_texture_view);
        gctx.destroyResource(demo.depth_texture);

        // Create a new depth texture to match the new window size.
        const depth = createDepthTexture(gctx);
        demo.depth_texture = depth.texture;
        demo.depth_texture_view = depth.view;
    }
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
    });
    const view = gctx.createTextureView(texture, .{});
    return .{ .texture = texture, .view = view };
}

// Define a struct for the expected JSON object
const ViewUpdate = struct {
    rotation: [3]f32,
    translation: [3]f32,
};

// Some game state.

const State = struct {
    camera_view: ViewUpdate,
};
var state: State = .{
    .camera_view = ViewUpdate{ .rotation = .{ 0.0, 0.0, 0.0 }, .translation = .{ 0.0, 0.0, -200.0 } },
};

const StateInspector = @import("./StateInspector.zig");
var stateInspector: StateInspector = undefined;

pub fn main() !void {
    std.debug.print("Hello, triangle!\n", .{});

    zglfw.init() catch {
        std.log.err("Failed to initialize GLFW library.\n", .{});
        return;
    };
    defer zglfw.terminate();

    // Change current working directory to where the executable is located.
    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        std.os.chdir(path) catch {};
    }

    const window = zglfw.Window.create(1600, 1000, window_title, null) catch {
        std.log.err("Failed to create demo window.\n", .{});
        return;
    };
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    stateInspector = try StateInspector.init(allocator);

    var demo = init(allocator, window) catch {
        std.log.err("Failed to initialize the demo.\n", .{});
        return;
    };
    defer deinit(allocator, &demo);

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    zgui.init(allocator);
    defer zgui.deinit();

    _ = zgui.io.addFontFromMemory(@embedFile("content/Roboto-Medium.ttf"), math.floor(16.0 * scale_factor));

    zgui.backend.init(
        window,
        demo.gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer zgui.backend.deinit();

    zgui.getStyle().scaleAllSizes(scale_factor);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        try update(&demo, allocator);
        draw(&demo);
    }
}
