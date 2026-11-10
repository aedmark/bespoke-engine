//! The proofs' decks for the browser runtime (P32-04, D-042): each deck's stage, its
//! after-tick rule, and its `[S]` catalyst, moved unchanged from the engine's `src/wasm.zig`.
//! `proofs/wasm_main.zig` exports them as `bespoke-proofs.wasm`; `proofs/wasm_golden_test.zig`
//! drives them natively.
const std = @import("std");
const bespoke = @import("bespoke");
const wasm = bespoke.wasm;
const WasmRuntime = wasm.WasmRuntime;

pub const decks = [_]wasm.Deck{
    .{ .title = "TAVERN HEIST (GUARD, BARD & CAT)", .background = .{ .r = 28, .g = 21, .b = 18 }, .load = load_tavern_heist, .catalyst = catalyst_tavern_heist },
    .{ .title = "BOOTY ISLAND SPITTING CONTEST", .background = .{ .r = 16, .g = 42, .b = 58 }, .load = load_spitting_contest, .catalyst = catalyst_spitting_contest },
    .{ .title = "GK3: CAT MOUSTACHE PUZZLE", .background = .{ .r = 32, .g = 52, .b = 34 }, .load = load_gk3_moustache, .catalyst = catalyst_gk3_moustache },
    .{ .title = "THE LIVING VILLAGE (EMERGENCE)", .background = .{ .r = 22, .g = 44, .b = 28 }, .load = load_living_village, .catalyst = catalyst_living_village, .after_tick = village_after_tick },
    .{ .title = "BROKEN SWORD: LOCHMARNE GOAT", .background = .{ .r = 38, .g = 48, .b = 40 }, .load = load_goat_puzzle, .catalyst = catalyst_goat_puzzle },
    .{ .title = "DAY OF THE TENTACLE TRIO", .background = .{ .r = 42, .g = 24, .b = 48 }, .load = load_dott_puzzle, .catalyst = catalyst_dott_puzzle },
    .{ .title = "CAUSTIC GROG (CONTAINER DEGRADATION)", .background = .{ .r = 20, .g = 42, .b = 40 }, .load = load_grog_puzzle, .catalyst = catalyst_grog_puzzle, .after_tick = grog_after_tick },
};

fn load_tavern_heist(rt: *WasmRuntime) anyerror!void {
    const room = try rt.world.intern_entity("Tavern");
    const cat = try rt.world.intern_entity("Cat");
    const guard = try rt.world.intern_entity("Guard");
    const bard = try rt.world.intern_entity("Bard");
    const cheese = try rt.world.intern_entity("Cheese");
    const carries = try rt.world.intern_relation("Carries", .set);

    const hearth_wp = try rt.spatial.graph.add_waypoint(room, 0, 0, "Hearth");
    const bar_wp = try rt.spatial.graph.add_waypoint(room, 20, 0, "Bar");
    const cellar_wp = try rt.spatial.graph.add_waypoint(room, 40, 0, "Cellar");
    try rt.spatial.graph.connect(hearth_wp, bar_wp, null);
    try rt.spatial.graph.connect(bar_wp, cellar_wp, null);

    const fire_ent = try rt.world.intern_entity("Fireplace");
    const cask_ent = try rt.world.intern_entity("WineCask");
    try rt.spatial.add_hotspot(fire_ent, room, .{ .x = 0, .y = -8 }, 6, "Fireplace", "Warm stone tavern hearth.");
    try rt.spatial.add_hotspot(cask_ent, room, .{ .x = 40, .y = -8 }, 6, "WineCask", "Oak wine cask in the cellar.");

    try rt.spatial.register_entity(cat, hearth_wp, 10);
    try rt.spatial.register_entity(guard, bar_wp, 8);
    try rt.spatial.register_entity(bard, hearth_wp, 8);
    try rt.world.remember(guard, carries, cheese.to_int(), 0);
    rt.player_entity = cat;
    rt.set_banner("Tavern Heist: Click waypoints to move Cat or press [S] to charm Guard!");
}

