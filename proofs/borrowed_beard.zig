const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const BeardKey = enum(u16) { inn, yard, office, scavenge, step_1, step_2, step_3, step_4, step_5, step_6, step_7, step_8 };

const beard_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_i, .action = @intFromEnum(BeardKey.inn) },
    .{ .key = bespoke.display.renderer.c.SDLK_y, .action = @intFromEnum(BeardKey.yard) },
    .{ .key = bespoke.display.renderer.c.SDLK_o, .action = @intFromEnum(BeardKey.office) },
    .{ .key = bespoke.display.renderer.c.SDLK_0, .action = @intFromEnum(BeardKey.scavenge) },
    .{ .key = bespoke.display.renderer.c.SDLK_1, .action = @intFromEnum(BeardKey.step_1) },
    .{ .key = bespoke.display.renderer.c.SDLK_2, .action = @intFromEnum(BeardKey.step_2) },
    .{ .key = bespoke.display.renderer.c.SDLK_3, .action = @intFromEnum(BeardKey.step_3) },
    .{ .key = bespoke.display.renderer.c.SDLK_4, .action = @intFromEnum(BeardKey.step_4) },
    .{ .key = bespoke.display.renderer.c.SDLK_5, .action = @intFromEnum(BeardKey.step_5) },
    .{ .key = bespoke.display.renderer.c.SDLK_6, .action = @intFromEnum(BeardKey.step_6) },
    .{ .key = bespoke.display.renderer.c.SDLK_7, .action = @intFromEnum(BeardKey.step_7) },
    .{ .key = bespoke.display.renderer.c.SDLK_8, .action = @intFromEnum(BeardKey.step_8) },
});

pub const BORROWED_BEARD_SCRIPT =
    \\scene: Inn Landing
    \\cast: Tamsin, CaptainRook
    \\props: RookDoor, WashStand
    \\marks: Room4, Room7, Stairs
    \\
    \\scene: Net Loft Yard
    \\cast: Bramble
    \\props: GateGap, RainBarrel
    \\marks: YardPath, GateMark, DogBed
    \\
    \\scene: Harbour Office
    \\cast: PurserWick
    \\props: BerthCounter, PacketBoat
    \\marks: OfficeDoor, CounterMark, Quay
    \\
    \\Taped is a state, which can be taped or untaped. The gap is untaped in the scene.
    \\Startled is a state, which can be startled or calm. The dog is calm in the scene.
    \\Disguised is a state, which can be disguised or undisguised. Tamsin is undisguised in the scene.
    \\HasBerthTicket is a state, which can be held or unheld.
    \\
    \\on cue Uses(Tamsin, WashStand):
    \\  if not Carries(Tamsin, Charcoal):
    \\    say Tamsin: "I'll take the charcoal stick, the roll of sail tape, and this pot of honey from my washstand."
    \\    remember Carries(Tamsin, Charcoal)
    \\    remember Carries(Tamsin, SailTape)
    \\    remember Carries(Tamsin, HoneyPot)
    \\
    \\on cue Uses(Tamsin, RainBarrel):
    \\  if not Carries(Tamsin, WateringCan):
    \\    say Tamsin: "A watering can, still half full. That could be useful."
    \\    remember Carries(Tamsin, WateringCan)
    \\
    \\routine RookPacing(CaptainRook):
    \\  loop:
    \\    walk CaptainRook to Room7
    \\    wait 30 ticks
    \\    walk CaptainRook to Stairs
    \\    wait 30 ticks
    \\
    \\routine DogNapping(Bramble):
    \\  loop:
    \\    wait 40 ticks
    \\    say Bramble: "Wuff..."
    \\
    \\on cue Uses(Tamsin, RookDoor):
    \\  if not Carries(Tamsin, RookPapers):
    \\    say Tamsin: "Rook's sailing papers are poking out of his coat on the door peg. I'll borrow them."
    \\    remember Carries(Tamsin, RookPapers)
    \\
    \\on cue Uses(Tamsin, Charcoal, RookPapers):
    \\  say Tamsin: "Rook's portrait has no beard! A few strokes of charcoal, and now it does."
    \\    remember PapersMarked(Tamsin, true)
    \\
    \\on cue Uses(Tamsin, SailTape, GateGap):
    \\  now GateGap is taped
    \\  say Tamsin: "I've stretched sail tape across the bottom of the gap under the gate."
    \\
    \\on cue Uses(Tamsin, WateringCan, Bramble):
    \\  if GateGap is not taped:
    \\    say Tamsin: "Soaking the dog now won't help; the gap under the gate isn't taped."
    \\  if GateGap is taped:
    \\    now Bramble is startled
    \\    animate (Bramble, dog-fleeing)
    \\    walk Bramble to GateMark
    \\    say Tamsin: "The soaked dog bolts under the gate, leaving a thick tuft of grey fur on the tape!"
    \\    remember GapHasFur(GateGap, true)
    \\
    \\on cue Uses(Tamsin, GateGap):
    \\  if GapHasFur(GateGap):
    \\    say Tamsin: "I'll peel the tape off. One strip of genuine grey dog fur."
    \\    remember Carries(Tamsin, DogFur)
    \\    forget GapHasFur(GateGap)
    \\    now GateGap is not taped
    \\
    \\on cue Uses(Tamsin, DogFur, HoneyPot):
    \\  say Tamsin: "I dab honey on my chin and press the fur firmly in place."
    \\  remember Carries(Tamsin, GreyBeard)
    \\  remember StickyChin(Tamsin, true)
    \\
    \\on cue Uses(Tamsin, GreyBeard, Tamsin):
    \\  if PapersMarked(Tamsin):
    \\    say Tamsin: "With Rook's papers and my bristling grey beard, the likeness is uncanny!"
    \\    remember Disguised(Tamsin, true)
    \\  if not PapersMarked(Tamsin):
    \\    say Tamsin: "The beard's on, but Rook's portrait is still clean-shaven. I need to fix his papers."
    \\
    \\on cue TalksTo(Tamsin, PurserWick):
    \\  choice "I'd like a berth on the packet boat." if not Disguised(Tamsin):
    \\    say PurserWick: "Sorry, miss. The last berth is held for Captain Ansel Rook."
    \\  choice "I am Captain Ansel Rook. I've come for my berth." if Disguised(Tamsin):
    \\    say PurserWick: "Captain Rook! That's a fine beard you're growing. Here's your berth ticket."
    \\    remember HasBerthTicket(Tamsin, true)
    \\  choice "Whose dog is that in the yard?":
    \\    say PurserWick: "That's Bramble, the net-mender's dog. Don't you go upsetting him."
    \\  choice "Good day.":
    \\    say PurserWick: "Fair winds, miss."
;

pub const BeardStage = enum {
    inn_landing,
    net_loft_yard,
    harbour_office,
};

/// Evaluates whether Tamsin has completed her disguise to claim Rook's berth (P14-01, D-016).
pub fn evaluate_disguise(world: *const bespoke.World) bool {
    // The exact fact the script writes when Tamsin puts the beard on, and the one the
    // purser's dialogue's `Disguised(Tamsin)` guards read (P32-19).
    const tamsin = world.lookup_entity("Tamsin") orelse return false;
    const rel = world.lookup_relation("Disguised") orelse return false;
    return world.has_fact(tamsin, rel, null);
}

/// Evaluates whether the berth puzzle has been solved (P14-01, D-016).
pub fn evaluate_puzzle_victory(world: *const bespoke.World) bool {
    const tamsin = world.lookup_entity("Tamsin") orelse return false;
    const rel = world.lookup_relation("HasBerthTicket") orelse return false;
    return world.has_fact(tamsin, rel, null);
}

