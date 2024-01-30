const subdiv = @import("./subdiv.zig");
const std = @import("std");

pub const Nodes = struct {
    pub fn helloSlice(faces: []subdiv.Face) ![]subdiv.Face {
        return faces;
    }

    pub fn testSubdiv(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        const allocator = std.heap.page_allocator;
        const result = try subdiv.Polygon(.Face).cmcSubdiv(
            allocator,
            points,
            faces,
        );
        return result;
    }

    pub fn testSubdiv2(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv3(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv4(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv5(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv6(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv7(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv8(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv9(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv10(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv11(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv12(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv13(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv22(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv23(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv24(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv25(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv26(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv27(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv28(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv29(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv210(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv211(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv212(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv213(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv32(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv33(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv34(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv35(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv36(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv37(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv38(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv39(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv310(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv311(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv312(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv313(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv322(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv323(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv324(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv325(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv326(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv327(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv328(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv329(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv3210(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv3211(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv3212(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
    }

    pub fn testSubdiv3213(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        _ = faces; // autofix
        _ = points; // autofix
        return error.APIUnavailable;
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
