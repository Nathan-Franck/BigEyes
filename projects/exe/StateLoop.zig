fn StateLoop(systems: anytype) type {
    _ = systems; // autofix
    return struct {};
}

const std = @import("std");
const zmath = @import("zmath");

const Settings = struct {
    gravity: f32,
    player_speed: f32,
};

const Input = struct {
    jump: bool,
    left: bool,
    right: bool,
};

const Vector2 = @Vector(2, f32);

const Time = struct {
    current: f32,
    delta: f32,
};

const Physics2D = struct {
    velocity: Vector2,
    position: Vector2,
};

const Player = struct {
    fn randomInput(
        random: *std.rand.Random,
    ) struct {
        input: Input,
    } {
        return .{ .input = .{
            .jump = random.int() % 10 == 0,
            .left = random.int() % 2 == 0,
            .right = random.int() % 2 == 0,
        } };
    }
    fn movement(
        input: Input,
        player_physics: Physics2D,
        time: Time,
        settings: Settings,
    ) struct {
        player_physics: Physics2D,
    } {
        const velocity = .{
            .x = player_physics.velocity.x + (input.right - input.left) * time.delta * settings.player_speed,
            .y = player_physics.velocity.y - time.delta * settings.gravity,
        };
        return .{ .player_physics = .{
            .velocity = velocity,
            .position = player_physics.position + velocity * time.delta,
        } };
    }
};

test "first" {
    var random = std.rand.Isaac64.init(0).random();

    const MyGameLoop = StateLoop(.{
        Player.randomInput,
        Player.movement,
    });
    const my_game_loop = MyGameLoop{
        .random = &random,
        .settings = .{
            .gravity = 9.8,
            .player_speed = 10,
        },
        .time = 0,
        .delta_time = 0,
    };
    _ = my_game_loop;
}
