import bpy

# get out of edit mode
bpy.ops.object.mode_set(mode='OBJECT')

# For each mesh, gather all polygons, these we'll export seperately to a json format - mesh -> polygons (indices)
meshes = []
for object in bpy.data.objects:
    if object.type != "MESH":
        continue
    mesh = object.data
    bpy.context.view_layer.objects.active = object
    for modifier in object.modifiers:
        if modifier.show_render:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    # apply mesh modifiers if they are enabled in the render
    # mesh.transform(mesh.matrix_world)
    polygons = []
    vertices = []
    for polygon in mesh.polygons:
        polygonRes = []
        for index in polygon.vertices:
            polygonRes.append(index)
        polygons.append(polygonRes)
    for vertex in mesh.vertices:
        vertices.append([vertex.co.x, vertex.co.y, vertex.co.z])
    # Extract shape keys
    shapeKeys = []
    if mesh.shape_keys != None:
        for shapeKey in mesh.shape_keys.key_blocks:
            shapeVerts = shapeKey.data.values()
            verts = []
            for vert in shapeVerts:
                verts.append([vert.co.x, vert.co.y, vert.co.z])
            shapeKeys.append({ "name":shapeKey.name, "vertices":verts })
    meshes.append({ "name":mesh.name, "polygons":polygons, "vertices":vertices, "shapeKeys":shapeKeys })
import os
import json
with open(bpy.path.abspath("//") + os.path.basename(bpy.context.blend_data.filepath) + ".json", "w") as file:
    json.dump(meshes, file, indent=4)
print("Export of " + bpy.path.abspath("//") + os.path.basename(bpy.context.blend_data.filepath) + ".json" + " complete")