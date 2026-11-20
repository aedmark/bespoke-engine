//! Script-declared decisions: an actor chooses among the options it knows (P44-05).
//!
//! A `decision` declaration names an actor, a cue, the trigger lines that mark a decision point,
//! and the options it may choose. An option is offered only when the actor knows it, read with
//! the same `Knows`/`Believes`/`Rejects` rule a spell uses (`src/spell.zig`), so a hand of cards
//! is private without a second knowledge model. Each option sums its `picks` and `drops` lines
//! whose condition holds; the highest score wins and an equal score goes to the earlier option.
//!
//! A decision point is an edge, not a level: the engine chooses once while the trigger holds,
//! records `DecisionState(Decision, Done)`, and re-arms when the trigger stops holding. All
//! lifecycle state is World facts, so save, rewind, and branch restore need no decision
//! snapshot:
//!   DecisionState(Decision, Idle | Done)   property on the decision entity
//!   Chose(Decision, Option)                set fact naming the choice, cleared on re-arm
//!
//! The engine fires the decision's cue with the actor and the winning option, so one handler can
//! run a whole game and a script that wants per-option behaviour matches the argument. Scoring
//! reads facts only and draws no random number, so a replay makes the same choices.

const std = @import("std");
const world_mod = @import("world.zig");
const spell_mod = @import("spell.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;

pub const MAX_DECISIONS: usize = 32;
pub const MAX_CLAUSES: usize = 8;
pub const MAX_OPTIONS: usize = 8;
pub const MAX_PICKS: usize = 8;
/// A single scored line's magnitude. The sum of a full option stays well inside `i32`.
pub const MAX_POINTS: u16 = 100;

pub const STATE_RELATION = "DecisionState";
pub const CHOSE_RELATION = "Chose";
pub const STAGE_NAMES = [_][]const u8{ "Idle", "Done" };

pub const Stage = enum(u8) { idle = 0, done = 1 };

pub const Error = error{InvalidDecision};

/// One trigger line, the same shape an agenda uses. A null subject or object is the `_`
/// wildcard. `negated` lines (`unless`) must not hold; the others (`requires`) must.
pub const Clause = struct {
    relation: []const u8,
    subject: ?EntityId = null,
    object: ?EntityId = null,
    negated: bool = false,
};

/// One scored line of an option: `points` added when the clause holds, or when it does not for
/// a `drops ... unless` line.
pub const Pick = struct {
    points: i32,
    clause: Clause,
};

/// One offered option. Its entity is what the actor must know for the engine to offer it.
pub const Option = struct {
    entity: EntityId,
    picks: []const Pick,
};

/// Immutable script program data for one decision.
pub const Decision = struct {
    entity: EntityId,
    actor: EntityId,
    /// The cue fired with the actor and the winning option.
    cue: EntityId,
    clauses: []const Clause,
    options: []const Option,
};

/// Compiler-owned declaration. The slices are freed by `deinit_owned`; relation names are
/// borrowed from the World's intern table, which outlives the program.
pub const Declaration = struct {
    decision: Decision,

    pub fn deinit_owned(self: *Declaration, allocator: std.mem.Allocator) void {
        for (self.decision.options) |option| allocator.free(option.picks);
        allocator.free(self.decision.options);
        allocator.free(self.decision.clauses);
        self.* = undefined;
    }
};

/// One choice made this tick, in declaration order.
pub const Choice = struct {
    decision: EntityId,
    actor: EntityId,
    cue: EntityId,
    option: EntityId,
    score: i32,
};

pub const Choices = struct {
    items: [MAX_DECISIONS]Choice = undefined,
    len: usize = 0,

    pub fn slice(self: *const Choices) []const Choice {
        return self.items[0..self.len];
    }
};

pub fn validate(decision: Decision) Error!void {
    if (decision.entity == .none or decision.actor == .none or decision.cue == .none) return Error.InvalidDecision;
    if (decision.clauses.len == 0 or decision.clauses.len > MAX_CLAUSES) return Error.InvalidDecision;
    for (decision.clauses) |clause| if (clause.relation.len == 0) return Error.InvalidDecision;
    if (decision.options.len == 0 or decision.options.len > MAX_OPTIONS) return Error.InvalidDecision;
    for (decision.options, 0..) |option, i| {
        if (option.entity == .none) return Error.InvalidDecision;
        for (decision.options[0..i]) |prior| if (prior.entity == option.entity) return Error.InvalidDecision;
        if (option.picks.len == 0 or option.picks.len > MAX_PICKS) return Error.InvalidDecision;
        for (option.picks) |pick| {
            if (pick.clause.relation.len == 0) return Error.InvalidDecision;
            if (pick.points > MAX_POINTS or pick.points < -@as(i32, MAX_POINTS)) return Error.InvalidDecision;
        }
    }
}

/// Validates a program's decisions together: entities must be unique.
pub fn validate_all(declarations: []const Declaration) Error!void {
    if (declarations.len > MAX_DECISIONS) return Error.InvalidDecision;
    for (declarations, 0..) |decl, i| {
        try validate(decl.decision);
        for (declarations[0..i]) |prior| if (prior.decision.entity == decl.decision.entity) return Error.InvalidDecision;
    }
}

const Vocabulary = struct {
    state: world_mod.RelationKind,
    chose: world_mod.RelationKind,
    stages: [STAGE_NAMES.len]EntityId,

    fn intern(world: *World) !Vocabulary {
        var v = Vocabulary{
            .state = try world.intern_relation(STATE_RELATION, .property),
            .chose = try world.intern_relation(CHOSE_RELATION, .set),
            .stages = undefined,
        };
        // A script that declared either name with another type would append rows instead of
        // replacing them, so the readout could report two choices for one decision.
        if (world.get_relation_meta(v.state).?.rel_type != .property or
            world.get_relation_meta(v.chose).?.rel_type != .set) return Error.InvalidDecision;
        for (STAGE_NAMES, 0..) |name, i| v.stages[i] = try world.intern_entity(name);
        return v;
    }

    fn stage_of(self: Vocabulary, world: *const World, decision: EntityId) ?Stage {
        const raw = world.get_property(decision, self.state) orelse return null;
        for (self.stages, 0..) |entity, i| if (entity.to_int() == raw) return @fromBackingInt(@intCast(i));
        return null;
    }

    fn set(self: Vocabulary, world: *World, decision: EntityId, stage: Stage) !void {
        try world.remember(decision, self.state, self.stages[@backingInt(stage)].to_int(), 0);
    }
};

/// The stage a decision is in, or null before seeding.
pub fn stage_of(world: *const World, decision: EntityId) ?Stage {
    const relation = world.lookup_relation(STATE_RELATION) orelse return null;
    const raw = world.get_property(decision, relation) orelse return null;
    for (STAGE_NAMES, 0..) |name, i| {
        const entity = world.lookup_entity(name) orelse continue;
        if (entity.to_int() == raw) return @fromBackingInt(@intCast(i));
    }
    return null;
}

/// The option chosen at the last decision point, or null between points. A set relation keeps
/// one row while the point stands, so a script reads the choice with `Chose(Decision, Option)`.
pub fn chosen(world: *const World, decision: EntityId) ?EntityId {
    const relation = world.lookup_relation(CHOSE_RELATION) orelse return null;
    const fact = world.find_first(decision, relation, null) orelse return null;
    return EntityId.from_int(fact.object_or_value);
}

/// Gives every decision without a stage the `Idle` stage. Repeated calls, including after a
/// restore, leave existing stages alone.
pub fn seed(world: *World, declarations: []const Declaration) !void {
    if (declarations.len == 0) return;
    const v = try Vocabulary.intern(world);
    for (declarations) |decl| {
        if (v.stage_of(world, decl.decision.entity) == null) try v.set(world, decl.decision.entity, .idle);
    }
}

/// Whether the clause's fact is present. A relation no fact has ever used cannot hold, so a
/// `requires` on it fails and an `unless` on it passes.
fn holds(world: *const World, clause: Clause) bool {
    const relation = world.lookup_relation(clause.relation) orelse return false;
    return world.has_fact(clause.subject, relation, if (clause.object) |o| o.to_int() else null);
}

/// True when every trigger line holds in the current World.
pub fn triggered(world: *const World, decision: Decision) bool {
    for (decision.clauses) |clause| {
        if (holds(world, clause) == clause.negated) return false;
    }
    return true;
}

/// What the actor knows about an option: `Knows` or `Believes`, unless `Rejects` says otherwise.
/// This is the same rule a spell cast reads, so a hand and a vocabulary gate the same way.
fn offered(world: *const World, actor: EntityId, option: EntityId) bool {
    return spell_mod.knows(world, actor, option);
}

/// The score of one option against the current World: every `picks` line whose clause holds and
/// every `drops` line whose clause does not. A drop is stored as a negative `points`, so the sum
/// carries the sign.
pub fn score_of(world: *const World, option: Option) i32 {
    var total: i32 = 0;
    for (option.picks) |pick| {
        if (holds(world, pick.clause) != pick.clause.negated) total += pick.points;
    }
    return total;
}

const Scored = struct { option: EntityId, score: i32 };

/// The highest-scoring offered option, or null when the actor knows none of them. An equal score
/// keeps the earlier option, so declaration order breaks ties without a second rule.
fn best_option(world: *const World, decision: Decision) ?Scored {
    var best: ?Scored = null;
    for (decision.options) |option| {
        if (!offered(world, decision.actor, option.entity)) continue;
        const score = score_of(world, option);
        if (best == null or score > best.?.score) best = .{ .option = option.entity, .score = score };
    }
    return best;
}

/// Advances every decision by one tick. Runs in `host.tick` after agendas, so a decision sees
/// this tick's facts, movement included, and its cue handler runs on the next tick like any
/// fired cue. A decision whose trigger rises with no offered option resolves to nothing, fires
/// nothing, and waits for the trigger to fall before it can choose again.
pub fn step(world: *World, declarations: []const Declaration) !Choices {
    var out = Choices{};
    if (declarations.len == 0) return out;
    const v = try Vocabulary.intern(world);
    for (declarations) |decl| {
        const decision = decl.decision;
        const was_done = switch (v.stage_of(world, decision.entity) orelse .idle) {
            .done => true,
            .idle => false,
        };
        const live = triggered(world, decision);
        if (was_done) {
            if (live) continue;
            try v.set(world, decision.entity, .idle);
            _ = world.forget(decision.entity, v.chose, null);
        }
        if (!live) continue;
        try v.set(world, decision.entity, .done);
        const scored = best_option(world, decision) orelse continue;
        try world.remember(decision.entity, v.chose, scored.option.to_int(), 0);
        out.items[out.len] = .{
            .decision = decision.entity,
            .actor = decision.actor,
            .cue = decision.cue,
            .option = scored.option,
            .score = scored.score,
        };
        out.len += 1;
    }
    return out;
}

test "P44-05: the highest-scoring offered option wins, and an equal score keeps the earlier one" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const seat = try world.intern_entity("Seat");
    const cue = try world.intern_entity("ChoseOption");
    const option_a = try world.intern_entity("OptionA");
    const option_b = try world.intern_entity("OptionB");
    const open = try world.intern_entity("Open");
    const risky = try world.intern_entity("Risky");
    const knows = try world.intern_relation("Knows", .set);
    const open_rel = try world.intern_relation("Open", .set);
    const risky_rel = try world.intern_relation("Risky", .set);

    const a_picks = [_]Pick{
        .{ .points = 3, .clause = .{ .relation = "Open" } },
        .{ .points = -1, .clause = .{ .relation = "Risky" } },
    };
    const b_picks = [_]Pick{.{ .points = 2, .clause = .{ .relation = "Open" } }};
    const options = [_]Option{
        .{ .entity = option_a, .picks = &a_picks },
        .{ .entity = option_b, .picks = &b_picks },
    };
    const decisions = [_]Declaration{.{
        .decision = .{
            .entity = try world.intern_entity("ChooseOnce"),
            .actor = seat,
            .cue = cue,
            .clauses = &.{.{ .relation = "Open" }},
            .options = &options,
        },
    }};

    try world.remember(seat, knows, option_a.to_int(), 0);
    try world.remember(seat, knows, option_b.to_int(), 0);
    try world.remember(open, open_rel, 0, 0);
    try seed(&world, &decisions);

    const first = try step(&world, &decisions);
    try testing.expectEqual(@as(usize, 1), first.len);
    try testing.expectEqual(option_a, first.items[0].option);
    try testing.expectEqual(@as(i32, 3), first.items[0].score);
    try testing.expectEqual(option_a, chosen(&world, decisions[0].decision.entity).?);

    // Still open: the decision point already happened, so nothing fires again.
    const again = try step(&world, &decisions);
    try testing.expectEqual(@as(usize, 0), again.len);

    // Risky lowers OptionA to a tie with OptionB, and the earlier option keeps it.
    try world.remember(risky, risky_rel, 0, 0);
    _ = world.forget(open, open_rel, null);
    _ = try step(&world, &decisions);
    try testing.expectEqual(@as(?EntityId, null), chosen(&world, decisions[0].decision.entity));
    try world.remember(open, open_rel, 0, 0);
    const tied = try step(&world, &decisions);
    try testing.expectEqual(@as(usize, 1), tied.len);
    try testing.expectEqual(option_a, tied.items[0].option);
    try testing.expectEqual(@as(i32, 2), tied.items[0].score);
}

