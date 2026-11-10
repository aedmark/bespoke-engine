const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const SpitKey = enum(u16) { spit, horn, drink, flags };

const spit_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_s, .action = @intFromEnum(SpitKey.spit), .sfx = art.sfx(.whistle) },
    .{ .key = bespoke.display.renderer.c.SDLK_h, .action = @intFromEnum(SpitKey.horn), .sfx = art.sfx(.horn) },
    .{ .key = bespoke.display.renderer.c.SDLK_g, .action = @intFromEnum(SpitKey.drink), .sfx = .{ .stock = .pickup } },
    .{ .key = bespoke.display.renderer.c.SDLK_f, .action = @intFromEnum(SpitKey.flags), .sfx = .{ .stock = .combine } },
});

pub const SPITTING_CONTEST_SCRIPT =
    \\scene: Spitting Competition
    \\cast: Guybrush, Organiser, Onlookers
    \\props: Flags
    \\marks: Starting Line, Looking Offstage
    \\
    \\Tampered with is a state, which can be tampered with or not tampered with.
    \\Distracted is a state, which can be distracted or not distracted.
    \\Wind is a state, which can be blowing or not blowing. The wind is not blowing in the scene.
    \\Spit is a state, which can be thick or not. Spit is not thick in the scene.
    \\
    \\remember: Carries(Guybrush, Horn) ~ this is something that will have happened in another scene
    \\remember: Carries(Guybrush, GreenDrink)
    \\
    \\routine EggingCrowd(Organiser):
    \\  loop:
    \\    walk Organiser to Onlookers
    \\    say Organiser to Onlookers: (something at random from list of Spitting Competition Quips)
    \\    wait 30 ticks
    \\    walk Organiser to Starting Line
    \\    wait 20 ticks
    \\    say Organiser to Scene: (something at random from list of Spitting Competition Encouragements)
    \\    wait 20 ticks
    \\
    \\routine WindBlowing(Scene):
    \\  loop:
    \\    Wind is not blowing in the scene.
    \\    wait 150 ticks
    \\    Wind is blowing in the scene.
    \\    wait 50 ticks
    \\
    \\when currently Wind is blowing:
    \\  interrupt Organiser with:
    \\    animate wind-blowing
    \\
    \\when Wind stops being blowing:
    \\  interrupt Organiser with:
    \\    stop animate wind-blowing
    \\
    \\when TalksTo(Guybrush, Organiser):
    \\  interrupt Organiser with:
    \\    face Organiser toward Guybrush
    \\    say Organiser to Scene: "Step right up to the line, lad!"
    \\    resume previous action
    \\
    \\on cue Uses(Guybrush, Horn):
    \\  interrupt Organiser with:
    \\    walk Organiser to Looking Offstage
    \\    face Onlookers toward Looking Offstage
    \\    say Organiser to Scene: "About time that damn ship came in."
    \\    remember Distracted[Organiser, Onlookers] for 100 ticks
    \\
    \\when Organiser forgets Distracted:
    \\  interrupt Organiser with:
    \\    walk Organiser to Starting Line
    \\    face Organiser toward Starting Line
    \\    face Onlookers toward Starting Line
    \\    resume previous action
    \\
    \\on cue Uses(Guybrush, Flags):
    \\  if Flags are tampered with:
    \\    say Narrator to Scene: "You've already tampered with the flags!"
    \\    done
    \\  if Flags are not tampered with:
    \\    if not Distracted(Organiser, _):
    \\      say Narrator to Scene: "You better not, he's watching."
    \\      done
    \\    if Distracted(Organiser, _):
    \\      now Flags are tampered with
    \\      animate (Flags, flags-tampering)
    \\      done
    \\
    \\on cue Uses(Guybrush, GreenDrink):
    \\  animate (Guybrush, Guybrush-drinking)
    \\  now Spit is thick
    \\
    \\on cue LeavingScene(Guybrush):
    \\  now Spit is not thick
    \\
    \\on cue Spits(Guybrush):
    \\  forget Placed(Guybrush)
    \\  if Spit is not thick:
    \\    say Guybrush to Scene: "Ptooie!"
    \\    animate (Guybrush, Guybrush-dribbling)
    \\    remember Placed(Guybrush, Dribble)
    \\  if Spit is thick:
    \\    if Flags are not tampered with:
    \\      animate (Guybrush, Guybrush-not-winning)
    \\      say Organiser to Scene: "Oh, third place!"
    \\      remember Placed(Guybrush, ThirdPlace)
    \\    if Flags are tampered with:
    \\      if Wind is not blowing:
    \\        animate (Guybrush, Guybrush-not-winning)
    \\        say Organiser to Scene: "Oh, second place!"
    \\        remember Placed(Guybrush, SecondPlace)
    \\      if Wind is blowing:
    \\        animate (Guybrush, Guybrush-winning)
    \\        say Organiser to Scene: "OH, we have a winner!"
    \\        remember Placed(Guybrush, FirstPlace)
