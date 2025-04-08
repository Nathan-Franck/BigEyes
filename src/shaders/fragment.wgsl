const pi = 3.1415926;

@group(0) @binding(1) var shadow_sampler: sampler;
@group(0) @binding(2) var shadow_texture: texture_depth_2d;

fn saturate(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

fn getShadowFactor(world_pos: vec3<f32>) -> f32 {
  // Transform world position to light space
  let pos_light_space = vec4(world_pos, 1.0) * frame_uniforms.light_view_proj;
  
  // Transform to [0,1] range
  let uv = vec2(pos_light_space.xy * vec2(0.5, -0.5) + vec2(0.5));
  
  // Current fragment depth
  let current_depth = pos_light_space.z;
  
  // Sample depth from shadow map - this returns a single f32 value
  let shadow_depth = textureSample(shadow_texture, shadow_sampler, uv);
  
  // Check if fragment is in shadow
  var shadow: f32 = 1.0; // Default to fully lit
  if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
    // Compare current depth with shadow map depth
    // If current_depth > shadow_depth, the fragment is in shadow
    if (current_depth > shadow_depth + 0.0) { // Add bias to avoid shadow acne
      shadow = 0.0; // In shadow
    }
  }
  
  return shadow;
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

  let base_color = basecolor_roughness.xyz;
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
  let light_dir = normalize(vec3(0.5, -0.8, -0.2));
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

  return vec4( getShadowFactor(position), 0, 0, 1);//color, 1.0);
}
