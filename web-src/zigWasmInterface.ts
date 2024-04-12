import type { WasmInterface } from "../gen/wasmInterface";
import init from '../bin/game.wasm?init';

let onMessage: null | ((message: string) => void) = null;
let onError: null | ((error: string) => void) = null;

function messageFromWasm(sourcePtr: number, sourceLen: number) {
  const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
  if (onMessage == null)
    console.log(str)
  else
    onMessage(str)
}

function debugLogFromWasm(sourcePtr: number, sourceLen: number) {
  const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
  console.log(str)
}

function errorFromWasm(sourcePtr: number, sourceLen: number) {
  const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
  if (onError == null)
    console.error(str)
  else
    onError(str);
}

const instance = (await init({
  env: {
    memory: new WebAssembly.Memory({ initial: 2 }),
    messageFromWasm,
    errorFromWasm,
    debugLogFromWasm,
  },
})) as {
  exports: {
    dumpNodeTypeInfo: () => void,
    callWithJson: (name_ptr: number, name_len: number, args_ptr: number, args_len: number) => void, // TODO: Generate from zig file
    allocUint8: (length: number) => number,
    memory: WebAssembly.Memory,
  },
};

export function callWasm<T extends keyof WasmInterface>(name: T, ...args: Parameters<WasmInterface[T]>): { error: string } | ReturnType<WasmInterface[T]> {
  const nameBuffer = stringToSlice(name);
  const argsBuffer = stringToSlice(JSON.stringify(args));
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
      nameBuffer.len,
      argsBuffer.ptr,
      argsBuffer.len
    );
  }
  catch (e: any) {
    result = { error: e.message }
  }
  onMessage = null;
  return result;
}

export function stringToSlice(string: string) {
  const buffer = new TextEncoder().encode(string);
  const pointer = instance.exports.allocUint8(buffer.length + 1);
  const slice = new Uint8Array(
    instance.exports.memory.buffer,
    pointer,
    buffer.length + 1
  );
  slice.set(buffer);
  slice[buffer.length] = 0;
  return { type: <const>"Uint8Array", ptr: pointer, len: buffer.length };
};

export function sliceToString(slice: { type: "Uint8Array", ptr: number, len: number }) {
  const result =  new TextDecoder().decode(new Uint8Array(instance.exports.memory.buffer, slice.ptr, slice.len));
  console.log("Slice to string", slice, result);
  return result;
}

function sliceToArrayFunc<N extends string, T extends new(buffer: ArrayBuffer, byteOffset: number, length: number) => any>(_: N, constructor: T) {
  return (slice: { type: N, ptr: number, len: number }) => {
    return new constructor(instance.exports.memory.buffer, slice.ptr, slice.len);
  }
}

export const sliceToArray = <const>{
  "Uint8ClampedArray": sliceToArrayFunc("Uint8Array", Uint8ClampedArray),
  "Uint8Array": sliceToArrayFunc("Uint8Array", Uint8Array),
  "Uint16Array": sliceToArrayFunc("Uint16Array", Uint16Array),
  "Uint32Array": sliceToArrayFunc("Uint32Array", Uint32Array),
  "Int8Array": sliceToArrayFunc("Int8Array", Int8Array),
  "Int16Array": sliceToArrayFunc("Int16Array", Int16Array),
  "Int32Array": sliceToArrayFunc("Int32Array", Int32Array),
  "Float32Array": sliceToArrayFunc("Float32Array", Float32Array),
};