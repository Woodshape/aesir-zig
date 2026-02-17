const std = @import("std");
const rl = @import("raylib");

pub const Animations = enum {
    none,
    player_idle,
    player_run,
    player_death,
};

pub const SpriteData = struct {
    frames: i8 = 0,
    duration: f32 = 0,
};

pub const AnimationData = struct {
    scale: rl.Vector2 = .{ .x = 1, .y = 1 },
    one_shot: bool = false,
};

pub const ANIMATION_SCALE = rl.Vector2{ .x = 4, .y = 4 };

const animation_data_base = AnimationData{
    .scale = ANIMATION_SCALE,
};

pub const sprite_data_table = std.EnumArray(Animations, SpriteData).init(.{
    .none = .{},
    .player_idle = .{ .frames = 2, .duration = 0.3 },
    .player_run = .{ .frames = 3, .duration = 0.1 },
    .player_death = .{ .frames = 3, .duration = 0.2 },
});

pub const animation_data_table = std.EnumArray(Animations, AnimationData).init(.{
    .none = .{},
    .player_idle = animation_data_base,
    .player_run = animation_data_base,
    .player_death = .{ .scale = ANIMATION_SCALE, .one_shot = true },
});

pub const AnimationSprite = struct {
    data: SpriteData = .{},
    texture: rl.Texture2D = std.mem.zeroes(rl.Texture2D),
};

pub const Animation = struct {
    name: Animations = .none,
    sprite: AnimationSprite = .{},
    data: AnimationData = .{},
    current_frame: i8 = 0,
    frame_timer: f32 = 0,
};

pub var animations = std.EnumArray(Animations, Animation).initFill(.{});

pub fn loadAnimationData() void {
    const fields = std.meta.fields(Animations);
    inline for (fields) |field| {
        const anim: Animations = @enumFromInt(field.value);
        if (anim == .none) {
            animations.set(anim, .{});
            continue;
        }

        const path = "res/images/" ++ field.name ++ ".png";
        const texture = rl.loadTexture(path) catch std.mem.zeroes(rl.Texture2D);

        const sprite = sprite_data_table.get(anim);
        const data = animation_data_table.get(anim);

        animations.set(anim, .{
            .name = anim,
            .sprite = .{ .data = sprite, .texture = texture },
            .data = data,
            .frame_timer = sprite.duration,
        });
    }
}

pub fn updateAnimation(anim: *Animation, frame_time: f32) bool {
    var loop = false;

    const frames = anim.sprite.data.frames;
    const frame_len = anim.sprite.data.duration;

    anim.frame_timer -= frame_time;
    while (anim.frame_timer <= 0) {
        anim.current_frame += 1;

        if (anim.current_frame >= frames) {
            anim.current_frame = if (anim.data.one_shot) frames - 1 else 0;
            loop = true;
        }

        anim.frame_timer = frame_len + anim.frame_timer;
    }

    return loop;
}

pub fn changeAnimation(anim: *Animation, new_anim: Animation) bool {
    if (anim.name == new_anim.name) {
        return false;
    }

    anim.name = new_anim.name;
    anim.sprite = new_anim.sprite;
    anim.data = new_anim.data;
    anim.frame_timer = new_anim.frame_timer;
    anim.current_frame = 0;
    return true;
}

pub fn drawAnimation(anim: Animation, position: rl.Vector2, flip_sprite: bool) void {
    if (anim.name == .none) {
        return;
    }

    const anim_data = anim.sprite.data;
    const anim_width: f32 = @floatFromInt(anim.sprite.texture.width);
    const anim_height: f32 = @floatFromInt(anim.sprite.texture.height);
    const size_x = anim_width / @as(f32, @floatFromInt(anim_data.frames));
    const size_y = anim_height;

    var source_width = size_x;
    if (flip_sprite) {
        source_width = -source_width;
    }

    const source = rl.Rectangle{
        .x = @as(f32, @floatFromInt(anim.current_frame)) * anim_width / @as(f32, @floatFromInt(anim_data.frames)),
        .y = 0,
        .width = source_width,
        .height = size_y,
    };

    const dest = rl.Rectangle{
        .x = position.x,
        .y = position.y,
        .width = size_x * anim.data.scale.x,
        .height = size_y * anim.data.scale.y,
    };

    rl.drawTexturePro(
        anim.sprite.texture,
        source,
        dest,
        .{ .x = 0, .y = 0 },
        0,
        rl.Color.ray_white,
    );
}

// Tests
test "update animation" {
    var anim = Animation{
        .sprite = .{ .data = .{ .frames = 2, .duration = 1 } },
        .frame_timer = 1,
    };

    _ = updateAnimation(&anim, 0.5);
    try std.testing.expectEqual(@as(i8, 0), anim.current_frame);
    _ = updateAnimation(&anim, 0.5);
    try std.testing.expectEqual(@as(i8, 1), anim.current_frame);
    _ = updateAnimation(&anim, 1);
    try std.testing.expectEqual(@as(i8, 0), anim.current_frame);
}

test "update animation one shot" {
    var anim = Animation{
        .sprite = .{ .data = .{ .frames = 2, .duration = 1 } },
        .data = .{ .one_shot = true },
        .frame_timer = 1,
    };

    _ = updateAnimation(&anim, 0.5);
    try std.testing.expectEqual(@as(i8, 0), anim.current_frame);
    _ = updateAnimation(&anim, 0.5);
    try std.testing.expectEqual(@as(i8, 1), anim.current_frame);
    _ = updateAnimation(&anim, 1);
    try std.testing.expectEqual(@as(i8, 1), anim.current_frame);
}

test "change animation" {
    var anim = Animation{
        .name = .player_idle,
        .sprite = .{ .data = .{ .frames = 2, .duration = 0.3 } },
        .frame_timer = 0.3,
    };

    const new_anim = Animation{
        .name = .player_run,
        .sprite = .{ .data = .{ .frames = 3, .duration = 0.1 } },
        .frame_timer = 0.1,
    };

    const changed = changeAnimation(&anim, new_anim);
    try std.testing.expect(changed);
    try std.testing.expectEqual(Animations.player_run, anim.name);
    try std.testing.expectEqual(@as(f32, 0.1), anim.frame_timer);
    try std.testing.expectEqual(@as(i8, 3), anim.sprite.data.frames);
    try std.testing.expectEqual(@as(i8, 0), anim.current_frame);

    // Changing to same animation should return false
    const not_changed = changeAnimation(&anim, new_anim);
    try std.testing.expect(!not_changed);
}
