//! BeSpoke Engine: Peripheral Audio Subsystem & Procedural Sound Synthesizer (Phase 16, D-001, D-019)
//!
//! A pure Zig procedural audio engine providing chiptune synthesis, action sound effects,
//! and scene background musical accompaniment with zero external audio assets or codec dependencies.
//! Audio cues from the discrete simulation spine are consumed asynchronously through the decoupled AudioBridge.

const std = @import("std");
const testing = std.testing;
const mml = @import("mml.zig");

pub const SAMPLE_RATE: u32 = 44100;
pub const MAX_SFX_VOICES: usize = 8;
pub const MAX_AUDIO_EVENTS: usize = 64;

// ---------------------------------------------------------------------------
// 1. Precomputed MIDI Note to 32-bit Phase Increment Table (44.1 kHz)
// ---------------------------------------------------------------------------
// Borrowed from Whimsy Machine (D-019):
// phase_inc = (frequency * 2^32) / 44100
// A4 (note 69) = 440 Hz -> phase_inc = 42,852,281
pub const MIDI_PHASE_INC: [128]u32 = [_]u32{
    796254,     843601,     893765,     946911,     1003217,    1062871,    1126073,    1193033,
    1263974,    1339134,    1418763,    1503127,    1592507,    1687203,    1787529,    1893821,
    2006434,    2125742,    2252146,    2386065,    2527948,    2678268,    2837526,    3006254,
    3185015,    3374406,    3575058,    3787642,    4012867,    4251485,    4504291,    4772130,
    5055896,    5356535,    5675051,    6012507,    6370030,    6748811,    7150117,    7575285,
    8025735,    8502970,    9008582,    9544261,    10111792,   10713070,   11350103,   12025015,
    12740059,   13497623,   14300233,   15150569,   16051469,   17005939,   18017165,   19088521,
    20223584,   21426141,   22700205,   24050030,   25480119,   26995246,   28600467,   30301139,
    32102938,   34011878,   36034330,   38177043,   40447168,   42852281,   45400411,   48100060,
    50960238,   53990491,   57200933,   60602278,   64205876,   68023757,   72068660,   76354085,
    80894335,   85704563,   90800821,   96200119,   101920476,  107980983,  114401866,  121204555,
    128411753,  136047513,  144137319,  152708170,  161788671,  171409126,  181601643,  192400238,
    203840952,  215961966,  228803732,  242409110,  256823506,  272095026,  288274639,  305416341,
    323577341,  342818251,  363203285,  384800477,  407681904,  431923931,  457607465,  484818220,
    513647012,  544190053,  576549277,  610832681,  647154683,  685636503,  726406571,  769600953,
    815363807,  863847862,  915214929,  969636441,  1027294024, 1088380105, 1153098554, 1221665363,
};

pub inline fn midi_to_phase_inc(note: u8) u32 {
    const n = @min(note, 127);
    return MIDI_PHASE_INC[n];
}

// ---------------------------------------------------------------------------
// 2. Pure Integer Waveform Generators
// ---------------------------------------------------------------------------

/// Generates a pulse wave with configurable duty cycle threshold.
/// duty_threshold = 0x80000000 for 50% square, 0x40000000 for 25% pulse, 0x20000000 for 12.5% pulse.
pub inline fn eval_pulse(phase: u32, duty_threshold: u32) i16 {
    return if (phase < duty_threshold) 24000 else -24000;
}

/// Generates a linear symmetric triangle wave (-32768 to +32767).
pub inline fn eval_triangle(phase: u32) i16 {
    if (phase < 0x80000000) {
        const val: i32 = @intCast(phase >> 15);
        return @intCast(val - 32768);
    } else {
        const val: i32 = @intCast((phase - 0x80000000) >> 15);
        return @intCast(32767 - val);
    }
}

/// Generates a linear ascending sawtooth wave (-32768 to +32767).
pub inline fn eval_sawtooth(phase: u32) i16 {
    const val: i32 = @intCast(phase >> 16);
    return @intCast(val - 32768);
}

/// Evaluates one oscillator through a wave shape (pulse uses `duty`), widened for mixing.
pub inline fn eval_wave(shape: Wave, phase: u32, duty: u32) i32 {
    return switch (shape) {
        .pulse => eval_pulse(phase, duty),
        .triangle => eval_triangle(phase),
        .saw => eval_sawtooth(phase),
    };
}

/// Generates pseudo-random uniform white noise via 32-bit Linear Congruential Generator.
pub inline fn eval_noise(rng: *u32) i16 {
    rng.* = rng.* *% 1664525 +% 1013904223;
    const val: i32 = @intCast(rng.* >> 16);
    return @intCast(val - 32768);
}

// ---------------------------------------------------------------------------
// 3. Audio Kinds & Enums
// ---------------------------------------------------------------------------

/// The engine's own sounds: interface feedback and the distaff (P16-02, P22-02). A game adds
/// its own effects as `SfxPatch` data in its `Soundtrack` (P32-02d, D-040).
pub const SoundEffectKind = enum(u8) {
    footstep,
    pickup,
    combine,
    alert,
    dialogue_blip,
    click,
    distaff_note,
    weave_success,
    weave_fizzle,
};

/// MIDI pitches for the seven distaff notes, indexed by `draft.Note` value (C4 to B4).
/// Audio takes the raw degree (0 to 6) so the synthesizer stays free of simulation imports.
pub const DISTAFF_MIDI = [7]u8{ 60, 62, 64, 65, 67, 69, 71 };
pub const DISTAFF_NOTE_COUNT: u8 = DISTAFF_MIDI.len;

/// A sound to play: one of the engine's, or an index into the host soundtrack's `sfx`.
pub const Sound = union(enum) {
    stock: SoundEffectKind,
    host: u8,
};

pub const Wave = enum { pulse, triangle, saw };

/// One addend of a voice's sample. `osc1` and `osc2` read that oscillator through `shape`
/// (pulse uses the voice's duty); `noise` is the shared noise generator, read once per sample
/// however many terms use it; `ring` multiplies `osc1` through `shape` by `osc2` through
/// `shape2` and scales by 2^-15.
pub const Term = struct {
    source: enum { osc1, osc2, noise, ring },
    shape: Wave = .triangle,
    shape2: Wave = .triangle,
    weight: i32 = 1,
};

/// How the summed terms are scaled: an arithmetic shift (floors) or a truncating divide.
pub const Mix = union(enum) {
    shift: u5,
    div: i32,
};

/// A note change during a sound: oscillator 1 jumps to `note` (and the duty, if set) when the
/// previous note's samples run out.
pub const NoteStep = struct {
    note: u8,
    duty: ?u32 = null,
    samples: u32 = 0,
};

/// A sound effect as data (P32-02d, D-040). Two oscillators start at `note1` and `note2`
/// (MIDI; no `note2` leaves oscillator 2 still). Oscillator 1 glides by `sweep` phase units a
/// sample. The envelope starts at `env` (0..32767) and falls by `decay` a sample for at most
/// `samples` samples. After `step_samples` samples, `steps` are applied in order, each lasting
/// its own `samples`; `loop` repeats them for as long as the sound lasts.
pub const SfxPatch = struct {
    note1: u8,
    note2: ?u8 = null,
    terms: []const Term,
    mix: Mix = .{ .shift = 0 },
    duty: u32 = 0x80000000,
    sweep: i32 = 0,
    env: i32,
    decay: i32,
    samples: u32,
    step_samples: u32 = 0,
    steps: []const NoteStep = &.{},
    loop: bool = false,
};

/// A named music track for a soundtrack: a grid pattern, an arranged set of grid sections
/// (P34-08, D-089), or an MML score (P28-02, D-061). When `score` is set it plays and the grid
/// fields are ignored; otherwise a non-empty `arrangement` plays and `pattern` is ignored.
pub const Music = struct {
    name: []const u8,
    pattern: BgmPattern = SILENT_PATTERN,
    score: ?*const MmlScore = null,
    /// The track's grid sections, referred to by index from `arrangement`.
    sections: []const BgmPattern = &.{},
    /// The order the sections play in, one pass each; after the last entry it starts over.
    arrangement: []const SectionPlay = &.{},
};

/// The grid parts an arrangement pass can silence.
pub const PartMask = struct {
    bass: bool = false,
    lead: bool = false,
    chords: bool = false,
    drums: bool = false,
};

/// One pass of a section in an arrangement (P34-08, D-089). A few written sections replayed
/// in a new key or with parts dropped give a track minutes of material before it repeats.
pub const SectionPlay = struct {
    section: u8,
    /// Semitones added to every bass, lead, and chord note; drums are unpitched.
    transpose: i8 = 0,
    mute: PartMask = .{},
};

/// The pattern one arrangement pass plays: the section with its notes transposed and its
/// muted parts emptied. An index past `sections` plays silence rather than reading out of
/// bounds; a note shifted outside MIDI 1 to 127 rests, since 0 already means rest.
pub fn arranged_pattern(music: *const Music, pass: SectionPlay) BgmPattern {
    if (pass.section >= music.sections.len) return SILENT_PATTERN;
    var p = music.sections[pass.section];
    for (0..BGM_STEPS) |i| {
        p.bass_notes[i] = if (pass.mute.bass) 0 else shift_note(p.bass_notes[i], pass.transpose);
        p.lead_notes[i] = if (pass.mute.lead) 0 else shift_note(p.lead_notes[i], pass.transpose);
        p.chord_notes[i] = if (pass.mute.chords) 0 else shift_note(p.chord_notes[i], pass.transpose);
        if (pass.mute.drums) p.drum_pattern[i] = 0;
    }
    return p;
}

fn shift_note(note: u8, semitones: i8) u8 {
    if (note == 0) return 0;
    const shifted = @as(i16, note) + semitones;
    return if (shifted < 1 or shifted > 127) 0 else @intCast(shifted);
}

