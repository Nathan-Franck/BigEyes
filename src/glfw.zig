const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zm = @import("zmath");
const zmesh = @import("zmesh");
const znoise = @import("znoise");
const runtime = @import("node_graph").Runtime;
const GameGraph = @import("game").GameGraph;
const wgsl = struct {
    const common = @embedFile("shaders/common.wgsl");
    pub const vs = common ++ @embedFile("shaders/vertex.wgsl");
    pub const fs = common ++ @embedFile("shaders/fragment.wgsl");
};

const content_dir = @import("build_options").content_dir;
const window_title = "zig-gamedev: procedural mesh (wgpu)";

const IndexType = u32;

const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
};

const Instance = struct {
    position: [3]f32,
    rotation: [4]f32,
    scale: f32,
    basecolor_roughness: [4]f32,
};

const FrameUniforms = struct {
    world_to_clip: zm.Mat,
    camera_position: zm.Vec, // You can't have a uniform member that is 12 bytes!
    light_direction: zm.Vec,
    light_view_proj: zm.Mat,
    color: zm.Vec,
};

const Submesh = struct {
    index_offset: u32,
    vertex_offset: i32,
    num_indices: u32,
};

const MeshResources = struct {
    num_instances: u32,
    color: zm.Vec,
    submesh: []const Submesh,
    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,
    instance_buffer: zgpu.BufferHandle,
};

