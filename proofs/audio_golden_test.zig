//! Audio characterization for the proofs of concept (P32-02d, docs/SEPARATION.md).
//!
//! Every sound effect, distaff note, and music track the proofs use is rendered offline by
//! the engine's synthesizer, and a hash of the samples is compared with
//! `proofs/golden/audio.txt`. A crossfade between two tracks and the choice of track for each
//! proof scene are recorded the same way. Moving sound definitions out of the engine (P32-02d)
//! must leave every line unchanged.
//!
//! The synthesizer is integer arithmetic over a seeded noise generator, so the samples do not
//! depend on the machine. Regenerate deliberately: `zig build test-proofs -Dupdate-goldens`.
//! On a mismatch, `proofs/golden/audio.actual.txt` is written beside the golden.
const std = @import("std");
const bespoke = @import("bespoke");
const options = @import("golden_options");
const audio = bespoke.audio;
const art = @import("art.zig");

const GOLDEN_NAME = "audio.txt";
const ACTUAL_NAME = "audio.actual.txt";
const MASTER: u8 = 80;
const SFX_VOL: u8 = 85;
const BGM_VOL: u8 = 75;
/// Longer than the longest effect (18,000 samples), so every effect is heard to silence.
const SFX_FRAMES: usize = 20_000;

/// Every scene name the proofs use, plus an empty and an unknown name.
const SCENES = [_][]const u8{
    "",                           "Nowhere In Particular",
    "Tavern",                     "CellarRoom",
    "Spitting Competition",       "Hotel Corridor",
    "Hotel Garden",               "Bike Rental Shop",
    "Tidewalk",                   "Fencing Yard",
    "Drowned Lantern",            "Living Village",
    "Lochmarne Castle Courtyard", "Templar Crypt",
    "Colonial Workshop",          "Motel Lobby",
    "Dystopian Guard Post",       "Suburban Bedroom",
    "Middlesex High School",      "Tangent Vortex Ridge",
    "Bell Tower Base",            "Bell Tower Belfry",
    "Saltglass Stockade",
};

/// The operations the record needs from the sound system. P32-02d changes how a sound is
/// named and where it is defined; only this adapter changes with it, never the labels.
const Sounds = struct {
    /// Effect labels, in the order the golden records them.
    const sfx_names = [_][]const u8{
        "footstep",      "pickup",       "combine",    "horn",
        "splash",        "sword_clash",  "alert",      "dialogue_blip",
        "click",         "whistle",      "goat_bleat", "thud",
        "toilet_flush",  "snip_shears",  "wood_chop",  "distaff_note",
        "weave_success", "weave_fizzle", "sizzle",
    };

    fn synth() audio.ChiptuneSynth {
        var s = audio.ChiptuneSynth.init();
        s.soundtrack = &art.soundtrack;
        return s;
    }
    fn trigger(s: *audio.ChiptuneSynth, name: []const u8) void {
        if (std.meta.stringToEnum(audio.SoundEffectKind, name)) |kind| {
            s.trigger_sfx(kind);
        } else {
            s.trigger_host_sfx(@intFromEnum(std.meta.stringToEnum(art.Sfx, name).?));
        }
    }
    fn play(s: *audio.ChiptuneSynth, name: []const u8) void {
        s.set_track(track_by_name(name));
    }
    fn for_scene(name: []const u8) []const u8 {
        const index = art.soundtrack.track_for_scene.?(name) orelse return "none";
        return art.soundtrack.tracks[index].name;
    }
    fn track_by_name(name: []const u8) u8 {
        return art.track(std.meta.stringToEnum(art.Track, name).?);
    }
    fn track_names() []const audio.Music {
        return art.soundtrack.tracks;
    }
};

fn hash_samples(buf: []const i16) u64 {
    return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(buf));
}

fn render(allocator: std.mem.Allocator, s: *audio.ChiptuneSynth, frames: usize) !u64 {
    const buf = try allocator.alloc(i16, frames * 2);
    defer allocator.free(buf);
    s.render_stereo(buf, MASTER, SFX_VOL, BGM_VOL);
    return hash_samples(buf);
}

/// An engine MML score, not a proof's (P28-02, D-061): every envelope preset, a volume change,
/// a tempo change from the bass part, all three drums, and parts of unequal length looping
/// together. Two passes are recorded so the whole-score loop is heard.
const MML_DEMO = [4][]const u8{
    "t132 o5 l8 @1 c e g > c < @2 g e @4 c4 L @5 d f a f @6 e2 @7 c4 @3 r4",
    "o3 l4 @0 c c g g t120 L a f g g",
    "o4 l2 v10 @7 e g L f e",
    "l8 v12 k h s h k k s h L [k h s h]2",
};