/// A game's sounds, registered with `AudioBridge.set_soundtrack` (or a display `Theme`).
/// Tracks and effects are referred to by index. Borrowed: the soundtrack must outlive the
/// bridge, and the audio thread reads it, so it must not change once registered.
pub const Soundtrack = struct {
    tracks: []const Music = &.{},
    sfx: []const SfxPatch = &.{},
    /// The track to play in a scene, or null for silence. Called on the host thread.
    track_for_scene: ?*const fn (scene_name: []const u8) ?u8 = null,
};

fn osc_term(source: @TypeOf(@as(Term, undefined).source), shape: Wave, weight: i32) Term {
    return .{ .source = source, .shape = shape, .weight = weight };
}

/// The engine's own effects, indexed by `SoundEffectKind`.
pub const STOCK_SFX = blk: {
    var t: [std.meta.fields(SoundEffectKind).len]SfxPatch = undefined;
    // Quick crisp noise burst with subtle bass tap
    t[@intFromEnum(SoundEffectKind.footstep)] = .{ .note1 = 36, .sweep = -120, .env = 26000, .decay = 26, .samples = 1000, .terms = &.{ .{ .source = .noise, .weight = 3 }, osc_term(.osc1, .triangle, 1) }, .mix = .{ .shift = 2 } };
    // Rising two-tone chime (note 64, then 71 at 50% duty)
    t[@intFromEnum(SoundEffectKind.pickup)] = .{ .note1 = 64, .duty = 0x40000000, .env = 28000, .decay = 8, .samples = 5000, .step_samples = 1800, .steps = &.{.{ .note = 71, .duty = 0x80000000 }}, .terms = &.{osc_term(.osc1, .pulse, 1)} };
    // Four-step arpeggio 60, 64, 67, 72
    t[@intFromEnum(SoundEffectKind.combine)] = .{ .note1 = 60, .duty = 0x40000000, .env = 30000, .decay = 6, .samples = 9000, .step_samples = 1500, .steps = &.{ .{ .note = 64, .samples = 1500 }, .{ .note = 67, .samples = 1500 }, .{ .note = 72, .samples = 1500 } }, .terms = &.{ osc_term(.osc1, .pulse, 1), osc_term(.osc1, .triangle, 1) }, .mix = .{ .shift = 1 } };
    // Dual detuned saw alarm
    t[@intFromEnum(SoundEffectKind.alert)] = .{ .note1 = 50, .note2 = 56, .env = 31000, .decay = 4, .samples = 7500, .terms = &.{ osc_term(.osc1, .saw, 1), osc_term(.osc2, .saw, 1) }, .mix = .{ .shift = 1 } };
    // Short falling square blip
    t[@intFromEnum(SoundEffectKind.dialogue_blip)] = .{ .note1 = 62, .sweep = -1200, .env = 20000, .decay = 25, .samples = 800, .terms = &.{osc_term(.osc1, .pulse, 1)} };
    // Tiny triangle tick
    t[@intFromEnum(SoundEffectKind.click)] = .{ .note1 = 76, .env = 18000, .decay = 50, .samples = 360, .terms = &.{osc_term(.osc1, .triangle, 1)} };
    // Sustained plucked-string tone; trigger_note sets the pitch (P22-02, D-029)
    t[@intFromEnum(SoundEffectKind.distaff_note)] = .{ .note1 = DISTAFF_MIDI[0], .note2 = DISTAFF_MIDI[0] + 12, .duty = 0x40000000, .env = 26000, .decay = 2, .samples = 13000, .terms = &.{ osc_term(.osc1, .triangle, 3), osc_term(.osc2, .pulse, 1) }, .mix = .{ .shift = 2 } };
    // Rising open fifth shimmer (C5 + G5) as a draft takes hold
    t[@intFromEnum(SoundEffectKind.weave_success)] = .{ .note1 = 72, .note2 = 79, .sweep = 40, .env = 28000, .decay = 2, .samples = 14000, .terms = &.{ osc_term(.osc1, .triangle, 1), osc_term(.osc2, .triangle, 1) }, .mix = .{ .shift = 1 } };
    // Falling detuned buzz as an unmatched draft unravels
    t[@intFromEnum(SoundEffectKind.weave_fizzle)] = .{ .note1 = 55, .note2 = 56, .sweep = -900, .env = 24000, .decay = 4, .samples = 6000, .terms = &.{ osc_term(.osc1, .saw, 1), osc_term(.osc2, .saw, 1), .{ .source = .noise } }, .mix = .{ .shift = 2 } };
    break :blk t;
};

/// Decoupled audio event queued by simulation or GUI and consumed by audio thread.
pub const AudioEvent = union(enum) {
    play_sfx: SoundEffectKind,
    play_host_sfx: u8,
    /// A distaff note by diatonic degree (0 = C .. 6 = B). Out-of-range degrees are dropped.
    play_note: u8,
    set_bgm: ?u8,
    set_soundtrack: ?*const Soundtrack,
    stop_bgm: void,
    set_master_volume: u8,
    set_sfx_volume: u8,
    set_bgm_volume: u8,
};

// ---------------------------------------------------------------------------
// 4. Procedural SFX Voice
// ---------------------------------------------------------------------------

pub const SfxVoice = struct {
    patch: *const SfxPatch = &STOCK_SFX[@intFromEnum(SoundEffectKind.click)],
    active: bool = false,
    phase1: u32 = 0,
    phase_inc1: u32 = 0,
    phase2: u32 = 0,
    phase_inc2: u32 = 0,
    duty: u32 = 0x80000000,
    pitch_sweep: i32 = 0,
    env_level: i32 = 0, // Q15: 0..32767
    env_decay: i32 = 0, // Decay subtracted per sample
    samples_left: u32 = 0,
    /// Index of the next `patch.steps` entry.
    step: u8 = 0,
    step_samples_left: u32 = 0,
    volume: u8 = 100, // 0..100
};

// ---------------------------------------------------------------------------
// 5. Procedural BGM Step Sequencer
// ---------------------------------------------------------------------------

pub const BGM_STEPS: usize = 32;

pub const BgmPattern = struct {
    bpm: u16,
    step_count: u8,
    bass_notes: [BGM_STEPS]u8,
    lead_notes: [BGM_STEPS]u8,
    chord_notes: [BGM_STEPS]u8,
    drum_pattern: [BGM_STEPS]u8, // 0 = rest, 1 = kick, 2 = snare, 3 = hat
};

/// A pattern that triggers nothing: an unknown track, no track, or an MML-only `Music`.
pub const SILENT_PATTERN = BgmPattern{
    .bpm = 120,
    .step_count = 32,
    .bass_notes = [_]u8{0} ** BGM_STEPS,
    .lead_notes = [_]u8{0} ** BGM_STEPS,
    .chord_notes = [_]u8{0} ** BGM_STEPS,
    .drum_pattern = [_]u8{0} ** BGM_STEPS,
};

// ---------------------------------------------------------------------------
// 5b. MML Score Playback (P28-02, D-061)
// ---------------------------------------------------------------------------

/// The four parts of an MML score, in the order they are processed each tick. Lead, bass, and
/// chords play the grid sequencer's lead, bass, and chord voices; percussion plays its drums.
pub const MmlPart = enum(u8) { lead, bass, chords, percussion };
pub const MML_PART_COUNT: usize = 4;

/// One part's events, borrowed from an `mml.Score` or static data.
pub const MmlTrack = struct {
    events: []const mml.Event = &.{},
    loop_start: ?usize = null,

    pub fn of(score: *const mml.Score) MmlTrack {
        return .{ .events = score.events, .loop_start = score.loop_start };
    }
};

/// A four-part MML score. Borrowed like a `Soundtrack`: the audio thread reads it, so it must
/// outlive the bridge and must not change once registered.
pub const MmlScore = struct {
    parts: [MML_PART_COUNT]MmlTrack = [_]MmlTrack{.{}} ** MML_PART_COUNT,

    pub fn part(self: *const MmlScore, which: MmlPart) MmlTrack {
        return self.parts[@intFromEnum(which)];
    }
};

/// An `@n` envelope (D-061). Levels are in the voice's envelope units; `sustain` is in 256ths
/// of the note's peak. `decay = null` uses the grid voice's own decay, and `release = 0` lets
/// the note ring past its written length, as grid notes do.
pub const Envelope = struct {
    attack: i32 = 0,
    decay: ?i32 = null,
    sustain: i32 = 0,
    release: i32 = 0,
    tremolo: bool = false,
};

pub const ENVELOPES = [mml.MAX_ENVELOPE + 1]Envelope{
    .{}, // @0 grid: the voice's own fixed decay, no note-off
    .{ .decay = 0, .sustain = 256, .release = 40 }, // @1 organ: hold, release at note end
    .{ .decay = 12, .release = 40 }, // @2 pluck
    .{ .decay = 1, .release = 2 }, // @3 long fade
    .{ .attack = 3, .decay = 0, .sustain = 256, .release = 6 }, // @4 swell
    .{ .decay = 30, .release = 120 }, // @5 staccato
    .{ .decay = 0, .sustain = 256, .release = 40, .tremolo = true }, // @6 tremolo
    .{ .attack = 1, .decay = 2, .sustain = 180, .release = 3 }, // @7 soft pad
};

/// Peak envelope and grid decay of the lead, bass, and chord voices, as the grid sequencer
/// sets them, so `@0` sounds like a grid note.
const MML_VOICE_PEAK = [3]i32{ 28000, 30000, 22000 };
const MML_VOICE_DECAY = [3]i32{ 4, 6, 3 };
/// About 6 Hz at 44.1 kHz.
const MML_TREMOLO_INC: u32 = 584337;