;

pub const SpitResult = enum {
    dribble_third,
    thick_flags_untouched_third,
    thick_flags_moved_no_wind_second,
    winner_first,
};

/// Reads the placement the script's `Spits` handler recorded for Guybrush, or null if he has
/// not spat. The rule itself (thick spit, moved flags, wind) lives in the script (P32-19).
pub fn placement(world: *const bespoke.World) ?SpitResult {
    const guybrush = world.lookup_entity("Guybrush") orelse return null;
    const placed_rel = world.lookup_relation("Placed") orelse return null;
    const fact = world.find_first(guybrush, placed_rel, null) orelse return null;
    const name = world.get_entity_name(bespoke.EntityId.from_int(fact.object_or_value)) orelse return null;
    if (std.mem.eql(u8, name, "Dribble")) return .dribble_third;
    if (std.mem.eql(u8, name, "ThirdPlace")) return .thick_flags_untouched_third;
    if (std.mem.eql(u8, name, "SecondPlace")) return .thick_flags_moved_no_wind_second;
    if (std.mem.eql(u8, name, "FirstPlace")) return .winner_first;
    return null;
}

/// Guybrush spits: fires the script's `Spits` cue, runs the tick that judges it, and returns
/// the placement the script recorded.
pub fn spit(world: *bespoke.World, vm: *bespoke.VM, compiled: *const bespoke.CompiledProgram) !SpitResult {
    const guybrush = world.lookup_entity("Guybrush") orelse return error.SpitNotJudged;
    _ = try vm.fire_cue(compiled, "Spits", guybrush, null, null);
    _ = try bespoke.host.tick(vm, compiled);
    return placement(world) orelse error.SpitNotJudged;
}

/// Asserts `subject is <state>` the way the script's `now X is Y` does. The script stores the
/// object as the interned entity `true`, and its `if X is Y` conditions compare against that
/// (ARCHITECTURE, Claims vs. code), so a host asserting the value 1 would not be seen.
fn set_state(world: *bespoke.World, subject: bespoke.EntityId, state: bespoke.RelationKind) !void {
    const truth = try world.intern_entity("true");
    try world.remember(subject, state, truth.to_int(), 0);
}

