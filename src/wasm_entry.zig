const std = @import("std");
const subdiv = @import("./subdiv.zig");
const wasmInterface = @import("./wasmInterface.zig");
const typeDefinitions = @import("./typeDefinitions.zig");

export fn allocUint8(length: u32) [*]const u8 {
    const slice = std.heap.page_allocator.alloc(u8, length) catch
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

fn callWithJsonErr(name_ptr: [*]const u8, name_len: usize, args_ptr: [*]const u8, args_len: usize) !void {
    const allocator = std.heap.page_allocator;
    const name: []const u8 = name_ptr[0..name_len];
    const args_string: []const u8 = args_ptr[0..args_len];
    const case = std.meta.stringToEnum(wasmInterface.InterfaceEnum, name) orelse {
        dumpError(try std.fmt.allocPrint(allocator, "unknown function: {s}\n", .{name}));
        return;
    };
    switch (case) {
        inline else => |fn_name| {
            const func = @field(wasmInterface.interface, @tagName(fn_name));
            var diagnostics = std.json.Diagnostics{};
            var scanner = std.json.Scanner.initCompleteInput(allocator, args_string);
            defer scanner.deinit();
            scanner.enableDiagnostics(&diagnostics);

            const args = std.json.parseFromTokenSource(wasmInterface.Args(func), allocator, &scanner, .{}) catch |err| {
                // dumpError(try std.fmt.allocPrint(allocator, "Something in here isn't parsing right: {s}", .{args_string[0..@intCast(diagnostics.getByteOffset())]}));
                return err;
            };
            const result = try @call(.auto, func, args.value);
            const converted_result = try typeDefinitions.deepTypedArrayReferences(@TypeOf(result), allocator, result);
            dumpMessage(try std.json.stringifyAlloc(allocator, converted_result, .{}));
        },
    }
}

export fn callWithJson(name_ptr: [*]const u8, name_len: usize, args_ptr: [*]const u8, args_len: usize) void {
    // const allocator = std.heap.page_allocator;
    callWithJsonErr(name_ptr, name_len, args_ptr, args_len) catch {
        // dumperror(std.fmt.allocprint(allocator, "error: {?}\n", .{err}) catch unreachable);
        return;
    };
}
