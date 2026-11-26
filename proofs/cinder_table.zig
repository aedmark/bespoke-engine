//! The Cinder Table, the Phase 44 decision proof (P44-05, D-137).
//!
//! Three seats play four rounds of a trick game at a foundry table. Each seat knows only its own
//! four cards, and the engine offers a seat only the options it knows, so a hand is private
//! without a hidden-information rule. Every play is a scored decision: follow the led suit when
//! it is in hand, and lead a suit an opponent has shown to be void in once that is public. The
//! script owns the hands, the scoring lines, and the effects; this proof owns staging, the tick
//! loop, the checks, and the transcript.
const std = @import("std");
const bespoke = @import("bespoke");
const golden = @import("golden_digest.zig");
const host = bespoke.host;
const decision = bespoke.decision;
const spell = bespoke.spell;
const ListWriter = bespoke.ListWriter;

/// Twelve cards: four rounds of three seats.
pub const TOTAL_PLAYS: usize = 12;

pub const CINDER_TABLE_SCRIPT =
    \\scene: TheCinderTable
    \\cast: Maren, Ossic, Ines
    \\props: TallyBoard, Tokens
    \\marks: Bench, Stove
    \\
    \\entity Salt, Reed, Cinder
    \\entity SaltOne, SaltTwo, SaltThree, SaltFour
    \\entity ReedOne, ReedTwo, ReedThree, ReedFour
    \\entity CinderOne, CinderTwo, CinderThree, CinderFour
    \\
    \\relation Knows(who, what)
    \\relation Played(who, what)
    \\relation Turn(who)
    \\relation SuitLed(suit)
    \\relation Void(who, suit)
    \\relation Chose(decision, option)
    \\
    \\remember Knows(Maren, SaltOne)
    \\remember Knows(Maren, CinderOne)
    \\remember Knows(Maren, CinderTwo)
    \\remember Knows(Maren, SaltTwo)
    \\remember Knows(Ossic, SaltThree)
    \\remember Knows(Ossic, ReedOne)
    \\remember Knows(Ossic, ReedTwo)
    \\remember Knows(Ossic, ReedThree)
    \\remember Knows(Ines, SaltFour)
    \\remember Knows(Ines, CinderThree)
    \\remember Knows(Ines, CinderFour)
    \\remember Knows(Ines, ReedFour)
    \\remember Turn(Maren)
    \\remember TrickEmpty(TheCinderTable)
    \\
    \\decision LeadMaren:
    \\  actor Maren
    \\  fires CardPlayed
    \\  requires Turn(Maren)
    \\  option SaltOne:
    \\    picks 6 when TrickEmpty(TheCinderTable)
    \\  option CinderOne:
    \\    picks 5 when TrickOpen(TheCinderTable)
    \\  option CinderTwo:
    \\    picks 4 when TrickOpen(TheCinderTable)
    \\    picks 6 when Void(Ossic, Cinder)
    \\  option SaltTwo:
    \\    picks 3 when TrickOpen(TheCinderTable)
    \\
    \\decision FollowOssic:
    \\  actor Ossic
    \\  fires CardPlayed
    \\  requires Turn(Ossic)
    \\  option SaltThree:
    \\    picks 3 when SuitLed(Salt)
    \\  option ReedOne:
    \\    picks 2 when SuitLed(Cinder)
    \\  option ReedTwo:
    \\    picks 1 when SuitLed(Cinder)
    \\  option ReedThree:
    \\    picks 3 when SuitLed(Salt)
    \\
    \\decision FollowInes:
    \\  actor Ines
    \\  fires CardPlayed
    \\  requires Turn(Ines)
    \\  option SaltFour:
    \\    picks 3 when SuitLed(Salt)
    \\  option CinderThree:
    \\    picks 3 when SuitLed(Cinder)
    \\  option CinderFour:
    \\    picks 2 when SuitLed(Cinder)
    \\  option ReedFour:
    \\    picks 1 when SuitLed(Salt)
    \\
    \\on cue CardPlayed(Maren, SaltOne):
    \\  remember Played(Maren, SaltOne)
    \\  forget Knows(Maren, SaltOne)
    \\  forget SuitLed(Salt)
    \\  forget SuitLed(Reed)
    \\  forget SuitLed(Cinder)
    \\  remember SuitLed(Salt)
    \\  forget TrickEmpty(TheCinderTable)
    \\  remember TrickOpen(TheCinderTable)
    \\  forget Turn(Maren)
    \\  remember Turn(Ossic)
    \\
    \\on cue CardPlayed(Maren, CinderOne):
    \\  remember Played(Maren, CinderOne)
    \\  forget Knows(Maren, CinderOne)
    \\  forget SuitLed(Salt)
    \\  forget SuitLed(Reed)
    \\  forget SuitLed(Cinder)
    \\  remember SuitLed(Cinder)
    \\  forget TrickEmpty(TheCinderTable)
    \\  remember TrickOpen(TheCinderTable)
    \\  forget Turn(Maren)
    \\  remember Turn(Ossic)
    \\
    \\on cue CardPlayed(Maren, CinderTwo):
    \\  remember Played(Maren, CinderTwo)
    \\  forget Knows(Maren, CinderTwo)
    \\  forget SuitLed(Salt)
    \\  forget SuitLed(Reed)
    \\  forget SuitLed(Cinder)
    \\  remember SuitLed(Cinder)
    \\  forget TrickEmpty(TheCinderTable)
    \\  remember TrickOpen(TheCinderTable)
    \\  forget Turn(Maren)
    \\  remember Turn(Ossic)
    \\
    \\on cue CardPlayed(Maren, SaltTwo):
    \\  remember Played(Maren, SaltTwo)
    \\  forget Knows(Maren, SaltTwo)
    \\  forget SuitLed(Salt)
    \\  forget SuitLed(Reed)
    \\  forget SuitLed(Cinder)
    \\  remember SuitLed(Salt)
    \\  forget TrickEmpty(TheCinderTable)
    \\  remember TrickOpen(TheCinderTable)
    \\  forget Turn(Maren)
    \\  remember Turn(Ossic)
    \\
    \\on cue CardPlayed(Ossic, SaltThree):
    \\  remember Played(Ossic, SaltThree)
    \\  forget Knows(Ossic, SaltThree)
    \\  forget Turn(Ossic)
    \\  remember Turn(Ines)
    \\
    \\on cue CardPlayed(Ossic, ReedOne):
    \\  remember Played(Ossic, ReedOne)
    \\  forget Knows(Ossic, ReedOne)
    \\  remember Void(Ossic, Cinder)
    \\  say Ossic: "No cinder left. I throw this one away."
    \\  forget Turn(Ossic)
    \\  remember Turn(Ines)
    \\
    \\on cue CardPlayed(Ossic, ReedTwo):
    \\  remember Played(Ossic, ReedTwo)
    \\  forget Knows(Ossic, ReedTwo)
    \\  forget Turn(Ossic)
    \\  remember Turn(Ines)
    \\
    \\on cue CardPlayed(Ossic, ReedThree):
    \\  remember Played(Ossic, ReedThree)
    \\  forget Knows(Ossic, ReedThree)
    \\  forget Turn(Ossic)
    \\  remember Turn(Ines)
    \\
    \\on cue CardPlayed(Ines, SaltFour):
    \\  remember Played(Ines, SaltFour)
    \\  forget Knows(Ines, SaltFour)
    \\  forget Turn(Ines)
    \\  remember Turn(Maren)
    \\
    \\on cue CardPlayed(Ines, CinderThree):
    \\  remember Played(Ines, CinderThree)
    \\  forget Knows(Ines, CinderThree)
    \\  forget Turn(Ines)
    \\  remember Turn(Maren)
    \\
    \\on cue CardPlayed(Ines, CinderFour):
    \\  remember Played(Ines, CinderFour)
    \\  forget Knows(Ines, CinderFour)
    \\  forget Turn(Ines)
    \\  remember Turn(Maren)
    \\
    \\on cue CardPlayed(Ines, ReedFour):
    \\  remember Played(Ines, ReedFour)
    \\  forget Knows(Ines, ReedFour)
    \\  forget Turn(Ines)
    \\  remember Turn(Maren)
