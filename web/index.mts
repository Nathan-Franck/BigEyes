import { helloThere } from "./anotherOne.mjs";

function messageFromWasm(sourcePtr: number, sourceLen: number) {
    const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
    console.log(str)
}
function errorFromWasm(sourcePtr: number, sourceLen: number) {
    const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
    console.error(str)
}
function encodeString(string: string) {
    const buffer = new TextEncoder().encode(string);
    const pointer = instance.exports.allocUint8(buffer.length + 1); // ask Zig to allocate memory
    const slice = new Uint8Array(
        instance.exports.memory.buffer, // memory exported from Zig
        pointer,
        buffer.length + 1
    );
    slice.set(buffer);
    slice[buffer.length] = 0; // null byte to null-terminate the string
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
            callWithJson: (name_ptr: number, name_len: number, args_ptr: number, args_len: number) => void, // TODO: Generate from zig file
            allocUint8: (length:number) => number,
            memory: WebAssembly.Memory,
        },
    },
};

var name = encodeString("testSubdiv");
const faces = [
    [ 0, 1, 2, 3 ],
    [ 0, 1, 5, 4 ],
];
const points = [
    [ -1.1, 1.0, 1.0, 1.0 ],
    [ -1.0, -1.0, 1.0, 1.0 ],
    [ 1.0, -1.0, 1.0, 1.0 ],
    [ 1.0, 1.0, 1.0, 1.0 ],
    [ -1.0, 1.0, -1.0, 1.0 ],
    [ -1.0, -1.0, -1.0, 1.0 ],
];
var args = encodeString(JSON.stringify([ faces, points ]));
instance.exports.callWithJson(
    name.ptr,
    name.length,
    args.ptr,
    args.length
);

helloThere();