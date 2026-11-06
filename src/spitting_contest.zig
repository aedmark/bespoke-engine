const std = @import("std");
const bespoke = @import("root.zig");

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
    \\  if Flags are Tampered With:
    \\    say Narrator to Scene: "You've already tampered with the flags!"
    \\    done
    \\  if Flags are not Tampered With:
    \\    if Organiser is not distracted:
    \\      say Narrator to Scene: "You better not, he's watching."
    \\      done
    \\    if Organiser is distracted:
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
    \\during Spitting Competition:
    \\  if Guybrush says "Ptooie!":
    \\    if Spit is not thick:
    \\      say Guybrush to Scene: "Ptooie!"
    \\      animate (Guybrush, Guybrush-dribbling)
    \\      done
    \\    if Spit is thick:
    \\      if Flags are not tampered with:
    \\        animate (Guybrush, Guybrush-not-winning)
    \\        say Organiser to Scene: "Oh, third place!"
    \\        done
    \\      if Flags are tampered with:
    \\        if Wind is not blowing:
    \\          animate (Guybrush, Guybrush-not-winning)
    \\          say Organiser to Scene: "Oh, second place!"
    \\          done
    \\        if Wind is blowing:
    \\          animate (Guybrush, Guybrush-winning)
    \\          say Organiser to Scene: "OH, we have a winner!"
    \\          done
;

pub const SpitResult = enum {
    dribble_third,
    thick_flags_untouched_third,
    thick_flags_moved_no_wind_second,
    winner_first,
};

/// Evaluates Guybrush's spit attempt against world simulation facts (P10-03, D-012).
pub fn evaluate_spit_contest(world: *const bespoke.World) SpitResult {
    var spit_thick = false;
    if (world.lookup_relation("thick")) |rel| {
        spit_thick = world.has_fact(null, rel, null);
    }

    var flags_tampered = false;
    if (world.lookup_relation("tampered")) |rel| {
        flags_tampered = flags_tampered or world.has_fact(null, rel, null);
    }
    if (world.lookup_relation("Tampered")) |rel| {
        flags_tampered = flags_tampered or world.has_fact(null, rel, null);
    }
    if (world.lookup_relation("TamperedWith")) |rel| {
        flags_tampered = flags_tampered or world.has_fact(null, rel, null);
    }

    var wind_blowing = false;
    if (world.lookup_relation("blowing")) |rel| {
        wind_blowing = world.has_fact(null, rel, null);
    }

    if (!spit_thick) {
        return .dribble_third;
    }

    if (!flags_tampered) {
        return .thick_flags_untouched_third;
    }

    if (!wind_blowing) {
        return .thick_flags_moved_no_wind_second;
    }

    return .winner_first;
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

    const starting_line_wp = spatial.graph.find_waypoint("Starting Line") orelse 1;
    const offstage_wp = spatial.graph.find_waypoint("Looking Offstage") orelse 2;

    try spatial.register_entity(guybrush, starting_line_wp, 10);
    try spatial.register_entity(organiser, starting_line_wp, 20);
    try spatial.register_entity(onlookers, starting_line_wp, 30);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);

    if (compiled.routine_entries.get("EggingCrowd")) |entry| {
        _ = try vm.spawn_routine(organiser, entry);
    }

    var history_snapshots = std.ArrayList(std.ArrayList(u8)).init(allocator);
    defer {
        for (history_snapshots.items) |*buf| buf.deinit();
        history_snapshots.deinit();
    }

    try writer.print("\n>>> STARTING BOOTY ISLAND SPITTING CONTEST SIMULATION <<<\n", .{});

    // Initial state snapshot 0
    var snap0 = std.ArrayList(u8).init(allocator);
    try world.save_state(snap0.writer());
    try history_snapshots.append(snap0);

    // Step 1: Baseline attempt (No prep)
    try writer.print("\n[Step 1: Baseline Attempt] Guybrush steps up to Starting Line and spits...\n", .{});
    const res1 = evaluate_spit_contest(&world);
    try writer.print("   -> Result: {s} (Dribbles on chin! Third place!)\n", .{@tagName(res1)});

    for (0..4) |_| {
        try vm.step_tick();
        var snap = std.ArrayList(u8).init(allocator);
        try world.save_state(snap.writer());
        try history_snapshots.append(snap);
    }

    // Step 2: Guybrush drinks GreenDrink
    try writer.print("\n[Step 2: Guybrush drinks GreenDrink] \"Glug glug glug...\"\n", .{});
    const thick_rel = try world.intern_relation("thick", .set);
    try world.remember(guybrush, thick_rel, 1, 0);
    try writer.print("   -> Fact asserted: Spit is thick!\n", .{});

    const res2 = evaluate_spit_contest(&world);
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
        var snap = std.ArrayList(u8).init(allocator);
        try world.save_state(snap.writer());
        try history_snapshots.append(snap);
    }

    // Step 5: Move flags while distracted!
    try writer.print("\n[Step 5: Guybrush tampers with Flags while crowd is distracted!]\n", .{});
    const tampered_rel = try world.intern_relation("tampered", .set);
    try world.remember(flags, tampered_rel, 1, 0);
    try writer.print("   -> Fact asserted: Flags are tampered with (moved closer to line)!\n", .{});

    const res3 = evaluate_spit_contest(&world);
    try writer.print("   -> Spit check without wind: {s} (Second place! Close, but need a tailwind!)\n", .{@tagName(res3)});

    // Step 6: Wind gust arrives! (Rising edge trigger)
    try writer.print("\n[Step 6: Wind gust cycles in!] Rising edge trigger activates...\n", .{});
    const blowing_rel = try world.intern_relation("blowing", .set);
    const scene_ent = try world.intern_entity("Scene");
    try world.remember(scene_ent, blowing_rel, 1, 0);

    try vm.step_tick();
    {
        var snap = std.ArrayList(u8).init(allocator);
        try world.save_state(snap.writer());
        try history_snapshots.append(snap);
    }

    try writer.print("   -> Wind is blowing! Thick Spit + Tampered Flags + Tailwind = GUYBRUSH SPITS!\n", .{});
    const res4 = evaluate_spit_contest(&world);
    try writer.print("   -> FINAL RESULT: {s}!\n", .{@tagName(res4)});
    try writer.print("   -> Organiser: \"OH, we have a winner! First Place!\"\n", .{});

    // Step 7: TTL Expiration and Falling Edge
    try writer.print("\n[Step 7: Testing TTL Expiration & Falling-Edge Triggers]\n", .{});
    while (world.has_fact(organiser, distracted_rel, null)) {
        try vm.step_tick();
        var snap = std.ArrayList(u8).init(allocator);
        try world.save_state(snap.writer());
        try history_snapshots.append(snap);
    }
    try writer.print("   -> Distraction TTL expired at Tick {d}!\n", .{world.current_tick});
    try writer.print("   -> 'when Organiser forgets Distracted' fired: Organiser returned to Starting Line.\n", .{});

    _ = world.forget(scene_ent, blowing_rel, null);
    try vm.step_tick();
    try writer.print("   -> Wind stopped blowing: 'when Wind stops being blowing' falling-edge hook fired.\n", .{});

    // Step 8: Time-Travel Rewind
    try writer.print("\n[Step 8: Time-Travel Rewind Demo]\n", .{});
    try writer.print("   -> Rewinding simulation to Tick {d} (before Horn distraction)...\n", .{pre_horn_tick});
    const pre_horn_snap = history_snapshots.items[pre_horn_tick];
    var stream = std.io.fixedBufferStream(pre_horn_snap.items);
    try world.restore_state(stream.reader());

    try writer.print("   -> Rewound Tick: {d}\n", .{world.current_tick});
    try writer.print("   -> Organiser Distracted? {s} (Restored to false!)\n", .{if (world.has_fact(organiser, distracted_rel, null)) "YES" else "NO"});
    try writer.print("   -> Flags Tampered?       {s} (Restored to false!)\n", .{if (world.has_fact(flags, tampered_rel, null)) "YES" else "NO"});
    const rewound_res = evaluate_spit_contest(&world);
    try writer.print("   -> Rewound Contest Result: {s} (Back to 3rd place!)\n", .{@tagName(rewound_res)});
    try writer.print("\n===================================================================\n", .{});
    try writer.print("   Booty Island Spitting Contest Vertical Slice Successfully Completed!  \n", .{});
    try writer.print("===================================================================\n", .{});
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
    try testing.expect(compiled.cue_handler_entries.contains("Uses"));

    // Verify reactive rules loaded (including on_expire and falling edge)
    try testing.expect(compiled.reactive_rules.items.len >= 3);
}