/// Fires one scripted action and advances until its first line of speech or `max_ticks`.
/// Puzzle facts remain owned by the script; the host only supplies player intent.
fn scripted_action(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    cue: []const u8,
    actor: bespoke.EntityId,
    target_a: ?bespoke.EntityId,
    target_b: ?bespoke.EntityId,
    max_ticks: usize,
    speech_buf: []u8,
) !?[]const u8 {
    _ = try vm.fire_cue(compiled, cue, actor, target_a, target_b);
    var ticks: usize = 0;
    while (ticks < max_ticks) : (ticks += 1) {
        _ = try bespoke.host.tick(vm, compiled);
        if (vm.dialogue_view() != null) _ = try vm.choose(0);
        if (bespoke.host.speech_this_tick(world, vm, speech_buf)) |speech| return speech;
    }
    return null;
}

/// Supplies interactive player intent to the script and advances the complete host session.
fn session_scripted_action(
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
    var tick: usize = 0;
    while (tick < ticks) : (tick += 1) _ = try session.advance();
}

/// Executes headless simulation of The Borrowed Beard vertical slice (P14-01, P14-03, D-016, P35-04).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("           BeSpoke Engine: The Borrowed Beard Scenario              \n", .{});
    try writer.print("  (Multi-Scene DSL * Crafting * Dynamic Fact-Guarded Dialogue)     \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Lowering The Borrowed Beard narrative script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, BORROWED_BEARD_SCRIPT);
    defer compiled.deinit();

    // Scene Room Entities
    const inn_scene = world.lookup_entity("Inn Landing").?;
    const yard_scene = world.lookup_entity("Net Loft Yard").?;
    const office_scene = world.lookup_entity("Harbour Office").?;

    // Actor Entities
    const tamsin = world.lookup_entity("Tamsin").?;
    const rook = world.lookup_entity("CaptainRook").?;
    const bramble = world.lookup_entity("Bramble").?;
    const purser = world.lookup_entity("PurserWick").?;

    // Spatial Marks
    const room4_wp = spatial.graph.find_waypoint_in_room(inn_scene, "Room4") orelse 1;
    const room7_wp = spatial.graph.find_waypoint_in_room(inn_scene, "Room7") orelse 2;
    const stairs_wp = spatial.graph.find_waypoint_in_room(inn_scene, "Stairs") orelse
        try spatial.graph.add_waypoint(inn_scene, 32, 0, "Stairs");

    const yard_path_wp = spatial.graph.find_waypoint_in_room(yard_scene, "YardPath") orelse
        try spatial.graph.add_waypoint(yard_scene, 0, 0, "YardPath");
    const gate_wp = spatial.graph.find_waypoint_in_room(yard_scene, "GateMark") orelse
        try spatial.graph.add_waypoint(yard_scene, 18, 0, "GateMark");
    const dog_wp = spatial.graph.find_waypoint_in_room(yard_scene, "DogBed") orelse
        try spatial.graph.add_waypoint(yard_scene, 34, 0, "DogBed");

    const office_door_wp = spatial.graph.find_waypoint_in_room(office_scene, "OfficeDoor") orelse
        try spatial.graph.add_waypoint(office_scene, 0, 0, "OfficeDoor");
    const counter_wp = spatial.graph.find_waypoint_in_room(office_scene, "CounterMark") orelse
        try spatial.graph.add_waypoint(office_scene, 16, 0, "CounterMark");
    const quay_wp = spatial.graph.find_waypoint_in_room(office_scene, "Quay") orelse
        try spatial.graph.add_waypoint(office_scene, 32, 0, "Quay");

    // Position waypoints (calibrated for 1280x720 standardized layout)
    if (spatial.graph.get_waypoint(room4_wp)) |_| spatial.graph.waypoints.items[room4_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(room7_wp)) |_| spatial.graph.waypoints.items[room7_wp - 1].pos = .{ .x = 16, .y = 0 };
    if (spatial.graph.get_waypoint(stairs_wp)) |_| spatial.graph.waypoints.items[stairs_wp - 1].pos = .{ .x = 32, .y = 0 };

    if (spatial.graph.get_waypoint(yard_path_wp)) |_| spatial.graph.waypoints.items[yard_path_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(gate_wp)) |_| spatial.graph.waypoints.items[gate_wp - 1].pos = .{ .x = 18, .y = 0 };
    if (spatial.graph.get_waypoint(dog_wp)) |_| spatial.graph.waypoints.items[dog_wp - 1].pos = .{ .x = 34, .y = 0 };

    if (spatial.graph.get_waypoint(office_door_wp)) |_| spatial.graph.waypoints.items[office_door_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(counter_wp)) |_| spatial.graph.waypoints.items[counter_wp - 1].pos = .{ .x = 16, .y = 0 };
    if (spatial.graph.get_waypoint(quay_wp)) |_| spatial.graph.waypoints.items[quay_wp - 1].pos = .{ .x = 32, .y = 0 };

    try spatial.graph.connect(room4_wp, room7_wp, null);
    try spatial.graph.connect(room7_wp, stairs_wp, null);
    try spatial.graph.connect(yard_path_wp, gate_wp, null);
    try spatial.graph.connect(gate_wp, dog_wp, null);
    try spatial.graph.connect(office_door_wp, counter_wp, null);
    try spatial.graph.connect(counter_wp, quay_wp, null);

    // Register actors
    try spatial.register_entity(tamsin, room4_wp, 10);
    try spatial.register_entity(rook, room7_wp, 11);
    try spatial.register_entity(bramble, dog_wp, 12);
    try spatial.register_entity(purser, counter_wp, 13);

    // Initial item entities (Tamsin starts with EMPTY inventory!)
    const carries_rel = try world.intern_relation("Carries", .set);
    const watering_can = try world.intern_entity("WateringCan");
    const sail_tape = try world.intern_entity("SailTape");
    const charcoal = try world.intern_entity("Charcoal");
    const honey = try world.intern_entity("HoneyPot");

    // Register Hotspots
    const rook_door = world.lookup_entity("RookDoor") orelse try world.intern_entity("RookDoor");
    const wash_stand = world.lookup_entity("WashStand") orelse try world.intern_entity("WashStand");
    const gate_gap = world.lookup_entity("GateGap") orelse try world.intern_entity("GateGap");
    const rain_barrel = world.lookup_entity("RainBarrel") orelse try world.intern_entity("RainBarrel");
    const berth_counter = world.lookup_entity("BerthCounter") orelse try world.intern_entity("BerthCounter");
    const packet_boat = world.lookup_entity("PacketBoat") orelse try world.intern_entity("PacketBoat");

    try spatial.add_hotspot(rook_door, inn_scene, .{ .x = 16, .y = -6 }, 8, "Rook's Door", "Room 7. Rook's coat is hanging on the door peg.");
    try spatial.add_hotspot(wash_stand, inn_scene, .{ .x = 0, .y = -6 }, 8, "Washstand", "A washstand holding a charcoal stick, a roll of sail tape, and a pot of honey.");
    try spatial.add_hotspot(gate_gap, yard_scene, .{ .x = 18, .y = -4 }, 8, "Gate Gap", "A low gap under the net-loft gate, just big enough for a dog.");
    try spatial.add_hotspot(rain_barrel, yard_scene, .{ .x = 34, .y = -4 }, 8, "Rain Barrel", "A rain barrel by the net pile, where Bramble likes to nap.");
    try spatial.add_hotspot(berth_counter, office_scene, .{ .x = 16, .y = -6 }, 8, "Berth Counter", "Purser Wick's counter, piled with tide tables and berth tickets.");
    try spatial.add_hotspot(packet_boat, office_scene, .{ .x = 32, .y = -6 }, 10, "Packet Boat", "The packet boat to Greyhaven. Its last berth is held for Captain Rook.");

    // VM
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(inn_scene);

    if (compiled.routine_entries.get("RookPacing")) |entry| {
        _ = try vm.spawn_routine(rook, entry);
    }
    if (compiled.routine_entries.get("DogNapping")) |entry| {
        _ = try vm.spawn_routine(bramble, entry);
    }

    try writer.print("[Step 1: Inspect Initial State]\n", .{});
    try writer.print("   -> Current Scene: Inn Landing\n", .{});
    try writer.print("   -> Tamsin Inventory Empty? {s}\n", .{if (!world.has_fact(tamsin, carries_rel, charcoal.to_int())) "YES (Empty)" else "NO"});
    try writer.print("   -> Tamsin Disguised? {s}\n", .{if (evaluate_disguise(&world)) "YES" else "NO"});
    try writer.print("   -> Has the Berth Ticket? {s}\n\n", .{if (evaluate_puzzle_victory(&world)) "YES" else "NO"});
    try std.testing.expect(!world.has_fact(tamsin, carries_rel, charcoal.to_int()));
    try std.testing.expect(!world.has_fact(tamsin, carries_rel, watering_can.to_int()));

    // Step 2: Step ticks to observe CaptainRook pacing
    try writer.print("[Step 2: Simulate Ambient Routines]\n", .{});
    var tick: usize = 0;
    while (tick < 5) : (tick += 1) {
        try vm.step_tick();
    }
    try writer.print("   -> Advanced to Tick 5: Captain Rook is pacing between Room 7 and the stairs.\n\n", .{});

    // Save snapshot 0 for time-travel rewind verification
    var snapshot_start = std.ArrayList(u8).init(allocator);
    defer snapshot_start.deinit();
    try world.save_state(snapshot_start.writer());

    // Step 3: Search the washstand for supplies (Charcoal, SailTape, HoneyPot)
    try writer.print("[Step 3: Search the Washstand for Supplies]\n", .{});
    var speech_buf: [512]u8 = undefined;
    const desk_speech = try scripted_action(&world, &vm, &compiled, "Uses", tamsin, wash_stand, null, 1, &speech_buf);
    try writer.print("   -> {s}\n\n", .{desk_speech orelse "Tamsin searched the washstand."});
    try std.testing.expect(world.has_fact(tamsin, carries_rel, charcoal.to_int()));
    try std.testing.expect(world.has_fact(tamsin, carries_rel, sail_tape.to_int()));
    try std.testing.expect(world.has_fact(tamsin, carries_rel, honey.to_int()));

    // Step 4: Borrow Rook's sailing papers
    try writer.print("[Step 4: Borrow Rook's Sailing Papers from Room 7]\n", .{});
    const papers_ent = try world.intern_entity("RookPapers");
    const papers_speech = try scripted_action(&world, &vm, &compiled, "Uses", tamsin, rook_door, null, 1, &speech_buf);
    try writer.print("   -> {s}\n\n", .{papers_speech orelse "Tamsin acquired RookPapers."});
    try std.testing.expect(world.has_fact(tamsin, carries_rel, papers_ent.to_int()));

    // Step 5: Draw a beard on Rook's portrait with charcoal
    try writer.print("[Step 5: Draw a Beard on Rook's Portrait with Charcoal]\n", .{});
    const papers_marked_rel = try world.intern_relation("PapersMarked", .property);
    const papers_marked_speech = try scripted_action(&world, &vm, &compiled, "Uses", tamsin, charcoal, papers_ent, 1, &speech_buf);
    try writer.print("   -> {s}\n\n", .{papers_marked_speech orelse "Rook's portrait now has a charcoal beard."});
    try std.testing.expect(world.has_fact(tamsin, papers_marked_rel, null));

    // Step 6: Transition to Net Loft Yard
    try writer.print("[Step 6: Transition Scene to Net Loft Yard]\n", .{});
    try vm.transition_to_scene(yard_scene);
    _ = try spatial.transition_actor(tamsin, yard_scene, yard_path_wp);
    try writer.print("   -> Tamsin stepped into the net loft yard.\n\n", .{});

    // Step 7: Take the watering can by the rain barrel
    try writer.print("[Step 7: Take the Watering Can by the Rain Barrel]\n", .{});
    const barrel_speech = try scripted_action(&world, &vm, &compiled, "Uses", tamsin, rain_barrel, null, 1, &speech_buf);
    try writer.print("   -> {s}\n\n", .{barrel_speech orelse "Tamsin acquired WateringCan."});
    try std.testing.expect(world.has_fact(tamsin, carries_rel, watering_can.to_int()));

    // Step 8: Tape the gap under the gate with SailTape
    try writer.print("[Step 8: Stretch Sail Tape Across the Gate Gap]\n", .{});
    // State syntax stores the state value (`taped`), not the declaration label (`Taped`).
    const taped_rel = try world.intern_relation("taped", .set);
    const tape_speech = try scripted_action(&world, &vm, &compiled, "Uses", tamsin, sail_tape, gate_gap, 1, &speech_buf);
    try writer.print("   -> {s}\n\n", .{tape_speech orelse "GateGap is now taped."});
    try std.testing.expect(world.has_fact(gate_gap, taped_rel, null));

    // Step 9: Soak Bramble with the WateringCan
    try writer.print("[Step 9: Soak Bramble with the Watering Can]\n", .{});
    const startled_rel = try world.intern_relation("startled", .set);
    const gap_fur_rel = try world.intern_relation("GapHasFur", .property);
    const dog_speech = try scripted_action(&world, &vm, &compiled, "Uses", tamsin, watering_can, bramble, 8, &speech_buf);
    try writer.print("   -> {s}\n\n", .{dog_speech orelse "The dog bolted under the gate."});
    try std.testing.expect(world.has_fact(bramble, startled_rel, null));
    try std.testing.expect(world.has_fact(gate_gap, gap_fur_rel, null));

    // Step 10: Collect DogFur from GateGap
    try writer.print("[Step 10: Peel the Dog Fur from the Tape]\n", .{});
    const dog_fur_ent = try world.intern_entity("DogFur");
    const hair_speech = try scripted_action(&world, &vm, &compiled, "Uses", tamsin, gate_gap, null, 1, &speech_buf);
    try writer.print("   -> {s}\n\n", .{hair_speech orelse "Tamsin acquired DogFur."});
    try std.testing.expect(world.has_fact(tamsin, carries_rel, dog_fur_ent.to_int()));
    try std.testing.expect(!world.has_fact(gate_gap, gap_fur_rel, null));
    try std.testing.expect(!world.has_fact(gate_gap, taped_rel, null));

    // Step 11: Combine DogFur with Breakfast HoneyPot to craft GreyBeard
    try writer.print("[Step 11: Make a Grey Beard with the Honey]\n", .{});
    const beard_ent = try world.intern_entity("GreyBeard");
    const sticky_lip_rel = try world.intern_relation("StickyChin", .property);
    const beard_speech = try scripted_action(&world, &vm, &compiled, "Uses", tamsin, dog_fur_ent, honey, 1, &speech_buf);
    try writer.print("   -> {s}\n\n", .{beard_speech orelse "Tamsin crafted GreyBeard."});
    try std.testing.expect(world.has_fact(tamsin, carries_rel, beard_ent.to_int()));
    try std.testing.expect(world.has_fact(tamsin, sticky_lip_rel, null));

    // Step 12: Put on GreyBeard and disguise as CaptainRook
    try writer.print("[Step 12: Don the Disguise]\n", .{});
    const disguised_rel = try world.intern_relation("Disguised", .property);
    const disguise_speech = try scripted_action(&world, &vm, &compiled, "Uses", tamsin, beard_ent, tamsin, 1, &speech_buf);
    try writer.print("   -> {s}\n", .{disguise_speech orelse "Tamsin dons the disguise."});
    try std.testing.expect(world.has_fact(tamsin, disguised_rel, null));
    try writer.print("   -> Tamsin is now DISGUISED as Captain Ansel Rook!\n", .{});
    try writer.print("   -> Evaluate Disguise: {s}\n\n", .{if (evaluate_disguise(&world)) "VALID DISGUISE" else "INVALID"});

    // Step 13: Transition to Harbour Office
    try writer.print("[Step 13: Transition to Harbour Office]\n", .{});
    try vm.transition_to_scene(office_scene);
    _ = try spatial.transition_actor(tamsin, office_scene, office_door_wp);
    try writer.print("   -> Tamsin entered the Harbour Office.\n\n", .{});

    // Step 14: Test relational dialogue choice pruning with Purser Wick
    try writer.print("[Step 14: Dialogue Choice Pruning with Purser Wick]\n", .{});
    const disguised_arg = [_][]const u8{"Tamsin"};
    const empty_body: []const bespoke.compiler.parser.Stmt = &[_]bespoke.compiler.parser.Stmt{};

    const purser_choices = [_]bespoke.compiler.parser.DialogueChoice{
        .{
            .text = "I'd like a berth on the packet boat.",
            .guard = .{ .not_fact = .{ .relation = "Disguised", .args = &disguised_arg } },
            .body = empty_body,
        },
        .{
            .text = "I am Captain Ansel Rook. I've come for my berth.",
            .guard = .{ .has_fact = .{ .relation = "Disguised", .args = &disguised_arg } },
            .body = empty_body,
        },
        .{
            .text = "Whose dog is that in the yard?",
            .guard = null,
            .body = empty_body,
        },
        .{
            .text = "Good day.",
            .guard = null,
            .body = empty_body,
        },
    };

    var pruned_choices: [8]bespoke.vm.PrunedChoice = undefined;
    const choice_count = vm.prune_dialogue_choices(&purser_choices, &pruned_choices);

    try writer.print("   -> Active Dialogue Choices Presented by Purser Wick ({d} available):\n", .{choice_count});
    var ci: usize = 0;
    while (ci < choice_count) : (ci += 1) {
        try writer.print("      [{d}] \"{s}\"\n", .{ ci + 1, pruned_choices[ci].text });
    }

    // Choice 0 is the CaptainRook impersonation branch
    try std.testing.expectEqualStrings("I am Captain Ansel Rook. I've come for my berth.", pruned_choices[0].text);
    try writer.print("   -> Tamsin selects Choice 1!\n", .{});

    const has_ticket_rel = try world.intern_relation("HasBerthTicket", .property);
    const purser_speech = try scripted_action(&world, &vm, &compiled, "TalksTo", tamsin, purser, null, 4, &speech_buf);
    try writer.print("   -> {s}\n", .{purser_speech orelse "Purser Wick hands Tamsin the berth ticket."});
    try std.testing.expect(world.has_fact(tamsin, has_ticket_rel, null));
    try writer.print("   -> Has the Berth Ticket? {s}\n", .{if (evaluate_puzzle_victory(&world)) "YES! PUZZLE SOLVED!" else "NO"});
    try std.testing.expect(evaluate_puzzle_victory(&world));
    try writer.print("\n", .{});

    // Step 15: Time-Travel Rewind Demo
    try writer.print("[Step 15: Time-Travel Rewind Demo]\n", .{});
    try writer.print("   -> Rewinding simulation state back to Step 2 (inn landing, undisguised, empty inventory)...\n", .{});
    var stream = std.io.fixedBufferStream(snapshot_start.items);
    try world.restore_state(stream.reader());

    try writer.print("   -> Rewound Tamsin Disguised? {s}\n", .{if (evaluate_disguise(&world)) "YES" else "NO (Restored to false!)"});
    try writer.print("   -> Rewound Has the Berth Ticket? {s}\n", .{if (evaluate_puzzle_victory(&world)) "YES" else "NO (Restored to false!)"});
    try writer.print("   -> Rewound Tamsin Has Charcoal? {s}\n", .{if (world.has_fact(tamsin, carries_rel, charcoal.to_int())) "YES" else "NO (Restored to empty!)"});
    try std.testing.expect(!evaluate_disguise(&world));
    try std.testing.expect(!evaluate_puzzle_victory(&world));
    try std.testing.expect(!world.has_fact(tamsin, carries_rel, charcoal.to_int()));
    try std.testing.expect(!world.has_fact(tamsin, carries_rel, watering_can.to_int()));

    try writer.print("\n===================================================================\n", .{});
    try writer.print("          The Borrowed Beard Vertical Slice Succeeded!              \n", .{});
    try writer.print("===================================================================\n", .{});
}

