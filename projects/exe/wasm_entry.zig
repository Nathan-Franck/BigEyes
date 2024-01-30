const std = @import("std");
const subdiv = @import("subdiv");

const MyFuncs = struct {
    pub fn helloSlice(faces: []subdiv.Face) ![]subdiv.Face {
        return faces;
    }

    pub fn testSubdiv(faces: []subdiv.Face, points: []subdiv.Point) !subdiv.Mesh {
        const allocator = std.heap.page_allocator;
        const result = try subdiv.Polygon(.Face).cmcSubdiv(
            allocator,
            points,
            faces,
        );
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

export fn allocUint8(length: u32) [*]const u8 {
    const slice = std.heap.page_allocator.alloc(u8, length) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

extern fn messageFromWasm(source_pointer: [*]const u8, source_len: u32) void;

extern fn errorFromWasm(source_pointer: [*]const u8, source_len: u32) void;

fn callWithJsonErr(name_ptr: [*]const u8, name_len: u32, args_ptr: [*]const u8, args_len: u32) !void {
    const allocator = std.heap.page_allocator;
    const name: []const u8 = name_ptr[0..name_len];
    const args_string: []const u8 = args_ptr[0..args_len];
    const FnEnum = MyFuncs.toEnum();
    const case = std.meta.stringToEnum(FnEnum, name) orelse {
        const message = try std.fmt.allocPrint(allocator, "unknown function: {s}\n", .{name});
        messageFromWasm(message.ptr, message.len);
        return;
    };
    switch (case) {
        inline else => |fn_name| {
            const func = @field(MyFuncs, @tagName(fn_name));
            const args = try std.json.parseFromSlice(Args(func), allocator, args_string, .{});
            const result = try @call(.auto, func, args.value);
            const message = try std.json.stringifyAlloc(allocator, result, .{});
            messageFromWasm(message.ptr, message.len);
        },
    }
}

export fn callWithJson(name_ptr: [*]const u8, name_len: u32, args_ptr: [*]const u8, args_len: u32) void {
    const allocator = std.heap.page_allocator;
    callWithJsonErr(name_ptr, name_len, args_ptr, args_len) catch |err| {
        const message = std.fmt.allocPrint(allocator, "error: {?}\n", .{err}) catch unreachable;
        errorFromWasm(message.ptr, message.len);
        return;
    };
}
