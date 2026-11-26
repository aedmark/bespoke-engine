//! Goals and hints (P44-01, D-134).
//!
//! A `goal` declaration names the needs a player must meet. A need is one fact pattern with
//! optional prerequisite needs and optional authored text per tier. The declaration is program
//! data owned by `CompiledProgram`, and `query` reads facts without writing any, so a save, a
//! rewind, and a replay see the same hint for the same world (D-003).
//!
//! The search is Holmesian first (D-126): the first unmet frontier need whose terms the player
//! character knows, phrased from those terms. When no frontier need is one the character could
//! reason about, the search falls back to the author's whole goal graph, which may name a place
//! or a thing the character has not met. Each result records the path that produced it.
const std = @import("std");
const limits_mod = @import("limits.zig");
const phrase = @import("phrase.zig");
const world_mod = @import("world.zig");
const World = world_mod.World;
const EntityId = world_mod.EntityId;
const value_mod = @import("value.zig");

/// Goals and needs per goal: sanity ceilings a script raises with `limit` (D-167, D-183). The
/// `MAX_` values are the fixed safety caps the loader holds untrusted packages to; the
/// frontier walk is linear in needs, so the cap keeps one query cheap.
pub const DEFAULT_GOALS: usize = limits_mod.default_of(.goals);
pub const MAX_GOALS: usize = limits_mod.cap_of(.goals);
pub const DEFAULT_NEEDS: usize = limits_mod.default_of(.needs);
pub const MAX_NEEDS: usize = limits_mod.cap_of(.needs);
pub const MAX_AFTER: usize = 8;
/// Tiers 1 to 3 have generated text (room, thing, relation); higher tiers exist only where a
/// script writes them (D-177, D-183). Tiers per need are a sanity ceiling like the others.
pub const GENERATED_TIERS: usize = 3;
pub const DEFAULT_TIERS: usize = limits_mod.default_of(.hints);
pub const MAX_TIERS: usize = limits_mod.cap_of(.hints);
pub const MAX_HINT_TEXT: usize = 120;
pub const MAX_HINT_WORDS: usize = 64;

/// Relations a player's knowledge is read from, in priority order. `Rejects` beats both
/// (P21-02, D-015): a rejected proposition is not known.
pub const KNOWS_RELATION = "Knows";
pub const BELIEVES_RELATION = "Believes";
pub const REJECTS_RELATION = "Rejects";

pub const Error = error{ InvalidGoal, HintTextTooLong };

/// A hint tier, counted from 1. Tiers 1 to 3 name the room, the thing, and the relation and
/// have generated text; a higher tier exists only where a script writes it (D-183).
pub const Tier = enum(u8) {
    room = 1,
    thing = 2,
    relation = 3,
    _,

    /// The tier numbered `value`, from 1 to the safety cap; null outside it.
    pub fn fromInt(value: u32) ?Tier {
        if (value == 0 or value > MAX_TIERS) return null;
        return @enumFromInt(value);
    }

    pub fn number(self: Tier) u8 {
        return @intFromEnum(self);
    }

    pub fn generated(self: Tier) bool {
        return self.number() <= GENERATED_TIERS;
    }

    /// Which part of the need the tier names, for a transcript or a test.
    pub fn label(self: Tier) []const u8 {
        return switch (self) {
            .room => "room",
            .thing => "thing",
            .relation => "relation",
            _ => "authored",
        };
    }
};

pub const Path = enum { holmesian, doylian };

/// One authored override. `text` is owned by the declaration.
pub const Authored = struct {
    tier: Tier,
    text: []const u8,
};

/// One need: the fact pattern that satisfies it, its prerequisites, the room tier 1 names, and
/// any authored text. `subject` and `object` are null for the `_` wildcard.
pub const Need = struct {
    entity: EntityId,
    relation: []const u8,
    subject: ?EntityId = null,
    object: ?EntityId = null,
    after: []const EntityId = &.{},
    room: ?EntityId = null,
    hints: []const Authored = &.{},
};

pub const Goal = struct {
    entity: EntityId,
    needs: []const Need,
};

