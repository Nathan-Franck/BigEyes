const Coord = @import("./forest.zig").Coord;
const Vec2 = @import("./forest.zig").Vec2;

size: f32,
resolution: struct { x: u32, y: u32 },
heights: []const f32,
// mask: []f32, // Do we need a mask?

inline fn sample(self: @This(), coord: Coord) f32 {
    const index = @as(usize, @intCast(coord[0] + coord[1] * @as(i32, @intCast(self.resolution.x))));
    return self.heights[index];
}

pub fn getHeight(
    self: *const @This(),
    spawn_pos: Vec2,
    pos_2d: Vec2,
) ?f32 {
    const rel_pos = (pos_2d - spawn_pos) / @as(Vec2, @splat(self.size));
    const stamp_pos = (rel_pos + @as(Vec2, @splat(0.5))) * Vec2{
        @floatFromInt(self.resolution.x - 1),
        @floatFromInt(self.resolution.y - 1),
    };

    if (@reduce(.Or, stamp_pos < @as(Vec2, @splat(1))) or
        @reduce(.Or, stamp_pos >= @as(Vec2, @splat(@floatFromInt(self.resolution.x - 1)))))
    {
        return null;
    }
    const pos0 = @floor(stamp_pos);
    const pos_int: Coord = @intFromFloat(pos0);
    const fract = stamp_pos - pos0;

    const h00 = self.sample(pos_int + Coord{ 0, 0 });
    const h10 = self.sample(pos_int + Coord{ 1, 0 });
    const h01 = self.sample(pos_int + Coord{ 0, 1 });
    const h11 = self.sample(pos_int + Coord{ 1, 1 });

    const h0 = h00 * (1 - fract[0]) + h10 * fract[0];
    const h1 = h01 * (1 - fract[0]) + h11 * fract[0];
    const stamp_height = h0 * (1 - fract[1]) + h1 * fract[1];
    return stamp_height;
}
