//! Arranged proof music (P34-08, D-089): tracks written as several two-bar grid sections and
//! an order that replays them in new keys and with parts dropped, so each runs for minutes
//! before it repeats. `art.zig` puts these tracks in the proofs' soundtrack.
//!
//! Sections are written one token per sixteenth-note step: a note name with its octave (`c4`
//! is MIDI 60, `f#3`, `bb2`), a drum (`k` kick, `s` snare, `h` hat), or `-` for a rest. `|`
//! only marks bars for the reader. Every part of a section must hold the same number of steps,
//! at most `audio.BGM_STEPS`, which becomes the section's length; a mistake is a compile error.
//!
//! Provenance (D-089): the maintainer orchestrated the design, choosing the form (written
//! sections and an arrangement), the scope, the order of the work, and which tracks to keep,
//! and approves each track by listening. An LLM (Claude, an Anthropic model) wrote this file:
//! the notation, the checks, and the music itself, every section's chord progression, melody,
//! bass line, and drum part, and every arrangement. Each track's section A keeps its earlier
//! two-bar loop (commit `6bfe0ce`, 2026-11-07), which Claude also wrote, in an earlier session
//! (per the maintainer, 2026-11-14). No audio model, recording, or sample is
//! involved; the engine's synthesizer (`src/audio.zig`) renders these notes with integer
//! arithmetic.
const std = @import("std");
const bespoke = @import("bespoke");
const audio = bespoke.audio;

pub const Arranged = struct {
    sections: []const audio.BgmPattern,
    arrangement: []const audio.SectionPlay,
};

fn note_value(comptime tok: []const u8) u8 {
    if (tok.len == 1) {
        return switch (tok[0]) {
            '-' => 0,
            'k' => 1,
            's' => 2,
            'h' => 3,
            else => @compileError("unknown step: " ++ tok),
        };
    }
    const pitch_class: i16 = switch (tok[0]) {
        'c' => 0,
        'd' => 2,
        'e' => 4,
        'f' => 5,
        'g' => 7,
        'a' => 9,
        'b' => 11,
        else => @compileError("unknown note: " ++ tok),
    };
    var i: usize = 1;
    var accidental: i16 = 0;
    if (tok[i] == '#') {
        accidental = 1;
        i += 1;
    } else if (tok[i] == 'b' and i + 1 < tok.len) {
        accidental = -1;
        i += 1;
    }
    const octave = std.fmt.parseInt(i16, tok[i..], 10) catch @compileError("bad octave: " ++ tok);
    const midi = (octave + 1) * 12 + pitch_class + accidental;
    if (midi < 1 or midi > 127) @compileError("note out of MIDI range: " ++ tok);
    return @intCast(midi);
}

fn part(comptime text: []const u8, count: *usize) [audio.BGM_STEPS]u8 {
    var out = @as([audio.BGM_STEPS]u8, @splat(0));
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, text, " |\n");
    while (it.next()) |tok| {
        if (n >= audio.BGM_STEPS) @compileError("more than BGM_STEPS steps: " ++ text);
        out[n] = note_value(tok);
        n += 1;
    }
    count.* = n;
    return out;
}

fn section(comptime bpm: u16, comptime bass: []const u8, comptime lead: []const u8, comptime chords: []const u8, comptime drums: []const u8) audio.BgmPattern {
    @setEvalBranchQuota(100_000);
    var counts: [4]usize = undefined;
    const p = audio.BgmPattern{
        .bpm = bpm,
        .step_count = 0,
        .bass_notes = part(bass, &counts[0]),
        .lead_notes = part(lead, &counts[1]),
        .chord_notes = part(chords, &counts[2]),
        .drum_pattern = part(drums, &counts[3]),
    };
    for (counts[1..]) |c| {
        if (c != counts[0]) @compileError("a section's parts differ in length: " ++ lead);
    }
    if (counts[0] == 0) @compileError("an empty section");
    var out = p;
    out.step_count = @intCast(counts[0]);
    return out;
}

/// Every track names its sections in this order, so an arrangement can name them.
const SECTION_NAMES = [_][]const u8{ "a", "a2", "b", "b2", "c", "c2", "d", "d2" };

/// An arrangement written as passes separated by spaces: a section name, then an optional
/// key change in semitones (`b+5`, `b2-2`), then an optional `/` and the parts to mute (`l`
/// lead, `b` bass, `c` chords, `d` drums), as in `a/ld` for the theme with only bass and
/// chords. A mistake is a compile error.
fn order(comptime text: []const u8) [count_passes(text)]audio.SectionPlay {
    @setEvalBranchQuota(100_000);
    var out: [count_passes(text)]audio.SectionPlay = undefined;
    var it = std.mem.tokenizeAny(u8, text, " \n");
    var n: usize = 0;
    while (it.next()) |tok| : (n += 1) out[n] = pass_of(tok);
    return out;
}

fn count_passes(comptime text: []const u8) usize {
    @setEvalBranchQuota(100_000);
    var it = std.mem.tokenizeAny(u8, text, " \n");
    var n: usize = 0;
    while (it.next()) |_| n += 1;
    return n;
}

fn pass_of(comptime tok: []const u8) audio.SectionPlay {
    const name_end = std.mem.indexOfAny(u8, tok, "+-/") orelse tok.len;
    const name = tok[0..name_end];
    var pass = audio.SectionPlay{ .section = for (SECTION_NAMES, 0..) |known, i| {
        if (std.mem.eql(u8, known, name)) break @intCast(i);
    } else @compileError("unknown section in arrangement: " ++ tok) };
    const mute_at = std.mem.indexOfScalar(u8, tok, '/') orelse tok.len;
    if (name_end < mute_at) {
        pass.transpose = std.fmt.parseInt(i8, tok[name_end..mute_at], 10) catch @compileError("bad key change: " ++ tok);
    }
    if (mute_at < tok.len) {
        for (tok[mute_at + 1 ..]) |c| switch (c) {
            'l' => pass.mute.lead = true,
            'b' => pass.mute.bass = true,
            'c' => pass.mute.chords = true,
            'd' => pass.mute.drums = true,
            else => @compileError("unknown part to mute: " ++ tok),
        };
    }
    return pass;
}

// ---------------------------------------------------------------------------
// Brackwater Tidewalk: a seafaring shanty in A minor, 112 bpm. Section A is the original
// two-bar theme; the others answer it, lift into C major for a chorus, settle into a D minor
// bridge, and run sixteenths like a hornpipe. One hornpipe pass sits in D minor, so its last
// chord (A) leads home.
// ---------------------------------------------------------------------------

const TIDE_BPM = 112;
const TIDEWALK_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(TIDE_BPM,
        \\a2 - - - f2 - - - g2 - - - e2 - - - | a2 - - - f2 - - - g2 - - - a2 - - -
    ,
        \\e4 a4 c5 b4 a4 - g4 - a4 c5 d5 - e5 - - - | e5 d5 c5 b4 a4 - g4 e4 f4 g4 a4 - a4 - - -
    ,
        \\a3 - c4 - f3 - a3 - g3 - b3 - e3 - g3 - | a3 - c4 - f3 - a3 - g3 - b3 - a3 - c4 -
    ,
        \\k - h - s - k - k - h - s - h - | k - h - s - k - k - h - s h k s
    ),
    // A2: the theme's answer, turning to E
    section(TIDE_BPM,
        \\a2 - - - f2 - - - g2 - - - e2 - - - | f2 - - - g2 - - - e2 - - - e2 - - -
    ,
        \\e4 a4 c5 b4 a4 - g4 - a4 c5 d5 - e5 - g5 - | f5 e5 d5 c5 d5 - b4 g4 b4 c5 b4 - g#4 - - -
    ,
        \\a3 - c4 - f3 - a3 - g3 - b3 - e3 - g#3 - | f3 - a3 - g3 - b3 - e3 - g#3 - b3 - e4 -
    ,
        \\k - h - s - k - k - h - s - h - | k - h - s - k - k - h - s s k s
    ),
    // B: the chorus, in C major with a walking bass
    section(TIDE_BPM,
        \\c3 - g2 - g2 - d3 - a2 - e2 - f2 - c3 - | d3 - a2 - g2 - d3 - e2 - b2 - e2 - g#2 -
    ,
        \\c5 - - e5 d5 - b4 - c5 - - a4 c5 - - - | d5 - f5 e5 d5 - b4 - b4 - c5 d5 e5 - - -
    ,
        \\e4 - c4 - d4 - b3 - c4 - a3 - c4 - a3 - | f3 - a3 - g3 - b3 - g#3 - b3 - e3 - g#3 -
    ,
        \\k - h h s - h - k - h h s - h - | k - h h s - h - k k h h s s s s
    ),
    // B2: the chorus coming home to A minor
    section(TIDE_BPM,
        \\c3 - g2 - g2 - d3 - a2 - e2 - f2 - c3 - | f2 - c3 - g2 - d3 - a2 - e2 - a2 - - -
    ,
        \\c5 - - e5 d5 - b4 - c5 - - a4 c5 - - - | a4 - c5 f5 e5 - d5 - c5 - b4 - a4 - - -
    ,
        \\e4 - c4 - d4 - b3 - c4 - a3 - c4 - a3 - | a3 - c4 - b3 - d4 - c4 - e4 - a3 - - -
    ,
        \\k - h h s - h - k - h h s - h - | k - h h s - h - k - h - s - k -
    ),
    // C: a half-time bridge in D minor
    section(TIDE_BPM,
        \\d2 - - - - - - - a2 - - - - - - - | d2 - - - - - - - e2 - - - - - - -
    ,
        \\f4 - - - a4 - - - e4 - - - c5 - - - | d5 - - - a4 - f4 - g#4 - - - b4 - - -
    ,
        \\d3 - f3 - a3 - f3 - a3 - c4 - e4 - c4 - | d3 - f3 - a3 - f3 - e3 - g#3 - b3 - g#3 -
    ,
        \\k - - - - - h - s - - - - - h - | k - - - - - h - s - - - h - h -
    ),
    // C2: the bridge building back toward E
    section(TIDE_BPM,
        \\f2 - - - - - - - c3 - - - - - - - | g2 - - - - - - - e2 - - - e2 - - -
    ,
        \\a4 - - - c5 - - - g4 - - - e5 - - - | d5 - - - b4 - g4 - b4 - - - - - - -
    ,
        \\f3 - a3 - c4 - a3 - c4 - e4 - g4 - e4 - | g3 - b3 - d4 - b3 - e3 - g#3 - b3 - e4 -
    ,
        \\k - - - - - h - s - - - - - h - | k - - - s - - - s - s - s s s s
    ),
    // D: a hornpipe run over A minor, E minor, F, and G
    section(TIDE_BPM,
        \\a2 - a2 - e2 - e2 - e2 - e2 - b2 - b2 - | f2 - f2 - c3 - c3 - g2 - g2 - d3 - b2 -
    ,
        \\a4 c5 e5 c5 a4 c5 e5 a5 g4 b4 e5 b4 g4 b4 e5 g5 | f4 a4 c5 a4 f4 a4 c5 f5 g4 b4 d5 b4 g4 b4 d5 g5
    ,
        \\a3 - - - c4 - - - g3 - - - b3 - - - | a3 - - - c4 - - - b3 - - - d4 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - h - s - s s
    ),
    // D2: the run landing on E
    section(TIDE_BPM,
        \\d3 - d3 - a2 - a2 - a2 - a2 - e2 - e2 - | f2 - f2 - c3 - c3 - e2 - e2 - e2 - e2 -
    ,
        \\d5 a4 f4 a4 d5 f5 a5 f5 e5 c5 a4 c5 e5 a5 e5 c5 | f5 c5 a4 c5 f5 a5 f5 c5 e5 b4 g#4 b4 e5 - - -
    ,
        \\d4 - - - f4 - - - c4 - - - e4 - - - | a3 - - - c4 - - - g#3 - - - b3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - s s s s
    ),
};

const TIDEWALK_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a/c a2 d/l d d2 c/d c2/d d+5 d2+5 a a2 b b2 b/d b2 c2/l a/d a2/lc
);

pub const tidewalk = Arranged{ .sections = &TIDEWALK_SECTIONS, .arrangement = &TIDEWALK_ARRANGEMENT };

// ---------------------------------------------------------------------------
// Vell's Fencing Yard: a driving duel in D minor, 144 bpm. Section A is the original cadence;
// B swings to F major, C holds a tense A pedal like two blades circling, and D is the riposte.
// One chorus pass drops a whole step, so it ends on C and steps up into D minor.
// ---------------------------------------------------------------------------

const YARD_BPM = 144;
const FENCING_YARD_SECTIONS = [_]audio.BgmPattern{
    // A: the cadence
    section(YARD_BPM,
        \\d2 d2 d2 d2 f2 f2 f2 f2 g2 g2 g2 g2 a2 a2 g2 f2 | d2 d2 d2 d2 f2 f2 f2 f2 g2 g2 a2 a2 d2 d2 - -
    ,
        \\d5 - f5 - a5 - g5 f5 e5 - f5 g5 a5 - - - | d6 - a5 - f5 - d5 - e5 f5 e5 c#5 d5 - - -
    ,
        \\d3 - f3 - f3 - a3 - g3 - bb3 - a3 - c#4 - | d3 - f3 - f3 - a3 - g3 - a3 - d3 - f3 -
    ,
        \\k h k h s h k h k h k h s h k s | k h k h s h k h k h k h s s k s
    ),
    // A2: the cadence ending on A
    section(YARD_BPM,
        \\d2 d2 d2 d2 f2 f2 f2 f2 g2 g2 g2 g2 a2 a2 g2 f2 | bb2 bb2 bb2 bb2 g2 g2 g2 g2 a2 a2 a2 a2 a2 a2 g2 e2
    ,
        \\d5 - f5 - a5 - g5 f5 e5 - f5 g5 a5 - - - | bb5 - a5 g5 f5 - d5 - c#5 - e5 - a4 - - -
    ,
        \\d3 - f3 - f3 - a3 - g3 - bb3 - a3 - c#4 - | bb3 - d4 - g3 - bb3 - a3 - c#4 - e4 - c#4 -
    ,
        \\k h k h s h k h k h k h s h k s | k h k h s h k h k h k h s s s s
    ),
    // B: a syncopated swing into F major
    section(YARD_BPM,
        \\f2 - f2 f2 - f2 c3 - d3 - d3 d3 - d3 bb2 - | g2 - g2 g2 - g2 c3 - f2 - f2 f2 a2 - a2 -
    ,
        \\a5 - - c6 - a5 g5 - f5 - - a5 - f5 d5 - | d5 - g5 - bb5 a5 g5 e5 f5 - - - e5 - c#5 -
    ,
        \\a3 - c4 - g3 - e3 - f3 - a3 - d4 - bb3 - | bb3 - d4 - g3 - e3 - a3 - c4 - c#4 - e4 -
    ,
        \\k - h k s - h k k - h k s - h k | k - h k s - h k k - h k s k s s
    ),
    // B2: the swing closing on D
    section(YARD_BPM,
        \\f2 - f2 f2 - f2 c3 - d3 - d3 d3 - d3 bb2 - | g2 - g2 g2 - a2 a2 - d2 - d2 d2 - d2 - -
    ,
        \\a5 - - c6 - a5 g5 - f5 - - a5 - f5 d5 - | bb5 - a5 g5 - e5 - c#5 d5 - - - - - - -
    ,
        \\a3 - c4 - g3 - e3 - f3 - a3 - d4 - bb3 - | bb3 - d4 - c#4 - e4 - d4 - f4 - a3 - - -
    ,
        \\k - h k s - h k k - h k s - h k | k - h k s - h k k - s - k - - -
    ),
    // C: circling over an A pedal
    section(YARD_BPM,
        \\a1 - a1 - a1 - a1 - a1 - a1 - a1 - a1 - | a1 - a1 - a1 - a1 - bb1 - bb1 - a1 - a1 -
    ,
        \\e5 - - - - - f5 - e5 - - - - - c#5 - | e5 - - - - - f5 - g5 - - - f5 - e5 -
    ,
        \\a3 - - - c#4 - - - e4 - - - c#4 - - - | a3 - - - c#4 - - - bb3 - - - a3 - - -
    ,
        \\k - - - - - - - k - - - s - - - | k - - - - - - - k - - - s - s s
    ),
    // C2: the pedal tightening into the attack
    section(YARD_BPM,
        \\a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 a1 | a2 a2 a2 a2 a2 a2 a2 a2 g2 g2 f2 f2 e2 e2 c#2 c#2
    ,
        \\e5 f5 e5 c#5 e5 f5 e5 c#5 e5 f5 g5 f5 e5 f5 g5 a5 | bb5 a5 g5 f5 e5 d5 c#5 d5 e5 f5 g5 a5 bb5 - a5 -
    ,
        \\a3 - c#4 - e4 - c#4 - a3 - c#4 - e4 - g4 - | a3 - c#4 - e4 - c#4 - g3 - bb3 - c#4 - e4 -
    ,
        \\k h h h s h h h k h h h s h s h | k s k s k s k s k s k s s s s s
    ),
    // D: the riposte, arpeggios over D minor, G minor, B flat, and A
    section(YARD_BPM,
        \\d2 - d3 - d2 - d3 - g2 - g2 - g2 - bb2 - | bb2 - bb2 - f2 - f2 - a2 - a2 - a1 - c#2 -
    ,
        \\a5 f5 d5 f5 a5 f5 d5 f5 bb5 g5 d5 g5 bb5 g5 d5 g5 | bb5 f5 d5 f5 a5 f5 c5 f5 a5 e5 c#5 e5 a5 e5 c#5 e5
    ,
        \\d4 - - - f4 - - - d4 - - - g4 - - - | d4 - - - c4 - - - c#4 - - - e4 - - -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k h s h k s s s
    ),
    // D2: the riposte landing on D
    section(YARD_BPM,
        \\d2 - d3 - d2 - d3 - c2 - c3 - c2 - c3 - | bb1 - bb2 - a1 - a2 - d2 - d2 - d2 - - -
    ,
        \\a5 f5 d5 f5 a5 f5 d5 f5 g5 e5 c5 e5 g5 e5 c5 e5 | f5 d5 bb4 d5 e5 c#5 a4 c#5 d5 - - - d6 - - -
    ,
        \\d4 - - - f4 - - - c4 - - - e4 - - - | bb3 - - - c#4 - - - d4 - f4 - a4 - - -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k - s - k - - -
    ),
};

