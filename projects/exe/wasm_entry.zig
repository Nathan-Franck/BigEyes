const std = @import("std");
const subdiv = @import("subdiv");

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

export fn allocUint8(length: u32) [*]const u8 {
    const slice = std.heap.page_allocator.alloc(u8, length) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

extern fn messageFromWasm(source_pointer: [*]const u8, source_len: u32) void;

extern fn errorFromWasm(source_pointer: [*]const u8, source_len: u32) void;

fn dumpMessage(source: []const u8) void {
    messageFromWasm(source.ptr, source.len);
}

fn dumpError(source: []const u8) void {
    errorFromWasm(source.ptr, source.len);
}

fn callWithJsonErr(name_ptr: [*]const u8, name_len: u32, args_ptr: [*]const u8, args_len: u32) !void {
    const allocator = std.heap.page_allocator;
    const name: []const u8 = name_ptr[0..name_len];
    const args_string: []const u8 = args_ptr[0..args_len];
    _ = args_string; // autofix
    const case = std.meta.stringToEnum(NodesEnum, name) orelse {
        dumpError(try std.fmt.allocPrint(allocator, "unknown function: {s}\n", .{name}));
        return;
    };
    switch (case) {
        inline else => |fn_name| {
            const func = @field(Nodes, @tagName(fn_name));
            _ = func; // autofix
            // const args = try std.json.parseFromSlice(Args(func), allocator, args_string, .{});
            // const result = try @call(.auto, func, args.value);
            // dumpMessage(try std.json.stringifyAlloc(allocator, result, .{}));
        },
    }
}

export fn callWithJson(name_ptr: [*]const u8, name_len: u32, args_ptr: [*]const u8, args_len: u32) void {
    const allocator = std.heap.page_allocator;
    callWithJsonErr(name_ptr, name_len, args_ptr, args_len) catch |err| {
        dumpError(std.fmt.allocPrint(allocator, "error: {?}\n", .{err}) catch unreachable);
        return;
    };
}

fn typescriptTypeOf(comptime from_type: anytype) []const u8 {
    return comptime switch (@typeInfo(from_type)) {
        .Int => "number",
        .Float => "number",
        .Array => |a| typescriptTypeOf(a.child) ++ "[]",
        .Vector => |v| {
            const chlid = typescriptTypeOf(v.child);
            var result: []const u8 = &.{};
            for (0..v.len) |i| {
                result = result ++ std.fmt.comptimePrint("{s}{s}", .{ if (i == 0) "" else ", ", chlid });
            }
            return std.fmt.comptimePrint("[ {s} ]", .{result});
        },
        .ErrorUnion => |eu| typescriptTypeOf(eu.payload), // Ignore the existence of errors for now...
        .Pointer => |p| switch (p.size) {
            .Many, .Slice => typescriptTypeOf(p.child) ++ "[]",
            else => "unknown",
        },
        .Struct => |s| {
            var decls: []const u8 = &.{};
            for (s.decls, 0..) |decl, i| {
                decls = decls ++ std.fmt.comptimePrint("{s}{s}: {s}", .{ if (i == 0) "" else ", ", decl.name, typescriptTypeOf(@TypeOf(@field(from_type, decl.name))) });
            }
            var fields: []const u8 = &.{};
            for (s.fields, 0..) |field, i| {
                fields = fields ++ std.fmt.comptimePrint("{s}{s}: {s}", .{ if (i == 0) "" else ", ", field.name, typescriptTypeOf(field.type) });
            }
            return std.fmt.comptimePrint("{{ {s}{s} }}", .{ if (decls.len > 0) decls ++ ", " else "", fields });
        },
        .Fn => |f| {
            var params: []const u8 = &.{};
            for (f.params, 0..) |param, i| {
                params = params ++ std.fmt.comptimePrint("{s}{d}: {s}", .{ if (i == 0) "" else ", ", i, typescriptTypeOf(param.type.?) });
            }
            return std.fmt.comptimePrint("({s}) => {s}", .{ params, typescriptTypeOf(f.return_type.?) });
        },
        else => "unknown",
    };
}

export fn dumpNodeTypeInfo() void {
    const allocator = std.heap.page_allocator;
    _ = allocator; // autofix

    dumpMessage(comptime typescriptTypeOf(Nodes));
}
