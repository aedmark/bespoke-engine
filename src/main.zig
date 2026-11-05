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

    try stdout.print("1. World Initialized:\n", .{});
    try stdout.print("   - Entities: Guard ({d}), Bard ({d}), Cheese ({d})\n", .{
        guard.to_int(),
        bard.to_int(),
        cheese.to_int(),
    });
    try stdout.print("   - Relations: Carries (set), Alertness (property), CharmedBy (set)\n\n", .{});

    // 2. Compile Bytecode Routines
    var chunk = bespoke.BytecodeChunk.init(allocator);
    defer chunk.deinit();

    // --- Routine: Patrol(Guard) (pc: 0) ---
    // Sets Alertness = 20, waits 10 ticks, then picks up Cheese
    const patrol_pc: usize = chunk.code.items.len;
    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(alertness);
    try chunk.emit_push_const(20);
    try chunk.emit_remember(0);

    try chunk.emit_wait_ticks(10); // Wait 10 ticks in patrol

    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(carries);
    try chunk.emit_push_entity(cheese);
    try chunk.emit_remember(0);
    _ = try chunk.emit_op(.halt);

    // --- Interrupt Routine: CharmedReaction (pc: 33) ---
    // Sets Alertness = 0, waits 5 ticks while listening to music, resumes patrol
    const charmed_pc: u16 = @intCast(chunk.code.items.len);
    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(alertness);
    try chunk.emit_push_const(0);
    try chunk.emit_remember(0);

    try chunk.emit_wait_ticks(5); // Distracted by music for 5 ticks
    _ = try chunk.emit_op(.resume_routine);

    try stdout.print("2. Bytecode Routines Compiled ({d} bytes):\n", .{chunk.count()});
    try stdout.print("   - Patrol routine entry at pc {d}\n", .{patrol_pc});
    try stdout.print("   - Charmed interrupt handler at pc {d}\n\n", .{charmed_pc});

    // 3. Initialize VM and Spawn Patrol Routine
    var vm = bespoke.VM.init(allocator, &world, &chunk);
    defer vm.deinit();

    const fiber_id = try vm.spawn_routine(guard, patrol_pc);
    try stdout.print("3. Spawned Fiber {d} for Guard Patrol\n\n", .{fiber_id});

    // 4. Run Simulation Loop
    try stdout.print("4. Executing Simulation Ticks:\n", .{});

    // Tick 1: Patrol starts, sets alertness = 20, enters 10-tick wait
    try vm.step_tick();
    try stdout.print("   - Tick {d}: Guard alertness={d}%, fiber state: waiting\n", .{
        world.current_tick,
        world.get_property(guard, alertness).?,
    });

    // Tick 2: Bard plays lute! Systemic cue charms Guard for 5 ticks and triggers interrupt
    try world.remember(guard, charmed, bard.to_int(), 5);
    try stdout.print("   - Tick {d}: >> Bard plays lute! CharmedBy(Guard, Bard) remembered <<\n", .{world.current_tick});
    _ = try vm.interrupt_entity(guard, charmed_pc);
    try stdout.print("   - Tick {d}: >> Interrupted Guard with CharmedReaction! <<\n", .{world.current_tick});

    // Tick 3: Guard is executing interrupt handler: alertness drops to 0% (charmed)
    try vm.step_tick();
    try stdout.print("   - Tick {d}: Guard charmed! Alertness dropped to {d}%\n", .{
        world.current_tick,
        world.get_property(guard, alertness).?,
    });

    // Advance 6 ticks to let charmed distraction expire and resume patrol
    for (0..6) |_| {
        try vm.step_tick();
    }
    try stdout.print("   - Tick {d}: Charm expired! Prior patrol routine resumed.\n", .{world.current_tick});

    // Advance remaining ticks to complete patrol
    for (0..10) |_| {
        try vm.step_tick();
    }

    try stdout.print("\n5. Simulation Complete at Tick {d}:\n", .{world.current_tick});
    try stdout.print("   - Guard carrying Cheese? {s}\n", .{
        if (world.has_fact(guard, carries, cheese.to_int())) "YES (Patrol finished successfully!)" else "NO",
    });
}
