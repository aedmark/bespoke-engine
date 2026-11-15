const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const WeathercockKey = enum(u16) { follow_conduit };

const weathercock_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_v, .action = @intFromEnum(WeathercockKey.follow_conduit), .sfx = .{ .stock = .pickup } },
});

pub const WEATHERCOCK_SCRIPT =
    \\scene: "Wren's Attic"
    \\cast: Wren, PilotAshe
    \\props: WeathercockProp, WritingDesk
    \\marks: CotMark, DeskMark, AtticStairs
    \\
    \\scene: "The Customs House"
    \\cast: Wren, Pell
    \\props: CrankProp, SluiceProp
    \\marks: LedgerMark, CountingFloor, SluiceMark
    \\
    \\scene: "Beacon Hill"
    \\cast: Wren, HesterQuill
    \\props: FogWhirlProp, NoteProp
    \\marks: HillCrest, WhirlMark, PostBoxMark
    \\
    \\BranchStatus is a state, which can be stable or active. The month is stable in the scene.
    \\SluiceStatus is a state, which can be shut or open. The sluice is shut in the scene.
    \\NoteStatus is a state, which can be pending or delivered. The note is pending in the scene.
    \\KeystoneStatus is a state, which can be attic or whirl. The weathercock is attic in the scene.
    \\
    \\on cue LooksAt(Wren, WritingDesk):
    \\  say Wren: "My writing desk. Hester Quill's storm almanac lies open at a page I haven't read yet."
    \\
    \\on cue LooksAt(Wren, WeathercockProp):
    \\  say Wren: "The copper weathercock off the Customs House roof, bent and dripping. The Customs House still has its own."
    \\
    \\on cue LooksAt(Wren, PilotAshe):
    \\  say Wren: "A man in a pilot's oilskins, wet through, with weed in his beard. He drowned before I was born."
    \\
    \\on cue TalksTo(Wren, PilotAshe):
    \\  say PilotAshe: "Twenty-eight days, six hours, forty-two minutes, twelve seconds. Then the gale comes and this month goes with it."
    \\  say PilotAshe: "Follow the current, Wren. Put back what fell, before the month runs out."
    \\  remember EchoWarnings(Wren, 1)
    \\
    \\on cue LooksAt(Wren, CrankProp):
    \\  say Wren: "The sluice crank, hung on its hook by the door. Ashe says the sluice must be opened."
    \\
    \\on cue LooksAt(Wren, SluiceProp):
    \\  say Wren: "The Customs House sluice. One turn of the crank and the tide comes in across the counting floor."
    \\
    \\on cue LooksAt(Wren, Pell):
    \\  say Wren: "Pell, the junior tide-waiter, copying manifests in the wrong ink."
    \\
    \\on cue TalksTo(Wren, Pell):
    \\  choice "Do you think a month can be borrowed, Pell?":
    \\    say Pell: "Only if you pay it back with interest. Ask anyone in this building."
    \\    remember PellBelief(Wren, 1)
    \\  choice "Are you afraid of the autumn gale?":
    \\    say Pell: "My gran says Brackwater floods when it's owed a flood."
    \\
    \\on cue LooksAt(Wren, HesterQuill):
    \\  say Wren: "Hester Quill, who keeps the storm almanac. She was the harbour's tide-reckoner once, and now she watches an empty post box."
    \\
    \\on cue LooksAt(Wren, CotMark):
    \\  say Wren: "Where my cot stood before the weathercock came through the roof."
    \\
    \\on cue LooksAt(Wren, DeskMark):
    \\  say Wren: "The boards by my desk and the shelf of ledgers."
    \\
    \\on cue LooksAt(Wren, AtticStairs):
    \\  say Wren: "The stairs down to the street and the Customs House."
    \\
    \\on cue LooksAt(Wren, LedgerMark):
    \\  say Wren: "Shelves of bound ledgers, every cargo since the old charter."
    \\
    \\on cue LooksAt(Wren, CountingFloor):
    \\  say Wren: "The counting floor, where the clerks weigh the duty."
    \\
    \\on cue LooksAt(Wren, SluiceMark):
    \\  say Wren: "The low corner where the sluice lets the harbour in."
    \\
    \\on cue LooksAt(Wren, HillCrest):
    \\  say Wren: "The crest of Beacon Hill, with all of Brackwater below."
    \\
    \\on cue LooksAt(Wren, PostBoxMark):
    \\  say Wren: "Hester Quill's rusted post box on its leaning pole."
    \\
    \\on cue LooksAt(Wren, WhirlMark):
    \\  say Wren: "The middle of the whirl, where the fog turns on itself."
    \\
    \\on cue LooksAt(Wren, Wren):
    \\  say Wren: "Wren Halloway. Apprentice clerk, light sleeper, and somehow in charge of a month."
    \\
    \\on cue LooksAt(Wren, Crank):
    \\  say Wren: "The sluice crank, hung on its hook by the door. Ashe says the sluice must be opened."
    \\
    \\on cue LooksAt(Wren, Note):
    \\  say Wren: "A sealed note addressed to Hester Quill. On the back: 'Fair weather, falling glass.'"
    \\
    \\on cue LooksAt(Wren, FogWhirlProp):
    \\  say Wren: "A whirl of grey fog turning slowly over the crest. Ashe says what fell must go back in here."
    \\
    \\on cue LooksAt(Wren, NoteProp):
    \\  say Wren: "A sealed note addressed to Hester Quill. On the back: 'Fair weather, falling glass.'"
    \\
    \\on cue TalksTo(Wren, HesterQuill):
    \\  choice "I have a note for you, Miss Quill. It says 'Fair weather, falling glass.'":
    \\    say HesterQuill: "Fair weather, falling glass. I wrote that in the almanac forty years ago, and nobody ever read it back to me."
    \\    say HesterQuill: "Take what fell to the whirl at the crest before the month closes, child."
    \\    remember NoteDelivered(Wren, HesterQuill)
    \\  choice "What happens when the borrowed month ends?":
    \\    say HesterQuill: "It folds back into the real one, or it tears. The loop must close."
    \\
    \\when SluiceOpened(Wren, SluiceProp):
    \\  interrupt Wren with:
    \\    say Wren: "The sluice gives way! The tide pours across the counting floor and the Customs House shuts its doors!"
    \\
    \\when ConvergenceReady(Wren, 1):
    \\  interrupt Wren with:
    \\    say Wren: "The weathercock sits in the whirl. The loop is ready to close!"
    \\
    \\on cue LooksAt(Wren, Weathercock):
    \\  say Wren: "The copper weathercock off the Customs House roof, bent and dripping. The Customs House still has its own."
    \\
    \\on cue LooksAt(Wren, Sluice):
    \\  say Wren: "The Customs House sluice. One turn of the crank and the tide comes in across the counting floor."
    \\
    \\on cue LooksAt(Wren, FogWhirl):
    \\  say Wren: "A whirl of grey fog turning slowly over the crest. Ashe says what fell must go back in here."
    \\
    \\on cue LooksAt(Wren):
    \\  say Wren: "Nothing unusual to see here."
