//! The sentences the engine writes for a player, as whole templates (P48-09, D-163, D-179).
//!
//! Each phrase has a key a script names (`phrase HintRoom: "Seek the {room}."`), English text,
//! and the placeholders it may use. The engine fills placeholders with display names and never
//! builds a sentence from fragments, so a translation can reorder words or decline a noun.
//! Overrides are program data on the World, like value bounds: the package carries them and a
//! save does not. The window's chrome (save and load messages, key hints) is not here (D-179).
const std = @import("std");
const world_mod = @import("world.zig");
const World = world_mod.World;

pub const Key = enum {
    hint_room,
    hint_thing,
    hint_fact,
    hint_state,
    unknown_word,
    not_understood,
    not_here,
    which_do_you_mean,
    choice_item,
    choice_join,
    choice_join_last,
    nothing_happens,
    cannot_get_there,
    appeal_unknown_value,
    appeal_nobody,
    narrate_walk,
    narrate_look,
    narrate_talk,
    narrate_take,
    narrate_use,
    narrate_use_on,
    arrive_scene,
    walking_to,
    someone,
    player_fallback,
    thing_fallback,
};

pub const Entry = struct {
    /// What a script writes after `phrase`.
    name: []const u8,
    english: []const u8,
    /// The placeholders the engine fills for this phrase; an override may use any of them,
    /// in any order, and no others.
    slots: []const []const u8 = &.{},
};

/// One entry per key, in `Key` order. The English text is exactly what the engine wrote before
/// templates, so no golden moved (D-179).
pub const ENTRIES = [_]Entry{
    .{ .name = "HintRoom", .english = "Look in the {room}.", .slots = &.{"room"} },
    .{ .name = "HintThing", .english = "You need the {thing}.", .slots = &.{"thing"} },
    .{ .name = "HintFact", .english = "You need {relation}({subject}, {object}).", .slots = &.{ "relation", "subject", "object" } },
    .{ .name = "HintState", .english = "You need {relation}({subject}).", .slots = &.{ "relation", "subject" } },
    .{ .name = "UnknownWord", .english = "I don't know the word \"{word}\".", .slots = &.{"word"} },
    .{ .name = "NotUnderstood", .english = "I don't understand that." },
    .{ .name = "NotHere", .english = "You don't see that here." },
    .{ .name = "WhichDoYouMean", .english = "Which do you mean: {choices}?", .slots = &.{"choices"} },
    .{ .name = "ChoiceItem", .english = "the {thing}", .slots = &.{"thing"} },
    .{ .name = "ChoiceJoin", .english = ", " },
    .{ .name = "ChoiceJoinLast", .english = " or " },
    .{ .name = "NothingHappens", .english = "Nothing happens." },
    .{ .name = "CannotGetThere", .english = "You can't get there from here." },
    .{ .name = "AppealUnknownValue", .english = "You don't know what moves them." },
    .{ .name = "AppealNobody", .english = "Nobody here would be moved by that." },
    .{ .name = "NarrateWalk", .english = "{actor} walks to {target}.", .slots = &.{ "actor", "target" } },
    .{ .name = "NarrateLook", .english = "{actor} looks at {target}.", .slots = &.{ "actor", "target" } },
    .{ .name = "NarrateTalk", .english = "{actor} talks to {target}.", .slots = &.{ "actor", "target" } },
    .{ .name = "NarrateTake", .english = "{actor} takes {target}.", .slots = &.{ "actor", "target" } },
    .{ .name = "NarrateUse", .english = "{actor} uses {target}.", .slots = &.{ "actor", "target" } },
    .{ .name = "NarrateUseOn", .english = "{actor} uses {thing} on {target}.", .slots = &.{ "actor", "thing", "target" } },
    .{ .name = "ArriveScene", .english = "{scene}.", .slots = &.{"scene"} },
    .{ .name = "WalkingTo", .english = "Walking to {mark}...", .slots = &.{"mark"} },
    .{ .name = "Someone", .english = "Someone" },
    .{ .name = "PlayerFallback", .english = "You" },
    .{ .name = "ThingFallback", .english = "it" },
};

