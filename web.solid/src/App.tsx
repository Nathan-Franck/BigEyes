import { createSignal } from 'solid-js'
import solidLogo from './assets/solid.svg'
import viteLogo from '/vite.svg'

function declareStyle<const T extends Record<string, Partial<CSSStyleDeclaration>>>(style: T) {
  // Build lookup of class names to class name as a string.
const classList: (keyof T)[] = Object.keys(style).reduce((acc, key) => {
  const keys = key.split('.');
  return [...acc, ...keys];
}, [] as any);
  const classes: { [key in keyof T]: key } = classList.reduce((acc, key) => {
    acc[key as string] = key;
    return acc;
  }, {} as any);
  const encodedStyle = classList.map((key) => {
    const value = style[key];
    return `.${key as string} {${Object.keys(value).map((key) => {
      const dashedKey = key.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`);
      return `${dashedKey}: ${value[key as any]};`
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
  },
  "logo": {
    filter: "grayscale(100%)",
    // "&:hover": {
    //   filter: "grayscale(0%)",
    // }
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
          <img src={solidLogo} class={`${classes.logo} ${classes.thing}`} alt="Solid logo" />
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
