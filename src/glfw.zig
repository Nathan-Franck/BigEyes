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
    // zig fmt: off
const common =
\\  struct FrameUniforms {
\\      world_to_clip: mat4x4<f32>,
\\      camera_position: vec3<f32>,
\\  }
\\  @group(0) @binding(0) var<uniform> frame_uniforms: FrameUniforms;
;
pub const vs = common ++
\\  struct Instance {
\\      @location(10) position: vec3<f32>,
\\      @location(11) rotation: vec4<f32>,
\\      @location(12) scale: f32,
\\      @location(13) basecolor_roughness: vec4<f32>,
\\  }
\\  struct VertexOut {
\\      @builtin(position) position_clip: vec4<f32>,
\\      @location(0) position: vec3<f32>,
\\      @location(1) normal: vec3<f32>,
\\      @location(2) barycentrics: vec3<f32>,
\\      @location(3) basecolor_roughness: vec4<f32>,
\\  }
\\  struct Vertex {
\\      @location(0) position: vec3<f32>,
\\      @location(1) normal: vec3<f32>,
\\      @builtin(vertex_index) index: u32,
\\  }
\\ fn matrix_from_instance(i: Instance) -> mat4x4<f32> {
\\    var x: f32 = i.rotation.x;
\\    var y: f32 = i.rotation.y;
\\    var z: f32 = i.rotation.z;
\\    var w: f32 = i.rotation.w;
\\    var rotationMatrix: mat3x3<f32> = mat3x3(
\\        1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y),
\\        2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x),
\\        2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)
\\    );
\\    var scaledRotation: mat3x3<f32> = mat3x3(
\\        rotationMatrix[0] * i.scale,
\\        rotationMatrix[1] * i.scale,
\\        rotationMatrix[2] * i.scale
\\    );
\\    var transform: mat4x4<f32> = mat4x4(
\\        vec4(scaledRotation[0], i.position.x),
\\        vec4(scaledRotation[1], i.position.y),
\\        vec4(scaledRotation[2], i.position.z),
\\        vec4(0.0, 0.0, 0.0, 1.0),
\\    );
\\    return transform;
\\ }
\\  @vertex fn main(
\\      vertex: Vertex,
\\      instance: Instance,
\\  ) -> VertexOut {
\\      var output: VertexOut;
\\      let transform = matrix_from_instance(instance);
\\      output.position_clip = vec4(vertex.position, 1.0) * transform * frame_uniforms.world_to_clip;
\\      output.position = (vec4(vertex.position, 1.0) * transform).xyz;
\\      output.normal = vertex.normal * mat3x3(
\\          transform[0].xyz,
\\          transform[1].xyz,
\\          transform[2].xyz,
\\      );
\\      let index = vertex.index % 3u;
\\      output.barycentrics = vec3(f32(index == 0u), f32(index == 1u), f32(index == 2u));
\\      output.basecolor_roughness = instance.basecolor_roughness;
\\      return output;
\\  }
;
pub const fs = common ++
\\  const pi = 3.1415926;
\\
\\  fn saturate(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }
\\
\\  // Trowbridge-Reitz GGX normal distribution function.
\\  fn distributionGgx(n: vec3<f32>, h: vec3<f32>, alpha: f32) -> f32 {
\\      let alpha_sq = alpha * alpha;
\\      let n_dot_h = saturate(dot(n, h));
\\      let k = n_dot_h * n_dot_h * (alpha_sq - 1.0) + 1.0;
\\      return alpha_sq / (pi * k * k);
\\  }
\\
\\  fn geometrySchlickGgx(x: f32, k: f32) -> f32 {
\\      return x / (x * (1.0 - k) + k);
\\  }
\\
\\  fn geometrySmith(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, k: f32) -> f32 {
\\      let n_dot_v = saturate(dot(n, v));
\\      let n_dot_l = saturate(dot(n, l));
\\      return geometrySchlickGgx(n_dot_v, k) * geometrySchlickGgx(n_dot_l, k);
\\  }
\\
\\  fn fresnelSchlick(h_dot_v: f32, f0: vec3<f32>) -> vec3<f32> {
\\      return f0 + (vec3(1.0, 1.0, 1.0) - f0) * pow(1.0 - h_dot_v, 5.0);
\\  }
\\
\\  @fragment fn main(
\\      @location(0) position: vec3<f32>,
\\      @location(1) normal: vec3<f32>,
\\      @location(2) barycentrics: vec3<f32>,
\\      @location(3) basecolor_roughness: vec4<f32>,
\\  ) -> @location(0) vec4<f32> {
\\      let v = normalize(frame_uniforms.camera_position - position);
\\      let n = normalize(normal);
\\
\\      let base_color = basecolor_roughness.xyz;
\\      let ao = 1.0;
\\      var roughness = basecolor_roughness.a;
\\      var metallic: f32;
\\      if (roughness < 0.0) { metallic = 1.0; } else { metallic = 0.0; }
\\      roughness = abs(roughness);
\\
\\      let alpha = roughness * roughness;
\\      var k = alpha + 1.0;
\\      k = (k * k) / 8.0;
\\      var f0 = vec3(0.04);
\\      f0 = mix(f0, base_color, metallic);
\\
\\      let light_positions = array<vec3<f32>, 4>(
\\          vec3(25.0, 15.0, 25.0),
\\          vec3(-25.0, 15.0, 25.0),
\\          vec3(25.0, 15.0, -25.0),
\\          vec3(-25.0, 15.0, -25.0),
\\      );
\\      let light_radiance = array<vec3<f32>, 4>(
\\          4.0 * vec3(0.0, 100.0, 250.0),
\\          8.0 * vec3(200.0, 150.0, 250.0),
\\          3.0 * vec3(200.0, 0.0, 0.0),
\\          9.0 * vec3(200.0, 150.0, 0.0),
\\      );
\\
\\      var lo = vec3(0.0);
\\      for (var light_index: i32 = 0; light_index < 4; light_index = light_index + 1) {
\\          let lvec = light_positions[light_index] - position;
\\
\\          let l = normalize(lvec);
\\          let h = normalize(l + v);
\\
\\          let distance_sq = dot(lvec, lvec);
\\          let attenuation = 1.0 / distance_sq;
\\          let radiance = light_radiance[light_index] * attenuation;
\\
\\          let f = fresnelSchlick(saturate(dot(h, v)), f0);
\\
\\          let ndf = distributionGgx(n, h, alpha);
\\          let g = geometrySmith(n, v, l, k);
\\
\\          let numerator = ndf * g * f;
\\          let denominator = 4.0 * saturate(dot(n, v)) * saturate(dot(n, l));
\\          let specular = numerator / max(denominator, 0.001);
\\
\\          let ks = f;
\\          let kd = (vec3(1.0) - ks) * (1.0 - metallic);
\\
\\          let n_dot_l = saturate(dot(n, l));
\\          lo = lo + (kd * base_color / pi + specular) * radiance * n_dot_l;
\\      }
\\
\\      let ambient = vec3(0.03) * base_color * ao;
\\      var color = ambient + lo;
\\      color = color / (color + 1.0);
\\      color = pow(color, vec3(1.0 / 2.2));
\\
\\      // wireframe
\\      var barys = barycentrics;
\\      barys.z = 1.0 - barys.x - barys.y;
\\      let deltas = fwidth(barys);
\\      let smoothing = deltas * 1.0;
\\      let thickness = deltas * 0.25;
\\      barys = smoothstep(thickness, thickness + smoothing, barys);
\\      let min_bary = min(barys.x, min(barys.y, barys.z));
\\      return vec4(min_bary * color, 1.0);
\\  }
// zig fmt: on
    ;
};

