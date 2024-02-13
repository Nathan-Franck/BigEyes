const Blueprint = @import("./interactiveNodeBuilderBlueprint.zig").Blueprint;
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");
const std = @import("std");

const Input = struct {
    name: []const u8,
    type: type,
};

fn Build(comptime graph: Blueprint, comptime node_definitions: anytype) void {
    const SystemInputs = build_type: {
        comptime var system_input_fields: []const std.builtin.Type.StructField = &.{};
        inline for (graph.nodes) |node|
            inline for (node.input_links) |link|
                switch (link) {
                    else => {},
                    .input => |input| {
                        const field_name = if (input.system_field) |system_field| system_field else input.input_field;
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
    @compileLog("inputs: {}", @import("./typeDefinitions.zig").typescriptTypeOf(SystemInputs, .{}));
}

test "Build" {
    const result = Build(node_graph_blueprint, NodeDefinitions);
    _ = result;
}
