const std = @import("std");
const utils = @import("utils");
const NodeGraphBlueprintEntry = @import("../node_graph.zig").NodeGraphBlueprintEntry;
const InputLink = @import("../node_graph.zig").InputLink;

pub fn MutableInputs(node: NodeGraphBlueprintEntry, NodeInputs: type) type {
    var mutable_fields: []const std.builtin.Type.StructField = &.{};
    const temp_node_inputs: NodeInputs = undefined;
    for (node.input_links) |link|
        switch (@typeInfo(@TypeOf(@field(temp_node_inputs, link.field)))) {
            else => {},
            .pointer => |pointer| if (!pointer.is_const) switch (pointer.size) {
                else => {},
                .One, .Slice => {
                    mutable_fields = mutable_fields ++ .{std.builtin.Type.StructField{
                        .name = link.field[0.. :0],
                        .type = switch (pointer.size) {
                            else => unreachable,
                            .One => *const pointer.child,
                            .Slice => []const pointer.child,
                        },
                        .default_value = null,
                        .is_comptime = false,
                        .alignment = @alignOf(pointer.child),
                    }};
                },
            },
        };
    const FieldsInner = @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = mutable_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
    return struct {
        pub const Fields = FieldsInner;

        fields: Fields,

        pub fn register(self: *@This(), TargetInputField: type, comptime link: InputLink, node_input_field: TargetInputField) TargetInputField {
            return switch (@typeInfo(TargetInputField)) {
                else => @compileError("Mutable field mismatch"),
                .pointer => |pointer| switch (pointer.size) {
                    .One => deferred_clone: {
                        @field(self.fields, link.field) = node_input_field;
                        break :deferred_clone undefined;
                    },
                    .Slice => deferred_clone: {
                        @field(self.fields, link.field) = node_input_field.*;
                        break :deferred_clone undefined;
                    },
                    else => @compileError("Unsupported pointer type"),
                },
            };
        }

        /// Duplicate data from inputs where the node is allowed to manipulate pointers
        pub fn duplicate(self: @This(), arena: std.mem.Allocator, node_inputs: anytype) !void {
            inline for (@typeInfo(@TypeOf(self.fields)).@"struct".fields) |field| {
                const pointer = @typeInfo(field.type).pointer;
                const input_to_clone = &@field(node_inputs.*, field.name);
                input_to_clone.* = switch (pointer.size) {
                    .One => cloned: {
                        const clone = try arena.create(pointer.child);
                        clone.* = try utils.deepClone(
                            pointer.child,
                            arena,
                            @field(self.fields, field.name).*,
                        );
                        break :cloned clone;
                    },
                    .Slice => try utils.deepClone(
                        @TypeOf(input_to_clone.*),
                        arena,
                        @field(self.fields, field.name),
                    ),
                    else => @panic("oh no..."),
                };
            }
        }
        pub fn copyBack(self: @This(), node_inputs: anytype, node_output: anytype) void {
            inline for (@typeInfo(@TypeOf(self.fields)).@"struct".fields) |mutable_field| {
                const pointer = @typeInfo(mutable_field.type).pointer;
                @field(node_output, mutable_field.name) = switch (pointer.size) {
                    else => @panic("qwer"),
                    .One => @field(node_inputs, mutable_field.name).*,
                    .Slice => @field(node_inputs, mutable_field.name),
                };
            }
        }
    };
}

/// Provides an interface a system can send to a function, where the function, when retrieving the containing
/// value will signal to the external system that the value has been retrieved.
/// For the NodeGraph, this Queryable can be used to retrieve values within a branch of the node's logic,
/// so that if the node has chosen a different branch, the value doesn't have to be considered when marking
/// the node as dirty.
pub const queryable = struct {
    pub fn isValue(candidate: type) bool {
        return switch (@typeInfo(candidate)) {
            .@"struct" => @hasDecl(candidate, "QueryableSource"),
            else => false,
        };
    }
    pub fn getSourceOrNull(candidate: type) ?type {
        return if (isValue(candidate))
            @field(candidate, "QueryableSource")
        else
            null;
    }

    pub fn Value(T: type) type {
        return struct {
            pub const QueryableSource = T;

            queried: *bool,
            raw: T,

            pub fn get(self: @This()) T {
                self.queried.* = true;
                return self.raw;
            }

            pub fn initQueryable(
                value: T,
                is_field_dirty: *bool,
                queried: *bool,
            ) @This() {
                if (!queried.*)
                    is_field_dirty.* = false;
                queried.* = false;
                return @This(){ .raw = value, .queried = queried };
            }
        };
    }
};

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