;

pub const Ids = struct {
    scene: bespoke.EntityId,
    maren: bespoke.EntityId,
    ossic: bespoke.EntityId,
    ines: bespoke.EntityId,
    bench_wp: u16,
    /// One decision per seat, in turn order, so index 0 is Maren's.
    decisions: [3]bespoke.EntityId,
};

pub fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const scene = world.lookup_entity("TheCinderTable").?;
    const ids = Ids{
        .scene = scene,
        .maren = world.lookup_entity("Maren").?,
        .ossic = world.lookup_entity("Ossic").?,
        .ines = world.lookup_entity("Ines").?,
        .bench_wp = spatial.graph.find_waypoint_in_room(scene, "Bench").?,
        .decisions = .{
            world.lookup_entity("LeadMaren").?,
            world.lookup_entity("FollowOssic").?,
            world.lookup_entity("FollowInes").?,
        },
    };
    try spatial.register_entity(ids.maren, ids.bench_wp, 10);
    try spatial.register_entity(ids.ossic, ids.bench_wp, 10);
    try spatial.register_entity(ids.ines, ids.bench_wp, 10);
    return ids;
}

fn expect_true(value: bool, err: anyerror) !void {
    if (!value) return err;
}

fn name_of(world: *const bespoke.World, entity: bespoke.EntityId) []const u8 {
    return world.get_entity_name(entity) orelse "?";
}

