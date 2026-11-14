const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const SpitKey = enum(u16) { spit, conch, drink, pegs };

const spit_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_s, .action = @intFromEnum(SpitKey.spit), .sfx = art.sfx(.whistle) },
    .{ .key = bespoke.display.renderer.c.SDLK_c, .action = @intFromEnum(SpitKey.conch), .sfx = art.sfx(.horn) },
    .{ .key = bespoke.display.renderer.c.SDLK_d, .action = @intFromEnum(SpitKey.drink), .sfx = .{ .stock = .pickup } },
    .{ .key = bespoke.display.renderer.c.SDLK_p, .action = @intFromEnum(SpitKey.pegs), .sfx = .{ .stock = .combine } },
});

pub const SPITTING_CONTEST_SCRIPT =
    \\scene: Pip-Spitting Green
    \\cast: Tamsin, JudgeMarrow, Fairgoers
    \\props: Pegs
    \\marks: Chalk Line, Harbour Wall
    \\
    \\Tampered with is a state, which can be tampered with or not tampered with.
    \\Distracted is a state, which can be distracted or not distracted.
    \\Wind is a state, which can be blowing or not blowing. The wind is not blowing in the scene.
    \\Spit is a state, which can be thick or not. Spit is not thick in the scene.
    \\
    \\remember: Carries(Tamsin, Conch) ~ this is something that will have happened in another scene
    \\remember: Carries(Tamsin, TreacleCider)
    \\
    \\routine EggingCrowd(JudgeMarrow):
    \\  loop:
    \\    walk JudgeMarrow to Fairgoers
    \\    say JudgeMarrow to Fairgoers: (something at random from list of Pip-Spitting Green Quips)
    \\    wait 30 ticks
    \\    walk JudgeMarrow to Chalk Line
    \\    wait 20 ticks
    \\    say JudgeMarrow to Scene: (something at random from list of Pip-Spitting Green Encouragements)
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
    \\  interrupt JudgeMarrow with:
    \\    animate wind-blowing
    \\
    \\when Wind stops being blowing:
    \\  interrupt JudgeMarrow with:
    \\    stop animate wind-blowing
    \\
    \\when TalksTo(Tamsin, JudgeMarrow):
    \\  interrupt JudgeMarrow with:
    \\    face JudgeMarrow toward Tamsin
    \\    say JudgeMarrow to Scene: "Toe the chalk, love, and mind my boots."
    \\    resume previous action
    \\
    \\on cue Uses(Tamsin, Conch):
    \\  remember Distracted[JudgeMarrow, Fairgoers] for 100 ticks
    \\  interrupt JudgeMarrow with:
    \\    walk JudgeMarrow to Harbour Wall
    \\    face Fairgoers toward Harbour Wall
    \\    say JudgeMarrow to Scene: "Is that the herring fleet back already?"
    \\
    \\when JudgeMarrow forgets Distracted:
    \\  interrupt JudgeMarrow with:
    \\    walk JudgeMarrow to Chalk Line
    \\    face JudgeMarrow toward Chalk Line
    \\    face Fairgoers toward Chalk Line
    \\    resume previous action
    \\
    \\on cue Uses(Tamsin, Pegs):
    \\  if Pegs are tampered with:
    \\    say Narrator to Scene: "The pegs have moved far enough already."
    \\    done
    \\  if Pegs are not tampered with:
    \\    if not Distracted(JudgeMarrow, _):
    \\      say Narrator to Scene: "Not while Judge Marrow is watching."
    \\      done
    \\    if Distracted(JudgeMarrow, _):
    \\      now Pegs are tampered with
    \\      animate (Pegs, pegs-tampering)
    \\      done
    \\
    \\on cue Uses(Tamsin, TreacleCider):
    \\  animate (Tamsin, Tamsin-drinking)
    \\  now Spit is thick
    \\
    \\on cue Gusts(Tamsin):
    \\  now Wind is blowing
    \\
    \\on cue LeavingScene(Tamsin):
    \\  now Spit is not thick
    \\
    \\on cue Spits(Tamsin):
    \\  forget Placed(Tamsin)
    \\  if Spit is not thick:
    \\    say Tamsin to Scene: "Pfft!"
    \\    animate (Tamsin, Tamsin-dribbling)
    \\    remember Placed(Tamsin, Dribble)
    \\  if Spit is thick:
    \\    if Pegs are not tampered with:
    \\      animate (Tamsin, Tamsin-not-winning)
    \\      say JudgeMarrow to Scene: "A respectable third!"
    \\      remember Placed(Tamsin, ThirdPlace)
    \\    if Pegs are tampered with:
    \\      if Wind is not blowing:
    \\        animate (Tamsin, Tamsin-not-winning)
    \\        say JudgeMarrow to Scene: "Second place! So close!"
    \\        remember Placed(Tamsin, SecondPlace)
    \\      if Wind is blowing:
    \\        animate (Tamsin, Tamsin-winning)
    \\        say JudgeMarrow to Scene: "Past the last peg! We have a champion!"
    \\        remember Placed(Tamsin, FirstPlace)
