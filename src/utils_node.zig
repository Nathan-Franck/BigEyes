const std = @import("std");

pub fn NodeOutputEventType(node_process_function: anytype) type {
    const node_process_function_info = @typeInfo(@TypeOf(node_process_function));
    if (node_process_function_info != .Fn) {
        @compileError("node_process_function must be a function, found '" ++ @typeName(node_process_function) ++ "'");
    }
    var return_type = node_process_function_info.Fn.return_type.?;
    if (@typeInfo(return_type) == .ErrorUnion) {
        return_type = @typeInfo(return_type).ErrorUnion.payload;
    }
    const event_field_info = std.meta.fieldInfo(return_type, .event);
    return event_field_info.type;
}

pub fn NodeInputEventType(node_process_function: anytype) type {
    const node_process_function_info = @typeInfo(@TypeOf(node_process_function));
    if (node_process_function_info != .Fn) {
        @compileError("node_process_function must be a function, found '" ++ @typeName(node_process_function) ++ "'");
    }
    const params = node_process_function_info.Fn.params;
    const event_field_info = std.meta.fieldInfo(params[params.len - 1].type.?, .event);
    return event_field_info.type;
}

pub fn eventTransform(target_event_type: type, source_event: anytype) target_event_type {
    const source_info = @typeInfo(@TypeOf(source_event));
    if (source_info != .Optional) {
        @compileError("source_event must be an optional union type (?union(enum){}), found '" ++ @typeName(source_event) ++ "'");
    }
    const source_optional_info = @typeInfo(source_info.Optional.child);
    if (source_optional_info != .Union) {
        @compileError("source_event must be an optional union type (?union(enum){}), found '" ++ @typeName(source_event) ++ "'");
    }
    const target_info = @typeInfo(target_event_type);
    if (target_info != .Optional) {
        @compileError("target_event_type must be an optional union type (?union(enum){}), found '" ++ @typeName(target_event_type) ++ "'");
    }
    const target_optional_info = @typeInfo(target_info.Optional.child);
    if (target_optional_info != .Union) {
        @compileError("target_event_type must be an optional union type (?union(enum){}), found '" ++ @typeName(target_event_type) ++ "'");
    }
    if (source_event) |source_not_null| {
        const field_index = @intFromEnum(source_not_null);
        inline for (source_optional_info.Union.fields, 0..) |source_field, i| {
            if (i == field_index) {
                const source = @field(source_not_null, source_field.name);
                inline for (target_optional_info.Union.fields) |target_field| {
                    const equal_names = comptime std.mem.eql(u8, source_field.name, target_field.name);
                    const equal_types = source_field.type == target_field.type;
                    if (equal_names and equal_types) {
                        return @unionInit(target_info.Optional.child, target_field.name, source);
                    } else if (equal_names and !equal_types) {
                        @compileError(std.fmt.comptimePrint("source and target field types do not match: {any} {any}", .{ target_field.type, source_field.type }));
                    } else if (equal_types and !equal_names) {
                        @compileError("source and target field names do not match: " ++ target_field.name ++ " " ++ source_field.name);
                    }
                }
            }
        }
    }
    return null;
}
