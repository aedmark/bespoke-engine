//! The Word Foundry, the Phase 44 spellbook proof (P44-04, D-136).
//!
//! Maren finds an abandoned foundry and three clues. Each clue teaches two words and none names
//! a combination, so she works the grammar out from the words alone. Two triples resolve and one
//! refuses, which shows that a wrong guess leaves the crucible as it was. The script owns the
//! words, the clues, and the effects; this proof owns staging, the attempts, and the transcript.
const std = @import("std");
const bespoke = @import("bespoke");
const golden = @import("golden_digest.zig");
const host = bespoke.host;
const spell = bespoke.spell;

pub const WORD_FOUNDRY_SCRIPT =
    \\scene: TheWordFoundry
    \\cast: Maren
    \\props: Bellows, ColdHearth, PatternBook, Crucible
    \\marks: Bench, Anvil
    \\
    \\relation Knows(who, what)
    \\
    \\spellbook FoundryLexicon:
    \\  power Spark, Forge
    \\  element Ember, Water
    \\  form Bolt, Ward
    \\  spell Kindle: Forge, Ember, Bolt
    \\  spell Quench: Spark, Water, Ward
    \\
    \\on cue LooksAt(Maren, Bellows):
    \\  say Maren: "Bellows: a spark to start the fire, and the forge for the long heat."
    \\  remember Knows(Maren, Spark)
    \\  remember Knows(Maren, Forge)
    \\
    \\on cue LooksAt(Maren, ColdHearth):
    \\  say Maren: "Embers still red in the grate, and a kettle of water on the hook."
    \\  remember Knows(Maren, Ember)
    \\  remember Knows(Maren, Water)
    \\
    \\on cue LooksAt(Maren, PatternBook):
    \\  say Maren: "Two plates: one a bolt of light, the other a standing ward."
    \\  remember Knows(Maren, Bolt)
    \\  remember Knows(Maren, Ward)
    \\
    \\on cue Kindle(Maren, Crucible):
    \\  say Maren: "Forge, ember, bolt. The crucible holds the light."
    \\  Crucible is glowing
    \\
    \\on cue Quench(Maren, Crucible):
    \\  say Maren: "Spark, water, ward. The metal goes still and hard."
    \\  Crucible is tempered
;

const Ids = struct {
    scene: bespoke.EntityId,
    maren: bespoke.EntityId,
    crucible: bespoke.EntityId,
    bellows: bespoke.EntityId,
    hearth: bespoke.EntityId,
    pattern_book: bespoke.EntityId,
    spark: bespoke.EntityId,
    forge: bespoke.EntityId,
    ember: bespoke.EntityId,
    water: bespoke.EntityId,
    bolt: bespoke.EntityId,
    ward: bespoke.EntityId,
    bench_wp: u16,
};

fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const scene = world.lookup_entity("TheWordFoundry").?;
    const ids = Ids{
        .scene = scene,
        .maren = world.lookup_entity("Maren").?,
        .crucible = world.lookup_entity("Crucible").?,
        .bellows = world.lookup_entity("Bellows").?,
        .hearth = world.lookup_entity("ColdHearth").?,
        .pattern_book = world.lookup_entity("PatternBook").?,
        .spark = world.lookup_entity("Spark").?,
        .forge = world.lookup_entity("Forge").?,
        .ember = world.lookup_entity("Ember").?,
        .water = world.lookup_entity("Water").?,
        .bolt = world.lookup_entity("Bolt").?,
        .ward = world.lookup_entity("Ward").?,
        .bench_wp = spatial.graph.find_waypoint_in_room(scene, "Bench").?,
    };
    try spatial.register_entity(ids.maren, ids.bench_wp, 10);
    return ids;
}

fn expect_true(value: bool, err: anyerror) !void {
    if (!value) return err;
}

fn name_of(world: *const bespoke.World, entity: bespoke.EntityId) []const u8 {
    return world.get_entity_name(entity) orelse "?";
}

fn refusal(outcome: spell.Outcome) ?spell.Refusal {
    return switch (outcome) {
        .refused => |why| why,
        .cast => null,
    };
}

/// One attempted triple: the words as the player chose them, then what the book made of them.
fn attempt(writer: anytype, world: *const bespoke.World, words: []const bespoke.EntityId, outcome: spell.Outcome) !void {
    try writer.writeAll("  -> ");
    for (words, 0..) |word, i| {
        if (i > 0) try writer.writeAll(" ");
        try writer.print("{s}", .{name_of(world, word)});
    }
    switch (outcome) {
        .cast => |resolved| try writer.print(": {s}.\n", .{name_of(world, resolved.entity)}),
        .refused => |why| try writer.print(": refused, {s}.\n", .{why.label()}),
    }
}