const GameState = struct {
    window: *zglfw.Window,
    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    mesh_resources: std.StringHashMap(MeshResources),

    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,

    shadow_texture: zgpu.TextureHandle,
    shadow_texture_view: zgpu.TextureViewHandle,
    shadow_bind_group: zgpu.BindGroupHandle,
    shadow_pipeline: zgpu.RenderPipelineHandle,

    mouse: struct {
        cursor_pos: [2]f64 = .{ 0, 0 },
    } = .{},

    graph: GameGraph.withFrontend(@This()) = undefined,

    world_matrix: zm.Mat = undefined,
    camera_position: zm.Vec = undefined,

    last_cursor_pos: [2]f64 = .{ 0, 0 },
    should_render: bool = false,

    frame_arena: std.heap.ArenaAllocator,

    button_lookup: std.StringHashMap(?u64),

    pub fn buttonAccum(self: *@This(), comptime src: std.builtin.SourceLocation, action: zglfw.Action) ?u64 {
        const src_key = std.fmt.comptimePrint("{s}:{d}:{d}", .{ src.file, src.line, src.column });
        const previous_entry = self.button_lookup.getOrPutValue(src_key, null) catch unreachable;
        switch (action) {
            .release => {
                previous_entry.value_ptr.* = null;
            },
            .press => {
                previous_entry.value_ptr.* = @intCast(@divFloor(std.time.nanoTimestamp(), std.time.ns_per_ms));
            },
            .repeat => {},
        }
        return previous_entry.value_ptr.*;
    }

    // Provide inputs to the back-end from the user, disk and network.
    pub fn poll(self: *@This(), comptime field_tag: GameGraph.InputTag) std.meta.fieldInfo(GameGraph.Inputs, field_tag).type {
        const ms_delay = 1000 / 15; // 15 FPS
        return switch (field_tag) {
            .orbit_speed => 0.01,
            .bounce => false,
            .size_multiplier => 1,
            .selected_camera => .orbit,
            .player_settings => .{ .movement_speed = 0.01, .look_speed = 0.001 },
            .time => @intCast(@divFloor(
                std.time.nanoTimestamp(),
                std.time.ns_per_ms * ms_delay,
            ) * ms_delay),
            .render_resolution => blk: {
                const size = self.window.getSize();
                break :blk .{ .x = @intCast(size[0]), .y = @intCast(size[1]) };
            },
            .input => blk: {
                zglfw.pollEvents();
                const cursor_pos = self.window.getCursorPos();
                defer self.last_cursor_pos = cursor_pos;

                break :blk .{
                    .mouse = .{
                        .delta = .{ @floatCast(cursor_pos[0] - self.last_cursor_pos[0]), @floatCast(cursor_pos[1] - self.last_cursor_pos[1]), 0, 0 },
                        .left_click = self.buttonAccum(@src(), self.window.getMouseButton(.left)),
                        .middle_click = self.buttonAccum(@src(), self.window.getMouseButton(.middle)),
                        .right_click = self.buttonAccum(@src(), self.window.getMouseButton(.right)),
                    },
                    .movement = .{ .left = null, .right = null, .forward = null, .backward = null },
                };
            },
        };
    }

    // Receive state changes back to the front-end to show to user.
    pub fn submit(self: *@This(), comptime field_tag: GameGraph.OutputTag, value: std.meta.fieldInfo(GameGraph.Outputs, field_tag).type) !void {
        switch (field_tag) {
            .world_matrix, .camera_position => {
                @field(self, @tagName(field_tag)) = value;
                self.should_render = true;
            },
            .terrain_mesh => {
                const gctx = self.gctx;
                const vertices = try self.frame_arena.allocator().alloc(Vertex, value.position.len);
                for (vertices, value.position, value.normal) |*vertex, position, normal| {
                    zm.storeArr3(&vertex.position, position);
                    zm.storeArr3(&vertex.normal, normal);
                }

                const vertex_buffer = gctx.createBuffer(.{
                    .usage = .{ .copy_dst = true, .vertex = true },
                    .size = vertices.len * @sizeOf(Vertex),
                });
                gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, vertices);

                const index_buffer = gctx.createBuffer(.{
                    .usage = .{ .copy_dst = true, .index = true },
                    .size = value.indices.len * @sizeOf(IndexType),
                });
                gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, IndexType, value.indices);

                const result = self.mesh_resources.getOrPut("terrain") catch unreachable;
                const resources = result.value_ptr;
                resources.color = value.color;
                resources.submesh = try self.frame_arena.allocator().dupe(Submesh, &.{Submesh{
                    .index_offset = 0,
                    .vertex_offset = 0,
                    .num_indices = @intCast(value.indices.len),
                }});
                resources.vertex_buffer = vertex_buffer;
                resources.index_buffer = index_buffer;
                self.should_render = true;
            },
            .terrain_instance => {
                const gctx = self.gctx;
                const instance_buffer = gctx.createBuffer(.{
                    .usage = .{ .copy_dst = true, .vertex = true },
                    .size = 1 * @sizeOf(Instance),
                });

                var instance: Instance = undefined;
                zm.storeArr3(&instance.position, value.instances[0].position);
                zm.storeArr4(&instance.rotation, value.instances[0].position);
                instance.scale = value.instances[0].scale[0];
                instance.basecolor_roughness = .{ 1, 1, 1, 0.5 };
                gctx.queue.writeBuffer(
                    gctx.lookupResource(instance_buffer).?,
                    0,
                    Instance,
                    &.{instance},
                );

                const result = try self.mesh_resources.getOrPut("terrain");
                const resources = result.value_ptr;
                resources.num_instances = 1;
                resources.instance_buffer = instance_buffer;
                self.should_render = true;
            },
            .models => {
                const gctx = self.gctx;
                for (value) |model| {
                    var vertices: std.ArrayList(Vertex) = .init(self.frame_arena.allocator());
                    var indices: std.ArrayList(u32) = .init(self.frame_arena.allocator());
                    var submeshes: std.ArrayList(Submesh) = .init(self.frame_arena.allocator());
                    var color: zm.Vec = undefined;
                    for (model.meshes) |mesh| {
                        switch (mesh) {
                            .greybox => |greybox| {
                                color = greybox.color;
                                const submesh: Submesh = .{
                                    .index_offset = @intCast(indices.items.len),
                                    .vertex_offset = @intCast(vertices.items.len),
                                    .num_indices = @intCast(greybox.indices.len),
                                };
                                try submeshes.append(submesh);
                                for (greybox.position, greybox.normal) |position, normal| {
                                    var vertex: Vertex = undefined;
                                    zm.storeArr3(&vertex.position, position);
                                    zm.storeArr3(&vertex.normal, normal);
                                    try vertices.append(vertex);
                                }
                                try indices.appendSlice(greybox.indices);
                            },
                            else => {},
                        }
                    }

                    const vertex_buffer = gctx.createBuffer(.{
                        .usage = .{ .copy_dst = true, .vertex = true },
                        .size = vertices.items.len * @sizeOf(Vertex),
                    });
                    gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, vertices.items);

                    const index_buffer = gctx.createBuffer(.{
                        .usage = .{ .copy_dst = true, .index = true },
                        .size = indices.items.len * @sizeOf(IndexType),
                    });
                    gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, IndexType, indices.items);

                    const result = try self.mesh_resources.getOrPut(model.label);
                    const resources = result.value_ptr;
                    resources.color = color;
                    resources.submesh = submeshes.items;
                    resources.vertex_buffer = vertex_buffer;
                    resources.index_buffer = index_buffer;
                    self.should_render = true;
                }
            },
            .model_instances => {
                const gctx = self.gctx;
                for (value) |_instances| {
                    var instances: std.ArrayList(Instance) = .init(self.frame_arena.allocator());
                    for (_instances.instances) |_instance| {
                        var instance: Instance = .{
                            .scale = _instance.scale[0],
                            .basecolor_roughness = .{ 1, 1, 1, 0.5 },
                            .position = undefined,
                            .rotation = undefined,
                        };
                        zm.storeArr3(&instance.position, _instance.position);
                        zm.storeArr4(&instance.rotation, _instance.rotation);
                        try instances.append(instance);
                    }
                    const instance_buffer = gctx.createBuffer(.{
                        .usage = .{ .copy_dst = true, .vertex = true },
                        .size = instances.items.len * @sizeOf(Instance),
                    });
                    gctx.queue.writeBuffer(
                        gctx.lookupResource(instance_buffer).?,
                        0,
                        Instance,
                        instances.items,
                    );
                    const result = try self.mesh_resources.getOrPut(_instances.label);
                    const resources = result.value_ptr;
                    resources.num_instances = @intCast(instances.items.len);
                    resources.instance_buffer = instance_buffer;
                    self.should_render = true;
                }
            },
            .shadow_update_bounds => {
                std.debug.print("Bounds get! {any}\n", .{value});
            },
            else => {},
        }
    }
};

fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !GameState {
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
        .{
            .present_mode = .immediate,
        },
    );
    errdefer gctx.destroy(allocator);

    // Create common vertex and instance attributes for both pipelines
    const vertex_attributes = [_]wgpu.VertexAttribute{ .{
        .format = .float32x3,
        .offset = @offsetOf(Vertex, "position"),
        .shader_location = 0,
    }, .{
        .format = .float32x3,
        .offset = @offsetOf(Vertex, "normal"),
        .shader_location = 1,
    } };

    const instance_attributes = [_]wgpu.VertexAttribute{ .{
        .format = .float32x3,
        .offset = @offsetOf(Instance, "position"),
        .shader_location = 10,
    }, .{
        .format = .float32x4,
        .offset = @offsetOf(Instance, "rotation"),
        .shader_location = 11,
    }, .{
        .format = .float32,
        .offset = @offsetOf(Instance, "scale"),
        .shader_location = 12,
    }, .{
        .format = .float32x4,
        .offset = @offsetOf(Instance, "basecolor_roughness"),
        .shader_location = 13,
    } };

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

    // Create shadow map texture and view
    // const shadow_map_size: u32 = 8192;
    const shadow_map_size: u32 = 128;
    const shadow_texture = gctx.createTexture(.{
        .usage = .{ .render_attachment = true, .texture_binding = true },
        .dimension = .tdim_2d,
        .size = .{
            .width = shadow_map_size,
            .height = shadow_map_size,
            .depth_or_array_layers = 1,
        },
        .format = .depth32_float,
        .mip_level_count = 1,
        .sample_count = 1,
    });
    const shadow_texture_view = gctx.createTextureView(shadow_texture, .{});

    // Create shadow sampler
    const shadow_sampler = gctx.createSampler(.{
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
        .mag_filter = .linear,
        .min_filter = .linear,
        .mipmap_filter = .linear,
    });

    // Create bind group layouts
    const shadow_bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
    });
    defer gctx.releaseResource(shadow_bind_group_layout);

    const bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
        zgpu.samplerEntry(1, .{ .fragment = true }, .filtering),
        zgpu.textureEntry(2, .{ .fragment = true }, .depth, .tvdim_2d, false),
    });
    defer gctx.releaseResource(bind_group_layout);

    // Create pipeline layouts
    const shadow_pipeline_layout = gctx.createPipelineLayout(&.{shadow_bind_group_layout});
    defer gctx.releaseResource(shadow_pipeline_layout);

    const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});
    defer gctx.releaseResource(pipeline_layout);

    // Create shadow pipeline for depth-only rendering
    const shadow_pipeline = shadow_pipeline: {
        const vs_module = zgpu.createWgslShaderModule(
            gctx.device,
            @embedFile("shaders/shadow_vert.wgsl"),
            "shadow_vs",
        );
        defer vs_module.release();

        const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
            .vertex = wgpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = wgpu.PrimitiveState{
                .front_face = .cw,
                .cull_mode = .back,
                .topology = .triangle_list,
            },
            .depth_stencil = &wgpu.DepthStencilState{
                .format = .depth32_float,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            // No fragment shader needed for shadow map generation
        };
        break :shadow_pipeline gctx.createRenderPipeline(shadow_pipeline_layout, pipeline_descriptor);
    };

    // Create main rendering pipeline
    const pipeline = pipeline: {
        const vs_module = zgpu.createWgslShaderModule(gctx.device, wgsl.vs, "vs");
        defer vs_module.release();

        const fs_module = zgpu.createWgslShaderModule(gctx.device, wgsl.fs, "fs");
        defer fs_module.release();

        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        // Create a render pipeline.
        const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
            .vertex = wgpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = wgpu.PrimitiveState{
                .front_face = .cw,
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
        break :pipeline gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    };

    // Create bind groups
    const shadow_bind_group = gctx.createBindGroup(shadow_bind_group_layout, &[_]zgpu.BindGroupEntryInfo{
        .{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0,
            .size = @sizeOf(FrameUniforms),
        },
    });

    const bind_group = gctx.createBindGroup(bind_group_layout, &[_]zgpu.BindGroupEntryInfo{
        .{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0,
            .size = @sizeOf(FrameUniforms),
        },
        .{
            .binding = 1,
            .sampler_handle = shadow_sampler,
        },
        .{
            .binding = 2,
            .texture_view_handle = shadow_texture_view,
        },
    });

    // Create a depth texture and its 'view'.
    const depth = createDepthTexture(gctx);

    // Initialize mesh resources
    const mesh_resources: std.StringHashMap(MeshResources) = .init(allocator);

    return GameState{
        .window = window,
        .gctx = gctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .mesh_resources = mesh_resources,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
        .frame_arena = .init(allocator),
        .shadow_texture = shadow_texture,
        .shadow_texture_view = shadow_texture_view,
        .shadow_bind_group = shadow_bind_group,
        .shadow_pipeline = shadow_pipeline,
        .button_lookup = .init(allocator),
    };
}

