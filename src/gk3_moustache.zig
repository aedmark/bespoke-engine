const std = @import("std");
const bespoke = @import("root.zig");

pub const GK3_MOUSTACHE_SCRIPT =
    \\scene: Hotel Corridor
    \\cast: Gabriel, Mosely
    \\props: MoselyDoor, RoomDesk
    \\marks: Room25, Room33, CorridorExit
    \\
    \\scene: Hotel Garden
    \\cast: StrayCat
    \\props: FenceHole, GardenShrub
    \\marks: GardenPath, FenceMark, CatLounge
    \\
    \\scene: Bike Rental Shop
    \\cast: Buthane
    \\props: RentalCounter, Motorcycle
    \\marks: ShopEntrance, CounterMark, BikeMark
    \\
    \\Taped is a state, which can be taped or untaped. The hole is untaped in the scene.
    \\Startled is a state, which can be startled or calm. The cat is calm in the scene.
    \\Disguised is a state, which can be disguised or undisguised. Gabriel is undisguised in the scene.
    \\HasBikeKeys is a state, which can be held or unheld.
    \\
    \\remember: Carries(Gabriel, SprayBottle)
    \\remember: Carries(Gabriel, MaskingTape)
    \\remember: Carries(Gabriel, Marker)
    \\remember: Carries(Gabriel, Syrup)
    \\
    \\routine MoselyPacing(Mosely):
    \\  loop:
    \\    walk Mosely to Room33
    \\    wait 30 ticks
    \\    walk Mosely to CorridorExit
    \\    wait 30 ticks
    \\
    \\routine CatNapping(StrayCat):
    \\  loop:
    \\    wait 40 ticks
    \\    say StrayCat: "Meow..."
    \\
    \\on cue Uses(Gabriel, MoselyDoor):
    \\  if not Carries(Gabriel, MoselyPassport):
    \\    say Gabriel: "I'll snatch Mosely's passport from his coat pocket while he's not looking."
    \\    remember Carries(Gabriel, MoselyPassport)
    \\
    \\on cue Uses(Gabriel, Marker, MoselyPassport):
    \\  say Gabriel: "Mosely doesn't even have a moustache in his passport photo! I'll draw one on with my marker."
    \\    remember PassportModified(Gabriel, true)
    \\
    \\on cue Uses(Gabriel, MaskingTape, FenceHole):
    \\  now FenceHole is taped
    \\  say Gabriel: "I've stretched sticky masking tape across the bottom of the fence hole."
    \\
    \\on cue Uses(Gabriel, SprayBottle, StrayCat):
    \\  if FenceHole is not taped:
    \\    say Gabriel: "Squirting the cat now won't help; the fence hole isn't taped."
    \\  if FenceHole is taped:
    \\    now StrayCat is startled
    \\    animate (StrayCat, cat-fleeing)
    \\    walk StrayCat to FenceMark
    \\    say Gabriel: "The startled cat bolts through the fence hole, leaving a thick tuft of black fur stuck to the tape!"
    \\    remember FenceHasHair(FenceHole, true)
    \\
    \\on cue Uses(Gabriel, FenceHole):
    \\  if FenceHasHair(FenceHole):
    \\    say Gabriel: "I'll peel the tape off. Presto: a strip of genuine black cat hair."
    \\    remember Carries(Gabriel, CatHair)
    \\    forget FenceHasHair(FenceHole)
    \\    now FenceHole is not taped
    \\
    \\on cue Uses(Gabriel, CatHair, Syrup):
    \\  say Gabriel: "I dab warm breakfast syrup onto my upper lip, then press the cat hair firmly in place."
    \\  remember Carries(Gabriel, CatMoustache)
    \\  remember StickyLip(Gabriel, true)
    \\
    \\on cue Uses(Gabriel, CatMoustache, Gabriel):
    \\  if PassportModified(Gabriel):
    \\    say Gabriel: "With Mosely's passport and my dashing cat-hair moustache, the resemblance is uncanny!"
    \\    now Gabriel is disguised
    \\  if not PassportModified(Gabriel):
    \\    say Gabriel: "I've got the moustache on, but Mosely's passport photo still has no moustache! I need to fix the passport."
    \\
    \\on cue TalksTo(Gabriel, Buthane):
    \\  choice "I'd like to rent a motorcycle." if not Disguised(Gabriel):
    \\    say Buthane: "Désolé, monsieur! The last motorcycle is reserved for detective Franklin Mosely."
    \\  choice "I am detective Franklin Mosely. I've come for my motorcycle." if Disguised(Gabriel):
    \\    say Buthane: "Ah, Monsieur Mosely! That is a magnificent moustache. Here are the keys!"
    \\    remember HasBikeKeys(Gabriel, true)
    \\  choice "Whose cat is that outside?":
    \\    say Buthane: "It belongs to the village priest. Don't frighten the poor creature!"
    \\  choice "Au revoir, madame.":
    \\    say Buthane: "Bonne journée, monsieur!"
;

pub const Gk3Stage = enum {
    hotel_corridor,
    hotel_garden,
    bike_rental_shop,
};

/// Evaluates whether Gabriel Knight has completed his disguise to rent the motorcycle (P14-01, D-016).
pub fn evaluate_disguise(world: *const bespoke.World) bool {
    const gabriel = world.lookup_entity("Gabriel") orelse return false;

    // Check disguised status
    var is_disguised = false;
    if (world.lookup_relation("disguised") orelse world.lookup_relation("Disguised")) |rel| {
        is_disguised = world.has_fact(gabriel, rel, null);
    }

    // Check carried cat moustache
    var has_moustache = false;
    if (world.lookup_relation("Carries")) |rel| {
        if (world.lookup_entity("CatMoustache")) |m_id| {
            has_moustache = world.has_fact(gabriel, rel, m_id.to_int());
        }
    }

    // Check modified passport
    var has_modified_passport = false;
    if (world.lookup_relation("PassportModified")) |rel| {
        has_modified_passport = world.has_fact(gabriel, rel, 1);
    }

    return is_disguised or (has_moustache and has_modified_passport);
}

