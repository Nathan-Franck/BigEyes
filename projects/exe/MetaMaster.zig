const std = @import("std");

/// Map a struct of data to another struct, where the fields are the same name (assumed to be the
/// same type). This will strip out any fields that are not present in the destination struct.
///
/// eg. `withFields(struct { a: u32 }, .{ .a = 5, .b = 6 })` will return a value of `.{ .a = 5 }`.
pub fn withFields(source_struct: anytype, field_changes: anytype) @TypeOf(source_struct) {
    switch (@typeInfo(@TypeOf(source_struct))) {
        .Struct => |structInfo| {
            var result = source_struct;
            inline for (structInfo.fields) |field| {
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
    return @Type(.{ .Struct = withFields(input_struct, .{
        .fields = &.{found_field},
    }) });
}
