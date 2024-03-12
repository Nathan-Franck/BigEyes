import { createSignal } from 'solid-js'
import solidLogo from './assets/solid.svg'
import viteLogo from '/vite.svg'
import { declareStyle } from "./declareStyle"
import { testCallNode } from "./zigWasmInterface"

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

function App() {
  const [count, setCount] = createSignal(0)

  return (
    <>
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
        <button onClick={() => setCount((count) => count + 1)}>
          count is {count()}
        </button>
        <p>
          Edit <code>src/App.tsx</code> and save to test HMR, sir
        </p>
      </div>
      <p class="read-the-docs">
        Click on the Vite and Solid logos to learn more
        What's up cool cats 🐱
        Don't be a stranger 👹
      </p>
    </>
  )
}

export default App
