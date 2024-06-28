import './app.css'
import { NodeGraph, GraphOutputs } from './nodeGraph';
import { declareStyle } from './declareStyle';
import { useEffect, useRef, useState } from 'preact/hooks'
import { sliceToArray, callWasm } from './zigWasmInterface';
import { Mat4, ShaderBuilder } from './shaderBuilder';

const { classes, encodedStyle } = declareStyle({
  nodeGraph: {
  },
  nodeGraphBackground: {
    backgroundColor: "#555",
    position: "absolute",
    top: "0px",
    left: "0px",
    width: "100%",
    height: "100vh",
    zIndex: "-1",
  },
  node: {
  },
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

const resources = callWasm("getResources");

// TODO - Get the error messages from the console showing up
// https://stackoverflow.com/questions/6604192/showing-console-errors-and-alerts-in-a-div-inside-the-page

let graphInputs: Parameters<typeof nodeGraph["call"]>[0] = { user_changes: { resolution_update: { x: window.innerWidth, y: window.innerHeight } } };
let updateRender: ((graphOutputs: NonNullable<GraphOutputs>) => () => void) | null = null

function updateGraph(newInputs: typeof graphInputs) {
  graphInputs = newInputs;
  const graphOutputs = nodeGraph.call(graphInputs);
  if (graphOutputs == null || "error" in graphOutputs)
    return;
  if (updateRender != null)
    requestAnimationFrame(updateRender(graphOutputs));
}

const nodeGraph = NodeGraph(graphInputs);
let lastMousePosition: { x: number, y: number } | null = null;

export function App() {

  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  const [windowSize, setWindowSize] = useState({ width: window.innerWidth, height: window.innerHeight });

  useEffect(() => {
    const resizeHandler = () => {
      setWindowSize({ width: canvasRef.current?.width || 0, height: canvasRef.current?.height || 0 });
      updateGraph({ user_changes: { resolution_update: { x: window.innerWidth, y: window.innerHeight } } });
    };
    window.addEventListener('resize', resizeHandler);
    return () => {
      window.removeEventListener('resize', resizeHandler);
    };
  }, []);

  useEffect(() => {
    if (!canvasRef.current)
      return;
    const canvas = canvasRef.current;
    const gl = canvas.getContext('webgl2');
    if (!gl)
      return;
    if ("error" in resources)
      return;
    const coolMesh = ShaderBuilder.generateMaterial(gl, {
      mode: 'TRIANGLES',
      globals: {
        indices: { type: "element" },
        position: { type: "attribute", unit: "vec3" },
        normals: { type: "attribute", unit: "vec3" },
        normal: { type: "varying", unit: "vec3" },
        item_position: { type: "attribute", unit: "vec3", instanced: true },
        perspectiveMatrix: { type: "uniform", unit: "mat4", count: 1 },
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
          gl_FragColor = vec4(normal * 0.5 + 0.5, 1);
        }
      `,
    });

    updateRender = (graphOutputs) => () => {
      {
        gl.clearColor(0, 0, 0, 1);
        gl.clear(gl.COLOR_BUFFER_BIT);
        gl.viewport(0, 0, windowSize.width, windowSize.height);
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        gl.enable(gl.DEPTH_TEST);
        // gl.disable(gl.CULL_FACE);
      }

      ShaderBuilder.renderMaterial(gl, coolMesh, {
        indices: ShaderBuilder.createElementBuffer(gl, sliceToArray.Uint32Array(resources.meshes[0].indices)),
        position: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(resources.meshes[0].position)),
        normals: ShaderBuilder.createBuffer(gl, sliceToArray.Float32Array(resources.meshes[0].normals)),
        item_position: ShaderBuilder.createBuffer(gl, new Float32Array([0, 0, 0])),
        perspectiveMatrix: graphOutputs.world_matrix.flatMap(row => row) as Mat4,
      });
    }

    updateGraph({ game_time_seconds: 0 });
  }, []);


  return (<>
    <style>{encodedStyle}</style >
    <div
      style={{ width: "100%", height: "100%", zIndex: 1, position: "absolute", left: 0, top: 0 }}
      onMouseMove={event => {
        const currentMouse = { x: event.clientX, y: event.clientY };
        const mouseDelta = lastMousePosition == null
          ? currentMouse
          : { x: currentMouse.x - lastMousePosition.x, y: currentMouse.y - lastMousePosition.y }
        lastMousePosition = currentMouse;
        if (event.buttons)
          updateGraph({
            game_time_seconds: Date.now() / 1000,
            input: { mouse_delta: [mouseDelta.x, mouseDelta.y, 0, 0] },
          });
      }}></div>
    <canvas ref={canvasRef} class={classes.canvas} id="canvas" width={windowSize.width} height={windowSize.height}></canvas>
  </>)
}