const EnvStage = enum { off, attack, decay, sustain, release };

pub const MmlPartState = struct {
    /// Next event to read.
    index: usize = 0,
    /// Ticks left in the current note, rest, or hit.
    wait: u32 = 0,
    /// Read past the last event; waits for the whole-score loop.
    finished: bool = true,
    volume: u8 = @intCast(mml.MAX_VOLUME),
    envelope: u8 = 0,
    stage: EnvStage = .off,
    level: i32 = 0,
    peak: i32 = 0,
    notes_started: u32 = 0,
};

/// Playback state of the current MML track. Time is integer: the clock gains `tempo * 48`
/// each sample and spends `sample_rate * 60` per tick, so a tick lasts exactly
/// `60 / (tempo * 48)` seconds on average and four parts can never drift apart.
pub const MmlState = struct {
    score: ?*const MmlScore = null,
    parts: [MML_PART_COUNT]MmlPartState = [_]MmlPartState{.{}} ** MML_PART_COUNT,
    /// One tempo for every part (D-061): a `t` in any part sets it for all.
    tempo: u16 = mml.DEFAULT_TEMPO,
    clock: u32 = 0,
    ticks: u64 = 0,
    lfo_phase: u32 = 0,
};

/// Generates pre-authored 32-step procedural score patterns for narrative locations (P16-03).

// ---------------------------------------------------------------------------
// 6. Complete Procedural Chiptune Synthesizer Engine
// ---------------------------------------------------------------------------

