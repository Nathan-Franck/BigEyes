const std = @import("std");
const zglfw = @import("zglfw");
const GameGraph = @import("game").GameGraph;
const runtime = @import("node_graph").runtime;
const game_backend = @import("game");
const zgpu = @import("zgpu");
const zgui = @import("zgui");
const Vec4 = @import("utils").Vec4;
const zmath = @import("zmath");
const types = @import("utils").types;
const resources = @import("resources");

const wgpu = zgpu.wgpu;
const math = std.math;
const assert = std.debug.assert;
const print = std.debug.print;

const content_dir = @import("build_options").content_dir;

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
++ @embedFile("glfw/greybox.vert.wgsl");

const wgsl_fs =
    \\  struct Fragment {
    \\      @location(0) normal: vec4<f32>,
    \\  }
    \\  struct Screen {
    \\      @location(0) color: vec4<f32>,
    \\  }
    \\
++ @embedFile("glfw/greybox.frag.wgsl");

const Game = struct {
    window: *zglfw.Window,
    gctx: *zgpu.GraphicsContext,
    dimensions: Dimensions,
    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,
    depth: Depth,
    pass: wgpu.RenderPassEncoder = undefined,

    pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !@This() {
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

        { // IMGUI
            zgui.init(allocator);
            const scale_factor = scale_factor: {
                const scale = window.getContentScale();
                break :scale_factor @max(scale[0], scale[1]);
            };
            const cwd = try std.process.getCwdAlloc(allocator);
            const path = try std.fmt.allocPrintZ(allocator, "{s}/" ++ content_dir ++ "Roboto-Medium.ttf", .{cwd});
            std.debug.print("Path to font {s}\n", .{path});
            const font_normal = zgui.io.addFontFromFile(
                path,
                math.floor(20.0 * scale_factor),
            );
            assert(zgui.io.getFont(0) == font_normal);

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
        }

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

        const depth = createDepthTexture(gctx);

        return .{
            .window = window,
            .gctx = gctx,
            .dimensions = calculateDimensions(gctx),
            .pipeline = pipeline,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .bind_group = bind_group,
            .depth = depth,
        };
    }

    const Dimensions = struct {
        width: f32,
        height: f32,
    };

    fn calculateDimensions(gctx: *zgpu.GraphicsContext) Dimensions {
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

    const Depth = struct {
        texture: zgpu.TextureHandle,
        view: zgpu.TextureViewHandle,
    };

    fn createDepthTexture(gctx: *zgpu.GraphicsContext) Depth {
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

    // Global state
    var bounce: bool = false;

    // Provide inputs to the back-end from the user, disk and network.
    pub fn poll(self: @This(), comptime field_tag: GameGraph.InputTag) std.meta.fieldInfo(GameGraph.Inputs, field_tag).type {
        _ = self;
        return switch (field_tag) {
            .time => 0,
            .render_resolution => .{ .x = 0, .y = 0 },
            .orbit_speed => 1,
            .input => .{ .mouse_delta = .{ 0, 0, 0, 0 }, .movement = .{ .left = null, .right = null, .forward = null, .backward = null } },
            .selected_camera => .orbit,
            .player_settings => .{ .movement_speed = 0.01, .look_speed = 0.01 },
            .bounce => zgui.checkbox("bounce", .{ .v = &bounce }),
            .size_multiplier => 1,
        };
    }

    // Recieve state changes back to the front-end to show to user.
    pub fn submit(self: @This(), comptime field_tag: GameGraph.OutputTag, value: std.meta.fieldInfo(GameGraph.Outputs, field_tag).type) void {
        switch (field_tag) {
            .world_matrix => {
                const mem = self.gctx.uniformsAllocate(struct { world_matrix: zmath.Mat }, 1);
                mem.slice[0].world_matrix = value;

                const bind_group = self.gctx.lookupResource(self.bind_group) orelse @panic("ono");

                self.pass.setBindGroup(0, bind_group, &.{mem.offset});
            },
            else => {},
        }
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    try zglfw.init();
    defer zglfw.terminate();

    zglfw.windowHint(.client_api, .no_api);

    const window = try zglfw.Window.create(600, 600, "zig-gamedev: minimal_glfw_wgpu", null);
    defer window.destroy();

    zglfw.makeContextCurrent(window);

    // zglfw.swapInterval(1);

    var game = try Game.init(allocator, window);
    // _ = gpu_state;

    game_backend.init(allocator);

    var game_graph: ?game_backend.GameGraph.withFrontend(Game) = null;
    while (!window.shouldClose()) {
        zglfw.pollEvents();

        { // IMGUI update
            zgui.backend.newFrame(
                game.gctx.swapchain_descriptor.width,
                game.gctx.swapchain_descriptor.height,
            );
            _ = zgui.begin("Pill", .{
                .flags = .{
                    // .no_title_bar = true,
                    // .no_move = true,
                    // .no_collapse = true,
                    // .always_auto_resize = true,
                },
            });
            defer zgui.end();

            if (game_graph) |*graph| {
                graph.update();
            } else {
                game_graph = .init(
                    allocator,
                    game,
                    .{
                        .orbit_camera = types.OrbitCamera{ .position = .{ 0, 0, 0, 1 }, .rotation = .{ 0, 0, 0, 1 }, .track_distance = 2 },
                        .player = types.Player{ .position = .{ 0, 0, 0, 1 }, .euler_rotation = .{ 0, 0, 0, 0 } },
                    },
                );
                game_graph.?.update();
            }
        }

        { // Final Render
            const gctx = game.gctx;

            const back_buffer_view = gctx.swapchain.getCurrentTextureView();
            defer back_buffer_view.release();

            const commands = commands: {
                const encoder = gctx.device.createCommandEncoder(null);
                defer encoder.release();
                {
                    const vb_info = gctx.lookupResourceInfo(game.vertex_buffer).?;
                    const ib_info = gctx.lookupResourceInfo(game.index_buffer).?;
                    const pipeline = gctx.lookupResource(game.pipeline).?;
                    // const bind_group = gctx.lookupResource(game.bind_group).?;
                    const depth_view = gctx.lookupResource(game.depth_texture_view).?;

                    const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                        .view = back_buffer_view,
                        .load_op = .load,
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

                    game.pass = encoder.beginRenderPass(render_pass_info);
                    defer {
                        game.pass.end();
                        game.pass.release();
                    }

                    game.pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
                    game.pass.setIndexBuffer(
                        ib_info.gpuobj.?,
                        .uint32,
                        0,
                        ib_info.size,
                    );

                    game.pass.setPipeline(pipeline);

                    { // IMGUI update
                        zgui.backend.newFrame(
                            game.gctx.swapchain_descriptor.width,
                            game.gctx.swapchain_descriptor.height,
                        );
                        _ = zgui.begin("Pill", .{});
                        defer zgui.end();

                        if (game_graph) |*graph| {
                            graph.update();
                        } else {
                            game_graph = .init(
                                allocator,
                                game,
                                .{
                                    .orbit_camera = types.OrbitCamera{ .position = .{ 0, 0, 0, 1 }, .rotation = .{ 0, 0, 0, 1 }, .track_distance = 2 },
                                    .player = types.Player{ .position = .{ 0, 0, 0, 1 }, .euler_rotation = .{ 0, 0, 0, 0 } },
                                },
                            );
                            game_graph.?.update();
                        }
                    }

                    zgui.backend.draw(game.pass);
                }

                break :commands encoder.finish(null);
            };

            gctx.submit(&.{commands});
            if (gctx.present() == .swap_chain_resized) {
                gctx.releaseResource(game.depth.view);
                gctx.destroyResource(game.depth.texture);
                game.dimensions = Game.calculateDimensions(gctx);
                game.depth = Game.createDepthTexture(gctx);
            }
        }
        window.swapBuffers();
    }
}