/// Compiler-owned declaration. The slices are freed by `deinit_owned`; the relation text and
/// entity names are borrowed from the World's tables, which outlives the program.
pub const Declaration = struct {
    goal: Goal,

    pub fn deinit_owned(self: *Declaration, allocator: std.mem.Allocator) void {
        for (self.goal.needs) |need| {
            for (need.hints) |hint| allocator.free(hint.text);
            allocator.free(need.hints);
            allocator.free(need.after);
        }
        allocator.free(self.goal.needs);
        self.* = undefined;
    }
};

pub const Hint = struct {
    goal: EntityId,
    need: EntityId,
    tier: Tier,
    path: Path,
    authored: bool,
    /// For an authored hint this borrows the declaration; otherwise it is the caller's buffer.
    text: []const u8,
};

pub fn validate(declaration: Declaration) Error!void {
    const goal = declaration.goal;
    if (goal.entity == .none) return Error.InvalidGoal;
    if (goal.needs.len == 0 or goal.needs.len > MAX_NEEDS) return Error.InvalidGoal;
    for (goal.needs, 0..) |need, i| {
        if (need.entity == .none or need.relation.len == 0) return Error.InvalidGoal;
        if (need.room == null or need.room.? == .none) return Error.InvalidGoal;
        if (need.after.len > MAX_AFTER) return Error.InvalidGoal;
        for (need.after) |prerequisite| {
            var found = false;
            for (goal.needs) |candidate| if (candidate.entity == prerequisite) {
                found = true;
                break;
            };
            if (!found or prerequisite == need.entity) return Error.InvalidGoal;
        }
        if (need.hints.len > MAX_TIERS) return Error.InvalidGoal;
        var has_authored_thing = false;
        for (need.hints, 0..) |hint, hi| {
            if (Tier.fromInt(hint.tier.number()) == null) return Error.InvalidGoal;
            if (hint.text.len == 0 or hint.text.len > MAX_HINT_TEXT) return Error.InvalidGoal;
            if (hint.tier == .thing) has_authored_thing = true;
            for (need.hints[0..hi]) |prior| if (prior.tier == hint.tier) return Error.InvalidGoal;
        }
        if (need.subject == null and need.object == null and !has_authored_thing) return Error.InvalidGoal;
        for (goal.needs[0..i]) |prior| if (prior.entity == need.entity) return Error.InvalidGoal;
    }
    // A cycle makes every need in it forever unready, so the authoring mistake is refused
    // rather than left to stall the frontier.
    if (has_cycle(goal.needs)) return Error.InvalidGoal;
}

fn index_of(needs: []const Need, entity: EntityId) ?usize {
    for (needs, 0..) |need, idx| if (need.entity == entity) return idx;
    return null;
}

fn has_cycle(needs: []const Need) bool {
    var state: [MAX_NEEDS]u8 = @splat(0); // 0 unvisited, 1 on stack, 2 done
    for (0..needs.len) |i| {
        if (state[i] == 0 and visit_cycle(needs, i, &state)) return true;
    }
    return false;
}

fn visit_cycle(needs: []const Need, idx: usize, state: *[MAX_NEEDS]u8) bool {
    state[idx] = 1;
    for (needs[idx].after) |dep| {
        const dep_idx = index_of(needs, dep) orelse continue;
        if (state[dep_idx] == 1) return true;
        if (state[dep_idx] == 0 and visit_cycle(needs, dep_idx, state)) return true;
    }
    state[idx] = 2;
    return false;
}

/// Validates a program's goals together: goal and need entities must be unique across the file,
/// because both are interned by name.
pub fn validate_all(declarations: []const Declaration) Error!void {
    if (declarations.len > MAX_GOALS) return Error.InvalidGoal;
    for (declarations, 0..) |declaration, i| {
        try validate(declaration);
        for (declarations[0..i]) |prior| {
            if (prior.goal.entity == declaration.goal.entity) return Error.InvalidGoal;
            for (prior.goal.needs) |prior_need| for (declaration.goal.needs) |need| {
                if (prior_need.entity == need.entity) return Error.InvalidGoal;
            };
        }
    }
}