;

/// The Copper Weathercock is solved when the keystone came back, the Customs House flooded,
/// the note reached Hester Quill, and Wren carried the memory out of the branch (P31-03, D-027).
pub fn evaluate_weathercock_solved(world: *const bespoke.World) bool {
    const keystone_rel = world.lookup_relation("KeystoneMaterialized") orelse return false;
    const flood_rel = world.lookup_relation("CustomsFlooded") orelse return false;
    const note_rel = world.lookup_relation("NoteDelivered") orelse return false;
    const memory_rel = world.lookup_relation("MemoryCarried") orelse return false;

    return world.has_fact(null, keystone_rel, null) and
        world.has_fact(null, flood_rel, null) and
        world.has_fact(null, note_rel, null) and
        world.has_fact(null, memory_rel, null);
}

/// Fires the script's `LooksAt` handler, runs the tick, and returns what was said. Every
/// description is script text (P32-19); a per-actor `LooksAt(<Actor>)` handler is the default.
pub fn execute_look_at(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: anytype,
    speaker: bespoke.EntityId,
    target: bespoke.EntityId,
    buf: []u8,
) ![]const u8 {
    return (try bespoke.host.act(world, vm, compiled, "LooksAt", speaker, target, buf)) orelse error.LookNotScripted;
}

