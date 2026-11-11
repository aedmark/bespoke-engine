//! Proactive social agency: agendas (P33-01, D-038, D-056).
//!
//! An agenda is a script-declared intention: an actor sets out to intercept a target when a set
//! of trigger clauses holds. This module decides which agendas are pursuing; P33-02 adds the
//! pursuit itself and the interception. All lifecycle state is World facts on the agenda's own
//! entity, so save, rewind, and branch restore need no agency snapshot:
//!   AgendaState(Agenda, Idle | Pursuing | Done)   property
//!   AgendaCooldown(Agenda)                         presence, expiring after `cooldown` ticks

const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const SpatialSystem = spatial_mod.SpatialSystem;

pub const MAX_CLAUSES: usize = 8;
pub const MAX_AGENDAS: usize = 32;

pub const STATE_RELATION = "AgendaState";
pub const COOLDOWN_RELATION = "AgendaCooldown";
pub const STAGE_NAMES = [_][]const u8{ "Idle", "Pursuing", "Done" };

pub const Stage = enum(u8) { idle = 0, pursuing = 1, done = 2 };

pub const Error = error{InvalidAgenda};

/// One trigger line. `relation` is interned program text; a null subject or object is the `_`
/// wildcard. `negated` lines (`unless`) must not hold; the others (`requires`) must.
pub const Clause = struct {
    relation: []const u8,
    subject: ?EntityId = null,
    object: ?EntityId = null,
    negated: bool = false,
};

/// Immutable script program data for one agenda.
pub const Agenda = struct {
    entity: EntityId,
    actor: EntityId,
    target: EntityId,
    priority: u16 = 0,
    cooldown_ticks: u32 = 0,
    once: bool = false,
    clauses: []const Clause,
};

pub fn validate(agenda: Agenda) !void {
    if (agenda.entity == .none or agenda.actor == .none or agenda.target == .none) return Error.InvalidAgenda;
    if (agenda.actor == agenda.target) return Error.InvalidAgenda;
    if (agenda.clauses.len == 0 or agenda.clauses.len > MAX_CLAUSES) return Error.InvalidAgenda;
    for (agenda.clauses) |clause| if (clause.relation.len == 0) return Error.InvalidAgenda;
}

/// Compiler-owned declaration.
pub const Declaration = struct {
    agenda: Agenda,

    pub fn deinit_owned(self: *Declaration, allocator: std.mem.Allocator) void {
        allocator.free(self.agenda.clauses);
        self.* = undefined;
    }
};

/// Validates a program's agendas together: entities must be unique.
pub fn validate_all(declarations: []const Declaration) !void {
    if (declarations.len > MAX_AGENDAS) return Error.InvalidAgenda;
    for (declarations, 0..) |decl, i| {
        try validate(decl.agenda);
        for (declarations[0..i]) |prior| if (prior.agenda.entity == decl.agenda.entity) return Error.InvalidAgenda;
    }
}

const Vocabulary = struct {
    state: RelationKind,
    cooldown: RelationKind,
    stages: [STAGE_NAMES.len]EntityId,

    fn intern(world: *World) !Vocabulary {
        var v = Vocabulary{
            .state = try world.intern_relation(STATE_RELATION, .property),
            .cooldown = try world.intern_relation(COOLDOWN_RELATION, .set),
            .stages = undefined,
        };
        // A script that declared either name with the other type would make stage writes
        // append rows instead of replacing them, or collapse cooldowns.
        if (world.get_relation_meta(v.state).?.rel_type != .property or
            world.get_relation_meta(v.cooldown).?.rel_type != .set) return Error.InvalidAgenda;
        for (STAGE_NAMES, 0..) |name, i| v.stages[i] = try world.intern_entity(name);
        return v;
    }

    fn stage_of(self: Vocabulary, world: *const World, agenda: EntityId) ?Stage {
        const raw = world.get_property(agenda, self.state) orelse return null;
        for (self.stages, 0..) |entity, i| if (entity.to_int() == raw) return @enumFromInt(i);
        return null;
    }

    fn set(self: Vocabulary, world: *World, agenda: EntityId, stage: Stage) !void {
        try world.remember(agenda, self.state, self.stages[@intFromEnum(stage)].to_int(), 0);
    }
};

