const std = @import("std");
const utils = @import("./utils.zig");

pub const NodeLink = struct {
    name: []const u8,
    field: []const u8,
};

pub const InputLink = struct {
    field: []const u8,
    source: union(enum) {
        node: NodeLink,
        input_field: []const u8,
        store_field: []const u8,
    },
};

pub const NodeGraphBlueprintEntry = struct {
    name: []const u8,
    function: []const u8,
    input_links: []const InputLink,

    pub fn validateLinkingAllParameters(
        comptime node: @This(),
        comptime function_params: []const std.builtin.Type.Fn.Param,
    ) void {
        comptime {
            var unhandled_inputs: []const []const u8 = &.{};

            for (@typeInfo(switch (function_params.len) {
                else => @compileError("Unsupported number of function parameters for node"),
                1 => function_params[0].type.?,
                2 => function_params[1].type.?,
            }).@"struct".fields) |field| {
                unhandled_inputs = unhandled_inputs ++ .{field.name};
            }
            for (node.input_links) |link| {
                var next_unhandled_inputs: []const []const u8 = &.{};
                for (unhandled_inputs) |unhandled_input| {
                    if (!std.mem.eql(u8, unhandled_input, link.field))
                        next_unhandled_inputs = next_unhandled_inputs ++ .{unhandled_input};
                }
                unhandled_inputs = next_unhandled_inputs;
            }
            if (unhandled_inputs.len > 0) {
                @compileError(std.fmt.comptimePrint(
                    "Node {s} missing input fields {s}",
                    .{ node.name, unhandled_inputs },
                ));
            }
        }
    }
};

pub const SystemSink = struct {
    output_node: []const u8,
    output_field: []const u8,
    system_field: []const u8,
};

pub const Blueprint = struct {
    nodes: []const NodeGraphBlueprintEntry,
    store: []const SystemSink,
    output: []const SystemSink,
};

const Input = struct {
    name: []const u8,
    type: type,
};