fn load_spitting_contest(rt: *WasmRuntime) anyerror!void {
    const room = try rt.world.intern_entity("Booty Island");
    const guybrush = try rt.world.intern_entity("Guybrush");
    const organiser = try rt.world.intern_entity("Organiser");
    const onlookers = try rt.world.intern_entity("Onlookers");
    const thick_rel = try rt.world.intern_relation("thick", .property);
    const wind_rel = try rt.world.intern_relation("blowing", .property);

    const start_wp = try rt.spatial.graph.add_waypoint(room, 4, 2, "Starting Line");
    const track_wp = try rt.spatial.graph.add_waypoint(room, 22, 2, "Flag Marker");
    const dock_wp = try rt.spatial.graph.add_waypoint(room, 38, 2, "Lookout Dock");
    try rt.spatial.graph.connect(start_wp, track_wp, null);
    try rt.spatial.graph.connect(track_wp, dock_wp, null);

    const flags_ent = try rt.world.intern_entity("DistanceFlags");
    try rt.spatial.add_hotspot(flags_ent, room, .{ .x = 22, .y = -6 }, 6, "DistanceFlags", "Contest distance flags on the lawn.");

    try rt.spatial.register_entity(guybrush, start_wp, 10);
    try rt.spatial.register_entity(organiser, start_wp, 8);
    try rt.spatial.register_entity(onlookers, track_wp, 8);
    try rt.world.remember(guybrush, thick_rel, 0, 0);
    try rt.world.remember(room, wind_rel, 1, 0);
    rt.player_entity = guybrush;
    rt.set_banner("Spitting Contest: Press [G] GreenDrink, [F] Move Flags, [S] Spit!");
}

fn load_gk3_moustache(rt: *WasmRuntime) anyerror!void {
    const room = try rt.world.intern_entity("Hotel Garden");
    const gabriel = try rt.world.intern_entity("Gabriel");
    const mosely = try rt.world.intern_entity("Mosely");
    const stray_cat = try rt.world.intern_entity("StrayCat");
    const buthane = try rt.world.intern_entity("Buthane");

    const corr_wp = try rt.spatial.graph.add_waypoint(room, 0, 2, "HotelCorridor");
    const fence_wp = try rt.spatial.graph.add_waypoint(room, 20, 2, "FenceGap");
    const shop_wp = try rt.spatial.graph.add_waypoint(room, 38, 2, "BikeShop");
    try rt.spatial.graph.connect(corr_wp, fence_wp, null);
    try rt.spatial.graph.connect(fence_wp, shop_wp, null);

    const hole_ent = try rt.world.intern_entity("FenceHole");
    try rt.spatial.add_hotspot(hole_ent, room, .{ .x = 20, .y = -7 }, 6, "FenceHole", "Broken picket fence gap.");

    try rt.spatial.register_entity(gabriel, corr_wp, 10);
    try rt.spatial.register_entity(mosely, corr_wp, 8);
    try rt.spatial.register_entity(stray_cat, fence_wp, 12);
    try rt.spatial.register_entity(buthane, shop_wp, 8);
    rt.player_entity = gabriel;
    rt.set_banner("GK3 Cat Moustache: Click FenceHole or press [S] to craft disguise!");
}