fn relation_kind(world: *const World, name: []const u8) ?world_mod.RelationKind {
    return world.lookup_relation(name);
}

/// True when any fact matches the need's pattern. A null term is the `_` wildcard.
pub fn satisfied(world: *const World, need: Need) bool {
    const relation = relation_kind(world, need.relation) orelse return false;
    return world.has_fact(need.subject, relation, if (need.object) |e| e.to_int() else null);
}

/// The first unmet need whose every prerequisite holds, or null when the goal is done.
pub fn frontier(world: *const World, needs: []const Need) ?*const Need {
    for (needs) |*need| {
        if (satisfied(world, need.*)) continue;
        var ready = true;
        for (need.after) |prerequisite| {
            var held = false;
            for (needs) |candidate| if (candidate.entity == prerequisite and satisfied(world, candidate)) {
                held = true;
                break;
            };
            if (!held) {
                ready = false;
                break;
            }
        }
        if (ready) return need;
    }
    return null;
}

fn rejects(world: *const World, player: EntityId, entity: EntityId) bool {
    const relation = relation_kind(world, REJECTS_RELATION) orelse return false;
    return world.has_fact(player, relation, entity.to_int());
}

/// What the player character knows: `Knows` or `Believes`, unless `Rejects` says otherwise.
/// Until per-character knowledge lands (P44-05), a script asserts these facts when a scene
/// shows the character something (D-126).
pub fn knows(world: *const World, player: EntityId, entity: EntityId) bool {
    if (rejects(world, player, entity)) return false;
    for ([_][]const u8{ KNOWS_RELATION, BELIEVES_RELATION }) |name| {
        if (relation_kind(world, name)) |relation| {
            if (world.has_fact(player, relation, entity.to_int())) return true;
        }
    }
    return false;
}

/// The terms a tier names. A tier 1 hint names the room as well as the pattern's entities, so
/// the room must be known before the character could point at it.
fn terms_known(world: *const World, player: EntityId, need: Need, tier: Tier) bool {
    if (need.subject) |subject| if (subject != player and !knows(world, player, subject)) return false;
    if (need.object) |object| if (object != player and !object_known(world, player, need.subject, object)) return false;
    if (tier == .room) {
        const room = need.room orelse return false;
        if (!knows(world, player, room)) return false;
    }
    return true;
}

/// A need's object is known as an entity, except a value axis about a character: knowing that
/// `Mercy` exists is not knowing that Oswin holds it, so `met Appealed(Oswin, Mercy)` is
/// Holmesian only once the player knows `Mercy of Oswin` (P45-05, D-149).
fn object_known(world: *const World, player: EntityId, subject: ?EntityId, object: EntityId) bool {
    const axis = value_mod.axis_of_entity(world, object) orelse return knows(world, player, object);
    const character = subject orelse return knows(world, player, object);
    var buf: [128]u8 = undefined;
    const name = value_mod.known_value_name(world, axis, character, &buf) catch return false;
    const value = world.lookup_entity(name) orelse return false;
    return knows(world, player, value);
}

fn authored(need: Need, tier: Tier) ?[]const u8 {
    for (need.hints) |hint| if (hint.tier == tier) return hint.text;
    return null;
}

/// How many tiers a need offers: the three generated ones, or more when the script wrote a
/// higher one. A host's hint control steps from 1 to this.
pub fn tier_count(need: Need) usize {
    var top: usize = GENERATED_TIERS;
    for (need.hints) |hint| top = @max(top, hint.tier.number());
    return top;
}

/// The tier a need answers `asked` with: the tier itself when the need has it, else the
/// highest tier below it that it has, so asking past a need's last tier repeats that tier
/// (D-183). Tiers 1 to 3 always exist.
pub fn tier_for(need: Need, asked: Tier) Tier {
    if (asked.generated()) return asked;
    var best: Tier = .relation;
    for (need.hints) |hint| {
        if (hint.tier.number() <= asked.number() and hint.tier.number() > best.number()) best = hint.tier;
    }
    return best;
}