const FENCING_YARD_ARRANGEMENT = order(
    \\c/l c2 a a2 b b2 a a2 d d2 c c2 b b2 a/c a2 d/l d d2 b-2 b2-2 a a2 c/d c2 d d2 b/b b2 a a2/l d d2 b b2 a a2 d2/lc
);

pub const fencing_yard = Arranged{ .sections = &FENCING_YARD_SECTIONS, .arrangement = &FENCING_YARD_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The Drowned Lantern: a rowdy tavern waltz in C major, 138 bpm, one bar per three steps
// (oom-pah-pah). Sections are eight bars (24 steps). B is the singalong chorus, C a minor-key
// lament, and D a step dance. One theme pass sits in F major, so it ends on the chorus's
// first chord.
// ---------------------------------------------------------------------------

const LANTERN_BPM = 138;
const LANTERN_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(LANTERN_BPM,
        \\c3 - - | c3 - - | g2 - - | c3 - - | f2 - - | g2 - - | c3 - - | c3 - -
    ,
        \\c5 - d5 | e5 - g5 | a5 - g5 | e5 - - | f5 - e5 | d5 - b4 | c5 - - | - - -
    ,
        \\- e4 e4 | - g4 g4 | - d4 d4 | - e4 e4 | - a4 a4 | - b3 b3 | - e4 e4 | - c4 c4
    ,
        \\k h h | k h h | k h h | k h h | k h h | k h h | k h h | k h s
    ),
    // A2: the theme through A minor and D minor
    section(LANTERN_BPM,
        \\c3 - - | c3 - - | a2 - - | a2 - - | d3 - - | g2 - - | c3 - - | c3 - -
    ,
        \\c5 - d5 | e5 - g5 | a5 - c6 | a5 - - | f5 - a5 | g5 - f5 | e5 - d5 | c5 - -
    ,
        \\- e4 e4 | - g4 g4 | - c4 c4 | - e4 e4 | - f4 f4 | - b3 b3 | - e4 e4 | - g4 g4
    ,
        \\k h h | k h h | k h h | k h h | k h h | k h h | k h h | k s s
    ),
    // B: the singalong chorus
    section(LANTERN_BPM,
        \\f2 - c3 | f2 - c3 | c3 - g2 | c3 - g2 | g2 - d3 | g2 - d3 | c3 - g2 | c3 - -
    ,
        \\a5 a5 a5 | c6 - a5 | g5 g5 g5 | e5 - - | d5 e5 f5 | g5 - b4 | c5 - e5 | g5 - -
    ,
        \\- a4 a4 | - c5 c5 | - g4 g4 | - e4 e4 | - b4 b4 | - d4 d4 | - e4 e4 | - c4 c4
    ,
        \\k h s | k h s | k h s | k h s | k h s | k h s | k h s | k s s
    ),
    // B2: the chorus again, closing the round
    section(LANTERN_BPM,
        \\f2 - c3 | f2 - c3 | c3 - g2 | a2 - e2 | d3 - a2 | g2 - d3 | c3 - - | c3 - -
    ,
        \\a5 a5 a5 | c6 - a5 | g5 g5 g5 | e5 - c5 | d5 f5 a5 | g5 - b4 | c5 - - | - - -
    ,
        \\- a4 a4 | - c5 c5 | - g4 g4 | - c4 c4 | - f4 f4 | - d4 d4 | - e4 e4 | - g4 g4
    ,
        \\k h s | k h s | k h s | k h s | k h s | k h s | k h h | k s k
    ),
    // C: a lament in A minor
    section(LANTERN_BPM,
        \\a2 - - | e2 - - | a2 - - | e2 - - | d3 - - | a2 - - | e2 - - | e2 - -
    ,
        \\e5 - - | d5 - b4 | c5 - - | b4 - g#4 | a4 - d5 | c5 - a4 | b4 - - | g#4 - -
    ,
        \\- c4 c4 | - b3 b3 | - c4 c4 | - g#3 g#3 | - f4 f4 | - e4 e4 | - d4 d4 | - b3 b3
    ,
        \\k - - | k - h | k - - | k - h | k - - | k - h | k - - | k h h
    ),
    // C2: the lament turning back to C on G
    section(LANTERN_BPM,
        \\f2 - - | g2 - - | a2 - - | a2 - e2 | f2 - - | g2 - - | g2 - d3 | g2 - b2
    ,
        \\a4 - c5 | b4 - d5 | c5 - e5 | a5 - - | a5 - c6 | b5 - g5 | f5 - d5 | b4 - -
    ,
        \\- c4 c4 | - d4 d4 | - e4 e4 | - c4 c4 | - a4 a4 | - b4 b4 | - g4 g4 | - f4 f4
    ,
        \\k - h | k - h | k - h | k - h | k h h | k h h | k s s | s s s
    ),
    // D: a step dance, the lead on every step
    section(LANTERN_BPM,
        \\c3 - g2 | g2 - d3 | c3 - g2 | g2 - d3 | f2 - c3 | c3 - g2 | g2 - d3 | c3 - -
    ,
        \\e5 g5 c6 | b5 g5 d5 | e5 g5 c6 | d6 b5 g5 | a5 f5 c5 | e5 g5 c6 | b5 g5 f5 | e5 c5 -
    ,
        \\- e4 - | - d4 - | - e4 - | - d4 - | - c4 - | - e4 - | - d4 - | - e4 -
    ,
        \\k h h | s h h | k h h | s h h | k h h | s h h | k h h | s s s
    ),
    // D2: the dance through A minor and E minor
    section(LANTERN_BPM,
        \\a2 - e2 | e2 - b2 | f2 - c3 | g2 - d3 | c3 - g2 | f2 - c3 | g2 - d3 | c3 - -
    ,
        \\c6 a5 e5 | b5 g5 e5 | a5 f5 c5 | b5 g5 d5 | c6 g5 e5 | a5 f5 c5 | d5 f5 b5 | c6 - -
    ,
        \\- c4 - | - b3 - | - a3 - | - b3 - | - e4 - | - a3 - | - b3 - | - c4 -
    ,
        \\k h h | s h h | k h h | s h h | k h h | s h h | k h s | k - -
    ),
};

const LANTERN_ARRANGEMENT = order(
    \\a/l a a2 a a2 b b2 c c2 a a2 d d2 b b2 a/c a2 c/d c2 d/l d d2 a+5 a2+5 b b2 c c2 d d2 a a2 b/b b2 c/l c2 a a2/d d d2 b b2 c c2/l a a2 d d2/lc
);

pub const lantern = Arranged{ .sections = &LANTERN_SECTIONS, .arrangement = &LANTERN_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The tavern: a jig in G dorian, 132 bpm. B brightens to B flat and F, C is a half-time lute
// break, D a fiddle reel. One chorus pass sits a fourth up and ends on C minor, the home
// key's fourth, before the break returns to G.
// ---------------------------------------------------------------------------

const TAVERN_BPM = 132;

const TAVERN_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(TAVERN_BPM,
        \\g2 - g2 - d2 - g2 - f2 - f2 - c2 - d2 - | g2 - g2 - d2 - g2 - f2 - f2 - d2 - g2 -
    ,
        \\g4 - bb4 c5 d5 - c5 bb4 a4 - f4 a4 g4 - - - | g4 a4 bb4 c5 d5 f5 d5 c5 bb4 a4 g4 f4 g4 - - -
    ,
        \\g3 - bb3 - g3 - bb3 - f3 - a3 - f3 - a3 - | g3 - bb3 - g3 - bb3 - f3 - a3 - g3 - bb3 -
    ,
        \\k h h h s h k h k h h h s h h h | k h h h s h k h k h h h s h k s
    ),
    // A2: the theme's answer, through C to D
    section(TAVERN_BPM,
        \\g2 - g2 - d2 - g2 - f2 - f2 - c2 - d2 - | c2 - c2 - g2 - c2 - d2 - d2 - a2 - d2 -
    ,
        \\g4 - bb4 c5 d5 - c5 bb4 a4 - f4 a4 g4 - - - | c5 - e5 g5 e5 - c5 - d5 - f5 e5 d5 - - -
    ,
        \\g3 - bb3 - g3 - bb3 - f3 - a3 - f3 - a3 - | c4 - e4 - c4 - g3 - d4 - f3 - a3 - d4 -
    ,
        \\k h h h s h k h k h h h s h h h | k h h h s h k h k h s h s s k s
    ),
    // B: the bright side, B flat, F, C, and G minor
    section(TAVERN_BPM,
        \\bb2 - f2 - bb2 - f2 - c3 - g2 - g2 - d3 - | bb2 - f2 - bb2 - f2 - c3 - g2 - d3 - a2 -
    ,
        \\d5 - d5 f5 d5 - c5 bb4 c5 - e5 - g5 - - - | f5 - d5 bb4 a4 - c5 - e5 - c5 g4 a4 - - -
    ,
        \\bb3 - d4 - a3 - c4 - g3 - c4 - g3 - bb3 - | bb3 - d4 - a3 - c4 - g3 - e4 - f#3 - a3 -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k h s h k s s s
    ),
    // B2: the bright side coming home
    section(TAVERN_BPM,
        \\bb2 - f2 - bb2 - f2 - c3 - g2 - g2 - d3 - | c3 - g2 - d3 - a2 - g2 - - - g2 - - -
    ,
        \\d5 - d5 f5 d5 - c5 bb4 c5 - e5 - g5 - - - | e5 - c5 g4 f#4 - a4 - g4 - - - - - - -
    ,
        \\bb3 - d4 - a3 - c4 - g3 - c4 - g3 - bb3 - | c4 - e4 - a3 - f#3 - g3 - bb3 - d4 - - -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k - s - k - - -
    ),
    // C: a half-time lute break
    section(TAVERN_BPM,
        \\g2 - - - - - - - c3 - - - - - - - | g2 - - - - - - - d3 - - - - - - -
    ,
        \\bb4 - - - a4 - g4 - e5 - - - d5 - c5 - | d5 - - - bb4 - g4 - f#4 - - - a4 - - -
    ,
        \\g3 - bb3 - d4 - bb3 - c4 - e4 - g4 - e4 - | g3 - bb3 - d4 - bb3 - f#3 - a3 - d4 - a3 -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - h h
    ),
    // C2: the break building back to D
    section(TAVERN_BPM,
        \\f2 - - - - - - - c3 - - - - - - - | bb2 - - - - - - - d3 - - - d3 - - -
    ,
        \\a4 - - - c5 - f5 - e5 - - - g5 - - - | f5 - d5 - bb4 - d5 - a4 - - - - - - -
    ,
        \\f3 - a3 - c4 - a3 - c4 - e4 - g4 - e4 - | bb3 - d4 - f4 - d4 - f#3 - a3 - d4 - f#4 -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - s - s - s s s s
    ),
    // D: a fiddle reel over G minor, F, C, and D
    section(TAVERN_BPM,
        \\g2 - d3 - g2 - d3 - f2 - c3 - f2 - c3 - | c3 - g2 - c3 - g2 - d3 - a2 - d3 - a2 -
    ,
        \\g4 bb4 d5 bb4 g4 bb4 d5 g5 f4 a4 c5 a4 f4 a4 c5 f5 | e5 c5 g4 c5 e5 g5 e5 c5 d5 a4 f#4 a4 d5 f#5 - -
    ,
        \\g3 - - - bb3 - - - a3 - - - c4 - - - | c4 - - - e4 - - - f#3 - - - a3 - - -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k h s h k s k s
    ),
    // D2: the reel landing on G minor
    section(TAVERN_BPM,
        \\g2 - d3 - g2 - d3 - c3 - g2 - c3 - g2 - | f2 - c3 - d3 - a2 - g2 - - - g2 - - -
    ,
        \\d5 bb4 g4 bb4 d5 g5 d5 bb4 c5 e5 g5 e5 c5 g4 e5 c5 | a4 c5 f5 c5 f#4 a4 d5 a4 g4 - - - g5 - - -
    ,
        \\bb3 - - - d4 - - - c4 - - - e4 - - - | a3 - - - f#3 - - - g3 - bb3 - d4 - - -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k - s - k - - -
    ),
};

const TAVERN_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a/c a2 c c2 d/l d d2 a a2 b+5 b2+5
    \\c/d c2 a a2 d d2 b b2 a/d a2/lc
);

pub const tavern = Arranged{ .sections = &TAVERN_SECTIONS, .arrangement = &TAVERN_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The cellar: a slow C minor walk with dripping echoes, 92 bpm. B climbs through A flat and
// E flat, C drips high over a C pedal with a flat second, D walks the bass down by steps. One
// B pass sits a whole step down and ends on B flat minor, a step below the pedal that follows.
// ---------------------------------------------------------------------------

const CELLAR_BPM = 92;

const CELLAR_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(CELLAR_BPM,
        \\c2 - - - eb2 - - - g2 - - - ab2 - g2 - | c2 - - - eb2 - - - f2 - - - g2 - - -
    ,
        \\c4 - eb4 - g4 - ab4 g4 eb4 - d4 - c4 - - - | c4 - eb4 - g4 - bb4 ab4 g4 - f4 - eb4 d4 c4 -
    ,
        \\c3 - - - eb3 - - - g3 - - - ab3 - g3 - | c3 - - - eb3 - - - f3 - - - g3 - - -
    ,
        \\k - - - - - - - h - - - - - - - | k - - - - - - - h - - - - - k -
    ),
    // A2: the theme ending on G
    section(CELLAR_BPM,
        \\c2 - - - eb2 - - - g2 - - - ab2 - g2 - | ab2 - - - f2 - - - g2 - - - g2 - - -
    ,
        \\c4 - eb4 - g4 - ab4 g4 eb4 - d4 - c4 - - - | c5 - - - ab4 - f4 - d4 - - - b3 - - -
    ,
        \\c3 - - - eb3 - - - g3 - - - ab3 - g3 - | ab3 - c4 - f3 - ab3 - g3 - b3 - d4 - b3 -
    ,
        \\k - - - - - - - h - - - - - - - | k - - - - - - - h - - - h - k -
    ),
    // B: climbing through A flat and E flat
    section(CELLAR_BPM,
        \\ab2 - - - - - - - eb2 - - - - - - - | f2 - - - - - - - g2 - - - - - - -
    ,
        \\eb5 - - - c5 - - - bb4 - - - g4 - - - | ab4 - c5 - f5 - eb5 - d5 - - - b4 - - -
    ,
        \\ab3 - c4 - eb4 - c4 - g3 - bb3 - eb4 - bb3 - | f3 - ab3 - c4 - ab3 - g3 - b3 - d4 - b3 -
    ,
        \\k - - - - - h - - - - - - - h - | k - - - - - h - - - - - h - - -
    ),
    // B2: the climb settling on C minor
    section(CELLAR_BPM,
        \\ab2 - - - - - - - eb2 - - - - - - - | f2 - - - g2 - - - c2 - - - - - - -
    ,
        \\eb5 - - - c5 - - - bb4 - - - g4 - eb4 - | f4 - ab4 - d4 - b3 - c4 - - - - - - -
    ,
        \\ab3 - c4 - eb4 - c4 - g3 - bb3 - eb4 - bb3 - | f3 - ab3 - g3 - b3 - c3 - eb3 - g3 - - -
    ,
        \\k - - - - - h - - - - - - - h - | k - - - - - h - k - - - - - - -
    ),
    // C: drips over a C pedal
    section(CELLAR_BPM,
        \\c2 - - - - - - - - - - - - - - - | c2 - - - - - - - - - - - db2 - - -
    ,
        \\g5 - - - - - - - eb5 - - - - - - - | g5 - - - - - ab5 - g5 - - - - - - -
    ,
        \\c3 - - - - - - - g3 - - - - - - - | c3 - - - - - - - db3 - - - - - - -
    ,
        \\k - - - - - - - - - - - h - - - | k - - - - - - - - - - - h - h -
    ),
    // C2: drips falling to G
    section(CELLAR_BPM,
        \\f2 - - - - - - - - - - - - - - - | g2 - - - - - - - - - - - g2 - - -
    ,
        \\ab5 - - - - - - - f5 - - - - - c5 - | d5 - - - - - b4 - - - g4 - - - - -
    ,
        \\f3 - - - - - - - ab3 - - - - - - - | g3 - - - - - - - b3 - - - d4 - - -
    ,
        \\k - - - - - - - - - - - h - - - | k - - - - - - - h - - - h - k -
    ),
    // D: the bass walks down by steps
    section(CELLAR_BPM,
        \\c2 - c3 - c2 - c3 - bb1 - bb2 - bb1 - bb2 - | ab1 - ab2 - ab1 - ab2 - g1 - g2 - g1 - b1 -
    ,
        \\g4 - - - - - eb4 f4 g4 - - - - - f4 eb4 | f4 - - - - - eb4 d4 d4 - - - - - - -
    ,
        \\c3 - eb3 - g3 - eb3 - bb2 - d3 - f3 - d3 - | ab2 - c3 - eb3 - c3 - g2 - b2 - d3 - b2 -
    ,
        \\k - h - - - h - k - h - - - h - | k - h - - - h - k - h - h - h h
    ),
    // D2: the walk closing on C minor
    section(CELLAR_BPM,
        \\c2 - c3 - c2 - c3 - bb1 - bb2 - bb1 - bb2 - | ab1 - ab2 - g1 - g2 - c2 - - - c2 - - -
    ,
        \\c5 - - - - - bb4 ab4 g4 - - - - - f4 g4 | ab4 - - - g4 - f4 - eb4 - - - c4 - - -
    ,
        \\c3 - eb3 - g3 - eb3 - bb2 - d3 - f3 - d3 - | ab2 - c3 - g2 - b2 - c3 - eb3 - g3 - - -
    ,
        \\k - h - - - h - k - h - - - h - | k - h - - - h - k - - - - - - -
    ),
};

