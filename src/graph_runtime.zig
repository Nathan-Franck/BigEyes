const std = @import("std");
const node_graph_blueprint = @import("./interactive_node_builder_blueprint.zig");
const utils = @import("./utils.zig");
const wasm_entry = @import("./wasm_entry.zig");

const Input = struct {
    name: []const u8,
    type: type,
};

inline fn IsEventType(the_type: type) bool {
    return switch (@typeInfo(the_type)) {
        else => false,
        .Optional => |optional| switch (@typeInfo(optional.child)) {
            else => false,
            .Union => true,
        },
    };
}

fn AttemptEventCast(InputType: type, OutputType: type, value: InputType) OutputType {
    return if (!IsEventType(InputType))
        value
    else if (value) |non_null_value| blk: {
        const active_tag_index = @intFromEnum(non_null_value);
        inline for (@typeInfo(@typeInfo(InputType).Optional.child).Union.fields, 0..) |field_candidate, field_index| {
            if (active_tag_index == field_index) {
                const OutputNonNull = @typeInfo(OutputType).Optional.child;
                inline for (@typeInfo(OutputNonNull).Union.fields) |output_field| {
                    if (field_candidate.type == output_field.type) {
                        break :blk @unionInit(OutputNonNull, output_field.name, @field(non_null_value, field_candidate.name));
                    }
                }
            }
        }
        break :blk null;
    } else null;
}

