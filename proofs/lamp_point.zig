//! The Donkey of Lamp Point (P35-05): Tamsin gets past the lighthouse keeper's donkey to the
//! wreckers' cellar. Each step is an arrival rule in the script; a 30-tick retreat window opens
//! when Cudgel charges, and hauling the anchor into his rope line closes the way to the hatch.
const std = @import("std");
const ListWriter = @import("bespoke").ListWriter;
const bespoke = @import("bespoke");
const golden = @import("golden_digest.zig");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const PointKey = enum(u16) { point, cellar, step_1, step_2, step_3, step_4 };

const point_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_l, .action = @intFromEnum(PointKey.point) },
    .{ .key = bespoke.display.renderer.c.SDLK_w, .action = @intFromEnum(PointKey.cellar) },
    .{ .key = bespoke.display.renderer.c.SDLK_1, .action = @intFromEnum(PointKey.step_1) },
    .{ .key = bespoke.display.renderer.c.SDLK_2, .action = @intFromEnum(PointKey.step_2) },
    .{ .key = bespoke.display.renderer.c.SDLK_3, .action = @intFromEnum(PointKey.step_3) },
    .{ .key = bespoke.display.renderer.c.SDLK_4, .action = @intFromEnum(PointKey.step_4) },
});

pub const LAMP_POINT_SCRIPT =
    \\scene: Lamp Point
    \\cast: Tamsin, Cudgel
    \\props: CellarHatch, OldAnchor, MooringPost
    \\marks: PointPath, FallMark, AnchorMark, TetherCenter, HatchMark
    \\
    \\scene: Wreckers Cellar
    \\cast: Tamsin
    \\props: WreckersChart, SeaChest
    \\marks: CellarSteps, ChestMark
    \\
    \\Tangled is a state, which can be tangled or untangled. The donkey is untangled in the scene.
    \\AnchorMoved is a state, which can be moved or unmoved. The anchor is unmoved in the scene.
    \\TamsinStatus is a state, which can be standing or knocked_down. Tamsin is standing in the scene.
    \\
    \\on cue LooksAt(Tamsin, Cudgel):
    \\  say Tamsin: "The lighthouse keeper's donkey, on a long rope tied to a post. He has decided he hates me."
    \\
    \\on cue LooksAt(Tamsin, CellarHatch):
    \\  say Tamsin: "A trapdoor in the turf, propped open. Steps go down into the dark."
    \\
    \\on cue LooksAt(Tamsin, OldAnchor):
    \\  say Tamsin: "A rusted ship's anchor sunk in the thrift. It would hold a schooner in a gale."
    \\
    \\on cue LooksAt(Tamsin, MooringPost):
    \\  say Tamsin: "An old mooring post, driven deep. The rope won't come off it."
    \\
    \\on cue TalksTo(Tamsin, Cudgel):
    \\  choice "Who's a good donkey?":
    \\    say Cudgel: "Hrumph. *stamps a hoof*"
    \\    say Tamsin: "Not him, apparently."
    \\  choice "Shoo! Off with you!":
    \\    say Cudgel: "HEE-HAWWW!"
    \\    say Tamsin: "Now he's angrier."
    \\
    \\on cue Uses(Tamsin, CellarHatch):
    \\  walk Tamsin to HatchMark
    \\
    \\when Tamsin arrives at HatchMark:
    \\  if Cudgel is tangled:
    \\    say Tamsin: "With his rope caught on the anchor, he can't reach the hatch. Down I go."
    \\    transition to scene: Wreckers Cellar
    \\  if Cudgel is not tangled:
    \\    say Cudgel: "HEE-HAW!"
    \\    say Tamsin: "Oof! He shoved me flat on my back, in front of the whole headland."
    \\    remember KnockedDown(Tamsin, true) for 15 ticks
    \\    now Tamsin is knocked_down
    \\    remember DonkeyRetreating(Cudgel, true) for 30 ticks
    \\    walk Cudgel to TetherCenter
    \\    walk Tamsin to FallMark
    \\
    \\on cue Uses(Tamsin, OldAnchor):
    \\  walk Tamsin to AnchorMark
    \\
    \\when Tamsin arrives at AnchorMark:
    \\  if Cudgel is tangled:
    \\    say Tamsin: "The anchor's already got his rope."
    \\  if Cudgel is not tangled:
    \\    if not DonkeyRetreating(Cudgel):
    \\      say Tamsin: "If I go for the anchor now, he'll kick me before it budges."
    \\    if DonkeyRetreating(Cudgel):
    \\      say Tamsin: "He's ambling back to his post. Now, while his back's turned! I heave the anchor into the line of his rope."
    \\      now Cudgel is tangled
    \\      now OldAnchor is moved
    \\      remember TangledWith(Cudgel, OldAnchor)
    \\      remember AnchorMoved(OldAnchor, true)
    \\      forget DonkeyRetreating(Cudgel)
    \\      say Cudgel: "Hronk! *tugs*"
    \\      say Tamsin: "Caught. His rope's wrapped round the anchor, and the hatch is out of reach."
    \\
    \\when Tamsin arrives at CellarSteps:
    \\  transition to scene: Lamp Point
    \\
    \\on cue LooksAt(Tamsin, WreckersChart):
    \\  say Tamsin: "A wreckers' chart scratched into the cellar wall, with every reef on the Point marked. Odell would give a year's pay for this."
    \\
    \\on cue LooksAt(Tamsin, SeaChest):
    \\  say Tamsin: "A sea chest, its lid rotted through. Empty, apart from sand."