/// Executes headless simulation of the Booty Island Spitting Contest vertical slice (P10-03, D-012).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("   BeSpoke Engine: The Booty Island Spitting Contest Vertical Slice\n", .{});
    try writer.print("  (Natural Stageplay DSL * Relational Spine * Falling Edge & TTL)  \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Lowering Booty Island stageplay script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SPITTING_CONTEST_SCRIPT);
    defer compiled.deinit();

    const guybrush = world.lookup_entity("Guybrush").?;
    const organiser = world.lookup_entity("Organiser").?;
    const onlookers = world.lookup_entity("Onlookers").?;
    const flags = world.lookup_entity("Flags").?;
    const room_ent = world.lookup_entity("Spitting Competition") orelse try world.intern_entity("Spitting Competition");

    const starting_line_wp = spatial.graph.find_waypoint("Starting Line") orelse 1;
    const offstage_wp = spatial.graph.find_waypoint("Looking Offstage") orelse 2;
    const onlookers_wp = spatial.graph.find_waypoint("Onlookers") orelse
        try spatial.graph.add_waypoint(room_ent, -8, 3, "Onlookers");

    if (spatial.graph.get_waypoint(starting_line_wp)) |_| {
        spatial.graph.waypoints.items[starting_line_wp - 1].pos = .{ .x = 0, .y = 0 };
    }
    if (spatial.graph.get_waypoint(offstage_wp)) |_| {
        spatial.graph.waypoints.items[offstage_wp - 1].pos = .{ .x = 42, .y = 0 };
    }

    try spatial.graph.connect(onlookers_wp, starting_line_wp, null);
    try spatial.graph.connect(starting_line_wp, offstage_wp, null);

    // Position Flags hotspot in the field at x=22
    for (spatial.hotspots.items) |*hs| {
        if (std.mem.indexOf(u8, hs.name, "Flag") != null) {
            hs.pos = .{ .x = 22, .y = -2 };
            break;
        }
    }

    try spatial.register_entity(guybrush, starting_line_wp, 10);
    try spatial.register_entity(organiser, starting_line_wp, 12);
    try spatial.register_entity(onlookers, onlookers_wp, 15);

    // Initial items for Guybrush
    const carries_rel = try world.intern_relation("Carries", .set);
    const horn_ent = try world.intern_entity("Horn");
    const drink_ent = try world.intern_entity("GreenDrink");
    try world.remember(guybrush, carries_rel, horn_ent.to_int(), 0);
    try world.remember(guybrush, carries_rel, drink_ent.to_int(), 0);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);

    if (compiled.routine_entries.get("EggingCrowd")) |entry| {
        _ = try vm.spawn_routine(organiser, entry);
    }

    var timeline = bespoke.host.Timeline.init(allocator);
    defer timeline.deinit();

    try writer.print("\n>>> STARTING BOOTY ISLAND SPITTING CONTEST SIMULATION <<<\n", .{});

    // Initial state snapshot 0
    try timeline.record(&world);

    // Step 1: Baseline attempt (No prep)
    try writer.print("\n[Step 1: Baseline Attempt] Guybrush steps up to Starting Line and spits...\n", .{});
    const spit_ent = world.lookup_entity("Spit").?;
    const wind_ent = world.lookup_entity("Wind").?;
    // One snapshot per tick keeps timeline indices equal to tick numbers for the rewind below.
    const res1 = try spit(&world, &vm, &compiled);
    try timeline.record(&world);
    try writer.print("   -> Result: {s} (Dribbles on chin! Third place!)\n", .{@tagName(res1)});

    for (0..4) |_| {
        try vm.step_tick();
        try timeline.record(&world);
    }

    // Step 2: Guybrush drinks GreenDrink
    try writer.print("\n[Step 2: Guybrush drinks GreenDrink] \"Glug glug glug...\"\n", .{});
    const thick_rel = try world.intern_relation("thick", .set);
    try set_state(&world, spit_ent, thick_rel);
    try writer.print("   -> Fact asserted: Spit is thick!\n", .{});

    const res2 = try spit(&world, &vm, &compiled);
    try timeline.record(&world);
    try writer.print("   -> Spit check: {s} (Thick spit, but flags untouched! Third place!)\n", .{@tagName(res2)});

    // Step 3: Attempting to move Flags while Organiser watches
    try writer.print("\n[Step 3: Attempting to move Flags while Organiser watches]...\n", .{});
    const distracted_rel = try world.intern_relation("Distracted", .set);
    const is_distracted = world.has_fact(organiser, distracted_rel, null);
    if (!is_distracted) {
        try writer.print("   -> Organiser is watching! Narrator: \"You better not, he's watching.\"\n", .{});
    }

    const pre_horn_tick = world.current_tick;

    // Step 4: Distract with Ship's Horn
    try writer.print("\n[Step 4: Guybrush sounds Ship's Horn!] *** HOOOOOOONK! ***\n", .{});
    try world.remember(organiser, distracted_rel, onlookers.to_int(), 100);
    _ = try spatial.walk_to(organiser, offstage_wp);
    _ = try spatial.walk_to(onlookers, offstage_wp);
    try writer.print("   -> Organiser: \"About time that damn ship came in!\"\n", .{});
    try writer.print("   -> Organiser and Onlookers walk to Looking Offstage! (Distracted TTL: 100 ticks)\n", .{});

    for (0..3) |_| {
        try vm.step_tick();
        try timeline.record(&world);
    }

    // Step 5: Move flags while distracted!
    try writer.print("\n[Step 5: Guybrush tampers with Flags while crowd is distracted!]\n", .{});
    const tampered_rel = try world.intern_relation("tampered", .set);
    try set_state(&world, flags, tampered_rel);
    try writer.print("   -> Fact asserted: Flags are tampered with (moved closer to line)!\n", .{});

    const res3 = try spit(&world, &vm, &compiled);
    try timeline.record(&world);
    try writer.print("   -> Spit check without wind: {s} (Second place! Close, but need a tailwind!)\n", .{@tagName(res3)});

    // Step 6: Wind gust arrives! (Rising edge trigger)
    try writer.print("\n[Step 6: Wind gust cycles in!] Rising edge trigger activates...\n", .{});
    const blowing_rel = try world.intern_relation("blowing", .set);
    try set_state(&world, wind_ent, blowing_rel);

    try vm.step_tick();
    {
        try timeline.record(&world);
    }

    try writer.print("   -> Wind is blowing! Thick Spit + Tampered Flags + Tailwind = GUYBRUSH SPITS!\n", .{});
    const res4 = try spit(&world, &vm, &compiled);
    try timeline.record(&world);
    try writer.print("   -> FINAL RESULT: {s}!\n", .{@tagName(res4)});
    try writer.print("   -> Organiser: \"OH, we have a winner! First Place!\"\n", .{});

    // Step 7: TTL Expiration and Falling Edge
    try writer.print("\n[Step 7: Testing TTL Expiration & Falling-Edge Triggers]\n", .{});
    while (world.has_fact(organiser, distracted_rel, null)) {
        try vm.step_tick();
        try timeline.record(&world);
    }
    try writer.print("   -> Distraction TTL expired at Tick {d}!\n", .{world.current_tick});
    try writer.print("   -> 'when Organiser forgets Distracted' fired: Organiser returned to Starting Line.\n", .{});

    _ = world.forget(wind_ent, blowing_rel, null);
    try vm.step_tick();
    try writer.print("   -> Wind stopped blowing: 'when Wind stops being blowing' falling-edge hook fired.\n", .{});

    // Step 8: Time-Travel Rewind
    try writer.print("\n[Step 8: Time-Travel Rewind Demo]\n", .{});
    try writer.print("   -> Rewinding simulation to Tick {d} (before Horn distraction)...\n", .{pre_horn_tick});
    _ = try timeline.restore(&world, pre_horn_tick);

    try writer.print("   -> Rewound Tick: {d}\n", .{world.current_tick});
    try writer.print("   -> Organiser Distracted? {s} (Restored to false!)\n", .{if (world.has_fact(organiser, distracted_rel, null)) "YES" else "NO"});
    try writer.print("   -> Flags Tampered?       {s} (Restored to false!)\n", .{if (world.has_fact(flags, tampered_rel, null)) "YES" else "NO"});
    const rewound_res = try spit(&world, &vm, &compiled);
    try writer.print("   -> Rewound Contest Result: {s} (Back to 3rd place!)\n", .{@tagName(rewound_res)});
    try writer.print("\n===================================================================\n", .{});
    try writer.print("   Booty Island Spitting Contest Vertical Slice Successfully Completed!  \n", .{});
    try writer.print("===================================================================\n", .{});
}

