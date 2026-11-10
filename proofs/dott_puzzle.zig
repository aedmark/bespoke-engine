const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

pub const DOTT_PUZZLE_SCRIPT =
    \\scene: Colonial Workshop
    \\cast: Hoagie, Washington, BetsyRoss
    \\props: ChronoToilet1790, TimeCapsule1790, KumquatTree, RedPaintBucket
    \\marks: WorkshopDoor, Fireplace1790, KumquatLawn, CapsuleNiche1790, ToiletMark1790
    \\
    \\scene: Motel Lobby
    \\cast: Bernard, DrFred
    \\props: ChronoToilet1993, TimeCapsule1993, VintageWineBottle, TentacleFlyerProp
    \\marks: LobbyDesk, MotelEntrance, CapsuleNiche1993, ToiletMark1993
    \\
    \\scene: Dystopian Guard Post
    \\cast: Laverne, PurpleTentacle
    \\props: ChronoToilet2193, TentacleFlagProp, PowerSocketProp, FutureTree
    \\marks: GuardPost, RoofGutter, TreeBranch2193, ToiletMark2193
    \\
    \\CapsuleStatus is a state, which can be open or sealed. The time capsule is open in the scene.
    \\KumquatStatus is a state, which can be unpainted or painted_red. The tree is unpainted in the scene.
    \\TreeStatus is a state, which can be standing or chopped. The tree is standing in the scene.
    \\ToiletStatus is a state, which can be unpowered or powered. The chrono toilet is unpowered in the scene.
    \\
    \\on cue LooksAt(Bernard, VintageWineBottle):
    \\  say Bernard: "A dusty 1993 vintage bottle of red wine sitting on the motel desk."
    \\
    \\on cue LooksAt(Bernard, TentacleFlyerProp):
    \\  say Bernard: "A campaign flyer showing Purple Tentacle's triangular silhouette. 'Vote Purple for Global Domination!'"
    \\
    \\on cue LooksAt(Bernard, ChronoToilet1993):
    \\  say Bernard: "The Chron-o-John! Dr. Fred's temporal displacement unit disguised as standard plumbing."
    \\
    \\on cue LooksAt(Bernard, TimeCapsule1993):
    \\  say Bernard: "The motel lobby time capsule, sealed tight to preserve artifacts for centuries."
    \\
    \\on cue LooksAt(Bernard, DrFred):
    \\  say Bernard: "Dr. Fred Edison, pacing nervously while muttering about world domination and temporal coordinates."
    \\
    \\on cue LooksAt(Bernard, VintageWine):
    \\  say Bernard: "A bottle of fine 1993 vintage wine. Probably tastes better after aging 200 years."
    \\
    \\on cue LooksAt(Bernard, TentacleFlyer):
    \\  say Bernard: "Purple Tentacle's campaign propaganda: 'A suction cup in every pot!'"
    \\
    \\on cue LooksAt(Bernard, Vinegar200Years):
    \\  say Bernard: "Pungent, highly acidic vinegar, cured over two whole centuries in the time capsule!"
    \\
    \\on cue LooksAt(Bernard, LobbyDesk):
    \\  say Bernard: "The motel registration desk. A classic bell, guestbook, and decades of neglect."
    \\
    \\on cue LooksAt(Bernard, MotelEntrance):
    \\  say Bernard: "Double doors leading outside to the motel driveway. Better stay focused on saving the world."
    \\
    \\on cue LooksAt(Bernard, CapsuleNiche1993):
    \\  say Bernard: "The display niche where the bicentennial time capsule is embedded in the wall."
    \\
    \\on cue LooksAt(Bernard, ToiletMark1993):
    \\  say Bernard: "Restroom tiles around the 1993 Chron-o-John."
    \\
    \\on cue LooksAt(Bernard, Bernard):
    \\  say Bernard: "Still me, still wearing my lucky bowtie."
    \\
    \\on cue LooksAt(Bernard, Hoagie):
    \\  say Bernard: "Hoagie is back in 1790 assisting our founding fathers."
    \\
    \\on cue LooksAt(Bernard, Laverne):
    \\  say Bernard: "Laverne is stuck 200 years in the future under tentacle rule."
    \\
    \\on cue LooksAt(Hoagie, KumquatTree):
    \\  say Hoagie: "A small, bushy kumquat tree. George Washington is glaring at it impatiently."
    \\
    \\on cue LooksAt(Hoagie, ChronoToilet1790):
    \\  say Hoagie: "My Chron-o-John in 1790. Needs electrical power before it can flush anything back to the future."
    \\
    \\on cue LooksAt(Hoagie, TimeCapsule1790):
    \\  say Hoagie: "A bronze time capsule embedded in the colonial hearth. Anything placed inside will survive to 1993."
    \\
    \\on cue LooksAt(Hoagie, RedPaintBucket):
    \\  say Hoagie: "A bucket of bright red colonial oil paint. Perfect for turning citrus trees into cherry trees."
    \\
    \\on cue LooksAt(Hoagie, Washington):
    \\  say Hoagie: "George Washington, father of our country. He is practically itching to chop down a cherry tree."
    \\
    \\on cue LooksAt(Hoagie, BetsyRoss):
    \\  say Hoagie: "Betsy Ross, embroidering away at the national flag. She seems open to design suggestions."
    \\
    \\on cue LooksAt(Hoagie, BatteryCasing):
    \\  say Hoagie: "An empty glass battery casing with copper and zinc electrodes. Just needs an acidic electrolyte!"
    \\
    \\on cue LooksAt(Hoagie, SuperBattery):
    \\  say Hoagie: "The Super Battery! 200-year-aged vinegar reacting with zinc and copper to produce mega-voltage!"
    \\
    \\on cue LooksAt(Hoagie, VintageWine):
    \\  say Hoagie: "A bottle of 1993 vintage wine sent from the future. It smells cheap and overly tannic."
    \\
    \\on cue LooksAt(Hoagie, Vinegar200Years):
    \\  say Hoagie: "Two centuries of time-capsule aging turned that cheap wine into potent vinegar acid!"
    \\
    \\on cue LooksAt(Hoagie, TentacleFlyer):
    \\  say Hoagie: "Future campaign literature from Purple Tentacle. Betsy Ross could use this as a flag pattern."
    \\
    \\on cue LooksAt(Hoagie, WorkshopDoor):
    \\  say Hoagie: "Heavy wooden door leading out to the colonial grounds and kumquat orchard."
    \\
    \\on cue LooksAt(Hoagie, Fireplace1790):
    \\  say Hoagie: "A brick hearth crackling with firewood. Great for aging vintage wine into vinegar."
    \\
    \\on cue LooksAt(Hoagie, KumquatLawn):
    \\  say Hoagie: "The green colonial lawn where George Washington is testing his axe."
    \\
    \\on cue LooksAt(Hoagie, CapsuleNiche1790):
    \\  say Hoagie: "A recessed stone niche housing the colonial time capsule."
    \\
    \\on cue LooksAt(Hoagie, ToiletMark1790):
    \\  say Hoagie: "The dirt patch where my Chron-o-John crash-landed in 1790."
    \\
    \\on cue LooksAt(Hoagie, Hoagie):
    \\  say Hoagie: "Just a roadie trying to get back to the gig."
    \\
    \\on cue LooksAt(Hoagie, Bernard):
    \\  say Hoagie: "Bernard is holding down the motel fort in 1993."
    \\
    \\on cue LooksAt(Hoagie, Laverne):
    \\  say Hoagie: "Laverne is waiting in the future. Hope she didn't get eaten by tentacles."
    \\
    \\on cue TalksTo(Hoagie, Washington):
    \\  choice "Care to chop down that cherry tree for historical destiny, Mr. Washington?" where Believes(Washington, CherryTree):
    \\    say Washington: "A cherry tree?! I cannot tell a lie! My axe hungers for colonial timber!"
    \\    say Washington: "*THWACK!* *CHOP!* Down it goes!"
    \\    remember TreeChoppedDown(Washington, KumquatTree)
    \\    remember FreedFromTree(Laverne, 1)
    \\  choice "Nice weather for drafting a constitution, George.":
    \\    say Washington: "Indeed, lad, but I yearn for an honorable tree to chop down. Sadly, only kumquats grow here."
    \\
    \\on cue TalksTo(Hoagie, BetsyRoss):
    \\  choice "Hey Betsy, here is the new official design for the American flag!" where Believes(BetsyRoss, TentacleFlagDesign):
    \\    say BetsyRoss: "A triangular purple motif with golden suction cups? How avant-garde! I shall sew it at once!"
    \\    say BetsyRoss: "*snip snip* *stitch stitch* The Tentacle Flag is finished!"
    \\    remember TentacleFlagSewn(BetsyRoss, 1)
    \\  choice "How goes the sewing, Betsy?":
    \\    say BetsyRoss: "I am working on the national banner, but the committee cannot agree on the pattern."
    \\
    \\on cue TalksTo(Laverne, PurpleTentacle):
    \\  choice "I need to use the bathroom!":
    \\    say PurpleTentacle: "Human biological maintenance permitted. Do your business in the yard!"
    \\    remember DoingBusiness(Laverne, 1)
    \\  choice "Nice tentacles you have there.":
    \\    say PurpleTentacle: "Silence, mammalian prisoner! No loitering at the checkpoint!"
    \\
    \\on cue LooksAt(Laverne, PurpleTentacle):
    \\  say Laverne: "A seven-foot mutant purple tentacle patrolling the security checkpoint. No humans allowed without a tentacle disguise."
    \\
    \\on cue LooksAt(Laverne, FutureTree):
    \\  say Laverne: "A bizarre 200-year-old kumquat tree reaching all the way to the roof. I am currently tangled in its branches!"
    \\
    \\on cue LooksAt(Laverne, TentacleFlagProp):
    \\  say Laverne: "The official planetary banner hoisted high on the guard roof: Purple Tentacle's suction-cup standard."
    \\
    \\on cue LooksAt(Laverne, PowerSocketProp):
    \\  say Laverne: "A high-voltage power terminal on the roof, hooked into the Chron-o-John temporal conduit."
    \\
    \\on cue LooksAt(Laverne, ChronoToilet2193):
    \\  say Laverne: "The future Chron-o-John! Once hooked up to power, it will reconnect the party across time."
    \\
    \\on cue LooksAt(Laverne, TentacleFlag):
    \\  say Laverne: "Betsy Ross's 1790 flag design, perfectly altered to double as an authentic tentacle disguise!"
    \\
    \\on cue LooksAt(Laverne, GuardPost):
    \\  say Laverne: "The tentacle security barrier. No humans permitted without a tentacle disguise."
    \\
    \\on cue LooksAt(Laverne, RoofGutter):
    \\  say Laverne: "Copper drainage gutter leading down from the guard post roof."
    \\
    \\on cue LooksAt(Laverne, TreeBranch2193):
    \\  say Laverne: "A thick, gnarly branch of the mutated kumquat tree high in the air."
    \\
    \\on cue LooksAt(Laverne, ToiletMark2193):
    \\  say Laverne: "The rooftop patio where the future Chron-o-John sits."
    \\
    \\on cue LooksAt(Laverne, Laverne):
    \\  say Laverne: "Med school didn't prepare me for mutant tentacles."
    \\
    \\on cue LooksAt(Laverne, Bernard):
    \\  say Laverne: "Bernard is in 1993 running around Dr. Fred's motel."
    \\
    \\on cue LooksAt(Laverne, Hoagie):
    \\  say Laverne: "Hoagie is chilling in colonial times with the founding fathers."
    \\
    \\when TreeChoppedDown(Washington, KumquatTree):
    \\  interrupt Laverne with:
    \\    say Laverne: "Whoa! The tree vanished beneath my feet! *THUD!* I'm on the ground!"
    \\
    \\when TentacleFlagSewn(BetsyRoss, 1):
    \\  interrupt Laverne with:
    \\    say Laverne: "Look up at the guard post roof! Betsy's flag is flying as the official planetary standard!"
    \\
    \\on cue LooksAt(Bernard):
    \\  say Bernard: "Nothing unusual to see here."
    \\
    \\on cue LooksAt(Hoagie):
    \\  say Hoagie: "Nothing unusual to see here."
    \\
    \\on cue LooksAt(Laverne):
    \\  say Laverne: "Nothing unusual to see here."