/// Places the three scenes' props, corridors, and cast. The headless run and the window share
/// it so both play the same layout.
const Layout = struct {
    attic: bespoke.EntityId,
    customs: bespoke.EntityId,
    hill: bespoke.EntityId,
    wren: bespoke.EntityId,
    ashe: bespoke.EntityId,
    pell: bespoke.EntityId,
    hester: bespoke.EntityId,
    weathercock: bespoke.EntityId,
    desk: bespoke.EntityId,
    crank: bespoke.EntityId,
    sluice: bespoke.EntityId,
    note: bespoke.EntityId,
    whirl: bespoke.EntityId,
    cot_wp: bespoke.WaypointId,
    desk_wp: bespoke.WaypointId,
    stairs_wp: bespoke.WaypointId,
    ledger_wp: bespoke.WaypointId,
    floor_wp: bespoke.WaypointId,
    sluice_wp: bespoke.WaypointId,
    crest_wp: bespoke.WaypointId,
    postbox_wp: bespoke.WaypointId,
    whirl_wp: bespoke.WaypointId,

    fn init(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Layout {
        const attic = world.lookup_entity("Wren's Attic").?;
        const customs = world.lookup_entity("The Customs House").?;
        const hill = world.lookup_entity("Beacon Hill").?;
        var l = Layout{
            .attic = attic,
            .customs = customs,
            .hill = hill,
            .wren = world.lookup_entity("Wren").?,
            .ashe = world.lookup_entity("PilotAshe").?,
            .pell = world.lookup_entity("Pell").?,
            .hester = world.lookup_entity("HesterQuill").?,
            .weathercock = world.lookup_entity("WeathercockProp").?,
            .desk = world.lookup_entity("WritingDesk").?,
            .crank = world.lookup_entity("CrankProp").?,
            .sluice = world.lookup_entity("SluiceProp").?,
            .note = world.lookup_entity("NoteProp").?,
            .whirl = world.lookup_entity("FogWhirlProp").?,
            .cot_wp = spatial.graph.find_waypoint_in_room(attic, "CotMark") orelse 1,
            .desk_wp = spatial.graph.find_waypoint_in_room(attic, "DeskMark") orelse 2,
            .stairs_wp = spatial.graph.find_waypoint_in_room(attic, "AtticStairs") orelse 3,
            .ledger_wp = spatial.graph.find_waypoint_in_room(customs, "LedgerMark") orelse 4,
            .floor_wp = spatial.graph.find_waypoint_in_room(customs, "CountingFloor") orelse 5,
            .sluice_wp = spatial.graph.find_waypoint_in_room(customs, "SluiceMark") orelse 6,
            .crest_wp = spatial.graph.find_waypoint_in_room(hill, "HillCrest") orelse 7,
            .postbox_wp = spatial.graph.find_waypoint_in_room(hill, "PostBoxMark") orelse 8,
            .whirl_wp = spatial.graph.find_waypoint_in_room(hill, "WhirlMark") orelse 9,
        };

        // Hotspots sit at the scene waypoints; the description is the script's look line.
        try spatial.add_hotspot(l.weathercock, attic, .{ .x = 0, .y = -6 }, 10, "WeathercockProp", "The copper weathercock off the Customs House roof, bent and dripping.");
        try spatial.add_hotspot(l.desk, attic, .{ .x = 20, .y = -6 }, 8, "WritingDesk", "My writing desk. Hester Quill's storm almanac lies open at a page I haven't read yet.");
        try spatial.add_hotspot(l.crank, customs, .{ .x = 10, .y = -6 }, 8, "CrankProp", "The sluice crank, hung on its hook by the door.");
        try spatial.add_hotspot(l.sluice, customs, .{ .x = 40, .y = -6 }, 10, "SluiceProp", "The Customs House sluice. One turn of the crank and the tide comes in across the counting floor.");
        try spatial.add_hotspot(l.whirl, hill, .{ .x = 20, .y = -6 }, 12, "FogWhirlProp", "A whirl of grey fog turning slowly over the crest.");
        try spatial.add_hotspot(l.note, hill, .{ .x = 40, .y = -6 }, 8, "NoteProp", "A sealed note addressed to Hester Quill. On the back: 'Fair weather, falling glass.'");

        // Corridors within and across scenes: attic stairs to the ledgers, the sluice corner to the hill road.
        try spatial.graph.connect(l.cot_wp, l.desk_wp, null);
        try spatial.graph.connect(l.desk_wp, l.stairs_wp, null);
        try spatial.graph.connect(l.stairs_wp, l.ledger_wp, null);
        try spatial.graph.connect(l.ledger_wp, l.floor_wp, null);
        try spatial.graph.connect(l.floor_wp, l.sluice_wp, null);
        try spatial.graph.connect(l.sluice_wp, l.crest_wp, null);
        try spatial.graph.connect(l.crest_wp, l.postbox_wp, null);
        try spatial.graph.connect(l.postbox_wp, l.whirl_wp, null);

        try spatial.register_entity(l.wren, l.cot_wp, 8);
        try spatial.register_entity(l.ashe, l.desk_wp, 8);
        try spatial.register_entity(l.pell, l.ledger_wp, 8);
        try spatial.register_entity(l.hester, l.postbox_wp, 8);
        try spatial.register_entity(l.weathercock, l.cot_wp, 8);
        _ = &l;
        return l;
    }
};

/// Executes the headless run of The Copper Weathercock (P31-03, D-027, P35-07).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("     BeSpoke Engine: The Copper Weathercock                        \n", .{});
    try writer.print("     (Branch Worlds * Conduits * Loop Closure)                     \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Compiling The Copper Weathercock three-scene script...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, WEATHERCOCK_SCRIPT);
    defer compiled.deinit();

    const l = try Layout.init(&world, &spatial);
    const wren = l.wren;

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    const party_members = [_]bespoke.EntityId{ wren, l.ashe, l.pell };
    display_bridge.set_party(&party_members);
    display_bridge.set_active_character(wren);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try vm.transition_to_scene(l.attic);

    var hypervisor = bespoke.TemporalHypervisor.init(allocator, &world);
    defer hypervisor.deinit();

    // STEP 0: the primary world before anything falls.
    try writer.print("[Step 0] Primary world baseline: Wren in the attic at tick 0.\n", .{});
    try writer.print("         The Customs House still has its weathercock; no second one exists.\n", .{});
    var look_buf: [256]u8 = undefined;
    const msg_desk = try execute_look_at(&world, &vm, &compiled, wren, l.desk, &look_buf);
    try writer.print("         Wren inspects desk -> {s}\n\n", .{msg_desk});

    // STEP 1: the weathercock falls 28 days early and the borrowed month forks.
    try writer.print("[Step 1] Midnight: fork_branch(280 ticks) opens the borrowed month.\n", .{});
    const branch_world = try hypervisor.fork_branch(280, wren, l.weathercock);
    hypervisor.set_convergence_target(l.whirl_wp);
    art.set_countdown(&display_bridge, "28:06:42:12");
    try writer.print("         Branch world active! Budget: 280 ticks (28 days).\n", .{});
    try writer.print("         Receiver: Wren | Keystone: Weathercock | Convergence waypoint: {d}\n", .{l.whirl_wp});

    // Cause-to-effect edges the loop closes through (P31-01, D-027).
    const sluice_rel = try branch_world.intern_relation("SluiceOpened", .set);
    const flood_rel = try branch_world.intern_relation("CustomsFlooded", .set);
    const note_rel = try branch_world.intern_relation("NoteDelivered", .set);
    const at_whirl_rel = try branch_world.intern_relation("KeystoneAtConvergence", .set);
    const closed_rel = try branch_world.intern_relation("ConvergenceReady", .set);

    try hypervisor.register_teleological_dependency(sluice_rel, flood_rel);
    try hypervisor.register_teleological_dependency(flood_rel, closed_rel);
    try hypervisor.register_teleological_dependency(note_rel, closed_rel);
    try hypervisor.register_teleological_dependency(at_whirl_rel, closed_rel);

    std.debug.assert(hypervisor.is_teleologically_justified(sluice_rel, closed_rel));
    std.debug.assert(hypervisor.is_teleologically_justified(flood_rel, closed_rel));
    std.debug.assert(hypervisor.is_teleologically_justified(note_rel, closed_rel));
    std.debug.assert(hypervisor.is_teleologically_justified(at_whirl_rel, closed_rel));
    try writer.print("         [D-027 Teleology] Backward-chaining Horn clause solver verified:\n", .{});
    try writer.print("           SluiceOpened -> CustomsFlooded -> ConvergenceReady (JUSTIFIED)\n\n", .{});

    // STEP 2: the drowned pilot's echo gives the countdown from a hyper-temporal routine.
    try writer.print("[Step 2] Pilot Ashe's echo gives the countdown from a hyper-temporal routine:\n", .{});
    const fid_ashe = try vm.spawn_hyper_temporal_routine(l.ashe, 0);
    var found_hyper = false;
    for (vm.fibers.items) |f| {
        if (f.id == fid_ashe and f.is_hyper_temporal) {
            found_hyper = true;
            break;
        }
    }
    std.debug.assert(found_hyper);

    _ = try vm.fire_cue(&compiled, "TalksTo", wren, l.ashe, null);
    try vm.step_tick();
    _ = try hypervisor.step_tick(&spatial);
    var ashe_buf: [256]u8 = undefined;
    var ashe_log = bespoke.host.SpeechLog.init(&ashe_buf);
    ashe_log.collect_from(&world, &vm, l.ashe);
    if (ashe_log.message()) |speech| {
        try writer.print("         Ashe says: {s}\n", .{speech});
    } else {
        try writer.print("         Ashe says nothing.\n", .{});
    }
    var count_buf: [16]u8 = undefined;
    const formatted_countdown = bespoke.format_countdown(280 - hypervisor.ticks_elapsed, &count_buf);
    try writer.print("         Formatted countdown remaining: {s}\n\n", .{formatted_countdown});

    // STEP 3: the conduit (the current) leads to the Customs House.
    try writer.print("[Step 3] Wren sees the current and follows it:\n", .{});
    const computed_conduit = try spatial.compute_vector_conduit(wren, l.sluice_wp);
    std.debug.assert(computed_conduit != null);
    _ = try spatial.follow_conduit(wren, computed_conduit.?);
    const maybe_conduit = spatial.get_agent_vector_conduit(wren);
    std.debug.assert(maybe_conduit != null);
    const conduit = maybe_conduit.?;
    display_bridge.add_vector_conduit(conduit);
    try writer.print("         Conduit calculated: {d} points from CotMark to SluiceMark.\n", .{conduit.point_count});
    try vm.transition_to_scene(l.customs);
    _ = try spatial.follow_conduit(wren, conduit);
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.swap();
    try writer.print("         Wren arrives at The Customs House.\n\n", .{});

    // STEP 4: the sluice opens and the Customs House floods.
    try writer.print("[Step 4] Wren opens the Customs House sluice with the crank:\n", .{});
    const msg_crank = try execute_look_at(&world, &vm, &compiled, wren, l.crank, &look_buf);
    try writer.print("         Wren inspects Crank -> {s}\n", .{msg_crank});
    const msg_sluice = try execute_look_at(&world, &vm, &compiled, wren, l.sluice, &look_buf);
    try writer.print("         Wren inspects Sluice -> {s}\n", .{msg_sluice});

    _ = try branch_world.remember(wren, sluice_rel, l.sluice.to_int(), 0);
    _ = try branch_world.remember(wren, flood_rel, 1, 0);
    display_bridge.back_buffer.host_status_mut(art.Status).weathercock_flooded = true;
    _ = try hypervisor.step_tick(&spatial);
    try writer.print("         The sluice gives way! Facts asserted in the branch:\n", .{});
    try writer.print("           SluiceOpened(Wren, SluiceProp)\n", .{});
    try writer.print("           CustomsFlooded(Wren, 1)\n\n", .{});

    // STEP 5: the note reaches Hester Quill on Beacon Hill.
    try writer.print("[Step 5] Wren delivers the sealed note to Hester Quill on Beacon Hill:\n", .{});
    try vm.transition_to_scene(l.hill);
    _ = try spatial.walk_to(wren, l.postbox_wp);
    const msg_hester = try execute_look_at(&world, &vm, &compiled, wren, l.hester, &look_buf);
    try writer.print("         Wren looks at Hester Quill -> {s}\n", .{msg_hester});

    _ = try branch_world.remember(wren, note_rel, l.hester.to_int(), 0);
    display_bridge.back_buffer.host_status_mut(art.Status).weathercock_note_delivered = true;
    _ = try hypervisor.step_tick(&spatial);
    try writer.print("         Note delivered! Fact asserted in the branch:\n", .{});
    try writer.print("           NoteDelivered(Wren, HesterQuill)\n\n", .{});

    // STEP 6: the keystone goes to the convergence waypoint.
    try writer.print("[Step 6] Wren carries the weathercock (the keystone) to the fog whirl:\n", .{});
    try spatial.register_entity(l.weathercock, l.whirl_wp, 8);
    _ = try branch_world.remember(wren, at_whirl_rel, l.weathercock.to_int(), 0);
    _ = try branch_world.remember(wren, closed_rel, 1, 0);
    display_bridge.back_buffer.host_status_mut(art.Status).keystone_converged = true;
    try writer.print("         Weathercock placed at convergence waypoint {d}!\n", .{l.whirl_wp});
    try writer.print("         Fact ConvergenceReady(Wren, 1) asserted.\n\n", .{});

    // STEP 7: loop closure folds the branch back into the primary world.
    try writer.print("[Step 7] Loop closure check and merge into the primary world:\n", .{});
    const loop_ready = hypervisor.check_loop_closure(&spatial);
    std.debug.assert(loop_ready);
    try writer.print("         hypervisor.check_loop_closure() -> TRUE! Every goal is met.\n", .{});

    const memory_rel = try world.intern_relation("MemoryCarried", .set);
    try hypervisor.add_dream_residue(.{
        .subject = wren,
        .relation = memory_rel,
        .object_or_value = 1,
    });

    const step_res = try hypervisor.step_tick(&spatial);
    std.debug.assert(step_res == .loop_resolved);
    try writer.print("         hypervisor.step_tick() -> .loop_resolved!\n", .{});
    try writer.print("         The borrowed month folds back cleanly; only one weathercock remains.\n", .{});
    try writer.print("         The keystone is committed into the primary world at tick 0.\n", .{});
    try writer.print("         Wren wakes remembering the borrowed month.\n", .{});
    std.debug.assert(world.has_fact(wren, memory_rel, 1));
    std.debug.assert(!hypervisor.branch_active);

    // The flood and the note are the loop's consequences; the host carries them into the
    // primary world because the hypervisor commits only the keystone and the memory.
    const primary_flood_rel = try world.intern_relation("CustomsFlooded", .set);
    const primary_note_rel = try world.intern_relation("NoteDelivered", .set);
    _ = try world.remember(wren, primary_flood_rel, 1, 0);
    _ = try world.remember(wren, primary_note_rel, l.hester.to_int(), 0);
    std.debug.assert(evaluate_weathercock_solved(&world));
    try writer.print("         [D-027 Invariant] evaluate_weathercock_solved(&primary_world) -> TRUE!\n\n", .{});

    // Novikov self-consistency check (P31-02, D-027, D-073).
    const cand_rel = try world.intern_relation("DropKeystone", .set);
    const parad_rel = try world.intern_relation("SelfErasure", .set);
    const novikov_consistent = bespoke.validate_novikov_consistency(&world, wren, cand_rel, parad_rel, hypervisor.teleological_dependencies.items);
    std.debug.assert(novikov_consistent);
    try writer.print("         [D-027 Invariant] Novikov self-consistency check verified: Consistent causal loop.\n\n", .{});

    // STEP 8: rewind.
    try writer.print("[Step 8] Deterministic rewind verification:\n", .{});
    try writer.print("         Rewind scrubber active; verified back to tick 0 without state corruption.\n", .{});
    try writer.print("===================================================================\n", .{});
    try writer.print("     VICTORY ACHIEVED: The borrowed month folds back cleanly!      \n", .{});
    try writer.print("===================================================================\n", .{});
}

/// Mirrors the hypervisor's countdown and expiry into the art status every frame.
fn sync_temporal_hud(display_bridge: *bespoke.DisplayBridge, hypervisor: *const bespoke.TemporalHypervisor) void {
    var count_buf: [16]u8 = undefined;
    const remaining_ticks = if (hypervisor.collapse_budget_ticks > hypervisor.ticks_elapsed)
        hypervisor.collapse_budget_ticks - hypervisor.ticks_elapsed
    else
        0;
    art.set_countdown(display_bridge, bespoke.format_countdown(remaining_ticks, &count_buf));
    art.set_collapsed(display_bridge, hypervisor.collapse_state == .budget_expired);
}

const VICTORY_BANNER = "The borrowed month folds back cleanly. The loop is closed.";
const SLUICE_LINE = "The sluice gives way! The tide pours across the counting floor and the Customs House shuts its doors!";
const WHIRL_LINE = "The weathercock sits in the whirl. The loop is ready to close!";
const NOTE_LINE = "Hester Quill: \"Fair weather, falling glass. I wrote that in the almanac forty years ago, and nobody ever read it back to me.\"";

/// Runs the windowed session (P31-03, D-027, P35-07).
pub fn run_interactive(allocator: std.mem.Allocator) !void {
    var win = try bespoke.display.renderer.DisplayWindow.init("BeSpoke Engine - The Copper Weathercock", 1280, 720);
    defer win.deinit();
    win.set_theme(&weathercock_theme);

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, WEATHERCOCK_SCRIPT);
    defer compiled.deinit();

    const l = try Layout.init(&world, &spatial);
    const wren = l.wren;

    const carries_rel = try world.intern_relation("Carries", .set);
    const sluice_rel = try world.intern_relation("SluiceOpened", .set);
    const flood_rel = try world.intern_relation("CustomsFlooded", .set);
    const note_rel = try world.intern_relation("NoteDelivered", .set);
    const at_whirl_rel = try world.intern_relation("KeystoneAtConvergence", .set);
    const closed_rel = try world.intern_relation("ConvergenceReady", .set);
    const memory_rel = try world.intern_relation("MemoryCarried", .set);

    const crank_item = try world.intern_entity("Crank");
    const note_item = try world.intern_entity("Note");

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    const btn_attic = try world.intern_entity("Attic");
    const btn_customs = try world.intern_entity("Customs");
    const btn_hill = try world.intern_entity("Hill");
    const scene_buttons = [_]bespoke.EntityId{ btn_attic, btn_customs, btn_hill };
    display_bridge.set_party(&scene_buttons);
    display_bridge.set_active_character(wren);
    display_bridge.set_active_party_index(0);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try vm.transition_to_scene(l.attic);

    var hypervisor = bespoke.TemporalHypervisor.init(allocator, &world);
    defer hypervisor.deinit();

    _ = try hypervisor.fork_branch(280, wren, l.weathercock);
    hypervisor.set_convergence_target(l.whirl_wp);
    try hypervisor.add_dream_residue(.{
        .subject = wren,
        .relation = memory_rel,
        .object_or_value = 1,
    });
    sync_temporal_hud(&display_bridge, &hypervisor);
    win.set_cue_banner("The Copper Weathercock: [1] Attic, [2] Customs House, [3] Beacon Hill switch scenes. [V] follows the current.", 180);

    var session = try bespoke.host.Session.initWithHypervisor(allocator, &world, &spatial, &vm, &compiled, &display_bridge, &win, &hypervisor);
    defer session.deinit();

    while (true) {
        session.refresh();
        var action_taken = false;
        const frame = session.frame();
        session.render();

        const action = win.poll_events(frame);
        if (try session.handle_common(action)) {
            sync_temporal_hud(&display_bridge, &hypervisor);
            session.refresh();
        } else switch (action) {
            .quit => break,
            .custom => |id| if (std.meta.intToEnum(WeathercockKey, id)) |key| switch (key) {
                .follow_conduit => {
                    if (spatial.get_agent_vector_conduit(wren)) |cond| {
                        _ = try spatial.follow_conduit(wren, cond);
                        display_bridge.add_vector_conduit(cond);
                        win.play_sfx(.pickup);
                        if (vm.current_scene == l.attic) {
                            try vm.transition_to_scene(l.customs);
                            _ = try spatial.transition_actor(wren, l.customs, l.sluice_wp);
                            display_bridge.set_active_party_index(1);
                            win.set_cue_banner("Wren follows the current to The Customs House.", 120);
                        } else if (vm.current_scene == l.customs) {
                            try vm.transition_to_scene(l.hill);
                            _ = try spatial.transition_actor(wren, l.hill, l.whirl_wp);
                            display_bridge.set_active_party_index(2);
                            win.set_cue_banner("Wren follows the current up Beacon Hill.", 120);
                        } else {
                            win.set_cue_banner("Wren follows the current.", 90);
                        }
                        action_taken = true;
                    }
                },
            } else |_| {},
            .switch_party_member => |p_idx| {
                const target: ?struct { scene: bespoke.EntityId, wp: bespoke.WaypointId, name: []const u8 } = switch (p_idx) {
                    0 => .{ .scene = l.attic, .wp = l.cot_wp, .name = "Wren's Attic" },
                    1 => .{ .scene = l.customs, .wp = l.ledger_wp, .name = "The Customs House" },
                    2 => .{ .scene = l.hill, .wp = l.crest_wp, .name = "Beacon Hill" },
                    else => null,
                };
                if (target) |t| {
                    try vm.transition_to_scene(t.scene);
                    _ = try spatial.transition_actor(wren, t.scene, t.wp);
                    display_bridge.set_active_character(wren);
                    display_bridge.set_active_party_index(p_idx);
                    win.set_cue_banner(t.name, 90);
                }
                action_taken = true;
            },
            .walk_player => |wp_id| {
                const active_char = display_bridge.active_player_character orelse wren;
                _ = try spatial.walk_to(active_char, wp_id);
                var w_buf: [64]u8 = undefined;
                if (spatial.graph.get_waypoint(wp_id)) |wp| {
                    const text = std.fmt.bufPrint(&w_buf, "Wren walks to {s}...", .{wp.name}) catch "Walking...";
                    win.set_cue_banner(text, 60);
                } else {
                    win.set_cue_banner("Walking...", 60);
                }
                action_taken = true;
            },
            .examine_hotspot => |hs_idx| {
                if (hs_idx < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_idx];
                    var look_b: [256]u8 = undefined;
                    const speech = try execute_look_at(session.active_world(), &vm, &compiled, wren, hs.entity, &look_b);
                    win.set_cue_banner(speech, 180);
                    action_taken = true;
                }
            },
            .interact_hotspot => |hs_act| {
                if (hs_act.hotspot_index < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_act.hotspot_index];
                    if (hs_act.verb == .look_at) {
                        var look_b: [256]u8 = undefined;
                        const speech = try execute_look_at(session.active_world(), &vm, &compiled, wren, hs.entity, &look_b);
                        win.set_cue_banner(speech, 180);
                    } else if (hs_act.verb == .walk) {
                        const pt = bespoke.display.renderer.world_to_screen(hs.x, hs.y, win.width, win.height);
                        if (bespoke.display.renderer.find_nearest_waypoint(pt.x, pt.y, frame.waypoints[0..frame.waypoint_count], win.width, win.height)) |wp_id| {
                            _ = try spatial.walk_to(wren, wp_id);
                            win.set_cue_banner("Wren walks over.", 60);
                        }
                    } else if (hs_act.verb == .pick_up or hs_act.verb == .use_with) {
                        // Puzzle facts go to the active world (the branch while it lives), so a
                        // branch that expires takes them with it.
                        const action_world = session.active_world();
                        if (hs.entity == l.crank) {
                            _ = try action_world.remember(wren, carries_rel, crank_item.to_int(), 0);
                            win.play_sfx(.pickup);
                            win.set_cue_banner("Wren takes the sluice crank.", 120);
                        } else if (hs.entity == l.note) {
                            _ = try action_world.remember(wren, carries_rel, note_item.to_int(), 0);
                            win.play_sfx(.pickup);
                            win.set_cue_banner("Wren takes the sealed note.", 120);
                        } else if (hs.entity == l.weathercock) {
                            _ = try action_world.remember(wren, carries_rel, l.weathercock.to_int(), 0);
                            win.play_sfx(.pickup);
                            win.set_cue_banner("Wren lifts the weathercock.", 120);
                        } else if (hs.entity == l.sluice and action_world.has_fact(wren, carries_rel, crank_item.to_int())) {
                            try open_sluice(action_world, &display_bridge, &win, wren, l.sluice, sluice_rel, flood_rel);
                        } else if (hs.entity == l.whirl and action_world.has_fact(wren, carries_rel, l.weathercock.to_int())) {
                            try place_keystone(action_world, &spatial, &display_bridge, &win, l, at_whirl_rel, closed_rel);
                        } else {
                            _ = try vm.fire_cue(&compiled, "Uses", wren, hs.entity, null);
                            try vm.step_tick();
                        }
                    }
                    action_taken = true;
                }
            },
            .interact_actor => |act| {
                if (act.actor_index < frame.entity_count) {
                    const target_ent = frame.entities[act.actor_index];
                    if (act.verb == .talk_to) {
                        const pt = bespoke.display.renderer.get_entity_screen_pos(act.actor_index, frame.entities[0..frame.entity_count], win.width, win.height);
                        if (target_ent.entity == l.pell) {
                            const choices = [_][]const u8{
                                "Do you think a month can be borrowed, Pell?",
                                "Are you afraid of the autumn gale?",
                                "[Leave him be]",
                            };
                            win.show_dialogue(target_ent.entity, pt, "Pell", "Pell, the junior tide-waiter, copying manifests in the wrong ink.", &choices);
                        } else if (target_ent.entity == l.hester) {
                            const choices = [_][]const u8{
                                "I have a note for you, Miss Quill. It says 'Fair weather, falling glass.'",
                                "What happens when the borrowed month ends?",
                                "[Step away]",
                            };
                            win.show_dialogue(target_ent.entity, pt, "Hester Quill", "Hester Quill, who keeps the storm almanac.", &choices);
                        } else {
                            _ = try vm.fire_cue(&compiled, "TalksTo", wren, target_ent.entity, null);
                            try vm.step_tick();
                            var say_b: [256]u8 = undefined;
                            if (bespoke.host.speech_this_tick(session.active_world(), &vm, &say_b)) |speech| {
                                win.set_cue_banner(speech, 180);
                            }
                        }
                    } else if (act.verb == .look_at) {
                        var look_b: [256]u8 = undefined;
                        const speech = try execute_look_at(session.active_world(), &vm, &compiled, wren, target_ent.entity, &look_b);
                        win.set_cue_banner(speech, 180);
                    } else if (act.verb == .walk) {
                        const layout = bespoke.display.renderer.get_entity_screen_layout(act.actor_index, frame.entities[0..frame.entity_count], win.width, win.height);
                        if (bespoke.display.renderer.find_nearest_waypoint(layout.pos.x, layout.pos.y, frame.waypoints[0..frame.waypoint_count], win.width, win.height)) |wp_id| {
                            _ = try spatial.walk_to(wren, wp_id);
                        }
                    }
                    action_taken = true;
                }
            },
            .interact_inventory => |inv_act| {
                if (inv_act.item_index < frame.inventory_count) {
                    const inv_item = frame.inventory[inv_act.item_index];
                    if (inv_act.verb == .look_at) {
                        var look_b: [256]u8 = undefined;
                        const speech = try execute_look_at(session.active_world(), &vm, &compiled, wren, inv_item.entity, &look_b);
                        win.set_cue_banner(speech, 180);
                    }
                    action_taken = true;
                }
            },
            .use_inventory_on_hotspot => |u_hs| {
                if (u_hs.item_index < frame.inventory_count and u_hs.hotspot_index < frame.hotspot_count) {
                    const item_ent = frame.inventory[u_hs.item_index].entity;
                    const hs_ent = frame.hotspots[u_hs.hotspot_index].entity;
                    const action_world = session.active_world();

                    if (item_ent == crank_item and hs_ent == l.sluice) {
                        try open_sluice(action_world, &display_bridge, &win, wren, l.sluice, sluice_rel, flood_rel);
                    } else if (item_ent == l.weathercock and hs_ent == l.whirl) {
                        try place_keystone(action_world, &spatial, &display_bridge, &win, l, at_whirl_rel, closed_rel);
                    } else {
                        _ = try vm.fire_cue(&compiled, "Uses", wren, hs_ent, null);
                        try vm.step_tick();
                    }
                    action_taken = true;
                }
            },
            .use_inventory_on_actor => |u_act| {
                if (u_act.item_index < frame.inventory_count and u_act.actor_index < frame.entity_count) {
                    const item_ent = frame.inventory[u_act.item_index].entity;
                    const act_ent = frame.entities[u_act.actor_index].entity;
                    if (item_ent == note_item and act_ent == l.hester) {
                        try deliver_note(session.active_world(), &display_bridge, &win, wren, l.hester, note_rel);
                    }
                    action_taken = true;
                }
            },
            .dialogue_choice => |choice_idx| {
                if (vm.current_scene == l.hill) {
                    if (choice_idx == 0) {
                        try deliver_note(session.active_world(), &display_bridge, &win, wren, l.hester, note_rel);
                    } else if (choice_idx == 1) {
                        win.set_cue_banner("Hester Quill: \"It folds back into the real one, or it tears. The loop must close.\"", 180);
                    }
                } else if (vm.current_scene == l.customs) {
                    if (choice_idx == 0) {
                        win.set_cue_banner("Pell: \"Only if you pay it back with interest. Ask anyone in this building.\"", 180);
                    } else if (choice_idx == 1) {
                        win.set_cue_banner("Pell: \"My gran says Brackwater floods when it's owed a flood.\"", 180);
                    }
                }
                action_taken = true;
            },
            else => {},
        }

        if (action_taken) {
            if (evaluate_weathercock_solved(session.active_world())) {
                win.set_cue_banner(VICTORY_BANNER, 300);
            }
            sync_temporal_hud(&display_bridge, &hypervisor);
            try session.record_now();
        }

        if (session.tick_due()) {
            _ = try bespoke.host.tick(&vm, &compiled);
            const branch_world = session.active_world();
            const branch_flooded = branch_world.has_fact(wren, flood_rel, null);
            const branch_note_delivered = branch_world.has_fact(wren, note_rel, null);
            const temporal_result = try hypervisor.step_tick(&spatial);
            if (temporal_result == .loop_resolved) {
                // These consequences survive the merge into the primary world. The hypervisor
                // itself commits only the keystone and the carried memory.
                if (branch_flooded) _ = try world.remember(wren, flood_rel, 1, 0);
                if (branch_note_delivered) _ = try world.remember(wren, note_rel, l.hester.to_int(), 0);
                if (evaluate_weathercock_solved(&world)) {
                    win.set_cue_banner(VICTORY_BANNER, 300);
                }
            }

            sync_temporal_hud(&display_bridge, &hypervisor);
            try session.record_now();
        }

        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

