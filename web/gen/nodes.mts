export const nodesDecl = { Struct: { 
	helloSlice: { Node: { State: { Struct: {  slice: { Array: { Array: "number" } } } }, Options: { Struct: {  saySomethingNice: "boolean" } }, Returns: { Struct: {  message: "string" } } } }, 
	helloFace: { Node: { State: { Struct: {  faces: { Array: { Array: "number" } } } }, Returns: { Struct: {  faces: { Array: { Array: "number" } } } } } }, 
	subdivideFaces: { Node: { State: { Struct: {  faces: { Array: { Array: "number" } }, points: { Array: ["number", "number", "number", "number"] } } }, Returns: { Struct: {  points: { Array: ["number", "number", "number", "number"] }, quads: { Array: ["number", "number", "number", "number"] } } } } }, 
} } as const;
