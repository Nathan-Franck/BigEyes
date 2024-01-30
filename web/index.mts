import { helloThere } from "./anotherOne.mjs";
import type { Nodes } from "./gen/nodes.d.ts";

let onMessage: null | ((message: string) => void) = null;
function messageFromWasm(sourcePtr: number, sourceLen: number) {
    const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
    if (onMessage == null)
        console.log(str)
    else
        onMessage(str)
}

function errorFromWasm(sourcePtr: number, sourceLen: number) {
    const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
    console.error(str)
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

function callNode<T extends keyof Nodes>(name: T, ...args: Parameters<Nodes[T]>): ReturnType<Nodes[T]> {
    const nameBuffer = encodeString(name);
    const argsBuffer = encodeString(JSON.stringify(args));
    let result: ReturnType<Nodes[T]> = null as any;
    onMessage = (message) => {
        result = JSON.parse(message);
    };
    instance.exports.callWithJson(
        nameBuffer.ptr,
        nameBuffer.length,
        argsBuffer.ptr,
        argsBuffer.length
    );
    onMessage = null;
    return result;
}

console.log(callNode("helloSlice", [[1, 2, 3]]));
console.log(callNode("testSubdiv", [
    [0, 1, 2, 3],
    [0, 1, 5, 4],
], [
    [-1.1, 1.0, 1.0, 1.0],
    [-1.0, -1.0, 1.0, 1.0],
    [1.0, -1.0, 1.0, 1.0],
    [1.0, 1.0, 1.0, 1.0],
    [-1.0, 1.0, -1.0, 1.0],
    [-1.0, -1.0, -1.0, 1.0],
]));

helloThere();