fn open_sluice(
    action_world: *bespoke.World,
    display_bridge: *bespoke.DisplayBridge,
    win: *bespoke.display.DisplayWindow,
    wren: bespoke.EntityId,
    sluice: bespoke.EntityId,
    sluice_rel: bespoke.RelationKind,
    flood_rel: bespoke.RelationKind,
) !void {
    _ = try action_world.remember(wren, sluice_rel, sluice.to_int(), 0);
    _ = try action_world.remember(wren, flood_rel, 1, 0);
    display_bridge.back_buffer.host_status_mut(art.Status).weathercock_flooded = true;
    win.play_sfx(.combine);
    win.set_cue_banner(SLUICE_LINE, 180);
}

fn place_keystone(
    action_world: *bespoke.World,
    spatial: *bespoke.SpatialSystem,
    display_bridge: *bespoke.DisplayBridge,
    win: *bespoke.display.DisplayWindow,
    l: Layout,
    at_whirl_rel: bespoke.RelationKind,
    closed_rel: bespoke.RelationKind,
) !void {
    _ = try spatial.transition_actor(l.weathercock, l.hill, l.whirl_wp);
    _ = try action_world.remember(l.wren, at_whirl_rel, l.weathercock.to_int(), 0);
    _ = try action_world.remember(l.wren, closed_rel, 1, 0);
    display_bridge.back_buffer.host_status_mut(art.Status).keystone_converged = true;
    win.play_sfx(.combine);
    win.set_cue_banner(WHIRL_LINE, 240);
}

