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
            const ReturnType = DeepTypedArrayReferences(function_info.return_type.?).type;
            return std.fmt.comptimePrint("({s}) => {s}", .{ params, typescriptTypeOf(ReturnType, .{}) });
        },
        else => std.fmt.comptimePrint("unknown /** zig type is {any} **/", .{@typeInfo(from_type)}),
    };
}

/// Recursively explores a structure for slices that are compatible with javascript typed arrays,
/// and replaces with a special shape that the front-end can directly use.
///
/// Supported typed arrays are:
/// * Float32Array
/// * Float64Array
/// * Int8Array
/// * Int16Array
/// * Int32Array
/// * NOT Uint8Array - since in Zig this is put aside for strings
pub fn deepTypedArrayReferences(t: type, allocator: std.mem.Allocator, data: t) !DeepTypedArrayReferences(t).type {
    if (!DeepTypedArrayReferences(t).changed) {
        return data;
    }
    return switch (@typeInfo(t)) {
        else => data,
        .ErrorUnion => try deepTypedArrayReferences(try data),
        .Optional => |op| if (data) |non_null_data| try deepTypedArrayReferences(op.child, allocator, non_null_data) else null,
        .Union => |u| blk: {
            inline for (u.fields, 0..) |field, i| if (i == @intFromEnum(data)) {
                break :blk @unionInit(
                    DeepTypedArrayReferences(t).type,
                    field.name,
                    try deepTypedArrayReferences(field.type, allocator, @field(data, field.name)),
                );
            };
            @panic("awful bonus");
        },
        .Struct => |s| blk: {
            var new_data: DeepTypedArrayReferences(t).type = undefined;
            inline for (s.fields) |field| {
                @import("wasm_entry.zig").dumpDebugLog(field.name);
                const result = try deepTypedArrayReferences(field.type, allocator, @field(data, field.name));
                @field(new_data, field.name) = result;
            }
            break :blk new_data;
        },
        .Array => |a| switch (a.child) {
            else => blk: {
                var elements = [a.len]a.child;
                for (data, 0..) |elem, idx| {
                    elements[idx] = try deepTypedArrayReferences(a.child, allocator, elem);
                }
                break :blk elements.items;
            },
            f32, f64, i8, i16, i32, u8, u16, u32 => .{
                .ptr = @intFromPtr(&data),
                .len = data.len * @sizeOf(a.child),
                .type = switch (a.child) {
                    f32 => .Float32Array,
                    f64 => .Float64Array,
                    i8 => .Int8Array,
                    i16 => .Int16Array,
                    i32 => .Int32Array,
                    u8 => .Uint8Array,
                    u16 => .Uint16Array,
                    u32 => .Uint32Array,
                    else => unreachable,
                },
            },
        },
        .Pointer => |p| switch (p.size) {
            else => blk: {
                var elements = std.ArrayList(DeepTypedArrayReferences(p.child).type).init(allocator);
                for (data) |elem| {
                    try elements.append(try deepTypedArrayReferences(p.child, allocator, elem));
                }
                break :blk elements.items;
            },
            .Many, .Slice => switch (p.child) {
                else => blk: {
                    var elements = std.ArrayList(DeepTypedArrayReferences(p.child).type).init(allocator);
                    @import("wasm_entry.zig").dumpDebugLog(try std.fmt.allocPrint(allocator, "{d}", .{data.len}));
                    for (data) |elem| {
                        try elements.append(try deepTypedArrayReferences(p.child, allocator, elem));
                    }
                    break :blk elements.items;
                },
                f32, f64, i8, i16, i32, u8, u16, u32 => .{
                    .ptr = @intFromPtr(@as(*const p.child, @ptrCast(data))),
                    .len = data.len * @sizeOf(p.child),
                    .type = switch (p.child) {
                        f32 => .Float32Array,
                        f64 => .Float64Array,
                        i8 => .Int8Array,
                        i16 => .Int16Array,
                        i32 => .Int32Array,
                        u8 => .Uint8Array,
                        u16 => .Uint16Array,
                        u32 => .Uint32Array,
                        else => unreachable,
                    },
                },
            },
        },
    };
}

