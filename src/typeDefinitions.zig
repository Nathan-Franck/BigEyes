const std = @import("std");
const utils = @import("./nodeUtils.zig");

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

pub const TypedArrayReference = struct {
    type: []const u8,
    pointer: u32,
    length: u32,
};

/// Recursively explores a structure for slices that are compatible with javascript typed arrays,
/// and replaces with a special shape that the front-end can directly use.
/// Supported typed arrays are:
/// Float32Array
/// Float64Array
/// Int8Array
/// Int16Array
/// Int32Array
/// NOT Uint8Array - since in Zig this is put aside for strings
pub fn DeepTypedArrayReferences(t: type) type {
    return switch (@typeInfo(t)) {
        else => t,
        .Array => |a| switch (a.child) {
            f32, f64, i8, i16, i32, u16, u32 => TypedArrayReference,
            else => @Type(.{ .Array = .{
                .len = a.len,
                .sentinel = a.sentinel,
                .child = DeepTypedArrayReferences(a.child),
            } }),
        },
        .Pointer => |p| switch (p.size) {
            .Many, .Slice => switch (p.child) {
                f32, f64, i8, i16, i32, u16, u32 => TypedArrayReference,
                else => @Type(.{ .Pointer = utils.copyWith(p, .{ .child = DeepTypedArrayReferences(p.child) }) }),
            },
            else => @Type(.{ .Pointer = utils.copyWith(p, .{ .child = DeepTypedArrayReferences(p.child) }) }),
        },
        .Struct => |s| blk: {
            var fields: []const std.builtin.Type.StructField = &.{};
            for (s.fields) |field| {
                const field_type = DeepTypedArrayReferences(field.type);
                fields = fields ++ .{std.builtin.Type.StructField{
                    .is_comptime = field.is_comptime,
                    .name = field.name,
                    .type = field_type,
                    .alignment = @alignOf(field_type),
                    .default_value = if (field_type == field.type)
                        field.default_value
                    else
                        null,
                }};
            }
            break :blk @Type(.{ .Struct = utils.copyWith(s, .{ .fields = fields }) });
        },
        .Union => |u| blk: {
            var fields: []const std.builtin.Type.UnionField = &.{};
            for (u.fields) |field| {
                fields = fields ++ .{utils.copyWith(field, .{
                    .type = DeepTypedArrayReferences(field.type),
                })};
            }
            break :blk @Type(.{ .Union = utils.copyWith(u, .{ .fields = fields }) });
        },
    };
}

test "DeepTypedArrayReferences" {
    {
        const actual = DeepTypedArrayReferences([]f32);
        const expected = TypedArrayReference;
        try std.testing.expect(actual == expected);
    }

    { // Struct
        const t = DeepTypedArrayReferences(struct { a: []f32, b: []const u8 });
        _ = t{ .a = .{ .type = "Float32Array", .pointer = 0, .length = 0 }, .b = "Hello World!" };
    }

    { // Slice
        const t = DeepTypedArrayReferences(struct { a: []const []f32 });
        _ = t{ .a = &.{.{ .type = "Float32Array", .pointer = 0, .length = 0 }} };
    }

    { // Array
        const t = DeepTypedArrayReferences(struct { a: [2][]f32 });
        _ = t{ .a = .{ .{ .type = "Float32Array", .pointer = 0, .length = 0 }, .{ .type = "Float32Array", .pointer = 0, .length = 0 } } };
    }
    { // Union
        const t = DeepTypedArrayReferences(union { a: []f32, b: []const u8 });
        _ = t{ .a = .{ .type = "Float32Array", .pointer = 0, .length = 0 } };
    }
}

pub fn main() !void {
    const interface = @import("./wasmInterface.zig").interface;
    const allocator = std.heap.page_allocator;
    try build_typescript_type(allocator, interface, "src", "../web/gen/wasmInterface.d.ts");
}

pub fn build_typescript_type(allocator: std.mem.Allocator, interface: anytype, folder_path: []const u8, file_name: []const u8) !void {
    const typeInfo = comptime typescriptTypeOf(interface, .{ .first = true });
    const contents = "export type WasmInterface = " ++ typeInfo;
    const file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ folder_path, file_name });
    std.fs.cwd().makeDir(folder_path) catch {};
    std.fs.cwd().deleteFile(file_path) catch {};
    const file = try std.fs.cwd().createFile(file_path, .{});
    try file.writeAll(contents);
    std.debug.print("Wrote file to {s}\n", .{file_path});
}