fn load_living_village(rt: *WasmRuntime) anyerror!void {
    const room = try rt.world.intern_entity("Living Village");
    const sheriff = try rt.world.intern_entity("Sheriff");
    const baker = try rt.world.intern_entity("Baker");
    const farmer = try rt.world.intern_entity("Farmer");
    const gossip = try rt.world.intern_entity("Gossip");
    const drifter = try rt.world.intern_entity("Drifter");

    const hunger_rel = try rt.world.intern_relation("Hunger", .property);
    const gold_rel = try rt.world.intern_relation("Gold", .property);
    const friend_rel = try rt.world.intern_relation("Friend", .set);

    const bakery_wp = try rt.spatial.graph.add_waypoint(room, 2, -8, "Bakery");
    const farm_wp = try rt.spatial.graph.add_waypoint(room, 2, 6, "Farm");
    const sq_wp = try rt.spatial.graph.add_waypoint(room, 20, -1, "TownSquare");
    const jail_wp = try rt.spatial.graph.add_waypoint(room, 38, 6, "SheriffsPost");
    try rt.spatial.graph.connect(bakery_wp, sq_wp, null);
    try rt.spatial.graph.connect(farm_wp, sq_wp, null);
    try rt.spatial.graph.connect(sq_wp, jail_wp, null);

    const oven_ent = try rt.world.intern_entity("BakeryOven");
    try rt.spatial.add_hotspot(oven_ent, room, .{ .x = 2, .y = -12 }, 6, "BakeryOven", "Warm sourdough brick oven.");

    try rt.spatial.register_entity(sheriff, jail_wp, 12);
    try rt.spatial.register_entity(baker, bakery_wp, 10);
    try rt.spatial.register_entity(farmer, farm_wp, 10);
    try rt.spatial.register_entity(gossip, sq_wp, 12);
    try rt.spatial.register_entity(drifter, sq_wp, 11);

    try rt.world.remember(sheriff, hunger_rel, 20, 0);
    try rt.world.remember(baker, hunger_rel, 25, 0);
    try rt.world.remember(farmer, hunger_rel, 45, 0);
    try rt.world.remember(drifter, hunger_rel, 70, 0);
    try rt.world.remember(drifter, gold_rel, 0, 0);
    try rt.world.remember(baker, friend_rel, gossip.to_int(), 0);
    try rt.world.remember(gossip, friend_rel, sheriff.to_int(), 0);

    rt.player_entity = sheriff;
    rt.set_banner("Living Village: Watch autonomous drives or press [S] for Theft Catalyst!");
}

fn load_goat_puzzle(rt: *WasmRuntime) anyerror!void {
    const room = try rt.world.intern_entity("Lochmarne Courtyard");
    const george = try rt.world.intern_entity("George");
    const goat = try rt.world.intern_entity("BillyGoat");
    const stake = try rt.world.intern_entity("TetherStake");

    const tether_rel = try rt.world.intern_relation("TetheredTo", .set);

    const ent_wp = try rt.spatial.graph.add_waypoint(room, 4, 2, "Entrance");
    const plough_wp = try rt.spatial.graph.add_waypoint(room, 16, 8, "Plough");
    const tether_wp = try rt.spatial.graph.add_waypoint(room, 24, 2, "Tether");
    const dig_wp = try rt.spatial.graph.add_waypoint(room, 38, 2, "CellarDig");
    try rt.spatial.graph.connect(ent_wp, plough_wp, null);
    try rt.spatial.graph.connect(plough_wp, tether_wp, null);
    try rt.spatial.graph.connect(tether_wp, dig_wp, null);

    const cellar_ent = try rt.world.intern_entity("CellarEntrance");
    const plough_ent = try rt.world.intern_entity("FarmPlough");
    try rt.spatial.add_hotspot(cellar_ent, room, .{ .x = 38, .y = -6 }, 6, "CellarEntrance", "Peagram's Templar excavation dig.");
    try rt.spatial.add_hotspot(plough_ent, room, .{ .x = 16, .y = 6 }, 6, "FarmPlough", "Old heavy iron farm plough.");

    try rt.spatial.register_entity(george, ent_wp, 10);
    try rt.spatial.register_entity(goat, tether_wp, 8);
    try rt.world.remember(goat, tether_rel, stake.to_int(), 0);

    rt.player_entity = george;
    rt.set_banner("Lochmarne Goat: [1] Approach Dig [2] Drag Plough [3] Descend to Crypt!");
}