fn deinit(allocator: std.mem.Allocator, game: *GameState) void {
    game.gctx.destroy(allocator);
    game.* = undefined;
}

fn updateGui(game: *const GameState) void {
    zgui.backend.newFrame(
        game.gctx.swapchain_descriptor.width,
        game.gctx.swapchain_descriptor.height,
    );

    zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .always });
    zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .always });

    if (zgui.begin("Game Settings", .{ .flags = .{ .no_move = true, .no_resize = true } })) {
        zgui.bulletText(
            "Average : {d:.3} ms/frame ({d:.1} fps)",
            .{ game.gctx.stats.average_cpu_time, game.gctx.stats.fps },
        );
        zgui.bulletText("RMB + drag : rotate camera", .{});
        zgui.bulletText("W, A, S, D : move camera", .{});
    }
    zgui.end();
}

fn drawMeshes(
    pass: wgpu.RenderPassEncoder,
    game: *const GameState,
    per_model_render: ?struct {
        bind_group: wgpu.BindGroup,
        frame_uniforms: FrameUniforms,
    },
) void {
    var mesh_resources = game.mesh_resources.iterator();
    while (mesh_resources.next()) |entry| {
        const resource = entry.value_ptr;

        if (per_model_render) |render| {
            const mem = game.gctx.uniformsAllocate(FrameUniforms, 1);
            mem.slice[0] = render.frame_uniforms;
            mem.slice[0].color = resource.color;
            pass.setBindGroup(0, render.bind_group, &.{mem.offset});
        }

        const vertex_buffer_info = game.gctx.lookupResourceInfo(resource.vertex_buffer) orelse continue;
        const instance_buffer_info = game.gctx.lookupResourceInfo(resource.instance_buffer) orelse continue;
        const index_buffer_info = game.gctx.lookupResourceInfo(resource.index_buffer) orelse continue;

        pass.setVertexBuffer(0, vertex_buffer_info.gpuobj.?, 0, vertex_buffer_info.size);
        pass.setVertexBuffer(1, instance_buffer_info.gpuobj.?, 0, instance_buffer_info.size);
        pass.setIndexBuffer(index_buffer_info.gpuobj.?, .uint32, 0, index_buffer_info.size);

        for (resource.submesh) |submesh| {
            pass.drawIndexed(
                submesh.num_indices,
                resource.num_instances,
                submesh.index_offset,
                submesh.vertex_offset,
                0,
            );
        }
    }
}

