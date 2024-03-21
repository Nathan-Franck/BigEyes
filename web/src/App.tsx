import { Show, createSignal, onMount } from 'solid-js'
import solidLogo from './assets/solid.svg'
import viteLogo from '/vite.svg'
import { declareStyle } from "./declareStyle"
import { testCallNode, callNode } from "./zigWasmInterface"

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
  }
});

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
  const [result, setResult] = createSignal(initial_result);
  return {
    graphResult: result,
    callGraph: (inputs: Parameters<typeof thinger>[0]) => {
      console.log("calling graph with", inputs);
      const result = thinger(inputs);
      console.log("result", result);
      setResult(result);
    },
  };
}

function App() {
  const [count, setCount] = createSignal(0)

  onMount(() => {
    console.log("App mounted")
  });
  console.log("App rendered")
  const { graphResult, callGraph } = getGraphSignal();
  const augh = graphResult();
  return (
    <>
      <Show when={"render_event" in augh} fallback={<div>error!</div>}>
        <Show when={augh.render_event.something_changed} fallback={<div>Nothing changed...</div>}>
          <div>something changed</div>
        </Show>
      </Show>
      {
        testCallNode().map(result => <div>{
          JSON.stringify(result)
        }</div>)
      }
      <style>{encodedStyle}</style>
      <div>
        <a href="https://vitejs.dev" target="_blank">
          <img src={viteLogo} class={classes.logo} alt="Vite logo" />
        </a>
        <a href="https://solidjs.com" target="_blank">
          <img src={solidLogo} class={`${classes.logo} ${classes.solidLogo}`} alt="Solid logo" />
        </a>
      </div>
      <h1>Vite + Solid</h1>
      <div class="card">
        <button onClick={() => callGraph({
          keyboard_modifiers: { shift: false, control: false, alt: false, super: false },
          recieved_blueprint: { output: [], store: [], nodes: [{ function: "what", input_links: [], name: "hey" }] },
        })}>
          count is {count()}
        </button>
        <p>
          Edit <code>src/App.tsx</code> and save to test HMR, sir
        </p>
      </div>
      <p class="read-the-docs">
        Click on the Vite and Solid logos to learn more
      </p>
    </>
  )
}

export default App
