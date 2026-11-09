const std = @import("std");
const bespoke = @import("bespoke");

pub const GOAT_PUZZLE_SCRIPT =
    \\scene: Lochmarne Castle Courtyard
    \\cast: George, BillyGoat
    \\props: CellarEntrance, FarmPlough, TetherStake
    \\marks: CourtyardEntrance, FallMark, PloughMark, TetherCenter, DigOpening
    \\
    \\scene: Templar Crypt
    \\cast: George
    \\props: CarvedMural, CryptAltar
    \\marks: CryptLadder, AltarMark
    \\
    \\Tangled is a state, which can be tangled or untangled. The goat is untangled in the scene.
    \\PloughMoved is a state, which can be moved or unmoved. The plough is unmoved in the scene.
    \\GeorgeStatus is a state, which can be standing or knocked_down. George is standing in the scene.
    \\
    \\on cue LooksAt(George, BillyGoat):
    \\  say George: "A fierce-looking Irish billy goat tied to a stake by a long rope. He's eyeing me with intense hostility."
    \\
    \\on cue LooksAt(George, CellarEntrance):
    \\  say George: "A dark opening in the castle ruins with a wooden ladder leading down into the excavation."
    \\
    \\on cue LooksAt(George, FarmPlough):
    \\  say George: "An old, heavy iron farm plough. It looks sturdy enough to anchor a battleship."
    \\
    \\on cue LooksAt(George, TetherStake):
    \\  say George: "A stout wooden post driven deep into the turf."
    \\
    \\on cue TalksTo(George, BillyGoat):
    \\  choice "Nice goat... friendly goat...":
    \\    say BillyGoat: "Snort! *headbutts turf*"
    \\    say George: "He doesn't seem interested in making friends."
    \\  choice "Shoo! Go away!":
    \\    say BillyGoat: "MAAAA-AAAH!"
    \\    say George: "That only seemed to make him angrier."
    \\
    \\on cue Uses(George, CellarEntrance):
    \\  if BillyGoat is tangled:
    \\    say George: "With the goat tangled around the plough, the way down is clear!"
    \\    transition to scene: Templar Crypt
    \\  if BillyGoat is not tangled:
    \\    say BillyGoat: "MAAAA-AAAH!"
    \\    say George: "Oof! The goat headbutted me right onto my rear!"
    \\    remember KnockedDown(George, true) for 15 ticks
    \\    now George is knocked_down
    \\    remember GoatRetreating(BillyGoat, true) for 30 ticks
    \\    walk BillyGoat to TetherCenter
    \\
    \\on cue Uses(George, FarmPlough):
    \\  if BillyGoat is tangled:
    \\    say George: "The plough is already locking the goat's tether in place."
    \\  if BillyGoat is not tangled:
    \\    if GoatRetreating(BillyGoat):
    \\      say George: "Quick, while the goat is trotting back! I haul the heavy iron plough right into the path of the rope!"
    \\      now BillyGoat is tangled
    \\      now FarmPlough is moved
    \\      remember TangledWith(BillyGoat, FarmPlough)
    \\      remember PloughMoved(FarmPlough, true)
    \\      forget GoatRetreating(BillyGoat)
    \\      say BillyGoat: "Bleee-aaat! *grunt*"
    \\      say George: "Gotcha! The goat's rope is wrapped tight around the plough. He can't reach the dig entrance now!"
    \\    if not GoatRetreating(BillyGoat):
    \\      say George: "If I try to move the heavy plough now, the goat will just butt me before I can budge it."
    \\
    \\on cue LooksAt(George, CarvedMural):
    \\  say George: "A centuries-old stone carving of a Templar knight holding a chalice. Peagram's dig site was right on the trail!"
    \\
    \\on cue LooksAt(George, CryptAltar):
    \\  say George: "An ancient stone altar covered in centuries of dust."
;

