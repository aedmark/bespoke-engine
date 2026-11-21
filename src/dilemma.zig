//! Dilemmas: a character weighs one value axis against another and acts by tier (P45-03, D-146).
//!
//! A `dilemma` names an actor, a cue, trigger lines (the decision shape, D-137), an axis and a
//! counter-axis (P45-01), lean lines read from world facts, and one authored line and action per
//! tier. When the trigger rises the engine computes
//!
//!   delta = value(axis) - value(counter-axis) + leans that hold
//!
//! and picks a tier from fixed, mirrored boundaries: 7 or more is strong toward the axis, 3 to 6
//! moderate, -2 to 2 neutral, and the same toward the counter-axis below zero. The difference,
//! not the sum, is the arithmetic: a low counter-value strengthens the lean toward the axis. A
//! missing value counts as 0 for weighing only; no fact is written.
//!
//! The actor speaks the tier's line, the engine records `Chose(Dilemma, Action)`, and the cue
//! fires with the actor and the action. A neutral result means "show me more": the dilemma waits
//! in `AwaitsEvidence`, and each new `Presented(Actor, Evidence)` fact (P44-03) weighs it again,
//! so evidence that turns a lean line on can move it out of neutral. All lifecycle state is
//! World facts, so save, rewind, and branch restore need no dilemma snapshot:
//!   DilemmaState(Dilemma, Idle | Done | AwaitsEvidence)   property
//!   EvidenceSeen(Dilemma, n)                               property, the Presented count weighed
//!   Chose(Dilemma, Action)                                 set fact, cleared on re-arm or re-weigh
//! Weighing reads facts only and draws no random number, so a replay makes the same choices.
//!
//! Drift (P45-04, D-148) is how outcomes change a character over a long game. A dilemma's
//! `drifts N toward|away from <Axis> when <Fact>` line adds N points, signed, to the actor's
//! accumulator on that axis each time its fact rises after the dilemma has first been weighed.
//! Every 5 points move the value one step, and one dilemma can move each axis at most 2 steps
//! over the whole game; points past the cap, or a step past -10 or +10, are discarded rather
//! than banked. Everything is an integer fact, so save, rewind, branch restore, and replay
//! reproduce drift exactly:
//!   <Axis> drift(Actor, points)        property, the signed accumulator, -4 to 4 between steps
//!   <Axis> drift steps(Dilemma, n)     property, the steps this dilemma has spent on the axis
//!   DriftHolding(Dilemma, mask)        property, which drift lines held last tick (edge state)
//!   DilemmaWeighed(Dilemma)            state, set at the first weighing and never cleared
//! The generated relation names contain a space, which no script name can, so they never
//! collide with an author's relation.
//!
//! Persuasion (P45-05, D-149): `appeals N to <Axis>` lines name the values the player may appeal
//! to and how far each moves the delta. `host.appeal` records `PendingAppeal(Dilemma, Axis)`;
//! the next weighing adds that line's points and forgets the appeal, and an appeal made while
//! the dilemma waits in neutral weighs it again, as evidence does. Values are learned by
//! watching: a weighing that lands outside neutral teaches everyone in the actor's room the axis
//! it leaned toward, as `Knows(Witness, <Axis> of <Actor>)` (`value.known_value`).

