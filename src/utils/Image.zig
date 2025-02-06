const std = @import("std");
const PngFormat = @import("./zigimg/src/formats/png.zig");
const Image = @import("./zigimg/src/Image.zig");
const Rgba32 = @import("./zigimg/src/color.zig").Rgba32;

const ImageSizeLimit = 4096;
pub const Rgba32Image = struct {
    pixels: []Rgba32,
    width: usize,
    height: usize,
};

pub fn loadPng(
    allocator: std.mem.Allocator,
    png_data: []const u8,
) !Rgba32Image {
    var stream_source = std.io.StreamSource{ .const_buffer = std.io.fixedBufferStream(png_data) };
    var default_options = PngFormat.DefaultOptions{};
    const image_data = try PngFormat.load(&stream_source, allocator, default_options.get());
    switch (image_data.pixels) {
        .rgba32 => |rgba| return .{
            .pixels = rgba,
            .width = image_data.width,
            .height = image_data.height,
        },
        else => @panic("handy axiom"),
    }
}

pub fn processImageForGPU(
    allocator: std.mem.Allocator,
    image_data: Rgba32Image,
) !Processed {
    const data = std.mem.sliceAsBytes(image_data.pixels);
    if (image_data.width > ImageSizeLimit or image_data.height > ImageSizeLimit) {
        // Return a down-sampled version instead
        var dimensions: struct { width: usize, height: usize } = .{ .width = image_data.width, .height = image_data.height };
        var downSampleRate: u8 = 1;
        while (dimensions.width > ImageSizeLimit or dimensions.height > ImageSizeLimit) {
            downSampleRate *= 2;
            dimensions.width /= 2;
            dimensions.height /= 2;
        }

        var new_data = try allocator.alloc(u8, dimensions.width * dimensions.height * 4);
        for (0..dimensions.height) |y| {
            for (0..dimensions.width) |x| {
                var pixel_accum = [4]u32{ 0, 0, 0, 0 };
                for (0..downSampleRate) |sy| {
                    for (0..downSampleRate) |sx| {
                        if (x * downSampleRate + sx < image_data.width and y * downSampleRate + sy < image_data.height) {
                            const sample_index = 4 * (image_data.width * (y * downSampleRate + sy) + x * downSampleRate + sx);
                            const pixel = data[sample_index .. sample_index + 4];
                            pixel_accum[0] += pixel[0];
                            pixel_accum[1] += pixel[1];
                            pixel_accum[2] += pixel[2];
                            pixel_accum[3] += pixel[3];
                        }
                    }
                }
                const pixel_index = 4 * (dimensions.width * y + x);
                new_data[pixel_index + 0] = @intCast(pixel_accum[0] / downSampleRate / downSampleRate);
                new_data[pixel_index + 1] = @intCast(pixel_accum[1] / downSampleRate / downSampleRate);
                new_data[pixel_index + 2] = @intCast(pixel_accum[2] / downSampleRate / downSampleRate);
                new_data[pixel_index + 3] = @intCast(pixel_accum[3] / downSampleRate / downSampleRate);
            }
        }
        return .{
            .data = new_data,
            .width = dimensions.width,
            .height = dimensions.height,
            .scale = downSampleRate,
        };
    }
    return .{
        .data = data,
        .width = image_data.width,
        .height = image_data.height,
        .scale = 1,
    };
}

pub const Processed = struct {
    data: []const u8,
    width: usize,
    height: usize,
    scale: u8, // If we downsample, we have to declare that we have to scale up upon displaying.
};

pub fn loadPngAndProcess(
    allocator: std.mem.Allocator,
    png_data: []const u8,
) !Processed {
    const image_data = try loadPng(allocator, png_data);
    return processImageForGPU(allocator, image_data);
}
