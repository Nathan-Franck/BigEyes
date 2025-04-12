struct FrameUniforms {
    world_to_clip: mat4x4<f32>,
    camera_position: vec3<f32>,
    light_direction: vec3<f32>,
    light_view_proj: mat4x4<f32>,  // Added for shadow mapping
    color: vec3<f32>,
}
@group(0) @binding(0) var<uniform> frame_uniforms: FrameUniforms;