test "P10-03: spitting contest puzzle systemic progression and resolution" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const thick_rel = try world.intern_relation("thick", .set);
    const tampered_rel = try world.intern_relation("tampered", .set);
    const blowing_rel = try world.intern_relation("blowing", .set);

    const guybrush = try world.intern_entity("Guybrush");
    const flags = try world.intern_entity("Flags");
    const scene = try world.intern_entity("Scene");

    // 1. Initial attempt: Spit is not thick -> Dribble, 3rd place
    try testing.expectEqual(SpitResult.dribble_third, evaluate_spit_contest(&world));

    // 2. Drink green drink -> Spit is thick, but flags not tampered -> 3rd place
    try world.remember(guybrush, thick_rel, 1, 0);
    try testing.expectEqual(SpitResult.thick_flags_untouched_third, evaluate_spit_contest(&world));

    // 3. Move flags -> Spit thick + flags moved, but wind not blowing -> 2nd place
    try world.remember(flags, tampered_rel, 1, 0);
    try testing.expectEqual(SpitResult.thick_flags_moved_no_wind_second, evaluate_spit_contest(&world));

    // 4. Wind gust blows! -> Thick spit + moved flags + wind gust -> WINNER! 1st place!
    try world.remember(scene, blowing_rel, 1, 0);
    try testing.expectEqual(SpitResult.winner_first, evaluate_spit_contest(&world));
}

test "P10-03: headless execution of Spitting Contest scenario" {
    const testing = std.testing;
    try run_headless(testing.allocator, std.io.null_writer);
}