fn load_dott_puzzle(rt: *WasmRuntime) anyerror!void {
    const room = try rt.world.intern_entity("Motel Lobby");
    const bernard = try rt.world.intern_entity("Bernard");
    const hoagie = try rt.world.intern_entity("Hoagie");
    const laverne = try rt.world.intern_entity("Laverne");

    const desk_wp = try rt.spatial.graph.add_waypoint(room, 6, 2, "LobbyDesk");
    const toilet_wp = try rt.spatial.graph.add_waypoint(room, 20, 2, "ToiletMark1993");
    const guard_wp = try rt.spatial.graph.add_waypoint(room, 36, 2, "GuardPost");
    try rt.spatial.graph.connect(desk_wp, toilet_wp, null);
    try rt.spatial.graph.connect(toilet_wp, guard_wp, null);

    const wine_ent = try rt.world.intern_entity("VintageWine");
    const flyer_ent = try rt.world.intern_entity("TentacleFlyer");
    const carries_rel = try rt.world.intern_relation("Carries", .set);

    try rt.spatial.register_entity(bernard, desk_wp, 8);
    try rt.spatial.register_entity(hoagie, toilet_wp, 8);
    try rt.spatial.register_entity(laverne, guard_wp, 8);

    _ = try rt.world.remember(bernard, carries_rel, wine_ent.to_int(), 0);
    _ = try rt.world.remember(bernard, carries_rel, flyer_ent.to_int(), 0);

    rt.player_entity = bernard;
    rt.set_banner("DOTT Trio: [S] Flush Wine & Flyer to Hoagie, Craft Battery, Sew Flag!");
}

fn catalyst_tavern_heist(rt: *WasmRuntime) anyerror!void {
    const guard = try rt.world.intern_entity("Guard");
    const bard = try rt.world.intern_entity("Bard");
    const cat = try rt.world.intern_entity("Cat");
    const cheese = try rt.world.intern_entity("Cheese");
    const charmed = try rt.world.intern_relation("CharmedBy", .set);
    const carries = try rt.world.intern_relation("Carries", .set);

    try rt.world.remember(guard, charmed, bard.to_int(), rt.world.current_tick + 10);
    _ = rt.world.forget(guard, carries, cheese.to_int());
    try rt.world.remember(cat, carries, cheese.to_int(), 0);
    rt.set_banner("Bard charmed Guard! Cat snatched the Cheese!");
}

fn catalyst_spitting_contest(rt: *WasmRuntime) anyerror!void {
    const guybrush = try rt.world.intern_entity("Guybrush");
    const champion = try rt.world.intern_relation("SpitChampion", .property);
    try rt.world.remember(guybrush, champion, 1, 0);
    rt.set_banner("Guybrush spits across the tailwind! 1st Place Champion!");
}

fn catalyst_gk3_moustache(rt: *WasmRuntime) anyerror!void {
    const gabriel = try rt.world.intern_entity("Gabriel");
    const disguised = try rt.world.intern_relation("Disguised", .property);
    const keys = try rt.world.intern_relation("HasBikeKeys", .property);
    try rt.world.remember(gabriel, disguised, 1, 0);
    try rt.world.remember(gabriel, keys, 1, 0);
    rt.set_banner("Gabriel crafts the cat-hair moustache and rents Mosely's bike!");
}

fn catalyst_living_village(rt: *WasmRuntime) anyerror!void {
    const drifter = try rt.world.intern_entity("Drifter");
    const hunger_rel = try rt.world.intern_relation("Hunger", .property);
    const arrested_rel = try rt.world.intern_relation("Arrested", .set);
    const stolen_rel = try rt.world.intern_relation("StolenFrom", .set);
    _ = rt.world.forget(drifter, arrested_rel, null);
    _ = rt.world.forget(drifter, stolen_rel, null);
    try rt.world.remember(drifter, hunger_rel, 85, 0);
    try rt.step_tick();
}

fn catalyst_goat_puzzle(rt: *WasmRuntime) anyerror!void {
    const goat = try rt.world.intern_entity("BillyGoat");
    const plough = try rt.world.intern_entity("FarmPlough");
    const tangled_rel = try rt.world.intern_relation("TangledWith", .property);
    const moved_rel = try rt.world.intern_relation("PloughMoved", .property);
    try rt.world.remember(goat, tangled_rel, plough.to_int(), 0);
    try rt.world.remember(plough, moved_rel, 1, 0);
    rt.set_banner("Hauled plough into rope line! Billy Goat is tangled and secured!");
}

