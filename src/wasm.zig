const std = @import("std");
const game = @import("game");
const type_definitions = @import("typecript").type_definitions;

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
pub fn dumpDebugLogFmt(comptime fmt: []const u8, args: anytype) void {
    dumpDebugLog(std.fmt.allocPrint(message_arena.allocator(), fmt, args) catch unreachable);
    _ = message_arena.reset(.retain_capacity);
}

pub fn Args(comptime func: anytype) type {
    const ParamInfo = @typeInfo(@TypeOf(func)).@"fn".params;
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
    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = true,
    } });
}

fn callWithJsonErr(name_ptr: [*]const u8, name_len: usize, args_ptr: [*]const u8, args_len: usize) !void {
    const allocator = message_arena.allocator();
    defer {
        _ = message_arena.reset(.retain_capacity);
    }
    const name: []const u8 = name_ptr[0..name_len];
    const args_string: []const u8 = args_ptr[0..args_len];
    const case = std.meta.stringToEnum(game.InterfaceEnum, name) orelse {
        dumpError(try std.fmt.allocPrint(allocator, "unknown function: {s}\n", .{name}));
        return;
    };
    switch (case) {
        inline else => |fn_tag| {
            const func = @field(game.interface, @tagName(fn_tag));

            var scanner = std.json.Scanner.initCompleteInput(allocator, args_string);
            defer scanner.deinit();

            var diagnostics = std.json.Diagnostics{};
            scanner.enableDiagnostics(&diagnostics);

            const args = std.json.parseFromTokenSource(Args(func), allocator, &scanner, .{}) catch |err| {
                dumpDebugLogFmt("Something in here isn't parsing right: {s}\nError: {any}\n", .{
                    args_string[0..@intCast(diagnostics.getByteOffset())],
                    err,
                });
                return err;
            };
            const result = switch (@typeInfo(@typeInfo(@TypeOf(func)).@"fn".return_type.?)) {
                .error_union => @call(.auto, func, args.value) catch |e| {
                    @panic(try std.fmt.allocPrint(allocator, "An error occured when calling {s} --- {any}\n", .{ @tagName(fn_tag), e }));
                },
                else => @call(.auto, func, args.value),
            };

            if (@TypeOf(result) != void) {
                const converted_result = try type_definitions.deepTypedArrayReferences(@TypeOf(result), message_arena.allocator(), result);
                dumpMessage(try std.json.stringifyAlloc(allocator, converted_result, .{}));
            }
        },
    }
}

export fn callWithJson(name_ptr: [*]const u8, name_len: usize, args_ptr: [*]const u8, args_len: usize) void {
    callWithJsonErr(name_ptr, name_len, args_ptr, args_len) catch |err| {
        dumpError(std.fmt.allocPrint(message_arena.allocator(), "error: {?}\n", .{err}) catch unreachable);
        _ = message_arena.reset(.retain_capacity);
        return;
    };
}

pub const Panic = struct {
    pub fn call(msg: []const u8, stack_trace: ?*std.builtin.StackTrace, starting_address: ?usize) noreturn {
        dumpDebugLogFmt("{s}", .{msg});
        if (stack_trace) |trace| {
            dumpDebugLogFmt("{any}", .{trace});
        }
        _ = starting_address;
        unreachable;
    }

    pub const messages = std.debug.FormattedPanic.messages;
    pub const inactiveUnionField = std.debug.FormattedPanic.inactiveUnionField;
    pub const outOfBounds = std.debug.FormattedPanic.outOfBounds;
    pub const sentinelMismatch = std.debug.FormattedPanic.sentinelMismatch;
    pub const startGreaterThanEnd = std.debug.FormattedPanic.startGreaterThanEnd;
    pub const unwrapError = std.debug.FormattedPanic.unwrapError;
};