/// The stage an agenda is in, or null before seeding.
pub fn stage_of(world: *const World, agenda: EntityId) ?Stage {
    const relation = world.lookup_relation(STATE_RELATION) orelse return null;
    const raw = world.get_property(agenda, relation) orelse return null;
    for (STAGE_NAMES, 0..) |name, i| {
        const entity = world.lookup_entity(name) orelse continue;
        if (entity.to_int() == raw) return @enumFromInt(i);
    }
    return null;
}

/// Gives every agenda without a stage the `Idle` stage. Repeated calls, including after a
/// restore, leave existing stages alone.
pub fn seed(world: *World, declarations: []const Declaration) !void {
    if (declarations.len == 0) return;
    const v = try Vocabulary.intern(world);
    for (declarations) |decl| {
        if (v.stage_of(world, decl.agenda.entity) == null) try v.set(world, decl.agenda.entity, .idle);
    }
}

/// True when every trigger line holds in the current World. A relation no fact has ever used
/// cannot hold, so a `requires` on it fails and an `unless` on it passes.
pub fn triggered(world: *const World, agenda: Agenda) bool {
    for (agenda.clauses) |clause| {
        const present = if (world.lookup_relation(clause.relation)) |relation|
            world.has_fact(clause.subject, relation, if (clause.object) |o| o.to_int() else null)
        else
            false;
        if (present == clause.negated) return false;
    }
    return true;
}

/// Route cost from the actor's waypoint to the target's, by edge cost along A*'s path. An
/// actor or target without a motor agent, or with no route, costs the maximum, so contention
/// still resolves by declaration order.
fn route_cost(spatial_opt: ?*const SpatialSystem, allocator: std.mem.Allocator, actor: EntityId, target: EntityId) !u64 {
    const spatial = spatial_opt orelse return std.math.maxInt(u64);
    const from = spatial.get_current_waypoint(actor) orelse return std.math.maxInt(u64);
    const to = spatial.get_current_waypoint(target) orelse return std.math.maxInt(u64);
    if (from == to) return 0;
    const path = (try spatial.graph.find_path(from, to, allocator)) orelse return std.math.maxInt(u64);
    defer allocator.free(path);
    var cost: u64 = 0;
    var prev = from;
    for (path) |wp| {
        if (wp == prev) continue;
        const a = spatial.graph.get_waypoint(prev).?.pos;
        const b = spatial.graph.get_waypoint(wp).?.pos;
        cost += a.distance_to(b);
        prev = wp;
    }
    return cost;
}

