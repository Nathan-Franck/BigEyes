/* @refresh reload */
import { render } from 'solid-js/web'

import './index.css'
import App from './App'

const root = document.getElementById('root')

// TODO: Figure out why this app isn't rendering - is it something wrong with my environment? Might have to test on the laptop...
render(() => <><App/></>, root!)