const std = @import("std");
const world_mod = @import("world.zig");
const decision_mod = @import("decision.zig");
const value_mod = @import("value.zig");
const spatial_mod = @import("spatial.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const Clause = decision_mod.Clause;

pub const MAX_DILEMMAS: usize = 32;
pub const MAX_CLAUSES: usize = decision_mod.MAX_CLAUSES;
pub const MAX_LEANS: usize = 8;
/// One lean line's magnitude, the width of half an axis.
pub const MAX_LEAN: u16 = 10;
/// Drift lines per dilemma; their edge state is one bit each in `DriftHolding`.
pub const MAX_DRIFTS: usize = 8;
pub const MAX_DRIFT: u16 = 10;
/// Points that move a value one step, and the steps one dilemma may move one axis (D-148).
pub const DRIFT_THRESHOLD: i32 = 5;
pub const DRIFT_STEPS_PER_DILEMMA: u32 = 2;
pub const HOLDING_RELATION = "DriftHolding";
pub const PENDING_APPEAL_RELATION = "PendingAppeal";
pub const KNOWS_RELATION = "Knows";
/// Appeal lines per dilemma: the values a player may appeal to (D-149, D-150).
pub const MAX_APPEALS: usize = 4;
pub const MAX_APPEAL: u16 = 10;
pub const WEIGHED_RELATION = "DilemmaWeighed";
/// Tier boundaries, mirrored around zero (D-146).
pub const STRONG_AT: i32 = 7;
pub const MODERATE_AT: i32 = 3;

pub const STATE_RELATION = "DilemmaState";
pub const SEEN_RELATION = "EvidenceSeen";
pub const PRESENTED_RELATION = "Presented";
pub const CHOSE_RELATION = decision_mod.CHOSE_RELATION;
pub const STAGE_NAMES = [_][]const u8{ "Idle", "Done", "AwaitsEvidence" };

pub const Stage = enum(u8) { idle = 0, done = 1, awaits_evidence = 2 };

/// The five tiers, in the order a script lists them from the axis to the counter-axis.
pub const Tier = enum(u8) {
    strong_axis = 0,
    moderate_axis = 1,
    neutral = 2,
    moderate_counter = 3,
    strong_counter = 4,
};
pub const TIER_COUNT = 5;

pub const Error = error{InvalidDilemma};

/// One lean line: `points` toward the axis (positive) or the counter-axis (negative) when the
/// clause holds, or when it does not for an `unless` line.
pub const Lean = struct {
    points: i32,
    clause: Clause,
};

/// One drift line: `points` toward the axis (positive) or away from it (negative) each time the
/// clause rises. `accumulator` and `spent` are the generated relations for that axis; see
/// `drift_relations`.
pub const Drift = struct {
    axis: RelationKind,
    points: i32,
    clause: Clause,
    accumulator: RelationKind,
    spent: RelationKind,
};

/// One appeal line: an appeal to the value `axis` adds `points` to the next weighing's delta,
/// positive toward the dilemma's axis and negative toward its counter-axis; `entity` is the
/// value's entity, which the appeal names. The value may be any declared axis (D-150).
pub const Appeal = struct {
    axis: RelationKind,
    entity: EntityId,
    points: i32,
};

/// Interns the two drift relations of an axis: `<Axis> drift` on the character and
/// `<Axis> drift steps` on the dilemma. Both are properties, so a write replaces the row.
pub fn drift_relations(world: *World, axis: RelationKind) !struct { accumulator: RelationKind, spent: RelationKind } {
    const name = (world.get_relation_meta(axis) orelse return Error.InvalidDilemma).name;
    var buf: [96]u8 = undefined;
    const acc_name = std.fmt.bufPrint(&buf, "{s} drift", .{name}) catch return Error.InvalidDilemma;
    const accumulator = try world.intern_relation(acc_name, .property);
    const spent_name = std.fmt.bufPrint(&buf, "{s} drift steps", .{name}) catch return Error.InvalidDilemma;
    const spent = try world.intern_relation(spent_name, .property);
    return .{ .accumulator = accumulator, .spent = spent };
}

/// One tier's authored response: a line the actor speaks (an interned text entity, as `say`
/// uses) and the action the cue carries.
pub const Response = struct {
    line: EntityId,
    action: EntityId,
};

pub const Dilemma = struct {
    entity: EntityId,
    actor: EntityId,
    cue: EntityId,
    clauses: []const Clause,
    axis: RelationKind,
    counter: RelationKind,
    leans: []const Lean,
    drifts: []const Drift = &.{},
    appeals: []const Appeal = &.{},
    /// Indexed by `Tier`; every tier has a response, so weighing is never silent.
    responses: [TIER_COUNT]Response,
};

pub const Declaration = struct {
    dilemma: Dilemma,

    pub fn deinit_owned(self: *Declaration, allocator: std.mem.Allocator) void {
        allocator.free(self.dilemma.leans);
        allocator.free(self.dilemma.drifts);
        allocator.free(self.dilemma.appeals);
        allocator.free(self.dilemma.clauses);
        self.* = undefined;
    }
};

/// The tier a delta falls into. Boundaries are inclusive at their inner edge: 7 is strong, 3 is
/// moderate, 2 is neutral.
pub fn tier_of(delta: i32) Tier {
    if (delta >= STRONG_AT) return .strong_axis;
    if (delta >= MODERATE_AT) return .moderate_axis;
    if (delta > -MODERATE_AT) return .neutral;
    if (delta > -STRONG_AT) return .moderate_counter;
    return .strong_counter;
}

pub fn validate(world: *const World, dilemma: Dilemma) Error!void {
    if (dilemma.entity == .none or dilemma.actor == .none or dilemma.cue == .none) return Error.InvalidDilemma;
    if (dilemma.clauses.len == 0 or dilemma.clauses.len > MAX_CLAUSES) return Error.InvalidDilemma;
    for (dilemma.clauses) |clause| if (clause.relation.len == 0) return Error.InvalidDilemma;
    if (dilemma.axis == dilemma.counter) return Error.InvalidDilemma;
    for ([_]RelationKind{ dilemma.axis, dilemma.counter }) |axis| {
        if (world.value_bound(axis) == null) return Error.InvalidDilemma;
    }
    if (dilemma.leans.len > MAX_LEANS) return Error.InvalidDilemma;
    for (dilemma.leans) |lean| {
        if (lean.clause.relation.len == 0) return Error.InvalidDilemma;
        if (lean.points == 0 or lean.points > MAX_LEAN or lean.points < -@as(i32, MAX_LEAN)) return Error.InvalidDilemma;
    }
    if (dilemma.drifts.len > MAX_DRIFTS) return Error.InvalidDilemma;
    for (dilemma.drifts) |drift| {
        if (world.value_bound(drift.axis) == null or drift.clause.relation.len == 0) return Error.InvalidDilemma;
        if (drift.points == 0 or drift.points > MAX_DRIFT or drift.points < -@as(i32, MAX_DRIFT)) return Error.InvalidDilemma;
        for ([_]RelationKind{ drift.accumulator, drift.spent }) |rel| {
            const meta = world.get_relation_meta(rel) orelse return Error.InvalidDilemma;
            if (meta.rel_type != .property) return Error.InvalidDilemma;
        }
    }
    if (dilemma.appeals.len > MAX_APPEALS) return Error.InvalidDilemma;
    for (dilemma.appeals, 0..) |appeal, i| {
        for (dilemma.appeals[0..i]) |prior| if (prior.axis == appeal.axis) return Error.InvalidDilemma;
        if (appeal.points == 0 or appeal.points > MAX_APPEAL or appeal.points < -@as(i32, MAX_APPEAL)) return Error.InvalidDilemma;
        if (value_mod.axis_of_entity(world, appeal.entity) != appeal.axis) return Error.InvalidDilemma;
    }
    for (dilemma.responses) |response| {
        if (world.get_entity_name(response.line) == null or world.get_entity_name(response.action) == null) return Error.InvalidDilemma;
    }
}

/// Validates a program's dilemmas together: entities are unique and none shares a decision's
/// entity, since both record their choice in `Chose`. No tier's action may be on its actor's red
/// lines (P45-02): the compiler refuses rather than let a weighed tier act against a red line.
pub fn validate_all(
    world: *const World,
    declarations: []const Declaration,
    decisions: []const decision_mod.Declaration,
    red_lines: []const decision_mod.RedLineDeclaration,
) Error!void {
    if (declarations.len > MAX_DILEMMAS) return Error.InvalidDilemma;
    for (declarations, 0..) |decl, i| {
        const dilemma = decl.dilemma;
        try validate(world, dilemma);
        for (declarations[0..i]) |prior| if (prior.dilemma.entity == dilemma.entity) return Error.InvalidDilemma;
        for (decisions) |decision| if (decision.decision.entity == dilemma.entity) return Error.InvalidDilemma;
        for (dilemma.responses) |response| {
            if (decision_mod.vetoed(red_lines, dilemma.actor, response.action)) return Error.InvalidDilemma;
        }
    }
}

const Vocabulary = struct {
    state: RelationKind,
    seen: RelationKind,
    chose: RelationKind,
    presented: RelationKind,
    stages: [STAGE_NAMES.len]EntityId,

    fn intern(world: *World) !Vocabulary {
        var v = Vocabulary{
            .state = try world.intern_relation(STATE_RELATION, .property),
            .seen = try world.intern_relation(SEEN_RELATION, .property),
            .chose = try world.intern_relation(CHOSE_RELATION, .set),
            .presented = try world.intern_relation(PRESENTED_RELATION, .set),
            .stages = undefined,
        };
        // Declared with another type, a property would append rows and a set would overwrite.
        if (world.get_relation_meta(v.state).?.rel_type != .property or
            world.get_relation_meta(v.seen).?.rel_type != .property or
            world.get_relation_meta(v.chose).?.rel_type != .set or
            world.get_relation_meta(v.presented).?.rel_type != .set) return Error.InvalidDilemma;
        for (STAGE_NAMES, 0..) |name, i| v.stages[i] = try world.intern_entity(name);
        return v;
    }

    fn stage_of(self: Vocabulary, world: *const World, dilemma: EntityId) ?Stage {
        const raw = world.get_property(dilemma, self.state) orelse return null;
        for (self.stages, 0..) |entity, i| if (entity.to_int() == raw) return @fromBackingInt(@intCast(i));
        return null;
    }

    fn set(self: Vocabulary, world: *World, dilemma: EntityId, stage: Stage) !void {
        try world.remember(dilemma, self.state, self.stages[@backingInt(stage)].to_int(), 0);
    }

    fn presented_count(self: Vocabulary, world: *const World, actor: EntityId) u32 {
        var count: u32 = 0;
        const slice = world.facts.slice();
        for (slice.items(.subject)[0..world.facts.len], slice.items(.relation)[0..world.facts.len]) |subject, relation| {
            if (subject == actor and relation == self.presented) count += 1;
        }
        return count;
    }
};

/// The stage a dilemma is in, or null before seeding.
pub fn stage_of(world: *const World, dilemma: EntityId) ?Stage {
    const relation = world.lookup_relation(STATE_RELATION) orelse return null;
    const raw = world.get_property(dilemma, relation) orelse return null;
    for (STAGE_NAMES, 0..) |name, i| {
        const entity = world.lookup_entity(name) orelse continue;
        if (entity.to_int() == raw) return @fromBackingInt(@intCast(i));
    }
    return null;
}

/// Gives every dilemma without a stage the `Idle` stage; existing stages are left alone.
pub fn seed(world: *World, declarations: []const Declaration) !void {
    if (declarations.len == 0) return;
    const v = try Vocabulary.intern(world);
    for (declarations) |decl| {
        if (v.stage_of(world, decl.dilemma.entity) == null) try v.set(world, decl.dilemma.entity, .idle);
    }
}

fn holds(world: *const World, clause: Clause) bool {
    const relation = world.lookup_relation(clause.relation) orelse return false;
    return world.has_fact(clause.subject, relation, if (clause.object) |o| o.to_int() else null);
}

fn triggered(world: *const World, dilemma: Dilemma) bool {
    for (dilemma.clauses) |clause| {
        if (holds(world, clause) == clause.negated) return false;
    }
    return true;
}

fn value_or_zero(world: *const World, actor: EntityId, axis: RelationKind) i32 {
    const raw = world.get_property(actor, axis) orelse return 0;
    return @bitCast(raw);
}

/// The dilemma's delta in the current World: axis minus counter-axis, plus every lean that holds.
pub fn delta_of(world: *const World, dilemma: Dilemma) i32 {
    var delta = value_or_zero(world, dilemma.actor, dilemma.axis) - value_or_zero(world, dilemma.actor, dilemma.counter);
    for (dilemma.leans) |lean| {
        if (holds(world, lean.clause) != lean.clause.negated) delta += lean.points;
    }
    return delta;
}

/// One weighing this tick, in declaration order.
pub const Outcome = struct {
    dilemma: EntityId,
    actor: EntityId,
    cue: EntityId,
    tier: Tier,
    delta: i32,
    line: EntityId,
    action: EntityId,
};

pub const Outcomes = struct {
    items: [MAX_DILEMMAS]Outcome = undefined,
    len: usize = 0,

    pub fn slice(self: *const Outcomes) []const Outcome {
        return self.items[0..self.len];
    }
};

/// Advances every dilemma by one tick. Runs in `host.tick` after decisions. A dilemma weighs
/// once when its trigger rises and re-arms when it falls; a neutral weighing waits for evidence
/// and weighs again each tick the count of things presented to the actor has grown.
pub fn step(world: *World, spatial: ?*const spatial_mod.SpatialSystem, declarations: []const Declaration) !Outcomes {
    var out = Outcomes{};
    if (declarations.len == 0) return out;
    const v = try Vocabulary.intern(world);
    const pending_rel = try world.intern_relation(PENDING_APPEAL_RELATION, .property);
    // Drift reads last tick's weighings: a fact that rises on the tick a dilemma is first
    // weighed was already true when it was weighed, so it is not an outcome of it.
    for (declarations) |decl| try apply_drift(world, decl.dilemma);
    for (declarations) |decl| {
        const dilemma = decl.dilemma;
        const stage = v.stage_of(world, dilemma.entity) orelse .idle;
        const live = triggered(world, dilemma);
        if (!live) {
            if (stage != .idle) {
                try v.set(world, dilemma.entity, .idle);
                _ = world.forget(dilemma.entity, v.chose, null);
                _ = world.forget(dilemma.entity, v.seen, null);
            }
            continue;
        }
        const presented = v.presented_count(world, dilemma.actor);
        switch (stage) {
            .done => continue,
            .awaits_evidence => {
                const seen = world.get_property(dilemma.entity, v.seen) orelse 0;
                const appealed = world.get_property(dilemma.entity, pending_rel) != null;
                if (presented <= seen and !appealed) continue;
            },
            .idle => {},
        }

        // A pending appeal counts at this weighing only, then it is spent (D-149).
        var delta = delta_of(world, dilemma);
        if (world.get_property(dilemma.entity, pending_rel)) |raw| {
            for (dilemma.appeals) |appeal| {
                if (appeal.entity.to_int() == raw) delta += appeal.points;
            }
            _ = world.forget(dilemma.entity, pending_rel, null);
        }
        const tier = tier_of(delta);
        const response = dilemma.responses[@backingInt(tier)];
        _ = world.forget(dilemma.entity, v.chose, null);
        try world.remember(dilemma.entity, v.chose, response.action.to_int(), 0);
        try world.remember(dilemma.entity, try world.intern_relation(WEIGHED_RELATION, .set), 0, 0);
        if (tier == .neutral) {
            try v.set(world, dilemma.entity, .awaits_evidence);
            try world.remember(dilemma.entity, v.seen, presented, 0);
        } else {
            try v.set(world, dilemma.entity, .done);
            _ = world.forget(dilemma.entity, v.seen, null);
        }
        if (tier != .neutral) try reveal(world, spatial, dilemma, tier);
        out.items[out.len] = .{
            .dilemma = dilemma.entity,
            .actor = dilemma.actor,
            .cue = dilemma.cue,
            .tier = tier,
            .delta = delta,
            .line = response.line,
            .action = response.action,
        };
        out.len += 1;
    }
    return out;
}

/// Teaches everyone in the actor's room the value a weighing leaned toward (D-149). Watching is
/// being there: without a spatial system, or for an actor with no place, nobody learns.
fn reveal(world: *World, spatial: ?*const spatial_mod.SpatialSystem, dilemma: Dilemma, tier: Tier) !void {
    const sp = spatial orelse return;
    const axis = switch (tier) {
        .strong_axis, .moderate_axis => dilemma.axis,
        .strong_counter, .moderate_counter => dilemma.counter,
        .neutral => return,
    };
    const room = room_of(sp, dilemma.actor) orelse return;
    const knows = try world.intern_relation(KNOWS_RELATION, .set);
    const value = try value_mod.known_value(world, axis, dilemma.actor);
    var it = sp.agents.iterator();
    while (it.next()) |entry| {
        const witness = entry.key_ptr.*;
        if (witness == dilemma.actor) continue;
        if ((room_of(sp, witness) orelse continue) != room) continue;
        try world.remember(witness, knows, value.to_int(), 0);
    }
}

fn room_of(sp: *const spatial_mod.SpatialSystem, entity: EntityId) ?EntityId {
    const wp = sp.get_current_waypoint(entity) orelse return null;
    return (sp.graph.get_waypoint(wp) orelse return null).room;
}

/// The dilemma an appeal to `axis_entity` would move for `character`, or null: the first in
/// declaration order whose actor is the character, that lists an appeal to that value, and that
/// has not already weighed to a final tier.
pub fn appeal_target(world: *const World, declarations: []const Declaration, character: EntityId, axis_entity: EntityId) ?*const Dilemma {
    for (declarations) |*decl| {
        const dilemma = &decl.dilemma;
        if (dilemma.actor != character) continue;
        if (stage_of(world, dilemma.entity) == .done) continue;
        for (dilemma.appeals) |appeal| {
            if (appeal.entity == axis_entity) return dilemma;
        }
    }
    return null;
}

/// Records an appeal for the next weighing; a newer appeal replaces an unspent one.
pub fn record_appeal(world: *World, dilemma: *const Dilemma, axis_entity: EntityId) !void {
    const pending_rel = try world.intern_relation(PENDING_APPEAL_RELATION, .property);
    try world.remember(dilemma.entity, pending_rel, axis_entity.to_int(), 0);
}

/// Updates each drift line's edge state and, once the dilemma has been weighed, adds the points
/// of every line whose fact rose this tick (D-148).
fn apply_drift(world: *World, dilemma: Dilemma) !void {
    if (dilemma.drifts.len == 0) return;
    const holding_rel = try world.intern_relation(HOLDING_RELATION, .property);
    const weighed_rel = try world.intern_relation(WEIGHED_RELATION, .set);
    const was: u32 = world.get_property(dilemma.entity, holding_rel) orelse 0;
    var now: u32 = 0;
    for (dilemma.drifts, 0..) |drift, i| {
        if (holds(world, drift.clause) != drift.clause.negated) now |= @as(u32, 1) << @intCast(i);
    }
    if (now != was) try world.remember(dilemma.entity, holding_rel, now, 0);
    if (!world.has_fact(dilemma.entity, weighed_rel, null)) return;
    const rose = now & ~was;
    for (dilemma.drifts, 0..) |drift, i| {
        if (rose & (@as(u32, 1) << @intCast(i)) != 0) try add_drift(world, dilemma, drift);
    }
}

/// Adds one line's points to the actor's accumulator and spends whole steps from it, up to the
/// dilemma's bound. Points that cannot become a step, because the bound is spent or the value
/// is already at the end of its range, are discarded: the accumulator keeps at most 4.
fn add_drift(world: *World, dilemma: Dilemma, drift: Drift) !void {
    var spent: u32 = world.get_property(dilemma.entity, drift.spent) orelse 0;
    if (spent >= DRIFT_STEPS_PER_DILEMMA) return;
    const bound = world.value_bound(drift.axis) orelse return;
    var acc: i32 = @as(i32, @bitCast(world.get_property(dilemma.actor, drift.accumulator) orelse 0)) + drift.points;
    var value = value_or_zero(world, dilemma.actor, drift.axis);
    const start_value = value;
    while (acc >= DRIFT_THRESHOLD or acc <= -DRIFT_THRESHOLD) {
        const dir: i32 = if (acc > 0) 1 else -1;
        acc -= dir * DRIFT_THRESHOLD;
        if (spent >= DRIFT_STEPS_PER_DILEMMA) break;
        // A step past the range would be clamped away (D-144); it spends nothing.
        if ((dir > 0 and value >= bound.max) or (dir < 0 and value <= bound.min)) continue;
        value += dir;
        spent += 1;
    }
    acc = std.math.clamp(acc, -(DRIFT_THRESHOLD - 1), DRIFT_THRESHOLD - 1);
    if (value != start_value or world.get_property(dilemma.actor, drift.axis) == null)
        try world.remember(dilemma.actor, drift.axis, @bitCast(value), 0);
    try world.remember(dilemma.actor, drift.accumulator, @bitCast(acc), 0);
    try world.remember(dilemma.entity, drift.spent, spent, 0);
}

/// The actor's undrifted points on an axis: the accumulator between steps, -4 to 4.
pub fn drift_points(world: *const World, actor: EntityId, accumulator: RelationKind) i32 {
    return @bitCast(world.get_property(actor, accumulator) orelse 0);
}

/// The action chosen at the last weighing, or null between points.
pub fn chosen(world: *const World, dilemma: EntityId) ?EntityId {
    return decision_mod.chosen(world, dilemma);
}

test "P45-03: tier boundaries are fixed and mirrored" {
    const testing = std.testing;
    const cases = [_]struct { delta: i32, tier: Tier }{
        .{ .delta = 30, .tier = .strong_axis },
        .{ .delta = 7, .tier = .strong_axis },
        .{ .delta = 6, .tier = .moderate_axis },
        .{ .delta = 3, .tier = .moderate_axis },
        .{ .delta = 2, .tier = .neutral },
        .{ .delta = 0, .tier = .neutral },
        .{ .delta = -2, .tier = .neutral },
        .{ .delta = -3, .tier = .moderate_counter },
        .{ .delta = -6, .tier = .moderate_counter },
        .{ .delta = -7, .tier = .strong_counter },
        .{ .delta = -30, .tier = .strong_counter },
    };
    for (cases) |case| try testing.expectEqual(case.tier, tier_of(case.delta));
}

const TestRig = struct {
    world: World,
    actor: EntityId,
    justice: RelationKind,
    mercy: RelationKind,
    accused: RelationKind,
    famine: RelationKind,
    criminal: RelationKind,
    thief: EntityId,
    town: EntityId,
    leans: [2]Lean,
    decls: [1]Declaration,

    fn init(rig: *TestRig) !void {
        const testing = std.testing;
        rig.world = try World.init(testing.allocator, 1024 * 1024);
        const w = &rig.world;
        rig.actor = try w.intern_entity("Oswin");
        rig.justice = (try value_mod.declare(w, "Justice", .{ "Cruelty", "Leniency" })).relation;
        rig.mercy = (try value_mod.declare(w, "Mercy", .{ "Vengeance", "Condoning Harm" })).relation;
        rig.accused = try w.intern_relation("Accused", .set);
        rig.famine = try w.intern_relation("Famine", .set);
        rig.criminal = try w.intern_relation("Criminal", .set);
        rig.thief = try w.intern_entity("Thief");
        rig.town = try w.intern_entity("Town");
        rig.leans = .{
            .{ .points = 3, .clause = .{ .relation = "Criminal", .subject = rig.thief } },
            .{ .points = -4, .clause = .{ .relation = "Famine", .subject = rig.town } },
        };
        var responses: [TIER_COUNT]Response = undefined;
        const names = [_][2][]const u8{
            .{ "The law is the law.", "Hang" },
            .{ "A night in the cells.", "Jail" },
            .{ "Show me why I should spare him.", "Wait" },
            .{ "Pay for the loaf.", "Fine" },
            .{ "Feed him and let him go.", "Pardon" },
        };
        for (names, 0..) |pair, i| responses[i] = .{ .line = try w.intern_entity(pair[0]), .action = try w.intern_entity(pair[1]) };
        rig.decls = .{.{ .dilemma = .{
            .entity = try w.intern_entity("StolenBread"),
            .actor = rig.actor,
            .cue = try w.intern_entity("Judged"),
            .clauses = &.{.{ .relation = "Accused" }},
            .axis = rig.justice,
            .counter = rig.mercy,
            .leans = &rig.leans,
            .responses = responses,
        } }};
        try validate_all(w, &rig.decls, &.{}, &.{});
        try seed(w, &rig.decls);
    }

    fn set_values(rig: *TestRig, justice: i32, mercy: i32) !void {
        try rig.world.remember(rig.actor, rig.justice, @bitCast(justice), 0);
        try rig.world.remember(rig.actor, rig.mercy, @bitCast(mercy), 0);
    }

    /// Re-arms the dilemma, then raises the trigger and weighs once.
    fn weigh(rig: *TestRig) !Outcomes {
        _ = rig.world.forget(rig.thief, rig.accused, null);
        _ = try step(&rig.world, null, &rig.decls);
        try rig.world.remember(rig.thief, rig.accused, 0, 0);
        return step(&rig.world, null, &rig.decls);
    }

    fn action_name(rig: *TestRig, outcome: Outcome) []const u8 {
        return rig.world.get_entity_name(outcome.action).?;
    }
};

test "P45-03: each tier boundary selects its line and action" {
    const testing = std.testing;
    var rig: TestRig = undefined;
    try rig.init();
    defer rig.world.deinit();
    const cases = [_]struct { justice: i32, mercy: i32, action: []const u8, tier: Tier }{
        .{ .justice = 7, .mercy = 0, .action = "Hang", .tier = .strong_axis },
        .{ .justice = 6, .mercy = 0, .action = "Jail", .tier = .moderate_axis },
        .{ .justice = 5, .mercy = 2, .action = "Jail", .tier = .moderate_axis },
        .{ .justice = 2, .mercy = 0, .action = "Wait", .tier = .neutral },
        .{ .justice = -2, .mercy = 0, .action = "Wait", .tier = .neutral },
        .{ .justice = 0, .mercy = 3, .action = "Fine", .tier = .moderate_counter },
        .{ .justice = 0, .mercy = 6, .action = "Fine", .tier = .moderate_counter },
        .{ .justice = 0, .mercy = 7, .action = "Pardon", .tier = .strong_counter },
        // The difference, not the sum: a low counter-value strengthens the lean.
        .{ .justice = 4, .mercy = -4, .action = "Hang", .tier = .strong_axis },
    };
    for (cases) |case| {
        try rig.set_values(case.justice, case.mercy);
        const out = try rig.weigh();
        try testing.expectEqual(@as(usize, 1), out.len);
        try testing.expectEqual(case.tier, out.items[0].tier);
        try testing.expectEqual(case.justice - case.mercy, out.items[0].delta);
        try testing.expectEqualStrings(case.action, rig.action_name(out.items[0]));
        try testing.expectEqual(out.items[0].action, chosen(&rig.world, rig.decls[0].dilemma.entity).?);
    }
    // A strong weighing is done: still triggered, it does not weigh again.
    try rig.set_values(9, 0);
    _ = try rig.weigh();
    try testing.expectEqual(@as(usize, 0), (try step(&rig.world, null, &rig.decls)).len);
    try testing.expectEqual(Stage.done, stage_of(&rig.world, rig.decls[0].dilemma.entity).?);

    // A missing value counts as 0 for weighing and writes nothing.
    _ = rig.world.forget(rig.actor, rig.justice, null);
    _ = rig.world.forget(rig.actor, rig.mercy, null);
    const unset = try rig.weigh();
    try testing.expectEqual(@as(i32, 0), unset.items[0].delta);
    try testing.expect(rig.world.get_property(rig.actor, rig.justice) == null);
}

test "P45-03: lean lines read world facts and move the tier" {
    const testing = std.testing;
    var rig: TestRig = undefined;
    try rig.init();
    defer rig.world.deinit();
    // Justice 4, Mercy 0: moderate toward Justice.
    try rig.set_values(4, 0);
    try testing.expectEqualStrings("Jail", rig.action_name((try rig.weigh()).items[0]));
    // A known criminal leans 3 toward Justice: 7, strong.
    try rig.world.remember(rig.thief, rig.criminal, 0, 0);
    const strong = try rig.weigh();
    try testing.expectEqual(@as(i32, 7), strong.items[0].delta);
    try testing.expectEqualStrings("Hang", rig.action_name(strong.items[0]));
    // A famine leans 4 toward Mercy: 3, moderate again.
    try rig.world.remember(rig.town, rig.famine, 0, 0);
    const both = try rig.weigh();
    try testing.expectEqual(@as(i32, 3), both.items[0].delta);
    try testing.expectEqualStrings("Jail", rig.action_name(both.items[0]));
    // Without the criminal record the famine alone gives 0: neutral.
    _ = rig.world.forget(rig.thief, rig.criminal, null);
    const famine = try rig.weigh();
    try testing.expectEqual(@as(i32, 0), famine.items[0].delta);
    try testing.expectEqual(Tier.neutral, famine.items[0].tier);
}

test "P45-03: a neutral weighing waits for evidence and weighs again when it arrives" {
    const testing = std.testing;
    var rig: TestRig = undefined;
    try rig.init();
    defer rig.world.deinit();
    const presented = try rig.world.intern_relation(PRESENTED_RELATION, .set);
    const ledger = try rig.world.intern_entity("Ledger");
    const letter = try rig.world.intern_entity("Letter");
    try rig.set_values(4, 0);
    try rig.world.remember(rig.town, rig.famine, 0, 0);
    const first = try rig.weigh();
    try testing.expectEqual(Tier.neutral, first.items[0].tier);
    try testing.expectEqual(Stage.awaits_evidence, stage_of(&rig.world, rig.decls[0].dilemma.entity).?);

    // Nothing new presented: no re-weighing.
    try testing.expectEqual(@as(usize, 0), (try step(&rig.world, null, &rig.decls)).len);

    // Evidence that changes nothing re-weighs once and stays neutral.
    try rig.world.remember(rig.actor, presented, letter.to_int(), 0);
    const still = try step(&rig.world, null, &rig.decls);
    try testing.expectEqual(@as(usize, 1), still.len);
    try testing.expectEqual(Tier.neutral, still.items[0].tier);
    try testing.expectEqual(@as(usize, 0), (try step(&rig.world, null, &rig.decls)).len);

    // The ledger proves the thief a criminal; presenting it re-weighs to moderate Justice.
    try rig.world.remember(rig.thief, rig.criminal, 0, 0);
    try rig.world.remember(rig.actor, presented, ledger.to_int(), 0);
    const moved = try step(&rig.world, null, &rig.decls);
    try testing.expectEqual(@as(usize, 1), moved.len);
    try testing.expectEqual(Tier.moderate_axis, moved.items[0].tier);
    try testing.expectEqualStrings("Jail", rig.action_name(moved.items[0]));
    try testing.expectEqual(Stage.done, stage_of(&rig.world, rig.decls[0].dilemma.entity).?);
    // One Chose row: the re-weighing replaced the neutral action.
    const chose = rig.world.lookup_relation(CHOSE_RELATION).?;
    var rows: usize = 0;
    const slice = rig.world.facts.slice();
    for (slice.items(.subject)[0..rig.world.facts.len], slice.items(.relation)[0..rig.world.facts.len]) |subject, relation| {
        if (subject == rig.decls[0].dilemma.entity and relation == chose) rows += 1;
    }
    try testing.expectEqual(@as(usize, 1), rows);
}

test "P45-03: a tier action on the actor's red lines is refused" {
    const testing = std.testing;
    var rig: TestRig = undefined;
    try rig.init();
    defer rig.world.deinit();
    const hang = rig.world.lookup_entity("Hang").?;
    const lines = [_]decision_mod.RedLineDeclaration{.{ .red_lines = .{ .actor = rig.actor, .options = &.{hang} } }};
    try testing.expectError(Error.InvalidDilemma, validate_all(&rig.world, &rig.decls, &.{}, &lines));
    // The same axis twice cannot be weighed.
    var same = rig.decls;
    same[0].dilemma.counter = rig.justice;
    try testing.expectError(Error.InvalidDilemma, validate_all(&rig.world, &same, &.{}, &.{}));
}

/// Gives the rig's dilemma drift lines: Repaid(Thief) toward Mercy, Robbed(Miller) away from it.
fn with_drifts(rig: *TestRig, lines: *[2]Drift, repaid_points: i32, robbed_points: i32) !void {
    const w = &rig.world;
    const rels = try drift_relations(w, rig.mercy);
    _ = try w.intern_relation("Repaid", .set);
    _ = try w.intern_relation("Robbed", .set);
    lines.* = .{
        .{ .axis = rig.mercy, .points = repaid_points, .clause = .{ .relation = "Repaid", .subject = rig.thief }, .accumulator = rels.accumulator, .spent = rels.spent },
        .{ .axis = rig.mercy, .points = robbed_points, .clause = .{ .relation = "Robbed", .subject = try w.intern_entity("Miller") }, .accumulator = rels.accumulator, .spent = rels.spent },
    };
    rig.decls[0].dilemma.drifts = lines;
    try validate_all(w, &rig.decls, &.{}, &.{});
}

/// Raises and lowers a drift line's fact once, stepping the dilemma on each side of the edge.
fn pulse(rig: *TestRig, relation: []const u8, subject: EntityId) !void {
    const rel = rig.world.lookup_relation(relation).?;
    try rig.world.remember(subject, rel, 0, 0);
    _ = try step(&rig.world, null, &rig.decls);
    _ = rig.world.forget(subject, rel, null);
    _ = try step(&rig.world, null, &rig.decls);
}

fn mercy_of(rig: *TestRig) i32 {
    return @bitCast(rig.world.get_property(rig.actor, rig.mercy).?);
}

test "P45-04: drift accumulates whole points and moves a value one step per 5" {
    const testing = std.testing;
    var rig: TestRig = undefined;
    try rig.init();
    defer rig.world.deinit();
    var lines: [2]Drift = undefined;
    try with_drifts(&rig, &lines, 3, -5);
    try rig.set_values(4, 0);
    const acc = lines[0].accumulator;

    // Before the dilemma has been weighed, an outcome is not its outcome.
    try pulse(&rig, "Repaid", rig.thief);
    try testing.expectEqual(@as(i32, 0), mercy_of(&rig));
    try testing.expectEqual(@as(i32, 0), drift_points(&rig.world, rig.actor, acc));

    _ = try rig.weigh();
    // A fact that holds without rising adds nothing: hold Repaid across two steps.
    const repaid = rig.world.lookup_relation("Repaid").?;
    try rig.world.remember(rig.thief, repaid, 0, 0);
    _ = try step(&rig.world, null, &rig.decls);
    _ = try step(&rig.world, null, &rig.decls);
    try testing.expectEqual(@as(i32, 3), drift_points(&rig.world, rig.actor, acc));
    try testing.expectEqual(@as(i32, 0), mercy_of(&rig));
    _ = rig.world.forget(rig.thief, repaid, null);
    _ = try step(&rig.world, null, &rig.decls);

    // A second repayment makes 6 points: one step toward Mercy, 1 point left over.
    try pulse(&rig, "Repaid", rig.thief);
    try testing.expectEqual(@as(i32, 1), mercy_of(&rig));
    try testing.expectEqual(@as(i32, 1), drift_points(&rig.world, rig.actor, acc));

    // A robbery drifts 5 away from Mercy. It first cancels the leftover point, so the
    // accumulator reads -4 and the value holds; a second robbery makes -9, one step back.
    const baker = rig.world.lookup_entity("Miller").?;
    try pulse(&rig, "Robbed", baker);
    try testing.expectEqual(@as(i32, 1), mercy_of(&rig));
    try testing.expectEqual(@as(i32, -4), drift_points(&rig.world, rig.actor, acc));
    try pulse(&rig, "Robbed", baker);
    try testing.expectEqual(@as(i32, 0), mercy_of(&rig));
    try testing.expectEqual(@as(i32, -4), drift_points(&rig.world, rig.actor, acc));
}

test "P45-04: one dilemma moves an axis at most two steps, and drift stops at the range" {
    const testing = std.testing;
    var rig: TestRig = undefined;
    try rig.init();
    defer rig.world.deinit();
    var lines: [2]Drift = undefined;
    try with_drifts(&rig, &lines, 10, -10);
    try rig.set_values(4, 0);
    _ = try rig.weigh();

    // 10 points are two steps; the bound is then spent and further points are dropped.
    try pulse(&rig, "Repaid", rig.thief);
    try testing.expectEqual(@as(i32, 2), mercy_of(&rig));
    try testing.expectEqual(@as(u32, 2), rig.world.get_property(rig.decls[0].dilemma.entity, lines[0].spent).?);
    try pulse(&rig, "Repaid", rig.thief);
    try pulse(&rig, "Robbed", rig.world.lookup_entity("Miller").?);
    try testing.expectEqual(@as(i32, 2), mercy_of(&rig));
    try testing.expectEqual(@as(i32, 0), drift_points(&rig.world, rig.actor, lines[0].accumulator));

    // At +10 a step would leave the range: it is discarded and spends nothing.
    var edge: TestRig = undefined;
    try edge.init();
    defer edge.world.deinit();
    var edge_lines: [2]Drift = undefined;
    try with_drifts(&edge, &edge_lines, 10, -5);
    try edge.set_values(0, 10);
    _ = try edge.weigh();
    try pulse(&edge, "Repaid", edge.thief);
    try testing.expectEqual(@as(i32, 10), mercy_of(&edge));
    try testing.expect(edge.world.get_property(edge.decls[0].dilemma.entity, edge_lines[0].spent).? == 0);
    try testing.expectEqual(@as(i32, 0), drift_points(&edge.world, edge.actor, edge_lines[0].accumulator));
    // The bound is untouched, so drift back down still works.
    try pulse(&edge, "Robbed", edge.world.lookup_entity("Miller").?);
    try testing.expectEqual(@as(i32, 9), mercy_of(&edge));
}
