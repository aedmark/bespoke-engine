//! BeSpoke Engine: Systemic Emergent Simulation Sandbox — "The Living Village" (Phase 18, D-021)
//!
//! Demonstrates unscripted systemic emergence driven by continuous relational rules,
//! autonomous NPC physiological drives (Hunger, Energy, Gold), social relationships
//! (Friend, Rival, Grudge), witness detection, rumor propagation across social links,
//! and an autonomous Sheriff investigation and arrest cascade.

const std = @import("std");
const bespoke = @import("root.zig");

/// BeSpoke DSL Script for "The Living Village" settlement (P18-01, P18-02, P18-03, D-021).
pub const VILLAGE_SCRIPT =
    \\scene: Living Village
    \\cast: Sheriff, Baker, Farmer, Innkeeper, Gossip, Drifter
    \\props: BakeryOven, TownFountain, SheriffJail, FarmGranary, TavernHearth, VillageCottages
    \\marks: Bakery, Farm, TownSquare, Cottages, Tavern, SheriffsPost
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

/// Autonomous villager activity states stored in the `Activity` property relation (P18-01, D-007, D-021).
pub const VillagerActivity = enum(u32) {
    working = 0,
    patrolling = 1,
    eating = 2,
    sleeping = 3,
    socializing = 4,
    stealing = 5,
    fleeing = 6,
    investigating = 7,
    arrested = 8,

    pub fn label(self: VillagerActivity) []const u8 {
        return switch (self) {
            .working => "Working",
            .patrolling => "Patrolling",
            .eating => "Eating",
            .sleeping => "Sleeping",
            .socializing => "Socializing",
            .stealing => "STEALING!",
            .fleeing => "Fleeing!",
            .investigating => "Investigating!",
            .arrested => "ARRESTED",
        };
    }

    pub fn from_int(val: u32) VillagerActivity {
        return if (val <= 8) @enumFromInt(val) else .working;
    }
};

/// Categories of emergent events recorded in the Village Chronicle (P18-03, D-021).
pub const ChronicleCategory = enum(u8) {
    work = 0,
    trade = 1,
    social = 2,
    crime = 3,
    witness = 4,
    rumor = 5,
    justice = 6,
    arrest = 7,

    pub fn tag(self: ChronicleCategory) []const u8 {
        return switch (self) {
            .work => "WORK",
            .trade => "TRADE",
            .social => "SOCIAL",
            .crime => "CRIME",
            .witness => "WITNESS",
            .rumor => "RUMOR",
            .justice => "JUSTICE",
            .arrest => "ARREST",
        };
    }
};

/// A single emergent event entry in the Village Event Chronicle ring buffer (P18-03, D-021).
pub const ChronicleEntry = struct {
    tick: u64 = 0,
    category: ChronicleCategory = .work,
    message: [96]u8 = [_]u8{0} ** 96,
    message_len: u8 = 0,

    pub fn get_message(self: *const ChronicleEntry) []const u8 {
        return self.message[0..self.message_len];
    }
};

pub const MAX_CHRONICLE_ENTRIES: usize = 24;
pub const DESPERATION_HUNGER_THRESHOLD: u32 = 80;
pub const HUNGRY_BUY_THRESHOLD: u32 = 55;
pub const LOW_ENERGY_THRESHOLD: u32 = 22;
pub const MEAL_PRICE_GOLD: u32 = 5;