fn catalyst_dott_puzzle(rt: *WasmRuntime) anyerror!void {
    const hoagie = try rt.world.intern_entity("Hoagie");
    const laverne = try rt.world.intern_entity("Laverne");
    const bat_rel = try rt.world.intern_relation("ToiletPowered", .property);
    const flag_rel = try rt.world.intern_relation("TentacleFlagSewn", .property);
    const chop_rel = try rt.world.intern_relation("TreeChoppedDown", .property);
    const free_rel = try rt.world.intern_relation("FreedFromTree", .property);
    const disg_rel = try rt.world.intern_relation("TentacleDisguiseActive", .property);

    try rt.world.remember(hoagie, bat_rel, 1, 0);
    try rt.world.remember(hoagie, flag_rel, 1, 0);
    try rt.world.remember(hoagie, chop_rel, 1, 0);
    try rt.world.remember(laverne, free_rel, 1, 0);
    try rt.world.remember(laverne, disg_rel, 1, 0);
    rt.set_banner("DOTT Trio Solved! Super Battery crafted, Tentacle Flag sewn, Laverne freed!");
}

/// The browser stage's stage ladder and exposure lengths. The desktop proof uses its script's
/// 4/3/2 ticks and 10 measures; the browser's four-tick walk legs need a little more room, so
/// this deck keeps the same rule with its own tuning.
const GROG_STAGE_NAMES = [_][]const u8{ "GrogSound", "Pitted", "Buckling", "GrogFailed" };
const GROG_STAGE_TICKS = [_]u64{ 6, 4, 3 };

fn grog_stage_index(name: []const u8) ?usize {
    for (GROG_STAGE_NAMES, 0..) |stage, i| {
        if (std.mem.eql(u8, stage, name)) return i;
    }
    return null;
}

fn load_grog_puzzle(rt: *WasmRuntime) anyerror!void {
    const room = try rt.world.intern_entity("Saltglass Stockade");
    const mara = try rt.world.intern_entity("Mara");
    const ivo = try rt.world.intern_entity("Ivo");
    const barrel = try rt.world.intern_entity("GrogBarrel");
    const cup_a = try rt.world.intern_entity("CupA");
    const cup_b = try rt.world.intern_entity("CupB");
    const cup_c = try rt.world.intern_entity("CupC");
    const lock = try rt.world.intern_entity("CellLock");
    const grog = try rt.world.intern_entity("CausticGrog");
    const sound = try rt.world.intern_entity("GrogSound");
    for (GROG_STAGE_NAMES) |stage_name| _ = try rt.world.intern_entity(stage_name);

    const contains = try rt.world.intern_relation("Contains", .set);
    const volume = try rt.world.intern_relation("Volume", .property);
    const stage = try rt.world.intern_relation("ContainerStage", .property);
    const exposure = try rt.world.intern_relation("ContainerExposure", .property);
    const carries = try rt.world.intern_relation("Carries", .set);
    const imprisoned = try rt.world.intern_relation("imprisoned", .property);

    const barrel_wp = try rt.spatial.graph.add_waypoint(room, 0, 4, "BarrelMark");
    const gallery_one_wp = try rt.spatial.graph.add_waypoint(room, 14, 4, "GalleryOne");
    const gallery_two_wp = try rt.spatial.graph.add_waypoint(room, 28, 4, "GalleryTwo");
    const lock_wp = try rt.spatial.graph.add_waypoint(room, 40, 4, "LockMark");
    try rt.spatial.graph.connect(barrel_wp, gallery_one_wp, null);
    try rt.spatial.graph.connect(gallery_one_wp, gallery_two_wp, null);
    try rt.spatial.graph.connect(gallery_two_wp, lock_wp, null);

    try rt.spatial.add_hotspot(barrel, room, .{ .x = 0, .y = -4 }, 7, "Grog Barrel", "A tarred barrel breathing sharp green fumes.");
    try rt.spatial.add_hotspot(lock, room, .{ .x = 40, .y = -3 }, 7, "Cell Lock", "A thick iron lock between Ivo and the docks.");

    try rt.spatial.register_entity(mara, barrel_wp, 10);
    try rt.spatial.register_entity(ivo, lock_wp, 1);
    try rt.world.remember(mara, carries, cup_a.to_int(), 0);
    try rt.world.remember(mara, carries, cup_b.to_int(), 0);
    try rt.world.remember(mara, carries, cup_c.to_int(), 0);
    for ([_]bespoke.EntityId{ cup_a, cup_b, cup_c }) |cup| {
        try rt.world.remember(cup, stage, sound.to_int(), 0);
        try rt.world.remember(cup, volume, 0, 0);
    }
    try rt.world.remember(cup_a, volume, 16, 0);
    try rt.world.remember(cup_a, contains, grog.to_int(), 0);
    try rt.world.remember(cup_a, exposure, sound.to_int(), GROG_STAGE_TICKS[0]);
    try rt.world.remember(ivo, imprisoned, 0, 0);

    rt.player_entity = mara;
    rt.set_banner("Caustic Grog: [S] pours A to B, then B to C; reach LockMark with four measures!");
}