;

/// Evaluates whether the Day of the Tentacle three-era milestone scenario is completely solved (P21-03, D-025).
pub fn evaluate_dott_solved(world: *const bespoke.World) bool {
    const bat_rel = world.lookup_relation("ToiletPowered") orelse return false;
    const flag_rel = world.lookup_relation("TentacleFlagSewn") orelse return false;
    const chop_rel = world.lookup_relation("TreeChoppedDown") orelse return false;
    const free_rel = world.lookup_relation("FreedFromTree") orelse return false;
    const disg_rel = world.lookup_relation("TentacleDisguiseActive") orelse return false;

    return world.has_fact(null, bat_rel, null) and
        world.has_fact(null, flag_rel, null) and
        world.has_fact(null, chop_rel, null) and
        world.has_fact(null, free_rel, null) and
        world.has_fact(null, disg_rel, null);
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

/// Executes headless simulation of the Day of the Tentacle Trio scenario (P21-03, D-025).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("    BeSpoke Engine: Day of the Tentacle Trio Milestone Scenario    \n", .{});
    try writer.print(" (Multi-Character Party * Remote Item Swaps * Temporal Epistemology)\n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Compiling Day of the Tentacle three-era script...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, DOTT_PUZZLE_SCRIPT);
    defer compiled.deinit();

    // 1. Scene Room Entities
    const past_scene = world.lookup_entity("Colonial Workshop").?;
    const present_scene = world.lookup_entity("Motel Lobby").?;
    const future_scene = world.lookup_entity("Dystopian Guard Post").?;

    // 2. Party Protagonists & Cast
    const hoagie = world.lookup_entity("Hoagie").?;
    const bernard = world.lookup_entity("Bernard").?;
    const laverne = world.lookup_entity("Laverne").?;
    const washington = world.lookup_entity("Washington").?;
    const betsy = world.lookup_entity("BetsyRoss").?;
    const tentacle = world.lookup_entity("PurpleTentacle").?;

    // 3. Register Party in DisplayBridge
    var display_bridge = bespoke.display.DisplayBridge.init();
    const party_members = [_]bespoke.EntityId{ hoagie, bernard, laverne };
    display_bridge.set_party(&party_members);
    display_bridge.set_active_character(bernard);

    // 4. Spatial Waypoints
    const past_toilet_wp = spatial.graph.find_waypoint_in_room(past_scene, "ToiletMark1790") orelse 1;
    const past_lawn_wp = spatial.graph.find_waypoint_in_room(past_scene, "KumquatLawn") orelse 2;
    const past_niche_wp = spatial.graph.find_waypoint_in_room(past_scene, "CapsuleNiche1790") orelse 3;

    const pres_toilet_wp = spatial.graph.find_waypoint_in_room(present_scene, "ToiletMark1993") orelse 4;
    const pres_desk_wp = spatial.graph.find_waypoint_in_room(present_scene, "LobbyDesk") orelse 5;
    const pres_niche_wp = spatial.graph.find_waypoint_in_room(present_scene, "CapsuleNiche1993") orelse 6;

    const fut_toilet_wp = spatial.graph.find_waypoint_in_room(future_scene, "ToiletMark2193") orelse 7;
    const fut_guard_wp = spatial.graph.find_waypoint_in_room(future_scene, "GuardPost") orelse 8;
    const fut_tree_wp = spatial.graph.find_waypoint_in_room(future_scene, "TreeBranch2193") orelse 9;
    const fut_roof_wp = spatial.graph.find_waypoint_in_room(future_scene, "RoofGutter") orelse 10;

    // Connect spatial topologies within rooms
    try spatial.graph.connect(past_toilet_wp, past_niche_wp, null);
    try spatial.graph.connect(past_niche_wp, past_lawn_wp, null);
    try spatial.graph.connect(pres_toilet_wp, pres_desk_wp, null);
    try spatial.graph.connect(pres_desk_wp, pres_niche_wp, null);
    try spatial.graph.connect(fut_toilet_wp, fut_guard_wp, null);
    try spatial.graph.connect(fut_guard_wp, fut_roof_wp, null);

    // Register actors at topological waypoints
    try spatial.register_entity(hoagie, past_toilet_wp, 8);
    try spatial.register_entity(washington, past_lawn_wp, 8);
    try spatial.register_entity(betsy, past_niche_wp, 8);
    try spatial.register_entity(bernard, pres_desk_wp, 8);
    try spatial.register_entity(laverne, fut_tree_wp, 8);
    try spatial.register_entity(tentacle, fut_guard_wp, 8);

    // Register Chron-o-John portals across eras (D-026)
    const toilet_1790_ent = world.lookup_entity("ChronoToilet1790").?;
    const toilet_1993_ent = world.lookup_entity("ChronoToilet1993").?;
    const toilet_2193_ent = world.lookup_entity("ChronoToilet2193").?;
    try spatial.register_portal(toilet_1790_ent, past_scene, past_toilet_wp);
    try spatial.register_portal(toilet_1993_ent, present_scene, pres_toilet_wp);
    try spatial.register_portal(toilet_2193_ent, future_scene, fut_toilet_wp);

    // Assert initial relational constraints (D-026)
    const trapped_rel = try world.intern_relation("Trapped", .set);
    _ = try world.remember(laverne, trapped_rel, 1, 0);

    // Explicit hotspot locations aligned with scene waypoints across all 3 eras
    const wine_prop = world.lookup_entity("VintageWineBottle").?;
    const flyer_prop = world.lookup_entity("TentacleFlyerProp").?;
    const flag_prop = world.lookup_entity("TentacleFlagProp").?;
    const socket_prop = world.lookup_entity("PowerSocketProp").?;
    const future_tree = world.lookup_entity("FutureTree").?;
    const tree_prop = world.lookup_entity("KumquatTree").?;
    const capsule_1790_ent = world.lookup_entity("TimeCapsule1790").?;
    const capsule_1993_ent = world.lookup_entity("TimeCapsule1993").?;
    const paint_prop = world.lookup_entity("RedPaintBucket").?;

    try spatial.add_hotspot(toilet_1790_ent, past_scene, .{ .x = 80, .y = -6 }, 10, "ChronoToilet1790", "The 1790 Chron-o-John. Needs electrical power before it can flush anything across time.");
    try spatial.add_hotspot(capsule_1790_ent, past_scene, .{ .x = 60, .y = -6 }, 8, "TimeCapsule1790", "A bronze time capsule embedded in the colonial hearth. Anything placed inside will survive to 1993.");
    try spatial.add_hotspot(tree_prop, past_scene, .{ .x = 40, .y = -6 }, 10, "KumquatTree", "A small, bushy kumquat tree. George Washington is glaring at it impatiently.");
    try spatial.add_hotspot(paint_prop, past_scene, .{ .x = 20, .y = -6 }, 8, "RedPaintBucket", "A bucket of bright red colonial oil paint. Perfect for turning citrus trees into cherry trees.");

    try spatial.add_hotspot(toilet_1993_ent, present_scene, .{ .x = 60, .y = -6 }, 10, "ChronoToilet1993", "The Chron-o-John! Dr. Fred's temporal displacement unit disguised as standard plumbing.");
    try spatial.add_hotspot(capsule_1993_ent, present_scene, .{ .x = 40, .y = -6 }, 8, "TimeCapsule1993", "The motel lobby time capsule, sealed tight to preserve artifacts for centuries.");
    try spatial.add_hotspot(wine_prop, present_scene, .{ .x = 0, .y = -6 }, 8, "VintageWineBottle", "A dusty 1993 vintage bottle of red wine sitting on the motel desk.");
    try spatial.add_hotspot(flyer_prop, present_scene, .{ .x = 5, .y = -6 }, 8, "TentacleFlyerProp", "A campaign flyer showing Purple Tentacle's triangular silhouette.");

    try spatial.add_hotspot(toilet_2193_ent, future_scene, .{ .x = 60, .y = -6 }, 10, "ChronoToilet2193", "The future Chron-o-John! Once hooked up to power, it will reconnect the party across time.");
    try spatial.add_hotspot(future_tree, future_scene, .{ .x = 40, .y = -6 }, 10, "FutureTree", "A bizarre 200-year-old kumquat tree reaching all the way to the roof. Laverne is currently tangled in its branches!");
    try spatial.add_hotspot(flag_prop, future_scene, .{ .x = 20, .y = -6 }, 8, "TentacleFlagProp", "The official planetary banner hoisted high on the guard roof: Purple Tentacle's suction-cup standard.");
    try spatial.add_hotspot(socket_prop, future_scene, .{ .x = 25, .y = -6 }, 8, "PowerSocketProp", "A high-voltage power terminal on the roof, hooked into the Chron-o-John temporal conduit.");

    // 5. Intern Items and Initial Inventory
    const carries_rel = try world.intern_relation("Carries", .set);
    const wine = try world.intern_entity("VintageWine");
    const flyer = try world.intern_entity("TentacleFlyer");
    const paint = try world.intern_entity("RedPaintBucket");
    const casing = try world.intern_entity("BatteryCasing");
    const vinegar = try world.intern_entity("Vinegar200Years");
    const battery = try world.intern_entity("SuperBattery");
    const flag = try world.intern_entity("TentacleFlag");
    const cherry_prop = try world.intern_entity("CherryTree");
    const flag_design = try world.intern_entity("TentacleFlagDesign");

    // Bernard in 1993 carries Vintage Wine and Tentacle Flyer
    _ = try world.remember(bernard, carries_rel, wine.to_int(), 0);
    _ = try world.remember(bernard, carries_rel, flyer.to_int(), 0);

    // Hoagie in 1790 carries Red Paint and Battery Casing
    _ = try world.remember(hoagie, carries_rel, paint.to_int(), 0);
    _ = try world.remember(hoagie, carries_rel, casing.to_int(), 0);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try vm.transition_to_scene(present_scene);

    try writer.print("[Step 0] Initial state: Bernard in 1993, Hoagie in 1790, Laverne in 2193.\n", .{});
    try writer.print("         Bernard carries: VintageWine, TentacleFlyer\n", .{});
    try writer.print("         Hoagie carries:  RedPaintBucket, BatteryCasing\n", .{});
    try writer.print("         Laverne trapped in 2193 tree branches.\n", .{});
    std.debug.assert(spatial.can_transfer_item_with_world(&world, bernard, hoagie, .portal_anchored));
    std.debug.assert(!spatial.can_transfer_item_with_world(&world, bernard, laverne, .portal_anchored));
    try writer.print("         [D-026 Invariant] Portal Gating Verified: Laverne trapped in tree -> Chron-o-John transfer rejected!\n", .{});
    try writer.print("         [D-026 Invariant] Portal Anchoring Verified: Bernard to Hoagie operational across eras.\n\n", .{});

    // STEP 0b: Three-Era Environmental Inspection (LooksAt cues)
    try writer.print("[Step 0b] Three-Era Environmental Inspection (LooksAt cues):\n", .{});
    var look_buf: [256]u8 = undefined;

    // 1993 Motel Lobby (Bernard)
    const drfred = world.lookup_entity("DrFred").?;

    const msg_wine_prop = try execute_look_at(&world, &vm, &compiled, bernard, wine_prop, &look_buf);
    try writer.print("         [1993] Bernard looks at VintageWineBottle -> {s}\n", .{msg_wine_prop});

    const msg_flyer_prop = try execute_look_at(&world, &vm, &compiled, bernard, flyer_prop, &look_buf);
    try writer.print("         [1993] Bernard looks at TentacleFlyerProp -> {s}\n", .{msg_flyer_prop});

    const msg_toilet_1993 = try execute_look_at(&world, &vm, &compiled, bernard, toilet_1993_ent, &look_buf);
    try writer.print("         [1993] Bernard looks at ChronoToilet1993 -> {s}\n", .{msg_toilet_1993});

    const msg_capsule_1993 = try execute_look_at(&world, &vm, &compiled, bernard, capsule_1993_ent, &look_buf);
    try writer.print("         [1993] Bernard looks at TimeCapsule1993 -> {s}\n", .{msg_capsule_1993});

    const msg_drfred = try execute_look_at(&world, &vm, &compiled, bernard, drfred, &look_buf);
    try writer.print("         [1993] Bernard looks at DrFred -> {s}\n", .{msg_drfred});

    const msg_wine = try execute_look_at(&world, &vm, &compiled, bernard, wine, &look_buf);
    try writer.print("         [1993] Bernard inspects VintageWine -> {s}\n", .{msg_wine});

    const msg_flyer = try execute_look_at(&world, &vm, &compiled, bernard, flyer, &look_buf);
    try writer.print("         [1993] Bernard inspects TentacleFlyer -> {s}\n", .{msg_flyer});

    // 1790 Colonial Workshop (Hoagie)
    try vm.transition_to_scene(past_scene);

    const msg_tree = try execute_look_at(&world, &vm, &compiled, hoagie, tree_prop, &look_buf);
    try writer.print("         [1790] Hoagie looks at KumquatTree -> {s}\n", .{msg_tree});

    const msg_toilet_1790 = try execute_look_at(&world, &vm, &compiled, hoagie, toilet_1790_ent, &look_buf);
    try writer.print("         [1790] Hoagie looks at ChronoToilet1790 -> {s}\n", .{msg_toilet_1790});

    const msg_capsule_1790 = try execute_look_at(&world, &vm, &compiled, hoagie, capsule_1790_ent, &look_buf);
    try writer.print("         [1790] Hoagie looks at TimeCapsule1790 -> {s}\n", .{msg_capsule_1790});

    const msg_wash = try execute_look_at(&world, &vm, &compiled, hoagie, washington, &look_buf);
    try writer.print("         [1790] Hoagie looks at Washington -> {s}\n", .{msg_wash});

    const msg_betsy = try execute_look_at(&world, &vm, &compiled, hoagie, betsy, &look_buf);
    try writer.print("         [1790] Hoagie looks at BetsyRoss -> {s}\n", .{msg_betsy});

    const msg_paint = try execute_look_at(&world, &vm, &compiled, hoagie, paint, &look_buf);
    try writer.print("         [1790] Hoagie inspects RedPaintBucket -> {s}\n", .{msg_paint});

    const msg_casing = try execute_look_at(&world, &vm, &compiled, hoagie, casing, &look_buf);
    try writer.print("         [1790] Hoagie inspects BatteryCasing -> {s}\n", .{msg_casing});

    // 2193 Dystopian Guard Post (Laverne)
    try vm.transition_to_scene(future_scene);

    const msg_tentacle = try execute_look_at(&world, &vm, &compiled, laverne, tentacle, &look_buf);
    try writer.print("         [2193] Laverne looks at PurpleTentacle -> {s}\n", .{msg_tentacle});

    const msg_fut_tree = try execute_look_at(&world, &vm, &compiled, laverne, future_tree, &look_buf);
    try writer.print("         [2193] Laverne looks at FutureTree -> {s}\n", .{msg_fut_tree});

    const msg_flag_prop = try execute_look_at(&world, &vm, &compiled, laverne, flag_prop, &look_buf);
    try writer.print("         [2193] Laverne looks at TentacleFlagProp -> {s}\n", .{msg_flag_prop});

    const msg_socket = try execute_look_at(&world, &vm, &compiled, laverne, socket_prop, &look_buf);
    try writer.print("         [2193] Laverne looks at PowerSocketProp -> {s}\n", .{msg_socket});

    const msg_toilet_2193 = try execute_look_at(&world, &vm, &compiled, laverne, toilet_2193_ent, &look_buf);
    try writer.print("         [2193] Laverne looks at ChronoToilet2193 -> {s}\n\n", .{msg_toilet_2193});

    // Restore present scene (Motel Lobby) for Step 1
    try vm.transition_to_scene(present_scene);

    // Capture initial frame snapshot
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.swap();
    const initial_frame = display_bridge.get_frame();
    std.debug.assert(initial_frame.party_count == 3);
    std.debug.assert(initial_frame.inventory_count == 2);

    // STEP 1: Bernard flushes Vintage Wine to Hoagie via Generalized Party Transfer
    try writer.print("[Step 1] Bernard flushes Vintage Wine to Hoagie...\n", .{});
    const t1_ok = try world.transfer_item(wine, bernard, hoagie);
    std.debug.assert(t1_ok);
    std.debug.assert(!world.has_fact(bernard, carries_rel, wine.to_int()));
    std.debug.assert(world.has_fact(hoagie, carries_rel, wine.to_int()));
    try writer.print("         Matter conserved: Bernard loses wine, Hoagie receives wine.\n", .{});

    // STEP 2: Hoagie places Vintage Wine into Time Capsule in 1790 and seals it
    try writer.print("[Step 2] Hoagie deposits wine into 1790 Time Capsule and seals the chamber...\n", .{});
    _ = world.forget(hoagie, carries_rel, wine.to_int());
    const capsule_rel = try world.intern_relation("SealedInCapsule", .set);
    _ = try world.remember(wine, capsule_rel, 1, 0);

    // Forward temporal causality catalyst: 200 years of container aging transforms wine to vinegar!
    const aged_rel = try world.intern_relation("WineAgedIntoVinegar", .set);
    _ = try world.remember(wine, aged_rel, 1, 0);
    try writer.print("         Forward Temporal Cascade: 200 years pass; wine transforms into 200-year-old vinegar.\n", .{});
    try writer.print("         [D-026 Invariant] Passive Incubation: No cutscene emitted; 200-year transformation discovered organically upon retrieval.\n", .{});

    // STEP 3: Bernard in 1993 opens Time Capsule and retrieves Vinegar
    try writer.print("[Step 3] Bernard in 1993 opens Time Capsule and retrieves 200-year-old vinegar...\n", .{});
    _ = try world.remember(bernard, carries_rel, vinegar.to_int(), 0);
    std.debug.assert(world.has_fact(bernard, carries_rel, vinegar.to_int()));

    // STEP 4: Bernard flushes Vinegar to Hoagie in 1790
    try writer.print("[Step 4] Bernard flushes 200-year-old vinegar to Hoagie in 1790...\n", .{});
    const t2_ok = try world.transfer_item(vinegar, bernard, hoagie);
    std.debug.assert(t2_ok);
    std.debug.assert(world.has_fact(hoagie, carries_rel, vinegar.to_int()));

    // STEP 5: Hoagie crafts Super Battery and powers 1790 Chrono-Toilet
    try writer.print("[Step 5] Hoagie combines vinegar with battery casing to craft Super Battery!\n", .{});
    _ = world.forget(hoagie, carries_rel, vinegar.to_int());
    _ = world.forget(hoagie, carries_rel, casing.to_int());
    _ = try world.remember(hoagie, carries_rel, battery.to_int(), 0);

    const msg_battery = try execute_look_at(&world, &vm, &compiled, hoagie, battery, &look_buf);
    try writer.print("         Hoagie inspects SuperBattery -> {s}\n", .{msg_battery});

    const toilet_rel = try world.intern_relation("ToiletPowered", .set);
    _ = try world.remember(hoagie, toilet_rel, 1, 0);
    try writer.print("         Hoagie plugs Super Battery into Chrono-Toilet 1790 -> POWER ONLINE!\n", .{});

    // STEP 6: Bernard flushes Tentacle Flyer to Hoagie
    try writer.print("[Step 6] Bernard flushes Tentacle Flyer to Hoagie...\n", .{});
    const t3_ok = try world.transfer_item(flyer, bernard, hoagie);
    std.debug.assert(t3_ok);

    // STEP 7: Hoagie presents flyer to Betsy Ross; Betsy evaluates belief and sews Tentacle Flag
    try writer.print("[Step 7] Epistemic Persuasion: Hoagie presents Tentacle Flyer to Betsy Ross...\n", .{});
    std.debug.assert(!vm.evaluates_belief(betsy, flag_design));
    try vm.assert_belief(betsy, flag_design);
    std.debug.assert(vm.evaluates_belief(betsy, flag_design));

    const flag_sewn_rel = try world.intern_relation("TentacleFlagSewn", .set);
    _ = try world.remember(betsy, flag_sewn_rel, 1, 0);
    try writer.print("         Betsy Ross adopts belief and stitches the national Tentacle Flag!\n", .{});

    // Step VM tick to fire reactive rule 'when TentacleFlagSewn(BetsyRoss, 1) -> interrupt Laverne'
    try vm.step_tick();
    if (bespoke.host.speech_this_tick(&world, &vm, &look_buf)) |cutscene_msg| {
        try writer.print("         [Cutscene Telegraph] {s}\n", .{cutscene_msg});
    }

    // STEP 8: Hoagie paints Kumquat Tree red; convinces Washington to chop it down
    try writer.print("[Step 8] Epistemic Belief & Hatchet: Hoagie paints kumquats red and talks to Washington...\n", .{});
    std.debug.assert(!vm.evaluates_belief(washington, cherry_prop));
    try vm.assert_belief(washington, cherry_prop);
    std.debug.assert(vm.evaluates_belief(washington, cherry_prop));

    const chop_rel = try world.intern_relation("TreeChoppedDown", .set);
    _ = try world.remember(washington, chop_rel, tree_prop.to_int(), 0);
    try writer.print("         Washington: 'I cannot tell a lie!' *CHOP!* Tree felled in 1790!\n", .{});

    // Step VM tick to fire reactive rule 'when TreeChoppedDown(Washington, KumquatTree) -> interrupt Laverne'
    try vm.step_tick();
    if (bespoke.host.speech_this_tick(&world, &vm, &look_buf)) |cutscene_msg| {
        try writer.print("         [Cutscene Telegraph] {s}\n", .{cutscene_msg});
    }

    // STEP 9: Forward Temporal Cascade -> Laverne freed in 2193!
    try writer.print("[Step 9] Forward Temporal Cascade: Tree ceased to exist centuries ago in 2193...\n", .{});
    const free_rel = try world.intern_relation("FreedFromTree", .set);
    _ = try world.remember(laverne, free_rel, 1, 0);
    _ = world.forget(laverne, trapped_rel, 1);
    _ = try spatial.transition_actor(laverne, future_scene, fut_guard_wp);
    try writer.print("         Laverne drops safely from absent tree to ground level!\n", .{});

    // Invariant verification (D-026): Tree removed, but Laverne is at GuardPost without costume or yard escort -> transfer fails
    std.debug.assert(!spatial.can_access_portal(&world, laverne));
    std.debug.assert(!spatial.can_transfer_item_with_world(&world, bernard, laverne, .portal_anchored));
    try writer.print("         [D-026 Invariant] Portal Access Gating: Laverne on ground but guarded -> Chron-o-John transfer rejected!\n", .{});

    // STEP 9b: Security Permission: Laverne requests bathroom escort / 'doing her business' in yard
    try writer.print("[Step 9b] Security Permission: Laverne: 'I need to use the bathroom!' -> Guard permits yard access...\n", .{});
    const doing_biz_rel = try world.intern_relation("DoingBusiness", .set);
    _ = try world.remember(laverne, doing_biz_rel, 1, 0);
    _ = try spatial.transition_actor(laverne, future_scene, fut_toilet_wp);
    std.debug.assert(spatial.can_access_portal(&world, laverne));
    std.debug.assert(spatial.can_transfer_item_with_world(&world, bernard, laverne, .portal_anchored));
    try writer.print("         [D-026 Invariant] Portal Access Gating: Laverne doing business in yard -> Chron-o-John transfer online!\n", .{});

    // STEP 10: Laverne retrieves Tentacle Flag disguise and bypasses guard
    try writer.print("[Step 10] Laverne climbs to roof, dons Tentacle Flag disguise, reaches power socket...\n", .{});
    _ = try world.remember(laverne, carries_rel, flag.to_int(), 0);
    const msg_flag = try execute_look_at(&world, &vm, &compiled, laverne, flag, &look_buf);
    try writer.print("         Laverne inspects TentacleFlag -> {s}\n", .{msg_flag});
    const disg_rel = try world.intern_relation("TentacleDisguiseActive", .set);
    _ = try world.remember(laverne, disg_rel, 1, 0);
    std.debug.assert(spatial.can_access_portal(&world, laverne));
    std.debug.assert(spatial.can_transfer_item_with_world(&world, bernard, laverne, .portal_anchored));
    try writer.print("         [D-026 Invariant] Portal Access Gating: Laverne wearing tentacle disguise -> permanent Chron-o-John access granted!\n", .{});

    // STEP 11: Verify Complete Victory
    std.debug.assert(evaluate_dott_solved(&world));
    try writer.print("\n>>> VICTORY ACHIEVED! Day of the Tentacle Trio Puzzle completely solved! <<<\n", .{});
    try writer.print("    - Hoagie: Toilet powered by 200-year-aged vinegar Super Battery.\n", .{});
    try writer.print("    - Betsy Ross: Epistemically convinced to sew Tentacle Flag.\n", .{});
    try writer.print("    - Washington: Epistemically convinced to chop down Kumquat/Cherry tree.\n", .{});
    try writer.print("    - Laverne: Freed in 2193 via temporal causality, disguised in Tentacle Flag.\n", .{});

    // STEP 12: Snapshot Time-Travel Rewind Verification
    try writer.print("\n[Time-Travel] Verifying deterministic rewind back to tick 0...\n", .{});
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.swap();
    const final_frame = display_bridge.get_frame();
    std.debug.assert(final_frame.dott_battery_charged);
    std.debug.assert(final_frame.dott_flag_sewn);
    std.debug.assert(final_frame.dott_tree_chopped);
    std.debug.assert(final_frame.dott_laverne_freed);
    std.debug.assert(final_frame.dott_laverne_disguised);

    try writer.print("SUCCESS: 100% deterministic time-travel and multi-character coordination verified.\n", .{});
}

/// Executes interactive SDL2 simulation with party switching and retro audio (P21-03, D-025).
pub fn run_interactive(allocator: std.mem.Allocator) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, DOTT_PUZZLE_SCRIPT);
    defer compiled.deinit();

    const past_scene = world.lookup_entity("Colonial Workshop").?;
    const present_scene = world.lookup_entity("Motel Lobby").?;
    const future_scene = world.lookup_entity("Dystopian Guard Post").?;

    const hoagie = world.lookup_entity("Hoagie").?;
    const bernard = world.lookup_entity("Bernard").?;
    const laverne = world.lookup_entity("Laverne").?;
    const washington = world.lookup_entity("Washington").?;
    const betsy = world.lookup_entity("BetsyRoss").?;
    const tentacle = world.lookup_entity("PurpleTentacle").?;

    // Spatial marks
    const past_toilet = spatial.graph.find_waypoint_in_room(past_scene, "ToiletMark1790") orelse 1;
    const past_lawn = spatial.graph.find_waypoint_in_room(past_scene, "KumquatLawn") orelse 2;
    const past_niche = spatial.graph.find_waypoint_in_room(past_scene, "CapsuleNiche1790") orelse 3;

    const pres_toilet = spatial.graph.find_waypoint_in_room(present_scene, "ToiletMark1993") orelse 4;
    const pres_desk = spatial.graph.find_waypoint_in_room(present_scene, "LobbyDesk") orelse 5;
    const pres_niche = spatial.graph.find_waypoint_in_room(present_scene, "CapsuleNiche1993") orelse 6;

    const fut_toilet = spatial.graph.find_waypoint_in_room(future_scene, "ToiletMark2193") orelse 7;
    const fut_guard = spatial.graph.find_waypoint_in_room(future_scene, "GuardPost") orelse 8;
    const fut_tree = spatial.graph.find_waypoint_in_room(future_scene, "TreeBranch2193") orelse 9;
    const fut_roof = spatial.graph.find_waypoint_in_room(future_scene, "RoofGutter") orelse 10;

    try spatial.graph.connect(past_toilet, past_niche, null);
    try spatial.graph.connect(past_niche, past_lawn, null);
    try spatial.graph.connect(pres_toilet, pres_desk, null);
    try spatial.graph.connect(pres_desk, pres_niche, null);
    try spatial.graph.connect(fut_toilet, fut_guard, null);
    try spatial.graph.connect(fut_guard, fut_roof, null);

    try spatial.register_entity(hoagie, past_toilet, 8);
    try spatial.register_entity(washington, past_lawn, 8);
    try spatial.register_entity(betsy, past_niche, 8);
    try spatial.register_entity(bernard, pres_desk, 8);
    try spatial.register_entity(laverne, fut_tree, 8);
    try spatial.register_entity(tentacle, fut_guard, 8);

    // Register Chron-o-John portals across eras (D-026)
    const toilet_1790_ent = world.lookup_entity("ChronoToilet1790").?;
    const toilet_1993_ent = world.lookup_entity("ChronoToilet1993").?;
    const toilet_2193_ent = world.lookup_entity("ChronoToilet2193").?;
    try spatial.register_portal(toilet_1790_ent, past_scene, past_toilet);
    try spatial.register_portal(toilet_1993_ent, present_scene, pres_toilet);
    try spatial.register_portal(toilet_2193_ent, future_scene, fut_toilet);

    const trapped_rel = try world.intern_relation("Trapped", .set);
    _ = try world.remember(laverne, trapped_rel, 1, 0);

    const carries_rel = try world.intern_relation("Carries", .set);
    const wine = try world.intern_entity("VintageWine");
    const flyer = try world.intern_entity("TentacleFlyer");
    const paint = try world.intern_entity("RedPaintBucket");
    const casing = try world.intern_entity("BatteryCasing");
    const vinegar = try world.intern_entity("Vinegar200Years");
    const battery = try world.intern_entity("SuperBattery");
    const flag = try world.intern_entity("TentacleFlag");
    const tree_prop = world.lookup_entity("KumquatTree").?;
    const capsule_1790 = world.lookup_entity("TimeCapsule1790").?;
    const capsule_1993 = world.lookup_entity("TimeCapsule1993").?;
    const wine_prop = world.lookup_entity("VintageWineBottle").?;
    const flyer_prop = world.lookup_entity("TentacleFlyerProp").?;
    const flag_prop = world.lookup_entity("TentacleFlagProp").?;
    const socket_prop = world.lookup_entity("PowerSocketProp").?;
    const future_tree = world.lookup_entity("FutureTree").?;

    // Explicit hotspot locations aligned with scene waypoints across all 3 eras
    try spatial.add_hotspot(toilet_1790_ent, past_scene, .{ .x = 80, .y = -6 }, 10, "ChronoToilet1790", "The 1790 Chron-o-John. Needs electrical power before it can flush anything across time.");
    try spatial.add_hotspot(capsule_1790, past_scene, .{ .x = 60, .y = -6 }, 8, "TimeCapsule1790", "A bronze time capsule embedded in the colonial hearth. Anything placed inside will survive to 1993.");
    try spatial.add_hotspot(tree_prop, past_scene, .{ .x = 40, .y = -6 }, 10, "KumquatTree", "A small, bushy kumquat tree. George Washington is glaring at it impatiently.");
    try spatial.add_hotspot(paint, past_scene, .{ .x = 20, .y = -6 }, 8, "RedPaintBucket", "A bucket of bright red colonial oil paint. Perfect for turning citrus trees into cherry trees.");

    try spatial.add_hotspot(toilet_1993_ent, present_scene, .{ .x = 60, .y = -6 }, 10, "ChronoToilet1993", "The Chron-o-John! Dr. Fred's temporal displacement unit disguised as standard plumbing.");
    try spatial.add_hotspot(capsule_1993, present_scene, .{ .x = 40, .y = -6 }, 8, "TimeCapsule1993", "The motel lobby time capsule, sealed tight to preserve artifacts for centuries.");
    try spatial.add_hotspot(wine_prop, present_scene, .{ .x = 0, .y = -6 }, 8, "VintageWineBottle", "A dusty 1993 vintage bottle of red wine sitting on the motel desk.");
    try spatial.add_hotspot(flyer_prop, present_scene, .{ .x = 5, .y = -6 }, 8, "TentacleFlyerProp", "A campaign flyer showing Purple Tentacle's triangular silhouette.");

    try spatial.add_hotspot(toilet_2193_ent, future_scene, .{ .x = 60, .y = -6 }, 10, "ChronoToilet2193", "The future Chron-o-John! Once hooked up to power, it will reconnect the party across time.");
    try spatial.add_hotspot(future_tree, future_scene, .{ .x = 40, .y = -6 }, 10, "FutureTree", "A bizarre 200-year-old kumquat tree reaching all the way to the roof. Laverne is currently tangled in its branches!");
    try spatial.add_hotspot(flag_prop, future_scene, .{ .x = 20, .y = -6 }, 8, "TentacleFlagProp", "The official planetary banner hoisted high on the guard roof: Purple Tentacle's suction-cup standard.");
    try spatial.add_hotspot(socket_prop, future_scene, .{ .x = 25, .y = -6 }, 8, "PowerSocketProp", "A high-voltage power terminal on the roof, hooked into the Chron-o-John temporal conduit.");

    const cherry_belief_rel = try world.intern_relation("Believes", .set);
    const toilet_powered_rel = try world.intern_relation("ToiletPowered", .set);
    const flag_design_rel = try world.intern_relation("TentacleFlagDesign", .set);
    const flag_sewn_rel = try world.intern_relation("TentacleFlagSewn", .set);
    const chop_rel = try world.intern_relation("TreeChoppedDown", .set);
    const free_rel = try world.intern_relation("FreedFromTree", .set);
    const doing_biz_rel = try world.intern_relation("DoingBusiness", .set);
    const disg_rel = try world.intern_relation("TentacleDisguiseActive", .set);

    _ = try world.remember(bernard, carries_rel, wine.to_int(), 0);
    _ = try world.remember(bernard, carries_rel, flyer.to_int(), 0);
    _ = try world.remember(hoagie, carries_rel, paint.to_int(), 0);
    _ = try world.remember(hoagie, carries_rel, casing.to_int(), 0);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try vm.transition_to_scene(present_scene);

    var win = try bespoke.display.DisplayWindow.init("BeSpoke Engine - Day of the Tentacle Trio", 1280, 720);
    defer win.deinit();
    win.set_theme(&art.theme);
    win.audio_bridge.set_track(.tentacle);

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.attach_audio_bridge(win.audio_bridge);
    const party = [_]bespoke.EntityId{ hoagie, bernard, laverne };
    display_bridge.set_party(&party);
    display_bridge.set_active_character(bernard);
    display_bridge.set_active_party_index(1);

    var session = try bespoke.host.Session.init(allocator, &world, &spatial, &vm, &compiled, &display_bridge, &win);
    defer session.deinit();
    win.set_cue_banner("Day of the Tentacle Trio loaded! Press [1] Hoagie, [2] Bernard, [3] Laverne to switch characters.", 180);

    while (true) {
        session.refresh();
        const frame = session.frame();
        session.render();

        const action = win.poll_events(frame);
        var action_taken = false;

        // Pause, step, scrub, rewind, and save actions are shared (host kit, P32-16, D-033).
        if (try session.handle_common(action)) {} else switch (action) {
            .quit => break,
            .walk_player => |wp_id| {
                const active_char = display_bridge.active_player_character orelse bernard;
                _ = try spatial.walk_to(active_char, wp_id);
                action_taken = true;
                win.set_cue_banner("Directing character to waypoint.", 60);
            },
            .switch_party_member => |p_idx| {
                if (p_idx < party.len) {
                    const char_id = party[p_idx];
                    display_bridge.set_active_character(char_id);
                    display_bridge.set_active_party_index(p_idx);
                    if (char_id == hoagie) {
                        try vm.transition_to_scene(past_scene);
                        win.set_cue_banner("Switched to Hoagie (1790 Colonial Workshop)", 120);
                    } else if (char_id == bernard) {
                        try vm.transition_to_scene(present_scene);
                        win.set_cue_banner("Switched to Bernard (1993 Motel Lobby)", 120);
                    } else if (char_id == laverne) {
                        try vm.transition_to_scene(future_scene);
                        win.set_cue_banner("Switched to Laverne (2193 Dystopian Guard Post)", 120);
                    }
                    action_taken = true;
                }
            },
            .examine_hotspot => |hs_idx| {
                if (hs_idx < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_idx];
                    const active_char = display_bridge.active_player_character orelse bernard;
                    var look_buf: [256]u8 = undefined;
                    const speech = try execute_look_at(&world, &vm, &compiled, active_char, hs.entity, &look_buf);
                    win.set_cue_banner(speech, 180);
                    std.debug.print("\n[DOTT Look] {s}\n", .{speech});
                    action_taken = true;
                }
            },
            .interact_hotspot => |hs_act| {
                if (hs_act.hotspot_index < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_act.hotspot_index];
                    const active_char = display_bridge.active_player_character orelse bernard;
                    if (hs_act.verb == .look_at) {
                        var look_buf: [256]u8 = undefined;
                        const speech = try execute_look_at(&world, &vm, &compiled, active_char, hs.entity, &look_buf);
                        win.set_cue_banner(speech, 180);
                        std.debug.print("\n[DOTT Look] {s}\n", .{speech});
                    } else if (hs_act.verb == .walk) {
                        const pt = bespoke.display.renderer.world_to_screen(hs.x, hs.y, win.width, win.height);
                        if (bespoke.display.renderer.find_nearest_waypoint(pt.x, pt.y, frame.waypoints[0..frame.waypoint_count], win.width, win.height)) |wp_id| {
                            _ = try spatial.walk_to(active_char, wp_id);
                            win.set_cue_banner("Approaching prop...", 60);
                        }
                    } else if (hs_act.verb == .pick_up or hs_act.verb == .use_with) {
                        const aged_rel = try world.intern_relation("WineAgedIntoVinegar", .set);
                        if (hs.entity == capsule_1993 or hs.entity == capsule_1790) {
                            if (world.has_fact(wine, aged_rel, 1)) {
                                if (!world.has_fact(null, carries_rel, vinegar.to_int())) {
                                    _ = try world.remember(active_char, carries_rel, vinegar.to_int(), 0);
                                    win.play_sfx(.pickup);
                                    win.set_cue_banner("Bernard opens the 1993 time capsule and retrieves the 200-year-aged vinegar!", 180);
                                } else {
                                    win.set_cue_banner("The time capsule is now empty.", 120);
                                }
                            } else {
                                win.set_cue_banner("The time capsule is empty. Nothing has been sealed in it yet.", 120);
                            }
                        } else if (hs.entity == flag_prop) {
                            if (world.has_fact(betsy, flag_sewn_rel, 1)) {
                                if (!world.has_fact(null, carries_rel, flag.to_int())) {
                                    _ = try world.remember(active_char, carries_rel, flag.to_int(), 0);
                                    win.play_sfx(.pickup);
                                    win.set_cue_banner("Laverne takes down the Tentacle Flag disguise from the roof flagpole!", 180);
                                } else {
                                    win.set_cue_banner("The flagpole is empty.", 90);
                                }
                            } else {
                                win.set_cue_banner("The tentacle flag has not been sewn yet.", 120);
                            }
                        } else {
                            _ = try vm.fire_cue(&compiled, "Uses", active_char, hs.entity, null);
                            try vm.step_tick();
                        }
                    } else {
                        _ = try vm.fire_cue(&compiled, "Uses", active_char, hs.entity, null);
                        try vm.step_tick();
                    }
                    action_taken = true;
                }
            },
            .interact_actor => |act| {
                if (act.actor_index < frame.entity_count) {
                    const target_entity = frame.entities[act.actor_index];
                    const active_char = display_bridge.active_player_character orelse bernard;
                    if (act.verb == .talk_to) {
                        _ = try vm.fire_cue(&compiled, "TalksTo", active_char, target_entity.entity, null);
                        try vm.step_tick();
                        var say_buf: [256]u8 = undefined;
                        if (bespoke.host.speech_this_tick(&world, &vm, &say_buf)) |speech| {
                            win.set_cue_banner(speech, 180);
                            std.debug.print("\n[DOTT Talk] {s}\n", .{speech});
                        }
                    } else if (act.verb == .look_at) {
                        var look_buf: [256]u8 = undefined;
                        const speech = try execute_look_at(&world, &vm, &compiled, active_char, target_entity.entity, &look_buf);
                        win.set_cue_banner(speech, 180);
                        std.debug.print("\n[DOTT Look] {s}\n", .{speech});
                    } else if (act.verb == .walk) {
                        const layout = bespoke.display.renderer.get_entity_screen_layout(act.actor_index, frame.entities[0..frame.entity_count], win.width, win.height);
                        if (bespoke.display.renderer.find_nearest_waypoint(layout.pos.x, layout.pos.y, frame.waypoints[0..frame.waypoint_count], win.width, win.height)) |wp_id| {
                            _ = try spatial.walk_to(active_char, wp_id);
                            win.set_cue_banner("Approaching character...", 60);
                        }
                    }
                    action_taken = true;
                }
            },
            .interact_inventory => |inv_act| {
                if (inv_act.item_index < frame.inventory_count) {
                    const inv_item = frame.inventory[inv_act.item_index];
                    const active_char = display_bridge.active_player_character orelse bernard;
                    if (inv_act.verb == .look_at) {
                        var look_buf: [256]u8 = undefined;
                        const speech = try execute_look_at(&world, &vm, &compiled, active_char, inv_item.entity, &look_buf);
                        win.set_cue_banner(speech, 180);
                        std.debug.print("\n[DOTT Look] {s}\n", .{speech});
                    }
                    action_taken = true;
                }
            },
            .use_inventory_on_hotspot => |u_hs| {
                if (u_hs.item_index < frame.inventory_count and u_hs.hotspot_index < frame.hotspot_count) {
                    const item_ent = frame.inventory[u_hs.item_index].entity;
                    const hs_ent = frame.hotspots[u_hs.hotspot_index].entity;
                    const active_char = display_bridge.active_player_character orelse bernard;

                    if (item_ent == paint and hs_ent == tree_prop) {
                        _ = try world.remember(washington, cherry_belief_rel, 1, 0);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Hoagie coats the kumquats in bright red paint! George Washington now believes it is a cherry tree!", 180);
                    } else if (item_ent == wine and (hs_ent == capsule_1790 or hs_ent == capsule_1993)) {
                        _ = try world.transfer_item(wine, active_char, hs_ent);
                        const aged_rel = try world.intern_relation("WineAgedIntoVinegar", .set);
                        _ = try world.remember(wine, aged_rel, 1, 0);
                        win.play_sfx(.pickup);
                        win.set_cue_banner("Vintage Wine sealed into the time capsule for two centuries of aging.", 180);
                    } else if (item_ent == battery and hs_ent == toilet_1790_ent) {
                        _ = try world.remember(hoagie, toilet_powered_rel, 1, 0);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Super Battery plugged in! The 1790 Chron-o-John hums with temporal power!", 180);
                    } else {
                        _ = try vm.fire_cue(&compiled, "Uses", active_char, hs_ent, null);
                        try vm.step_tick();
                    }
                    action_taken = true;
                }
            },
            .use_inventory_on_actor => |u_act| {
                if (u_act.item_index < frame.inventory_count and u_act.actor_index < frame.entity_count) {
                    const item_ent = frame.inventory[u_act.item_index].entity;
                    const act_ent = frame.entities[u_act.actor_index].entity;

                    if (item_ent == flyer and act_ent == betsy) {
                        _ = try world.remember(betsy, flag_design_rel, 1, 0);
                        _ = try world.remember(betsy, flag_sewn_rel, 1, 0);
                        _ = try world.remember(laverne, carries_rel, flag.to_int(), 0);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Betsy Ross: 'A tentacle flag? Avant-garde! I shall sew it at once!' Flag complete!", 180);
                    } else if (item_ent == flag and (act_ent == laverne or act_ent == tentacle)) {
                        _ = try world.remember(laverne, disg_rel, 1, 0);
                        win.play_sfx(.pickup);
                        win.set_cue_banner("Laverne dons the Tentacle Flag disguise! Security checkpoint access granted!", 180);
                    }
                    action_taken = true;
                }
            },
            .combine_inventory_items => |comb| {
                if (comb.primary_index < frame.inventory_count and comb.secondary_index < frame.inventory_count) {
                    const item1 = frame.inventory[comb.primary_index].entity;
                    const item2 = frame.inventory[comb.secondary_index].entity;
                    const active_char = display_bridge.active_player_character orelse hoagie;

                    if ((item1 == vinegar and item2 == casing) or (item1 == casing and item2 == vinegar)) {
                        _ = world.forget(active_char, carries_rel, vinegar.to_int());
                        _ = world.forget(active_char, carries_rel, casing.to_int());
                        _ = try world.remember(active_char, carries_rel, battery.to_int(), 0);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Hoagie combines 200-year vinegar with battery casing! Super Battery created!", 180);
                    }
                    action_taken = true;
                }
            },
            .dialogue_choice => |choice_idx| {
                const active_char = display_bridge.active_player_character orelse bernard;
                if (active_char == hoagie and choice_idx == 0) {
                    if (world.has_fact(washington, cherry_belief_rel, 1)) {
                        _ = try world.remember(washington, chop_rel, tree_prop.to_int(), 0);
                        _ = try world.remember(laverne, free_rel, 1, 0);
                        _ = world.forget(laverne, trapped_rel, 1);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Washington: 'A cherry tree?! Down it goes!' *THWACK!* Laverne freed from tree!", 180);
                    }
                } else if (active_char == laverne and choice_idx == 0) {
                    _ = try world.remember(laverne, doing_biz_rel, 1, 0);
                    win.set_cue_banner("Purple Tentacle: 'Human biological maintenance permitted. Do your business in the yard!'", 180);
                }
                action_taken = true;
            },
            .transfer_inventory_item => |trans| {
                if (trans.target_party_index < party.len and trans.item_index < frame.inventory_count) {
                    const from_id = display_bridge.active_player_character orelse bernard;
                    const to_id = party[trans.target_party_index];
                    const item_ent = frame.inventory[trans.item_index].entity;
                    if (!spatial.can_transfer_item_with_world(&world, from_id, to_id, .portal_anchored)) {
                        const target_name = world.get_entity_name(to_id) orelse "Character";
                        var block_buf: [128]u8 = undefined;
                        const block_msg = std.fmt.bufPrint(&block_buf, "{s} cannot reach the Chron-o-John right now!", .{target_name}) catch "Transfer blocked!";
                        win.set_cue_banner(block_msg, 120);
                    } else {
                        _ = try world.transfer_item(item_ent, from_id, to_id);
                        win.play_sfx(.toilet_flush);
                    }
                    action_taken = true;
                }
            },
            else => {},
        }

        if (action_taken) {
            if (evaluate_dott_solved(&world)) {
                win.set_cue_banner("VICTORY ACHIEVED! Day of the Tentacle Trio temporal puzzle solved!", 300);
            }
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        // Stepping simulation clock
        if (session.tick_due()) {
            _ = try session.advance();
            var cutscene_buf: [256]u8 = undefined;
            if (bespoke.host.speech_this_tick(&world, &vm, &cutscene_buf)) |cutscene_msg| {
                win.set_cue_banner(cutscene_msg, 180);
                std.debug.print("\n[Cutscene Telegraph] {s}\n", .{cutscene_msg});
            }
        }

        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P21-03: Day of the Tentacle full puzzle DAG compilation, cross-era transfers, and temporal victory" {
    const testing = std.testing;
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try run_headless(testing.allocator, buf.writer());
    try testing.expect(buf.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buf.items, "VICTORY ACHIEVED!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[Step 0b] Three-Era Environmental Inspection (LooksAt cues):") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Gating Verified: Laverne trapped in tree -> Chron-o-John transfer rejected!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Anchoring Verified: Bernard to Hoagie operational across eras.") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Passive Incubation: No cutscene emitted; 200-year transformation discovered organically upon retrieval.") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[Cutscene Telegraph] Laverne: \"Look up at the guard post roof! Betsy's flag is flying as the official planetary standard!\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[Cutscene Telegraph] Laverne: \"Whoa! The tree vanished beneath my feet! *THUD!* I'm on the ground!\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Access Gating: Laverne on ground but guarded -> Chron-o-John transfer rejected!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Access Gating: Laverne doing business in yard -> Chron-o-John transfer online!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Access Gating: Laverne wearing tentacle disguise -> permanent Chron-o-John access granted!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Bernard looks at VintageWineBottle -> Bernard: \"A dusty 1993 vintage bottle of red wine sitting on the motel desk.\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Hoagie looks at KumquatTree -> Hoagie: \"A small, bushy kumquat tree. George Washington is glaring at it impatiently.\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Laverne looks at PurpleTentacle -> Laverne: \"A seven-foot mutant purple tentacle patrolling the security checkpoint. No humans allowed without a tentacle disguise.\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Hoagie inspects SuperBattery -> Hoagie: \"The Super Battery! 200-year-aged vinegar reacting with zinc and copper to produce mega-voltage!\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Laverne inspects TentacleFlag -> Laverne: \"Betsy Ross's 1790 flag design, perfectly altered to double as an authentic tentacle disguise!\"") != null);
}

test "P32-19: each party member has a scripted default look description" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, DOTT_PUZZLE_SCRIPT);
    defer compiled.deinit();
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    const pebble = try world.intern_entity("UnscriptedPebble");
    var buf: [512]u8 = undefined;
    inline for (.{ "Bernard", "Hoagie", "Laverne" }) |name| {
        const said = try execute_look_at(&world, &vm, &compiled, world.lookup_entity(name).?, pebble, &buf);
        try testing.expectEqualStrings(name ++ ": \"Nothing unusual to see here.\"", said);
    }

    // A specific handler still wins over the default.
    const desk = try execute_look_at(&world, &vm, &compiled, world.lookup_entity("Bernard").?, world.lookup_entity("LobbyDesk").?, &buf);
    try testing.expect(std.mem.indexOf(u8, desk, "Nothing unusual") == null);
}
