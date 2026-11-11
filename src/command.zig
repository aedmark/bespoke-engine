//! Typed commands: words, frames, and scoped nouns (P26-01, D-057).
//!
//! A typed line such as `> pour the grog into the mug` becomes words (`pour grog into mug`),
//! a frame match (`pour <thing> into <thing>` -> `Pours`), and entity resolution for each
//! `<thing>` against what the actor can see or holds. This module owns the vocabulary and the
//! noun rules; P26-02 matches frames and dispatches cues. It names no game content: the
//! default frames use the engine's conventional cue names, and scripts add their own.

const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const SpatialSystem = spatial_mod.SpatialSystem;

pub const MAX_INPUT: usize = 256;
pub const MAX_WORDS: usize = 16;
pub const MAX_ELEMENTS: usize = 8;
pub const MAX_SLOTS: usize = 2;
pub const MAX_SCOPE: usize = 64;
pub const MAX_NAME_WORDS: usize = 8;
pub const MAX_CANDIDATES: usize = 8;
pub const MAX_ALIAS_PHRASES: usize = 8;

pub const ARTICLES = [_][]const u8{ "a", "an", "the" };
pub const PREPOSITIONS = [_][]const u8{ "with", "on", "to", "about", "into", "in", "at", "from" };

pub const Error = error{ InputTooLong, TooManyWords, InvalidFrame, InvalidAlias };

fn contains(list: []const []const u8, word: []const u8) bool {
    for (list) |item| if (std.mem.eql(u8, item, word)) return true;
    return false;
}

pub fn is_preposition(word: []const u8) bool {
    return contains(&PREPOSITIONS, word);
}

/// A typed line split into lowercase words, articles removed. Words are slices of `buf`, so
/// fill it in place with `tokenize` and do not copy it by value afterwards.
pub const Words = struct {
    buf: [MAX_INPUT]u8 = undefined,
    items: [MAX_WORDS][]const u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const Words) []const []const u8 {
        return self.items[0..self.len];
    }
};

/// Splits on anything that is not a letter, digit, or apostrophe, so `>`, commas, and full
/// stops separate words without becoming words.
pub fn tokenize(input: []const u8, out: *Words) !void {
    if (input.len > MAX_INPUT) return Error.InputTooLong;
    out.len = 0;
    for (input, 0..) |ch, i| out.buf[i] = std.ascii.toLower(ch);
    var i: usize = 0;
    while (i < input.len) {
        while (i < input.len and !is_word_char(out.buf[i])) i += 1;
        const start = i;
        while (i < input.len and is_word_char(out.buf[i])) i += 1;
        if (i == start) break;
        const word = out.buf[start..i];
        if (contains(&ARTICLES, word)) continue;
        if (out.len == MAX_WORDS) return Error.TooManyWords;
        out.items[out.len] = word;
        out.len += 1;
    }
}

fn is_word_char(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '\'';
}

pub const Element = union(enum) {
    word: []const u8,
    thing,
};

/// A sentence shape mapped to a cue. Elements borrow the frame text.
pub const Frame = struct {
    cue: []const u8,
    elements: [MAX_ELEMENTS]Element = undefined,
    len: usize = 0,

    pub fn slice(self: *const Frame) []const Element {
        return self.elements[0..self.len];
    }

    pub fn slots(self: *const Frame) usize {
        var n: usize = 0;
        for (self.slice()) |e| if (e == .thing) {
            n += 1;
        };
        return n;
    }
};

/// Parses frame text such as `pour <thing> into <thing>`. A frame starts with a literal verb
/// word, has at most two slots, and never puts two slots side by side: with no word between
/// them, the matcher could not tell where the first noun ends.
pub fn parse_frame(cue: []const u8, text: []const u8) !Frame {
    if (cue.len == 0) return Error.InvalidFrame;
    var frame = Frame{ .cue = cue };
    var it = std.mem.tokenizeAny(u8, text, " \t");
    var slots: usize = 0;
    while (it.next()) |part| {
        if (frame.len == MAX_ELEMENTS) return Error.InvalidFrame;
        if (std.mem.eql(u8, part, "<thing>")) {
            if (frame.len == 0) return Error.InvalidFrame;
            if (frame.elements[frame.len - 1] == .thing) return Error.InvalidFrame;
            slots += 1;
            if (slots > MAX_SLOTS) return Error.InvalidFrame;
            frame.elements[frame.len] = .thing;
        } else {
            for (part) |ch| if (!std.ascii.isLower(ch) and !std.ascii.isDigit(ch) and ch != '\'') return Error.InvalidFrame;
            if (contains(&ARTICLES, part)) return Error.InvalidFrame;
            frame.elements[frame.len] = .{ .word = part };
        }
        frame.len += 1;
    }
    if (frame.len == 0) return Error.InvalidFrame;
    return frame;
}

