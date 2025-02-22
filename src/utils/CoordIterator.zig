pub const Coord = @Vector(2, i32);

total: usize,
next_coord: Coord,
min_coord: Coord,
max_coord: Coord,

pub fn init(min_coord: Coord, max_coord: Coord) @This() {
    return .{
        .total = @intCast((max_coord[0] - min_coord[0]) * (max_coord[1] - min_coord[1])), // TODO - use @reduce and vector subtraction instead
        .next_coord = .{ min_coord[0] - 1, min_coord[1] },
        .min_coord = min_coord,
        .max_coord = max_coord,
    };
}

pub fn width(self: @This()) i32 {
    return self.max_coord[0] - self.min_coord[0];
}

pub fn next(self: *@This()) ?Coord {
    self.next_coord[0] += 1;
    if (self.next_coord[0] >= self.max_coord[0]) {
        self.next_coord[0] = self.min_coord[0];
        self.next_coord[1] += 1;
        if (self.next_coord[1] >= self.max_coord[1]) {
            return null;
        }
    }
    return self.next_coord;
}