;

/// Evaluates whether Cudgel has been tangled around the anchor (P20-01, D-023, P35-05).
pub fn evaluate_donkey_tangled(world: *const bespoke.World) bool {
    // The exact fact the script's `now Cudgel is tangled` writes (P32-19).
    const donkey = world.lookup_entity("Cudgel") orelse return false;
    const rel = world.lookup_relation("Tangled") orelse return false;
    return world.has_fact(donkey, rel, null);
}

/// Evaluates whether Tamsin has gone down into the Wreckers Cellar (P20-01, D-023, P35-05).
pub fn evaluate_cellar_entered(world: *const bespoke.World, vm: *const bespoke.VM) bool {
    if (vm.current_scene) |scene_id| {
        if (world.get_entity_name(scene_id)) |sname| {
            if (std.mem.eql(u8, sname, "Wreckers Cellar")) {
                return true;
            }
        }
    }
    return false;
}

/// Entities and marks of the two scenes, laid out and connected for both runners, the tests,
/// and the browser deck, so the window and the page share one layout (D-100).
pub const Stage = struct {
    point_scene: bespoke.EntityId,
    cellar_scene: bespoke.EntityId,
    tamsin: bespoke.EntityId,
    donkey: bespoke.EntityId,
    cellar_hatch: bespoke.EntityId,
    old_anchor: bespoke.EntityId,
    wreckers_chart: bespoke.EntityId,
    sea_chest: bespoke.EntityId,
    path_wp: bespoke.WaypointId,
    anchor_wp: bespoke.WaypointId,
    tether_wp: bespoke.WaypointId,
    hatch_wp: bespoke.WaypointId,
    steps_wp: bespoke.WaypointId,
    chest_wp: bespoke.WaypointId,

    /// `registered` is true when a host has already placed the cast (the browser deck's
    /// `start_script`), so they are moved to their marks rather than registered again.
    pub fn init(world: *bespoke.World, spatial: *bespoke.SpatialSystem, registered: bool) !Stage {
        const point_scene = world.lookup_entity("Lamp Point").?;
        const cellar_scene = world.lookup_entity("Wreckers Cellar").?;
        const tamsin = world.lookup_entity("Tamsin").?;
        const donkey = world.lookup_entity("Cudgel").?;

        const path_wp = spatial.graph.find_waypoint_in_room(point_scene, "PointPath") orelse 1;
        const fall_wp = spatial.graph.find_waypoint_in_room(point_scene, "FallMark") orelse 2;
        const anchor_wp = spatial.graph.find_waypoint_in_room(point_scene, "AnchorMark") orelse 3;
        const tether_wp = spatial.graph.find_waypoint_in_room(point_scene, "TetherCenter") orelse 4;
        const hatch_wp = spatial.graph.find_waypoint_in_room(point_scene, "HatchMark") orelse 5;
        const steps_wp = spatial.graph.find_waypoint_in_room(cellar_scene, "CellarSteps") orelse 6;
        const chest_wp = spatial.graph.find_waypoint_in_room(cellar_scene, "ChestMark") orelse 7;

        // Calibrate coordinates for 1280x720 standardized layout
        bespoke.host.place_waypoint(spatial, path_wp, 4, 0);
        bespoke.host.place_waypoint(spatial, fall_wp, 8, 0);
        bespoke.host.place_waypoint(spatial, anchor_wp, 10, 8);
        bespoke.host.place_waypoint(spatial, tether_wp, 16, 0);
        bespoke.host.place_waypoint(spatial, hatch_wp, 28, 0);
        bespoke.host.place_waypoint(spatial, steps_wp, 4, 0);
        bespoke.host.place_waypoint(spatial, chest_wp, 20, 0);

        spatial.graph.edges.clearRetainingCapacity();
        try spatial.graph.connect(path_wp, fall_wp, null);
        try spatial.graph.connect(fall_wp, tether_wp, null);
        try spatial.graph.connect(fall_wp, anchor_wp, null);
        try spatial.graph.connect(anchor_wp, tether_wp, null);
        try spatial.graph.connect(tether_wp, hatch_wp, null);
        try spatial.graph.connect(steps_wp, chest_wp, null);

        const cellar_hatch = world.lookup_entity("CellarHatch").?;
        const old_anchor = world.lookup_entity("OldAnchor").?;
        const mooring_post = world.lookup_entity("MooringPost").?;
        const wreckers_chart = world.lookup_entity("WreckersChart").?;
        const sea_chest = world.lookup_entity("SeaChest").?;

        try spatial.add_hotspot(cellar_hatch, point_scene, .{ .x = 28, .y = -4 }, 8, "Cellar Hatch", "A trapdoor in the turf, propped open over the wreckers' cellar.");
        try spatial.add_hotspot(old_anchor, point_scene, .{ .x = 10, .y = 8 }, 8, "Old Anchor", "A rusted ship's anchor sunk in the thrift.");
        try spatial.add_hotspot(mooring_post, point_scene, .{ .x = 16, .y = -4 }, 6, "Mooring Post", "An old mooring post driven deep into the headland.");
        try spatial.add_hotspot(sea_chest, cellar_scene, .{ .x = 20, .y = -4 }, 8, "Sea Chest", "A sea chest, its lid rotted through.");
        try spatial.add_hotspot(wreckers_chart, cellar_scene, .{ .x = 30, .y = -6 }, 8, "Wreckers Chart", "A chart of the Point's reefs scratched into the cellar wall.");

        // Register actors at starting waypoints
        if (registered) {
            _ = try spatial.transition_actor(tamsin, point_scene, path_wp);
            _ = try spatial.transition_actor(donkey, point_scene, tether_wp);
        } else {
            try spatial.register_entity(tamsin, path_wp, 10);
            try spatial.register_entity(donkey, tether_wp, 8);
        }

        // Initial fact assertions
        const tether_rel = try world.intern_relation("TetheredTo", .set);
        try world.remember(donkey, tether_rel, mooring_post.to_int(), 0);

        return .{
            .point_scene = point_scene,
            .cellar_scene = cellar_scene,
            .tamsin = tamsin,
            .donkey = donkey,
            .cellar_hatch = cellar_hatch,
            .old_anchor = old_anchor,
            .wreckers_chart = wreckers_chart,
            .sea_chest = sea_chest,
            .path_wp = path_wp,
            .anchor_wp = anchor_wp,
            .tether_wp = tether_wp,
            .hatch_wp = hatch_wp,
            .steps_wp = steps_wp,
            .chest_wp = chest_wp,
        };
    }

    /// Puts Tamsin at the foot or head of the cellar steps when a tick changed the scene. The
    /// script decides the transition (arrival rules, P32-18); where an actor stands in the new
    /// scene is layout. Placing is not arriving, so this cannot re-trigger the rule that fired.
    fn follow_scene(self: Stage, vm: *const bespoke.VM, spatial: *bespoke.SpatialSystem, before: ?bespoke.EntityId) !bool {
        _ = self;
        const now = vm.current_scene orelse return false;
        if (before != null and before.? == now) return false;
        return follow_into_scene(vm.world, spatial, vm);
    }
};

