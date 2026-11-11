//! Music Macro Language scores (P28-01, D-060): one track's MML text parsed into a flat list of
//! integer-timed events. The module imports only `std`, so the audio thread can read its event
//! type (P28-02) without pulling in the compiler, and the compiler can parse `score` strings
//! (P28-03) without pulling in audio.
//!
//! Score text comes from scripts, so it is untrusted: every count, range, nesting depth, event
//! total, and the work spent expanding repeats is bounded, and every rejection names the
//! offending column.

const std = @import("std");

/// Note lengths are integer ticks. 192 per whole note gives exact sixteenths, sixty-fourths,
/// triplets (3, 6, 12, 24, 48), and one dot on anything down to a thirty-second.
pub const TICKS_PER_WHOLE: u32 = 192;
pub const MAX_EVENTS: usize = 4096;
pub const MAX_LOOP_DEPTH: usize = 4;
pub const MAX_REPEAT: u32 = 99;
/// Characters read, counting every pass through a repeat body. Bounds a score such as nested
/// empty repeats, which emits no events but would otherwise spin for millions of passes.
pub const MAX_WORK: usize = 1 << 18;
pub const MIN_TEMPO: u32 = 32;
pub const MAX_TEMPO: u32 = 255;
pub const MAX_VOLUME: u32 = 15;
/// `@n` selects one of the envelope presets P28-02 defines.
pub const MAX_ENVELOPE: u32 = 7;
pub const MAX_OCTAVE: u8 = 8;

pub const DEFAULT_TEMPO: u16 = 120;
pub const DEFAULT_OCTAVE: u8 = 4;
pub const DEFAULT_LENGTH: u32 = TICKS_PER_WHOLE / 4;

pub const TrackKind = enum { melodic, percussion };

/// The engine's three drum voices; the values match `BgmPattern.drum_pattern` codes.
pub const Drum = enum(u8) { kick = 1, snare = 2, hat = 3 };

pub const Note = struct { midi: u8, ticks: u32 };
pub const Hit = struct { drum: Drum, ticks: u32 };

pub const Event = union(enum) {
    note: Note,
    rest: u32,
    hit: Hit,
    /// Beats per minute from this event on.
    tempo: u16,
    /// 0 (silent) to 15 (full).
    volume: u8,
    /// Envelope preset index, 0 to `MAX_ENVELOPE`.
    envelope: u8,

    /// How long the event holds its track; state changes take no time.
    pub fn ticks(self: Event) u32 {
        return switch (self) {
            .note => |n| n.ticks,
            .rest => |r| r,
            .hit => |h| h.ticks,
            else => 0,
        };
    }
};

pub const Score = struct {
    kind: TrackKind,
    events: []Event,
    /// Index of the first event replayed after the last one (`L`); null plays once.
    loop_start: ?usize,
    total_ticks: u64,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Score) void {
        self.allocator.free(self.events);
        self.events = &.{};
    }
};

/// Where and why a score was rejected. `message` is static text.
pub const Diagnostic = struct {
    offset: usize = 0,
    line: u32 = 1,
    column: u32 = 1,
    message: []const u8 = "",
};

pub const ParseError = error{ InvalidScore, OutOfMemory };

/// Parses one track. Octave changes, lengths, and other state inside `[ ]n` apply on every pass,
/// as in an MML player, so `[c >]2` plays two different octaves.
pub fn parse(allocator: std.mem.Allocator, text: []const u8, kind: TrackKind, diag: *Diagnostic) ParseError!Score {
    var p = Parser{ .text = text, .kind = kind, .diag = diag, .events = std.ArrayList(Event).init(allocator) };
    errdefer p.events.deinit();
    try p.run();
    var total: u64 = 0;
    for (p.events.items) |e| total += e.ticks();
    return .{
        .kind = kind,
        .events = try p.events.toOwnedSlice(),
        .loop_start = p.loop_start,
        .total_ticks = total,
        .allocator = allocator,
    };
}

const Repeat = struct {
    /// Offset of the `[`, for an unclosed-repeat error.
    open: usize,
    /// Offset just after the `[`, where each pass restarts.
    body: usize,
    /// Passes still to run; null until the first `]` reads the count.
    remaining: ?u32 = null,
};

