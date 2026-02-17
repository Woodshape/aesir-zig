const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");

pub const entity = @import("entity.zig");
pub const animation_mod = @import("animation.zig");
pub const enemy_mod = @import("enemy.zig");

const Entity = entity.Entity;
const EntityHandle = entity.EntityHandle;
const GameState = entity.GameState;
const Player = entity.Player;
const Skeleton = enemy_mod.Skeleton;
const Animation = animation_mod.Animation;
const ANIMATION_SCALE = animation_mod.ANIMATION_SCALE;

const WINDOW_WIDTH: i32 = 1280;
const WINDOW_HEIGHT: i32 = 720;

const JUMP_FORCE: f32 = 600.0;
const SPEED: f32 = 400.0;
const GRAVITY: f32 = 2000.0;

const TICK_TIME: f64 = 1.0;

const Input = struct {
    move_left: bool = false,
    move_right: bool = false,
    jump: bool = false,
};

const WeaponSprite = struct {
    texture: rl.Texture2D = std.mem.zeroes(rl.Texture2D),
};

const Weapon = struct {
    sprite: WeaponSprite = .{},
    rotation_angle: f32 = 0,
    offset: rl.Vector2 = .{ .x = 0, .y = 0 },
    origin: rl.Vector2 = .{ .x = 0, .y = 0 },
};

fn updateWeaponAim(player: *Entity, weapon: *Weapon, mouse_pos: rl.Vector2) void {
    const dir_x = mouse_pos.x - player.pos.x;
    const dir_y = mouse_pos.y - player.pos.y;

    const angle_rad = std.math.atan2(dir_y, dir_x);
    weapon.rotation_angle = angle_rad * (180.0 / std.math.pi);

    const distance: f32 = 50.0;

    weapon.offset.x = @cos(angle_rad) * distance;
    weapon.offset.y = @sin(angle_rad) * distance;
}

fn canJump(p: Player, jumps_taken: u8) bool {
    return jumps_taken <= p.extra_jumps;
}

fn handleInput() Input {
    return .{
        .move_left = rl.isKeyDown(.left) or rl.isKeyDown(.a),
        .move_right = rl.isKeyDown(.right) or rl.isKeyDown(.d),
        .jump = rl.isKeyPressed(.space),
    };
}

fn drawWeapon(weapon: Weapon, player: Entity) void {
    const weapon_sprite = weapon.sprite.texture;

    const player_anim = player.animation;
    const player_width = @as(f32, @floatFromInt(player_anim.sprite.texture.width)) /
        @as(f32, @floatFromInt(player_anim.sprite.data.frames)) *
        player_anim.data.scale.x;
    const player_height = @as(f32, @floatFromInt(player_anim.sprite.texture.height)) * player_anim.data.scale.y;
    const player_center_x = player.pos.x + player_width * 0.5;
    const player_center_y = player.pos.y + player_height * 0.5;

    rl.drawTexturePro(
        weapon_sprite,
        .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(weapon_sprite.width),
            .height = @floatFromInt(weapon_sprite.height),
        },
        .{
            .x = player_center_x + weapon.offset.x,
            .y = player_center_y + weapon.offset.y,
            .width = @as(f32, @floatFromInt(weapon_sprite.width)) * ANIMATION_SCALE.x,
            .height = @as(f32, @floatFromInt(weapon_sprite.height)) * ANIMATION_SCALE.y,
        },
        weapon.origin,
        weapon.rotation_angle,
        rl.Color.white,
    );
}

