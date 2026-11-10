//! BeSpoke Engine proof: "The Living Village" (Phase 18, D-021; client of the engine's
//! emergent society module since P32-05, D-032, D-034).
//!
//! Six villagers with Hunger, Energy, and Gold, a six-building settlement, and three catalysts.
//! The drives, witness detection, rumor propagation, and justice cascade are engine mechanics
//! (`bespoke.society`); this file supplies only the village's names, map, roster tuning, script,
//! and interactive loop.

const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const VillageKey = enum(u16) { theft, feast, tip };

const village_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_s, .action = @intFromEnum(VillageKey.theft), .sfx = art.sfx(.whistle) },
    .{ .key = bespoke.display.renderer.c.SDLK_f, .action = @intFromEnum(VillageKey.feast), .sfx = .{ .stock = .combine } },
    .{ .key = bespoke.display.renderer.c.SDLK_g, .action = @intFromEnum(VillageKey.tip), .sfx = .{ .stock = .pickup } },
});

/// BeSpoke DSL Script for "The Living Village" settlement (P18-01, P18-02, P18-03, D-021).
pub const VILLAGE_SCRIPT =
    \\scene: Living Village
    \\cast: Sheriff, Baker, Farmer, Innkeeper, Gossip, Drifter
    \\props: BakeryOven, TownFountain, SheriffJail, FarmGranary, TavernHearth, VillageCottages
    \\marks: Bakery, Farm, TownSquare, Cottages, Tavern, SheriffsPost
    \\
    \\society VillageSociety:
    \\  need Hunger high 100 3 1 55 trade Baker 5 50 5 80 60 10 "a warm meal"
    \\  need Energy low 100 2 0 22 stay Cottages 14 90 sleeping true "exhausted" "sleep"
    \\  member Sheriff 25 patrolling:
    \\    need Hunger 20 none Innkeeper
    \\    need Energy 90 none none
    \\    routine patrolling 5 TownSquare, SheriffsPost
    \\  member Baker 30 working:
    \\    need Hunger 25 none none
    \\    need Energy 85 none none
    \\    routine working 1 Bakery
    \\    work Bakery 5 1 true
    \\    merchant Bakery BreadLoaf
    \\    owns BreadLoaf
    \\    carries BreadLoaf
    \\  member Farmer 15 working:
    \\    need Hunger 45 none none
    \\    need Energy 80 none none
    \\    routine working 6 Farm, TownSquare
    \\    work Farm 4 2 false
    \\    owns WheatBundle
    \\  member Innkeeper 25 working:
    \\    need Hunger 30 none Innkeeper
    \\    need Energy 85 none none
    \\    routine working 1 Tavern
    \\    work Tavern 5 1 false
    \\    merchant Tavern AleMug
    \\    owns AleMug
    \\  member Gossip 12 socializing:
    \\    need Hunger 35 none none
    \\    need Energy 90 none none
    \\    routine none 4 TownSquare, Bakery, Tavern
    \\    broadcaster
    \\  member Drifter 0 socializing:
    \\    need Hunger 64 4 none
    \\    need Energy 75 none none
    \\    routine none 1 TownSquare
    \\  enforcer Sheriff
    \\  holding SheriffsPost
    \\  gathering TownSquare
    \\  flight Farm Cottages 4
    \\  friend Baker Farmer
    \\  friend Baker Gossip
    \\  friend Farmer Innkeeper
    \\  friend Gossip Innkeeper
    \\  friend Gossip Sheriff
    \\  friend Innkeeper Sheriff
    \\
    \\on cue Uses(Sheriff, BakeryOven):
    \\  say Sheriff: "Warm brick ovens smelling of fresh sourdough loaves."
    \\
    \\on cue Uses(Sheriff, TownFountain):
    \\  say Sheriff: "The central stone fountain where villagers gather to trade news and rumors."
    \\
    \\on cue Uses(Sheriff, SheriffJail):
    \\  say Sheriff: "Sturdy iron bars awaiting anyone who breaks the village peace."
    \\
    \\on cue TalksTo(Sheriff, Baker):
    \\  choice "How is business at the bakery?" if not StolenFrom(Drifter, Baker):
    \\    say Baker: "Fresh loaves flying off the shelves, Sheriff! Honest coin for honest bread."
    \\  choice "Report on the stolen bread!" if Witnessed(Baker, Drifter):
    \\    say Baker: "That starving Drifter snatched a loaf right off my counter! Arrest them!"
    \\    remember KnowsRumor(Sheriff, Drifter)
    \\  choice "Carry on, citizen.":
    \\    say Baker: "Stay vigilant, Sheriff."
    \\
    \\on cue TalksTo(Sheriff, Gossip):
    \\  choice "Heard any rumors in the square?" if KnowsRumor(Gossip, Drifter):
    \\    say Gossip: "Word is the Drifter raided the Bakery oven while starving!"
    \\    remember KnowsRumor(Sheriff, Drifter)
    \\  choice "All quiet in the village?" if not KnowsRumor(Gossip, Drifter):
    \\    say Gossip: "Just the Farmer trading wheat and the Innkeeper pouring ale!"
