const std = @import("std");
const bespoke = @import("root.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Check command line arguments
    var is_headless_arg = false;
    var is_spitting_contest = false;
    var is_gk3 = false;
    var is_sword_fighting = false;
    var ticks_arg: usize = 20;

    var subcommand: ?enum { run, compile, check, help } = null;
    var target_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;

    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();
    _ = args_it.next(); // Skip binary name
    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "run")) {
            subcommand = .run;
            if (args_it.next()) |file| {
                target_file = file;
            }
        } else if (std.mem.eql(u8, arg, "compile")) {
            subcommand = .compile;
            if (args_it.next()) |file| {
                target_file = file;
            }
        } else if (std.mem.eql(u8, arg, "check")) {
            subcommand = .check;
            if (args_it.next()) |file| {
                target_file = file;
            }
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            if (args_it.next()) |out| {
                output_file = out;
            }
        } else if (std.mem.eql(u8, arg, "--ticks")) {
            if (args_it.next()) |t_str| {
                ticks_arg = std.fmt.parseInt(usize, t_str, 10) catch 20;
            }
        } else if (std.mem.eql(u8, arg, "--headless")) {
            is_headless_arg = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "help")) {
            subcommand = .help;
        } else if (std.mem.eql(u8, arg, "--spitting-contest") or std.mem.eql(u8, arg, "--spit")) {
            is_spitting_contest = true;
        } else if (std.mem.eql(u8, arg, "--gk3") or std.mem.eql(u8, arg, "--cat-moustache")) {
            is_gk3 = true;
        } else if (std.mem.eql(u8, arg, "--sword-fighting") or std.mem.eql(u8, arg, "--insults") or std.mem.eql(u8, arg, "--sword")) {
            is_sword_fighting = true;
        } else if (std.mem.eql(u8, arg, "--scenario")) {
            if (args_it.next()) |scen| {
                if (std.mem.eql(u8, scen, "spitting-contest") or std.mem.eql(u8, scen, "spit")) {
                    is_spitting_contest = true;
                } else if (std.mem.eql(u8, scen, "gk3") or std.mem.eql(u8, scen, "cat-moustache")) {
                    is_gk3 = true;
                } else if (std.mem.eql(u8, scen, "sword-fighting") or std.mem.eql(u8, scen, "insults") or std.mem.eql(u8, scen, "sword")) {
                    is_sword_fighting = true;
                }
            }
        } else if (target_file == null and !std.mem.startsWith(u8, arg, "-")) {
            subcommand = .run;
            target_file = arg;
        }
    }

    if (subcommand) |cmd| {
        switch (cmd) {
            .help => {
                try stdout.print(
                    \\BeSpoke Engine - Standalone Simulation Spine & Narrative Game DSL
                    \\
                    \\Usage:
                    \\  bespoke run <script.bespoke | game.bspk> [--headless] [--ticks N]
                    \\  bespoke compile <script.bespoke> -o <game.bspk>
                    \\  bespoke check <script.bespoke>
                    \\
                    \\Built-in Vertical Slices:
                    \\  bespoke --headless               (The Tavern Heist demo)
                    \\  bespoke --spitting-contest       (Monkey Island 2 Spitting Contest)
                    \\  bespoke --gk3                    (Gabriel Knight 3 Cat Moustache)
                    \\  bespoke --sword-fighting         (Monkey Island 1 Insult Sword Fighting)
                    \\
                , .{});
                return;
            },
            .check => {
                if (target_file) |fpath| {
                    const ok = try bespoke.runner.check_file(allocator, fpath, stdout);
                    if (!ok) std.process.exit(1);
                    return;
                } else {
                    try stdout.print("error: 'bespoke check' requires a script file path\n", .{});
                    std.process.exit(1);
                }
            },
            .compile => {
                if (target_file) |in_path| {
                    const out_path = output_file orelse "game.bspk";
                    try bespoke.runner.compile_file(allocator, in_path, out_path, stdout);
                    return;
                } else {
                    try stdout.print("error: 'bespoke compile' requires an input script file path\n", .{});
                    std.process.exit(1);
                }
            },
            .run => {
                if (target_file) |fpath| {
                    try bespoke.runner.run_file(allocator, fpath, .{
                        .ticks = ticks_arg,
                        .is_headless = is_headless_arg,
                        .verbose = true,
                    }, stdout);
                    return;
                }
            },
        }
    }

    if (is_sword_fighting) {
        if (is_headless_arg) {
            try bespoke.sword_fighting.run_headless(allocator, stdout);
        } else {
            try bespoke.sword_fighting.run_interactive(allocator, stdout);
        }
        return;
    }

    if (is_gk3) {
        if (is_headless_arg) {
            try bespoke.gk3_moustache.run_headless(allocator, stdout);
        } else {
            try bespoke.gk3_moustache.run_interactive(allocator, stdout);
        }
        return;
    }

    if (is_spitting_contest) {
        if (is_headless_arg) {
            try bespoke.spitting_contest.run_headless(allocator, stdout);
        } else {
            try bespoke.spitting_contest.run_gui(allocator, stdout);
        }
        return;
    }

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
    var repl_instance = bespoke.Repl.init(&world, &spatial, &vm);

    const patrol_pc = compiled.routine_entries.get("Patrol").?;

    _ = try vm.spawn_routine(guard, patrol_pc);

    // Array to record historical snapshot buffers for time-travel rewind (P5-02)
    var history_snapshots = std.ArrayList(std.ArrayList(u8)).init(allocator);
    defer {
        for (history_snapshots.items) |*buf| buf.deinit();
        history_snapshots.deinit();
    }

    // Initialize SDL2 Peripheral Display Window (D-008, P6-01)
    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Tavern Heist", 1280, 720);
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
        try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
        try stdout.print("Interactive Adventure Controls:\n", .{});
        try stdout.print("   - [Right Click]:         Cycle Verb (WALK, LOOK, TALK, TAKE, USE)\n", .{});
        try stdout.print("   - [Verb Bar Buttons]:    Click WALK, LOOK, TALK, TAKE, or USE to activate\n", .{});
        try stdout.print("   - [Left Click Actor]:    Interact with Guard, Bard, or Cat with active verb\n", .{});
        try stdout.print("   - [Left Click Prop]:     Interact with Fireplace, Bar Counter, or Wine Cask\n", .{});
        try stdout.print("   - [Left Click Waypoint]: Direct Cat (Player) to walk\n", .{});
        try stdout.print("   - [Timeline Scrubber]:   Click or drag timeline bar (or [< / >] arrows) to scrub history\n", .{});
        try stdout.print("   - [F1 / D]:              Toggle Debug Inspector (Active Facts, Fibers, Stacks, Spatial)\n", .{});
        try stdout.print("   - [Tab / ` / C]:         Toggle Live REPL Console Drawer ('help', 'remember', 'walk')\n", .{});
        try stdout.print("   - [Space]:               Pause / Resume Simulation\n", .{});
        try stdout.print("   - [N]:                   Single-step Simulation Tick\n", .{});
        try stdout.print("   - [R]:                   Instant Time-Travel Rewind to Tick 2\n", .{});
        try stdout.print("   - [Esc / Close]:         Exit\n\n", .{});

        // Initial snapshot at tick 0
        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.set_max_history_tick(0);
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
                                if (frame.cheese_holder == target_entity.entity) {
                                    _ = world.forget(target_entity.entity, carries, cheese.to_int());
                                    try world.remember(cat, carries, cheese.to_int(), 0);
                                    window.set_cue_banner("★ You snatched the Cheese from the Guard! ★", 120);
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
                            .walk => {},
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
                            .walk => {},
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
                .rewind => {
                    if (history_snapshots.items.len > 2) {
                        is_paused = true;
                        const target_snapshot = history_snapshots.items[2];
                        var stream = std.io.fixedBufferStream(target_snapshot.items);
                        try world.restore_state(stream.reader());
                        // Sync display frame
                        display_bridge.capture_frame(&world, &spatial, &vm);
                        display_bridge.set_max_history_tick(history_snapshots.items.len - 1);
                        display_bridge.swap();
                        window.set_cue_banner("<<< REWOUND TO PRE-HEIST TICK 2 (PAUSED) <<<", 90);
                        try stdout.print("[Time-Travel] Rewound simulation to Tick 2!\n", .{});
                    }
                },
                .scrub_to_tick => |target_tick| {
                    if (history_snapshots.items.len > 0) {
                        const clamped = @min(target_tick, history_snapshots.items.len - 1);
                        is_paused = true;
                        const target_snapshot = history_snapshots.items[clamped];
                        var stream = std.io.fixedBufferStream(target_snapshot.items);
                        try world.restore_state(stream.reader());
                        display_bridge.capture_frame(&world, &spatial, &vm);
                        display_bridge.set_max_history_tick(history_snapshots.items.len - 1);
                        display_bridge.swap();

                        var banner_buf: [96]u8 = undefined;
                        const text = std.fmt.bufPrint(&banner_buf, "<<< TIME-TRAVEL: SCRUBBED TO TICK {d} (PAUSED) <<<", .{world.current_tick}) catch "Scrubbed";
                        window.set_cue_banner(text, 90);
                        try stdout.print("[Time-Travel] Scrubbed simulation to Tick {d} (of {d})\n", .{ world.current_tick, history_snapshots.items.len - 1 });
                    }
                },
                .repl_command => |cmd| {
                    const line = cmd.buf[0..cmd.len];
                    const res = repl_instance.execute(line);
                    window.add_console_history(res.get_text());
                    if (res.output_len > 0) {
                        window.set_cue_banner(res.get_text(), 120);
                        try stdout.print("[REPL] > {s}\n       {s}\n", .{ line, res.get_text() });
                    }
                    if (world.current_tick >= history_snapshots.items.len) {
                        var snap = std.ArrayList(u8).init(allocator);
                        try world.save_state(snap.writer());
                        try history_snapshots.append(snap);
                    }
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.set_max_history_tick(history_snapshots.items.len - 1);
                    display_bridge.swap();
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
                .spit_contest_spit, .sound_horn, .drink_green_drink, .tamper_flags => {},
                .none => {},
            }

            // 2. Advance simulation clock if unpaused or single-stepped
            const now = std.time.milliTimestamp();
            if (should_step_now or (!is_paused and now - last_tick_time >= tick_interval_ms)) {
                last_tick_time = now;

                // If simulation clock was scrubbed into the past and is advancing,
                // discard invalidated future snapshots to record a divergent timeline.
                if (world.current_tick + 1 < history_snapshots.items.len) {
                    for (history_snapshots.items[world.current_tick + 1 ..]) |*s| {
                        s.deinit();
                    }
                    history_snapshots.shrinkRetainingCapacity(world.current_tick + 1);
                }

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

                try vm.step_tick();

                // Save snapshot for potential rewind
                var snap = std.ArrayList(u8).init(allocator);
                try world.save_state(snap.writer());
                try history_snapshots.append(snap);

                // Synchronize display bridge
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.set_max_history_tick(history_snapshots.items.len - 1);
                display_bridge.swap();
            }

            // 3. Render 2D Frame at Display Refresh Rate (P6-02, P6-04)
            window.render_frame(display_bridge.get_frame(), is_paused);

            // Cap display loop ~60 FPS
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
}
