const std = @import("std");

// fn query(allocator: std.mem.Allocator, input: anytype, query: type)  {
// }

test "query test" {
    const Character = struct {
        name: []const u8,
        age: u8,
    };

    const characters: []const Character = &.{
        .{ .name = "Todd Howard", .age = 40 },
        .{ .name = "Budd Lite", .age = 20 },
    };

    const allocator = std.heap.page_allocator;
    const preferred_age = 20;

    // Best overall for clarity and conciseness
    const result = map: {
        var result = std.ArrayList(struct {
            first_name: []const u8,
            last_name: []const u8,
        }).init(allocator);
        for (characters) |c| {
            if (c.age != preferred_age) continue;
            var it = std.mem.split(u8, c.name, " ");
            try result.append(.{
                .first_name = if (it.next()) |n| n else "",
                .last_name = if (it.next()) |n| n else "",
            });
        }
        break :map result;
    };

    // This is pretty tempting to implement... :)
    // Could be a pain to maintain and add new features all the time to...
    // Though could be educational!
    // Tooling is bad, but nothing github copilot can't make up for!
    const another_query_result: struct {
        first_name: []const u8,
        last_name: []const u8,
    } = sql_query(allocator, .{ .characters = characters }, .{ .preferred_age = preferred_age },
        \\ SELECT
        \\ SUBSTRING_INDEX(name, " ", 1) AS first_name,
        \\ SUBSTRING_INDEX(name " ", -1) AS last_name,
        \\ WHERE age == {preferred_age} FROM {characters}"
    );

    // Ugly but single-expression, can't really filter any results out in this pass...
    const result_2 = if (allocator.alloc(struct {
        first_name: []const u8,
        last_name: []const u8,
    }, characters.len)) |out| for (out, 0..) |*item, i| {
        var it = std.mem.split(u8, characters[i].name, " ");
        item.* = .{
            .first_name = if (it.next()) |n| n else "",
            .last_name = if (it.next()) |n| n else "",
        };
    } else out else |err| return err;

    // Fanciful and arduous... still somewhat compelling? I wish that zig took on some responsibility
    // for inferring types from function contents, but I know that is way not going to happen...

    // const FormattedCharacter = struct {
    //     first_name: []const u8,
    //     last_name: []const u8,
    //     preferred: bool,
    // };
    // const query_result: FormattedCharacter = query(allocator, characters, struct {
    //     preferred_age: u8,
    //     fn map(context: @This(), character: Character) FormattedCharacter {
    //         var it = try std.mem.split(u8, character.name, " ");
    //         return .{
    //             .first_name = try it.next(),
    //             .last_name = try it.next(),
    //             .preferred = character.age == context.preferred_age,
    //         };
    //     }
    //     fn filter(context: @This(), character: FormattedCharacter) bool {
    //         return character.preferred;
    //     }
    // }{ .preferred_age = preferred_age });

    std.debug.print("Here's all the first and last names! {any}\n", .{std.json.fmt(result.items, .{ .whitespace = .indent_4 })});
    std.debug.print("Here's all the first and last names (2)! {any}\n", .{std.json.fmt(result_2, .{ .whitespace = .indent_4 })});
}
