pub const types = @import("utils").types;
pub const config = @import("config.zig");
pub const mesh_loader = @import("mesh_loader.zig");

const std = @import("std");

const Image = @import("utils").Image;
const raytrace = @import("utils").raytrace;
const tree = @import("utils").tree;

pub export fn getResources(resources: *types.Resources) void {
    const arena = std.heap.page_allocator;
    const result = mesh_loader.loadModelsFromBlends(arena, &.{
        .{ .model_name = "ebike" },
        .{ .model_name = "Sonic (rough)", .subdiv_level = 2 },
    }) catch unreachable;

    const skybox = blk: {
        var images: types.ProcessedCubeMap = undefined;
        inline for (@typeInfo(types.ProcessedCubeMap).@"struct".fields) |field| {
            const image_png = @embedFile("./content/cloudy skybox/" ++ field.name ++ ".png");
            const image_data = Image.loadPngAndProcess(arena, image_png) catch unreachable;
            @field(images, field.name) = image_data;
        }
        break :blk images;
    };

    const cutout_leaf = blk: {
        const diffuse = Image.loadPng(arena, @embedFile("./content/manitoba maple/diffuse.png")) catch unreachable;
        const alpha = Image.loadPng(arena, @embedFile("./content/manitoba maple/alpha.png")) catch unreachable;
        const cutout_diffuse = Image.Rgba32Image{
            .width = diffuse.width,
            .height = diffuse.height,
            .pixels = arena.alloc(@TypeOf(diffuse.pixels[0]), diffuse.pixels.len) catch unreachable,
        };
        for (cutout_diffuse.pixels, 0..) |*pixel, pixel_index| {
            pixel.* = diffuse.pixels[pixel_index];
            pixel.*.a = alpha.pixels[pixel_index].r;
        }
        break :blk Image.processImageForGPU(arena, cutout_diffuse) catch unreachable;
    };

    var trees = std.ArrayList(types.TreeMesh).init(arena);
    inline for (@typeInfo(config.ForestSettings).@"struct".decls) |decl| {
        const tree_blueprint = @field(config.Trees, decl.name);
        const tree_skeleton = tree.generateStructure(arena, tree_blueprint.structure) catch unreachable;
        const bark_mesh = tree.generateTaperedWood(arena, tree_skeleton, tree_blueprint.mesh) catch unreachable;
        const leaf_mesh = tree.generateLeaves(arena, tree_skeleton, tree_blueprint.mesh) catch unreachable;
        const bounds = raytrace.Bounds.encompassBounds(
            raytrace.Bounds.encompassPoints(bark_mesh.vertices.slice().items(.position)),
            raytrace.Bounds.encompassPoints(leaf_mesh.vertices.slice().items(.position)),
        );
        trees.append(types.TreeMesh{
            .label = decl.name,
            .skeleton = tree_skeleton,
            .bark_mesh = bark_mesh,
            .leaf_mesh = leaf_mesh,
            .bounds = bounds,
        }) catch unreachable;
    }

    resources.* = types.Resources{
        .models = result.models.items,
        .model_transforms = result.model_transforms,
        .skybox = skybox,
        .cutout_leaf = cutout_leaf,
        .trees = trees.items,
    };
}