/// Advances every agenda by one tick (P33-01, D-056). Runs in `host.tick` after the VM tick, so
/// expired cooldowns are already pruned.
/// 1. A pursuing agenda whose trigger no longer holds returns to `Idle`, with no cooldown.
/// 2. Idle, triggered agendas without a cooldown are candidates. For each target with no
///    pursuit already under way, the candidate with the highest priority, then the lowest
///    route cost, then the earliest declaration starts pursuing. An actor pursues one agenda
///    at a time; the others stay idle and are reconsidered next tick.
pub fn step(world: *World, spatial: ?*const SpatialSystem, allocator: std.mem.Allocator, declarations: []const Declaration) !void {
    if (declarations.len == 0) return;
    const v = try Vocabulary.intern(world);

    var stages: [MAX_AGENDAS]Stage = undefined;
    for (declarations, 0..) |decl, i| {
        const agenda = decl.agenda;
        var stage = v.stage_of(world, agenda.entity) orelse .idle;
        if (stage == .pursuing and !triggered(world, agenda)) {
            try v.set(world, agenda.entity, .idle);
            stage = .idle;
        }
        stages[i] = stage;
    }

    for (declarations, 0..) |decl, i| {
        if (stages[i] != .idle) continue;
        const agenda = decl.agenda;
        if (busy(declarations, stages[0..declarations.len], agenda)) continue;
        if (world.has_fact(agenda.entity, v.cooldown, null) or !triggered(world, agenda)) continue;

        // The first eligible candidate for this target decides for the whole target, so scan
        // every rival once here; later rivals are skipped by `busy` after the winner is set.
        var best = i;
        var best_cost = try route_cost(spatial, allocator, agenda.actor, agenda.target);
        for (declarations[i + 1 ..], i + 1..) |rival_decl, j| {
            const rival = rival_decl.agenda;
            if (rival.target != agenda.target or stages[j] != .idle) continue;
            if (busy(declarations, stages[0..declarations.len], rival)) continue;
            if (world.has_fact(rival.entity, v.cooldown, null) or !triggered(world, rival)) continue;
            const rival_cost = try route_cost(spatial, allocator, rival.actor, rival.target);
            const current = declarations[best].agenda;
            if (rival.priority > current.priority or (rival.priority == current.priority and rival_cost < best_cost)) {
                best = j;
                best_cost = rival_cost;
            }
        }
        try v.set(world, declarations[best].agenda.entity, .pursuing);
        stages[best] = .pursuing;
    }
}

/// True when the agenda's target is already being pursued, or its actor already pursues.
fn busy(declarations: []const Declaration, stages: []const Stage, agenda: Agenda) bool {
    for (declarations, stages) |other, stage| {
        if (stage != .pursuing) continue;
        if (other.agenda.target == agenda.target or other.agenda.actor == agenda.actor) return true;
    }
    return false;
}

/// Ends a pursuit (D-056 point 5): a `once` agenda becomes `Done`; any other returns to `Idle`
/// and starts its cooldown. Resolving an agenda that is not pursuing is an error, so a host
/// cannot finish an encounter that never started.
pub fn resolve(world: *World, agenda: Agenda) !void {
    const v = try Vocabulary.intern(world);
    if (v.stage_of(world, agenda.entity) != .pursuing) return Error.InvalidAgenda;
    if (agenda.once) {
        try v.set(world, agenda.entity, .done);
        return;
    }
    try v.set(world, agenda.entity, .idle);
    if (agenda.cooldown_ticks > 0) try world.remember(agenda.entity, v.cooldown, 0, agenda.cooldown_ticks);
}

const testing = std.testing;

const Fixture = struct {
    world: World,
    investigated: RelationKind,
    warned: RelationKind,
    hero: EntityId,
    shed: EntityId,

    fn init() !Fixture {
        var world = try World.init(testing.allocator, 256 * 1024);
        errdefer world.deinit();
        return .{
            .investigated = try world.intern_relation("Investigated", .set),
            .warned = try world.intern_relation("Warned", .set),
            .hero = try world.intern_entity("TestHero"),
            .shed = try world.intern_entity("TestShed"),
            .world = world,
        };
    }

    fn agenda(self: *Fixture, name: []const u8, actor: []const u8, priority: u16, clauses: []const Clause) !Agenda {
        return .{
            .entity = try self.world.intern_entity(name),
            .actor = try self.world.intern_entity(actor),
            .target = self.hero,
            .priority = priority,
            .clauses = clauses,
        };
    }
};