pub const ChiptuneSynth = struct {
    sample_rate: u32 = SAMPLE_RATE,
    rng_state: u32 = 0x811c9dc5,

    // SFX Voice Pool
    sfx_voices: [MAX_SFX_VOICES]SfxVoice = [_]SfxVoice{.{}} ** MAX_SFX_VOICES,

    // BGM Sequencer State
    /// Read by the audio thread; replaced only through `AudioEvent.set_soundtrack`.
    soundtrack: ?*const Soundtrack = null,
    current_track: ?u8 = null,
    target_track: ?u8 = null,
    active_pattern: BgmPattern = std.mem.zeroes(BgmPattern),
    current_step: usize = 0,
    /// The arrangement entry playing, for a track with sections (D-089).
    arrangement_pos: usize = 0,
    samples_per_step: u32 = 5512,
    step_sample_counter: u32 = 0,

    // BGM Channels
    bass_phase: u32 = 0,
    bass_phase_inc: u32 = 0,
    bass_env: i32 = 0,

    lead_phase: u32 = 0,
    lead_phase_inc: u32 = 0,
    lead_env: i32 = 0,
    lead_vibrato_phase: u32 = 0,

    chord_phase: u32 = 0,
    chord_phase_inc: u32 = 0,
    chord_env: i32 = 0,

    kick_phase: u32 = 0,
    kick_phase_inc: u32 = 0,
    kick_env: i32 = 0,

    snare_phase: u32 = 0,
    snare_phase_inc: u32 = 0,
    snare_env: i32 = 0,

    hat_env: i32 = 0,

    /// MML playback (P28-02); `mml.score` is null while a grid pattern or nothing plays.
    mml: MmlState = .{},

    // Track Crossfade
    fade_level: i32 = 32767, // 0..32767
    is_fading_out: bool = false,

    pub fn init() ChiptuneSynth {
        var synth = ChiptuneSynth{};
        synth.set_track(null);
        return synth;
    }

    /// Sets or changes the active background music track (P16-03).
    pub fn set_track(self: *ChiptuneSynth, track: ?u8) void {
        if (self.current_track == track) return;

        if (self.current_track == null) {
            // Immediate start
            self.current_track = track;
            self.target_track = track;
            self.start_track(track);
            self.fade_level = 32767;
            self.is_fading_out = false;
        } else {
            // Begin fast crossfade
            self.target_track = track;
            self.is_fading_out = true;
        }
    }

    /// Starts a track from its first step and, when it is arranged, its first section.
    fn start_track(self: *ChiptuneSynth, track: ?u8) void {
        self.arrangement_pos = 0;
        self.load_pattern(self.pattern_of(track));
        self.start_mml(track);
        self.current_step = 0;
        self.step_sample_counter = 0;
    }

    fn load_pattern(self: *ChiptuneSynth, pattern: BgmPattern) void {
        self.active_pattern = pattern;
        if (pattern.bpm > 0) {
            // 1 step = 1 sixteenth note = (60 / bpm / 4) seconds
            const step_sec = (60.0 / @as(f64, @floatFromInt(pattern.bpm))) / 4.0;
            self.samples_per_step = @intFromFloat(step_sec * @as(f64, @floatFromInt(self.sample_rate)));
        }
    }

    /// The pattern a track plays now: its arrangement entry at `arrangement_pos`, else its one
    /// pattern; an unknown index or null is silence at 120 bpm.
    fn pattern_of(self: *const ChiptuneSynth, track: ?u8) BgmPattern {
        const music = self.music_of(track) orelse return SILENT_PATTERN;
        if (music.arrangement.len == 0) return music.pattern;
        return arranged_pattern(music, music.arrangement[self.arrangement_pos % music.arrangement.len]);
    }

    /// At the end of a section, moves an arranged track to its next entry, wrapping after the
    /// last. A track with one pattern replays it.
    fn next_section(self: *ChiptuneSynth) void {
        const music = self.music_of(self.current_track) orelse return;
        if (music.arrangement.len == 0) return;
        self.arrangement_pos = (self.arrangement_pos + 1) % music.arrangement.len;
        self.load_pattern(self.pattern_of(self.current_track));
    }

    fn music_of(self: *const ChiptuneSynth, track: ?u8) ?*const Music {
        const index = track orelse return null;
        const st = self.soundtrack orelse return null;
        if (index >= st.tracks.len) return null;
        return &st.tracks[index];
    }

    /// Starts the track's MML score from its first event, or stops MML when it has none.
    fn start_mml(self: *ChiptuneSynth, track: ?u8) void {
        self.mml = .{};
        const music = self.music_of(track) orelse return;
        const score = music.score orelse return;
        self.mml.score = score;
        for (&self.mml.parts) |*p| p.finished = false;
        self.mml_advance(score);
    }

    /// One tick: count down every part, release notes whose written length ended, read the
    /// next events, and loop the whole score once every part has finished (D-061).
    fn mml_tick(self: *ChiptuneSynth) void {
        const score = self.mml.score orelse return;
        self.mml.ticks += 1;
        for (&self.mml.parts) |*p| {
            if (p.finished or p.wait == 0) continue;
            p.wait -= 1;
            if (p.wait == 0) mml_note_off(p);
        }
        self.mml_advance(score);
    }

    fn mml_advance(self: *ChiptuneSynth, score: *const MmlScore) void {
        for (0..MML_PART_COUNT) |i| self.mml_advance_part(score, i);
        for (self.mml.parts) |p| if (!p.finished) return;
        // Every part has ended: looping parts restart at their own L together, so parts of
        // different lengths re-align each pass; parts without L stay silent. A restart happens
        // at most once per tick, so even a hand-built loop with no duration cannot spin here.
        var looped = false;
        for (&self.mml.parts, 0..) |*p, i| {
            const track = score.parts[i];
            const start = track.loop_start orelse continue;
            if (start >= track.events.len) continue;
            p.index = start;
            p.finished = false;
            looped = true;
        }
        if (looped) {
            for (0..MML_PART_COUNT) |i| self.mml_advance_part(score, i);
        }
    }

    /// Reads a part's zero-time events up to and including its next note, rest, or hit.
    fn mml_advance_part(self: *ChiptuneSynth, score: *const MmlScore, i: usize) void {
        const p = &self.mml.parts[i];
        if (p.finished or p.wait > 0) return;
        const events = score.parts[i].events;
        const percussion = i == @intFromEnum(MmlPart.percussion);
        while (p.index < events.len) {
            const e = events[p.index];
            p.index += 1;
            // Values are clamped, not trusted: a score may be built by hand rather than parsed.
            switch (e) {
                .tempo => |bpm| self.mml.tempo = std.math.clamp(bpm, @as(u16, mml.MIN_TEMPO), @as(u16, mml.MAX_TEMPO)),
                .volume => |v| p.volume = @min(v, @as(u8, mml.MAX_VOLUME)),
                .envelope => |n| p.envelope = @min(n, @as(u8, ENVELOPES.len - 1)),
                .note => |n| {
                    if (!percussion) self.mml_note_on(i, n.midi);
                    p.wait = n.ticks;
                },
                .rest => |t| p.wait = t,
                .hit => |h| {
                    if (percussion) self.mml_hit(h.drum, p.volume);
                    p.wait = h.ticks;
                },
            }
            if (p.wait > 0) return;
        }
        p.finished = true;
    }

    fn mml_note_on(self: *ChiptuneSynth, i: usize, midi: u8) void {
        const p = &self.mml.parts[i];
        const inc = midi_to_phase_inc(@min(midi, 127));
        switch (i) {
            0 => self.lead_phase_inc = inc,
            1 => self.bass_phase_inc = inc,
            else => self.chord_phase_inc = inc,
        }
        const env = ENVELOPES[p.envelope];
        p.peak = @divTrunc(MML_VOICE_PEAK[i] * @as(i32, p.volume), @as(i32, mml.MAX_VOLUME));
        if (env.attack > 0) {
            p.level = 0;
            p.stage = .attack;
        } else {
            p.level = p.peak;
            p.stage = .decay;
        }
        p.notes_started += 1;
    }

    fn mml_note_off(p: *MmlPartState) void {
        if (p.stage == .off) return;
        if (ENVELOPES[p.envelope].release > 0) p.stage = .release;
    }

    /// The grid sequencer's drums at the part's volume; envelopes do not apply to drums.
    fn mml_hit(self: *ChiptuneSynth, drum: mml.Drum, volume: u8) void {
        const v: i32 = volume;
        const full: i32 = mml.MAX_VOLUME;
        switch (drum) {
            .kick => {
                self.kick_phase_inc = midi_to_phase_inc(36) * 2;
                self.kick_env = @divTrunc(32000 * v, full);
            },
            .snare => {
                self.snare_phase_inc = midi_to_phase_inc(48);
                self.snare_env = @divTrunc(30000 * v, full);
            },
            .hat => self.hat_env = @divTrunc(24000 * v, full),
        }
        self.mml.parts[@intFromEnum(MmlPart.percussion)].notes_started += 1;
    }

    /// Advances the MML clock by one sample, running every tick that falls due.
    fn mml_clock_step(self: *ChiptuneSynth) void {
        self.mml.clock += @as(u32, self.mml.tempo) * (mml.TICKS_PER_WHOLE / 4);
        const per_tick = self.sample_rate * 60;
        while (self.mml.clock >= per_tick) {
            self.mml.clock -= per_tick;
            self.mml_tick();
        }
    }

    /// Steps each melodic part's envelope one sample and hands the level to its grid voice,
    /// which then synthesizes exactly as for a grid note. The voice's own per-sample decay is
    /// overwritten here every sample, so it never acts on an MML note.
    fn mml_apply_envelopes(self: *ChiptuneSynth) void {
        self.mml.lfo_phase +%= MML_TREMOLO_INC;
        const lfo: i32 = eval_triangle(self.mml.lfo_phase);
        for (0..3) |i| {
            const p = &self.mml.parts[i];
            const env = ENVELOPES[p.envelope];
            switch (p.stage) {
                .off => p.level = 0,
                .attack => {
                    p.level += env.attack;
                    if (p.level >= p.peak) {
                        p.level = p.peak;
                        p.stage = .decay;
                    }
                },
                .decay => {
                    const floor = @divTrunc(p.peak * env.sustain, 256);
                    p.level -= env.decay orelse MML_VOICE_DECAY[i];
                    if (p.level <= floor) {
                        p.level = floor;
                        p.stage = if (floor > 0) .sustain else .off;
                    }
                },
                .sustain => {},
                .release => {
                    p.level -= env.release;
                    if (p.level <= 0) {
                        p.level = 0;
                        p.stage = .off;
                    }
                },
            }
            // Tremolo swings between half and full level.
            const out = if (env.tremolo) (p.level * (24576 + (lfo >> 2))) >> 15 else p.level;
            switch (i) {
                0 => self.lead_env = out,
                1 => self.bass_env = out,
                else => self.chord_env = out,
            }
        }
    }

    /// Plays one distaff note (P22-02). Degrees outside 0..6 come from an untrusted caller
    /// (host input or a wasm export) and are ignored rather than clamped to a wrong pitch.
    pub fn trigger_note(self: *ChiptuneSynth, degree: u8) void {
        if (degree >= DISTAFF_NOTE_COUNT) return;
        const v = self.trigger_sfx_voice(.distaff_note);
        const midi = DISTAFF_MIDI[degree];
        v.phase_inc1 = midi_to_phase_inc(midi);
        v.phase_inc2 = midi_to_phase_inc(midi + 12);
    }

    /// Triggers one of the engine's sound effects in an available voice slot (P16-02).
    pub fn trigger_sfx(self: *ChiptuneSynth, kind: SoundEffectKind) void {
        _ = self.trigger_sfx_voice(kind);
    }

    /// Triggers effect `index` of the registered soundtrack; an unknown index is ignored.
    pub fn trigger_host_sfx(self: *ChiptuneSynth, index: u8) void {
        const st = self.soundtrack orelse return;
        if (index >= st.sfx.len) return;
        _ = self.trigger_patch(&st.sfx[index]);
    }

    fn trigger_sfx_voice(self: *ChiptuneSynth, kind: SoundEffectKind) *SfxVoice {
        return self.trigger_patch(&STOCK_SFX[@intFromEnum(kind)]);
    }

    /// Starts `patch` in a free voice, or steals the quietest one (P32-02d, D-040).
    pub fn trigger_patch(self: *ChiptuneSynth, patch: *const SfxPatch) *SfxVoice {
        var slot: usize = 0;
        var lowest_env: i32 = 32768;
        for (self.sfx_voices, 0..) |voice, i| {
            if (!voice.active) {
                slot = i;
                break;
            }
            if (voice.env_level < lowest_env) {
                lowest_env = voice.env_level;
                slot = i;
            }
        }

        const v = &self.sfx_voices[slot];
        v.* = SfxVoice{
            .patch = patch,
            .active = true,
            .phase_inc1 = midi_to_phase_inc(patch.note1),
            .phase_inc2 = if (patch.note2) |n| midi_to_phase_inc(n) else 0,
            .duty = patch.duty,
            .pitch_sweep = patch.sweep,
            .env_level = patch.env,
            .env_decay = patch.decay,
            .samples_left = patch.samples,
            .step_samples_left = patch.step_samples,
            .volume = 100,
        };
        return v;
    }

    /// One sample of a voice before its envelope: note steps first, then the patch's terms.
    fn voice_sample(self: *ChiptuneSynth, v: *SfxVoice) i32 {
        const p = v.patch;
        if (p.steps.len > 0) {
            if (v.step_samples_left == 0 and (v.step < p.steps.len or p.loop)) {
                const st = p.steps[v.step];
                v.phase_inc1 = midi_to_phase_inc(st.note);
                if (st.duty) |d| v.duty = d;
                v.step_samples_left = st.samples;
                v.step = if (p.loop) @intCast((v.step + 1) % p.steps.len) else v.step + 1;
            } else if (v.step_samples_left > 0) {
                v.step_samples_left -= 1;
            }
        }

        // Noise advances the shared generator, so it is drawn at most once per voice sample.
        var noise: ?i32 = null;
        var sum: i32 = 0;
        for (p.terms) |t| {
            const value: i32 = switch (t.source) {
                .osc1 => eval_wave(t.shape, v.phase1, v.duty),
                .osc2 => eval_wave(t.shape, v.phase2, v.duty),
                .noise => noise orelse blk: {
                    const n: i32 = eval_noise(&self.rng_state);
                    noise = n;
                    break :blk n;
                },
                .ring => (eval_wave(t.shape, v.phase1, v.duty) * eval_wave(t.shape2, v.phase2, v.duty)) >> 15,
            };
            sum += value * t.weight;
        }
        return switch (p.mix) {
            .shift => |n| sum >> n,
            .div => |d| @divTrunc(sum, d),
        };
    }

    /// Renders stereo 16-bit PCM samples into output buffer (interleaved L, R, L, R...).
    pub fn render_stereo(
        self: *ChiptuneSynth,
        buffer: []i16,
        master_vol: u8,
        sfx_vol: u8,
        bgm_vol: u8,
    ) void {
        const frame_count = buffer.len / 2;

        for (0..frame_count) |f| {
            // 1. Advance BGM Step Sequencer (an MML track runs its own clock instead)
            if (self.current_track != null and self.mml.score == null) {
                self.step_sample_counter += 1;
                if (self.step_sample_counter >= self.samples_per_step) {
                    self.step_sample_counter = 0;
                    self.current_step = (self.current_step + 1) % self.active_pattern.step_count;
                    if (self.current_step == 0) self.next_section();

                    // Trigger new step notes
                    const step = self.current_step;
                    const b_note = self.active_pattern.bass_notes[step];
                    if (b_note > 0) {
                        self.bass_phase_inc = midi_to_phase_inc(b_note);
                        self.bass_env = 30000;
                    }

                    const l_note = self.active_pattern.lead_notes[step];
                    if (l_note > 0) {
                        self.lead_phase_inc = midi_to_phase_inc(l_note);
                        self.lead_env = 28000;
                    }

                    const c_note = self.active_pattern.chord_notes[step];
                    if (c_note > 0) {
                        self.chord_phase_inc = midi_to_phase_inc(c_note);
                        self.chord_env = 22000;
                    }

                    const d_hit = self.active_pattern.drum_pattern[step];
                    if (d_hit == 1) {
                        // Kick
                        self.kick_phase_inc = midi_to_phase_inc(36) * 2;
                        self.kick_env = 32000;
                    } else if (d_hit == 2) {
                        // Snare
                        self.snare_phase_inc = midi_to_phase_inc(48);
                        self.snare_env = 30000;
                    } else if (d_hit == 3) {
                        // Hat
                        self.hat_env = 24000;
                    }
                }
            }

            // Track crossfade handling
            if (self.is_fading_out) {
                self.fade_level -= 32;
                if (self.fade_level <= 0) {
                    self.fade_level = 0;
                    self.is_fading_out = false;
                    self.current_track = self.target_track;
                    self.start_track(self.target_track);
                }
            } else if (self.fade_level < 32767) {
                self.fade_level += 32;
                if (self.fade_level > 32767) self.fade_level = 32767;
            }

            if (self.mml.score != null) {
                self.mml_clock_step();
                self.mml_apply_envelopes();
            }

            // 2. Synthesize BGM Channels
            var bgm_sample: i32 = 0;

            if (self.current_track != null and self.fade_level > 0) {
                // Bass (Triangle)
                if (self.bass_env > 0) {
                    const raw = eval_triangle(self.bass_phase);
                    bgm_sample += (@as(i32, raw) * (self.bass_env >> 8)) >> 8;
                    self.bass_phase +%= self.bass_phase_inc;
                    self.bass_env -= 6;
                    if (self.bass_env < 0) self.bass_env = 0;
                }

                // Lead (Pulse 25% with vibrato LFO)
                if (self.lead_env > 0) {
                    self.lead_vibrato_phase +%= 12000000; // ~5.5 Hz vibrato
                    const vib = eval_triangle(self.lead_vibrato_phase);
                    const delta: i32 = @divTrunc(@as(i32, vib), 80);
                    const mod_inc: u32 = @intCast(@max(0, @as(i32, @intCast(self.lead_phase_inc)) + delta));
                    const raw = eval_pulse(self.lead_phase, 0x40000000);
                    bgm_sample += (@as(i32, raw) * (self.lead_env >> 8)) >> 8;
                    self.lead_phase +%= mod_inc;
                    self.lead_env -= 4;
                    if (self.lead_env < 0) self.lead_env = 0;
                }

                // Chord (Warm dual saw/triangle pad)
                if (self.chord_env > 0) {
                    const raw_tri = eval_triangle(self.chord_phase);
                    const raw_saw = eval_sawtooth(self.chord_phase);
                    const raw = (@as(i32, raw_tri) + @as(i32, raw_saw)) >> 1;
                    bgm_sample += (raw * (self.chord_env >> 8)) >> 9;
                    self.chord_phase +%= self.chord_phase_inc;
                    self.chord_env -= 3;
                    if (self.chord_env < 0) self.chord_env = 0;
                }

                // Percussion - Kick
                if (self.kick_env > 0) {
                    const raw = eval_triangle(self.kick_phase);
                    bgm_sample += (@as(i32, raw) * (self.kick_env >> 8)) >> 7;
                    self.kick_phase +%= self.kick_phase_inc;
                    if (self.kick_phase_inc > 150000) {
                        self.kick_phase_inc -= (self.kick_phase_inc >> 6);
                    }
                    self.kick_env -= 35;
                    if (self.kick_env < 0) self.kick_env = 0;
                }

                // Percussion - Snare
                if (self.snare_env > 0) {
                    const noise = eval_noise(&self.rng_state);
                    const tone = eval_triangle(self.snare_phase);
                    const raw = (@as(i32, noise) * 3 + @as(i32, tone)) >> 2;
                    bgm_sample += (raw * (self.snare_env >> 8)) >> 7;
                    self.snare_phase +%= self.snare_phase_inc;
                    self.snare_env -= 40;
                    if (self.snare_env < 0) self.snare_env = 0;
                }

                // Percussion - Hat
                if (self.hat_env > 0) {
                    const noise = eval_noise(&self.rng_state);
                    bgm_sample += (@as(i32, noise) * (self.hat_env >> 8)) >> 8;
                    self.hat_env -= 70;
                    if (self.hat_env < 0) self.hat_env = 0;
                }

                // Apply crossfade level
                bgm_sample = (bgm_sample * self.fade_level) >> 15;
            }

            // 3. Synthesize Active SFX Voices
            var sfx_sample: i32 = 0;

            for (&self.sfx_voices) |*v| {
                if (!v.active or v.env_level <= 0 or v.samples_left == 0) {
                    v.active = false;
                    continue;
                }

                const voice_out = self.voice_sample(v);

                // Envelope and volume scaling
                const amp = @divTrunc((v.env_level >> 8) * @as(i32, v.volume), 100);
                sfx_sample += (voice_out * amp) >> 8;

                // Step voice parameters
                v.phase1 +%= v.phase_inc1;
                v.phase2 +%= v.phase_inc2;
                if (v.pitch_sweep != 0) {
                    const new_inc = @as(i32, @intCast(v.phase_inc1)) + v.pitch_sweep;
                    v.phase_inc1 = @intCast(@max(0, new_inc));
                }
                v.env_level -= v.env_decay;
                v.samples_left -= 1;
            }

            // 4. Mix SFX and BGM with master volumes
            const mixed_bgm = @divTrunc(bgm_sample * @as(i32, bgm_vol), 100);
            const mixed_sfx = @divTrunc(sfx_sample * @as(i32, sfx_vol), 100);
            var mix = @divTrunc((mixed_bgm + mixed_sfx) * @as(i32, master_vol), 100);

            // Soft saturation curve to prevent harsh digital clipping
            if (mix > 26000) {
                mix = 26000 + @divTrunc(mix - 26000, 2);
            } else if (mix < -26000) {
                mix = -26000 + @divTrunc(mix + 26000, 2);
            }
            mix = std.math.clamp(mix, -32768, 32767);

            // Output stereo (interleaved L, R)
            buffer[f * 2] = @intCast(mix);
            buffer[f * 2 + 1] = @intCast(mix);
        }
    }
};