pub fn TypedArrayReference(type_enum: type) type {
    return struct {
        type: type_enum,
        ptr: usize,
        len: usize,
    };
}

pub fn DeepTypedArrayReferences(t: type) struct { type: type, changed: bool = false } {
    return switch (@typeInfo(t)) {
        else => .{ .type = t },
        .ErrorUnion => |eu| DeepTypedArrayReferences(eu.payload),
        .Optional => |op| blk: {
            const result = DeepTypedArrayReferences(op.child);
            break :blk if (!result.changed) .{ .type = t } else .{ .changed = true, .type = ?result.type };
        },
        .Union => |u| blk: {
            var fields: []const std.builtin.Type.UnionField = &.{};
            var changed = false;
            for (u.fields) |field| {
                const new_field = DeepTypedArrayReferences(field.type);
                changed = changed or new_field.changed;
                fields = fields ++ .{utils.copyWith(field, .{
                    .type = new_field.type,
                })};
            }
            break :blk if (!changed)
                .{ .type = t }
            else
                .{ .changed = true, .type = @Type(.{ .Union = utils.copyWith(u, .{ .fields = fields }) }) };
        },
        .Struct => |s| blk: {
            var fields: []const std.builtin.Type.StructField = &.{};
            var changed = false;
            for (s.fields) |field| {
                const new_field = DeepTypedArrayReferences(field.type);
                changed = changed or new_field.changed;
                fields = fields ++ .{std.builtin.Type.StructField{
                    .is_comptime = field.is_comptime,
                    .name = field.name,
                    .type = new_field.type,
                    .alignment = @alignOf(new_field.type),
                    .default_value = if (new_field.type == field.type)
                        field.default_value
                    else
                        null,
                }};
            }
            break :blk if (!changed)
                .{ .type = t }
            else
                .{ .changed = true, .type = @Type(.{ .Struct = utils.copyWith(s, .{ .fields = fields }) }) };
        },
        .Array => |a| switch (a.child) {
            f32, f64, i8, i16, i32, u8, u16, u32 => .{
                .changed = true,
                .type = switch (a.child) {
                    else => unreachable,
                    f32 => TypedArrayReference(enum { Float32Array }),
                    f64 => TypedArrayReference(enum { Float64Array }),
                    i8 => TypedArrayReference(enum { Int8Array }),
                    i16 => TypedArrayReference(enum { Int16Array }),
                    i32 => TypedArrayReference(enum { Int32Array }),
                    u8 => TypedArrayReference(enum { Uint8Array }),
                    u16 => TypedArrayReference(enum { Uint16Array }),
                    u32 => TypedArrayReference(enum { Uint32Array }),
                },
            },

            else => blk: {
                const child = DeepTypedArrayReferences(a.child);
                break :blk if (!child.changed)
                    .{ .type = t }
                else
                    .{ .changed = true, .type = @Type(.{ .Array = .{ .len = a.len, .sentinel = a.sentinel, .child = child.type } }) };
            },
        },
        .Pointer => |p| switch (p.size) {
            .Many, .Slice => switch (p.child) {
                f32, f64, i8, i16, i32, u8, u16, u32 => .{
                    .changed = true,
                    .type = switch (p.child) {
                        else => unreachable,
                        f32 => TypedArrayReference(enum { Float32Array }),
                        f64 => TypedArrayReference(enum { Float64Array }),
                        i8 => TypedArrayReference(enum { Int8Array }),
                        i16 => TypedArrayReference(enum { Int16Array }),
                        i32 => TypedArrayReference(enum { Int32Array }),
                        u8 => TypedArrayReference(enum { Uint8Array }),
                        u16 => TypedArrayReference(enum { Uint16Array }),
                        u32 => TypedArrayReference(enum { Uint32Array }),
                    },
                },
                else => blk: {
                    const child = DeepTypedArrayReferences(p.child);
                    break :blk if (!child.changed)
                        .{ .type = t }
                    else
                        .{ .changed = true, .type = @Type(.{ .Pointer = utils.copyWith(p, .{ .child = child.type }) }) };
                },
            },
            else => blk: {
                const child = DeepTypedArrayReferences(p.child);
                break :blk if (!child.changed)
                    .{ .type = t }
                else
                    .{ .changed = true, .type = @Type(.{ .Pointer = utils.copyWith(p, .{ .child = child.type }) }) };
            },
        },
    };
}