/// Evaluates whether the motorcycle puzzle has been successfully solved (P14-01, D-016).
pub fn evaluate_puzzle_victory(world: *const bespoke.World) bool {
    const gabriel = world.lookup_entity("Gabriel") orelse return false;
    if (world.lookup_relation("HasBikeKeys") orelse world.lookup_relation("BikeRented")) |rel| {
        return world.has_fact(gabriel, rel, null);
    }
    return false;
}

/// Executes headless simulation of the Gabriel Knight 3 Cat Moustache vertical slice (P14-01, P14-03, D-016).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("      BeSpoke Engine: The Gabriel Knight 3 Cat Moustache Scenario   \n", .{});
    try writer.print("  (Multi-Scene DSL * Crafting * Dynamic Fact-Guarded Dialogue)     \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Lowering Gabriel Knight 3 narrative script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, GK3_MOUSTACHE_SCRIPT);
    defer compiled.deinit();

    // Scene Room Entities
    const hotel_scene = world.lookup_entity("Hotel Corridor").?;
    const garden_scene = world.lookup_entity("Hotel Garden").?;
    const shop_scene = world.lookup_entity("Bike Rental Shop").?;

    // Actor Entities
    const gabriel = world.lookup_entity("Gabriel").?;
    const mosely = world.lookup_entity("Mosely").?;
    const stray_cat = world.lookup_entity("StrayCat").?;
    const buthane = world.lookup_entity("Buthane").?;

    // Spatial Marks
    const r25_wp = spatial.graph.find_waypoint_in_room(hotel_scene, "Room25") orelse 1;
    const r33_wp = spatial.graph.find_waypoint_in_room(hotel_scene, "Room33") orelse 2;
    const corridor_wp = spatial.graph.find_waypoint_in_room(hotel_scene, "CorridorExit") orelse
        try spatial.graph.add_waypoint(hotel_scene, 24, 0, "CorridorExit");

    const garden_path_wp = spatial.graph.find_waypoint_in_room(garden_scene, "GardenPath") orelse
        try spatial.graph.add_waypoint(garden_scene, 0, 0, "GardenPath");
    const fence_wp = spatial.graph.find_waypoint_in_room(garden_scene, "FenceMark") orelse
        try spatial.graph.add_waypoint(garden_scene, 18, 0, "FenceMark");
    const cat_wp = spatial.graph.find_waypoint_in_room(garden_scene, "CatLounge") orelse
        try spatial.graph.add_waypoint(garden_scene, 32, 0, "CatLounge");

    const shop_ent_wp = spatial.graph.find_waypoint_in_room(shop_scene, "ShopEntrance") orelse
        try spatial.graph.add_waypoint(shop_scene, 0, 0, "ShopEntrance");
    const counter_wp = spatial.graph.find_waypoint_in_room(shop_scene, "CounterMark") orelse
        try spatial.graph.add_waypoint(shop_scene, 16, 0, "CounterMark");
    const bike_wp = spatial.graph.find_waypoint_in_room(shop_scene, "BikeMark") orelse
        try spatial.graph.add_waypoint(shop_scene, 30, 0, "BikeMark");

    // Position waypoints
    if (spatial.graph.get_waypoint(r25_wp)) |_| spatial.graph.waypoints.items[r25_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(r33_wp)) |_| spatial.graph.waypoints.items[r33_wp - 1].pos = .{ .x = 12, .y = 0 };
    if (spatial.graph.get_waypoint(corridor_wp)) |_| spatial.graph.waypoints.items[corridor_wp - 1].pos = .{ .x = 24, .y = 0 };

    if (spatial.graph.get_waypoint(garden_path_wp)) |_| spatial.graph.waypoints.items[garden_path_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(fence_wp)) |_| spatial.graph.waypoints.items[fence_wp - 1].pos = .{ .x = 18, .y = 0 };
    if (spatial.graph.get_waypoint(cat_wp)) |_| spatial.graph.waypoints.items[cat_wp - 1].pos = .{ .x = 32, .y = 0 };

    if (spatial.graph.get_waypoint(shop_ent_wp)) |_| spatial.graph.waypoints.items[shop_ent_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(counter_wp)) |_| spatial.graph.waypoints.items[counter_wp - 1].pos = .{ .x = 16, .y = 0 };
    if (spatial.graph.get_waypoint(bike_wp)) |_| spatial.graph.waypoints.items[bike_wp - 1].pos = .{ .x = 30, .y = 0 };

    try spatial.graph.connect(r25_wp, r33_wp, null);
    try spatial.graph.connect(r33_wp, corridor_wp, null);
    try spatial.graph.connect(garden_path_wp, fence_wp, null);
    try spatial.graph.connect(fence_wp, cat_wp, null);
    try spatial.graph.connect(shop_ent_wp, counter_wp, null);
    try spatial.graph.connect(counter_wp, bike_wp, null);

    // Register actors
    try spatial.register_entity(gabriel, r25_wp, 10);
    try spatial.register_entity(mosely, r33_wp, 11);
    try spatial.register_entity(stray_cat, cat_wp, 12);
    try spatial.register_entity(buthane, counter_wp, 13);

    // Initial inventory for Gabriel (from script declarations)
    const carries_rel = try world.intern_relation("Carries", .set);
    const spray_bottle = try world.intern_entity("SprayBottle");
    const masking_tape = try world.intern_entity("MaskingTape");
    const marker = try world.intern_entity("Marker");
    const syrup = try world.intern_entity("Syrup");
    try world.remember(gabriel, carries_rel, spray_bottle.to_int(), 0);
    try world.remember(gabriel, carries_rel, masking_tape.to_int(), 0);
    try world.remember(gabriel, carries_rel, marker.to_int(), 0);
    try world.remember(gabriel, carries_rel, syrup.to_int(), 0);

    // Register Hotspots
    const mosely_door = world.lookup_entity("MoselyDoor") orelse try world.intern_entity("MoselyDoor");
    const room_desk = world.lookup_entity("RoomDesk") orelse try world.intern_entity("RoomDesk");
    const fence_hole = world.lookup_entity("FenceHole") orelse try world.intern_entity("FenceHole");
    const garden_shrub = world.lookup_entity("GardenShrub") orelse try world.intern_entity("GardenShrub");
    const rental_counter = world.lookup_entity("RentalCounter") orelse try world.intern_entity("RentalCounter");
    const motorcycle = world.lookup_entity("Motorcycle") orelse try world.intern_entity("Motorcycle");

    try spatial.add_hotspot(mosely_door, hotel_scene, .{ .x = 12, .y = -6 }, 8, "Mosely's Door", "Room 33. Mosely's jacket is hanging on the coat rack inside.");
    try spatial.add_hotspot(room_desk, hotel_scene, .{ .x = 0, .y = -6 }, 8, "Room Desk", "A wooden desk holding breakfast syrup, tape, and a marker.");
    try spatial.add_hotspot(fence_hole, garden_scene, .{ .x = 18, .y = -4 }, 8, "Fence Hole", "A low hole cut into the base of the wooden garden fence.");
    try spatial.add_hotspot(garden_shrub, garden_scene, .{ .x = 32, .y = -4 }, 8, "Garden Shrub", "A sun-dappled lavender bush where the stray cat likes to nap.");
    try spatial.add_hotspot(rental_counter, shop_scene, .{ .x = 16, .y = -6 }, 8, "Rental Desk", "Madame Buthane's counter, piled with French road maps and bike keys.");
    try spatial.add_hotspot(motorcycle, shop_scene, .{ .x = 30, .y = -6 }, 10, "Motorcycle", "A sleek vintage motorcycle, reserved for detective Mosely.");

    // VM
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(hotel_scene);

    if (compiled.routine_entries.get("MoselyPacing")) |entry| {
        _ = try vm.spawn_routine(mosely, entry);
    }
    if (compiled.routine_entries.get("CatNapping")) |entry| {
        _ = try vm.spawn_routine(stray_cat, entry);
    }

    try writer.print("[Step 1: Inspect Initial State]\n", .{});
    try writer.print("   -> Current Scene: Hotel Corridor\n", .{});
    try writer.print("   -> Gabriel Disguised? {s}\n", .{if (evaluate_disguise(&world)) "YES" else "NO"});
    try writer.print("   -> Has Motorcycle Keys? {s}\n\n", .{if (evaluate_puzzle_victory(&world)) "YES" else "NO"});

    // Step 2: Step ticks to observe Mosely pacing
    try writer.print("[Step 2: Simulate Ambient Routines]\n", .{});
    var tick: usize = 0;
    while (tick < 5) : (tick += 1) {
        try vm.step_tick();
    }
    try writer.print("   -> Advanced to Tick 5: Mosely is pacing between Room 33 and the corridor.\n\n", .{});

    // Save snapshot 0 for time-travel rewind verification
    var snapshot_start = std.ArrayList(u8).init(allocator);
    defer snapshot_start.deinit();
    try world.save_state(snapshot_start.writer());

    // Step 3: Snatch Mosely's passport
    try writer.print("[Step 3: Snatch Mosely's Passport from Room 33]\n", .{});
    const passport_ent = try world.intern_entity("MoselyPassport");
    try world.remember(gabriel, carries_rel, passport_ent.to_int(), 0);
    try writer.print("   -> Gabriel acquired MoselyPassport!\n\n", .{});

    // Step 4: Draw fake moustache on Mosely's passport with marker
    try writer.print("[Step 4: Draw Moustache on Mosely's Passport with Marker]\n", .{});
    const passport_mod_rel = try world.intern_relation("PassportModified", .property);
    try world.remember(gabriel, passport_mod_rel, 1, 0);
    try writer.print("   -> Mosely's passport photo now features a drawn moustache!\n\n", .{});

    // Step 5: Transition to Hotel Garden
    try writer.print("[Step 5: Transition Scene to Hotel Garden]\n", .{});
    try vm.transition_to_scene(garden_scene);
    _ = try spatial.transition_actor(gabriel, garden_scene, garden_path_wp);
    try writer.print("   -> Gabriel stepped into the courtyard garden.\n\n", .{});

    // Step 6: Tape the fence hole with MaskingTape
    try writer.print("[Step 6: Stretch Masking Tape Across Fence Hole]\n", .{});
    const taped_rel = try world.intern_relation("Taped", .property);
    try world.remember(fence_hole, taped_rel, 1, 0);
    try writer.print("   -> FenceHole is now taped!\n\n", .{});

    // Step 7: Squirt StrayCat with SprayBottle
    try writer.print("[Step 7: Squirt Stray Cat with Water Bottle]\n", .{});
    const startled_rel = try world.intern_relation("Startled", .property);
    const fence_hair_rel = try world.intern_relation("FenceHasHair", .property);
    try world.remember(stray_cat, startled_rel, 1, 0);
    _ = try spatial.walk_to(stray_cat, fence_wp);
    try world.remember(fence_hole, fence_hair_rel, 1, 0);
    try writer.print("   -> Cat bolted through fence! A thick strip of cat fur clings to the tape!\n\n", .{});

    // Step 8: Collect CatHair from FenceHole
    try writer.print("[Step 8: Peel Cat Hair from the Fence Tape]\n", .{});
    const cat_hair_ent = try world.intern_entity("CatHair");
    try world.remember(gabriel, carries_rel, cat_hair_ent.to_int(), 0);
    _ = world.forget(fence_hole, fence_hair_rel, null);
    _ = world.forget(fence_hole, taped_rel, null);
    try writer.print("   -> Gabriel acquired CatHair!\n\n", .{});

    // Step 9: Combine CatHair with Breakfast Syrup to craft CatMoustache
    try writer.print("[Step 9: Craft Cat-Hair Moustache with Syrup]\n", .{});
    const moustache_ent = try world.intern_entity("CatMoustache");
    const sticky_lip_rel = try world.intern_relation("StickyLip", .property);
    try world.remember(gabriel, carries_rel, moustache_ent.to_int(), 0);
    try world.remember(gabriel, sticky_lip_rel, 1, 0);
    try writer.print("   -> Gabriel applied syrup adhesive and crafted CatMoustache!\n\n", .{});

    // Step 10: Put on CatMoustache and disguise as Mosely
    try writer.print("[Step 10: Don the Disguise]\n", .{});
    const disguised_rel = try world.intern_relation("Disguised", .property);
    try world.remember(gabriel, disguised_rel, 1, 0);
    try writer.print("   -> Gabriel is now DISGUISED as Franklin Mosely!\n", .{});
    try writer.print("   -> Evaluate Disguise: {s}\n\n", .{if (evaluate_disguise(&world)) "VALID DISGUISE" else "INVALID"});

    // Step 11: Transition to Bike Rental Shop
    try writer.print("[Step 11: Transition to Bike Rental Shop]\n", .{});
    try vm.transition_to_scene(shop_scene);
    _ = try spatial.transition_actor(gabriel, shop_scene, shop_ent_wp);
    try writer.print("   -> Gabriel entered Madame Buthane's motorcycle rental desk.\n\n", .{});

    // Step 12: Test Relational Dialogue Choice Pruning with Madame Buthane
    try writer.print("[Step 12: Dialogue Choice Pruning with Madame Buthane]\n", .{});
    const disguised_arg = [_][]const u8{"Gabriel"};
    const empty_body: []const bespoke.compiler.parser.Stmt = &[_]bespoke.compiler.parser.Stmt{};

    const buthane_choices = [_]bespoke.compiler.parser.DialogueChoice{
        .{
            .text = "I'd like to rent a motorcycle.",
            .guard = .{ .not_fact = .{ .relation = "Disguised", .args = &disguised_arg } },
            .body = empty_body,
        },
        .{
            .text = "I am detective Franklin Mosely. I've come for my motorcycle.",
            .guard = .{ .has_fact = .{ .relation = "Disguised", .args = &disguised_arg } },
            .body = empty_body,
        },
        .{
            .text = "Do you know whose cat is prowling outside?",
            .guard = null,
            .body = empty_body,
        },
        .{
            .text = "Au revoir, madame.",
            .guard = null,
            .body = empty_body,
        },
    };

    var pruned_choices: [8]bespoke.vm.PrunedChoice = undefined;
    const choice_count = vm.prune_dialogue_choices(&buthane_choices, &pruned_choices);

    try writer.print("   -> Active Dialogue Choices Presented by Buthane ({d} available):\n", .{choice_count});
    var ci: usize = 0;
    while (ci < choice_count) : (ci += 1) {
        try writer.print("      [{d}] \"{s}\"\n", .{ ci + 1, pruned_choices[ci].text });
    }

    // Choice 0 is the Mosely impersonation branch
    try std.testing.expectEqualStrings("I am detective Franklin Mosely. I've come for my motorcycle.", pruned_choices[0].text);
    try writer.print("   -> Gabriel selects Choice 1!\n", .{});

    const has_keys_rel = try world.intern_relation("HasBikeKeys", .property);
    try world.remember(gabriel, has_keys_rel, 1, 0);

    try writer.print("   -> Buthane: \"Ah, Monsieur Mosely! That is a magnificent moustache. Here are the keys!\"\n", .{});
    try writer.print("   -> Has Motorcycle Keys? {s}\n", .{if (evaluate_puzzle_victory(&world)) "YES! PUZZLE SOLVED!" else "NO"});
    try std.testing.expect(evaluate_puzzle_victory(&world));
    try writer.print("\n", .{});

    // Step 13: Time-Travel Rewind Demo
    try writer.print("[Step 13: Time-Travel Rewind Demo]\n", .{});
    try writer.print("   -> Rewinding simulation state back to Step 2 (hotel corridor, undisguised)...\n", .{});
    var stream = std.io.fixedBufferStream(snapshot_start.items);
    try world.restore_state(stream.reader());

    try writer.print("   -> Rewound Gabriel Disguised? {s}\n", .{if (evaluate_disguise(&world)) "YES" else "NO (Restored to false!)"});
    try writer.print("   -> Rewound Has Motorcycle Keys? {s}\n", .{if (evaluate_puzzle_victory(&world)) "YES" else "NO (Restored to false!)"});
    try std.testing.expect(!evaluate_disguise(&world));
    try std.testing.expect(!evaluate_puzzle_victory(&world));

    try writer.print("\n===================================================================\n", .{});
    try writer.print("   Gabriel Knight 3 Cat Moustache Vertical Slice Succeeded!       \n", .{});
    try writer.print("===================================================================\n", .{});
}