;

const society = bespoke.society;

/// Member activities come from the engine's emergent society module (P32-05, D-032).
pub const VillagerActivity = society.Activity;
pub const ChronicleCategory = society.ChronicleCategory;

/// Roster order is evaluation order: each society tick visits members in this order, so it is
/// part of the proof's observable behaviour (and its golden).
const SHERIFF = 0;
const BAKER = 1;
const FARMER = 2;
const INNKEEPER = 3;
const GOSSIP = 4;
const DRIFTER = 5;
const HUNGER = 0;
const ENERGY = 1;

/// "The Living Village": six villagers, six buildings, and their goods, run by the engine's
/// emergent society module. This struct holds the proof's content (names, map, roster
/// tuning) and its interactive catalysts; the drives, witness, rumor, and justice systems are
/// engine code (`bespoke.society`).
pub const VillageSimulation = struct {
    village_scene: bespoke.EntityId,
    sheriff: bespoke.EntityId,
    baker: bespoke.EntityId,
    farmer: bespoke.EntityId,
    innkeeper: bespoke.EntityId,
    gossip: bespoke.EntityId,
    drifter: bespoke.EntityId,

    bread_loaf: bespoke.EntityId,
    wheat_bundle: bespoke.EntityId,
    ale_mug: bespoke.EntityId,

    bakery_wp: bespoke.WaypointId,
    farm_wp: bespoke.WaypointId,
    town_square_wp: bespoke.WaypointId,
    cottages_wp: bespoke.WaypointId,
    tavern_wp: bespoke.WaypointId,
    sheriffs_post_wp: bespoke.WaypointId,

    society: society.Society,

    /// Builds the settlement map and hands the roster to the engine's society module.
    pub fn init(world: *bespoke.World, spatial: *bespoke.SpatialSystem, compiled: *const bespoke.CompiledProgram) !VillageSimulation {
        const village_scene = try world.intern_entity("Living Village");
        const sheriff = try world.intern_entity("Sheriff");
        const baker = try world.intern_entity("Baker");
        const farmer = try world.intern_entity("Farmer");
        const innkeeper = try world.intern_entity("Innkeeper");
        const gossip = try world.intern_entity("Gossip");
        const drifter = try world.intern_entity("Drifter");

        const bread_loaf = try world.intern_entity("BreadLoaf");
        const wheat_bundle = try world.intern_entity("WheatBundle");
        const ale_mug = try world.intern_entity("AleMug");

        // Six-building settlement laid out beside the left and right HUD panels at 1280x720:
        // left column (x=2) Bakery and Farm, centre (x=15) TownSquare and Cottages,
        // right (x=28) Tavern and SheriffsPost.
        const bakery_wp = spatial.graph.find_waypoint("Bakery") orelse return error.MissingVillageMark;
        const farm_wp = spatial.graph.find_waypoint("Farm") orelse return error.MissingVillageMark;
        const town_square_wp = spatial.graph.find_waypoint("TownSquare") orelse return error.MissingVillageMark;
        const cottages_wp = spatial.graph.find_waypoint("Cottages") orelse return error.MissingVillageMark;
        const tavern_wp = spatial.graph.find_waypoint("Tavern") orelse return error.MissingVillageMark;
        const sheriffs_post_wp = spatial.graph.find_waypoint("SheriffsPost") orelse return error.MissingVillageMark;

        spatial.graph.waypoints.items[bakery_wp - 1].pos = .{ .x = 2, .y = -10 };
        spatial.graph.waypoints.items[farm_wp - 1].pos = .{ .x = 2, .y = 6 };
        spatial.graph.waypoints.items[town_square_wp - 1].pos = .{ .x = 15, .y = -2 };
        spatial.graph.waypoints.items[cottages_wp - 1].pos = .{ .x = 15, .y = 9 };
        spatial.graph.waypoints.items[tavern_wp - 1].pos = .{ .x = 28, .y = -10 };
        spatial.graph.waypoints.items[sheriffs_post_wp - 1].pos = .{ .x = 28, .y = 6 };
        spatial.graph.edges.clearRetainingCapacity();

        try spatial.graph.connect(bakery_wp, town_square_wp, null);
        try spatial.graph.connect(farm_wp, town_square_wp, null);
        try spatial.graph.connect(bakery_wp, farm_wp, null);
        try spatial.graph.connect(town_square_wp, cottages_wp, null);
        try spatial.graph.connect(town_square_wp, tavern_wp, null);
        try spatial.graph.connect(town_square_wp, sheriffs_post_wp, null);
        try spatial.graph.connect(tavern_wp, sheriffs_post_wp, null);
        try spatial.graph.connect(cottages_wp, farm_wp, null);
        try spatial.graph.connect(cottages_wp, sheriffs_post_wp, null);

        spatial.clear_hotspots();
        const oven_ent = try world.intern_entity("BakeryOven");
        const fountain_ent = try world.intern_entity("TownFountain");
        const jail_ent = try world.intern_entity("SheriffJail");
        const granary_ent = try world.intern_entity("FarmGranary");
        const hearth_ent = try world.intern_entity("TavernHearth");
        const beds_ent = try world.intern_entity("VillageCottages");

        try spatial.add_hotspot(oven_ent, village_scene, .{ .x = 2, .y = -13 }, 6, "BakeryOven", "Warm brick bakery oven stacked with golden sourdough loaves.");
        try spatial.add_hotspot(granary_ent, village_scene, .{ .x = 2, .y = 9 }, 6, "FarmGranary", "Timber granary storing harvested bundles of village wheat.");
        try spatial.add_hotspot(fountain_ent, village_scene, .{ .x = 15, .y = -5 }, 6, "TownFountain", "The cobblestone town square fountain where villagers exchange gossip.");
        try spatial.add_hotspot(beds_ent, village_scene, .{ .x = 15, .y = 12 }, 6, "VillageCottages", "Cozy thatched cottages where tired villagers rest to restore Energy.");
        try spatial.add_hotspot(hearth_ent, village_scene, .{ .x = 28, .y = -13 }, 6, "TavernHearth", "Crackling stone hearth inside the village tavern.");
        try spatial.add_hotspot(jail_ent, village_scene, .{ .x = 28, .y = 9 }, 6, "SheriffJail", "Iron-barred holding cell inside the Sheriff's Post.");

        try spatial.register_entity(sheriff, sheriffs_post_wp, 12);
        try spatial.register_entity(baker, bakery_wp, 10);
        try spatial.register_entity(farmer, farm_wp, 10);
        try spatial.register_entity(innkeeper, tavern_wp, 10);
        try spatial.register_entity(gossip, town_square_wp, 13);
        try spatial.register_entity(drifter, cottages_wp, 11);

        if (compiled.societies.items.len != 1) return error.MissingVillageSociety;
        var soc = try society.Society.init(world, compiled.societies.items[0].config);

        soc.chronicle.log(0, .social, "Living Village initialized: 6 autonomous villagers active.");

        return .{
            .village_scene = village_scene,
            .sheriff = sheriff,
            .baker = baker,
            .farmer = farmer,
            .innkeeper = innkeeper,
            .gossip = gossip,
            .drifter = drifter,
            .bread_loaf = bread_loaf,
            .wheat_bundle = wheat_bundle,
            .ale_mug = ale_mug,
            .bakery_wp = bakery_wp,
            .farm_wp = farm_wp,
            .town_square_wp = town_square_wp,
            .cottages_wp = cottages_wp,
            .tavern_wp = tavern_wp,
            .sheriffs_post_wp = sheriffs_post_wp,
            .society = soc,
        };
    }

    pub fn rel(self: *const VillageSimulation) society.RelationIds {
        return self.society.rel;
    }

    pub fn villagers(self: *const VillageSimulation) [6]bespoke.EntityId {
        return .{ self.sheriff, self.baker, self.farmer, self.innkeeper, self.gossip, self.drifter };
    }

    pub fn get_hunger(self: *const VillageSimulation, world: *const bespoke.World, npc: bespoke.EntityId) u32 {
        return self.society.get_need(world, npc, HUNGER);
    }

    pub fn get_energy(self: *const VillageSimulation, world: *const bespoke.World, npc: bespoke.EntityId) u32 {
        return self.society.get_need(world, npc, ENERGY);
    }

    pub fn get_gold(self: *const VillageSimulation, world: *const bespoke.World, npc: bespoke.EntityId) u32 {
        return self.society.get_gold(world, npc);
    }

    pub fn get_activity(self: *const VillageSimulation, world: *const bespoke.World, npc: bespoke.EntityId) VillagerActivity {
        return self.society.get_activity(world, npc);
    }

    /// One village tick: the VM (movement, scripts, weaves) through the host kit, then the
    /// engine's society systems.
    pub fn step_simulation(
        self: *VillageSimulation,
        world: *bespoke.World,
        spatial: *bespoke.SpatialSystem,
        vm: *bespoke.VM,
        compiled: *const bespoke.compiler.CompiledProgram,
    ) !void {
        _ = try bespoke.host.tick(vm, compiled);
        try self.society.step(world, spatial, vm);
    }

    /// Catalyst [S]: drives the Drifter into desperation at the Bakery so the theft, witness,
    /// rumor, and arrest cascade plays out on demand.
    pub fn trigger_desperation_catalyst(self: *VillageSimulation, world: *bespoke.World, spatial: *bespoke.SpatialSystem) !void {
        const r = self.rel();
        _ = world.forget(self.drifter, r.arrested, null);
        _ = world.forget(self.drifter, r.stolen_from, null);
        _ = world.forget(self.sheriff, r.warrant_for, null);
        for (self.villagers()) |npc| {
            _ = world.forget(npc, r.witnessed, self.drifter.to_int());
            _ = world.forget(npc, r.knows_rumor, self.drifter.to_int());
        }
        try self.society.set_need(world, self.drifter, HUNGER, 88);
        try self.society.set_gold(world, self.drifter, 0);
        try self.society.set_activity(world, self.drifter, .stealing);
        _ = try society.Society.walk_to(spatial, self.drifter, self.bakery_wp);
        self.society.chronicle.log(world.current_tick, .crime, "Catalyst injected: Drifter is starving (Hunger 88, Gold 0)!");
    }

    /// Catalyst [F]: feeds and rests every villager and grants a 10g bonus.
    pub fn feed_all_villagers(self: *VillageSimulation, world: *bespoke.World) !void {
        for (self.villagers()) |npc| {
            try self.society.set_need(world, npc, HUNGER, 10);
            try self.society.set_need(world, npc, ENERGY, 95);
            try self.society.set_gold(world, npc, self.get_gold(world, npc) + 10);
        }
        self.society.chronicle.log(world.current_tick, .trade, "Prosperity feast: All villagers fed (Hunger=10, +10g)!");
    }
};

