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
    const case = std.meta.stringToEnum(NodesEnum, name) orelse {
        dumpMessage(try std.fmt.allocPrint(allocator, "unknown function: {s}\n", .{name}));
        return;
    };
    switch (case) {
        inline else => |fn_name| {
            const func = @field(Nodes, @tagName(fn_name));
            const args = try std.json.parseFromSlice(Args(func), allocator, args_string, .{});
            const result = try @call(.auto, func, args.value);
            dumpMessage(try std.json.stringifyAlloc(allocator, result, .{}));
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
        .ErrorUnion => |eu| typescriptTypeOf(eu.payload),
        .Pointer => |p| switch (p.size) {
            .One => typescriptTypeOf(p.child) ++ " | null",
            .Many, .Slice => typescriptTypeOf(p.child) ++ "[]",
            else => "any",
        },
        .Struct => |s| {
            var fields: []const u8 = &.{};
            for (s.fields, 0..) |field, i| {
                fields = fields ++ std.fmt.comptimePrint("{s}{s}: {s}", .{ if (i == 0) "" else ", ", field.name, typescriptTypeOf(field.type) });
            }
            return std.fmt.comptimePrint("{{ {s} }}", .{fields});
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
    inline for (@typeInfo(NodesEnum).Enum.fields) |field| {
        const node = @field(Nodes, field.name);
        dumpMessage(comptime typescriptTypeOf(@TypeOf(node)));
    }
}
