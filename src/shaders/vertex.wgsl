struct Instance {
    @location(10) position: vec3<f32>,
    @location(11) rotation: vec4<f32>,
    @location(12) scale: f32,
    @location(13) basecolor_roughness: vec4<f32>,
}

struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(3) basecolor_roughness: vec4<f32>,
}

struct Vertex {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @builtin(vertex_index) index: u32,
}

fn matrix_from_instance(i: Instance) -> mat4x4<f32> {
    var x: f32 = i.rotation.x;
    var y: f32 = i.rotation.y;
    var z: f32 = i.rotation.z;
    var w: f32 = i.rotation.w;
    var rotationMatrix: mat3x3<f32> = mat3x3(
        1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y),
        2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x),
        2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)
    );
    var scaledRotation: mat3x3<f32> = mat3x3(
        rotationMatrix[0] * i.scale,
        rotationMatrix[1] * i.scale,
        rotationMatrix[2] * i.scale
    );
    var transform: mat4x4<f32> = mat4x4(
        vec4(scaledRotation[0], i.position.x),
        vec4(scaledRotation[1], i.position.y),
        vec4(scaledRotation[2], i.position.z),
        vec4(0.0, 0.0, 0.0, 1.0),
    );
    return transform;
}

@vertex fn main(
    vertex: Vertex,
    instance: Instance,
) -> VertexOut {
    var output: VertexOut;
    let transform = matrix_from_instance(instance);
    output.position_clip = vec4(vertex.position, 1.0) * transform * frame_uniforms.world_to_clip;
    output.position = (vec4(vertex.position, 1.0) * transform).xyz;
    output.normal = vertex.normal * mat3x3(
        transform[0].xyz,
        transform[1].xyz,
        transform[2].xyz,
    );
    let index = vertex.index % 3u;
    output.basecolor_roughness = instance.basecolor_roughness;
    return output;
}