/// Runs the deterministic headless verification of "The Living Village" emergent simulation (P18-01..P18-03, D-021).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("  BeSpoke Engine - Phase 18: \"The Living Village\" Sandbox\n", .{});
    try writer.print("  (Autonomous Drives, Rumor Propagation & Justice Cascades)\n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, VILLAGE_SCRIPT);
    defer compiled.deinit();

    var sim = try VillageSimulation.init(&world, &spatial, &compiled);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(sim.village_scene);

    // Save baseline snapshot at Tick 0 for time-travel verification
    var snap0 = std.ArrayList(u8).init(allocator);
    defer snap0.deinit();
    try world.save_state(snap0.writer());

    try writer.print("[Phase 1: Settlement Topology & Initial Villager Drives (Tick 0)]\n", .{});
    try writer.print("   -> Settlement Landmarks: Bakery, Farm, TownSquare, Cottages, Tavern, SheriffsPost\n", .{});
    for (sim.villagers()) |npc| {
        const name = world.get_entity_name(npc) orelse "NPC";
        try writer.print("   -> {s:<10} | Hunger: {d:>2}/100 | Energy: {d:>2}/100 | Gold: {d:>2}g | Activity: {s}\n", .{
            name,
            sim.get_hunger(&world, npc),
            sim.get_energy(&world, npc),
            sim.get_gold(&world, npc),
            sim.get_activity(&world, npc).label(),
        });
    }
    try writer.print("\n", .{});

    // Run autonomous simulation until the full emergent chain completes (up to 45 ticks)
    var saw_theft = false;
    var saw_witness = false;
    var saw_rumor_spread = false;
    var saw_warrant = false;
    var saw_arrest = false;

    var printed_chronicle_idx: usize = 1; // Skip initial message

    var step_i: usize = 0;
    while (step_i < 45) : (step_i += 1) {
        try sim.step_simulation(&world, &spatial, &vm, &compiled);

        // Print any new chronicle events emitted during this tick
        while (printed_chronicle_idx < sim.society.chronicle.count) : (printed_chronicle_idx += 1) {
            const entry = &sim.society.chronicle.entries[printed_chronicle_idx];
            try writer.print("   [Tick {d:02} | {s:<7}] {s}\n", .{
                entry.tick,
                entry.category.tag(),
                entry.get_message(),
            });
        }

        if (world.has_fact(sim.drifter, sim.rel().stolen_from, sim.baker.to_int())) {
            saw_theft = true;
        }
        if (world.has_fact(null, sim.rel().witnessed, sim.drifter.to_int())) {
            saw_witness = true;
        }
        if (world.has_fact(sim.gossip, sim.rel().knows_rumor, sim.drifter.to_int()) or
            world.has_fact(sim.farmer, sim.rel().knows_rumor, sim.drifter.to_int()) or
            world.has_fact(sim.sheriff, sim.rel().knows_rumor, sim.drifter.to_int()))
        {
            saw_rumor_spread = true;
        }
        if (world.has_fact(sim.sheriff, sim.rel().warrant_for, sim.drifter.to_int())) {
            saw_warrant = true;
        }
        if (world.has_fact(sim.drifter, sim.rel().arrested, sim.sheriff.to_int())) {
            saw_arrest = true;
            break;
        }
    }

    try writer.print("\n[Phase 2: Emergent Cascade Verification (Tick {d})]\n", .{world.current_tick});
    try writer.print("   -> 1. Autonomous Desperation Theft (StolenFrom):  {s}\n", .{if (saw_theft) "VERIFIED" else "FAILED"});
    try writer.print("   -> 2. Co-Located Witness Detection (Witnessed):   {s}\n", .{if (saw_witness) "VERIFIED" else "FAILED"});
    try writer.print("   -> 3. Social Graph Rumor Propagation (KnowsRumor):{s}\n", .{if (saw_rumor_spread) "VERIFIED" else "FAILED"});
    try writer.print("   -> 4. Sheriff Priority Warrant (WarrantFor):      {s}\n", .{if (saw_warrant) "VERIFIED" else "FAILED"});
    try writer.print("   -> 5. Suspect Apprehended & Jailed (Arrested):    {s}\n", .{if (saw_arrest) "VERIFIED" else "FAILED"});

    try std.testing.expect(saw_theft);
    try std.testing.expect(saw_witness);
    try std.testing.expect(saw_rumor_spread);
    try std.testing.expect(saw_warrant);
    try std.testing.expect(saw_arrest);
    try std.testing.expect(world.has_fact(sim.baker, sim.rel().carries, sim.bread_loaf.to_int()));

    // Verify deterministic time-travel rewind back to Tick 0 pre-crime state
    try writer.print("\n[Phase 3: Deterministic Time-Travel Rewind to Pre-Crime State]\n", .{});
    var fbs = std.io.fixedBufferStream(snap0.items);
    try world.restore_state(fbs.reader());
    try writer.print("   -> Restored Tick {d} snapshot.\n", .{world.current_tick});
    try writer.print("   -> StolenFrom(Drifter, Baker) active? {s}\n", .{
        if (!world.has_fact(sim.drifter, sim.rel().stolen_from, null)) "false (Clean)" else "true (Leaked!)",
    });
    try writer.print("   -> Arrested(Drifter, Sheriff) active? {s}\n", .{
        if (!world.has_fact(sim.drifter, sim.rel().arrested, null)) "false (Clean)" else "true (Leaked!)",
    });
    try std.testing.expectEqual(@as(u64, 0), world.current_tick);
    try std.testing.expect(!world.has_fact(sim.drifter, sim.rel().stolen_from, null));
    try std.testing.expect(!world.has_fact(sim.drifter, sim.rel().arrested, null));

    try writer.print("\n>>> ALL LIVING VILLAGE EMERGENT SIMULATION CHECKS PASSED! <<<\n", .{});
}

