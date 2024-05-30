import bpy
import mathutils
import struct

# get out of edit mode
bpy.ops.object.mode_set(mode="OBJECT")

# For each mesh, gather all polygons, these we'll export seperately to a json format - mesh -> polygons (indices)
meshes = []
nodes = []
# armatures = []
for object in bpy.data.objects:
    print("Exporting " + object.name + " " + object.type)
    matrix = object.matrix_local
    nodes.append(
        {
            "name": object.name,
            "type": object.type,
            "parent": object.parent.name if object.parent != None else None,
            "position": [
                matrix.to_translation().x,
                matrix.to_translation().y,
                matrix.to_translation().z,
            ],
            "rotation": [matrix.to_euler().x, matrix.to_euler().y, matrix.to_euler().z],
            "scale": [matrix.to_scale().x, matrix.to_scale().y, matrix.to_scale().z],
        }
    )
    # if object.type == "ARMATURE":
    #     armature = object.data
    #     bones = []
    #     for bone in armature.bones:
    #         matrix = bone.matrix_local
    #         bones.append(
    #             {
    #                 "name": bone.name,
    #                 "parent": bone.parent.name if bone.parent != None else None,
    #                 "position": [
    #                     matrix.to_translation().x,
    #                     matrix.to_translation().y
    #                     + (bone.parent.length if bone.parent != None else 0),
    #                     matrix.to_translation().z,
    #                 ],
    #                 "rotation": [
    #                     matrix.to_euler().x,
    #                     matrix.to_euler().y,
    #                     matrix.to_euler().z,
    #                 ],
    #                 "scale": [
    #                     matrix.to_scale().x,
    #                     matrix.to_scale().y,
    #                     matrix.to_scale(te).z,
    #                 ],
    #             }
    #         )
    #     armatures.append({"name": armature.name, "bones": bones})
    if object.type == "MESH":
        mesh = object.data
        bpy.context.view_layer.objects.active = object
        for modifier in object.modifiers:
            if modifier.show_render:
                bpy.ops.object.modifier_apply(modifier=modifier.name)
        # apply mesh modifiers if they are enabled in the render
        # mesh.transform(mesh.matrix_world)
        polygons = []
        for polygon in mesh.polygons:
            polygonRes = []
            for index in polygon.vertices:
                polygonRes.append(index)
            polygons.append(polygonRes)
        frame_to_vertices = []
        for frame in range(bpy.context.scene.frame_start, bpy.context.scene.frame_end): 
            vertices = []
            for vertex in mesh.vertices:
                vertices.append([vertex.co.x, vertex.co.y, -vertex.co.z, 1])
            vertex_strings = [] 
            for vertex in mesh.vertices:
                vertex_array = [vertex.co.x, vertex.co.y, -vertex.co.z, 1] 
                vertex_string = ''.join(''.join(format(byte, '02x') for byte in struct.pack('<f', value)) for value in vertex_array)
                vertex_strings.append(vertex_string)
            frame_to_vertices.append(''.join(vertex_strings))
        # Extract armature weighting
        # vertexGroups = {}
        # for vertexGroup in object.vertex_groups:
        #     vertexGroups[vertexGroup.name] = []
        # for vertex in mesh.vertices:
        #     for group in vertex.groups:
        #         vertexGroups[object.vertex_groups[group.group].name].append(
        #             {"index": vertex.index, "weight": group.weight}
        #         )
        # # Extract shape keys
        # shapeKeys = []
        # if mesh.shape_keys != None:
        #     for shapeKey in mesh.shape_keys.key_blocks:
        #         shapeVerts = shapeKey.data.values()
        #         verts = []
        #         for vert in shapeVerts:
        #             verts.append([vert.co.x, vert.co.y, -vert.co.z, 1])
        #         shapeKeys.append({"name": shapeKey.name, "vertices": verts})
        meshes.append(
            {
                "name": mesh.name,
                "polygons": polygons,
                "frame_to_vertices": frame_to_vertices,
                # "shapeKeys": shapeKeys,
                # "vertexGroups": [
                #     {
                #         "name": key,
                #         "vertices": vertexGroups[key],
                #     }
                #     for key in vertexGroups
                # ],
            }
        )
# # Get animation data
# actions = []
# for action in bpy.data.actions:
#     fcurves = []
#     for fcurve in action.fcurves:
#         keyframes = []
#         for keyframe in fcurve.keyframe_points:
#             keyframes.append([keyframe.co.x, keyframe.co.y])
#         fcurves.append(
#             {
#                 "data_path": fcurve.data_path,
#                 "array_index": fcurve.array_index,
#                 "keyframes": keyframes,
#             }
#         )
#     actions.append({"name": action.name, "fcurves": fcurves})
import os
import json


with open(
    bpy.path.abspath("//")
    + os.path.basename(bpy.context.blend_data.filepath)
    + ".json",
    "w",
) as file:
    json.dump(
        {
            # "actions": actions,
            # "armatures": armatures,
            "nodes": nodes,
            "meshes": meshes,
        },
        file,
        indent=4,
    )
print(
    "Export of "
    + bpy.path.abspath("//")
    + os.path.basename(bpy.context.blend_data.filepath)
    + ".json"
    + " complete"
)