/// Executes interactive 60 Hz simulation with graphical display (P14-03, D-016).
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, BORROWED_BEARD_SCRIPT);
    defer compiled.deinit();

    const inn_scene = world.lookup_entity("Inn Landing").?;
    const yard_scene = world.lookup_entity("Net Loft Yard").?;
    const office_scene = world.lookup_entity("Harbour Office").?;

    const tamsin = world.lookup_entity("Tamsin").?;
    const rook = world.lookup_entity("CaptainRook").?;
    const bramble = world.lookup_entity("Bramble").?;
    const purser = world.lookup_entity("PurserWick").?;

    const room4_wp = spatial.graph.find_waypoint_in_room(inn_scene, "Room4") orelse 1;
    const room7_wp = spatial.graph.find_waypoint_in_room(inn_scene, "Room7") orelse 2;
    const stairs_wp = spatial.graph.find_waypoint_in_room(inn_scene, "Stairs") orelse
        try spatial.graph.add_waypoint(inn_scene, 32, 0, "Stairs");

    const yard_path_wp = spatial.graph.find_waypoint_in_room(yard_scene, "YardPath") orelse
        try spatial.graph.add_waypoint(yard_scene, 0, 0, "YardPath");
    const gate_wp = spatial.graph.find_waypoint_in_room(yard_scene, "GateMark") orelse
        try spatial.graph.add_waypoint(yard_scene, 18, 0, "GateMark");
    const dog_wp = spatial.graph.find_waypoint_in_room(yard_scene, "DogBed") orelse
        try spatial.graph.add_waypoint(yard_scene, 34, 0, "DogBed");

    const office_door_wp = spatial.graph.find_waypoint_in_room(office_scene, "OfficeDoor") orelse
        try spatial.graph.add_waypoint(office_scene, 0, 0, "OfficeDoor");
    const counter_wp = spatial.graph.find_waypoint_in_room(office_scene, "CounterMark") orelse
        try spatial.graph.add_waypoint(office_scene, 16, 0, "CounterMark");
    const quay_wp = spatial.graph.find_waypoint_in_room(office_scene, "Quay") orelse
        try spatial.graph.add_waypoint(office_scene, 32, 0, "Quay");

    // Position waypoints (calibrated for 1280x720 standardized layout)
    if (spatial.graph.get_waypoint(room4_wp)) |_| spatial.graph.waypoints.items[room4_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(room7_wp)) |_| spatial.graph.waypoints.items[room7_wp - 1].pos = .{ .x = 16, .y = 0 };
    if (spatial.graph.get_waypoint(stairs_wp)) |_| spatial.graph.waypoints.items[stairs_wp - 1].pos = .{ .x = 32, .y = 0 };

    if (spatial.graph.get_waypoint(yard_path_wp)) |_| spatial.graph.waypoints.items[yard_path_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(gate_wp)) |_| spatial.graph.waypoints.items[gate_wp - 1].pos = .{ .x = 18, .y = 0 };
    if (spatial.graph.get_waypoint(dog_wp)) |_| spatial.graph.waypoints.items[dog_wp - 1].pos = .{ .x = 34, .y = 0 };

    if (spatial.graph.get_waypoint(office_door_wp)) |_| spatial.graph.waypoints.items[office_door_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(counter_wp)) |_| spatial.graph.waypoints.items[counter_wp - 1].pos = .{ .x = 16, .y = 0 };
    if (spatial.graph.get_waypoint(quay_wp)) |_| spatial.graph.waypoints.items[quay_wp - 1].pos = .{ .x = 32, .y = 0 };

    try spatial.graph.connect(room4_wp, room7_wp, null);
    try spatial.graph.connect(room7_wp, stairs_wp, null);
    try spatial.graph.connect(yard_path_wp, gate_wp, null);
    try spatial.graph.connect(gate_wp, dog_wp, null);
    try spatial.graph.connect(office_door_wp, counter_wp, null);
    try spatial.graph.connect(counter_wp, quay_wp, null);

    try spatial.register_entity(tamsin, room4_wp, 10);
    try spatial.register_entity(rook, room7_wp, 11);
    try spatial.register_entity(bramble, dog_wp, 12);
    try spatial.register_entity(purser, counter_wp, 13);

    // Initial inventory for Tamsin (starts empty; gather from the washstand and rain barrel)
    const carries_rel = try world.intern_relation("Carries", .set);
    const watering_can = try world.intern_entity("WateringCan");
    const sail_tape = try world.intern_entity("SailTape");
    const charcoal = try world.intern_entity("Charcoal");
    const honey = try world.intern_entity("HoneyPot");

    const rook_door = world.lookup_entity("RookDoor") orelse try world.intern_entity("RookDoor");
    const wash_stand = world.lookup_entity("WashStand") orelse try world.intern_entity("WashStand");
    const gate_gap = world.lookup_entity("GateGap") orelse try world.intern_entity("GateGap");
    const rain_barrel = world.lookup_entity("RainBarrel") orelse try world.intern_entity("RainBarrel");
    const berth_counter = world.lookup_entity("BerthCounter") orelse try world.intern_entity("BerthCounter");
    const packet_boat = world.lookup_entity("PacketBoat") orelse try world.intern_entity("PacketBoat");

    try spatial.add_hotspot(rook_door, inn_scene, .{ .x = 16, .y = -6 }, 8, "Rook's Door", "Room 7. Rook's coat is hanging on the door peg.");
    try spatial.add_hotspot(wash_stand, inn_scene, .{ .x = 0, .y = -6 }, 8, "Washstand", "A washstand holding a charcoal stick, a roll of sail tape, and a pot of honey.");
    try spatial.add_hotspot(gate_gap, yard_scene, .{ .x = 18, .y = -4 }, 8, "Gate Gap", "A low gap under the net-loft gate, just big enough for a dog.");
    try spatial.add_hotspot(rain_barrel, yard_scene, .{ .x = 34, .y = -4 }, 8, "Rain Barrel", "A rain barrel by the net pile, where Bramble likes to nap.");
    try spatial.add_hotspot(berth_counter, office_scene, .{ .x = 16, .y = -6 }, 8, "Berth Counter", "Purser Wick's counter, piled with tide tables and berth tickets.");
    try spatial.add_hotspot(packet_boat, office_scene, .{ .x = 32, .y = -6 }, 10, "Packet Boat", "The packet boat to Greyhaven. Its last berth is held for Captain Rook.");

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(inn_scene);

    if (compiled.routine_entries.get("RookPacing")) |entry| {
        _ = try vm.spawn_routine(rook, entry);
    }
    if (compiled.routine_entries.get("DogNapping")) |entry| {
        _ = try vm.spawn_routine(bramble, entry);
    }

    var display_bridge = bespoke.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("Tamsin")) |player| display_bridge.set_active_character(player);
    const repl_instance = bespoke.Repl.init(&world, &spatial, &vm);
    _ = repl_instance;

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Borrowed Beard", 1280, 720);
    defer window.deinit();
    window.set_theme(&beard_theme);

    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
    try stdout.print("The Borrowed Beard Controls:\n", .{});
    try stdout.print("   - [I]:                   Go to the Inn Landing\n", .{});
    try stdout.print("   - [Y]:                   Go to the Net Loft Yard\n", .{});
    try stdout.print("   - [O]:                   Go to the Harbour Office\n", .{});
    try stdout.print("   - [0]:                   [Dev Quick-Fill] Gather washstand & rain barrel supplies\n", .{});
    try stdout.print("   - [1]:                   Borrow Rook's Sailing Papers from Room 7\n", .{});
    try stdout.print("   - [2]:                   Draw a Beard on Rook's Portrait with Charcoal\n", .{});
    try stdout.print("   - [3]:                   Tape the Gap under the Gate\n", .{});
    try stdout.print("   - [4]:                   Soak the Dog with the Watering Can\n", .{});
    try stdout.print("   - [5]:                   Peel the Dog Fur from the Tape\n", .{});
    try stdout.print("   - [6]:                   Make a Grey Beard with the Honey\n", .{});
    try stdout.print("   - [7]:                   Put on the Disguise (Grey Beard + Marked Papers)\n", .{});
    try stdout.print("   - [8]:                   Talk to Purser Wick & Claim the Berth\n", .{});
    try stdout.print("   - [Timeline Scrubber]:   Click or drag timeline bar (or [< / >] arrows)\n", .{});
    try stdout.print("   - [F1 / D]:              Toggle Debug Relational Fact & Fiber Overlay\n", .{});
    try stdout.print("   - [Tab / ` / C]:         Toggle Live REPL Console Drawer\n", .{});
    try stdout.print("   - [Space]:               Pause / Resume Simulation Clock\n", .{});
    try stdout.print("   - [N]:                   Single-step Simulation Tick\n", .{});
    try stdout.print("   - [R]:                   Instant Time-Travel Rewind\n", .{});
    try stdout.print("   - [Esc / Close]:         Exit\n\n", .{});

    display_bridge.attach_audio_bridge(window.audio_bridge);
    var session = try bespoke.host.Session.init(allocator, &world, &spatial, &vm, &compiled, &display_bridge, &window);
    defer session.deinit();

    window.set_cue_banner("Brackwater: Search the washstand & rain barrel for items! [I/Y/O] Scenes [0-8] Steps", 180);

    const papers_ent = try world.intern_entity("RookPapers");
    const taped_rel = try world.intern_relation("taped", .set);
    const gap_fur_rel = try world.intern_relation("GapHasFur", .property);
    const dog_fur_ent = try world.intern_entity("DogFur");
    const beard_ent = try world.intern_entity("GreyBeard");

    while (true) {
        const action = window.poll_events(session.frame());

        // Pause, step, scrub, rewind, and save actions are shared (host kit, P32-16, D-033).
        if (try session.handle_common(action)) {} else switch (action) {
            .quit => break,
            .walk_player => |wp_id| {
                _ = try spatial.walk_to(tamsin, wp_id);
                if (wp_id == stairs_wp and vm.current_scene == inn_scene) {
                    try vm.transition_to_scene(yard_scene);
                    _ = try spatial.transition_actor(tamsin, yard_scene, yard_path_wp);
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                    window.set_cue_banner("Stepped outside into the Net Loft Yard. [I] Inn [O] Office", 120);
                } else if (wp_id == yard_path_wp and vm.current_scene == yard_scene) {
                    try vm.transition_to_scene(inn_scene);
                    _ = try spatial.transition_actor(tamsin, inn_scene, stairs_wp);
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                    window.set_cue_banner("Returned inside to the Inn Landing. [Y] Yard [O] Office", 120);
                } else if (wp_id == office_door_wp and vm.current_scene == office_scene) {
                    try vm.transition_to_scene(yard_scene);
                    _ = try spatial.transition_actor(tamsin, yard_scene, gate_wp);
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                    window.set_cue_banner("Stepped back into the Net Loft Yard. [I] Inn [O] Office", 120);
                } else {
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                    window.set_cue_banner("Directing Tamsin to waypoint.", 60);
                }
            },
            .combine_inventory_items => |comb| {
                const frame = display_bridge.get_frame();
                if (comb.primary_index < frame.inventory_count and comb.secondary_index < frame.inventory_count) {
                    const item_a = frame.inventory[comb.primary_index].get_name();
                    const item_b = frame.inventory[comb.secondary_index].get_name();

                    if ((std.mem.eql(u8, item_a, "Charcoal") and std.mem.eql(u8, item_b, "RookPapers")) or
                        (std.mem.eql(u8, item_a, "RookPapers") and std.mem.eql(u8, item_b, "Charcoal")))
                    {
                        try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, charcoal, papers_ent, 1);
                        window.set_cue_banner("★ Step 2: Drew a bushy beard on Rook's portrait! ★", 150);
                    } else if ((std.mem.eql(u8, item_a, "HoneyPot") and std.mem.eql(u8, item_b, "DogFur")) or
                        (std.mem.eql(u8, item_a, "DogFur") and std.mem.eql(u8, item_b, "HoneyPot")))
                    {
                        try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, dog_fur_ent, honey, 1);
                        window.set_cue_banner("★ Step 6: Stuck the fur on with honey: a fine grey beard! ★", 150);
                    } else {
                        var buf: [96]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "You can't combine {s} with {s}.", .{ item_a, item_b }) catch "Can't combine";
                        window.set_cue_banner(msg, 90);
                    }
                }
            },
            .use_inventory_on_actor => |act| {
                const frame = display_bridge.get_frame();
                if (act.item_index < frame.inventory_count and act.actor_index < frame.entity_count) {
                    const item_name = frame.inventory[act.item_index].get_name();
                    const actor_name = frame.entities[act.actor_index].get_name();

                    if (std.mem.eql(u8, item_name, "WateringCan") and std.mem.eql(u8, actor_name, "Bramble")) {
                        if (world.has_fact(gate_gap, taped_rel, null)) {
                            try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, watering_can, bramble, 8);
                            window.set_cue_banner("★ Step 4: SPLASH! Bramble bolted under the gate! Fur left on the tape! ★", 180);
                        } else {
                            window.set_cue_banner("Tamsin: \"Soaking the dog now won't help; the gap isn't taped!\"", 120);
                        }
                    } else if (std.mem.eql(u8, item_name, "GreyBeard") and std.mem.eql(u8, actor_name, "Tamsin")) {
                        if (world.has_fact(tamsin, world.lookup_relation("PapersMarked").?, null)) {
                            try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, beard_ent, tamsin, 1);
                            window.set_cue_banner("★ Step 7: Tamsin is now fully DISGUISED as Captain Rook! ★", 180);
                        } else {
                            window.set_cue_banner("Tamsin: \"The beard's on, but Rook's portrait is still clean-shaven!\"", 120);
                        }
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

                    if (std.mem.eql(u8, item_name, "SailTape") and std.mem.indexOf(u8, hs_name, "Gap") != null) {
                        try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, sail_tape, gate_gap, 1);
                        window.set_cue_banner("★ Step 3: Stretched sail tape across the gap under the gate! ★", 150);
                    } else if (std.mem.indexOf(u8, hs_name, "Door") != null) {
                        if (!world.has_fact(tamsin, carries_rel, papers_ent.to_int())) {
                            try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rook_door, null, 1);
                            window.set_cue_banner("★ Step 1: Borrowed Rook's sailing papers from his coat! ★", 150);
                        } else {
                            window.set_cue_banner("Tamsin: \"I already have Rook's papers.\"", 90);
                        }
                    } else {
                        var buf: [96]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "Using {s} on {s} has no effect.", .{ item_name, hs_name }) catch "No effect";
                        window.set_cue_banner(msg, 90);
                    }
                }
            },
            .examine_hotspot => |hs_idx| {
                const frame = display_bridge.get_frame();
                if (hs_idx < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_idx];
                    const hname = hs.get_name();
                    if (std.mem.indexOf(u8, hname, "Washstand") != null) {
                        if (!world.has_fact(tamsin, carries_rel, charcoal.to_int())) {
                            window.set_cue_banner("Washstand: A charcoal stick, a roll of sail tape, and a pot of honey.", 150);
                        } else {
                            window.set_cue_banner("Washstand: Cleared out. Nothing else useful here.", 120);
                        }
                    } else if (std.mem.indexOf(u8, hname, "Barrel") != null) {
                        if (!world.has_fact(tamsin, carries_rel, watering_can.to_int())) {
                            window.set_cue_banner("Rain Barrel: A watering can stands beside it, half full.", 150);
                        } else {
                            window.set_cue_banner("Rain Barrel: Full to the brim. Bramble is napping nearby.", 120);
                        }
                    } else if (std.mem.indexOf(u8, hname, "Door") != null) {
                        if (!world.has_fact(tamsin, carries_rel, papers_ent.to_int())) {
                            window.set_cue_banner("Room 7: Rook's room. His sailing papers are poking out of his coat!", 150);
                        } else {
                            window.set_cue_banner("Room 7: Rook's room. You've already borrowed his papers.", 120);
                        }
                    } else if (std.mem.indexOf(u8, hname, "Gap") != null) {
                        if (world.has_fact(gate_gap, gap_fur_rel, null)) {
                            window.set_cue_banner("Gate Gap: Thick grey dog fur is stuck to the sail tape!", 150);
                        } else if (world.has_fact(gate_gap, taped_rel, null)) {
                            window.set_cue_banner("Gate Gap: Sail tape is stretched across the gap.", 120);
                        } else {
                            window.set_cue_banner("Gate Gap: A low gap under the net-loft gate.", 120);
                        }
                    } else if (std.mem.indexOf(u8, hname, "Packet Boat") != null) {
                        window.set_cue_banner("Packet Boat: Bound for Greyhaven. The last berth is held for Captain Rook.", 120);
                    } else if (std.mem.indexOf(u8, hname, "Counter") != null or std.mem.indexOf(u8, hname, "Berth") != null) {
                        window.set_cue_banner("Berth Counter: Purser Wick's counter, piled with tide tables and tickets.", 120);
                    } else {
                        var buf: [256]u8 = undefined;
                        const text = std.fmt.bufPrint(&buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Hotspot";
                        window.set_cue_banner(text, 120);
                    }
                }
            },
            .interact_actor => |act| {
                const frame = display_bridge.get_frame();
                if (act.actor_index < frame.entity_count) {
                    const target_entity = frame.entities[act.actor_index];
                    const tname = target_entity.get_name();

                    if (act.verb == .look_at) {
                        if (std.mem.eql(u8, tname, "PurserWick")) {
                            window.set_cue_banner("Purser Wick: Keeper of the packet boat's berths.", 120);
                        } else if (std.mem.eql(u8, tname, "CaptainRook")) {
                            window.set_cue_banner("Captain Rook: Captain Ansel Rook, pacing the landing and stroking his grey beard.", 120);
                        } else if (std.mem.eql(u8, tname, "Bramble")) {
                            window.set_cue_banner("Bramble: A shaggy grey dog dozing by the rain barrel.", 120);
                        } else {
                            window.set_cue_banner("Tamsin: Duellist, fair champion, and now a would-be sea captain.", 120);
                        }
                    } else if (act.verb == .talk_to or act.verb == .use_with) {
                        if (std.mem.eql(u8, tname, "PurserWick")) {
                            // The script owns the line, the pruned options, and the outcome
                            // (P32-30); the host supplies the intent to talk and who is shown
                            // as speaking. The set itself is keyed by the fiber's owner.
                            try vm.set_dialogue_speaker(tamsin, purser);
                            _ = try vm.fire_cue(&compiled, "TalksTo", tamsin, purser, null);
                        } else if (std.mem.eql(u8, tname, "CaptainRook")) {
                            window.set_cue_banner("Captain Rook: \"Mind the stairs, girl. Some of us have a boat to catch.\"", 90);
                        } else if (std.mem.eql(u8, tname, "Bramble")) {
                            window.set_cue_banner("Bramble: \"Wuff! (The dog thumps its tail at you.)\"", 90);
                        } else {
                            window.set_cue_banner("Tamsin: Talking to myself won't get me on that boat.", 90);
                        }
                    } else if (act.verb == .pick_up) {
                        if (std.mem.eql(u8, tname, "Bramble")) {
                            window.set_cue_banner("Bramble is far too heavy and far too wet to carry!", 120);
                        } else {
                            window.set_cue_banner("You can't pick up other people!", 90);
                        }
                    } else {
                        window.set_cue_banner("Directing Tamsin.", 60);
                    }
                }
            },
            .interact_hotspot => |hs_act| {
                const frame = display_bridge.get_frame();
                if (hs_act.hotspot_index < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_act.hotspot_index];
                    const hname = hs.get_name();

                    if (hs_act.verb == .look_at) {
                        // Look verb: Show examine description without looting
                        if (std.mem.indexOf(u8, hname, "Washstand") != null) {
                            if (!world.has_fact(tamsin, carries_rel, charcoal.to_int())) {
                                window.set_cue_banner("Washstand: A charcoal stick, a roll of sail tape, and a pot of honey.", 150);
                            } else {
                                window.set_cue_banner("Washstand: Cleared out. Nothing else useful here.", 120);
                            }
                        } else if (std.mem.indexOf(u8, hname, "Barrel") != null) {
                            if (!world.has_fact(tamsin, carries_rel, watering_can.to_int())) {
                                window.set_cue_banner("Rain Barrel: A watering can stands beside it, half full.", 150);
                            } else {
                                window.set_cue_banner("Rain Barrel: Full to the brim. Bramble is napping nearby.", 120);
                            }
                        } else if (std.mem.indexOf(u8, hname, "Door") != null) {
                            if (!world.has_fact(tamsin, carries_rel, papers_ent.to_int())) {
                                window.set_cue_banner("Room 7: Rook's room. His sailing papers are poking out of his coat!", 150);
                            } else {
                                window.set_cue_banner("Room 7: Rook's room. You've already borrowed his papers.", 120);
                            }
                        } else if (std.mem.indexOf(u8, hname, "Gap") != null) {
                            if (world.has_fact(gate_gap, gap_fur_rel, null)) {
                                window.set_cue_banner("Gate Gap: Thick grey dog fur is stuck to the sail tape!", 150);
                            } else if (world.has_fact(gate_gap, taped_rel, null)) {
                                window.set_cue_banner("Gate Gap: Sail tape is stretched across the gap.", 120);
                            } else {
                                window.set_cue_banner("Gate Gap: A low gap under the net-loft gate.", 120);
                            }
                        } else if (std.mem.indexOf(u8, hname, "Packet Boat") != null) {
                            window.set_cue_banner("Packet Boat: Bound for Greyhaven. The last berth is held for Captain Rook.", 120);
                        } else if (std.mem.indexOf(u8, hname, "Counter") != null or std.mem.indexOf(u8, hname, "Berth") != null) {
                            window.set_cue_banner("Berth Counter: Purser Wick's counter, piled with tide tables and tickets.", 120);
                        } else {
                            var buf: [256]u8 = undefined;
                            const text = std.fmt.bufPrint(&buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Hotspot";
                            window.set_cue_banner(text, 120);
                        }
                    } else if (hs_act.verb == .pick_up) {
                        // Take verb: gather items or collect the dog fur
                        if (std.mem.indexOf(u8, hname, "Washstand") != null) {
                            if (!world.has_fact(tamsin, carries_rel, charcoal.to_int())) {
                                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, wash_stand, null, 1);
                                window.set_cue_banner("★ Washstand: took the charcoal, sail tape, and honey! ★", 180);
                            } else {
                                window.set_cue_banner("Washstand: Cleared out. You already took the charcoal, tape, and honey.", 90);
                            }
                        } else if (std.mem.indexOf(u8, hname, "Door") != null) {
                            if (!world.has_fact(tamsin, carries_rel, papers_ent.to_int())) {
                                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rook_door, null, 1);
                                window.set_cue_banner("★ Slipped into Room 7 and borrowed Rook's papers! ★", 150);
                            } else {
                                window.set_cue_banner("Tamsin: \"I already borrowed Rook's papers.\"", 90);
                            }
                        } else if (std.mem.indexOf(u8, hname, "Barrel") != null) {
                            if (!world.has_fact(tamsin, carries_rel, watering_can.to_int())) {
                                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rain_barrel, null, 1);
                                window.set_cue_banner("★ Found a watering can by the rain barrel! ★", 180);
                            } else {
                                window.set_cue_banner("Rain Barrel: Full to the brim. Bramble is napping nearby.", 90);
                            }
                        } else if (std.mem.indexOf(u8, hname, "Gap") != null) {
                            if (world.has_fact(gate_gap, gap_fur_rel, null)) {
                                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, gate_gap, null, 1);
                                window.set_cue_banner("★ Peeled the dog fur off the tape! ★", 150);
                            } else if (world.has_fact(gate_gap, taped_rel, null)) {
                                window.set_cue_banner("Sail tape is stretched across the gap. Now to soak the dog!", 120);
                            } else {
                                window.set_cue_banner("You can't take a gap under a gate!", 90);
                            }
                        } else if (std.mem.indexOf(u8, hname, "Packet Boat") != null) {
                            if (evaluate_puzzle_victory(&world)) {
                                window.set_cue_banner("★ VICTORY! Tamsin sails for Greyhaven in Captain Rook's berth! ★", 180);
                            } else {
                                window.set_cue_banner("Purser Wick won't let you aboard without a berth ticket!", 120);
                            }
                        } else {
                            window.set_cue_banner("You can't pick that up.", 90);
                        }
                    } else if (hs_act.verb == .talk_to) {
                        window.set_cue_banner("You can't talk to that.", 90);
                    } else if (hs_act.verb == .use_with) {
                        if (std.mem.indexOf(u8, hname, "Washstand") != null) {
                            window.set_cue_banner("Use TAKE to gather items from the washstand.", 120);
                        } else if (std.mem.indexOf(u8, hname, "Barrel") != null) {
                            window.set_cue_banner("Use TAKE to collect the watering can by the barrel.", 120);
                        } else if (std.mem.indexOf(u8, hname, "Door") != null) {
                            window.set_cue_banner("Use TAKE to borrow Rook's papers from his coat.", 120);
                        } else {
                            window.set_cue_banner("Select an item from your inventory first to use on this.", 120);
                        }
                    } else {
                        window.set_cue_banner("Directing Tamsin to interact.", 60);
                    }
                }
            },
            .dialogue_choice => |choice_idx| {
                if (try session.choose_dialogue(choice_idx)) |_| {
                    var speech_buf: [256]u8 = undefined;
                    if (bespoke.host.speech_this_tick(&world, &vm, &speech_buf)) |speech| {
                        window.set_cue_banner(speech, 180);
                    }
                    if (evaluate_puzzle_victory(&world)) {
                        window.set_cue_banner("★ VICTORY! Purser Wick hands over the berth ticket! ★", 180);
                    }
                } else {
                    window.dismiss_dialogue();
                }
            },
            else => {},
        }

        // Immediately update frame buffer on interactive player action
        if (action != .none and action != .toggle_pause and action != .step_tick and action != .quit) {
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        // Check helper hotkeys
        // Bound keys arrive once per press as `UserAction.custom` (P32-02c); they used to be
        // polled every frame from SDL's keyboard state.
        const pressed: ?BeardKey = if (action == .custom) std.meta.intToEnum(BeardKey, action.custom) catch null else null;
        if (pressed != null) {
            var hotkey_handled = false;
            // [I] Inn Landing
            if (pressed == .inn) {
                try vm.transition_to_scene(inn_scene);
                _ = try spatial.transition_actor(tamsin, inn_scene, room4_wp);
                window.set_cue_banner("Switched Scene: Inn Landing", 60);
                hotkey_handled = true;
            }
            // [Y] Net Loft Yard
            if (pressed == .yard) {
                try vm.transition_to_scene(yard_scene);
                _ = try spatial.transition_actor(tamsin, yard_scene, yard_path_wp);
                window.set_cue_banner("Switched Scene: Net Loft Yard", 60);
                hotkey_handled = true;
            }
            // [O] Harbour Office
            if (pressed == .office) {
                try vm.transition_to_scene(office_scene);
                _ = try spatial.transition_actor(tamsin, office_scene, office_door_wp);
                window.set_cue_banner("Switched Scene: Harbour Office", 60);
                hotkey_handled = true;
            }
            // [0] Quick Scavenge Supplies (Dev Shortcut)
            if (pressed == .scavenge) {
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, wash_stand, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rain_barrel, null, 1);
                window.set_cue_banner("Dev Quick-Fill: Gathered the charcoal, sail tape, honey, and watering can!", 90);
                hotkey_handled = true;
            }
            // [1] Borrow the papers
            if (pressed == .step_1) {
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rook_door, null, 1);
                window.set_cue_banner("Step 1: Borrowed Rook's sailing papers from Room 7!", 90);
                hotkey_handled = true;
            }
            // [2] Draw a beard on the portrait
            if (pressed == .step_2) {
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, wash_stand, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rook_door, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, charcoal, papers_ent, 1);
                window.set_cue_banner("Step 2: Drew a beard on Rook's portrait!", 90);
                hotkey_handled = true;
            }
            // [3] Tape the gate gap
            if (pressed == .step_3) {
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, wash_stand, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, sail_tape, gate_gap, 1);
                window.set_cue_banner("Step 3: Stretched sail tape across the gap!", 90);
                hotkey_handled = true;
            }
            // [4] Soak the dog
            if (pressed == .step_4) {
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, wash_stand, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rain_barrel, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, sail_tape, gate_gap, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, watering_can, bramble, 8);
                window.set_cue_banner("Step 4: Soaked the dog! Fur left on the tape!", 90);
                hotkey_handled = true;
            }
            // [5] Collect the dog fur
            if (pressed == .step_5) {
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, wash_stand, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rain_barrel, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, sail_tape, gate_gap, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, watering_can, bramble, 8);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, gate_gap, null, 1);
                window.set_cue_banner("Step 5: Peeled the dog fur off the tape!", 90);
                hotkey_handled = true;
            }
            // [6] Make the grey beard with honey
            if (pressed == .step_6) {
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, wash_stand, null, 1);
                if (!world.has_fact(tamsin, carries_rel, dog_fur_ent.to_int())) {
                    try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rain_barrel, null, 1);
                    try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, sail_tape, gate_gap, 1);
                    try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, watering_can, bramble, 8);
                    try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, gate_gap, null, 1);
                }
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, dog_fur_ent, honey, 1);
                window.set_cue_banner("Step 6: Stuck the fur on with honey: a grey beard!", 90);
                hotkey_handled = true;
            }
            // [7] Don Disguise
            if (pressed == .step_7) {
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, wash_stand, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rook_door, null, 1);
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, charcoal, papers_ent, 1);
                if (!world.has_fact(tamsin, carries_rel, beard_ent.to_int())) {
                    try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, rain_barrel, null, 1);
                    try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, sail_tape, gate_gap, 1);
                    try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, watering_can, bramble, 8);
                    try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, gate_gap, null, 1);
                    try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, dog_fur_ent, honey, 1);
                }
                try session_scripted_action(&session, &vm, &compiled, "Uses", tamsin, beard_ent, tamsin, 1);
                window.set_cue_banner("Step 7: Tamsin is now fully DISGUISED as Captain Rook!", 90);
                hotkey_handled = true;
            }
            // [8] Talk to Purser Wick
            if (pressed == .step_8) {
                if (evaluate_disguise(&world)) {
                    try session_scripted_action(&session, &vm, &compiled, "TalksTo", tamsin, purser, null, 1);
                    window.set_cue_banner("★ Step 8 VICTORY: Purser Wick gave the berth ticket to \"Captain Rook\"! ★", 180);
                } else {
                    window.set_cue_banner("Step 8: Purser Wick turned Tamsin away! (Need the full disguise!)", 90);
                }
                hotkey_handled = true;
            }

            if (hotkey_handled) {
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.swap();
            }
        }

        if (session.tick_due()) {
            _ = try session.advance();
        }

        session.render();
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P14-01: The Borrowed Beard script compiles and lowers to bytecode" {
    const testing = std.testing;

    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, BORROWED_BEARD_SCRIPT);
    defer compiled.deinit();

    try testing.expect(world.lookup_entity("Tamsin") != null);
    try testing.expect(world.lookup_entity("CaptainRook") != null);
    try testing.expect(world.lookup_entity("Bramble") != null);
    try testing.expect(world.lookup_entity("PurserWick") != null);
    try testing.expect(world.lookup_entity("Inn Landing") != null);
    try testing.expect(world.lookup_entity("Net Loft Yard") != null);
    try testing.expect(world.lookup_entity("Harbour Office") != null);

    try testing.expect(compiled.chunk.count() > 0);
}

test "P14-03: The Borrowed Beard headless simulation executes and rewinds cleanly" {
    const testing = std.testing;
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    try run_headless(testing.allocator, list.writer());
    try testing.expect(list.items.len > 0);
}

test "P14-02: verify scene transition capture to the net loft yard" {
    const testing = std.testing;

    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, BORROWED_BEARD_SCRIPT);
    defer compiled.deinit();

    const inn_scene = world.lookup_entity("Inn Landing").?;
    const yard_scene = world.lookup_entity("Net Loft Yard").?;

    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(inn_scene);

    var display_bridge = bespoke.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("Tamsin")) |player| display_bridge.set_active_character(player);
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.swap();

    const f1 = display_bridge.get_frame();
    try testing.expectEqualStrings("Inn Landing", f1.get_current_scene());

    try vm.transition_to_scene(yard_scene);
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.swap();

    const f2 = display_bridge.get_frame();
    try testing.expectEqualStrings("Net Loft Yard", f2.get_current_scene());
}
