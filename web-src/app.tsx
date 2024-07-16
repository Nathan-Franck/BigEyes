import "./app.css";
import { NodeGraph, GraphOutputs } from "./nodeGraph";
import { declareStyle } from "./declareStyle";
import { useEffect, useRef, useState } from "preact/hooks";
import { sliceToArray } from "./zigWasmInterface";
import { Mat4, ShaderBuilder } from "./shaderBuilder";

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

let graphInputs: Parameters<(typeof nodeGraph)["call"]>[0] = {
  game_time_ms: 0,
  user_changes: {
    resolution_update: { x: window.innerWidth, y: window.innerHeight },
  },
};
let updateRender:
  | ((graphOutputs: NonNullable<GraphOutputs>) => () => void)
  | null = null;

function updateGraph(newInputs: typeof graphInputs) {
  graphInputs = newInputs;
  const graphOutputs = nodeGraph.call(graphInputs);
  if (graphOutputs == null || "error" in graphOutputs) return;
  if (updateRender != null) updateRender(graphOutputs)();
}

const nodeGraph = NodeGraph(graphInputs);
let lastMousePosition: { x: number; y: number } | null = null;

export function App() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  const [windowSize, setWindowSize] = useState({
    width: window.innerWidth,
    height: window.innerHeight,
  });

  const [subdivLevel, setSubdivLevel] = useState(1);
  const [stats, setStats] = useState({ polygonCount: 0, framerate: 0 });

  useEffect(() => {
    const resizeHandler = () => {
      setWindowSize({
        width: canvasRef.current?.width || 0,
        height: canvasRef.current?.height || 0,
      });
      updateGraph({
        game_time_ms: Date.now(),
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
    const gl = canvas.getContext("webgl2", { antialias: false });
    if (!gl) return;

    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    gl.enable(gl.DEPTH_TEST);

    const catMeshMaterial = ShaderBuilder.generateMaterial(gl, {
      mode: "TRIANGLES",
      globals: {
        indices: { type: "element" },
        position: { type: "attribute", unit: "vec3" },
        normals: { type: "attribute", unit: "vec3" },
        normal: { type: "varying", unit: "vec3" },
        item_position: { type: "attribute", unit: "vec3", instanced: true },
        perspectiveMatrix: { type: "uniform", unit: "mat4", count: 1 },
        // out_diffuse: { type: "output", unit: "vec4" },
        // out_normal: { type: "output", unit: "vec4" },
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
          // gl_FragColor = vec4(normal * 0.5 + 0.5, 1);
          // Super simple lighting from the sun at a diagonal
          vec3 lightDir = normalize(vec3(1, 1, 1));
          float lightIntensity = max(dot(normal, lightDir), 0.0);
          gl_FragColor = vec4(vec3(0.5, 0.5, 0.5) + lightIntensity, 1);
        }
      `,
    });

    updateRender = (graphOutputs) => () => {
      const buffers: ShaderBuilder.MaterialBinds<typeof catMeshMaterial> = {
        indices: ShaderBuilder.createElementBuffer(
          gl,
          sliceToArray.Uint32Array(graphOutputs.current_cat_mesh.indices),
        ),
        position: ShaderBuilder.createBuffer(
          gl,
          sliceToArray.Float32Array(graphOutputs.current_cat_mesh.position),
        ),
        normals: ShaderBuilder.createBuffer(
          gl,
          sliceToArray.Float32Array(graphOutputs.current_cat_mesh.normal),
        ),
        item_position: ShaderBuilder.createBuffer(
          gl,
          new Float32Array([0, 0, 0]),
        ),
        perspectiveMatrix: graphOutputs.world_matrix.flatMap(
          (row) => row,
        ) as Mat4,
        // outputs: ShaderBuilder.createMRTFrameBuffer(
        //   gl,
        //   windowSize.width,
        //   windowSize.height,
        //   true,
        //   { out_diffuse: "vec4", out_normal: "vec4" },
        // ),
      };
      requestAnimationFrame(() => {
        setStats({
          polygonCount: buffers.indices.length / 3,
          framerate: 1000.0 / (Date.now() - graphInputs.game_time_ms),
        });
        {
          gl.viewport(0, 0, windowSize.width, windowSize.height);
          gl.clearColor(0, 0, 0, 1);
          gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        }

        ShaderBuilder.renderMaterial(gl, catMeshMaterial, buffers);
      });
    };

    updateGraph({ game_time_ms: Date.now() });

    let animationRunning = true;
    const intervalID = setInterval(() => {
      if (!animationRunning) clearInterval(intervalID);
      if (document.hasFocus()) updateGraph({ game_time_ms: Date.now() });
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
              game_time_ms: Date.now(),
              input: { mouse_delta: [mouseDelta.x, mouseDelta.y, 0, 0] },
            });
          }
        }}
      >
        // Select a subdivision detail between 0-3
        <input
          type="range"
          min="0"
          max="3"
          value={subdivLevel}
          onChange={(event) => {
            setSubdivLevel(parseInt(event.target!.value));
            updateGraph({
              game_time_ms: Date.now(),
              user_changes: {
                subdiv_level_update: parseInt(event.target!.value),
              },
            });
          }}
        ></input>
        <div class={classes.stats}>
          <div>subdiv_level - {subdivLevel}</div>
          <div>polygon_count - {stats.polygonCount}</div>
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