/// The deck's own container lifecycle: spill while the holder moves, then advance an expired
/// stage. The desktop proof runs the engine's ContainerSystem; this keeps the browser stage
/// playable without compiling a script into the wasm module.
fn grog_after_tick(rt: *WasmRuntime) anyerror!void {
    const mara = rt.world.lookup_entity("Mara") orelse return;
    const grog = rt.world.lookup_entity("CausticGrog") orelse return;
    const contains = rt.world.lookup_relation("Contains") orelse return;
    const volume = rt.world.lookup_relation("Volume") orelse return;
    const stage_rel = rt.world.lookup_relation("ContainerStage") orelse return;
    const exposure = rt.world.lookup_relation("ContainerExposure") orelse return;
    const failed_rel = try rt.world.intern_relation("ContainerFailedAt", .property);
    const moving = rt.spatial.is_moving(mara);

    for ([_][]const u8{ "CupA", "CupB", "CupC" }) |cup_name| {
        const cup = rt.world.lookup_entity(cup_name) orelse continue;
        if (!rt.world.has_fact(cup, contains, grog.to_int())) continue;

        if (moving) {
            const before = rt.world.get_property(cup, volume) orelse continue;
            const after = before -| 1;
            try rt.world.remember(cup, volume, after, 0);
            if (after == 0) {
                _ = rt.world.forget(cup, contains, grog.to_int());
                _ = rt.world.forget(cup, exposure, null);
                var msg: [80]u8 = undefined;
                rt.set_banner(std.fmt.bufPrint(&msg, "{s} runs dry in transit.", .{cup_name}) catch "A cup runs dry.");
                continue;
            }
        }

        const stage_value = rt.world.get_property(cup, stage_rel) orelse continue;
        if (rt.world.has_fact(cup, exposure, stage_value)) continue;
        const stage_name = rt.world.get_entity_name(bespoke.EntityId.from_int(stage_value)) orelse continue;
        const current = grog_stage_index(stage_name) orelse continue;
        if (current + 1 >= GROG_STAGE_NAMES.len) continue;
        const next = rt.world.lookup_entity(GROG_STAGE_NAMES[current + 1]) orelse continue;
        try rt.world.remember(cup, stage_rel, next.to_int(), 0);

        var msg: [96]u8 = undefined;
        if (current + 1 == GROG_STAGE_NAMES.len - 1) {
            _ = rt.world.forget(cup, contains, grog.to_int());
            try rt.world.remember(cup, volume, 0, 0);
            if (rt.spatial.get_current_waypoint(mara)) |waypoint| {
                try rt.world.remember(cup, failed_rel, waypoint, 0);
            }
            rt.set_banner(std.fmt.bufPrint(&msg, "{s} fails in Mara's hands.", .{cup_name}) catch "A cup fails.");
        } else {
            try rt.world.remember(cup, exposure, next.to_int(), GROG_STAGE_TICKS[current + 1]);
            rt.set_banner(std.fmt.bufPrint(&msg, "{s} reaches {s}.", .{ cup_name, GROG_STAGE_NAMES[current + 1] }) catch "A cup degrades.");
        }
    }
}

