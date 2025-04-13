const std = @import("std");

// Structure to hold and calculate timing statistics
const history_size = 120; // How many samples to keep

times_ns: [history_size]u64 = .{0} ** history_size,
index: usize = 0, // Current index in the circular buffer
count: usize = 0, // Number of valid entries (up to buffer size)

// Calculated statistics
avg_ms: f64 = 0,
p99_ms: f64 = 0, // 1% high (99th percentile)
p999_ms: f64 = 0, // 0.1% high (99.9th percentile)

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
