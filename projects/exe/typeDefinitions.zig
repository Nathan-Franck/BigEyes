const std = @import("std");

fn typescriptTypeOf(comptime from_type: anytype) []const u8 {
    return comptime switch (@typeInfo(from_type)) {
        .Int => "number",
        .Float => "number",
        .Array => |a| typescriptTypeOf(a.child) ++ "[]",
        .Vector => |v| {
            const chlid = typescriptTypeOf(v.child);
            var result: []const u8 = &.{};
            for (0..v.len) |i| {
                result = result ++ std.fmt.comptimePrint("{s}{s}", .{ if (i == 0) "" else ", ", chlid });
            }
            return std.fmt.comptimePrint("[ {s} ]", .{result});
        },
        .ErrorUnion => |eu| typescriptTypeOf(eu.payload), // Ignore the existence of errors for now...
        .Pointer => |p| switch (p.size) {
            .Many, .Slice => typescriptTypeOf(p.child) ++ "[]",
            else => "unknown",
        },
        .Struct => |s| {
            var decls: []const u8 = &.{};
            for (s.decls, 0..) |decl, i| {
                decls = decls ++ std.fmt.comptimePrint("{s}{s}: {s}", .{ if (i == 0) "" else ", ", decl.name, typescriptTypeOf(@TypeOf(@field(from_type, decl.name))) });
            }
            var fields: []const u8 = &.{};
            for (s.fields, 0..) |field, i| {
                fields = fields ++ std.fmt.comptimePrint("{s}{s}: {s}", .{ if (i == 0) "" else ", ", field.name, typescriptTypeOf(field.type) });
            }
            return std.fmt.comptimePrint("{{ {s}{s} }}", .{ if (decls.len > 0) decls ++ ", " else "", fields });
        },
        .Fn => |f| {
            var params: []const u8 = &.{};
            for (f.params, 0..) |param, i| {
                params = params ++ std.fmt.comptimePrint("{s}arg{d}: {s}", .{ if (i == 0) "" else ", ", i, typescriptTypeOf(param.type.?) });
            }
            return std.fmt.comptimePrint("({s}) => {s}", .{ params, typescriptTypeOf(f.return_type.?) });
        },
        else => "unknown",
    };
}

pub fn main() !void {
    const typeInfo = comptime typescriptTypeOf(@import("./nodes.zig").Nodes);
    const contents = "export type Nodes = " ++ typeInfo;
    std.fs.cwd().makeDir("web/gen") catch {};
    const file = std.fs.cwd().openFile("web/gen/nodes.d.ts", .{ .mode = .write_only }) catch
        try std.fs.cwd().createFile("web/gen/nodes.d.ts", .{});
    try file.writeAll(contents);
}