// ---------------------------------------------------------------------------
// 7. Decoupled Audio Bridge (P16-01, D-001, D-019)
// ---------------------------------------------------------------------------

pub const AudioBridge = struct {
    mutex: std.Thread.Mutex = .{},
    event_queue: [MAX_AUDIO_EVENTS]AudioEvent = undefined,
    queue_head: usize = 0,
    queue_tail: usize = 0,
    synth: ChiptuneSynth = ChiptuneSynth.init(),

    master_volume: u8 = 80,
    sfx_volume: u8 = 85,
    bgm_volume: u8 = 75,

    audio_enabled: bool = false,
    last_scene_hash: u32 = 0,
    /// The host's sounds, as last registered; the synth receives its copy through the queue.
    soundtrack: ?*const Soundtrack = null,

    pub fn init() AudioBridge {
        return AudioBridge{};
    }

    /// Enqueues an action SFX trigger to be played asynchronously by the audio thread.
    pub fn enqueue_sfx(self: *AudioBridge, kind: SoundEffectKind) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const next = (self.queue_head + 1) % MAX_AUDIO_EVENTS;
        if (next == self.queue_tail) {
            // Queue full, drop event to avoid stalling simulation clock (D-001)
            return;
        }
        self.event_queue[self.queue_head] = AudioEvent{ .play_sfx = kind };
        self.queue_head = next;
    }

    /// Enqueues a distaff note by degree (0 = C .. 6 = B) for the audio thread (P22-02, D-019).
    /// Shares the ring buffer and drop-when-full policy with SFX: input never blocks a tick.
    pub fn enqueue_note(self: *AudioBridge, degree: u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const next = (self.queue_head + 1) % MAX_AUDIO_EVENTS;
        if (next == self.queue_tail) return;
        self.event_queue[self.queue_head] = AudioEvent{ .play_note = degree };
        self.queue_head = next;
    }

    /// Enqueues a background music change: a soundtrack track index, or null for silence.
    pub fn set_track(self: *AudioBridge, track: ?u8) void {
        self.push(.{ .set_bgm = track });
    }

    /// Plays an engine or soundtrack effect.
    pub fn enqueue_sound(self: *AudioBridge, sound: Sound) void {
        switch (sound) {
            .stock => |kind| self.enqueue_sfx(kind),
            .host => |index| self.push(.{ .play_host_sfx = index }),
        }
    }

    /// Registers a game's tracks, effects, and scene-to-track rule (P32-02d, D-040). The
    /// audio thread switches to it at its next buffer; scene music is chosen afresh.
    pub fn set_soundtrack(self: *AudioBridge, soundtrack: ?*const Soundtrack) void {
        self.soundtrack = soundtrack;
        self.last_scene_hash = 0;
        self.push(.{ .set_soundtrack = soundtrack });
    }

    /// Queues an event, dropping it when the queue is full so the caller never blocks (D-001).
    /// A dropped `set_soundtrack` would leave the synth on the old one; it is sent while the
    /// queue is nearly empty (window setup), so this has not been observed.
    fn push(self: *AudioBridge, event: AudioEvent) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const next = (self.queue_head + 1) % MAX_AUDIO_EVENTS;
        if (next == self.queue_tail) return;
        self.event_queue[self.queue_head] = event;
        self.queue_head = next;
    }

    /// Stops background music.
    pub fn stop_bgm(self: *AudioBridge) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const next = (self.queue_head + 1) % MAX_AUDIO_EVENTS;
        if (next == self.queue_tail) return;
        self.event_queue[self.queue_head] = .stop_bgm;
        self.queue_head = next;
    }

    /// Sets master output volume (0..100).
    pub fn set_master_volume(self: *AudioBridge, volume: u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.master_volume = @min(volume, 100);
    }

    /// The registered track for a scene, or null (no music) when there is no soundtrack or it
    /// has no rule for the scene (P32-02d, D-040).
    pub fn track_for_scene(self: *const AudioBridge, scene_name: []const u8) ?u8 {
        const st = self.soundtrack orelse return null;
        const pick = st.track_for_scene orelse return null;
        return pick(scene_name);
    }

    /// The track to play: the soundtrack track named `score_name` when there is one (script
    /// music, P28-03, D-062), else the soundtrack's rule for the scene.
    pub fn track_for(self: *const AudioBridge, scene_name: []const u8, score_name: []const u8) ?u8 {
        if (score_name.len > 0) {
            if (self.soundtrack) |st| {
                for (st.tracks, 0..) |music, i| {
                    if (i > std.math.maxInt(u8)) break;
                    if (std.mem.eql(u8, music.name, score_name)) return @intCast(i);
                }
            }
        }
        return self.track_for_scene(scene_name);
    }

    /// Examines the current frame's scene and chosen score, changing music when either changes.
    pub fn process_scene_and_cues(self: *AudioBridge, scene_name: []const u8, score_name: []const u8) void {
        if (scene_name.len == 0 and score_name.len == 0) return;

        // Hash scene and score names to detect transitions; the separator keeps "ab"+"c" and
        // "a"+"bc" apart.
        var h: u32 = 2166136261;
        for (scene_name) |b| {
            h ^= b;
            h *%= 16777619;
        }
        h ^= 0xFF;
        h *%= 16777619;
        for (score_name) |b| {
            h ^= b;
            h *%= 16777619;
        }

        if (h != self.last_scene_hash) {
            self.last_scene_hash = h;
            self.set_track(self.track_for(scene_name, score_name));
        }
    }

    /// Renders audio into PCM buffer. Called by SDL audio callback or offline test suite.
    pub fn render_samples(self: *AudioBridge, buffer: []i16) void {
        // 1. Drain pending events under brief mutex lock
        var pending_events: [MAX_AUDIO_EVENTS]AudioEvent = undefined;
        var pending_count: usize = 0;

        {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.queue_tail != self.queue_head) {
                pending_events[pending_count] = self.event_queue[self.queue_tail];
                self.queue_tail = (self.queue_tail + 1) % MAX_AUDIO_EVENTS;
                pending_count += 1;
            }
        }

        // 2. Dispatch events to synthesis engine outside lock
        for (pending_events[0..pending_count]) |ev| {
            switch (ev) {
                .play_sfx => |kind| self.synth.trigger_sfx(kind),
                .play_host_sfx => |index| self.synth.trigger_host_sfx(index),
                .set_soundtrack => |st| {
                    // A new soundtrack's track indices mean different music: stop the old.
                    self.synth.soundtrack = st;
                    self.synth.set_track(null);
                },
                .play_note => |degree| self.synth.trigger_note(degree),
                .set_bgm => |track| self.synth.set_track(track),
                .stop_bgm => self.synth.set_track(null),
                .set_master_volume => |v| self.master_volume = v,
                .set_sfx_volume => |v| self.sfx_volume = v,
                .set_bgm_volume => |v| self.bgm_volume = v,
            }
        }

        // 3. Render audio synthesis into PCM buffer
        self.synth.render_stereo(buffer, self.master_volume, self.sfx_volume, self.bgm_volume);
    }
};

