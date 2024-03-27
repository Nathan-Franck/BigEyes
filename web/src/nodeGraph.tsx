import { useState } from 'preact/hooks';
import { callWasm } from './zigWasmInterface';

export function NodeGraph() {

  const interfaceFunctionName = "callNodeGraph" as const;
  type InterfaceFunction = typeof callWasm<typeof interfaceFunctionName>;

  var store: Extract<ReturnType<InterfaceFunction>, { store: any; }>["store"] = {
    blueprint: { nodes: [], output: [], store: [] },
    node_dimensions: [],
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

  const initial_outputs: NonNullable<Extract<ReturnType<InterfaceFunction>, { outputs: any; }>["outputs"]> | { error: string } = call({
    keyboard_modifiers: { shift: false, control: false, alt: false, super: false },
  })!;

  function call(inputs: Parameters<InterfaceFunction>[1]) {
    const result = callWasm(interfaceFunctionName, inputs, store);
    if ("error" in result) {
      return result;
    }
    store = result.store;
    return result.outputs;
  }

  return {
    getStore: () => store,
    useState: () => {
      const [outputs, setOutputs] = useState(initial_outputs);
      return {
        graphOutputs: outputs,
        callGraph: (inputs: Parameters<typeof call>[0]) => {
          const result = call(inputs);
          if (result != null)
            setOutputs(result);
        },
      };
    }
  };
}
