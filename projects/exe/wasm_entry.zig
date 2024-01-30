const std = @import("std");
const subdiv = @import("subdiv");

extern fn messageFromWasm(source_pointer: [*]const u8, source_len: u32) void;

const MyFuncs = struct {
    pub fn testSubdiv(inp: u32) subdiv.Mesh {
        _ = inp;
        const allocator = std.heap.page_allocator;
        var points = [_]subdiv.Point{
            subdiv.Point{ -1.1, 1.0, 1.0, 1.0 },
            subdiv.Point{ -1.0, -1.0, 1.0, 1.0 },
            subdiv.Point{ 1.0, -1.0, 1.0, 1.0 },
            subdiv.Point{ 1.0, 1.0, 1.0, 1.0 },
            subdiv.Point{ -1.0, 1.0, -1.0, 1.0 },
            subdiv.Point{ -1.0, -1.0, -1.0, 1.0 },
        };

        var faces = [_]subdiv.Face{
            &[_]u32{ 0, 1, 2, 3 },
            &[_]u32{ 0, 1, 5, 4 },
        };
        const result = subdiv.Polygon(.Face).cmcSubdiv(
            allocator,
            &points,
            &faces,
        ) catch @panic("subdiv.Subdiv.cmcSubdiv");
        return result;
    }

    fn toEnum() type {
        const info = @typeInfo(MyFuncs);
        var enum_fields: []const std.builtin.Type.EnumField = &.{};
        for (info.Struct.decls, 0..) |struct_decl, i| {
            enum_fields = enum_fields ++ &[_]std.builtin.Type.EnumField{.{
                .name = struct_decl.name,
                .value = i,
            }};
        }
        return @Type(.{ .Enum = .{
            .tag_type = u32,
            .fields = enum_fields,
            .decls = &.{},
            .is_exhaustive = true,
        } });
    }
};

export fn allocUint8(length: u32) [*]const u8 {
    const slice = std.heap.page_allocator.alloc(u8, length) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

fn Args(comptime func: anytype) type {
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
        .layout = .Auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = true,
    } });
}

export fn callMyFunc(name_ptr: [*]const u8, name_len: u32, args_ptr: [*]const u8, args_len: u32) void {
    const allocator = std.heap.page_allocator;
    const name: []const u8 = name_ptr[0..name_len];
    const args_string: []const u8 = args_ptr[0..args_len];
    const FnEnum = MyFuncs.toEnum();
    const case = std.meta.stringToEnum(FnEnum, name) orelse {
        const message = std.fmt.allocPrint(allocator, "unknown function: {s}\n", .{name}) catch @panic("std.fmt.allocPrint");
        messageFromWasm(message.ptr, message.len);
        return;
    };
    switch (case) {
        inline else => |fn_name| {
            const func = @field(MyFuncs, @tagName(fn_name));
            const args = std.json.parseFromSlice(Args(func), allocator, args_string, .{}) catch @panic("std.json.parse");
            const result = @call(.auto, func, args.value);
            const message = std.fmt.allocPrint(allocator, "Sick! {?} {?}\n", .{ fn_name, result }) catch @panic("std.fmt.allocPrint");
            messageFromWasm(message.ptr, message.len);
        },
    }
}