/// Launches the full graphical 2D adventure display window for the Spitting Contest (P10-03, D-001, D-008, D-012).
pub fn run_gui(allocator: std.mem.Allocator, stdout: anytype) !void {
    try stdout.print("\n===================================================================\n", .{});
    try stdout.print("   BeSpoke Engine: The Booty Island Spitting Contest (Graphical 2D)\n", .{});
    try stdout.print("  (Natural Stageplay DSL * Relational Spine * Falling Edge & TTL)  \n", .{});
    try stdout.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try stdout.print("[Compiler] Lowering Booty Island stageplay script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SPITTING_CONTEST_SCRIPT);
    defer compiled.deinit();

    const guybrush = world.lookup_entity("Guybrush").?;
    const organiser = world.lookup_entity("Organiser").?;
    const onlookers = world.lookup_entity("Onlookers").?;
    const flags = world.lookup_entity("Flags").?;
    const room_ent = world.lookup_entity("Spitting Competition") orelse try world.intern_entity("Spitting Competition");

    const starting_line_wp = spatial.graph.find_waypoint("Starting Line") orelse 1;
    const offstage_wp = spatial.graph.find_waypoint("Looking Offstage") orelse 2;
    const onlookers_wp = spatial.graph.find_waypoint("Onlookers") orelse
        try spatial.graph.add_waypoint(room_ent, -8, 3, "Onlookers");

    if (spatial.graph.get_waypoint(starting_line_wp)) |_| {
        spatial.graph.waypoints.items[starting_line_wp - 1].pos = .{ .x = 0, .y = 0 };
    }
    if (spatial.graph.get_waypoint(offstage_wp)) |_| {
        spatial.graph.waypoints.items[offstage_wp - 1].pos = .{ .x = 42, .y = 0 };
    }

    try spatial.graph.connect(onlookers_wp, starting_line_wp, null);
    try spatial.graph.connect(starting_line_wp, offstage_wp, null);

    // Position Flags hotspot in the field at x=22
    for (spatial.hotspots.items) |*hs| {
        if (std.mem.indexOf(u8, hs.name, "Flag") != null) {
            hs.pos = .{ .x = 22, .y = -2 };
            break;
        }
    }

    try spatial.register_entity(guybrush, starting_line_wp, 10);
    try spatial.register_entity(organiser, starting_line_wp, 12);
    try spatial.register_entity(onlookers, onlookers_wp, 15);

    // Initial items for Guybrush
    const carries_rel = try world.intern_relation("Carries", .set);
    const horn_ent = try world.intern_entity("Horn");
    const drink_ent = try world.intern_entity("GreenDrink");
    try world.remember(guybrush, carries_rel, horn_ent.to_int(), 0);
    try world.remember(guybrush, carries_rel, drink_ent.to_int(), 0);

    const thick_rel = try world.intern_relation("thick", .set);
    const tampered_rel = try world.intern_relation("tampered", .set);
    const distracted_rel = try world.intern_relation("Distracted", .set);
    const spit_ent = world.lookup_entity("Spit").?;

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);

    var display_bridge = bespoke.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("Guybrush")) |player| display_bridge.set_active_character(player);
    var repl_instance = bespoke.Repl.init(&world, &spatial, &vm);

    if (compiled.routine_entries.get("EggingCrowd")) |entry| {
        _ = try vm.spawn_routine(organiser, entry);
    }
    if (compiled.routine_entries.get("WindBlowing")) |entry| {
        _ = try vm.spawn_routine(room_ent, entry);
    }

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Booty Island Spitting Contest", 1280, 720);
    defer window.deinit();
    window.set_theme(&spit_theme);

    vm.current_scene = room_ent;
    display_bridge.attach_audio_bridge(window.audio_bridge);
    window.set_bgm(art.track(.spitting_contest));

    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
    try stdout.print("Booty Island Contest Controls:\n", .{});
    try stdout.print("   - [S]:                   SPIT! (Evaluate spit attempt against active facts)\n", .{});
    try stdout.print("   - [H]:                   SOUND SHIP'S HORN (Distract crowd for 100 ticks)\n", .{});
    try stdout.print("   - [G]:                   DRINK GREEN DRINK (Thicken spit)\n", .{});
    try stdout.print("   - [F]:                   TAMPER WITH FLAGS (Move record line closer)\n", .{});
    try stdout.print("   - [Left Click Actor]:    Interact with Guybrush, Organiser, or Onlookers\n", .{});
    try stdout.print("   - [Left Click Prop]:     Examine or Move Flags\n", .{});
    try stdout.print("   - [Timeline Scrubber]:   Click or drag timeline bar (or [< / >] arrows)\n", .{});
    try stdout.print("   - [F1 / D]:              Toggle Debug Relational Fact & Fiber Overlay\n", .{});
    try stdout.print("   - [Tab / ` / C]:         Toggle Live REPL Console Drawer\n", .{});
    try stdout.print("   - [Space]:               Pause / Resume Simulation Clock\n", .{});
    try stdout.print("   - [N]:                   Single-step Simulation Tick\n", .{});
    try stdout.print("   - [R]:                   Instant Time-Travel Rewind\n", .{});
    try stdout.print("   - [Esc / Close]:         Exit\n\n", .{});

    // Snapshot 0 and the first frame (host kit, P32-16, D-033)
    var session = try bespoke.host.Session.init(allocator, &world, &spatial, &vm, &compiled, &display_bridge, &window);
    defer session.deinit();

    window.set_cue_banner("Welcome to Booty Island! Press [S] to Spit, [H] for Horn, [G] for Drink, [F] for Flags.", 150);

    while (true) {
        const action = window.poll_events(session.frame());

        if (action == .rewind) {
            // This proof's [R] returns to the opening state rather than one step back.
            if ((try session.jump_to(0)) != null) window.set_cue_banner("<<< REWOUND TO INITIAL STATE (TICK 0) <<<", 90);
        } else if (try session.handle_common(action)) {} else switch (action) {
            .quit => break,
            .walk_player => |wp_id| {
                _ = try spatial.walk_to(guybrush, wp_id);
                window.set_cue_banner("Directing Guybrush to waypoint.", 60);
            },
            .examine_hotspot => |hs_idx| {
                const frame = display_bridge.get_frame();
                if (hs_idx < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_idx];
                    var buf: [128]u8 = undefined;
                    const text = std.fmt.bufPrint(&buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Flags";
                    window.set_cue_banner(text, 120);
                }
            },
            .interact_actor => |act| {
                const frame = display_bridge.get_frame();
                if (act.actor_index < frame.entity_count) {
                    const target_entity = frame.entities[act.actor_index];
                    const tname = target_entity.get_name();
                    const pt = bespoke.display.renderer.get_entity_screen_pos(act.actor_index, frame.entities[0..frame.entity_count], window.width, window.height);

                    if (std.mem.eql(u8, tname, "Organiser")) {
                        window.show_dialogue(
                            target_entity.entity,
                            pt,
                            "Organiser",
                            "\"Step right up, lad! You think you have what it takes?\"",
                            &[_][]const u8{
                                "1. \"I'm ready to spit!\"",
                                "2. \"What are the rules again?\"",
                                "3. \"Never mind.\"",
                            },
                        );
                    } else if (std.mem.eql(u8, tname, "Guybrush")) {
                        window.set_cue_banner("Guybrush: \"I am Guybrush Threepwood, mighty spitter!\"", 90);
                    } else {
                        window.set_cue_banner("Onlookers: \"Hooray! Make way for the next spitter!\"", 90);
                    }
                }
            },
            .interact_hotspot => |hs_act| {
                const frame = display_bridge.get_frame();
                if (hs_act.hotspot_index < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_act.hotspot_index];
                    if (hs_act.verb == .look_at) {
                        var buf: [128]u8 = undefined;
                        const text = std.fmt.bufPrint(&buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Flags";
                        window.set_cue_banner(text, 120);
                    } else if (hs_act.verb == .walk) {
                        const pt = bespoke.display.renderer.world_to_screen(hs.x, hs.y, window.width, window.height);
                        if (bespoke.display.renderer.find_nearest_waypoint(pt.x, pt.y, frame.waypoints[0..frame.waypoint_count], window.width, window.height)) |wp_id| {
                            _ = try spatial.walk_to(guybrush, wp_id);
                            window.set_cue_banner("Approaching flags...", 60);
                        }
                    } else {
                        const is_distracted = world.has_fact(organiser, distracted_rel, null);
                        if (is_distracted) {
                            try set_state(&world, flags, tampered_rel);
                            window.set_cue_banner("★ You secretly moved the flags closer while the crowd wasn't looking! ★", 120);
                            window.play_sfx(.combine);
                        } else {
                            window.set_cue_banner("Narrator: \"You better not, he's watching.\"", 90);
                        }
                    }
                }
            },
            .interact_inventory => |inv_act| {
                const frame = display_bridge.get_frame();
                if (inv_act.item_index < frame.inventory_count) {
                    const item_name = frame.inventory[inv_act.item_index].get_name();
                    if (inv_act.verb == .look_at) {
                        if (std.mem.indexOf(u8, item_name, "Horn") != null) {
                            window.set_cue_banner("Ship's Foghorn: A brass horn capable of producing a deafening blast.", 120);
                        } else if (std.mem.indexOf(u8, item_name, "Drink") != null) {
                            window.set_cue_banner("Green Drink: A thick, sugary syrup from the scumm bar. Thickens saliva.", 120);
                        } else {
                            var buf: [128]u8 = undefined;
                            const text = std.fmt.bufPrint(&buf, "{s}: \"An item in Guybrush's inventory.\"", .{item_name}) catch "Item";
                            window.set_cue_banner(text, 120);
                        }
                    } else if (inv_act.verb == .use_with) {
                        if (std.mem.indexOf(u8, item_name, "Horn") != null) {
                            try world.remember(organiser, distracted_rel, onlookers.to_int(), 100);
                            _ = try spatial.walk_to(organiser, offstage_wp);
                            _ = try spatial.walk_to(onlookers, offstage_wp);
                            window.set_cue_banner("HOOOOONK! Organiser: \"About time that damn ship came in!\" Crowd distracted!", 120);
                            window.play_sound(art.sfx(.horn));
                        } else if (std.mem.indexOf(u8, item_name, "Drink") != null) {
                            try set_state(&world, spit_ent, thick_rel);
                            window.set_cue_banner("\"Glug glug glug...\" Guybrush's spit is now thick and potent!", 120);
                            window.play_sfx(.pickup);
                        }
                    }
                }
            },
            .dialogue_choice => |choice_idx| {
                if (choice_idx == 0) {
                    _ = try vm.fire_cue(&compiled, "Spits", guybrush, null, null);
                    _ = try session.advance();
                    const res = placement(&world) orelse return error.SpitNotJudged;
                    switch (res) {
                        .dribble_third => {
                            window.set_cue_banner("Guybrush: \"Ptooie!\" ...Dribbles on his chin! (3rd Place)", 120);
                            window.play_sound(art.sfx(.splash));
                        },
                        .thick_flags_untouched_third => {
                            window.set_cue_banner("Guybrush: \"Ptooie!\" Thick spit flies, but flags are untouched! (3rd Place)", 120);
                            window.play_sound(art.sfx(.whistle));
                        },
                        .thick_flags_moved_no_wind_second => {
                            window.set_cue_banner("Guybrush: \"Ptooie!\" Flies past moved flags! Second Place! (Need wind!)", 120);
                            window.play_sound(art.sfx(.whistle));
                        },
                        .winner_first => {
                            window.set_cue_banner("★ WINNER! Riding the wind past the champion line! FIRST PLACE! ★", 180);
                            window.play_sfx(.alert);
                        },
                    }
                } else if (choice_idx == 1) {
                    window.set_cue_banner("Organiser: \"Spit past the flags to win! Thick spit and a strong wind will do it!\"", 120);
                } else {
                    window.set_cue_banner("Guybrush steps back.", 60);
                }
            },
            .dismiss_dialogue => window.dismiss_dialogue(),
            .custom => |id| if (std.meta.intToEnum(SpitKey, id)) |key| switch (key) {
                .spit => {
                    _ = try vm.fire_cue(&compiled, "Spits", guybrush, null, null);
                    _ = try session.advance();
                    const res = placement(&world) orelse return error.SpitNotJudged;
                    switch (res) {
                        .dribble_third => {
                            window.set_cue_banner("Guybrush: \"Ptooie!\" ...Dribbles on his chin! (3rd Place)", 120);
                            window.play_sound(art.sfx(.splash));
                        },
                        .thick_flags_untouched_third => {
                            window.set_cue_banner("Guybrush: \"Ptooie!\" Thick spit flies, but flags are untouched! (3rd Place)", 120);
                            window.play_sound(art.sfx(.whistle));
                        },
                        .thick_flags_moved_no_wind_second => {
                            window.set_cue_banner("Guybrush: \"Ptooie!\" Past moved flags! Second Place! (Need a gust of wind!)", 120);
                            window.play_sound(art.sfx(.whistle));
                        },
                        .winner_first => {
                            window.set_cue_banner("★ WINNER! Riding the wind past the champion line! FIRST PLACE! ★", 180);
                            window.play_sfx(.alert);
                        },
                    }
                },
                .horn => {
                    try world.remember(organiser, distracted_rel, onlookers.to_int(), 100);
                    _ = try spatial.walk_to(organiser, offstage_wp);
                    _ = try spatial.walk_to(onlookers, offstage_wp);
                    window.set_cue_banner("HOOOOONK! Organiser: \"About time that damn ship came in!\" Crowd distracted!", 120);
                    window.play_sound(art.sfx(.horn));
                },
                .drink => {
                    try set_state(&world, spit_ent, thick_rel);
                    window.set_cue_banner("\"Glug glug glug...\" Guybrush's spit is now thick and potent!", 120);
                    window.play_sfx(.pickup);
                },
                .flags => {
                    const is_distracted = world.has_fact(organiser, distracted_rel, null);
                    if (is_distracted) {
                        try set_state(&world, flags, tampered_rel);
                        window.set_cue_banner("★ Flags secretly moved closer to the starting line! ★", 120);
                        window.play_sfx(.combine);
                    } else {
                        window.set_cue_banner("Narrator: \"You better not, he's watching.\"", 90);
                    }
                },
            } else |_| {},
            .repl_command => |cmd| {
                const line = cmd.buf[0..cmd.len];
                const res = repl_instance.execute(line);
                window.add_console_history(res.get_text());
                if (res.output_len > 0) {
                    window.set_cue_banner(res.get_text(), 120);
                }
                session.refresh();
            },
            .toggle_debug => {},
            .toggle_console => {},
            .combine_inventory_items => |comb| {
                const frame = display_bridge.get_frame();
                const p_name = if (comb.primary_index < frame.inventory_count)
                    frame.inventory[comb.primary_index].get_name()
                else
                    "item";
                const s_name = if (comb.secondary_index < frame.inventory_count)
                    frame.inventory[comb.secondary_index].get_name()
                else
                    "item";
                var buf: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "You can't combine {s} with {s}.", .{ p_name, s_name }) catch "Can't combine";
                window.set_cue_banner(msg, 90);
            },
            .use_inventory_on_actor => |act| {
                const frame = display_bridge.get_frame();
                if (act.item_index < frame.inventory_count and act.actor_index < frame.entity_count) {
                    const item_name = frame.inventory[act.item_index].get_name();
                    const actor_name = frame.entities[act.actor_index].get_name();
                    if (std.mem.eql(u8, item_name, "GreenDrink") and std.mem.eql(u8, actor_name, "Guybrush")) {
                        try set_state(&world, spit_ent, thick_rel);
                        window.set_cue_banner("\"Glug glug glug...\" Guybrush's spit is now thick and potent!", 120);
                    } else if (std.mem.eql(u8, item_name, "Horn")) {
                        try world.remember(organiser, distracted_rel, onlookers.to_int(), 100);
                        _ = try spatial.walk_to(organiser, offstage_wp);
                        _ = try spatial.walk_to(onlookers, offstage_wp);
                        window.set_cue_banner("HOOOOONK! Organiser: \"About time that damn ship came in!\" Crowd distracted!", 120);
                    } else {
                        var buf: [96]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "Using {s} on {s} has no effect.", .{ item_name, actor_name }) catch "No effect";
                        window.set_cue_banner(msg, 90);
                    }
                }
            },
            .use_inventory_on_hotspot => |hs_act| {
                const frame = display_bridge.get_frame();
                if (hs_act.item_index < frame.inventory_count and hs_act.hotspot_index < frame.hotspot_count) {
                    const item_name = frame.inventory[hs_act.item_index].get_name();
                    const hs_name = frame.hotspots[hs_act.hotspot_index].get_name();
                    if (std.mem.indexOf(u8, hs_name, "Flag") != null) {
                        const is_distracted = world.has_fact(organiser, distracted_rel, null);
                        if (is_distracted) {
                            try set_state(&world, flags, tampered_rel);
                            window.set_cue_banner("★ Flags secretly moved closer to the starting line! ★", 120);
                        } else {
                            window.set_cue_banner("Narrator: \"You better not, he's watching.\"", 90);
                        }
                    } else {
                        var buf: [96]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "Using {s} on {s} has no effect.", .{ item_name, hs_name }) catch "No effect";
                        window.set_cue_banner(msg, 90);
                    }
                }
            },
            else => {},
        }

        if (session.tick_due()) {
            _ = try session.advance();
        }

        session.render();
    }
}

