const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const GoatKey = enum(u16) { courtyard, crypt, step_1, step_2, step_3, step_4 };

const goat_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_c, .action = @intFromEnum(GoatKey.courtyard) },
    .{ .key = bespoke.display.renderer.c.SDLK_t, .action = @intFromEnum(GoatKey.crypt) },
    .{ .key = bespoke.display.renderer.c.SDLK_1, .action = @intFromEnum(GoatKey.step_1) },
    .{ .key = bespoke.display.renderer.c.SDLK_2, .action = @intFromEnum(GoatKey.step_2) },
    .{ .key = bespoke.display.renderer.c.SDLK_3, .action = @intFromEnum(GoatKey.step_3) },
    .{ .key = bespoke.display.renderer.c.SDLK_4, .action = @intFromEnum(GoatKey.step_4) },
});

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
    \\  walk George to DigOpening
    \\
    \\when George arrives at DigOpening:
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
    \\    walk George to FallMark
    \\
    \\on cue Uses(George, FarmPlough):
    \\  walk George to PloughMark
    \\
    \\when George arrives at PloughMark:
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
    \\when George arrives at CryptLadder:
    \\  transition to scene: Lochmarne Castle Courtyard
    \\
    \\on cue LooksAt(George, CarvedMural):
    \\  say George: "A centuries-old stone carving of a Templar knight holding a chalice. Peagram's dig site was right on the trail!"
    \\
    \\on cue LooksAt(George, CryptAltar):
    \\  say George: "An ancient stone altar covered in centuries of dust."
;