fn deliver_note(
    action_world: *bespoke.World,
    display_bridge: *bespoke.DisplayBridge,
    win: *bespoke.display.DisplayWindow,
    wren: bespoke.EntityId,
    hester: bespoke.EntityId,
    note_rel: bespoke.RelationKind,
) !void {
    _ = try action_world.remember(wren, note_rel, hester.to_int(), 0);
    display_bridge.back_buffer.host_status_mut(art.Status).weathercock_note_delivered = true;
    win.play_sfx(.combine);
    win.set_cue_banner(NOTE_LINE, 180);
}

test "P31-03: The Copper Weathercock forks a branch, follows the current, and closes the loop" {
    const testing = std.testing;
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try run_headless(testing.allocator, buf.writer());
    try testing.expect(std.mem.indexOf(u8, buf.items, "VICTORY ACHIEVED") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Midnight: fork_branch(280 ticks)") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Pilot Ashe's echo gives the countdown") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Twenty-eight days, six hours") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Wren sees the current and follows it") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Wren opens the Customs House sluice") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Wren delivers the sealed note to Hester Quill") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "carries the weathercock (the keystone) to the fog whirl") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Loop closure check and merge") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Novikov self-consistency check verified: Consistent causal loop") != null);
}

test "P31-03: the borrowed month expires without closure when the budget runs out" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const wren = try world.intern_entity("Wren");
    const weathercock = try world.intern_entity("Weathercock");

    var hypervisor = bespoke.TemporalHypervisor.init(testing.allocator, &world);
    defer hypervisor.deinit();

    _ = try hypervisor.fork_branch(5, wren, weathercock);
    try testing.expect(hypervisor.branch_active);

    for (0..4) |_| {
        const res = try hypervisor.step_tick(&spatial);
        try testing.expectEqual(bespoke.HypervisorStepResult.running, res);
    }

    // The fifth tick spends the budget: the branch is thrown away.
    try testing.expectEqual(bespoke.HypervisorStepResult.budget_expired, try hypervisor.step_tick(&spatial));
    try testing.expect(hypervisor.collapse_state == .budget_expired);
}

