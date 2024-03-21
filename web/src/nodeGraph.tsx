import { useState } from 'preact/hooks';
import { callNode } from './zigWasmInterface';

export function NodeGraph() {

  var store: Extract<ReturnType<typeof callNode<"testNodeGraph">>, { store: any; }>["store"] = {
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

  const initial_result = call({
    keyboard_modifiers: { shift: false, control: false, alt: false, super: false },
  });

  function call(inputs: Parameters<typeof callNode<"testNodeGraph">>[1]) {
    const result = callNode("testNodeGraph", inputs, store);
    if ("error" in result) {
      return result;
    }
    store = result.store;
    return result.outputs;
  }

  return {
    useState: () => {
      const [result, setResult] = useState(initial_result);
      return {
        graphResult: result,
        callGraph: (inputs: Parameters<typeof call>[0]) => {
          const result = call(inputs);
          setResult(result);
        },
      };
    }
  };
}