comptime {
    if (ENTRIES.len != @typeInfo(Key).@"enum".field_names.len) @compileError("phrase.ENTRIES needs one entry per Key");
}

pub const Error = error{ UnknownPhrase, UnknownPhraseSlot, UnclosedPhraseSlot, PhraseTooLong };

/// The key a script names, or null.
pub fn find(name: []const u8) ?Key {
    for (ENTRIES, 0..) |candidate, i| {
        if (std.mem.eql(u8, candidate.name, name)) return @enumFromInt(i);
    }
    return null;
}

pub fn entry(key: Key) Entry {
    return ENTRIES[@intFromEnum(key)];
}

/// The phrase's text: the game's override, else English.
pub fn text(world: *const World, key: Key) []const u8 {
    const e = entry(key);
    return world.phrase_override(e.name) orelse e.english;
}

/// Checks an override before it is stored: every `{slot}` must be one the phrase takes.
pub fn validate(key: Key, template: []const u8) Error!void {
    var rest = template;
    while (std.mem.indexOfScalar(u8, rest, '{')) |open| {
        const close = std.mem.indexOfScalarPos(u8, rest, open, '}') orelse return Error.UnclosedPhraseSlot;
        const slot = rest[open + 1 .. close];
        var known = false;
        for (entry(key).slots) |s| {
            if (std.mem.eql(u8, s, slot)) known = true;
        }
        if (!known) return Error.UnknownPhraseSlot;
        rest = rest[close + 1 ..];
    }
}

pub const Arg = struct { slot: []const u8, value: []const u8 };

/// Writes the phrase with each `{slot}` replaced by its argument. A slot without an argument
/// writes nothing; text that does not fit is `PhraseTooLong`.
pub fn render(world: *const World, key: Key, args: []const Arg, buf: []u8) Error![]const u8 {
    return fill(text(world, key), args, buf);
}

pub fn fill(template: []const u8, args: []const Arg, buf: []u8) Error![]const u8 {
    var w: std.Io.Writer = .fixed(buf);
    var rest = template;
    while (std.mem.indexOfScalar(u8, rest, '{')) |open| {
        w.writeAll(rest[0..open]) catch return Error.PhraseTooLong;
        const close = std.mem.indexOfScalarPos(u8, rest, open, '}') orelse return Error.UnclosedPhraseSlot;
        const slot = rest[open + 1 .. close];
        for (args) |arg| {
            if (std.mem.eql(u8, arg.slot, slot)) {
                w.writeAll(arg.value) catch return Error.PhraseTooLong;
                break;
            }
        }
        rest = rest[close + 1 ..];
    }
    w.writeAll(rest) catch return Error.PhraseTooLong;
    return w.buffered();
}

test "P48-09: phrases render in English, take overrides, and refuse unknown slots" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var buf: [96]u8 = undefined;
    try testing.expectEqualStrings("Look in the Archive.", try render(&world, .hint_room, &.{.{ .slot = "room", .value = "Archive" }}, &buf));
    try validate(.hint_room, "Cherchez dans {room}.");
    try world.set_phrase("HintRoom", "Cherchez dans {room}.");
    try testing.expectEqualStrings("Cherchez dans Archive.", try render(&world, .hint_room, &.{.{ .slot = "room", .value = "Archive" }}, &buf));
    try testing.expectError(Error.UnknownPhraseSlot, validate(.hint_room, "Look for {thing}."));
    try testing.expectError(Error.UnclosedPhraseSlot, validate(.hint_room, "Look in {room."));
    try testing.expectEqual(Key.narrate_use_on, find("NarrateUseOn").?);
    try testing.expect(find("Narrate") == null);
}
