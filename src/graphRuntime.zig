const std = @import("std");
const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;

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

pub fn NodeGraph(comptime node_definitions: anytype, comptime graph: Blueprint) type {
    const NodeOutputs = build_type: {
        comptime var node_output_fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.nodes) |node| {
            const node_defn = @field(node_definitions, node.name);
            const node_outputs = @typeInfo(@TypeOf(node_defn)).Fn.return_type.?;
            const non_error_outputs = switch (@typeInfo(node_outputs)) {
                else => node_outputs,
                .ErrorUnion => |error_union| error_union.payload,
            };
            node_output_fields = comptime node_output_fields ++ .{.{
                .name = node.name[0.. :0],
                .type = non_error_outputs,
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
            var system_input_fields: []const std.builtin.Type.StructField = &.{};
            for (graph.nodes) |node|
                for (node.input_links) |link| switch (link.source) {
                    else => {},
                    .input_field => |input_field| {
                        const node_params = @typeInfo(@TypeOf(@field(node_definitions, node.name))).Fn.params;
                        const field_type = for (@typeInfo(node_params[node_params.len - 1].type.?).Struct.fields) |field|
                            if (std.mem.eql(u8, field.name, input_field)) break field.type else continue
                        else
                            @panic("fancy serve"); // TODO: Provide a useful compiler error about how blueprint and node defn's disagree.
                        system_input_fields = system_input_fields ++ for (system_input_fields) |system_input|
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
                .fields = system_input_fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };
        pub const SystemOutputs = build_type: {
            var system_output_fields: []const std.builtin.Type.StructField = &.{};
            for (graph.output) |output_defn| {
                const name = output_defn.system_field;
                const node_id = output_defn.output_node;
                const node = for (graph.nodes) |node|
                    if (std.mem.eql(u8, node.name, node_id)) break node else continue
                else
                    @compileError("Node not found " ++ node_id);
                const node_outputs = @typeInfo(@TypeOf(@field(node_definitions, node.name))).Fn.return_type.?;
                const non_error_outputs = switch (@typeInfo(node_outputs)) {
                    else => node_outputs,
                    .ErrorUnion => |error_union| error_union.payload,
                };
                const field_type = for (@typeInfo(non_error_outputs).Struct.fields) |field|
                    if (std.mem.eql(u8, field.name, output_defn.system_field)) break field.type else continue
                else
                    @panic("arced virus"); // TODO: Provide a useful compiler error about how blueprint and node defn's disagree.
                system_output_fields = system_output_fields ++ .{.{
                    .name = name[0.. :0],
                    .type = field_type,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field_type),
                }};
            }
            break :build_type @Type(.{ .Struct = .{
                .layout = .auto,
                .fields = system_output_fields,
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
                const node_outputs = @typeInfo(@TypeOf(@field(node_definitions, node.name))).Fn.return_type.?;
                const field_type = for (switch (@typeInfo(node_outputs)) {
                    .ErrorUnion => |error_union| @typeInfo(error_union.payload).Struct.fields,
                    .Struct => |the_struct| the_struct.fields,
                    else => @compileError("Invalid output type, expected struct or error union with a struct"),
                }) |field|
                    if (std.mem.eql(u8, field.name, store_field.system_field)) break field.type else continue
                else
                    @compileError("Field not found " ++ store_field.system_field ++ " in " ++ node_id);
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
        pub fn update(self: *Self, inputs: SystemInputs) !SystemOutputs {
            const nodes = node_definitions{ .allocator = self.allocator };
            var nodes_outputs: NodeOutputs = undefined;
            inline for (node_order) |node_index| {
                const node = graph.nodes[node_index];
                const node_defn = @field(node_definitions, node.name);
                const node_params = @typeInfo(@TypeOf(node_defn)).Fn.params;
                const NodeInputs = node_params[node_params.len - 1].type.?;
                var node_inputs: NodeInputs = undefined;
                inline for (node.input_links) |link| switch (link.source) {
                    .input_field => |input_field| {
                        @field(node_inputs, link.field) = @field(inputs, input_field);
                    },
                    .store_field => |store_field| {
                        @field(node_inputs, link.field) = @field(self.store, store_field);
                    },
                    .node => |node_blueprint| {
                        const node_outputs = @field(nodes_outputs, node_blueprint.name);
                        const node_output = @field(node_outputs, node_blueprint.field);
                        const InputType = @TypeOf(node_output);
                        const OutputType = @TypeOf(@field(node_inputs, link.field));
                        @field(node_inputs, link.field) =
                            AttemptEventCast(InputType, OutputType, node_output);
                    },
                };
                const node_output = @call(
                    .auto,
                    @field(node_definitions, node.function),
                    if (@typeInfo(@TypeOf(@field(node_definitions, node.function))).Fn.params.len == 2)
                        .{ nodes, node_inputs }
                    else
                        .{node_inputs},
                );

                @field(nodes_outputs, node.name) = switch (@typeInfo(@TypeOf(node_output))) {
                    else => node_output,
                    .ErrorUnion => try node_output,
                };
            }
            // Update store with new values from nodes!
            inline for (node_graph_blueprint.store) |store_defn| {
                const node_outputs = @field(nodes_outputs, store_defn.output_node);
                @field(self.store, store_defn.system_field) =
                    @field(node_outputs, store_defn.output_field);
            }
            // Output from system from select nodes...
            var system_outputs: SystemOutputs = undefined;
            inline for (node_graph_blueprint.output) |output_defn| {
                const node_outputs = @field(nodes_outputs, output_defn.output_node);
                @field(system_outputs, output_defn.system_field) =
                    @field(node_outputs, output_defn.output_field);
            }
            return system_outputs;
        }
    };
    return Graph;
}

test "Build" {
    const allocator = std.heap.page_allocator;
    const MyNodeGraph = NodeGraph(
        NodeDefinitions,
        node_graph_blueprint,
    );
    var my_node_graph = MyNodeGraph{
        .allocator = allocator,
        .store = .{
            .blueprint = .{
                .nodes = &.{},
                .output = &.{},
                .store = &.{},
            },
            .camera = .{},
            .context_menu = .{ .open = false, .location = .{ .x = 0, .y = 0 } },
            .interaction_state = .{ .node_selection = &.{} },
        },
    };
    const result_commands = try my_node_graph.update(.{
        .recieved_blueprint = node_graph_blueprint,
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
    try std.testing.expect(result_commands.render_event.?.something_changed == true);

    // const my_enum = enum {
    //     hello,
    //     goodbye,
    // };
    // const my_state = struct {
    //     test_me: my_enum,
    // };
    // std.debug.print("\n{s}\n", .{try std.json.stringifyAlloc(allocator, my_state{ .test_me = .hello }, .{})});
}
