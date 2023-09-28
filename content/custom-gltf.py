import bpy

# set undo point
bpy.ops.ed.undo_push()

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
    meshes.append({ "name":mesh.name, "polygons":polygons, "vertices":vertices })
# import json
# with open(bpy.path.abspath("//") + "polygons.json", "w") as file:
#     json.dump(meshes, file, indent=4)
# Instead, export using the name of the file as the json file name
import os
import json
with open(bpy.path.abspath("//") + os.path.basename(bpy.context.blend_data.filepath) + ".json", "w") as file:
    json.dump(meshes, file, indent=4)
print("Export of " + bpy.path.abspath("//") + os.path.basename(bpy.context.blend_data.filepath) + ".json" + " complete")

# restore undo point
bpy.ops.ed.undo()