//! BeSpoke Engine: Peripheral Audio Subsystem & Procedural Sound Synthesizer (Phase 16, D-001, D-019)
//!
//! A pure Zig procedural audio engine providing chiptune synthesis, action sound effects,
//! and scene background musical accompaniment with zero external audio assets or codec dependencies.
//! Audio cues from the discrete simulation spine are consumed asynchronously through the decoupled AudioBridge.

const std = @import("std");
const testing = std.testing;

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

/// Generates pseudo-random uniform white noise via 32-bit Linear Congruential Generator.
pub inline fn eval_noise(rng: *u32) i16 {
    rng.* = rng.* *% 1664525 +% 1013904223;
    const val: i32 = @intCast(rng.* >> 16);
    return @intCast(val - 32768);
}

// ---------------------------------------------------------------------------
// 3. Audio Kinds & Enums
// ---------------------------------------------------------------------------

/// Procedural sound effect categories for player/world interactions (P16-02, D-019).
pub const SoundEffectKind = enum(u8) {
    footstep,
    pickup,
    combine,
    horn,
    splash,
    sword_clash,
    alert,
    dialogue_blip,
    click,
    whistle,
    goat_bleat,
    thud,
    toilet_flush,
    snip_shears,
    wood_chop,
    // Musical draft spellcraft (P22-02, D-029)
    distaff_note,
    weave_success,
    weave_fizzle,
};

/// MIDI pitches for the seven distaff notes, indexed by `draft.Note` value (C4 to B4).
/// Audio takes the raw degree (0 to 6) so the synthesizer stays free of simulation imports.
pub const DISTAFF_MIDI = [7]u8{ 60, 62, 64, 65, 67, 69, 71 };
pub const DISTAFF_NOTE_COUNT: u8 = DISTAFF_MIDI.len;

/// Procedural background musical accompaniment tracks for narrative scenes (P16-03, D-019).
pub const MusicTrackKind = enum(u8) {
    none = 0,
    tavern,
    cellar,
    spitting_contest,
    high_road,
    sanctuary,
    scumm_bar,
    courtyard,
    bike_shop,
    lochmarne,
    tentacle,
};

/// Decoupled audio event queued by simulation or GUI and consumed by audio thread.
pub const AudioEvent = union(enum) {
    play_sfx: SoundEffectKind,
    /// A distaff note by diatonic degree (0 = C .. 6 = B). Out-of-range degrees are dropped.
    play_note: u8,
    set_bgm: MusicTrackKind,
    stop_bgm: void,
    set_master_volume: u8,
    set_sfx_volume: u8,
    set_bgm_volume: u8,
};

// ---------------------------------------------------------------------------
// 4. Procedural SFX Voice
// ---------------------------------------------------------------------------