/// The engine's default frames (D-057 point 2). Script frames are tried before these.
pub const DEFAULT_FRAMES = [_]struct { cue: []const u8, text: []const u8 }{
    .{ .cue = "LooksAt", .text = "look at <thing>" },
    .{ .cue = "LooksAt", .text = "examine <thing>" },
    .{ .cue = "LooksAt", .text = "x <thing>" },
    .{ .cue = "Uses", .text = "use <thing> with <thing>" },
    .{ .cue = "Uses", .text = "use <thing> on <thing>" },
    .{ .cue = "Uses", .text = "use <thing>" },
    .{ .cue = "TalksTo", .text = "ask <thing> about <thing>" },
    .{ .cue = "TalksTo", .text = "talk to <thing>" },
    .{ .cue = "WalksTo", .text = "go to <thing>" },
    .{ .cue = "WalksTo", .text = "walk to <thing>" },
};

/// A script `command <Cue>: <frame>` line, owned by the compiled program.
pub const CommandDecl = struct {
    cue: []const u8,
    text: []const u8,

    pub fn deinit_owned(self: *CommandDecl, allocator: std.mem.Allocator) void {
        allocator.free(self.cue);
        allocator.free(self.text);
        self.* = undefined;
    }

    pub fn frame(self: CommandDecl) !Frame {
        return parse_frame(self.cue, self.text);
    }
};

/// A script `alias <Entity>: phrase, phrase` line, owned by the compiled program. Phrases are
/// stored lowercase.
pub const AliasDecl = struct {
    entity: EntityId,
    phrases: []const []const u8,

    pub fn deinit_owned(self: *AliasDecl, allocator: std.mem.Allocator) void {
        for (self.phrases) |p| allocator.free(p);
        allocator.free(self.phrases);
        self.* = undefined;
    }

    pub fn validate(self: AliasDecl) !void {
        if (self.entity == .none or self.phrases.len == 0 or self.phrases.len > MAX_ALIAS_PHRASES) return Error.InvalidAlias;
        for (self.phrases) |p| {
            if (p.len == 0) return Error.InvalidAlias;
            for (p) |ch| if (!std.ascii.isLower(ch) and !std.ascii.isDigit(ch) and ch != ' ' and ch != '\'') return Error.InvalidAlias;
        }
    }
};

/// The lowercase words of an entity name, split at spaces, underscores, hyphens, and each
/// change from a lowercase letter or digit to an uppercase one. Words are kept as offsets into
/// `buf`, not slices, so the struct stays valid when it is returned or copied by value.
pub const NameWords = struct {
    buf: [64]u8 = undefined,
    starts: [MAX_NAME_WORDS]u8 = undefined,
    ends: [MAX_NAME_WORDS]u8 = undefined,
    len: usize = 0,

    pub fn of(name: []const u8) NameWords {
        var out = NameWords{};
        const n = @min(name.len, out.buf.len);
        var start: ?usize = null;
        for (0..n) |i| {
            const ch = name[i];
            out.buf[i] = std.ascii.toLower(ch);
            const separator = ch == ' ' or ch == '_' or ch == '-';
            const boundary = i > 0 and std.ascii.isUpper(ch) and (std.ascii.isLower(name[i - 1]) or std.ascii.isDigit(name[i - 1]));
            if (separator or boundary) {
                if (start) |st| out.push(st, i);
                start = if (separator) null else i;
            } else if (start == null) start = i;
        }
        if (start) |st| out.push(st, n);
        return out;
    }

    fn push(self: *NameWords, start: usize, end: usize) void {
        if (end <= start or self.len == MAX_NAME_WORDS) return;
        self.starts[self.len] = @intCast(start);
        self.ends[self.len] = @intCast(end);
        self.len += 1;
    }

    pub fn word(self: *const NameWords, i: usize) []const u8 {
        return self.buf[self.starts[i]..self.ends[i]];
    }

    pub fn has(self: *const NameWords, w: []const u8) bool {
        for (0..self.len) |i| if (std.mem.eql(u8, self.word(i), w)) return true;
        return false;
    }
};

