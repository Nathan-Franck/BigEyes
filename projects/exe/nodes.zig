const subdiv = @import("./subdiv.zig");
const std = @import("std");

pub const Nodes = struct {
    const StructArray = []struct { a: bool, b: []u8 };
    pub fn helloStructArray(state: StructArray) !StructArray {
        return state;
    }

    pub fn helloSlice(state: []subdiv.Face, options: struct { saySomethingNice: bool }) ![]const u8 {
        _ = state; // autofix
        return if (options.saySomethingNice) "hello beautiful!" else "goodbye, cruel world";
    }

    pub fn subdivideFaces(state: struct { faces: []subdiv.Face, points: []subdiv.Point }) !subdiv.Mesh {
        const allocator = std.heap.page_allocator;
        const result = try subdiv.Polygon(.Face).cmcSubdiv(
            allocator,
            state.points,
            state.faces,
        );
        return result;
    }
};
pub const NodesEnum = DeclsToEnum(Nodes);

pub fn DeclsToEnum(comptime container: type) type {
    const info = @typeInfo(container);
    var enum_fields: []const std.builtin.Type.EnumField = &.{};
    for (info.Struct.decls, 0..) |struct_decl, i| {
        enum_fields = enum_fields ++ &[_]std.builtin.Type.EnumField{.{
            .name = struct_decl.name,
            .value = i,
        }};
    }
    return @Type(.{ .Enum = .{
        .tag_type = u32,
        .fields = enum_fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });
}
pub fn Args(comptime func: anytype) type {
    const ParamInfo = @typeInfo(@TypeOf(func)).Fn.params;
    var fields: []const std.builtin.Type.StructField = &.{};
    for (ParamInfo, 0..) |param_info, i| {
        fields = fields ++ &[_]std.builtin.Type.StructField{.{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = param_info.type.?,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(param_info.type.?),
        }};
    }
    return @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = true,
    } });
}