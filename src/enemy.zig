const std = @import("std");
const entity_mod = @import("entity.zig");

pub const GameState = entity_mod.GameState;

pub const Skeleton = struct {
    bones: i32 = 0,
};

pub const Bat = struct {
    flying: bool = false,
};

pub fn updateSkeleton(skeleton: *Skeleton, _: f32) void {
    skeleton.bones += 10;
}

// Tests
test "enemy stuff" {
    var skeleton = Skeleton{ .bones = 250 };
    var bat = Bat{};

    try std.testing.expectEqual(@as(i32, 250), skeleton.bones);
    try std.testing.expectEqual(false, bat.flying);

    updateSkeleton(&skeleton, 0.5);
    try std.testing.expectEqual(@as(i32, 260), skeleton.bones);

    bat.flying = !bat.flying;
    try std.testing.expect(bat.flying);
}

test "entity skeleton variant" {
    var state = GameState.init(std.testing.allocator);
    defer state.deinit();

    const ent = state.createEntity(.{ .skeleton = .{ .bones = 5 } });

    if (ent.as(Skeleton)) |s| {
        try std.testing.expectEqual(@as(i32, 5), s.bones);
    } else {
        return error.TestUnexpectedResult;
    }
}

test "entity bat variant" {
    var state = GameState.init(std.testing.allocator);
    defer state.deinit();

    const ent = state.createEntity(.{ .bat = .{ .flying = true } });

    if (ent.as(Bat)) |b| {
        try std.testing.expectEqual(true, b.flying);
    } else {
        return error.TestUnexpectedResult;
    }
}
