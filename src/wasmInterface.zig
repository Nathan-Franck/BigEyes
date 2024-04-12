const subdiv = @import("./subdiv.zig");
const std = @import("std");
const graphRuntime = @import("./graphRuntime.zig");
const NodeDefinitions = @import("./nodeGraphBlueprintNodes.zig");
const node_graph_blueprint = @import("./interactiveNodeBuilderBlueprint.zig").node_graph_blueprint;
const typeDefinitions = @import("./typeDefinitions.zig");

const MyNodeGraph = graphRuntime.NodeGraph(
    NodeDefinitions,
    node_graph_blueprint,
);

pub const interface = struct {
    pub fn helloSliceHiHi(faces: []subdiv.Face) ![]subdiv.Face {
        const allocator = std.heap.page_allocator;
        return std.mem.concat(allocator, subdiv.Face, &.{ faces, &.{&.{ 4, 5, 6 }} });
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

    const SpriteSheetRaw = struct {
        png: []const u8,
        json: []const u8,
    };
    pub fn getAllResources() !struct {
        smile_test: struct { data: []const u8, width: usize, height: usize },
    } {
        const allocator = std.heap.page_allocator;

        // const animations = .{
        //     "Attack",
        //     "AttackStartup",
        //     "Idle-loop",
        //     "Run-loop",
        //     "RunEnd",
        //     "RunStart",
        // };
        // const base_name = "content/RoyalArcher_FullHD_";
        // const file_extensions = .{ ".png", ".json" };
        // var fields: []const []std.builtin.Type.StructField = .{};
        // inline for (animations) |animation| for (file_extensions) |extension| {
        //     const file_path = base_name ++ animation ++ extension;
        //     const file_data = @embedFile(file_path);
        //     fields = fields ++ &std.builtin.Type.StructField{
        //         .alignment = @alignOf([]const u8),
        //         .is_comptime = false,
        //         .name = file_path,
        //         .type = @TypeOf(file_data),
        //     };
        // };
        // const RoyalArcher = @Type(std.builtin.Type{ .Struct = .{
        //     .decls = &.{},
        //     .is_tuple = false,
        //     .layout = .auto,
        //     .fields = fields,
        // } });
        const Png = @import("./zigimg/src/formats/png.zig");

        const png_data = @embedFile("content/RoyalArcher_FullHD_Attack.png");
        var stream_source = std.io.StreamSource{ .const_buffer = std.io.fixedBufferStream(png_data) };
        var default_options = Png.DefaultOptions{};
        const image = try Png.load(&stream_source, allocator, default_options.get());
        return .{
            .smile_test = .{
                .data = switch (image.pixels) {
                    .rgba32 => |rgba| std.mem.sliceAsBytes(rgba),
                    else => @panic("handy axiom"),
                },
                .width = image.width,
                .height = image.height,
            },
        };
    }

    var previous_outputs_hash: u32 = 0;
    var my_node_graph = MyNodeGraph{
        .allocator = std.heap.page_allocator,
        .store = .{
            .blueprint = .{
                .nodes = &.{},
                .output = &.{},
                .store = &.{},
            },
            .node_dimensions = &.{},
            .interaction_state = .{
                .node_selection = &.{},
            },
            .camera = .{},
            .context_menu = .{
                .open = false,
                .location = .{ .x = 0, .y = 0 },
                .options = &.{},
            },
        },
    };

    pub fn callNodeGraph(
        inputs: MyNodeGraph.SystemInputs,
    ) !struct {
        outputs: ?MyNodeGraph.SystemOutputs,
    } {
        const outputs = try my_node_graph.update(inputs);
        // const send_outputs = true;
        const send_outputs = blk: {
            var hasher = std.hash.Adler32.init();
            std.hash.autoHashStrat(&hasher, outputs, .DeepRecursive);
            defer previous_outputs_hash = hasher.final();
            break :blk hasher.final() != previous_outputs_hash;
        };
        return .{
            .outputs = if (send_outputs) outputs else null,
        };
    }
};

pub const InterfaceEnum = DeclsToEnum(interface);

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
