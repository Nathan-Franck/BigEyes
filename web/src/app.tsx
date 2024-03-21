import { useState } from 'preact/hooks'
import preactLogo from './assets/preact.svg'
import viteLogo from '/vite.svg'
import './app.css'
import { callNode } from './zigWasmInterface';

// const { classes, encodedStyle } = declareStyle({
//   solidLogo: {
//     height: "6em",
//     padding: "1.5em",
//     willChange: "filter",
//     transition: "filter 300ms",
//   },
//   logo: {
//     filter: "grayscale(100%)",
//     "&:hover": {
//       filter: "grayscale(0%)",
//     }
//   }
// });

function thinger(inputs: Parameters<typeof callNode<"testNodeGraph">>[1]) {
  const result = callNode("testNodeGraph", inputs, store);
  if ("error" in result) {
    return result;
  }
  store = result.store;
  return result.outputs;
}

var store: Extract<ReturnType<typeof callNode<"testNodeGraph">>, { store: any }>["store"] = {
  blueprint: { nodes: [], output: [], store: [] },
  interaction_state: {
    node_selection: [],
  },
  camera: {},
  context_menu: {
    open: false,
    location: { x: 0, y: 0 },
    options: [],
  }
};

const initial_result = thinger({
  keyboard_modifiers: { shift: false, control: false, alt: false, super: false },
});

function getGraphSignal() {
  const [result, setResult] = useState(initial_result);
  return {
    graphResult: result,
    callGraph: (inputs: Parameters<typeof thinger>[0]) => {
      const result = thinger(inputs);
      setResult(result);
    },
  };
}

export function App() {
  const [count, setCount] = useState(0)
  const { graphResult, callGraph } = getGraphSignal();

  return (
    <>
      <button onClick={() => callGraph({
        keyboard_modifiers: { shift: false, control: false, alt: false, super: false },
        recieved_blueprint: { output: [], store: [], nodes: [{ function: "what", input_links: [], name: "hey" }] },
      })}>
        {"error" in graphResult ? <>{graphResult.error}</> : <>{graphResult.render_event?.something_changed ? "Something Changed!" : "Nothing Changed"}</> }
      </button>
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
