const std = @import("std");

pub fn FunctionArgs(comptime func: anytype) type {
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
        .layout = .auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = true,
    } });
}

pub fn EnumStruct(field_key: type, field_value: type) type {
    switch (@typeInfo(field_key)) {
        else => @compileError("Expected field_key to be an enum"),
        .Enum => |enum_info| {
            var fields: []const std.builtin.Type.StructField = &.{};
            inline for (enum_info.fields) |field| {
                fields = fields ++ .{std.builtin.Type.StructField{
                    .name = field.name,
                    .type = field_value,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field_value),
                }};
            }
            return @Type(.{ .Struct = std.builtin.Type.Struct{
                .layout = .auto,
                .fields = fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        },
    }
}

/// Apply the changes in `field_changes` to `source_data`.
///
/// NOTE: This will fail to compile if not all field_changes are used in the original source_data.
///
/// eg. `copyWith(.{ .a = 0, .b = 2} .{ .a = 1 })` will return a type that is equivalent
/// to `.{ .a = 1, .b = 2 }`.
pub fn copyWith(source_data: anytype, field_changes: anytype) @TypeOf(source_data) {
    switch (@typeInfo(@TypeOf(source_data))) {
        else => @compileError("Can't merge non-struct types"),
        .@"struct" => |struct_info| {
            var result = source_data;
            comptime var unused_field_changes: []const []const u8 = &.{};
            inline for (@typeInfo(@TypeOf(field_changes)).@"struct".fields) |unused_field| {
                unused_field_changes = unused_field_changes ++ &[_][]const u8{unused_field.name};
            }
            inline for (struct_info.fields) |field| {
                if (@hasField(@TypeOf(field_changes), field.name))
                    @field(result, field.name) = @field(field_changes, field.name);
                comptime var next_unused_field_changes: []const []const u8 = &.{};
                inline for (unused_field_changes) |unused_field| {
                    comptime if (!std.mem.eql(u8, unused_field, field.name)) {
                        next_unused_field_changes = next_unused_field_changes ++ &[_][]const u8{unused_field};
                    };
                }
                unused_field_changes = next_unused_field_changes;
            }
            if (unused_field_changes.len > 0) {
                @compileError(std.fmt.comptimePrint("Unused fields found: {s}", .{unused_field_changes}));
            }
            return result;
        },
    }
}

test "copyWith" {
    const Data = struct { a: u32, b: f32, c: bool };
    const input_data: Data = .{ .a = 1, .b = 2.0, .c = true };
    const output_data = copyWith(input_data, .{ .a = 3 });
    try std.testing.expectEqual(output_data, Data{ .a = 3, .b = 2.0, .c = true });
}

/// Filter out all but one field from a struct.
///
/// eg. `PickField(struct { a: u32, b: f32 }, .my_field)` will return a type that is equivalent to
/// `struct { a: f32 }`.
///
/// This is useful for communicating at comptime partial data changes from a function.
pub fn PickField(comptime t: type, comptime field_tag: anytype) type {
    const input_struct = @typeInfo(t).Struct;
    const found_field = found_field: for (input_struct.fields) |field| {
        if (std.mem.eql(u8, field.name, @tagName(field_tag))) {
            break :found_field field;
        }
    };
    return @Type(.{ .Struct = copyWith(input_struct, .{
        .fields = &.{found_field},
    }) });
}

test "PickField" {
    const input_struct = struct { a: u32, b: f32 };
    const output_struct = PickField(input_struct, .a);
    const expected_struct = struct { a: u32 };
    try std.testing.expectEqualSlices(
        std.builtin.Type.StructField,
        @typeInfo(output_struct).@"struct".fields,
        @typeInfo(expected_struct).@"struct".fields,
    );
}

/// Filter out all but a set of fields from a struct.
///
/// eg. `Pick(struct { a: u32, b: f32, c: bool }, .{ .a, .c })` will return a type that is equivalent to
/// `struct { a: u32, c: bool }`.
///
/// This is useful for communicating at comptime partial data changes from a function.
pub fn Pick(comptime t: type, comptime field_tags: anytype) type {
    const input_struct = @typeInfo(t).Struct;
    var output_fields: []const std.builtin.Type.StructField = &.{};
    inline for (input_struct.fields) |field| {
        if (match: for (@typeInfo(@TypeOf(field_tags)).@"struct".fields) |tag| {
            if (std.mem.eql(u8, field.name, @tagName(@field(field_tags, tag.name)))) {
                break :match true;
            }
        } else false) {
            output_fields = output_fields ++ &[_]std.builtin.Type.StructField{field};
        }
    }
    return @Type(.{ .Struct = copyWith(input_struct, .{
        .fields = output_fields,
    }) });
}

test "Pick" {
    const input_struct = struct { a: u32, b: f32, c: bool };
    const output_struct = Pick(input_struct, .{ .a, .c });
    const expected_struct = struct { a: u32, c: bool };
    try std.testing.expectEqualSlices(
        std.builtin.Type.StructField,
        @typeInfo(output_struct).@"struct".fields,
        @typeInfo(expected_struct).@"struct".fields,
    );
}

fn DeepCloneResult(T: type) type {
    return struct {
        value: T,
        allocator_used: bool,
    };
}

pub fn deepClone(
    T: type,
    allocator: std.mem.Allocator,
    source: anytype,
) !T {
    const result = try deepCloneInner(T, allocator, source);
    return result.value;
}

fn deepCloneInner(
    T: type,
    allocator: std.mem.Allocator,
    source: anytype,
) !DeepCloneResult(T) {
    return switch (@typeInfo(T)) {
        else => .{ .value = source, .allocator_used = false },
        .array => |a| blk: {
            var elements: [a.len]a.child = undefined;
            var allocator_used = false;
            for (source, 0..) |elem, idx| {
                const result = try deepCloneInner(a.child, allocator, elem);
                allocator_used = allocator_used or result.allocator_used;
                elements[idx] = result.value;
            }
            if (!allocator_used) {
                break :blk .{ .value = source, .allocator_used = false };
            } else {
                break :blk .{ .value = elements, .allocator_used = true };
            }
        },
        .@"struct" => |struct_info| blk: {
            // Solution to clone ArrayLists and HashMaps, and who knows what else!
            if (@hasDecl(T, "cloneWithAllocator")) {
                break :blk .{
                    .value = try source.cloneWithAllocator(allocator),
                    .allocator_used = true,
                };
            } else if (@hasDecl(T, "clone")) {
                break :blk .{
                    .value = try copyWith(source, .{ .allocator = allocator }).clone(),
                    .allocator_used = true,
                };
            }

            // Resume regular cloning...
            var result: T = undefined;
            var allocator_used = false;
            inline for (struct_info.fields) |field| {
                const field_value = @field(source, field.name);
                const field_clone = try deepCloneInner(field.type, allocator, field_value);
                allocator_used = allocator_used or field_clone.allocator_used;
                @field(result, field.name) = field_clone.value;
            }
            if (!allocator_used) {
                break :blk .{ .value = source, .allocator_used = false };
            } else {
                break :blk .{ .value = result, .allocator_used = true };
            }
        },
        .@"union" => |union_info| blk: {
            if (union_info.tag_type == null) {
                @compileError(std.fmt.comptimePrint("unable to copy an untagged union: {any}", .{T}));
            }
            const active_tag_index = @intFromEnum(source);
            inline for (union_info.fields, 0..) |field_candidate, field_index| {
                if (active_tag_index == field_index) {
                    const result = try deepCloneInner(
                        field_candidate.type,
                        allocator,
                        @field(source, field_candidate.name),
                    );
                    if (!result.allocator_used) {
                        break :blk .{
                            .value = source,
                            .allocator_used = false,
                        };
                    } else {
                        break :blk .{
                            .value = @unionInit(T, field_candidate.name, result.value),
                            .allocator_used = true,
                        };
                    }
                }
            }
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .Many, .Slice => blk: {
                var elements = std.ArrayList(pointer_info.child).init(allocator);
                for (source) |elem| {
                    const result = try deepCloneInner(pointer_info.child, allocator, elem);
                    try elements.append(result.value);
                }
                break :blk .{ .value = elements.items, .allocator_used = true };
            },
            else => {
                @compileError(std.fmt.comptimePrint("Unsupported pointer type {any}", .{pointer_info.child}));
            },
        },
        .optional => |optional_info| blk: {
            if (source) |non_null_source| {
                const result = try deepCloneInner(optional_info.child, allocator, non_null_source);
                break :blk .{ .value = result.value, .allocator_used = result.allocator_used };
            } else {
                break :blk .{ .value = null, .allocator_used = false };
            }
        },
    };
}

test "deepClone" {
    { // Simple struct
        const Type = struct { a: i32, b: i32 };
        const source: Type = .{ .a = 1, .b = 2 };
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.meta.eql(source, result));
    }

    { // Slice
        const Type = []const i32;
        const source: Type = &.{ 1, 2, 3 };
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.mem.eql(i32, source, result));
    }

    { // Slice of union (that uses allocators)
        const Union = union(enum) { first: []const u8, second: []const u32 };
        const Type = []const Union;
        const source: Type = &.{ .{ .first = "hello!" }, .{ .second = &.{ 1, 2, 3 } } };
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.mem.eql(u32, source[1].second, result[1].second));
    }

    { // Slice of slices
        const Type = []const []const i32;
        const source: Type = &.{&.{ 1, 2, 3 }};
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.mem.eql(i32, source[0], result[0]));
    }

    { // Array
        const Type = []const [4]i32;
        const source: Type = &.{.{ 1, 2, 3, 4 }};
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.mem.eql(i32, &source[0], &result[0]));
    }

    { // Struct with slices inside
        const Type = struct { a: []const i32, b: []const i32 };
        const source: Type = .{ .a = &.{ 1, 2, 3 }, .b = &.{ 4, 5, 6 } };
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.mem.eql(i32, source.a, result.a));
    }

    { // Hashmap
        var thinger = std.AutoHashMap(u32, u32).init(std.heap.page_allocator);
        try thinger.put(1, 2);
        try thinger.put(3, 4);
        const result = try deepClone(@TypeOf(thinger), std.heap.page_allocator, thinger);
        try std.testing.expect(thinger.get(1) == result.get(1));
    }

    { // Hashmap
        var thinger = std.AutoArrayHashMap(u32, u32).init(std.heap.page_allocator);
        try thinger.put(1, 2);
        try thinger.put(3, 4);
        const result = try deepClone(@TypeOf(thinger), std.heap.page_allocator, thinger);
        try std.testing.expect(thinger.get(1) == result.get(1));
    }

    { // ArrayList
        var thinger = std.ArrayList(u32).init(std.heap.page_allocator);
        try thinger.append(1);
        try thinger.append(3);
        const result = try deepClone(@TypeOf(thinger), std.heap.page_allocator, thinger);
        try std.testing.expect(std.mem.eql(u32, thinger.items, result.items));
    }
}

