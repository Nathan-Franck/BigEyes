export type Nodes = {
	helloSlice: (arg0: number[][]) => number[][], 
	testSubdiv: (arg0: number[][], arg1: [number, number, number, number][]) => { points: [number, number, number, number][], quads: number[][] }, 
	testNodeGraph: (arg0: {  }) => void, 
}