test "P44-05: an option the actor does not know is never offered, and Rejects overrides" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const seat = try world.intern_entity("Seat");
    const cue = try world.intern_entity("ChoseOption");
    const known = try world.intern_entity("KnownCard");
    const unknown = try world.intern_entity("UnknownCard");
    const knows = try world.intern_relation("Knows", .set);
    const rejects = try world.intern_relation("Rejects", .set);
    const open = try world.intern_relation("Open", .set);

    const unknown_picks = [_]Pick{.{ .points = 9, .clause = .{ .relation = "Open" } }};
    const known_picks = [_]Pick{.{ .points = 1, .clause = .{ .relation = "Open" } }};
    const options = [_]Option{
        .{ .entity = unknown, .picks = &unknown_picks },
        .{ .entity = known, .picks = &known_picks },
    };
    const decisions = [_]Declaration{.{
        .decision = .{
            .entity = try world.intern_entity("PickACard"),
            .actor = seat,
            .cue = cue,
            .clauses = &.{.{ .relation = "Open" }},
            .options = &options,
        },
    }};
    try seed(&world, &decisions);
    try world.remember(known, open, 0, 0);

    // The actor knows only `known`, so the higher-scoring card is invisible.
    try world.remember(seat, knows, known.to_int(), 0);
    const first = try step(&world, &decisions);
    try testing.expectEqual(@as(usize, 1), first.len);
    try testing.expectEqual(known, first.items[0].option);

    // A rejection of the known card leaves no offered option, so nothing fires.
    _ = world.forget(known, open, null);
    _ = try step(&world, &decisions);
    try world.remember(known, open, 0, 0);
    try world.remember(seat, rejects, known.to_int(), 0);
    const second = try step(&world, &decisions);
    try testing.expectEqual(@as(usize, 0), second.len);
    try testing.expectEqual(@as(?EntityId, null), chosen(&world, decisions[0].decision.entity));
}
