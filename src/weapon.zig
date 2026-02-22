const std = @import("std");
const rl = @import("raylib");

pub const WeaponType = enum {
    sword,
    bow,
    staff,
    spear,
};

pub const AttackAnimationType = enum {
    swing,
    thrust,
    none, // used for ranged weapons
};

pub const WeaponRarity = enum(u3) {
    common = 0,
    uncommon = 1,
    rare = 2,
    epic = 3,
    legendary = 4,

    pub fn getColor(self: WeaponRarity) rl.Color {
        return switch (self) {
            .common => rl.Color.white,
            .uncommon => rl.Color.green,
            .rare => rl.Color.dark_blue,
            .epic => rl.Color.purple,
            .legendary => rl.Color.orange,
        };
    }

    pub fn getStatMultiplier(self: WeaponRarity) f32 {
        return switch (self) {
            .common => 1.0,
            .uncommon => 1.25,
            .rare => 1.5,
            .epic => 2.0,
            .legendary => 3.0,
        };
    }

    pub fn getName(self: WeaponRarity) [:0]const u8 {
        return switch (self) {
            .common => "Common",
            .uncommon => "Uncommon",
            .rare => "Rare",
            .epic => "Epic",
            .legendary => "Legendary",
        };
    }
};

pub const WeaponStats = struct {
    damage: i32,
    attack_speed: f32, // attacks per second
    projectile_speed: f32,
    life_time: f32, // How long the projectile/hitbox lasts
    piercing: i32 = 1,
    reach: f32 = 0, // Extra distance for thrust attacks
    animation_type: AttackAnimationType = .none,
};

pub const WeaponSprite = struct {
    texture: rl.Texture2D = std.mem.zeroes(rl.Texture2D),
};

pub const Weapon = struct {
    weapon_type: WeaponType = .sword,
    rarity: WeaponRarity = .common,
    stats: WeaponStats = .{
        .damage = 10,
        .attack_speed = 1.0,
        .projectile_speed = 0.0,
        .life_time = 0.1,
    },

    sprite: WeaponSprite = .{},
    rotation_angle: f32 = 0,
    offset: rl.Vector2 = .{ .x = 0, .y = 0 },
    origin: rl.Vector2 = .{ .x = 0, .y = 0 },

    pub fn generateRandomWeapon(random: std.Random) Weapon {
        const wt_int = random.intRangeLessThan(u8, 0, 4);
        const w_type: WeaponType = @enumFromInt(wt_int);

        // Weighted rarity:
        // Common 50%, Uncommon 25%, Rare 15%, Epic 8%, Legendary 2%
        const r = random.float(f32);
        const rarity: WeaponRarity = if (r < 0.50)
            .common
        else if (r < 0.75)
            .uncommon
        else if (r < 0.90)
            .rare
        else if (r < 0.98)
            .epic
        else
            .legendary;

        const mult = rarity.getStatMultiplier();
        var stats: WeaponStats = undefined;

        switch (w_type) {
            .sword => {
                const base_dmg: f32 = 15.0 + random.float(f32) * 10.0;

                // Randomly choose swing or thrust for swords
                const anim_type: AttackAnimationType = if (random.boolean()) .swing else .thrust;

                stats = .{
                    .damage = @intFromFloat(base_dmg * mult),
                    .attack_speed = (1.5 + random.float(f32) * 1.0) * (1.0 + (mult - 1.0) * 0.2),
                    .projectile_speed = 0.0, // Melee
                    .life_time = 0.15, // short hitbox lifetime
                    .piercing = 999, // Swords hit everything in range
                    .reach = if (anim_type == .thrust) 40.0 + random.float(f32) * 20.0 else 0.0,
                    .animation_type = anim_type,
                };
            },
            .bow => {
                const base_dmg: f32 = 10.0 + random.float(f32) * 5.0;
                stats = .{
                    .damage = @intFromFloat(base_dmg * mult),
                    .attack_speed = (1.0 + random.float(f32) * 0.5) * (1.0 + (mult - 1.0) * 0.2),
                    .projectile_speed = 600.0 + random.float(f32) * 200.0,
                    .life_time = 2.0, // Arrow flies for 2s
                    .piercing = 1,
                };
            },
            .staff => {
                const base_dmg: f32 = 20.0 + random.float(f32) * 10.0;
                stats = .{
                    .damage = @intFromFloat(base_dmg * mult),
                    .attack_speed = (0.5 + random.float(f32) * 0.5) * (1.0 + (mult - 1.0) * 0.2),
                    .projectile_speed = 400.0 + random.float(f32) * 100.0,
                    .life_time = 3.0,
                    .piercing = if (rarity == .legendary) 3 else 1,
                };
            },
            .spear => {
                const base_dmg: f32 = 12.0 + random.float(f32) * 8.0;

                stats = .{
                    .damage = @intFromFloat(base_dmg * mult),
                    .attack_speed = (1.2 + random.float(f32) * 0.8) * (1.0 + (mult - 1.0) * 0.2),
                    .projectile_speed = 0.0, // Melee
                    .life_time = 0.20, // longer hitbox lifetime
                    .piercing = 999, // Spears hit everything in range
                    .reach = 80.0 + random.float(f32) * 40.0, // Long reach
                    .animation_type = .thrust,
                };
            },
        }

        return Weapon{
            .weapon_type = w_type,
            .rarity = rarity,
            .stats = stats,
        };
    }
};

test "generate weapon" {
    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    for (0..100) |_| {
        const w = Weapon.generateRandomWeapon(random);
        try std.testing.expect(w.stats.damage > 0);
        try std.testing.expect(w.stats.attack_speed > 0);
    }
}