const CELLAR_ARRANGEMENT = order(
    \\a/ld a/l a a2 c/d c2 b b2 a a2 d/l d d2 c c2 b b2 a/c a2 d d2 b-2 b2-2 c/l c2
    \\a a2/d
);

pub const cellar = Arranged{ .sections = &CELLAR_SECTIONS, .arrangement = &CELLAR_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The spitting contest: a jaunty march in C major, 126 bpm. B is the trio in F, as marches
// have; C stalks in A minor without hats; D is a fanfare. One theme pass sits a whole step up
// and ends on A, and the trio that follows starts on F.
// ---------------------------------------------------------------------------

const SPIT_BPM = 126;

const SPITTING_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(SPIT_BPM,
        \\c3 - g2 - c3 - g2 - f2 - c3 - g2 - d3 - | c3 - g2 - c3 - g2 - f2 - g2 - c3 - - -
    ,
        \\e5 - g5 - e5 d5 c5 - d5 - e5 f5 g5 - - - | a5 - g5 e5 c5 - d5 - e5 d5 c5 - c5 - - -
    ,
        \\- c4 - c4 - c4 - c4 - a3 - a3 - g3 - g3 | - c4 - c4 - c4 - c4 - a3 - g3 - c4 - -
    ,
        \\k h h h s h k h k h h h s s h h | k h h h s h k h k h h h s h k s
    ),
    // A2: the theme turning to G
    section(SPIT_BPM,
        \\c3 - g2 - c3 - g2 - f2 - c3 - g2 - d3 - | a2 - e2 - d3 - a2 - g2 - d3 - g2 - - -
    ,
        \\e5 - g5 - e5 d5 c5 - d5 - e5 f5 g5 - - - | a5 - c6 a5 f5 - a5 - g5 - f5 e5 d5 - - -
    ,
        \\- c4 - c4 - c4 - c4 - a3 - a3 - g3 - g3 | - e4 - c4 - f4 - a3 - d4 - b3 - g3 - -
    ,
        \\k h h h s h k h k h h h s s h h | k h h h s h k h k h s h s s s s
    ),
    // B: the trio in F
    section(SPIT_BPM,
        \\f2 - c3 - f2 - c3 - c3 - g2 - c3 - g2 - | f2 - c3 - bb2 - f2 - c3 - g2 - c3 - e2 -
    ,
        \\a4 - c5 - f5 - - - e5 - d5 - c5 - bb4 - | a4 - c5 f5 d5 - - - c5 - bb4 - g4 - - -
    ,
        \\- a3 - c4 - a3 - c4 - g3 - bb3 - g3 - bb3 | - a3 - c4 - d4 - bb3 - g3 - e4 - g3 - bb3
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k h s h k s s s
    ),
    // B2: the trio back toward C
    section(SPIT_BPM,
        \\f2 - c3 - f2 - c3 - c3 - g2 - c3 - g2 - | f2 - c3 - d3 - a2 - g2 - d3 - g2 - b2 -
    ,
        \\a4 - c5 - f5 - - - e5 - d5 - c5 - bb4 - | a4 - c5 f5 a5 - f5 - g5 - f5 - d5 - b4 -
    ,
        \\- a3 - c4 - a3 - c4 - g3 - bb3 - g3 - bb3 | - a3 - c4 - d4 - f4 - b3 - d4 - f4 - d4
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k s k s s s s s
    ),
    // C: stalking in A minor
    section(SPIT_BPM,
        \\a2 - - - e2 - - - a2 - - - e2 - - - | f2 - - - c3 - - - e2 - - - e2 - g#2 -
    ,
        \\c5 - - b4 a4 - - - e5 - - d5 c5 - - - | a4 - - c5 f5 - - e5 e5 - - - g#4 - b4 -
    ,
        \\- a3 - - - e3 - - - a3 - - - g#3 - - | - a3 - - - c4 - - - b3 - - - g#3 - -
    ,
        \\k - - - s - - - k - - - s - - - | k - - - s - - - k - - - s - s s
    ),
    // C2: the stalk turning to G
    section(SPIT_BPM,
        \\a2 - - - e2 - - - d3 - - - a2 - - - | f2 - - - g2 - - - g2 - - - g2 - d3 -
    ,
        \\c5 - - b4 a4 - - - f5 - - e5 d5 - - - | c5 - - a4 f4 - - - g4 - b4 - d5 - - -
    ,
        \\- a3 - - - e3 - - - d4 - - - a3 - - | - a3 - - - b3 - - - d4 - - - f4 - -
    ,
        \\k - - - s - - - k - - - s - - - | k - - - s - - - k - s - s s s s
    ),
    // D: a fanfare
    section(SPIT_BPM,
        \\c3 - - - c3 - - - f2 - - - f2 - - - | g2 - - - g2 - - - c3 - g2 - c3 - - -
    ,
        \\c5 c5 c5 - g4 - c5 - f5 f5 f5 - c5 - f5 - | g5 g5 g5 - d5 - g5 - c6 - g5 - e5 - c5 -
    ,
        \\- e4 - g4 - e4 - g4 - f4 - a4 - f4 - a4 | - d4 - g4 - b3 - d4 - e4 - g4 - c4 - -
    ,
        \\k - k - s - k - k - k - s - k - | k - k - s - k - k s k s s s s s
    ),
    // D2: the fanfare's answer
    section(SPIT_BPM,
        \\a2 - - - a2 - - - f2 - - - f2 - - - | g2 - - - g2 - - - c3 - - - c3 - - -
    ,
        \\e5 e5 e5 - c5 - e5 - a5 a5 a5 - f5 - a5 - | g5 - f5 - e5 - d5 - c5 - - - c6 - - -
    ,
        \\- c4 - e4 - c4 - e4 - a3 - c4 - a3 - c4 | - b3 - d4 - b3 - f4 - e4 - g4 - c4 - -
    ,
        \\k - k - s - k - k - k - s - k - | k - k - s - k - k - s - k - - -
    ),
};

const SPITTING_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 d d2 c/d c2 a a2 b b2 d/l d d2 c c2 a+2 a2+2 b b2
    \\a/c a2 d d2 c/l c2 a a2/lc
);

pub const spitting_contest = Arranged{ .sections = &SPITTING_SECTIONS, .arrangement = &SPITTING_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The inn and its net loft yard: a gentle stroll in F major, 104 bpm. B wanders through B flat and
// A minor, C is a fountain of high arpeggios over held bass, D strolls with a walking bass.
// One B pass sits a whole step up and ends on G, a step above the theme's F.
// ---------------------------------------------------------------------------

const COURT_BPM = 104;

const COURTYARD_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(COURT_BPM,
        \\f2 - c3 - f2 - c3 - bb2 - f2 - c3 - g2 - | f2 - c3 - f2 - c3 - bb2 - c3 - f2 - - -
    ,
        \\a4 - c5 - f5 - e5 d5 c5 - bb4 - a4 - g4 - | a4 - c5 - f5 - g5 f5 e5 - d5 - c5 - - -
    ,
        \\f3 - a3 - f3 - a3 - bb3 - f3 - a3 - g3 - | f3 - a3 - f3 - a3 - bb3 - a3 - f3 - - -
    ,
        \\k - h - - - h - k - h - - - h - | k - h - - - h - k - h - - - k -
    ),
    // A2: the theme turning to C
    section(COURT_BPM,
        \\f2 - c3 - f2 - c3 - bb2 - f2 - c3 - g2 - | d3 - a2 - g2 - d3 - c3 - g2 - c3 - - -
    ,
        \\a4 - c5 - f5 - e5 d5 c5 - bb4 - a4 - g4 - | a4 - d5 - f5 - d5 - e5 - c5 - g4 - - -
    ,
        \\f3 - a3 - f3 - a3 - bb3 - f3 - a3 - g3 - | d4 - f4 - b3 - d4 - c4 - e4 - g3 - - -
    ,
        \\k - h - - - h - k - h - - - h - | k - h - - - h - k - h - h - k -
    ),
    // B: wandering through B flat, C, A minor, and D minor
    section(COURT_BPM,
        \\bb2 - f2 - bb2 - f2 - c3 - g2 - c3 - g2 - | a2 - e2 - a2 - e2 - d3 - a2 - d3 - a2 -
    ,
        \\d5 - - - f5 - d5 - e5 - - - g5 - e5 - | c5 - - - e5 - a5 - f5 - - - d5 - - -
    ,
        \\bb3 - d4 - f4 - d4 - c4 - e4 - g4 - e4 - | a3 - c4 - e4 - c4 - d4 - f4 - a4 - f4 -
    ,
        \\k - h - - - h - k - h - - - h - | k - h - - - h - k - h - - - h -
    ),
    // B2: the wander coming back to F
    section(COURT_BPM,
        \\bb2 - f2 - bb2 - f2 - c3 - g2 - c3 - e2 - | f2 - c3 - a2 - c3 - f2 - - - f2 - - -
    ,
        \\d5 - - - f5 - d5 - e5 - - - g5 - bb5 - | a5 - - - f5 - c5 - a4 - - - - - - -
    ,
        \\bb3 - d4 - f4 - d4 - c4 - e4 - g4 - bb3 - | a3 - c4 - f4 - c4 - a3 - - - f3 - - -
    ,
        \\k - h - - - h - k - h - - - h - | k - h - - - h - k - - - k - - -
    ),
    // C: a fountain of high arpeggios
    section(COURT_BPM,
        \\f2 - - - - - - - bb2 - - - - - - - | f2 - - - - - - - c3 - - - - - - -
    ,
        \\c6 a5 f5 a5 c6 a5 f5 a5 d6 bb5 f5 bb5 d6 bb5 f5 bb5 | c6 a5 f5 a5 c6 a5 f5 a5 c6 g5 e5 g5 bb5 g5 e5 g5
    ,
        \\f3 - - - - - - - bb3 - - - - - - - | a3 - - - - - - - g3 - - - - - - -
    ,
        \\k - - - - - - - - - - - - - - - | k - - - - - - - - - - - h - - -
    ),
    // C2: the fountain in D minor's shade
    section(COURT_BPM,
        \\d3 - - - - - - - g2 - - - - - - - | bb2 - - - - - - - c3 - - - - - - -
    ,
        \\a5 f5 d5 f5 a5 f5 d5 f5 bb5 g5 d5 g5 bb5 g5 d5 g5 | bb5 f5 d5 f5 bb5 f5 d5 f5 c6 g5 e5 g5 bb5 g5 e5 c5
    ,
        \\d4 - - - - - - - g3 - - - - - - - | bb3 - - - - - - - c4 - - - - - - -
    ,
        \\k - - - - - - - - - - - - - - - | k - - - - - - - h - - - h - h -
    ),
    // D: a stroll with a walking bass
    section(COURT_BPM,
        \\f2 - g2 - a2 - c3 - bb2 - a2 - g2 - c3 - | f2 - g2 - a2 - bb2 - c3 - d3 - c3 - e2 -
    ,
        \\c5 - - a4 c5 - f5 - d5 - - c5 bb4 - g4 - | a4 - - c5 f5 - a5 - g5 - - e5 c5 - bb4 -
    ,
        \\f3 - a3 - c4 - a3 - bb3 - d4 - g3 - bb3 - | f3 - a3 - c4 - a3 - c4 - e4 - g3 - bb3 -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - h - s - h h
    ),
    // D2: the stroll ending on F
    section(COURT_BPM,
        \\d3 - c3 - bb2 - a2 - g2 - a2 - bb2 - b2 - | c3 - - - c3 - - - f2 - - - f2 - - -
    ,
        \\f5 - - d5 a4 - d5 - d5 - - bb4 g4 - bb4 - | c5 - e5 - g5 - e5 - f5 - - - - - - -
    ,
        \\d4 - f4 - a4 - f4 - g3 - bb3 - d4 - bb3 - | c4 - e4 - g4 - e4 - f3 - a3 - c4 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - - - k - - -
    ),
};

const COURTYARD_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 c/d c2/d a a2 d d2 b b2 a/c a2 c c2 d/l d d2 b+2 b2+2 a a2
    \\c/l c2 a a2/lc
);

pub const net_loft = Arranged{ .sections = &COURTYARD_SECTIONS, .arrangement = &COURTYARD_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The harbour office: a breezy cadence in G minor, 118 bpm. B swings into B flat, C is a
// musette with neighbour-note trills, D bounces like a ship's bell. One B pass sits a fourth
// up and ends on C minor, the home key's fourth.
// ---------------------------------------------------------------------------

const BIKE_BPM = 118;

const BIKE_SHOP_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(BIKE_BPM,
        \\g2 - d3 - g2 - d3 - f2 - c3 - g2 - d3 - | g2 - d3 - g2 - d3 - f2 - a2 - g2 - - -
    ,
        \\g4 bb4 d5 c#5 d5 - bb4 - g4 a4 bb4 c5 a4 - - - | g4 bb4 d5 c#5 d5 f5 d5 bb4 a4 bb4 a4 f#4 g4 - - -
    ,
        \\- g3 - bb3 - g3 - bb3 - f3 - a3 - g3 - bb3 | - g3 - bb3 - g3 - bb3 - f3 - f#3 - g3 - -
    ,
        \\k h h h s h k h k h h h s h h h | k h h h s h k h k h h h s h k s
    ),
    // A2: the theme through E flat to D
    section(BIKE_BPM,
        \\g2 - d3 - g2 - d3 - f2 - c3 - g2 - d3 - | eb2 - bb2 - c3 - g2 - d3 - a2 - d3 - - -
    ,
        \\g4 bb4 d5 c#5 d5 - bb4 - g4 a4 bb4 c5 a4 - - - | g4 bb4 eb5 d5 c5 - eb5 - d5 - c5 bb4 a4 - - -
    ,
        \\- g3 - bb3 - g3 - bb3 - f3 - a3 - g3 - bb3 | - g3 - bb3 - c4 - eb4 - f#3 - a3 - d4 - -
    ,
        \\k h h h s h k h k h h h s h h h | k h h h s h k h k h s h s s k s
    ),
    // B: a swing into B flat
    section(BIKE_BPM,
        \\bb2 - f2 - bb2 - f2 - g2 - d3 - g2 - d3 - | c3 - g2 - c3 - g2 - f2 - c3 - f2 - a2 -
    ,
        \\f5 - d5 - bb4 - d5 f5 g5 - - - d5 - bb4 - | eb5 - c5 - g4 - c5 eb5 f5 - - - c5 - a4 -
    ,
        \\- bb3 - d4 - bb3 - d4 - g3 - bb3 - g3 - bb3 | - c4 - eb4 - c4 - eb4 - a3 - c4 - a3 - c4
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k h s h k s k s
    ),
    // B2: the swing back to G minor
    section(BIKE_BPM,
        \\bb2 - f2 - bb2 - f2 - g2 - d3 - g2 - d3 - | eb2 - bb2 - d3 - a2 - g2 - - - g2 - - -
    ,
        \\f5 - d5 - bb4 - d5 f5 g5 - - - d5 - bb4 - | c5 - eb5 - f#5 - d5 a4 g4 - - - - - - -
    ,
        \\- bb3 - d4 - bb3 - d4 - g3 - bb3 - g3 - bb3 | - g3 - eb4 - f#3 - a3 - g3 - bb3 - d4 - bb3
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k - s - k - - -
    ),
    // C: a musette with neighbour-note trills
    section(BIKE_BPM,
        \\g2 - - - d3 - - - c3 - - - g2 - - - | eb2 - - - bb2 - - - d3 - - - a2 - - -
    ,
        \\d5 eb5 d5 - - - bb4 - c5 d5 c5 - - - g4 - | bb4 c5 bb4 - - - g4 - a4 bb4 a4 - f#4 - - -
    ,
        \\g3 - bb3 - d4 - bb3 - c4 - eb4 - g4 - eb4 - | bb3 - g3 - eb4 - g3 - a3 - f#3 - d4 - f#3 -
    ,
        \\k - h - - - h - k - h - - - h - | k - h - - - h - k - h - h - h h
    ),
    // C2: the musette through F and B flat to D
    section(BIKE_BPM,
        \\g2 - - - d3 - - - f2 - - - c3 - - - | bb2 - - - f2 - - - d3 - - - d3 - - -
    ,
        \\d5 eb5 d5 - - - bb4 - c5 d5 c5 - - - a4 - | d5 f5 d5 - - - bb4 - a4 - c5 - f#4 - - -
    ,
        \\g3 - bb3 - d4 - bb3 - f3 - a3 - c4 - a3 - | bb3 - d4 - f4 - d4 - a3 - c4 - f#3 - a3 -
    ,
        \\k - h - - - h - k - h - - - h - | k - h - s - h - s - s - s s s s
    ),
    // D: a ship's-bell bounce
    section(BIKE_BPM,
        \\g2 - - g2 d3 - - d3 c3 - - c3 g2 - - g2 | d3 - - d3 a2 - - a2 g2 - d3 - g2 - - -
    ,
        \\g5 - d5 - bb4 - d5 - g5 - eb5 - c5 - eb5 - | f#5 - d5 - a4 - c5 - bb4 - d5 - g5 - - -
    ,
        \\- bb3 - d4 - bb3 - d4 - c4 - eb4 - c4 - eb4 | - a3 - c4 - f#3 - a3 - g3 - bb3 - d4 - -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k h s - k - - -
    ),
    // D2: the bounce through F, B flat, and E flat to D
    section(BIKE_BPM,
        \\f2 - - f2 c3 - - c3 bb2 - - bb2 f2 - - f2 | eb2 - - eb2 bb2 - - bb2 d3 - - d3 a2 - - -
    ,
        \\f5 - c5 - a4 - c5 - f5 - d5 - bb4 - d5 - | eb5 - bb4 - g4 - bb4 - a4 - c5 - f#4 - - -
    ,
        \\- a3 - c4 - a3 - c4 - bb3 - d4 - bb3 - d4 | - g3 - bb3 - g3 - eb4 - f#3 - a3 - d4 - -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k s k s s s s s
    ),
};

