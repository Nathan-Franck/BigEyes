# Big Eyes

Can 3D toon graphics be easy?

### Objective

* Make a simple renderer and game loop to test out mesh generation techniques in zig
* Have fun!

### Building

Requires Zig 0.11
> Currently on zig version 0.12.0-dev.3381+7057bffc1

```
git submodule update 
zig build run
```

### Custom Blender Export

* Ensure your blender is in the path
```
blender triangle_wgpu_content/cube.blend --background --python .\tools\custom-gltf.py
```

### Blender View Script

* Load the camera_stream_addon.py as a module in Blender
* This allows the game scene to read the current blender camera state when previewing models in-engine! TODO - all kinds of state?

### Zig->Typescript Node Types
`zig run src/typeDefinitions.zig`
