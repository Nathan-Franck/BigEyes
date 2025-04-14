const pi = 3.1415926;

@group(0) @binding(1) var shadow_sampler: sampler;
@group(0) @binding(2) var shadow_texture: texture_depth_2d;

fn saturate(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn getShadowFactor(world_pos: vec3<f32>) -> f32 {
  let pos_light_space_clip = vec4(world_pos, 1.0) * frame_uniforms.light_view_proj;

  let pos_light_space = pos_light_space_clip.xyz / pos_light_space_clip.w;

  let uv = pos_light_space.xy * vec2(0.5, -0.5) + vec2(0.5);

  let current_depth = pos_light_space.z; // Assuming Z is already [0, 1] after divide

  var shadow_factor: f32 = 0.0;
  
  // --- PCF Implementation ---
  let shadow_map_size = vec2<f32>(textureDimensions(shadow_texture));
  let texel_size = 1.0 / shadow_map_size;

  // 3x3 PCF loop
  for (var y: i32 = -1; y <= 1; y = y + 1) {
    for (var x: i32 = -1; x <= 1; x = x + 1) {
      let offset = vec2<f32>(f32(x), f32(y)) * texel_size;
      let sample_uv = uv + offset;

      let shadow_depth = textureSample(shadow_texture, shadow_sampler, sample_uv);

      if (current_depth <= shadow_depth) {
        shadow_factor = shadow_factor + 1.0;
      }
    }
  }

  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    return 1.0;  
  }
  // Average the results (divide by the number of samples)
  return shadow_factor / 9.0;
}
// Trowbridge-Reitz GGX normal distribution function.
fn distributionGgx(n: vec3<f32>, h: vec3<f32>, alpha: f32) -> f32 {
  let alpha_sq = alpha * alpha;
  let n_dot_h = saturate(dot(n, h));
  let k = n_dot_h * n_dot_h * (alpha_sq - 1.0) + 1.0;
  return alpha_sq / (pi * k * k);
}

fn geometrySchlickGgx(x: f32, k: f32) -> f32 {
  return x / (x * (1.0 - k) + k);
}

fn geometrySmith(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, k: f32) -> f32 {
  let n_dot_v = saturate(dot(n, v));
  let n_dot_l = saturate(dot(n, l));
  return geometrySchlickGgx(n_dot_v, k) * geometrySchlickGgx(n_dot_l, k);
}

fn fresnelSchlick(h_dot_v: f32, f0: vec3<f32>) -> vec3<f32> {
  return f0 + (vec3(1.0, 1.0, 1.0) - f0) * pow(1.0 - h_dot_v, 5.0);
}

@fragment fn main(
  @location(0) position: vec3<f32>,
  @location(1) normal: vec3<f32>,
  @location(3) basecolor_roughness: vec4<f32>,
) -> @location(0) vec4<f32> {
  let v = normalize(frame_uniforms.camera_position - position);
  let n = normalize(normal);

  let base_color = frame_uniforms.color * basecolor_roughness.xyz;
  let ao = 1.0;
  var roughness = basecolor_roughness.a;
  var metallic: f32;
  if (roughness < 0.0) { metallic = 1.0; } else { metallic = 0.0; }
  roughness = abs(roughness);

  let alpha = roughness * roughness;
  var k = alpha + 1.0;
  k = (k * k) / 8.0;
  var f0 = vec3(0.04);
  f0 = mix(f0, base_color, metallic);

  // Use a single directional light (sun) instead of the 4 point lights
  let light_dir = normalize(frame_uniforms.light_direction);
  let light_radiance = vec3(10.0);

  // Get shadow factor
  let shadow_factor = getShadowFactor(position);

  var lo = vec3(0.0);
  
  // Calculate lighting with the directional light
  let l = -light_dir;  // Light direction (pointing from surface to light)
  let h = normalize(l + v);

  let f = fresnelSchlick(saturate(dot(h, v)), f0);

  let ndf = distributionGgx(n, h, alpha);
  let g = geometrySmith(n, v, l, k);

  let numerator = ndf * g * f;
  let denominator = 4.0 * saturate(dot(n, v)) * saturate(dot(n, l));
  let specular = numerator / max(denominator, 0.001);

  let ks = f;
  let kd = (vec3(1.0) - ks) * (1.0 - metallic);

  let n_dot_l = saturate(dot(n, l));
  lo = (kd * base_color / pi + specular) * light_radiance * n_dot_l * shadow_factor;

  let ambient = vec3(0.03) * base_color * ao;
  var color = ambient + lo;
  color = color / (color + 1.0);
  color = pow(color, vec3(1.0 / 2.2));

  return vec4(color, 1.0);
}