test "P33-01: requires and unless clauses trigger on facts and omissions" {
    var fx = try Fixture.init();
    defer fx.world.deinit();
    const clauses = [_]Clause{
        .{ .relation = "Investigated", .subject = fx.hero, .object = fx.shed },
        .{ .relation = "Warned", .subject = fx.hero, .negated = true },
    };
    const agenda = try fx.agenda("TestWarnOff", "TestKeeper", 1, &clauses);
    try validate(agenda);
    try testing.expect(!triggered(&fx.world, agenda));
    try fx.world.remember(fx.hero, fx.investigated, fx.shed.to_int(), 0);
    try testing.expect(triggered(&fx.world, agenda));
    // The omission ends once the hero has been warned (any object).
    try fx.world.remember(fx.hero, fx.warned, 0, 0);
    try testing.expect(!triggered(&fx.world, agenda));

    // A wildcard subject matches anyone; a relation never used fails `requires`.
    const wild = [_]Clause{.{ .relation = "Investigated", .object = fx.shed }};
    try testing.expect(triggered(&fx.world, try fx.agenda("TestWild", "TestKeeper", 0, &wild)));
    const unknown = [_]Clause{.{ .relation = "NeverUsed" }};
    try testing.expect(!triggered(&fx.world, try fx.agenda("TestUnknown", "TestKeeper", 0, &unknown)));
    const unknown_unless = [_]Clause{.{ .relation = "NeverUsed", .negated = true }};
    try testing.expect(triggered(&fx.world, try fx.agenda("TestUnknownUnless", "TestKeeper", 0, &unknown_unless)));
}

test "P33-01: pursuit starts, abandons, resolves with cooldown, and rewinds with the World" {
    var fx = try Fixture.init();
    defer fx.world.deinit();
    const clauses = [_]Clause{.{ .relation = "Investigated", .subject = fx.hero, .object = fx.shed }};
    var agenda = try fx.agenda("TestWarnOff", "TestKeeper", 1, &clauses);
    agenda.cooldown_ticks = 3;
    const decls = [_]Declaration{.{ .agenda = agenda }};
    try seed(&fx.world, &decls);
    try testing.expectEqual(Stage.idle, stage_of(&fx.world, agenda.entity).?);
    try step(&fx.world, null, testing.allocator, &decls);
    try testing.expectEqual(Stage.idle, stage_of(&fx.world, agenda.entity).?);

    try fx.world.remember(fx.hero, fx.investigated, fx.shed.to_int(), 0);
    try step(&fx.world, null, testing.allocator, &decls);
    try testing.expectEqual(Stage.pursuing, stage_of(&fx.world, agenda.entity).?);

    var snapshot = std.ArrayList(u8).init(testing.allocator);
    defer snapshot.deinit();
    try fx.world.save_state(snapshot.writer());

    // The trigger lapses: the agenda gives up without a cooldown.
    _ = fx.world.forget(fx.hero, fx.investigated, null);
    try step(&fx.world, null, testing.allocator, &decls);
    try testing.expectEqual(Stage.idle, stage_of(&fx.world, agenda.entity).?);
    try testing.expectError(Error.InvalidAgenda, resolve(&fx.world, agenda));

    var stream = std.io.fixedBufferStream(snapshot.items);
    try fx.world.restore_state(stream.reader());
    try testing.expectEqual(Stage.pursuing, stage_of(&fx.world, agenda.entity).?);

    // Resolution starts a three-tick cooldown, after which the still-true trigger fires again.
    try resolve(&fx.world, agenda);
    try testing.expectEqual(Stage.idle, stage_of(&fx.world, agenda.entity).?);
    var ticks: u32 = 0;
    while (stage_of(&fx.world, agenda.entity).? != .pursuing) : (ticks += 1) {
        _ = fx.world.step_tick();
        try step(&fx.world, null, testing.allocator, &decls);
        try testing.expect(ticks < 10);
    }
    try testing.expectEqual(@as(u32, 3), ticks);

    // A `once` agenda finishes for good.
    agenda.once = true;
    try resolve(&fx.world, agenda);
    try testing.expectEqual(Stage.done, stage_of(&fx.world, agenda.entity).?);
    _ = fx.world.step_tick();
    try step(&fx.world, null, testing.allocator, &(.{Declaration{ .agenda = agenda }}));
    try testing.expectEqual(Stage.done, stage_of(&fx.world, agenda.entity).?);
}

