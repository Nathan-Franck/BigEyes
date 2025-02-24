
fn matrix_from_instance(i: Instance) -> mat4x4<f32> {
   // Convert quaternion to rotation matrix
   var x: f32 = i.rotation.x;
   var y: f32 = i.rotation.y;
   var z: f32 = i.rotation.z;
   var w: f32 = i.rotation.w;
   var rotationMatrix: mat3x3<f32> = mat3x3(
       1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y),
       2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x),
       2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)
   );
   // Scale the rotation matrix
   var scaledRotation: mat3x3<f32> = mat3x3(
       rotationMatrix[0] * i.scale.x,
       rotationMatrix[1] * i.scale.y,
       rotationMatrix[2] * i.scale.z
   );
   // Expand scaledRotation into a mat4
   var transform: mat4x4<f32> = mat4x4(
       vec4(scaledRotation[0], 0.0),
       vec4(scaledRotation[1], 0.0),
       vec4(scaledRotation[2], 0.0),
       i.position
   );
   return transform;
}

@vertex fn main(vertex: Vertex, instance: Instance) -> Fragment {
    // WebGPU mat4x4 are column vectors - TODO might be a bug for me once this actually runs...
    var fragment: Fragment;
    var instance_mat: mat4x4<f32> = matrix_from_instance(instance);
    fragment.position = vertex.position * instance_mat * object_to_clip;
    fragment.normal = vertex.normal;
    return fragment;
}
