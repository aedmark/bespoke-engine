//! Emergent society simulation (P32-05, D-032, D-034).
//!
//! A data-driven social layer over the World, Spatial, and VM stores. The host supplies a
//! `Config`: a list of needs, a roster with data roles (merchant, broadcaster, enforcer) and
//! routines, and the locations the systems use. Each tick, `Society.step` runs four systems in
//! a fixed order:
//!
//!   1. Drives: needs decay, members rest, trade, steal in desperation, flee, or follow routines.
//!   2. Witnesses: members near a crime scene while the culprit is there learn of the crime.
//!   3. Rumors: knowledge spreads one hop per tick between co-located members along social links.
//!   4. Justice: an enforcer who hears a rumor issues a warrant, pursues, arrests, and recovers goods.
//!
//! All simulation state lives in World facts (property and set relations), never in this struct,
//! so a world snapshot captures the whole society and rewind restores it exactly. This struct
//! holds only the immutable configuration and interned relation ids, plus a display chronicle.
//!
//! The module names no character, place, or setting. Names in chronicle lines come from the
//! World (entity names), the Spatial graph (waypoint names), and the config's theme strings.
const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const vm_mod = @import("vm.zig");
const agency_mod = @import("agency.zig");

const World = world_mod.World;
const EntityId = world_mod.EntityId;
const RelationKind = world_mod.RelationKind;
const SpatialSystem = spatial_mod.SpatialSystem;
const WaypointId = spatial_mod.WaypointId;
const VM = vm_mod.VM;

/// Fixed capacities. The society copies its config into fixed arrays so that it owns no heap
/// memory and the host's config slices may be temporaries.
pub const MAX_MEMBERS: usize = 32;
pub const MAX_NEEDS: usize = 8;
pub const MAX_STOPS: usize = 8;
pub const MAX_CHRONICLE_ENTRIES: usize = 24;
pub const CHRONICLE_MESSAGE_LEN: usize = 96;

pub const Error = error{InvalidSocietyConfig};