fn draw(game: *GameState) void {
    if (!game.should_render) {
        std.Thread.sleep(1_000_000);
        return;
    }
    game.should_render = false;

    updateGui(game);

    const gctx = game.gctx;

    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        // Set up light view-projection matrix once for both passes
        const light = blk: {
            const light_position = zm.f32x4(20.0, 20.0, 20.0, 1.0);
            const light_target = zm.f32x4(0.0, 0.0, 0.0, 1.0);
            const light_up = zm.f32x4(0.0, 1.0, 0.0, 0.0);
            break :blk .{
                .view = zm.lookAtLh(light_position, light_target, light_up),
                .projection = zm.orthographicLh(20.0, 20.0, 0.1, 50.0),
                .direction = light_target - light_position,
            };
        };
        const light_view_proj = zm.mul(light.view, light.projection);

        // Shadow pass - render depth from light's perspective
        {
            const pipeline = gctx.lookupResource(game.shadow_pipeline) orelse break :commands encoder.finish(null);
            const bind_group = gctx.lookupResource(game.shadow_bind_group) orelse break :commands encoder.finish(null);
            const shadow_view = gctx.lookupResource(game.shadow_texture_view) orelse break :commands encoder.finish(null);

            const depth_attachment = wgpu.RenderPassDepthStencilAttachment{
                .view = shadow_view,
                .depth_load_op = .clear,
                .depth_store_op = .store,
                .depth_clear_value = 1.0,
            };

            const render_pass_info = wgpu.RenderPassDescriptor{
                .depth_stencil_attachment = &depth_attachment,
                .color_attachments = null,
                .color_attachment_count = 0,
            };

            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            // Set up light view-projection matrix for shadow pass
            {
                const mem = gctx.uniformsAllocate(struct {
                    light_view_proj: zm.Mat,
                }, 1);
                mem.slice[0] = .{
                    .light_view_proj = zm.transpose(light_view_proj),
                };
                pass.setBindGroup(0, bind_group, &.{mem.offset});
            }

            pass.setPipeline(pipeline);
            drawMeshes(pass, game, null);
        }

        // Main pass
        {
            const pipeline = gctx.lookupResource(game.pipeline) orelse break :commands encoder.finish(null);
            const bind_group = gctx.lookupResource(game.bind_group) orelse break :commands encoder.finish(null);
            const depth_view = gctx.lookupResource(game.depth_texture_view) orelse break :commands encoder.finish(null);

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
            var pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }
            pass.setPipeline(pipeline);

            // Update bindings
            {
                const frame_uniforms: FrameUniforms = .{
                    .world_to_clip = zm.transpose(game.world_matrix),
                    .camera_position = game.camera_position,
                    .light_direction = light.direction,
                    .light_view_proj = zm.transpose(light_view_proj),
                    .color = undefined,
                };
                drawMeshes(pass, game, .{
                    .bind_group = bind_group,
                    .frame_uniforms = frame_uniforms,
                });
            }
        }

        // Gui pass
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
        gctx.releaseResource(game.depth_texture_view);
        gctx.destroyResource(game.depth_texture);

        // Create a new depth texture to match the new window size.
        const depth = createDepthTexture(gctx);
        game.depth_texture = depth.texture;
        game.depth_texture_view = depth.view;
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
        .sample_count = 1,
    });
    const view = gctx.createTextureView(texture, .{});
    return .{ .texture = texture, .view = view };
}

pub fn main() !void {
    try zglfw.init();
    defer zglfw.terminate();

    // Change current working directory to where the executable is located.
    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        std.posix.chdir(path) catch {};
    }

    zglfw.windowHint(.client_api, .no_api);

    const window = try zglfw.Window.create(640, 480, window_title, null);
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var game = try init(allocator, window);
    defer deinit(allocator, &game);

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    zgui.init(allocator);
    defer zgui.deinit();

    zgui.backend.init(
        window,
        game.gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer zgui.backend.deinit();

    zgui.backend.newFrame(0, 0);
    game.graph = .init(allocator, &game, .{
        .all_models = &.{},
        .all_instances = &.{},
        .orbit_camera = .{
            .position = .{ -3, 0, 0, 1 },
            .rotation = .{ 0, 0, 0, 1 },
            .track_distance = 10,
        },
        .player = .{
            .position = .{ 0, 0, 0, 1 },
            .euler_rotation = .{ 0, 0, 0, 0 },
        },
    });

    zgui.getStyle().scaleAllSizes(scale_factor);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        game.graph.update();
        draw(&game);
    }
}