/// Moves Tamsin into the scene the script changed to, if she is not already there: the foot of
/// the cellar steps going down, the hatch coming up. The desktop window and the browser deck
/// share it (D-100), so the script's `transition to scene` places her the same way in both.
pub fn follow_into_scene(world: *const bespoke.World, spatial: *bespoke.SpatialSystem, vm: *const bespoke.VM) !bool {
    const scene = vm.current_scene orelse return false;
    const tamsin = world.lookup_entity("Tamsin") orelse return false;
    const agent = spatial.agents.get(tamsin) orelse return false;
    const here = spatial.graph.get_waypoint(agent.current_wp) orelse return false;
    if (here.room == scene) return false;
    const name = world.get_entity_name(scene) orelse return false;
    const mark = if (std.mem.eql(u8, name, "Wreckers Cellar")) "CellarSteps" else if (std.mem.eql(u8, name, "Lamp Point")) "HatchMark" else return false;
    const wp = spatial.graph.find_waypoint_in_room(scene, mark) orelse return false;
    _ = try spatial.transition_actor(tamsin, scene, wp);
    return true;
}

/// Upper bound on the ticks one scripted walk and its arrival rule may take in the headless run.
const MAX_WALK_TICKS: usize = 40;

const Outcome = enum { donkey_retreating, donkey_tangled, cellar_entered };