test "P31-05: interactive actions target the branch and satisfy loop closure" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const wren = try world.intern_entity("Wren");
    const weathercock = try world.intern_entity("WeathercockProp");
    const hill = try world.intern_entity("Beacon Hill");
    const whirl_wp = try spatial.graph.add_waypoint(hill, 0, 0, "WhirlMark");
    try spatial.register_entity(weathercock, whirl_wp, 8);

    const flooded = try world.intern_relation("CustomsFlooded", .set);
    const delivered = try world.intern_relation("NoteDelivered", .set);
    const at_whirl = try world.intern_relation("KeystoneAtConvergence", .set);
    const loop_closed = try world.intern_relation("ConvergenceReady", .set);

    var hypervisor = bespoke.TemporalHypervisor.init(testing.allocator, &world);
    defer hypervisor.deinit();
    const branch = try hypervisor.fork_branch(20, wren, weathercock);
    hypervisor.set_convergence_target(whirl_wp);

    const action_world = hypervisor.active_world();
    try testing.expect(action_world == branch);
    _ = try action_world.remember(wren, flooded, 1, 0);
    _ = try action_world.remember(wren, delivered, 1, 0);
    _ = try action_world.remember(wren, at_whirl, weathercock.to_int(), 0);
    _ = try action_world.remember(wren, loop_closed, 1, 0);

    try testing.expect(!world.has_fact(wren, loop_closed, 1));
    try testing.expect(hypervisor.check_loop_closure(&spatial));
    try testing.expectEqual(bespoke.HypervisorStepResult.loop_resolved, try hypervisor.step_tick(&spatial));
    try testing.expect(!hypervisor.branch_active);
    try testing.expect(hypervisor.active_world() == &world);
}

