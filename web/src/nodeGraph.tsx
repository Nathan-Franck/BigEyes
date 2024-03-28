import { useState } from 'preact/hooks';
import { callWasm } from './zigWasmInterface';

type InterfaceFunction = typeof callWasm<typeof interfaceFunctionName>;
const interfaceFunctionName = "callNodeGraph" as const;
type Inputs = Parameters<InterfaceFunction>[1];
type Store = Parameters<InterfaceFunction>[2];
type Outputs = (ReturnType<InterfaceFunction> & { outputs: any })["outputs"]

export function NodeGraph(initial_inputs: Inputs, store: Store) {

  const initial_outputs = call(initial_inputs)!;

  function call(inputs: Inputs): { error: string } | Outputs {
    const result = callWasm(interfaceFunctionName, inputs, store);
    if ("error" in result)
      return result;
    store = result.store;
    return result.outputs;
  }

  return {
    useState: () => {
      const [outputs, setOutputs] = useState(initial_outputs);
      return {
        graphOutputs: outputs,
        callGraph: (inputs: Inputs) => {
          const new_result = call(inputs);
          if (new_result != null)
            setOutputs(new_result);
        },
      };
    }
  };
}