fn alias_has_word(aliases: []const AliasDecl, entity: EntityId, word: []const u8) bool {
    for (aliases) |alias| {
        if (alias.entity != entity) continue;
        for (alias.phrases) |phrase| {
            var it = std.mem.tokenizeScalar(u8, phrase, ' ');
            while (it.next()) |w| if (std.mem.eql(u8, w, word)) return true;
        }
    }
    return false;
}

/// True when every word of `phrase` is a word of the entity's name or of one of its aliases.
pub fn matches(world: *const World, aliases: []const AliasDecl, entity: EntityId, phrase: []const []const u8) bool {
    if (phrase.len == 0) return false;
    const name = world.get_entity_name(entity) orelse return false;
    const words = NameWords.of(name);
    for (phrase) |w| {
        if (!words.has(w) and !alias_has_word(aliases, entity, w)) return false;
    }
    return true;
}

/// The entities a typed noun may name (D-057 point 3): agents, hotspots, and marks in the
/// actor's room, and what the actor holds. The actor itself is excluded.
pub const Scope = struct {
    items: [MAX_SCOPE]EntityId = undefined,
    len: usize = 0,

    pub fn slice(self: *const Scope) []const EntityId {
        return self.items[0..self.len];
    }

    fn add(self: *Scope, entity: EntityId, actor: EntityId) void {
        if (entity == .none or entity == actor or self.len == MAX_SCOPE) return;
        for (self.slice()) |e| if (e == entity) return;
        self.items[self.len] = entity;
        self.len += 1;
    }

    pub fn gather(world: *const World, spatial: ?*const SpatialSystem, room: ?EntityId, actor: EntityId) Scope {
        var scope = Scope{};
        if (spatial) |sp| {
            if (room) |r| {
                var it = sp.agents.iterator();
                while (it.next()) |entry| {
                    const wp = sp.graph.get_waypoint(entry.value_ptr.current_wp) orelse continue;
                    if (wp.room == r) scope.add(entry.key_ptr.*, actor);
                }
                for (sp.hotspots.items) |hs| if (hs.room == r) scope.add(hs.entity, actor);
                for (sp.graph.waypoints.items) |wp| {
                    if (wp.room != r) continue;
                    if (world.lookup_entity(wp.name)) |mark| scope.add(mark, actor);
                }
            }
        }
        for ([_][]const u8{ "Carries", "InInventory" }) |relation_name| {
            const relation = world.lookup_relation(relation_name) orelse continue;
            var q = world.query(actor, relation, null);
            while (q.next()) |fact| scope.add(EntityId.from_int(fact.object_or_value), actor);
        }
        return scope;
    }
};

pub const Resolution = union(enum) {
    none,
    one: EntityId,
    many: struct { items: [MAX_CANDIDATES]EntityId, len: usize },
};

/// Resolves a noun phrase against a scope: no match, one match, or the candidates to ask
/// about (D-057 point 4). No match is ever preferred over another.
pub fn resolve(world: *const World, aliases: []const AliasDecl, scope: *const Scope, phrase: []const []const u8) Resolution {
    var found: [MAX_CANDIDATES]EntityId = undefined;
    var n: usize = 0;
    for (scope.slice()) |entity| {
        if (!matches(world, aliases, entity, phrase)) continue;
        if (n < found.len) found[n] = entity;
        n += 1;
    }
    if (n == 0) return .none;
    if (n == 1) return .{ .one = found[0] };
    return .{ .many = .{ .items = found, .len = @min(n, found.len) } };
}

/// True when the word names something: a frame word, a preposition, or a word of an entity in
/// scope. Used to report the first unknown word.
pub fn known_word(world: *const World, aliases: []const AliasDecl, scope: *const Scope, frames: []const Frame, word: []const u8) bool {
    if (is_preposition(word)) return true;
    for (frames) |f| for (f.slice()) |e| switch (e) {
        .word => |w| if (std.mem.eql(u8, w, word)) return true,
        .thing => {},
    };
    for (scope.slice()) |entity| {
        const one = [_][]const u8{word};
        if (matches(world, aliases, entity, &one)) return true;
    }
    return false;
}

