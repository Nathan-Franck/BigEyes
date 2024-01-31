import { ObjectUtils } from "./ObjectUtils.mjs";
import { helloThere } from "./anotherOne.mjs";
import { nodesDecl } from "./gen/nodes.mjs";

type DeclToTypeVector<T> = T extends [] ? [] : T extends [infer U, ...infer Rest] ? [DeclToDirectFunction<U>, ...DeclToTypeVector<Rest>] : [];
type DeclToDirectFunction<T> =
    T extends { Struct: infer U } ? { -readonly [K in keyof U]: DeclToDirectFunction<U[K]> }
    : T extends { Node: { State: infer State, Options: infer Options, Returns: infer Returns } } ? (state: DeclToDirectFunction<State>, options: DeclToDirectFunction<Options>) => DeclToDirectFunction<Returns>
    : T extends { Node: { State: infer State, Returns: infer Returns } } ? (state: DeclToDirectFunction<State>) => DeclToDirectFunction<Returns>
    : T extends { Array: infer U } ? DeclToDirectFunction<U>[]
    : T extends readonly [...infer U] ? DeclToTypeVector<U>
    : T extends "number" ? number
    : T extends "string" ? string
    : T extends "boolean" ? boolean
    : T extends null ? null
    : unknown;

type NodesDirect = DeclToDirectFunction<typeof nodesDecl>;

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
    const buffer = new TextEncoder().encode(string)
    const pointer = instance.exports.allocUint8(buffer.length + 1)
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
            callWithJson: (name_ptr: number, name_len: number, args_ptr: number, args_len: number) => void, // TODO: Generate from zig file
            allocUint8: (length: number) => number,
            memory: WebAssembly.Memory,
        },
    },
};

function callNodeDirect<T extends keyof NodesDirect>(name: T, ...args: Parameters<NodesDirect[T]>): ReturnType<NodesDirect[T]> {
    const nameBuffer = encodeString(name);
    const argsBuffer = encodeString(JSON.stringify(args));
    let result: ReturnType<NodesDirect[T]> = null as any;
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

let nodesDirect: NodesDirect;
{
    const result = {} as any;
    ObjectUtils.entries(nodesDecl.Struct).forEach(([key, value]) => {
        if ("Options" in value.Node)
            result[key] = (state: any, options: any) => callNodeDirect(key, state, options);
        else
            result[key] = (state: any) => callNodeDirect(key, state);
    })
    nodesDirect = result;
}

type NodeGraph<Inputs, Nodes> = {
    Inputs: Inputs,
    Nodes: {
        [name in keyof Nodes]: {
            node: keyof NodesDirect,
            stateInputs: "hi",
        }
    },
};

const nodeGraph = validateNodeGraph({
    Inputs: {
        dkdf: "number",
    },
    Nodes: {
        helloSlice: {
            node: "helloSlice",
            stateInputs: "hi",
        },
        helloStructArray: {
            node: "helloSlice",
            stateInputs: "w",
        },
    },
});

function validateNodeGraph<Inputs, Nodes, const Graph extends NodeGraph<Inputs, Nodes>>(graph: Graph & NodeGraph<Inputs, Nodes>): Graph {
    return graph;
}

console.log(nodesDirect.helloSlice([[1, 2, 3]], { saySomethingNice: true }));
console.log(nodesDirect.subdivideFaces({
    faces: [
        [0, 1, 2, 3],
        [0, 1, 5, 4],
    ],
    points: [
        [-1.1, 1.0, 1.0, 1.0],
        [-1.0, -1.0, 1.0, 1.0],
        [1.0, -1.0, 1.0, 1.0],
        [1.0, 1.0, 1.0, 1.0],
        [-1.0, 1.0, -1.0, 1.0],
        [-1.0, -1.0, -1.0, 1.0],
    ],
}));

helloThere();