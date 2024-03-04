const std = @import("std");
const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;

const Input = struct {
    name: []const u8,
    type: type,
};

fn Build(allocator: std.mem.Allocator, comptime graph: Blueprint, comptime node_definitions: anytype) type {
    const SystemInputs = build_type: {
        comptime var system_input_fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.nodes) |node|
            inline for (node.input_links) |link|
                switch (link) {
                    else => {},
                    .input => |input| {
                        const field_name = input.uniqueID();
                        const node_params = @typeInfo(@TypeOf(@field(node_definitions, node.uniqueID()))).Fn.params;
                        const field_type = comptime for (@typeInfo(node_params[node_params.len - 1].type.?).Struct.fields) |field|
                            if (std.mem.eql(u8, field.name, field_name)) break field.type else continue
                        else
                            unreachable; // TODO: Provide a useful compiler error about how blueprint and node defn's disagree.
                        system_input_fields = comptime system_input_fields ++ for (system_input_fields) |system_input|
                            if (std.mem.eql(u8, system_input.name, input.input_field)) break .{} else continue
                        else
                            .{.{
                                .name = field_name[0.. :0],
                                .type = field_type,
                                .default_value = null,
                                .is_comptime = false,
                                .alignment = @alignOf(field_type),
                            }};
                    },
                };
        break :build_type @Type(.{ .Struct = .{
            .layout = .Auto,
            .fields = system_input_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };
    const SystemOutputs = build_type: {
        comptime var system_output_fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.output) |output_defn| {
            const name = output_defn.uniqueID();
            const node_id = output_defn.output_node;
            const node = comptime for (graph.nodes) |node|
                if (std.mem.eql(u8, node.uniqueID(), node_id)) break node else continue
            else
                @compileError("Node not found " ++ node_id);
            const node_outputs = @typeInfo(@TypeOf(@field(node_definitions, node.uniqueID()))).Fn.return_type.?;
            const field_type = comptime for (@typeInfo(node_outputs).Struct.fields) |field|
                if (std.mem.eql(u8, field.name, output_defn.system_field)) break field.type else continue
            else
                unreachable; // TODO: Provide a useful compiler error about how blueprint and node defn's disagree.
            system_output_fields = comptime system_output_fields ++ .{.{
                .name = name[0.. :0],
                .type = field_type,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(field_type),
            }};
        }
        break :build_type @Type(.{ .Struct = .{
            .layout = .Auto,
            .fields = system_output_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };
    const SystemStore = build_type: {
        // EXAMPLE OF HOW TO BUILD A STORE in the blueprint
        // .store = &.{
        //     .{ .system_field = "context_menu", .output_node = "ContextMenuInteraction" },
        //     .{ .system_field = "active_node", .output_node = "NodeInteraction" },
        //     .{ .system_field = "camera", .output_node = "CameraControls" },
        //     .{ .system_field = "blueprint", .output_node = "NodeFormatting" },
        // },
        const store_fields = graph.store;
        comptime var system_store_fields: []const std.builtin.Type.StructField = &.{};
        inline for (store_fields) |store_field| {
            const name = store_field.system_field;
            const node_id = store_field.output_node;
            const node = comptime for (graph.nodes) |node|
                if (std.mem.eql(u8, node.uniqueID(), node_id)) break node else continue
            else
                @compileError("Node not found " ++ node_id);
            const node_outputs = @typeInfo(@TypeOf(@field(node_definitions, node.uniqueID()))).Fn.return_type.?;
            const field_type = comptime for (switch (@typeInfo(node_outputs)) {
                .ErrorUnion => |error_union| @typeInfo(error_union.payload).Struct.fields,
                .Struct => |the_struct| the_struct.fields,
                else => @compileError("Invalid output type, expected struct or error union with a struct"),
            }) |field|
                if (std.mem.eql(u8, field.name, store_field.system_field)) break field.type else continue
            else
                @compileError("Field not found " ++ store_field.system_field ++ " in " ++ node_id);
            system_store_fields = comptime system_store_fields ++ .{.{
                .name = name[0.. :0],
                .type = field_type,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(field_type),
            }};
        }
        break :build_type @Type(.{ .Struct = .{
            .layout = .Auto,
            .fields = system_store_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };
    const NodeOutputs = build_type: {
        comptime var node_output_fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.nodes) |node| {
            const node_defn = @field(node_definitions, node.uniqueID());
            const node_outputs = @typeInfo(@TypeOf(node_defn)).Fn.return_type.?;
            node_output_fields = comptime node_output_fields ++ .{.{
                .name = node.uniqueID()[0.. :0],
                .type = node_outputs,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(node_outputs),
            }};
        }
        break :build_type @Type(.{ .Struct = .{
            .layout = .Auto,
            .fields = node_output_fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };
    const node_order = precalculate: {
        var max_node_priority: u16 = 0;
        var node_priorities = [_]u16{0} ** graph.nodes.len;
        var next_nodes: []const struct { unique_id: []const u8, priority: u16 } = &.{};
        gather_initial_nodes: inline for (graph.nodes) |node| {
            inline for (node.input_links) |link| switch (link) {
                else => {},
                .input => {
                    next_nodes = comptime next_nodes ++ .{.{ .unique_id = node.uniqueID(), .priority = 0 }};
                    continue :gather_initial_nodes;
                },
            };
        }
        inline while (next_nodes.len > 0) {
            const current_nodes = next_nodes;
            next_nodes = &.{};
            inline for (current_nodes) |current_node| {
                const node_index = for (graph.nodes, 0..) |node, index|
                    if (std.mem.eql(u8, node.uniqueID(), current_node.unique_id)) break index else continue
                else
                    unreachable;
                node_priorities[node_index] = @max(node_priorities[node_index], current_node.priority);
                inline for (graph.nodes) |node|
                    if (std.mem.eql(u8, node.uniqueID(), current_node.unique_id))
                        inline for (graph.nodes) |next_node| {
                            if (is_output_node: for (next_node.input_links) |input_link| switch (input_link) {
                                else => continue,
                                .node => |input_node| if (std.mem.eql(u8, input_node.from, current_node.unique_id)) break :is_output_node true else continue,
                            } else break :is_output_node false)
                                next_nodes = comptime next_nodes ++ .{.{
                                    .unique_id = next_node.uniqueID(),
                                    .priority = current_node.priority + 1,
                                }};
                            max_node_priority = @max(max_node_priority, current_node.priority + 1);
                        };
            }
        }
        comptime var node_order: []const u16 = &.{};
        inline for (0..max_node_priority) |current_priority| {
            inline for (node_priorities, 0..) |node_priority, node_index| {
                if (node_priority == current_priority)
                    node_order = comptime node_order ++ .{node_index};
            }
        }
        break :precalculate node_order;
    };
    const nodes = NodeDefinitions{ .allocator = allocator };
    return struct {
        store: SystemStore,
        fn update(inputs: SystemInputs) SystemOutputs {
            var node_outputs: NodeOutputs = undefined;
            inline for (node_order) |node_index| {
                const node = graph.nodes[node_index];
                const node_defn = @field(node_definitions, node.uniqueID());
                const node_params = @typeInfo(@TypeOf(node_defn)).Fn.params;
                const NodeInputs = node_params[node_params.len - 1].type.?;
                var node_inputs: NodeInputs = undefined;
                inline for (node.input_links) |link| {
                    switch (link) {
                        else => {},
                        .input => |input| {
                            @field(node_inputs, input.uniqueID()) = @field(inputs, input.input_field);
                        },
                        .node => |node_blueprint| {
                            const node_output = @field(node_outputs, node_blueprint.from);
                            @field(node_inputs, node_blueprint.uniqueID()) = node_output;
                        },
                        .store => |store| {
                            @field(node_inputs, store.uniqueID()) = @field(inputs.store, store.system_field);
                        },
                    }
                }
                const node_output = @call(.auto, @field(nodes, node.name), node_inputs);
                @field(node_outputs, node.uniqueID()) = node_output;
            }
        }
    };
}

test "Build" {
    const allocator = std.heap.page_allocator;
    const result = Build(allocator, node_graph_blueprint, NodeDefinitions);
    _ = result.update(.{
        .event = null,
        .recieved_blueprint = null,
        .keyboard_modifiers = .{ .shift = false, .alt = false, .control = false, .super = false },
    });
}