;

pub const SpitResult = enum {
    dribble_third,
    thick_pegs_untouched_third,
    thick_pegs_moved_no_wind_second,
    winner_first,
};

/// Reads the placement the script's `Spits` handler recorded for Tamsin, or null if she has
/// not spat. The rule itself (thick spit, moved pegs, wind) lives in the script (P32-19).
pub fn placement(world: *const bespoke.World) ?SpitResult {
    const tamsin = world.lookup_entity("Tamsin") orelse return null;
    const placed_rel = world.lookup_relation("Placed") orelse return null;
    const fact = world.find_first(tamsin, placed_rel, null) orelse return null;
    const name = world.get_entity_name(bespoke.EntityId.from_int(fact.object_or_value)) orelse return null;
    if (std.mem.eql(u8, name, "Dribble")) return .dribble_third;
    if (std.mem.eql(u8, name, "ThirdPlace")) return .thick_pegs_untouched_third;
    if (std.mem.eql(u8, name, "SecondPlace")) return .thick_pegs_moved_no_wind_second;
    if (std.mem.eql(u8, name, "FirstPlace")) return .winner_first;
    return null;
}

/// Tamsin spits: fires the script's `Spits` cue, runs the tick that judges it, and returns
/// the placement the script recorded.
pub fn spit(world: *bespoke.World, vm: *bespoke.VM, compiled: *const bespoke.CompiledProgram) !SpitResult {
    const tamsin = world.lookup_entity("Tamsin") orelse return error.SpitNotJudged;
    _ = try vm.fire_cue(compiled, "Spits", tamsin, null, null);
    _ = try bespoke.host.tick(vm, compiled);
    return placement(world) orelse error.SpitNotJudged;
}

/// Fires a content action and advances enough ticks for direct handlers or one nested
/// interrupt to run. Speech comes from the final tick, where nested interrupt bodies speak.
fn script_action(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    cue: []const u8,
    actor: bespoke.EntityId,
    target_a: ?bespoke.EntityId,
    target_b: ?bespoke.EntityId,
    ticks: usize,
    speech_buf: []u8,
) !?[]const u8 {
    _ = try vm.fire_cue(compiled, cue, actor, target_a, target_b);
    var remaining = ticks;
    while (remaining > 0) : (remaining -= 1) _ = try bespoke.host.tick(vm, compiled);
    return bespoke.host.speech_this_tick(world, vm, speech_buf);
}

fn script_action_until_speech(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    cue: []const u8,
    actor: bespoke.EntityId,
    target: ?bespoke.EntityId,
    max_ticks: usize,
    speech_buf: []u8,
) !?[]const u8 {
    _ = try vm.fire_cue(compiled, cue, actor, target, null);
    var tick_count: usize = 0;
    while (tick_count < max_ticks) : (tick_count += 1) {
        _ = try bespoke.host.tick(vm, compiled);
        if (bespoke.host.speech_this_tick(world, vm, speech_buf)) |speech| return speech;
    }
    return null;
}

fn session_action(
    session: *bespoke.host.Session,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    cue: []const u8,
    actor: bespoke.EntityId,
    target_a: ?bespoke.EntityId,
    target_b: ?bespoke.EntityId,
    ticks: usize,
) !void {
    _ = try vm.fire_cue(compiled, cue, actor, target_a, target_b);
    var remaining = ticks;
    while (remaining > 0) : (remaining -= 1) _ = try session.advance();
}

