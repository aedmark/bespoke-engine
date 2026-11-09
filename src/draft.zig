const std = @import("std");
const world_mod = @import("world.zig");
const EntityId = world_mod.EntityId;

/// Musical draft primitives for pitch-based spellcraft (P22-01, D-029).
///
/// A draft is a fixed ordered sequence of `DRAFT_LEN` diatonic notes. Draft tables are
/// compile-time program data owned by `CompiledProgram`, never world facts: the world arena
/// stays a pure memory copy on save/restore (D-003), and what a caster has *learned* is an
/// ordinary relational fact the script asserts (e.g. `Knows(Player, Kindle)`).
pub const DRAFT_LEN: usize = 4;

/// The seven diatonic staff pitches. Values are stable: they are serialized in `.bspk`
/// packages and travel through `AudioEvent` to the synthesizer (P22-02).
pub const Note = enum(u8) {
    C = 0,
    D = 1,
    E = 2,
    F = 3,
    G = 4,
    A = 5,
    B = 6,

    pub fn from_name(name: []const u8) ?Note {
        if (name.len != 1) return null;
        return switch (name[0]) {
            'C' => .C,
            'D' => .D,
            'E' => .E,
            'F' => .F,
            'G' => .G,
            'A' => .A,
            'B' => .B,
            else => null,
        };
    }

    pub fn from_int(val: u8) ?Note {
        if (val > 6) return null;
        return @enumFromInt(val);
    }
};

pub const Notes = [DRAFT_LEN]Note;

pub fn reversed(notes: Notes) Notes {
    var out: Notes = undefined;
    for (notes, 0..) |n, i| out[DRAFT_LEN - 1 - i] = n;
    return out;
}

pub fn is_palindrome(notes: Notes) bool {
    return std.mem.eql(Note, &notes, &reversed(notes));
}

pub fn notes_eql(a: Notes, b: Notes) bool {
    return std.mem.eql(Note, &a, &b);
}

/// One playable draft in a compiled program. A declared `reverse` produces a second entry
/// whose notes are the reversal and whose `inverse` points back, so lookup by notes needs
/// no direction flag.
pub const CompiledDraft = struct {
    entity: EntityId,
    notes: Notes,
    inverse: ?EntityId = null,
};

/// Finds the draft whose notes exactly match `notes`. The compiler guarantees that no two
/// entries share a sequence (forward or reversed), so the first match is the only match.
pub fn find_by_notes(drafts: []const CompiledDraft, notes: Notes) ?CompiledDraft {
    for (drafts) |d| {
        if (notes_eql(d.notes, notes)) return d;
    }
    return null;
}

pub fn find_by_entity(drafts: []const CompiledDraft, entity: EntityId) ?CompiledDraft {
    for (drafts) |d| {
        if (d.entity == entity) return d;
    }
    return null;
}

/// A weave queued by the `weave` opcode for host re-dispatch (D-029). The VM cannot run cue
/// handlers mid-tick because it does not hold the compiled program, so in-script weaves wait
/// here until the host calls `VM.dispatch_pending_weaves` after `step_tick`.
pub const PendingWeave = struct {
    caster: EntityId,
    draft: EntityId,
    target: EntityId,
};

/// Cue name every weave dispatches through (D-009: verbs are cues).
pub const WEAVE_CUE = "Weave";
/// Peripheral cue recorded when a weave resolves to no handler or no draft (P22-02 audio hook).
pub const WEAVE_FIZZLED_CUE = "WeaveFizzled";

/// What the last completed phrase did, for HUD feedback (P22-02).
pub const WeaveOutcome = enum(u8) {
    none = 0,
    woven = 1,
    fizzled = 2,
};

