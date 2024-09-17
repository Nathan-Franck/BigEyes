import "./app.css";
import { declareStyle } from "./declareStyle";
import { useEffect, useRef, useState } from "preact/hooks";
import { callWasm, sliceToArray, sliceToString } from "./zigWasmInterface";
import { Mat4, ShaderBuilder, Binds } from "./shaderBuilder";

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

// TODO - Get the error messages from the console showing up
// https://stackoverflow.com/questions/6604192/showing-console-errors-and-alerts-in-a-div-inside-the-page

type UpdateNodeGraph = typeof callWasm<"updateNodeGraph">;
type GraphOutputs = Exclude<ReturnType<UpdateNodeGraph>, { error: any }>["outputs"];
const graphInputs: Parameters<UpdateNodeGraph>[1] = {
  // game_time_ms: Date.now(),
  user_changes: {
    resolution_update: { x: window.innerWidth, y: window.innerHeight },
  },
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

export function App() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

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
        // game_time_ms: Date.now(),
        user_changes: {
          resolution_update: { x: window.innerWidth, y: window.innerHeight },
        },
      });
    };
    window.addEventListener("resize", resizeHandler);
    return () => {
      window.removeEventListener("resize", resizeHandler);
    };
  }, []);

  useEffect(() => {
    if (!canvasRef.current) return;
    const canvas = canvasRef.current;
    const gl = canvas.getContext("webgl2");
    if (!gl) return;

    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.enable(gl.DEPTH_TEST);

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
          // uv = vec2(0.5, 0.5);
          normal = normals;
        }
      `,
      fragSource: `
        precision highp float;
        void main(void) {
          if (texture2D(texture, uv).a > 0.65) {
            discard;
          }
          gl_FragColor = vec4(texture2D(texture, uv).rgb, 1);
        }
      `,
    });


    type Model =
      | { greybox: Omit<Binds<typeof greyboxMaterial.globals>, "perspectiveMatrix"> }
      | { textured: Omit<Binds<typeof texturedMeshMaterial.globals>, "perspectiveMatrix"> }
    let models: Record<string, Model> = {};
    let perspectiveMatrix: Mat4;

    updateRender = (graphOutputs) => () => {
      const worldMatrix = graphOutputs.world_matrix;
      if (worldMatrix) {
        perspectiveMatrix = worldMatrix.flat() as Mat4;
      }
      const meshes = graphOutputs.meshes;
      if (meshes != null) {
        for (let meshVariation of meshes) {
          if ("greybox" in meshVariation) {
            const mesh = meshVariation.greybox;
            const label = sliceToString(mesh.label);
            models[label] = {
              greybox: {
                indices: ShaderBuilder.createElementBuffer(
                  gl,
                  sliceToArray.Uint32Array(mesh.indices),
                ),
                position: ShaderBuilder.createBuffer(
                  gl,
                  sliceToArray.Float32Array(mesh.position),
                ),
                normals: ShaderBuilder.createBuffer(
                  gl,
                  sliceToArray.Float32Array(mesh.normal),
                ),
                item_position: ShaderBuilder.createBuffer(
                  gl,
                  new Float32Array([0, 0, 0, 1, 0, 1]),
                ),
              },
            };
          }
          else if ("textured" in meshVariation) {
            const mesh = meshVariation.textured;
            const label = sliceToString(mesh.label);
            const uvs = sliceToArray.Float32Array(mesh.uv);
            // uvs[0] = 1;
            models[label] = {
              textured: {
                indices: ShaderBuilder.createElementBuffer(
                  gl,
                  sliceToArray.Uint32Array(mesh.indices),
                ),
                position: ShaderBuilder.createBuffer(
                  gl,
                  sliceToArray.Float32Array(mesh.position),
                ),
                normals: ShaderBuilder.createBuffer(
                  gl,
                  sliceToArray.Float32Array(mesh.normal),
                ),
                uvs: ShaderBuilder.createBuffer(
                  gl,
                  uvs,
                ),
                item_position: ShaderBuilder.createBuffer(
                  gl,
                  new Float32Array([0, 0, 0, 1, 0, 1]),
                ),
                texture: ShaderBuilder.loadImageData(gl,
                  sliceToArray.Uint8Array(mesh.diffuse_alpha.data),
                  mesh.diffuse_alpha.width,
                  mesh.diffuse_alpha.height,
                ),
              },
            };
          }
        }
      }
      requestAnimationFrame(() => {
        {
          gl.viewport(0, 0, windowSize.width, windowSize.height);
          gl.clearColor(0, 0, 0, 1);
          gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        }

        for (const [_, model] of Object.entries(models)) {
          if ("greybox" in model) {
            ShaderBuilder.renderMaterial(gl, greyboxMaterial, { ...model.greybox, perspectiveMatrix });
          }
          if ("textured" in model) {
            ShaderBuilder.renderMaterial(gl, texturedMeshMaterial, { ...model.textured, perspectiveMatrix });
          }
        }
      });
    };

    updateGraph(graphInputs);

    let animationRunning = true;
    const intervalID = setInterval(() => {
      if (!animationRunning) clearInterval(intervalID);
      // if (document.hasFocus()) updateGraph({
      //   // game_time_ms: Date.now()
      // });
    }, 1000.0 / 24.0);

    return () => (animationRunning = false);
  }, []);

  return (
    <>
      <style>{encodedStyle}</style>
      <div
        style={{
          width: "100%",
          height: "100%",
          zIndex: 1,
          position: "absolute",
          left: 0,
          top: 0,
        }}
        onMouseMove={(event) => {
          const currentMouse = { x: event.clientX, y: event.clientY };
          const mouseDelta =
            lastMousePosition == null
              ? currentMouse
              : {
                x: currentMouse.x - lastMousePosition.x,
                y: currentMouse.y - lastMousePosition.y,
              };
          lastMousePosition = currentMouse;
          if (event.buttons) {
            updateGraph({
              input: { mouse_delta: [mouseDelta.x, mouseDelta.y, 0, 0] },
            });
          }
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
