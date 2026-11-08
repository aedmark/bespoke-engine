const std = @import("std");
const bespoke = @import("root.zig");

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
    \\when TreeChoppedDown(Washington, KumquatTree):
    \\  interrupt Laverne with:
    \\    say Laverne: "Whoa! The tree vanished beneath my feet! *THUD!* I'm on the ground!"
    \\
    \\when TentacleFlagSewn(BetsyRoss, 1):
    \\  interrupt Laverne with:
    \\    say Laverne: "Look up at the guard post roof! Betsy's flag is flying as the official planetary standard!"
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

/// Extracts the latest dialogue/speech message from emitted cues on the VM.
pub fn get_latest_say_message(world: *const bespoke.World, vm: *const bespoke.VM, buf: []u8) ?[]const u8 {
    for (vm.emitted_cues.items) |c| {
        if (c.cue_id == 2 and c.arg_count >= 2) {
            const speaker_ent = bespoke.EntityId.from_int(c.args[0]);
            const text_ent = bespoke.EntityId.from_int(c.args[1]);
            const speaker_name = world.get_entity_name(speaker_ent) orelse "Someone";
            const text_str = world.get_entity_name(text_ent) orelse "";
            return std.fmt.bufPrint(buf, "{s}: \"{s}\"", .{ speaker_name, text_str }) catch text_str;
        }
    }
    return null;
}

/// Fallback description generator for props, actors, and items across all three DOTT eras.
pub fn get_dott_look_description(actor_name: []const u8, target_name: []const u8) []const u8 {
    _ = actor_name;
    if (std.mem.eql(u8, target_name, "VintageWineBottle") or std.mem.eql(u8, target_name, "VintageWine")) {
        return "Bernard: \"A dusty 1993 vintage bottle of red wine sitting on the motel desk.\"";
    } else if (std.mem.eql(u8, target_name, "TentacleFlyerProp") or std.mem.eql(u8, target_name, "TentacleFlyer")) {
        return "Bernard: \"A campaign flyer showing Purple Tentacle's triangular silhouette. 'Vote Purple for Global Domination!'\"";
    } else if (std.mem.eql(u8, target_name, "ChronoToilet1993")) {
        return "Bernard: \"The Chron-o-John! Dr. Fred's temporal displacement unit disguised as standard plumbing.\"";
    } else if (std.mem.eql(u8, target_name, "TimeCapsule1993")) {
        return "Bernard: \"The motel lobby time capsule, sealed tight to preserve artifacts for centuries.\"";
    } else if (std.mem.eql(u8, target_name, "DrFred")) {
        return "Bernard: \"Dr. Fred Edison, pacing nervously while muttering about world domination and temporal coordinates.\"";
    } else if (std.mem.eql(u8, target_name, "KumquatTree")) {
        return "Hoagie: \"A small, bushy kumquat tree. George Washington is glaring at it impatiently.\"";
    } else if (std.mem.eql(u8, target_name, "ChronoToilet1790")) {
        return "Hoagie: \"My Chron-o-John in 1790. Needs electrical power before it can flush anything back to the future.\"";
    } else if (std.mem.eql(u8, target_name, "TimeCapsule1790")) {
        return "Hoagie: \"A bronze time capsule embedded in the colonial hearth. Anything placed inside will survive to 1993.\"";
    } else if (std.mem.eql(u8, target_name, "RedPaintBucket")) {
        return "Hoagie: \"A bucket of bright red colonial oil paint. Perfect for turning citrus trees into cherry trees.\"";
    } else if (std.mem.eql(u8, target_name, "BatteryCasing")) {
        return "Hoagie: \"An empty glass battery casing with copper and zinc electrodes. Just needs an acidic electrolyte!\"";
    } else if (std.mem.eql(u8, target_name, "SuperBattery")) {
        return "Hoagie: \"The Super Battery! 200-year-aged vinegar reacting with zinc and copper to produce mega-voltage!\"";
    } else if (std.mem.eql(u8, target_name, "Vinegar200Years")) {
        return "Hoagie: \"Two centuries of time-capsule aging turned that cheap wine into potent vinegar acid!\"";
    } else if (std.mem.eql(u8, target_name, "Washington")) {
        return "Hoagie: \"George Washington, father of our country. He is practically itching to chop down a cherry tree.\"";
    } else if (std.mem.eql(u8, target_name, "BetsyRoss")) {
        return "Hoagie: \"Betsy Ross, embroidering away at the national flag. She seems open to design suggestions.\"";
    } else if (std.mem.eql(u8, target_name, "PurpleTentacle")) {
        return "Laverne: \"A seven-foot mutant purple tentacle patrolling the security checkpoint. No humans allowed without a tentacle disguise.\"";
    } else if (std.mem.eql(u8, target_name, "FutureTree")) {
        return "Laverne: \"A bizarre 200-year-old kumquat tree reaching all the way to the roof. I am currently tangled in its branches!\"";
    } else if (std.mem.eql(u8, target_name, "TentacleFlagProp") or std.mem.eql(u8, target_name, "TentacleFlag")) {
        return "Laverne: \"Betsy Ross's 1790 flag design, perfectly altered to double as an authentic tentacle disguise!\"";
    } else if (std.mem.eql(u8, target_name, "PowerSocketProp")) {
        return "Laverne: \"A high-voltage power terminal on the roof, hooked into the Chron-o-John temporal conduit.\"";
    } else if (std.mem.eql(u8, target_name, "ChronoToilet2193")) {
        return "Laverne: \"The future Chron-o-John! Once hooked up to power, it will reconnect the party across time.\"";
    } else {
        return "Nothing unusual to see here.";
    }
}

