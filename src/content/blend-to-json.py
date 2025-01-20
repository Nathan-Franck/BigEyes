import bpy
import mathutils
import struct
import os
import json

# get out of edit mode
bpy.ops.object.mode_set(mode="OBJECT")

# For each mesh, gather all polygons, these we'll export seperately to a json format - mesh -> polygons (indices)
meshes = []
nodes = []
armatures = []
for object in bpy.data.objects:
    print("Exporting " + object.name + " " + object.type)
    translation, rotation, scale =  object.matrix_local.decompose() # Transform a point in bone space to "Armature" space
    object_data = {
        "name": object.name,
        "type": object.type,
        "parent": object.parent.name if object.parent != None else None,
        "position": [
            translation.x,
            translation.y,
            translation.z,
            0,
        ],
        "rotation": [
            rotation.x,
            rotation.y,
            rotation.z,
            rotation.w,
        ],
        "scale": [
            scale.x,
            scale.y,
            scale.z,
            0,
        ],

    };
    if object.type == "ARMATURE":
        armature = object.data
        bones = []
        for bone in armature.bones:
            bones.append(
                {
                    "name": bone.name,
                    "parent": bone.parent.name if bone.parent != None else None,
                    "rest_matrix": [list(row) for row in bone.matrix_local.inverted()], # Transform a point relative to the "Armature" node to the bone-space
                }
            )

        frame_start = bpy.context.scene.frame_start
        frame_end = bpy.context.scene.frame_end
        animation = []

        for frame in range(frame_start, frame_end + 1):
            bpy.context.scene.frame_set(frame)
            frame_data = {"frame": frame, "bones": []}

            for bone in armature.bones:
                pose_bone = object.pose.bones.get(bone.name)
                if pose_bone:
                    translation, rotation, scale = pose_bone.matrix.decompose() # Transform a point in bone space to "Armature" space
                    frame_data["bones"].append({
                        "position": [
                            translation.x,
                            translation.y,
                            translation.z,
                            0,
                        ],
                        "rotation": [
                            rotation.x,
                            rotation.y,
                            rotation.z,
                            rotation.w,
                        ],
                        "scale": [
                            scale.x,
                            scale.y,
                            scale.z,
                            0,
                        ],
                    })
            animation.append(frame_data)
        object_data["armature"] = {"bones": bones, "animation": animation}

    if object.type == "MESH":
        bpy.context.view_layer.objects.active = object

        # Only activate modifiers that are set to show in render (we are that render)
        modifiers_to_remove = [mod for mod in object.modifiers if not mod.show_render]
        for mod in modifiers_to_remove:
            object.modifiers.remove(mod)

        depsgraph = bpy.context.evaluated_depsgraph_get()
        object_eval = object.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(object_eval)

        polygons = []
        for polygon in mesh.polygons:
            polygonRes = []
            for index in polygon.vertices:
                polygonRes.append(index)
            polygons.append(polygonRes)

        bpy.context.scene.frame_set(bpy.context.scene.frame_start)

        depsgraph = bpy.context.evaluated_depsgraph_get()
        object_eval = object.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(object_eval)

        vertex_strings = []
        bone_indices = []
        for vertex in mesh.vertices:
            vertex_array = [vertex.co.x, vertex.co.z, vertex.co.y]
            vertex_string = ''.join(''.join(format(byte, '02x') for byte in struct.pack('<f', value)) for value in vertex_array)
            vertex_strings.append(vertex_string)

            # Find most heavily weighted bone
            max_weight = 0
            max_bone_index = -1
            for group in vertex.groups:
                weight = group.weight
                if weight > max_weight:
                    max_weight = weight
                    max_bone_index = group.group
            bone_indices.append(max_bone_index)

        object_data["mesh"] = {
            "polygons": polygons,
            "vertices": ''.join(vertex_strings),
            "bone_indices": bone_indices,
        }
    nodes.append(object_data)

with open(
    bpy.path.abspath("//")
    + os.path.basename(bpy.context.blend_data.filepath)
    + ".json",
    "w",
) as file:
    json.dump(
        {
            "framerate": bpy.context.scene.render.fps,
            "nodes": nodes,
        },
        file,
        # indent=4,
    )
print(
    "Export of "
    + bpy.path.abspath("//")
    + os.path.basename(bpy.context.blend_data.filepath)
    + ".json"
    + " complete"
)
