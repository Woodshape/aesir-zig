const std = @import("std");

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