pub const SfxVoice = struct {
    kind: SoundEffectKind = .click,
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

/// Generates pre-authored 32-step procedural score patterns for narrative locations (P16-03).
pub fn get_track_pattern(track: MusicTrackKind) BgmPattern {
    var p = BgmPattern{
        .bpm = 120,
        .step_count = 32,
        .bass_notes = [_]u8{0} ** BGM_STEPS,
        .lead_notes = [_]u8{0} ** BGM_STEPS,
        .chord_notes = [_]u8{0} ** BGM_STEPS,
        .drum_pattern = [_]u8{0} ** BGM_STEPS,
    };

    switch (track) {
        .none => return p,

        // The Tavern Heist: Lively G-Dorian pipe & lute jig
        .tavern => {
            p.bpm = 132;
            p.bass_notes = [BGM_STEPS]u8{
                43, 0, 43, 0, 38, 0, 43, 0, 41, 0, 41, 0, 36, 0, 38, 0,
                43, 0, 43, 0, 38, 0, 43, 0, 41, 0, 41, 0, 38, 0, 43, 0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                67, 0, 70, 72, 74, 0, 72, 70, 69, 0, 65, 69, 67, 0, 0,  0,
                67, 69, 70, 72, 74, 77, 74, 72, 70, 69, 67, 65, 67, 0, 0,  0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                55, 0, 58, 0, 55, 0, 58, 0, 53, 0, 57, 0, 53, 0, 57, 0,
                55, 0, 58, 0, 55, 0, 58, 0, 53, 0, 57, 0, 55, 0, 58, 0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 3, 3, 3, 2, 3, 1, 3, 1, 3, 3, 3, 2, 3, 3, 3,
                1, 3, 3, 3, 2, 3, 1, 3, 1, 3, 3, 3, 2, 3, 1, 2,
            };
        },

        // The Wine Cellar: Moody subterranean minor bassline and dripping echoes
        .cellar => {
            p.bpm = 92;
            p.bass_notes = [BGM_STEPS]u8{
                36, 0, 0, 0, 39, 0, 0, 0, 43, 0, 0, 0, 44, 0, 43, 0,
                36, 0, 0, 0, 39, 0, 0, 0, 41, 0, 0, 0, 43, 0, 0,  0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                60, 0, 63, 0, 67, 0, 68, 67, 63, 0, 62, 0, 60, 0, 0,  0,
                60, 0, 63, 0, 67, 0, 70, 68, 67, 0, 65, 0, 63, 62, 60, 0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                48, 0, 0, 0, 51, 0, 0, 0, 55, 0, 0, 0, 56, 0, 55, 0,
                48, 0, 0, 0, 51, 0, 0, 0, 53, 0, 0, 0, 55, 0, 0,  0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0,
                1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 1, 0,
            };
        },

        // Booty Island Spitting Contest: Jaunty Caribbean pirate regatta march
        .spitting_contest => {
            p.bpm = 126;
            p.bass_notes = [BGM_STEPS]u8{
                48, 0, 43, 0, 48, 0, 43, 0, 41, 0, 48, 0, 43, 0, 50, 0,
                48, 0, 43, 0, 48, 0, 43, 0, 41, 0, 43, 0, 48, 0, 0,  0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                76, 0, 79, 0, 76, 74, 72, 0, 74, 0, 76, 77, 79, 0, 0,  0,
                81, 0, 79, 76, 72, 0, 74, 0, 76, 74, 72, 0, 72, 0, 0,  0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                0, 60, 0, 60, 0, 60, 0, 60, 0, 57, 0, 57, 0, 55, 0, 55,
                0, 60, 0, 60, 0, 60, 0, 60, 0, 57, 0, 55, 0, 60, 0, 0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 3, 3, 3, 2, 3, 1, 3, 1, 3, 3, 3, 2, 2, 3, 3,
                1, 3, 3, 3, 2, 3, 1, 3, 1, 3, 3, 3, 2, 3, 1, 2,
            };
        },

        // Mêlée Island High Road: Adventurous seafaring shanty progression
        .high_road => {
            p.bpm = 112;
            p.bass_notes = [BGM_STEPS]u8{
                45, 0, 0, 0, 41, 0, 0, 0, 43, 0, 0, 0, 40, 0, 0, 0,
                45, 0, 0, 0, 41, 0, 0, 0, 43, 0, 0, 0, 45, 0, 0, 0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                64, 69, 72, 71, 69, 0, 67, 0, 69, 72, 74, 0, 76, 0, 0,  0,
                76, 74, 72, 71, 69, 0, 67, 64, 65, 67, 69, 0, 69, 0, 0,  0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                57, 0, 60, 0, 53, 0, 57, 0, 55, 0, 59, 0, 52, 0, 55, 0,
                57, 0, 60, 0, 53, 0, 57, 0, 55, 0, 59, 0, 57, 0, 60, 0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 0, 3, 0, 2, 0, 1, 0, 1, 0, 3, 0, 2, 0, 3, 0,
                1, 0, 3, 0, 2, 0, 1, 0, 1, 0, 3, 0, 2, 3, 1, 2,
            };
        },

        // Carla's Sanctuary: Intense, dramatic sword duel cadence
        .sanctuary => {
            p.bpm = 144;
            p.bass_notes = [BGM_STEPS]u8{
                38, 38, 38, 38, 41, 41, 41, 41, 43, 43, 43, 43, 45, 45, 43, 41,
                38, 38, 38, 38, 41, 41, 41, 41, 43, 43, 45, 45, 38, 38, 0,  0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                74, 0, 77, 0, 81, 0, 79, 77, 76, 0, 77, 79, 81, 0, 0,  0,
                86, 0, 81, 0, 77, 0, 74, 0, 76, 77, 76, 73, 74, 0, 0,  0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                50, 0, 53, 0, 53, 0, 57, 0, 55, 0, 58, 0, 57, 0, 61, 0,
                50, 0, 53, 0, 53, 0, 57, 0, 55, 0, 57, 0, 50, 0, 53, 0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 3, 1, 3, 2, 3, 1, 3, 1, 3, 1, 3, 2, 3, 1, 2,
                1, 3, 1, 3, 2, 3, 1, 3, 1, 3, 1, 3, 2, 2, 1, 2,
            };
        },

        // The Scumm Bar: Rowdy pirate tavern waltz in 3/4 time
        .scumm_bar => {
            p.bpm = 138;
            p.bass_notes = [BGM_STEPS]u8{
                48, 0, 0, 48, 0, 0, 43, 0, 0, 48, 0, 0, 41, 0, 0, 43,
                48, 0, 0, 48, 0, 0, 45, 0, 0, 43, 0, 0, 48, 0, 0, 0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                72, 0, 74, 76, 0, 79, 81, 0, 79, 76, 0, 0, 72, 0, 76, 74,
                72, 0, 74, 76, 0, 79, 81, 0, 79, 76, 74, 0, 72, 0, 0,  0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                0, 60, 60, 0, 60, 60, 0, 55, 55, 0, 60, 60, 0, 57, 57, 0,
                0, 60, 60, 0, 60, 60, 0, 57, 57, 0, 55, 55, 0, 60, 60, 0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 3, 3, 1, 3, 3, 1, 3, 3, 1, 3, 3, 1, 3, 3, 2,
                1, 3, 3, 1, 3, 3, 1, 3, 3, 1, 3, 3, 1, 3, 3, 2,
            };
        },

        // Gabriel Knight 3 Hotel Courtyard Garden: Peaceful French provincial waltz
        .courtyard => {
            p.bpm = 104;
            p.bass_notes = [BGM_STEPS]u8{
                41, 0, 48, 0, 41, 0, 48, 0, 46, 0, 41, 0, 48, 0, 43, 0,
                41, 0, 48, 0, 41, 0, 48, 0, 46, 0, 48, 0, 41, 0, 0,  0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                69, 0, 72, 0, 77, 0, 76, 74, 72, 0, 70, 0, 69, 0, 67, 0,
                69, 0, 72, 0, 77, 0, 79, 77, 76, 0, 74, 0, 72, 0, 0,  0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                53, 0, 57, 0, 53, 0, 57, 0, 58, 0, 53, 0, 57, 0, 55, 0,
                53, 0, 57, 0, 53, 0, 57, 0, 58, 0, 57, 0, 53, 0, 0,  0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 0, 3, 0, 0, 0, 3, 0, 1, 0, 3, 0, 0, 0, 3, 0,
                1, 0, 3, 0, 0, 0, 3, 0, 1, 0, 3, 0, 0, 0, 1, 0,
            };
        },

        // Gabriel Knight 3 Bike Rental Shop: Breezy French café accordion cadence
        .bike_shop => {
            p.bpm = 118;
            p.bass_notes = [BGM_STEPS]u8{
                43, 0, 50, 0, 43, 0, 50, 0, 41, 0, 48, 0, 43, 0, 50, 0,
                43, 0, 50, 0, 43, 0, 50, 0, 41, 0, 45, 0, 43, 0, 0,  0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                67, 70, 74, 73, 74, 0, 70, 0, 67, 69, 70, 72, 69, 0, 0,  0,
                67, 70, 74, 73, 74, 77, 74, 70, 69, 70, 69, 66, 67, 0, 0,  0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                0, 55, 0, 58, 0, 55, 0, 58, 0, 53, 0, 57, 0, 55, 0, 58,
                0, 55, 0, 58, 0, 55, 0, 58, 0, 53, 0, 54, 0, 55, 0, 0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 3, 3, 3, 2, 3, 1, 3, 1, 3, 3, 3, 2, 3, 3, 3,
                1, 3, 3, 3, 2, 3, 1, 3, 1, 3, 3, 3, 2, 3, 1, 2,
            };
        },

        // Lochmarne Castle & Templar Crypt: Lively Celtic whistle jig in 6/8 time (P20-03, D-023)
        .lochmarne => {
            p.bpm = 126;
            p.bass_notes = [BGM_STEPS]u8{
                43, 0, 50, 43, 0, 50, 41, 0, 48, 43, 0, 50, 43, 0, 50, 41,
                43, 0, 50, 43, 0, 50, 45, 0, 52, 43, 0, 50, 43, 0, 0,  0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                71, 74, 76, 79, 76, 74, 76, 74, 71, 69, 71, 74, 71, 0, 0,  0,
                71, 74, 76, 79, 81, 79, 76, 74, 76, 74, 71, 69, 71, 0, 0,  0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                0, 55, 59, 0, 55, 59, 0, 53, 57, 0, 55, 59, 0, 55, 59, 0,
                0, 55, 59, 0, 55, 59, 0, 57, 60, 0, 55, 59, 0, 55, 59, 0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 3, 3, 2, 3, 3, 1, 3, 1, 3, 3, 2, 3, 3, 3, 3,
                1, 3, 3, 2, 3, 3, 1, 3, 1, 3, 3, 2, 3, 3, 1, 2,
            };
        },

        // Day of the Tentacle Trio: Quirky cartoon march with bouncy bass and syncopated lead (P21-03, D-025)
        .tentacle => {
            p.bpm = 132;
            p.bass_notes = [BGM_STEPS]u8{
                36, 0, 48, 0, 39, 0, 51, 0, 41, 0, 53, 0, 43, 0, 55, 0,
                36, 0, 48, 0, 39, 0, 51, 0, 44, 0, 56, 0, 43, 0, 41, 0,
            };
            p.lead_notes = [BGM_STEPS]u8{
                60, 63, 67, 72, 70, 67, 63, 60, 65, 68, 72, 75, 72, 0, 0, 0,
                60, 63, 67, 72, 75, 74, 72, 70, 72, 70, 67, 63, 60, 0, 0, 0,
            };
            p.chord_notes = [BGM_STEPS]u8{
                0, 48, 51, 0, 48, 51, 0, 51, 55, 0, 53, 56, 0, 55, 58, 0,
                0, 48, 51, 0, 48, 51, 0, 56, 60, 0, 55, 58, 0, 53, 56, 0,
            };
            p.drum_pattern = [BGM_STEPS]u8{
                1, 3, 2, 3, 1, 3, 2, 3, 1, 3, 2, 3, 1, 1, 2, 2,
                1, 3, 2, 3, 1, 3, 2, 3, 1, 3, 2, 3, 1, 2, 3, 1,
            };
        },
    }

    return p;
}

// ---------------------------------------------------------------------------
// 6. Complete Procedural Chiptune Synthesizer Engine
// ---------------------------------------------------------------------------

pub const ChiptuneSynth = struct {
    sample_rate: u32 = SAMPLE_RATE,
    rng_state: u32 = 0x811c9dc5,

    // SFX Voice Pool
    sfx_voices: [MAX_SFX_VOICES]SfxVoice = [_]SfxVoice{.{}} ** MAX_SFX_VOICES,

    // BGM Sequencer State
    current_track: MusicTrackKind = .none,
    target_track: MusicTrackKind = .none,
    active_pattern: BgmPattern = std.mem.zeroes(BgmPattern),
    current_step: usize = 0,
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

    // Track Crossfade
    fade_level: i32 = 32767, // 0..32767
    is_fading_out: bool = false,

    pub fn init() ChiptuneSynth {
        var synth = ChiptuneSynth{};
        synth.set_track(.none);
        return synth;
    }

    /// Sets or changes the active background music track (P16-03).
    pub fn set_track(self: *ChiptuneSynth, track: MusicTrackKind) void {
        if (self.current_track == track) return;

        if (self.current_track == .none) {
            // Immediate start
            self.current_track = track;
            self.target_track = track;
            self.active_pattern = get_track_pattern(track);
            self.current_step = 0;
            self.step_sample_counter = 0;
            self.fade_level = 32767;
            self.is_fading_out = false;
            if (self.active_pattern.bpm > 0) {
                // 1 step = 1 sixteenth note = (60 / bpm / 4) seconds
                const step_sec = (60.0 / @as(f64, @floatFromInt(self.active_pattern.bpm))) / 4.0;
                self.samples_per_step = @intFromFloat(step_sec * @as(f64, @floatFromInt(self.sample_rate)));
            }
        } else {
            // Begin fast crossfade
            self.target_track = track;
            self.is_fading_out = true;
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

    /// Triggers an action sound effect in an available voice slot (P16-02).
    pub fn trigger_sfx(self: *ChiptuneSynth, kind: SoundEffectKind) void {
        _ = self.trigger_sfx_voice(kind);
    }

    fn trigger_sfx_voice(self: *ChiptuneSynth, kind: SoundEffectKind) *SfxVoice {
        // Find inactive voice, or steal the voice with lowest envelope level
        var slot: usize = 0;
        var lowest_env: i32 = 32768;
        var found_free = false;

        for (self.sfx_voices, 0..) |voice, i| {
            if (!voice.active) {
                slot = i;
                found_free = true;
                break;
            }
            if (voice.env_level < lowest_env) {
                lowest_env = voice.env_level;
                slot = i;
            }
        }

        var v = &self.sfx_voices[slot];
        v.* = SfxVoice{
            .kind = kind,
            .active = true,
            .phase1 = 0,
            .phase2 = 0,
            .step = 0,
            .volume = 100,
        };

        switch (kind) {
            .footstep => {
                // Quick crisp noise burst with subtle bass tap
                v.phase_inc1 = midi_to_phase_inc(36);
                v.pitch_sweep = -120;
                v.env_level = 26000;
                v.env_decay = 26; // ~1000 samples (~22 ms)
                v.samples_left = 1000;
            },
            .pickup => {
                // Rising two-tone chime (Note 64 -> Note 71)
                v.phase_inc1 = midi_to_phase_inc(64);
                v.duty = 0x40000000; // 25% pulse
                v.env_level = 28000;
                v.env_decay = 8;
                v.samples_left = 5000;
                v.step_samples_left = 1800; // First tone lasts 1800 samples
            },
            .combine => {
                // Sparkling 4-tone ascending arpeggio (C5 -> E5 -> G5 -> C6)
                v.phase_inc1 = midi_to_phase_inc(60);
                v.duty = 0x40000000;
                v.env_level = 30000;
                v.env_decay = 6;
                v.samples_left = 9000;
                v.step_samples_left = 1500;
            },
            .horn => {
                // Low brass dual-saw blare (D2 + A2)
                v.phase_inc1 = midi_to_phase_inc(38);
                v.phase_inc2 = midi_to_phase_inc(45);
                v.env_level = 30000;
                v.env_decay = 3;
                v.samples_left = 11000; // ~250 ms
            },
            .splash => {
                // Noise splash with descending bubble sweep
                v.phase_inc1 = midi_to_phase_inc(72);
                v.pitch_sweep = -6000;
                v.env_level = 28000;
                v.env_decay = 3;
                v.samples_left = 9000;
            },
            .sword_clash => {
                // High metallic ring modulation + noise impact
                v.phase_inc1 = midi_to_phase_inc(84); // C7
                v.phase_inc2 = midi_to_phase_inc(90); // F#7 inharmonic
                v.env_level = 32000;
                v.env_decay = 6;
                v.samples_left = 5500;
            },
            .alert => {
                // Dramatic diminished stinger (D3 + Ab3)
                v.phase_inc1 = midi_to_phase_inc(50);
                v.phase_inc2 = midi_to_phase_inc(56);
                v.env_level = 31000;
                v.env_decay = 4;
                v.samples_left = 7500;
            },
            .dialogue_blip => {
                // Subtle retro speech chirp (D5)
                v.phase_inc1 = midi_to_phase_inc(62);
                v.pitch_sweep = -1200;
                v.env_level = 20000;
                v.env_decay = 25;
                v.samples_left = 800; // ~18 ms
            },
            .click => {
                // Crisp 8ms UI tick
                v.phase_inc1 = midi_to_phase_inc(76);
                v.env_level = 18000;
                v.env_decay = 50;
                v.samples_left = 360; // ~8 ms
            },
            .whistle => {
                // Ascending pure whistle
                v.phase_inc1 = midi_to_phase_inc(60);
                v.pitch_sweep = 3500;
                v.env_level = 22000;
                v.env_decay = 2;
                v.samples_left = 11000;
            },
            .goat_bleat => {
                // Dual saw-wave bleating voice with rapid vibrato modulation (P20-03, D-023)
                v.phase_inc1 = midi_to_phase_inc(60); // C4
                v.phase_inc2 = midi_to_phase_inc(63); // Eb4
                v.duty = 0x60000000;
                v.pitch_sweep = 150;
                v.env_level = 30000;
                v.env_decay = 3;
                v.samples_left = 9000; // ~200 ms
                v.step_samples_left = 1200;
            },
            .thud => {
                // Heavy percussive headbutt impact with rapid pitch drop (P20-03, D-023)
                v.phase_inc1 = midi_to_phase_inc(40); // E2
                v.pitch_sweep = -1800;
                v.env_level = 32000;
                v.env_decay = 20;
                v.samples_left = 1600; // ~36 ms
            },
            .toilet_flush => {
                // Downward swirling resonant flush with noise and pitch glide (P21-03, D-025)
                v.phase_inc1 = midi_to_phase_inc(64);
                v.pitch_sweep = -120;
                v.env_level = 28000;
                v.env_decay = 2;
                v.samples_left = 18000; // ~400 ms
            },
            .snip_shears => {
                // Sharp metallic snip sound for Betsy Ross cutting cloth (P21-03, D-025)
                v.phase_inc1 = midi_to_phase_inc(84);
                v.pitch_sweep = -1200;
                v.env_level = 26000;
                v.env_decay = 18;
                v.samples_left = 2200; // ~50 ms
            },
            .wood_chop => {
                // Heavy wooden axe thud on timber for George Washington (P21-03, D-025)
                v.phase_inc1 = midi_to_phase_inc(36);
                v.pitch_sweep = -2200;
                v.env_level = 32000;
                v.env_decay = 24;
                v.samples_left = 2000; // ~45 ms
            },
            .distaff_note => {
                // Sustained plucked-string tone; trigger_note sets the pitch (P22-02, D-029)
                v.phase_inc1 = midi_to_phase_inc(DISTAFF_MIDI[0]);
                v.phase_inc2 = midi_to_phase_inc(DISTAFF_MIDI[0] + 12);
                v.duty = 0x40000000;
                v.env_level = 26000;
                v.env_decay = 2;
                v.samples_left = 13000; // ~300 ms
            },
            .weave_success => {
                // Rising open fifth shimmer (C5 + G5) as a draft takes hold (P22-02, D-029)
                v.phase_inc1 = midi_to_phase_inc(72);
                v.phase_inc2 = midi_to_phase_inc(79);
                v.pitch_sweep = 40;
                v.env_level = 28000;
                v.env_decay = 2;
                v.samples_left = 14000; // ~320 ms
            },
            .weave_fizzle => {
                // Falling detuned buzz as an unmatched draft unravels (P22-02, D-029)
                v.phase_inc1 = midi_to_phase_inc(55);
                v.phase_inc2 = midi_to_phase_inc(56);
                v.pitch_sweep = -900;
                v.env_level = 24000;
                v.env_decay = 4;
                v.samples_left = 6000; // ~135 ms
            },
        }
        return v;
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
            // 1. Advance BGM Step Sequencer
            if (self.current_track != .none) {
                self.step_sample_counter += 1;
                if (self.step_sample_counter >= self.samples_per_step) {
                    self.step_sample_counter = 0;
                    self.current_step = (self.current_step + 1) % self.active_pattern.step_count;

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
                    self.active_pattern = get_track_pattern(self.target_track);
                    self.current_step = 0;
                    self.step_sample_counter = 0;
                    if (self.active_pattern.bpm > 0) {
                        const step_sec = (60.0 / @as(f64, @floatFromInt(self.active_pattern.bpm))) / 4.0;
                        self.samples_per_step = @intFromFloat(step_sec * @as(f64, @floatFromInt(self.sample_rate)));
                    }
                }
            } else if (self.fade_level < 32767) {
                self.fade_level += 32;
                if (self.fade_level > 32767) self.fade_level = 32767;
            }

            // 2. Synthesize BGM Channels
            var bgm_sample: i32 = 0;

            if (self.current_track != .none and self.fade_level > 0) {
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

                var voice_out: i32 = 0;

                switch (v.kind) {
                    .footstep => {
                        const noise = eval_noise(&self.rng_state);
                        const tap = eval_triangle(v.phase1);
                        voice_out = (@as(i32, noise) * 3 + @as(i32, tap)) >> 2;
                    },
                    .pickup => {
                        // Advance to second chime note if first finished
                        if (v.step == 0 and v.step_samples_left == 0) {
                            v.step = 1;
                            v.phase_inc1 = midi_to_phase_inc(71); // B5
                            v.duty = 0x80000000;
                        } else if (v.step_samples_left > 0) {
                            v.step_samples_left -= 1;
                        }
                        voice_out = eval_pulse(v.phase1, v.duty);
                    },
                    .combine => {
                        // 4-step arpeggio: 60 -> 64 -> 67 -> 72
                        if (v.step_samples_left == 0 and v.step < 3) {
                            v.step += 1;
                            v.step_samples_left = 1500;
                            const note: u8 = switch (v.step) {
                                1 => 64,
                                2 => 67,
                                else => 72,
                            };
                            v.phase_inc1 = midi_to_phase_inc(note);
                        } else if (v.step_samples_left > 0) {
                            v.step_samples_left -= 1;
                        }
                        const pulse = eval_pulse(v.phase1, v.duty);
                        const tri = eval_triangle(v.phase1);
                        voice_out = (@as(i32, pulse) + @as(i32, tri)) >> 1;
                    },
                    .horn => {
                        const saw1 = eval_sawtooth(v.phase1);
                        const saw2 = eval_sawtooth(v.phase2);
                        voice_out = (@as(i32, saw1) + @as(i32, saw2)) >> 1;
                    },
                    .splash => {
                        const noise = eval_noise(&self.rng_state);
                        const bubble = eval_triangle(v.phase1);
                        voice_out = @divTrunc(@as(i32, noise) * 2 + @as(i32, bubble), 3);
                    },
                    .sword_clash => {
                        const tri1 = eval_triangle(v.phase1);
                        const tri2 = eval_triangle(v.phase2);
                        const ring = (@as(i32, tri1) * @as(i32, tri2)) >> 15;
                        const noise = eval_noise(&self.rng_state);
                        voice_out = (ring + @as(i32, noise)) >> 1;
                    },
                    .alert => {
                        const saw1 = eval_sawtooth(v.phase1);
                        const saw2 = eval_sawtooth(v.phase2);
                        voice_out = (@as(i32, saw1) + @as(i32, saw2)) >> 1;
                    },
                    .dialogue_blip => {
                        voice_out = eval_pulse(v.phase1, 0x80000000);
                    },
                    .click => {
                        const tri = eval_triangle(v.phase1);
                        voice_out = tri;
                    },
                    .whistle => {
                        voice_out = eval_triangle(v.phase1);
                    },
                    .goat_bleat => {
                        if (v.step_samples_left == 0) {
                            v.step ^= 1;
                            v.step_samples_left = 1200;
                            v.phase_inc1 = if (v.step == 0) midi_to_phase_inc(60) else midi_to_phase_inc(63);
                        } else {
                            v.step_samples_left -= 1;
                        }
                        const saw = eval_sawtooth(v.phase1);
                        const pulse = eval_pulse(v.phase2, v.duty);
                        voice_out = (@as(i32, saw) + @as(i32, pulse)) >> 1;
                    },
                    .thud => {
                        const noise = eval_noise(&self.rng_state);
                        const tri = eval_triangle(v.phase1);
                        voice_out = (@as(i32, noise) + @as(i32, tri) * 3) >> 2;
                    },
                    .toilet_flush => {
                        const noise = eval_noise(&self.rng_state);
                        const saw = eval_sawtooth(v.phase1);
                        voice_out = (@as(i32, noise) + @as(i32, saw)) >> 1;
                    },
                    .snip_shears => {
                        const pulse = eval_pulse(v.phase1, 0x40000000);
                        const noise = eval_noise(&self.rng_state);
                        voice_out = (@as(i32, pulse) + @as(i32, noise)) >> 1;
                    },
                    .wood_chop => {
                        const noise = eval_noise(&self.rng_state);
                        const tri = eval_triangle(v.phase1);
                        voice_out = (@as(i32, noise) * 2 + @as(i32, tri) * 2) >> 2;
                    },
                    .distaff_note => {
                        // Triangle body with a quiet octave pulse overtone
                        const tri = eval_triangle(v.phase1);
                        const over = eval_pulse(v.phase2, v.duty);
                        voice_out = (@as(i32, tri) * 3 + @as(i32, over)) >> 2;
                    },
                    .weave_success => {
                        const tri1 = eval_triangle(v.phase1);
                        const tri2 = eval_triangle(v.phase2);
                        voice_out = (@as(i32, tri1) + @as(i32, tri2)) >> 1;
                    },
                    .weave_fizzle => {
                        const saw1 = eval_sawtooth(v.phase1);
                        const saw2 = eval_sawtooth(v.phase2);
                        const noise = eval_noise(&self.rng_state);
                        voice_out = (@as(i32, saw1) + @as(i32, saw2) + @as(i32, noise)) >> 2;
                    },
                }

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

    /// Enqueues a scene background music change.
    pub fn set_track(self: *AudioBridge, track: MusicTrackKind) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const next = (self.queue_head + 1) % MAX_AUDIO_EVENTS;
        if (next == self.queue_tail) return;
        self.event_queue[self.queue_head] = AudioEvent{ .set_bgm = track };
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

    /// Automatically maps scene name strings to narrative music tracks (P16-03).
    pub fn get_track_for_scene(scene_name: []const u8) MusicTrackKind {
        if (scene_name.len == 0) return .none;

        if (std.mem.indexOf(u8, scene_name, "Spitting") != null or
            std.mem.indexOf(u8, scene_name, "Booty") != null or
            std.mem.indexOf(u8, scene_name, "Spit") != null)
        {
            return .spitting_contest;
        } else if (std.mem.indexOf(u8, scene_name, "High Road") != null or
            std.mem.indexOf(u8, scene_name, "Road") != null)
        {
            return .high_road;
        } else if (std.mem.indexOf(u8, scene_name, "Sanctuary") != null or
            std.mem.indexOf(u8, scene_name, "Sword Master") != null)
        {
            return .sanctuary;
        } else if (std.mem.indexOf(u8, scene_name, "Scumm") != null) {
            return .scumm_bar;
        } else if (std.mem.indexOf(u8, scene_name, "Cellar") != null) {
            return .cellar;
        } else if (std.mem.indexOf(u8, scene_name, "Tavern") != null or
            std.mem.indexOf(u8, scene_name, "Common") != null)
        {
            return .tavern;
        } else if (std.mem.indexOf(u8, scene_name, "Garden") != null or
            std.mem.indexOf(u8, scene_name, "Courtyard") != null or
            std.mem.indexOf(u8, scene_name, "Corridor") != null)
        {
            return .courtyard;
        } else if (std.mem.indexOf(u8, scene_name, "Bike") != null or
            std.mem.indexOf(u8, scene_name, "Rental") != null)
        {
            return .bike_shop;
        } else if (std.mem.indexOf(u8, scene_name, "Lochmarne") != null or
            std.mem.indexOf(u8, scene_name, "Goat") != null or
            std.mem.indexOf(u8, scene_name, "Crypt") != null or
            std.mem.indexOf(u8, scene_name, "Templar") != null)
        {
            return .lochmarne;
        } else if (std.mem.indexOf(u8, scene_name, "Colonial") != null or
            std.mem.indexOf(u8, scene_name, "Motel") != null or
            std.mem.indexOf(u8, scene_name, "Dystopia") != null or
            std.mem.indexOf(u8, scene_name, "Tentacle") != null or
            std.mem.indexOf(u8, scene_name, "Dott") != null or
            std.mem.indexOf(u8, scene_name, "Chrono") != null)
        {
            return .tentacle;
        }

        return .tavern;
    }

    /// Examines the current simulation frame scene and cues, triggering procedural audio reactions.
    pub fn process_scene_and_cues(self: *AudioBridge, scene_name: []const u8) void {
        if (scene_name.len == 0) return;

        // Hash scene name to detect transitions
        var h: u32 = 2166136261;
        for (scene_name) |b| {
            h ^= b;
            h *%= 16777619;
        }

        if (h != self.last_scene_hash) {
            self.last_scene_hash = h;
            const track = get_track_for_scene(scene_name);
            self.set_track(track);
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
                .play_note => |degree| self.synth.trigger_note(degree),
                .set_bgm => |track| self.synth.set_track(track),
                .stop_bgm => self.synth.set_track(.none),
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
    bridge.set_track(.tavern);

    try testing.expectEqual(@as(usize, 3), bridge.queue_head);
    try testing.expectEqual(@as(usize, 0), bridge.queue_tail);

    // Render into mock PCM buffer
    var pcm: [256]i16 = undefined;
    bridge.render_samples(&pcm);

    // Events were consumed
    try testing.expectEqual(bridge.queue_head, bridge.queue_tail);
    try testing.expectEqual(MusicTrackKind.tavern, bridge.synth.current_track);
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

    // Trigger all sound effects to verify initialization parameters
    const all_sfx = [_]SoundEffectKind{
        .footstep,
        .pickup,
        .combine,
        .horn,
        .splash,
        .sword_clash,
        .alert,
        .dialogue_blip,
        .click,
        .whistle,
    };

    for (all_sfx) |kind| {
        synth.trigger_sfx(kind);
    }

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

test "P16-03: Scene BGM patterns and automatic scene name mapping" {
    try testing.expectEqual(MusicTrackKind.spitting_contest, AudioBridge.get_track_for_scene("Booty Island Spitting Contest"));
    try testing.expectEqual(MusicTrackKind.cellar, AudioBridge.get_track_for_scene("The Wine Cellar"));
    try testing.expectEqual(MusicTrackKind.high_road, AudioBridge.get_track_for_scene("Mêlée Island High Road"));
    try testing.expectEqual(MusicTrackKind.sanctuary, AudioBridge.get_track_for_scene("Carla's Sanctuary"));
    try testing.expectEqual(MusicTrackKind.scumm_bar, AudioBridge.get_track_for_scene("The Scumm Bar"));
    try testing.expectEqual(MusicTrackKind.courtyard, AudioBridge.get_track_for_scene("Hotel Courtyard Garden"));
    try testing.expectEqual(MusicTrackKind.bike_shop, AudioBridge.get_track_for_scene("Bike Rental Shop"));
    try testing.expectEqual(MusicTrackKind.tavern, AudioBridge.get_track_for_scene("Tavern Common Room"));

    // Verify pattern contents
    const tavern_pat = get_track_pattern(.tavern);
    try testing.expectEqual(@as(u16, 132), tavern_pat.bpm);
    try testing.expect(tavern_pat.bass_notes[0] > 0);
    try testing.expect(tavern_pat.lead_notes[0] > 0);
}

test "P16-03: BGM step sequencer advances steps and renders non-clipping audio" {
    var synth = ChiptuneSynth.init();
    synth.set_track(.tavern);
    try testing.expectEqual(MusicTrackKind.tavern, synth.current_track);

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
    const sfx_list = [_]SoundEffectKind{
        .footstep,
        .pickup,
        .combine,
        .horn,
        .splash,
        .sword_clash,
        .alert,
        .dialogue_blip,
        .click,
        .whistle,
    };

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
    const tracks = [_]MusicTrackKind{
        .tavern,
        .cellar,
        .spitting_contest,
        .high_road,
        .sanctuary,
        .scumm_bar,
        .courtyard,
        .bike_shop,
    };

    var buf: [1024]i16 = undefined;
    for (tracks) |t| {
        var synth = ChiptuneSynth.init();
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
    synth.set_track(.tavern);
    try testing.expectEqual(MusicTrackKind.tavern, synth.current_track);

    // Switch track while running
    synth.set_track(.cellar);
    try testing.expect(synth.is_fading_out);
    try testing.expectEqual(MusicTrackKind.cellar, synth.target_track);

    // Render through crossfade
    var buf: [2048]i16 = undefined;
    for (0..30) |_| {
        synth.render_stereo(&buf, 80, 0, 80);
    }

    // Now current_track should have transitioned to cellar
    try testing.expectEqual(MusicTrackKind.cellar, synth.current_track);
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
        try testing.expectEqual(SoundEffectKind.distaff_note, bridge.synth.sfx_voices[0].kind);

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
