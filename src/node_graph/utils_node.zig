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