// ---------------------------------------------------------------------------
// 8. Unit Tests & Offline Synthesis Verification
// ---------------------------------------------------------------------------

test "P16-01: AudioBridge event queueing and decoupled drainage" {
    var bridge = AudioBridge.init();
    try testing.expectEqual(@as(usize, 0), bridge.queue_head);
    try testing.expectEqual(@as(usize, 0), bridge.queue_tail);

    bridge.enqueue_sfx(.footstep);
    bridge.enqueue_sfx(.pickup);
    bridge.set_soundtrack(&TEST_SOUNDTRACK);
    bridge.set_track(0);

    try testing.expectEqual(@as(usize, 4), bridge.queue_head);
    try testing.expectEqual(@as(usize, 0), bridge.queue_tail);

    // Render into mock PCM buffer
    var pcm: [256]i16 = undefined;
    bridge.render_samples(&pcm);

    // Events were consumed
    try testing.expectEqual(bridge.queue_head, bridge.queue_tail);
    try testing.expectEqual(@as(?u8, 0), bridge.synth.current_track);
}

test "P16-02: Waveform generators produce bounded non-zero signals" {
    var rng: u32 = 0x12345678;

    const pulse50 = eval_pulse(0x40000000, 0x80000000);
    try testing.expectEqual(@as(i16, 24000), pulse50);
    const pulse50_low = eval_pulse(0xC0000000, 0x80000000);
    try testing.expectEqual(@as(i16, -24000), pulse50_low);

    const tri_mid = eval_triangle(0x80000000);
    try testing.expect(tri_mid >= 32760);

    const saw_mid = eval_sawtooth(0x80000000);
    try testing.expectEqual(@as(i16, 0), saw_mid);

    const noise1 = eval_noise(&rng);
    const noise2 = eval_noise(&rng);
    try testing.expect(noise1 != noise2);
}

test "P16-02: Procedural SFX triggers generate active voices and decay to silence" {
    var synth = ChiptuneSynth.init();

    // Trigger every engine effect and the test soundtrack's effect
    const all_sfx = std.meta.tags(SoundEffectKind);

    synth.soundtrack = &TEST_SOUNDTRACK;
    for (all_sfx) |kind| {
        synth.trigger_sfx(kind);
    }
    synth.trigger_host_sfx(0);

    // Verify voices are active
    var active_count: usize = 0;
    for (synth.sfx_voices) |v| {
        if (v.active) active_count += 1;
    }
    try testing.expect(active_count > 0);

    // Render audio frames until short SFX decay
    var buffer: [1024]i16 = undefined;
    var non_zero_samples: usize = 0;
    for (0..20) |_| {
        synth.render_stereo(&buffer, 100, 100, 0);
        for (buffer) |s| {
            if (s != 0) non_zero_samples += 1;
        }
    }
    try testing.expect(non_zero_samples > 0);
}


test "P16-03: BGM step sequencer advances steps and renders non-clipping audio" {
    var synth = ChiptuneSynth.init();
    synth.soundtrack = &TEST_SOUNDTRACK;
    synth.set_track(0);
    try testing.expectEqual(@as(?u8, 0), synth.current_track);

    var buf: [2048]i16 = undefined;
    for (0..10) |_| {
        synth.render_stereo(&buf, 80, 0, 80);
        for (buf) |s| {
            try testing.expect(s <= 32767 and s >= -32768);
        }
    }

    try testing.expect(synth.current_step > 0 or synth.step_sample_counter > 0);
}

test "P16-01: AudioBridge queue overflow drops events gracefully without blocking" {
    var bridge = AudioBridge.init();

    // Fill queue beyond capacity (64 events)
    for (0..MAX_AUDIO_EVENTS + 10) |_| {
        bridge.enqueue_sfx(.click);
    }

    // Queue must not have crashed or deadlocked
    var buf: [512]i16 = undefined;
    bridge.render_samples(&buf);
    try testing.expectEqual(bridge.queue_head, bridge.queue_tail);
}

test "P16-02: Individual SFX synthesis renders distinct non-zero waveforms" {
    const sfx_list = comptime std.meta.tags(SoundEffectKind);

    inline for (sfx_list) |sfx| {
        var synth = ChiptuneSynth.init();
        synth.trigger_sfx(sfx);

        var buf: [512]i16 = undefined;
        synth.render_stereo(&buf, 100, 100, 0);

        var has_signal = false;
        for (buf) |sample| {
            if (sample != 0) {
                has_signal = true;
                break;
            }
        }
        try testing.expect(has_signal);
    }
}

test "P16-02: SFX voice stealing re-uses lowest envelope when pool exhausted" {
    var synth = ChiptuneSynth.init();

    // Trigger more SFX than MAX_SFX_VOICES (8)
    for (0..MAX_SFX_VOICES * 2) |_| {
        synth.trigger_sfx(.footstep);
    }

    // Exactly MAX_SFX_VOICES should be active
    var active_count: usize = 0;
    for (synth.sfx_voices) |v| {
        if (v.active) active_count += 1;
    }
    try testing.expectEqual(MAX_SFX_VOICES, active_count);
}

test "P16-03: All scene background music tracks synthesize cleanly without clipping" {
    const tracks = [_]u8{ 0, 1 };

    var buf: [1024]i16 = undefined;
    for (tracks) |t| {
        var synth = ChiptuneSynth.init();
        synth.soundtrack = &TEST_SOUNDTRACK;
        synth.set_track(t);

        // Render multiple blocks
        for (0..4) |_| {
            synth.render_stereo(&buf, 90, 0, 90);
            for (buf) |s| {
                try testing.expect(s <= 32767 and s >= -32768);
            }
        }
    }
}

test "P16-03: Music track crossfade transitions between tracks smoothly" {
    var synth = ChiptuneSynth.init();
    synth.soundtrack = &TEST_SOUNDTRACK;
    synth.set_track(0);
    try testing.expectEqual(@as(?u8, 0), synth.current_track);

    // Switch track while running
    synth.set_track(1);
    try testing.expect(synth.is_fading_out);
    try testing.expectEqual(@as(?u8, 1), synth.target_track);

    // Render through crossfade
    var buf: [2048]i16 = undefined;
    for (0..30) |_| {
        synth.render_stereo(&buf, 80, 0, 80);
    }

    // Now current_track should have transitioned to the second track
    try testing.expectEqual(@as(?u8, 1), synth.current_track);
}

test "P22-02: distaff notes render at distinct pitches through the bridge" {
    // Count zero crossings over a fixed window: higher pitch, more crossings.
    var crossings: [DISTAFF_NOTE_COUNT]usize = undefined;
    for (0..DISTAFF_NOTE_COUNT) |deg| {
        var bridge = AudioBridge.init();
        bridge.enqueue_note(@intCast(deg));
        var buf: [4096]i16 = undefined;
        bridge.render_samples(&buf);
        try testing.expect(bridge.synth.sfx_voices[0].active);
        try testing.expectEqual(&STOCK_SFX[@intFromEnum(SoundEffectKind.distaff_note)], bridge.synth.sfx_voices[0].patch);

        var count: usize = 0;
        var prev: i16 = buf[0];
        var peak: i32 = 0;
        var i: usize = 2;
        while (i < buf.len) : (i += 2) {
            if ((prev < 0) != (buf[i] < 0)) count += 1;
            prev = buf[i];
            peak = @max(peak, @as(i32, @intCast(@abs(buf[i]))));
        }
        try testing.expect(peak > 1000);
        crossings[deg] = count;
    }
    for (1..DISTAFF_NOTE_COUNT) |deg| {
        try testing.expect(crossings[deg] >= crossings[deg - 1]);
    }
    try testing.expect(crossings[DISTAFF_NOTE_COUNT - 1] > crossings[0]);
}

