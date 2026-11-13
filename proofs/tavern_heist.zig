const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// The Tavern Heist: the original Engine-as-Spine vertical slice (P5, P6, P9), moved out of
/// the engine CLI so `src/main.zig` carries no scenario content (D-031).
pub fn run(allocator: std.mem.Allocator, stdout: anytype, is_headless_arg: bool) !void {
    try stdout.print("===================================================================\n", .{});
    try stdout.print("       BeSpoke Engine: The Tavern Heist Vertical Slice Demo        \n", .{});
    try stdout.print("   (Engine-as-Spine * Custom Bytecode * Relational & Temporal)  \n", .{});
    try stdout.print("===================================================================\n\n", .{});

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

    // Register scene hotspots / inspectable props (P7-01, D-009)
    const fireplace = try world.intern_entity("Fireplace");
    const bar_counter = try world.intern_entity("BarCounter");
    const wine_cask = try world.intern_entity("WineCask");

    try spatial.add_hotspot(fireplace, tavern, .{ .x = 0, .y = -6 }, 8, "Fireplace", "A warm stone fireplace crackling with cozy embers.");
    try spatial.add_hotspot(bar_counter, tavern, .{ .x = 20, .y = -6 }, 8, "Bar Counter", "A sturdy oak counter with empty tankards and spilled ale.");
    try spatial.add_hotspot(wine_cask, cellar_room, .{ .x = 40, .y = -6 }, 8, "Wine Cask", "A massive oak barrel filled with vintage elven wine.");

    // 3. The 20-line DSL Source Script from docs/script_spec.md
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
        \\
        \\when Carries(Cat, Cheese):
        \\  interrupt Guard with:
        \\    face Guard toward Cat
        \\    wait 2 ticks
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
    try vm.load_compiled_rules(&compiled);

    var display_bridge = bespoke.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("Cat")) |player| display_bridge.set_active_character(player);
    var repl_instance = bespoke.Repl.init(&world, &spatial, &vm);

    const patrol_pc = compiled.routine_entries.get("Patrol").?;

    _ = try vm.spawn_routine(guard, patrol_pc);

    // Array to record historical snapshot buffers for time-travel rewind (P5-02)
    // Headless rewind demo timeline; the interactive loop keeps its own in host.Session.
    var timeline = bespoke.host.Timeline.init(allocator);
    defer timeline.deinit();

    // Initialize SDL2 Peripheral Display Window (D-008, P6-01). Headless runs never open one,
    // so the characterization test (P32-07) can run this proof without a display.
    var window_storage: ?bespoke.display.DisplayWindow = if (is_headless_arg)
        null
    else
        try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Tavern Heist", 1280, 720);
    defer if (window_storage) |*w| w.deinit();
    if (window_storage) |*w| w.set_theme(&art.theme);

    vm.current_scene = tavern;
    if (window_storage) |*w| {
        display_bridge.attach_audio_bridge(w.audio_bridge);
        w.set_bgm(art.track(.tavern));
    }

    if (window_storage == null or window_storage.?.is_headless) {
        try stdout.print("\n>>> STARTING SIMULATION CLOCK (Headless Mode) <<<\n", .{});

        // Capture initial tick 0
        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.swap();
        try display_bridge.render_terminal(stdout);

        // Save snapshot 0
        try timeline.record(&world);

        // Run forward simulation for 18 ticks
        while (world.current_tick < 18) {
            if (world.current_tick == 1) {
                try world.remember(guard, charmed, bard.to_int(), 4);
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

            try timeline.record(&world);

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
        _ = try timeline.restore(&world, target_rewind_tick);

        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.swap();
        try display_bridge.render_terminal(stdout);

        try stdout.print("\nRewound State Verification:\n", .{});
        try stdout.print("   - Simulation Clock Restored: Tick {d}\n", .{world.current_tick});
        try stdout.print("   - Guard carries Cheese?      {s} (Restored!)\n", .{if (world.has_fact(guard, carries, cheese.to_int())) "YES" else "NO"});
        try stdout.print("   - Cat carries Cheese?        {s} (Undone!)\n", .{if (world.has_fact(cat, carries, cheese.to_int())) "YES" else "NO"});
        try stdout.print("===================================================================\n", .{});
    } else {
        const window = &window_storage.?;
        try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
        try stdout.print("Interactive Adventure Controls:\n", .{});
        try stdout.print("   - [Right Click]:         Cycle Verb (WALK, LOOK, TALK, TAKE, USE)\n", .{});
        try stdout.print("   - [Verb Bar Buttons]:    Click WALK, LOOK, TALK, TAKE, or USE to activate\n", .{});
        try stdout.print("   - [Left Click Actor]:    Interact with Guard, Bard, or Cat with active verb\n", .{});
        try stdout.print("   - [Left Click Prop]:     Interact with Fireplace, Bar Counter, or Wine Cask\n", .{});
        try stdout.print("   - [Left Click Waypoint]: Direct Cat (Player) to walk\n", .{});
        try stdout.print("   - [Timeline Scrubber]:   Click or drag timeline bar (or [< / >] arrows) to scrub history\n", .{});
        try stdout.print("   - [F1 / D]:              Toggle Debug Inspector (Active Facts, Fibers, Stacks, Spatial)\n", .{});
        try stdout.print("   - [P / F2 / F3]:         Toggle Pause & Save/Load Slot Manager Drawer\n", .{});
        try stdout.print("   - [F5 / F9]:             Quick-Save / Quick-Load State\n", .{});
        try stdout.print("   - [Tab / ` / C]:         Toggle Live REPL Console Drawer ('help', 'remember', 'walk')\n", .{});
        try stdout.print("   - [Space]:               Pause / Resume Simulation\n", .{});
        try stdout.print("   - [N]:                   Single-step Simulation Tick\n", .{});
        try stdout.print("   - [R]:                   Instant Time-Travel Rewind to Tick 2\n", .{});
        try stdout.print("   - [Esc / Close]:         Exit\n\n", .{});

        // Initial snapshot at tick 0
        // Snapshot 0 and the first frame (host kit, P32-16, D-033)
        var session = try bespoke.host.Session.init(allocator, &world, &spatial, &vm, &compiled, &display_bridge, window);
        defer session.deinit();

        window.set_cue_banner("Welcome to BeSpoke Engine! Left-click nodes to move Cat.", 90);

        // Interactive 60 Hz Display Loop (D-001, P6-01)
        while (true) {
            // 1. Poll peripheral inputs
            const action = window.poll_events(session.frame());

            if (action == .rewind) {
                // This proof's [R] jumps to tick 2, just before the heist.
                if ((try session.jump_to(2)) != null) {
                    window.set_cue_banner("<<< TIME-TRAVEL: REWOUND TO TICK 2 (BEFORE HEIST) <<<", 90);
                    try stdout.print("[Time-Travel] Rewound simulation to Tick {d}\n", .{world.current_tick});
                }
            } else if (try session.handle_common(action)) {} else switch (action) {
                .quit => break,
                .walk_player => |wp_id| {
                    _ = try spatial.walk_to(cat, wp_id);
                    var banner_buf: [64]u8 = undefined;
                    const text = std.fmt.bufPrint(&banner_buf, "Directing Cat to Waypoint #{d}", .{wp_id}) catch "Directing Cat";
                    window.set_cue_banner(text, 60);
                },
                .examine_hotspot => |hs_idx| {
                    const frame = display_bridge.get_frame();
                    if (hs_idx < frame.hotspot_count) {
                        const hs = frame.hotspots[hs_idx];
                        var banner_buf: [128]u8 = undefined;
                        const text = std.fmt.bufPrint(&banner_buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Examined";
                        window.set_cue_banner(text, 120);
                        try stdout.print("\n[Look] {s}: \"{s}\"\n", .{ hs.get_name(), hs.get_examine_text() });
                    }
                },
                .interact_actor => |act| {
                    const frame = display_bridge.get_frame();
                    if (act.actor_index < frame.entity_count) {
                        const target_entity = frame.entities[act.actor_index];
                        const tname = target_entity.get_name();
                        var buf: [128]u8 = undefined;

                        switch (act.verb) {
                            .look_at => {
                                const desc = if (std.mem.eql(u8, tname, "Guard"))
                                    "A stern tavern guard watching for troublemakers."
                                else if (std.mem.eql(u8, tname, "Bard"))
                                    "A flamboyant musician with an enchanted lute."
                                else
                                    "A nimble feline mastermind.";
                                const text = std.fmt.bufPrint(&buf, "[Look] {s}: {s}", .{ tname, desc }) catch "Look";
                                window.set_cue_banner(text, 120);
                                try stdout.print("\n[Look] {s}: {s}\n", .{ tname, desc });
                            },
                            .talk_to => {
                                const pt = bespoke.display.renderer.get_entity_screen_pos(act.actor_index, frame.entities[0..frame.entity_count], window.width, window.height);
                                if (std.mem.eql(u8, tname, "Guard")) {
                                    const choices = [_][]const u8{
                                        "1. Meow innocently (Purr)",
                                        "2. Hiss at the Guard!",
                                        "3. [Slink away]",
                                    };
                                    window.show_dialogue(target_entity.entity, pt, "Guard", "Move along, cat! No mischief on my watch!", &choices);
                                } else if (std.mem.eql(u8, tname, "Bard")) {
                                    const choices = [_][]const u8{
                                        "1. Play a soothing melody! (Distract)",
                                        "2. What news of the cellar key?",
                                        "3. [Walk away]",
                                    };
                                    window.show_dialogue(target_entity.entity, pt, "Bard", "Care to hear a jaunty tavern ballad?", &choices);
                                } else {
                                    window.show_dialogue(target_entity.entity, pt, "Cat", "Meow! (I only speak in cunning heists.)", &[_][]const u8{});
                                }
                                try stdout.print("\n[Dialogue Started with {s}]\n", .{tname});
                            },
                            .pick_up => {
                                if (art.status_of(frame).cheese_holder == target_entity.entity) {
                                    _ = world.forget(target_entity.entity, carries, cheese.to_int());
                                    try world.remember(cat, carries, cheese.to_int(), 0);
                                    window.set_cue_banner("★ You snatched the Cheese from the Guard! ★", 120);
                                    window.play_sfx(.pickup);
                                    try stdout.print("\n★ [HEIST] Player snatched Cheese from {s}! ★\n", .{tname});
                                } else {
                                    const text = std.fmt.bufPrint(&buf, "You cannot pick up {s}!", .{tname}) catch "Error";
                                    window.set_cue_banner(text, 90);
                                }
                            },
                            .use_with => {
                                if (world.has_fact(cat, carries, cheese.to_int())) {
                                    const text = std.fmt.bufPrint(&buf, "You offer a crumb of cheese to {s}.", .{tname}) catch "Used";
                                    window.set_cue_banner(text, 90);
                                    try stdout.print("\n[Use] Offered cheese to {s}!\n", .{tname});
                                } else {
                                    window.set_cue_banner("You have nothing to use!", 90);
                                }
                            },
                            .walk => {
                                const layout = bespoke.display.renderer.get_entity_screen_layout(act.actor_index, frame.entities[0..frame.entity_count], window.width, window.height);
                                if (bespoke.display.renderer.find_nearest_waypoint(layout.pos.x, layout.pos.y, frame.waypoints[0..frame.waypoint_count], window.width, window.height)) |wp_id| {
                                    _ = try spatial.walk_to(cat, wp_id);
                                    window.set_cue_banner("Approaching actor...", 60);
                                }
                            },
                        }
                    }
                },
                .interact_hotspot => |hs_act| {
                    const frame = display_bridge.get_frame();
                    if (hs_act.hotspot_index < frame.hotspot_count) {
                        const hs = frame.hotspots[hs_act.hotspot_index];
                        var buf: [128]u8 = undefined;

                        switch (hs_act.verb) {
                            .look_at => {
                                const text = std.fmt.bufPrint(&buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Look";
                                window.set_cue_banner(text, 120);
                                try stdout.print("\n[Look] {s}: \"{s}\"\n", .{ hs.get_name(), hs.get_examine_text() });
                            },
                            .talk_to => {
                                const pt = bespoke.display.renderer.world_to_screen(hs.x, hs.y, window.width, window.height);
                                window.show_dialogue(hs.entity, pt, hs.get_name(), "...", &[_][]const u8{});
                                const text = std.fmt.bufPrint(&buf, "You speak to the {s}, but it stays silent.", .{hs.get_name()}) catch "Talk";
                                window.set_cue_banner(text, 90);
                                try stdout.print("\n[Dialogue] {s}\n", .{text});
                            },
                            .pick_up => {
                                const text = std.fmt.bufPrint(&buf, "The {s} is far too heavy to carry!", .{hs.get_name()}) catch "PickUp";
                                window.set_cue_banner(text, 90);
                            },
                            .use_with => {
                                if (world.has_fact(cat, carries, cheese.to_int())) {
                                    if (std.mem.eql(u8, hs.get_name(), "Fireplace")) {
                                        window.set_cue_banner("You toast cheese by the embers! A delicious snack!", 120);
                                        try stdout.print("\n[Use] Toasted cheese at the Fireplace!\n", .{});
                                    } else if (std.mem.eql(u8, hs.get_name(), "Wine Cask")) {
                                        window.set_cue_banner("You pair fine vintage wine with cheese! Magnifique!", 120);
                                        try stdout.print("\n[Use] Paired cheese with Wine Cask!\n", .{});
                                    } else {
                                        const text = std.fmt.bufPrint(&buf, "You place cheese on the {s}.", .{hs.get_name()}) catch "Use";
                                        window.set_cue_banner(text, 90);
                                    }
                                } else {
                                    const text = std.fmt.bufPrint(&buf, "Nothing interesting happens with the {s}.", .{hs.get_name()}) catch "Use";
                                    window.set_cue_banner(text, 90);
                                }
                            },
                            .walk => {
                                const pt = bespoke.display.renderer.world_to_screen(hs.x, hs.y, window.width, window.height);
                                if (bespoke.display.renderer.find_nearest_waypoint(pt.x, pt.y, frame.waypoints[0..frame.waypoint_count], window.width, window.height)) |wp_id| {
                                    _ = try spatial.walk_to(cat, wp_id);
                                    window.set_cue_banner("Walking to prop...", 60);
                                }
                            },
                        }
                    }
                },
                .dialogue_choice => |choice_idx| {
                    if (window.active_balloon) |b| {
                        const sname = b.get_speaker_name();
                        if (std.mem.eql(u8, sname, "Bard")) {
                            if (choice_idx == 0) {
                                // Choice 0: Play a soothing melody!
                                try world.remember(guard, charmed, bard.to_int(), 40);
                                window.set_cue_banner("♪ Bard plays an enchanting tune! Guard is Charmed! ♪", 120);
                                window.play_sfx(.alert);
                                try stdout.print("\n[Dialogue Choice] Bard plays lute! Guard is charmed!\n", .{});
                            } else if (choice_idx == 1) {
                                window.set_cue_banner("Bard: \"Rumor has it the cellar cask is full of elven wine!\"", 120);
                                try stdout.print("\n[Dialogue Choice] Bard shares cellar rumors!\n", .{});
                            } else {
                                window.set_cue_banner("You slip away quietly.", 60);
                            }
                        } else if (std.mem.eql(u8, sname, "Guard")) {
                            if (choice_idx == 0) {
                                window.set_cue_banner("Guard: \"Heh, good kitty... now shoo!\"", 90);
                                try stdout.print("\n[Dialogue Choice] Guard pets Cat and says shoo!\n", .{});
                            } else if (choice_idx == 1) {
                                window.set_cue_banner("Guard: \"Watch the claws, mangy flea-bag!\"", 90);
                                try stdout.print("\n[Dialogue Choice] Guard grumbles at Cat!\n", .{});
                            } else {
                                window.set_cue_banner("You slink into the shadows.", 60);
                            }
                        }
                    }
                    window.dismiss_dialogue();
                },
                .dismiss_dialogue => {
                    window.dismiss_dialogue();
                },
                .repl_command => |cmd| {
                    const line = cmd.buf[0..cmd.len];
                    const res = repl_instance.execute(line);
                    window.add_console_history(res.get_text());
                    if (res.output_len > 0) {
                        window.set_cue_banner(res.get_text(), 120);
                        try stdout.print("[REPL] > {s}\n       {s}\n", .{ line, res.get_text() });
                    }
                    // A REPL command that moved the clock past the timeline gets recorded.
                    if (world.current_tick >= session.timeline.len()) try session.record_now() else session.refresh();
                },
                .toggle_debug => {
                    const status_str = if (window.show_debug_overlay) "ENABLED" else "DISABLED";
                    try stdout.print("[Dashboard] Debug Fact & Fiber Inspector {s}\n", .{status_str});
                },
                .toggle_console => {
                    const status_str = if (window.show_console) "OPENED" else "CLOSED";
                    try stdout.print("[Console] Live REPL Console Drawer {s}\n", .{status_str});
                },
                .combine_inventory_items => |comb| {
                    const frame = display_bridge.get_frame();
                    if (comb.primary_index < frame.inventory_count and comb.secondary_index < frame.inventory_count) {
                        const p_name = frame.inventory[comb.primary_index].get_name();
                        const s_name = frame.inventory[comb.secondary_index].get_name();
                        var buf: [96]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "You attempt to combine {s} and {s}, but nothing happens.", .{ p_name, s_name }) catch "No combination";
                        window.set_cue_banner(msg, 90);
                        try stdout.print("\n[Combine] {s} + {s} -> no combination\n", .{ p_name, s_name });
                    }
                },
                .interact_inventory => |inv_act| {
                    const frame = display_bridge.get_frame();
                    if (inv_act.item_index < frame.inventory_count) {
                        const item_name = frame.inventory[inv_act.item_index].get_name();
                        if (inv_act.verb == .look_at) {
                            if (std.mem.eql(u8, item_name, "Cheese")) {
                                window.set_cue_banner("A golden wheel of sharp cheddar, liberated from the Guard.", 120);
                                try stdout.print("\n[Look Inventory] A golden wheel of sharp cheddar.\n", .{});
                            } else {
                                var buf: [128]u8 = undefined;
                                const text = std.fmt.bufPrint(&buf, "{s}: \"An item in your inventory.\"", .{item_name}) catch "Item";
                                window.set_cue_banner(text, 120);
                            }
                        }
                    }
                },
                .use_inventory_on_actor => |act| {
                    const frame = display_bridge.get_frame();
                    if (act.item_index < frame.inventory_count and act.actor_index < frame.entity_count) {
                        const item_name = frame.inventory[act.item_index].get_name();
                        const target_entity = frame.entities[act.actor_index];
                        const tname = target_entity.get_name();
                        var buf: [96]u8 = undefined;
                        const text = std.fmt.bufPrint(&buf, "You offer {s} to {s}.", .{ item_name, tname }) catch "Used";
                        window.set_cue_banner(text, 90);
                        try stdout.print("\n[Use In-Hand] Offered {s} to {s}!\n", .{ item_name, tname });
                    }
                },
                .use_inventory_on_hotspot => |hs_act| {
                    const frame = display_bridge.get_frame();
                    if (hs_act.item_index < frame.inventory_count and hs_act.hotspot_index < frame.hotspot_count) {
                        const item_name = frame.inventory[hs_act.item_index].get_name();
                        const hs = frame.hotspots[hs_act.hotspot_index];
                        var buf: [96]u8 = undefined;
                        if (std.mem.eql(u8, hs.get_name(), "Fireplace")) {
                            window.set_cue_banner("You toast cheese by the embers! A delicious snack!", 120);
                            try stdout.print("\n[Use In-Hand] Toasted {s} at the Fireplace!\n", .{item_name});
                        } else if (std.mem.eql(u8, hs.get_name(), "Wine Cask")) {
                            window.set_cue_banner("You pair fine vintage wine with cheese! Magnifique!", 120);
                            try stdout.print("\n[Use In-Hand] Paired {s} with Wine Cask!\n", .{item_name});
                        } else {
                            const text = std.fmt.bufPrint(&buf, "You place {s} on the {s}.", .{ item_name, hs.get_name() }) catch "Use";
                            window.set_cue_banner(text, 90);
                        }
                    }
                },
                else => {},
            }

            // 2. Advance simulation clock if unpaused or single-stepped
            if (session.tick_due()) {
                // Scripted narrative cues for the vertical slice
                if (world.current_tick == 1) {
                    try world.remember(guard, charmed, bard.to_int(), 4);
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

                // Discards any scrubbed-away future, ticks, records, and publishes the frame.
                _ = try session.advance();
            }

            // 3. Render 2D Frame at Display Refresh Rate (P6-02, P6-04)
            session.render();

            // Cap display loop ~60 FPS
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
}
