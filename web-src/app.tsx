import "./app.css";
import { declareStyle } from "./declareStyle";
import { useEffect, useRef, useState } from "preact/hooks";
import { callWasm, sliceToArray, sliceToString } from "./zigWasmInterface";
import { Mat4, ShaderBuilder, Binds, SizedBuffer } from "./shaderBuilder";

const { classes, encodedStyle } = declareStyle({
  stats: {
    position: "absolute",
    top: "0px",
    left: "0px",
    color: "#fff",
    backgroundColor: "#000",
    padding: "5px",
    borderRadius: "5px",
  },
  nodeGraph: {},
  nodeGraphBackground: {
    backgroundColor: "#555",
    position: "absolute",
    top: "0px",
    left: "0px",
    width: "100%",
    height: "100vh",
    zIndex: "-1",
  },
  node: {},
  contextMenu: {
    display: "flex",
    position: "absolute",
    flexDirection: "column",
    width: "max-content",
    backgroundColor: "#333",
    borderRadius: "10px",
  },
  contextMenuSeperator: {
    height: "1px",
    margin: "5px",
    backgroundColor: "#0008",
  },
  contextMenuItem: {
    backgroundColor: "#0000",
  },
  canvas: {
    width: "100%",
    height: "100%",
    position: "absolute",
    left: 0,
    top: 0,
    zIndex: -1,
  },
});

function fromEntries<T extends [string, any]>(entries: T[]) {
  return Object.fromEntries(entries) as any as { [key in T[0]]: T[1] };
}

function toEntries<T extends Object>(object: T) {
  return Object.entries(object) as any as Array<[keyof T, T[keyof T]]>;
}

// TODO - Get the error messages from the console showing up
// https://stackoverflow.com/questions/6604192/showing-console-errors-and-alerts-in-a-div-inside-the-page

type UpdateNodeGraph = typeof callWasm<"updateNodeGraph">;
type GraphOutputs = Exclude<ReturnType<UpdateNodeGraph>, { error: any }>["outputs"];
const graphInputs: Parameters<UpdateNodeGraph>[1] = {
  render_resolution: { x: window.innerWidth, y: window.innerHeight },
};

callWasm("init");
let updateRender:
  | ((graphOutputs: GraphOutputs) => () => void)
  | null = null;


function updateGraph(newInputs: typeof graphInputs) {
  var graphInputs = newInputs;
  const graphResult = callWasm("updateNodeGraph", graphInputs);
  if ("error" in graphResult) return graphResult;
  if (updateRender != null) updateRender(graphResult.outputs)();
}

let lastMousePosition: { x: number; y: number } | null = null;
let controllerInputs: NonNullable<typeof graphInputs.input> = { mouse_delta: [0, 0, 0, 0], movement: { left: null, right: null, forward: null, backward: null } };