pub fn NodeGraph(
    comptime graph: node_graph_blueprint.Blueprint,
    comptime node_definitions: anytype,
) type {
    const NodeOutputs = build_type: {
        comptime var node_output_fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.nodes) |node| {
            const node_defn = @field(node_definitions, node.name);
            const function_definition = @typeInfo(@TypeOf(node_defn)).Fn;
            const node_outputs = function_definition.return_type.?;
            const node_inputs = function_definition.params;
            const non_error_outputs = switch (@typeInfo(node_outputs)) {
                else => node_outputs,
                .ErrorUnion => |error_union| error_union.payload,
            };
            comptime var output_fields: []const std.builtin.Type.StructField = @typeInfo(non_error_outputs).Struct.fields;
            for (@typeInfo(node_inputs[node_inputs.len - 1].type.?).Struct.fields) |input_field| {
                switch (@typeInfo(input_field.type)) {
                    .Pointer => |pointer| {
                        switch (pointer.size) {
                            .One => {
                                if (!pointer.is_const)
                                    output_fields = comptime output_fields ++ .{.{
                                        .name = input_field.name,
                                        .type = pointer.child,
                                        .default_value = null,
                                        .is_comptime = false,
                                        .alignment = @alignOf(input_field.type),
                                    }};
                            },
                            .Slice => {
                                output_fields = comptime output_fields ++ .{.{
                                    .name = input_field.name,
                                    .type = []const pointer.child,
                                    .default_value = null,
                                    .is_comptime = false,
                                    .alignment = @alignOf(input_field.type),
                                }};
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            }
            const non_error_outputs_and_pointers = @Type(std.builtin.Type{ .Struct = .{
                .layout = .auto,
                .fields = output_fields,
                .decls = &.{},
                .is_tuple = false,
            } });
            node_output_fields = comptime node_output_fields ++ .{.{
                .name = node.name[0.. :0],
                .type = non_error_outputs_and_pointers,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(non_error_outputs),
            }};
        }
        break :build_type @Type(std.builtin.Type{ .Struct = .{
            .layout = .auto,
            .fields = node_output_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };
    const NodesDirtyFlags = build_type: {
        comptime var fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.nodes) |node| {
            fields = comptime fields ++ .{.{
                .name = node.name[0.. :0],
                .type = bool,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(bool),
            }};
        }
        break :build_type @Type(std.builtin.Type{ .Struct = .{
            .layout = .auto,
            .fields = fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };
    const node_order = precalculate: {
        var max_node_priority: u16 = 0;
        var node_priorities = [_]u16{0} ** graph.nodes.len;
        var next_nodes: []const struct { name: []const u8, priority: u16 } = &.{};
        gather_initial_nodes: inline for (graph.nodes) |node| {
            inline for (node.input_links) |link| switch (link.source) {
                else => {},
                .input_field => {
                    next_nodes = comptime next_nodes ++ .{.{ .name = node.name, .priority = 0 }};
                    continue :gather_initial_nodes;
                },
            };
        }
        inline while (next_nodes.len > 0) {
            const current_nodes = next_nodes;
            next_nodes = &.{};
            inline for (current_nodes) |current_node| {
                const node_index = for (graph.nodes, 0..) |node, index|
                    if (std.mem.eql(u8, node.name, current_node.name)) break index else continue
                else
                    @panic("trump tart");
                node_priorities[node_index] = @max(node_priorities[node_index], current_node.priority);
                @setEvalBranchQuota(9000);
                inline for (graph.nodes) |node|
                    if (std.mem.eql(u8, node.name, current_node.name))
                        inline for (graph.nodes) |next_node| {
                            if (is_output_node: for (next_node.input_links) |link| switch (link.source) {
                                else => continue,
                                .node => |input_node| if (std.mem.eql(
                                    u8,
                                    input_node.name,
                                    current_node.name,
                                )) break :is_output_node true else continue,
                            } else break :is_output_node false)
                                next_nodes = comptime next_nodes ++ .{.{
                                    .name = next_node.name,
                                    .priority = current_node.priority + 1,
                                }};
                            max_node_priority = @max(max_node_priority, current_node.priority + 1);
                        };
            }
        }
        comptime var node_order: []const u16 = &.{};
        @setEvalBranchQuota(9000);
        inline for (0..max_node_priority) |current_priority| {
            inline for (node_priorities, 0..) |node_priority, node_index| {
                if (node_priority == current_priority)
                    node_order = comptime node_order ++ .{node_index};
            }
        }
        break :precalculate node_order;
    };
    const Graph = struct {
        const Self = @This();
        pub const SystemInputs = build_type: {
            var fields: []const std.builtin.Type.StructField = &.{};
            for (graph.nodes) |node|
                for (node.input_links) |link| switch (link.source) {
                    else => {},
                    .input_field => |input_field| {
                        const node_params = @typeInfo(@TypeOf(@field(node_definitions, node.name))).Fn.params;
                        const field_type = for (@typeInfo(node_params[node_params.len - 1].type.?).Struct.fields) |field|
                            if (std.mem.eql(u8, field.name, input_field)) break field.type else continue
                        else
                            @panic("fancy serve"); // TODO: Provide a useful compiler error about how blueprint and node defn's disagree.
                        fields = fields ++ for (fields) |system_input|
                            if (std.mem.eql(u8, system_input.name, input_field)) break .{} else continue
                        else
                            .{std.builtin.Type.StructField{
                                .name = input_field[0.. :0],
                                .type = field_type,
                                .default_value = switch (@typeInfo(field_type)) {
                                    else => null,
                                    .Optional => |optional| blk: {
                                        const default_value: ?optional.child = null;
                                        break :blk @ptrCast(&default_value);
                                    },
                                },
                                .is_comptime = false,
                                .alignment = @alignOf(field_type),
                            }};
                    },
                };
            break :build_type @Type(.{ .Struct = .{
                .layout = .auto,
                .fields = fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };
        pub const SystemInputsDirtyFlags = build_type: {
            var fields: []const std.builtin.Type.StructField = &.{};
            for (graph.nodes) |node|
                for (node.input_links) |link| switch (link.source) {
                    else => {},
                    .input_field => |input_field| {
                        fields = fields ++ for (fields) |system_input_dirty|
                            if (std.mem.eql(u8, system_input_dirty.name, input_field)) break .{} else continue
                        else
                            .{std.builtin.Type.StructField{
                                .name = input_field[0.. :0],
                                .type = bool,
                                .default_value = null,
                                .is_comptime = false,
                                .alignment = @alignOf(bool),
                            }};
                    },
                };
            break :build_type @Type(.{ .Struct = .{
                .layout = .auto,
                .fields = fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };
        fn getOutputFieldTypeFromNode(node: node_graph_blueprint.NodeGraphBlueprintEntry, field_name: []const u8) type {
            const node_outputs = for (@typeInfo(NodeOutputs).Struct.fields) |field|
                if (std.mem.eql(u8, field.name, node.name))
                    break field.type
                else
                    continue
            else
                unreachable;
            const field_type = for (@typeInfo(node_outputs).Struct.fields) |field|
                if (std.mem.eql(u8, field.name, field_name))
                    break field.type
                else
                    continue
            else
                unreachable;
            return field_type;
        }
        pub const SystemOutputs = build_type: {
            var fields: []const std.builtin.Type.StructField = &.{};
            for (graph.output) |output_defn| {
                const name = output_defn.system_field;
                const node_id = output_defn.output_node;
                const node = for (graph.nodes) |node|
                    if (std.mem.eql(u8, node.name, node_id)) break node else continue
                else
                    @compileError("Node not found " ++ node_id);
                const field_type = getOutputFieldTypeFromNode(node, output_defn.output_field);
                fields = fields ++ .{.{
                    .name = name[0.. :0],
                    .type = field_type,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field_type),
                }};
            }
            break :build_type @Type(.{ .Struct = .{
                .layout = .auto,
                .fields = fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };
        pub const SystemStore = build_type: {
            const store_fields = graph.store;
            var system_store_fields: []const std.builtin.Type.StructField = &.{};
            for (store_fields) |store_field| {
                const name = store_field.system_field;
                const node_id = store_field.output_node;
                const node = for (graph.nodes) |node|
                    if (std.mem.eql(u8, node.name, node_id)) break node else continue
                else
                    @compileError("Node not found " ++ node_id);
                const field_type = getOutputFieldTypeFromNode(node, store_field.output_field);
                system_store_fields = system_store_fields ++ .{.{
                    .name = name[0.. :0],
                    .type = field_type,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field_type),
                }};
            }
            break :build_type @Type(.{ .Struct = .{
                .layout = .auto,
                .fields = system_store_fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };
        allocator: std.mem.Allocator,
        store: SystemStore,
        store_arena: std.heap.ArenaAllocator,
        system_inputs: ?SystemInputs,
        nodes_arenas: [graph.nodes.len]std.heap.ArenaAllocator,
        nodes_outputs: NodeOutputs,
        nodes_dirty_flags: NodesDirtyFlags,
        pub fn init(props: struct {
            allocator: std.mem.Allocator,
            store: SystemStore,
        }) !Self {
            var self = Self{
                .allocator = props.allocator,
                .store = props.store,
                .store_arena = std.heap.ArenaAllocator.init(props.allocator),
                .system_inputs = null,
                .nodes_arenas = undefined,
                .nodes_outputs = undefined,
                .nodes_dirty_flags = undefined,
            };
            for (graph.nodes, 0..) |_, index| {
                self.nodes_arenas[index] = std.heap.ArenaAllocator.init(props.allocator);
            }
            return self;
        }
        pub fn update(self: *Self, inputs: SystemInputs) !SystemOutputs {

            // Check inputs for changes...
            var inputs_dirty: SystemInputsDirtyFlags = undefined;
            inline for (@typeInfo(SystemInputs).Struct.fields) |field| {
                const field_name = field.name;
                @field(inputs_dirty, field_name) = if (self.system_inputs) |previous_inputs|
                    !std.meta.eql(@field(inputs, field_name), @field(previous_inputs, field_name))
                else
                    true;
            }
            self.system_inputs = inputs;

            // Process all nodes...
            inline for (node_order) |node_index| {
                const node = graph.nodes[node_index];
                const node_defn = @field(node_definitions, node.name);
                const node_params = @typeInfo(@TypeOf(node_defn)).Fn.params;
                const NodeInputs = node_params[node_params.len - 1].type.?;
                var node_inputs: NodeInputs = undefined;
                var dirty = false;
                var mutable_fields: build_type: {
                    var mutable_fields: []const std.builtin.Type.StructField = &.{};
                    for (node.input_links) |link| {
                        switch (@typeInfo(@TypeOf(@field(node_inputs, link.field)))) {
                            .Pointer => |pointer| {
                                switch (pointer.size) {
                                    .One => {
                                        mutable_fields = mutable_fields ++ .{.{
                                            .name = link.field[0.. :0],
                                            .type = *const pointer.child,
                                            .default_value = null,
                                            .is_comptime = false,
                                            .alignment = @alignOf(pointer.child),
                                        }};
                                    },
                                    .Slice => {
                                        mutable_fields = mutable_fields ++ .{.{
                                            .name = link.field[0.. :0],
                                            .type = []const pointer.child,
                                            .default_value = null,
                                            .is_comptime = false,
                                            .alignment = @alignOf(pointer.child),
                                        }};
                                    },
                                    else => {},
                                }
                            },
                            else => {},
                        }
                    }
                    break :build_type @Type(.{ .Struct = .{
                        .layout = .auto,
                        .fields = mutable_fields,
                        .decls = &.{},
                        .is_tuple = false,
                    } });
                } = undefined;
                inline for (node.input_links) |link| {
                    const node_input_field = switch (link.source) {
                        .input_field => |input_field| node_input: {
                            if (@field(inputs_dirty, input_field)) {
                                dirty = true;
                            }
                            break :node_input @field(inputs, input_field);
                        },
                        .store_field => |store_field| @field(self.store, store_field),
                        .node => |node_blueprint| input_field: {
                            const node_outputs = @field(self.nodes_outputs, node_blueprint.name);
                            const node_output = @field(node_outputs, node_blueprint.field);
                            const InputType = @TypeOf(node_output);
                            const OutputType = @TypeOf(@field(node_inputs, link.field));
                            if (@field(self.nodes_dirty_flags, node_blueprint.name)) {
                                dirty = true;
                            }
                            break :input_field AttemptEventCast(InputType, OutputType, node_output);
                        },
                    };
                    const target_input_field = &@field(node_inputs, link.field);
                    target_input_field.* = switch (@typeInfo(@TypeOf(target_input_field.*))) {
                        else => node_input_field,
                        .Pointer => |pointer| switch (pointer.size) {
                            .One => deferred_clone: {
                                @field(mutable_fields, link.field) = &node_input_field;
                                break :deferred_clone undefined;
                            },
                            .Slice => deferred_clone: {
                                @field(mutable_fields, link.field) = node_input_field;
                                break :deferred_clone undefined;
                            },
                            else => unreachable,
                        },
                    };
                }

                @field(self.nodes_dirty_flags, node.name) = dirty;

                const target = &@field(self.nodes_outputs, node.name);
                target.* = if (!dirty)
                    target.*
                else blk: {
                    _ = self.nodes_arenas[node_index].reset(.retain_capacity);

                    // Duplicate data from inputs where the node is allowed to manipulate pointers ...
                    // inline for (@typeInfo(@TypeOf(mutable_fields)).Struct.fields) |field| {
                    //     const pointer = @typeInfo(field.type).Pointer;
                    //     const input_to_clone = &@field(node_inputs, field.name);
                    //     input_to_clone.* = switch (pointer.size) {
                    //         .One => cloned: {
                    //             var result = (try utils.deepClone(
                    //                 pointer.child,
                    //                 self.nodes_arenas[node_index].allocator(),
                    //                 @field(mutable_fields, field.name).*,
                    //             )).value;
                    //             break :cloned &result;
                    //         },
                    //         .Slice => (try utils.deepClone(
                    //             @TypeOf(input_to_clone.*),
                    //             self.nodes_arenas[node_index].allocator(),
                    //             @field(mutable_fields, field.name),
                    //         )).value,
                    //         else => unreachable,
                    //     };
                    // }

                    const function_output = @call(
                        .auto,
                        @field(node_definitions, node.function),
                        if (@typeInfo(@TypeOf(@field(node_definitions, node.function))).Fn.params.len == 1)
                            .{
                                node_inputs,
                            }
                        else
                            .{
                                &self.nodes_arenas[node_index],
                                node_inputs,
                            },
                    );
                    var node_output: @TypeOf(target.*) = undefined;
                    // inline for (@typeInfo(@TypeOf(mutable_fields)).Struct.fields) |mutable_field| {
                    //     const pointer = @typeInfo(mutable_field.type).Pointer;
                    //     @field(node_output, mutable_field.name) = switch (pointer.size) {
                    //         else => unreachable,
                    //         .One => @field(node_inputs, mutable_field.name).*,
                    //         .Slice => @field(node_inputs, mutable_field.name),
                    //     };
                    // }
                    node_output = utils.copyWith(
                        node_output,
                        switch (@typeInfo(@TypeOf(function_output))) {
                            else => function_output,
                            .ErrorUnion => try function_output,
                        },
                    );
                    break :blk node_output;
                };
            }

            _ = self.store_arena.reset(.retain_capacity);

            // Copy over new store values...
            inline for (graph.store) |store_defn| {
                const node_result = @field(self.nodes_outputs, store_defn.output_node);
                const result = @field(node_result, store_defn.output_field);
                @field(self.store, store_defn.system_field) =
                    (try utils.deepClone(@TypeOf(result), self.store_arena.allocator(), result)).value;
            }

            // Output from system from select nodes...
            var system_outputs: SystemOutputs = undefined;
            inline for (graph.output) |output_defn| {
                const node_outputs = @field(self.nodes_outputs, output_defn.output_node);
                const result = @field(node_outputs, output_defn.output_field);
                @field(system_outputs, output_defn.system_field) =
                    (try utils.deepClone(@TypeOf(result), self.store_arena.allocator(), result)).value;
            }

            return system_outputs;
        }
    };
    return Graph;
}

test "Build" {
    const NodeDefinitions = @import("./node_graph_blueprint_nodes.zig");
    const allocator = std.heap.page_allocator;
    const MyNodeGraph = NodeGraph(
        node_graph_blueprint.node_graph_blueprint,
        NodeDefinitions,
    );
    var my_node_graph = try MyNodeGraph.init(.{
        .allocator = allocator,
        .store = .{
            .node_dimensions = &.{},
            .blueprint = .{
                .nodes = &.{},
                .output = &.{},
                .store = &.{},
            },
            .camera = .{},
            .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 } },
            .interaction_state = .{ .node_selection = &.{} },
        },
    });
    _ = try my_node_graph.update(.{
        .recieved_blueprint = node_graph_blueprint.node_graph_blueprint,
        .keyboard_modifiers = .{
            .shift = false,
            .alt = false,
            .control = false,
            .super = false,
        },
    });
    // Yay, at least we can confirm that the Blueprint Loader works!
    // Next will be to validate that multiple steps are working in-tandem with each other...
    try std.testing.expect(my_node_graph.store.blueprint.nodes.len > 0);
    try std.testing.expect(my_node_graph.store.blueprint.store.len > 0);
}
