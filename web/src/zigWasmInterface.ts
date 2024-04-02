import type { WasmInterface } from "../gen/wasmInterface";

let onMessage: null | ((message: string) => void) = null;
let onError: null | ((error: string) => void) = null;

function messageFromWasm(sourcePtr: number, sourceLen: number) {
  const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
  if (onMessage == null)
    console.log(str)
  else
    onMessage(str)
}

function errorFromWasm(sourcePtr: number, sourceLen: number) {
  const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
  if (onError == null)
    console.error(str)
  else
    onError(str);
}

function encodeString(string: string) {
  const buffer = new TextEncoder().encode(string);
  const pointer = instance.exports.allocUint8(buffer.length + 1);
  const slice = new Uint8Array(
    instance.exports.memory.buffer,
    pointer,
    buffer.length + 1
  );
  slice.set(buffer);
  slice[buffer.length] = 0;
  return { ptr: pointer, length: buffer.length };
};

const { instance } = await WebAssembly.instantiateStreaming(fetch("bin/game.wasm"), {
  env: {
    memory: new WebAssembly.Memory({ initial: 2 }),
    messageFromWasm,
    errorFromWasm,
  },
}) as any as {
  instance: {
    exports: {
      dumpNodeTypeInfo: () => void,
      callWithJson: (name_ptr: number, name_len: number, args_ptr: number, args_len: number) => void, // TODO: Generate from zig file
      allocUint8: (length: number) => number,
      memory: WebAssembly.Memory,
    },
  },
};

export function callWasm<T extends keyof WasmInterface>(name: T, ...args: Parameters<WasmInterface[T]>): { error: string } | ReturnType<WasmInterface[T]> {
  const nameBuffer = encodeString(name);
  const argsBuffer = encodeString(JSON.stringify(args));
  let result: { error: string } | ReturnType<WasmInterface[T]> = null as any;
  onMessage = (message) => {
    result = JSON.parse(message);
  };
  onError = (error) => {
    result = { error };
  };
  try {
    instance.exports.callWithJson(
      nameBuffer.ptr,
      nameBuffer.length,
      argsBuffer.ptr,
      argsBuffer.length
    );
  }
  catch (e: any) {
    result = { error: e.message }
  }
  onMessage = null;
  return result;
}

