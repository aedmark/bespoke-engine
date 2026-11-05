const std = @import("std");
const bespoke = @import("root.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("===================================================================\n", .{});
    try stdout.print("       BeSpoke Engine: The Tavern Heist Vertical Slice Demo        \n", .{});
    try stdout.print("   (Engine-as-Spine * Custom Bytecode * Relational & Temporal)  \n", .{});
    try stdout.print("===================================================================\n\n", .{});

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

    // 3. The 20-line DSL Source Script from script_spec.md
    const script =
        \\entity Guard, Bard, Cat, Cheese
        \\relation Carries(holder, item)
        \\relation CharmedBy(listener, musician)
        \\
        \\remember Carries(Guard, Cheese)
        \\
        \\routine Patrol(Guard):
        \\  walk Guard to Cellar
        \\  wait 5 ticks
        \\  walk Guard to Hearth
        \\
        \\when CharmedBy(Guard, Bard):
        \\  interrupt Guard with:
        \\    face Guard toward Bard
        \\    wait 4 ticks
    ;

    try stdout.print("[Compiler] Lowering BeSpoke DSL script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, script);
    defer compiled.deinit();

    const guard = try world.intern_entity("Guard");
    const bard = try world.intern_entity("Bard");
    const cat = try world.intern_entity("Cat");
    const cheese = try world.intern_entity("Cheese");
    const carries = try world.intern_relation("Carries", .set);
    const charmed = try world.intern_relation("CharmedBy", .set);

    // Initial world setup: Guard carries Cheese, starts at Hearth
    try world.remember(guard, carries, cheese.to_int(), 0);
    try spatial.register_entity(guard, hearth_wp, 10);
    try spatial.register_entity(bard, bar_wp, 0); // Bard stationed at Bar
    try spatial.register_entity(cat, hearth_wp, 15); // Cat lurking near Hearth

    // 4. Initialize VM & Display Bridge
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    var display_bridge = bespoke.DisplayBridge.init();

    const patrol_pc = compiled.routine_entries.get("Patrol").?;
    const charmed_rule_pc: u16 = @intCast(compiled.when_rule_entries.items[0]);

    _ = try vm.spawn_routine(guard, patrol_pc);

    // Array to record historical snapshot buffers for time-travel rewind (P5-02)
    var history_snapshots = std.ArrayList(std.ArrayList(u8)).init(allocator);
    defer {
        for (history_snapshots.items) |*buf| buf.deinit();
        history_snapshots.deinit();
    }

    // Check command line arguments for --headless
    var is_headless_arg = false;
    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();
    _ = args_it.next(); // Skip binary name
    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--headless")) {
            is_headless_arg = true;
        }
    }

    // Initialize SDL2 Peripheral Display Window (D-008, P6-01)
    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Tavern Heist", 960, 540);
    defer window.deinit();

    if (window.is_headless or is_headless_arg) {
        try stdout.print("\n>>> STARTING SIMULATION CLOCK (Headless Mode) <<<\n", .{});

        // Capture initial tick 0
        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.swap();
        try display_bridge.render_terminal(stdout);

        // Save snapshot 0
        var snap0 = std.ArrayList(u8).init(allocator);
        try world.save_state(snap0.writer());
        try history_snapshots.append(snap0);

        // Run forward simulation for 18 ticks
        while (world.current_tick < 18) {
            if (world.current_tick == 1) {
                try world.remember(guard, charmed, bard.to_int(), 4);
                _ = try vm.interrupt_entity(guard, charmed_rule_pc);
                try stdout.print("\n*** [CUE] Bard plays enchanting melody on lute! Guard charmed! ***\n", .{});
            }

            if (world.current_tick == 3) {
                if (world.has_fact(guard, charmed, bard.to_int()) and world.has_fact(guard, carries, cheese.to_int())) {
                    _ = world.forget(guard, carries, cheese.to_int());
                    try world.remember(cat, carries, cheese.to_int(), 0);
                    try stdout.print("\n*** [HEIST] Cat stealthily steals Cheese from charmed Guard! ***\n", .{});
                }
            }

            try vm.step_tick();

            var snap = std.ArrayList(u8).init(allocator);
            try world.save_state(snap.writer());
            try history_snapshots.append(snap);

            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
            try display_bridge.render_terminal(stdout);
        }

        try stdout.print("\n===================================================================\n", .{});
        try stdout.print("Heist Outcome at Tick {d}:\n", .{world.current_tick});
        try stdout.print("   - Guard carries Cheese? {s}\n", .{if (world.has_fact(guard, carries, cheese.to_int())) "YES" else "NO"});
        try stdout.print("   - Cat carries Cheese?   {s}\n", .{if (world.has_fact(cat, carries, cheese.to_int())) "YES" else "NO"});
        try stdout.print("===================================================================\n\n", .{});

        // 5. Time-Travel Rewind Demo
        try stdout.print(">>> DEMONSTRATING TIME-TRAVEL REWIND: REWINDING TO TICK 2 (BEFORE HEIST) <<<\n", .{});
        const target_rewind_tick: usize = 2;
        const target_snapshot = history_snapshots.items[target_rewind_tick];

        var stream = std.io.fixedBufferStream(target_snapshot.items);
        try world.restore_state(stream.reader());

        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.swap();
        try display_bridge.render_terminal(stdout);

        try stdout.print("\nRewound State Verification:\n", .{});
        try stdout.print("   - Simulation Clock Restored: Tick {d}\n", .{world.current_tick});
        try stdout.print("   - Guard carries Cheese?      {s} (Restored!)\n", .{if (world.has_fact(guard, carries, cheese.to_int())) "YES" else "NO"});
        try stdout.print("   - Cat carries Cheese?        {s} (Undone!)\n", .{if (world.has_fact(cat, carries, cheese.to_int())) "YES" else "NO"});
        try stdout.print("===================================================================\n", .{});
    } else {
        try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (960x540) <<<\n", .{});
        try stdout.print("Interactive Controls:\n", .{});
        try stdout.print("   - [Left Click Waypoint]: Direct Cat (Player) to walk\n", .{});
        try stdout.print("   - [Space]:               Pause / Resume Simulation\n", .{});
        try stdout.print("   - [N]:                   Single-step Simulation Tick\n", .{});
        try stdout.print("   - [R]:                   Instant Time-Travel Rewind to Tick 2\n", .{});
        try stdout.print("   - [Esc / Close]:         Exit\n\n", .{});

        // Initial snapshot at tick 0
        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.swap();

        var snap0 = std.ArrayList(u8).init(allocator);
        try world.save_state(snap0.writer());
        try history_snapshots.append(snap0);

        var is_paused = false;
        var last_tick_time = std.time.milliTimestamp();
        const tick_interval_ms: i64 = 250; // 4 ticks/sec for clear visual perception

        window.set_cue_banner("Welcome to BeSpoke Engine! Left-click nodes to move Cat.", 90);

        // Interactive 60 Hz Display Loop (D-001, P6-01)
        while (true) {
            // 1. Poll peripheral inputs
            const action = window.poll_events(display_bridge.get_frame());
            var should_step_now = false;

            switch (action) {
                .quit => break,
                .toggle_pause => {
                    is_paused = !is_paused;
                },
                .step_tick => {
                    should_step_now = true;
                },
                .walk_player => |wp_id| {
                    _ = try spatial.walk_to(cat, wp_id);
                    var banner_buf: [64]u8 = undefined;
                    const text = std.fmt.bufPrint(&banner_buf, "Directing Cat to Waypoint #{d}", .{wp_id}) catch "Directing Cat";
                    window.set_cue_banner(text, 60);
                },
                .rewind => {
                    if (history_snapshots.items.len > 2) {
                        const target_snapshot = history_snapshots.items[2];
                        var stream = std.io.fixedBufferStream(target_snapshot.items);
                        try world.restore_state(stream.reader());
                        // Sync display frame
                        display_bridge.capture_frame(&world, &spatial, &vm);
                        display_bridge.swap();
                        window.set_cue_banner("<<< REWOUND TO PRE-HEIST TICK 2 <<<", 90);
                        try stdout.print("[Time-Travel] Rewound simulation to Tick 2!\n", .{});
                    }
                },
                .none => {},
            }

            // 2. Advance simulation clock if unpaused or single-stepped
            const now = std.time.milliTimestamp();
            if (should_step_now or (!is_paused and now - last_tick_time >= tick_interval_ms)) {
                last_tick_time = now;

                // Scripted narrative cues for the vertical slice
                if (world.current_tick == 1) {
                    try world.remember(guard, charmed, bard.to_int(), 4);
                    _ = try vm.interrupt_entity(guard, charmed_rule_pc);
                    window.set_cue_banner("♫ [CUE] Bard charms Guard with lute melody! ♫", 60);
                    try stdout.print("\n*** [CUE] Bard plays enchanting melody on lute! Guard charmed! ***\n", .{});
                }

                if (world.current_tick == 3) {
                    if (world.has_fact(guard, charmed, bard.to_int()) and world.has_fact(guard, carries, cheese.to_int())) {
                        _ = world.forget(guard, carries, cheese.to_int());
                        try world.remember(cat, carries, cheese.to_int(), 0);
                        window.set_cue_banner("★ [HEIST] Cat stealthily snatches Cheese from Guard! ★", 60);
                        try stdout.print("\n*** [HEIST] Cat stealthily steals Cheese from charmed Guard! ***\n", .{});
                    }
                }

                try vm.step_tick();

                // Save snapshot for potential rewind
                var snap = std.ArrayList(u8).init(allocator);
                try world.save_state(snap.writer());
                try history_snapshots.append(snap);

                // Synchronize display bridge
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.swap();
            }

            // 3. Render 2D Frame at Display Refresh Rate (P6-02, P6-04)
            window.render_frame(display_bridge.get_frame(), is_paused);

            // Cap display loop ~60 FPS
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
}