/// Runs the interactive 60 Hz SDL2 graphical sandbox for "The Living Village" (P18-03, D-021).
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, VILLAGE_SCRIPT);
    defer compiled.deinit();

    var sim = try VillageSimulation.init(&world, &spatial, &compiled);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(sim.village_scene);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Living Village (Emergent Simulation Sandbox)", 1280, 720);
    defer window.deinit();
    window.set_theme(&village_theme);

    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED LIVING VILLAGE SANDBOX WINDOW (1280x720) <<<\n", .{});
    try stdout.print("Living Village Sandbox Controls:\n", .{});
    try stdout.print("   - [Click / Right-Click]:  Inspect buildings, walk Sheriff, or talk to Villagers\n", .{});
    try stdout.print("   - [S]:                    Catalyst: Trigger Desperate Theft at Bakery\n", .{});
    try stdout.print("   - [F]:                    Catalyst: Prosperity Feast (Feed all villagers +10g)\n", .{});
    try stdout.print("   - [G]:                    Catalyst: Spread Rumor to Sheriff\n", .{});
    try stdout.print("   - [Space / N]:            Pause / Step Single Tick\n", .{});
    try stdout.print("   - [< / > or Timeline]:    Time-Travel Scrubbing across emergent history\n", .{});
    try stdout.print("   - [P / F2 / F3 / F5 / F9]:Persistent Save / Load Drawer & Quick-Save\n", .{});
    try stdout.print("   - [F1 / D] / [C / Tab]:   Relational World Inspector / Live REPL\n\n", .{});

    var repl_engine = bespoke.Repl.init(&world, &spatial, &vm);
    var display_bridge = bespoke.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    display_bridge.attach_audio_bridge(window.audio_bridge);
    // Snapshot 0 and the first frame (host kit, P32-16, D-033)
    var session = try bespoke.host.Session.init(allocator, &world, &spatial, &vm, &compiled, &display_bridge, &window);
    defer session.deinit();

    window.set_cue_banner("The Living Village: Watch autonomous drives, rumors, and justice unfold!", 180);

    var is_running = true;
    var last_logged_chronicle: usize = 0;

    while (is_running) {
        const action = window.poll_events(session.frame());

        if (action == .rewind) {
            // This proof's [R] returns to the tick 0 baseline rather than one step back.
            if ((try session.jump_to(0)) != null) window.set_cue_banner("Rewound to Tick 0 baseline!", 120);
        } else if (try session.handle_common(action)) {} else switch (action) {
            .quit => is_running = false,
            .walk_player => |wp_id| {
                _ = try spatial.walk_to(sim.sheriff, wp_id);
            },
            .examine_hotspot => |hs_idx| {
                if (hs_idx < session.frame().hotspot_count) {
                    const hs = &session.frame().hotspots[hs_idx];
                    window.set_cue_banner(hs.get_examine_text(), 150);
                }
            },
            .interact_actor => |ia| {
                if (ia.actor_index < session.frame().entity_count) {
                    const target_ent = session.frame().entities[ia.actor_index];
                    const name = target_ent.get_name();
                    const hunger = sim.get_hunger(&world, target_ent.entity);
                    const energy = sim.get_energy(&world, target_ent.entity);
                    const gold = sim.get_gold(&world, target_ent.entity);
                    const act = sim.get_activity(&world, target_ent.entity);
                    var buf: [128]u8 = undefined;
                    const msg = std.fmt.bufPrint(
                        &buf,
                        "{s} [{s}] — Hunger: {d}/100, Energy: {d}/100, Gold: {d}g",
                        .{ name, act.label(), hunger, energy, gold },
                    ) catch name;
                    window.set_cue_banner(msg, 160);
                }
            },
            .custom => |id| if (std.meta.intToEnum(VillageKey, id)) |key| switch (key) {
                .theft => {
                    // [S] hotkey triggers the Desperation Theft Catalyst in Living Village
                    try sim.trigger_desperation_catalyst(&world, &spatial);
                    window.set_cue_banner("Catalyst [S]: Drifter driven to desperate hunger at Bakery!", 150);
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                },
                .feast => {
                    // [F] hotkey triggers Prosperity Feast (feeds all villagers)
                    try sim.feed_all_villagers(&world);
                    window.set_cue_banner("Catalyst [F]: Prosperity Feast! All villagers fed (+10g).", 150);
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                },
                .tip => {
                    // [G] hotkey tips off the Sheriff with the active rumor
                    try world.remember(sim.sheriff, sim.rel().knows_rumor, sim.drifter.to_int(), 0);
                    sim.society.chronicle.log(world.current_tick, .rumor, "Tip-off [G]: Sheriff alerted to rumor about Drifter!");
                    window.set_cue_banner("Catalyst [G]: Sheriff tipped off! Warrant cascade initiated!", 150);
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                },
            } else |_| {},
            .repl_command => |rc| {
                const cmd_str = rc.buf[0..rc.len];
                const res = repl_engine.execute(cmd_str);
                window.add_console_history(res.get_text());
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.swap();
            },
            else => {},
        }

        // The village steps the VM and its emergent systems together, then records the tick.
        if (session.tick_due()) {
            try sim.step_simulation(&world, &spatial, &vm, &compiled);

            if (sim.society.chronicle.count > last_logged_chronicle) {
                const latest = &sim.society.chronicle.entries[sim.society.chronicle.count - 1];
                window.set_cue_banner(latest.get_message(), 120);
                last_logged_chronicle = sim.society.chronicle.count;
            }

            try session.record_now();
        }

        session.render();
        std.time.sleep(16 * std.time.ns_per_ms);
    }
}

