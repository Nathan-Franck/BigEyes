import bpy

# Export glTF 2.0 using project path as the file name
# bpy.ops.export_scene.gltf(filepath=bpy.path.abspath("//") + bpy.path.basename(bpy.context.blend_data.filepath) + ".gltf")
# Save as above, but ensure it uses the gltf encoding instead of glb
bpy.ops.export_scene.gltf(filepath=bpy.path.abspath("//") + bpy.path.basename(bpy.context.blend_data.filepath) + ".gltf", export_format='GLTF_EMBEDDED')

# For each mesh, gather all polygons, these we'll export seperately to a json format - mesh -> polygons (indices)
meshes = []
for mesh in bpy.data.meshes:
    polygons = []
    vertices = []
    for polygon in mesh.polygons:
        polygonRes = []
        for index in polygon.vertices:
            polygonRes.append(index)
        polygons.append(polygonRes)
    for vertex in mesh.vertices:
        vertices.append([vertex.co.x, vertex.co.y, vertex.co.z])
    meshes.append({ "name":mesh.name, "polygons":polygons, "vertices":vertices })
# import json
# with open(bpy.path.abspath("//") + "polygons.json", "w") as file:
#     json.dump(meshes, file, indent=4)
# Instead, export using the name of the file as the json file name
import os
import json
with open(bpy.path.abspath("//") + os.path.basename(bpy.context.blend_data.filepath) + ".json", "w") as file:
    json.dump(meshes, file, indent=4)