/// Deterministic proof: a refused cast before any word is learned, three clues that teach only
/// words, a triple the book does not hold, then the two spells the words allow.
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("       BeSpoke Engine: The Word Foundry (Spell Vocabulary)         \n");
    try writer.writeAll("       (Discovery * Two Spells * One Refusal)                      \n");
    try writer.writeAll("===================================================================\n\n");

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, WORD_FOUNDRY_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);

    try writer.writeAll("[Empty hands] Maren tries the phrase she has not earned.\n");
    const before = world.fact_count();
    var outcome = try host.combine(&vm, &compiled, ids.maren, ids.forge, ids.ember, ids.bolt, ids.crucible);
    try attempt(writer, &world, &.{ ids.forge, ids.ember, ids.bolt }, outcome);
    try writer.print("     {d} facts before, {d} after.\n", .{ before, world.fact_count() });
    try expect_true(refusal(outcome) == .unlearned_power, error.CastWithoutWords);
    try expect_true(world.fact_count() == before, error.RefusalChangedState);

    try writer.writeAll("\n[Words] Three clues. None names a combination.\n");
    const clues = [_]struct { prop: bespoke.EntityId, label: []const u8, words: [2]bespoke.EntityId }{
        .{ .prop = ids.bellows, .label = "Bellows", .words = .{ ids.spark, ids.forge } },
        .{ .prop = ids.hearth, .label = "Cold Hearth", .words = .{ ids.ember, ids.water } },
        .{ .prop = ids.pattern_book, .label = "Pattern Book", .words = .{ ids.bolt, ids.ward } },
    };
    for (clues) |clue| {
        _ = try vm.fire_cue(&compiled, "LooksAt", ids.maren, clue.prop, null);
        _ = try host.tick(&vm, &compiled);
        var speech_buf: [256]u8 = undefined;
        if (host.speech_this_tick(&world, &vm, &speech_buf)) |line| try writer.print("  [ {d}] {s}\n", .{ world.current_tick, line });
        try writer.print("     {s}: knows {s} and {s}.\n", .{ clue.label, name_of(&world, clue.words[0]), name_of(&world, clue.words[1]) });
        for (clue.words) |word| try expect_true(spell.knows(&world, ids.maren, word), error.WordNotLearned);
    }

    try writer.writeAll("\n[Fizzle] Three known words that the book does not join.\n");
    const before_fizzle = world.fact_count();
    outcome = try host.combine(&vm, &compiled, ids.maren, ids.forge, ids.water, ids.bolt, ids.crucible);
    try attempt(writer, &world, &.{ ids.forge, ids.water, ids.bolt }, outcome);
    try writer.print("     {d} facts before, {d} after.\n", .{ before_fizzle, world.fact_count() });
    try expect_true(refusal(outcome) == .no_such_spell, error.FizzleResolved);
    try expect_true(world.fact_count() == before_fizzle, error.FizzleChangedState);
    _ = try host.tick(&vm, &compiled);
    try expect_true(!host.has_state(&world, ids.crucible, "glowing"), error.FizzleLitTheCrucible);

    try writer.writeAll("\n[Kindle] Forge, ember, bolt.\n");
    outcome = try host.combine(&vm, &compiled, ids.maren, ids.forge, ids.ember, ids.bolt, ids.crucible);
    try attempt(writer, &world, &.{ ids.forge, ids.ember, ids.bolt }, outcome);
    _ = try host.tick(&vm, &compiled);
    var speech_buf: [256]u8 = undefined;
    if (host.speech_this_tick(&world, &vm, &speech_buf)) |line| try writer.print("  [ {d}] {s}\n", .{ world.current_tick, line });
    try expect_true(host.has_state(&world, ids.crucible, "glowing"), error.KindleFailed);

    try writer.writeAll("\n[Quench] Spark, water, ward.\n");
    outcome = try host.combine(&vm, &compiled, ids.maren, ids.spark, ids.water, ids.ward, ids.crucible);
    try attempt(writer, &world, &.{ ids.spark, ids.water, ids.ward }, outcome);
    _ = try host.tick(&vm, &compiled);
    if (host.speech_this_tick(&world, &vm, &speech_buf)) |line| try writer.print("  [ {d}] {s}\n", .{ world.current_tick, line });
    try expect_true(host.has_state(&world, ids.crucible, "tempered"), error.QuenchFailed);

    try writer.writeAll("\n===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: two spells found by their words alone.  \n");
    try writer.writeAll("===================================================================\n\n");
    try golden.final_facts(allocator, writer, &world);
}