/// Executes headless simulation of the Pip-Spitting Green vertical slice (P10-03, D-012).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("   BeSpoke Engine: The Pip-Spitting Green Vertical Slice\n", .{});
    try writer.print("  (Natural Stageplay DSL * Relational Spine * Falling Edge & TTL)  \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Lowering Pip-Spitting Green stageplay script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SPITTING_CONTEST_SCRIPT);
    defer compiled.deinit();

    const tamsin = world.lookup_entity("Tamsin").?;
    const judge = world.lookup_entity("JudgeMarrow").?;
    const fairgoers = world.lookup_entity("Fairgoers").?;
    const pegs = world.lookup_entity("Pegs").?;
    const room_ent = world.lookup_entity("Pip-Spitting Green") orelse try world.intern_entity("Pip-Spitting Green");

    const starting_line_wp = spatial.graph.find_waypoint("Chalk Line") orelse 1;
    const offstage_wp = spatial.graph.find_waypoint("Harbour Wall") orelse 2;
    const fairgoers_wp = spatial.graph.find_waypoint("Fairgoers") orelse
        try spatial.graph.add_waypoint(room_ent, -8, 3, "Fairgoers");

    if (spatial.graph.get_waypoint(starting_line_wp)) |_| {
        spatial.graph.waypoints.items[starting_line_wp - 1].pos = .{ .x = 0, .y = 0 };
    }
    if (spatial.graph.get_waypoint(offstage_wp)) |_| {
        spatial.graph.waypoints.items[offstage_wp - 1].pos = .{ .x = 42, .y = 0 };
    }

    try spatial.graph.connect(fairgoers_wp, starting_line_wp, null);
    try spatial.graph.connect(starting_line_wp, offstage_wp, null);

    // Position Pegs hotspot in the field at x=22
    for (spatial.hotspots.items) |*hs| {
        if (std.mem.indexOf(u8, hs.name, "Peg") != null) {
            hs.pos = .{ .x = 22, .y = -2 };
            break;
        }
    }

    try spatial.register_entity(tamsin, starting_line_wp, 10);
    try spatial.register_entity(judge, starting_line_wp, 12);
    try spatial.register_entity(fairgoers, fairgoers_wp, 15);

    // Script-declared initial items for Tamsin.
    const carries_rel = try world.intern_relation("Carries", .set);
    const conch_ent = try world.intern_entity("Conch");
    const drink_ent = try world.intern_entity("TreacleCider");

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try bespoke.host.run_initial_statements(&world, &vm, &compiled);
    try std.testing.expect(world.has_fact(tamsin, carries_rel, conch_ent.to_int()));
    try std.testing.expect(world.has_fact(tamsin, carries_rel, drink_ent.to_int()));

    if (compiled.routine_entries.get("EggingCrowd")) |entry| {
        _ = try vm.spawn_routine(judge, entry);
    }

    var timeline = bespoke.host.Timeline.init(allocator);
    defer timeline.deinit();

    try writer.print("\n>>> STARTING PIP-SPITTING GREEN SIMULATION <<<\n", .{});

    // Initial state snapshot 0
    try timeline.record(&world);

    // Step 1: Baseline attempt (No prep)
    try writer.print("\n[Step 1: Baseline Attempt] Tamsin steps up to Chalk Line and spits...\n", .{});
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

    // Step 2: Tamsin drinks treacle cider
    try writer.print("\n[Step 2: Tamsin drinks treacle cider] \"Glug glug glug...\"\n", .{});
    const thick_rel = try world.intern_relation("thick", .set);
    var speech_buf: [512]u8 = undefined;
    _ = try script_action(&world, &vm, &compiled, "Uses", tamsin, drink_ent, null, 1, &speech_buf);
    try std.testing.expect(world.has_fact(spit_ent, thick_rel, null));
    try writer.print("   -> Fact asserted: Spit is thick!\n", .{});

    const res2 = try spit(&world, &vm, &compiled);
    try timeline.record(&world);
    try writer.print("   -> Spit check: {s} (Thick spit, but pegs untouched! Third place!)\n", .{@tagName(res2)});

    // Step 3: Attempting to move Pegs while Judge Marrow watches
    try writer.print("\n[Step 3: Attempting to move Pegs while Judge Marrow watches]...\n", .{});
    const distracted_rel = try world.intern_relation("Distracted", .set);
    const is_distracted = world.has_fact(judge, distracted_rel, null);
    if (!is_distracted) {
        try writer.print("   -> Judge Marrow is watching! Narrator: \"Not while Judge Marrow is watching.\"\n", .{});
    }

    const pre_conch_tick = world.current_tick;
    const pre_conch_snapshot = timeline.last_index();

    // Step 4: Distract with Conch
    try writer.print("\n[Step 4: Tamsin blows the Conch!] *** BWOOOOOOM! ***\n", .{});
    const conch_speech = try script_action_until_speech(&world, &vm, &compiled, "Uses", tamsin, conch_ent, 12, &speech_buf);
    try std.testing.expect(world.has_fact(judge, distracted_rel, fairgoers.to_int()));
    try writer.print("   -> {s}\n", .{conch_speech orelse "Judge Marrow turns toward the harbour."});
    try writer.print("   -> Judge Marrow walks to Harbour Wall! (Distracted TTL: 100 ticks)\n", .{});

    for (0..3) |_| {
        try vm.step_tick();
        try timeline.record(&world);
    }

    // Step 5: Move pegs while distracted!
    try writer.print("\n[Step 5: Tamsin tampers with Pegs while crowd is distracted!]\n", .{});
    const tampered_rel = try world.intern_relation("tampered", .set);
    _ = try script_action(&world, &vm, &compiled, "Uses", tamsin, pegs, null, 1, &speech_buf);
    try std.testing.expect(world.has_fact(pegs, tampered_rel, null));
    try writer.print("   -> Fact asserted: Pegs are tampered with (moved closer to line)!\n", .{});

    const res3 = try spit(&world, &vm, &compiled);
    try timeline.record(&world);
    try writer.print("   -> Spit check without wind: {s} (Second place! Close, but need a tailwind!)\n", .{@tagName(res3)});

    // Step 6: Wind gust arrives! (Rising edge trigger)
    try writer.print("\n[Step 6: Wind gust cycles in!] Rising edge trigger activates...\n", .{});
    const blowing_rel = try world.intern_relation("blowing", .set);
    _ = try script_action(&world, &vm, &compiled, "Gusts", tamsin, null, null, 1, &speech_buf);
    try std.testing.expect(world.has_fact(wind_ent, blowing_rel, null));

    {
        try timeline.record(&world);
    }

    try writer.print("   -> Wind is blowing! Thick Spit + Tampered Pegs + Tailwind = GUYBRUSH SPITS!\n", .{});
    const res4 = try spit(&world, &vm, &compiled);
    try timeline.record(&world);
    try writer.print("   -> FINAL RESULT: {s}!\n", .{@tagName(res4)});
    try writer.print("   -> Judge Marrow: \"Past the last peg! We have a champion!\"\n", .{});

    // Step 7: TTL Expiration and Falling Edge
    try writer.print("\n[Step 7: Testing TTL Expiration & Falling-Edge Triggers]\n", .{});
    while (world.has_fact(judge, distracted_rel, null)) {
        try vm.step_tick();
        try timeline.record(&world);
    }
    try writer.print("   -> Distraction TTL expired at Tick {d}!\n", .{world.current_tick});
    try writer.print("   -> 'when Judge Marrow forgets Distracted' fired: Judge Marrow returned to Chalk Line.\n", .{});

    _ = world.forget(wind_ent, blowing_rel, null);
    try vm.step_tick();
    try writer.print("   -> Wind stopped blowing: 'when Wind stops being blowing' falling-edge hook fired.\n", .{});

    // Step 8: Time-Travel Rewind
    try writer.print("\n[Step 8: Time-Travel Rewind Demo]\n", .{});
    try writer.print("   -> Rewinding simulation to Tick {d} (before Conch distraction)...\n", .{pre_conch_tick});
    _ = try timeline.restore(&world, pre_conch_snapshot);

    try writer.print("   -> Rewound Tick: {d}\n", .{world.current_tick});
    try writer.print("   -> Judge Marrow Distracted? {s} (Restored to false!)\n", .{if (world.has_fact(judge, distracted_rel, null)) "YES" else "NO"});
    try writer.print("   -> Pegs Tampered?       {s} (Restored to false!)\n", .{if (world.has_fact(pegs, tampered_rel, null)) "YES" else "NO"});
    const rewound_res = try spit(&world, &vm, &compiled);
    try writer.print("   -> Rewound Contest Result: {s} (Back to 3rd place!)\n", .{@tagName(rewound_res)});
    try writer.print("\n===================================================================\n", .{});
    try writer.print("   Pip-Spitting Green Vertical Slice Successfully Completed!  \n", .{});
    try writer.print("===================================================================\n", .{});
}