test "DeepTypedArrayReferences" {
    // {
    //     const actual = DeepTypedArrayReferences([]f32).type;
    //     const expected = TypedArrayReference(enum { Float32Array });
    //     try std.testing.expect(actual == expected);
    // }

    // { // Struct
    //     const t = DeepTypedArrayReferences(struct { a: []f32, b: []const u8 }).type;
    //     _ = t{ .a = .{ .type = .Float32Array, .ptr = 0, .len = 0 }, .b = "Hello World!" };
    // }

    { // Slice
        const t = DeepTypedArrayReferences(struct { a: []const []f32 }).type;
        _ = t{ .a = &.{.{ .type = .Float32Array, .ptr = 0, .len = 0 }} };
    }

    { // Array
        const t = DeepTypedArrayReferences(struct { a: [2][]f32 }).type;
        _ = t{ .a = .{ .{ .type = .Float32Array, .ptr = 0, .len = 0 }, .{ .type = .Float32Array, .ptr = 0, .len = 0 } } };
    }

    { // Array of U8
        const t = DeepTypedArrayReferences(struct { a: [2][]u8 }).type;
        _ = t{ .a = .{ .{ .type = .Uint8Array, .ptr = 0, .len = 0 }, .{ .type = .Uint8Array, .ptr = 0, .len = 0 } } };
    }

    { // Union
        const t = DeepTypedArrayReferences(union { a: []f32, b: []const u8 }).type;
        _ = t{ .a = .{ .type = .Float32Array, .ptr = 0, .len = 0 } };
    }

    { // Optional
        const t = DeepTypedArrayReferences(union { a: ?[]f32, b: []const u8 }).type;
        _ = t{ .a = .{ .type = .Float32Array, .ptr = 0, .len = 0 } };
    }

    { // Deep type equality when nothing is referenceable
        const original = struct { a: []const u7, b: []const u7 };
        const transfromed = DeepTypedArrayReferences(original).type;
        try std.testing.expect(original == transfromed);
    }
}

// test "deepTypedArrayReferences" {
//     const allocator = std.heap.page_allocator;
//     const TheType = struct { a: []const f32, b: []const u8 };
//     const data: TheType = .{ .a = &.{ 1.0, 2.0, 3.0 }, .b = "Hello World!" };
//     const actual = deepTypedArrayReferences(TheType, allocator, data);
//     try std.testing.expect(actual.a.len == 12);
//     try std.testing.expect(std.mem.eql(u8, actual.b, "Hello World!"));
//     try std.testing.expect(std.mem.eql(u8, actual.a.type, .Float32Array));
// }

test "DeepTypedArrayReferences Mesh type conversion" {
    const Mesh = @import("./subdiv.zig").Mesh;
    {
        const actual = DeepTypedArrayReferences(Mesh).type;
        _ = actual{ .points = &.{}, .quads = &.{.{ .type = .Uint32Array, .ptr = 0, .len = 0 }} };
    }
}

pub fn main() !void {
    const interface = @import("./wasmInterface.zig").interface;
    const allocator = std.heap.page_allocator;
    try build_typescript_type(allocator, interface, "src", "../gen/wasmInterface.d.ts");
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
