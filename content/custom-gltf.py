import bpy

# get out of edit mode
bpy.ops.object.mode_set(mode="OBJECT")

# For each mesh, gather all polygons, these we'll export seperately to a json format - mesh -> polygons (indices)
meshes = []
nodes = []
armatures = []
for object in bpy.data.objects:
    print("Exporting " + object.name + " " + object.type)
    nodes.append(
        {
            "name": object.name,
            "type": object.type,
            "parent": object.parent.name if object.parent != None else None,
            "position": [object.location.x, object.location.y, object.location.z],
            "rotation": [
                object.rotation_euler.x,
                object.rotation_euler.y,
                object.rotation_euler.z,
            ],
            "scale": [object.scale.x, object.scale.y, object.scale.z],
        }
    )
    if object.type == "ARMATURE":
        armature = object.data
        bones = []
        for bone in armature.bones:
            bones.append(
                {
                    "name": bone.name,
                    "parent": bone.parent.name if bone.parent != None else None,
                    "position": [
                        bone.matrix_local.to_translation().x,
                        bone.matrix_local.to_translation().y
                        + (bone.parent.length if bone.parent != None else 0),
                        bone.matrix_local.to_translation().z,
                    ],
                    "rotation": [
                        bone.matrix_local.to_euler().x,
                        bone.matrix_local.to_euler().y,
                        bone.matrix_local.to_euler().z,
                    ],
                    "scale": [
                        bone.matrix_local.to_scale().x,
                        bone.matrix_local.to_scale().y,
                        bone.matrix_local.to_scale().z,
                    ],
                }
            )
        armatures.append({"name": armature.name, "bones": bones})
    if object.type == "MESH":
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
            vertices.append([vertex.co.x, vertex.co.y, vertex.co.z, 1])
        # Extract armature weighting
        vertexGroups = {}
        for vertexGroup in object.vertex_groups:
            vertexGroups[vertexGroup.name] = []
        for vertex in mesh.vertices:
            for group in vertex.groups:
                vertexGroups[object.vertex_groups[group.group].name].append(
                    [vertex.index, group.weight]
                )
        # Extract shape keys
        shapeKeys = []
        if mesh.shape_keys != None:
            for shapeKey in mesh.shape_keys.key_blocks:
                shapeVerts = shapeKey.data.values()
                verts = []
                for vert in shapeVerts:
                    verts.append([vert.co.x, vert.co.y, vert.co.z, 1])
                shapeKeys.append({"name": shapeKey.name, "vertices": verts})
        meshes.append(
            {
                "name": mesh.name,
                "polygons": polygons,
                "vertices": vertices,
                "shapeKeys": shapeKeys,
                "vertexGroups": vertexGroups,
            }
        )
# Get animation data
actions = []
for action in bpy.data.actions:
    fcurves = []
    for fcurve in action.fcurves:
        keyframes = []
        for keyframe in fcurve.keyframe_points:
            keyframes.append([keyframe.co.x, keyframe.co.y])
        fcurves.append(
            {
                "data_path": fcurve.data_path,
                "array_index": fcurve.array_index,
                "keyframes": keyframes,
            }
        )
    actions.append({"name": action.name, "fcurves": fcurves})
import os
import json

with open(
    bpy.path.abspath("//")
    + os.path.basename(bpy.context.blend_data.filepath)
    + ".json",
    "w",
) as file:
    json.dump(
        {"actions": actions, "nodes": nodes, "armatures": armatures, "meshes": meshes},
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