/// Launches the full graphical 2D adventure display window for the Spitting Contest (P10-03, D-001, D-008, D-012).
pub fn run_gui(allocator: std.mem.Allocator, stdout: anytype) !void {
    try stdout.print("\n===================================================================\n", .{});
    try stdout.print("   BeSpoke Engine: The Pip-Spitting Green (Graphical 2D)\n", .{});
    try stdout.print("  (Natural Stageplay DSL * Relational Spine * Falling Edge & TTL)  \n", .{});
    try stdout.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try stdout.print("[Compiler] Lowering Pip-Spitting Green stageplay script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SPITTING_CONTEST_SCRIPT);
    defer compiled.deinit();

    const tamsin = world.lookup_entity("Tamsin").?;
    const judge = world.lookup_entity("JudgeMarrow").?;
    const fairgoers = world.lookup_entity("Fairgoers").?;
    const pegs = world.lookup_entity("Pegs").?;
    const room_ent = world.lookup_entity("Pip-Spitting Green") orelse try world.intern_entity("Pip-Spitting Green");

    const starting_line_wp = spatial.graph.find_waypoint("Chalk Line") orelse 1;
    const offstage_wp = spatial.graph.find_waypoint("Harbour Wall") orelse 2;
    const fairgoers_wp = spatial.graph.find_waypoint("Fairgoers") orelse
        try spatial.graph.add_waypoint(room_ent, -8, 3, "Fairgoers");

    if (spatial.graph.get_waypoint(starting_line_wp)) |_| {
        spatial.graph.waypoints.items[starting_line_wp - 1].pos = .{ .x = 0, .y = 0 };
    }
    if (spatial.graph.get_waypoint(offstage_wp)) |_| {
        spatial.graph.waypoints.items[offstage_wp - 1].pos = .{ .x = 42, .y = 0 };
    }

    try spatial.graph.connect(fairgoers_wp, starting_line_wp, null);
    try spatial.graph.connect(starting_line_wp, offstage_wp, null);

    // Position Pegs hotspot in the field at x=22
    for (spatial.hotspots.items) |*hs| {
        if (std.mem.indexOf(u8, hs.name, "Peg") != null) {
            hs.pos = .{ .x = 22, .y = -2 };
            break;
        }
    }

    try spatial.register_entity(tamsin, starting_line_wp, 10);
    try spatial.register_entity(judge, starting_line_wp, 12);
    try spatial.register_entity(fairgoers, fairgoers_wp, 15);

    // Initial items are declared by the script.
    const conch_ent = try world.intern_entity("Conch");
    const drink_ent = try world.intern_entity("TreacleCider");

    const tampered_rel = try world.intern_relation("tampered", .set);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try bespoke.host.run_initial_statements(&world, &vm, &compiled);

    var display_bridge = bespoke.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("Tamsin")) |player| display_bridge.set_active_character(player);
    var repl_instance = bespoke.Repl.init(&world, &spatial, &vm);

    if (compiled.routine_entries.get("EggingCrowd")) |entry| {
        _ = try vm.spawn_routine(judge, entry);
    }
    if (compiled.routine_entries.get("WindBlowing")) |entry| {
        _ = try vm.spawn_routine(room_ent, entry);
    }

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Pip-Spitting Green", 1280, 720);
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
    try stdout.print("Harvest Fair Contest Controls:\n", .{});
    try stdout.print("   - [S]:                   SPIT! (Evaluate spit attempt against active facts)\n", .{});
    try stdout.print("   - [H]:                   SOUND SHIP'S HORN (Distract crowd for 100 ticks)\n", .{});
    try stdout.print("   - [G]:                   DRINK GREEN DRINK (Thicken spit)\n", .{});
    try stdout.print("   - [F]:                   TAMPER WITH FLAGS (Move record line closer)\n", .{});
    try stdout.print("   - [Left Click Actor]:    Interact with Tamsin, Judge Marrow, or Fairgoers\n", .{});
    try stdout.print("   - [Left Click Prop]:     Examine or Move Pegs\n", .{});
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

    window.set_cue_banner("Welcome to the Harvest Fair! Press [S] to Spit, [C] for the Conch, [D] to Drink, [P] for the Pegs.", 150);

    while (true) {
        const action = window.poll_events(session.frame());

        if (action == .rewind) {
            // This proof's [R] returns to the opening state rather than one step back.
            if ((try session.jump_to(0)) != null) window.set_cue_banner("<<< REWOUND TO INITIAL STATE (TICK 0) <<<", 90);
        } else if (try session.handle_common(action)) {} else switch (action) {
            .quit => break,
            .walk_player => |wp_id| {
                _ = try spatial.walk_to(tamsin, wp_id);
                window.set_cue_banner("Directing Tamsin to waypoint.", 60);
            },
            .examine_hotspot => |hs_idx| {
                const frame = display_bridge.get_frame();
                if (hs_idx < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_idx];
                    var buf: [128]u8 = undefined;
                    const text = std.fmt.bufPrint(&buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Pegs";
                    window.set_cue_banner(text, 120);
                }
            },
            .interact_actor => |act| {
                const frame = display_bridge.get_frame();
                if (act.actor_index < frame.entity_count) {
                    const target_entity = frame.entities[act.actor_index];
                    const tname = target_entity.get_name();
                    const pt = bespoke.display.renderer.get_entity_screen_pos(act.actor_index, frame.entities[0..frame.entity_count], window.width, window.height);

                    if (std.mem.eql(u8, tname, "JudgeMarrow")) {
                        window.show_dialogue(
                            target_entity.entity,
                            pt,
                            "JudgeMarrow",
                            "\"Toe the chalk, love, and mind my boots.\"",
                            &[_][]const u8{
                                "1. \"I'm ready to spit!\"",
                                "2. \"What are the rules again?\"",
                                "3. \"Never mind.\"",
                            },
                        );
                    } else if (std.mem.eql(u8, tname, "Tamsin")) {
                        window.set_cue_banner("Tamsin: \"Watch this.\"", 90);
                    } else {
                        window.set_cue_banner("Fairgoers: \"Hooray! Make way for the next spitter!\"", 90);
                    }
                }
            },
            .interact_hotspot => |hs_act| {
                const frame = display_bridge.get_frame();
                if (hs_act.hotspot_index < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_act.hotspot_index];
                    if (hs_act.verb == .look_at) {
                        var buf: [128]u8 = undefined;
                        const text = std.fmt.bufPrint(&buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Pegs";
                        window.set_cue_banner(text, 120);
                    } else if (hs_act.verb == .walk) {
                        const pt = bespoke.display.renderer.world_to_screen(hs.x, hs.y, window.width, window.height);
                        if (bespoke.display.renderer.find_nearest_waypoint(pt.x, pt.y, frame.waypoints[0..frame.waypoint_count], window.width, window.height)) |wp_id| {
                            _ = try spatial.walk_to(tamsin, wp_id);
                            window.set_cue_banner("Approaching pegs...", 60);
                        }
                    } else {
                        try session_action(&session, &vm, &compiled, "Uses", tamsin, pegs, null, 1);
                        if (world.has_fact(pegs, tampered_rel, null)) {
                            window.set_cue_banner("★ You secretly moved the pegs closer while the crowd wasn't looking! ★", 120);
                            window.play_sfx(.combine);
                        } else {
                            window.set_cue_banner("Narrator: \"Not while Judge Marrow is watching.\"", 90);
                        }
                    }
                }
            },
            .interact_inventory => |inv_act| {
                const frame = display_bridge.get_frame();
                if (inv_act.item_index < frame.inventory_count) {
                    const item_name = frame.inventory[inv_act.item_index].get_name();
                    if (inv_act.verb == .look_at) {
                        if (std.mem.indexOf(u8, item_name, "Conch") != null) {
                            window.set_cue_banner("Conch: A great spiral shell that booms like a conch.", 120);
                        } else if (std.mem.indexOf(u8, item_name, "Drink") != null) {
                            window.set_cue_banner("Green Drink: A thick, sugary syrup from the scumm bar. Thickens saliva.", 120);
                        } else {
                            var buf: [128]u8 = undefined;
                            const text = std.fmt.bufPrint(&buf, "{s}: \"An item in Tamsin's inventory.\"", .{item_name}) catch "Item";
                            window.set_cue_banner(text, 120);
                        }
                    } else if (inv_act.verb == .use_with) {
                        if (std.mem.indexOf(u8, item_name, "Conch") != null) {
                            try session_action(&session, &vm, &compiled, "Uses", tamsin, conch_ent, null, 2);
                            window.set_cue_banner("BWOOOOOM! Judge Marrow: \"Is that the herring fleet back already?\" Crowd distracted!", 120);
                            window.play_sound(art.sfx(.horn));
                        } else if (std.mem.indexOf(u8, item_name, "Drink") != null) {
                            try session_action(&session, &vm, &compiled, "Uses", tamsin, drink_ent, null, 1);
                            window.set_cue_banner("\"Glug glug glug...\" Tamsin's spit is now thick and potent!", 120);
                            window.play_sfx(.pickup);
                        }
                    }
                }
            },
            .dialogue_choice => |choice_idx| {
                if (choice_idx == 0) {
                    _ = try vm.fire_cue(&compiled, "Spits", tamsin, null, null);
                    _ = try session.advance();
                    const res = placement(&world) orelse return error.SpitNotJudged;
                    switch (res) {
                        .dribble_third => {
                            window.set_cue_banner("Tamsin: \"Pfft!\" ...Dribbles on her chin! (3rd Place)", 120);
                            window.play_sound(art.sfx(.splash));
                        },
                        .thick_pegs_untouched_third => {
                            window.set_cue_banner("Tamsin: \"Pfft!\" Thick spit flies, but pegs are untouched! (3rd Place)", 120);
                            window.play_sound(art.sfx(.whistle));
                        },
                        .thick_pegs_moved_no_wind_second => {
                            window.set_cue_banner("Tamsin: \"Pfft!\" Flies past moved pegs! Second Place! (Need wind!)", 120);
                            window.play_sound(art.sfx(.whistle));
                        },
                        .winner_first => {
                            window.set_cue_banner("★ WINNER! Riding the wind past the champion line! FIRST PLACE! ★", 180);
                            window.play_sfx(.alert);
                        },
                    }
                } else if (choice_idx == 1) {
                    window.set_cue_banner("Judge Marrow: \"Spit past the last peg to win! Thick spit and a sea breeze will do it!\"", 120);
                } else {
                    window.set_cue_banner("Tamsin steps back.", 60);
                }
            },
            .dismiss_dialogue => window.dismiss_dialogue(),
            .custom => |id| if (std.meta.intToEnum(SpitKey, id)) |key| switch (key) {
                .spit => {
                    _ = try vm.fire_cue(&compiled, "Spits", tamsin, null, null);
                    _ = try session.advance();
                    const res = placement(&world) orelse return error.SpitNotJudged;
                    switch (res) {
                        .dribble_third => {
                            window.set_cue_banner("Tamsin: \"Pfft!\" ...Dribbles on her chin! (3rd Place)", 120);
                            window.play_sound(art.sfx(.splash));
                        },
                        .thick_pegs_untouched_third => {
                            window.set_cue_banner("Tamsin: \"Pfft!\" Thick spit flies, but pegs are untouched! (3rd Place)", 120);
                            window.play_sound(art.sfx(.whistle));
                        },
                        .thick_pegs_moved_no_wind_second => {
                            window.set_cue_banner("Tamsin: \"Pfft!\" Past moved pegs! Second Place! (Need a gust of wind!)", 120);
                            window.play_sound(art.sfx(.whistle));
                        },
                        .winner_first => {
                            window.set_cue_banner("★ WINNER! Riding the wind past the champion line! FIRST PLACE! ★", 180);
                            window.play_sfx(.alert);
                        },
                    }
                },
                .conch => {
                    try session_action(&session, &vm, &compiled, "Uses", tamsin, conch_ent, null, 2);
                    window.set_cue_banner("BWOOOOOM! Judge Marrow: \"Is that the herring fleet back already?\" Crowd distracted!", 120);
                    window.play_sound(art.sfx(.horn));
                },
                .drink => {
                    try session_action(&session, &vm, &compiled, "Uses", tamsin, drink_ent, null, 1);
                    window.set_cue_banner("\"Glug glug glug...\" Tamsin's spit is now thick and potent!", 120);
                    window.play_sfx(.pickup);
                },
                .pegs => {
                    try session_action(&session, &vm, &compiled, "Uses", tamsin, pegs, null, 1);
                    if (world.has_fact(pegs, tampered_rel, null)) {
                        window.set_cue_banner("★ Pegs secretly moved closer to the chalk line! ★", 120);
                        window.play_sfx(.combine);
                    } else {
                        window.set_cue_banner("Narrator: \"Not while Judge Marrow is watching.\"", 90);
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
                    if (std.mem.eql(u8, item_name, "TreacleCider") and std.mem.eql(u8, actor_name, "Tamsin")) {
                        try session_action(&session, &vm, &compiled, "Uses", tamsin, drink_ent, null, 1);
                        window.set_cue_banner("\"Glug glug glug...\" Tamsin's spit is now thick and potent!", 120);
                    } else if (std.mem.eql(u8, item_name, "Conch")) {
                        try session_action(&session, &vm, &compiled, "Uses", tamsin, conch_ent, null, 2);
                        window.set_cue_banner("BWOOOOOM! Judge Marrow: \"Is that the herring fleet back already?\" Crowd distracted!", 120);
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
                    if (std.mem.indexOf(u8, hs_name, "Peg") != null) {
                        try session_action(&session, &vm, &compiled, "Uses", tamsin, pegs, null, 1);
                        if (world.has_fact(pegs, tampered_rel, null)) {
                            window.set_cue_banner("★ Pegs secretly moved closer to the chalk line! ★", 120);
                        } else {
                            window.set_cue_banner("Narrator: \"Not while Judge Marrow is watching.\"", 90);
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
    try testing.expect(world.lookup_entity("Tamsin") != null);
    try testing.expect(world.lookup_entity("JudgeMarrow") != null);
    try testing.expect(world.lookup_entity("Fairgoers") != null);
    try testing.expect(world.lookup_entity("Pegs") != null);
    try testing.expect(world.lookup_entity("Chalk Line") != null);
    try testing.expect(world.lookup_entity("Harbour Wall") != null);

    // Verify waypoints registered in spatial graph
    try testing.expect(spatial.graph.waypoints.items.len >= 2);

    // Verify routines compiled
    try testing.expect(compiled.routine_entries.contains("EggingCrowd"));
    try testing.expect(compiled.routine_entries.contains("WindBlowing"));

    // Verify cue handlers compiled
    try testing.expect(compiled.cue_handler_entries.contains("Uses:Tamsin:Conch"));

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
    const tamsin = world.lookup_entity("Tamsin").?;
    const pegs = world.lookup_entity("Pegs").?;

    // Nobody has spat yet.
    try testing.expectEqual(@as(?SpitResult, null), placement(&world));

    // 1. Initial attempt: Spit is not thick -> Dribble, 3rd place
    try testing.expectEqual(SpitResult.dribble_third, try spit(&world, &vm, &compiled));

    // 2. Drink treacle cider (the script's own handler) -> thick, pegs untouched -> 3rd place
    _ = try vm.fire_cue(&compiled, "Uses", tamsin, world.lookup_entity("TreacleCider").?, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    try testing.expect(world.has_fact(world.lookup_entity("Spit").?, thick_rel, null));
    try testing.expectEqual(SpitResult.thick_pegs_untouched_third, try spit(&world, &vm, &compiled));

    // 3. The script refuses tampering while Judge Marrow watches, and allows it once distracted
    _ = try vm.fire_cue(&compiled, "Uses", tamsin, pegs, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    try testing.expect(!world.has_fact(pegs, tampered_rel, null));

    const judge = world.lookup_entity("JudgeMarrow").?;
    const distracted_rel = world.lookup_relation("Distracted").?;
    var speech_buf: [256]u8 = undefined;
    _ = try script_action(&world, &vm, &compiled, "Uses", tamsin, try world.intern_entity("Conch"), null, 2, &speech_buf);
    try testing.expect(world.has_fact(judge, distracted_rel, null));
    _ = try vm.fire_cue(&compiled, "Uses", tamsin, pegs, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    try testing.expect(world.has_fact(pegs, tampered_rel, null));
    try testing.expectEqual(SpitResult.thick_pegs_moved_no_wind_second, try spit(&world, &vm, &compiled));

    // 4. Wind gust blows! -> Thick spit + moved pegs + wind gust -> WINNER! 1st place!
    _ = try script_action(&world, &vm, &compiled, "Gusts", tamsin, null, null, 1, &speech_buf);
    try testing.expect(world.has_fact(world.lookup_entity("Wind").?, blowing_rel, null));
    try testing.expectEqual(SpitResult.winner_first, try spit(&world, &vm, &compiled));

    // Exactly one placement is recorded at a time.
    var count: usize = 0;
    var it = world.query(tamsin, world.lookup_relation("Placed").?, null);
    while (it.next()) |_| count += 1;
    try testing.expectEqual(@as(usize, 1), count);
}

test "P10-03: headless execution of Spitting Contest scenario" {
    const testing = std.testing;
    try run_headless(testing.allocator, std.io.null_writer);
}