pub fn NodeGraph(
    comptime graph: Blueprint,
    comptime node_definitions: anytype,
) type {
    const NodeOutputs = build_type: {
        comptime var node_output_fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.nodes) |node| {
            const node_defn = @field(node_definitions, node.name);

            const function_definition = @typeInfo(@TypeOf(node_defn)).@"fn";
            const node_outputs = function_definition.return_type.?;
            const node_inputs = function_definition.params;
            const non_error_outputs = switch (@typeInfo(node_outputs)) {
                else => node_outputs,
                .error_union => |error_union| error_union.payload,
            };

            // Most outputs from node come from return structure of function.
            comptime var output_fields: []const std.builtin.Type.StructField =
                @typeInfo(non_error_outputs).@"struct".fields;

            // Input fields that are non-constant pointers are also considered outputs from this node.
            for (@typeInfo(
                node_inputs[node_inputs.len - 1].type.?,
            ).@"struct".fields) |input_field| switch (@typeInfo(input_field.type)) {
                else => {},
                .pointer => |pointer| if (!pointer.is_const) switch (pointer.size) {
                    else => {},
                    .One => {
                        output_fields = comptime output_fields ++ .{std.builtin.Type.StructField{
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
                },
            };

            const non_error_outputs_and_pointers = @Type(std.builtin.Type{ .@"struct" = .{
                .layout = .auto,
                .fields = output_fields,
                .decls = &.{},
                .is_tuple = false,
            } });

            node_output_fields = comptime node_output_fields ++ .{std.builtin.Type.StructField{
                .name = node.name[0.. :0],
                .type = non_error_outputs_and_pointers,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(non_error_outputs),
            }};
        }
        break :build_type @Type(std.builtin.Type{ .@"struct" = .{
            .layout = .auto,
            .fields = node_output_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };

    const NodesDirtyFlags = build_type: {
        comptime var fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.nodes) |node| {
            fields = comptime fields ++ .{std.builtin.Type.StructField{
                .name = node.name[0.. :0],
                .type = bool,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(bool),
            }};
        }
        break :build_type @Type(std.builtin.Type{ .@"struct" = .{
            .layout = .auto,
            .fields = fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };

    const NodesQueriedFlags = build_type: {
        var node_fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.nodes) |node| {
            const node_defn = @field(node_definitions, node.name);
            const node_params = @typeInfo(@TypeOf(node_defn)).@"fn".params;
            const node_input_fields = @typeInfo(node_params[node_params.len - 1].type.?).@"struct".fields;
            var fields: []const std.builtin.Type.StructField = &.{};
            inline for (node_input_fields) |field| {
                if (utils.queryable.getSourceOrNull(field.type) != null) {
                    fields = fields ++ .{std.builtin.Type.StructField{
                        .name = field.name,
                        .type = bool,
                        .alignment = @alignOf(bool),
                        .default_value = null,
                        .is_comptime = false,
                    }};
                }
            }
            node_fields = node_fields ++ .{std.builtin.Type.StructField{
                .name = node.name[0.. :0],
                .type = @Type(std.builtin.Type{ .@"struct" = .{
                    .layout = .auto,
                    .fields = fields,
                    .decls = &.{},
                    .is_tuple = false,
                } }),
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(bool),
            }};
        }
        break :build_type @Type(std.builtin.Type{ .@"struct" = .{
            .layout = .auto,
            .fields = node_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };

    var max_node_priority: u16 = 0;
    const node_priorities = precalculate: {
        var node_priorities = [_]u16{0} ** graph.nodes.len;
        const Node = struct { name: []const u8, priority: u16 };
        var next_nodes: []const Node = &.{};

        gather_initial_nodes: inline for (graph.nodes) |node| {
            if (node.input_links.len > 0)
                inline for (node.input_links) |link|
                    switch (link.source) {
                        .input_field => continue,
                        else => continue :gather_initial_nodes,
                    };
            next_nodes = comptime next_nodes ++ .{Node{ .name = node.name, .priority = 0 }};
        }

        inline while (next_nodes.len > 0) {
            const current_nodes = next_nodes;
            next_nodes = &.{};
            inline for (current_nodes) |current_node| {

                // Get this node's index from our definitions
                const node_index = for (graph.nodes, 0..) |node, index|
                    if (std.mem.eql(u8, node.name, current_node.name)) break index else continue;

                // Register this node with the priorities list (the final output we're looking for)
                node_priorities[node_index] = @max(node_priorities[node_index], current_node.priority);

                // Figure out what nodes connect to this current one and queue them up for next iteration with a priority + 1
                @setEvalBranchQuota(9000);
                inline for (graph.nodes) |next_node| {
                    if (is_next_connected: for (next_node.input_links) |link| {
                        switch (link.source) {
                            else => {},
                            .node => |input_node| if (std.mem.eql(
                                u8,
                                input_node.name,
                                current_node.name,
                            )) break :is_next_connected true,
                        }
                    } else break :is_next_connected false)
                        next_nodes = comptime next_nodes ++ .{Node{
                            .name = next_node.name,
                            .priority = current_node.priority + 1,
                        }};
                    max_node_priority = @max(max_node_priority, current_node.priority + 1);
                }
            }
        }
        break :precalculate node_priorities;
    };

    const node_order = precalculate: {
        comptime var node_order: []const u16 = &.{};
        @setEvalBranchQuota(9000);
        inline for (0..max_node_priority) |current_priority|
            inline for (node_priorities, 0..) |node_priority, node_index| {
                if (node_priority == current_priority)
                    node_order = comptime node_order ++ .{node_index};
            };
        break :precalculate node_order;
    };

    const Graph = struct {
        const Self = @This();
        pub const Definitions = node_definitions;

        allocator: std.mem.Allocator,
        store: SystemStore,
        store_arena: std.heap.ArenaAllocator,
        system_inputs: SystemInputs,
        nodes_arenas: [graph.nodes.len]std.heap.ArenaAllocator,
        nodes_outputs: NodeOutputs,
        nodes_dirty_flags: NodesDirtyFlags,
        nodes_queried_flags: NodesQueriedFlags,

        pub const SystemInputs = build_type: {
            var fields: []const std.builtin.Type.StructField = &.{};
            for (graph.nodes) |node|
                for (node.input_links) |link| switch (link.source) {
                    else => {},
                    .input_field => |input_field| {
                        const field_type = blk: {
                            const node_params = @typeInfo(
                                @TypeOf(@field(node_definitions, node.name)),
                            ).@"fn".params;
                            const output_node_type = node_params[node_params.len - 1].type.?;
                            break :blk for (@typeInfo(output_node_type).@"struct".fields) |field|
                                if (std.mem.eql(u8, field.name, input_field))
                                    break utils.queryable.getSourceOrNull(field.type) orelse field.type
                                else
                                    continue
                            else
                                @compileError(std.fmt.comptimePrint("Can't find the field {s} in type {any}", .{
                                    input_field,
                                    output_node_type,
                                }));
                        };
                        fields = fields ++ for (fields) |system_input|
                            if (std.mem.eql(u8, system_input.name, input_field)) break .{} else continue
                        else
                            .{std.builtin.Type.StructField{
                                .name = input_field[0.. :0],
                                .type = field_type,
                                .default_value = null,
                                .is_comptime = false,
                                .alignment = @alignOf(field_type),
                            }};
                    },
                };
            break :build_type @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };

        pub const PartialSystemInputs = build_type: {
            var fields: []const std.builtin.Type.StructField = &.{};
            for (@typeInfo(SystemInputs).@"struct".fields) |input_field| {
                fields = fields ++ .{std.builtin.Type.StructField{
                    .name = input_field.name[0.. :0],
                    .type = ?input_field.type,
                    .default_value = blk: {
                        const default_value: ?input_field.type = null;
                        break :blk @ptrCast(&default_value);
                    },
                    .is_comptime = false,
                    .alignment = @alignOf(?input_field.type),
                }};
            }
            break :build_type @Type(.{ .@"struct" = .{
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
                            if (std.mem.eql(u8, system_input_dirty.name, input_field))
                                break .{}
                            else
                                continue
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
            break :build_type @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };

        pub const SystemOutputs = build_type: {
            var fields: []const std.builtin.Type.StructField = &.{};
            outputs: for (graph.output) |output_defn| {
                const name = output_defn.system_field;
                const node_id = output_defn.output_node;
                const node = for (graph.nodes) |node|
                    if (std.mem.eql(u8, node.name, node_id)) break node else continue
                else
                    @compileError("Node not found " ++ node_id);
                const field_type = getOutputFieldTypeFromNode(node, output_defn.output_field);
                for (fields) |existing_field|
                    if (std.mem.eql(u8, existing_field.name, name))
                        continue :outputs;
                fields = fields ++ .{std.builtin.Type.StructField{
                    .name = name[0.. :0],
                    .type = ?field_type,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(?field_type),
                }};
            }
            break :build_type @Type(.{ .@"struct" = .{
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
                system_store_fields = system_store_fields ++ .{std.builtin.Type.StructField{
                    .name = name[0.. :0],
                    .type = field_type,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field_type),
                }};
            }
            break :build_type @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = system_store_fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };

        pub fn init(props: struct {
            allocator: std.mem.Allocator,
            inputs: SystemInputs,
            store: SystemStore,
        }) !Self {
            var self = Self{
                .allocator = props.allocator,
                .store = props.store,
                .store_arena = std.heap.ArenaAllocator.init(props.allocator),
                .system_inputs = props.inputs,
                .nodes_arenas = undefined,
                .nodes_outputs = undefined,
                .nodes_dirty_flags = undefined,
                .nodes_queried_flags = undefined,
            };
            inline for (graph.nodes, 0..) |node, index| {
                self.nodes_arenas[index] = std.heap.ArenaAllocator.init(props.allocator);
                @field(self.nodes_dirty_flags, node.name) = true;
                const queried_flags = &@field(self.nodes_queried_flags, node.name);
                inline for (@typeInfo(@TypeOf(queried_flags.*)).@"struct".fields) |field| {
                    @field(queried_flags, field.name) = true;
                }
            }
            return self;
        }

        fn getOutputFieldTypeFromNode(node: NodeGraphBlueprintEntry, field_name: []const u8) type {
            const node_outputs = for (@typeInfo(NodeOutputs).@"struct".fields) |field|
                if (!std.mem.eql(u8, field.name, node.name)) continue else break field.type
            else
                @compileError("Node not found " ++ node.name);
            const field_type = for (@typeInfo(node_outputs).@"struct".fields) |field|
                if (!std.mem.eql(u8, field.name, field_name)) continue else break field.type
            else
                @compileError("Field not found " ++ field_name ++ " in node " ++ node.name);
            return field_type;
        }

        pub fn dirtyFromInputs(self: *Self, system_inputs: PartialSystemInputs) SystemInputsDirtyFlags {
            var inputs_dirty: SystemInputsDirtyFlags = undefined;
            inline for (@typeInfo(SystemInputs).@"struct".fields) |field| {
                const field_name = field.name;
                const maybe_input = @field(system_inputs, field_name);
                const dirty = &@field(inputs_dirty, field_name);
                if (maybe_input) |input| {
                    dirty.* = !std.meta.eql(
                        input,
                        @field(self.system_inputs, field_name),
                    );
                    @field(self.system_inputs, field_name) = input;
                } else dirty.* = false;
            }
            return inputs_dirty;
        }

        pub fn update(self: *Self, system_inputs: PartialSystemInputs) !SystemOutputs {

            // Check inputs for changes...
            const inputs_dirty = self.dirtyFromInputs(system_inputs);

            // Process all nodes...
            inline for (node_order) |node_index| {
                const node = graph.nodes[node_index];
                const node_defn = @field(node_definitions, node.name);
                const node_params = @typeInfo(@TypeOf(node_defn)).@"fn".params;
                const NodeInputs = node_params[node_params.len - 1].type.?;
                const MutableInputs = utils.MutableInputs(node, NodeInputs);

                const function_params = @typeInfo(
                    @TypeOf(@field(node_definitions, node.function)),
                ).@"fn".params;

                node.validateLinkingAllParameters(function_params);

                const is_dirty = &@field(self.nodes_dirty_flags, node.name);

                var mutable_inputs: MutableInputs = undefined;
                var node_inputs: NodeInputs = undefined;
                inline for (node.input_links) |link| {
                    var is_field_dirty = false;
                    var node_input_field = switch (link.source) {
                        .input_field => |input_field| node_input: {
                            if (@field(inputs_dirty, input_field)) {
                                is_field_dirty = true;
                            }
                            break :node_input @field(self.system_inputs, input_field);
                        },
                        .store_field => |store_field| @field(self.store, store_field),
                        .node => |node_blueprint| input_field: {
                            const node_outputs = @field(self.nodes_outputs, node_blueprint.name);
                            const node_output = @field(node_outputs, node_blueprint.field);
                            if (@field(self.nodes_dirty_flags, node_blueprint.name)) {
                                is_field_dirty = true;
                            }
                            break :input_field node_output;
                        },
                    };
                    const target_input_field = &@field(node_inputs, link.field);
                    const TargetInputField = @TypeOf(target_input_field.*);
                    const value = if (@hasField(MutableInputs.Fields, link.field))
                        mutable_inputs.register(TargetInputField, link, &node_input_field)
                    else
                        node_input_field;
                    target_input_field.* = if (comptime utils.queryable.isValue(TargetInputField))
                        TargetInputField.initQueryable(
                            value,
                            &is_field_dirty,
                            &@field(@field(self.nodes_queried_flags, node.name), link.field),
                        )
                    else
                        value;

                    // Accumulate dirtiness on dirty fields
                    if (is_field_dirty) is_dirty.* = true;
                }

                const target = &@field(self.nodes_outputs, node.name);
                target.* = if (!is_dirty.*)
                    target.*
                else process_output: {
                    const node_arena = &self.nodes_arenas[node_index];

                    _ = node_arena.reset(.retain_capacity);

                    try mutable_inputs.duplicate(node_arena.allocator(), &node_inputs);

                    const function_output = @call(.auto, @field(
                        node_definitions,
                        node.function,
                    ), if (function_params.len == 1) .{
                        node_inputs,
                    } else .{
                        node_arena.allocator(),
                        node_inputs,
                    });

                    var node_output: @TypeOf(target.*) = undefined;

                    mutable_inputs.copyBack(node_inputs, &node_output);

                    node_output = utils.copyWith(
                        node_output,
                        switch (@typeInfo(@TypeOf(function_output))) {
                            else => function_output,
                            .error_union => try function_output,
                        },
                    );
                    break :process_output node_output;
                };
            }

            _ = self.store_arena.reset(.retain_capacity);

            // Copy over new store values...
            inline for (graph.store) |store_defn| {
                // TODO - Once we need to optimize, only copy values that have changed!
                const node_result = @field(self.nodes_outputs, store_defn.output_node);
                const result = @field(node_result, store_defn.output_field);
                @field(self.store, store_defn.system_field) = try utils.deepClone(
                    @TypeOf(result),
                    self.store_arena.allocator(),
                    result,
                );
            }

            // Output from system from select nodes...
            var system_outputs: SystemOutputs = undefined;
            inline for (@typeInfo(SystemOutputs).@"struct".fields) |output_field| {
                comptime var output_defns: []const SystemSink = &.{};
                inline for (graph.output) |output_defn| {
                    if (comptime std.mem.eql(u8, output_defn.system_field, output_field.name)) output_defns = output_defns ++ .{output_defn};
                }
                if (output_defns.len == 1) {
                    const output_defn = output_defns[0];
                    const target = &@field(system_outputs, output_field.name);
                    const is_dirty = @field(self.nodes_dirty_flags, output_defn.output_node);
                    if (!is_dirty) {
                        target.* = null;
                    } else {
                        const node_outputs = @field(self.nodes_outputs, output_defn.output_node);
                        const result = @field(node_outputs, output_defn.output_field);
                        target.* = try utils.deepClone(
                            @TypeOf(result),
                            self.store_arena.allocator(),
                            result,
                        );
                    }
                } else {
                    var any_dirty = false;
                    const OutputType = @typeInfo(output_field.type).optional.child;
                    const error_message = std.fmt.comptimePrint("Expected a slice type when combining node outputs - field {s}", .{output_field.name});
                    switch (@typeInfo(OutputType)) {
                        else => @compileError(error_message),
                        .pointer => |pointer| switch (pointer.size) {
                            else => @compileError(error_message),
                            .Slice => {},
                        },
                    }
                    var to_concat: [output_defns.len]OutputType = undefined;

                    inline for (output_defns, 0..) |output_defn, i| {
                        const is_dirty = @field(self.nodes_dirty_flags, output_defn.output_node);
                        to_concat[i] = blk: {
                            if (is_dirty) {
                                any_dirty = true;
                                const node_outputs = @field(self.nodes_outputs, output_defn.output_node);
                                break :blk @field(node_outputs, output_defn.output_field);
                            } else {
                                break :blk &.{};
                            }
                        };
                    }
                    if (any_dirty) {
                        @field(system_outputs, output_field.name) = try std.mem.concat(
                            self.store_arena.allocator(),
                            @typeInfo(OutputType).pointer.child,
                            &to_concat,
                        );
                    }
                }
            }

            // Set all nodes to not dirty
            inline for (node_order) |node_index| {
                const node = graph.nodes[node_index];
                const is_dirty = &@field(self.nodes_dirty_flags, node.name);
                is_dirty.* = false;
            }

            return system_outputs;
        }

        pub fn getDisplayDefinition() struct { blueprint: Blueprint, node_priorities: []const u16 } {
            return .{ .blueprint = graph, .node_priorities = &node_priorities };
        }

        pub fn deinit(self: Self) void {
            for (self.nodes_arenas) |arena| {
                arena.deinit();
            }
            self.store_arena.deinit();
        }
    };
    return Graph;
}
