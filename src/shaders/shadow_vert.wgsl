struct FrameUniforms {
  light_view_proj: mat4x4<f32>,
}
@group(0) @binding(0) var<uniform> frame_uniforms: FrameUniforms;

struct Instance {
  @location(10) position: vec3<f32>,
  @location(11) rotation: vec4<f32>,
  @location(12) scale: f32,
  @location(13) basecolor_roughness: vec4<f32>,
}

struct Vertex {
  @location(0) position: vec3<f32>,
  @location(1) normal: vec3<f32>,
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
) -> @builtin(position) vec4<f32> {
  let transform = matrix_from_instance(instance);
  let offset = normalize(vertex.normal) * 0.003;
  return vec4(vertex.position - offset, 1.0) * transform * frame_uniforms.light_view_proj;
}