const BIKE_SHOP_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 a a2 b b2 c c2/d d/l d d2 b+5 b2+5 a/c a2
    \\c/l c2 d d2 a a2/lc
);

pub const harbour_office = Arranged{ .sections = &BIKE_SHOP_SECTIONS, .arrangement = &BIKE_SHOP_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The castle and crypt: a whistle jig in G mixolydian, 126 bpm, six steps to a bar of 6/8, so
// sections are four bars (24 steps). B climbs to E minor, C is the crypt (slow, a drone, a
// leading tone), D is a running reel. One B pass sits a whole step up and ends on A, a step
// above the theme's G.
// ---------------------------------------------------------------------------

const JIG_BPM = 126;

const CASTLE_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(JIG_BPM,
        \\g2 - d3 | g2 - d3 | f2 - c3 | g2 - d3 | g2 - d3 | g2 - d3 | f2 - c3 | g2 - -
    ,
        \\b4 d5 e5 | g5 e5 d5 | c5 a4 f4 | b4 d5 g5 | b4 d5 e5 | g5 a5 g5 | f5 e5 c5 | d5 b4 -
    ,
        \\- g3 b3 | - g3 b3 | - f3 a3 | - g3 b3 | - g3 b3 | - g3 b3 | - f3 a3 | - g3 b3
    ,
        \\k h h | s h h | k h h | s h h | k h h | s h h | k h h | s s h
    ),
    // A2: the theme through C to D
    section(JIG_BPM,
        \\g2 - d3 | g2 - d3 | f2 - c3 | g2 - d3 | c3 - g2 | c3 - g2 | d3 - a2 | d3 - -
    ,
        \\b4 d5 e5 | g5 e5 d5 | c5 a4 f4 | b4 d5 g5 | e5 g5 e5 | c5 e5 g5 | f#5 e5 d5 | a4 - -
    ,
        \\- g3 b3 | - g3 b3 | - f3 a3 | - g3 b3 | - c4 e4 | - c4 e4 | - f#3 a3 | - d4 f#4
    ,
        \\k h h | s h h | k h h | s h h | k h h | s h h | k h s | s s s
    ),
    // B: the high part in E minor
    section(JIG_BPM,
        \\e2 - b2 | e2 - b2 | d3 - a2 | d3 - a2 | c3 - g2 | c3 - g2 | d3 - a2 | d3 - -
    ,
        \\e5 f#5 g5 | b5 g5 e5 | d5 e5 f#5 | a5 f#5 d5 | e5 g5 c6 | g5 e5 c5 | d5 e5 f#5 | d5 - -
    ,
        \\- e3 g3 | - e3 b3 | - d4 f#4 | - d4 a3 | - c4 e4 | - c4 g3 | - d4 f#4 | - d4 a3
    ,
        \\k h h | s h h | k h h | s h h | k h h | s h h | k h h | s h s
    ),
    // B2: the high part coming home to G
    section(JIG_BPM,
        \\e2 - b2 | e2 - b2 | d3 - a2 | d3 - a2 | c3 - g2 | d3 - a2 | g2 - d3 | g2 - -
    ,
        \\e5 f#5 g5 | b5 g5 e5 | d5 e5 f#5 | a5 f#5 d5 | e5 g5 c6 | a5 f#5 d5 | b4 d5 g5 | g4 - -
    ,
        \\- e3 g3 | - e3 b3 | - d4 f#4 | - d4 a3 | - c4 e4 | - d4 f#4 | - g3 b3 | - g3 d4
    ,
        \\k h h | s h h | k h h | s h h | k h h | s h h | k h s | k - -
    ),
    // C: the crypt, slow over a drone
    section(JIG_BPM,
        \\e2 - - | - - - | e2 - - | - - - | c3 - - | - - - | b2 - - | - - -
    ,
        \\b4 - - | a4 - g4 | f#4 - - | e4 - - | g4 - - | e4 - c5 | b4 - - | - - -
    ,
        \\- e3 - | - b3 - | - e3 - | - g3 - | - c4 - | - e4 - | - b3 - | - d#4 -
    ,
        \\k - - | - - - | k - - | - - h | k - - | - - - | k - - | h - h
    ),
    // C2: the crypt climbing out to D
    section(JIG_BPM,
        \\a2 - - | - - - | e2 - - | - - - | c3 - - | - - - | d3 - - | d3 - -
    ,
        \\c5 - - | b4 - a4 | b4 - - | g4 - - | e5 - - | d5 - c5 | a4 - - | f#4 - -
    ,
        \\- a3 - | - c4 - | - e3 - | - g3 - | - c4 - | - e4 - | - d4 - | - f#4 -
    ,
        \\k - - | - - - | k - - | - - h | k - - | s - - | k - s | s s s
    ),
    // D: a running reel over G, C, and D
    section(JIG_BPM,
        \\g2 - d3 | g2 - d3 | c3 - g2 | c3 - g2 | d3 - a2 | d3 - a2 | g2 - d3 | g2 - -
    ,
        \\g5 f#5 g5 | d5 b4 d5 | e5 d5 e5 | c5 g4 c5 | f#5 e5 f#5 | d5 a4 d5 | b5 a5 g5 | d5 b4 g4
    ,
        \\- b3 - | - d4 - | - c4 - | - e4 - | - a3 - | - f#4 - | - b3 - | - g3 -
    ,
        \\k h h | s h h | k h h | s h h | k h h | s h h | k h h | s s s
    ),
    // D2: the reel through F, the mixolydian seventh, to D
    section(JIG_BPM,
        \\g2 - d3 | g2 - d3 | f2 - c3 | f2 - c3 | c3 - g2 | c3 - g2 | d3 - a2 | d3 - -
    ,
        \\g5 a5 g5 | d5 b4 d5 | f5 g5 f5 | c5 a4 c5 | e5 f5 e5 | c5 g4 c5 | d5 e5 f#5 | a5 - -
    ,
        \\- b3 - | - d4 - | - a3 - | - c4 - | - e4 - | - g4 - | - f#4 - | - a4 -
    ,
        \\k h h | s h h | k h h | s h h | k h h | s h h | k h s | s s s
    ),
};

const CASTLE_ARRANGEMENT = order(
    \\a/ld a/l a a2 a a2 b b2 a a2 d d2 c/d c2 a a2 b b2 d/l d d2 a/c a2 c c2 b+2 b2+2
    \\a a2 d d2 b b2 c/l c2 a a2/d d d2 b b2 c c2 a a2/lc
);

pub const wreckers_cellar = Arranged{ .sections = &CASTLE_SECTIONS, .arrangement = &CASTLE_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The three eras: a bouncy cartoon march in C minor, 132 bpm. B is a goofy turn to E flat
// major, C tiptoes chromatically, D is a chase over a falling bass. One tiptoe pass sits a
// fourth up and ends on C, which the chase then turns minor.
// ---------------------------------------------------------------------------

const MARCH_BPM = 132;

const ERAS_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(MARCH_BPM,
        \\c2 - c3 - eb2 - eb3 - f2 - f3 - g2 - g3 - | c2 - c3 - eb2 - eb3 - ab2 - ab3 - g2 - f2 -
    ,
        \\c4 eb4 g4 c5 bb4 g4 eb4 c4 f4 ab4 c5 eb5 c5 - - - | c4 eb4 g4 c5 eb5 d5 c5 bb4 c5 bb4 g4 eb4 c4 - - -
    ,
        \\- c3 eb3 - c3 eb3 - eb3 g3 - f3 ab3 - g3 bb3 - | - c3 eb3 - c3 eb3 - ab3 c4 - g3 bb3 - f3 ab3 -
    ,
        \\k h s h k h s h k h s h k k s s | k h s h k h s h k h s h k s h k
    ),
    // A2: the theme turning to G
    section(MARCH_BPM,
        \\c2 - c3 - eb2 - eb3 - f2 - f3 - g2 - g3 - | ab2 - ab3 - f2 - f3 - g2 - g3 - g2 - b2 -
    ,
        \\c4 eb4 g4 c5 bb4 g4 eb4 c4 f4 ab4 c5 eb5 c5 - - - | ab4 c5 eb5 ab5 f5 - c5 ab4 g4 b4 d5 f5 g5 - - -
    ,
        \\- c3 eb3 - c3 eb3 - eb3 g3 - f3 ab3 - g3 bb3 - | - ab3 c4 - f3 ab3 - g3 b3 - g3 b3 - d4 f4 -
    ,
        \\k h s h k h s h k h s h k k s s | k h s h k h s h k s k s s s s s
    ),
    // B: a goofy turn to E flat major
    section(MARCH_BPM,
        \\eb2 - bb2 - eb2 - bb2 - bb1 - f2 - bb1 - f2 - | ab1 - eb2 - ab1 - eb2 - bb1 - f2 - bb1 - d2 -
    ,
        \\g4 - bb4 - eb5 - - g5 f5 - d5 - bb4 - - - | c5 - eb5 - ab5 - g5 f5 f5 - - d5 bb4 - - -
    ,
        \\- g3 bb3 - g3 bb3 - f3 bb3 - f3 d4 - f3 bb3 - | - ab3 c4 - ab3 eb4 - f3 bb3 - f3 d4 - d3 f3 -
    ,
        \\k - s - k k s - k - s - k k s - | k - s - k k s - k - s - k s s s
    ),
    // B2: the turn falling back to C minor
    section(MARCH_BPM,
        \\eb2 - bb2 - eb2 - bb2 - bb1 - f2 - bb1 - f2 - | ab1 - eb2 - g1 - d2 - c2 - g2 - c2 - - -
    ,
        \\g4 - bb4 - eb5 - - g5 f5 - d5 - bb4 - - - | ab4 - c5 - b4 - d5 - c5 - - - c4 - - -
    ,
        \\- g3 bb3 - g3 bb3 - f3 bb3 - f3 d4 - f3 bb3 - | - ab3 c4 - g3 b3 - g3 d4 - c3 eb3 - c3 g3 -
    ,
        \\k - s - k k s - k - s - k k s - | k - s - k k s - k - s - k - - -
    ),
    // C: a chromatic tiptoe
    section(MARCH_BPM,
        \\c2 - - - g2 - - - c2 - - - g2 - - - | ab1 - - - eb2 - - - g1 - - - g2 - - -
    ,
        \\g4 - ab4 - g4 - - - f#4 - g4 - - - - - | ab4 - g4 - f4 - eb4 - d4 - - - b3 - - -
    ,
        \\- - c3 - - - eb3 - - - c3 - - - g3 - | - - ab3 - - - c4 - - - g3 - - - b3 -
    ,
        \\k - - - s - - - k - - - s - - - | k - - - s - - - k - - - s - h h
    ),
    // C2: the tiptoe springing up to G
    section(MARCH_BPM,
        \\c2 - - - g2 - - - f2 - - - c3 - - - | ab1 - - - eb2 - - - g1 - - - b1 - - -
    ,
        \\g4 - ab4 - g4 - - - c5 - eb5 - - - - - | f5 - eb5 - d5 - c5 - b4 - d5 - g5 - - -
    ,
        \\- - c3 - - - eb3 - - - f3 - - - ab3 - | - - ab3 - - - c4 - - - g3 - - - d4 -
    ,
        \\k - - - s - - - k - - - s - - - | k - - - s - - - k - k - s s s s
    ),
    // D: a chase over a falling bass
    section(MARCH_BPM,
        \\c2 c3 c2 c3 bb1 bb2 bb1 bb2 ab1 ab2 ab1 ab2 g1 g2 g1 g2 | c2 c3 c2 c3 bb1 bb2 bb1 bb2 ab1 ab2 g1 g2 c2 - - -
    ,
        \\c5 g4 eb4 g4 bb4 f4 d4 f4 ab4 eb4 c4 eb4 g4 d4 b3 d4 | c5 g4 eb4 g4 bb4 f4 d4 f4 c5 ab4 b4 d5 c5 - - -
    ,
        \\- eb4 - - - d4 - - - c4 - - - b3 - - | - eb4 - - - d4 - - - c4 - b3 - c4 - -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h k s k s k - - -
    ),
    // D2: the chase through E flat to G
    section(MARCH_BPM,
        \\eb2 eb3 eb2 eb3 bb1 bb2 bb1 bb2 c2 c3 c2 c3 g1 g2 g1 g2 | ab1 ab2 ab1 ab2 f2 f3 f2 f3 g1 g2 g1 g2 g2 - - -
    ,
        \\eb5 bb4 g4 bb4 d5 bb4 f4 bb4 c5 g4 eb4 g4 b4 g4 d4 g4 | c5 ab4 eb4 ab4 c5 ab4 f4 ab4 b4 g4 d4 g4 b4 d5 f5 g5
    ,
        \\- g4 - - - f4 - - - eb4 - - - d4 - - | - eb4 - - - f4 - - - d4 - - - b3 - -
    ,
        \\k h s h k h s h k h s h k h s h | k h s h k h s h s s s s s s s s
    ),
};

const ERAS_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 a a2 b b2 c c2 d/l d d2 a/c a2 c+5 c2+5
    \\d d2 c/l c2 a a2 b b2 a/d a2/lc
);