/// Member activity, stored as an integer in the activity property relation (D-007).
pub const Activity = enum(u32) {
    working = 0,
    patrolling = 1,
    eating = 2,
    sleeping = 3,
    socializing = 4,
    stealing = 5,
    fleeing = 6,
    investigating = 7,
    arrested = 8,

    pub fn label(self: Activity) []const u8 {
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

    pub fn from_int(val: u32) Activity {
        return if (val <= @intFromEnum(Activity.arrested)) @enumFromInt(val) else .working;
    }
};

/// Which end of a need's range is bad. Hunger is worse high; energy is worse low.
pub const Worse = enum { high, low };

/// A need met by staying at a place until it recovers (rest, for example).
pub const Stay = struct {
    at: WaypointId,
    /// Value regained per tick while at `at`.
    restore: u32,
    /// The stay ends once the value has recovered to this.
    until: u32,
    activity: Activity = .sleeping,
    /// Members staying for this need cannot witness crimes or hear rumors.
    unaware: bool = true,
    /// Theme words for the chronicle line "<name> is <state> (<need> <v>) and heads to <place> to <verb>."
    state: []const u8 = "tired",
    verb: []const u8 = "rest",
};

/// A need met by buying relief from a merchant, or by stealing it in desperation.
pub const Trade = struct {
    /// Default provider (roster index of a merchant); a member may override it.
    provider: ?usize = null,
    price: u32,
    /// Relief moves the value toward good by this much; if that would overshoot, it lands at `floor`.
    relief: u32,
    floor: u32 = 0,
    /// At or past this value a member who cannot afford `price` steals the provider's goods.
    critical: ?u32 = null,
    theft_relief: u32 = 0,
    theft_floor: u32 = 0,
    /// Theme words for the chronicle line "<name> bought <item> from <merchant> for <price><unit>."
    item: []const u8 = "a meal",
};

pub const Satisfier = union(enum) {
    stay: Stay,
    trade: Trade,
};

/// One need, stored as a property relation named `name`. Values run from 0 to `max`.
/// Thresholds are given as values; `worse` says which direction they count from.
pub const Need = struct {
    name: []const u8,
    worse: Worse = .high,
    max: u32 = 100,
    /// Per-tick drift toward worse.
    rate: u32,
    /// Per-tick drift toward worse while the member stays to meet a different need.
    resting_rate: u32 = 0,
    /// A member acts on the need at or past this value.
    seek: u32,
    satisfy: Satisfier,
};

/// A member's starting value and overrides for one need, aligned with `Config.needs`.
pub const MemberNeed = struct {
    value: u32,
    rate: ?u32 = null,
    provider: ?usize = null,
};

pub const Merchant = struct {
    /// Where the merchant trades; buyers walk here, and a theft from the merchant happens here.
    post: WaypointId,
    goods: EntityId,
};

pub const Work = struct {
    at: WaypointId,
    every: u64,
    earn: u32,
    /// Merchants restock their goods when they work.
    restock: bool = false,
};

/// A routine cycles through `stops`, moving to the next every `period` ticks.
pub const Routine = struct {
    activity: ?Activity = null,
    stops: []const WaypointId = &.{},
    period: u64 = 1,
    work: ?Work = null,
};

pub const Member = struct {
    entity: EntityId,
    needs: []const MemberNeed,
    gold: u32 = 0,
    /// Starting activity, and the one a member returns to after meeting a need.
    idle: Activity = .working,
    routine: Routine = .{},
    merchant: ?Merchant = null,
    /// A broadcaster shares rumors with anyone and seeks out the enforcer with news.
    broadcaster: bool = false,
    owns: []const EntityId = &.{},
    carries: []const EntityId = &.{},
};

/// Where a culprit runs after a theft: to `to`, then on to `then` every `every` ticks.
pub const Flight = struct {
    to: WaypointId,
    then: ?WaypointId = null,
    every: u64 = 4,
};

/// Distances in world units.
pub const Radii = struct {
    /// How close a witness must be to the crime scene.
    witness: i32 = 14,
    /// How close the culprit must be to the crime scene to be seen.
    culprit: i32 = 12,
    /// How close two members must be to share a rumor.
    rumor: i32 = 15,
    /// How close the enforcer must be to make an arrest.
    arrest: i32 = 14,
};

/// Relation names the society interns. Override them to theme the fact vocabulary.
pub const Relations = struct {
    currency: []const u8 = "Gold",
    activity: []const u8 = "Activity",
    tending: []const u8 = "Tending",
    friend: []const u8 = "Friend",
    rival: []const u8 = "Rival",
    grudge: []const u8 = "Grudge",
    owns: []const u8 = "Owns",
    carries: []const u8 = "Carries",
    stolen_from: []const u8 = "StolenFrom",
    crime_scene: []const u8 = "CrimeScene",
    witnessed: []const u8 = "Witnessed",
    knows_rumor: []const u8 = "KnowsRumor",
    warrant_for: []const u8 = "WarrantFor",
    arrested: []const u8 = "Arrested",
};

/// An undirected social link seeded when a society starts.
pub const FriendLink = struct {
    a: EntityId,
    b: EntityId,
};

pub const Config = struct {
    needs: []const Need,
    members: []const Member,
    /// Roster index of the member who runs justice; null disables the justice system.
    enforcer: ?usize = null,
    /// Where arrested members are held.
    holding: ?WaypointId = null,
    /// Where witnesses and rumor-bearers go to find others.
    gathering: WaypointId,
    flight: Flight,
    radii: Radii = .{},
    witness_grudge_ticks: u64 = 60,
    rumor_grudge_ticks: u64 = 50,
    warrant_priority: u16 = 10,
    currency_unit: []const u8 = "g",
    relations: Relations = .{},
    friends: []const FriendLink = &.{},
};

/// Complete immutable program data for one script-declared society. The compiler owns the
/// arrays; names and theme text point into the World's intern table.
pub const Declaration = struct {
    config: Config,

    pub fn deinit_owned(self: *Declaration, allocator: std.mem.Allocator) void {
        for (self.config.members) |member| {
            allocator.free(member.needs);
            allocator.free(member.routine.stops);
            allocator.free(member.owns);
            allocator.free(member.carries);
        }
        allocator.free(self.config.needs);
        allocator.free(self.config.members);
        allocator.free(self.config.friends);
        self.* = undefined;
    }
};

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

pub const ChronicleEntry = struct {
    tick: u64 = 0,
    category: ChronicleCategory = .work,
    message: [CHRONICLE_MESSAGE_LEN]u8 = [_]u8{0} ** CHRONICLE_MESSAGE_LEN,
    message_len: u8 = 0,

    pub fn get_message(self: *const ChronicleEntry) []const u8 {
        return self.message[0..self.message_len];
    }
};

/// Display log of emergent events. It is presentation, not state: it is not part of the world
/// snapshot, so a rewind leaves it as it was.
pub const Chronicle = struct {
    entries: [MAX_CHRONICLE_ENTRIES]ChronicleEntry = [_]ChronicleEntry{.{}} ** MAX_CHRONICLE_ENTRIES,
    count: usize = 0,

    pub fn log(self: *Chronicle, tick: u64, category: ChronicleCategory, text: []const u8) void {
        var entry = ChronicleEntry{ .tick = tick, .category = category };
        const len = @min(text.len, entry.message.len);
        @memcpy(entry.message[0..len], text[0..len]);
        entry.message_len = @intCast(len);

        if (self.count < MAX_CHRONICLE_ENTRIES) {
            self.entries[self.count] = entry;
            self.count += 1;
        } else {
            std.mem.copyForwards(ChronicleEntry, self.entries[0 .. MAX_CHRONICLE_ENTRIES - 1], self.entries[1..]);
            self.entries[MAX_CHRONICLE_ENTRIES - 1] = entry;
        }
    }

    /// Formats a line, truncating it to the entry size.
    pub fn logf(self: *Chronicle, tick: u64, category: ChronicleCategory, comptime fmt: []const u8, args: anytype) void {
        var buf: [CHRONICLE_MESSAGE_LEN]u8 = undefined;
        // On overflow bufPrint has filled the whole buffer before failing, so the full
        // buffer is the truncated line.
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch buf[0..];
        self.log(tick, category, msg);
    }

    pub fn latest(self: *const Chronicle) ?*const ChronicleEntry {
        return if (self.count == 0) null else &self.entries[self.count - 1];
    }
};

/// A need rule in pressure terms: pressure 0 is fully satisfied and `max` is worst, whatever
/// the need's direction. Thresholds are converted once at init so the systems compare one way.
const NeedRule = struct {
    relation: RelationKind,
    name: []const u8,
    worse: Worse,
    max: u32,
    rate: u32,
    resting_rate: u32,
    seek: u32,
    kind: union(enum) {
        stay: struct { at: WaypointId, restore: u32, until: u32, activity: Activity, unaware: bool, state: []const u8, verb: []const u8 },
        trade: struct { provider: ?usize, price: u32, relief: u32, floor: u32, critical: ?u32, theft_relief: u32, theft_floor: u32, item: []const u8 },
    },

    fn to_pressure(self: *const NeedRule, value: u32) u32 {
        return if (self.worse == .high) @min(value, self.max) else self.max -| value;
    }

    fn to_value(self: *const NeedRule, pressure: u32) u32 {
        return if (self.worse == .high) pressure else self.max -| pressure;
    }
};

const MemberState = struct {
    entity: EntityId,
    idle: Activity,
    broadcaster: bool,
    merchant: ?Merchant,
    rates: [MAX_NEEDS]u32,
    providers: [MAX_NEEDS]?usize,
    routine_activity: ?Activity,
    stops: [MAX_STOPS]WaypointId,
    stop_count: usize,
    period: u64,
    work: ?Work,
};

/// Interned relation ids.
pub const RelationIds = struct {
    currency: RelationKind,
    activity: RelationKind,
    tending: RelationKind,
    friend: RelationKind,
    rival: RelationKind,
    grudge: RelationKind,
    owns: RelationKind,
    carries: RelationKind,
    stolen_from: RelationKind,
    crime_scene: RelationKind,
    witnessed: RelationKind,
    knows_rumor: RelationKind,
    warrant_for: RelationKind,
    arrested: RelationKind,
};

pub const Society = struct {
    needs: [MAX_NEEDS]NeedRule,
    need_count: usize,
    members: [MAX_MEMBERS]MemberState,
    member_count: usize,
    enforcer: ?usize,
    holding: ?WaypointId,
    gathering: WaypointId,
    flight: Flight,
    radii: Radii,
    witness_grudge_ticks: u64,
    rumor_grudge_ticks: u64,
    warrant_priority: u16,
    currency_unit: []const u8,
    rel: RelationIds,
    chronicle: Chronicle = .{},

    /// Validates the config, interns the society's relations, and seeds each member's needs,
    /// currency, activity, and holdings as facts.
    pub fn init(world: *World, config: Config) !Society {
        try validate(config);

        var self = Society{
            .needs = undefined,
            .need_count = config.needs.len,
            .members = undefined,
            .member_count = config.members.len,
            .enforcer = config.enforcer,
            .holding = config.holding,
            .gathering = config.gathering,
            .flight = config.flight,
            .radii = config.radii,
            .witness_grudge_ticks = config.witness_grudge_ticks,
            .rumor_grudge_ticks = config.rumor_grudge_ticks,
            .warrant_priority = config.warrant_priority,
            .currency_unit = config.currency_unit,
            .rel = undefined,
        };

        // Needs are interned first, as properties (one scalar per member, D-007).
        for (config.needs, 0..) |need, i| {
            self.needs[i] = try compile_need(world, need);
        }
        const r = config.relations;
        self.rel = .{
            .currency = try world.intern_relation(r.currency, .property),
            .activity = try world.intern_relation(r.activity, .property),
            .friend = try world.intern_relation(r.friend, .set),
            .rival = try world.intern_relation(r.rival, .set),
            .grudge = try world.intern_relation(r.grudge, .set),
            .owns = try world.intern_relation(r.owns, .set),
            .carries = try world.intern_relation(r.carries, .set),
            .stolen_from = try world.intern_relation(r.stolen_from, .set),
            .crime_scene = try world.intern_relation(r.crime_scene, .set),
            .witnessed = try world.intern_relation(r.witnessed, .set),
            .knows_rumor = try world.intern_relation(r.knows_rumor, .set),
            .warrant_for = try world.intern_relation(r.warrant_for, .set),
            .arrested = try world.intern_relation(r.arrested, .set),
            // Which stay need a member is meeting. A fact, not a field, so rewind restores it.
            .tending = try world.intern_relation(r.tending, .property),
        };

        for (config.members, 0..) |m, mi| {
            var st = MemberState{
                .entity = m.entity,
                .idle = m.idle,
                .broadcaster = m.broadcaster,
                .merchant = m.merchant,
                .rates = undefined,
                .providers = undefined,
                .routine_activity = m.routine.activity,
                .stops = undefined,
                .stop_count = m.routine.stops.len,
                .period = m.routine.period,
                .work = m.routine.work,
            };
            for (m.needs, 0..) |mn, ni| {
                st.rates[ni] = mn.rate orelse self.needs[ni].rate;
                st.providers[ni] = switch (self.needs[ni].kind) {
                    .trade => |t| mn.provider orelse t.provider,
                    .stay => null,
                };
            }
            @memcpy(st.stops[0..m.routine.stops.len], m.routine.stops);
            self.members[mi] = st;

            for (m.needs, 0..) |mn, ni| try world.remember(m.entity, self.needs[ni].relation, mn.value, 0);
            try world.remember(m.entity, self.rel.currency, m.gold, 0);
            try world.remember(m.entity, self.rel.activity, @intFromEnum(m.idle), 0);
            for (m.owns) |e| try world.remember(m.entity, self.rel.owns, e.to_int(), 0);
            for (m.carries) |e| try world.remember(m.entity, self.rel.carries, e.to_int(), 0);
        }
        for (config.friends) |link| try self.befriend(world, link.a, link.b);
        return self;
    }

    fn compile_need(world: *World, need: Need) !NeedRule {
        var rule = NeedRule{
            .relation = try world.intern_relation(need.name, .property),
            .name = need.name,
            .worse = need.worse,
            .max = need.max,
            .rate = need.rate,
            .resting_rate = need.resting_rate,
            .seek = 0,
            .kind = undefined,
        };
        rule.seek = rule.to_pressure(need.seek);
        rule.kind = switch (need.satisfy) {
            .stay => |s| .{ .stay = .{
                .at = s.at,
                .restore = s.restore,
                .until = rule.to_pressure(s.until),
                .activity = s.activity,
                .unaware = s.unaware,
                .state = s.state,
                .verb = s.verb,
            } },
            .trade => |t| .{ .trade = .{
                .provider = t.provider,
                .price = t.price,
                .relief = t.relief,
                .floor = rule.to_pressure(t.floor),
                .critical = if (t.critical) |c| rule.to_pressure(c) else null,
                .theft_relief = t.theft_relief,
                .theft_floor = rule.to_pressure(t.theft_floor),
                .item = t.item,
            } },
        };
        return rule;
    }

    fn validate(config: Config) Error!void {
        const bad = Error.InvalidSocietyConfig;
        if (config.needs.len > MAX_NEEDS or config.members.len > MAX_MEMBERS) return bad;
        if (config.enforcer) |e| if (e >= config.members.len) return bad;
        if (config.flight.every == 0) return bad;
        for (config.needs) |need| switch (need.satisfy) {
            .trade => |t| if (t.provider) |p| try check_merchant(config, p),
            .stay => {},
        };
        for (config.members) |m| {
            if (m.needs.len != config.needs.len) return bad;
            if (m.routine.stops.len > MAX_STOPS or m.routine.period == 0) return bad;
            if (m.routine.work) |w| if (w.every == 0) return bad;
            if (m.routine.work) |w| if (w.restock and m.merchant == null) return bad;
            for (m.needs) |mn| if (mn.provider) |p| try check_merchant(config, p);
        }
    }

    fn check_merchant(config: Config, index: usize) Error!void {
        if (index >= config.members.len or config.members[index].merchant == null) return Error.InvalidSocietyConfig;
    }

    // ---------------------------------------------------------------------------------------
    // Queries and host controls
    // ---------------------------------------------------------------------------------------

    pub fn member_entity(self: *const Society, index: usize) EntityId {
        return self.members[index].entity;
    }

    pub fn member_index(self: *const Society, entity: EntityId) ?usize {
        for (self.members[0..self.member_count], 0..) |m, i| if (m.entity == entity) return i;
        return null;
    }

    pub fn need_index(self: *const Society, name: []const u8) ?usize {
        for (self.needs[0..self.need_count], 0..) |n, i| if (std.mem.eql(u8, n.name, name)) return i;
        return null;
    }

    pub fn need_relation(self: *const Society, need: usize) RelationKind {
        return self.needs[need].relation;
    }

    pub fn get_need(self: *const Society, world: *const World, entity: EntityId, need: usize) u32 {
        return world.get_property(entity, self.needs[need].relation) orelse 0;
    }

    pub fn set_need(self: *const Society, world: *World, entity: EntityId, need: usize, value: u32) !void {
        try world.remember(entity, self.needs[need].relation, @min(value, self.needs[need].max), 0);
    }

    pub fn get_gold(self: *const Society, world: *const World, entity: EntityId) u32 {
        return world.get_property(entity, self.rel.currency) orelse 0;
    }

    pub fn set_gold(self: *const Society, world: *World, entity: EntityId, gold: u32) !void {
        try world.remember(entity, self.rel.currency, gold, 0);
    }

    pub fn get_activity(self: *const Society, world: *const World, entity: EntityId) Activity {
        return Activity.from_int(world.get_property(entity, self.rel.activity) orelse 0);
    }

    /// Sets a member's activity from outside the systems, ending any stay in progress.
    pub fn set_activity(self: *const Society, world: *World, entity: EntityId, activity: Activity) !void {
        _ = world.forget(entity, self.rel.tending, null);
        try world.remember(entity, self.rel.activity, @intFromEnum(activity), 0);
    }

    pub fn befriend(self: *const Society, world: *World, a: EntityId, b: EntityId) !void {
        try world.remember(a, self.rel.friend, b.to_int(), 0);
        try world.remember(b, self.rel.friend, a.to_int(), 0);
    }

    /// True if two agents stand at the same waypoint, or are within `max_dist` of each other.
    pub fn are_colocated(spatial: *const SpatialSystem, a: EntityId, b: EntityId, max_dist: i32) bool {
        const agent_a = spatial.agents.get(a) orelse return false;
        const agent_b = spatial.agents.get(b) orelse return false;
        if (agent_a.current_wp == agent_b.current_wp and !agent_a.is_moving and !agent_b.is_moving) return true;
        const dx = agent_a.pos.x - agent_b.pos.x;
        const dy = agent_a.pos.y - agent_b.pos.y;
        return (dx * dx + dy * dy) <= (max_dist * max_dist);
    }

    /// Walks an agent toward `target` unless it is there or already heading there.
    /// Returns true only if the agent stands at `target`. An agent holding `Pursuing` belongs
    /// to its agenda (P33-02, D-056): society routines leave its walk alone, so the two never
    /// issue competing walk intents.
    pub fn walk_to(world: *const World, spatial: *SpatialSystem, entity: EntityId, target: WaypointId) !bool {
        if (spatial.agents.get(entity)) |agent| {
            if (agent.current_wp == target and !agent.is_moving) return true;
            if (world.lookup_relation(agency_mod.PURSUING_RELATION)) |pursuing| {
                if (world.has_fact(entity, pursuing, null)) return false;
            }
            if (agent.is_moving and agent.target_wp == target) return false;
            _ = try spatial.walk_to(entity, target);
        }
        return false;
    }

    fn near_waypoint(spatial: *const SpatialSystem, entity: EntityId, wp: WaypointId, radius: i32) bool {
        const agent = spatial.agents.get(entity) orelse return false;
        const node = spatial.graph.get_waypoint(wp) orelse return false;
        const dx = agent.pos.x - node.pos.x;
        const dy = agent.pos.y - node.pos.y;
        return (dx * dx + dy * dy) <= (radius * radius);
    }

    fn name_of(world: *const World, entity: EntityId) []const u8 {
        return world.get_entity_name(entity) orelse "someone";
    }

    fn waypoint_name(spatial: *const SpatialSystem, wp: WaypointId) []const u8 {
        return if (spatial.graph.get_waypoint(wp)) |w| w.name else "somewhere";
    }

    fn enforcer_entity(self: *const Society) ?EntityId {
        return if (self.enforcer) |e| self.members[e].entity else null;
    }

    /// Members meeting a stay need marked `unaware` cannot witness or hear rumors.
    fn is_unaware(self: *const Society, world: *const World, entity: EntityId) bool {
        const tending = world.get_property(entity, self.rel.tending) orelse return false;
        if (tending >= self.need_count) return false;
        return switch (self.needs[tending].kind) {
            .stay => |s| s.unaware,
            .trade => false,
        };
    }

    /// The goods taken in a member's first recorded theft, and the victim's roster index.
    fn stolen_goods(self: *const Society, world: *const World, thief: EntityId) ?struct { victim: EntityId, goods: EntityId } {
        const fact = world.find_first(thief, self.rel.stolen_from, null) orelse return null;
        const victim = EntityId.from_int(fact.object_or_value);
        const vi = self.member_index(victim) orelse return null;
        const merchant = self.members[vi].merchant orelse return null;
        return .{ .victim = victim, .goods = merchant.goods };
    }

    // ---------------------------------------------------------------------------------------
    // Systems
    // ---------------------------------------------------------------------------------------

    /// Runs one society tick. The host steps the VM (`host.tick`) first, so movement and
    /// script effects of this tick are visible to the systems. `vm` is optional: without it,
    /// warrants raise no fiber interrupt.
    pub fn step(self: *Society, world: *World, spatial: *SpatialSystem, vm: ?*VM) !void {
        try self.step_drives(world, spatial);
        try self.evaluate_witnesses(world, spatial);
        try self.propagate_rumors(world, spatial);
        try self.evaluate_justice(world, spatial, vm);
    }

    /// Drives. Each member takes the first applicable branch, in this priority order:
    /// held (arrested), staying, then needs decay, enforcer on duty, start a stay, steal in
    /// desperation, flee, buy relief, broadcast news, routine. Within a branch, needs are
    /// considered in config order.
    pub fn step_drives(self: *Society, world: *World, spatial: *SpatialSystem) !void {
        const tick = world.current_tick;
        const enforcer = self.enforcer_entity();

        for (self.members[0..self.member_count], 0..) |*m, mi| {
            const npc = m.entity;

            if (world.has_fact(npc, self.rel.arrested, null)) {
                _ = world.forget(npc, self.rel.tending, null);
                try world.remember(npc, self.rel.activity, @intFromEnum(Activity.arrested), 0);
                if (self.holding) |h| _ = try walk_to(world, spatial, npc, h);
                continue;
            }

            var pressure: [MAX_NEEDS]u32 = undefined;
            for (self.needs[0..self.need_count], 0..) |*n, ni| pressure[ni] = n.to_pressure(self.get_need(world, npc, ni));
            var gold = self.get_gold(world, npc);
            const cur_act = self.get_activity(world, npc);

            // Staying: regain the tended need at its place; other needs drift at their resting rate.
            if (world.get_property(npc, self.rel.tending)) |tended| {
                if (tended < self.need_count and self.needs[tended].kind == .stay) {
                    const stay = self.needs[tended].kind.stay;
                    if (try walk_to(world, spatial, npc, stay.at)) {
                        for (self.needs[0..self.need_count], 0..) |*n, ni| {
                            pressure[ni] = if (ni == tended)
                                pressure[ni] -| stay.restore
                            else
                                @min(n.max, pressure[ni] + n.resting_rate);
                            try world.remember(npc, n.relation, n.to_value(pressure[ni]), 0);
                        }
                        if (pressure[tended] <= stay.until) {
                            _ = world.forget(npc, self.rel.tending, null);
                            try world.remember(npc, self.rel.activity, @intFromEnum(m.idle), 0);
                        }
                    }
                    continue;
                }
            }

            // Decay.
            for (self.needs[0..self.need_count], 0..) |*n, ni| {
                pressure[ni] = @min(n.max, pressure[ni] + m.rates[ni]);
                try world.remember(npc, n.relation, n.to_value(pressure[ni]), 0);
            }

            // An enforcer holding a warrant ignores routine drives until the arrest.
            if (enforcer != null and npc == enforcer.? and world.has_fact(npc, self.rel.warrant_for, null)) continue;

            // Start a stay.
            if (cur_act != .stealing and cur_act != .fleeing) {
                var started = false;
                for (self.needs[0..self.need_count], 0..) |*n, ni| {
                    if (n.kind != .stay or pressure[ni] < n.seek) continue;
                    const stay = n.kind.stay;
                    try world.remember(npc, self.rel.activity, @intFromEnum(stay.activity), 0);
                    try world.remember(npc, self.rel.tending, @intCast(ni), 0);
                    _ = try walk_to(world, spatial, npc, stay.at);
                    self.chronicle.logf(tick, .work, "{s} is {s} ({s} {d}) and heads to {s} to {s}.", .{
                        name_of(world, npc), stay.state, n.name, n.to_value(pressure[ni]), waypoint_name(spatial, stay.at), stay.verb,
                    });
                    started = true;
                    break;
                }
                if (started) continue;
            }

            // Desperation: a critical trade need the member cannot pay for.
            if (try self.try_theft(world, spatial, m, mi, &pressure, gold, tick)) continue;

            if (cur_act == .fleeing) {
                if ((try walk_to(world, spatial, npc, self.flight.to)) and tick % self.flight.every == 0) {
                    if (self.flight.then) |then| _ = try walk_to(world, spatial, npc, then);
                }
                continue;
            }

            // Buy relief from a merchant.
            var traded = false;
            for (self.needs[0..self.need_count], 0..) |*n, ni| {
                if (n.kind != .trade) continue;
                const trade = n.kind.trade;
                const pi = m.providers[ni] orelse continue;
                if (pressure[ni] < n.seek or gold < trade.price) continue;
                const provider = &self.members[pi];
                try world.remember(npc, self.rel.activity, @intFromEnum(Activity.eating), 0);
                if (try walk_to(world, spatial, npc, provider.merchant.?.post)) {
                    pressure[ni] = if (pressure[ni] > trade.relief) pressure[ni] - trade.relief else trade.floor;
                    try world.remember(npc, n.relation, n.to_value(pressure[ni]), 0);
                    if (pi != mi) {
                        gold -= trade.price;
                        try self.set_gold(world, npc, gold);
                        try self.set_gold(world, provider.entity, self.get_gold(world, provider.entity) + trade.price);
                        try self.befriend(world, npc, provider.entity);
                        self.chronicle.logf(tick, .trade, "{s} bought {s} from {s} for {d}{s}.", .{
                            name_of(world, npc), trade.item, name_of(world, provider.entity), trade.price, self.currency_unit,
                        });
                    }
                    try world.remember(npc, self.rel.activity, @intFromEnum(m.idle), 0);
                }
                traded = true;
                break;
            }
            if (traded) continue;

            // A broadcaster with news the enforcer lacks goes looking for the enforcer.
            if (m.broadcaster and enforcer != null and world.has_fact(npc, self.rel.knows_rumor, null) and
                !world.has_fact(enforcer.?, self.rel.knows_rumor, null))
            {
                try world.remember(npc, self.rel.activity, @intFromEnum(Activity.socializing), 0);
                const dest = if (spatial.agents.get(enforcer.?)) |a| a.current_wp else self.gathering;
                _ = try walk_to(world, spatial, npc, dest);
                continue;
            }

            try self.follow_routine(world, spatial, m, gold, tick);
        }
    }

    fn try_theft(
        self: *Society,
        world: *World,
        spatial: *SpatialSystem,
        m: *const MemberState,
        mi: usize,
        pressure: *[MAX_NEEDS]u32,
        gold: u32,
        tick: u64,
    ) !bool {
        const npc = m.entity;
        for (self.needs[0..self.need_count], 0..) |*n, ni| {
            if (n.kind != .trade) continue;
            const trade = n.kind.trade;
            const critical = trade.critical orelse continue;
            const pi = m.providers[ni] orelse continue;
            if (pi == mi) continue;
            const victim = &self.members[pi];
            if (pressure[ni] < critical or gold >= trade.price) continue;
            if (world.has_fact(npc, self.rel.stolen_from, victim.entity.to_int())) continue;

            const merchant = victim.merchant.?;
            try world.remember(npc, self.rel.activity, @intFromEnum(Activity.stealing), 0);
            if (try walk_to(world, spatial, npc, merchant.post)) {
                try world.remember(npc, self.rel.stolen_from, victim.entity.to_int(), 0);
                try world.remember(npc, self.rel.crime_scene, merchant.post, 0);
                try world.remember(npc, self.rel.carries, merchant.goods.to_int(), 0);
                _ = world.forget(victim.entity, self.rel.carries, merchant.goods.to_int());

                pressure[ni] = if (pressure[ni] > trade.theft_relief) pressure[ni] - trade.theft_relief else trade.theft_floor;
                try world.remember(npc, n.relation, n.to_value(pressure[ni]), 0);
                try world.remember(npc, self.rel.activity, @intFromEnum(Activity.fleeing), 0);

                self.chronicle.logf(tick, .crime, "{s} ({s}>={d}, {s}={d}) stole {s} from {s}!", .{
                    name_of(world, npc), n.name,                         n.to_value(critical),          world.get_relation_meta(self.rel.currency).?.name,
                    gold,                name_of(world, merchant.goods), name_of(world, victim.entity),
                });

                // Anyone present at the moment of the crime sees it.
                try self.evaluate_witnesses(world, spatial);
                _ = try walk_to(world, spatial, npc, self.flight.to);
            }
            return true;
        }
        return false;
    }

    fn follow_routine(self: *Society, world: *World, spatial: *SpatialSystem, m: *const MemberState, gold: u32, tick: u64) !void {
        if (m.routine_activity) |a| try world.remember(m.entity, self.rel.activity, @intFromEnum(a), 0);
        if (m.stop_count == 0) return;
        const dest = m.stops[@intCast((tick / m.period) % m.stop_count)];
        if (!(try walk_to(world, spatial, m.entity, dest))) return;
        const work = m.work orelse return;
        if (work.at != dest or tick % work.every != 0) return;
        if (work.restock) {
            const goods = m.merchant.?.goods.to_int();
            try world.remember(m.entity, self.rel.owns, goods, 0);
            try world.remember(m.entity, self.rel.carries, goods, 0);
        }
        try self.set_gold(world, m.entity, gold + work.earn);
    }

    /// Witnesses. A member who is aware and near a culprit's crime scene while the culprit is
    /// still there learns of the crime, holds a grudge, and heads to the gathering place.
    pub fn evaluate_witnesses(self: *Society, world: *World, spatial: *SpatialSystem) !void {
        const tick = world.current_tick;
        const enforcer = self.enforcer_entity();

        for (self.members[0..self.member_count]) |*t| {
            const thief = t.entity;
            if (!world.has_fact(thief, self.rel.stolen_from, null)) continue;
            if (world.has_fact(thief, self.rel.arrested, null)) continue;
            const scene_fact = world.find_first(thief, self.rel.crime_scene, null) orelse continue;
            const scene: WaypointId = @intCast(scene_fact.object_or_value);
            const goods = if (self.stolen_goods(world, thief)) |s| name_of(world, s.goods) else "goods";

            for (self.members[0..self.member_count]) |*w| {
                const witness = w.entity;
                if (witness == thief) continue;
                if (world.has_fact(witness, self.rel.witnessed, thief.to_int())) continue;
                if (self.is_unaware(world, witness)) continue;

                const at_scene = blk: {
                    const agent = spatial.agents.get(witness) orelse break :blk false;
                    if (agent.current_wp == scene and !agent.is_moving) break :blk true;
                    break :blk near_waypoint(spatial, witness, scene, self.radii.witness);
                };
                if (!at_scene or !near_waypoint(spatial, thief, scene, self.radii.culprit)) continue;

                try world.remember(witness, self.rel.witnessed, thief.to_int(), 0);
                try world.remember(witness, self.rel.knows_rumor, thief.to_int(), 0);
                try world.remember(witness, self.rel.grudge, thief.to_int(), self.witness_grudge_ticks);
                try world.remember(witness, self.rel.rival, thief.to_int(), 0);
                self.chronicle.logf(tick, .witness, "{s} witnessed {s} stealing {s} and formed a {s}!", .{
                    name_of(world, witness), name_of(world, thief), goods, world.get_relation_meta(self.rel.grudge).?.name,
                });

                if (enforcer == null or witness != enforcer.?) _ = try walk_to(world, spatial, witness, self.gathering);
            }
        }
    }

    /// Rumors. Spread one hop per tick: only members who knew at the start of the tick speak.
    /// A co-located, aware listener learns if the two are friends, the speaker is a witness or
    /// a broadcaster, or the listener is the enforcer.
    pub fn propagate_rumors(self: *Society, world: *World, spatial: *SpatialSystem) !void {
        const tick = world.current_tick;
        const enforcer = self.enforcer_entity();

        for (self.members[0..self.member_count]) |*t| {
            const thief = t.entity;
            if (!world.has_fact(thief, self.rel.stolen_from, null)) continue;
            if (world.has_fact(thief, self.rel.arrested, null)) continue;

            var speakers: [MAX_MEMBERS]usize = undefined;
            var speaker_count: usize = 0;
            for (self.members[0..self.member_count], 0..) |*s, si| {
                if (s.entity != thief and world.has_fact(s.entity, self.rel.knows_rumor, thief.to_int())) {
                    speakers[speaker_count] = si;
                    speaker_count += 1;
                }
            }

            for (speakers[0..speaker_count]) |si| {
                const speaker = self.members[si].entity;
                if (self.is_unaware(world, speaker)) continue;

                const enforcer_knows = if (enforcer) |e| world.has_fact(e, self.rel.knows_rumor, thief.to_int()) else false;
                if (!enforcer_knows and (enforcer == null or speaker != enforcer.?)) {
                    _ = try walk_to(world, spatial, speaker, self.gathering);
                }

                for (self.members[0..self.member_count]) |*l| {
                    const listener = l.entity;
                    if (listener == speaker or listener == thief) continue;
                    if (world.has_fact(listener, self.rel.knows_rumor, thief.to_int())) continue;
                    if (self.is_unaware(world, listener)) continue;
                    if (!are_colocated(spatial, speaker, listener, self.radii.rumor)) continue;

                    const friends = world.has_fact(speaker, self.rel.friend, listener.to_int()) or
                        world.has_fact(listener, self.rel.friend, speaker.to_int());
                    const is_witness = world.has_fact(speaker, self.rel.witnessed, thief.to_int());
                    const to_enforcer = enforcer != null and listener == enforcer.?;
                    if (!(friends or is_witness or self.members[si].broadcaster or to_enforcer)) continue;

                    try world.remember(listener, self.rel.knows_rumor, thief.to_int(), 0);
                    try world.remember(listener, self.rel.grudge, thief.to_int(), self.rumor_grudge_ticks);
                    self.chronicle.logf(tick, .rumor, "{s} spread rumor of {s}'s theft to {s}!", .{
                        name_of(world, speaker), name_of(world, thief), name_of(world, listener),
                    });
                }
            }
        }
    }

    /// Justice. For each member the enforcer has heard about: issue a warrant (with a priority
    /// interrupt on the enforcer's fiber), pursue, and on contact arrest, recover any stolen
    /// goods, and escort the culprit to the holding place.
    pub fn evaluate_justice(self: *Society, world: *World, spatial: *SpatialSystem, vm: ?*VM) !void {
        const tick = world.current_tick;
        const enforcer = self.enforcer_entity() orelse return;
        const enforcer_idle = self.members[self.enforcer.?].idle;

        for (self.members[0..self.member_count]) |*t| {
            const thief = t.entity;
            if (thief == enforcer) continue;
            if (!world.has_fact(enforcer, self.rel.knows_rumor, thief.to_int())) continue;
            if (world.has_fact(thief, self.rel.arrested, null)) continue;

            if (!world.has_fact(enforcer, self.rel.warrant_for, thief.to_int())) {
                try world.remember(enforcer, self.rel.warrant_for, thief.to_int(), 0);
                try world.remember(enforcer, self.rel.activity, @intFromEnum(Activity.investigating), 0);
                if (vm) |v| _ = try v.interrupt_entity_priority(enforcer, 0, self.warrant_priority);
                self.chronicle.logf(tick, .justice, "{s} heard rumor and issued {s}({s}, {s})!", .{
                    name_of(world, enforcer), world.get_relation_meta(self.rel.warrant_for).?.name, name_of(world, enforcer), name_of(world, thief),
                });
            }

            try world.remember(enforcer, self.rel.activity, @intFromEnum(Activity.investigating), 0);
            if (spatial.agents.get(thief)) |a| _ = try walk_to(world, spatial, enforcer, a.current_wp);

            if (!are_colocated(spatial, enforcer, thief, self.radii.arrest)) continue;

            try world.remember(thief, self.rel.arrested, enforcer.to_int(), 0);
            _ = world.forget(enforcer, self.rel.warrant_for, thief.to_int());
            _ = world.forget(thief, self.rel.tending, null);
            try world.remember(thief, self.rel.activity, @intFromEnum(Activity.arrested), 0);
            try world.remember(enforcer, self.rel.activity, @intFromEnum(enforcer_idle), 0);

            const stolen = self.stolen_goods(world, thief);
            if (stolen) |s| {
                _ = world.forget(thief, self.rel.carries, s.goods.to_int());
                try world.remember(s.victim, self.rel.owns, s.goods.to_int(), 0);
                try world.remember(s.victim, self.rel.carries, s.goods.to_int(), 0);
            }
            if (self.holding) |h| {
                _ = try walk_to(world, spatial, thief, h);
                _ = try walk_to(world, spatial, enforcer, h);
            }

            if (stolen) |s| {
                self.chronicle.logf(tick, .arrest, "{s} arrested {s}, recovered {s}, and jailed offender!", .{
                    name_of(world, enforcer), name_of(world, thief), name_of(world, s.goods),
                });
            } else {
                self.chronicle.logf(tick, .arrest, "{s} arrested {s} and jailed offender!", .{ name_of(world, enforcer), name_of(world, thief) });
            }
        }
    }
};

// =============================================================================================
// Tests. A second roster with different needs, places, and names runs on the same module.
// =============================================================================================

const testing = std.testing;

const Outpost = struct {
    world: World,
    spatial: SpatialSystem,
    society: Society,
    marshal: EntityId,
    cook: EntityId,
    medic: EntityId,
    crier: EntityId,
    stray: EntityId,
    ration: EntityId,
    canteen: WaypointId,
    plaza: WaypointId,
    bunks: WaypointId,
    brig: WaypointId,
    ridge: WaypointId,

    fn deinit(self: *Outpost) void {
        self.spatial.deinit();
        self.world.deinit();
    }
};

/// Three needs: Thirst (traded at the canteen, worse high), Stamina (rested at the bunks, worse
/// low), and Boredom (traded with the medic, worse high, no theft).
fn make_outpost(allocator: std.mem.Allocator) !Outpost {
    var world = try World.init(allocator, 1 << 20);
    errdefer world.deinit();
    var spatial = SpatialSystem.init(allocator);
    errdefer spatial.deinit();

    const room = try world.intern_entity("Outpost");
    const marshal = try world.intern_entity("Marshal");
    const cook = try world.intern_entity("Cook");
    const medic = try world.intern_entity("Medic");
    const crier = try world.intern_entity("Crier");
    const stray = try world.intern_entity("Stray");
    const ration = try world.intern_entity("Ration");
    const tonic = try world.intern_entity("Tonic");

    const canteen = try spatial.graph.add_waypoint(room, 0, 0, "Canteen");
    const plaza = try spatial.graph.add_waypoint(room, 10, 0, "Plaza");
    const bunks = try spatial.graph.add_waypoint(room, 10, 10, "Bunks");
    const brig = try spatial.graph.add_waypoint(room, 20, 0, "Brig");
    const ridge = try spatial.graph.add_waypoint(room, 0, 10, "Ridge");
    try spatial.graph.connect(canteen, plaza, null);
    try spatial.graph.connect(plaza, bunks, null);
    try spatial.graph.connect(plaza, brig, null);
    try spatial.graph.connect(canteen, ridge, null);
    try spatial.graph.connect(ridge, bunks, null);

    try spatial.register_entity(marshal, brig, 12);
    try spatial.register_entity(cook, canteen, 10);
    try spatial.register_entity(medic, plaza, 10);
    try spatial.register_entity(crier, plaza, 12);
    try spatial.register_entity(stray, plaza, 10);

    const needs = [_]Need{
        .{ .name = "Thirst", .rate = 2, .seek = 50, .satisfy = .{ .trade = .{
            .provider = 1,
            .price = 3,
            .relief = 40,
            .floor = 5,
            .critical = 70,
            .theft_relief = 50,
            .theft_floor = 5,
            .item = "a canteen cup",
        } } },
        .{ .name = "Stamina", .worse = .low, .rate = 1, .seek = 10, .satisfy = .{ .stay = .{
            .at = bunks,
            .restore = 20,
            .until = 80,
            .state = "spent",
            .verb = "rest",
        } } },
        .{ .name = "Boredom", .rate = 1, .seek = 90, .satisfy = .{ .trade = .{ .provider = 2, .price = 1, .relief = 50 } } },
    };
    const members = [_]Member{
        .{ .entity = marshal, .needs = &.{ .{ .value = 10 }, .{ .value = 90 }, .{ .value = 0 } }, .gold = 20, .idle = .patrolling, .routine = .{ .activity = .patrolling, .stops = &.{ plaza, brig }, .period = 3 } },
        .{ .entity = cook, .needs = &.{ .{ .value = 10 }, .{ .value = 90 }, .{ .value = 0 } }, .gold = 10, .merchant = .{ .post = canteen, .goods = ration }, .carries = &.{ration}, .routine = .{ .activity = .working, .stops = &.{canteen}, .work = .{ .at = canteen, .every = 3, .earn = 1, .restock = true } } },
        .{ .entity = medic, .needs = &.{ .{ .value = 10 }, .{ .value = 90 }, .{ .value = 0 } }, .gold = 10, .merchant = .{ .post = plaza, .goods = tonic }, .routine = .{ .activity = .working, .stops = &.{plaza} } },
        .{ .entity = crier, .needs = &.{ .{ .value = 10 }, .{ .value = 90 }, .{ .value = 0 } }, .gold = 10, .idle = .socializing, .broadcaster = true, .routine = .{ .stops = &.{ canteen, plaza }, .period = 2 } },
        .{ .entity = stray, .needs = &.{ .{ .value = 60, .rate = 3 }, .{ .value = 90 }, .{ .value = 0 } }, .gold = 0, .idle = .socializing, .routine = .{ .stops = &.{plaza} } },
    };

    const society = try Society.init(&world, .{
        .needs = &needs,
        .members = &members,
        .enforcer = 0,
        .holding = brig,
        .gathering = plaza,
        .flight = .{ .to = ridge, .then = bunks, .every = 3 },
        .currency_unit = " chits",
        .relations = .{ .currency = "Chits" },
    });
    try society.befriend(&world, cook, crier);
    try society.befriend(&world, medic, marshal);

    return .{
        .world = world,
        .spatial = spatial,
        .society = society,
        .marshal = marshal,
        .cook = cook,
        .medic = medic,
        .crier = crier,
        .stray = stray,
        .ration = ration,
        .canteen = canteen,
        .plaza = plaza,
        .bunks = bunks,
        .brig = brig,
        .ridge = ridge,
    };
}

fn step_outpost(o: *Outpost) !void {
    _ = o.world.step_tick();
    o.spatial.step_tick();
    try o.society.step(&o.world, &o.spatial, null);
}

test "P32-05: society seeds needs, currency, and activity from config" {
    var o = try make_outpost(testing.allocator);
    defer o.deinit();
    const thirst = o.society.need_index("Thirst").?;
    const stamina = o.society.need_index("Stamina").?;
    try testing.expectEqual(@as(u32, 60), o.society.get_need(&o.world, o.stray, thirst));
    try testing.expectEqual(@as(u32, 90), o.society.get_need(&o.world, o.cook, stamina));
    try testing.expectEqual(@as(u32, 20), o.society.get_gold(&o.world, o.marshal));
    try testing.expectEqual(Activity.socializing, o.society.get_activity(&o.world, o.crier));
    try testing.expect(o.world.lookup_relation("Chits") != null);
    try testing.expect(o.world.has_fact(o.cook, o.society.rel.carries, o.ration.to_int()));
}

test "P32-05: worse-low need decays, starts a stay, and recovers to idle" {
    var o = try make_outpost(testing.allocator);
    defer o.deinit();
    const stamina = o.society.need_index("Stamina").?;
    try o.society.set_need(&o.world, o.medic, stamina, 11);
    try step_outpost(&o);
    try testing.expectEqual(@as(u32, 10), o.society.get_need(&o.world, o.medic, stamina));
    try testing.expectEqual(Activity.sleeping, o.society.get_activity(&o.world, o.medic));
    try testing.expectEqualStrings("Medic is spent (Stamina 10) and heads to Bunks to rest.", o.society.chronicle.latest().?.get_message());

    var i: usize = 0;
    while (i < 12) : (i += 1) try step_outpost(&o);
    try testing.expect(o.society.get_need(&o.world, o.medic, stamina) >= 80);
    try testing.expectEqual(Activity.working, o.society.get_activity(&o.world, o.medic));
    try testing.expect(o.world.get_property(o.medic, o.society.rel.tending) == null);
}

test "P32-05: trade pays the provider and befriends; the provider's own need costs nothing" {
    var o = try make_outpost(testing.allocator);
    defer o.deinit();
    const thirst = o.society.need_index("Thirst").?;
    try o.society.set_need(&o.world, o.medic, thirst, 55);
    try o.society.set_need(&o.world, o.cook, thirst, 55);
    var i: usize = 0;
    while (i < 6) : (i += 1) try step_outpost(&o);
    try testing.expect(o.society.get_need(&o.world, o.medic, thirst) < 30);
    try testing.expectEqual(@as(u32, 7), o.society.get_gold(&o.world, o.medic));
    try testing.expect(o.world.has_fact(o.medic, o.society.rel.friend, o.cook.to_int()));
    try testing.expect(o.society.get_need(&o.world, o.cook, thirst) < 30);
}

test "P32-05: second roster runs the full theft, witness, rumor, and arrest cascade" {
    var o = try make_outpost(testing.allocator);
    defer o.deinit();
    const rel = o.society.rel;
    var saw_theft = false;
    var saw_witness = false;
    var saw_warrant = false;
    var i: usize = 0;
    while (i < 60) : (i += 1) {
        try step_outpost(&o);
        if (o.world.has_fact(o.stray, rel.stolen_from, o.cook.to_int())) saw_theft = true;
        if (o.world.has_fact(null, rel.witnessed, o.stray.to_int())) saw_witness = true;
        if (o.world.has_fact(o.marshal, rel.warrant_for, o.stray.to_int())) saw_warrant = true;
        if (o.world.has_fact(o.stray, rel.arrested, o.marshal.to_int())) break;
    }
    try testing.expect(saw_theft);
    try testing.expect(saw_witness);
    try testing.expect(saw_warrant);
    try testing.expect(o.world.has_fact(o.stray, rel.arrested, o.marshal.to_int()));
    try testing.expectEqual(Activity.arrested, o.society.get_activity(&o.world, o.stray));
    try testing.expect(o.world.has_fact(o.cook, rel.carries, o.ration.to_int()));
    try testing.expect(!o.world.has_fact(o.stray, rel.carries, o.ration.to_int()));

    var found_line = false;
    for (o.society.chronicle.entries[0..o.society.chronicle.count]) |*e| {
        if (std.mem.eql(u8, e.get_message(), "Marshal arrested Stray, recovered Ration, and jailed offender!")) found_line = true;
    }
    try testing.expect(found_line);
}

test "P32-05: society state lives in facts, so a snapshot restore rewinds it" {
    var o = try make_outpost(testing.allocator);
    defer o.deinit();
    var snap = std.ArrayList(u8).init(testing.allocator);
    defer snap.deinit();
    try o.world.save_state(snap.writer());
    const stamina = o.society.need_index("Stamina").?;
    try o.society.set_need(&o.world, o.medic, stamina, 5);
    try step_outpost(&o);
    try testing.expect(o.world.get_property(o.medic, o.society.rel.tending) != null);
    var fbs = std.io.fixedBufferStream(snap.items);
    try o.world.restore_state(fbs.reader());
    try testing.expect(o.world.get_property(o.medic, o.society.rel.tending) == null);
    try testing.expectEqual(@as(u32, 90), o.society.get_need(&o.world, o.medic, stamina));
}

test "P32-05: invalid configs are refused" {
    var world = try World.init(testing.allocator, 1 << 20);
    defer world.deinit();
    const e = try world.intern_entity("Someone");
    const needs = [_]Need{.{ .name = "Thirst", .rate = 1, .seek = 50, .satisfy = .{ .trade = .{ .provider = 0, .price = 1, .relief = 10 } } }};
    // Provider 0 is not a merchant.
    try testing.expectError(Error.InvalidSocietyConfig, Society.init(&world, .{
        .needs = &needs,
        .members = &.{.{ .entity = e, .needs = &.{.{ .value = 0 }} }},
        .gathering = 1,
        .flight = .{ .to = 1 },
    }));
    // Member need list not aligned with the config's needs.
    try testing.expectError(Error.InvalidSocietyConfig, Society.init(&world, .{
        .needs = &.{},
        .members = &.{.{ .entity = e, .needs = &.{.{ .value = 0 }} }},
        .gathering = 1,
        .flight = .{ .to = 1 },
    }));
}

test "P33-02: society routines do not move an actor that is pursuing an agenda" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    const room = try world.intern_entity("SocietyGuardRoom");
    const home = try spatial.graph.add_waypoint(room, 0, 0, "SocietyGuardHome");
    const work = try spatial.graph.add_waypoint(room, 10, 0, "SocietyGuardWork");
    try spatial.graph.connect(home, work, null);
    const npc = try world.intern_entity("SocietyGuardNpc");
    try spatial.register_entity(npc, home, 5);

    const pursuing = try world.intern_relation(agency_mod.PURSUING_RELATION, .set);
    try world.remember(npc, pursuing, 0, 0);
    try testing.expect(!(try Society.walk_to(&world, &spatial, npc, work)));
    try testing.expect(!spatial.is_moving(npc));
    // Standing at the destination still counts as arrived.
    try testing.expect(try Society.walk_to(&world, &spatial, npc, home));

    _ = world.forget(npc, pursuing, null);
    _ = try Society.walk_to(&world, &spatial, npc, work);
    try testing.expect(spatial.is_moving(npc));
}