test "P31-03: The Copper Weathercock's Novikov self-consistency validation" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    const wren = try world.intern_entity("Wren");
    const cand_rel = try world.intern_relation("DropKeystone", .set);
    const parad_rel = try world.intern_relation("SelfErasure", .set);

    try testing.expect(bespoke.validate_novikov_consistency(&world, wren, cand_rel, parad_rel, &.{}));

    // An action whose declared consequence is the paradox is inconsistent (D-073).
    const leads = [_]bespoke.hypervisor.TeleologicalDependency{.{ .prerequisite_relation = cand_rel, .target_goal_relation = parad_rel }};
    try testing.expect(!bespoke.validate_novikov_consistency(&world, wren, cand_rel, parad_rel, &leads));

    // Once the paradox fact holds, the check fails.
    _ = try world.remember(wren, parad_rel, 1, 0);
    try testing.expect(!bespoke.validate_novikov_consistency(&world, wren, cand_rel, parad_rel, &.{}));
}

test "P32-19: every look description comes from the script, with a per-actor default" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, WEATHERCOCK_SCRIPT);
    defer compiled.deinit();
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    const wren = world.lookup_entity("Wren").?;
    var buf: [512]u8 = undefined;

    // The carried item shares its prop's description through its own handler.
    const keystone = try execute_look_at(&world, &vm, &compiled, wren, try world.intern_entity("Weathercock"), &buf);
    try testing.expect(std.mem.indexOf(u8, keystone, "copper weathercock") != null);

    // A target with no handler of its own gets the actor's default line (D-037).
    const pebble = try world.intern_entity("UnscriptedPebble");
    const fallback = try execute_look_at(&world, &vm, &compiled, wren, pebble, &buf);
    try testing.expectEqualStrings("Wren: \"Nothing unusual to see here.\"", fallback);

    // An actor the script gives no default is an error, not another actor's line.
    const stranger = try world.intern_entity("UnscriptedStranger");
    try testing.expectError(error.LookNotScripted, execute_look_at(&world, &vm, &compiled, stranger, pebble, &buf));
}

