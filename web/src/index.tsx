/* @refresh reload */
import { render } from 'solid-js/web'

import './index.css'
import App from './App'

const root = document.getElementById('root')

render(() => <><div>Hello World!</div><App/></>, root!)