/// Executes interactive 60 Hz simulation with graphical display (P14-03, D-016).
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, GK3_MOUSTACHE_SCRIPT);
    defer compiled.deinit();

    const hotel_scene = world.lookup_entity("Hotel Corridor").?;
    const garden_scene = world.lookup_entity("Hotel Garden").?;
    const shop_scene = world.lookup_entity("Bike Rental Shop").?;

    const gabriel = world.lookup_entity("Gabriel").?;
    const mosely = world.lookup_entity("Mosely").?;
    const stray_cat = world.lookup_entity("StrayCat").?;
    const buthane = world.lookup_entity("Buthane").?;

    const r25_wp = spatial.graph.find_waypoint_in_room(hotel_scene, "Room25") orelse 1;
    const r33_wp = spatial.graph.find_waypoint_in_room(hotel_scene, "Room33") orelse 2;
    const corridor_wp = spatial.graph.find_waypoint_in_room(hotel_scene, "CorridorExit") orelse
        try spatial.graph.add_waypoint(hotel_scene, 24, 0, "CorridorExit");

    const garden_path_wp = spatial.graph.find_waypoint_in_room(garden_scene, "GardenPath") orelse
        try spatial.graph.add_waypoint(garden_scene, 0, 0, "GardenPath");
    const fence_wp = spatial.graph.find_waypoint_in_room(garden_scene, "FenceMark") orelse
        try spatial.graph.add_waypoint(garden_scene, 18, 0, "FenceMark");
    const cat_wp = spatial.graph.find_waypoint_in_room(garden_scene, "CatLounge") orelse
        try spatial.graph.add_waypoint(garden_scene, 32, 0, "CatLounge");

    const shop_ent_wp = spatial.graph.find_waypoint_in_room(shop_scene, "ShopEntrance") orelse
        try spatial.graph.add_waypoint(shop_scene, 0, 0, "ShopEntrance");
    const counter_wp = spatial.graph.find_waypoint_in_room(shop_scene, "CounterMark") orelse
        try spatial.graph.add_waypoint(shop_scene, 16, 0, "CounterMark");
    const bike_wp = spatial.graph.find_waypoint_in_room(shop_scene, "BikeMark") orelse
        try spatial.graph.add_waypoint(shop_scene, 30, 0, "BikeMark");

    // Position waypoints
    if (spatial.graph.get_waypoint(r25_wp)) |_| spatial.graph.waypoints.items[r25_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(r33_wp)) |_| spatial.graph.waypoints.items[r33_wp - 1].pos = .{ .x = 12, .y = 0 };
    if (spatial.graph.get_waypoint(corridor_wp)) |_| spatial.graph.waypoints.items[corridor_wp - 1].pos = .{ .x = 24, .y = 0 };

    if (spatial.graph.get_waypoint(garden_path_wp)) |_| spatial.graph.waypoints.items[garden_path_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(fence_wp)) |_| spatial.graph.waypoints.items[fence_wp - 1].pos = .{ .x = 18, .y = 0 };
    if (spatial.graph.get_waypoint(cat_wp)) |_| spatial.graph.waypoints.items[cat_wp - 1].pos = .{ .x = 32, .y = 0 };

    if (spatial.graph.get_waypoint(shop_ent_wp)) |_| spatial.graph.waypoints.items[shop_ent_wp - 1].pos = .{ .x = 0, .y = 0 };
    if (spatial.graph.get_waypoint(counter_wp)) |_| spatial.graph.waypoints.items[counter_wp - 1].pos = .{ .x = 16, .y = 0 };
    if (spatial.graph.get_waypoint(bike_wp)) |_| spatial.graph.waypoints.items[bike_wp - 1].pos = .{ .x = 30, .y = 0 };

    try spatial.graph.connect(r25_wp, r33_wp, null);
    try spatial.graph.connect(r33_wp, corridor_wp, null);
    try spatial.graph.connect(garden_path_wp, fence_wp, null);
    try spatial.graph.connect(fence_wp, cat_wp, null);
    try spatial.graph.connect(shop_ent_wp, counter_wp, null);
    try spatial.graph.connect(counter_wp, bike_wp, null);

    try spatial.register_entity(gabriel, r25_wp, 10);
    try spatial.register_entity(mosely, r33_wp, 11);
    try spatial.register_entity(stray_cat, cat_wp, 12);
    try spatial.register_entity(buthane, counter_wp, 13);

    // Initial inventory for Gabriel
    const carries_rel = try world.intern_relation("Carries", .set);
    const spray_bottle = try world.intern_entity("SprayBottle");
    const masking_tape = try world.intern_entity("MaskingTape");
    const marker = try world.intern_entity("Marker");
    const syrup = try world.intern_entity("Syrup");
    try world.remember(gabriel, carries_rel, spray_bottle.to_int(), 0);
    try world.remember(gabriel, carries_rel, masking_tape.to_int(), 0);
    try world.remember(gabriel, carries_rel, marker.to_int(), 0);
    try world.remember(gabriel, carries_rel, syrup.to_int(), 0);

    const mosely_door = world.lookup_entity("MoselyDoor") orelse try world.intern_entity("MoselyDoor");
    const room_desk = world.lookup_entity("RoomDesk") orelse try world.intern_entity("RoomDesk");
    const fence_hole = world.lookup_entity("FenceHole") orelse try world.intern_entity("FenceHole");
    const garden_shrub = world.lookup_entity("GardenShrub") orelse try world.intern_entity("GardenShrub");
    const rental_counter = world.lookup_entity("RentalCounter") orelse try world.intern_entity("RentalCounter");
    const motorcycle = world.lookup_entity("Motorcycle") orelse try world.intern_entity("Motorcycle");

    try spatial.add_hotspot(mosely_door, hotel_scene, .{ .x = 12, .y = -6 }, 8, "Mosely's Door", "Room 33. Mosely's jacket is hanging on the coat rack inside.");
    try spatial.add_hotspot(room_desk, hotel_scene, .{ .x = 0, .y = -6 }, 8, "Room Desk", "A wooden desk holding breakfast syrup, tape, and a marker.");
    try spatial.add_hotspot(fence_hole, garden_scene, .{ .x = 18, .y = -4 }, 8, "Fence Hole", "A low hole cut into the base of the wooden garden fence.");
    try spatial.add_hotspot(garden_shrub, garden_scene, .{ .x = 32, .y = -4 }, 8, "Garden Shrub", "A sun-dappled lavender bush where the stray cat likes to nap.");
    try spatial.add_hotspot(rental_counter, shop_scene, .{ .x = 16, .y = -6 }, 8, "Rental Desk", "Madame Buthane's counter, piled with French road maps and bike keys.");
    try spatial.add_hotspot(motorcycle, shop_scene, .{ .x = 30, .y = -6 }, 10, "Motorcycle", "A sleek vintage motorcycle, reserved for detective Mosely.");

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(hotel_scene);

    if (compiled.routine_entries.get("MoselyPacing")) |entry| {
        _ = try vm.spawn_routine(mosely, entry);
    }
    if (compiled.routine_entries.get("CatNapping")) |entry| {
        _ = try vm.spawn_routine(stray_cat, entry);
    }

    var display_bridge = bespoke.DisplayBridge.init();
    const repl_instance = bespoke.Repl.init(&world, &spatial, &vm);
    _ = repl_instance;

    var history_snapshots = std.ArrayList(std.ArrayList(u8)).init(allocator);
    defer {
        for (history_snapshots.items) |*buf| buf.deinit();
        history_snapshots.deinit();
    }

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - Gabriel Knight 3: The Cat Moustache", 960, 540);
    defer window.deinit();

    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (960x540) <<<\n", .{});
    try stdout.print("Gabriel Knight 3 Scenario Controls:\n", .{});
    try stdout.print("   - [H]:                   Go to Hotel Corridor\n", .{});
    try stdout.print("   - [G]:                   Go to Hotel Courtyard Garden\n", .{});
    try stdout.print("   - [B]:                   Go to Madame Buthane's Bike Rental Shop\n", .{});
    try stdout.print("   - [1]:                   Snatch Mosely's Passport from Room 33\n", .{});
    try stdout.print("   - [2]:                   Draw Moustache on Passport with Marker\n", .{});
    try stdout.print("   - [3]:                   Tape the Fence Hole\n", .{});
    try stdout.print("   - [4]:                   Squirt the Cat with Water Bottle\n", .{});
    try stdout.print("   - [5]:                   Peel Cat Hair from Fence Tape\n", .{});
    try stdout.print("   - [6]:                   Craft Cat Moustache with Syrup Adhesive\n", .{});
    try stdout.print("   - [7]:                   Don the Disguise (Cat Moustache + Modified Passport)\n", .{});
    try stdout.print("   - [8]:                   Talk to Madame Buthane & Claim Motorcycle\n", .{});
    try stdout.print("   - [Timeline Scrubber]:   Click or drag timeline bar (or [< / >] arrows)\n", .{});
    try stdout.print("   - [F1 / D]:              Toggle Debug Relational Fact & Fiber Overlay\n", .{});
    try stdout.print("   - [Tab / ` / C]:         Toggle Live REPL Console Drawer\n", .{});
    try stdout.print("   - [Space]:               Pause / Resume Simulation Clock\n", .{});
    try stdout.print("   - [N]:                   Single-step Simulation Tick\n", .{});
    try stdout.print("   - [R]:                   Instant Time-Travel Rewind\n", .{});
    try stdout.print("   - [Esc / Close]:         Exit\n\n", .{});

    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.set_max_history_tick(0);
    display_bridge.swap();

    var snap0 = std.ArrayList(u8).init(allocator);
    try world.save_state(snap0.writer());
    try history_snapshots.append(snap0);

    var is_paused = false;
    var last_tick_time = std.time.milliTimestamp();
    const tick_interval_ms: i64 = 200;

    window.set_cue_banner("Welcome to Rennes-le-Château! [H] Hotel, [G] Garden, [B] Bike Shop. [1-8] Solve Puzzle.", 150);

    const passport_ent = try world.intern_entity("MoselyPassport");
    const passport_mod_rel = try world.intern_relation("PassportModified", .property);
    const taped_rel = try world.intern_relation("Taped", .property);
    const startled_rel = try world.intern_relation("Startled", .property);
    const fence_hair_rel = try world.intern_relation("FenceHasHair", .property);
    const cat_hair_ent = try world.intern_entity("CatHair");
    const moustache_ent = try world.intern_entity("CatMoustache");
    const sticky_lip_rel = try world.intern_relation("StickyLip", .property);
    const disguised_rel = try world.intern_relation("Disguised", .property);
    const has_keys_rel = try world.intern_relation("HasBikeKeys", .property);

    while (true) {
        const action = window.poll_events(display_bridge.get_frame());
        var should_step_now = false;

        switch (action) {
            .quit => break,
            .toggle_pause => is_paused = !is_paused,
            .step_tick => should_step_now = true,
            .walk_player => |wp_id| {
                _ = try spatial.walk_to(gabriel, wp_id);
                if (wp_id == corridor_wp and vm.current_scene == hotel_scene) {
                    try vm.transition_to_scene(garden_scene);
                    _ = try spatial.transition_actor(gabriel, garden_scene, garden_path_wp);
                    window.set_cue_banner("Stepped outside into the Hotel Courtyard Garden. [H] Hotel [B] Shop", 120);
                } else if (wp_id == cat_wp and vm.current_scene == garden_scene) {
                    try vm.transition_to_scene(shop_scene);
                    _ = try spatial.transition_actor(gabriel, shop_scene, shop_ent_wp);
                    window.set_cue_banner("Walked into Madame Buthane's Bike Rental Shop. [H] Hotel [G] Garden", 120);
                } else if (wp_id == shop_ent_wp and vm.current_scene == shop_scene) {
                    try vm.transition_to_scene(hotel_scene);
                    _ = try spatial.transition_actor(gabriel, hotel_scene, r25_wp);
                    window.set_cue_banner("Returned to the Hotel Corridor. [G] Garden [B] Shop", 120);
                } else {
                    window.set_cue_banner("Directing Gabriel to waypoint.", 60);
                }
            },
            .combine_inventory_items => |comb| {
                const frame = display_bridge.get_frame();
                if (comb.primary_index < frame.inventory_count and comb.secondary_index < frame.inventory_count) {
                    const item_a = frame.inventory[comb.primary_index].get_name();
                    const item_b = frame.inventory[comb.secondary_index].get_name();

                    if ((std.mem.eql(u8, item_a, "Marker") and std.mem.eql(u8, item_b, "MoselyPassport")) or
                        (std.mem.eql(u8, item_a, "MoselyPassport") and std.mem.eql(u8, item_b, "Marker")))
                    {
                        try world.remember(gabriel, passport_mod_rel, 1, 0);
                        window.set_cue_banner("★ Step 2: Drew a magnificent moustache on Mosely's passport photo! ★", 150);
                    } else if ((std.mem.eql(u8, item_a, "Syrup") and std.mem.eql(u8, item_b, "CatHair")) or
                               (std.mem.eql(u8, item_a, "CatHair") and std.mem.eql(u8, item_b, "Syrup")))
                    {
                        try world.remember(gabriel, carries_rel, moustache_ent.to_int(), 0);
                        try world.remember(gabriel, sticky_lip_rel, 1, 0);
                        _ = world.forget(gabriel, carries_rel, cat_hair_ent.to_int());
                        window.set_cue_banner("★ Step 6: Applied warm breakfast syrup and crafted Cat Moustache! ★", 150);
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

                    if (std.mem.eql(u8, item_name, "SprayBottle") and std.mem.eql(u8, actor_name, "StrayCat")) {
                        if (world.has_fact(fence_hole, taped_rel, null)) {
                            try world.remember(stray_cat, startled_rel, 1, 0);
                            try world.remember(fence_hole, fence_hair_rel, 1, 0);
                            _ = try spatial.walk_to(stray_cat, fence_wp);
                            window.set_cue_banner("★ Step 4: SQUIRT! Cat bolted through fence! Strip of fur left on tape! ★", 180);
                        } else {
                            window.set_cue_banner("Gabriel: \"Squirting the cat now won't help; the fence hole isn't taped!\"", 120);
                        }
                    } else if (std.mem.eql(u8, item_name, "CatMoustache") and std.mem.eql(u8, actor_name, "Gabriel")) {
                        if (world.has_fact(gabriel, passport_mod_rel, null)) {
                            try world.remember(gabriel, disguised_rel, 1, 0);
                            window.set_cue_banner("★ Step 7: Gabriel is now fully DISGUISED as detective Mosely! ★", 180);
                        } else {
                            window.set_cue_banner("Gabriel: \"I've got the moustache, but Mosely's passport photo still has no moustache!\"", 120);
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

                    if (std.mem.eql(u8, item_name, "MaskingTape") and std.mem.indexOf(u8, hs_name, "Hole") != null) {
                        try world.remember(fence_hole, taped_rel, 1, 0);
                        window.set_cue_banner("★ Step 3: Stretched sticky masking tape across the fence hole! ★", 150);
                    } else if (std.mem.indexOf(u8, hs_name, "Door") != null) {
                        if (!world.has_fact(gabriel, carries_rel, passport_ent.to_int())) {
                            try world.remember(gabriel, carries_rel, passport_ent.to_int(), 0);
                            window.set_cue_banner("★ Step 1: Reached into Mosely's room and snatched his passport! ★", 150);
                        } else {
                            window.set_cue_banner("Gabriel: \"I already have Mosely's passport.\"", 90);
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
                    var buf: [128]u8 = undefined;
                    const text = std.fmt.bufPrint(&buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Hotspot";
                    window.set_cue_banner(text, 120);
                }
            },
            .interact_actor => |act| {
                const frame = display_bridge.get_frame();
                if (act.actor_index < frame.entity_count) {
                    const target_entity = frame.entities[act.actor_index];
                    const tname = target_entity.get_name();
                    const pt = bespoke.display.renderer.get_entity_screen_pos(act.actor_index, frame.entities[0..frame.entity_count], window.width, window.height);

                    if (std.mem.eql(u8, tname, "Buthane")) {
                        const is_dg = evaluate_disguise(&world);
                        if (is_dg) {
                            window.show_dialogue(
                                target_entity.entity,
                                pt,
                                "Madame Buthane",
                                "\"Bonjour, monsieur! How can I help you today?\"",
                                &[_][]const u8{
                                    "I am detective Franklin Mosely. I've come for my bike.",
                                    "Do you know whose cat that is outside?",
                                    "Au revoir, madame.",
                                },
                            );
                        } else {
                            window.show_dialogue(
                                target_entity.entity,
                                pt,
                                "Madame Buthane",
                                "\"Bonjour, monsieur! How can I help you today?\"",
                                &[_][]const u8{
                                    "I'd like to rent a motorcycle.",
                                    "Do you know whose cat that is outside?",
                                    "Au revoir, madame.",
                                },
                            );
                        }
                    } else if (std.mem.eql(u8, tname, "Mosely")) {
                        window.set_cue_banner("Mosely: \"Hey Gabriel! Taking in the French sights?\"", 90);
                    } else if (std.mem.eql(u8, tname, "StrayCat")) {
                        window.set_cue_banner("Stray Cat: \"Meow! (A sleek black coat, basking in the sun.)\"", 90);
                    } else {
                        window.set_cue_banner("Gabriel Knight: Scribe, shadow hunter, man about town.", 90);
                    }
                }
            },
            .interact_hotspot => |hs_act| {
                const frame = display_bridge.get_frame();
                if (hs_act.hotspot_index < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_act.hotspot_index];
                    const hname = hs.get_name();
                    if (std.mem.indexOf(u8, hname, "Door") != null) {
                        try world.remember(gabriel, carries_rel, passport_ent.to_int(), 0);
                        window.set_cue_banner("★ Step 1: Snatched Mosely's passport from Room 33! ★", 150);
                    } else if (std.mem.indexOf(u8, hname, "Hole") != null) {
                        if (world.has_fact(fence_hole, fence_hair_rel, null)) {
                            try world.remember(gabriel, carries_rel, cat_hair_ent.to_int(), 0);
                            _ = world.forget(fence_hole, fence_hair_rel, null);
                            _ = world.forget(fence_hole, taped_rel, null);
                            window.set_cue_banner("★ Step 5: Peeled Cat Hair from the fence tape into inventory! ★", 150);
                        } else if (world.has_fact(fence_hole, taped_rel, null)) {
                            window.set_cue_banner("Masking tape is stretched across the fence hole. Need to squirt the cat!", 120);
                        } else {
                            window.set_cue_banner("Fence hole: Low escape passage through the wooden fence.", 90);
                        }
                    } else if (std.mem.indexOf(u8, hname, "Desk") != null) {
                        window.set_cue_banner("Room Desk: You already have the tape, marker, syrup, and spray bottle in inventory.", 120);
                    } else if (std.mem.indexOf(u8, hname, "Motorcycle") != null) {
                        if (evaluate_puzzle_victory(&world)) {
                            window.set_cue_banner("★ VICTORY! Cruising into the French countryside on Mosely's bike! ★", 180);
                        } else {
                            window.set_cue_banner("Vintage motorcycle: Reserved for detective Mosely. Talk to Madame Buthane!", 120);
                        }
                    }
                }
            },
            .dialogue_choice => |choice_idx| {
                const is_dg = evaluate_disguise(&world);
                if (is_dg and choice_idx == 0) {
                    try world.remember(gabriel, has_keys_rel, 1, 0);
                    window.set_cue_banner("★ VICTORY! Buthane: \"Ah, Monsieur Mosely! Here are the keys!\" ★", 180);
                } else if (!is_dg and choice_idx == 0) {
                    window.set_cue_banner("Buthane: \"Désolé, monsieur! The last motorcycle is reserved for Mosely.\"", 120);
                } else if (choice_idx == 1) {
                    window.set_cue_banner("Buthane: \"It belongs to the village priest. Don't frighten the cat!\"", 120);
                } else {
                    window.set_cue_banner("Buthane: \"Bonne journée, monsieur!\"", 90);
                }
                window.dismiss_dialogue();
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

        // Check helper hotkeys
        const keys = bespoke.display.renderer.c.SDL_GetKeyboardState(null);
        if (keys != null) {
            // [H] Hotel Corridor
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_H] != 0) {
                try vm.transition_to_scene(hotel_scene);
                _ = try spatial.transition_actor(gabriel, hotel_scene, r25_wp);
                window.set_cue_banner("Switched Scene: Hotel Corridor", 60);
            }
            // [G] Courtyard Garden
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_G] != 0) {
                try vm.transition_to_scene(garden_scene);
                _ = try spatial.transition_actor(gabriel, garden_scene, garden_path_wp);
                window.set_cue_banner("Switched Scene: Hotel Courtyard Garden", 60);
            }
            // [B] Bike Rental Shop
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_B] != 0) {
                try vm.transition_to_scene(shop_scene);
                _ = try spatial.transition_actor(gabriel, shop_scene, shop_ent_wp);
                window.set_cue_banner("Switched Scene: Bike Rental Shop", 60);
            }
            // [1] Snatch Passport
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_1] != 0) {
                try world.remember(gabriel, carries_rel, passport_ent.to_int(), 0);
                window.set_cue_banner("Step 1: Acquired Mosely's Passport from Room 33!", 90);
            }
            // [2] Draw Moustache on Passport
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_2] != 0) {
                try world.remember(gabriel, passport_mod_rel, 1, 0);
                window.set_cue_banner("Step 2: Drew moustache on Mosely's passport photo!", 90);
            }
            // [3] Tape Fence Hole
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_3] != 0) {
                try world.remember(fence_hole, taped_rel, 1, 0);
                window.set_cue_banner("Step 3: Stretched masking tape across fence hole!", 90);
            }
            // [4] Squirt Stray Cat
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_4] != 0) {
                try world.remember(stray_cat, startled_rel, 1, 0);
                try world.remember(fence_hole, fence_hair_rel, 1, 0);
                window.set_cue_banner("Step 4: Squirting cat! Fur left stuck to fence tape!", 90);
            }
            // [5] Collect Cat Hair
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_5] != 0) {
                try world.remember(gabriel, carries_rel, cat_hair_ent.to_int(), 0);
                _ = world.forget(fence_hole, fence_hair_rel, null);
                _ = world.forget(fence_hole, taped_rel, null);
                window.set_cue_banner("Step 5: Peeled Cat Hair from tape into inventory!", 90);
            }
            // [6] Craft Cat Moustache with Syrup
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_6] != 0) {
                try world.remember(gabriel, carries_rel, moustache_ent.to_int(), 0);
                try world.remember(gabriel, sticky_lip_rel, 1, 0);
                window.set_cue_banner("Step 6: Applied syrup adhesive and crafted Cat Moustache!", 90);
            }
            // [7] Don Disguise
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_7] != 0) {
                try world.remember(gabriel, disguised_rel, 1, 0);
                window.set_cue_banner("Step 7: Gabriel is now fully DISGUISED as Mosely!", 90);
            }
            // [8] Talk to Buthane
            if (keys[bespoke.display.renderer.c.SDL_SCANCODE_8] != 0) {
                if (evaluate_disguise(&world)) {
                    try world.remember(gabriel, has_keys_rel, 1, 0);
                    window.set_cue_banner("★ Step 8 VICTORY: Buthane gave motorcycle keys to \"Mosely\"! ★", 180);
                } else {
                    window.set_cue_banner("Step 8: Buthane rejected Gabriel! (Need complete disguise!)", 90);
                }
            }
        }

        const now = std.time.milliTimestamp();
        if (!is_paused and (now - last_tick_time >= tick_interval_ms)) {
            should_step_now = true;
            last_tick_time = now;
        }

        if (should_step_now) {
            try vm.step_tick();

            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.set_max_history_tick(world.current_tick);
            display_bridge.swap();

            var snap = std.ArrayList(u8).init(allocator);
            try world.save_state(snap.writer());
            try history_snapshots.append(snap);
        }

        window.render_frame(display_bridge.get_frame(), is_paused);
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P14-01: Gabriel Knight 3 script compiles and lowers to bytecode" {
    const testing = std.testing;

    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, GK3_MOUSTACHE_SCRIPT);
    defer compiled.deinit();

    try testing.expect(world.lookup_entity("Gabriel") != null);
    try testing.expect(world.lookup_entity("Mosely") != null);
    try testing.expect(world.lookup_entity("StrayCat") != null);
    try testing.expect(world.lookup_entity("Buthane") != null);
    try testing.expect(world.lookup_entity("Hotel Corridor") != null);
    try testing.expect(world.lookup_entity("Hotel Garden") != null);
    try testing.expect(world.lookup_entity("Bike Rental Shop") != null);

    try testing.expect(compiled.chunk.count() > 0);
}

test "P14-03: Gabriel Knight 3 headless simulation executes and rewinds cleanly" {
    const testing = std.testing;
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    try run_headless(testing.allocator, list.writer());
    try testing.expect(list.items.len > 0);
}
