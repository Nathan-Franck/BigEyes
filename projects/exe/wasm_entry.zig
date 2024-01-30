const std = @import("std");
const subdiv = @import("subdiv");

extern fn messageFromWasm(source_pointer: [*]const u8, source_len: u32) void;

const MyFuncs = struct {
    pub fn testSubdiv(inp: u32) void {
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
        const stringified_result = std.json.stringifyAlloc(allocator, result, .{}) catch @panic("std.json.stringifyAlloc");
        messageFromWasm(stringified_result.ptr, stringified_result.len);
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

export fn callMyFunc(name_ptr: [*]const u8, name_len: u32, args_ptr: [*]const u8, args_len: u32) void {
    const allocator = std.heap.page_allocator;
    const name: []const u8 = name_ptr[0..name_len];
    const args_string: []const u8 = args_ptr[0..args_len];
    _ = args_string; // autofix
    const FnEnum = MyFuncs.toEnum();
    const case = std.meta.stringToEnum(FnEnum, name) orelse {
        const message = std.fmt.allocPrint(allocator, "unknown function: {s}\n", .{name}) catch @panic("std.fmt.allocPrint");
        messageFromWasm(message.ptr, message.len);
        return;
    };
    switch (case) {
        inline else => |fn_name| {
            const message = std.fmt.allocPrint(allocator, "Sick! {?}\n", .{fn_name}) catch @panic("std.fmt.allocPrint");
            messageFromWasm(message.ptr, message.len);
        },
    }
}