fn grog_has_contents(rt: *WasmRuntime, cup: bespoke.EntityId) bool {
    const grog = rt.world.lookup_entity("CausticGrog") orelse return false;
    const contains = rt.world.lookup_relation("Contains") orelse return false;
    return rt.world.has_fact(cup, contains, grog.to_int());
}

fn grog_has_volume(rt: *WasmRuntime, cup: bespoke.EntityId) bool {
    if (!grog_has_contents(rt, cup)) return false;
    const volume = rt.world.lookup_relation("Volume") orelse return false;
    return (rt.world.get_property(cup, volume) orelse 0) > 0;
}

fn grog_at_lock(rt: *WasmRuntime) bool {
    const mara = rt.world.lookup_entity("Mara") orelse return false;
    const waypoint = rt.spatial.get_current_waypoint(mara) orelse return false;
    const mark = rt.spatial.graph.get_waypoint(waypoint) orelse return false;
    return std.mem.eql(u8, mark.name, "LockMark");
}

fn grog_pour(rt: *WasmRuntime, source: bespoke.EntityId, target: bespoke.EntityId, target_name: []const u8) anyerror!bool {
    const grog = rt.world.lookup_entity("CausticGrog") orelse return false;
    const contains = rt.world.lookup_relation("Contains") orelse return false;
    const volume = rt.world.lookup_relation("Volume") orelse return false;
    const stage_rel = rt.world.lookup_relation("ContainerStage") orelse return false;
    const exposure = rt.world.lookup_relation("ContainerExposure") orelse return false;

    const target_stage_value = rt.world.get_property(target, stage_rel) orelse return false;
    const target_stage_name = rt.world.get_entity_name(bespoke.EntityId.from_int(target_stage_value)) orelse return false;
    const target_stage = grog_stage_index(target_stage_name) orelse return false;
    if (target_stage >= GROG_STAGE_NAMES.len - 1) {
        rt.set_banner("That cup is already ruined.");
        return false;
    }

    const amount = rt.world.get_property(source, volume) orelse return false;
    try rt.world.remember(target, contains, grog.to_int(), 0);
    try rt.world.remember(target, volume, amount, 0);
    try rt.world.remember(source, volume, 0, 0);
    _ = rt.world.forget(source, contains, grog.to_int());
    _ = rt.world.forget(source, exposure, null);
    try rt.world.remember(target, exposure, target_stage_value, GROG_STAGE_TICKS[target_stage]);

    var msg: [96]u8 = undefined;
    rt.set_banner(std.fmt.bufPrint(&msg, "Poured {d} measures into {s}; its damage stays.", .{ amount, target_name }) catch "Poured without loss.");
    return true;
}

fn catalyst_grog_puzzle(rt: *WasmRuntime) anyerror!void {
    const ivo = rt.world.lookup_entity("Ivo") orelse return;
    const lock = rt.world.lookup_entity("CellLock") orelse return;
    const cup_a = rt.world.lookup_entity("CupA") orelse return;
    const cup_b = rt.world.lookup_entity("CupB") orelse return;
    const cup_c = rt.world.lookup_entity("CupC") orelse return;
    const volume = rt.world.lookup_relation("Volume") orelse return;
    const cup_c_volume = if (grog_has_contents(rt, cup_c)) (rt.world.get_property(cup_c, volume) orelse 0) else 0;
    const at_lock = grog_at_lock(rt);

    if (cup_c_volume >= 4 and at_lock) {
        const dissolved = try rt.world.intern_relation("dissolved", .property);
        const imprisoned = try rt.world.intern_relation("imprisoned", .property);
        try rt.world.remember(lock, dissolved, 0, 0);
        _ = rt.world.forget(ivo, imprisoned, null);
        rt.set_banner("The grog bites through the lock. Ivo is free!");
        return;
    }
    if (cup_c_volume >= 4) {
        rt.set_banner("Cup C holds four measures; Mara must stand at LockMark.");
        return;
    }

    if (grog_has_volume(rt, cup_a) and !grog_has_contents(rt, cup_b)) {
        _ = try grog_pour(rt, cup_a, cup_b, "Cup B");
        return;
    }
    if (grog_has_volume(rt, cup_b) and !grog_has_contents(rt, cup_c)) {
        _ = try grog_pour(rt, cup_b, cup_c, "Cup C");
        return;
    }
    if (at_lock) {
        rt.set_banner("Cup C is dry; rewind with [R] and pour sooner.");
    } else {
        rt.set_banner("The cups are dry; rewind with [R] and pour sooner.");
    }
}