/// Frames in match order: the script's first, in declaration order, then the engine defaults.
pub const FrameList = struct {
    items: [MAX_FRAMES]Frame = undefined,
    len: usize = 0,

    pub fn build(script: []const CommandDecl) FrameList {
        var list = FrameList{};
        for (script) |decl| {
            if (list.len == MAX_FRAMES) break;
            // Compiled and loaded commands were validated; a frame that still fails is skipped
            // rather than aborting every typed line.
            list.items[list.len] = decl.frame() catch continue;
            list.len += 1;
        }
        for (DEFAULT_FRAMES) |d| {
            if (list.len == MAX_FRAMES) break;
            list.items[list.len] = parse_frame(d.cue, d.text) catch unreachable;
            list.len += 1;
        }
        return list;
    }

    pub fn slice(self: *const FrameList) []const Frame {
        return self.items[0..self.len];
    }
};

pub const MAX_FRAMES: usize = 64;

/// A frame matched against words: the noun phrase each slot captured.
pub const Match = struct {
    frame: *const Frame,
    phrases: [MAX_SLOTS][]const []const u8 = .{ &.{}, &.{} },
    slots: usize = 0,
};

/// Matches words against one frame. A word element must equal the next word; a slot takes
/// every word up to the frame's next literal word (or the end) and must take at least one.
pub fn match_frame(frame: *const Frame, words: []const []const u8) ?Match {
    var m = Match{ .frame = frame };
    var w: usize = 0;
    const elements = frame.slice();
    for (elements, 0..) |element, e| {
        switch (element) {
            .word => |lit| {
                if (w >= words.len or !std.mem.eql(u8, words[w], lit)) return null;
                w += 1;
            },
            .thing => {
                // The next literal word bounds this slot; a trailing slot runs to the end.
                const stop: ?[]const u8 = if (e + 1 < elements.len) elements[e + 1].word else null;
                const start = w;
                while (w < words.len) : (w += 1) {
                    if (stop) |st| if (std.mem.eql(u8, words[w], st)) break;
                }
                if (w == start) return null;
                if (stop != null and w == words.len) return null;
                m.phrases[m.slots] = words[start..w];
                m.slots += 1;
            },
        }
    }
    if (w != words.len) return null;
    return m;
}

/// A resolved typed command: a cue and its targets.
pub const Command = struct {
    cue: []const u8,
    a: ?EntityId = null,
    b: ?EntityId = null,
};

/// What a typed line produced (D-057 point 4). `ambiguous` keeps its candidates so the next
/// line can answer the question with a bare noun.
pub const Outcome = union(enum) {
    empty,
    unknown_word: []const u8,
    not_understood,
    not_here,
    ambiguous: struct { items: [MAX_CANDIDATES]EntityId, len: usize },
    command: Command,

    /// The reply a player sees, or null when the command goes on to its cue.
    pub fn message(self: Outcome, world: *const World, buf: []u8) ?[]const u8 {
        var stream = std.io.fixedBufferStream(buf);
        const out = stream.writer();
        switch (self) {
            .empty, .command => return null,
            .unknown_word => |word| out.print("I don't know the word \"{s}\".", .{word}) catch {},
            .not_understood => out.writeAll("I don't understand that.") catch {},
            .not_here => out.writeAll("You don't see that here.") catch {},
            .ambiguous => |amb| {
                out.writeAll("Which do you mean: ") catch {};
                for (amb.items[0..amb.len], 0..) |entity, i| {
                    if (i > 0) out.writeAll(if (i + 1 == amb.len) " or " else ", ") catch {};
                    out.writeAll("the ") catch {};
                    const words = NameWords.of(world.get_entity_name(entity) orelse "thing");
                    for (0..words.len) |k| {
                        if (k > 0) out.writeByte(' ') catch {};
                        out.writeAll(words.word(k)) catch {};
                    }
                }
                out.writeByte('?') catch {};
            },
        }
        return stream.getWritten();
    }
};