test "P22-02: out-of-range note degrees are dropped and weave stingers synthesize" {
    var bridge = AudioBridge.init();
    bridge.enqueue_note(7);
    bridge.enqueue_note(255);
    var buf: [1024]i16 = undefined;
    bridge.render_samples(&buf);
    for (bridge.synth.sfx_voices) |v| try testing.expect(!v.active);

    for ([_]SoundEffectKind{ .weave_success, .weave_fizzle }) |kind| {
        var b = AudioBridge.init();
        b.enqueue_sfx(kind);
        var out: [2048]i16 = undefined;
        b.render_samples(&out);
        var peak: i32 = 0;
        for (out) |smp| peak = @max(peak, @as(i32, @intCast(@abs(smp))));
        try testing.expect(peak > 500);
    }
}


/// A soundtrack for these tests, unrelated to any proof: two short tracks, one effect, and a
/// rule that plays the first track in scenes whose name starts with "Upper".
fn test_pattern(bpm: u16, root: u8) BgmPattern {
    var p = BgmPattern{
        .bpm = bpm,
        .step_count = 8,
        .bass_notes = [_]u8{0} ** BGM_STEPS,
        .lead_notes = [_]u8{0} ** BGM_STEPS,
        .chord_notes = [_]u8{0} ** BGM_STEPS,
        .drum_pattern = [_]u8{0} ** BGM_STEPS,
    };
    for (0..8) |i| {
        p.bass_notes[i] = if (i % 2 == 0) root else 0;
        p.lead_notes[i] = root + 24 + @as(u8, @intCast(i));
        p.drum_pattern[i] = @intCast(i % 4);
    }
    return p;
}

fn test_scene_rule(scene: []const u8) ?u8 {
    return if (std.mem.startsWith(u8, scene, "Upper")) 0 else null;
}

const TEST_SOUNDTRACK = Soundtrack{
    .tracks = &.{
        .{ .name = "alpha", .pattern = test_pattern(140, 40) },
        .{ .name = "beta", .pattern = test_pattern(90, 45) },
    },
    .sfx = &.{.{ .note1 = 48, .note2 = 55, .sweep = -300, .env = 30000, .decay = 5, .samples = 4000, .step_samples = 500, .steps = &.{ .{ .note = 50, .samples = 500 }, .{ .note = 48, .samples = 500 } }, .loop = true, .terms = &.{ .{ .source = .ring, .shape = .saw, .shape2 = .triangle }, .{ .source = .noise, .weight = 2 } }, .mix = .{ .div = 3 } }},
    .track_for_scene = test_scene_rule,
};

test "P32-02d: a registered soundtrack chooses scene music; without one there is none" {
    var bridge = AudioBridge.init();
    try testing.expectEqual(@as(?u8, null), bridge.track_for_scene("Upper Hall"));

    bridge.set_soundtrack(&TEST_SOUNDTRACK);
    try testing.expectEqual(@as(?u8, 0), bridge.track_for_scene("Upper Hall"));
    try testing.expectEqual(@as(?u8, null), bridge.track_for_scene("Lower Hall"));

    bridge.process_scene_and_cues("Upper Hall", "");
    var buf: [256]i16 = undefined;
    bridge.render_samples(&buf);
    try testing.expectEqual(@as(?*const Soundtrack, &TEST_SOUNDTRACK), bridge.synth.soundtrack);
    try testing.expectEqual(@as(?u8, 0), bridge.synth.current_track);
    try testing.expectEqual(@as(u16, 140), bridge.synth.active_pattern.bpm);

    // Unregistering fades the music out and forgets the effects.
    bridge.set_soundtrack(null);
    bridge.enqueue_sound(.{ .host = 0 });
    var fade: [4096]i16 = undefined;
    bridge.render_samples(&fade);
    try testing.expectEqual(@as(?u8, null), bridge.synth.current_track);
    for (bridge.synth.sfx_voices) |v| try testing.expect(!v.active);
}

test "P32-02d: patches step, loop, ring-modulate, and divide as declared" {
    var synth = ChiptuneSynth.init();
    synth.soundtrack = &TEST_SOUNDTRACK;
    synth.trigger_host_sfx(0);
    synth.trigger_host_sfx(9); // no such effect: ignored
    var active: usize = 0;
    for (synth.sfx_voices) |v| active += @intFromBool(v.active);
    try testing.expectEqual(@as(usize, 1), active);

    const v = &synth.sfx_voices[0];
    var buf: [2]i16 = undefined;
    var notes_seen = [_]bool{false} ** 2;
    var peak: i32 = 0;
    for (0..2500) |_| {
        synth.render_stereo(&buf, 100, 100, 0);
        peak = @max(peak, @as(i32, @intCast(@abs(buf[0]))));
        // The looping steps alternate oscillator 1 between notes 50 and 48 (the sweep then
        // bends each), so its increment keeps returning near both notes.
        if (v.phase_inc1 >= midi_to_phase_inc(50) - 600 and v.phase_inc1 <= midi_to_phase_inc(50)) notes_seen[0] = true;
        if (v.phase_inc1 >= midi_to_phase_inc(48) - 600 and v.phase_inc1 <= midi_to_phase_inc(48)) notes_seen[1] = true;
    }
    try testing.expect(notes_seen[0] and notes_seen[1]);
    try testing.expect(v.step < 2);
    try testing.expect(peak > 500);
}

// ---------------------------------------------------------------------------
// MML playback tests (P28-02, D-061)
// ---------------------------------------------------------------------------

/// Parses four parts into an `MmlScore`; the parsed scores own the events and must outlive it.
const MmlFixture = struct {
    parsed: [MML_PART_COUNT]mml.Score = undefined,
    count: usize = 0,
    score: MmlScore = .{},
    music: [1]Music = undefined,
    soundtrack: Soundtrack = .{},

    fn init(self: *MmlFixture, texts: [MML_PART_COUNT][]const u8) !void {
        for (texts, 0..) |text, i| {
            var diag = mml.Diagnostic{};
            const kind: mml.TrackKind = if (i == @intFromEnum(MmlPart.percussion)) .percussion else .melodic;
            self.parsed[i] = try mml.parse(testing.allocator, text, kind, &diag);
            self.count += 1;
            self.score.parts[i] = MmlTrack.of(&self.parsed[i]);
        }
        self.music = .{.{ .name = "mml", .score = &self.score }};
        self.soundtrack = .{ .tracks = &self.music };
    }

    fn deinit(self: *MmlFixture) void {
        for (self.parsed[0..self.count]) |*p| p.deinit();
    }

    fn synth(self: *const MmlFixture) ChiptuneSynth {
        var s = ChiptuneSynth.init();
        s.soundtrack = &self.soundtrack;
        s.set_track(0);
        return s;
    }
};

fn render_frames(synth: *ChiptuneSynth, frames: usize) void {
    var buf: [1024]i16 = undefined;
    var left = frames;
    while (left > 0) {
        const n: usize = @min(left, buf.len / 2);
        synth.render_stereo(buf[0 .. n * 2], 100, 100, 100);
        left -= n;
    }
}

fn run_to_tick(synth: *ChiptuneSynth, tick: u64) void {
    var buf: [2]i16 = undefined;
    while (synth.mml.ticks < tick) synth.render_stereo(&buf, 100, 100, 100);
}

fn part_of(synth: *const ChiptuneSynth, which: MmlPart) MmlPartState {
    return synth.mml.parts[@intFromEnum(which)];
}

test "P28-02: the MML clock counts exact integer ticks at any tempo" {
    var f = MmlFixture{};
    defer f.deinit();
    try f.init(.{ "c1 c1", "", "", "" });
    var s = f.synth();
    // A quarter note at 120 bpm is 22,050 samples and 48 ticks, with no rounding drift.
    render_frames(&s, 22_050 * 3);
    try testing.expectEqual(@as(u64, 144), s.mml.ticks);

    var g = MmlFixture{};
    defer g.deinit();
    try g.init(.{ "t100 c1", "", "", "" });
    var t = g.synth();
    render_frames(&t, 26_459);
    try testing.expectEqual(@as(u64, 47), t.mml.ticks);
    render_frames(&t, 1);
    try testing.expectEqual(@as(u64, 48), t.mml.ticks);
}

test "P28-02: a tempo in any part sets the one clock for every part" {
    var f = MmlFixture{};
    defer f.deinit();
    try f.init(.{ "c4 d4", "t240 c2", "", "" });
    var s = f.synth();
    // At 240 bpm the lead's first quarter ends after 11,025 samples, not 22,050.
    render_frames(&s, 11_024);
    try testing.expectEqual(@as(u32, 1), part_of(&s, .lead).notes_started);
    render_frames(&s, 1);
    try testing.expectEqual(@as(u32, 2), part_of(&s, .lead).notes_started);
    try testing.expectEqual(midi_to_phase_inc(62), s.lead_phase_inc);
}

test "P28-02: looping parts restart together at their own L once every part has ended" {
    var f = MmlFixture{};
    defer f.deinit();
    // Lead: an intro note, then a looped quarter. Bass: a looped half. Chords play once.
    try f.init(.{ "c4 L d4", "L e2", "g1", "" });
    var s = f.synth();
    run_to_tick(&s, 96);
    try testing.expectEqual(@as(u32, 2), part_of(&s, .lead).notes_started);
    try testing.expect(part_of(&s, .lead).finished);
    try testing.expect(part_of(&s, .bass).finished);
    // The chord's whole note holds the score until tick 192; nothing restarts before it.
    run_to_tick(&s, 191);
    try testing.expectEqual(@as(u32, 2), part_of(&s, .lead).notes_started);
    try testing.expectEqual(@as(u32, 1), part_of(&s, .bass).notes_started);
    run_to_tick(&s, 192);
    try testing.expectEqual(@as(u32, 3), part_of(&s, .lead).notes_started);
    try testing.expectEqual(@as(u32, 2), part_of(&s, .bass).notes_started);
    try testing.expectEqual(midi_to_phase_inc(62), s.lead_phase_inc);
    try testing.expect(part_of(&s, .chords).finished);
    // Second pass: the bass's half outlasts the lead's quarter, so both restart at 288.
    run_to_tick(&s, 287);
    try testing.expectEqual(@as(u32, 3), part_of(&s, .lead).notes_started);
    run_to_tick(&s, 288);
    try testing.expectEqual(@as(u32, 4), part_of(&s, .lead).notes_started);
    try testing.expectEqual(@as(u32, 3), part_of(&s, .bass).notes_started);
    try testing.expectEqual(@as(u32, 1), part_of(&s, .chords).notes_started);
}

