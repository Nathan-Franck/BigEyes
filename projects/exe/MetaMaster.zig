const std = @import("std");

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
