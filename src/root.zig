const std = @import("std");

pub const world = @import("world.zig");
pub const World = world.World;
pub const EntityId = world.EntityId;
pub const RelationKind = world.RelationKind;
pub const RelationType = world.RelationType;
pub const Fact = world.Fact;

test "root test imports world" {
    _ = @import("world.zig");
}