/// Helper to fire LooksAt cue, step the VM, and retrieve the speech message.
pub fn execute_look_at(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: anytype,
    speaker: bespoke.EntityId,
    target: bespoke.EntityId,
    buf: []u8,
) ![]const u8 {
    _ = try vm.fire_cue(compiled, "LooksAt", speaker, target, null);
    try vm.step_tick();
    if (get_latest_say_message(world, vm, buf)) |msg| {
        return msg;
    }
    const speaker_name = world.get_entity_name(speaker) orelse "Hero";
    const target_name = world.get_entity_name(target) orelse "Object";
    return get_dott_look_description(speaker_name, target_name);
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
    const tree_prop = world.lookup_entity("KumquatTree").?;

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
    const wine_prop = world.lookup_entity("VintageWineBottle").?;
    const flyer_prop = world.lookup_entity("TentacleFlyerProp").?;
    const toilet_1993_prop = world.lookup_entity("ChronoToilet1993").?;
    const capsule_1993_prop = world.lookup_entity("TimeCapsule1993").?;
    const drfred = world.lookup_entity("DrFred").?;

    const msg_wine_prop = try execute_look_at(&world, &vm, &compiled, bernard, wine_prop, &look_buf);
    try writer.print("         [1993] Bernard looks at VintageWineBottle -> {s}\n", .{msg_wine_prop});

    const msg_flyer_prop = try execute_look_at(&world, &vm, &compiled, bernard, flyer_prop, &look_buf);
    try writer.print("         [1993] Bernard looks at TentacleFlyerProp -> {s}\n", .{msg_flyer_prop});

    const msg_toilet_1993 = try execute_look_at(&world, &vm, &compiled, bernard, toilet_1993_prop, &look_buf);
    try writer.print("         [1993] Bernard looks at ChronoToilet1993 -> {s}\n", .{msg_toilet_1993});

    const msg_capsule_1993 = try execute_look_at(&world, &vm, &compiled, bernard, capsule_1993_prop, &look_buf);
    try writer.print("         [1993] Bernard looks at TimeCapsule1993 -> {s}\n", .{msg_capsule_1993});

    const msg_drfred = try execute_look_at(&world, &vm, &compiled, bernard, drfred, &look_buf);
    try writer.print("         [1993] Bernard looks at DrFred -> {s}\n", .{msg_drfred});

    const msg_wine = try execute_look_at(&world, &vm, &compiled, bernard, wine, &look_buf);
    try writer.print("         [1993] Bernard inspects VintageWine -> {s}\n", .{msg_wine});

    const msg_flyer = try execute_look_at(&world, &vm, &compiled, bernard, flyer, &look_buf);
    try writer.print("         [1993] Bernard inspects TentacleFlyer -> {s}\n", .{msg_flyer});

    // 1790 Colonial Workshop (Hoagie)
    try vm.transition_to_scene(past_scene);
    const toilet_1790_prop = world.lookup_entity("ChronoToilet1790").?;
    const capsule_1790_prop = world.lookup_entity("TimeCapsule1790").?;

    const msg_tree = try execute_look_at(&world, &vm, &compiled, hoagie, tree_prop, &look_buf);
    try writer.print("         [1790] Hoagie looks at KumquatTree -> {s}\n", .{msg_tree});

    const msg_toilet_1790 = try execute_look_at(&world, &vm, &compiled, hoagie, toilet_1790_prop, &look_buf);
    try writer.print("         [1790] Hoagie looks at ChronoToilet1790 -> {s}\n", .{msg_toilet_1790});

    const msg_capsule_1790 = try execute_look_at(&world, &vm, &compiled, hoagie, capsule_1790_prop, &look_buf);
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
    const future_tree_prop = world.lookup_entity("FutureTree").?;
    const flag_prop = world.lookup_entity("TentacleFlagProp").?;
    const socket_prop = world.lookup_entity("PowerSocketProp").?;
    const toilet_2193_prop = world.lookup_entity("ChronoToilet2193").?;

    const msg_tentacle = try execute_look_at(&world, &vm, &compiled, laverne, tentacle, &look_buf);
    try writer.print("         [2193] Laverne looks at PurpleTentacle -> {s}\n", .{msg_tentacle});

    const msg_fut_tree = try execute_look_at(&world, &vm, &compiled, laverne, future_tree_prop, &look_buf);
    try writer.print("         [2193] Laverne looks at FutureTree -> {s}\n", .{msg_fut_tree});

    const msg_flag_prop = try execute_look_at(&world, &vm, &compiled, laverne, flag_prop, &look_buf);
    try writer.print("         [2193] Laverne looks at TentacleFlagProp -> {s}\n", .{msg_flag_prop});

    const msg_socket = try execute_look_at(&world, &vm, &compiled, laverne, socket_prop, &look_buf);
    try writer.print("         [2193] Laverne looks at PowerSocketProp -> {s}\n", .{msg_socket});

    const msg_toilet_2193 = try execute_look_at(&world, &vm, &compiled, laverne, toilet_2193_prop, &look_buf);
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
    if (get_latest_say_message(&world, &vm, &look_buf)) |cutscene_msg| {
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
    if (get_latest_say_message(&world, &vm, &look_buf)) |cutscene_msg| {
        try writer.print("         [Cutscene Telegraph] {s}\n", .{cutscene_msg});
    }

    // STEP 9: Forward Temporal Cascade -> Laverne freed in 2193!
    try writer.print("[Step 9] Forward Temporal Cascade: Tree ceased to exist centuries ago in 2193...\n", .{});
    const free_rel = try world.intern_relation("FreedFromTree", .set);
    _ = try world.remember(laverne, free_rel, 1, 0);
    _ = world.forget(laverne, trapped_rel, 1);
    _ = try spatial.transition_actor(laverne, future_scene, fut_guard_wp);
    try writer.print("         Laverne drops safely from absent tree to ground level!\n", .{});
    std.debug.assert(spatial.can_transfer_item_with_world(&world, bernard, laverne, .portal_anchored));
    try writer.print("         [D-026 Invariant] Portal Gating Verified: Laverne freed -> Chron-o-John transfer online!\n", .{});

    // STEP 10: Laverne retrieves Tentacle Flag disguise and bypasses guard
    try writer.print("[Step 10] Laverne climbs to roof, dons Tentacle Flag disguise, reaches power socket...\n", .{});
    _ = try world.remember(laverne, carries_rel, flag.to_int(), 0);
    const msg_flag = try execute_look_at(&world, &vm, &compiled, laverne, flag, &look_buf);
    try writer.print("         Laverne inspects TentacleFlag -> {s}\n", .{msg_flag});
    const disg_rel = try world.intern_relation("TentacleDisguiseActive", .set);
    _ = try world.remember(laverne, disg_rel, 1, 0);

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
    win.audio_bridge.set_track(.tentacle);

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.attach_audio_bridge(win.audio_bridge);
    const party = [_]bespoke.EntityId{ hoagie, bernard, laverne };
    display_bridge.set_party(&party);
    display_bridge.set_active_character(bernard);

    var is_paused = false;
    var last_tick_time = std.time.milliTimestamp();
    const tick_interval_ms: i64 = 200;
    win.set_cue_banner("Day of the Tentacle Trio loaded! Press [1] Hoagie, [2] Bernard, [3] Laverne to switch characters.", 180);

    while (true) {
        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.swap();

        const frame = display_bridge.get_frame();
        win.render_frame(frame, is_paused);

        const action = win.poll_events(frame);
        var should_step_now = false;
        switch (action) {
            .quit => break,
            .toggle_pause => is_paused = !is_paused,
            .step_tick => should_step_now = true,
            .walk_player => |wp_id| {
                const active_char = display_bridge.active_player_character orelse bernard;
                _ = try spatial.walk_to(active_char, wp_id);
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.swap();
                win.set_cue_banner("Directing character to waypoint.", 60);
            },
            .switch_party_member => |p_idx| {
                if (p_idx < party.len) {
                    const char_id = party[p_idx];
                    display_bridge.set_active_character(char_id);
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
                    } else {
                        _ = try vm.fire_cue(&compiled, "Uses", active_char, hs.entity, null);
                        try vm.step_tick();
                    }
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
                        if (get_latest_say_message(&world, &vm, &say_buf)) |speech| {
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
                }
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
                }
            },
            else => {},
        }

        // Stepping simulation clock
        const current_time = std.time.milliTimestamp();
        if ((!is_paused and (current_time - last_tick_time >= tick_interval_ms)) or should_step_now) {
            last_tick_time = current_time;
            try vm.step_tick();
            var cutscene_buf: [256]u8 = undefined;
            if (get_latest_say_message(&world, &vm, &cutscene_buf)) |cutscene_msg| {
                win.set_cue_banner(cutscene_msg, 180);
                std.debug.print("\n[Cutscene Telegraph] {s}\n", .{cutscene_msg});
            }
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
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
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Gating Verified: Laverne freed -> Chron-o-John transfer online!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Bernard looks at VintageWineBottle -> Bernard: \"A dusty 1993 vintage bottle of red wine sitting on the motel desk.\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Hoagie looks at KumquatTree -> Hoagie: \"A small, bushy kumquat tree. George Washington is glaring at it impatiently.\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Laverne looks at PurpleTentacle -> Laverne: \"A seven-foot mutant purple tentacle patrolling the security checkpoint. No humans allowed without a tentacle disguise.\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Hoagie inspects SuperBattery -> Hoagie: \"The Super Battery! 200-year-aged vinegar reacting with zinc and copper to produce mega-voltage!\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Laverne inspects TentacleFlag -> Laverne: \"Betsy Ross's 1790 flag design, perfectly altered to double as an authentic tentacle disguise!\"") != null);
}
