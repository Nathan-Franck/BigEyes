const std = @import("std");
const zmath = @import("zmath");
const meta = @import("./MetaMaster.zig");

pub fn main() !void {
    const thinger: meta.PickField(struct { first: u32, second: f32 }, .first) = .{ .first = 1 };
    std.debug.print("Hello, world! {?}\n", .{thinger.first});
}

fn StateLoop(systems: anytype) type {
    _ = systems; // autofix
    return struct {};
}

const Settings = struct {
    gravity: f32,
    player_speed: f32,
};

const Vec2 = @Vector(2, f32);

const Time = struct {
    current: f32,
    delta: f32,
};

const Physics2D = struct {
    velocity: Vec2,
    position: Vec2,
};

// Easy composition using structs! 💪
const Player = struct {
    input: struct {
        jump: bool,
        left: bool,
        right: bool,
    },
    physics: Physics2D,

    fn randomInput(
        random: *std.rand.Random,
    ) struct { player: meta.PickField(@This(), .input) } {
        return .{ .player = .{ .input = .{
            .jump = random.int() % 10 == 0,
            .left = random.int() % 2 == 0,
            .right = random.int() % 2 == 0,
        } } };
    }

    fn movement(
        // Query from the state loop to get relevant data for this system! 🤓
        player: @This(),
        time: Time,
        settings: Settings,
    ) struct { player: meta.PickField(@This(), .physics) } {
        const velocity = .{
            .x = player.physics.velocity.x + (player.input.right - player.input.left) * time.delta * settings.player_speed,
            .y = player.physics.velocity.y - time.delta * settings.gravity,
        };
        // Write back some data! 📝
        return .{ .player = .{ .physics = .{
            .velocity = velocity,
            .position = player.physics.position + velocity * time.delta,
        } } };
    }

    fn render(
        player: @This(),
    ) void {
        std.debug.print("player position: {s} ... TODO actual render 😀\n", .{player.physics.position});
    }
};

test "first" {
    var random = std.rand.Isaac64.init(0).random();

    // Exclicitly set all order of systems! 🛠️
    const MyGameLoop = StateLoop(.{
        Player.randomInput,
        Player.movement,
        Player.render,
    });

    const my_game_loop = MyGameLoop{
        .random = &random,
        .settings = .{
            .gravity = 9.8,
            .player_speed = 10,
        },
        .time = 0,
        .delta_time = 0,
        .player = .{
            .input = .{
                .jump = false,
                .left = false,
                .right = false,
            },
            .physics = .{
                .velocity = .{ .x = 0, .y = 0 },
                .position = .{ .x = 0, .y = 0 },
            },
        },
    };

    _ = my_game_loop;
}