fn human_name(name: []const u8, out: []u8) []const u8 {
    var n: usize = 0;
    for (name, 0..) |ch, i| {
        if (ch == '_') {
            if (n < out.len) {
                out[n] = ' ';
                n += 1;
            }
            continue;
        }
        if (i > 0 and std.ascii.isUpper(ch) and name[i - 1] != ' ' and n + 1 < out.len) {
            out[n] = ' ';
            n += 1;
        }
        if (n < out.len) {
            out[n] = ch;
            n += 1;
        }
    }
    return out[0..n];
}

/// What players read for `entity`: its `name` line, else its identifier as words (D-179).
fn name_of(world: *const World, entity: EntityId, out: []u8) []const u8 {
    if (world.display_text(entity)) |text| return text;
    return human_name(world.get_entity_name(entity) orelse "", out);
}

/// The base case: a tier with no authored text, built from the need's room, its thing, and its
/// relation, using the names the script declared.
fn generate(world: *const World, need: Need, tier: Tier, buf: []u8) Error![]const u8 {
    switch (tier) {
        // `tier_for` only lands above 3 on a tier the need wrote, so there is no text to make.
        _ => return Error.InvalidGoal,
        .room => {
            const room = need.room orelse return Error.InvalidGoal;
            var words: [MAX_HINT_WORDS]u8 = undefined;
            return phrase.render(world, .hint_room, &.{.{ .slot = "room", .value = name_of(world, room, &words) }}, buf) catch Error.HintTextTooLong;
        },
        .thing => {
            const thing = need.object orelse need.subject orelse return Error.InvalidGoal;
            var words: [MAX_HINT_WORDS]u8 = undefined;
            return phrase.render(world, .hint_thing, &.{.{ .slot = "thing", .value = name_of(world, thing, &words) }}, buf) catch Error.HintTextTooLong;
        },
        .relation => {
            var subject_words: [MAX_HINT_WORDS]u8 = undefined;
            const subject = if (need.subject) |entity| name_of(world, entity, &subject_words) else "_";
            if (need.object) |entity| {
                var object_words: [MAX_HINT_WORDS]u8 = undefined;
                return phrase.render(world, .hint_fact, &.{
                    .{ .slot = "relation", .value = need.relation },
                    .{ .slot = "subject", .value = subject },
                    .{ .slot = "object", .value = name_of(world, entity, &object_words) },
                }, buf) catch Error.HintTextTooLong;
            }
            return phrase.render(world, .hint_state, &.{
                .{ .slot = "relation", .value = need.relation },
                .{ .slot = "subject", .value = subject },
            }, buf) catch Error.HintTextTooLong;
        },
    }
}

fn report(world: *const World, goal: EntityId, need: Need, asked: Tier, path: Path, buf: []u8) Error!Hint {
    const tier = tier_for(need, asked);
    const text = authored(need, tier);
    return .{
        .goal = goal,
        .need = need.entity,
        .tier = tier,
        .path = path,
        .authored = text != null,
        .text = text orelse try generate(world, need, tier, buf),
    };
}

/// Reports the nearest unmet need at `tier`, or at its highest tier below it (`tier_for`); the
/// result names the tier it answered with. Holmesian first: each goal's frontier need, when
/// the player knows its terms. When no goal offers one, the first unmet need in declaration
/// order answers as the author (D-126). Null means every need of every goal holds.
pub fn query(
    goals: []const Declaration,
    world: *const World,
    player: EntityId,
    tier: Tier,
    buf: []u8,
) Error!?Hint {
    for (goals) |declaration| {
        const need = (frontier(world, declaration.goal.needs) orelse continue).*;
        if (!terms_known(world, player, need, tier_for(need, tier))) continue;
        return try report(world, declaration.goal.entity, need, tier, .holmesian, buf);
    }
    for (goals) |declaration| {
        for (declaration.goal.needs) |*need| {
            if (satisfied(world, need.*)) continue;
            return try report(world, declaration.goal.entity, need.*, tier, .doylian, buf);
        }
    }
    return null;
}