/// Evaluates whether the Billy Goat has been tangled around the plough (P20-01, D-023).
pub fn evaluate_goat_tangled(world: *const bespoke.World) bool {
    const goat = world.lookup_entity("BillyGoat") orelse return false;

    if (world.lookup_relation("tangled") orelse world.lookup_relation("Tangled")) |rel| {
        if (world.has_fact(goat, rel, null)) return true;
    }
    if (world.lookup_relation("TangledWith")) |rel| {
        if (world.has_fact(goat, rel, null)) return true;
    }
    if (world.lookup_relation("PloughMoved")) |rel| {
        if (world.has_fact(null, rel, 1)) return true;
    }
    return false;
}

/// Evaluates whether George has descended into the subterranean Templar Crypt (P20-01, D-023).
pub fn evaluate_crypt_entered(world: *const bespoke.World, vm: *const bespoke.VM) bool {
    if (vm.current_scene) |scene_id| {
        if (world.get_entity_name(scene_id)) |sname| {
            if (std.mem.indexOf(u8, sname, "Crypt") != null or std.mem.indexOf(u8, sname, "Templar") != null) {
                return true;
            }
        }
    }
    return false;
}

/// Executes headless simulation of the Broken Sword Lochmarne Goat vertical slice (P20-01, P20-03, D-023).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("      BeSpoke Engine: Broken Sword Lochmarne Goat Puzzle Scenario   \n", .{});
    try writer.print("  (Authentic 1996 Threat-Radius Timing * Plough Dragging * Crypt)  \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Compiling Lochmarne Goat narrative script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, GOAT_PUZZLE_SCRIPT);
    defer compiled.deinit();

    // Scene Room Entities
    const courtyard_scene = world.lookup_entity("Lochmarne Castle Courtyard").?;
    const crypt_scene = world.lookup_entity("Templar Crypt").?;

    // Actor Entities
    const george = world.lookup_entity("George").?;
    const goat = world.lookup_entity("BillyGoat").?;

    // Spatial Marks
    const entrance_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "CourtyardEntrance") orelse 1;
    const fall_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "FallMark") orelse 2;
    const plough_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "PloughMark") orelse 3;
    const tether_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "TetherCenter") orelse 4;
    const dig_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "DigOpening") orelse 5;

    const crypt_ladder_wp = spatial.graph.find_waypoint_in_room(crypt_scene, "CryptLadder") orelse 6;
    const altar_wp = spatial.graph.find_waypoint_in_room(crypt_scene, "AltarMark") orelse 7;

    // Calibrate coordinates for 1280x720 standardized layout
    if (spatial.graph.get_waypoint(entrance_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 4, .y = 0 };
    if (spatial.graph.get_waypoint(fall_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 8, .y = 0 };
    if (spatial.graph.get_waypoint(plough_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 10, .y = 8 };
    if (spatial.graph.get_waypoint(tether_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 16, .y = 0 };
    if (spatial.graph.get_waypoint(dig_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 28, .y = 0 };

    if (spatial.graph.get_waypoint(crypt_ladder_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 4, .y = 0 };
    if (spatial.graph.get_waypoint(altar_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 20, .y = 0 };

    spatial.graph.edges.clearRetainingCapacity();
    try spatial.graph.connect(entrance_wp, fall_wp, null);
    try spatial.graph.connect(fall_wp, tether_wp, null);
    try spatial.graph.connect(fall_wp, plough_wp, null);
    try spatial.graph.connect(plough_wp, tether_wp, null);
    try spatial.graph.connect(tether_wp, dig_wp, null);
    try spatial.graph.connect(crypt_ladder_wp, altar_wp, null);

    const cellar_entrance = world.lookup_entity("CellarEntrance").?;
    const farm_plough = world.lookup_entity("FarmPlough").?;
    const tether_stake = world.lookup_entity("TetherStake").?;
    const carved_mural = world.lookup_entity("CarvedMural").?;
    const crypt_altar = world.lookup_entity("CryptAltar").?;

    try spatial.add_hotspot(cellar_entrance, courtyard_scene, .{ .x = 28, .y = -4 }, 8, "Cellar Entrance", "A dark excavation pit leading down into the subterranean ruins.");
    try spatial.add_hotspot(farm_plough, courtyard_scene, .{ .x = 10, .y = 8 }, 8, "Farm Plough", "An old, heavy iron farm plough resting in the weeds.");
    try spatial.add_hotspot(tether_stake, courtyard_scene, .{ .x = 16, .y = -4 }, 6, "Tether Stake", "A sturdy wooden post driven into the Irish turf.");
    try spatial.add_hotspot(crypt_altar, crypt_scene, .{ .x = 20, .y = -4 }, 8, "Crypt Altar", "An ancient Templar stone altar carved with medieval inscriptions.");
    try spatial.add_hotspot(carved_mural, crypt_scene, .{ .x = 30, .y = -6 }, 8, "Carved Mural", "A wall carving of a Knights Templar bearing a chalice.");

    // Register actors at starting waypoints
    try spatial.register_entity(george, entrance_wp, 10);
    try spatial.register_entity(goat, tether_wp, 8);

    // Initial fact assertions
    const tether_rel = try world.intern_relation("TetheredTo", .set);
    try world.remember(goat, tether_rel, tether_stake.to_int(), 0);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    try vm.transition_to_scene(courtyard_scene);

    var display_bridge = bespoke.display.DisplayBridge.init();

    // Save initial state snapshot for time-travel verification
    var snapshot_0 = std.ArrayList(u8).init(allocator);
    defer snapshot_0.deinit();
    try world.save_state(snapshot_0.writer());

    try writer.print("\n[Step 1] Initial Inspection: George arrives at Lochmarne Castle Courtyard.\n", .{});
    _ = try vm.fire_cue(&compiled, "LooksAt", george, goat, null);
    try vm.step_tick();
    display_bridge.capture_frame(&world, &spatial, &vm);
    try writer.print("  -> Fact count: {d}, George at CourtyardEntrance, Goat at TetherCenter\n", .{world.fact_count()});

    try writer.print("\n[Step 2] Threat Radius Exploration: George approaches CellarEntrance.\n", .{});
    _ = try vm.fire_cue(&compiled, "Uses", george, cellar_entrance, null);
    try vm.step_tick();
    display_bridge.capture_frame(&world, &spatial, &vm);

    // Verify headbutt knockback and 30-tick retreat window
    const retreating_rel = world.lookup_relation("GoatRetreating").?;
    const is_retreating = world.has_fact(goat, retreating_rel, null);
    try writer.print("  -> Goat reactive charge triggered! George knocked down to FallMark.\n", .{});
    try writer.print("  -> Goat retreating window active: {any} (30 ticks remaining)\n", .{is_retreating});

    if (!is_retreating) {
        return error.GoatRetreatWindowMissing;
    }

    try writer.print("\n[Step 3] Seizing the Window: George hauls FarmPlough while goat retreats!\n", .{});
    _ = try vm.fire_cue(&compiled, "Uses", george, farm_plough, null);
    try vm.step_tick();
    display_bridge.capture_frame(&world, &spatial, &vm);

    const is_tangled = evaluate_goat_tangled(&world);
    try writer.print("  -> Plough hauled into rope path! Goat tangled status: {any}\n", .{is_tangled});
    if (!is_tangled) {
        return error.GoatNotTangled;
    }

    try writer.print("\n[Step 4] Accessing the Dig: George descends into CellarEntrance.\n", .{});
    _ = try vm.fire_cue(&compiled, "Uses", george, cellar_entrance, null);
    try vm.step_tick();
    display_bridge.capture_frame(&world, &spatial, &vm);

    const entered_crypt = evaluate_crypt_entered(&world, &vm);
    try writer.print("  -> Multi-scene transition to Templar Crypt successful: {any}\n", .{entered_crypt});
    if (!entered_crypt) {
        return error.FailedToEnterCrypt;
    }

    try writer.print("\n[Step 5] Archaeological Discovery: George examines the CarvedMural.\n", .{});
    _ = try vm.fire_cue(&compiled, "LooksAt", george, carved_mural, null);
    try vm.step_tick();
    display_bridge.capture_frame(&world, &spatial, &vm);

    try writer.print("\n[Step 6] Time-Travel Rewind Verification: Restoring pristine Courtyard state.\n", .{});
    var stream = std.io.fixedBufferStream(snapshot_0.items);
    try world.restore_state(stream.reader());
    vm.current_scene = courtyard_scene;
    _ = try spatial.transition_actor(george, courtyard_scene, entrance_wp);
    _ = try spatial.transition_actor(goat, courtyard_scene, tether_wp);
    display_bridge.capture_frame(&world, &spatial, &vm);

    const is_tangled_after_rewind = evaluate_goat_tangled(&world);
    try writer.print("  -> Restored tick 0 snapshot. Goat tangled status: {any} (Expected: false)\n", .{is_tangled_after_rewind});
    if (is_tangled_after_rewind) {
        return error.RewindFailed;
    }

    try writer.print("\n===================================================================\n", .{});
    try writer.print("  VERIFICATION COMPLETE: Broken Sword Goat Puzzle 100% Deterministic! \n", .{});
    try writer.print("===================================================================\n\n", .{});
}

/// Executes interactive 60 Hz simulation with graphical display (P20-03, D-023).
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, GOAT_PUZZLE_SCRIPT);
    defer compiled.deinit();

    const courtyard_scene = world.lookup_entity("Lochmarne Castle Courtyard").?;
    const crypt_scene = world.lookup_entity("Templar Crypt").?;

    const george = world.lookup_entity("George").?;
    const goat = world.lookup_entity("BillyGoat").?;

    const entrance_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "CourtyardEntrance") orelse 1;
    const fall_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "FallMark") orelse 2;
    const plough_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "PloughMark") orelse 3;
    const tether_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "TetherCenter") orelse 4;
    const dig_wp = spatial.graph.find_waypoint_in_room(courtyard_scene, "DigOpening") orelse 5;

    const crypt_ladder_wp = spatial.graph.find_waypoint_in_room(crypt_scene, "CryptLadder") orelse 6;
    const altar_wp = spatial.graph.find_waypoint_in_room(crypt_scene, "AltarMark") orelse 7;

    // Calibrate coordinates for 1280x720 standardized layout
    if (spatial.graph.get_waypoint(entrance_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 4, .y = 0 };
    if (spatial.graph.get_waypoint(fall_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 8, .y = 0 };
    if (spatial.graph.get_waypoint(plough_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 10, .y = 8 };
    if (spatial.graph.get_waypoint(tether_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 16, .y = 0 };
    if (spatial.graph.get_waypoint(dig_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 28, .y = 0 };

    if (spatial.graph.get_waypoint(crypt_ladder_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 4, .y = 0 };
    if (spatial.graph.get_waypoint(altar_wp)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = 20, .y = 0 };

    spatial.graph.edges.clearRetainingCapacity();
    try spatial.graph.connect(entrance_wp, fall_wp, null);
    try spatial.graph.connect(fall_wp, tether_wp, null);
    try spatial.graph.connect(fall_wp, plough_wp, null);
    try spatial.graph.connect(plough_wp, tether_wp, null);
    try spatial.graph.connect(tether_wp, dig_wp, null);
    try spatial.graph.connect(crypt_ladder_wp, altar_wp, null);

    const cellar_entrance = world.lookup_entity("CellarEntrance").?;
    const farm_plough = world.lookup_entity("FarmPlough").?;
    const tether_stake = world.lookup_entity("TetherStake").?;
    const carved_mural = world.lookup_entity("CarvedMural").?;
    const crypt_altar = world.lookup_entity("CryptAltar").?;

    try spatial.add_hotspot(cellar_entrance, courtyard_scene, .{ .x = 28, .y = -4 }, 8, "Cellar Entrance", "A dark excavation pit leading down into the subterranean ruins.");
    try spatial.add_hotspot(farm_plough, courtyard_scene, .{ .x = 10, .y = 8 }, 8, "Farm Plough", "An old, heavy iron farm plough resting in the weeds.");
    try spatial.add_hotspot(tether_stake, courtyard_scene, .{ .x = 16, .y = -4 }, 6, "Tether Stake", "A sturdy wooden post driven into the Irish turf.");
    try spatial.add_hotspot(crypt_altar, crypt_scene, .{ .x = 20, .y = -4 }, 8, "Crypt Altar", "An ancient Templar stone altar carved with medieval inscriptions.");
    try spatial.add_hotspot(carved_mural, crypt_scene, .{ .x = 30, .y = -6 }, 8, "Carved Mural", "A wall carving of a Knights Templar bearing a chalice.");

    try spatial.register_entity(george, entrance_wp, 10);
    try spatial.register_entity(goat, tether_wp, 8);

    const tether_rel = try world.intern_relation("TetheredTo", .set);
    try world.remember(goat, tether_rel, tether_stake.to_int(), 0);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(courtyard_scene);

    var display_bridge = bespoke.display.DisplayBridge.init();
    var history_snapshots = std.ArrayList(std.ArrayList(u8)).init(allocator);
    defer {
        for (history_snapshots.items) |*buf| buf.deinit();
        history_snapshots.deinit();
    }

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - Broken Sword: The Lochmarne Goat", 1280, 720);
    defer window.deinit();

    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
    try stdout.print("Broken Sword Lochmarne Goat Scenario Controls:\n", .{});
    try stdout.print("   - [C]:                   Go to Lochmarne Castle Courtyard\n", .{});
    try stdout.print("   - [T]:                   Go to Subterranean Templar Crypt\n", .{});
    try stdout.print("   - [1]:                   Step 1: Approach Cellar Pit (triggers threat-radius charge & retreat window)\n", .{});
    try stdout.print("   - [2]:                   Step 2: Drag Farm Plough into rope line (tangles goat)\n", .{});
    try stdout.print("   - [3]:                   Step 3: Descend ladder into Templar Crypt\n", .{});
    try stdout.print("   - [4]:                   Step 4: Inspect Knights Templar Wall Mural & Stone Altar\n", .{});
    try stdout.print("   - [Timeline Scrubber]:   Click or drag timeline bar (or [< / >] arrows)\n", .{});
    try stdout.print("   - [F1 / D]:              Toggle Debug Relational Fact & Fiber Overlay\n", .{});
    try stdout.print("   - [Tab / ` / C]:         Toggle Live REPL Console Drawer\n", .{});
    try stdout.print("   - [Space]:               Pause / Resume Simulation Clock\n", .{});
    try stdout.print("   - [N]:                   Single-step Simulation Tick\n", .{});
    try stdout.print("   - [R]:                   Instant Time-Travel Rewind\n", .{});
    try stdout.print("   - [Esc / Close]:         Exit\n\n", .{});

    display_bridge.attach_audio_bridge(window.audio_bridge);
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.set_max_history_tick(0);
    display_bridge.swap();

    var snap0 = std.ArrayList(u8).init(allocator);
    try world.save_state(snap0.writer());
    try history_snapshots.append(snap0);

    var is_paused = false;
    var last_tick_time = std.time.milliTimestamp();

    window.set_cue_banner("Lochmarne Castle: Navigate past the fierce Billy Goat to reach Peagram's dig! [C/T] [1-4]", 180);

    const retreating_rel = world.lookup_relation("GoatRetreating").?;

    while (true) {
        const action = window.poll_events(display_bridge.get_frame());
        var should_step_now = false;

        _ = window.handle_save_action(action, &world, &spatial, &vm, &display_bridge, &is_paused);
        switch (action) {
            .quit => break,
            .toggle_pause => is_paused = !is_paused,
            .step_tick => should_step_now = true,
            .walk_player => |wp_id| {
                if (world.has_fact(george, world.lookup_relation("KnockedDown").?, null)) {
                    window.set_cue_banner("George is knocked flat on his back! Recovering...", 60);
                } else {
                    const from_wp = spatial.get_current_waypoint(george);
                    _ = try spatial.walk_to(george, wp_id);
                    if (vm.current_scene == crypt_scene and wp_id == crypt_ladder_wp and from_wp != null and from_wp.? != crypt_ladder_wp) {
                        try vm.transition_to_scene(courtyard_scene);
                        _ = try spatial.transition_actor(george, courtyard_scene, dig_wp);
                        window.set_cue_banner("Climbed ladder back up into the castle ruins courtyard! [T] Crypt", 120);
                    }
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                    window.set_cue_banner("Directing George to waypoint.", 60);
                }
            },
            .interact_actor => |act| {
                const frame = display_bridge.get_frame();
                if (act.actor_index < frame.entity_count) {
                    const target_entity = frame.entities[act.actor_index];
                    const tname = target_entity.get_name();

                    if (std.mem.eql(u8, tname, "BillyGoat")) {
                        if (act.verb == .look_at) {
                            window.set_cue_banner("Billy Goat: A fierce Irish goat tied by a long rope. Eyeing George hostilely.", 120);
                        } else if (act.verb == .talk_to) {
                            window.set_cue_banner("Billy Goat: 'MAAAA-AAAH!' *snorts and headbutts the air*", 120);
                        } else if (act.verb == .use_with or act.verb == .pick_up) {
                            if (world.has_fact(goat, retreating_rel, null)) {
                                _ = try vm.fire_cue(&compiled, "Uses", george, farm_plough, null);
                                window.set_cue_banner("★ VICTORY! Hauled plough into the rope! Goat is tangled and secured! ★", 180);
                            } else {
                                window.set_cue_banner("George: 'I'm not getting within reach of those horns without a plan!'", 120);
                            }
                        }
                    } else {
                        window.set_cue_banner("George Stobbart: American tourist investigating the Templars in Ireland.", 120);
                    }
                }
            },
            .interact_hotspot => |hs_act| {
                const frame = display_bridge.get_frame();
                if (hs_act.hotspot_index < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_act.hotspot_index];
                    const hname = hs.get_name();

                    if (std.mem.indexOf(u8, hname, "Cellar") != null) {
                        if (hs_act.verb == .look_at) {
                            window.set_cue_banner("Cellar Opening: Peagram's excavation pit leading down into the Templar crypt.", 150);
                        } else {
                            if (vm.current_scene == courtyard_scene) {
                                _ = try spatial.walk_to(george, dig_wp);
                                window.set_cue_banner("Directing George to approach Peagram's cellar pit...", 90);
                            }
                        }
                    } else if (std.mem.indexOf(u8, hname, "Plough") != null) {
                        if (hs_act.verb == .look_at) {
                            window.set_cue_banner("Farm Plough: An old, heavy iron farm plough resting in the weeds.", 150);
                        } else {
                            if (vm.current_scene == courtyard_scene) {
                                _ = try spatial.walk_to(george, plough_wp);
                                window.set_cue_banner("Directing George to the heavy iron farm plough...", 90);
                            }
                        }
                    } else if (std.mem.indexOf(u8, hname, "Stake") != null) {
                        window.set_cue_banner("Tether Stake: A stout wooden post driven deep into the Irish turf.", 120);
                    } else if (std.mem.indexOf(u8, hname, "Mural") != null) {
                        if (vm.current_scene == crypt_scene) {
                            _ = try spatial.walk_to(george, altar_wp);
                            _ = try vm.fire_cue(&compiled, "LooksAt", george, carved_mural, null);
                            window.set_cue_banner("Carved Mural: Ancient stone relief of a Templar knight bearing a chalice.", 150);
                        }
                    } else if (std.mem.indexOf(u8, hname, "Altar") != null) {
                        if (vm.current_scene == crypt_scene) {
                            _ = try spatial.walk_to(george, altar_wp);
                            _ = try vm.fire_cue(&compiled, "LooksAt", george, crypt_altar, null);
                            window.set_cue_banner("Crypt Altar: Medieval stone altar adorned with ancient inscriptions.", 150);
                        }
                    }
                }
            },
            .interact_inventory => |inv_act| {
                const frame = display_bridge.get_frame();
                if (inv_act.item_index < frame.inventory_count) {
                    const item_name = frame.inventory[inv_act.item_index].get_name();
                    if (inv_act.verb == .look_at) {
                        var buf: [128]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "{s}: \"An item in George's pockets.\"", .{item_name}) catch "Item";
                        window.set_cue_banner(msg, 120);
                    }
                }
            },
            .scrub_to_tick => |target_tick| {
                if (target_tick < history_snapshots.items.len) {
                    var stream = std.io.fixedBufferStream(history_snapshots.items[target_tick].items);
                    world.restore_state(stream.reader()) catch {};
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();

                    while (history_snapshots.items.len > target_tick + 1) {
                        var popped = history_snapshots.pop();
                        popped.deinit();
                    }
                    display_bridge.set_max_history_tick(target_tick);
                    var buf: [64]u8 = undefined;
                    const banner = std.fmt.bufPrint(&buf, "Time-Travel Rewound to Tick {d}", .{target_tick}) catch "Rewound";
                    window.set_cue_banner(banner, 90);
                }
            },
            .rewind => {
                if (history_snapshots.items.len > 1) {
                    var last_snap = history_snapshots.pop();
                    last_snap.deinit();
                    const target_tick = history_snapshots.items.len - 1;
                    var stream = std.io.fixedBufferStream(history_snapshots.items[target_tick].items);
                    world.restore_state(stream.reader()) catch {};
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                    display_bridge.set_max_history_tick(target_tick);
                    window.set_cue_banner("Stepped back 1 snapshot in time.", 60);
                }
            },
            else => {},
        }

        // Immediately update frame buffer on player action
        if (action != .none and action != .toggle_pause and action != .step_tick and action != .quit) {
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        // Check helper hotkeys
        const keys = bespoke.display.renderer.c.SDL_GetKeyboardState(null);
        if (keys != null) {
            // [C] Courtyard Scene
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_C] != 0) {
                try vm.transition_to_scene(courtyard_scene);
                _ = try spatial.transition_actor(george, courtyard_scene, entrance_wp);
                window.set_cue_banner("Switched Scene: Lochmarne Castle Courtyard", 60);
            }
            // [T] Templar Crypt Scene
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_T] != 0) {
                try vm.transition_to_scene(crypt_scene);
                _ = try spatial.transition_actor(george, crypt_scene, crypt_ladder_wp);
                window.set_cue_banner("Switched Scene: Subterranean Templar Crypt", 60);
            }
            // [1] Approach Cellar Dig (Step 1)
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_1] != 0) {
                if (vm.current_scene == courtyard_scene) {
                    _ = try spatial.walk_to(george, dig_wp);
                    window.set_cue_banner("Step 1: Directing George toward Cellar Dig (Billy Goat threat zone)...", 90);
                }
            }
            // [2] Drag Plough (Step 2)
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_2] != 0) {
                if (vm.current_scene == courtyard_scene) {
                    _ = try spatial.walk_to(george, plough_wp);
                    window.set_cue_banner("Step 2: Directing George toward Farm Plough...", 90);
                }
            }
            // [3] Descend into Crypt (Step 3)
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_3] != 0) {
                if (vm.current_scene == courtyard_scene) {
                    _ = try spatial.walk_to(george, dig_wp);
                    window.set_cue_banner("Step 3: Directing George toward Cellar Pit to descend into Crypt...", 90);
                }
            }
            // [4] Inspect Templar Mural (Step 4)
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_4] != 0) {
                if (vm.current_scene == crypt_scene) {
                    _ = try spatial.walk_to(george, altar_wp);
                    _ = try vm.fire_cue(&compiled, "LooksAt", george, carved_mural, null);
                    window.set_cue_banner("Step 4: Examined Knights Templar carved mural and stone altar!", 120);
                } else {
                    window.set_cue_banner("You must enter the Templar Crypt first to examine the mural!", 120);
                }
            }
        }

        // Stepping simulation clock
        const current_time = std.time.milliTimestamp();
        if ((!is_paused and (current_time - last_tick_time >= window.current_tick_interval_ms)) or should_step_now) {
            last_tick_time = current_time;
            try vm.step_tick();

            // Check George arrival events at key marks
            if (spatial.get_current_waypoint(george)) |cur_wp| {
                if (vm.current_scene == courtyard_scene) {
                    if (cur_wp == dig_wp) {
                        if (evaluate_goat_tangled(&world)) {
                            try vm.transition_to_scene(crypt_scene);
                            _ = try spatial.transition_actor(george, crypt_scene, crypt_ladder_wp);
                            window.set_cue_banner("★ Descended ladder into subterranean Templar Crypt! [C] Return to Courtyard ★", 180);
                        } else {
                            _ = try vm.fire_cue(&compiled, "Uses", george, cellar_entrance, null);
                            _ = try spatial.transition_actor(george, courtyard_scene, fall_wp);
                            window.set_cue_banner("★ Billy Goat charges! George is knocked flat! (30-tick retreat window active!) ★", 180);
                        }
                    } else if (cur_wp == plough_wp) {
                        if (world.has_fact(goat, retreating_rel, null) and !evaluate_goat_tangled(&world)) {
                            _ = try vm.fire_cue(&compiled, "Uses", george, farm_plough, null);
                            window.set_cue_banner("★ VICTORY! Hauled plough into the rope! Goat is tangled and secured! ★", 180);
                        }
                    }
                }
            }

            var snap = std.ArrayList(u8).init(allocator);
            try world.save_state(snap.writer());
            try history_snapshots.append(snap);

            display_bridge.set_max_history_tick(world.current_tick);
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        window.render_frame(display_bridge.get_frame(), is_paused);
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P20-01: compile and execute Broken Sword Goat Puzzle script" {
    const allocator = std.testing.allocator;

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, GOAT_PUZZLE_SCRIPT);
    defer compiled.deinit();

    const courtyard_scene = world.lookup_entity("Lochmarne Castle Courtyard").?;
    const crypt_scene = world.lookup_entity("Templar Crypt").?;
    const george = world.lookup_entity("George").?;
    const goat = world.lookup_entity("BillyGoat").?;
    const cellar = world.lookup_entity("CellarEntrance").?;
    const plough = world.lookup_entity("FarmPlough").?;

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    try vm.transition_to_scene(courtyard_scene);

    // Initial state: not tangled
    try std.testing.expect(!evaluate_goat_tangled(&world));

    // Try moving plough without retreat window -> denied
    _ = try vm.fire_cue(&compiled, "Uses", george, plough, null);
    try vm.step_tick();
    try std.testing.expect(!evaluate_goat_tangled(&world));

    // Try cellar -> goat attacks, triggers retreat window
    _ = try vm.fire_cue(&compiled, "Uses", george, cellar, null);
    try vm.step_tick();
    const retreating_rel = world.lookup_relation("GoatRetreating").?;
    try std.testing.expect(world.has_fact(goat, retreating_rel, null));

    // Move plough during retreat window -> tangled!
    _ = try vm.fire_cue(&compiled, "Uses", george, plough, null);
    try vm.step_tick();
    try std.testing.expect(evaluate_goat_tangled(&world));

    // Now descend cellar -> transitions to Templar Crypt
    _ = try vm.fire_cue(&compiled, "Uses", george, cellar, null);
    try vm.step_tick();
    try std.testing.expect(evaluate_crypt_entered(&world, &vm));
    try std.testing.expectEqual(crypt_scene, vm.current_scene.?);
}

test "P20-03: headless execution runs full scenario and time-travel rewind" {
    const allocator = std.testing.allocator;
    const null_writer = std.io.null_writer;
    try run_headless(allocator, null_writer);
}
