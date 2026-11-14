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
    var out = [_]u8{0} ** audio.BGM_STEPS;
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
// The courtyard garden: a gentle stroll in F major, 104 bpm. B wanders through B flat and
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

pub const courtyard = Arranged{ .sections = &COURTYARD_SECTIONS, .arrangement = &COURTYARD_ARRANGEMENT };

// ---------------------------------------------------------------------------
// The bike shop: a breezy cafe cadence in G minor, 118 bpm. B swings into B flat, C is a
// musette with neighbour-note trills, D bounces like a bicycle bell. One B pass sits a fourth
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
    // D: a bicycle-bell bounce
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

pub const bike_shop = Arranged{ .sections = &BIKE_SHOP_SECTIONS, .arrangement = &BIKE_SHOP_ARRANGEMENT };

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

pub const lochmarne = Arranged{ .sections = &CASTLE_SECTIONS, .arrangement = &CASTLE_ARRANGEMENT };

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

pub const tentacle = Arranged{ .sections = &ERAS_SECTIONS, .arrangement = &ERAS_ARRANGEMENT };

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
// Checks
// ---------------------------------------------------------------------------

/// Seconds an arranged track plays before its sound repeats exactly: the shortest period of
/// the full step stream (every part of every pass), times the step length. A cyclic stream
/// that is a smaller loop played several times reports that smaller loop.
pub fn seconds_before_repeat(allocator: std.mem.Allocator, a: Arranged) !f64 {
    const Step = [5]u8;
    var stream = std.ArrayList(Step).init(allocator);
    defer stream.deinit();
    var seconds_per_pass = std.ArrayList(f64).init(allocator);
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
pub const ALL = [_]Arranged{ tavern, cellar, spitting_contest, tidewalk, fencing_yard, lantern, courtyard, bike_shop, lochmarne, tentacle, bell_tower };

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
