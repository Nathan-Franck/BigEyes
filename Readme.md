# Big Eyes

Can 3D toon graphics be easy?

### Objective

* Make a simple renderer and game loop to test out mesh generation techniques in zig
* Have fun!

### Building

Requires Zig 0.14
> Currently on zig version 0.14.0-dev.105+f7d72ce88

```
zig build wasm
```

### Release Build

The game won't run fast unless you build the wasm bundle on ReleaseFast, though this takes much longer to build
```
zig build wasm -Doptimize=ReleaseFast
```

### Custom Blender Export

* Ensure your blender is in the path
** Flatpak version currently doesn't work
```
blender triangle_wgpu_content/cube.blend --background --python .\tools\custom-gltf.py
```
This is automatically executed from the build script!

### Zig->Typescript Node Types
`zig run src/tool_game_build_type_definitions.zig`

### Future Development Directions

- Cat animations!
- Forest rendering would be really nice to try out, just to satisfy my personal interests
  - Just go full 3D since that can look the coolest, with a dense forest
  - Use that cool algorithm that I already know about
- Orthographic rendering would be cool because I can optimize it pretty strongly for low-end hardware and power concious devices like phones
- Loading in 3D models with multiple textures (diffuse, normal, rough-spec) and having a basic display for those models with maybe some cubemap lighting
