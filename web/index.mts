import {helloThere} from "./anotherOne.mjs";

function messageFromWasm(sourcePtr: number, sourceLen: number) {
    const str = (new TextDecoder()).decode(new Uint8Array(instance.exports.memory.buffer, sourcePtr, sourceLen))
    console.log("Hello! " + str)
}

const { instance } = await WebAssembly.instantiateStreaming(fetch("bin/game.wasm"), {
    env: {
        memory: new WebAssembly.Memory({ initial: 2 }),
        messageFromWasm: messageFromWasm,
    },
}) as any as {
    instance: {
        exports: {
            testSubdiv: (arg0: number) => void, // TODO: Generate from zig file
            memory: WebAssembly.Memory,
        },
    },
};

instance.exports.testSubdiv(2);

helloThere();