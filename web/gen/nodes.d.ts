export type Nodes = {
	helloSlice: (arg0: number[][]) => number[][], 
	testSubdiv: (arg0: number[][], arg1: [number, number, number, number][]) => { points: [number, number, number, number][], quads: number[][] }, 
	testNodeGraph: (arg0: { open: boolean, selected_node?: number[], location: { x: number, y: number }, options: number[][] }) => void, 
}