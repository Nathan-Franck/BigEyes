import { useState } from 'preact/hooks';
import { callWasm } from './zigWasmInterface';

type InterfaceFunction = typeof callWasm<typeof interfaceFunctionName>;
const interfaceFunctionName = "callNodeGraph" as const;
export type GraphInputs = Parameters<InterfaceFunction>[1];
export type GraphOutputs = Extract<ReturnType<InterfaceFunction>, { outputs: any }>["outputs"]

export function NodeGraph(initial_inputs: GraphInputs) {

  const initial_outputs = call(initial_inputs)!;

  function call(inputs: GraphInputs): { error: string } | GraphOutputs {
    console.log("Calling wasm with inputs", inputs);
    const result = callWasm(interfaceFunctionName, inputs);
    if ("error" in result)
      return result;
    return result.outputs;
  }

  return {
    call,
    useState: () => {
      const [outputs, setOutputs] = useState(initial_outputs);
      return {
        graphOutputs: outputs,
        callGraph: (inputs: GraphInputs) => {
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
