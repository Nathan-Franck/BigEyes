const pi = 3.1415926;

@group(0) @binding(1) var shadow_sampler: sampler_comparison;
@group(0) @binding(2) var shadow_texture: texture_depth_2d;

fn saturate(x: f32) -> f32 { return clamp(x, 0.0, 1.0); }

// Predefined 2x2 "disk" / rotated grid offsets for PCF
// These offsets provide a slightly better distribution than a simple aligned 2x2 grid.
// Values are relative texel offsets from the center.
const pcf_disk_offsets = array<vec2<f32>, 4>(
  vec2<f32>(-1.5, -0.5),
  vec2<f32>(0.5, -1.5),
  vec2<f32>(-0.5, 1.5),
  vec2<f32>(1.5, 0.5)
);

fn getShadowFactor(world_pos: vec3<f32>) -> f32 {
  let pos_light_space_clip =
    vec4(world_pos, 1.0) * frame_uniforms.light_view_proj;

  // Perspective divide
  let pos_light_space = pos_light_space_clip.xyz / pos_light_space_clip.w;

  // Transform to texture coordinates [0, 1]
  // Flip Y coordinate for typical texture conventions
  let uv = pos_light_space.xy * vec2(0.5, -0.5) + vec2(0.5);

  // Depth in light space [0, 1] (assuming projection matrix maps depth to [0, 1])
  let current_depth = pos_light_space.z;


  var shadow_factor: f32 = 0.0;

  // --- PCF Implementation using 4 disk samples ---
  let shadow_map_size = vec2<f32>(textureDimensions(shadow_texture));
  let texel_size = 1.0 / shadow_map_size;

  // Loop through the 4 predefined offsets
  for (var i = 0u; i < 4u; i = i + 1u) {
    let offset = pcf_disk_offsets[i] / 2.0 * texel_size;
    let sample_uv = uv + offset;

    // Perform depth comparison
    shadow_factor += textureSampleCompare(
      shadow_texture,
      shadow_sampler,
      sample_uv,
      current_depth
    );
  }

  // Check if the fragment is outside the shadow map frustum
  // Add a small epsilon to avoid edge artifacts
  let epsilon = 0.001;
  if (
    uv.x < epsilon || uv.x > (1.0 - epsilon) || uv.y < epsilon ||
    uv.y > (1.0 - epsilon) || current_depth > (1.0 - epsilon)
  ) {
    // Outside the frustum, assume not shadowed
    return 1.0;
  }

  // Average the results (divide by the number of samples)
  return shadow_factor / 4.0;
}

// Trowbridge-Reitz GGX normal distribution function.
fn distributionGgx(n: vec3<f32>, h: vec3<f32>, alpha: f32) -> f32 {
  let alpha_sq = alpha * alpha;
  let n_dot_h = saturate(dot(n, h));
  let k = n_dot_h * n_dot_h * (alpha_sq - 1.0) + 1.0;
  return alpha_sq / (pi * k * k);
}

// Geometry function: Schlick approximation for GGX
fn geometrySchlickGgx(x: f32, k: f32) -> f32 {
  return x / (x * (1.0 - k) + k);
}

// Geometry function: Smith's method (combining Schlick-GGX for view and light)
fn geometrySmith(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, k: f32) -> f32 {
  let n_dot_v = saturate(dot(n, v));
  let n_dot_l = saturate(dot(n, l));
  return geometrySchlickGgx(n_dot_v, k) * geometrySchlickGgx(n_dot_l, k);
}

// Fresnel function: Schlick approximation
fn fresnelSchlick(h_dot_v: f32, f0: vec3<f32>) -> vec3<f32> {
  return f0 + (vec3(1.0, 1.0, 1.0) - f0) * pow(1.0 - h_dot_v, 5.0);
}

@fragment fn main(
  @location(0) position: vec3<f32>,
  @location(1) normal: vec3<f32>,
  @location(3) basecolor_roughness: vec4<f32>,
) -> @location(0) vec4<f32> {
  // --- Input Vectors ---
  let v = normalize(frame_uniforms.camera_position - position); // View vector
  let n = normalize(normal); // Normal vector

  // --- Material Properties ---
  let base_color = frame_uniforms.color * basecolor_roughness.xyz;
  let ao = 1.0; // Ambient Occlusion (assuming 1.0 if not provided)
  var roughness = basecolor_roughness.a;
  var metallic: f32;
  // Simple encoding: negative roughness means metallic
  if (roughness < 0.0) {
    metallic = 1.0;
  } else {
    metallic = 0.0;
  }
  roughness = abs(roughness); // Use absolute value for calculations

  // --- PBR Parameters ---
  let alpha = roughness * roughness; // GGX alpha parameter
  // Parameter for Smith's geometry function (derived from alpha)
  var k = alpha + 1.0;
  k = (k * k) / 8.0;
  // Base reflectance at normal incidence (F0)
  var f0 = vec3(0.04); // Default for non-metals
  f0 = mix(f0, base_color, metallic); // Blend towards base color for metals

  // --- Light Properties (Single Directional Light) ---
  let light_dir = normalize(frame_uniforms.light_direction); // Direction TO the light source
  let light_radiance = vec3(10.0); // Intensity/color of the light

  // --- Shadow Calculation ---
  let shadow_factor = getShadowFactor(position);

  // --- PBR Calculation ---
  var lo = vec3(0.0); // Outgoing radiance

  // Calculate lighting only if the surface faces the light
  let l = -light_dir; // Light vector (from surface TO light)
  let n_dot_l = saturate(dot(n, l));
  if (n_dot_l > 0.0) {
    let h = normalize(l + v); // Halfway vector

    // Fresnel term
    let f = fresnelSchlick(saturate(dot(h, v)), f0);
    // Normal Distribution Function (NDF)
    let ndf = distributionGgx(n, h, alpha);
    // Geometry term (masking/shadowing)
    let g = geometrySmith(n, v, l, k);

    // Cook-Torrance BRDF numerator
    let numerator = ndf * g * f;
    // Cook-Torrance BRDF denominator
    // Add small epsilon to prevent division by zero
    let denominator = 4.0 * saturate(dot(n, v)) * n_dot_l + 0.001;
    let specular = numerator / denominator;

    // Determine diffuse and specular contributions
    let ks = f; // Specular ratio comes from Fresnel
    // Diffuse ratio (energy conservation) - metals have no diffuse component
    let kd = (vec3(1.0) - ks) * (1.0 - metallic);

    // Combine diffuse and specular, scale by light radiance, NdotL, and shadow factor
    // Lambertian diffuse term: base_color / pi
    lo = (kd * base_color / pi + specular) * light_radiance * n_dot_l *
      shadow_factor;
  }

  // --- Final Color ---
  // Add ambient light
  let ambient = vec3(0.03) * base_color * ao;
  var color = ambient + lo;

  // Basic Reinhard tone mapping
  color = color / (color + vec3(1.0));
  // Gamma correction (approximate sRGB)
  color = pow(color, vec3(1.0 / 2.2));

  return vec4(color, 1.0);
}