test "P10-03: compile and verify Spitting Contest script AST and bytecode" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SPITTING_CONTEST_SCRIPT);
    defer compiled.deinit();

    // Verify entities and stage marks interned
    try testing.expect(world.lookup_entity("Guybrush") != null);
    try testing.expect(world.lookup_entity("Organiser") != null);
    try testing.expect(world.lookup_entity("Onlookers") != null);
    try testing.expect(world.lookup_entity("Flags") != null);
    try testing.expect(world.lookup_entity("Starting Line") != null);
    try testing.expect(world.lookup_entity("Looking Offstage") != null);

    // Verify waypoints registered in spatial graph
    try testing.expect(spatial.graph.waypoints.items.len >= 2);

    // Verify routines compiled
    try testing.expect(compiled.routine_entries.contains("EggingCrowd"));
    try testing.expect(compiled.routine_entries.contains("WindBlowing"));

    // Verify cue handlers compiled
    try testing.expect(compiled.cue_handler_entries.contains("Uses:Guybrush:Horn"));

    // Verify reactive rules loaded (including on_expire and falling edge)
    try testing.expect(compiled.reactive_rules.items.len >= 3);
}

test "P10-03: spitting contest puzzle systemic progression and resolution" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SPITTING_CONTEST_SCRIPT);
    defer compiled.deinit();
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);

    const thick_rel = world.lookup_relation("thick").?;
    const tampered_rel = world.lookup_relation("tampered").?;
    const blowing_rel = world.lookup_relation("blowing").?;
    const guybrush = world.lookup_entity("Guybrush").?;
    const flags = world.lookup_entity("Flags").?;

    // Nobody has spat yet.
    try testing.expectEqual(@as(?SpitResult, null), placement(&world));

    // 1. Initial attempt: Spit is not thick -> Dribble, 3rd place
    try testing.expectEqual(SpitResult.dribble_third, try spit(&world, &vm, &compiled));

    // 2. Drink green drink (the script's own handler) -> thick, flags untouched -> 3rd place
    _ = try vm.fire_cue(&compiled, "Uses", guybrush, world.lookup_entity("GreenDrink").?, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    try testing.expect(world.has_fact(world.lookup_entity("Spit").?, thick_rel, null));
    try testing.expectEqual(SpitResult.thick_flags_untouched_third, try spit(&world, &vm, &compiled));

    // 3. The script refuses tampering while the Organiser watches, and allows it once distracted
    _ = try vm.fire_cue(&compiled, "Uses", guybrush, flags, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    try testing.expect(!world.has_fact(flags, tampered_rel, null));

    const organiser = world.lookup_entity("Organiser").?;
    const distracted_rel = world.lookup_relation("Distracted").?;
    try world.remember(organiser, distracted_rel, world.lookup_entity("Onlookers").?.to_int(), 100);
    _ = try vm.fire_cue(&compiled, "Uses", guybrush, flags, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    try testing.expect(world.has_fact(flags, tampered_rel, null));
    try testing.expectEqual(SpitResult.thick_flags_moved_no_wind_second, try spit(&world, &vm, &compiled));

    // 4. Wind gust blows! -> Thick spit + moved flags + wind gust -> WINNER! 1st place!
    try set_state(&world, world.lookup_entity("Wind").?, blowing_rel);
    try testing.expectEqual(SpitResult.winner_first, try spit(&world, &vm, &compiled));

    // Exactly one placement is recorded at a time.
    var count: usize = 0;
    var it = world.query(guybrush, world.lookup_relation("Placed").?, null);
    while (it.next()) |_| count += 1;
    try testing.expectEqual(@as(usize, 1), count);
}

test "P10-03: headless execution of Spitting Contest scenario" {
    const testing = std.testing;
    try run_headless(testing.allocator, std.io.null_writer);
}
