const std = @import("std");

pub const world = @import("world.zig");
pub const bytecode = @import("bytecode.zig");
pub const vm = @import("vm.zig");
pub const spatial = @import("spatial.zig");
pub const compiler = @import("compiler.zig");
pub const display = @import("display.zig");
pub const repl = @import("repl.zig");
pub const spitting_contest = @import("spitting_contest.zig");
pub const gk3_moustache = @import("gk3_moustache.zig");
pub const sword_fighting = @import("sword_fighting.zig");

pub const World = world.World;
pub const EntityId = world.EntityId;
pub const RelationKind = world.RelationKind;
pub const RelationType = world.RelationType;
pub const Fact = world.Fact;
pub const PatternTerm = world.PatternTerm;
pub const PatternClause = world.PatternClause;
pub const VariableBindings = world.VariableBindings;
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
pub const compile_source = compiler.compile_source;
pub const CompiledProgram = compiler.CompiledProgram;
pub const DisplayBridge = display.DisplayBridge;
pub const RenderFrame = display.RenderFrame;
pub const Repl = repl.Repl;
pub const ReplResult = repl.ReplResult;

test "root test imports all modules" {
    _ = @import("world.zig");
    _ = @import("bytecode.zig");
    _ = @import("vm.zig");
    _ = @import("spatial.zig");
    _ = @import("compiler.zig");
    _ = @import("display.zig");
    _ = @import("repl.zig");
    _ = @import("spitting_contest.zig");
    _ = @import("gk3_moustache.zig");
    _ = @import("sword_fighting.zig");
}
