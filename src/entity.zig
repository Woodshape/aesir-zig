const std = @import("std");
const rl = @import("raylib");
const animation = @import("animation.zig");
const enemy_mod = @import("enemy.zig");

pub const Animation = animation.Animation;
pub const Skeleton = enemy_mod.Skeleton;
pub const Bat = enemy_mod.Bat;

pub const MAX_ENTITIES: usize = 2048;

pub const EntityHandle = struct {
    index: i32 = -1,
    id: i32 = 0,
};

pub const Player = struct {
    extra_jumps: u8 = 0,
    jump_force: f32 = 0,
    grounded: bool = false,
};

pub const Entity = struct {
    allocated: bool = false,
    handle: EntityHandle = .{},
    animation: Animation = .{},
    hp: i32 = 0,
    pos: rl.Vector2 = .{ .x = 0, .y = 0 },
    vel: rl.Vector2 = .{ .x = 0, .y = 0 },
    flip_x: bool = false,

    kind: Kind = .none,

    pub const Kind = union(enum) {
        none,
        player: Player,
        skeleton: Skeleton,
        bat: Bat,
    };

    pub fn as(self: *Entity, comptime T: type) ?*T {
        const name = comptime name: {
            for (@typeInfo(Kind).@"union".fields) |field| {
                if (field.type == T) break :name field.name;
            }
            @compileError(@typeName(T) ++ " is not a variant of Entity.Kind");
        };
        if (std.meta.activeTag(self.kind) == @field(std.meta.Tag(Kind), name)) {
            return &@field(self.kind, name);
        }
        return null;
    }

    pub fn isValid(self: Entity) bool {
        return self.handle.id != 0;
    }
};

pub const ScratchData = struct {
    all_entities: []EntityHandle = &.{},
};

pub const GameState = struct {
    ticks: u64 = 0,
    time_elapsed: f64 = 0,

    entity_top_count: i32 = 0,
    latest_entity_id: i32 = 0,
    entities: [MAX_ENTITIES]Entity = [_]Entity{.{}} ** MAX_ENTITIES,
    entity_free_list: std.ArrayList(i32) = .{},
    allocator: std.mem.Allocator,

    player_handle: EntityHandle = .{},
    scratch: ScratchData = .{},
    scratch_dirty: bool = true,

    pub fn init(allocator: std.mem.Allocator) GameState {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GameState) void {
        self.entity_free_list.deinit(self.allocator);
    }

    pub fn createEntity(self: *GameState, kind: Entity.Kind) *Entity {
        var index: i32 = -1;
        if (self.entity_free_list.items.len > 0) {
            index = self.entity_free_list.pop().?;
        }

        if (index == -1) {
            std.debug.assert(self.entity_top_count + 1 < MAX_ENTITIES);
            self.entity_top_count += 1;
            index = self.entity_top_count;
        }

        const idx: usize = @intCast(index);
        const ent = &self.entities[idx];
        ent.handle.index = index;
        ent.handle.id = self.latest_entity_id + 1;
        self.latest_entity_id = ent.handle.id;

        ent.kind = kind;

        switch (kind) {
            .player => self.player_handle = ent.handle,
            else => {},
        }

        ent.allocated = true;
        self.scratch_dirty = true;

        return ent;
    }

    pub fn destroyEntity(self: *GameState, e: *Entity) void {
        self.entity_free_list.append(self.allocator, e.handle.index) catch @panic("failed to append to free list");
        e.* = .{};
        self.scratch_dirty = true;
    }

    pub fn entityFromHandle(self: *GameState, handle: EntityHandle) ?*Entity {
        if (handle.index <= 0 or handle.index > self.entity_top_count) {
            return null;
        }

        const idx: usize = @intCast(handle.index);
        const ent = &self.entities[idx];
        if (ent.handle.id != handle.id) {
            return null;
        }

        return ent;
    }

    pub fn getPlayer(self: *GameState) ?*Entity {
        return self.entityFromHandle(self.player_handle);
    }

    pub fn getAllEntities(self: *GameState, allocator: std.mem.Allocator) []EntityHandle {
        if (self.scratch_dirty) {
            self.rebuildScratch(allocator);
            self.scratch_dirty = false;
        }
        return self.scratch.all_entities;
    }

    fn rebuildScratch(self: *GameState, allocator: std.mem.Allocator) void {
        var all_ents: std.ArrayList(EntityHandle) = .{};
        for (&self.entities) |*e| {
            if (!e.isValid()) continue;
            all_ents.append(allocator, e.handle) catch {};
        }
        self.scratch.all_entities = all_ents.toOwnedSlice(allocator) catch &.{};
    }
};

// Tests
test "entity create" {
    var state = GameState.init(std.testing.allocator);
    defer state.deinit();

    const ent = state.createEntity(.{ .player = .{ .jump_force = 600 } });

    try std.testing.expectEqual(@as(i32, 1), ent.handle.index);
    try std.testing.expectEqual(@as(i32, 1), ent.handle.id);
    try std.testing.expectEqual(ent.handle, state.player_handle);
    try std.testing.expectEqual(false, state.entities[0].allocated);
    try std.testing.expectEqual(true, state.entities[1].allocated);
    try std.testing.expectEqual(@as(usize, 0), state.entity_free_list.items.len);
    try std.testing.expect(state.latest_entity_id >= 1);

    const ents = state.getAllEntities(std.testing.allocator);
    defer std.testing.allocator.free(ents);
    try std.testing.expect(ents.len >= 1);
}

test "entity create and destroy" {
    var state = GameState.init(std.testing.allocator);
    defer state.deinit();

    const ent = state.createEntity(.{ .player = .{} });
    const handle = ent.handle;

    const ents_before = state.getAllEntities(std.testing.allocator);
    const before_len = ents_before.len;
    std.testing.allocator.free(ents_before);

    state.destroyEntity(ent);

    const ents_after = state.getAllEntities(std.testing.allocator);
    defer std.testing.allocator.free(ents_after);

    try std.testing.expectEqual(before_len - 1, ents_after.len);

    // Entity should be zeroed
    const result = state.entityFromHandle(handle);
    try std.testing.expectEqual(@as(?*Entity, null), result);
}

test "entity player variant" {
    var state = GameState.init(std.testing.allocator);
    defer state.deinit();

    const ent = state.createEntity(.{ .player = .{ .jump_force = 600 } });
    ent.hp = 100;

    if (ent.as(Player)) |p| {
        try std.testing.expectApproxEqAbs(@as(f32, 600), p.jump_force, 0.001);
        try std.testing.expectEqual(@as(i32, 100), ent.hp);
    } else {
        return error.TestUnexpectedResult;
    }
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