/// Turns typed lines into commands, remembering one open "which do you mean" question.
pub const Interpreter = struct {
    /// The last line's words; `unknown_word` outcomes point here.
    words: Words = .{},
    answered_cue: [64]u8 = undefined,
    pending: ?Pending = null,

    /// An open "which do you mean" question: the command so far and the slot it is missing.
    const Pending = struct {
        cue_buf: [64]u8 = undefined,
        cue_len: usize,
        resolved: [MAX_SLOTS]?EntityId,
        open_slot: usize,
        slots: usize,
        candidates: [MAX_CANDIDATES]EntityId,
        candidate_count: usize,
    };

    /// Interprets one line. A line matching no frame while a question is open is taken as
    /// the answer, a noun naming one of the candidates; any other line drops the question.
    pub fn interpret(self: *Interpreter, world: *const World, aliases: []const AliasDecl, frames: []const Frame, scope: *const Scope, input: []const u8) Outcome {
        tokenize(input, &self.words) catch return .not_understood;
        const words = self.words.slice();
        if (words.len == 0) return .empty;

        var matched: ?Match = null;
        for (frames) |*f| {
            if (match_frame(f, words)) |m| {
                matched = m;
                break;
            }
        }

        if (matched == null) {
            if (self.pending) |*p| {
                var narrowed = Scope{};
                for (p.candidates[0..p.candidate_count]) |c| narrowed.add(c, .none);
                switch (resolve(world, aliases, &narrowed, words)) {
                    .one => |entity| {
                        p.resolved[p.open_slot] = entity;
                        const command = Command{ .cue = "", .a = p.resolved[0], .b = if (p.slots > 1) p.resolved[1] else null };
                        return self.finish(command);
                    },
                    else => {},
                }
            }
            self.pending = null;
            for (words) |word| if (!known_word(world, aliases, scope, frames, word)) return .{ .unknown_word = word };
            return .not_understood;
        }

        self.pending = null;
        const m = matched.?;
        var resolved: [MAX_SLOTS]?EntityId = .{ null, null };
        for (0..m.slots) |i| {
            switch (resolve(world, aliases, scope, m.phrases[i])) {
                .one => |entity| resolved[i] = entity,
                .none => {
                    for (m.phrases[i]) |word| if (!known_word(world, aliases, scope, frames, word)) return .{ .unknown_word = word };
                    return .not_here;
                },
                .many => |amb| {
                    var p = Pending{
                        .cue_len = @min(m.frame.cue.len, 64),
                        .resolved = resolved,
                        .open_slot = i,
                        .slots = m.slots,
                        .candidates = amb.items,
                        .candidate_count = amb.len,
                    };
                    @memcpy(p.cue_buf[0..p.cue_len], m.frame.cue[0..p.cue_len]);
                    // Later slots are resolved now so the answer completes the command.
                    var later = i + 1;
                    while (later < m.slots) : (later += 1) {
                        switch (resolve(world, aliases, scope, m.phrases[later])) {
                            .one => |entity| p.resolved[later] = entity,
                            else => return .not_understood,
                        }
                    }
                    self.pending = p;
                    return .{ .ambiguous = .{ .items = amb.items, .len = amb.len } };
                },
            }
        }
        return .{ .command = .{ .cue = m.frame.cue, .a = resolved[0], .b = resolved[1] } };
    }

    /// Completes a command from the open question and closes it. The cue is copied to
    /// `answered_cue`, which the returned command borrows until the next line.
    fn finish(self: *Interpreter, command: Command) Outcome {
        const p = self.pending.?;
        self.pending = null;
        @memcpy(self.answered_cue[0..p.cue_len], p.cue_buf[0..p.cue_len]);
        var c = command;
        c.cue = self.answered_cue[0..p.cue_len];
        return .{ .command = c };
    }
};
const testing = std.testing;

test "P26-01: tokenizer lowercases, drops articles and punctuation, keeps prepositions" {
    var words = Words{};
    try tokenize("> Pour the Grog into a MUG.", &words);
    try testing.expectEqual(@as(usize, 4), words.len);
    const expected = [_][]const u8{ "pour", "grog", "into", "mug" };
    for (expected, words.slice()) |want, got| try testing.expectEqualStrings(want, got);
    try testing.expect(is_preposition(words.items[2]));
    try tokenize("   ", &words);
    try testing.expectEqual(@as(usize, 0), words.len);
    try testing.expectError(Error.TooManyWords, tokenize("b c d e f g h i j k l m n o p q r", &words));
}

test "P26-01: frames parse slots and reject ambiguous or malformed shapes" {
    const pour = try parse_frame("Pours", "pour <thing> into <thing>");
    try testing.expectEqual(@as(usize, 4), pour.len);
    try testing.expectEqual(@as(usize, 2), pour.slots());
    try testing.expectEqualStrings("into", pour.elements[2].word);
    for (DEFAULT_FRAMES) |d| _ = try parse_frame(d.cue, d.text);
    const bad = [_][]const u8{ "", "<thing> on", "give <thing> <thing>", "use <thing> with <thing> on <thing>", "Look at <thing>", "look at the <thing>" };
    for (bad) |text| try testing.expectError(Error.InvalidFrame, parse_frame("LooksAt", text));
}