/// Takes any type that has fields and returns a list of the field names as strings.
pub fn fieldNamesToStrings(comptime with_fields: type) []const []const u8 {
    comptime var options: []const []const u8 = &.{};
    inline for (std.meta.fields(with_fields)) |field| {
        options = options ++ .{field.name};
    }
    return options;
}

test "fieldNamesToStrings" {
    const Type = struct { a: i32, b: i32 };
    const result = fieldNamesToStrings(Type);
    try std.testing.expect(std.mem.eql(u8, result[0], "a"));
    try std.testing.expect(std.mem.eql(u8, result[1], "b"));
}

pub fn deepHashableStruct(t: type, quantization: u32, allocator: std.mem.Allocator, data: t) !DeepHashableStruct(t).type {
    if (!DeepHashableStruct(t).changed) {
        return data;
    }
    return switch (@typeInfo(t)) {
        else => data,
        .Float => @intFromFloat(data * @as(t, @floatFromInt(quantization))),
        .ErrorUnion => try deepHashableStruct(try data),
        .Optional => |op| if (data) |non_null_data| try deepHashableStruct(op.child, quantization, allocator, non_null_data) else null,
        .Union => |u| blk: {
            inline for (u.fields, 0..) |field, i| if (i == @intFromEnum(data)) {
                break :blk @unionInit(
                    DeepHashableStruct(t).type,
                    field.name,
                    try deepHashableStruct(field.type, quantization, allocator, @field(data, field.name)),
                );
            };
            @panic("awful bonus");
        },
        .Struct => |s| blk: {
            var new_data: DeepHashableStruct(t).type = undefined;
            inline for (s.fields) |field| {
                const result = try deepHashableStruct(field.type, quantization, allocator, @field(data, field.name));
                @field(new_data, field.name) = result;
            }
            break :blk new_data;
        },
        .Array => |a| blk: {
            var elements: [a.len]DeepHashableStruct(a.child).type = undefined;
            for (data, 0..) |elem, idx| {
                elements[idx] = try deepHashableStruct(a.child, quantization, allocator, elem);
            }
            break :blk elements;
        },
        .Vector => |a| blk: {
            var elements: @Vector(a.len, DeepHashableStruct(a.child).type) = undefined;
            for (0..a.len) |idx| {
                elements[idx] = try deepHashableStruct(a.child, quantization, allocator, data[idx]);
            }
            break :blk elements;
        },
        .Pointer => |p| blk: {
            var elements = std.ArrayList(DeepHashableStruct(p.child).type).init(allocator);
            for (data) |elem| {
                try elements.append(try deepHashableStruct(p.child, quantization, allocator, elem));
            }
            break :blk elements.items;
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

pub fn DeepHashableStruct(t: type) struct { type: type, changed: bool = false } {
    return switch (@typeInfo(t)) {
        else => .{ .type = t },
        .Float => .{ .type = u64, .changed = true },
        .ErrorUnion => |eu| DeepHashableStruct(eu.payload),
        .Optional => |op| blk: {
            const result = DeepHashableStruct(op.child);
            break :blk if (!result.changed) .{ .type = t } else .{ .changed = true, .type = ?result.type };
        },
        .Union => |u| blk: {
            var fields: []const std.builtin.Type.UnionField = &.{};
            var changed = false;
            for (u.fields) |field| {
                const new_field = DeepHashableStruct(field.type);
                changed = changed or new_field.changed;
                fields = fields ++ .{copyWith(field, .{
                    .type = new_field.type,
                })};
            }
            break :blk if (!changed)
                .{ .type = t }
            else
                .{ .changed = true, .type = @Type(.{ .Union = copyWith(u, .{ .fields = fields }) }) };
        },
        .Struct => |s| blk: {
            var fields: []const std.builtin.Type.StructField = &.{};
            var changed = false;
            for (s.fields) |field| {
                const new_field = DeepHashableStruct(field.type);
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
                .{ .changed = true, .type = @Type(.{ .Struct = copyWith(s, .{ .decls = &[_]std.builtin.Type.Declaration{}, .fields = fields }) }) };
        },
        .Vector => |a| blk: {
            const child = DeepHashableStruct(a.child);
            break :blk if (!child.changed)
                .{ .type = t }
            else
                .{ .changed = true, .type = @Type(.{ .Vector = .{ .len = a.len, .child = child.type } }) };
        },
        .Array => |a| blk: {
            const child = DeepHashableStruct(a.child);
            break :blk if (!child.changed)
                .{ .type = t }
            else
                .{ .changed = true, .type = @Type(.{ .Array = .{ .len = a.len, .sentinel = a.sentinel, .child = child.type } }) };
        },
        .Pointer => |p| blk: {
            const child = DeepHashableStruct(p.child);
            break :blk if (!child.changed)
                .{ .type = t }
            else
                .{ .changed = true, .type = @Type(.{ .Pointer = copyWith(p, .{ .child = child.type }) }) };
        },
    };
}

/// Find the smallest number in a slice of numbers and return the value and the index.
/// Uses SIMD to process multiple numbers at once.
pub fn findSmallestNumberAndIndex(T: type, numbers: []const T) struct { value: T, index: usize } {
    const vec_len = 32;
    const Vec = @Vector(vec_len, T);
    const IndexVec = @Vector(vec_len, usize);

    const max_value = switch (@typeInfo(T)) {
        .Float => std.math.floatMax(T),
        .Int => std.math.maxInt(T),
        else => @compileError("Invalid type"),
    };

    var min_vec: Vec = @splat(max_value);
    var min_index_vec: IndexVec = @splat(@as(usize, 0));

    var i: usize = 0;
    while (i < numbers.len) : (i += vec_len) {
        var current_vec: Vec = @splat(max_value);
        var index_vec: IndexVec = undefined;
        for (i..@min(i + vec_len, numbers.len)) |j| {
            current_vec[j - i] = numbers[j];
            index_vec[j - i] = @intCast(j);
        }
        const mask = current_vec < min_vec;
        min_vec = @select(T, mask, current_vec, min_vec);
        min_index_vec = @select(usize, mask, index_vec, min_index_vec);
    }

    // Find the minimum value and its index from the vectors
    const min_value = @reduce(.Min, min_vec);
    const min_index = @reduce(.Min, @select(
        usize,
        min_vec == @as(Vec, @splat(min_value)),
        min_index_vec,
        @as(IndexVec, @splat(std.math.maxInt(usize))),
    ));

    return .{ .value = min_value, .index = min_index };
}

test "smallest and index" {
    {
        const numbers = [_]i32{ 5, 2, 8, 2, 9, 3, 9, 7, 4, 6, 1 };
        const result = findSmallestNumberAndIndex(i32, &numbers);
        try std.testing.expectEqual(result.value, 1);
        try std.testing.expectEqual(result.index, 10);
    }

    {
        const numbers = [_]f32{ 61.0, 34.0, 40.0, 22.0, 95.0, 51.0, 79.0, 83.0 };
        const result = findSmallestNumberAndIndex(f32, &numbers);
        try std.testing.expectEqual(result.value, 22);
        try std.testing.expectEqual(result.index, 3);
    }
}