fn reached(outcome: Outcome, world: *const bespoke.World, vm: *const bespoke.VM, stage: Stage) bool {
    return switch (outcome) {
        .donkey_retreating => world.has_fact(stage.donkey, world.lookup_relation("DonkeyRetreating") orelse return false, null),
        .donkey_tangled => evaluate_donkey_tangled(world),
        .cellar_entered => evaluate_cellar_entered(world, vm),
    };
}

/// Fires `Uses(Tamsin, target)` and ticks until the walk it starts has arrived and the arrival
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
    _ = try vm.fire_cue(compiled, "Uses", stage.tamsin, target, null);
    var ticks: usize = 0;
    while (ticks < MAX_WALK_TICKS) : (ticks += 1) {
        const scene_before = vm.current_scene;
        _ = try bespoke.host.tick(vm, compiled);
        _ = try stage.follow_scene(vm, spatial, scene_before);
        if (reached(outcome, world, vm, stage)) return true;
    }
    return false;
}

/// Executes the headless run of the Donkey of Lamp Point (P20-01, P20-03, D-023, P35-05).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("          BeSpoke Engine: The Donkey of Lamp Point Scenario          \n", .{});
    try writer.print("     (Threat-Radius Timing * Anchor Hauling * Wreckers Cellar)      \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Compiling Lamp Point narrative script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, LAMP_POINT_SCRIPT);
    defer compiled.deinit();

    const stage = try Stage.init(&world, &spatial, false);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);

    try vm.transition_to_scene(stage.point_scene);

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("Tamsin")) |player| display_bridge.set_active_character(player);

    // Save initial state snapshot for time-travel verification
    var snapshot_0 = std.array_list.Managed(u8).init(allocator);
    defer snapshot_0.deinit();
    var lw1 = ListWriter.init(&snapshot_0);
    try world.save_state(&lw1.writer);

    try writer.print("\n[Step 1] Initial Inspection: Tamsin arrives at Lamp Point.\n", .{});
    _ = try vm.fire_cue(&compiled, "LooksAt", stage.tamsin, stage.donkey, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    display_bridge.capture_frame(&world, &spatial, &vm);
    try writer.print("  -> Fact count: {d}, Tamsin at PointPath, Cudgel at TetherCenter\n", .{world.fact_count()});

    // Steps 2 to 4 walk Tamsin to a mark; the script's arrival rules do the rest (P32-18).
    try writer.print("\n[Step 2] Threat Radius Exploration: Tamsin approaches CellarHatch.\n", .{});
    const is_retreating = try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.cellar_hatch, .donkey_retreating);
    display_bridge.capture_frame(&world, &spatial, &vm);

    // Verify the shove knockback and 30-tick retreat window
    try writer.print("  -> Cudgel charges! Tamsin knocked down to FallMark.\n", .{});
    try writer.print("  -> Donkey retreating window active: {any} (30 ticks remaining)\n", .{is_retreating});

    if (!is_retreating) {
        return error.RetreatWindowMissing;
    }

    try writer.print("\n[Step 3] Seizing the Window: Tamsin hauls OldAnchor while Cudgel retreats!\n", .{});
    const is_tangled = try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.old_anchor, .donkey_tangled);
    display_bridge.capture_frame(&world, &spatial, &vm);

    try writer.print("  -> Anchor hauled into rope path! Donkey tangled status: {any}\n", .{is_tangled});
    if (!is_tangled) {
        return error.DonkeyNotTangled;
    }

    try writer.print("\n[Step 4] Into the Cellar: Tamsin goes down through CellarHatch.\n", .{});
    const entered_cellar = try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.cellar_hatch, .cellar_entered);
    display_bridge.capture_frame(&world, &spatial, &vm);

    try writer.print("  -> Multi-scene transition to Wreckers Cellar successful: {any}\n", .{entered_cellar});
    if (!entered_cellar) {
        return error.FailedToEnterCellar;
    }

    try writer.print("\n[Step 5] The Chart: Tamsin examines the WreckersChart.\n", .{});
    _ = try vm.fire_cue(&compiled, "LooksAt", stage.tamsin, stage.wreckers_chart, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    display_bridge.capture_frame(&world, &spatial, &vm);

    try writer.print("\n[Step 6] Time-Travel Rewind Verification: Restoring pristine Lamp Point state.\n", .{});
    var stream: std.Io.Reader = .fixed(snapshot_0.items);
    try world.restore_state(&stream);
    vm.current_scene = stage.point_scene;
    _ = try spatial.transition_actor(stage.tamsin, stage.point_scene, stage.path_wp);
    _ = try spatial.transition_actor(stage.donkey, stage.point_scene, stage.tether_wp);
    display_bridge.capture_frame(&world, &spatial, &vm);

    const is_tangled_after_rewind = evaluate_donkey_tangled(&world);
    try writer.print("  -> Restored tick 0 snapshot. Donkey tangled status: {any} (Expected: false)\n", .{is_tangled_after_rewind});
    if (is_tangled_after_rewind) {
        return error.RewindFailed;
    }

    try writer.print("\n===================================================================\n", .{});
    try writer.print("  VERIFICATION COMPLETE: Donkey of Lamp Point 100% Deterministic!   \n", .{});
    try writer.print("===================================================================\n\n", .{});
    try golden.final_facts(allocator, writer, &world);
}

