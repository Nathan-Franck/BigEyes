import { render } from 'preact'
// import { App } from './app.tsx'
import {Flow} from './node_graph_editor.tsx'
import './index.css'
// import ImageProcessingWorkflow from './image-process.tsx'

// render(<App />, document.getElementById('app')!)
render(<Flow />, document.getElementById('app')!)
// render(<ImageProcessingWorkflow />, document.getElementById('app')!);