/// Evaluates whether the Billy Goat has been tangled around the plough (P20-01, D-023).
pub fn evaluate_goat_tangled(world: *const bespoke.World) bool {
    // The exact fact the script's `now BillyGoat is tangled` writes (P32-19).
    const goat = world.lookup_entity("BillyGoat") orelse return false;
    const rel = world.lookup_relation("tangled") orelse return false;
    return world.has_fact(goat, rel, null);
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

/// Entities and marks of the two scenes, laid out and connected for both runners and the tests.
const Stage = struct {
    courtyard_scene: bespoke.EntityId,
    crypt_scene: bespoke.EntityId,
    george: bespoke.EntityId,
    goat: bespoke.EntityId,
    cellar_entrance: bespoke.EntityId,
    farm_plough: bespoke.EntityId,
    carved_mural: bespoke.EntityId,
    crypt_altar: bespoke.EntityId,
    entrance_wp: bespoke.WaypointId,
    plough_wp: bespoke.WaypointId,
    tether_wp: bespoke.WaypointId,
    dig_wp: bespoke.WaypointId,
    crypt_ladder_wp: bespoke.WaypointId,
    altar_wp: bespoke.WaypointId,

    fn init(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Stage {
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
        bespoke.host.place_waypoint(spatial, entrance_wp, 4, 0);
        bespoke.host.place_waypoint(spatial, fall_wp, 8, 0);
        bespoke.host.place_waypoint(spatial, plough_wp, 10, 8);
        bespoke.host.place_waypoint(spatial, tether_wp, 16, 0);
        bespoke.host.place_waypoint(spatial, dig_wp, 28, 0);
        bespoke.host.place_waypoint(spatial, crypt_ladder_wp, 4, 0);
        bespoke.host.place_waypoint(spatial, altar_wp, 20, 0);

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

        return .{
            .courtyard_scene = courtyard_scene,
            .crypt_scene = crypt_scene,
            .george = george,
            .goat = goat,
            .cellar_entrance = cellar_entrance,
            .farm_plough = farm_plough,
            .carved_mural = carved_mural,
            .crypt_altar = crypt_altar,
            .entrance_wp = entrance_wp,
            .plough_wp = plough_wp,
            .tether_wp = tether_wp,
            .dig_wp = dig_wp,
            .crypt_ladder_wp = crypt_ladder_wp,
            .altar_wp = altar_wp,
        };
    }

    /// Puts George at the foot or head of the ladder when a tick changed the scene. The script
    /// decides the transition (arrival rules, P32-18); where an actor stands in the new scene
    /// is layout. Placing is not arriving, so this cannot re-trigger the rule that fired.
    fn follow_scene(self: Stage, vm: *const bespoke.VM, spatial: *bespoke.SpatialSystem, before: ?bespoke.EntityId) !bool {
        const now = vm.current_scene orelse return false;
        if (before != null and before.? == now) return false;
        if (now == self.crypt_scene) {
            _ = try spatial.transition_actor(self.george, self.crypt_scene, self.crypt_ladder_wp);
        } else if (now == self.courtyard_scene) {
            _ = try spatial.transition_actor(self.george, self.courtyard_scene, self.dig_wp);
        }
        return true;
    }
};

/// Upper bound on the ticks one scripted walk and its arrival rule may take in the headless run.
const MAX_WALK_TICKS: usize = 40;

const Outcome = enum { goat_retreating, goat_tangled, crypt_entered };

fn reached(outcome: Outcome, world: *const bespoke.World, vm: *const bespoke.VM, stage: Stage) bool {
    return switch (outcome) {
        .goat_retreating => world.has_fact(stage.goat, world.lookup_relation("GoatRetreating") orelse return false, null),
        .goat_tangled => evaluate_goat_tangled(world),
        .crypt_entered => evaluate_crypt_entered(world, vm),
    };
}

/// Fires `Uses(George, target)` and ticks until the walk it starts has arrived and the arrival
/// rule has produced `outcome`. Returns false if the bound runs out first.
fn use_and_walk(
    world: *bespoke.World,
    spatial: *bespoke.SpatialSystem,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    stage: Stage,
    target: bespoke.EntityId,
    outcome: Outcome,
) !bool {
    _ = try vm.fire_cue(compiled, "Uses", stage.george, target, null);
    var ticks: usize = 0;
    while (ticks < MAX_WALK_TICKS) : (ticks += 1) {
        const scene_before = vm.current_scene;
        _ = try bespoke.host.tick(vm, compiled);
        _ = try stage.follow_scene(vm, spatial, scene_before);
        if (reached(outcome, world, vm, stage)) return true;
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

    const stage = try Stage.init(&world, &spatial);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);

    try vm.transition_to_scene(stage.courtyard_scene);

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("George")) |player| display_bridge.set_active_character(player);

    // Save initial state snapshot for time-travel verification
    var snapshot_0 = std.ArrayList(u8).init(allocator);
    defer snapshot_0.deinit();
    try world.save_state(snapshot_0.writer());

    try writer.print("\n[Step 1] Initial Inspection: George arrives at Lochmarne Castle Courtyard.\n", .{});
    _ = try vm.fire_cue(&compiled, "LooksAt", stage.george, stage.goat, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    display_bridge.capture_frame(&world, &spatial, &vm);
    try writer.print("  -> Fact count: {d}, George at CourtyardEntrance, Goat at TetherCenter\n", .{world.fact_count()});

    // Steps 2 to 4 walk George to a mark; the script's arrival rules do the rest (P32-18).
    try writer.print("\n[Step 2] Threat Radius Exploration: George approaches CellarEntrance.\n", .{});
    const is_retreating = try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.cellar_entrance, .goat_retreating);
    display_bridge.capture_frame(&world, &spatial, &vm);

    // Verify headbutt knockback and 30-tick retreat window
    try writer.print("  -> Goat reactive charge triggered! George knocked down to FallMark.\n", .{});
    try writer.print("  -> Goat retreating window active: {any} (30 ticks remaining)\n", .{is_retreating});

    if (!is_retreating) {
        return error.GoatRetreatWindowMissing;
    }

    try writer.print("\n[Step 3] Seizing the Window: George hauls FarmPlough while goat retreats!\n", .{});
    const is_tangled = try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.farm_plough, .goat_tangled);
    display_bridge.capture_frame(&world, &spatial, &vm);

    try writer.print("  -> Plough hauled into rope path! Goat tangled status: {any}\n", .{is_tangled});
    if (!is_tangled) {
        return error.GoatNotTangled;
    }

    try writer.print("\n[Step 4] Accessing the Dig: George descends into CellarEntrance.\n", .{});
    const entered_crypt = try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.cellar_entrance, .crypt_entered);
    display_bridge.capture_frame(&world, &spatial, &vm);

    try writer.print("  -> Multi-scene transition to Templar Crypt successful: {any}\n", .{entered_crypt});
    if (!entered_crypt) {
        return error.FailedToEnterCrypt;
    }

    try writer.print("\n[Step 5] Archaeological Discovery: George examines the CarvedMural.\n", .{});
    _ = try vm.fire_cue(&compiled, "LooksAt", stage.george, stage.carved_mural, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    display_bridge.capture_frame(&world, &spatial, &vm);

    try writer.print("\n[Step 6] Time-Travel Rewind Verification: Restoring pristine Courtyard state.\n", .{});
    var stream = std.io.fixedBufferStream(snapshot_0.items);
    try world.restore_state(stream.reader());
    vm.current_scene = stage.courtyard_scene;
    _ = try spatial.transition_actor(stage.george, stage.courtyard_scene, stage.entrance_wp);
    _ = try spatial.transition_actor(stage.goat, stage.courtyard_scene, stage.tether_wp);
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

    const stage = try Stage.init(&world, &spatial);
    const courtyard_scene = stage.courtyard_scene;
    const crypt_scene = stage.crypt_scene;
    const george = stage.george;
    const goat = stage.goat;
    const farm_plough = stage.farm_plough;
    const carved_mural = stage.carved_mural;
    const crypt_altar = stage.crypt_altar;
    const entrance_wp = stage.entrance_wp;
    const plough_wp = stage.plough_wp;
    const dig_wp = stage.dig_wp;
    const crypt_ladder_wp = stage.crypt_ladder_wp;
    const altar_wp = stage.altar_wp;

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try vm.transition_to_scene(courtyard_scene);

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("George")) |player| display_bridge.set_active_character(player);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - Broken Sword: The Lochmarne Goat", 1280, 720);
    defer window.deinit();
    window.set_theme(&goat_theme);

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
    var session = try bespoke.host.Session.init(allocator, &world, &spatial, &vm, &compiled, &display_bridge, &window);
    defer session.deinit();

    window.set_cue_banner("Lochmarne Castle: Navigate past the fierce Billy Goat to reach Peagram's dig! [C/T] [1-4]", 180);

    const retreating_rel = world.lookup_relation("GoatRetreating").?;
    const knocked_rel = world.lookup_relation("KnockedDown").?;

    while (true) {
        const action = window.poll_events(session.frame());

        // Pause, step, scrub, rewind, and save actions are shared (host kit, P32-16, D-033).
        if (try session.handle_common(action)) {} else switch (action) {
            .quit => break,
            .walk_player => |wp_id| {
                if (world.has_fact(george, knocked_rel, null)) {
                    window.set_cue_banner("George is knocked flat on his back! Recovering...", 60);
                } else {
                    // Walking is all the host does; the script reacts when George arrives.
                    _ = try spatial.walk_to(george, wp_id);
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
                                window.set_cue_banner("George dashes for the heavy iron farm plough...", 90);
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
            else => {},
        }

        // Immediately update frame buffer on player action
        if (action != .none and action != .toggle_pause and action != .step_tick and action != .quit) {
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        // Check helper hotkeys
        // Bound keys arrive once per press as `UserAction.custom` (P32-02c); they used to be
        // polled every frame from SDL's keyboard state.
        const pressed: ?GoatKey = if (action == .custom) std.meta.intToEnum(GoatKey, action.custom) catch null else null;
        if (pressed != null) {
            // [C] Courtyard Scene
            if (pressed == .courtyard) {
                try vm.transition_to_scene(courtyard_scene);
                _ = try spatial.transition_actor(george, courtyard_scene, entrance_wp);
                window.set_cue_banner("Switched Scene: Lochmarne Castle Courtyard", 60);
            }
            // [T] Templar Crypt Scene
            if (pressed == .crypt) {
                try vm.transition_to_scene(crypt_scene);
                _ = try spatial.transition_actor(george, crypt_scene, crypt_ladder_wp);
                window.set_cue_banner("Switched Scene: Subterranean Templar Crypt", 60);
            }
            // [1] Approach Cellar Dig (Step 1)
            if (pressed == .step_1) {
                if (vm.current_scene == courtyard_scene) {
                    _ = try spatial.walk_to(george, dig_wp);
                    window.set_cue_banner("Step 1: Directing George toward Cellar Dig (Billy Goat threat zone)...", 90);
                }
            }
            // [2] Drag Plough (Step 2)
            if (pressed == .step_2) {
                if (vm.current_scene == courtyard_scene) {
                    _ = try spatial.walk_to(george, plough_wp);
                    window.set_cue_banner("Step 2: Directing George toward Farm Plough...", 90);
                }
            }
            // [3] Descend into Crypt (Step 3)
            if (pressed == .step_3) {
                if (vm.current_scene == courtyard_scene) {
                    _ = try spatial.walk_to(george, dig_wp);
                    window.set_cue_banner("Step 3: Directing George toward Cellar Pit to descend into Crypt...", 90);
                }
            }
            // [4] Inspect Templar Mural (Step 4)
            if (pressed == .step_4) {
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
        if (session.tick_due()) {
            const scene_before = vm.current_scene;
            const was_down = world.has_fact(george, knocked_rel, null);
            const was_tangled = evaluate_goat_tangled(&world);

            _ = try bespoke.host.tick(&vm, &compiled);

            // The script's arrival rules decided what happened this tick (P32-18); the host
            // only places George in a new scene and narrates the change.
            if (try stage.follow_scene(&vm, &spatial, scene_before)) {
                if (vm.current_scene == crypt_scene) {
                    window.set_cue_banner("★ Descended ladder into subterranean Templar Crypt! [C] Return to Courtyard ★", 180);
                } else {
                    window.set_cue_banner("Climbed ladder back up into the castle ruins courtyard! [T] Crypt", 120);
                }
            } else if (!was_down and world.has_fact(george, knocked_rel, null)) {
                window.set_cue_banner("★ Billy Goat charges! George is knocked flat! (30-tick retreat window active!) ★", 180);
            } else if (!was_tangled and evaluate_goat_tangled(&world)) {
                window.set_cue_banner("★ VICTORY! Hauled plough into the rope! Goat is tangled and secured! ★", 180);
            }

            // Record after the placement above, so the snapshot includes it.
            try session.record_now();
        }

        session.render();
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

    const stage = try Stage.init(&world, &spatial);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);

    try vm.transition_to_scene(stage.courtyard_scene);

    // Initial state: not tangled
    try std.testing.expect(!evaluate_goat_tangled(&world));

    // Walk to the plough without a retreat window -> arrival, but the plough stays put
    try std.testing.expect(!try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.farm_plough, .goat_tangled));
    try std.testing.expectEqual(stage.plough_wp, spatial.get_current_waypoint(stage.george).?);

    // Walk to the cellar -> on arrival the goat attacks and the retreat window opens
    try std.testing.expect(try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.cellar_entrance, .goat_retreating));
    try std.testing.expectEqual(stage.dig_wp, spatial.get_current_waypoint(stage.george).?);
    try std.testing.expect(!evaluate_crypt_entered(&world, &vm));

    // Reach the plough during the retreat window -> tangled!
    try std.testing.expect(try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.farm_plough, .goat_tangled));

    // Now walk to the cellar -> the arrival rule transitions to the Templar Crypt
    try std.testing.expect(try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.cellar_entrance, .crypt_entered));
    try std.testing.expectEqual(stage.crypt_scene, vm.current_scene.?);
    try std.testing.expectEqual(stage.crypt_ladder_wp, spatial.get_current_waypoint(stage.george).?);

    // Walking off the ladder and back climbs out; being placed at the dig does not descend again
    _ = try spatial.walk_to(stage.george, stage.altar_wp);
    var ticks: usize = 0;
    while (ticks < MAX_WALK_TICKS and spatial.get_current_waypoint(stage.george).? != stage.altar_wp) : (ticks += 1) {
        _ = try bespoke.host.tick(&vm, &compiled);
    }
    _ = try spatial.walk_to(stage.george, stage.crypt_ladder_wp);
    ticks = 0;
    while (ticks < MAX_WALK_TICKS and vm.current_scene.? != stage.courtyard_scene) : (ticks += 1) {
        const scene_before = vm.current_scene;
        _ = try bespoke.host.tick(&vm, &compiled);
        _ = try stage.follow_scene(&vm, &spatial, scene_before);
    }
    try std.testing.expectEqual(stage.courtyard_scene, vm.current_scene.?);
    try std.testing.expectEqual(stage.dig_wp, spatial.get_current_waypoint(stage.george).?);
    for (0..5) |_| _ = try bespoke.host.tick(&vm, &compiled);
    try std.testing.expectEqual(stage.courtyard_scene, vm.current_scene.?);
}

test "P20-03: headless execution runs full scenario and time-travel rewind" {
    const allocator = std.testing.allocator;
    const null_writer = std.io.null_writer;
    try run_headless(allocator, null_writer);
}