fn option_of(decl: decision.Decision, entity: bespoke.EntityId) ?decision.Option {
    for (decl.options) |option| if (option.entity == entity) return option;
    return null;
}

const Play = struct {
    actor: bespoke.EntityId,
    option: bespoke.EntityId,
    score: i32,
};

const Run = struct {
    plays: [TOTAL_PLAYS]Play = undefined,
    len: usize = 0,
    rounds: usize = 0,
    /// The last option each seat chose, so a choice is reported once.
    last: [3]?bespoke.EntityId = .{ null, null, null },
};

/// Ticks the table until twelve cards are played, reporting each choice through `writer`. The
/// caller ticks once for the deal, so the first call reports whatever that tick decided.
fn play_game(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    ids: Ids,
    writer: anytype,
    run: *Run,
) !void {
    var ticks: usize = 0;
    while (run.len < TOTAL_PLAYS and ticks < TOTAL_PLAYS * 4) : (ticks += 1) {
        if (ticks > 0) _ = try host.tick(vm, compiled);

        var speech_buf: [512]u8 = undefined;
        if (host.speech_this_tick(world, vm, &speech_buf)) |line|
            try writer.print("  [ {d}] {s}\n", .{ world.current_tick, line });

        for (ids.decisions, 0..) |entity, index| {
            const option = decision.chosen(world, entity) orelse continue;
            if (run.last[index]) |prior| if (prior == option) continue;
            const decl = &compiled.decisions.items[index].decision;
            const found = option_of(decl.*, option) orelse return error.UnknownOption;
            const score = decision.score_of(world, found);
            // The engine offers only what the seat knows, so a play from another hand would fail
            // here before the transcript could record it.
            try expect_true(spell.knows(world, decl.actor, option), error.PlayedACardItDidNotKnow);
            if (decl.actor == ids.maren) {
                run.rounds += 1;
                try writer.print("\n[Round {d}] Maren leads.\n", .{run.rounds});
            }
            try writer.print("  {s} plays {s} ({d}).\n", .{ name_of(world, decl.actor), name_of(world, option), score });
            run.last[index] = option;
            run.plays[run.len] = .{
                .actor = decl.actor,
                .option = option,
                .score = score,
            };
            run.len += 1;
        }
    }
}

