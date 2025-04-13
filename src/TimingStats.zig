const std = @import("std");
const json = std.json;

// Structure to hold and calculate timing statistics
const history_size = 120; // How many samples to keep

times_ns: [history_size]u64 = .{0} ** history_size,
index: usize = 0, // Current index in the circular buffer
count: usize = 0, // Number of valid entries (up to buffer size)

// Calculated statistics
avg_ms: f64 = 0,
p99_ms: f64 = 0, // 1% high (99th percentile)
p999_ms: f64 = 0, // 0.1% high (99.9th percentile)

const perf_json_filename = "timing_stats.json";

pub fn saveJson(self: @This()) !void {

    // Only save if we have collected some stats
    if (self.count == 0) {
        std.debug.print("No timing stats collected, skipping JSON save.\n", .{});
        return;
    }

    // Prepare the data structure
    const stats_to_save = .{
        .avg_ms = self.avg_ms,
        .p99_ms = self.p99_ms,
        .p999_ms = self.p999_ms,
    };

    // Create/overwrite the file.
    // Using createFile ensures it truncates if it exists.
    var file = try std.fs.cwd().createFile(perf_json_filename, .{});
    defer file.close();

    // Use a buffered writer for potentially better performance
    var buf_writer = std.io.bufferedWriter(file.writer());

    // Stringify the data directly to the buffered writer
    // Using .pretty = true makes the JSON file human-readable
    try json.stringify(stats_to_save, .{ .whitespace = .indent_4 }, buf_writer.writer());

    // Ensure all buffered data is written to the file
    try buf_writer.flush();

    std.debug.print("Performance stats saved to {s}\n", .{perf_json_filename});
}

// Helper function to determine text color based on millisecond timing
pub fn getTimingColor(ms: f64) [4]f32 {
    if (ms > 16.0) {
        return .{ 1.0, 0.0, 0.0, 1.0 }; // Red
    } else if (ms > 8.0) {
        return .{ 1.0, 0.4, 0.0, 1.0 }; // Red-Orange
    } else if (ms > 4.0) {
        return .{ 1.0, 0.65, 0.0, 1.0 }; // Orange
    } else if (ms > 2.0) {
        return .{ 1.0, 0.85, 0.4, 1.0 }; // Orange-Yellow
    } else if (ms > 1.0) {
        return .{ 1.0, 1.0, 0.7, 1.0 }; // Light Yellow
    } else {
        // Default color (e.g., white or use zgui.getStyleColorVec4(.text))
        // For simplicity, let's use white here.
        return .{ 1.0, 1.0, 1.0, 1.0 }; // White
    }
}

// Adds a new sample time in nanoseconds
pub fn addSample(self: *@This(), arena: std.mem.Allocator, duration_ns: u64) void {
    self.times_ns[self.index] = duration_ns;
    self.index = (self.index + 1) % history_size;
    if (self.count < history_size) {
        self.count += 1;
    }
    if (self.count == 0) {
        self.avg_ms = 0.0;
        self.p99_ms = 0.0;
        self.p999_ms = 0.0;
        return;
    }

    const valid_times = self.times_ns[0..self.count];

    // Calculate Average
    var sum_ns: u128 = 0;
    for (valid_times) |t| {
        sum_ns += t;
    }
    self.avg_ms = @as(f64, @floatFromInt(sum_ns)) / @as(f64, @floatFromInt(self.count)) / 1_000_000.0;

    // Calculate Percentiles (requires sorting a copy)
    var sorted_times_list = std.ArrayList(u64).init(arena);

    sorted_times_list.appendSlice(valid_times) catch unreachable;
    std.sort.pdq(u64, sorted_times_list.items, {}, std.sort.asc(u64));
    const sorted_times = sorted_times_list.items;

    // P99 (1% high)
    const p99_float_index = @floor(@as(f64, @floatFromInt(self.count)) * 0.99);
    const p99_index = @min(self.count - 1, @as(u64, @intFromFloat(p99_float_index)));
    self.p99_ms = @as(f64, @floatFromInt(sorted_times[p99_index])) / 1_000_000.0;

    // P99.9 (0.1% high)
    const p999_float_index = @floor(@as(f64, @floatFromInt(self.count)) * 0.999);
    const p999_index = @min(self.count - 1, @as(u64, @intFromFloat(p999_float_index)));
    self.p999_ms = @as(f64, @floatFromInt(sorted_times[p999_index])) / 1_000_000.0;
}