export function App() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const divRef = useRef<HTMLDivElement | null>(null);

  const [windowSize, setWindowSize] = useState({
    width: window.innerWidth,
    height: window.innerHeight,
  });

  const [
    stats,
    // setStats,
  ] = useState({
    // polygonCount: 0,
    framerate: 0,
  });

  useEffect(() => {
    const resizeHandler = () => {
      setWindowSize({
        width: canvasRef.current?.width || 0,
        height: canvasRef.current?.height || 0,
      });
      updateGraph({
        render_resolution: { x: window.innerWidth, y: window.innerHeight },
      });
    };
    window.addEventListener("resize", resizeHandler);
    return () => {
      window.removeEventListener("resize", resizeHandler);
    };
  }, []);

  useEffect(() => {
    // Focus the div when component mounts
    divRef.current?.focus();
  }, []);

  useEffect(() => {
    if (!canvasRef.current) return;
    const canvas = canvasRef.current;
    const gl = canvas.getContext("webgl2");
    if (!gl) return;

    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.enable(gl.DEPTH_TEST);

    const skyboxMaterial = ShaderBuilder.generateMaterial(gl, {
      mode: "TRIANGLES",
      globals: {
        indices: { type: "element" },
        uv: { type: "attribute", unit: "vec2" },
        normals: { type: "attribute", unit: "vec3" },
        normal: { type: "varying", unit: "vec3" },
        skybox: { type: "uniform", unit: "samplerCube", count: 1 },
      },
      vertSource: `
        precision highp float;
        void main(void) {
          gl_Position = vec4(vec2(-1, -1) + vec2(2, 2) * uv, 0, 1);
          normal = normals;
        }
      `,
      fragSource: `
        precision highp float;
        void main(void) {
          gl_FragColor = textureCube(skybox, normalize(normal));
        }
      `,
    });

    const greyboxMaterial = ShaderBuilder.generateMaterial(gl, {
      mode: "TRIANGLES",
      globals: {
        indices: { type: "element" },
        position: { type: "attribute", unit: "vec3" },
        normals: { type: "attribute", unit: "vec3" },
        uv: { type: "varying", unit: "vec2" },
        normal: { type: "varying", unit: "vec3" },
        perspectiveMatrix: { type: "uniform", unit: "mat4", count: 1 },
        item_position: { type: "attribute", unit: "vec3", instanced: true },
      },
      vertSource: `
        precision highp float;
        void main(void) {
          gl_Position = perspectiveMatrix * vec4(item_position + position, 1);
          normal = normals;
        }
      `,
      fragSource: `
        precision highp float;
        void main(void) {
          float brightness = clamp(dot(normal, normalize(vec3(1, 1, 1))), 0.0, 1.0);
          gl_FragColor = vec4(vec3(0.8, 0.8, 0.8) * mix(0.5, 1.0, brightness), 1);
        }
      `,
    });

    const texturedMeshMaterial = ShaderBuilder.generateMaterial(gl, {
      mode: "TRIANGLES",
      globals: {
        indices: { type: "element" },
        position: { type: "attribute", unit: "vec3" },
        normals: { type: "attribute", unit: "vec3" },
        uvs: { type: "attribute", unit: "vec2" },
        uv: { type: "varying", unit: "vec2" },
        normal: { type: "varying", unit: "vec3" },
        texture: { type: "uniform", unit: "sampler2D", count: 1 },
        perspectiveMatrix: { type: "uniform", unit: "mat4", count: 1 },
        item_position: { type: "attribute", unit: "vec3", instanced: true },
      },
      vertSource: `
        precision highp float;
        void main(void) {
          gl_Position = perspectiveMatrix * vec4(item_position + position, 1);
          uv = uvs;
          normal = normals;
        }
      `,
      fragSource: `
        precision highp float;
        void main(void) {
          if (texture2D(texture, uv).a > 0.65) {
            discard;
          }
          float brightness = abs(dot(normal, normalize(vec3(1, 1, 1))));
          gl_FragColor = vec4(texture2D(texture, uv).rgb * brightness, 1);
        }
      `,
    });


    type Model =
      | { greybox: Omit<Binds<typeof greyboxMaterial.globals>, "perspectiveMatrix" | "item_position"> }
      | { textured: Omit<Binds<typeof texturedMeshMaterial.globals>, "perspectiveMatrix" | "item_position"> }
    let models: Record<string, Model[]> = {};
    let perspectiveMatrix: Mat4;
    let item_positions: Record<string, SizedBuffer> = {};
    let skybox: Binds<typeof skyboxMaterial.globals>;

    updateRender = (graphOutputs) => () => {
      const worldMatrix = graphOutputs.world_matrix;
      if (worldMatrix) {
        perspectiveMatrix = worldMatrix.flat() as Mat4;
      }
      const skybox_data = graphOutputs.skybox;
      if (skybox_data) {
        var texture_data = fromEntries(toEntries(skybox_data).map(([key, value]) => [
          key,
          sliceToArray.Uint8Array(value.data),
        ] as const))
        skybox = {
          ...skybox,
          skybox: ShaderBuilder.loadCubemapData(gl, texture_data, skybox_data.nx.width, skybox_data.nx.height),
        };
      }
      const screenspace_data = graphOutputs.screen_space_mesh;
      if (screenspace_data) {
        skybox = {
          ...skybox,
          indices: ShaderBuilder.createElementBuffer(gl, sliceToArray.Uint32Array(screenspace_data.indices)),
          uv: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(screenspace_data.uvs)),
          normals: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(screenspace_data.normals)),
        };
      }
      const forest_data = graphOutputs.forest_data;
      if (forest_data) {
        for (let data of forest_data) {
          const label = sliceToString(data.label);
          item_positions[label] = ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(data.positions));
        }
      }
      const terrain_instance = graphOutputs.terrain_instance;
      if (terrain_instance) {
        const label = sliceToString(terrain_instance.label);
        item_positions[label] = ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(terrain_instance.positions));
      }
      const terrain_mesh = graphOutputs.terrain_mesh;
      if (terrain_mesh) {
        console.log(terrain_mesh.indices.len);
        models["terrain"] = [
          {
            greybox: {
              indices: ShaderBuilder.createElementBuffer(gl, sliceToArray.Uint32Array(terrain_mesh.indices)),
              normals: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(terrain_mesh.normal)),
              position: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(terrain_mesh.position)),
            },
          },
        ];
      }
      if (graphOutputs.models != null) {
        for (let model of graphOutputs.models) {
          const label = sliceToString(model.label);
          const meshes: Model[] = [];
          models[label] = meshes;

          for (let meshVariation of model.meshes) {
            if ("greybox" in meshVariation) {
              const mesh = meshVariation.greybox;
              meshes.push({
                greybox: {
                  indices: ShaderBuilder.createElementBuffer(gl, sliceToArray.Uint32Array(mesh.indices)),
                  position: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(mesh.position)),
                  normals: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(mesh.normal)),
                },
              });
            }
            else if ("textured" in meshVariation) {
              const mesh = meshVariation.textured;
              const uvs = sliceToArray.Float32Array(mesh.uv);
              meshes.push({
                textured: {
                  indices: ShaderBuilder.createElementBuffer(gl, sliceToArray.Uint32Array(mesh.indices)),
                  position: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(mesh.position)),
                  normals: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(mesh.normal)),
                  uvs: ShaderBuilder.createBuffer(gl, uvs),
                  texture: ShaderBuilder.loadImageData(gl,
                    sliceToArray.Uint8Array(mesh.diffuse_alpha.data),
                    mesh.diffuse_alpha.width,
                    mesh.diffuse_alpha.height,
                  ),
                },
              });
            }
          }
        }
      }
      requestAnimationFrame(() => {
        {
          gl.viewport(0, 0, windowSize.width, windowSize.height);
          gl.clearColor(0, 0, 0, 1);
          gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        }

        gl.depthMask(false);
        ShaderBuilder.renderMaterial(gl, skyboxMaterial, skybox);
        gl.depthMask(true);

        for (const [key, model] of Object.entries(models)) {
          const item_position = item_positions[key];
          for (const mesh of model) {
            if ("greybox" in mesh) {
              ShaderBuilder.renderMaterial(gl, greyboxMaterial, { ...mesh.greybox, item_position, perspectiveMatrix });
            }
            if ("textured" in mesh) {
              ShaderBuilder.renderMaterial(gl, texturedMeshMaterial, { ...mesh.textured, item_position, perspectiveMatrix });
            }
          }
        }
      });
    };

    updateGraph(graphInputs);

    let animationRunning = true;
    const update = () => {
      if (document.hasFocus()) {
        updateGraph({
          input: controllerInputs,
          time: Date.now()
        });
        controllerInputs.mouse_delta = [0, 0, 0, 0];
      }
      if (animationRunning) requestAnimationFrame(update);
    }
    requestAnimationFrame(update);

    return () => (animationRunning = false);
  }, []);

  const keyToDirection = {
    "w": "forward",
    "s": "backward",
    "a": "left",
    "d": "right",
  } as const;

  return (
    <>
      <style>{encodedStyle}</style>
      <div
        tabIndex={0}
        style={{
          width: "100%",
          height: "100%",
          zIndex: 1,
          position: "absolute",
          left: 0,
          top: 0,
          outline: 'none',
        }}
        onMouseDown={(event) => {
          console.log(event.button);
          if (event.button == 1) {
            updateGraph({
              selected_camera: "orbit",
            });
            event.preventDefault();
          } else if (event.button == 2) {
            updateGraph({
              selected_camera: "first_person",
            });
            event.preventDefault();
          }
        }}
        onKeyDown={(event) => {
          const direction = keyToDirection[event.key as keyof typeof keyToDirection];
          if (direction != null) {
            controllerInputs.mouse_delta = [0, 0, 0, 0];
            controllerInputs.movement[direction] = Date.now();
          }
        }}
        onKeyUp={(event) => {
          const direction = keyToDirection[event.key as keyof typeof keyToDirection];
          if (direction != null) {
            controllerInputs.mouse_delta = [0, 0, 0, 0];
            controllerInputs.movement[direction] = null;
          }
        }}
        onMouseMove={(event) => {
          const currentMouse = { x: event.clientX, y: event.clientY };
          if (event.buttons) {
            const mouseDelta =
              lastMousePosition == null
                ? currentMouse
                : {
                  x: currentMouse.x - lastMousePosition.x,
                  y: currentMouse.y - lastMousePosition.y,
                };
            controllerInputs.mouse_delta = [mouseDelta.x, mouseDelta.y, 0, 0];
          }
          lastMousePosition = currentMouse;
        }}
      >
        <div class={classes.stats}>
          <div>frame_rate - {"" + Math.round(stats.framerate)}</div>
        </div>
      </div>
      <canvas
        ref={canvasRef}
        class={classes.canvas}
        id="canvas"
        width={windowSize.width}
        height={windowSize.height}
      ></canvas>
    </>
  );
}
