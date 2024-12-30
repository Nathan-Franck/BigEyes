const std = @import("std");
const utils = @import("./utils.zig");

pub inline fn typescriptTypeOf(from_type: type, comptime options: struct { first: bool = false, decl: ?from_type = null }) []const u8 {
    return comptime switch (@typeInfo(from_type)) {
        .bool => "boolean",
        .void => "void",
        .int => if (options.decl) |decl| std.fmt.comptimePrint("{}", .{decl}) else "number",
        .float => "number",
        .optional => |optional_info| typescriptTypeOf(optional_info.child, .{}) ++ " | null",
        .array => |array_info| typescriptTypeOf(array_info.child, .{}) ++ "[]",
        .vector => |vector_info| {
            const child = typescriptTypeOf(vector_info.child, .{});
            var result: []const u8 = &.{};
            for (0..vector_info.len) |i| {
                result = result ++ std.fmt.comptimePrint("{s}{s}", .{ if (i == 0) "" else ", ", child });
            }
            return std.fmt.comptimePrint("[{s}]", .{result});
        },
        .error_union => |eu| typescriptTypeOf(eu.payload, .{}), // Ignore the existence of errors for now...
        .pointer => |pointer| switch (pointer.size) {
            .Many, .Slice => if (pointer.child == u8)
                "string"
            else
                "Array<" ++ typescriptTypeOf(pointer.child, .{}) ++ ">",
            else => "unknown",
        },
        .@"enum" => |enum_info| {
            var result: []const u8 = &.{};
            for (enum_info.fields, 0..) |field, i| {
                result = result ++ std.fmt.comptimePrint("{s}\"{s}\"", .{
                    if (i == 0) "" else " | ",
                    field.name,
                });
            }
            return result;
        },
        .@"union" => |union_info| {
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
        .@"struct" => |struct_info| {
            var decls: []const u8 = &.{};
            for (struct_info.decls, 0..) |decl, i| {
                const field = @field(from_type, decl.name);

                decls = decls ++ std.fmt.comptimePrint("{s}{s}{s}: {s}", .{
                    if (i == 0) "" else ", ",
                    if (options.first) "\n\t" else "",
                    decl.name,
                    typescriptTypeOf(@TypeOf(field), .{ .decl = field }),
                });
            }
            var fields: []const u8 = &.{};
            for (struct_info.fields, 0..) |field, i| {
                const default = .{ field.type, false };
                const field_type, const is_optional = switch (@typeInfo(field.type)) {
                    else => default,
                    .optional => |field_optional_info| if (field.default_value) |_| .{ field_optional_info.child, true } else default,
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
        .@"fn" => |function_info| {
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
/// * Uint8Array - This is tricky, since in Zig this is put aside for strings... and most likely we don't want to obfuscate strings in JSON
pub fn deepTypedArrayReferences(t: type, allocator: std.mem.Allocator, data: t) !DeepTypedArrayReferences(t).type {
    if (!DeepTypedArrayReferences(t).changed) {
        return data;
    }
    return switch (@typeInfo(t)) {
        else => data,
        .error_union => try deepTypedArrayReferences(try data),
        .optional => |op| if (data) |non_null_data| try deepTypedArrayReferences(op.child, allocator, non_null_data) else null,
        .@"union" => |u| blk: {
            inline for (u.fields, 0..) |field, i| if (i == @intFromEnum(data)) {
                break :blk @unionInit(
                    DeepTypedArrayReferences(t).type,
                    field.name,
                    try deepTypedArrayReferences(field.type, allocator, @field(data, field.name)),
                );
            };
            @panic("awful bonus");
        },
        .@"struct" => |s| blk: {
            var new_data: DeepTypedArrayReferences(t).type = undefined;
            inline for (s.fields) |field| {
                const result = try deepTypedArrayReferences(field.type, allocator, @field(data, field.name));
                @field(new_data, field.name) = result;
            }
            break :blk new_data;
        },
        .array => |a| blk: {
            var elements: [a.len]DeepTypedArrayReferences(a.child).type = undefined;
            for (data, 0..) |elem, idx| {
                elements[idx] = try deepTypedArrayReferences(a.child, allocator, elem);
            }
            break :blk elements;
        },
        .pointer => |p| switch (p.size) {
            else => blk: {
                var elements = std.ArrayList(DeepTypedArrayReferences(p.child).type).init(allocator);
                for (data) |elem| {
                    try elements.append(try deepTypedArrayReferences(p.child, allocator, elem));
                }
                break :blk elements.items;
            },
            .Many, .Slice => switch (p.child) {
                else => switch (@typeInfo(p.child)) {
                    .vector => |vec| .{
                        .ptr = @intFromPtr(@as(*const p.child, @ptrCast(data))),
                        .len = data.len * vec.len,
                        .type = typeToTypedArrayEnumElement(vec.child),
                    },
                    .array => |arr| .{
                        .ptr = @intFromPtr(@as(*const p.child, @ptrCast(data))),
                        .len = data.len * arr.len,
                        .type = typeToTypedArrayEnumElement(arr.child),
                    },
                    else => blk: {
                        var elements = std.ArrayList(DeepTypedArrayReferences(p.child).type).init(allocator);
                        for (data) |elem| {
                            try elements.append(try deepTypedArrayReferences(p.child, allocator, elem));
                        }
                        break :blk elements.items;
                    },
                },
                f32, f64, i8, i16, i32, u8, u16, u32 => .{
                    .ptr = @intFromPtr(@as(*const p.child, @ptrCast(data))),
                    .len = data.len,
                    .type = typeToTypedArrayEnumElement(p.child),
                },
            },
        },
    };
}

pub fn TypedArrayReference(type_enum: type, _vec_len: u8) type {
    return struct {
        pub const vec_len: u8 = _vec_len;

        type: type_enum,
        ptr: usize,
        len: usize,
    };
}

fn TypeToTypedArrayEnum(t: type) type {
    return switch (t) {
        f32 => enum { Float32Array },
        f64 => enum { Float64Array },
        i8 => enum { Int8Array },
        i16 => enum { Int16Array },
        i32 => enum { Int32Array },
        u8 => enum { Uint8Array },
        u16 => enum { Uint16Array },
        u32 => enum { Uint32Array },
        else => @compileError(std.fmt.comptimePrint("Unsupported typed array {}", .{t})),
    };
}

fn typeToTypedArrayEnumElement(t: type) TypeToTypedArrayEnum(t) {
    return switch (t) {
        f32 => .Float32Array,
        f64 => .Float64Array,
        i8 => .Int8Array,
        i16 => .Int16Array,
        i32 => .Int32Array,
        u8 => .Uint8Array,
        u16 => .Uint16Array,
        u32 => .Uint32Array,
        else => @compileError(std.fmt.comptimePrint("Unsupported typed array {}", .{t})),
    };
}

pub fn DeepTypedArrayReferences(t: type) struct { type: type, changed: bool = false } {
    return switch (@typeInfo(t)) {
        else => .{ .type = t },
        .error_union => |eu| DeepTypedArrayReferences(eu.payload),
        .optional => |op| blk: {
            const result = DeepTypedArrayReferences(op.child);
            break :blk if (!result.changed) .{ .type = t } else .{ .changed = true, .type = ?result.type };
        },
        .@"union" => |u| blk: {
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
                .{ .changed = true, .type = @Type(.{ .@"union" = utils.copyWith(u, .{ .fields = fields }) }) };
        },
        .@"struct" => |s| blk: {
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
                .{ .changed = true, .type = @Type(.{ .@"struct" = utils.copyWith(s, .{ .decls = &[_]std.builtin.Type.Declaration{}, .fields = fields }) }) };
        },
        .array => |a| blk: {
            const child = DeepTypedArrayReferences(a.child);
            break :blk if (!child.changed)
                .{ .type = t }
            else
                .{ .changed = true, .type = @Type(.{ .Array = .{ .len = a.len, .sentinel = a.sentinel, .child = child.type } }) };
        },
        .pointer => |p| switch (p.size) {
            .Many, .Slice => switch (p.child) {
                f32, f64, i8, i16, i32, u8, u16, u32 => .{
                    .changed = true,
                    .type = TypedArrayReference(TypeToTypedArrayEnum(p.child), 1),
                },
                else => switch (@typeInfo(p.child)) {
                    .vector => |vec| .{ .changed = true, .type = TypedArrayReference(TypeToTypedArrayEnum(vec.child), vec.len) },
                    .array => |arr| .{ .changed = true, .type = TypedArrayReference(TypeToTypedArrayEnum(arr.child), arr.len) },
                    else => blk: {
                        const child = DeepTypedArrayReferences(p.child);
                        break :blk if (!child.changed)
                            .{ .type = t }
                        else
                            .{ .changed = true, .type = @Type(.{ .pointer = utils.copyWith(p, .{ .child = child.type }) }) };
                    },
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

    { // String
        const String = []const u8;
        const Fn = struct {
            noinline fn justAString() String {
                return "Hello!";
            }
        }.justAString;
        const t = try deepTypedArrayReferences(String, std.testing.allocator, Fn());
        try std.testing.expect(t.len > 0);
    }

    { // Deep type equality when nothing is referenceable
        const original = struct { a: []const u7, b: []const u7 };
        const transfromed = DeepTypedArrayReferences(original).type;
        try std.testing.expect(original == transfromed);
    }
}