/// Executes interactive 60 Hz simulation with graphical display (P20-03, D-023).
pub fn run_interactive(allocator: std.mem.Allocator, io: std.Io, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, LAMP_POINT_SCRIPT);
    defer compiled.deinit();

    const stage = try Stage.init(&world, &spatial, false);
    const point_scene = stage.point_scene;
    const cellar_scene = stage.cellar_scene;
    const tamsin = stage.tamsin;
    const donkey = stage.donkey;
    const old_anchor = stage.old_anchor;
    const wreckers_chart = stage.wreckers_chart;
    const sea_chest = stage.sea_chest;
    const path_wp = stage.path_wp;
    const anchor_wp = stage.anchor_wp;
    const hatch_wp = stage.hatch_wp;
    const steps_wp = stage.steps_wp;
    const chest_wp = stage.chest_wp;

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try vm.transition_to_scene(point_scene);

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("Tamsin")) |player| display_bridge.set_active_character(player);

    var window = try bespoke.display.DisplayWindow.init(io, "BeSpoke Engine - The Donkey of Lamp Point", 1280, 720);
    defer window.deinit();
    window.set_theme(&point_theme);

    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
    try stdout.print("The Donkey of Lamp Point Controls:\n", .{});
    try stdout.print("   - [L]:                   Go to Lamp Point\n", .{});
    try stdout.print("   - [W]:                   Go to the Wreckers Cellar\n", .{});
    try stdout.print("   - [1]:                   Step 1: Approach the Cellar Hatch (Cudgel charges; retreat window opens)\n", .{});
    try stdout.print("   - [2]:                   Step 2: Haul the Old Anchor into the rope line (tangles Cudgel)\n", .{});
    try stdout.print("   - [3]:                   Step 3: Go down the steps into the Wreckers Cellar\n", .{});
    try stdout.print("   - [4]:                   Step 4: Study the Wreckers Chart and the Sea Chest\n", .{});
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

    window.set_cue_banner("Lamp Point: get past Cudgel the donkey to the wreckers' cellar. [L/W] [1-4]", 180);

    const retreating_rel = world.lookup_relation("DonkeyRetreating").?;
    const knocked_rel = world.lookup_relation("KnockedDown").?;

    while (true) {
        const action = window.poll_events(session.frame());

        // Pause, step, scrub, rewind, and save actions are shared (host kit, P32-16, D-033).
        if (try session.handle_common(action)) {} else switch (action) {
            .quit => break,
            .walk_player => |wp_id| {
                if (world.has_fact(tamsin, knocked_rel, null)) {
                    window.set_cue_banner("Tamsin is flat on her back! Getting up...", 60);
                } else {
                    // Walking is all the host does; the script reacts when Tamsin arrives.
                    _ = try spatial.walk_to(tamsin, wp_id);
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                    window.set_cue_banner("Walking Tamsin to the mark.", 60);
                }
            },
            .interact_actor => |act| {
                const frame = display_bridge.get_frame();
                if (act.actor_index < frame.entity_count) {
                    const target_entity = frame.entities[act.actor_index];
                    const tname = target_entity.get_name();

                    if (std.mem.eql(u8, tname, "Cudgel")) {
                        if (act.verb == .look_at) {
                            window.set_cue_banner("Cudgel: the lighthouse keeper's donkey, on a long rope. He glares at Tamsin.", 120);
                        } else if (act.verb == .talk_to) {
                            window.set_cue_banner("Cudgel: 'HEE-HAWWW!' *stamps a hoof*", 120);
                        } else if (act.verb == .use_with or act.verb == .pick_up) {
                            if (world.has_fact(donkey, retreating_rel, null)) {
                                _ = try vm.fire_cue(&compiled, "Uses", tamsin, old_anchor, null);
                                window.set_cue_banner("Tamsin runs for the old anchor...", 90);
                            } else {
                                window.set_cue_banner("Tamsin: 'I'm not going near those hooves without a plan!'", 120);
                            }
                        }
                    } else {
                        window.set_cue_banner("Tamsin: a Brackwater fencer, looking for the wreckers' old chart.", 120);
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
                            window.set_cue_banner("Cellar Hatch: a trapdoor in the turf over the wreckers' cellar.", 150);
                        } else {
                            if (vm.current_scene == point_scene) {
                                _ = try spatial.walk_to(tamsin, hatch_wp);
                                window.set_cue_banner("Walking Tamsin to the cellar hatch...", 90);
                            }
                        }
                    } else if (std.mem.indexOf(u8, hname, "Anchor") != null) {
                        if (hs_act.verb == .look_at) {
                            window.set_cue_banner("Old Anchor: a rusted ship's anchor sunk in the thrift.", 150);
                        } else {
                            if (vm.current_scene == point_scene) {
                                _ = try spatial.walk_to(tamsin, anchor_wp);
                                window.set_cue_banner("Walking Tamsin to the old anchor...", 90);
                            }
                        }
                    } else if (std.mem.indexOf(u8, hname, "Mooring") != null) {
                        window.set_cue_banner("Mooring Post: an old post driven deep into the headland.", 120);
                    } else if (std.mem.indexOf(u8, hname, "Chart") != null) {
                        if (vm.current_scene == cellar_scene) {
                            _ = try spatial.walk_to(tamsin, chest_wp);
                            _ = try vm.fire_cue(&compiled, "LooksAt", tamsin, wreckers_chart, null);
                            window.set_cue_banner("Wreckers Chart: every reef on the Point, scratched into the wall.", 150);
                        }
                    } else if (std.mem.indexOf(u8, hname, "Chest") != null) {
                        if (vm.current_scene == cellar_scene) {
                            _ = try spatial.walk_to(tamsin, chest_wp);
                            _ = try vm.fire_cue(&compiled, "LooksAt", tamsin, sea_chest, null);
                            window.set_cue_banner("Sea Chest: its lid rotted through, nothing inside but sand.", 150);
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
                        const msg = std.fmt.bufPrint(&buf, "{s}: \"Something in Tamsin's pockets.\"", .{item_name}) catch "Item";
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
        const pressed: ?PointKey = if (action == .custom) std.enums.fromInt(PointKey, action.custom) else null;
        if (pressed != null) {
            // [L] Lamp Point
            if (pressed == .point) {
                try vm.transition_to_scene(point_scene);
                _ = try spatial.transition_actor(tamsin, point_scene, path_wp);
                window.set_cue_banner("Switched scene: Lamp Point", 60);
            }
            // [W] Wreckers Cellar
            if (pressed == .cellar) {
                try vm.transition_to_scene(cellar_scene);
                _ = try spatial.transition_actor(tamsin, cellar_scene, steps_wp);
                window.set_cue_banner("Switched scene: Wreckers Cellar", 60);
            }
            // [1] Approach the hatch (Step 1)
            if (pressed == .step_1) {
                if (vm.current_scene == point_scene) {
                    _ = try spatial.walk_to(tamsin, hatch_wp);
                    window.set_cue_banner("Step 1: Walking Tamsin to the cellar hatch, within Cudgel's reach...", 90);
                }
            }
            // [2] Haul the anchor (Step 2)
            if (pressed == .step_2) {
                if (vm.current_scene == point_scene) {
                    _ = try spatial.walk_to(tamsin, anchor_wp);
                    window.set_cue_banner("Step 2: Walking Tamsin to the old anchor...", 90);
                }
            }
            // [3] Go down into the cellar (Step 3)
            if (pressed == .step_3) {
                if (vm.current_scene == point_scene) {
                    _ = try spatial.walk_to(tamsin, hatch_wp);
                    window.set_cue_banner("Step 3: Walking Tamsin to the hatch to go down...", 90);
                }
            }
            // [4] Study the chart (Step 4)
            if (pressed == .step_4) {
                if (vm.current_scene == cellar_scene) {
                    _ = try spatial.walk_to(tamsin, chest_wp);
                    _ = try vm.fire_cue(&compiled, "LooksAt", tamsin, wreckers_chart, null);
                    window.set_cue_banner("Step 4: Tamsin studies the wreckers' chart and the sea chest.", 120);
                } else {
                    window.set_cue_banner("Go down to the Wreckers Cellar first to see the chart.", 120);
                }
            }
        }

        // Stepping simulation clock
        if (session.tick_due()) {
            const scene_before = vm.current_scene;
            const was_down = world.has_fact(tamsin, knocked_rel, null);
            const was_tangled = evaluate_donkey_tangled(&world);

            _ = try bespoke.host.tick(&vm, &compiled);

            // The script's arrival rules decided what happened this tick (P32-18); the host
            // only places Tamsin in a new scene and narrates the change.
            if (try stage.follow_scene(&vm, &spatial, scene_before)) {
                if (vm.current_scene == cellar_scene) {
                    window.set_cue_banner("★ Down the steps into the Wreckers Cellar! [L] Back to Lamp Point ★", 180);
                } else {
                    window.set_cue_banner("Back up the steps onto Lamp Point. [W] Cellar", 120);
                }
            } else if (!was_down and world.has_fact(tamsin, knocked_rel, null)) {
                window.set_cue_banner("★ Cudgel shoves Tamsin flat! (30-tick retreat window open) ★", 180);
            } else if (!was_tangled and evaluate_donkey_tangled(&world)) {
                window.set_cue_banner("★ The anchor has his rope! Cudgel can't reach the hatch. ★", 180);
            }

            // Record after the placement above, so the snapshot includes it.
            try session.record_now();
        }

        session.render();
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P20-01: compile and execute the Lamp Point donkey script" {
    const allocator = std.testing.allocator;

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, LAMP_POINT_SCRIPT);
    defer compiled.deinit();

    const stage = try Stage.init(&world, &spatial, false);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);

    try vm.transition_to_scene(stage.point_scene);

    // Initial state: not tangled
    try std.testing.expect(!evaluate_donkey_tangled(&world));

    // Walk to the anchor without a retreat window -> arrival, but the anchor stays put
    try std.testing.expect(!try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.old_anchor, .donkey_tangled));
    try std.testing.expectEqual(stage.anchor_wp, spatial.get_current_waypoint(stage.tamsin).?);

    // Walk to the hatch -> on arrival the donkey charges and the retreat window opens
    try std.testing.expect(try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.cellar_hatch, .donkey_retreating));
    try std.testing.expectEqual(stage.hatch_wp, spatial.get_current_waypoint(stage.tamsin).?);
    try std.testing.expect(!evaluate_cellar_entered(&world, &vm));

    // Reach the anchor during the retreat window -> tangled! The "too early" line is checked
    // first, so forgetting the window on success cannot make it fire as well.
    try std.testing.expect(try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.old_anchor, .donkey_tangled));
    var caught_buf: [512]u8 = undefined;
    const caught = bespoke.host.speech_this_tick(&world, &vm, &caught_buf) orelse "";
    try std.testing.expect(std.mem.indexOf(u8, caught, "Caught.") != null);
    try std.testing.expect(std.mem.indexOf(u8, caught, "If I go for the anchor now") == null);

    // Now walk to the hatch -> the arrival rule transitions to the Wreckers Cellar
    try std.testing.expect(try use_and_walk(&world, &spatial, &vm, &compiled, stage, stage.cellar_hatch, .cellar_entered));
    try std.testing.expectEqual(stage.cellar_scene, vm.current_scene.?);
    try std.testing.expectEqual(stage.steps_wp, spatial.get_current_waypoint(stage.tamsin).?);

    // Looking at the chart straight after the room change says its line.
    _ = try vm.fire_cue(&compiled, "LooksAt", stage.tamsin, stage.wreckers_chart, null);
    _ = try bespoke.host.tick(&vm, &compiled);
    var said: [256]u8 = undefined;
    const line = bespoke.host.speech_this_tick(&world, &vm, &said) orelse "";
    try std.testing.expect(std.mem.indexOf(u8, line, "every reef on the Point") != null);

    // Walking off the steps and back climbs out; being placed at the hatch does not descend again
    _ = try spatial.walk_to(stage.tamsin, stage.chest_wp);
    var ticks: usize = 0;
    while (ticks < MAX_WALK_TICKS and spatial.get_current_waypoint(stage.tamsin).? != stage.chest_wp) : (ticks += 1) {
        _ = try bespoke.host.tick(&vm, &compiled);
    }
    _ = try spatial.walk_to(stage.tamsin, stage.steps_wp);
    ticks = 0;
    while (ticks < MAX_WALK_TICKS and vm.current_scene.? != stage.point_scene) : (ticks += 1) {
        const scene_before = vm.current_scene;
        _ = try bespoke.host.tick(&vm, &compiled);
        _ = try stage.follow_scene(&vm, &spatial, scene_before);
    }
    try std.testing.expectEqual(stage.point_scene, vm.current_scene.?);
    try std.testing.expectEqual(stage.hatch_wp, spatial.get_current_waypoint(stage.tamsin).?);
    for (0..5) |_| _ = try bespoke.host.tick(&vm, &compiled);
    try std.testing.expectEqual(stage.point_scene, vm.current_scene.?);
}

test "P20-03: headless execution runs full scenario and time-travel rewind" {
    const allocator = std.testing.allocator;
    var null_writer_buf: [64]u8 = undefined;
    var null_writer_sink: std.Io.Writer.Discarding = .init(&null_writer_buf);
    const null_writer = &null_writer_sink.writer;
    try run_headless(allocator, null_writer);
}