const content_dir = @import("build_options").content_dir;
const window_title = "zig-gamedev: procedural mesh (wgpu)";

const IndexType = zmesh.Shape.IndexType;

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
    camera_position: [3]f32,
};

const Mesh = struct {
    index_offset: u32,
    vertex_offset: i32,
    num_indices: u32,
    num_vertices: u32,
};

const Drawable = struct {
    mesh_index: u32,
    position: [3]f32,
    basecolor_roughness: [4]f32,
};

const GameState = struct {
    window: *zglfw.Window,
    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,

    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,
    instance_buffer: zgpu.BufferHandle,

    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,

    meshes: std.ArrayList(Mesh),
    drawables: std.ArrayList(Drawable),

    mouse: struct {
        cursor_pos: [2]f64 = .{ 0, 0 },
    } = .{},

    graph: GameGraph.withFrontend(@This()) = undefined,

    world_matrix: zm.Mat = undefined,
    camera_position: zm.Vec = undefined,

    bounce: bool = false,
    last_cursor_pos: [2]f64 = .{ 0, 0 },

    // Provide inputs to the back-end from the user, disk and network.
    pub fn poll(self: *@This(), comptime field_tag: GameGraph.InputTag) std.meta.fieldInfo(GameGraph.Inputs, field_tag).type {
        return switch (field_tag) {
            .time => @intCast(@divFloor(std.time.nanoTimestamp(), std.time.ns_per_ms)),
            .render_resolution => blk: {
                const size = self.window.getSize();
                break :blk .{ .x = @intCast(size[0]), .y = @intCast(size[1]) };
            },

            .input => blk: {
                zglfw.pollEvents();
                const cursor_pos = self.window.getCursorPos();
                defer self.last_cursor_pos = cursor_pos;

                break :blk .{
                    .mouse_delta = .{ @floatCast(cursor_pos[0] - self.last_cursor_pos[0]), @floatCast(cursor_pos[1] - self.last_cursor_pos[1]), 0, 0 },
                    .movement = .{ .left = null, .right = null, .forward = null, .backward = null },
                };
            },

            .selected_camera => .orbit,
            .orbit_speed => 0.01,
            .player_settings => .{ .movement_speed = 0.01, .look_speed = 0.001 },

            .bounce => zgui.checkbox("bounce", .{ .v = &self.bounce }),
            .size_multiplier => 1,
        };
    }

    // Recieve state changes back to the front-end to show to user.
    pub fn submit(self: *@This(), comptime field_tag: GameGraph.OutputTag, value: std.meta.fieldInfo(GameGraph.Outputs, field_tag).type) void {
        switch (field_tag) {
            .world_matrix, .camera_position => @field(self, @tagName(field_tag)) = value,
            else => {},
        }
    }
};

