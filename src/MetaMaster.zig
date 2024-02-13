const std = @import("std");

/// Merge two structs of data together.
///
/// NOTE: This does not add any additional fields to those already present in the source data.
///
/// eg. `merge(.{ .a = 0, .b = 2} .{ .a = 1 })` will return a type that is equivalent
/// to `.{ .a = 1, .b = 2 }`.
pub fn merge(source_data: anytype, field_changes: anytype) @TypeOf(source_data) {
    switch (@typeInfo(@TypeOf(source_data))) {
        .Struct => |struct_info| {
            var result = source_data;
            inline for (struct_info.fields) |field| {
                if (@hasField(@TypeOf(field_changes), field.name))
                    @field(result, field.name) = @field(field_changes, field.name);
            }
            return result;
        },
        else => {
            @compileError("Can't merge non-struct types");
        },
    }
}

test "merge" {
    const Data = struct { a: u32, b: f32, c: bool };
    const input_data: Data = .{ .a = 1, .b = 2.0, .c = true };
    const output_data = merge(input_data, .{ .a = 3 });
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
    return @Type(.{ .Struct = merge(input_struct, .{
        .fields = &.{found_field},
    }) });
}

test "PickField" {
    const input_struct = struct { a: u32, b: f32 };
    const output_struct = PickField(input_struct, .a);
    const expected_struct = struct { a: u32 };
    try std.testing.expectEqualSlices(
        std.builtin.Type.StructField,
        @typeInfo(output_struct).Struct.fields,
        @typeInfo(expected_struct).Struct.fields,
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
        if (match: for (@typeInfo(@TypeOf(field_tags)).Struct.fields) |tag| {
            if (std.mem.eql(u8, field.name, @tagName(@field(field_tags, tag.name)))) {
                break :match true;
            }
        } else false) {
            output_fields = output_fields ++ &[_]std.builtin.Type.StructField{field};
        }
    }
    return @Type(.{ .Struct = merge(input_struct, .{
        .fields = output_fields,
    }) });
}

test "Pick" {
    const input_struct = struct { a: u32, b: f32, c: bool };
    const output_struct = Pick(input_struct, .{ .a, .c });
    const expected_struct = struct { a: u32, c: bool };
    try std.testing.expectEqualSlices(
        std.builtin.Type.StructField,
        @typeInfo(output_struct).Struct.fields,
        @typeInfo(expected_struct).Struct.fields,
    );
}
