import { useState } from 'preact/hooks'
import preactLogo from './assets/preact.svg'
import viteLogo from '/vite.svg'
import './app.css'
import { NodeGraph } from './nodeGraph';

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

const nodeGraph = NodeGraph();

export function App() {
  const [count, setCount] = useState(0)
  const { graphResult, callGraph } = nodeGraph.useState();

  return (
    <>
      <button onClick={() => callGraph({
        keyboard_modifiers: { shift: false, control: false, alt: false, super: false },
        recieved_blueprint: { output: [], store: [], nodes: [{ function: "what", input_links: [], name: "hey" }] },
      })}>
        {"error" in graphResult ? <>{graphResult.error}</> : <>{graphResult.render_event?.something_changed ? "Something Changed!" : "Nothing Changed"}</>}
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