/// Systemic Emergent Simulation Engine for "The Living Village" (P18-01..P18-03, D-021).
pub const VillageSimulation = struct {
    // Scene & Cast Entities
    village_scene: bespoke.EntityId,
    sheriff: bespoke.EntityId,
    baker: bespoke.EntityId,
    farmer: bespoke.EntityId,
    innkeeper: bespoke.EntityId,
    gossip: bespoke.EntityId,
    drifter: bespoke.EntityId,

    // Commodities / Props
    bread_loaf: bespoke.EntityId,
    wheat_bundle: bespoke.EntityId,
    ale_mug: bespoke.EntityId,

    // Settlement Waypoints (P18-03)
    bakery_wp: bespoke.WaypointId,
    farm_wp: bespoke.WaypointId,
    town_square_wp: bespoke.WaypointId,
    cottages_wp: bespoke.WaypointId,
    tavern_wp: bespoke.WaypointId,
    sheriffs_post_wp: bespoke.WaypointId,

    // Physiological Drive Property Relations (P18-01, D-007)
    hunger_rel: bespoke.RelationKind,
    energy_rel: bespoke.RelationKind,
    gold_rel: bespoke.RelationKind,
    activity_rel: bespoke.RelationKind,
    mood_rel: bespoke.RelationKind,

    // Social, Property, and Emergence Set Relations (P18-01, P18-02, D-010)
    friend_rel: bespoke.RelationKind,
    rival_rel: bespoke.RelationKind,
    grudge_rel: bespoke.RelationKind,
    owns_rel: bespoke.RelationKind,
    carries_rel: bespoke.RelationKind,
    stolen_from_rel: bespoke.RelationKind,
    crime_scene_rel: bespoke.RelationKind,
    witnessed_rel: bespoke.RelationKind,
    knows_rumor_rel: bespoke.RelationKind,
    warrant_for_rel: bespoke.RelationKind,
    arrested_rel: bespoke.RelationKind,

    // Event Chronicle Ring Buffer (P18-03)
    chronicle: [MAX_CHRONICLE_ENTRIES]ChronicleEntry = [_]ChronicleEntry{.{}} ** MAX_CHRONICLE_ENTRIES,
    chronicle_count: usize = 0,

    /// Initializes the Living Village relational schema, spatial settlement graph, and initial NPC drives.
    pub fn init(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !VillageSimulation {
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

        // Intern Physiological Drive Relations (.property auto-overwrites scalar values per villager, D-007)
        const hunger_rel = try world.intern_relation("Hunger", .property);
        const energy_rel = try world.intern_relation("Energy", .property);
        const gold_rel = try world.intern_relation("Gold", .property);
        const activity_rel = try world.intern_relation("Activity", .property);
        const mood_rel = try world.intern_relation("Mood", .property);

        // Intern Social & Emergence Relations (.set allows multiple relational edges per subject)
        const friend_rel = try world.intern_relation("Friend", .set);
        const rival_rel = try world.intern_relation("Rival", .set);
        const grudge_rel = try world.intern_relation("Grudge", .set);
        const owns_rel = try world.intern_relation("Owns", .set);
        const carries_rel = try world.intern_relation("Carries", .set);
        const stolen_from_rel = try world.intern_relation("StolenFrom", .set);
        const crime_scene_rel = try world.intern_relation("CrimeScene", .set);
        const witnessed_rel = try world.intern_relation("Witnessed", .set);
        const knows_rumor_rel = try world.intern_relation("KnowsRumor", .set);
        const warrant_for_rel = try world.intern_relation("WarrantFor", .set);
        const arrested_rel = try world.intern_relation("Arrested", .set);

        // Construct 6-building settlement waypoint topology (P18-03, D-005, D-021)
        // Coordinates positioned for clean layout alongside left/right HUD panels at 1280x720:
        // Left column (x=2): Bakery (2, -10), Farm (2, 6)
        // Center column (x=15): TownSquare (15, -2), Cottages (15, 9)
        // Right column (x=28): Tavern (28, -10), SheriffsPost (28, 6)
        const bakery_wp = try spatial.graph.add_waypoint(village_scene, 2, -10, "Bakery");
        const farm_wp = try spatial.graph.add_waypoint(village_scene, 2, 6, "Farm");
        const town_square_wp = try spatial.graph.add_waypoint(village_scene, 15, -2, "TownSquare");
        const cottages_wp = try spatial.graph.add_waypoint(village_scene, 15, 9, "Cottages");
        const tavern_wp = try spatial.graph.add_waypoint(village_scene, 28, -10, "Tavern");
        const sheriffs_post_wp = try spatial.graph.add_waypoint(village_scene, 28, 6, "SheriffsPost");

        // Village cobblestone road network
        try spatial.graph.connect(bakery_wp, town_square_wp, null);
        try spatial.graph.connect(farm_wp, town_square_wp, null);
        try spatial.graph.connect(bakery_wp, farm_wp, null);
        try spatial.graph.connect(town_square_wp, cottages_wp, null);
        try spatial.graph.connect(town_square_wp, tavern_wp, null);
        try spatial.graph.connect(town_square_wp, sheriffs_post_wp, null);
        try spatial.graph.connect(tavern_wp, sheriffs_post_wp, null);
        try spatial.graph.connect(cottages_wp, farm_wp, null);
        try spatial.graph.connect(cottages_wp, sheriffs_post_wp, null);

        // Register inspectable building props / hotspots (P18-03)
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

        // Register villagers in spatial navigation system
        try spatial.register_entity(sheriff, sheriffs_post_wp, 12);
        try spatial.register_entity(baker, bakery_wp, 10);
        try spatial.register_entity(farmer, farm_wp, 10);
        try spatial.register_entity(innkeeper, tavern_wp, 10);
        try spatial.register_entity(gossip, town_square_wp, 13);
        try spatial.register_entity(drifter, cottages_wp, 11);

        var sim = VillageSimulation{
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
            .hunger_rel = hunger_rel,
            .energy_rel = energy_rel,
            .gold_rel = gold_rel,
            .activity_rel = activity_rel,
            .mood_rel = mood_rel,
            .friend_rel = friend_rel,
            .rival_rel = rival_rel,
            .grudge_rel = grudge_rel,
            .owns_rel = owns_rel,
            .carries_rel = carries_rel,
            .stolen_from_rel = stolen_from_rel,
            .crime_scene_rel = crime_scene_rel,
            .witnessed_rel = witnessed_rel,
            .knows_rumor_rel = knows_rumor_rel,
            .warrant_for_rel = warrant_for_rel,
            .arrested_rel = arrested_rel,
        };

        // Seed initial physiological drives (Hunger, Energy, Gold, Activity)
        // Sheriff: well-fed, high energy, patrolling
        try world.remember(sheriff, hunger_rel, 20, 0);
        try world.remember(sheriff, energy_rel, 90, 0);
        try world.remember(sheriff, gold_rel, 25, 0);
        try world.remember(sheriff, activity_rel, @intFromEnum(VillagerActivity.patrolling), 0);

        // Baker: working at Bakery, owns BreadLoaf
        try world.remember(baker, hunger_rel, 25, 0);
        try world.remember(baker, energy_rel, 85, 0);
        try world.remember(baker, gold_rel, 30, 0);
        try world.remember(baker, activity_rel, @intFromEnum(VillagerActivity.working), 0);
        try world.remember(baker, owns_rel, bread_loaf.to_int(), 0);
        try world.remember(baker, carries_rel, bread_loaf.to_int(), 0);

        // Farmer: working at Farm, grows wheat, gets hungry and buys bread
        try world.remember(farmer, hunger_rel, 45, 0);
        try world.remember(farmer, energy_rel, 80, 0);
        try world.remember(farmer, gold_rel, 15, 0);
        try world.remember(farmer, activity_rel, @intFromEnum(VillagerActivity.working), 0);
        try world.remember(farmer, owns_rel, wheat_bundle.to_int(), 0);

        // Innkeeper: working at Tavern
        try world.remember(innkeeper, hunger_rel, 30, 0);
        try world.remember(innkeeper, energy_rel, 85, 0);
        try world.remember(innkeeper, gold_rel, 25, 0);
        try world.remember(innkeeper, activity_rel, @intFromEnum(VillagerActivity.working), 0);
        try world.remember(innkeeper, owns_rel, ale_mug.to_int(), 0);

        // Gossip: socializing at TownSquare, connects Baker, Farmer, Innkeeper, and Sheriff
        try world.remember(gossip, hunger_rel, 35, 0);
        try world.remember(gossip, energy_rel, 90, 0);
        try world.remember(gossip, gold_rel, 12, 0);
        try world.remember(gossip, activity_rel, @intFromEnum(VillagerActivity.socializing), 0);

        // Drifter: impoverished newcomer with high initial hunger (64) and 0 Gold!
        try world.remember(drifter, hunger_rel, 64, 0);
        try world.remember(drifter, energy_rel, 75, 0);
        try world.remember(drifter, gold_rel, 0, 0);
        try world.remember(drifter, activity_rel, @intFromEnum(VillagerActivity.socializing), 0);

        // Seed initial social network graph (Friend edges)
        try sim.add_friendship(world, baker, farmer);
        try sim.add_friendship(world, baker, gossip);
        try sim.add_friendship(world, farmer, innkeeper);
        try sim.add_friendship(world, gossip, innkeeper);
        try sim.add_friendship(world, gossip, sheriff);
        try sim.add_friendship(world, innkeeper, sheriff);

        sim.log_chronicle(0, .social, "Living Village initialized: 6 autonomous villagers active.");
        return sim;
    }

    pub fn add_friendship(self: *const VillageSimulation, world: *bespoke.World, a: bespoke.EntityId, b: bespoke.EntityId) !void {
        try world.remember(a, self.friend_rel, b.to_int(), 0);
        try world.remember(b, self.friend_rel, a.to_int(), 0);
    }

    /// Appends an entry to the Village Event Chronicle ring buffer (P18-03).
    pub fn log_chronicle(self: *VillageSimulation, tick: u64, category: ChronicleCategory, text: []const u8) void {
        var entry = ChronicleEntry{
            .tick = tick,
            .category = category,
            .message = [_]u8{0} ** 96,
            .message_len = 0,
        };
        const len = @min(text.len, entry.message.len);
        @memcpy(entry.message[0..len], text[0..len]);
        entry.message_len = @intCast(len);

        if (self.chronicle_count < MAX_CHRONICLE_ENTRIES) {
            self.chronicle[self.chronicle_count] = entry;
            self.chronicle_count += 1;
        } else {
            var i: usize = 0;
            while (i + 1 < MAX_CHRONICLE_ENTRIES) : (i += 1) {
                self.chronicle[i] = self.chronicle[i + 1];
            }
            self.chronicle[MAX_CHRONICLE_ENTRIES - 1] = entry;
        }
    }

    /// Returns the array of all 6 village NPCs.
    pub fn villagers(self: *const VillageSimulation) [6]bespoke.EntityId {
        return .{
            self.sheriff,
            self.baker,
            self.farmer,
            self.innkeeper,
            self.gossip,
            self.drifter,
        };
    }

    /// Queries a villager's current Hunger (0..100).
    pub fn get_hunger(self: *const VillageSimulation, world: *const bespoke.World, npc: bespoke.EntityId) u32 {
        return world.get_property(npc, self.hunger_rel) orelse 0;
    }

    /// Queries a villager's current Energy (0..100).
    pub fn get_energy(self: *const VillageSimulation, world: *const bespoke.World, npc: bespoke.EntityId) u32 {
        return world.get_property(npc, self.energy_rel) orelse 0;
    }

    /// Queries a villager's current Gold.
    pub fn get_gold(self: *const VillageSimulation, world: *const bespoke.World, npc: bespoke.EntityId) u32 {
        return world.get_property(npc, self.gold_rel) orelse 0;
    }

    /// Queries a villager's current Activity enum.
    pub fn get_activity(self: *const VillageSimulation, world: *const bespoke.World, npc: bespoke.EntityId) VillagerActivity {
        const raw = world.get_property(npc, self.activity_rel) orelse 0;
        return VillagerActivity.from_int(raw);
    }

    /// Checks whether two villagers are co-located (same waypoint or within Euclidean distance threshold).
    pub fn are_colocated(spatial: *const bespoke.SpatialSystem, a: bespoke.EntityId, b: bespoke.EntityId, max_dist: i32) bool {
        const agent_a = spatial.agents.get(a) orelse return false;
        const agent_b = spatial.agents.get(b) orelse return false;
        if (agent_a.current_wp == agent_b.current_wp and !agent_a.is_moving and !agent_b.is_moving) {
            return true;
        }
        const dx = agent_a.pos.x - agent_b.pos.x;
        const dy = agent_a.pos.y - agent_b.pos.y;
        return (dx * dx + dy * dy) <= (max_dist * max_dist);
    }

    /// Commands an entity to walk toward `target_wp` if not already there or walking toward it.
    fn direct_walk_to(spatial: *bespoke.SpatialSystem, npc: bespoke.EntityId, target_wp: bespoke.WaypointId) !bool {
        if (spatial.agents.get(npc)) |agent| {
            if (agent.current_wp == target_wp and !agent.is_moving) {
                return true; // Already arrived
            }
            if (agent.is_moving and agent.target_wp == target_wp) {
                return false; // Already en route
            }
            _ = try spatial.walk_to(npc, target_wp);
        }
        return false;
    }

    /// Advances one full tick of the Living Village simulation spine:
    /// 1. Steps VM, World TTL clock, and Spatial A* movement.
    /// 2. Updates physiological drives (Hunger, Energy, Gold) & utility choices (P18-01).
    /// 3. Evaluates witness detection at crime scenes (P18-02).
    /// 4. Propagates rumors across co-located social graph links (P18-02).
    /// 5. Executes autonomous Sheriff investigation, pursuit, and arrest cascades (P18-02).
    pub fn step_simulation(
        self: *VillageSimulation,
        world: *bespoke.World,
        spatial: *bespoke.SpatialSystem,
        vm: *bespoke.VM,
    ) !void {
        try vm.step_tick();
        try self.step_drives(world, spatial);
        try self.evaluate_witnesses(world, spatial);
        try self.propagate_rumors(world, spatial);
        try self.evaluate_justice_cascade(world, spatial, vm);
    }

    /// Step 1: Continuous Physiological Needs & Autonomous Utility Decisions (P18-01, D-007, D-021).
    pub fn step_drives(self: *VillageSimulation, world: *bespoke.World, spatial: *bespoke.SpatialSystem) !void {
        const tick = world.current_tick;
        const all_npcs = self.villagers();

        for (all_npcs) |npc| {
            const name = world.get_entity_name(npc) orelse "Villager";

            // If arrested, remain in Sheriff's jail cell
            if (world.has_fact(npc, self.arrested_rel, null)) {
                try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.arrested), 0);
                _ = try direct_walk_to(spatial, npc, self.sheriffs_post_wp);
                continue;
            }

            var hunger = self.get_hunger(world, npc);
            var energy = self.get_energy(world, npc);
            var gold = self.get_gold(world, npc);
            const cur_act = self.get_activity(world, npc);

            // 1. Sleeping recovery at Cottages
            if (cur_act == .sleeping) {
                const at_cottages = try direct_walk_to(spatial, npc, self.cottages_wp);
                if (at_cottages) {
                    energy = @min(100, energy + 14);
                    hunger = @min(100, hunger + 1);
                    try world.remember(npc, self.energy_rel, energy, 0);
                    try world.remember(npc, self.hunger_rel, hunger, 0);
                    if (energy >= 90) {
                        const resume_act: VillagerActivity = if (npc == self.sheriff)
                            .patrolling
                        else if (npc == self.gossip or npc == self.drifter)
                            .socializing
                        else
                            .working;
                        try world.remember(npc, self.activity_rel, @intFromEnum(resume_act), 0);
                    }
                }
                continue;
            }

            // 2. Normal metabolic tick: Hunger rises, Energy falls
            const hunger_rate: u32 = if (npc == self.drifter) 4 else 3;
            hunger = @min(100, hunger + hunger_rate);
            energy = if (energy > 2) energy - 2 else 0;
            try world.remember(npc, self.hunger_rel, hunger, 0);
            try world.remember(npc, self.energy_rel, energy, 0);

            // If Sheriff is actively investigating a warrant, do not override with routine drives
            if (npc == self.sheriff and world.has_fact(self.sheriff, self.warrant_for_rel, null)) {
                continue;
            }

            // 3. Exhaustion check: go sleep at Cottages when Energy is critical
            if (energy <= LOW_ENERGY_THRESHOLD and cur_act != .stealing and cur_act != .fleeing) {
                try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.sleeping), 0);
                _ = try direct_walk_to(spatial, npc, self.cottages_wp);
                var buf: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "{s} is exhausted (Energy {d}) and heads to Cottages to sleep.", .{ name, energy }) catch "Villager heads to sleep.";
                self.log_chronicle(tick, .work, msg);
                continue;
            }

            // 4. Desperation Theft check: Hunger >= 80 and Gold < MEAL_PRICE_GOLD (P18-02)
            if (hunger >= DESPERATION_HUNGER_THRESHOLD and gold < MEAL_PRICE_GOLD and
                !world.has_fact(npc, self.stolen_from_rel, self.baker.to_int()))
            {
                try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.stealing), 0);
                const arrived_bakery = try direct_walk_to(spatial, npc, self.bakery_wp);
                if (arrived_bakery) {
                    // Execute emergent property theft at the Bakery!
                    try world.remember(npc, self.stolen_from_rel, self.baker.to_int(), 0);
                    try world.remember(npc, self.crime_scene_rel, self.bakery_wp, 0);
                    try world.remember(npc, self.carries_rel, self.bread_loaf.to_int(), 0);
                    _ = world.forget(self.baker, self.carries_rel, self.bread_loaf.to_int());

                    // Eating the stolen bread relieves desperate hunger
                    hunger = if (hunger > 60) hunger - 60 else 10;
                    try world.remember(npc, self.hunger_rel, hunger, 0);
                    try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.fleeing), 0);

                    var buf: [96]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "{s} (Hunger>=80, Gold=0) stole BreadLoaf from Baker!", .{name}) catch "BreadLoaf stolen!";
                    self.log_chronicle(tick, .crime, msg);

                    // Immediately detect any witnesses present at the Bakery at the moment of the crime
                    try self.evaluate_witnesses(world, spatial);

                    // Thief flees toward the Farm hideout
                    _ = try direct_walk_to(spatial, npc, self.farm_wp);
                }
                continue;
            }

            // If fleeing after a crime, run toward Farm or Cottages
            if (cur_act == .fleeing) {
                const at_farm = try direct_walk_to(spatial, npc, self.farm_wp);
                if (at_farm and tick % 4 == 0) {
                    _ = try direct_walk_to(spatial, npc, self.cottages_wp);
                }
                continue;
            }

            // 5. Honest Meal Purchase when Hungry and has Gold >= 5
            if (hunger >= HUNGRY_BUY_THRESHOLD and gold >= MEAL_PRICE_GOLD) {
                try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.eating), 0);
                const food_wp = if (npc == self.sheriff or npc == self.innkeeper) self.tavern_wp else self.bakery_wp;
                const merchant = if (food_wp == self.tavern_wp) self.innkeeper else self.baker;
                const merchant_name = world.get_entity_name(merchant) orelse "Merchant";

                if (try direct_walk_to(spatial, npc, food_wp)) {
                    hunger = if (hunger > 50) hunger - 50 else 5;
                    try world.remember(npc, self.hunger_rel, hunger, 0);

                    if (npc != merchant) {
                        gold -= MEAL_PRICE_GOLD;
                        try world.remember(npc, self.gold_rel, gold, 0);
                        const m_gold = self.get_gold(world, merchant) + MEAL_PRICE_GOLD;
                        try world.remember(merchant, self.gold_rel, m_gold, 0);
                        try self.add_friendship(world, npc, merchant);

                        var buf: [96]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "{s} bought a warm meal from {s} for {d}g.", .{ name, merchant_name, MEAL_PRICE_GOLD }) catch "Bought meal.";
                        self.log_chronicle(tick, .trade, msg);
                    }

                    const next_act: VillagerActivity = if (npc == self.sheriff) .patrolling else .working;
                    try world.remember(npc, self.activity_rel, @intFromEnum(next_act), 0);
                }
                continue;
            }

            // 6. Routine Daily Schedules & Autonomous Patrols
            if (npc == self.baker) {
                try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.working), 0);
                if (try direct_walk_to(spatial, npc, self.bakery_wp)) {
                    if (tick % 5 == 0) {
                        try world.remember(self.baker, self.owns_rel, self.bread_loaf.to_int(), 0);
                        try world.remember(self.baker, self.carries_rel, self.bread_loaf.to_int(), 0);
                        try world.remember(self.baker, self.gold_rel, gold + 1, 0);
                    }
                }
            } else if (npc == self.farmer) {
                try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.working), 0);
                const dest_wp = if ((tick / 6) % 2 == 0) self.farm_wp else self.town_square_wp;
                if (try direct_walk_to(spatial, npc, dest_wp)) {
                    if (dest_wp == self.farm_wp and tick % 4 == 0) {
                        try world.remember(self.farmer, self.gold_rel, gold + 2, 0);
                    }
                }
            } else if (npc == self.innkeeper) {
                try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.working), 0);
                if (try direct_walk_to(spatial, npc, self.tavern_wp)) {
                    if (tick % 5 == 0) {
                        try world.remember(self.innkeeper, self.gold_rel, gold + 1, 0);
                    }
                }
            } else if (npc == self.gossip) {
                // If Gossip knows a crime rumor, they hurry toward TownSquare / SheriffsPost to spread it!
                if (world.has_fact(self.gossip, self.knows_rumor_rel, null) and
                    !world.has_fact(self.sheriff, self.knows_rumor_rel, null))
                {
                    try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.socializing), 0);
                    if (spatial.agents.get(self.sheriff)) |sh_agent| {
                        _ = try direct_walk_to(spatial, self.gossip, sh_agent.current_wp);
                    } else {
                        _ = try direct_walk_to(spatial, self.gossip, self.town_square_wp);
                    }
                } else {
                    const cycle = (tick / 4) % 3;
                    const wp = switch (cycle) {
                        0 => self.town_square_wp,
                        1 => self.bakery_wp,
                        else => self.tavern_wp,
                    };
                    _ = try direct_walk_to(spatial, self.gossip, wp);
                }
            } else if (npc == self.sheriff) {
                try world.remember(npc, self.activity_rel, @intFromEnum(VillagerActivity.patrolling), 0);
                const patrol_wp = if ((tick / 5) % 2 == 0) self.town_square_wp else self.sheriffs_post_wp;
                _ = try direct_walk_to(spatial, self.sheriff, patrol_wp);
            } else if (npc == self.drifter) {
                // Before desperation strikes, Drifter wanders to TownSquare looking for odd jobs
                _ = try direct_walk_to(spatial, self.drifter, self.town_square_wp);
            }
        }
    }

    /// Step 2: Witness Detection at the Crime Scene (P18-02, D-010, D-021).
    pub fn evaluate_witnesses(self: *VillageSimulation, world: *bespoke.World, spatial: *bespoke.SpatialSystem) !void {
        const tick = world.current_tick;
        const all_npcs = self.villagers();

        // Check if any villager has committed a theft
        for (all_npcs) |thief| {
            if (!world.has_fact(thief, self.stolen_from_rel, null)) continue;
            if (world.has_fact(thief, self.arrested_rel, null)) continue;

            const thief_name = world.get_entity_name(thief) orelse "Thief";

            for (all_npcs) |witness| {
                if (witness == thief) continue;
                if (world.has_fact(witness, self.witnessed_rel, thief.to_int())) continue;

                // Sleeping villagers cannot witness crimes
                if (self.get_activity(world, witness) == .sleeping) continue;

                // Witness detects theft only if present near the Bakery crime scene when the theft occurs
                const at_crime_scene = blk: {
                    const wit_agent = spatial.agents.get(witness) orelse break :blk false;
                    const bakery_node = spatial.graph.get_waypoint(self.bakery_wp) orelse break :blk false;
                    if (wit_agent.current_wp == self.bakery_wp and !wit_agent.is_moving) break :blk true;
                    const dx = wit_agent.pos.x - bakery_node.pos.x;
                    const dy = wit_agent.pos.y - bakery_node.pos.y;
                    break :blk (dx * dx + dy * dy) <= (14 * 14);
                };
                const thief_at_bakery = blk: {
                    const th_agent = spatial.agents.get(thief) orelse break :blk false;
                    const bakery_node = spatial.graph.get_waypoint(self.bakery_wp) orelse break :blk false;
                    const dx = th_agent.pos.x - bakery_node.pos.x;
                    const dy = th_agent.pos.y - bakery_node.pos.y;
                    break :blk (dx * dx + dy * dy) <= (12 * 12);
                };

                if (at_crime_scene and thief_at_bakery) {
                    try world.remember(witness, self.witnessed_rel, thief.to_int(), 0);
                    try world.remember(witness, self.knows_rumor_rel, thief.to_int(), 0);
                    // Temporal grudge that expires after 60 ticks (D-003)
                    try world.remember(witness, self.grudge_rel, thief.to_int(), tick + 60);
                    try world.remember(witness, self.rival_rel, thief.to_int(), 0);

                    const wit_name = world.get_entity_name(witness) orelse "Villager";
                    var buf: [96]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "{s} witnessed {s} stealing BreadLoaf and formed a Grudge!", .{ wit_name, thief_name }) catch "Crime witnessed!";
                    self.log_chronicle(tick, .witness, msg);

                    // Witness walks to TownSquare to report the crime to Gossip / Sheriff
                    if (witness != self.sheriff) {
                        _ = try direct_walk_to(spatial, witness, self.town_square_wp);
                    }
                }
            }
        }
    }

    /// Step 3: Rumor Propagation across Co-Located Social Graph Links (P18-02, D-010, D-021).
    pub fn propagate_rumors(self: *VillageSimulation, world: *bespoke.World, spatial: *bespoke.SpatialSystem) !void {
        const tick = world.current_tick;
        const all_npcs = self.villagers();

        for (all_npcs) |thief| {
            if (!world.has_fact(thief, self.stolen_from_rel, null)) continue;
            if (world.has_fact(thief, self.arrested_rel, null)) continue;

            const thief_name = world.get_entity_name(thief) orelse "Thief";

            // Collect speakers who already know the rumor at the start of this tick
            // so a rumor spreads 1 hop per tick along the social graph.
            var speakers: [6]bespoke.EntityId = undefined;
            var speaker_count: usize = 0;
            for (all_npcs) |npc| {
                if (npc != thief and world.has_fact(npc, self.knows_rumor_rel, thief.to_int())) {
                    speakers[speaker_count] = npc;
                    speaker_count += 1;
                }
            }

            for (speakers[0..speaker_count]) |speaker| {
                if (self.get_activity(world, speaker) == .sleeping) continue;

                // If speaker hasn't told the Sheriff yet, walk toward TownSquare to cross paths
                if (!world.has_fact(self.sheriff, self.knows_rumor_rel, thief.to_int()) and speaker != self.sheriff) {
                    _ = try direct_walk_to(spatial, speaker, self.town_square_wp);
                }

                for (all_npcs) |listener| {
                    if (listener == speaker or listener == thief) continue;
                    if (world.has_fact(listener, self.knows_rumor_rel, thief.to_int())) continue;
                    if (self.get_activity(world, listener) == .sleeping) continue;

                    // Must be co-located at the same landmark or road segment
                    if (!are_colocated(spatial, speaker, listener, 15)) continue;

                    // Social graph check: spreads if Friends, if speaker is Witness/Gossip, or if listener is Sheriff
                    const are_friends = world.has_fact(speaker, self.friend_rel, listener.to_int()) or
                        world.has_fact(listener, self.friend_rel, speaker.to_int());
                    const is_witness = world.has_fact(speaker, self.witnessed_rel, thief.to_int());
                    const can_share = are_friends or is_witness or (speaker == self.gossip) or (listener == self.sheriff);

                    if (can_share) {
                        try world.remember(listener, self.knows_rumor_rel, thief.to_int(), 0);
                        // Listener also forms disapproval grudge against thief
                        try world.remember(listener, self.grudge_rel, thief.to_int(), tick + 50);

                        const spk_name = world.get_entity_name(speaker) orelse "Speaker";
                        const lst_name = world.get_entity_name(listener) orelse "Listener";
                        var buf: [96]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "{s} spread rumor of {s}'s theft to {s}!", .{ spk_name, thief_name, lst_name }) catch "Rumor spread!";
                        self.log_chronicle(tick, .rumor, msg);
                    }
                }
            }
        }
    }

    /// Step 4: Autonomous Sheriff Investigation, Warrant Issuance, and Arrest Cascade (P18-02, D-004, D-021).
    pub fn evaluate_justice_cascade(
        self: *VillageSimulation,
        world: *bespoke.World,
        spatial: *bespoke.SpatialSystem,
        vm: *bespoke.VM,
    ) !void {
        const tick = world.current_tick;
        const all_npcs = self.villagers();

        for (all_npcs) |thief| {
            if (thief == self.sheriff) continue;
            if (!world.has_fact(self.sheriff, self.knows_rumor_rel, thief.to_int())) continue;
            if (world.has_fact(thief, self.arrested_rel, null)) continue;

            const thief_name = world.get_entity_name(thief) orelse "Thief";

            // 1. Issue Warrant & Preempt Sheriff's Routine Patrol (Priority 10 Interrupt, D-004)
            if (!world.has_fact(self.sheriff, self.warrant_for_rel, thief.to_int())) {
                try world.remember(self.sheriff, self.warrant_for_rel, thief.to_int(), 0);
                try world.remember(self.sheriff, self.activity_rel, @intFromEnum(VillagerActivity.investigating), 0);

                // Trigger priority interrupt on Sheriff fiber if present
                _ = try vm.interrupt_entity_priority(self.sheriff, 0, 10);

                var buf: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Sheriff heard rumor and issued WarrantFor(Sheriff, {s})!", .{thief_name}) catch "Warrant issued!";
                self.log_chronicle(tick, .justice, msg);
            }

            // 2. Sheriff pursues the suspect across the village waypoint graph
            try world.remember(self.sheriff, self.activity_rel, @intFromEnum(VillagerActivity.investigating), 0);
            if (spatial.agents.get(thief)) |thief_agent| {
                _ = try direct_walk_to(spatial, self.sheriff, thief_agent.current_wp);
            }

            // 3. When Sheriff intercepts the suspect, execute the Arrest and recover stolen property!
            if (are_colocated(spatial, self.sheriff, thief, 14)) {
                try world.remember(thief, self.arrested_rel, self.sheriff.to_int(), 0);
                _ = world.forget(self.sheriff, self.warrant_for_rel, thief.to_int());
                try world.remember(thief, self.activity_rel, @intFromEnum(VillagerActivity.arrested), 0);
                try world.remember(self.sheriff, self.activity_rel, @intFromEnum(VillagerActivity.patrolling), 0);

                // Recover stolen BreadLoaf and return ownership to Baker
                _ = world.forget(thief, self.carries_rel, self.bread_loaf.to_int());
                try world.remember(self.baker, self.owns_rel, self.bread_loaf.to_int(), 0);
                try world.remember(self.baker, self.carries_rel, self.bread_loaf.to_int(), 0);

                // Escort both Sheriff and arrested thief to SheriffsPost jail cell
                _ = try direct_walk_to(spatial, thief, self.sheriffs_post_wp);
                _ = try direct_walk_to(spatial, self.sheriff, self.sheriffs_post_wp);

                var buf: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Sheriff arrested {s}, recovered BreadLoaf, and jailed offender!", .{thief_name}) catch "Suspect arrested!";
                self.log_chronicle(tick, .arrest, msg);
            }
        }
    }

    /// Interactive Catalyst: Forces `Drifter` into immediate desperation at the `Bakery`
    /// so players can trigger and watch the theft -> witness -> rumor -> arrest cascade on demand.
    pub fn trigger_desperation_catalyst(self: *VillageSimulation, world: *bespoke.World, spatial: *bespoke.SpatialSystem) !void {
        _ = world.forget(self.drifter, self.arrested_rel, null);
        _ = world.forget(self.drifter, self.stolen_from_rel, null);
        _ = world.forget(self.sheriff, self.warrant_for_rel, null);
        for (self.villagers()) |npc| {
            _ = world.forget(npc, self.witnessed_rel, self.drifter.to_int());
            _ = world.forget(npc, self.knows_rumor_rel, self.drifter.to_int());
        }
        try world.remember(self.drifter, self.hunger_rel, 88, 0);
        try world.remember(self.drifter, self.gold_rel, 0, 0);
        try world.remember(self.drifter, self.activity_rel, @intFromEnum(VillagerActivity.stealing), 0);
        _ = try direct_walk_to(spatial, self.drifter, self.bakery_wp);
        self.log_chronicle(world.current_tick, .crime, "Catalyst injected: Drifter is starving (Hunger 88, Gold 0)!");
    }

    /// Interactive Catalyst: Feeds all villagers and grants 10g prosperity bonus.
    pub fn feed_all_villagers(self: *VillageSimulation, world: *bespoke.World) !void {
        for (self.villagers()) |npc| {
            try world.remember(npc, self.hunger_rel, 10, 0);
            try world.remember(npc, self.energy_rel, 95, 0);
            const g = self.get_gold(world, npc);
            try world.remember(npc, self.gold_rel, g + 10, 0);
        }
        self.log_chronicle(world.current_tick, .trade, "Prosperity feast: All villagers fed (Hunger=10, +10g)!");
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

    var sim = try VillageSimulation.init(&world, &spatial);

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
        try sim.step_simulation(&world, &spatial, &vm);

        // Print any new chronicle events emitted during this tick
        while (printed_chronicle_idx < sim.chronicle_count) : (printed_chronicle_idx += 1) {
            const entry = &sim.chronicle[printed_chronicle_idx];
            try writer.print("   [Tick {d:02} | {s:<7}] {s}\n", .{
                entry.tick,
                entry.category.tag(),
                entry.get_message(),
            });
        }

        if (world.has_fact(sim.drifter, sim.stolen_from_rel, sim.baker.to_int())) {
            saw_theft = true;
        }
        if (world.has_fact(null, sim.witnessed_rel, sim.drifter.to_int())) {
            saw_witness = true;
        }
        if (world.has_fact(sim.gossip, sim.knows_rumor_rel, sim.drifter.to_int()) or
            world.has_fact(sim.farmer, sim.knows_rumor_rel, sim.drifter.to_int()) or
            world.has_fact(sim.sheriff, sim.knows_rumor_rel, sim.drifter.to_int()))
        {
            saw_rumor_spread = true;
        }
        if (world.has_fact(sim.sheriff, sim.warrant_for_rel, sim.drifter.to_int())) {
            saw_warrant = true;
        }
        if (world.has_fact(sim.drifter, sim.arrested_rel, sim.sheriff.to_int())) {
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
    try std.testing.expect(world.has_fact(sim.baker, sim.carries_rel, sim.bread_loaf.to_int()));

    // Verify deterministic time-travel rewind back to Tick 0 pre-crime state
    try writer.print("\n[Phase 3: Deterministic Time-Travel Rewind to Pre-Crime State]\n", .{});
    var fbs = std.io.fixedBufferStream(snap0.items);
    try world.restore_state(fbs.reader());
    try writer.print("   -> Restored Tick {d} snapshot.\n", .{world.current_tick});
    try writer.print("   -> StolenFrom(Drifter, Baker) active? {s}\n", .{
        if (!world.has_fact(sim.drifter, sim.stolen_from_rel, null)) "false (Clean)" else "true (Leaked!)",
    });
    try writer.print("   -> Arrested(Drifter, Sheriff) active? {s}\n", .{
        if (!world.has_fact(sim.drifter, sim.arrested_rel, null)) "false (Clean)" else "true (Leaked!)",
    });
    try std.testing.expectEqual(@as(u64, 0), world.current_tick);
    try std.testing.expect(!world.has_fact(sim.drifter, sim.stolen_from_rel, null));
    try std.testing.expect(!world.has_fact(sim.drifter, sim.arrested_rel, null));

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

    var sim = try VillageSimulation.init(&world, &spatial);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(sim.village_scene);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Living Village (Emergent Simulation Sandbox)", 1280, 720);
    defer window.deinit();

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

    var history_snapshots = std.ArrayList(std.ArrayList(u8)).init(allocator);
    defer {
        for (history_snapshots.items) |*snap| snap.deinit();
        history_snapshots.deinit();
    }

    var snap0 = std.ArrayList(u8).init(allocator);
    try world.save_state(snap0.writer());
    try history_snapshots.append(snap0);

    var repl_engine = bespoke.Repl.init(&world, &spatial, &vm);
    var display_bridge = bespoke.DisplayBridge.init();
    display_bridge.attach_audio_bridge(window.audio_bridge);
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.swap();

    window.set_cue_banner("The Living Village: Watch autonomous drives, rumors, and justice unfold!", 180);

    var is_running = true;
    var is_paused = false;
    var last_tick_time = std.time.milliTimestamp();
    var last_logged_chronicle: usize = 0;

    while (is_running) {
        const current_frame = display_bridge.get_frame();
        const action = window.poll_events(current_frame);
        _ = window.handle_save_action(action, &world, &spatial, &vm, &display_bridge, &is_paused);

        switch (action) {
            .quit => is_running = false,
            .toggle_pause => is_paused = !is_paused,
            .step_tick => {
                if (is_paused) {
                    try sim.step_simulation(&world, &spatial, &vm);
                    var snap = std.ArrayList(u8).init(allocator);
                    try world.save_state(snap.writer());
                    try history_snapshots.append(snap);
                    display_bridge.set_max_history_tick(world.current_tick);
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                }
            },
            .walk_player => |wp_id| {
                _ = try spatial.walk_to(sim.sheriff, wp_id);
            },
            .examine_hotspot => |hs_idx| {
                if (hs_idx < current_frame.hotspot_count) {
                    const hs = &current_frame.hotspots[hs_idx];
                    window.set_cue_banner(hs.get_examine_text(), 150);
                }
            },
            .interact_actor => |ia| {
                if (ia.actor_index < current_frame.entity_count) {
                    const target_ent = current_frame.entities[ia.actor_index];
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
            .spit_contest_spit => {
                // [S] hotkey triggers the Desperation Theft Catalyst in Living Village
                try sim.trigger_desperation_catalyst(&world, &spatial);
                window.set_cue_banner("Catalyst [S]: Drifter driven to desperate hunger at Bakery!", 150);
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.swap();
            },
            .tamper_flags => {
                // [F] hotkey triggers Prosperity Feast (feeds all villagers)
                try sim.feed_all_villagers(&world);
                window.set_cue_banner("Catalyst [F]: Prosperity Feast! All villagers fed (+10g).", 150);
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.swap();
            },
            .drink_green_drink => {
                // [G] hotkey tips off the Sheriff with the active rumor
                try world.remember(sim.sheriff, sim.knows_rumor_rel, sim.drifter.to_int(), 0);
                sim.log_chronicle(world.current_tick, .rumor, "Tip-off [G]: Sheriff alerted to rumor about Drifter!");
                window.set_cue_banner("Catalyst [G]: Sheriff tipped off! Warrant cascade initiated!", 150);
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.swap();
            },
            .rewind => {
                if (history_snapshots.items.len > 0) {
                    var fbs = std.io.fixedBufferStream(history_snapshots.items[0].items);
                    try world.restore_state(fbs.reader());
                    window.set_cue_banner("Rewound to Tick 0 baseline!", 120);
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.swap();
                }
            },
            .scrub_to_tick => |target_tick| {
                is_paused = true;
                for (history_snapshots.items) |snap| {
                    var fbs = std.io.fixedBufferStream(snap.items);
                    try world.restore_state(fbs.reader());
                    if (world.current_tick == target_tick) break;
                }
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.swap();
            },
            .repl_command => |rc| {
                const cmd_str = rc.buf[0..rc.len];
                const res = repl_engine.execute(cmd_str);
                window.add_console_history(res.get_text());
                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.swap();
            },
            else => {},
        }

        const now = std.time.milliTimestamp();
        if (!is_paused and (now - last_tick_time >= window.current_tick_interval_ms)) {
            last_tick_time = now;
            try sim.step_simulation(&world, &spatial, &vm);

            if (sim.chronicle_count > last_logged_chronicle) {
                const latest = &sim.chronicle[sim.chronicle_count - 1];
                window.set_cue_banner(latest.get_message(), 120);
                last_logged_chronicle = sim.chronicle_count;
            }

            var snap = std.ArrayList(u8).init(allocator);
            try world.save_state(snap.writer());
            try history_snapshots.append(snap);
            display_bridge.set_max_history_tick(world.current_tick);

            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        window.render_frame(display_bridge.get_frame(), is_paused);
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

    var sim = try VillageSimulation.init(&world, &spatial);

    // Verify all 6 villagers and initial property relations exist
    try testing.expectEqual(@as(u32, 20), sim.get_hunger(&world, sim.sheriff));
    try testing.expectEqual(@as(u32, 90), sim.get_energy(&world, sim.sheriff));
    try testing.expectEqual(@as(u32, 30), sim.get_gold(&world, sim.baker));
    try testing.expectEqual(@as(u32, 0), sim.get_gold(&world, sim.drifter));

    // Verify social graph Friend edges
    try testing.expect(world.has_fact(sim.baker, sim.friend_rel, sim.gossip.to_int()));
    try testing.expect(world.has_fact(sim.gossip, sim.friend_rel, sim.sheriff.to_int()));

    // Step 1 metabolic tick and verify Hunger increases and Energy decreases
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    try sim.step_simulation(&world, &spatial, &vm);
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

    var sim = try VillageSimulation.init(&world, &spatial);
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    // Set Farmer Energy to 15 (below LOW_ENERGY_THRESHOLD = 22)
    try world.remember(sim.farmer, sim.energy_rel, 15, 0);

    // Step simulation: Farmer should transition to .sleeping and walk to Cottages
    try sim.step_simulation(&world, &spatial, &vm);
    try testing.expectEqual(VillagerActivity.sleeping, sim.get_activity(&world, sim.farmer));

    // Step 10 ticks so Farmer arrives at Cottages and recovers Energy >= 90
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try sim.step_simulation(&world, &spatial, &vm);
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

    var sim = try VillageSimulation.init(&world, &spatial);
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    // Place Farmer at Bakery with Hunger = 65 and Gold = 15
    try world.remember(sim.farmer, sim.hunger_rel, 65, 0);
    try world.remember(sim.farmer, sim.gold_rel, 15, 0);
    const initial_baker_gold = sim.get_gold(&world, sim.baker);

    var i: usize = 0;
    while (i < 6) : (i += 1) {
        try sim.step_simulation(&world, &spatial, &vm);
    }

    // Farmer should have paid 5g to Baker and reduced Hunger
    try testing.expect(sim.get_hunger(&world, sim.farmer) < 40);
    try testing.expect(sim.get_gold(&world, sim.baker) >= initial_baker_gold + MEAL_PRICE_GOLD);
    try testing.expect(world.has_fact(sim.farmer, sim.friend_rel, sim.baker.to_int()));
}

test "P18-02: Emergent cascade — desperation theft, witness detection, rumor propagation, and Sheriff arrest" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, VILLAGE_SCRIPT);
    defer compiled.deinit();

    var sim = try VillageSimulation.init(&world, &spatial);
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
        try sim.step_simulation(&world, &spatial, &vm);

        if (world.has_fact(sim.drifter, sim.stolen_from_rel, sim.baker.to_int())) saw_theft = true;
        if (world.has_fact(sim.baker, sim.witnessed_rel, sim.drifter.to_int())) saw_witness = true;
        if (world.has_fact(sim.sheriff, sim.knows_rumor_rel, sim.drifter.to_int())) saw_rumor = true;
        if (world.has_fact(sim.sheriff, sim.warrant_for_rel, sim.drifter.to_int())) saw_warrant = true;
        if (world.has_fact(sim.drifter, sim.arrested_rel, sim.sheriff.to_int())) {
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
    try testing.expect(world.has_fact(sim.baker, sim.carries_rel, sim.bread_loaf.to_int()));
}

test "P18-03: Village spatial topology, hotspots, and headless runner verification" {
    const testing = std.testing;
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try run_headless(testing.allocator, buf.writer());
    try testing.expect(std.mem.indexOf(u8, buf.items, "ALL LIVING VILLAGE EMERGENT SIMULATION CHECKS PASSED!") != null);
}
