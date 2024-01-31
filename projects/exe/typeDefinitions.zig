const std = @import("std");

fn typescriptTypeOf(comptime from_type: anytype, options: struct { first: bool = false }) []const u8 {
    return comptime switch (@typeInfo(from_type)) {
        .Int => "number",
        .Float => "number",
        .Bool => "boolean",
        .Array => |a| typescriptTypeOf(a.child, .{}) ++ "[]",
        .Vector => |v| {
            const chlid = typescriptTypeOf(v.child, .{});
            var result: []const u8 = &.{};
            for (0..v.len) |i| {
                result = result ++ std.fmt.comptimePrint("{s}{s}", .{ if (i == 0) "" else ", ", chlid });
            }
            return std.fmt.comptimePrint("[{s}]", .{result});
        },
        .ErrorUnion => |eu| typescriptTypeOf(eu.payload, .{}), // Ignore the existence of errors for now...
        .Pointer => |p| switch (p.size) {
            .Many, .Slice => typescriptTypeOf(p.child, .{}) ++ "[]",
            else => "unknown",
        },
        .Struct => |s| {
            var decls: []const u8 = &.{};
            for (s.decls, 0..) |decl, i| {
                decls = decls ++ std.fmt.comptimePrint("{s}{s}{s}: {s}", .{
                    if (i == 0) "" else ", ",
                    if (options.first) "\n\t" else "",
                    decl.name,
                    typescriptTypeOf(@TypeOf(@field(from_type, decl.name)), .{}),
                });
            }
            var fields: []const u8 = &.{};
            for (s.fields, 0..) |field, i| {
                fields = fields ++ std.fmt.comptimePrint("{s}{s}{s}: {s}", .{
                    if (i == 0) "" else ", ",
                    if (options.first) "\n\t" else "",
                    field.name,
                    typescriptTypeOf(field.type, .{}),
                });
            }
            return std.fmt.comptimePrint("{{{s}{s}{s}{s}}}", .{
                if (options.first) "" else " ",
                if (decls.len > 0) decls ++ ", " else "",
                fields,
                if (options.first) "\n" else " ",
            });
        },
        .Fn => |f| {
            var params: []const u8 = &.{};
            for (f.params, 0..) |param, i| {
                params = params ++ std.fmt.comptimePrint("{s}arg{d}: {s}", .{ if (i == 0) "" else ", ", i, typescriptTypeOf(param.type.?, .{}) });
            }
            return std.fmt.comptimePrint("({s}) => {s}", .{ params, typescriptTypeOf(f.return_type.?, .{}) });
        },
        else => "unknown",
    };
}

fn typescriptObjectStructureDeclaration(comptime from_type: anytype, options: struct { first: bool = false }) []const u8 {
    return comptime switch (@typeInfo(from_type)) {
        .Int => "\"number\"",
        .Float => "\"number\"",
        .Bool => "\"boolean\"",
        .Array => |a| {
            const child = typescriptObjectStructureDeclaration(a.child, .{});
            var result: []const u8 = &.{};
            for (0..a.len) |i| {
                result = result ++ std.fmt.comptimePrint("{s}{s}", .{ if (i == 0) "" else ", ", child });
            }
            return std.fmt.comptimePrint("[{s}]", .{result});
        },
        .Vector => |v| {
            const child = typescriptObjectStructureDeclaration(v.child, .{});
            var result: []const u8 = &.{};
            for (0..v.len) |i| {
                result = result ++ std.fmt.comptimePrint("{s}{s}", .{ if (i == 0) "" else ", ", child });
            }
            return std.fmt.comptimePrint("[{s}]", .{result});
        },
        .ErrorUnion => |eu| typescriptObjectStructureDeclaration(eu.payload, .{}), // Ignore the existence of errors for now...
        .Pointer => |p| switch (p.size) {
            .Many, .Slice => if (p.child == u8)
                "\"string\""
            else
                "{ Array: " ++ typescriptObjectStructureDeclaration(p.child, .{}) ++ " }",
            else => "\"unknown\"",
        },
        .Struct => |s| {
            var decls: []const u8 = &.{};
            for (s.decls, 0..) |decl, i| {
                decls = decls ++ std.fmt.comptimePrint("{s}{s}{s}: {s}", .{
                    if (i == 0) "" else ", ",
                    if (options.first) "\n\t" else "",
                    decl.name,
                    typescriptObjectStructureDeclaration(@TypeOf(@field(from_type, decl.name)), .{}),
                });
            }
            var fields: []const u8 = &.{};
            for (s.fields, 0..) |field, i| {
                fields = fields ++ std.fmt.comptimePrint("{s}{s}{s}: {s}", .{
                    if (i == 0) "" else ", ",
                    if (options.first) "\n\t" else "",
                    field.name,
                    typescriptObjectStructureDeclaration(field.type, .{}),
                });
            }
            return std.fmt.comptimePrint("{{ Struct: {{ {s}{s}{s}{s}}} }}", .{
                if (options.first) "" else " ",
                if (decls.len > 0) decls ++ ", " else "",
                fields,
                if (options.first) "\n" else " ",
            });
        },
        .Fn => |f| {
            return std.fmt.comptimePrint("{{ Node: {{ State: {s}{s}, Returns: {s} }} }}", .{
                typescriptObjectStructureDeclaration(f.params[0].type.?, .{}),
                if (f.params.len <= 1) "" else ", Options: " ++ typescriptObjectStructureDeclaration(f.params[1].type.?, .{}),
                typescriptObjectStructureDeclaration(f.return_type.?, .{}),
            });
        },
        else => "\"unknown\"",
    };
}

pub fn main() !void {
    const typeInfo = comptime typescriptObjectStructureDeclaration(@import("./nodes.zig").Nodes, .{ .first = true });
    const contents = "export const nodesDecl = " ++ typeInfo ++ " as const;\n";
    std.fs.cwd().makeDir("web/gen") catch {};
    std.fs.cwd().deleteFile("web/gen/nodes.mts") catch {};
    const file = try std.fs.cwd().createFile("web/gen/nodes.mts", .{});
    try file.writeAll(contents);
}