pub fn main() void {
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Aesir");
    defer rl.closeWindow();
    rl.setTargetFPS(120);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var state = GameState.init(std.heap.page_allocator);
    defer state.deinit();

    animation_mod.loadAnimationData();

    const player_entity = state.createEntity(.{ .player = .{ .jump_force = JUMP_FORCE } });
    player_entity.pos = .{ .x = @as(f32, @floatFromInt(WINDOW_WIDTH)) / 2.0, .y = @as(f32, @floatFromInt(WINDOW_HEIGHT)) / 2.0 };

    var weapon = Weapon{};
    weapon.sprite.texture = rl.loadTexture("res/images/sword.png") catch std.mem.zeroes(rl.Texture2D);
    weapon.origin = .{
        .x = @as(f32, @floatFromInt(weapon.sprite.texture.width)) * 0.5,
        .y = 64,
    };

    // Spawn some random enemies
    var prng = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    const random = prng.random();
    for (0..10) |_| {
        const r = random.float(f32);
        if (r > 0.5) continue;
        const bones: i32 = @intCast(random.intRangeAtMost(u32, 1, 10));
        _ = state.createEntity(.{ .skeleton = .{ .bones = bones } });
    }

    const player = player_entity.as(Player) orelse unreachable;

    var delta_t: f32 = 0;
    var player_dead: bool = false;
    var jumps: u8 = 0;

    // Debug text buffer
    var buf: [256]u8 = undefined;

    while (!rl.windowShouldClose()) {
        // Clear scratch
        _ = arena.reset(.retain_capacity);
        state.scratch_dirty = true;

        // Update timing
        delta_t = rl.getFrameTime();
        state.time_elapsed += @as(f64, @floatCast(delta_t));
        state.ticks = @intFromFloat(state.time_elapsed / TICK_TIME);

        const input = handleInput();

        if (!player_dead) {
            if (input.move_left) {
                player_entity.vel.x = -SPEED;
                player_entity.flip_x = true;
                _ = animation_mod.changeAnimation(&player_entity.animation, animation_mod.animations.get(.player_run));
            } else if (input.move_right) {
                player_entity.vel.x = SPEED;
                player_entity.flip_x = false;
                _ = animation_mod.changeAnimation(&player_entity.animation, animation_mod.animations.get(.player_run));
            } else {
                player_entity.vel.x = 0.0;
                _ = animation_mod.changeAnimation(&player_entity.animation, animation_mod.animations.get(.player_idle));
            }
        }

        if (rl.isKeyPressed(.f)) {
            _ = animation_mod.changeAnimation(&player_entity.animation, animation_mod.animations.get(.player_death));
            player_dead = !player_dead;
            player_entity.vel.x = 0.0;
        }

        player_entity.vel.y += GRAVITY * delta_t;

        if (input.jump and canJump(player.*, jumps)) {
            player_entity.vel.y = -player.jump_force;
            player.grounded = false;
            jumps += 1;
        }

        player_entity.pos.x += player_entity.vel.x * delta_t;
        player_entity.pos.y += player_entity.vel.y * delta_t;

        const floor_pos: f32 = @as(f32, @floatFromInt(rl.getScreenHeight())) - 96;
        if (player_entity.pos.y > floor_pos) {
            player_entity.pos.y = floor_pos;
            player.grounded = true;
            jumps = 0;
        }

        updateWeaponAim(player_entity, &weapon, rl.getMousePosition());
        _ = animation_mod.updateAnimation(&player_entity.animation, delta_t);

        rl.beginDrawing();
        rl.clearBackground(rl.Color.sky_blue);

        animation_mod.drawAnimation(player_entity.animation, player_entity.pos, player_entity.flip_x);
        drawWeapon(weapon, player_entity.*);

        if (player_dead) {
            rl.drawText("You are Dead", @divTrunc(WINDOW_WIDTH, 2) - 200, @divTrunc(WINDOW_HEIGHT, 2), 50, rl.Color.black);
        }

        // Debug text overlay
        const ents = state.getAllEntities(arena.allocator());

        const delta_text = std.fmt.bufPrintZ(&buf, "delta: {d:.6}", .{delta_t}) catch "???";
        rl.drawText(delta_text, 10, 10, 20, rl.Color.black);

        const elapsed_text = std.fmt.bufPrintZ(&buf, "elapsed: {d:.2}", .{state.time_elapsed}) catch "???";
        rl.drawText(elapsed_text, 10, 30, 20, rl.Color.black);

        const ticks_text = std.fmt.bufPrintZ(&buf, "ticks: {d}", .{state.ticks}) catch "???";
        rl.drawText(ticks_text, 10, 50, 20, rl.Color.black);

        const ents_text = std.fmt.bufPrintZ(&buf, "ents: {d}", .{ents.len}) catch "???";
        rl.drawText(ents_text, 10, 70, 20, rl.Color.black);

        rl.drawFPS(WINDOW_WIDTH - 100, 10);

        rl.endDrawing();
    }
}

// Tests
test "player jump" {
    const p = Player{
        .extra_jumps = 1,
    };

    try std.testing.expect(canJump(p, 0));
    try std.testing.expect(canJump(p, 1));
    try std.testing.expect(!canJump(p, 2));
}

test {
    _ = entity;
    _ = animation_mod;
    _ = enemy_mod;
}
