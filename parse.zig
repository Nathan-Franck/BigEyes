const std = @import("std");

// Helper: returns a new string that is indent concatenated with two spaces.
fn appendIndent(indent: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // Use the standard library to concatenate the current indent with "  "
    return std.mem.concat(allocator, u8, &[_][]const u8{ indent, "  " });
}

/// Given an AST and a node index, extract a substring from the original source
/// spanning the declaration. (This example assumes the AST nodes have "start" and "end" fields.)
fn getDeclText(ast: *std.zig.Ast, nodeIdx: usize) []const u8 {
    // Access the node (using the assumed API: ast.nodes.get(index))
    const node = ast.nodes.get(nodeIdx);
    // node.start and node.end are indices into ast.source.

    return ast.source[node.data.lhs..node.data.rhs];
}

/// Process a single declaration (by index) from the AST.
/// This function prints out public function and container (type) declarations.
/// It recurses into container members.
fn processDecl(ast: *std.zig.Ast, nodeIdx: u32, allocator: std.mem.Allocator, indent: []const u8) !void {
    const node = ast.nodes.get(nodeIdx);
    // Here we assume that a nonzero visib_token indicates a "pub" declaration.
    if (node.main_token == 0) return;

    // Use a switch on the node tag. We assume the tags "fn_decl" and "container_decl"
    // are used for functions and for containers (structs/unions/enums) respectively.
    switch (node.tag) {
        // Public function declaration.
        .fn_decl => {
            // Assume that the function name is the token immediately after the "fn" keyword.
            const fnName = ast.tokenSlice(node.main_token + 1);
            std.debug.print("{s}Function: {s}\n", .{ indent, fnName });
            // Optionally, print the full signature by extracting the source slice for the declaration.
            const declText = getDeclText(ast, nodeIdx);
            std.debug.print("{s}{s}\n\n", .{ indent, declText });
        },
        // Container declaration (struct/union/enum).
        .container_decl => {
            const typeName = ast.tokenSlice(node.main_token + 1);
            std.debug.print("{s}Type: {s}\n", .{ indent, typeName });
            const declText = getDeclText(ast, nodeIdx);
            std.debug.print("{s}{s}\n", .{ indent, declText });
            // Recurse into container members.
            // We assume that ast.containerDecl(nodeIdx) returns a struct with an "ast.members" field.
            const container = ast.containerDecl(nodeIdx);
            // For each member, increase the indent.
            const newIndent = try appendIndent(indent, allocator);
            for (container.ast.members) |memberIdx| {
                try processDecl(ast, memberIdx, allocator, newIndent);
            }
        },
        else => {
            // Other declarations are ignored.
        },
    }
}

/// Process all root declarations from the AST.
fn processDecls(ast: *std.zig.Ast, allocator: std.mem.Allocator, indent: []const u8) !void {
    const decls = ast.rootDecls();
    for (decls) |declIdx| {
        try processDecl(ast, declIdx, allocator, indent);
    }
}

/// Entry point: expects a folder path as the first argument.
pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 1) {
        std.debug.print("Usage: {s} <folder_path>\n", .{args[0]});
        return;
    }
    // const folderPath = args[1];

    // Get current working directory.
    const cwd = std.fs.cwd();
    const folder = try cwd.openDir("src", .{ .iterate = true });

    // Recursively walk the folder.
    var it = try folder.walk(allocator);
    while (try it.next()) |entry| {
        // Process only files ending with ".zig".
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        std.debug.print("Processing file: {s}\n", .{entry.path});

        const file = try folder.openFile(entry.path, .{});
        const contents = try file.readToEndAlloc(allocator, 4096 * 16);
        defer allocator.free(contents);

        const contents_null_term = try std.fmt.allocPrintZ(allocator, "{s}", .{contents});

        // Parse the file into an AST.
        // The third parameter (.zig) indicates the parsing mode.
        var ast = try std.zig.Ast.parse(allocator, contents_null_term, .zig);
        defer ast.deinit(allocator);

        // Process all root declarations.
        try processDecls(&ast, allocator, "");
    }
}
