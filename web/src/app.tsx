import { useState } from 'preact/hooks'
import preactLogo from './assets/preact.svg'
import viteLogo from '/vite.svg'
import './app.css'
import { NodeGraph } from './nodeGraph';
import { declareStyle } from './declareStyle';

const { classes, encodedStyle } = declareStyle({
  solidLogo: {
    height: "6em",
    padding: "1.5em",
    willChange: "filter",
    transition: "filter 300ms",
  },
  logo: {
    filter: "grayscale(100%)",
    "&:hover": {
      filter: "grayscale(0%)",
    }
  },
  node: {
  },
  contextMenu: {
    display: "flex",
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

const nodeGraph = NodeGraph();

export function App() {
  const [count, setCount] = useState(0)
  const { graphResult, callGraph } = nodeGraph.useState();
  if ("error" in graphResult)
    return <div>Error: {graphResult.error}</div>

  const keyboard_modifiers = { alt: false, control: false, super: false, shift: false };

  return (
    <>
      <div>{encodedStyle}</div>
      <style>{encodedStyle}</style>
      <button onClick={() => callGraph({
        keyboard_modifiers,
        recieved_blueprint: {
          output: [],
          store: [],
          nodes: [
            { function: "what", input_links: [], name: "hey!" },
            { function: "what", input_links: [], name: "hey2!" },
          ]
        },
      })}> {
          <>{graphResult.blueprint.nodes.length}</>
        } </button>
      {
        graphResult.blueprint.nodes.map(node => <button class={classes.node} onClick={event => callGraph({
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
              node_name: node.name,
            }
          }
        })
        }>{node.name}</button>)
      }
      <div class={classes.contextMenu}>{
        graphResult.context_menu.open
          ? graphResult.context_menu.options.map((option, index) => <>
            {index > 0 ? <div class={classes.contextMenuSeperator} /> : null}
            <button class={classes.contextMenuItem} onClick={() => callGraph({
              keyboard_modifiers,
              event: {
                context_event: {
                  option_selected: option
                }
              }
            })}>{option}</button>
          </>
          )
          : null
      }</div>
      <div>{JSON.stringify(nodeGraph.getStore())}</div>
      <div>{JSON.stringify("event" in graphResult ? graphResult.event : null)}</div>
      <div>
        <a href="https://vitejs.dev" target="_blank">
          <img src={viteLogo} class="logo" alt="Vite logo" />
        </a>
        <a href="https://preactjs.com" target="_blank">
          <img src={preactLogo} class="logo preact" alt="Preact logo" />
        </a>
      </div>
      <h1>Vite + Preact</h1>
      <div class="card">
        <button onClick={() => setCount((count) => count + 1)}>
          count is {count}
        </button>
        <p>
          Edit <code>src/app.tsx</code> and save to test HMR
        </p>
      </div>
      <p class="read-the-docs">
        Click on the Vite and Preact logos to learn more
      </p>
    </>
  )
}
