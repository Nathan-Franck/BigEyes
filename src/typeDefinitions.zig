const std = @import("std");

pub inline fn typescriptTypeOf(comptime from_type: anytype, comptime options: struct { first: bool = false }) []const u8 {
    return comptime switch (@typeInfo(from_type)) {
        .Bool => "boolean",
        .Void => "void",
        .Int => "number",
        .Float => "number",
        .Optional => |optional_info| typescriptTypeOf(optional_info.child, .{}) ++ " | null",
        .Array => |array_info| typescriptTypeOf(array_info.child, .{}) ++ "[]",
        .Vector => |vector_info| {
            const child = typescriptTypeOf(vector_info.child, .{});
            var result: []const u8 = &.{};
            for (0..vector_info.len) |i| {
                result = result ++ std.fmt.comptimePrint("{s}{s}", .{ if (i == 0) "" else ", ", child });
            }
            return std.fmt.comptimePrint("[{s}]", .{result});
        },
        .ErrorUnion => |eu| typescriptTypeOf(eu.payload, .{}), // Ignore the existence of errors for now...
        .Pointer => |pointer| switch (pointer.size) {
            .Many, .Slice => if (pointer.child == u8)
                "string"
            else
                typescriptTypeOf(pointer.child, .{}) ++ "[]",
            else => "unknown",
        },
        .Enum => |enum_info| {
            var result: []const u8 = &.{};
            for (enum_info.fields, 0..) |field, i| {
                result = result ++ std.fmt.comptimePrint("{s}\"{s}\"", .{
                    if (i == 0) "" else " | ",
                    field.name,
                });
            }
            return result;
        },
        .Union => |union_info| {
            var result: []const u8 = &.{};
            for (union_info.fields, 0..) |field, i| {
                result = result ++ std.fmt.comptimePrint("{s}{{ {s}: {s} }}", .{
                    if (i == 0) "" else " | ",
                    field.name,
                    typescriptTypeOf(field.type, .{}),
                });
            }
            return result;
        },
        .Struct => |struct_info| {
            var decls: []const u8 = &.{};
            for (struct_info.decls, 0..) |decl, i| {
                decls = decls ++ std.fmt.comptimePrint("{s}{s}{s}: {s}", .{
                    if (i == 0) "" else ", ",
                    if (options.first) "\n\t" else "",
                    decl.name,
                    typescriptTypeOf(@TypeOf(@field(from_type, decl.name)), .{}),
                });
            }
            var fields: []const u8 = &.{};
            for (struct_info.fields, 0..) |field, i| {
                const default = .{ field.type, false };
                const field_type, const is_optional = switch (@typeInfo(field.type)) {
                    else => default,
                    .Optional => |field_optional_info| if (field.default_value) |_| .{ field_optional_info.child, true } else default,
                };
                fields = fields ++ std.fmt.comptimePrint("{s}{s}{s}{s}: {s}", .{
                    if (i == 0) "" else ", ",
                    if (options.first) "\n\t" else "",
                    field.name,
                    if (is_optional) "?" else "",
                    typescriptTypeOf(field_type, .{}),
                });
            }
            const result = std.fmt.comptimePrint("{{{s}{s}{s}{s}}}", .{
                if (options.first) "" else " ",
                if (decls.len > 0) decls ++ ", " else "",
                fields,
                if (options.first) "\n" else " ",
            });
            return result;
        },
        .Fn => |function_info| {
            var params: []const u8 = &.{};
            for (function_info.params, 0..) |param, i| {
                params = params ++ std.fmt.comptimePrint("{s}arg{d}: {s}", .{ if (i == 0) "" else ", ", i, typescriptTypeOf(param.type.?, .{}) });
            }
            return std.fmt.comptimePrint("({s}) => {s}", .{ params, typescriptTypeOf(function_info.return_type.?, .{}) });
        },
        else => std.fmt.comptimePrint("unknown /** zig type is {any} **/", .{@typeInfo(from_type)}),
    };
}

pub fn main() !void {
    const typeInfo = comptime typescriptTypeOf(@import("./wasmInterface.zig").interface, .{ .first = true });
    const contents = "export type WasmInterface = " ++ typeInfo;
    std.fs.cwd().makeDir("web/gen") catch {};
    std.fs.cwd().deleteFile("web/gen/wasmInterface.d.ts") catch {};
    const file = try std.fs.cwd().createFile("web/gen/wasmInterface.d.ts", .{});
    try file.writeAll(contents);
}
