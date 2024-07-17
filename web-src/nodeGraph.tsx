import { useState } from "preact/hooks";
import { callWasm } from "./zigWasmInterface";

const interfaceFunctionName = "updateNodeGraph" as const;
type InterfaceFunction = typeof callWasm<typeof interfaceFunctionName>;
export type GraphInputs = Parameters<InterfaceFunction>[1];
export type GraphOutputs = Extract<
  ReturnType<InterfaceFunction>,
  { outputs: any }
>["outputs"];

export function NodeGraph(initial_inputs: GraphInputs) {
  const initial_outputs = call(initial_inputs)!;

  function call(inputs: GraphInputs): { error: string } | GraphOutputs {
    const result = callWasm(interfaceFunctionName, inputs);
    if ("error" in result) return result;
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
          if (new_result != null) {
            setOutputs(new_result);
          }
        },
      };
    },
  };
}
