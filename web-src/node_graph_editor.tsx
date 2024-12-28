import { useState, useCallback } from 'react';
import {
  ReactFlow,
  addEdge,
  applyNodeChanges,
  applyEdgeChanges,
  type Node,
  type Edge,
  type FitViewOptions,
  type OnConnect,
  type OnNodesChange,
  type OnEdgesChange,
  type OnNodeDrag,
  type NodeTypes,
  type EdgeTypes,
  type DefaultEdgeOptions,
  NodeProps,
  EdgeProps,
  Controls,
  MiniMap,
  Background,
  BackgroundVariant,
  Handle,
  Position,
} from '@xyflow/react';

import '@xyflow/react/dist/style.css';

type NumberNode = Node<{ number: number }, 'number'>;
export function NumberNode({ data }: NodeProps<NumberNode>) {
  console.table(data);
  return <div>A special number: {data.number}</div>;
}

type TextNode = Node<{ text: string }, 'text'>;
export function TextNode({ data }: NodeProps<TextNode>) {
  const isConnectable = true;
  return <div className="react-flow__node-default">
    <Handle
      type="target"
      position={Position.Top}
      isConnectable={isConnectable}
      isValidConnection={(edge) => edge.target == '1'}
    />
    <div>A special text: {data.text}</div>
  </div>
}

const initialNodes: Node[] = [
  { id: '1', type: "txt", data: { text: "hi", label: 'Node 1' }, position: { x: 5, y: 5 } },
  { id: '2', data: { number: 1, label: 'Node 2' }, position: { x: 5, y: 100 } },
];

const initialEdges: Edge[] = [{ id: 'e1-2', source: '1', target: '2' }];

const fitViewOptions: FitViewOptions = {
  padding: 0.2,
};

const defaultEdgeOptions: DefaultEdgeOptions = {
  animated: true,
};

const nodeTypes: NodeTypes = {
  num: NumberNode,
  txt: TextNode,
};

function MyEdge({ data }: EdgeProps<Edge<{ thinger: string }, 'my-edge'>>) {
  return <div>Hello: {data?.thinger}</div>;
}
const edgeTypes: EdgeTypes = {
  txt: MyEdge,
};

const onNodeDrag: OnNodeDrag = (_, node) => {
  console.log('drag event', node.data);
};

export function Flow() {
  const [nodes, setNodes] = useState<Node[]>(initialNodes);
  const [edges, setEdges] = useState<Edge[]>(initialEdges);

  const onNodesChange: OnNodesChange = useCallback(
    (changes) => setNodes((nds) => applyNodeChanges(changes, nds)),
    [setNodes],
  );
  const onEdgesChange: OnEdgesChange = useCallback(
    (changes) => setEdges((eds) => applyEdgeChanges(changes, eds)),
    [setEdges],
  );
  const onConnect: OnConnect = useCallback(
    (connection) => setEdges((eds) => addEdge(connection, eds)),
    [setEdges],
  );

  return (

    <div style={{ width: '100vw', height: '100vh' }}>
      <ReactFlow
        nodes={nodes}
        nodeTypes={nodeTypes}
        edges={edges}
        edgeTypes={edgeTypes}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        onNodeDrag={onNodeDrag}
        fitView
        fitViewOptions={fitViewOptions}
        defaultEdgeOptions={defaultEdgeOptions}
      >
        <Controls />
        <MiniMap />
        <Background variant={BackgroundVariant.Dots} gap={12} size={1} />
      </ReactFlow>
    </div>
  );
}