test "P44-01: a goal with no hint text yields room, thing, and relation tiers" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    _ = try world.intern_relation("Carries", .set);
    const hero = try world.intern_entity("Hero");
    const slab = try world.intern_entity("ExposureSlip");
    const archive = try world.intern_entity("Archive");
    for ([_]EntityId{ slab, archive }) |known| {
        try world.remember(hero, try world.intern_relation("Knows", .set), known.to_int(), 0);
    }

    var needs = [_]Need{.{
        .entity = try world.intern_entity("TakeTheSlip"),
        .relation = "Carries",
        .subject = hero,
        .object = slab,
        .room = archive,
    }};
    const declaration = Declaration{ .goal = .{ .entity = try world.intern_entity("RecoverThePlate"), .needs = &needs } };
    try validate(declaration);

    var buf: [128]u8 = undefined;
    const room = (try query(&.{declaration}, &world, hero, .room, &buf)).?;
    try testing.expectEqual(Path.holmesian, room.path);
    try testing.expectEqualStrings("Look in the Archive.", room.text);
    const thing = (try query(&.{declaration}, &world, hero, .thing, &buf)).?;
    try testing.expectEqualStrings("You need the Exposure Slip.", thing.text);
    const relation = (try query(&.{declaration}, &world, hero, .relation, &buf)).?;
    try testing.expectEqualStrings("You need Carries(Hero, Exposure Slip).", relation.text);
    try testing.expect(!room.authored);
}

test "P44-01: an unknown term falls back to the author's graph and says so" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const hero = try world.intern_entity("Hero");
    const slab = try world.intern_entity("ExposureSlip");
    const archive = try world.intern_entity("Archive");
    var needs = [_]Need{.{
        .entity = try world.intern_entity("TakeTheSlip"),
        .relation = "Carries",
        .subject = hero,
        .object = slab,
        .room = archive,
    }};
    const declaration = Declaration{ .goal = .{ .entity = try world.intern_entity("RecoverThePlate"), .needs = &needs } };

    var buf: [128]u8 = undefined;
    const hint = (try query(&.{declaration}, &world, hero, .room, &buf)).?;
    try testing.expectEqual(Path.doylian, hint.path);
    try testing.expectEqualStrings("Look in the Archive.", hint.text);

    // Knowing the room and the thing makes the same need Holmesian.
    try world.remember(hero, try world.intern_relation("Knows", .set), slab.to_int(), 0);
    try world.remember(hero, try world.intern_relation("Knows", .set), archive.to_int(), 0);
    try testing.expectEqual(Path.holmesian, (try query(&.{declaration}, &world, hero, .room, &buf)).?.path);
}

test "P44-01: a need waits behind its prerequisite, and Rejects beats Knows" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const hero = try world.intern_entity("Hero");
    const slip = try world.intern_entity("ExposureSlip");
    const log = try world.intern_entity("TelescopeLog");
    const archive = try world.intern_entity("Archive");
    const dome = try world.intern_entity("Dome");
    for ([_]EntityId{ slip, log, archive, dome }) |known| {
        try world.remember(hero, try world.intern_relation("Knows", .set), known.to_int(), 0);
    }
    const take = try world.intern_entity("TakeTheSlip");
    const read = try world.intern_entity("ReadTheLog");
    const after = [_]EntityId{take};
    var needs = [_]Need{
        .{ .entity = take, .relation = "Carries", .subject = hero, .object = slip, .room = archive },
        .{ .entity = read, .relation = "Read", .subject = hero, .object = log, .after = &after, .room = dome },
    };
    const declaration = Declaration{ .goal = .{ .entity = try world.intern_entity("RecoverThePlate"), .needs = &needs } };
    try validate(declaration);

    var buf: [128]u8 = undefined;
    // The log need is unmet but blocked, so the slip answers.
    try testing.expectEqual(take, (try query(&.{declaration}, &world, hero, .relation, &buf)).?.need);
    try world.remember(hero, try world.intern_relation("Carries", .set), slip.to_int(), 0);
    try testing.expectEqual(read, (try query(&.{declaration}, &world, hero, .relation, &buf)).?.need);

    // A rejected claim is not knowledge, so the next query speaks as the author.
    try world.remember(hero, try world.intern_relation("Rejects", .set), log.to_int(), 0);
    const hint = (try query(&.{declaration}, &world, hero, .relation, &buf)).?;
    try testing.expectEqual(Path.doylian, hint.path);
}

