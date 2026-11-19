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
const world_mod = @import("world.zig");
const World = world_mod.World;
const EntityId = world_mod.EntityId;

pub const MAX_GOALS: usize = 16;
/// Needs per goal. The frontier walk is linear in this, so the ceiling keeps one query cheap.
pub const MAX_NEEDS: usize = 16;
pub const MAX_AFTER: usize = 8;
/// One authored override per tier: room, thing, relation.
pub const MAX_TIERS: usize = 3;
pub const MAX_HINT_TEXT: usize = 120;
pub const MAX_HINT_WORDS: usize = 64;

/// Relations a player's knowledge is read from, in priority order. `Rejects` beats both
/// (P21-02, D-015): a rejected proposition is not known.
pub const KNOWS_RELATION = "Knows";
pub const BELIEVES_RELATION = "Believes";
pub const REJECTS_RELATION = "Rejects";

pub const Error = error{ InvalidGoal, HintTextTooLong };

pub const Tier = enum(u2) {
    room = 1,
    thing = 2,
    relation = 3,

    pub fn fromInt(value: u32) ?Tier {
        return switch (value) {
            1 => .room,
            2 => .thing,
            3 => .relation,
            else => null,
        };
    }

    /// Which part of the need the tier names, for a transcript or a test.
    pub fn label(self: Tier) []const u8 {
        return switch (self) {
            .room => "room",
            .thing => "thing",
            .relation => "relation",
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
        for (need.hints, 0..) |hint, hi| {
            if (hint.text.len == 0 or hint.text.len > MAX_HINT_TEXT) return Error.InvalidGoal;
            for (need.hints[0..hi]) |prior| if (prior.tier == hint.tier) return Error.InvalidGoal;
        }
        for (goal.needs[0..i]) |prior| if (prior.entity == need.entity) return Error.InvalidGoal;
    }
    // A cycle makes every need in it forever unready, so the authoring mistake is refused
    // rather than left to stall the frontier.
    for (goal.needs) |need| if (reaches(goal.needs, need.entity, need.entity, 0)) return Error.InvalidGoal;
}

fn reaches(needs: []const Need, from: EntityId, target: EntityId, depth: usize) bool {
    if (depth > MAX_NEEDS) return true;
    for (needs) |need| {
        if (need.entity != from) continue;
        for (need.after) |next| {
            if (next == target) return true;
            if (reaches(needs, next, target, depth + 1)) return true;
        }
        return false;
    }
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
    if (need.object) |object| if (object != player and !knows(world, player, object)) return false;
    if (tier == .room) {
        const room = need.room orelse return false;
        if (!knows(world, player, room)) return false;
    }
    return true;
}

fn authored(need: Need, tier: Tier) ?[]const u8 {
    for (need.hints) |hint| if (hint.tier == tier) return hint.text;
    return null;
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

fn name_of(world: *const World, entity: EntityId, out: []u8) []const u8 {
    return human_name(world.get_entity_name(entity) orelse "", out);
}

/// The base case: a tier with no authored text, built from the need's room, its thing, and its
/// relation, using the names the script declared.
fn generate(world: *const World, need: Need, tier: Tier, buf: []u8) Error![]const u8 {
    switch (tier) {
        .room => {
            const room = need.room orelse return Error.InvalidGoal;
            var words: [MAX_HINT_WORDS]u8 = undefined;
            return std.fmt.bufPrint(buf, "Look in the {s}.", .{name_of(world, room, &words)}) catch Error.HintTextTooLong;
        },
        .thing => {
            const thing = need.object orelse need.subject orelse return Error.InvalidGoal;
            var words: [MAX_HINT_WORDS]u8 = undefined;
            return std.fmt.bufPrint(buf, "You need the {s}.", .{name_of(world, thing, &words)}) catch Error.HintTextTooLong;
        },
        .relation => {
            var subject_words: [MAX_HINT_WORDS]u8 = undefined;
            const subject = if (need.subject) |entity| name_of(world, entity, &subject_words) else "_";
            if (need.object) |entity| {
                var object_words: [MAX_HINT_WORDS]u8 = undefined;
                return std.fmt.bufPrint(buf, "You need {s}({s}, {s}).", .{
                    need.relation, subject, name_of(world, entity, &object_words),
                }) catch Error.HintTextTooLong;
            }
            return std.fmt.bufPrint(buf, "You need {s}({s}).", .{ need.relation, subject }) catch Error.HintTextTooLong;
        },
    }
}

/// Reports the nearest unmet need at `tier`. Holmesian first: the first unmet frontier need
/// whose terms the player knows. When there is none, the first unmet need in declaration order
/// answers as the author (D-126). Null means every need of every goal holds.
pub fn query(
    goals: []const Declaration,
    world: *const World,
    player: EntityId,
    tier: Tier,
    buf: []u8,
) Error!?Hint {
    for (goals) |declaration| {
        for (declaration.goal.needs) |*need| {
            if (satisfied(world, need.*)) continue;
            const candidate = frontier(world, declaration.goal.needs) orelse continue;
            if (candidate.entity != need.entity) continue;
            if (!terms_known(world, player, need.*, tier)) continue;
            return .{
                .goal = declaration.goal.entity,
                .need = need.entity,
                .tier = tier,
                .path = .holmesian,
                .authored = authored(need.*, tier) != null,
                .text = authored(need.*, tier) orelse try generate(world, need.*, tier, buf),
            };
        }
    }
    for (goals) |declaration| {
        for (declaration.goal.needs) |*need| {
            if (satisfied(world, need.*)) continue;
            return .{
                .goal = declaration.goal.entity,
                .need = need.entity,
                .tier = tier,
                .path = .doylian,
                .authored = authored(need.*, tier) != null,
                .text = authored(need.*, tier) orelse try generate(world, need.*, tier, buf),
            };
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