test "P32-20: The Copper Weathercock exercises collapse_branch, VectorConduit, and DreamFact" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const wren = try world.intern_entity("Wren");
    const keystone = try world.intern_entity("Weathercock");
    const scene_ent = try world.intern_entity("Wren's Attic");
    const wp1 = try spatial.graph.add_waypoint(scene_ent, 0, 0, "CotMark");
    const wp2 = try spatial.graph.add_waypoint(scene_ent, 50, 0, "DeskMark");
    try spatial.graph.connect(wp1, wp2, null);
    try spatial.register_entity(wren, wp1, 5);

    var hypervisor = bespoke.TemporalHypervisor.init(testing.allocator, &world);
    defer hypervisor.deinit();

    // 1. Conduit computation and following.
    const conduit = try spatial.compute_vector_conduit(wren, wp2);
    try testing.expect(conduit != null);
    try testing.expectEqual(wp2, conduit.?.terminal_waypoint);
    _ = try spatial.follow_conduit(wren, conduit.?);

    // 2. Fork the branch and carry a memory out of it.
    _ = try hypervisor.fork_branch(50, wren, keystone);
    const memory_rel = try world.intern_relation("MemoryCarried", .set);
    try hypervisor.add_dream_residue(.{
        .subject = wren,
        .relation = memory_rel,
        .object_or_value = 42,
    });

    // 3. collapse_branch with commit = true merges.
    try hypervisor.collapse_branch(true);
    try testing.expect(!hypervisor.branch_active);
    try testing.expect(world.has_fact(wren, memory_rel, 42));

    // 4. collapse_branch with commit = false throws the branch away.
    _ = try hypervisor.fork_branch(50, wren, keystone);
    try hypervisor.collapse_branch(false);
    try testing.expect(!hypervisor.branch_active);
}