/// Player-side phrase buffer for the distaff (P22-02, D-029). This is peripheral input state,
/// like a half-typed console line: it lives in the host runner, not the world arena, so a
/// snapshot or rewind never captures a half-played phrase.
///
/// `reach` is how many notes of the scale the caster can currently play, counted from C.
/// It models a distaff that gains notes as the story advances; the host sets it from script
/// facts. Notes outside reach are refused so a phrase can only contain playable notes.
pub const DistaffInput = struct {
    played: Notes = undefined,
    len: u8 = 0,
    reach: u8 = 7,
    outcome: WeaveOutcome = .none,

    pub fn can_play(self: *const DistaffInput, note: Note) bool {
        return @intFromEnum(note) < self.reach;
    }

    /// Adds a note. Returns the full phrase when the fourth note lands and resets the buffer,
    /// so the host weaves exactly once per phrase. Returns null while the phrase is incomplete
    /// or the note is out of reach.
    pub fn press(self: *DistaffInput, note: Note) ?Notes {
        if (!self.can_play(note)) return null;
        if (self.len == 0) self.outcome = .none;
        self.played[self.len] = note;
        self.len += 1;
        if (self.len < DRAFT_LEN) return null;
        self.len = 0;
        return self.played;
    }

    pub fn clear(self: *DistaffInput) void {
        self.len = 0;
    }

    pub fn set_reach(self: *DistaffInput, reach: u8) void {
        self.reach = @min(reach, 7);
    }

    /// Notes of the phrase in progress.
    pub fn current(self: *const DistaffInput) []const Note {
        return self.played[0..self.len];
    }
};

test "P22-01: note names, reversal, and palindromes" {
    const testing = std.testing;
    try testing.expectEqual(Note.G, Note.from_name("G").?);
    try testing.expect(Note.from_name("H") == null);
    try testing.expect(Note.from_name("CC") == null);
    try testing.expect(Note.from_int(7) == null);

    const kindle = Notes{ .C, .E, .G, .E };
    try testing.expect(notes_eql(reversed(kindle), Notes{ .E, .G, .E, .C }));
    try testing.expect(!is_palindrome(kindle));
    try testing.expect(is_palindrome(Notes{ .D, .A, .A, .D }));
}

test "P22-01: lookup by notes resolves forward and declared reverse entries" {
    const testing = std.testing;
    const kindle = EntityId.from_int(10);
    const douse = EntityId.from_int(11);
    const table = [_]CompiledDraft{
        .{ .entity = kindle, .notes = .{ .C, .E, .G, .E }, .inverse = douse },
        .{ .entity = douse, .notes = .{ .E, .G, .E, .C }, .inverse = kindle },
    };
    try testing.expectEqual(kindle, find_by_notes(&table, .{ .C, .E, .G, .E }).?.entity);
    try testing.expectEqual(douse, find_by_notes(&table, .{ .E, .G, .E, .C }).?.entity);
    try testing.expect(find_by_notes(&table, .{ .C, .C, .C, .C }) == null);
    try testing.expectEqual(kindle, find_by_entity(&table, douse).?.inverse.?);
}

test "P22-02: distaff input completes a phrase on the fourth note and honours reach" {
    const testing = std.testing;
    var input = DistaffInput{};
    try testing.expect(input.press(.C) == null);
    try testing.expect(input.press(.E) == null);
    try testing.expect(input.press(.G) == null);
    try testing.expectEqual(@as(usize, 3), input.current().len);
    const phrase = input.press(.E).?;
    try testing.expect(notes_eql(phrase, .{ .C, .E, .G, .E }));
    try testing.expectEqual(@as(usize, 0), input.current().len);

    // An outcome persists until the next phrase starts.
    input.outcome = .fizzled;
    try testing.expect(input.press(.D) == null);
    try testing.expectEqual(WeaveOutcome.none, input.outcome);
    input.clear();
    try testing.expectEqual(@as(usize, 0), input.current().len);

    // Reach 3 allows C, D, E only; refused notes do not enter the phrase.
    input.set_reach(3);
    try testing.expect(input.can_play(.E));
    try testing.expect(!input.can_play(.F));
    try testing.expect(input.press(.F) == null);
    try testing.expectEqual(@as(usize, 0), input.current().len);
    input.set_reach(200);
    try testing.expectEqual(@as(u8, 7), input.reach);
}