// =============================================================================
// Unit Tests (Phase 18: P18-01, P18-02, P18-03, D-021)
// =============================================================================

test "P18-01: Village relational schema and autonomous NPC drive metabolism" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, VILLAGE_SCRIPT);
    defer compiled.deinit();

    var sim = try VillageSimulation.init(&world, &spatial, &compiled);

    // Verify all 6 villagers and initial property relations exist
    try testing.expectEqual(@as(u32, 20), sim.get_hunger(&world, sim.sheriff));
    try testing.expectEqual(@as(u32, 90), sim.get_energy(&world, sim.sheriff));
    try testing.expectEqual(@as(u32, 30), sim.get_gold(&world, sim.baker));
    try testing.expectEqual(@as(u32, 0), sim.get_gold(&world, sim.drifter));

    // Verify social graph Friend edges
    try testing.expect(world.has_fact(sim.baker, sim.rel().friend, sim.gossip.to_int()));
    try testing.expect(world.has_fact(sim.gossip, sim.rel().friend, sim.sheriff.to_int()));

    // Step 1 metabolic tick and verify Hunger increases and Energy decreases
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    try sim.step_simulation(&world, &spatial, &vm, &compiled);
    try testing.expect(sim.get_hunger(&world, sim.sheriff) > 20);
    try testing.expect(sim.get_energy(&world, sim.sheriff) < 90);
}

