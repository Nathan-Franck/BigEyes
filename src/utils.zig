const std = @import("std");

pub fn copyWith(source_data: anytype, field_changes: anytype) @TypeOf(source_data) {
    switch (@typeInfo(@TypeOf(source_data))) {
        else => @compileError("Can't merge non-struct types"),
        .Struct => |struct_info| {
            var result = source_data;
            comptime var unused_field_changes: []const []const u8 = &.{};
            inline for (@typeInfo(@TypeOf(field_changes)).Struct.fields) |unused_field| {
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

pub fn deepClone(
    T: type,
    allocator: std.mem.Allocator,
    source: anytype,
) !struct {
    value: T,
    allocator_used: bool = false,
} {
    return switch (@typeInfo(T)) {
        else => .{ .value = source, .allocator_used = false },
        .Array => |a| blk: {
            var elements: [a.len]a.child = undefined;
            var allocator_used = false;
            for (source, 0..) |elem, idx| {
                const result = try deepClone(a.child, allocator, elem);
                allocator_used = allocator_used or result.allocator_used;
                elements[idx] = result.value;
            }
            if (!allocator_used) {
                break :blk .{ .value = source, .allocator_used = false };
            } else {
                break :blk .{ .value = elements, .allocator_used = true };
            }
        },
        .Struct => |struct_info| blk: {
            var result: T = undefined;
            var allocator_used = false;
            inline for (struct_info.fields) |field| {
                const field_value = @field(source, field.name);
                const field_clone = try deepClone(field.type, allocator, field_value);
                allocator_used = allocator_used or field_clone.allocator_used;
                @field(result, field.name) = field_clone.value;
            }
            if (!allocator_used) {
                break :blk .{ .value = source, .allocator_used = false };
            } else {
                break :blk .{ .value = result, .allocator_used = true };
            }
        },
        .Union => |union_info| blk: {
            const active_tag_index = @intFromEnum(source);
            inline for (union_info.fields, 0..) |field_candidate, field_index| {
                if (active_tag_index == field_index) {
                    const result = try deepClone(
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
            unreachable;
        },
        .Pointer => |pointer_info| switch (pointer_info.size) {
            .Many, .Slice => blk: {
                var elements = std.ArrayList(pointer_info.child).init(allocator);
                for (source) |elem| {
                    const result = try deepClone(pointer_info.child, allocator, elem);
                    try elements.append(result.value);
                }
                break :blk .{ .value = elements.items, .allocator_used = true };
            },
            else => {
                @compileError(std.fmt.comptimePrint("Unsupported pointer type {any}", .{pointer_info.child}));
            },
        },
        .Optional => |optional_info| blk: {
            if (source) |non_null_source| {
                const result = try deepClone(optional_info.child, allocator, non_null_source);
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
        try std.testing.expect(std.meta.eql(source, result.value));
    }

    { // slice
        const Type = []const i32;
        const source: Type = &.{ 1, 2, 3 };
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.mem.eql(i32, source, result.value));
    }

    { // slice of slices
        const Type = []const []const i32;
        const source: Type = &.{&.{ 1, 2, 3 }};
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.mem.eql(i32, source[0], result.value[0]));
    }

    { // array
        const Type = []const [4]i32;
        const source: Type = &.{.{ 1, 2, 3, 4 }};
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.mem.eql(i32, &source[0], &result.value[0]));
    }

    { // Struct with slices inside
        const Type = struct { a: []const i32, b: []const i32 };
        const source: Type = .{ .a = &.{ 1, 2, 3 }, .b = &.{ 4, 5, 6 } };
        const result = try deepClone(Type, std.heap.page_allocator, source);
        try std.testing.expect(std.mem.eql(i32, source.a, result.value.a));
    }

    // { // Hashmap
    //     // ERROR: can't copy the arbitrary sized pointer in the hashmap
    //     var thinger = std.AutoHashMap(u32, u32).init(std.heap.page_allocator);
    //     try thinger.put(1, 2);
    //     try thinger.put(3, 4);
    //     const result = try deepClone(@TypeOf(thinger), std.heap.page_allocator, thinger);
    //     try std.testing.expect(thinger.capacity == result.value.capacity);
    // }

    // { // Hashmap attempt #2
    //     // ERROR: can't copy the arbitrary sized pointer in the hashmap
    //     var thinger = std.AutoArrayHashMap(u32, u32).init(std.heap.page_allocator);
    //     try thinger.put(1, 2);
    //     try thinger.put(3, 4);
    //     const result = try deepClone(@TypeOf(thinger), std.heap.page_allocator, thinger);
    //     try std.testing.expect(thinger.capacity == result.value.capacity);
    // }
    // { // ArrayList
    //     var thinger = std.ArrayList(u32).init(std.heap.page_allocator);
    //     try thinger.append(1);
    //     try thinger.append(3);
    //     const result = try deepClone(@TypeOf(thinger), std.heap.page_allocator, thinger);
    //     try std.testing.expect(thinger.capacity == result.value.capacity);
    // }
}

/// Takes any type that has fields and returns a list of the field names as strings.
/// NOTE: Required to run at comptime from the callsite.
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
