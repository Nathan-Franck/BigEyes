# Big Eyes

Can 3D toon graphics be easy?

### Objective

* Make a simple renderer and game loop to test out mesh generation techniques in zig
* Have fun!

### Building

Requires Zig 0.11
```
git submodule update 
zig build run
```

### Custom Blender Export

* Ensure your blender is in the path
```
blender triangle_wgpu_content/cube.blend --background --python .\tools\custom-gltf.py
```