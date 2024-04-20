import './app.css'
import { NodeGraph } from './nodeGraph';
import { declareStyle } from './declareStyle';
import { useEffect, useRef } from 'preact/hooks'
import { sliceToArray, sliceToString, callWasm } from './zigWasmInterface';

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
});

// TODO - Get the error messages from the console showing up
// https://stackoverflow.com/questions/6604192/showing-console-errors-and-alerts-in-a-div-inside-the-page

const keyboard_modifiers = { alt: false, control: false, super: false, shift: false };
const nodeGraph = NodeGraph({
  keyboard_modifiers,
  recieved_blueprint: {
    nodes: [
      { function: "test", input_links: [], name: "TestA" },
      { function: "test", input_links: [], name: "TestB" },
    ],
    output: [],
    store: [],
  },
},);

const allResources = callWasm("getAllResources") as Exclude<ReturnType<typeof callWasm<"getAllResources">>, { "error": any }>;


export function App() {
  const { graphOutputs, callGraph } = nodeGraph.useState();
  if ("error" in graphOutputs)
    return <div>Error: {graphOutputs.error}</div>

  const nodeReferences = useRef<Record<string, HTMLButtonElement>>({});

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

  // Given the refs to all the nodes, we can move these around based on the nodeGraph data 
  {
    const positions = graphOutputs.node_coords;
    for (const { node, data: position } of positions) {
      const button = nodeReferences.current[sliceToString(node)];
      if (button && "innerHTML" in button) {
        button.style.position = "absolute";
        button.style.left = `${position.x}px`;
        button.style.top = `${position.y}px`;
      }
    }
  }

  const lastTargetRef = useRef<HTMLElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  // Display image on canvas
  useEffect(() => {
    if (canvasRef.current) {
      const canvas = canvasRef.current;
      const ctx = canvas.getContext('2d');
      if (ctx) {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        const { data, width, height } = allResources.smile_test;
        const clampedData = sliceToArray.Uint8ClampedArray(data);
        const imageData = new ImageData(clampedData, width, height);
        ctx.putImageData(imageData, -306, -306, 306, 306, 296, 296);
      }
    }
  });

  return (
    <>
      <style>{encodedStyle}</style>
      <div class={classes.nodeGraphBackground} onClick={event => {
        lastTargetRef.current = event.target as HTMLElement;
        const clickPosition = {
          x: event.clientX,
          y: event.clientY,
        };
        callGraph({
          keyboard_modifiers, event: {
            mouse_event: {
              mouse_down: {
                button: event.button == 0
                  ? "right" /**temp for touch testing **/
                  : event.button == 1 ? "middle" : "right",
                location: clickPosition,
              }
            }
          }
        });
      }}></div>
      <div class={classes.nodeGraph} >
        {
          graphOutputs.context_menu.open
            ? <div class={classes.contextMenu} ref={contextMenuRef}>{
              graphOutputs.context_menu.options.map((option, index) => <>
                {index > 0 ? <div class={classes.contextMenuSeperator} /> : null}
                < button class={classes.contextMenuItem} onClick={() => callGraph({
                  keyboard_modifiers,
                  event: {
                    context_event: {
                      option_selected: sliceToString(option)
                    }
                  }
                })}>{sliceToString(option)}</button>
              </>)
            }</div>
            : null
        }
        {
          graphOutputs.blueprint.nodes.map(node => <button
            ref={elem => {
              if (elem != null)
                nodeReferences.current[sliceToString(node.name)] = elem
            }}
            class={classes.node}
            onClick={event => callGraph({
              keyboard_modifiers,
              event: {
                external_node_event: {
                  mouse_event: {
                    mouse_down: {
                      button: event.button == 0
                        ? "right" /**temp for touch testing **/
                        : event.button == 1
                          ? "middle"
                          : "right",
                      location: { x: event.x, y: event.y }
                    },
                  },
                  node_name: sliceToString(node.name),
                }
              }
            })
            }>{sliceToString(node.name)}</button>)
        }
      </div>
      <canvas ref={canvasRef} id="canvas" width="1000" height="1000"></canvas>
    </>
  )
}