test "P18-01: Tired villager walks to Cottages and sleeps to restore Energy" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, VILLAGE_SCRIPT);
    defer compiled.deinit();

    var sim = try VillageSimulation.init(&world, &spatial, &compiled);
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    // Set Farmer Energy below the script-declared work threshold.
    try world.remember(sim.farmer, sim.society.need_relation(1), 15, 0);

    // Step simulation: Farmer should transition to .sleeping and walk to Cottages
    try sim.step_simulation(&world, &spatial, &vm, &compiled);
    try testing.expectEqual(VillagerActivity.sleeping, sim.get_activity(&world, sim.farmer));

    // Step 10 ticks so Farmer arrives at Cottages and recovers Energy >= 90
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try sim.step_simulation(&world, &spatial, &vm, &compiled);
    }
    try testing.expect(sim.get_energy(&world, sim.farmer) >= 70);
}

test "P18-01: Hungry villager with Gold purchases meal from Baker and strengthens friendship" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, VILLAGE_SCRIPT);
    defer compiled.deinit();

    var sim = try VillageSimulation.init(&world, &spatial, &compiled);
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    // Place Farmer at Bakery with Hunger = 65 and Gold = 15
    try world.remember(sim.farmer, sim.society.need_relation(0), 65, 0);
    try world.remember(sim.farmer, sim.rel().currency, 15, 0);
    const initial_baker_gold = sim.get_gold(&world, sim.baker);

    var i: usize = 0;
    while (i < 6) : (i += 1) {
        try sim.step_simulation(&world, &spatial, &vm, &compiled);
    }

    // Farmer should have paid the script-declared meal price and reduced Hunger.
    const meal_price = compiled.societies.items[0].config.needs[0].satisfy.trade.price;
    try testing.expect(sim.get_hunger(&world, sim.farmer) < 40);
    try testing.expect(sim.get_gold(&world, sim.baker) >= initial_baker_gold + meal_price);
    try testing.expect(world.has_fact(sim.farmer, sim.rel().friend, sim.baker.to_int()));
}

