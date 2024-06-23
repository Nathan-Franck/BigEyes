import './app.css'
import { NodeGraph } from './nodeGraph';
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

const startLoadResources = Date.now();
const resources = callWasm("getResources");
const resourcesLoadTime = Date.now() - startLoadResources;

// TODO - Get the error messages from the console showing up
// https://stackoverflow.com/questions/6604192/showing-console-errors-and-alerts-in-a-div-inside-the-page

const keyboard_modifiers = { alt: false, control: false, super: false, shift: false };

const nodeGraph = NodeGraph({
  game_time_seconds: 0,
  input: { mouse_delta: [0, 0, 0, 0] },
  orbit_speed: 1,
},);


export function App() {
  const { graphOutputs, callGraph } = nodeGraph.useState();

  if ("error" in graphOutputs)
    return <div>Error: {graphOutputs.error}</div>

  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  // useEffect(() => {
  //   callGraph({
  //     keyboard_modifiers,
  //     post_render_event: {
  //       node_dimensions: Object.entries(nodeReferences.current)
  //         .map(([node, button]) => ({
  //           node, data: {
  //             width: button.clientWidth,
  //             height: button.clientHeight,
  //           }
  //         }))
  //     }
  //   });
  // });

  const rerenderCount = useRef(0);
  rerenderCount.current += 1;

  const contextMenuRef = useRef<HTMLDivElement>(null);
  const contextMenuOpen = useRef(false);
  useEffect(() => {
    // When first opening the menu, we should focus the first button so it's easy to keyboard-first this context menu.
    if (!contextMenuRef.current) {
      contextMenuOpen.current = false;
    }
    else {
      if (!contextMenuOpen.current) {
        contextMenuRef.current.querySelector("button")?.focus();
        contextMenuOpen.current = true;
      }
    }
  });

  const [windowSize, setWindowSize] = useState({ width: window.innerWidth, height: window.innerHeight });

  useEffect(() => {
    const resizeHandler = () => {
      setWindowSize({ width: window.innerWidth, height: window.innerHeight });
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
  });

  // Given the refs to all the nodes, we can move these around based on the nodeGraph data 
  {
    // const positions = graphOutputs.node_coords;
    // for(const { node, data: position } of positions) {
    //   const button = nodeReferences.current[sliceToString(node)];
    //   if (button && "innerHTML" in button) {
    //     button.style.position = "absolute";
    //     button.style.left = `${position.x}px`;
    //     button.style.top = `${position.y}px`;
    //   }
    // }
  }

  console.log("Trying to make a canvas that I can click!")

  return (
    <>
      <style>{encodedStyle}</style>
      <div style={{ width: "100%", height: "100%", zIndex: 1, position: "absolute", left: 0, top: 0 }} onMouseMove={event =>{
        console.log(`Recieved event - ${JSON.stringify(event.type)}`);
        callGraph({
          game_time_seconds: Date.now() / 1000,
          input: { mouse_delta: [event.clientX, event.clientY, 0, 0]},
          orbit_speed: 0.00001,
        })
      }}></div>
      <canvas ref={canvasRef} class={classes.canvas} id="canvas" width={windowSize.width} height={windowSize.height} onMouseEnter={event =>
        console.log("HI")}>canvas</canvas>
    </>
  )
}
