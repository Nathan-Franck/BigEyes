export const nodesDecl = { Struct: { 
	helloStructArray: { Node: { State: { Array: { Struct: {  a: "boolean", b: "string" } } }, Returns: { Array: { Struct: {  a: "boolean", b: "string" } } } } }, 
	helloSlice: { Node: { State: { Array: { Array: "number" } }, Options: { Struct: {  saySomethingNice: "boolean" } }, Returns: "string" } }, 
	subdivideFaces: { Node: { State: { Struct: {  faces: { Array: { Array: "number" } }, points: { Array: ["number", "number", "number", "number"] } } }, Returns: { Struct: {  points: { Array: ["number", "number", "number", "number"] }, quads: { Array: ["number", "number", "number", "number"] } } } } }, 
} } as const;