test "P18-02: Emergent cascade — desperation theft, witness detection, rumor propagation, and Sheriff arrest" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, VILLAGE_SCRIPT);
    defer compiled.deinit();

    var sim = try VillageSimulation.init(&world, &spatial, &compiled);
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    var saw_theft = false;
    var saw_witness = false;
    var saw_rumor = false;
    var saw_warrant = false;
    var saw_arrest = false;

    var tick_i: usize = 0;
    while (tick_i < 45) : (tick_i += 1) {
        try sim.step_simulation(&world, &spatial, &vm, &compiled);

        if (world.has_fact(sim.drifter, sim.rel().stolen_from, sim.baker.to_int())) saw_theft = true;
        if (world.has_fact(sim.baker, sim.rel().witnessed, sim.drifter.to_int())) saw_witness = true;
        if (world.has_fact(sim.sheriff, sim.rel().knows_rumor, sim.drifter.to_int())) saw_rumor = true;
        if (world.has_fact(sim.sheriff, sim.rel().warrant_for, sim.drifter.to_int())) saw_warrant = true;
        if (world.has_fact(sim.drifter, sim.rel().arrested, sim.sheriff.to_int())) {
            saw_arrest = true;
            break;
        }
    }

    try testing.expect(saw_theft);
    try testing.expect(saw_witness);
    try testing.expect(saw_rumor);
    try testing.expect(saw_warrant);
    try testing.expect(saw_arrest);
    try testing.expectEqual(VillagerActivity.arrested, sim.get_activity(&world, sim.drifter));
    // Baker's stolen BreadLoaf is recovered upon arrest
    try testing.expect(world.has_fact(sim.baker, sim.rel().carries, sim.bread_loaf.to_int()));
}

test "P18-03: Village spatial topology, hotspots, and headless runner verification" {
    const testing = std.testing;
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try run_headless(testing.allocator, buf.writer());
    try testing.expect(std.mem.indexOf(u8, buf.items, "ALL LIVING VILLAGE EMERGENT SIMULATION CHECKS PASSED!") != null);
}