test "P44-01: authored text replaces a generated tier and no hint remains when every need holds" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    _ = try world.intern_relation("Carries", .set);
    const hero = try world.intern_entity("Hero");
    const slip = try world.intern_entity("ExposureSlip");
    const archive = try world.intern_entity("Archive");
    try world.remember(hero, try world.intern_relation("Knows", .set), slip.to_int(), 0);
    try world.remember(hero, try world.intern_relation("Knows", .set), archive.to_int(), 0);
    var hints = [_]Authored{
        .{ .tier = .thing, .text = "Your own notebook names the slip." },
        .{ .tier = .relation, .text = "Pick it up before you read the log." },
    };
    var needs = [_]Need{.{
        .entity = try world.intern_entity("TakeTheSlip"),
        .relation = "Carries",
        .subject = hero,
        .object = slip,
        .room = archive,
        .hints = &hints,
    }};
    const declaration = Declaration{ .goal = .{ .entity = try world.intern_entity("RecoverThePlate"), .needs = &needs } };
    try validate(declaration);

    var buf: [128]u8 = undefined;
    const thing = (try query(&.{declaration}, &world, hero, .thing, &buf)).?;
    try testing.expect(thing.authored);
    try testing.expectEqualStrings("Your own notebook names the slip.", thing.text);
    try testing.expectEqualStrings("Look in the Archive.", (try query(&.{declaration}, &world, hero, .room, &buf)).?.text);

    try world.remember(hero, try world.intern_relation("Carries", .set), slip.to_int(), 0);
    try testing.expect((try query(&.{declaration}, &world, hero, .room, &buf)) == null);
}

test "P44-01: validation refuses a missing room, an unknown prerequisite, and a cycle" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const hero = try world.intern_entity("Hero");
    const slip = try world.intern_entity("ExposureSlip");
    const archive = try world.intern_entity("Archive");
    const take = try world.intern_entity("TakeTheSlip");
    const read = try world.intern_entity("ReadTheLog");

    var needs = [_]Need{.{ .entity = take, .relation = "Carries", .subject = hero, .object = slip }};
    try testing.expectError(Error.InvalidGoal, validate(.{ .goal = .{ .entity = try world.intern_entity("G"), .needs = &needs } }));

    needs[0].room = archive;
    try validate(.{ .goal = .{ .entity = try world.intern_entity("G"), .needs = &needs } });

    const after = [_]EntityId{read};
    var pair = [_]Need{
        .{ .entity = take, .relation = "Carries", .subject = hero, .object = slip, .room = archive, .after = &after },
        .{ .entity = read, .relation = "Read", .subject = hero, .object = slip, .room = archive },
    };
    try validate(.{ .goal = .{ .entity = try world.intern_entity("G"), .needs = &pair } });

    // A prerequisite that is not a need of this goal is refused.
    const stranger = [_]EntityId{try world.intern_entity("Stranger")};
    pair[0].after = &stranger;
    try testing.expectError(Error.InvalidGoal, validate(.{ .goal = .{ .entity = try world.intern_entity("G"), .needs = &pair } }));

    // A cycle is refused: the pair waits on itself.
    const back = [_]EntityId{take};
    pair[0].after = &after;
    pair[1].after = &back;
    try testing.expectError(Error.InvalidGoal, validate(.{ .goal = .{ .entity = try world.intern_entity("G"), .needs = &pair } }));
}

