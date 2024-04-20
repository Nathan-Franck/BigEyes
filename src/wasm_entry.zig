const std = @import("std");
const game = @import("./game.zig");
const type_definitions = @import("./type_definitions.zig");

var message_arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);

export fn allocUint8(length: u32) [*]const u8 {
    const slice = message_arena.allocator().alloc(u8, length) catch
        @panic("failed to allocate memory");
    return slice.ptr;
}

extern fn messageFromWasm(source_pointer: [*]const u8, source_len: usize) void;

extern fn errorFromWasm(source_pointer: [*]const u8, source_len: usize) void;

extern fn debugLogFromWasm(source_pointer: [*]const u8, source_len: usize) void;

fn dumpMessage(source: []const u8) void {
    messageFromWasm(source.ptr, source.len);
}

fn dumpError(source: []const u8) void {
    errorFromWasm(source.ptr, source.len);
}

pub fn dumpDebugLog(source: []const u8) void {
    debugLogFromWasm(source.ptr, source.len);
}

pub const InterfaceEnum = DeclsToEnum(game);

pub fn DeclsToEnum(comptime container: type) type {
    const info = @typeInfo(container);
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

pub fn Args(comptime func: anytype) type {
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

fn callWithJsonErr(name_ptr: [*]const u8, name_len: usize, args_ptr: [*]const u8, args_len: usize) !void {
    const allocator = message_arena.allocator();
    const name: []const u8 = name_ptr[0..name_len];
    const args_string: []const u8 = args_ptr[0..args_len];
    const case = std.meta.stringToEnum(InterfaceEnum, name) orelse {
        dumpError(try std.fmt.allocPrint(allocator, "unknown function: {s}\n", .{name}));
        return;
    };
    switch (case) {
        inline else => |fn_name| {
            const func = @field(game, @tagName(fn_name));
            var diagnostics = std.json.Diagnostics{};
            var scanner = std.json.Scanner.initCompleteInput(allocator, args_string);
            defer scanner.deinit();
            scanner.enableDiagnostics(&diagnostics);

            const args = std.json.parseFromTokenSource(Args(func), allocator, &scanner, .{}) catch |err| {
                dumpError(try std.fmt.allocPrint(allocator, "Something in here isn't parsing right: {s}", .{args_string[0..@intCast(diagnostics.getByteOffset())]}));
                return err;
            };
            const result = try @call(.auto, func, args.value);
            const converted_result = try type_definitions.deepTypedArrayReferences(@TypeOf(result), allocator, result);
            dumpMessage(try std.json.stringifyAlloc(allocator, converted_result, .{}));
            _ = message_arena.reset(.retain_capacity);
        },
    }
}

export fn callWithJson(name_ptr: [*]const u8, name_len: usize, args_ptr: [*]const u8, args_len: usize) void {
    callWithJsonErr(name_ptr, name_len, args_ptr, args_len) catch |err| {
        const allocator = std.heap.page_allocator;
        dumpError(std.fmt.allocPrint(allocator, "error: {?}\n", .{err}) catch unreachable);
        return;
    };
}
