const std = @import("std");

const Vec4 = @Vector(4, f32);

pub fn Forest(Prefab: type, comptime chunk_size: i32) type {
    return struct {
        pub const Tree = struct {
            pub const SpawnRadius = struct {
                tree: *const Tree,
                radius: f32,
                likelihood_change: f32,
            };
            spawn_radius: ?[]const SpawnRadius = null,
            prefab: Prefab,
        };

        pub const Spawn = struct {
            tree: *const Tree,
            position: Vec4,
            rotation: Vec4,
            scale: f32,
        };

        pub const Chunk = [chunk_size][chunk_size]?Spawn;

        chunks: std.AutoHashMap(@Vector(3, i32), Chunk),
    };
}

/// Takes a Node type and calls the run function on it, returning the result of node_output.
/// This makes using nodes as pure functions more ergonomic.
pub fn callNode(node: anytype) @TypeOf(node).NodeOutput {
    var resulting_node = node;
    resulting_node.run();
    return resulting_node.node_output;
}

/// Validate a node type
///
/// Input struct is expected to have the following boilerplate to be considered a Node
///
/// ```zig
/// struct {
///     node_output: NodeOutput = undefined,
///
///     // Input fields here
///
///     pub const NodeOutput = struct {
///         // Output fields here
///     };
///
///     pub fn run(self: *@This()) void {
///         // Implementation goes here
///     }
/// }
/// ```
fn Node(NodeToValidate: type) type {
    const instance: NodeToValidate = undefined;

    if (!@hasField(NodeToValidate, "node_output"))
        @compileError("Expected a field called 'node_output' to exist");

    if (@TypeOf(instance.node_output) != NodeToValidate.NodeOutput)
        @compileError("Expected field 'node_output' to be of type NodeOutput");

    if (!@hasDecl(NodeToValidate, "run"))
        @compileError("Expected function called 'run' to exist");

    if (@typeInfo(@TypeOf(NodeToValidate.run)).Fn.params[0].type != *NodeToValidate)
        @compileError("Expected first parameter of 'run' to be of type *@This()");

    return NodeToValidate;
}

test "Graph Node Idea" {
    const MyNode0 = Node(struct {
        node_output: NodeOutput = undefined,

        pub const NodeOutput = struct {
            first: []const u8,
            second: u8,
            third: f32,
        };

        pub fn run(self: *@This()) void {
            self.node_output = .{
                .first = "hello!",
                .second = '%',
                .third = 1.0,
            };
        }
    });

    const MyNode1 = Node(struct {
        node_output: NodeOutput = undefined,

        first: *const []const u8,
        second: *const u8,
        third: *const f32,

        pub const NodeOutput = struct {
            success: bool,
        };

        pub fn run(self: *@This()) void {
            self.node_output = output: {
                if (std.mem.eql(u8, self.first.*, "hello!")) {
                    break :output .{ .success = true };
                } else {
                    break :output .{ .success = false };
                }
            };
        }
    });

    // Declare a graph of nodes to run later...
    const Graph = struct {
        pub const my_node_0 = MyNode0{};
        pub const my_node_1 = MyNode1{
            .first = &my_node_0.node_output.first,
            .second = &my_node_0.node_output.second,
            .third = &my_node_0.node_output.third,
        };
    };
    _ = Graph; // autofix

    // Or, just call the nodes inline!
    var live_node_0 = callNode(MyNode0{});
    const live_node_1 = callNode(MyNode1{
        .first = &"hello!",
        .second = &live_node_0.second,
        .third = &live_node_0.third,
    });
    // Note this isn't the greatest for ergonomics, but will work in a pinch...

    std.debug.print("{any}\n", .{live_node_1.success});
}

test "Ascii Forest" {
    std.debug.print("{s}\n", .{"Hello!"});
    const Ascii = struct {
        character: u8,
    };
    const AsciiForest = Forest(Ascii, 5);

    const Trees = struct {
        pub const little_tree = AsciiForest.Tree{
            .prefab = .{ .character = 'i' },
        };
        pub const big_tree = AsciiForest.Tree{
            .prefab = .{ .character = '&' },
            .spawn_radius = &[_]AsciiForest.Tree.SpawnRadius{
                .{
                    .tree = &little_tree,
                    .radius = 10,
                    .likelihood_change = 1,
                },
            },
        };
    };

    // I'm a little sad that my variable id's go away once packed into a tuple :/
    const typeInfo: std.builtin.Type = @typeInfo(Trees);
    const decls = typeInfo.Struct.decls;

    std.debug.print("fields are {any}\n", .{decls});
}