const Parser = struct {
    text: []const u8,
    kind: TrackKind,
    diag: *Diagnostic,
    events: std.ArrayList(Event),
    pos: usize = 0,
    work: usize = 0,
    octave: u8 = DEFAULT_OCTAVE,
    length: u32 = DEFAULT_LENGTH,
    repeats: [MAX_LOOP_DEPTH]Repeat = undefined,
    depth: usize = 0,
    loop_start: ?usize = null,
    /// The previous command was a note, rest, or hit, so `&` may extend it.
    tieable: bool = false,

    fn fail(self: *Parser, at: usize, message: []const u8) ParseError {
        var line: u32 = 1;
        var column: u32 = 1;
        for (self.text[0..@min(at, self.text.len)]) |ch| {
            if (ch == '\n') {
                line += 1;
                column = 1;
            } else column += 1;
        }
        self.diag.* = .{ .offset = at, .line = line, .column = column, .message = message };
        return error.InvalidScore;
    }

    fn peek(self: *const Parser) ?u8 {
        return if (self.pos < self.text.len) self.text[self.pos] else null;
    }

    fn emit(self: *Parser, at: usize, event: Event) ParseError!void {
        if (self.events.items.len == MAX_EVENTS) return self.fail(at, "score has more than 4096 events");
        try self.events.append(event);
    }

    /// Up to three digits; null when no digit follows.
    fn number(self: *Parser) ?u32 {
        var value: u32 = 0;
        var digits: usize = 0;
        while (self.peek()) |ch| {
            if (ch < '0' or ch > '9' or digits == 3) break;
            value = value * 10 + (ch - '0');
            digits += 1;
            self.pos += 1;
        }
        return if (digits == 0) null else value;
    }

    fn required(self: *Parser, at: usize, min: u32, max: u32, message: []const u8) ParseError!u32 {
        const value = self.number() orelse return self.fail(at, message);
        if (value < min or value > max) return self.fail(at, message);
        return value;
    }

    /// A length (`4`, `8.`, `16..`) in ticks, or `fallback` and its dots when no digits follow.
    fn length_spec(self: *Parser, at: usize, fallback: ?u32) ParseError!u32 {
        var ticks: u32 = undefined;
        if (self.number()) |n| {
            if (n == 0 or n > 64 or TICKS_PER_WHOLE % n != 0) return self.fail(at, "length must divide a whole note: 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, or 64");
            ticks = TICKS_PER_WHOLE / n;
        } else {
            ticks = fallback orelse return self.fail(at, "l needs a length");
        }
        var add = ticks;
        while (self.peek() == '.') {
            self.pos += 1;
            if (add % 2 != 0) return self.fail(at, "dotted length is finer than 1/192 of a whole note");
            add /= 2;
            ticks += add;
        }
        return ticks;
    }

    /// A note letter and its accidental at the current octave, as a MIDI pitch.
    fn pitch(self: *Parser, at: usize) ParseError!u8 {
        const letter = self.text[self.pos];
        self.pos += 1;
        const semitones = [_]i32{ 9, 11, 0, 2, 4, 5, 7 }; // a b c d e f g
        var semi = semitones[letter - 'a'];
        if (self.peek()) |ch| {
            if (ch == '+' or ch == '#') {
                semi += 1;
                self.pos += 1;
            } else if (ch == '-') {
                semi -= 1;
                self.pos += 1;
            }
        }
        // o0 c- is 11 and o8 b+ is 120, so every written pitch fits MIDI 1..127; 0 stays free
        // to mean silence in the grid sequencer.
        const midi = (@as(i32, self.octave) + 1) * 12 + semi;
        if (midi < 1 or midi > 127) return self.fail(at, "pitch outside MIDI 1..127");
        return @intCast(midi);
    }

    fn drum(letter: u8) ?Drum {
        return switch (letter) {
            'k' => .kick,
            's' => .snare,
            'h' => .hat,
            else => null,
        };
    }

    fn tie(self: *Parser, at: usize) ParseError!void {
        if (!self.tieable) return self.fail(at, "& must follow a note, rest, or drum hit");
        self.pos += 1;
        while (self.peek()) |ch| {
            if (ch != ' ' and ch != '\t') break;
            self.pos += 1;
        }
        const last = &self.events.items[self.events.items.len - 1];
        const sym_at = self.pos;
        if (self.peek()) |ch| {
            // A symbol after `&` must repeat the tied one; any other note, rest, or hit would
            // otherwise be read as a bare tie of the default length followed by a new event.
            const is_symbol = (ch >= 'a' and ch <= 'g') or ch == 'r' or drum(ch) != null;
            switch (last.*) {
                .note => |n| if (ch >= 'a' and ch <= 'g') {
                    if (try self.pitch(sym_at) != n.midi) return self.fail(sym_at, "a tie joins notes of the same pitch");
                } else if (is_symbol) return self.fail(sym_at, "a tie joins notes of the same pitch"),
                .rest => if (ch == 'r') {
                    self.pos += 1;
                } else if (is_symbol) return self.fail(sym_at, "a tie joins a rest to a rest"),
                .hit => |h| if (drum(ch)) |d| {
                    if (d != h.drum) return self.fail(sym_at, "a tie joins hits of the same drum");
                    self.pos += 1;
                } else if (is_symbol) return self.fail(sym_at, "a tie joins hits of the same drum"),
                else => unreachable,
            }
        }
        const extra = try self.length_spec(sym_at, self.length);
        switch (last.*) {
            .note => |*n| n.ticks += extra,
            .rest => |*r| r.* += extra,
            .hit => |*h| h.ticks += extra,
            else => unreachable,
        }
    }

    fn close_repeat(self: *Parser, at: usize) ParseError!void {
        if (self.depth == 0) return self.fail(at, "] without a matching [");
        self.pos += 1;
        const count = self.number() orelse 2;
        if (count < 1 or count > MAX_REPEAT) return self.fail(at, "repeat count must be 1 to 99");
        const top = &self.repeats[self.depth - 1];
        if (top.remaining == null) top.remaining = count - 1;
        if (top.remaining.? > 0) {
            top.remaining.? -= 1;
            self.pos = top.body;
        } else {
            self.depth -= 1;
        }
    }

    fn run(self: *Parser) ParseError!void {
        while (self.peek()) |ch| {
            self.work += 1;
            if (self.work > MAX_WORK) return self.fail(self.pos, "score expands too far; shorten its repeats");
            const at = self.pos;
            const was_tieable = self.tieable;
            self.tieable = false;
            switch (ch) {
                ' ', '\t', '\n', '\r' => {
                    self.pos += 1;
                    self.tieable = was_tieable;
                },
                'a'...'g' => {
                    if (self.kind == .percussion) return self.fail(at, "a percussion track plays k, s, and h, not notes");
                    const midi = try self.pitch(at);
                    const ticks = try self.length_spec(at, self.length);
                    try self.emit(at, .{ .note = .{ .midi = midi, .ticks = ticks } });
                    self.tieable = true;
                },
                'k', 's', 'h' => {
                    if (self.kind == .melodic) return self.fail(at, "drum letters k, s, and h belong on a percussion track");
                    self.pos += 1;
                    const ticks = try self.length_spec(at, self.length);
                    try self.emit(at, .{ .hit = .{ .drum = drum(ch).?, .ticks = ticks } });
                    self.tieable = true;
                },
                'r' => {
                    self.pos += 1;
                    const ticks = try self.length_spec(at, self.length);
                    try self.emit(at, .{ .rest = ticks });
                    self.tieable = true;
                },
                '&' => {
                    self.tieable = was_tieable;
                    try self.tie(at);
                    self.tieable = true;
                },
                't' => {
                    self.pos += 1;
                    const bpm = try self.required(at, MIN_TEMPO, MAX_TEMPO, "tempo must be t32 to t255");
                    try self.emit(at, .{ .tempo = @intCast(bpm) });
                },
                'v' => {
                    self.pos += 1;
                    const level = try self.required(at, 0, MAX_VOLUME, "volume must be v0 to v15");
                    try self.emit(at, .{ .volume = @intCast(level) });
                },
                '@' => {
                    self.pos += 1;
                    const preset = try self.required(at, 0, MAX_ENVELOPE, "envelope must be @0 to @7");
                    try self.emit(at, .{ .envelope = @intCast(preset) });
                },
                'l' => {
                    self.pos += 1;
                    self.length = try self.length_spec(at, null);
                },
                'o', '<', '>' => {
                    if (self.kind == .percussion) return self.fail(at, "a percussion track has no octave");
                    self.pos += 1;
                    if (ch == 'o') {
                        self.octave = @intCast(try self.required(at, 0, MAX_OCTAVE, "octave must be o0 to o8"));
                    } else if (ch == '>') {
                        if (self.octave == MAX_OCTAVE) return self.fail(at, "> above octave 8");
                        self.octave += 1;
                    } else {
                        if (self.octave == 0) return self.fail(at, "< below octave 0");
                        self.octave -= 1;
                    }
                },
                '[' => {
                    if (self.depth == MAX_LOOP_DEPTH) return self.fail(at, "repeats nest at most 4 deep");
                    self.pos += 1;
                    self.repeats[self.depth] = .{ .open = at, .body = self.pos };
                    self.depth += 1;
                },
                ']' => try self.close_repeat(at),
                'L' => {
                    if (self.depth > 0) return self.fail(at, "L cannot sit inside a repeat");
                    if (self.loop_start != null) return self.fail(at, "a track has one L");
                    self.pos += 1;
                    self.loop_start = self.events.items.len;
                },
                else => return self.fail(at, "unknown MML command"),
            }
        }
        if (self.depth > 0) return self.fail(self.repeats[self.depth - 1].open, "[ without a matching ]");
        if (self.loop_start) |start| {
            // A loop with no duration would replay forever without advancing the clock.
            var ticks: u64 = 0;
            for (self.events.items[start..]) |e| ticks += e.ticks();
            if (ticks == 0) return self.fail(self.text.len, "L needs a note, rest, or hit after it");
        }
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn parse_ok(text: []const u8, kind: TrackKind) !Score {
    var diag = Diagnostic{};
    return parse(testing.allocator, text, kind, &diag) catch |err| {
        std.debug.print("unexpected MML error at {d}:{d}: {s}\n", .{ diag.line, diag.column, diag.message });
        return err;
    };
}

fn expect_error(text: []const u8, kind: TrackKind, column: u32, message: []const u8) !void {
    var diag = Diagnostic{};
    try testing.expectError(error.InvalidScore, parse(testing.allocator, text, kind, &diag));
    try testing.expectEqualStrings(message, diag.message);
    try testing.expectEqual(column, diag.column);
}

fn expect_notes(score: Score, expected: []const [2]u32) !void {
    var i: usize = 0;
    for (score.events) |e| switch (e) {
        .note => |n| {
            try testing.expect(i < expected.len);
            try testing.expectEqual(expected[i][0], n.midi);
            try testing.expectEqual(expected[i][1], n.ticks);
            i += 1;
        },
        else => {},
    };
    try testing.expectEqual(expected.len, i);
}

test "P28-01: the roadmap example parses to tempo and five timed notes" {
    var score = try parse_ok("t120 o4 l8 cdef e2", .melodic);
    defer score.deinit();
    try testing.expectEqual(Event{ .tempo = 120 }, score.events[0]);
    try expect_notes(score, &.{ .{ 60, 24 }, .{ 62, 24 }, .{ 64, 24 }, .{ 65, 24 }, .{ 64, 96 } });
    try testing.expectEqual(@as(u64, 4 * 24 + 96), score.total_ticks);
    try testing.expectEqual(@as(?usize, null), score.loop_start);
}

test "P28-01: accidentals, octave shifts, dots, triplets, and default length" {
    var score = try parse_ok("o4 c+4. d-8 > c16 < < b c#3 l16. e", .melodic);
    defer score.deinit();
    try expect_notes(score, &.{ .{ 61, 72 }, .{ 61, 24 }, .{ 72, 12 }, .{ 59, 48 }, .{ 49, 64 }, .{ 52, 18 } });
}

test "P28-01: ties extend the previous note, rest, or hit" {
    var score = try parse_ok("c4&8 c4 & c8 r2&4 r4&r4", .melodic);
    defer score.deinit();
    try testing.expectEqual(@as(usize, 4), score.events.len);
    try testing.expectEqual(@as(u32, 72), score.events[0].ticks());
    try testing.expectEqual(@as(u32, 72), score.events[1].ticks());
    try testing.expectEqual(@as(u32, 144), score.events[2].ticks());
    try testing.expectEqual(@as(u32, 96), score.events[3].ticks());
    var drums = try parse_ok("k8&k8 h", .percussion);
    defer drums.deinit();
    try testing.expectEqual(@as(u32, 48), drums.events[0].ticks());
    try expect_error("c4&d8", .melodic, 4, "a tie joins notes of the same pitch");
    try expect_error("c4&r8", .melodic, 4, "a tie joins notes of the same pitch");
    try expect_error("r4&c4", .melodic, 4, "a tie joins a rest to a rest");
    try expect_error("k4&r4", .percussion, 4, "a tie joins hits of the same drum");
    try expect_error("k4&s4", .percussion, 4, "a tie joins hits of the same drum");
    try expect_error("c4 v8 &8", .melodic, 7, "& must follow a note, rest, or drum hit");
    try expect_error("&4", .melodic, 1, "& must follow a note, rest, or drum hit");
}

test "P28-01: repeats re-read their body, so relative state changes on every pass" {
    var climb = try parse_ok("o4 [c >]3 c", .melodic);
    defer climb.deinit();
    try expect_notes(climb, &.{ .{ 60, 48 }, .{ 72, 48 }, .{ 84, 48 }, .{ 96, 48 } });
    var nested = try parse_ok("l8 [[c]3 d]2 e", .melodic);
    defer nested.deinit();
    try expect_notes(nested, &.{ .{ 60, 24 }, .{ 60, 24 }, .{ 60, 24 }, .{ 62, 24 }, .{ 60, 24 }, .{ 60, 24 }, .{ 60, 24 }, .{ 62, 24 }, .{ 64, 24 } });
    var once = try parse_ok("[c d]1 [e] f", .melodic);
    defer once.deinit();
    try expect_notes(once, &.{ .{ 60, 48 }, .{ 62, 48 }, .{ 64, 48 }, .{ 64, 48 }, .{ 65, 48 } });
    try expect_error("c [d e", .melodic, 3, "[ without a matching ]");
    try expect_error("c ]2", .melodic, 3, "] without a matching [");
    try expect_error("[c]0", .melodic, 3, "repeat count must be 1 to 99");
}

test "P28-01: L marks where the track loops and must be followed by time" {
    var score = try parse_ok("t100 c L d e", .melodic);
    defer score.deinit();
    try testing.expectEqual(@as(?usize, 2), score.loop_start);
    try testing.expectEqual(Event{ .note = .{ .midi = 62, .ticks = 48 } }, score.events[score.loop_start.?]);
    try expect_error("c L v8", .melodic, 7, "L needs a note, rest, or hit after it");
    try expect_error("[c L]2", .melodic, 4, "L cannot sit inside a repeat");
    try expect_error("L c L d", .melodic, 5, "a track has one L");
}

test "P28-01: percussion tracks use drum letters and melodic tracks refuse them" {
    var score = try parse_ok("t96 l8 v12 @1 [k h s h]2 L k4 r4", .percussion);
    defer score.deinit();
    try testing.expectEqual(Event{ .hit = .{ .drum = .kick, .ticks = 24 } }, score.events[3]);
    try testing.expectEqual(Event{ .hit = .{ .drum = .snare, .ticks = 24 } }, score.events[5]);
    try testing.expectEqual(Event{ .volume = 12 }, score.events[1]);
    try testing.expectEqual(Event{ .envelope = 1 }, score.events[2]);
    try testing.expectEqual(@as(?usize, 11), score.loop_start);
    try testing.expectEqual(@as(u64, 8 * 24 + 48 + 48), score.total_ticks);
    try expect_error("l8 k c", .percussion, 6, "a percussion track plays k, s, and h, not notes");
    try expect_error("o3 k", .percussion, 1, "a percussion track has no octave");
    try expect_error("c k", .melodic, 3, "drum letters k, s, and h belong on a percussion track");
}

test "P28-01: out-of-range values are refused with their line and column" {
    try expect_error("t20 c", .melodic, 1, "tempo must be t32 to t255");
    try expect_error("t c", .melodic, 1, "tempo must be t32 to t255");
    try expect_error("c v16", .melodic, 3, "volume must be v0 to v15");
    try expect_error("@8", .melodic, 1, "envelope must be @0 to @7");
    try expect_error("o9", .melodic, 1, "octave must be o0 to o8");
    try expect_error("o8 >", .melodic, 4, "> above octave 8");
    try expect_error("o0 <", .melodic, 4, "< below octave 0");
    try expect_error("c5", .melodic, 1, "length must divide a whole note: 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, or 64");
    try expect_error("c64.", .melodic, 1, "dotted length is finer than 1/192 of a whole note");
    try expect_error("l c", .melodic, 1, "l needs a length");
    try expect_error("C", .melodic, 1, "unknown MML command");
    var diag = Diagnostic{};
    try testing.expectError(error.InvalidScore, parse(testing.allocator, "c d\n  e x", .melodic, &diag));
    try testing.expectEqual(@as(u32, 2), diag.line);
    try testing.expectEqual(@as(u32, 5), diag.column);
    try testing.expectEqual(@as(usize, 8), diag.offset);
}

test "P28-01: nesting, event count, and repeat work are bounded" {
    try expect_error("[[[[[c]2]2]2]2]2", .melodic, 5, "repeats nest at most 4 deep");
    try expect_error("[[[c]99]99]2", .melodic, 4, "score has more than 4096 events");
    var diag = Diagnostic{};
    try testing.expectError(error.InvalidScore, parse(testing.allocator, "[[[[ ]99]99]99]99", .melodic, &diag));
    try testing.expectEqualStrings("score expands too far; shorten its repeats", diag.message);
    var empty = try parse_ok("", .melodic);
    defer empty.deinit();
    try testing.expectEqual(@as(usize, 0), empty.events.len);
}
