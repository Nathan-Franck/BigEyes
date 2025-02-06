pub fn Shader(props: type) type {
    for (@typeInfo(props).@"struct".fields) |field| {
        @compileLog(field.name);
    }
    return struct {
        fn Material() struct {
            props: props,
        } {
            return .{
                .props = undefined,
            };
        }
    };
}

fn Property(
    kind: enum { varying, uniform, attribute, element },
    @"type": enum {
        float,
        vec2,
        vec3,
        vec4,
        sampler2D,
        samplerCube,
        mat4,
    },
) type {
    _ = .{ kind, @"type" };
    switch (@"type") {
        f32 => {},
        i32 => {},
        else => @compileError("Unsupported type"),
    }
    return struct {};
}

pub fn build(props: anytype) Shader(@TypeOf(props)) {}

pub fn hello() void {
    const shader = Shader(struct {
        first: Property(.varying, .float),
    });
    const mat = shader.Material();
    _ = mat.props.first;
}