test "P28-02: a score without L plays once and falls silent" {
    var f = MmlFixture{};
    defer f.deinit();
    try f.init(.{ "@1 c4", "", "", "" });
    var s = f.synth();
    run_to_tick(&s, 60);
    for (s.mml.parts) |p| try testing.expect(p.finished);
    try testing.expectEqual(@as(i32, 0), s.lead_env);
    var buf: [512]i16 = undefined;
    s.render_stereo(&buf, 100, 100, 100);
    for (buf) |x| try testing.expectEqual(@as(i16, 0), x);
}

test "P28-02: envelopes hold, release at the written length, swell, and tremble" {
    var organ = MmlFixture{};
    defer organ.deinit();
    try organ.init(.{ "@1 c4 r4", "@0 c4 r4", "@4 c1", "" });
    var s = organ.synth();
    // Part levels, not voice envelopes: a voice subtracts its grid decay once after each sample
    // before the next sample's level overwrites it.
    run_to_tick(&s, 1);
    // A swell starts near silence.
    try testing.expect(part_of(&s, .chords).level < 2_000);
    try testing.expectEqual(EnvStage.attack, part_of(&s, .chords).stage);
    run_to_tick(&s, 5);
    // The organ holds its peak; the grid preset decays like a grid note, 6 a sample
    // (five ticks are about 2,297 samples).
    try testing.expectEqual(@as(i32, 28_000), part_of(&s, .lead).level);
    try testing.expect(part_of(&s, .bass).level < 30_000 - 6 * 2_000);
    try testing.expect(part_of(&s, .bass).level > 0);
    run_to_tick(&s, 40);
    try testing.expectEqual(@as(i32, 22_000), part_of(&s, .chords).level);
    run_to_tick(&s, 50);
    // At the written length the organ releases; the grid preset has no note-off and simply
    // runs out, as a grid note does.
    try testing.expectEqual(@as(i32, 0), part_of(&s, .lead).level);
    try testing.expectEqual(EnvStage.off, part_of(&s, .lead).stage);
    try testing.expectEqual(@as(i32, 0), s.lead_env);

    var trem = MmlFixture{};
    defer trem.deinit();
    try trem.init(.{ "@6 c1", "", "", "" });
    var t = trem.synth();
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = 0;
    var buf: [2]i16 = undefined;
    for (0..20_000) |_| {
        t.render_stereo(&buf, 100, 100, 100);
        lo = @min(lo, t.lead_env);
        hi = @max(hi, t.lead_env);
    }
    try testing.expectEqual(@as(i32, 28_000), part_of(&t, .lead).level);
    try testing.expect(hi - lo > 10_000);
}

test "P28-02: volume scales notes and drums, and v0 is silent" {
    var quiet = MmlFixture{};
    defer quiet.deinit();
    try quiet.init(.{ "v0 c1", "v0 c1", "v0 c1", "v0 k1" });
    var s = quiet.synth();
    var buf: [4096]i16 = undefined;
    s.render_stereo(&buf, 100, 100, 100);
    for (buf) |x| try testing.expectEqual(@as(i16, 0), x);

    var mid = MmlFixture{};
    defer mid.deinit();
    try mid.init(.{ "v8 @1 c1", "", "", "v5 k4 s4 h4" });
    var m = mid.synth();
    try testing.expectEqual(@as(i32, 32_000 * 5 / 15), m.kick_env);
    run_to_tick(&m, 2);
    try testing.expectEqual(@as(i32, 28_000 * 8 / 15), part_of(&m, .lead).level);
    run_to_tick(&m, 48);
    // The snare voice has already decayed one sample (40) since the hit.
    try testing.expectEqual(@as(i32, 30_000 * 5 / 15 - 40), m.snare_env);
    try testing.expectEqual(@as(u32, 2), part_of(&m, .percussion).notes_started);
}

test "P28-02: hand-built scores are clamped and cannot stall the audio thread" {
    // Events no parser would produce: a drum hit on the lead, a note on percussion, an
    // out-of-range tempo and envelope, and a loop whose body takes no time.
    const lead = [_]mml.Event{ .{ .tempo = 1000 }, .{ .envelope = 200 }, .{ .hit = .{ .drum = .kick, .ticks = 4 } } };
    const drums = [_]mml.Event{ .{ .note = .{ .midi = 60, .ticks = 4 } }, .{ .volume = 99 } };
    const score = MmlScore{ .parts = .{
        .{ .events = &lead, .loop_start = 0 },
        .{},
        .{},
        .{ .events = &drums, .loop_start = 1 },
    } };
    const music = [_]Music{.{ .name = "raw", .score = &score }};
    const st = Soundtrack{ .tracks = &music };
    var s = ChiptuneSynth.init();
    s.soundtrack = &st;
    s.set_track(0);
    try testing.expectEqual(@as(u16, 255), s.mml.tempo);
    try testing.expectEqual(@as(i32, 0), s.kick_env);
    render_frames(&s, 5_000);
    try testing.expect(s.mml.ticks > 0);
    try testing.expectEqual(@as(u8, 15), part_of(&s, .percussion).volume);
    try testing.expectEqual(@as(u8, ENVELOPES.len - 1), part_of(&s, .lead).envelope);
}

test "P28-02: grid and MML tracks crossfade into each other" {
    var f = MmlFixture{};
    defer f.deinit();
    try f.init(.{ "L c4 e4", "", "", "" });
    const tracks = [_]Music{
        .{ .name = "grid", .pattern = test_pattern(140, 40) },
        .{ .name = "mml", .score = &f.score },
    };
    const st = Soundtrack{ .tracks = &tracks };
    var s = ChiptuneSynth.init();
    s.soundtrack = &st;
    s.set_track(0);
    try testing.expectEqual(@as(?*const MmlScore, null), s.mml.score);
    render_frames(&s, 4_000);
    s.set_track(1);
    render_frames(&s, 4_000);
    try testing.expectEqual(@as(?u8, 1), s.current_track);
    try testing.expectEqual(@as(?*const MmlScore, &f.score), s.mml.score);
    try testing.expectEqual(@as(u32, 1), part_of(&s, .lead).notes_started);
    s.set_track(0);
    render_frames(&s, 4_000);
    try testing.expectEqual(@as(?*const MmlScore, null), s.mml.score);
    try testing.expectEqual(@as(u16, 140), s.active_pattern.bpm);
}

test "P34-08: an arranged track plays its sections in order, transposed and muted per pass, then starts over" {
    const sections = [_]BgmPattern{ test_pattern(140, 40), test_pattern(140, 45) };
    const order = [_]SectionPlay{
        .{ .section = 0 },
        .{ .section = 1, .transpose = 2, .mute = .{ .drums = true } },
        .{ .section = 0, .mute = .{ .lead = true } },
    };
    const tracks = [_]Music{.{ .name = "arranged", .sections = &sections, .arrangement = &order }};
    const st = Soundtrack{ .tracks = &tracks };
    var s = ChiptuneSynth.init();
    s.soundtrack = &st;
    s.set_track(0);
    try testing.expectEqual(@as(usize, 0), s.arrangement_pos);
    try testing.expectEqual(@as(u8, 40), s.active_pattern.bass_notes[0]);

    // One pass of an 8-step section, and the next entry plays: section 1, two semitones up,
    // drums silent.
    const pass = @as(usize, s.samples_per_step) * 8;
    render_frames(&s, pass);
    try testing.expectEqual(@as(usize, 1), s.arrangement_pos);
    try testing.expectEqual(@as(u8, 47), s.active_pattern.bass_notes[0]);
    try testing.expectEqual(@as(u8, 45 + 24 + 2), s.active_pattern.lead_notes[0]);
    for (s.active_pattern.drum_pattern) |d| try testing.expectEqual(@as(u8, 0), d);

    render_frames(&s, pass);
    try testing.expectEqual(@as(usize, 2), s.arrangement_pos);
    for (s.active_pattern.lead_notes) |n| try testing.expectEqual(@as(u8, 0), n);
    try testing.expectEqual(@as(u8, 40), s.active_pattern.bass_notes[0]);

    // After the last entry the arrangement starts over, and a new track starts at its top.
    render_frames(&s, pass);
    try testing.expectEqual(@as(usize, 0), s.arrangement_pos);
    try testing.expectEqual(@as(u8, 40 + 24), s.active_pattern.lead_notes[0]);
}

test "P34-08: an arrangement pass never reads past its sections or out of MIDI range" {
    var high = test_pattern(120, 40);
    high.lead_notes[0] = 127;
    const sections = [_]BgmPattern{high};
    const music = Music{ .name = "edge", .sections = &sections };
    const missing = arranged_pattern(&music, .{ .section = 3 });
    try testing.expectEqualSlices(u8, &SILENT_PATTERN.lead_notes, &missing.lead_notes);
    const up = arranged_pattern(&music, .{ .section = 0, .transpose = 1 });
    try testing.expectEqual(@as(u8, 0), up.lead_notes[0]);
    try testing.expectEqual(@as(u8, 41), up.bass_notes[0]);
    const down = arranged_pattern(&music, .{ .section = 0, .transpose = -40 });
    try testing.expectEqual(@as(u8, 0), down.bass_notes[0]);
}
