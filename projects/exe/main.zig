const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zgui = @import("zgui");
const zm = @import("zmath");

const subdiv = @import("subdiv");

const content_dir = @import("build_options").content_dir;
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
\\      return vec4(normal, 1.0);
\\  }
// zig fmt: on
;

const Vertex = struct {
    position: [3]f32,
    color: [3]f32,
    normal: [3]f32,
};

const DemoState = struct {
    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    vert_count: u32,
    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,

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

    const bind_group = gctx.createBindGroup(bind_group_layout, &[_]zgpu.BindGroupEntryInfo{
        .{ .binding = 0, .buffer_handle = gctx.uniforms.buffer, .offset = 0, .size = @sizeOf(zm.Mat) },
    });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const mesh = mesh: {

        // Load seperately a json file with the polygon data, should be called *.gltf.json
        const polygonJSON = json: {
            const json_data = std.fs.cwd().readFileAlloc(arena.allocator(), content_dir ++ "boss.blend.json", 512 * 1024 * 1024) catch |err| {
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

        // pack into subdiv mesh for processing
        const first = polygonJSON.value[4];

        const firstRoundSubd = subdiv.Subdiv(true);
        const secondRoundSubd = subdiv.Subdiv(false);

        // Start a timer
        var first_results = first_results: {
            var timer = try std.time.Timer.start();

            var first_round = try firstRoundSubd.cmcSubdiv(arena.allocator(), first.shapeKeys[0].vertices, first.polygons);
            var second_round = try secondRoundSubd.cmcSubdiv(arena.allocator(), first_round.points, first_round.quads);
            var third_round = try secondRoundSubd.cmcSubdiv(arena.allocator(), second_round.points, second_round.quads);

            var ns = timer.read();

            std.debug.print("Subdiv took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
            break :first_results [_]subdiv.Mesh{ first_round, second_round, third_round };
        };

        // Second round with only points calculations (have to reuse the face calcs from first pass)
        var second_results = second_results: {
            var timer = try std.time.Timer.start();

            var first_round = try firstRoundSubd.cmcSubdivOnlyPoints(arena.allocator(), first.shapeKeys[1].vertices, first.polygons);
            var second_round = try secondRoundSubd.cmcSubdivOnlyPoints(arena.allocator(), first_round, first_results[0].quads);
            var third_round = try secondRoundSubd.cmcSubdivOnlyPoints(arena.allocator(), second_round, first_results[1].quads);

            var ns = timer.read();

            std.debug.print("Second round took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
            break :second_results third_round;
        };

        // Start a timer
        var third_results = third_results: {
            var timer = try std.time.Timer.start();

            var first_round = try firstRoundSubd.cmcSubdiv(arena.allocator(), first.vertices, first.polygons);
            var second_round = try secondRoundSubd.cmcSubdiv(arena.allocator(), first_round.points, first_round.quads);
            var third_round = try secondRoundSubd.cmcSubdiv(arena.allocator(), second_round.points, second_round.quads);

            var ns = timer.read();

            std.debug.print("Subdiv took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
            break :third_results [_]subdiv.Mesh{ first_round, second_round, third_round };
        };
        _ = third_results;

        // Second round with only points calculations (have to reuse the face calcs from first pass)
        var fourth_results = fourth_results: {
            var timer = try std.time.Timer.start();

            var first_round = try firstRoundSubd.cmcSubdivOnlyPoints(arena.allocator(), first.vertices, first.polygons);
            var second_round = try secondRoundSubd.cmcSubdivOnlyPoints(arena.allocator(), first_round, first_results[0].quads);
            var third_round = try secondRoundSubd.cmcSubdivOnlyPoints(arena.allocator(), second_round, first_results[1].quads);

            var ns = timer.read();

            std.debug.print("Second round took {d} ms\n", .{@as(f64, @floatFromInt(ns)) / 1_000_000});
            break :fourth_results third_round;
        };
        _ = fourth_results;

        std.debug.print("Got {} points and {} faces\n", .{ second_results.len, first_results[2].quads.len });

        break :mesh subdiv.Mesh{ .points = second_results, .quads = first_results[2].quads };
    };

    const hexColors = [_][3]f32{
        .{ 1.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 1.0 },
        .{ 1.0, 1.0, 0.0 },
        .{ 1.0, 0.0, 1.0 },
        .{ 0.0, 1.0, 1.0 },
    };

    var vertex_data = vertex_data: {
        var vertex_data = std.ArrayList(Vertex).init(arena.allocator());
        var vertexToQuad = std.AutoHashMap(u32, std.ArrayList(*const [4]u32)).init(arena.allocator());
        for (mesh.quads) |*quad| {
            for (quad) |vertex| {
                var quadsList = if (vertexToQuad.get(vertex)) |existing| existing else std.ArrayList(*const [4]u32).init(arena.allocator());
                try quadsList.append(quad);
                try vertexToQuad.put(vertex, quadsList);
            }
        }
        for (mesh.points, 0..) |point, i| {
            var normal = if (vertexToQuad.get(@intCast(i))) |quads| normal: {
                var normal = subdiv.Point{ 0, 0, 0, 0 };
                for (quads.items) |quad| {
                    var quad_normal = zm.cross3(mesh.points[quad[0]] - mesh.points[quad[2]], mesh.points[quad[1]] - mesh.points[quad[2]]);
                    normal += zm.normalize3(quad_normal) / @as(@Vector(4, f32), @splat(@floatFromInt(quads.items.len)));
                }
                break :normal normal;
            } else subdiv.Point{ 0, 0, 0, 0 };
            try vertex_data.append(Vertex{ .position = @as([4]f32, point)[0..3].*, .color = hexColors[i % hexColors.len], .normal = @as([4]f32, normal)[0..3].* });
        }
        break :vertex_data vertex_data.items;
    };

    var index_data = index_data: {
        var index_data = std.ArrayList(u32).init(arena.allocator());
        for (mesh.quads) |face| {
            try index_data.append(face[1]);
            try index_data.append(face[2]);
            try index_data.append(face[0]);
            try index_data.append(face[2]);
            try index_data.append(face[0]);
            try index_data.append(face[3]);
        }
        break :index_data index_data.items;
    };

    // Create a vertex buffer.
    const vertex_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = vertex_data.len * @sizeOf(Vertex),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, vertex_data[0..]);

    // Create an index buffer.
    const index_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = index_data.len * @sizeOf(u32),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, u32, index_data[0..]);

    // Create a depth texture and its 'view'.
    const depth = createDepthTexture(gctx);

    return DemoState{
        .gctx = gctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .vert_count = if (false) 6 else @intCast(index_data.len),
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
    };
}

fn deinit(allocator: std.mem.Allocator, demo: *DemoState) void {
    demo.gctx.destroy(allocator);
    demo.* = undefined;
}

fn update(demo: *DemoState) void {
    zgui.backend.newFrame(
        demo.gctx.swapchain_descriptor.width,
        demo.gctx.swapchain_descriptor.height,
    );
    zgui.showDemoWindow(null);
}

fn draw(demo: *DemoState) void {
    const gctx = demo.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;
    const t = @as(f32, @floatCast(gctx.stats.time));

    const cam_world_to_view = zm.lookAtLh(
        zm.f32x4(3.0, 3.0, -3.0, 1.0),
        zm.f32x4(0.0, 0.0, 0.0, 1.0),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );
    const cam_view_to_clip = zm.perspectiveFovLh(
        0.25 * math.pi,
        @as(f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height)),
        0.01,
        200.0,
    );
    const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        pass: {
            const vb_info = gctx.lookupResourceInfo(demo.vertex_buffer) orelse break :pass;
            const ib_info = gctx.lookupResourceInfo(demo.index_buffer) orelse break :pass;
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

            pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
            pass.setIndexBuffer(ib_info.gpuobj.?, .uint32, 0, ib_info.size);

            pass.setPipeline(pipeline);

            // Draw triangle 1.
            {
                const object_to_world = zm.mul(zm.rotationY(t), zm.translation(-1.0, 0.0, 0.0));
                const object_to_clip = zm.mul(object_to_world, cam_world_to_clip);

                const mem = gctx.uniformsAllocate(zm.Mat, 1);
                mem.slice[0] = zm.transpose(object_to_clip);

                pass.setBindGroup(0, bind_group, &.{mem.offset});
                pass.drawIndexed(demo.vert_count, 1, 0, 0, 0);
            }

            // Draw triangle 2.
            {
                const object_to_world = zm.mul(zm.rotationY(0.75 * t), zm.translation(1.0, 0.0, 0.0));
                const object_to_clip = zm.mul(object_to_world, cam_world_to_clip);

                const mem = gctx.uniformsAllocate(zm.Mat, 1);
                mem.slice[0] = zm.transpose(object_to_clip);

                pass.setBindGroup(0, bind_group, &.{mem.offset});
                pass.drawIndexed(demo.vert_count, 1, 0, 0, 0);
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
        .sample_count = 1,
    });
    const view = gctx.createTextureView(texture, .{});
    return .{ .texture = texture, .view = view };
}

pub fn main() !void {
    zglfw.init() catch {
        std.log.err("Failed to initialize GLFW library.", .{});
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
        std.log.err("Failed to create demo window.", .{});
        return;
    };
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var demo = init(allocator, window) catch {
        std.log.err("Failed to initialize the demo.", .{});
        return;
    };
    defer deinit(allocator, &demo);

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    zgui.init(allocator);
    defer zgui.deinit();

    _ = zgui.io.addFontFromFile(content_dir ++ "Roboto-Medium.ttf", math.floor(16.0 * scale_factor));

    zgui.backend.init(
        window,
        demo.gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
    );
    defer zgui.backend.deinit();

    zgui.getStyle().scaleAllSizes(scale_factor);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        update(&demo);
        draw(&demo);
    }
}