fn appendMesh(
    mesh: zmesh.Shape,
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_positions: *std.ArrayList([3]f32),
    meshes_normals: *std.ArrayList([3]f32),
) void {
    meshes.append(.{
        .index_offset = @as(u32, @intCast(meshes_indices.items.len)),
        .vertex_offset = @as(i32, @intCast(meshes_positions.items.len)),
        .num_indices = @as(u32, @intCast(mesh.indices.len)),
        .num_vertices = @as(u32, @intCast(mesh.positions.len)),
    }) catch unreachable;

    meshes_indices.appendSlice(mesh.indices) catch unreachable;
    meshes_positions.appendSlice(mesh.positions) catch unreachable;
    meshes_normals.appendSlice(mesh.normals.?) catch unreachable;
}

fn initScene(
    allocator: std.mem.Allocator,
    drawables: *std.ArrayList(Drawable),
    meshes: *std.ArrayList(Mesh),
    meshes_indices: *std.ArrayList(IndexType),
    meshes_positions: *std.ArrayList([3]f32),
    meshes_normals: *std.ArrayList([3]f32),
) void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    zmesh.init(arena);
    defer zmesh.deinit();

    // Trefoil knot.
    {
        var mesh = zmesh.Shape.initTrefoilKnot(10, 128, 0.8);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 0, 1, 0 },
            .basecolor_roughness = .{ 0.0, 0.7, 0.0, 0.6 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Parametric sphere.
    {
        var mesh = zmesh.Shape.initParametricSphere(20, 20);
        defer mesh.deinit();
        mesh.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 3, 1, 0 },
            .basecolor_roughness = .{ 0.7, 0.0, 0.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Icosahedron.
    {
        var mesh = zmesh.Shape.initIcosahedron();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ -3, 1, 0 },
            .basecolor_roughness = .{ 0.7, 0.6, 0.0, 0.4 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Dodecahedron.
    {
        var mesh = zmesh.Shape.initDodecahedron();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 0, 1, 3 },
            .basecolor_roughness = .{ 0.0, 0.1, 1.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Cylinder with top and bottom caps.
    {
        var disk = zmesh.Shape.initParametricDisk(10, 2);
        defer disk.deinit();
        disk.invert(0, 0);

        var cylinder = zmesh.Shape.initCylinder(10, 4);
        defer cylinder.deinit();

        cylinder.merge(disk);
        cylinder.translate(0, 0, -1);
        disk.invert(0, 0);
        cylinder.merge(disk);

        cylinder.scale(0.5, 0.5, 2);
        cylinder.rotate(math.pi * 0.5, 1.0, 0.0, 0.0);

        cylinder.unweld();
        cylinder.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ -3, 0, 3 },
            .basecolor_roughness = .{ 1.0, 0.0, 0.0, 0.3 },
        }) catch unreachable;

        appendMesh(cylinder, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Torus.
    {
        var mesh = zmesh.Shape.initTorus(10, 20, 0.2);
        defer mesh.deinit();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 3, 1.5, 3 },
            .basecolor_roughness = .{ 1.0, 0.5, 0.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Subdivided sphere.
    {
        var mesh = zmesh.Shape.initSubdividedSphere(3);
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 3, 1, 6 },
            .basecolor_roughness = .{ 0.0, 1.0, 0.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Tetrahedron.
    {
        var mesh = zmesh.Shape.initTetrahedron();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 0, 0.5, 6 },
            .basecolor_roughness = .{ 1.0, 0.0, 1.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Octahedron.
    {
        var mesh = zmesh.Shape.initOctahedron();
        defer mesh.deinit();
        mesh.unweld();
        mesh.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ -3, 1, 6 },
            .basecolor_roughness = .{ 0.2, 0.0, 1.0, 0.2 },
        }) catch unreachable;

        appendMesh(mesh, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Rock.
    {
        var rock = zmesh.Shape.initRock(123, 4);
        defer rock.deinit();
        rock.unweld();
        rock.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ -6, 0, 3 },
            .basecolor_roughness = .{ 1.0, 1.0, 1.0, 1.0 },
        }) catch unreachable;

        appendMesh(rock, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
    // Custom parametric (simple terrain).
    {
        const gen = znoise.FnlGenerator{
            .fractal_type = .fbm,
            .frequency = 2.0,
            .octaves = 5,
            .lacunarity = 2.02,
        };
        const local = struct {
            fn terrain(uv: *const [2]f32, position: *[3]f32, userdata: ?*anyopaque) callconv(.C) void {
                _ = userdata;
                position[0] = uv[0];
                position[1] = 0.025 * gen.noise2(uv[0], uv[1]);
                position[2] = uv[1];
            }
        };
        var ground = zmesh.Shape.initParametric(local.terrain, 40, 40, null);
        defer ground.deinit();
        ground.translate(-0.5, -0.0, -0.5);
        ground.invert(0, 0);
        ground.scale(20, 20, 20);
        ground.computeNormals();

        drawables.append(.{
            .mesh_index = @as(u32, @intCast(meshes.items.len)),
            .position = .{ 0, 0, 0 },
            .basecolor_roughness = .{ 0.1, 0.1, 0.1, 1.0 },
        }) catch unreachable;

        appendMesh(ground, meshes, meshes_indices, meshes_positions, meshes_normals);
    }
}

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

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const bind_group_layout = gctx.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
    });
    defer gctx.releaseResource(bind_group_layout);

    const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});
    defer gctx.releaseResource(pipeline_layout);

    const pipeline = pipeline: {
        const vs_module = zgpu.createWgslShaderModule(gctx.device, wgsl.vs, "vs");
        defer vs_module.release();

        const fs_module = zgpu.createWgslShaderModule(gctx.device, wgsl.fs, "fs");
        defer fs_module.release();

        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

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

    const bind_group = gctx.createBindGroup(bind_group_layout, &.{
        .{
            .binding = 0,
            .buffer_handle = gctx.uniforms.buffer,
            .offset = 0,
            .size = @sizeOf(FrameUniforms),
        },
    });

    var drawables = std.ArrayList(Drawable).init(allocator);
    var meshes = std.ArrayList(Mesh).init(allocator);
    var meshes_indices = std.ArrayList(IndexType).init(arena);
    var meshes_positions = std.ArrayList([3]f32).init(arena);
    var meshes_normals = std.ArrayList([3]f32).init(arena);
    initScene(allocator, &drawables, &meshes, &meshes_indices, &meshes_positions, &meshes_normals);

    const total_num_vertices = @as(u32, @intCast(meshes_positions.items.len));
    const total_num_indices = @as(u32, @intCast(meshes_indices.items.len));

    // Create a vertex buffer.
    const vertex_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = total_num_vertices * @sizeOf(Vertex),
    });
    {
        var vertex_data = std.ArrayList(Vertex).init(arena);
        defer vertex_data.deinit();
        vertex_data.resize(total_num_vertices) catch unreachable;

        for (meshes_positions.items, 0..) |_, i| {
            vertex_data.items[i].position = meshes_positions.items[i];
            vertex_data.items[i].normal = meshes_normals.items[i];
        }
        gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, vertex_data.items);
    }

    // Create an index buffer.
    const index_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = total_num_indices * @sizeOf(IndexType),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, IndexType, meshes_indices.items);

    var instances = std.ArrayList(Instance).init(allocator);
    for (drawables.items) |drawable| {
        try instances.append(.{
            .position = drawable.position,
            .rotation = .{ 0, 0, 0, 1 },
            .scale = 1,
            .basecolor_roughness = drawable.basecolor_roughness,
        });
    }
    const instance_buffer = gctx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = instances.items.len * @sizeOf(Instance),
    });
    gctx.queue.writeBuffer(gctx.lookupResource(instance_buffer).?, 0, Instance, instances.items);

    // Create a depth texture and its 'view'.
    const depth = createDepthTexture(gctx);

    return GameState{
        .window = window,
        .gctx = gctx,
        .pipeline = pipeline,
        .bind_group = bind_group,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .instance_buffer = instance_buffer,
        .depth_texture = depth.texture,
        .depth_texture_view = depth.view,
        .meshes = meshes,
        .drawables = drawables,
    };
}

