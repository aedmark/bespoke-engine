//! The engine's relation names (P48-10, D-164, D-180).
//!
//! Two kinds share the World. Bookkeeping, which only the engine reads, is named with a leading
//! `#` that no script identifier can spell, so a script can never collide with it. The relations
//! below are author-facing: the engine writes or reads them, and scripts may test them (and
//! write the ones the spec says to). Each records the release that added it. A script that
//! declares a relation the table marks as newer than the language version keeps its own, and
//! the engine feature of that name stays off for that game, so a 1.0 game is never broken by a
//! name a later release adopts.
const std = @import("std");
const world_mod = @import("world.zig");

pub const Release = struct {
    major: u16,
    minor: u16,

    pub fn newer_than(self: Release, other: Release) bool {
        return self.major > other.major or (self.major == other.major and self.minor > other.minor);
    }
};

/// The language version every script is written against.
pub const LANGUAGE = Release{ .major = 1, .minor = 0 };

pub const AuthorRelation = struct {
    name: []const u8,
    since: Release = LANGUAGE,
};

/// Every author-facing engine relation, with the release that added it. All are 1.0.
pub const AUTHOR_FACING = [_]AuthorRelation{
    .{ .name = "AgendaState" },     .{ .name = "DecisionState" }, .{ .name = "DilemmaState" },
    .{ .name = "Knows" },           .{ .name = "Believes" },      .{ .name = "Rejects" },
    .{ .name = "Presented" },       .{ .name = "Chose" },         .{ .name = "Appealed" },
    .{ .name = "PathActive" },      .{ .name = "Pursuing" },      .{ .name = "CellFlammable" },
    .{ .name = "CellLiquid" },      .{ .name = "CellBlocking" },  .{ .name = "CellBurning" },
    .{ .name = "CellSmoke" },       .{ .name = "InBurningCell" }, .{ .name = "InSmokeCell" },
    .{ .name = "InLiquidCell" },    .{ .name = "ConvergenceReady" }, .{ .name = "LoopClosed" },
};

/// The entry for `name` when it is newer than the language a script is written against.
pub fn newer_than_language(table: []const AuthorRelation, name: []const u8) ?AuthorRelation {
    for (table) |entry| {
        if (std.mem.eql(u8, entry.name, name) and entry.since.newer_than(LANGUAGE)) return entry;
    }
    return null;
}

/// Whether an engine feature may use the relation `name` in this world: false once the script
/// has declared its own relation of that name (D-180). A feature added after 1.0 asks this
/// before it reads or writes its relation; 1.0 features share theirs with scripts by design.
pub fn engine_may_use(world: *const world_mod.World, name: []const u8) bool {
    const relation = world.lookup_relation(name) orelse return true;
    const meta = world.get_relation_meta(relation) orelse return true;
    return !meta.script_owned;
}

/// A bookkeeping name: the engine's own, never a script's.
pub fn is_bookkeeping(name: []const u8) bool {
    return name.len > 0 and name[0] == '#';
}

test "P48-10: a relation newer than the language is found, and 1.0 relations are not" {
    const testing = std.testing;
    try testing.expect(newer_than_language(&AUTHOR_FACING, "Knows") == null);
    const later = [_]AuthorRelation{.{ .name = "Hears", .since = .{ .major = 1, .minor = 1 } }};
    try testing.expectEqualStrings("Hears", newer_than_language(&later, "Hears").?.name);
    try testing.expect(is_bookkeeping("#DialogueOpen"));
    try testing.expect(!is_bookkeeping("DialogueOpen"));
}