test "P26-01: entity names split into words at case changes and separators" {
    const cases = [_]struct { name: []const u8, words: []const []const u8 }{
        .{ .name = "ExposureSlip", .words = &.{ "exposure", "slip" } },
        .{ .name = "Great Hall", .words = &.{ "great", "hall" } },
        .{ .name = "cellar_door", .words = &.{ "cellar", "door" } },
        .{ .name = "Room25Key", .words = &.{ "room25", "key" } },
        .{ .name = "Ines", .words = &.{"ines"} },
    };
    for (cases) |c| {
        const got = NameWords.of(c.name);
        try testing.expectEqual(c.words.len, got.len);
        for (c.words, 0..) |want, i| try testing.expectEqualStrings(want, got.word(i));
    }
}

test "P26-01: nouns resolve within scope, through aliases, and report ambiguity" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    const room = try world.intern_entity("CommandStudy");
    const elsewhere = try world.intern_entity("CommandCellar");
    const desk_wp = try spatial.graph.add_waypoint(room, 0, 0, "CommandDesk");
    _ = try world.intern_entity("CommandDesk"); // the compiler interns every mark
    const cellar_wp = try spatial.graph.add_waypoint(elsewhere, 0, 0, "CommandCellarFloor");
    const hero = try world.intern_entity("CommandHero");
    const butler = try world.intern_entity("CommandButler");
    const cook = try world.intern_entity("CommandCook");
    const brass = try world.intern_entity("BrassKey");
    const iron = try world.intern_entity("IronKey");
    const lamp = try world.intern_entity("OilLamp");
    try spatial.register_entity(hero, desk_wp, 1);
    try spatial.register_entity(butler, desk_wp, 1);
    try spatial.register_entity(cook, cellar_wp, 1);
    try spatial.add_hotspot(lamp, room, .{ .x = 0, .y = 0 }, 2, "Oil Lamp", "A lamp.");
    const carries = try world.intern_relation("Carries", .set);
    const inventory = try world.intern_relation("InInventory", .set);
    try world.remember(hero, carries, brass.to_int(), 0);
    try world.remember(hero, inventory, iron.to_int(), 0);

    const scope = Scope.gather(&world, &spatial, room, hero);
    try testing.expect(std.mem.indexOfScalar(EntityId, scope.slice(), butler) != null);
    try testing.expect(std.mem.indexOfScalar(EntityId, scope.slice(), cook) == null); // other room
    try testing.expect(std.mem.indexOfScalar(EntityId, scope.slice(), hero) == null); // the actor
    try testing.expect(std.mem.indexOfScalar(EntityId, scope.slice(), world.lookup_entity("CommandDesk").?) != null);

    const alias_phrases = [_][]const u8{"lantern"};
    const aliases = [_]AliasDecl{.{ .entity = lamp, .phrases = &alias_phrases }};
    try (aliases[0]).validate();
    try testing.expectEqual(Resolution{ .one = brass }, resolve(&world, &aliases, &scope, &.{ "brass", "key" }));
    try testing.expectEqual(Resolution{ .one = lamp }, resolve(&world, &aliases, &scope, &.{"lantern"}));
    try testing.expectEqual(Resolution{ .one = lamp }, resolve(&world, &aliases, &scope, &.{ "oil", "lamp" }));
    try testing.expectEqual(Resolution.none, resolve(&world, &aliases, &scope, &.{"cook"}));
    const keys = resolve(&world, &aliases, &scope, &.{"key"});
    try testing.expectEqual(@as(usize, 2), keys.many.len);

    const frames = [_]Frame{try parse_frame("LooksAt", "examine <thing>")};
    try testing.expect(known_word(&world, &aliases, &scope, &frames, "examine"));
    try testing.expect(known_word(&world, &aliases, &scope, &frames, "lantern"));
    try testing.expect(!known_word(&world, &aliases, &scope, &frames, "xyzzy"));
}