fn run_headless_inner(allocator: std.mem.Allocator, writer: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, CINDER_TABLE_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);

    // The deal is the initializer's. Saving before it runs keeps the world a player would branch
    // from, and the restore below runs the same initializer again.
    var opening = std.array_list.Managed(u8).init(allocator);
    defer opening.deinit();
    var opening_writer = ListWriter.init(&opening);
    _ = try bespoke.write_save_state(allocator, &opening_writer.writer, &world, &spatial, &vm, .{ .description = "The Cinder Table deal" });

    // First pass: silent, and from the saved deal, so the replay is the whole table.
    var first = Run{};
    var sink = std.array_list.Managed(u8).init(allocator);
    defer sink.deinit();
    var sink_writer = ListWriter.init(&sink);
    try host.run_initial_statements(&world, &vm, &compiled);
    try play_game(&world, &vm, &compiled, ids, &sink_writer.writer, &first);
    try expect_true(first.len == TOTAL_PLAYS, error.TableNotFinished);

    // Second pass: restore the deal and report it.
    var restore_stream: std.Io.Reader = .fixed(opening.items);
    _ = try bespoke.read_save_state(allocator, &restore_stream, &world, &spatial, &vm);
    try expect_true(decision.chosen(&world, ids.decisions[0]) == null, error.RewindKeptChoice);
    try host.run_initial_statements(&world, &vm, &compiled);
    var second = Run{};

    try writer.writeAll("[Deal] Three seats, four cards each, and each seat knows only its own.\n");
    for (compiled.decisions.items) |decl| {
        try writer.print("  {s}:", .{name_of(&world, decl.decision.actor)});
        for (decl.decision.options) |option| {
            if (!spell.knows(&world, decl.decision.actor, option.entity)) continue;
            try writer.print(" {s}", .{name_of(&world, option.entity)});
        }
        try writer.writeAll("\n");
    }

    try play_game(&world, &vm, &compiled, ids, writer, &second);
    try expect_true(second.len == TOTAL_PLAYS, error.TableNotFinished);

    // The replayed table makes the same twelve choices, card for card and score for score.
    try expect_true(first.len == second.len, error.ReplayShortened);
    for (first.plays[0..first.len], second.plays[0..second.len]) |a, b| {
        try expect_true(a.actor == b.actor and a.option == b.option and a.score == b.score, error.ReplayDiverged);
    }

    // Every seat played four cards, and the discard is public knowledge.
    var played = [3]usize{ 0, 0, 0 };
    for (second.plays[0..second.len]) |play| {
        if (play.actor == ids.maren) played[0] += 1;
        if (play.actor == ids.ossic) played[1] += 1;
        if (play.actor == ids.ines) played[2] += 1;
    }
    try expect_true(played[0] == 4 and played[1] == 4 and played[2] == 4, error.SeatSkipped);
    const void_rel = world.lookup_relation("Void") orelse return error.NoVoidFact;
    try expect_true(world.has_fact(ids.ossic, void_rel, world.lookup_entity("Cinder").?.to_int()), error.DiscardUnrecorded);

    // The inference is the point: Ossic's discard raises the lead Maren already held from five
    // points to ten, and that is why the second cinder comes out in round three.
    var before_void: ?i32 = null;
    var after_void: ?i32 = null;
    for (second.plays[0..second.len]) |play| {
        if (play.actor != ids.maren) continue;
        if (play.option == world.lookup_entity("CinderOne").?) before_void = play.score;
        if (play.option == world.lookup_entity("CinderTwo").?) after_void = play.score;
    }
    try expect_true(before_void != null and after_void != null, error.CinderNotLed);
    try expect_true(after_void.? > before_void.?, error.InferenceDidNotRaiseTheScore);

    try writer.writeAll("\n[Rewind] The same deal replayed makes the same twelve plays.\n");
    try writer.print("     Ossic is void in cinder after round two; Maren's cinder lead rises from {d} to {d}.\n", .{ before_void.?, after_void.? });
    try writer.writeAll("\n===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: private hands, scored plays, one inference.\n");
    try writer.writeAll("===================================================================\n\n");
    try golden.final_facts(allocator, writer, &world);
}

pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("       BeSpoke Engine: The Cinder Table (Private Hands)\n");
    try writer.writeAll("       (Four Rounds * Scored Plays * One Inference)\n");
    try writer.writeAll("===================================================================\n\n");
    try run_headless_inner(allocator, writer);
}
