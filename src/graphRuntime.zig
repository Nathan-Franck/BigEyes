const std = @import("std");
const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;

const Input = struct {
    name: []const u8,
    type: type,
};

fn Build(comptime graph: Blueprint, comptime node_definitions: anytype) type {
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
    var max_node_priority: u16 = 0;
    const node_priorities = pre_calculate: {
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
        break :pre_calculate node_priorities;
    };
    comptime var node_order: []const u16 = &.{};
    inline for (0..max_node_priority) |priority| {
        inline for (graph.nodes, 0..) |node, node_index| {
            if (node_priorities[node_index] == priority) {
                @compileLog(std.fmt.comptimePrint("node: {any}", .{node.uniqueID()}));
                node_order = comptime node_order ++ .{node_index};
            }
        }
    }
    @compileLog(std.fmt.comptimePrint("node_orders: {any}", .{node_order}));
    @compileLog("inputs: {}", @import("./typeDefinitions.zig").typescriptTypeOf(SystemInputs, .{}));
    @compileLog("outputs: {}", @import("./typeDefinitions.zig").typescriptTypeOf(SystemOutputs, .{}));
    return struct {
        fn update(inputs: SystemInputs) SystemOutputs {
            _ = inputs;
            @panic("TODO: Implement");
        }
    };
}

test "Build" {
    const result = Build(node_graph_blueprint, NodeDefinitions);
    _ = result;
}
