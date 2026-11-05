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

    // 3. Compile Raw BeSpoke DSL Script (Phase 4, P4-01, P4-02, P4-03)
    const script =
        \\entity Guard, Bard, Cheese
        \\relation Carries(holder, item)
        \\property Alertness(agent, value)
        \\relation CharmedBy(listener, musician)
        \\
        \\routine Patrol(Guard):
        \\  walk Guard to Cellar
        \\  remember Carries(Guard, Cheese)
        \\  wait 5 ticks
        \\  walk Guard to Hearth
        \\
        \\when CharmedBy(Guard, Bard):
        \\  interrupt Guard with:
        \\    face Guard toward Bard
        \\    wait 3 ticks
    ;

    try stdout.print("1. Compiling BeSpoke DSL Source Script:\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, script);
    defer compiled.deinit();

    try stdout.print("   - Successfully lowered DSL AST directly to {d} bytes of VM bytecode!\n", .{compiled.chunk.count()});
    try stdout.print("   - Registered Routines: {d}\n", .{compiled.routine_entries.count()});
    try stdout.print("   - Registered When-Rules: {d}\n\n", .{compiled.when_rule_entries.items.len});

    // Register Guard in spatial system at Hearth
    const guard = try world.intern_entity("Guard");
    const bard = try world.intern_entity("Bard");
    const cheese = try world.intern_entity("Cheese");
    const carries = try world.intern_relation("Carries", .set);
    const charmed = try world.intern_relation("CharmedBy", .set);
    try spatial.register_entity(guard, hearth_wp, 10);

    // 4. Initialize VM with Compiled Bytecode and Spatial Engine
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    const patrol_pc = compiled.routine_entries.get("Patrol").?;
    const charmed_rule_pc: u16 = @intCast(compiled.when_rule_entries.items[0]);

    _ = try vm.spawn_routine(guard, patrol_pc);
    try stdout.print("2. Spawned Guard Patrol Routine (pc: {d})\n\n", .{patrol_pc});

    // 5. Run Live Simulation
    try stdout.print("3. Executing Simulation Ticks:\n", .{});

    // Tick 1: Guard begins walking to Cellar
    try vm.step_tick();
    try stdout.print("   - Tick {d}: Guard pos=({d}, {d}) walking toward Cellar\n", .{
        world.current_tick,
        spatial.get_position(guard).?.x,
        spatial.get_position(guard).?.y,
    });

    // Tick 2: Guard in transit
    try vm.step_tick();
    try stdout.print("   - Tick {d}: Guard pos=({d}, {d}) in transit.\n", .{
        world.current_tick,
        spatial.get_position(guard).?.x,
        spatial.get_position(guard).?.y,
    });

    // Trigger When-Rule: Bard charms Guard for 4 ticks
    try world.remember(guard, charmed, bard.to_int(), 4);
    _ = try vm.interrupt_entity(guard, charmed_rule_pc);
    try stdout.print("   - Tick {d}: >> Systemic Event: Bard charms Guard! Preempted patrol with compiled When-Rule <<\n", .{world.current_tick});

    // Ticks 3, 4, 5: Guard is distracted listening to Bard
    for (0..3) |_| {
        try vm.step_tick();
        try stdout.print("   - Tick {d}: Guard distracted by music (pos={d})\n", .{
            world.current_tick,
            spatial.get_position(guard).?.x,
        });
    }

    // Tick 6+: Distraction clears, Guard resumes walking to Cellar, grabs Cheese, walks back to Hearth!
    try stdout.print("   - Tick {d}: Charm expired! Guard resumes patrol to Cellar...\n", .{world.current_tick});
    while (world.current_tick < 18) {
        try vm.step_tick();
        try stdout.print("   - Tick {d}: Guard pos=({d}, {d}) [Carrying cheese? {s}]\n", .{
            world.current_tick,
            spatial.get_position(guard).?.x,
            spatial.get_position(guard).?.y,
            if (world.has_fact(guard, carries, cheese.to_int())) "YES" else "NO",
        });
    }

    try stdout.print("\n4. Simulation Complete at Tick {d}!\n", .{world.current_tick});
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