test "P48-13: a need with six authored tiers steps through them, and asking past its last repeats it" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    _ = try world.intern_relation("Carries", .set);
    const hero = try world.intern_entity("Hero");
    const slip = try world.intern_entity("ExposureSlip");
    const archive = try world.intern_entity("Archive");
    for ([_]EntityId{ slip, archive }) |known| try world.remember(hero, try world.intern_relation("Knows", .set), known.to_int(), 0);
    const texts = [_][]const u8{ "Somewhere dusty.", "Something paper.", "Pick it up.", "Look under the press.", "The drawer sticks.", "Pull hard." };
    var hints: [6]Authored = undefined;
    for (&hints, texts, 1..) |*h, text, n| h.* = .{ .tier = Tier.fromInt(@intCast(n)).?, .text = text };
    var needs = [_]Need{.{ .entity = try world.intern_entity("TakeTheSlip"), .relation = "Carries", .subject = hero, .object = slip, .room = archive, .hints = &hints }};
    const declaration = Declaration{ .goal = .{ .entity = try world.intern_entity("RecoverThePlate"), .needs = &needs } };
    try validate(declaration);
    try testing.expectEqual(@as(usize, 6), tier_count(needs[0]));

    var buf: [128]u8 = undefined;
    for (texts, 1..) |text, n| {
        const hint = (try query(&.{declaration}, &world, hero, Tier.fromInt(@intCast(n)).?, &buf)).?;
        try testing.expectEqualStrings(text, hint.text);
        try testing.expectEqual(@as(u8, @intCast(n)), hint.tier.number());
    }
    // Tier 9 of a need that stops at 6 answers with tier 6, and says so.
    const past = (try query(&.{declaration}, &world, hero, Tier.fromInt(9).?, &buf)).?;
    try testing.expectEqual(@as(u8, 6), past.tier.number());
    try testing.expectEqualStrings("Pull hard.", past.text);

    // A need with only generated tiers answers tier 5 with its relation tier.
    needs[0].hints = &.{};
    const plain = (try query(&.{declaration}, &world, hero, Tier.fromInt(5).?, &buf)).?;
    try testing.expectEqual(Tier.relation, plain.tier);
    try testing.expect(!plain.authored);
    try testing.expect(Tier.fromInt(MAX_TIERS + 1) == null);
}

test "P48-24: validate handles a 64-need diamond DAG in linear time and refuses all-wildcard needs without a tier-2 hint" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const room = try world.intern_entity("Room");
    const hero = try world.intern_entity("Hero");

    // Diamond DAG of 64 needs: N[i] waits on N[i+1] and N[i+2].
    var needs: [64]Need = undefined;
    var deps: [64][2]EntityId = undefined;
    for (0..64) |i| {
        var name_buf: [16]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "N{d}", .{i});
        needs[i] = .{
            .entity = try world.intern_entity(name),
            .relation = "Ready",
            .subject = hero,
            .room = room,
        };
    }
    for (0..64) |i| {
        if (i + 2 < 64) {
            deps[i] = .{ needs[i + 1].entity, needs[i + 2].entity };
            needs[i].after = &deps[i];
        } else if (i + 1 < 64) {
            deps[i] = .{ needs[i + 1].entity, needs[i + 1].entity };
            needs[i].after = deps[i][0..1];
        }
    }
    const goal = try world.intern_entity("Diamond");
    try validate(.{ .goal = .{ .entity = goal, .needs = &needs } });

    // An all-wildcard need without a tier-2 authored hint is refused at validation.
    var wild = [_]Need{.{ .entity = try world.intern_entity("Wild"), .relation = "Alarm", .room = room }};
    try testing.expectError(Error.InvalidGoal, validate(.{ .goal = .{ .entity = try world.intern_entity("G2"), .needs = &wild } }));

    // Adding an authored tier-2 hint makes the all-wildcard need valid and queryable.
    const tier2 = [_]Authored{.{ .tier = .thing, .text = "The bell." }};
    wild[0].hints = &tier2;
    const decl = Declaration{ .goal = .{ .entity = try world.intern_entity("G2"), .needs = &wild } };
    try validate(decl);
    var buf: [128]u8 = undefined;
    try testing.expectEqualStrings("The bell.", (try query(&.{decl}, &world, hero, .thing, &buf)).?.text);
}