test "P33-01: contention picks priority, then route cost, then declaration order" {
    var fx = try Fixture.init();
    defer fx.world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    const room = try fx.world.intern_entity("TestManor");
    const hall = try spatial.graph.add_waypoint(room, 0, 0, "TestHall");
    const near = try spatial.graph.add_waypoint(room, 10, 0, "TestNear");
    const far = try spatial.graph.add_waypoint(room, 30, 0, "TestFar");
    try spatial.graph.connect(hall, near, null);
    try spatial.graph.connect(near, far, null);

    const clauses = [_]Clause{.{ .relation = "Investigated", .subject = fx.hero }};
    const far_low = try fx.agenda("TestFarLow", "TestFarKeeper", 1, &clauses);
    const near_low = try fx.agenda("TestNearLow", "TestNearKeeper", 1, &clauses);
    try spatial.register_entity(fx.hero, hall, 1);
    try spatial.register_entity(far_low.actor, far, 1);
    try spatial.register_entity(near_low.actor, near, 1);
    try fx.world.remember(fx.hero, fx.investigated, fx.shed.to_int(), 0);

    // Equal priority: the nearer actor wins although declared second.
    {
        const decls = [_]Declaration{ .{ .agenda = far_low }, .{ .agenda = near_low } };
        try seed(&fx.world, &decls);
        try step(&fx.world, &spatial, testing.allocator, &decls);
        try testing.expectEqual(Stage.idle, stage_of(&fx.world, far_low.entity).?);
        try testing.expectEqual(Stage.pursuing, stage_of(&fx.world, near_low.entity).?);
        // An existing pursuit is not preempted, even by a higher priority.
        const urgent = try fx.agenda("TestUrgent", "TestUrgentKeeper", 9, &clauses);
        const more = [_]Declaration{ .{ .agenda = far_low }, .{ .agenda = near_low }, .{ .agenda = urgent } };
        try seed(&fx.world, &more);
        try step(&fx.world, &spatial, testing.allocator, &more);
        try testing.expectEqual(Stage.idle, stage_of(&fx.world, urgent.entity).?);
        try resolve(&fx.world, near_low);
    }
    // Higher priority beats distance.
    {
        const far_high = try fx.agenda("TestFarHigh", "TestFarKeeper", 5, &clauses);
        const decls = [_]Declaration{ .{ .agenda = near_low }, .{ .agenda = far_high } };
        try seed(&fx.world, &decls);
        try step(&fx.world, &spatial, testing.allocator, &decls);
        try testing.expectEqual(Stage.pursuing, stage_of(&fx.world, far_high.entity).?);
        try testing.expectEqual(Stage.idle, stage_of(&fx.world, near_low.entity).?);
        try resolve(&fx.world, far_high);
    }
    // Without a spatial system every cost ties, so declaration order decides.
    {
        const decls = [_]Declaration{ .{ .agenda = far_low }, .{ .agenda = near_low } };
        try step(&fx.world, null, testing.allocator, &decls);
        try testing.expectEqual(Stage.pursuing, stage_of(&fx.world, far_low.entity).?);
        try testing.expectEqual(Stage.idle, stage_of(&fx.world, near_low.entity).?);
    }
}

test "P33-01: validation rejects self-targeting, empty, and duplicate agendas" {
    var fx = try Fixture.init();
    defer fx.world.deinit();
    const clauses = [_]Clause{.{ .relation = "Investigated" }};
    var agenda = try fx.agenda("TestAgenda", "TestKeeper", 0, &clauses);
    agenda.target = agenda.actor;
    try testing.expectError(Error.InvalidAgenda, validate(agenda));
    agenda = try fx.agenda("TestAgenda", "TestKeeper", 0, &.{});
    try testing.expectError(Error.InvalidAgenda, validate(agenda));
    agenda = try fx.agenda("TestAgenda", "TestKeeper", 0, &clauses);
    try testing.expectError(Error.InvalidAgenda, validate_all(&.{ .{ .agenda = agenda }, .{ .agenda = agenda } }));
}
