const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");

pub const entity = @import("entity.zig");
pub const animation_mod = @import("animation.zig");
pub const enemy_mod = @import("enemy.zig");
pub const weapon_mod = @import("weapon.zig");

const Entity = entity.Entity;
const EntityHandle = entity.EntityHandle;
const GameState = entity.GameState;
const Player = entity.Player;
const Skeleton = enemy_mod.Skeleton;
const Animation = animation_mod.Animation;
const ANIMATION_SCALE = animation_mod.ANIMATION_SCALE;
const Weapon = weapon_mod.Weapon;

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

const AttackState = struct {
    is_attacking: bool = false,
    timer: f32 = 0,
    duration: f32 = 0,
    start_angle: f32 = 0,
    target_angle: f32 = 0,
    base_angle: f32 = 0, // angle to mouse when attack started
};

fn updateWeaponAim(player: *Entity, weapon: *Weapon, state: *AttackState, mouse_pos: rl.Vector2) void {
    const player_anim = player.animation;
    const player_width = @as(f32, @floatFromInt(player_anim.sprite.texture.width)) /
        @as(f32, @floatFromInt(player_anim.sprite.data.frames)) * player_anim.data.scale.x;
    const player_height = @as(f32, @floatFromInt(player_anim.sprite.texture.height)) * player_anim.data.scale.y;

    const player_center_x = player.pos.x + player_width * 0.5;
    const player_center_y = player.pos.y + player_height * 0.5;

    const dir_x = mouse_pos.x - player_center_x;
    const dir_y = mouse_pos.y - player_center_y;

    if (!state.is_attacking) {
        const angle_rad = std.math.atan2(dir_y, dir_x);
        weapon.rotation_angle = angle_rad * (180.0 / std.math.pi);

        const distance: f32 = 60.0; // orbiting distance from center

        weapon.offset.x = @cos(angle_rad) * distance;
        weapon.offset.y = @sin(angle_rad) * distance;
    } else {
        const progress = state.timer / state.duration; // 0.0 to 1.0 (actually going backwards 1.0 -> 0.0, so we do 1.0 - progress)
        const t = 1.0 - progress;

        // Simple ease-out cubic
        const ease_t = 1.0 - std.math.pow(f32, 1.0 - t, 3.0);

        if (weapon.stats.animation_type == .swing) {
            weapon.rotation_angle = state.start_angle + (state.target_angle - state.start_angle) * ease_t;

            const distance: f32 = 60.0;
            const angle_rad = weapon.rotation_angle * (std.math.pi / 180.0);
            weapon.offset.x = @cos(angle_rad) * distance;
            weapon.offset.y = @sin(angle_rad) * distance;
        } else if (weapon.stats.animation_type == .thrust) {
            weapon.rotation_angle = state.base_angle;

            // Thrust distance: goes out and comes back
            // peak at t = 0.5
            const dist_t = if (t < 0.5) t * 2.0 else (1.0 - t) * 2.0;
            const ease_dist = 1.0 - std.math.pow(f32, 1.0 - dist_t, 2.0); // ease-out

            const distance: f32 = 60.0 + weapon.stats.reach * ease_dist;

            const angle_rad = weapon.rotation_angle * (std.math.pi / 180.0);
            weapon.offset.x = @cos(angle_rad) * distance;
            weapon.offset.y = @sin(angle_rad) * distance;
        }
    }
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
        weapon.rotation_angle + 90.0,
        weapon.rarity.getColor(),
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

    var prng = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    const random = prng.random();

    const base_weapon_tex = rl.loadTexture("res/images/sword.png") catch std.mem.zeroes(rl.Texture2D);

    var weapon = Weapon.generateRandomWeapon(random);
    weapon.sprite.texture = base_weapon_tex;
    // Set origin to bottom center of the weapon passing its actual height
    weapon.origin = .{
        .x = @as(f32, @floatFromInt(base_weapon_tex.width)) * 0.5,
        .y = @as(f32, @floatFromInt(base_weapon_tex.height)),
    };

    for (0..20) |_| {
        const r = random.float(f32);
        if (r > 0.5) continue;
        const bones: i32 = @intCast(random.intRangeAtMost(u32, 1, 10));
        const e = state.createEntity(.{ .skeleton = .{ .bones = bones } });
        e.hp = 50 + @as(i32, @intCast(bones)) * 5;
        e.pos = .{
            .x = random.float(f32) * @as(f32, @floatFromInt(WINDOW_WIDTH)),
            .y = @as(f32, @floatFromInt(WINDOW_HEIGHT)) - 96.0,
        };
        e.radius = 20.0;
    }

    const player = player_entity.as(Player) orelse unreachable;

    var delta_t: f32 = 0;
    var player_dead: bool = false;
    var jumps: u8 = 0;
    var attack_timer: f32 = 0;
    var attack_state: AttackState = .{};

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

        if (attack_timer > 0) {
            attack_timer -= delta_t;
        }

        if (attack_state.is_attacking) {
            attack_state.timer -= delta_t;
            if (attack_state.timer <= 0) {
                attack_state.is_attacking = false;
            }
        }

        if (rl.isKeyPressed(.e)) {
            weapon = Weapon.generateRandomWeapon(random);
            weapon.sprite.texture = base_weapon_tex;
            weapon.origin = .{
                .x = @as(f32, @floatFromInt(base_weapon_tex.width)) * 0.5,
                .y = @as(f32, @floatFromInt(base_weapon_tex.height)),
            };
        }

        if (rl.isMouseButtonDown(.left) and attack_timer <= 0 and !player_dead) {
            attack_timer = 1.0 / weapon.stats.attack_speed;

            if (weapon.stats.animation_type != .none) {
                attack_state.is_attacking = true;
                attack_state.duration = weapon.stats.life_time;
                attack_state.timer = attack_state.duration;

                const player_width = @as(f32, @floatFromInt(player_entity.animation.sprite.texture.width)) /
                    @as(f32, @floatFromInt(player_entity.animation.sprite.data.frames)) * player_entity.animation.data.scale.x;
                const player_height = @as(f32, @floatFromInt(player_entity.animation.sprite.texture.height)) * player_entity.animation.data.scale.y;

                const player_center_x = player_entity.pos.x + player_width * 0.5;
                const player_center_y = player_entity.pos.y + player_height * 0.5;

                const mouse_pos = rl.getMousePosition();
                const dir_x = mouse_pos.x - player_center_x;
                const dir_y = mouse_pos.y - player_center_y;

                const angle_rad = std.math.atan2(dir_y, dir_x);
                attack_state.base_angle = angle_rad * (180.0 / std.math.pi);

                if (weapon.stats.animation_type == .swing) {
                    // Swing from -60 to +60 degrees
                    attack_state.start_angle = attack_state.base_angle - 60.0;
                    attack_state.target_angle = attack_state.base_angle + 60.0;

                    // Flip swing direction if player is facing left
                    if (mouse_pos.x < player_center_x) {
                        attack_state.start_angle = attack_state.base_angle + 60.0;
                        attack_state.target_angle = attack_state.base_angle - 60.0;
                    }
                }
            }

            const player_width = @as(f32, @floatFromInt(player_entity.animation.sprite.texture.width)) /
                @as(f32, @floatFromInt(player_entity.animation.sprite.data.frames)) * player_entity.animation.data.scale.x;
            const player_height = @as(f32, @floatFromInt(player_entity.animation.sprite.texture.height)) * player_entity.animation.data.scale.y;

            const spawn_pos = rl.Vector2{
                .x = player_entity.pos.x + player_width * 0.5 + weapon.offset.x,
                .y = player_entity.pos.y + player_height * 0.5 + weapon.offset.y,
            };

            const rad = weapon.rotation_angle * (std.math.pi / 180.0);
            const dir = rl.Vector2{ .x = @cos(rad), .y = @sin(rad) };

            var proj = state.createEntity(.{ .projectile = .{
                .damage = weapon.stats.damage,
                .life_time = weapon.stats.life_time,
                .pierce_count = weapon.stats.piercing,
                .shooter_id = player_entity.handle.id,
                .is_melee = (weapon.weapon_type == .sword or weapon.weapon_type == .spear),
                .color = weapon.rarity.getColor(),
            } });

            proj.pos = spawn_pos;
            proj.vel = .{ .x = dir.x * weapon.stats.projectile_speed, .y = dir.y * weapon.stats.projectile_speed };
            if (weapon.weapon_type == .sword) {
                proj.radius = 35.0;
            } else if (weapon.weapon_type == .spear) {
                proj.radius = 20.0;
            } else {
                proj.radius = 10.0;
            }
        }

        // Projectile update and collision
        const active_ents = state.getAllEntities(arena.allocator());
        for (active_ents) |handle| {
            if (state.entityFromHandle(handle)) |e| {
                if (e.as(entity.Projectile)) |proj| {
                    if (proj.life_time <= 0) {
                        state.destroyEntity(e);
                        continue;
                    }

                    if (!proj.is_melee) {
                        e.pos.x += e.vel.x * delta_t;
                        e.pos.y += e.vel.y * delta_t;
                    } else {
                        // Melee hitbox follows weapon
                        const player_width = @as(f32, @floatFromInt(player_entity.animation.sprite.texture.width)) /
                            @as(f32, @floatFromInt(player_entity.animation.sprite.data.frames)) * player_entity.animation.data.scale.x;
                        const player_height = @as(f32, @floatFromInt(player_entity.animation.sprite.texture.height)) * player_entity.animation.data.scale.y;
                        e.pos = .{
                            .x = player_entity.pos.x + player_width * 0.5 + weapon.offset.x,
                            .y = player_entity.pos.y + player_height * 0.5 + weapon.offset.y,
                        };
                    }

                    proj.life_time -= delta_t;

                    // Collision checking
                    for (active_ents) |other_handle| {
                        if (handle.id == other_handle.id) continue;
                        if (state.entityFromHandle(other_handle)) |other| {
                            if (other.handle.id == proj.shooter_id) continue;
                            if (other.kind == .projectile) continue;
                            if (other.hp <= 0 and other.kind != .player) continue;

                            // Check distance
                            const dx = e.pos.x - other.pos.x;
                            const dy = e.pos.y - other.pos.y;
                            const dist_sq = dx * dx + dy * dy;
                            const rad_sum = e.radius + other.radius;

                            if (dist_sq <= rad_sum * rad_sum) {
                                if (!proj.hasHit(other.handle.id)) {
                                    proj.addHit(other.handle.id);
                                    other.hp -= proj.damage;
                                    proj.pierce_count -= 1;

                                    if (other.hp <= 0 and other.kind != .player) {
                                        state.destroyEntity(other);
                                    }

                                    if (proj.pierce_count <= 0) {
                                        proj.life_time = 0; // destroy projectile
                                    }
                                }
                            }
                        }
                    }
                }
            }
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

        updateWeaponAim(player_entity, &weapon, &attack_state, rl.getMousePosition());
        _ = animation_mod.updateAnimation(&player_entity.animation, delta_t);

        rl.beginDrawing();
        rl.clearBackground(rl.Color.sky_blue);

        animation_mod.drawAnimation(player_entity.animation, player_entity.pos, player_entity.flip_x);
        drawWeapon(weapon, player_entity.*);

        // Draw projectiles and enemies
        for (state.getAllEntities(arena.allocator())) |handle| {
            if (state.entityFromHandle(handle)) |e| {
                if (e.as(entity.Projectile)) |proj| {
                    if (proj.is_melee) {
                        // Debug draw melee hitbox
                        // rl.drawCircleLines(@intFromFloat(e.pos.x), @intFromFloat(e.pos.y), e.radius, rl.colorAlpha(proj.color, 0.5));
                    } else {
                        rl.drawCircle(@intFromFloat(e.pos.x), @intFromFloat(e.pos.y), e.radius, proj.color);
                    }
                }

                if (e.kind == .skeleton) {
                    rl.drawRectangle(@intFromFloat(e.pos.x - 15), @intFromFloat(e.pos.y - 30), 30, 40, rl.Color.gray);
                    const hp_ratio = std.math.clamp(@as(f32, @floatFromInt(e.hp)) / 100.0, 0.0, 1.0);
                    if (hp_ratio > 0) {
                        rl.drawRectangle(@intFromFloat(e.pos.x - 15), @intFromFloat(e.pos.y - 40), @intFromFloat(30.0 * hp_ratio), 5, rl.Color.red);
                    }
                }
            }
        }

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

        const weapon_text = std.fmt.bufPrintZ(&buf, "Weapon: {s} {s}\nDmg: {d} SPD: {d:.2}", .{ weapon.rarity.getName(), @tagName(weapon.weapon_type), weapon.stats.damage, weapon.stats.attack_speed }) catch "???";
        rl.drawText(weapon_text, 10, WINDOW_HEIGHT - 60, 20, weapon.rarity.getColor());

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
    _ = weapon_mod;
}
