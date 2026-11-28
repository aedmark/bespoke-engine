//! The ceilings a script may raise with `limit <name> N` (P48-13, D-167, D-183).
//!
//! Each is a sanity check with today's number as its default: a game that needs more says so
//! once, on purpose, rather than meeting a wall. Every ceiling also has a fixed safety cap,
//! eight times its default, which no script may pass; the package loader holds untrusted
//! counts to the same caps, so a limit is a compile-time rule and the package carries none.
//! Structural bounds (three cue parameters, eight guard variables, the three generated hint
//! tiers) are not here: they are shapes of the engine, not sanity checks.
const std = @import("std");

pub const Kind = enum {
    goals,
    needs,
    decisions,
    options,
    dilemmas,
    axes,
    spells,
    words,
    hints,
    commands,
};

pub const COUNT = @typeInfo(Kind).@"enum".field_names.len;

pub const Entry = struct {
    /// What a script writes after `limit`.
    name: []const u8,
    default: usize,
    /// What the number counts, for a diagnostic: "needs in one goal".
    counts: []const u8,
};

/// One entry per kind, in `Kind` order.
pub const ENTRIES = [COUNT]Entry{
    .{ .name = "goals", .default = 16, .counts = "goals" },
    .{ .name = "needs", .default = 16, .counts = "needs in one goal" },
    .{ .name = "decisions", .default = 32, .counts = "decisions" },
    .{ .name = "options", .default = 8, .counts = "options in one decision" },
    .{ .name = "dilemmas", .default = 32, .counts = "dilemmas" },
    .{ .name = "axes", .default = 64, .counts = "axes" },
    .{ .name = "spells", .default = 16, .counts = "spells in the spellbook" },
    .{ .name = "words", .default = 12, .counts = "words of one kind in the spellbook" },
    .{ .name = "hints", .default = 3, .counts = "hint tiers in one need" },
    // 64 frames less the engine's 13 defaults, the room a script always had (P49-05, D-210).
    .{ .name = "commands", .default = 51, .counts = "command phrases" },
};

/// The safety cap is a fixed multiple of the default (D-183).
pub const CAP_FACTOR = 8;

pub fn default_of(kind: Kind) usize {
    return ENTRIES[@intFromEnum(kind)].default;
}

pub fn cap_of(kind: Kind) usize {
    return default_of(kind) * CAP_FACTOR;
}

pub fn find(name: []const u8) ?Kind {
    for (ENTRIES, 0..) |entry, i| if (std.mem.eql(u8, entry.name, name)) return @enumFromInt(i);
    return null;
}

/// The ceilings one script compiles under: each default, or the value its `limit` line gave.
pub const Limits = struct {
    values: [COUNT]usize = blk: {
        var v: [COUNT]usize = undefined;
        for (ENTRIES, &v) |entry, *out| out.* = entry.default;
        break :blk v;
    },

    pub fn get(self: Limits, kind: Kind) usize {
        return self.values[@intFromEnum(kind)];
    }
};

test "P48-13: each limit defaults to today's ceiling and caps at eight times it" {
    const limits = Limits{};
    try std.testing.expectEqual(@as(usize, 32), limits.get(.decisions));
    try std.testing.expectEqual(@as(usize, 3), limits.get(.hints));
    try std.testing.expectEqual(@as(usize, 256), cap_of(.dilemmas));
    try std.testing.expectEqual(Kind.words, find("words").?);
    try std.testing.expect(find("leans") == null);
}