fn record_mml(allocator: std.mem.Allocator, w: anytype) !void {
    var parsed: [4]bespoke.mml.Score = undefined;
    var score = audio.MmlScore{};
    for (MML_DEMO, 0..) |text, i| {
        var diag = bespoke.mml.Diagnostic{};
        parsed[i] = try bespoke.mml.parse(allocator, text, if (i == 3) .percussion else .melodic, &diag);
        score.parts[i] = audio.MmlTrack.of(&parsed[i]);
    }
    defer for (&parsed) |*p| p.deinit();
    const music = [_]audio.Music{.{ .name = "mml-demo", .score = &score }};
    const soundtrack = audio.Soundtrack{ .tracks = &music };
    var s = audio.ChiptuneSynth.init();
    s.soundtrack = &soundtrack;
    s.set_track(0);
    // Intro (4 quarters) plus two passes of the loop (4 quarters each) at 120 bpm or faster.
    try w.print("mml/demo: {x:0>16}\n", .{try render(allocator, &s, 22_050 * 12)});
}

fn record_all(allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const w = out.writer();

    for (Sounds.sfx_names) |sfx| {
        var s = Sounds.synth();
        Sounds.trigger(&s, sfx);
        try w.print("sfx/{s}: {x:0>16}\n", .{ sfx, try render(allocator, &s, SFX_FRAMES) });
    }

    var degree: u8 = 0;
    while (degree < audio.DISTAFF_NOTE_COUNT) : (degree += 1) {
        var s = Sounds.synth();
        s.trigger_note(degree);
        try w.print("note/{d}: {x:0>16}\n", .{ degree, try render(allocator, &s, SFX_FRAMES) });
    }

    for (Sounds.track_names()) |music| {
        var s = Sounds.synth();
        Sounds.play(&s, music.name);
        // One full pass of the pattern, and a little of the next.
        const frames = @as(usize, s.samples_per_step) * s.active_pattern.step_count + 2_000;
        try w.print("track/{s}: {x:0>16}\n", .{ music.name, try render(allocator, &s, frames) });
    }

    // Arranged tracks (P34-08, D-089): the length before the first exact repeat, and the
    // first three passes, so a section change and its transposes and mutes are heard.
    for (Sounds.track_names()) |music| {
        if (music.arrangement.len == 0) continue;
        const seconds = try @import("music.zig").seconds_before_repeat(allocator, .{ .sections = music.sections, .arrangement = music.arrangement });
        var s = Sounds.synth();
        Sounds.play(&s, music.name);
        var frames: usize = 0;
        for (music.arrangement[0..3]) |pass| {
            const p = audio.arranged_pattern(&music, pass);
            frames += @as(usize, s.samples_per_step) * p.step_count;
        }
        try w.print("arrangement/{s}: {d} passes, {d:.1}s before repeat, {x:0>16}\n", .{ music.name, music.arrangement.len, seconds, try render(allocator, &s, frames + 2_000) });
    }

    {
        // A scene change while music plays: the old track fades out, the new one fades in.
        var s = Sounds.synth();
        Sounds.play(&s, "tavern");
        const before = try render(allocator, &s, 20_000);
        Sounds.play(&s, "cellar");
        const after = try render(allocator, &s, 40_000);
        try w.print("fade/tavern->cellar: {x:0>16} {x:0>16}\n", .{ before, after });
    }

    for (SCENES) |scene| {
        try w.print("scene/{s}: {s}\n", .{ scene, Sounds.for_scene(scene) });
    }

    try record_mml(allocator, w);
    return out;
}

test "P32-02d: every proof sound renders the samples recorded in its audio golden" {
    const allocator = std.testing.allocator;
    var dir = try std.fs.cwd().makeOpenPath(options.golden_dir, .{});
    defer dir.close();

    var actual = try record_all(allocator);
    defer actual.deinit();

    if (options.update_goldens) {
        try dir.writeFile(.{ .sub_path = GOLDEN_NAME, .data = actual.items });
        dir.deleteFile(ACTUAL_NAME) catch {};
        return;
    }

    const expected = dir.readFileAlloc(allocator, GOLDEN_NAME, 1 << 20) catch |err| {
        std.debug.print("audio golden {s}/{s} unreadable ({s}); run `zig build test-proofs -Dupdate-goldens`\n", .{ options.golden_dir, GOLDEN_NAME, @errorName(err) });
        return error.AudioGoldenMissing;
    };
    defer allocator.free(expected);

    if (std.mem.eql(u8, expected, actual.items)) {
        dir.deleteFile(ACTUAL_NAME) catch {};
        return;
    }
    try dir.writeFile(.{ .sub_path = ACTUAL_NAME, .data = actual.items });
    var want_lines = std.mem.splitScalar(u8, expected, '\n');
    var got_lines = std.mem.splitScalar(u8, actual.items, '\n');
    var changed: usize = 0;
    while (true) {
        const want = want_lines.next();
        const got = got_lines.next();
        if (want == null and got == null) break;
        if (want != null and got != null and std.mem.eql(u8, want.?, got.?)) continue;
        changed += 1;
        std.debug.print("\naudio differs:\n  golden: {s}\n  actual: {s}\n", .{ want orelse "<none>", got orelse "<none>" });
    }
    std.debug.print("\n{d} line(s) differ; record written to {s}/{s}\n", .{ changed, options.golden_dir, ACTUAL_NAME });
    return error.AudioGoldenMismatch;
}