fn grog_walk_to_mark(rt: *WasmRuntime, entity: bespoke.EntityId, mark: []const u8) !void {
    const room = rt.world.lookup_entity("Saltglass Stockade") orelse return error.UnknownRoom;
    const waypoint = rt.spatial.graph.find_waypoint_in_room(room, mark) orelse return error.UnknownMark;
    try std.testing.expect(try rt.spatial.walk_to(entity, waypoint));
    var guard: usize = 0;
    while (rt.spatial.is_moving(entity) and guard < 20) : (guard += 1) _ = try rt.step_tick();
    try std.testing.expect(!rt.spatial.is_moving(entity));
}

test "P23-03: the browser grog deck pours and dissolves the lock" {
    var rt = try wasm.WasmRuntime.init(std.testing.allocator, &decks, 6);
    defer rt.deinit();
    const mara = rt.world.lookup_entity("Mara").?;
    const lock = rt.world.lookup_entity("CellLock").?;

    // The intended sprint: pour at each gallery before the carried cup gives out.
    try grog_walk_to_mark(&rt, mara, "GalleryOne");
    try rt.trigger_catalyst();
    try grog_walk_to_mark(&rt, mara, "GalleryTwo");
    try rt.trigger_catalyst();
    try grog_walk_to_mark(&rt, mara, "LockMark");
    try rt.trigger_catalyst();

    const dissolved = rt.world.lookup_relation("dissolved").?;
    try std.testing.expect(rt.world.has_fact(lock, dissolved, 0));
}

/// The village deck's own hunger, theft, rumor, and arrest rule, run after every tick.
fn village_after_tick(rt: *WasmRuntime) anyerror!void {
    if (rt.world.lookup_entity("Drifter")) |drifter| {
        const hunger_rel = try rt.world.intern_relation("Hunger", .property);
        const stolen_rel = try rt.world.intern_relation("StolenFrom", .set);
        const rumor_rel = try rt.world.intern_relation("KnowsRumor", .set);
        const arrested_rel = try rt.world.intern_relation("Arrested", .set);
        const baker = rt.world.lookup_entity("Baker") orelse .none;
        const sheriff = rt.world.lookup_entity("Sheriff") orelse .none;

        if (!rt.world.has_fact(drifter, arrested_rel, null)) {
            const h = @min(100, (rt.world.get_property(drifter, hunger_rel) orelse 50) + 5);
            try rt.world.remember(drifter, hunger_rel, h, 0);

            if (h >= 80 and !rt.world.has_fact(drifter, stolen_rel, null)) {
                try rt.world.remember(drifter, stolen_rel, baker.to_int(), 0);
                try rt.world.remember(baker, rumor_rel, drifter.to_int(), 0);
                rt.set_banner("[CRIME] Starving Drifter stole BreadLoaf from Baker!");
            } else if (rt.world.has_fact(baker, rumor_rel, drifter.to_int()) and
                !rt.world.has_fact(sheriff, rumor_rel, drifter.to_int()))
            {
                try rt.world.remember(sheriff, rumor_rel, drifter.to_int(), 0);
                rt.set_banner("[RUMOR] Baker & Gossip spread theft rumor to Sheriff!");
            } else if (rt.world.has_fact(sheriff, rumor_rel, drifter.to_int())) {
                try rt.world.remember(drifter, arrested_rel, sheriff.to_int(), 0);
                rt.set_banner("[ARREST] Sheriff apprehended Drifter and restored order!");
            }
        }
    }
}
