import { useState } from 'preact/hooks';
import { callWasm } from './zigWasmInterface';

type InterfaceFunction = typeof callWasm<typeof interfaceFunctionName>;
const interfaceFunctionName = "callNodeGraph" as const;
type Inputs = Parameters<InterfaceFunction>[1];
type Outputs = Extract<ReturnType<InterfaceFunction>, { outputs: any }>["outputs"]

export function NodeGraph(initial_inputs: Inputs) {

  const initial_outputs = call(initial_inputs)!;

  function call(inputs: Inputs): { error: string } | Outputs {
    console.log("Calling wasm with inputs", inputs);
    const result = callWasm(interfaceFunctionName, inputs);
    if ("error" in result)
      return result;
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
            {
            console.log("Got result", new_result);
            setOutputs(new_result);
            }
        },
      };
    }
  };
}
