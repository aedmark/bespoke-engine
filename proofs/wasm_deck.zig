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
