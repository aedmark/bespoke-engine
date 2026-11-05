const std = @import("std");
const bespoke = @import("root.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== BeSpoke Engine v0.1.0-dev (Engine-as-Spine) ===\n\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. Initialize Relational World
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    const guard = try world.intern_entity("Guard");
    const bard = try world.intern_entity("Bard");
    const cheese = try world.intern_entity("Cheese");
    const carries = try world.intern_relation("Carries", .set);
    const alertness = try world.intern_relation("Alertness", .property);
    const charmed = try world.intern_relation("CharmedBy", .set);

    // 2. Initialize Spatial Waypoint Graph (Phase 3, D-005)
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    const tavern = try world.intern_entity("Tavern");
    const cellar_room = try world.intern_entity("CellarRoom");

    const hearth_wp = try spatial.graph.add_waypoint(tavern, 0, 0, "Hearth");
    const bar_wp = try spatial.graph.add_waypoint(tavern, 20, 0, "Bar");
    const cellar_wp = try spatial.graph.add_waypoint(cellar_room, 40, 0, "Cellar");

    try spatial.graph.connect(hearth_wp, bar_wp, null);
    try spatial.graph.connect(bar_wp, cellar_wp, null);

    // Guard starts at Hearth with speed 10 units/tick (transit Hearth -> Cellar is 40 units = 4 ticks)
    try spatial.register_entity(guard, hearth_wp, 10);

    try stdout.print("1. World & Spatial Topology Initialized:\n", .{});
    try stdout.print("   - Entities: Guard ({d}), Bard ({d}), Cheese ({d})\n", .{
        guard.to_int(),
        bard.to_int(),
        cheese.to_int(),
    });
    try stdout.print("   - Waypoints: Hearth (0,0) <-> Bar (20,0) <-> Cellar (40,0)\n", .{});
    try stdout.print("   - Guard speed: 10 units/tick\n\n", .{});

    // 3. Compile Bytecode Routines
    var chunk = bespoke.BytecodeChunk.init(allocator);
    defer chunk.deinit();

    // --- Routine: Patrol(Guard) (pc: 0) ---
    // walk Guard to Cellar, pick up Cheese, wait 5 ticks, walk Guard to Hearth
    const patrol_pc: usize = chunk.code.items.len;
    try chunk.emit_walk_to(guard, cellar_wp);

    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(carries);
    try chunk.emit_push_entity(cheese);
    try chunk.emit_remember(0);

    try chunk.emit_wait_ticks(5);

    try chunk.emit_walk_to(guard, hearth_wp);
    _ = try chunk.emit_op(.halt);

    // --- Interrupt Routine: CharmedDistraction (pc: 43) ---
    // Sets Alertness = 0, pauses for 3 ticks listening to lute, then resumes walking!
    const charmed_pc: u16 = @intCast(chunk.code.items.len);
    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(alertness);
    try chunk.emit_push_const(0);
    try chunk.emit_remember(0);

    try chunk.emit_wait_ticks(3);
    _ = try chunk.emit_op(.resume_routine);

    try stdout.print("2. Bytecode Routines Compiled ({d} bytes):\n", .{chunk.count()});
    try stdout.print("   - Patrol routine entry at pc {d} (asynchronous motor walk & cheese pickup)\n", .{patrol_pc});
    try stdout.print("   - Charmed interrupt handler at pc {d}\n\n", .{charmed_pc});

    // 4. Initialize VM with Spatial System
    var vm = bespoke.VM.init(allocator, &world, &chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    _ = try vm.spawn_routine(guard, patrol_pc);
    try stdout.print("3. Spawned Guard Patrol Routine\n\n", .{});

    // 5. Run Live Simulation
    try stdout.print("4. Executing Simulation Ticks:\n", .{});

    // Tick 1: Guard begins walking to Cellar
    try vm.step_tick();
    try stdout.print("   - Tick {d}: Guard pos=({d}, {d}) walking toward Cellar\n", .{
        world.current_tick,
        spatial.get_position(guard).?.x,
        spatial.get_position(guard).?.y,
    });

    // Tick 2: Guard reaches x=10. Bard plays lute!
    try vm.step_tick();
    try stdout.print("   - Tick {d}: Guard pos=({d}, {d}) in transit.\n", .{
        world.current_tick,
        spatial.get_position(guard).?.x,
        spatial.get_position(guard).?.y,
    });

    try world.remember(guard, charmed, bard.to_int(), 4);
    _ = try vm.interrupt_entity(guard, charmed_pc);
    try stdout.print("   - Tick {d}: >> Bard charms Guard! Interrupted motor routine with CharmedDistraction <<\n", .{world.current_tick});

    // Ticks 3, 4, 5: Guard is charmed, listening to music
    for (0..3) |_| {
        try vm.step_tick();
        try stdout.print("   - Tick {d}: Guard distracted by music (pos={d})\n", .{
            world.current_tick,
            spatial.get_position(guard).?.x,
        });
    }

    // Tick 6+: Distraction finishes, Guard resumes walking to Cellar!
    try stdout.print("   - Tick {d}: Charm ended! Guard resumes walking toward Cellar...\n", .{world.current_tick});
    while (world.current_tick < 18) {
        try vm.step_tick();
        try stdout.print("   - Tick {d}: Guard pos=({d}, {d}) [Carrying cheese? {s}]\n", .{
            world.current_tick,
            spatial.get_position(guard).?.x,
            spatial.get_position(guard).?.y,
            if (world.has_fact(guard, carries, cheese.to_int())) "YES" else "NO",
        });
    }

    try stdout.print("\n5. Simulation Complete at Tick {d}!\n", .{world.current_tick});
    try stdout.print("   - Final Guard Position: ({d}, {d}) at waypoint {d} ({s})\n", .{
        spatial.get_position(guard).?.x,
        spatial.get_position(guard).?.y,
        spatial.get_current_waypoint(guard).?,
        spatial.graph.get_waypoint(spatial.get_current_waypoint(guard).?).?.name,
    });
    try stdout.print("   - Guard carrying Cheese? {s}\n", .{
        if (world.has_fact(guard, carries, cheese.to_int())) "YES" else "NO",
    });
}