pub const three_tides = Arranged{ .sections = &ERAS_SECTIONS, .arrangement = &ERAS_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The bell tower: a slow modal hymn in D dorian, 72 bpm. The theme quotes the Kindle and Toll
// drafts; B rings the Toll an octave up, C tolls over open fifths, D is a procession with a
// walking bass.
// ---------------------------------------------------------------------------

const HYMN_BPM = 72;

const BELL_TOWER_SECTIONS = [_]audio.BgmPattern{
    // A: the theme
    section(HYMN_BPM,
        \\d2 - - - - - - - c2 - - - - - - - | f2 - - - - - - - g2 - - - d2 - - -
    ,
        \\c5 - d5 - e5 - c5 - - - - - a4 - - - | g4 - a4 - b4 - g4 - - - - - d4 - - -
    ,
        \\d3 - - - a3 - - - c3 - - - g3 - - - | f3 - - - a3 - - - g3 - - - d3 - - -
    ,
        \\k - - - - - - - - - - - - - - - | k - - - - - - - - - - - h - - -
    ),
    // A2: the theme's answer, ending on A
    section(HYMN_BPM,
        \\d2 - - - - - - - c2 - - - - - - - | bb1 - - - - - - - a1 - - - - - - -
    ,
        \\c5 - d5 - e5 - c5 - - - - - g4 - - - | f4 - g4 - a4 - f4 - - - - - e4 - - -
    ,
        \\d3 - - - a3 - - - c3 - - - g3 - - - | bb2 - - - f3 - - - a2 - - - e3 - - -
    ,
        \\k - - - - - - - - - - - - - - - | k - - - - - - - - - - - h - - -
    ),
    // B: the Toll rung an octave up
    section(HYMN_BPM,
        \\g2 - - - - - - - d2 - - - - - - - | c3 - - - - - - - g2 - - - - - - -
    ,
        \\g5 - a5 - b5 - g5 - - - - - d5 - - - | e5 - - - c5 - - - d5 - - - - - - -
    ,
        \\g3 - - - b3 - - - d3 - - - a3 - - - | c4 - - - e4 - - - g3 - - - b3 - - -
    ,
        \\k - - - - - - - h - - - - - - - | k - - - - - - - h - - - - - - -
    ),
    // B2: the high Toll settling on D
    section(HYMN_BPM,
        \\g2 - - - - - - - d2 - - - - - - - | c3 - - - - - - - a2 - - - d2 - - -
    ,
        \\g5 - a5 - b5 - g5 - - - - - d5 - - - | e5 - - - c5 - - - a4 - - - d5 - - -
    ,
        \\g3 - - - b3 - - - d3 - - - a3 - - - | c4 - - - e4 - - - a3 - - - d3 - - -
    ,
        \\k - - - - - - - h - - - - - - - | k - - - - - - - h - - - k - - -
    ),
    // C: tolling over open fifths
    section(HYMN_BPM,
        \\d2 - - - - - - - - - - - - - - - | a1 - - - - - - - - - - - - - - -
    ,
        \\d4 - - - - - - - a4 - - - - - - - | e4 - - - - - - - e5 - - - - - - -
    ,
        \\d3 - - - f3 - - - a3 - - - f3 - - - | a2 - - - c3 - - - e3 - - - c3 - - -
    ,
        \\k - - - - - - - - - - - - - - - | k - - - - - - - - - - - - - - -
    ),
    // C2: the tolling through F and C
    section(HYMN_BPM,
        \\f2 - - - - - - - - - - - - - - - | c2 - - - - - - - - - - - - - - -
    ,
        \\a4 - - - - - - - f4 - - - - - - - | g4 - - - - - - - e4 - - - - - - -
    ,
        \\f3 - - - a3 - - - c4 - - - a3 - - - | c3 - - - e3 - - - g3 - - - e3 - - -
    ,
        \\k - - - - - - - - - - - - - - - | k - - - - - - - - - - - h - - -
    ),
    // D: a procession with a walking bass
    section(HYMN_BPM,
        \\d2 - - - e2 - - - f2 - - - g2 - - - | a2 - - - g2 - - - f2 - - - e2 - - -
    ,
        \\a4 - b4 - c5 - - - a4 - c5 - d5 - - - | e5 - d5 - c5 - d5 - a4 - - - g4 - - -
    ,
        \\f3 - - - - - - - a3 - - - - - - - | c4 - - - - - - - a3 - - - - - - -
    ,
        \\k - - - h - - - k - - - h - - - | k - - - h - - - k - - - h - - -
    ),
    // D2: the procession arriving on D
    section(HYMN_BPM,
        \\d2 - - - c2 - - - bb1 - - - a1 - - - | g1 - - - a1 - - - d2 - - - d2 - - -
    ,
        \\f5 - e5 - d5 - - - c5 - a4 - c5 - - - | b4 - - - c5 - - - d5 - - - - - - -
    ,
        \\a3 - - - - - - - f3 - - - - - - - | g3 - - - e3 - - - d3 - f3 - a3 - - -
    ,
        \\k - - - h - - - k - - - h - - - | k - - - h - - - k - - - - - - -
    ),
};

const BELL_TOWER_ARRANGEMENT = order(
    \\a/ld a/l a a2 c/d c2 b b2 a a2 d d2 c c2 b/d b2 a/c a2 d/l d2 c/l c2/d
);

pub const bell_tower = Arranged{ .sections = &BELL_TOWER_SECTIONS, .arrangement = &BELL_TOWER_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The living village: a bright D major morning round, 108 bpm.
// ---------------------------------------------------------------------------

const VILLAGE_BPM = 108;

const LIVING_VILLAGE_SECTIONS = [_]audio.BgmPattern{
    section(VILLAGE_BPM,
        \\d2 - a2 - d2 - a2 - g2 - d2 - a2 - e2 - | d2 - a2 - b2 - f#2 - g2 - a2 - d2 - - -
    ,
        \\f#4 a4 d5 - e5 - f#5 d5 b4 - g4 - a4 - - - | d5 - f#5 - d5 b4 a4 f#4 g4 - e4 - d4 - - -
    ,
        \\d3 - f#3 - a3 - f#3 - g3 - b3 - a3 - e3 - | d3 - f#3 - b3 - d4 - g3 - a3 - d3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - h -
    ),
    section(VILLAGE_BPM,
        \\d2 - a2 - d2 - a2 - g2 - d2 - a2 - e2 - | b2 - f#2 - g2 - a2 - d2 - - - d2 - - -
    ,
        \\f#4 a4 d5 - e5 - f#5 d5 g5 - b4 - c#5 - a4 - | d5 - f#5 - b4 d5 c#5 e5 d5 - - - - - - -
    ,
        \\d3 - f#3 - a3 - f#3 - g3 - b3 - a3 - c#4 - | b3 - d4 - g3 - a3 - d3 - f#3 - a3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - - -
    ),
    section(VILLAGE_BPM,
        \\g2 - d3 - g2 - d3 - d2 - a2 - d2 - a2 - | e2 - b2 - e2 - b2 - a2 - e2 - a2 - - -
    ,
        \\g4 b4 d5 - b4 - g4 - f#4 a4 d5 - a4 - f#4 - | g4 b4 e5 - b4 - g4 - a4 - - - - - - -
    ,
        \\g3 - b3 - d4 - b3 - d3 - f#3 - a3 - f#3 - | e3 - g3 - b3 - g3 - a3 - c#4 - e4 - - -
    ,
        \\k h - h s - h - k h - h s - h - | k h - h s - h - k - s - s h s h
    ),
    section(VILLAGE_BPM,
        \\g2 - d3 - b2 - f#2 - e2 - b2 - a2 - e2 - | g2 - a2 - d2 - - - d2 - - - d2 - - -
    ,
        \\b4 d5 g5 - f#5 - d5 - e5 g5 b4 - c#5 - a4 - | b4 d5 c#5 e5 d5 - - - d4 - - - - - - -
    ,
        \\g3 - b3 - b3 - d4 - e3 - g3 - a3 - c#4 - | g3 - a3 - d3 - f#3 - a3 - - - - - - -
    ,
        \\k h - h s - h - k h - h s - h - | k - s - k - - - - - - - - - - -
    ),
    section(VILLAGE_BPM,
        \\b2 - - - f#2 - - - g2 - - - d2 - - - | e2 - - - b2 - - - a2 - - - - - - -
    ,
        \\f#5 - - - d5 - b4 - b4 - - - g4 - - - | g4 - b4 - d5 - b4 - a4 - - - - - - -
    ,
        \\b3 - d4 - f#4 - d4 - g3 - b3 - d4 - b3 - | e3 - g3 - b3 - g3 - a3 - c#4 - e4 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - h -
    ),
    section(VILLAGE_BPM,
        \\b2 - - - f#2 - - - g2 - - - e2 - - - | a2 - - - e2 - - - d2 - - - d2 - - -
    ,
        \\d5 - f#5 - d5 - b4 - d5 - b4 - g4 - - - | e5 - c#5 - a4 - c#5 - d5 - - - - - - -
    ,
        \\b3 - d4 - f#4 - d4 - g3 - b3 - e3 - g3 - | a3 - c#4 - e4 - c#4 - d3 - f#3 - a3 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - s - k - - -
    ),
    section(VILLAGE_BPM,
        \\d2 - a2 - d3 - a2 - g2 - d3 - g2 - d3 - | e2 - b2 - a2 - e2 - d2 - a2 - d2 - a2 -
    ,
        \\d5 - e5 - f#5 - d5 - g5 - f#5 - e5 - d5 - | e5 - d5 - c#5 - b4 - a4 - b4 - c#5 - d5 -
    ,
        \\d3 - - - a3 - - - g3 - - - d4 - - - | e3 - - - a3 - - - d3 - - - f#3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - s -
    ),
    section(VILLAGE_BPM,
        \\g2 - d3 - b2 - f#2 - e2 - b2 - a2 - e2 - | g2 - a2 - d2 - a2 - d2 - - - - - - -
    ,
        \\g5 - f#5 - d5 - b4 - e5 - d5 - c#5 - a4 - | b4 - c#5 - d5 - - - d5 - - - - - - -
    ,
        \\g3 - - - b3 - - - e3 - - - a3 - - - | g3 - - - a3 - - - d3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const LIVING_VILLAGE_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a+5 a2+5 c c2 d/l d2 a a2 b/d b2 d d2 a a2/lc
);

pub const living_village = Arranged{ .sections = &LIVING_VILLAGE_SECTIONS, .arrangement = &LIVING_VILLAGE_ARRANGEMENT };

// ---------------------------------------------------------------------------
// Lamp Point headland: E dorian coastal whistle march, 116 bpm.
// ---------------------------------------------------------------------------

const HEADLAND_BPM = 116;

const LAMP_POINT_SECTIONS = [_]audio.BgmPattern{
    section(HEADLAND_BPM,
        \\e2 - b2 - e2 - b2 - d2 - a2 - d2 - a2 - | c2 - g2 - d2 - a2 - e2 - b2 - e2 - - -
    ,
        \\e4 g4 b4 - d5 - b4 a4 f#4 - a4 - d4 - - - | e4 g4 c5 - a4 - f#4 d4 e4 - - - - - - -
    ,
        \\e3 - g3 - b3 - g3 - d3 - f#3 - a3 - f#3 - | c3 - e3 - d3 - f#3 - e3 - g3 - b3 - - -
    ,
        \\k - - - h - s - k - - - h - s - | k - - - h - s - k - s - k - - -
    ),
    section(HEADLAND_BPM,
        \\e2 - b2 - e2 - b2 - g2 - d3 - d2 - a2 - | b2 - f#2 - d2 - a2 - e2 - - - e2 - - -
    ,
        \\b4 - d5 - e5 - b4 g4 b4 - d5 - a4 - - - | f#4 - b4 - a4 - f#4 d4 e4 - - - - - - -
    ,
        \\e3 - g3 - b3 - g3 - g3 - b3 - d3 - f#3 - | b3 - d4 - d3 - f#3 - e3 - g3 - b3 - - -
    ,
        \\k - - - h - s - k - - - h - s - | k - - - h - s - k - - - s - - -
    ),
    section(HEADLAND_BPM,
        \\g2 - d3 - g2 - d3 - d2 - a2 - d2 - a2 - | e2 - b2 - g2 - d3 - b2 - f#2 - b2 - - -
    ,
        \\g5 - d5 b4 d5 - g5 - f#5 - d5 a4 d5 - f#5 - | e5 - b4 g4 d5 - b4 - b4 - - - - - - -
    ,
        \\g3 - b3 - d4 - b3 - d3 - f#3 - a3 - f#3 - | e3 - g3 - g3 - b3 - b3 - d4 - f#4 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - h -
    ),
    section(HEADLAND_BPM,
        \\c3 - g2 - d3 - a2 - e2 - b2 - d2 - a2 - | c2 - d2 - e2 - - - e2 - - - e2 - - -
    ,
        \\e5 - c5 g4 f#5 - d5 a4 g5 - e5 b4 f#5 - d5 - | e5 - f#5 - e5 - - - e4 - - - - - - -
    ,
        \\c4 - e4 - d4 - f#4 - e3 - g3 - d3 - f#3 - | c3 - d3 - e3 - g3 - b3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
    section(HEADLAND_BPM,
        \\e2 - - - b2 - - - d2 - - - a2 - - - | c2 - - - g2 - - - b2 - - - - - - -
    ,
        \\b4 - - - e5 - b4 - a4 - - - f#4 - - - | g4 - e4 - c4 - e4 - f#4 - - - - - - -
    ,
        \\e3 - g3 - b3 - g3 - d3 - f#3 - a3 - f#3 - | c3 - e3 - g3 - e3 - b3 - d4 - f#4 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - s -
    ),
    section(HEADLAND_BPM,
        \\e2 - - - b2 - - - d2 - - - b2 - - - | c2 - d2 - e2 - - - e2 - - - e2 - - -
    ,
        \\e5 - d5 - b4 - g4 - a4 - f#4 - d5 - b4 - | c5 - d5 - e5 - - - - - - - - - - -
    ,
        \\e3 - g3 - b3 - g3 - d3 - f#3 - b3 - d4 - | c3 - d3 - e3 - g3 - b3 - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - k - - - - - - - - - - -
    ),
    section(HEADLAND_BPM,
        \\e2 - b2 - e3 - b2 - d2 - a2 - d3 - a2 - | c2 - g2 - c3 - g2 - b2 - f#2 - b2 - f#2 -
    ,
        \\e5 - d5 - b4 - g4 - d5 - c5 - a4 - f#4 - | e4 - g4 - c5 - e5 - d5 - b4 - f#4 - b4 -
    ,
        \\e3 - - - b3 - - - d3 - - - a3 - - - | c3 - - - g3 - - - b3 - - - f#3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - s -
    ),
    section(HEADLAND_BPM,
        \\e2 - b2 - g2 - d3 - c2 - g2 - d2 - a2 - | b2 - f#2 - e2 - - - e2 - - - - - - -
    ,
        \\e5 - g5 - b4 - d5 - c5 - e5 - d5 - f#5 - | b4 - d5 - e5 - - - e5 - - - - - - -
    ,
        \\e3 - - - g3 - - - c3 - - - d3 - - - | b3 - - - e3 - - - - - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const LAMP_POINT_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a-2 a2-2 c c2 d/l d2 b b2 a/d a2 b+2 b2+2 d d2 a a2/lc
);

pub const lamp_point = Arranged{ .sections = &LAMP_POINT_SECTIONS, .arrangement = &LAMP_POINT_ARRANGEMENT };

// ---------------------------------------------------------------------------
// Caustic grog: urgent A minor tick-tock caper, 132 bpm.
// ---------------------------------------------------------------------------

const GROG_BPM = 132;

const CAUSTIC_GROG_SECTIONS = [_]audio.BgmPattern{
    section(GROG_BPM,
        \\a2 - e3 - a2 - e3 - g2 - d3 - g2 - d3 - | f2 - c3 - f2 - c3 - e2 - b2 - e2 - b2 -
    ,
        \\a4 - c5 - e5 - a5 - g5 - e5 - d5 - b4 - | f4 - a4 - c5 - f5 - e5 - d5 - c5 - b4 -
    ,
        \\a3 - - - c4 - - - g3 - - - b3 - - - | f3 - - - a3 - - - e3 - - - g#3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - s -
    ),
    section(GROG_BPM,
        \\a2 - e3 - a2 - e3 - d3 - a3 - d3 - a3 - | f2 - c3 - e2 - b2 - a2 - - - - - - -
    ,
        \\a4 - c5 - e5 - c5 - d5 - f5 - a5 - f5 - | c5 - a4 - b4 - g#4 - a4 - - - - - - -
    ,
        \\a3 - - - c4 - - - d4 - - - f4 - - - | f3 - - - e3 - - - a3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - s - k - s - k - - - - - - -
    ),
    section(GROG_BPM,
        \\c3 - g3 - c3 - g3 - g2 - d3 - g2 - d3 - | d3 - a3 - d3 - a3 - e2 - b2 - e2 - b2 -
    ,
        \\e5 - c5 - g4 - c5 - d5 - b4 - g4 - b4 - | f5 - d5 - a4 - d5 - e5 - b4 - g#4 - e4 -
    ,
        \\c4 - - - e4 - - - g3 - - - b3 - - - | d4 - - - f4 - - - e3 - - - g#3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - h - s - s -
    ),
    section(GROG_BPM,
        \\f2 - c3 - d3 - a3 - g2 - d3 - c3 - g3 - | f2 - e2 - a2 - - - a2 - - - - - - -
    ,
        \\a4 - c5 - d5 - f5 - b4 - d5 - e5 - c5 - | f5 - e5 - a4 - - - a4 - - - - - - -
    ,
        \\f3 - - - d4 - - - g3 - - - c4 - - - | f3 - - - e3 - - - a3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - s - k - s - k - - - - - - -
    ),
    section(GROG_BPM,
        \\a2 - - - - - - - g2 - - - - - - - | f2 - - - - - - - e2 - - - - - - -
    ,
        \\a4 - b4 - c5 - e5 - g4 - a4 - b4 - d5 - | f4 - g4 - a4 - c5 - e4 - f4 - g#4 - b4 -
    ,
        \\a3 - - - c4 - - - g3 - - - b3 - - - | f3 - - - a3 - - - e3 - - - g#3 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - s -
    ),
    section(GROG_BPM,
        \\d3 - - - - - - - c3 - - - - - - - | b2 - - - - - - - e2 - - - a2 - - -
    ,
        \\d5 - e5 - f5 - a5 - c5 - d5 - e5 - g5 - | b4 - c5 - d5 - f5 - e5 - d5 - c5 - a4 -
    ,
        \\d4 - - - f4 - - - c4 - - - e4 - - - | b3 - - - d4 - - - e3 - - - a3 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - h - s - k - - - - - - -
    ),
    section(GROG_BPM,
        \\a2 - g2 - f2 - e2 - d2 - c2 - b1 - e2 - | a2 - b2 - c3 - d3 - e3 - b2 - a2 - - -
    ,
        \\a5 - g5 - f5 - e5 - d5 - c5 - b4 - g#4 - | a4 - b4 - c5 - d5 - e5 - g#5 - a5 - - -
    ,
        \\a3 - g3 - f3 - e3 - | d3 - c3 - b2 - e3 - | a3 - c4 - d4 - e4 - | e3 - g#3 - a3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - - -
    ),
    section(GROG_BPM,
        \\f2 - c3 - g2 - d3 - a2 - e3 - c3 - g3 - | d3 - a3 - e2 - b2 - a2 - - - - - - -
    ,
        \\f5 - c5 - g5 - d5 - a5 - e5 - c5 - g5 - | d5 - f5 - e5 - b4 - a4 - - - - - - -
    ,
        \\f3 - - - g3 - - - a3 - - - c4 - - - | d4 - - - e3 - - - a3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - s - s - s - k - - - - - - -
    ),
};

const CAUSTIC_GROG_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a+2 a2+2 c c2 d/l d2 a a2 b/d b2 c+2 c2+2 b b2 c c2 d d2 a/d a2/lc
);

pub const caustic_grog = Arranged{ .sections = &CAUSTIC_GROG_SECTIONS, .arrangement = &CAUSTIC_GROG_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The Saltmarket: bustling D phrygian bazaar groove, 118 bpm.
// ---------------------------------------------------------------------------

const SALTMARKET_BPM = 118;

const SALTMARKET_SECTIONS = [_]audio.BgmPattern{
    section(SALTMARKET_BPM,
        \\d2 - a2 - eb2 - bb2 - d2 - a2 - c2 - g2 - | d2 - eb2 - f#2 - g2 - d2 - a2 - d2 - - -
    ,
        \\d5 f#5 g5 f#5 eb5 d5 c5 eb5 d5 - a4 - c5 - bb4 a4 | d5 eb5 f#5 g5 a5 f#5 eb5 d5 d5 - - - - - - -
    ,
        \\d3 - f#3 - eb3 - g3 - d3 - f#3 - c3 - eb3 - | d3 - eb3 - f#3 - g3 - d3 - a3 - d3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - h -
    ),
    section(SALTMARKET_BPM,
        \\d2 - a2 - eb2 - bb2 - g2 - d3 - c2 - g2 - | eb2 - bb2 - c2 - g2 - d2 - - - d2 - - -
    ,
        \\f#5 - eb5 d5 eb5 - c5 bb4 g4 - bb4 - c5 - eb5 - | d5 c5 bb4 a4 g4 a4 bb4 c5 d5 - - - - - - -
    ,
        \\d3 - f#3 - eb3 - g3 - g3 - bb3 - c3 - eb3 - | eb3 - g3 - c3 - eb3 - d3 - f#3 - d3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - - - s - - -
    ),
    section(SALTMARKET_BPM,
        \\g2 - d3 - g2 - d3 - c3 - g2 - f2 - c3 - | bb2 - f2 - eb2 - bb2 - a2 - e2 - a2 - - -
    ,
        \\g5 f5 eb5 d5 g5 a5 bb5 g5 c5 bb4 a4 g4 f4 g4 a4 c5 | d5 c5 bb4 a4 g4 f4 eb4 d4 e4 - - - a4 - - -
    ,
        \\g3 - bb3 - d4 - bb3 - c4 - eb4 - f3 - a3 - | bb3 - d4 - eb3 - g3 - a3 - c#4 - e4 - - -
    ,
        \\k - - - h - s - k - h - s - h - | k - - - h - s - k - s - k - s -
    ),
    section(SALTMARKET_BPM,
        \\eb2 - bb2 - d2 - a2 - c2 - g2 - bb2 - f2 - | eb2 - a2 - d2 - - - d2 - - - d2 - - -
    ,
        \\eb5 g5 f5 eb5 d5 f#5 a5 f#5 c5 eb5 d5 c5 bb4 d5 c5 bb4 | eb5 d5 c#5 a4 d5 - - - d4 - - - - - - -
    ,
        \\eb3 - g3 - d3 - f#3 - c3 - eb3 - bb3 - d4 - | eb3 - a3 - d3 - f#3 - a3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
    section(SALTMARKET_BPM,
        \\d2 - - - eb2 - - - f#2 - - - g2 - - - | eb2 - - - c2 - - - d2 - - - - - - -
    ,
        \\d4 - f#4 a4 eb4 - g4 bb4 f#4 - a4 c5 g4 - bb4 d5 | eb5 - c5 - g4 - eb4 - d4 - - - - - - -
    ,
        \\d3 - a3 - eb3 - bb3 - f#3 - c4 - g3 - d4 - | eb3 - g3 - c3 - eb3 - d3 - f#3 - a3 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - h -
    ),
    section(SALTMARKET_BPM,
        \\g2 - - - f2 - - - eb2 - - - d2 - - - | c2 - eb2 - d2 - - - d2 - - - d2 - - -
    ,
        \\g4 bb4 d5 - f4 a4 c5 - eb4 g4 bb4 - d4 f#4 a4 - | c4 eb4 g4 c5 d5 - - - - - - - - - - -
    ,
        \\g3 - bb3 - f3 - a3 - eb3 - g3 - d3 - f#3 - | c3 - eb3 - d3 - f#3 - d3 - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - k - - - - - - - - - - -
    ),
    section(SALTMARKET_BPM,
        \\d2 - a2 - eb2 - bb2 - d2 - a2 - f#2 - c3 - | g2 - d3 - eb2 - bb2 - d2 - a2 - d2 - - -
    ,
        \\d5 - f#5 - eb5 - g5 - d5 - a5 - f#5 - c5 - | bb4 - d5 - eb5 - g5 - f#5 - a5 - d5 - - -
    ,
        \\d3 - - - eb3 - - - d3 - - - f#3 - - - | g3 - - - eb3 - - - d3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - - -
    ),
    section(SALTMARKET_BPM,
        \\eb2 - bb2 - d2 - a2 - c2 - g2 - bb2 - f2 - | eb2 - a2 - d2 - a2 - d2 - - - - - - -
    ,
        \\g5 - f5 - f#5 - d5 - eb5 - d5 - d5 - bb4 - | g4 - a4 - d5 - - - d5 - - - - - - -
    ,
        \\eb3 - - - d3 - - - c3 - - - bb3 - - - | eb3 - - - d3 - - - - - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const SALTMARKET_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a+5 a2+5 c c2 d/l d2 a a2 b/d b2 c c2 d d2 a/d a2/lc
);

pub const saltmarket = Arranged{ .sections = &SALTMARKET_SECTIONS, .arrangement = &SALTMARKET_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The Copper Weathercock: rain-swept F# minor countdown, 104 bpm.
// ---------------------------------------------------------------------------

const WEATHERCOCK_BPM = 104;

const WEATHERCOCK_SECTIONS = [_]audio.BgmPattern{
    section(WEATHERCOCK_BPM,
        \\f#2 - c#3 - e2 - b2 - d2 - a2 - c#2 - g#2 - | b2 - f#2 - c#2 - g#2 - f#2 - - - f#2 - - -
    ,
        \\c#5 f#4 a4 c#5 b4 e4 g#4 b4 a4 d4 f#4 a4 g#4 c#4 e#4 g#4 | d5 b4 f#4 d4 c#5 g#4 e#4 c#4 f#4 - - - - - - -
    ,
        \\f#3 - a3 - e3 - g#3 - d3 - f#3 - c#3 - e#3 - | b3 - d4 - c#3 - e#3 - f#3 - a3 - c#4 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - - -
    ),
    section(WEATHERCOCK_BPM,
        \\f#2 - c#3 - d2 - a2 - e2 - b2 - a2 - e2 - | d2 - a2 - c#2 - g#2 - f#2 - - - f#2 - - -
    ,
        \\f#5 c#5 a4 f#4 d5 a4 f#4 d4 e5 b4 g#4 e4 c#5 a4 e4 c#4 | f#5 d5 a4 f#4 e#5 c#5 g#4 e#4 f#5 - - - - - - -
    ,
        \\f#3 - a3 - d3 - f#3 - e3 - g#3 - a3 - c#4 - | d3 - f#3 - c#3 - e#3 - f#3 - a3 - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - - - - - - -
    ),
    section(WEATHERCOCK_BPM,
        \\a2 - e3 - e2 - b2 - f#2 - c#3 - d2 - a2 - | b2 - f#2 - e2 - b2 - c#2 - g#2 - c#2 - - -
    ,
        \\a4 c#5 e5 a5 g#5 e5 b4 g#4 f#5 c#5 a4 f#4 d5 a4 f#4 d4 | d5 f#5 b4 d5 e5 b4 g#4 e4 c#5 - - - - - - -
    ,
        \\a3 - c#4 - e3 - g#3 - f#3 - a3 - d3 - f#3 - | b3 - d4 - e3 - g#3 - c#3 - e#3 - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - - - s - - -
    ),
    section(WEATHERCOCK_BPM,
        \\d2 - a2 - e2 - b2 - f#2 - c#3 - a2 - e2 - | b2 - c#2 - f#2 - - - f#2 - - - f#2 - - -
    ,
        \\f#5 a5 d5 f#5 g#5 b5 e5 g#5 a5 f#5 c#5 a4 e5 c#5 a4 e4 | d5 b4 e#5 c#5 f#5 - - - f#4 - - - - - - -
    ,
        \\d3 - f#3 - e3 - g#3 - f#3 - a3 - a3 - c#4 - | b3 - c#3 - f#3 - a3 - c#4 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
    section(WEATHERCOCK_BPM,
        \\f#2 - - - e2 - - - d2 - - - c#2 - - - | b1 - - - c#2 - - - f#2 - - - - - - -
    ,
        \\c#6 - - - b5 - - - a5 - - - g#5 - - - | f#5 - d5 - e#5 - c#5 - f#5 - - - - - - -
    ,
        \\f#3 - a3 - e3 - g#3 - d3 - f#3 - c#3 - e#3 - | b2 - d3 - c#3 - e#3 - f#3 - a3 - c#4 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - k - - - - - - -
    ),
    section(WEATHERCOCK_BPM,
        \\d2 - - - c#2 - - - b1 - - - a1 - - - | g#1 - - - c#2 - - - f#2 - - - f#2 - - -
    ,
        \\a4 - d5 - g#4 - c#5 - f#4 - b4 - e4 - a4 - | b4 - d5 - c#5 - e#5 - f#5 - - - - - - -
    ,
        \\d3 - f#3 - c#3 - e#3 - b2 - d3 - a2 - c#3 - | g#2 - b2 - c#3 - e#3 - f#3 - a3 - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - - - - - - -
    ),
    section(WEATHERCOCK_BPM,
        \\f#2 - c#3 - e2 - b2 - d2 - a2 - c#2 - g#2 - | b2 - f#2 - a2 - e2 - g#2 - d2 - c#2 - g#2 -
    ,
        \\f#5 - c#5 - e5 - b4 - d5 - a4 - c#5 - g#4 - | b4 - f#4 - a4 - e4 - g#4 - d4 - c#5 - e#5 -
    ,
        \\f#3 - - - e3 - - - d3 - - - c#3 - - - | b3 - - - a3 - - - g#3 - - - c#3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - h -
    ),
    section(WEATHERCOCK_BPM,
        \\d2 - a2 - e2 - b2 - f#2 - c#3 - a2 - e2 - | b2 - c#2 - f#2 - c#2 - f#2 - - - - - - -
    ,
        \\d5 - f#5 - e5 - g#5 - f#5 - a5 - a5 - c#5 - | d5 - e#5 - f#5 - - - f#5 - - - - - - -
    ,
        \\d3 - - - e3 - - - f#3 - - - a3 - - - | b3 - - - c#3 - - - f#3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const WEATHERCOCK_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a-2 a2-2 c c2 d/l d2 a a2 b/d b2 d d2 a/d a2/lc
);

pub const weathercock = Arranged{ .sections = &WEATHERCOCK_SECTIONS, .arrangement = &WEATHERCOCK_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The Castle Fire Escape: crackling C# minor keep dash, 136 bpm.
// ---------------------------------------------------------------------------

const FIRE_ESCAPE_BPM = 136;

const FIRE_ESCAPE_SECTIONS = [_]audio.BgmPattern{
    section(FIRE_ESCAPE_BPM,
        \\c#2 - g#2 - c#2 - g#2 - a1 - e2 - b1 - f#2 - | c#2 - g#2 - b1 - f#2 - c#2 - - - g#1 - - -
    ,
        \\c#5 e5 g#5 e5 c#5 e5 g#5 c#6 a4 c#5 e5 a5 b4 d#5 f#5 b5 | g#5 e5 c#5 e5 f#5 d#5 b4 d#5 c#5 - - - - - - -
    ,
        \\c#3 - e3 - g#3 - e3 - a2 - c#3 - b2 - d#3 - | c#3 - e3 - b2 - d#3 - c#3 - g#3 - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - s -
    ),
    section(FIRE_ESCAPE_BPM,
        \\c#2 - g#2 - a1 - e2 - b1 - f#2 - g#1 - d#2 - | a1 - b1 - c#2 - - - c#2 - - - c#2 - - -
    ,
        \\g#5 e5 c#5 g#4 a5 e5 c#5 a4 b5 f#5 d#5 b4 g#5 d#5 b#4 g#4 | a4 c#5 b4 d#5 c#5 - - - c#4 - - - - - - -
    ,
        \\c#3 - e3 - a2 - c#3 - b2 - d#3 - g#2 - b#2 - | a2 - b2 - c#3 - e3 - g#3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - s - k - s - k - - - - - - -
    ),
    section(FIRE_ESCAPE_BPM,
        \\e2 - b2 - e2 - b2 - b1 - f#2 - b1 - f#2 - | c#2 - g#2 - a1 - e2 - b1 - f#2 - b1 - - -
    ,
        \\e5 g#5 b5 g#5 e5 g#5 b5 e6 d#5 f#5 b5 f#5 d#5 b4 f#4 b4 | c#5 e5 g#5 e5 a4 c#5 e5 a5 b4 - - - - - - -
    ,
        \\e3 - g#3 - b3 - g#3 - b2 - d#3 - f#3 - d#3 - | c#3 - e3 - a2 - c#3 - b2 - d#3 - f#3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - - - s - - -
    ),
    section(FIRE_ESCAPE_BPM,
        \\a1 - e2 - b1 - f#2 - c#2 - g#2 - e2 - b2 - | a1 - g#1 - c#2 - - - c#2 - - - c#2 - - -
    ,
        \\a5 e5 c#5 a4 b5 f#5 d#5 b4 g#5 e5 c#5 g#4 e5 b4 g#4 e4 | f#4 a4 g#4 b#4 c#5 - - - c#4 - - - - - - -
    ,
        \\a2 - c#3 - b2 - d#3 - c#3 - e3 - e3 - g#3 - | a2 - g#2 - c#3 - e3 - - - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
    section(FIRE_ESCAPE_BPM,
        \\c#2 - - - b1 - - - a1 - - - g#1 - - - | f#1 - - - g#1 - - - c#2 - - - - - - -
    ,
        \\c#5 - e5 g#5 b4 - d#5 f#5 a4 - c#5 e5 g#4 - b#4 d#5 | f#4 - a4 c#5 g#4 - b#4 d#5 c#5 - - - - - - -
    ,
        \\c#3 - e3 - b2 - d#3 - a2 - c#3 - g#2 - b#2 - | f#2 - a2 - g#2 - b#2 - c#3 - e3 - g#3 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - h -
    ),
    section(FIRE_ESCAPE_BPM,
        \\e2 - - - d#2 - - - c#2 - - - b1 - - - | a1 - b1 - c#2 - - - c#2 - - - c#2 - - -
    ,
        \\e5 - b4 - d#5 - b4 - c#5 - g#4 - b4 - f#4 - | a4 - b4 - c#5 - - - - - - - - - - -
    ,
        \\e3 - g#3 - d#3 - f#3 - c#3 - e3 - b2 - d#3 - | a2 - b2 - c#3 - e3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - k - - - - - - - - - - -
    ),
    section(FIRE_ESCAPE_BPM,
        \\c#2 - g#2 - e2 - b2 - a1 - e2 - b1 - f#2 - | c#2 - g#2 - b1 - f#2 - a1 - e2 - g#1 - d#2 -
    ,
        \\c#5 - g#5 - e5 - b5 - a4 - e5 - b4 - f#5 - | c#5 - g#5 - b4 - f#5 - a4 - e5 - g#4 - d#5 -
    ,
        \\c#3 - - - e3 - - - a2 - - - b2 - - - | c#3 - - - b2 - - - a2 - - - g#2 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - s -
    ),
    section(FIRE_ESCAPE_BPM,
        \\a1 - e2 - b1 - f#2 - c#2 - g#2 - e2 - b2 - | a1 - g#1 - c#2 - g#2 - c#2 - - - - - - -
    ,
        \\a5 - e5 - b5 - f#5 - c#6 - g#5 - e5 - b4 - | a4 - b#4 - c#5 - - - c#5 - - - - - - -
    ,
        \\a2 - - - b2 - - - c#3 - - - e3 - - - | a2 - - - g#2 - - - c#3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const FIRE_ESCAPE_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a+2 a2+2 c c2 d/l d2 a a2 b/d b2 c+2 c2+2 b b2 d d2 c c2 d d2 a/d a2/lc
);

pub const fire_escape = Arranged{ .sections = &FIRE_ESCAPE_SECTIONS, .arrangement = &FIRE_ESCAPE_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The Larkspur Observatory: nocturnal Bb minor stargazing mystery, 96 bpm.
// ---------------------------------------------------------------------------

const OBSERVATORY_BPM = 96;

const OBSERVATORY_SECTIONS = [_]audio.BgmPattern{
    section(OBSERVATORY_BPM,
        \\bb1 - - - f2 - - - gb2 - - - f2 - - - | eb2 - - - bb2 - - - f2 - - - bb1 - - -
    ,
        \\bb4 - f5 - db5 - bb4 - gb5 - eb5 - c5 - a4 - | gb4 - eb4 - f4 - db5 - c5 - a4 - bb4 - - -
    ,
        \\bb2 - db3 - f3 - db3 - gb2 - bb2 - f2 - a2 - | eb3 - gb3 - f2 - a2 - bb2 - - - - - - -
    ,
        \\k - - - - - - - h - - - - - - - | k - - - - - - - h - - - - - k -
    ),
    section(OBSERVATORY_BPM,
        \\bb1 - - - f2 - - - db2 - - - ab2 - - - | gb2 - - - f2 - - - bb1 - - - bb1 - - -
    ,
        \\f5 - db5 - bb4 - f4 - ab5 - f5 - db5 - ab4 - | gb5 - eb5 - c5 - a4 - bb4 - - - - - - -
    ,
        \\bb2 - db3 - f3 - db3 - db3 - f3 - ab3 - f3 - | gb2 - bb2 - f2 - a2 - bb2 - db3 - - - - -
    ,
        \\k - - - - - - - h - - - - - - - | k - - - s - - - k - - - - - - -
    ),
    section(OBSERVATORY_BPM,
        \\db2 - ab2 - db3 - ab2 - gb2 - db3 - gb2 - db3 - | ab2 - eb3 - ab2 - eb3 - f2 - c3 - f2 - - -
    ,
        \\db5 f5 ab5 f5 db5 f5 ab5 db6 gb5 eb5 bb4 eb5 gb5 bb5 eb6 gb5 | ab5 eb5 c5 eb5 ab5 f5 eb5 c5 f5 - - - - - - -
    ,
        \\db3 - f3 - ab3 - f3 - gb3 - bb3 - db4 - bb3 - | ab3 - c4 - eb4 - c4 - f3 - a3 - c4 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - - -
    ),
    section(OBSERVATORY_BPM,
        \\gb2 - db3 - f2 - c3 - eb2 - bb2 - db2 - ab2 - | gb2 - f2 - bb1 - - - bb1 - - - bb1 - - -
    ,
        \\bb5 gb5 db5 bb4 a5 f5 c5 a4 gb5 eb5 bb4 gb4 f5 db5 ab4 f4 | eb5 gb5 f5 a5 bb5 - - - bb4 - - - - - - -
    ,
        \\gb3 - bb3 - f3 - a3 - eb3 - gb3 - db3 - f3 - | gb2 - f2 - bb2 - db3 - f3 - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - - - - - - -
    ),
    section(OBSERVATORY_BPM,
        \\bb1 - - - - - - - eb2 - - - - - - - | gb2 - - - - - - - f2 - - - - - - -
    ,
        \\db5 - f5 - bb5 - f5 - eb5 - gb5 - bb5 - gb5 - | db5 - bb4 - gb4 - bb4 - c5 - a4 - f4 - - -
    ,
        \\bb2 - db3 - f3 - db3 - eb3 - gb3 - bb3 - gb3 - | gb2 - bb2 - db3 - bb2 - f2 - a2 - c3 - - -
    ,
        \\k - - - - - - - - - - - - - - - | k - - - - - - - h - - - - - - -
    ),
    section(OBSERVATORY_BPM,
        \\gb2 - - - ab2 - - - bb2 - - - f2 - - - | eb2 - f2 - bb1 - - - bb1 - - - bb1 - - -
    ,
        \\bb4 - gb4 - c5 - ab4 - db5 - bb4 - a4 - f4 - | gb4 - a4 - bb4 - - - - - - - - - - -
    ,
        \\gb2 - bb2 - ab2 - c3 - bb2 - db3 - f2 - a2 - | eb3 - f2 - bb2 - db3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - k - - - - - - - - - - -
    ),
    section(OBSERVATORY_BPM,
        \\bb1 - f2 - db2 - f2 - gb2 - db3 - f2 - c3 - | eb2 - bb2 - f2 - c3 - bb1 - f2 - db2 - ab2 -
    ,
        \\bb4 - db5 - f5 - bb5 - gb5 - eb5 - c5 - f5 - | eb5 - bb4 - a4 - f4 - db5 - f5 - ab5 - c5 -
    ,
        \\bb2 - - - db3 - - - gb2 - - - f2 - - - | eb3 - - - f2 - - - bb2 - - - db3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - s -
    ),
    section(OBSERVATORY_BPM,
        \\gb2 - db3 - ab2 - eb3 - f2 - c3 - bb1 - f2 - | eb2 - f2 - bb1 - - - bb1 - - - - - - -
    ,
        \\gb5 - bb5 - ab5 - c5 - a5 - f5 - bb4 - db5 - | eb5 - f5 - bb4 - - - bb4 - - - - - - -
    ,
        \\gb2 - - - ab2 - - - f2 - - - bb2 - - - | eb3 - - - f2 - - - bb2 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const OBSERVATORY_ARRANGEMENT = order(
    \\a/ld a/l a a2 c/d c2 b b2 a a2 d d2 b b2 a+5 a2+5 c c2 d/l d2 a a2 b/d b2 a/d a2/lc
);

pub const observatory = Arranged{ .sections = &OBSERVATORY_SECTIONS, .arrangement = &OBSERVATORY_ARRANGEMENT };

// ---------------------------------------------------------------------------
// Valerius and the Bread: austere F minor garrison hymn & spring thaw, 88 bpm.
// ---------------------------------------------------------------------------

const VALERIUS_BPM = 88;

const VALERIUS_SECTIONS = [_]audio.BgmPattern{
    section(VALERIUS_BPM,
        \\f2 - - - c2 - - - db2 - - - c2 - - - | bb1 - - - c2 - - - f2 - - - f2 - - -
    ,
        \\f4 - g4 - ab4 - c5 - db5 - c5 - ab4 - g4 - | f4 - eb4 - e4 - c4 - f4 - - - - - - -
    ,
        \\f3 - ab3 - c3 - eb3 - db3 - f3 - c3 - eb3 - | bb2 - db3 - c3 - e3 - f3 - ab3 - - - - -
    ,
        \\k - - - - - - - h - - - - - - - | k - - - - - - - k - - - h - - -
    ),
    section(VALERIUS_BPM,
        \\f2 - - - eb2 - - - db2 - - - ab1 - - - | bb1 - - - c2 - - - f2 - - - f2 - - -
    ,
        \\c5 - bb4 - ab4 - g4 - f4 - ab4 - c5 - ab4 - | g4 - f4 - e4 - g4 - f4 - - - - - - -
    ,
        \\f3 - ab3 - eb3 - g3 - db3 - f3 - ab2 - c3 - | bb2 - db3 - c3 - e3 - f3 - ab3 - - - - -
    ,
        \\k - - - - - - - h - - - - - - - | k - - - s - - - k - - - - - - -
    ),
    section(VALERIUS_BPM,
        \\ab2 - eb3 - ab2 - eb3 - eb2 - bb2 - eb2 - bb2 - | db2 - ab2 - db2 - ab2 - c2 - g2 - c2 - - -
    ,
        \\ab4 c5 eb5 - c5 - ab4 - g4 bb4 eb5 - bb4 - g4 - | f4 ab4 db5 - ab4 - f4 - g4 - - - - - - -
    ,
        \\ab3 - c4 - eb4 - c4 - eb3 - g3 - bb3 - g3 - | db3 - f3 - ab3 - f3 - c3 - e3 - g3 - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - - -
    ),
    section(VALERIUS_BPM,
        \\f2 - c3 - eb2 - bb2 - db2 - ab2 - c2 - g2 - | bb1 - c2 - f2 - - - f2 - - - f2 - - -
    ,
        \\c5 - ab4 f4 eb5 - bb4 g4 db5 - ab4 f4 c5 - g4 e4 | f4 db5 c5 e5 f5 - - - f4 - - - - - - -
    ,
        \\f3 - ab3 - eb3 - g3 - db3 - f3 - c3 - e3 - | bb2 - c3 - f3 - ab3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - - - - - - -
    ),
    section(VALERIUS_BPM,
        \\f2 - - - - - - - c2 - - - - - - - | db2 - - - - - - - c2 - - - - - - -
    ,
        \\f4 - - - c5 - - - g4 - - - e4 - - - | f4 - - - ab4 - - - g4 - - - - - - -
    ,
        \\f3 - ab3 - c4 - ab3 - c3 - e3 - g3 - e3 - | db3 - f3 - ab3 - f3 - c3 - e3 - g3 - - -
    ,
        \\k - - - - - - - - - - - - - - - | k - - - - - - - h - - - - - - -
    ),
    section(VALERIUS_BPM,
        \\bb1 - - - ab1 - - - g1 - - - c2 - - - | db2 - eb2 - f2 - - - f2 - - - f2 - - -
    ,
        \\bb4 - f4 - ab4 - eb4 - g4 - db4 - e4 - c4 - | f4 - g4 - ab4 - - - - - - - - - - -
    ,
        \\bb2 - db3 - ab2 - c3 - g2 - bb2 - c3 - e3 - | db3 - eb3 - f3 - ab3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - k - - - - - - - - - - -
    ),
    section(VALERIUS_BPM,
        \\f2 - c3 - eb2 - bb2 - db2 - ab2 - c2 - g2 - | bb1 - f2 - c2 - g2 - f2 - c3 - f2 - - -
    ,
        \\f4 - ab4 - eb5 - g4 - db5 - f4 - c5 - e4 - | db4 - f4 - e4 - g4 - f4 - ab4 - c5 - - -
    ,
        \\f3 - - - eb3 - - - db3 - - - c3 - - - | bb2 - - - c3 - - - f3 - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - - -
    ),
    section(VALERIUS_BPM,
        \\ab2 - eb3 - eb2 - bb2 - db2 - ab2 - c2 - g2 - | bb1 - c2 - f2 - - - f2 - - - - - - -
    ,
        \\c5 - eb5 - bb4 - g4 - ab4 - f4 - g4 - e4 - | f4 - g4 - f4 - - - f4 - - - - - - -
    ,
        \\ab3 - - - eb3 - - - db3 - - - c3 - - - | bb2 - - - f3 - - - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - - - - - - -
    ),
};

const VALERIUS_ARRANGEMENT = order(
    \\a/ld a/l a a2 c/d c2 b b2 a a2 d d2 b b2 a+5 a2+5 c c2 d/l d2 a a2 b/d b2
);

pub const valerius = Arranged{ .sections = &VALERIUS_SECTIONS, .arrangement = &VALERIUS_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The Lamplighter's Round: G minor cobblestone dusk stroll, 102 bpm.
// ---------------------------------------------------------------------------

const LAMPLIGHTER_BPM = 102;

const LAMPLIGHTER_SECTIONS = [_]audio.BgmPattern{
    section(LAMPLIGHTER_BPM,
        \\g2 - d3 - f2 - c3 - eb2 - bb2 - d2 - a2 - | c2 - g2 - d2 - a2 - g2 - - - g2 - - -
    ,
        \\g4 - bb4 d5 f5 - d5 c5 eb5 - c5 bb4 a4 - f#4 d4 | g4 - bb4 - a4 - f#4 - g4 - - - - - - -
    ,
        \\g3 - bb3 - f3 - a3 - eb3 - g3 - d3 - f#3 - | c3 - eb3 - d3 - f#3 - g3 - bb3 - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - k - - -
    ),
    section(LAMPLIGHTER_BPM,
        \\g2 - d3 - bb2 - f2 - c2 - g2 - d2 - a2 - | eb2 - d2 - g2 - - - g2 - - - g2 - - -
    ,
        \\d5 - g5 f5 d5 - bb4 f4 eb5 - c5 g4 f#4 - a4 d5 | g5 eb5 d5 f#5 g5 - - - g4 - - - - - - -
    ,
        \\g3 - bb3 - bb3 - d4 - c3 - eb3 - d3 - f#3 - | eb3 - d3 - g3 - bb3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - - - - - - -
    ),
    section(LAMPLIGHTER_BPM,
        \\bb2 - f2 - f2 - c3 - g2 - d3 - eb2 - bb2 - | c2 - g2 - f2 - c3 - d2 - a2 - d2 - - -
    ,
        \\bb4 d5 f5 - a4 c5 f5 - g4 bb4 d5 - g4 bb4 eb5 - | c5 eb5 g5 - a4 c5 f5 - d5 - - - - - - -
    ,
        \\bb3 - d4 - f3 - a3 - g3 - bb3 - eb3 - g3 - | c3 - eb3 - f3 - a3 - d3 - f#3 - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - - - s - - -
    ),
    section(LAMPLIGHTER_BPM,
        \\eb2 - bb2 - f2 - c3 - bb2 - f2 - g2 - d3 - | c2 - d2 - g2 - - - g2 - - - g2 - - -
    ,
        \\eb5 g5 bb5 g5 f5 a5 c6 a5 d5 f5 bb4 d5 g5 d5 bb4 g4 | eb5 c5 f#4 a4 g4 - - - - - - - - - - -
    ,
        \\eb3 - g3 - f3 - a3 - bb3 - d4 - g3 - bb3 - | c3 - d3 - g3 - bb3 - - - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
    section(LAMPLIGHTER_BPM,
        \\g2 - - - f2 - - - eb2 - - - d2 - - - | c2 - - - d2 - - - g2 - - - - - - -
    ,
        \\d5 - bb4 - c5 - a4 - bb4 - g4 - a4 - f#4 - | g4 - eb4 - f#4 - d4 - g4 - - - - - - -
    ,
        \\g3 - bb3 - f3 - a3 - eb3 - g3 - d3 - f#3 - | c3 - eb3 - d3 - f#3 - g3 - bb3 - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - - -
    ),
    section(LAMPLIGHTER_BPM,
        \\c2 - - - bb1 - - - a1 - - - d2 - - - | eb2 - f2 - g2 - - - g2 - - - g2 - - -
    ,
        \\c5 - g4 - bb4 - f4 - a4 - e4 - f#4 - d4 - | g4 - a4 - bb4 - - - - - - - - - - -
    ,
        \\c3 - eb3 - bb2 - d3 - a2 - c3 - d3 - f#3 - | eb3 - f3 - g3 - bb3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - k - - - - - - - - - - -
    ),
    section(LAMPLIGHTER_BPM,
        \\g2 - d3 - f2 - c3 - eb2 - bb2 - d2 - a2 - | c2 - g2 - d2 - a2 - g2 - d3 - g2 - - -
    ,
        \\g4 - bb4 - f4 - a4 - eb4 - g4 - d4 - f#4 - | c4 - eb4 - d4 - f#4 - g4 - bb4 - d5 - - -
    ,
        \\g3 - - - f3 - - - eb3 - - - d3 - - - | c3 - - - d3 - - - g3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - h -
    ),
    section(LAMPLIGHTER_BPM,
        \\eb2 - bb2 - f2 - c3 - g2 - d3 - bb2 - f2 - | c2 - d2 - g2 - - - g2 - - - - - - -
    ,
        \\eb5 - g5 - f5 - a5 - g5 - bb5 - d5 - f5 - | eb5 - f#5 - g5 - - - g5 - - - - - - -
    ,
        \\eb3 - - - f3 - - - g3 - - - bb3 - - - | c3 - - - d3 - - - g3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const LAMPLIGHTER_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a+5 a2+5 c c2 d/l d2 a a2 b/d b2 a/d a2/lc
);

pub const lamplighter = Arranged{ .sections = &LAMPLIGHTER_SECTIONS, .arrangement = &LAMPLIGHTER_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The Long Gallery: B minor stealth tiptoe and pursuit next door, 110 bpm.
// ---------------------------------------------------------------------------

const LONG_GALLERY_BPM = 110;

const LONG_GALLERY_SECTIONS = [_]audio.BgmPattern{
    section(LONG_GALLERY_BPM,
        \\b1 - f#2 - a1 - e2 - g1 - d2 - f#1 - c#2 - | e1 - b1 - f#1 - c#2 - b1 - - - b1 - - -
    ,
        \\b4 - d5 - f#5 - d5 - e5 - c#5 - a#4 - f#4 - | g4 - b4 - c#5 - a#4 - b4 - - - - - - -
    ,
        \\b2 - d3 - a2 - c#3 - g2 - b2 - f#2 - a#2 - | e2 - g2 - f#2 - a#2 - b2 - d3 - - - - -
    ,
        \\k - - - h - - - - - - - h - - - | k - - - h - - - s - - - h - - -
    ),
    section(LONG_GALLERY_BPM,
        \\b1 - f#2 - g1 - d2 - a1 - e2 - d2 - a2 - | e2 - f#2 - b1 - - - b1 - - - b1 - - -
    ,
        \\f#5 - d5 b4 g5 - d5 b4 e5 - c#5 a4 d5 - f#5 a5 | g5 e5 c#5 a#4 b4 - - - b3 - - - - - - -
    ,
        \\b2 - d3 - g2 - b2 - a2 - c#3 - d3 - f#3 - | e3 - f#2 - b2 - d3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - - - - - - -
    ),
    section(LONG_GALLERY_BPM,
        \\d2 - a2 - d2 - a2 - a1 - e2 - a1 - e2 - | g1 - d2 - e2 - b2 - f#2 - c#3 - f#2 - - -
    ,
        \\d5 f#5 a5 f#5 d5 f#5 a5 d6 c#5 e5 a5 e5 c#5 a4 e4 a4 | b4 d5 g5 d5 e5 g5 b5 g5 f#5 - - - - - - -
    ,
        \\d3 - f#3 - a3 - f#3 - a2 - c#3 - e3 - c#3 - | g2 - b2 - e3 - g3 - f#3 - a#3 - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - - - s - - -
    ),
    section(LONG_GALLERY_BPM,
        \\g1 - d2 - a1 - e2 - b1 - f#2 - d2 - a2 - | g1 - f#1 - b1 - - - b1 - - - b1 - - -
    ,
        \\g5 d5 b4 g4 e5 c#5 a4 e4 f#5 d5 b4 f#4 d5 a4 f#4 d4 | g4 b4 a#4 c#5 b4 - - - b3 - - - - - - -
    ,
        \\g2 - b2 - a2 - c#3 - b2 - d3 - d3 - f#3 - | g2 - f#2 - b2 - d3 - - - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
    section(LONG_GALLERY_BPM,
        \\b1 - - - a1 - - - g1 - - - f#1 - - - | e1 - - - f#1 - - - b1 - - - - - - -
    ,
        \\b4 - f#5 - a4 - e5 - g4 - d5 - f#4 - c#5 - | e4 - g4 - f#4 - a#4 - b4 - - - - - - -
    ,
        \\b2 - d3 - a2 - c#3 - g2 - b2 - f#2 - a#2 - | e2 - g2 - f#2 - a#2 - b2 - d3 - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - - -
    ),
    section(LONG_GALLERY_BPM,
        \\g1 - - - f#1 - - - e1 - - - d2 - - - | g1 - f#1 - b1 - - - b1 - - - b1 - - -
    ,
        \\g4 - b4 - f#4 - a#4 - e4 - g4 - d5 - f#4 - | g4 - a#4 - b4 - - - - - - - - - - -
    ,
        \\g2 - b2 - f#2 - a#2 - e2 - g2 - d3 - f#3 - | g2 - f#2 - b2 - d3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - k - - - - - - - - - - -
    ),
    section(LONG_GALLERY_BPM,
        \\b1 - f#2 - a1 - e2 - g1 - d2 - f#1 - c#2 - | e1 - b1 - d2 - a2 - g1 - d2 - f#1 - c#2 -
    ,
        \\b4 - d5 - a4 - c#5 - g4 - b4 - f#4 - a#4 - | e4 - g4 - d5 - f#5 - g4 - b4 - f#4 - c#5 -
    ,
        \\b2 - - - a2 - - - g2 - - - f#2 - - - | e2 - - - d3 - - - g2 - - - f#2 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - h -
    ),
    section(LONG_GALLERY_BPM,
        \\g1 - d2 - a1 - e2 - b1 - f#2 - d2 - a2 - | e2 - f#2 - b1 - - - b1 - - - - - - -
    ,
        \\g5 - b4 - a5 - c#5 - b5 - d5 - f#5 - a4 - | g4 - a#4 - b4 - - - b4 - - - - - - -
    ,
        \\g2 - - - a2 - - - b2 - - - d3 - - - | e3 - - - f#2 - - - b2 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const LONG_GALLERY_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a+5 a2+5 c c2 d/l d2 a a2 b/d b2 d d2 a/d a2/lc
);

pub const long_gallery = Arranged{ .sections = &LONG_GALLERY_SECTIONS, .arrangement = &LONG_GALLERY_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The Word Foundry: metallic D dorian/mixolydian anvil & lexicon, 100 bpm.
// ---------------------------------------------------------------------------

const FOUNDRY_BPM = 100;

const WORD_FOUNDRY_SECTIONS = [_]audio.BgmPattern{
    section(FOUNDRY_BPM,
        \\d2 - a2 - c2 - g2 - bb1 - f2 - a1 - e2 - | g1 - d2 - a1 - e2 - d2 - - - d2 - - -
    ,
        \\d4 a4 d5 - c4 g4 c5 - bb3 f4 bb4 - a3 e4 a4 - | g4 b4 d5 - a4 c#5 e5 - d5 - - - - - - -
    ,
        \\d3 - f3 - c3 - e3 - bb2 - d3 - a2 - c3 - | g2 - b2 - a2 - c#3 - d3 - f3 - - - - -
    ,
        \\k - - - s - - - k - - - s - - - | k - - - s - - - k - s - k - - -
    ),
    section(FOUNDRY_BPM,
        \\d2 - a2 - f2 - c3 - c2 - g2 - a1 - e2 - | bb1 - a1 - d2 - - - d2 - - - d2 - - -
    ,
        \\d5 a4 f4 d4 f5 c5 a4 f4 e5 c5 g4 e4 c#5 a4 e4 c#4 | d5 bb4 c#5 a4 d5 - - - d4 - - - - - - -
    ,
        \\d3 - f3 - f3 - a3 - c3 - e3 - a2 - c#3 - | bb2 - a2 - d3 - f#3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - - - - - - -
    ),
    section(FOUNDRY_BPM,
        \\f2 - c3 - f2 - c3 - c2 - g2 - c2 - g2 - | bb1 - f2 - g1 - d2 - a1 - e2 - a1 - - -
    ,
        \\f4 a4 c5 f5 e5 c5 a4 f4 c4 e4 g4 c5 b4 g4 e4 c4 | d4 f4 bb4 - g4 b4 d5 - e5 - - - a4 - - -
    ,
        \\f3 - a3 - c4 - a3 - c3 - e3 - g3 - e3 - | bb2 - d3 - g2 - b2 - a2 - c#3 - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - - - s - - -
    ),
    section(FOUNDRY_BPM,
        \\g1 - d2 - a1 - e2 - d2 - a2 - f2 - c3 - | bb1 - c2 - d2 - - - d2 - - - d2 - - -
    ,
        \\g4 b4 d5 g5 a4 c#5 e5 a5 d5 f5 a5 f5 c5 a4 f4 c4 | d5 bb4 e5 c5 d5 - - - - - - - - - - -
    ,
        \\g2 - b2 - a2 - c#3 - d3 - f3 - f3 - a3 - | bb2 - c3 - d3 - f#3 - - - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
    section(FOUNDRY_BPM,
        \\d2 - - - c2 - - - bb1 - - - a1 - - - | g1 - - - a1 - - - d2 - - - - - - -
    ,
        \\d5 - - - e5 - - - f5 - - - e5 - - - | d5 - b4 - c#5 - a4 - d5 - - - - - - -
    ,
        \\d3 - f3 - c3 - e3 - bb2 - d3 - a2 - c3 - | g2 - b2 - a2 - c#3 - d3 - f3 - - - - -
    ,
        \\k - - - - - - - s - - - - - - - | k - - - s - - - k - - - - - - -
    ),
    section(FOUNDRY_BPM,
        \\bb1 - - - c2 - - - d2 - - - f2 - - - | g2 - a2 - d2 - - - d2 - - - d2 - - -
    ,
        \\bb4 - d5 - c5 - e5 - d5 - f5 - a5 - f5 - | g5 - e5 - d5 - - - - - - - - - - -
    ,
        \\bb2 - d3 - c3 - e3 - d3 - f3 - f3 - a3 - | g3 - a3 - d3 - f#3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - k - - - - - - - - - - -
    ),
    section(FOUNDRY_BPM,
        \\d2 - a2 - c2 - g2 - bb1 - f2 - a1 - e2 - | g1 - d2 - a1 - e2 - d2 - a2 - f2 - c3 -
    ,
        \\d5 - a4 - c5 - g4 - bb4 - f4 - a4 - e4 - | g4 - d5 - a4 - e5 - d5 - f5 - a5 - c5 -
    ,
        \\d3 - - - c3 - - - bb2 - - - a2 - - - | g2 - - - a2 - - - d3 - - - f3 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - h -
    ),
    section(FOUNDRY_BPM,
        \\bb1 - f2 - c2 - g2 - d2 - a2 - f2 - c3 - | g2 - a2 - d2 - - - d2 - - - - - - -
    ,
        \\bb4 - d5 - c5 - e5 - d5 - f5 - c5 - a5 - | g5 - e5 - d5 - - - d5 - - - - - - -
    ,
        \\bb2 - - - c3 - - - d3 - - - f3 - - - | g3 - - - a3 - - - d3 - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const WORD_FOUNDRY_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a+5 a2+5 c c2 d/l d2 a a2 b/d b2 a/d a2/lc
);

pub const word_foundry = Arranged{ .sections = &WORD_FOUNDRY_SECTIONS, .arrangement = &WORD_FOUNDRY_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The Cinder Table: sly Eb major / C minor parlor card sway, 114 bpm.
// ---------------------------------------------------------------------------

const CINDER_TABLE_BPM = 114;

const CINDER_TABLE_SECTIONS = [_]audio.BgmPattern{
    section(CINDER_TABLE_BPM,
        \\eb2 - bb2 - c2 - g2 - ab1 - eb2 - bb1 - f2 - | g1 - d2 - c2 - g2 - eb2 - - - bb1 - - -
    ,
        \\g4 - bb4 eb5 c5 - g4 eb4 ab4 - c5 eb5 f4 - d5 bb4 | g4 - b4 d5 c5 - g4 - eb4 - - - - - - -
    ,
        \\eb3 - g3 - c3 - eb3 - ab2 - c3 - bb2 - d3 - | g2 - b2 - c3 - eb3 - eb3 - g3 - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - k - - -
    ),
    section(CINDER_TABLE_BPM,
        \\eb2 - bb2 - g2 - d3 - ab1 - eb2 - bb1 - f2 - | ab1 - bb1 - eb2 - - - eb2 - - - eb2 - - -
    ,
        \\eb5 - bb4 g4 d5 - b4 g4 c5 - eb5 c5 d5 - bb4 f4 | ab4 c5 bb4 d5 eb5 - - - eb4 - - - - - - -
    ,
        \\eb3 - g3 - g3 - b3 - ab2 - c3 - bb2 - d3 - | ab2 - bb2 - eb3 - g3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - s - - - k - - - - - - -
    ),
    section(CINDER_TABLE_BPM,
        \\c2 - g2 - c2 - g2 - f2 - c3 - f2 - c3 - | bb1 - f2 - eb2 - bb2 - g1 - d2 - g1 - - -
    ,
        \\c5 eb5 g5 eb5 c5 g4 eb4 g4 f4 ab4 c5 ab4 f4 c4 f4 ab4 | bb4 d5 f5 d5 eb5 bb4 g4 eb4 d5 - - - - - - -
    ,
        \\c3 - eb3 - g3 - eb3 - f3 - ab3 - c4 - ab3 - | bb2 - d3 - eb3 - g3 - g2 - b2 - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - - - s - - -
    ),
    section(CINDER_TABLE_BPM,
        \\ab1 - eb2 - bb1 - f2 - c2 - g2 - g1 - d2 - | ab1 - bb1 - eb2 - - - eb2 - - - eb2 - - -
    ,
        \\ab4 c5 eb5 ab5 bb4 d5 f5 bb5 g5 eb5 c5 g4 d5 b4 g4 d4 | c5 eb5 d5 f5 eb5 - - - - - - - - - - -
    ,
        \\ab2 - c3 - bb2 - d3 - c3 - eb3 - g2 - b2 - | ab2 - bb2 - eb3 - g3 - - - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
    section(CINDER_TABLE_BPM,
        \\c2 - - - bb1 - - - ab1 - - - g1 - - - | f1 - - - g1 - - - c2 - - - - - - -
    ,
        \\g4 - c5 eb5 f4 - bb4 d5 eb4 - ab4 c5 d4 - g4 b4 | f4 - ab4 - g4 - b4 - c5 - - - - - - -
    ,
        \\c3 - eb3 - bb2 - d3 - ab2 - c3 - g2 - b2 - | f2 - ab2 - g2 - b2 - c3 - eb3 - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - - - h - - - s - - - h - - -
    ),
    section(CINDER_TABLE_BPM,
        \\ab1 - - - g1 - - - f1 - - - bb1 - - - | ab1 - bb1 - eb2 - - - eb2 - - - eb2 - - -
    ,
        \\c5 - eb5 - b4 - d5 - ab4 - c5 - d5 - bb4 - | c5 - d5 - eb5 - - - - - - - - - - -
    ,
        \\ab2 - c3 - g2 - b2 - f2 - ab2 - bb2 - d3 - | ab2 - bb2 - eb3 - g3 - - - - - - - - -
    ,
        \\k - - - h - - - s - - - h - - - | k - s - k - - - - - - - - - - -
    ),
    section(CINDER_TABLE_BPM,
        \\eb2 - bb2 - c2 - g2 - ab1 - eb2 - bb1 - f2 - | g1 - d2 - c2 - g2 - f1 - c2 - bb1 - f2 -
    ,
        \\eb5 - bb4 - c5 - g4 - ab4 - eb4 - bb4 - d5 - | g4 - d5 - c5 - eb5 - f4 - ab4 - bb4 - d5 -
    ,
        \\eb3 - - - c3 - - - ab2 - - - bb2 - - - | g2 - - - c3 - - - f2 - - - bb2 - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - h - s - h - k - s - k - h -
    ),
    section(CINDER_TABLE_BPM,
        \\c2 - g2 - ab1 - eb2 - bb1 - f2 - g1 - d2 - | ab1 - bb1 - eb2 - - - eb2 - - - - - - -
    ,
        \\c5 - eb5 - ab4 - c5 - bb4 - d5 - g4 - b4 - | c5 - d5 - eb5 - - - eb5 - - - - - - -
    ,
        \\c3 - - - ab2 - - - bb2 - - - g2 - - - | ab2 - - - eb3 - - - - - - - - - - -
    ,
        \\k - h - s - h - k - h - s - h - | k - - - s - - - k - - - - - - -
    ),
};

const CINDER_TABLE_ARRANGEMENT = order(
    \\a/ld a/l a a2 b b2 a a2 c/d c2 d d2 b b2 a-2 a2-2 c c2 d/l d2 a a2 b/d b2 c c2 d d2 a/d a2/lc
);

pub const cinder_table = Arranged{ .sections = &CINDER_TABLE_SECTIONS, .arrangement = &CINDER_TABLE_ARRANGEMENT };

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

/// Seconds an arranged track plays before its sound repeats exactly: the shortest period of
/// the full step stream (every part of every pass), times the step length. A cyclic stream
/// that is a smaller loop played several times reports that smaller loop.
pub fn seconds_before_repeat(allocator: std.mem.Allocator, a: Arranged) !f64 {
    const Step = [5]u8;
    var stream = std.array_list.Managed(Step).init(allocator);
    defer stream.deinit();
    var seconds_per_pass = std.array_list.Managed(f64).init(allocator);
    defer seconds_per_pass.deinit();
    const music = audio.Music{ .name = "", .sections = a.sections, .arrangement = a.arrangement };
    for (a.arrangement) |pass| {
        const p = audio.arranged_pattern(&music, pass);
        for (0..p.step_count) |i| {
            try stream.append(.{ p.bass_notes[i], p.lead_notes[i], p.chord_notes[i], p.drum_pattern[i], @intCast(p.bpm & 0xff) });
            try seconds_per_pass.append(60.0 / @as(f64, @floatFromInt(p.bpm)) / 4.0);
        }
    }
    const n = stream.items.len;
    var period: usize = 1;
    while (period <= n) : (period += 1) {
        if (n % period != 0) continue;
        var same = true;
        for (0..n) |i| {
            if (!std.mem.eql(u8, &stream.items[i], &stream.items[(i + period) % n])) {
                same = false;
                break;
            }
        }
        if (same) break;
    }
    var total: f64 = 0;
    for (seconds_per_pass.items[0..period]) |s| total += s;
    return total;
}

/// Every arranged track, for the length check.
pub const ALL = [_]Arranged{
    tavern, cellar, spitting_contest, tidewalk, fencing_yard, lantern, net_loft, harbour_office, wreckers_cellar, three_tides, bell_tower,
    living_village, lamp_point, caustic_grog, saltmarket, weathercock, fire_escape, observatory, valerius, lamplighter, long_gallery, word_foundry, cinder_table,
};

test "P34-08: every proof track plays at least two minutes before it repeats" {
    for (ALL) |a| {
        const seconds = try seconds_before_repeat(std.testing.allocator, a);
        try std.testing.expect(seconds >= 120.0);
    }
}

test "P34-08: section notation reads note names, accidentals, drums, and rests" {
    try std.testing.expectEqual(@as(u8, 60), comptime note_value("c4"));
    try std.testing.expectEqual(@as(u8, 61), comptime note_value("c#4"));
    try std.testing.expectEqual(@as(u8, 46), comptime note_value("bb2"));
    try std.testing.expectEqual(@as(u8, 47), comptime note_value("b2"));
    try std.testing.expectEqual(@as(u8, 0), comptime note_value("-"));
    try std.testing.expectEqual(@as(u8, 2), comptime note_value("s"));
    const p = comptime section(120, "c3 - | g2 -", "c5 d5 | e5 -", "- e4 | - g4", "k h | s h");
    try std.testing.expectEqual(@as(u8, 4), p.step_count);
    try std.testing.expectEqual(@as(u8, 43), p.bass_notes[2]);
    try std.testing.expectEqual(@as(u8, 0), p.bass_notes[4]);

    const passes = comptime order("a b2+5 d2-2/lc c/bd");
    try std.testing.expectEqual(@as(usize, 4), passes.len);
    try std.testing.expectEqual(@as(u8, 3), passes[1].section);
    try std.testing.expectEqual(@as(i8, 5), passes[1].transpose);
    try std.testing.expectEqual(@as(i8, -2), passes[2].transpose);
    try std.testing.expect(passes[2].mute.lead and passes[2].mute.chords and !passes[2].mute.drums);
    try std.testing.expect(passes[3].mute.bass and passes[3].mute.drums and passes[3].transpose == 0);
}
