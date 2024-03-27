const std = @import("std");

pub inline fn ExtractEventFields(the_type: type) []const std.builtin.Type.UnionField {
    return switch (@typeInfo(the_type)) {
        else => &.{},
        .Optional => |optional| switch (@typeInfo(optional.child)) {
            else => &.{optional.child},
            .Union => |the_union| the_union.fields,
        },
    };
}

pub inline fn ComposeEventType(event_fields: []const std.builtin.Type.UnionField) type {
    return @Type(.{ .Optional = .{
        .child = @Type(.{ .Union = .{
            .layout = .auto,
            .decls = &.{},
            .fields = event_fields,
            .tag_type = @Type(.{ .Enum = .{
                .tag_type = u8,
                .decls = &.{},
                .is_exhaustive = true,
                .fields = enum_fields: {
                    var fields: []const std.builtin.Type.EnumField = &.{};
                    break :enum_fields for (event_fields, 0..) |event_field, i| {
                        fields = fields ++ .{std.builtin.Type.EnumField{
                            .name = event_field.name,
                            .value = i,
                        }};
                    } else fields;
                },
            } }),
        } }),
    } });
}

test "ExtractEventTypes" {
    const MyFirstEventType = struct {};
    const MySecondEventType = struct {};
    const my_event_type_collection = ?union(enum) {
        MyFirstEventType: MyFirstEventType,
        MySecondEventType: MySecondEventType,
    };

    const result = ExtractEventFields(my_event_type_collection);

    const MyThirdEventType = struct {};
    const MyFourthEventType = struct {};
    const my_event_type_collection_2 = ?union(enum) {
        MyThirdEventType: MyThirdEventType,
        MyFourthEventType: MyFourthEventType,
    };

    const result_2 = ExtractEventFields(my_event_type_collection_2);

    const CombinedType = ComposeEventType(result ++ result_2);

    var tester: CombinedType = .MyFirstEventType;
    tester = .MySecondEventType;
    tester = .MyThirdEventType;
    tester = .MyFourthEventType;
}