fn deinit(allocator: std.mem.Allocator, game: *GameState) void {
    game.meshes.deinit();
    game.drawables.deinit();
    game.gctx.destroy(allocator);
    game.* = undefined;
}

fn update(game: *GameState) void {
    zgui.backend.newFrame(
        game.gctx.swapchain_descriptor.width,
        game.gctx.swapchain_descriptor.height,
    );

    game.graph.update();

    zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .always });
    zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .always });

    if (zgui.begin("Gamer Settings", .{ .flags = .{ .no_move = true, .no_resize = true } })) {
        zgui.bulletText(
            "Average : {d:.3} ms/frame ({d:.1} fps)",
            .{ game.gctx.stats.average_cpu_time, game.gctx.stats.fps },
        );
        zgui.bulletText("RMB + drag : rotate camera", .{});
        zgui.bulletText("W, A, S, D : move camera", .{});
    }
    zgui.end();
}

fn draw(game: *GameState) void {
    const gctx = game.gctx;

    const back_buffer_view = gctx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gctx.device.createCommandEncoder(null);
        defer encoder.release();

        // Main pass.
        pass: {
            const vb_info = gctx.lookupResourceInfo(game.vertex_buffer) orelse break :pass;
            const itb_info = gctx.lookupResourceInfo(game.instance_buffer) orelse break :pass;
            const ib_info = gctx.lookupResourceInfo(game.index_buffer) orelse break :pass;
            const pipeline = gctx.lookupResource(game.pipeline) orelse break :pass;
            const bind_group = gctx.lookupResource(game.bind_group) orelse break :pass;
            const depth_view = gctx.lookupResource(game.depth_texture_view) orelse break :pass;

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
            pass.setVertexBuffer(1, itb_info.gpuobj.?, 0, itb_info.size);

            pass.setIndexBuffer(ib_info.gpuobj.?, if (IndexType == u16) .uint16 else .uint32, 0, ib_info.size);

            pass.setPipeline(pipeline);

            // Update "world to clip" (camera) xform.
            {
                const mem = gctx.uniformsAllocate(FrameUniforms, 1);
                mem.slice[0].world_to_clip = zm.transpose(game.world_matrix);
                mem.slice[0].camera_position = @as([4]f32, @bitCast(game.camera_position))[0..3].*;

                pass.setBindGroup(0, bind_group, &.{mem.offset});
            }

            for (game.drawables.items) |drawable| {

                // Draw.
                pass.drawIndexed(
                    game.meshes.items[drawable.mesh_index].num_indices,
                    1,
                    game.meshes.items[drawable.mesh_index].index_offset,
                    game.meshes.items[drawable.mesh_index].vertex_offset,
                    drawable.mesh_index,
                );
            }
        }

        // Gui pass.
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

    const window = try zglfw.Window.create(1600, 1000, window_title, null);
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

    const dir = content_dir ++ "Roboto-Medium.ttf";
    std.debug.print("dir {s}\n", .{dir});
    // _ = zgui.io.addFontFromFile(content_dir ++ "Roboto-Medium.ttf", math.floor(16.0 * scale_factor));

    zgui.backend.init(
        window,
        game.gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer zgui.backend.deinit();

    zgui.backend.newFrame(0, 0);
    game.graph = .init(allocator, &game, .{ .orbit_camera = .{
        .position = .{ 0, 0, 0, 1 },
        .rotation = .{ 0, 0, 0, 1 },
        .track_distance = 1,
    }, .player = .{
        .position = .{ 0, 0, 0, 1 },
        .euler_rotation = .{ 0, 0, 0, 0 },
    } });

    zgui.getStyle().scaleAllSizes(scale_factor);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();
        update(&game);
        draw(&game);
    }
}
