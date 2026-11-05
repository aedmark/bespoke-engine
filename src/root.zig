const std = @import("std");

pub const world = @import("world.zig");
pub const bytecode = @import("bytecode.zig");
pub const vm = @import("vm.zig");
pub const spatial = @import("spatial.zig");

pub const World = world.World;
pub const EntityId = world.EntityId;
pub const RelationKind = world.RelationKind;
pub const RelationType = world.RelationType;
pub const Fact = world.Fact;
pub const Opcode = bytecode.Opcode;
pub const BytecodeChunk = bytecode.BytecodeChunk;
pub const VM = vm.VM;
pub const Fiber = vm.Fiber;
pub const FiberId = vm.FiberId;
pub const FiberState = vm.FiberState;
pub const SpatialGraph = spatial.SpatialGraph;
pub const SpatialSystem = spatial.SpatialSystem;
pub const Point2D = spatial.Point2D;
pub const Waypoint = spatial.Waypoint;
pub const WaypointId = spatial.WaypointId;

test "root test imports all modules" {
    _ = @import("world.zig");
    _ = @import("bytecode.zig");
    _ = @import("vm.zig");
    _ = @import("spatial.zig");
}
