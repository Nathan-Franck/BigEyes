import { createSignal } from 'solid-js'
import solidLogo from './assets/solid.svg'
import viteLogo from '/vite.svg'

function declareStyle<const T extends Record<string, Partial<CSSStyleDeclaration>>>(style: T) {
  const classes = Object.keys(style) as (keyof T)[];
  const encodedStyle = classes.map((key) => {
    const value = style[key];
    return `.${key} {${Object.keys(value).map((key) => {
      const dashedKey = key.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`);
      return `${dashedKey}: ${value[key]};`
    }).join('')}}`
  }).join('');
  return { classes, encodedStyle };
}

const { classes, encodedStyle } = declareStyle({
  thing: {
    height: "6em",
    padding: "1.5em",
    willChange: "filter",
    transition: "filter 300ms",
  }
});

function App() {
  const [count, setCount] = createSignal(0)

  return (
    <>
      <style>{encodedStyle}</style>
      <div>
        <a href="https://vitejs.dev" target="_blank">
          <img src={viteLogo} class={classes.logo} alt="Vite logo" />
        </a>
        <a href="https://solidjs.com" target="_blank">
          <img src={solidLogo} class={`${classes.logo} ${classes.solid}`} alt="Solid logo" />
        </a>
      </div>
      <h1>Vite + Solid</h1>
      <div class="card">
        <button onClick={() => setCount((count) => count + 1)}>
          count is {count()}
        </button>
        <p>
          Edit <code>src/App.tsx</code> and save to test HMR
        </p>
      </div>
      <p class="read-the-docs">
        Click on the Vite and Solid logos to learn more
      </p>
    </>
  )
}

export default App