test "P26-02: frames match slots bounded by their next word" {
    const pour = try parse_frame("Pours", "pour <thing> into <thing>");
    const m = match_frame(&pour, &.{ "pour", "caustic", "grog", "into", "pewter", "mug" }).?;
    try testing.expectEqual(@as(usize, 2), m.slots);
    try testing.expectEqual(@as(usize, 2), m.phrases[0].len);
    try testing.expectEqualStrings("pewter", m.phrases[1][0]);
    try testing.expect(match_frame(&pour, &.{ "pour", "grog" }) == null); // missing "into"
    try testing.expect(match_frame(&pour, &.{ "pour", "into", "mug" }) == null); // empty slot
    const look = try parse_frame("LooksAt", "look at <thing>");
    try testing.expect(match_frame(&look, &.{ "look", "at" }) == null);
    try testing.expect(match_frame(&look, &.{ "look", "lamp" }) == null);
}

test "P26-02: the interpreter resolves commands, asks which, and explains failures" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    const room = try world.intern_entity("ParseStudy");
    const desk_wp = try spatial.graph.add_waypoint(room, 0, 0, "ParseDesk");
    _ = try world.intern_entity("ParseDesk");
    const hero = try world.intern_entity("ParseHero");
    const butler = try world.intern_entity("ParseButler");
    const brass = try world.intern_entity("BrassKey");
    const iron = try world.intern_entity("IronKey");
    const lamp = try world.intern_entity("OilLamp");
    try spatial.register_entity(hero, desk_wp, 1);
    try spatial.register_entity(butler, desk_wp, 1);
    try spatial.add_hotspot(lamp, room, .{ .x = 0, .y = 0 }, 2, "Oil Lamp", "A lamp.");
    const carries = try world.intern_relation("Carries", .set);
    try world.remember(hero, carries, brass.to_int(), 0);
    try world.remember(hero, carries, iron.to_int(), 0);
    const scope = Scope.gather(&world, &spatial, room, hero);

    const script = [_]CommandDecl{.{ .cue = "Pours", .text = "pour <thing> into <thing>" }};
    const frames = FrameList.build(&script);
    const lantern = [_][]const u8{"lantern"};
    const aliases = [_]AliasDecl{.{ .entity = lamp, .phrases = &lantern }};
    var interp = Interpreter{};
    var buf: [128]u8 = undefined;

    const look = interp.interpret(&world, &aliases, frames.slice(), &scope, "> Examine the lantern.");
    try testing.expectEqualStrings("LooksAt", look.command.cue);
    try testing.expectEqual(lamp, look.command.a.?);

    const use = interp.interpret(&world, &aliases, frames.slice(), &scope, "use brass key on lamp");
    try testing.expectEqualStrings("Uses", use.command.cue);
    try testing.expectEqual(brass, use.command.a.?);
    try testing.expectEqual(lamp, use.command.b.?);

    const ask = interp.interpret(&world, &aliases, frames.slice(), &scope, "ask butler about iron key");
    try testing.expectEqualStrings("TalksTo", ask.command.cue);
    try testing.expectEqual(iron, ask.command.b.?);

    // "key" names two things: the interpreter asks, and a bare noun answers.
    const which = interp.interpret(&world, &aliases, frames.slice(), &scope, "use key on lamp");
    try testing.expectEqualStrings("Which do you mean: the brass key or the iron key?", which.message(&world, &buf).?);
    const answered = interp.interpret(&world, &aliases, frames.slice(), &scope, "iron");
    try testing.expectEqualStrings("Uses", answered.command.cue);
    try testing.expectEqual(iron, answered.command.a.?);
    try testing.expectEqual(lamp, answered.command.b.?);
    // The question is closed: the same bare noun now means nothing.
    try testing.expectEqual(Outcome.not_understood, interp.interpret(&world, &aliases, frames.slice(), &scope, "iron"));

    const unknown = interp.interpret(&world, &aliases, frames.slice(), &scope, "examine xyzzy");
    try testing.expectEqualStrings("I don't know the word \"xyzzy\".", unknown.message(&world, &buf).?);
    // A word known only from frames, naming nothing in scope.
    try testing.expectEqual(Outcome.not_here, interp.interpret(&world, &aliases, frames.slice(), &scope, "examine pour"));
    try testing.expectEqual(Outcome.not_understood, interp.interpret(&world, &aliases, frames.slice(), &scope, "lamp examine"));
    try testing.expectEqual(Outcome.empty, interp.interpret(&world, &aliases, frames.slice(), &scope, "  the  "));

    // Script frames are tried first and reach script cues.
    const poured = interp.interpret(&world, &aliases, frames.slice(), &scope, "pour lantern into brass key");
    try testing.expectEqualStrings("Pours", poured.command.cue);
}
