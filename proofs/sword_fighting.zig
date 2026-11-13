const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const SwordKey = enum(u16) { duel_pike, duel_vell, talk_barkeep, wait_50 };

const sword_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_d, .action = @intFromEnum(SwordKey.duel_pike), .sfx = art.sfx(.sword_clash) },
    .{ .key = bespoke.display.renderer.c.SDLK_c, .action = @intFromEnum(SwordKey.duel_vell), .sfx = art.sfx(.sword_clash) },
    .{ .key = bespoke.display.renderer.c.SDLK_t, .action = @intFromEnum(SwordKey.talk_barkeep) },
    .{ .key = bespoke.display.renderer.c.SDLK_w, .action = @intFromEnum(SwordKey.wait_50) },
});

/// The Brackwater Barbs script: a fencing duel of barbs and comebacks, and a barkeep who
/// tires of repeated questions (P35-02 replaced the borrowed duel with this original).
pub const SWORD_FIGHTING_SCRIPT =
    \\scene: Tidewalk
    \\cast: Tamsin, BosunPike, OldGannet
    \\marks: TidewalkWest, TidewalkMid, TidewalkEast
    \\
    \\scene: Fencing Yard
    \\cast: Vell
    \\marks: YardGate, YardCircle, YardDoor
    \\
    \\scene: Drowned Lantern
    \\cast: Barkeep, Citizen
    \\marks: LanternDoor, CounterMark, FireplaceMark
    \\
    \\duel BrackwaterBarbs:
    \\  pair Barb1:
    \\    challenge "You wield that sword like a mop handle!"
    \\    reply "Good, then that means I can still wipe the floor with you."
    \\    variant 1 "I've seen housemaids wield a grittier scour!"
    \\  pair Barb2:
    \\    challenge "I've sunk ships with less effort than this!"
    \\    reply "Was that before or after you climbed aboard?"
    \\    variant 1 "Whole fleets have turned tail at the sight of me!"
    \\  pair Barb3:
    \\    challenge "Your parries are slower than the waning tide!"
    \\    reply "This tide is patient; I always come back!"
    \\    variant 1 "I'll have you beaten before the sun rises!"
    \\  pair Barb4:
    \\    challenge "My grandmother lunges better than you!"
    \\    reply "Then bring her. I'd like a real fight."
    \\    variant 1 "My old, blind tutor could best you with one hand!"
    \\  pair Barb5:
    \\    challenge "You'll be feeding the gulls by sundown!"
    \\    reply "Unfortunately for you, they'll be too busy picking apart your reputation."
    \\    variant 1 "The crabs are already laying the table for you!"
    \\  pair Barb6:
    \\    challenge "I wielded a blade before I learned to walk!"
    \\    reply "And you've been tripping over yourself ever since."
    \\    variant 1 "I was crossing blades while you were crossing the schoolyard!"
    \\  pair Barb7:
    \\    challenge "Your sword is as dull as your intellect!"
    \\    reply "How convenient! You'll be asleep for the final blow!"
    \\    variant 1 "Every thrust of your sword bores me endlessly!"
    \\  pair Barb8:
    \\    challenge "I'll carve my initials in your chest!"
    \\    reply "Do take your time; I know how much you struggle with spelling."
    \\    variant 1 "I'll engrave my name on your scalp!"
    \\  pair Barb9:
    \\    challenge "You smell like a fishmonger's apron!"
    \\    reply "I find the fragrance befitting for the occasion, don't you?"
    \\    variant 1 "Phew, with that stench... I can see gulls follow you for a reason!"
    \\  pair Barb10:
    \\    challenge "I've eaten better fencers than you for breakfast!"
    \\    reply "Then you must be starving by now."
    \\    variant 1 "I dine from the skulls of my vanquished enemies!"
    \\  pair Barb11:
    \\    challenge "Your stance is a disgrace to the guild!"
    \\    reply "And your personality is an insult to humanity!"
    \\    variant 1 "Your technique is an abomination to fencing."
    \\  pair Barb12:
    \\    challenge "Surrender now and I'll spare your dignity!"
    \\    reply "Too late. You spent yours on that suit."
    \\    variant 1 "Kneel and I may let you keep your pride!"
    \\  pair Barb13:
    \\    challenge "I've got more scars than you've had hot dinners!"
    \\    reply "Fencing that badly, I'm not surprised."
    \\    variant 1 "Every mark on my arms is a duel I've won!"
    \\  pair Barb14:
    \\    challenge "My cousin could beat you with a spoon!"
    \\    reply "Not to worry; it'll be the sharpest thing on your side."
    \\    variant 1 "I could best you armed only with a soup ladle!"
    \\  pair Barb15:
    \\    challenge "You'll be begging for mercy before the bell rings!"
    \\    reply "I'll ring it myself, so they know when to collect you."
    \\    variant 1 "By the next chime you'll be on your knees!"
    \\  fallback "Er... is that the time?"
    \\  fallback "I have to return some video tapes."
    \\  fallback "I think I left my oven on! Gotta go!"
    \\  win 3
    \\  relations HeardBarb MasteredComeback Counters VellVariant FencingTier Advantage DuelsWon
    \\  tier Vell 1
    \\  fatigue Inquiries "welcoming":
    \\    stage AnnoyedWith 2 100 "annoyed"
    \\    stage FuriousWith 3 250 "furious"
    \\
    \\routine PatrolTidewalk(BosunPike):
    \\  loop:
    \\    walk BosunPike to TidewalkWest
    \\    wait 30 ticks
    \\    walk BosunPike to TidewalkEast
    \\    wait 30 ticks
    \\
    \\routine BarkeepTending(Barkeep):
    \\  loop:
    \\    walk Barkeep to CounterMark
    \\    wait 40 ticks
    \\    say Barkeep: "Finest cider in Brackwater!"
    \\    wait 40 ticks
    \\
    \\on cue TalksTo(Tamsin, Barkeep):
    \\  choice "Tell me about Harbourmaster Odell." if not Inquired(Tamsin, Odell, _):
    \\    say Barkeep: "Odell? Counts every barrel twice and trusts nobody once."
    \\    remember Inquired(Tamsin, Odell, 1)
    \\  choice "Tell me more about Harbourmaster Odell." if Inquired(Tamsin, Odell, 1):
    \\    say Barkeep: "I've told you already. His office is above the customs shed."
    \\    remember Inquired(Tamsin, Odell, 2)
    \\    remember AnnoyedWith(Barkeep, Tamsin) for 100 ticks
    \\  choice "About Harbourmaster Odell..." if AnnoyedWith(Barkeep, Tamsin):
    \\    say Barkeep: "Ask me once more and you'll be drinking from the canal!"
    \\    remember FuriousWith(Barkeep, Tamsin) for 250 ticks
    \\  choice "Got any work for a fencer?":
    \\    say Barkeep: "Try the yard by the lighthouse. Ask for Mistress Vell."
;

const duel_mod = bespoke.duel;
const ANNOYED: usize = 0;
const FURIOUS: usize = 1;

/// Runs the Brackwater Barbs duel and the barkeep's patience headlessly, with checks.
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("            BeSpoke Engine: Brackwater Barbs Scenario              \n", .{});
    try writer.print(" (Combinatorial Queries * Target Invariants * Repetition Fatigue) \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Lowering Brackwater stageplay script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();

    if (compiled.duels.items.len != 1) return error.MissingSwordDuel;
    const duel_decl = &compiled.duels.items[0];
    var duel = try duel_mod.Duel.init(&world, duel_decl.config);
    var fatigue = try duel_mod.InquiryFatigue.init(&world, duel_decl.fatigue);
    const swagger_rel = try world.intern_relation("Swagger", .property);
    const path_chosen_rel = try world.intern_relation("PathChosen", .property);

    const tamsin = try world.intern_entity("Tamsin");
    const bosun_pike = try world.intern_entity("BosunPike");
    const old_gannet = try world.intern_entity("OldGannet");
    const vell = try world.intern_entity("Vell");
    const barkeep = try world.intern_entity("Barkeep");
    const citizen = try world.intern_entity("Citizen");
    _ = citizen;

    try duel_decl.apply_tiers(&duel);

    var timeline = bespoke.host.Timeline.init(allocator);
    defer timeline.deinit();

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    // Snapshot 0: Baseline state
    try timeline.record(&world);

    // -------------------------------------------------------------------------
    // Step 1: Epistemological Zero Baseline & Learning the First Barb and Comeback
    // -------------------------------------------------------------------------
    try writer.print("[Step 1: Epistemological Zero Baseline]\n", .{});
    try writer.print("   -> Tamsin arrives in Brackwater with 0 known barbs and 0 mastered comebacks.\n", .{});

    const barb_1 = duel.challenge(0, 0);
    const reply_1 = duel.reply(0);
    const barb_5 = duel.challenge(4, 0);
    const reply_5 = duel.reply(4);

    var candidate_replies: [8]duel_mod.Candidate = undefined;
    var reply_count = duel.replies(&vm, tamsin, barb_1, &candidate_replies);

    try writer.print("   -> Bosun Pike blocks the Tidewalk and draws a rapier!\n", .{});
    try writer.print("   -> Pike throws Barb 1: \"{s}\"\n", .{duel.config.pairs[0].challenge});
    try writer.print("   -> Active Choices Available to Tamsin ({d}):\n", .{reply_count});
    for (candidate_replies[0..reply_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\"\n", .{ i + 1, cand.text });
    }
    try std.testing.expectEqual(@as(usize, 1), reply_count);
    try std.testing.expectEqualStrings(duel.config.fallbacks[0], candidate_replies[0].text);

    // Tamsin knows no comeback, so the first fallback line is her only reply.
    try writer.print("   -> Tamsin stammers: \"{s}\"\n", .{candidate_replies[0].text});
    const round_step1 = try duel.resolve_round(bosun_pike, tamsin, barb_1, candidate_replies[0].entity);
    try std.testing.expect(!round_step1.parried);
    // The fumble count is a fact, and it picks her next fallback line (D-076).
    try std.testing.expectEqual(@as(u32, 1), duel.fumbles(tamsin));
    const next_fallback = duel.config.fallbacks[duel.fumbles(tamsin) % duel.config.fallbacks.len];
    try writer.print("   -> DuelFumbles(Tamsin, 1): her next fallback line is \"{s}\"\n", .{next_fallback});

    try writer.print("   -> Pike lunges and taunts: \"{s}\"\n", .{duel.config.pairs[0].reply});
    try writer.print("   -> Relational Learning Triggered:\n", .{});
    try writer.print("      - Remembered HeardBarb(Tamsin, 1): \"{s}\"\n", .{duel.config.pairs[0].challenge});
    try writer.print("      - Remembered MasteredComeback(Tamsin, 1): \"{s}\"\n\n", .{duel.config.pairs[0].reply});

    try std.testing.expect(world.has_fact(tamsin, duel.heard_rel, barb_1.to_int()));
    try std.testing.expect(world.has_fact(tamsin, duel.mastered_rel, reply_1.to_int()));

    // -------------------------------------------------------------------------
    // Step 2: Initiative & Throwing Heard Barbs
    // -------------------------------------------------------------------------
    try writer.print("[Step 2: Offensive Initiative with Learned Barbs]\n", .{});
    var candidate_barbs: [8]duel_mod.Candidate = undefined;
    const barb_count = duel.challenges(&vm, tamsin, old_gannet, &candidate_barbs);

    try writer.print("   -> Tamsin confronts Old Gannet!\n", .{});
    try writer.print("   -> Available Offensive Barbs for Tamsin ({d}):\n", .{barb_count});
    for (candidate_barbs[0..barb_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\"\n", .{ i + 1, cand.text });
    }
    try std.testing.expectEqual(@as(usize, 1), barb_count);
    try std.testing.expectEqualStrings(duel.config.pairs[0].challenge, candidate_barbs[0].text);

    try writer.print("   -> Tamsin throws Barb 1: \"{s}\"\n", .{duel.config.pairs[0].challenge});
    try writer.print("   -> Gannet fails to counter and retorts with Barb 5: \"{s}\"\n", .{duel.config.pairs[4].challenge});

    // The defender hears Barb 5 and learns Comeback 5 through combat.
    try duel.hear(tamsin, barb_5);
    try duel.master(tamsin, reply_5);
    try writer.print("   -> Tamsin commits Barb 5 and Comeback 5 to memory!\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 3: Dynamic Relational Counter-Strike & Advantage Progression
    // -------------------------------------------------------------------------
    try writer.print("[Step 3: Relational Query Pruning & Duel Victory]\n", .{});
    try writer.print("   -> Bosun Pike challenges Tamsin again!\n", .{});
    try writer.print("   -> Pike throws Barb 1: \"{s}\"\n", .{duel.config.pairs[0].challenge});

    reply_count = duel.replies(&vm, tamsin, barb_1, &candidate_replies);
    try writer.print("   -> Tamsin's Mastered Comebacks ({d}):\n", .{reply_count});
    var correct_choice_idx: ?usize = null;
    for (candidate_replies[0..reply_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\" (Counters Barb? {s})\n", .{
            i + 1,
            cand.text,
            if (cand.counters) "YES!" else "no",
        });
        if (cand.counters) correct_choice_idx = i;
    }
    try std.testing.expect(reply_count >= 2);
    try std.testing.expect(correct_choice_idx != null);

    const chosen = candidate_replies[correct_choice_idx.?];
    try writer.print("   -> Tamsin parries with Choice {d}: \"{s}\"\n", .{ correct_choice_idx.? + 1, chosen.text });
    const round_step3 = try duel.resolve_round(bosun_pike, tamsin, barb_1, chosen.entity);
    try std.testing.expect(round_step3.parried);

    // Score advantage to 3 to win duel
    try world.remember(tamsin, duel.advantage_rel, 3, 0);
    try world.remember(tamsin, duel.wins_rel, 1, 0);
    try world.remember(tamsin, swagger_rel, 2, 0);

    try writer.print("   -> Clang! Pike's rapier skids across the cobbles! Tamsin wins the duel!\n", .{});
    try writer.print("   -> Facts asserted: Advantage(Tamsin, 3), DuelsWon(Tamsin, 1), Swagger(Tamsin, 2)\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 4: Mistress Vell & the Tier Invariant
    // -------------------------------------------------------------------------
    try writer.print("[Step 4: Mistress Vell & Tier Invariant Verification]\n", .{});
    try writer.print("   -> Tamsin climbs the lighthouse steps to Mistress Vell's fencing yard.\n", .{});

    // Vell throws her own variant of Barb 5.
    const vell_barb = duel.challenge(4, 1);
    const vell_barb_text = duel.config.pairs[4].variants[0];
    try writer.print("   -> Vell sneers: \"{s}\"\n", .{vell_barb_text});

    reply_count = duel.replies(&vm, tamsin, vell_barb, &candidate_replies);
    try writer.print("   -> Relational Query maps Vell's variant to base Barb 5:\n", .{});
    for (candidate_replies[0..reply_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\" (Counters Vell? {s})\n", .{
            i + 1,
            cand.text,
            if (cand.counters) "YES!" else "no",
        });
    }
    try std.testing.expect(duel.counters(reply_5, vell_barb));

    // Tamsin parries Vell's variant with the same comeback.
    const round_vell = try duel.resolve_round(vell, tamsin, vell_barb, reply_5);
    try std.testing.expect(round_vell.parried);
    try writer.print("   -> Tamsin parries Vell: \"{s}\"\n", .{duel.config.pairs[4].reply});
    try writer.print("   -> Vell lowers her blade: \"A tongue as quick as your wrist!\"\n", .{});

    // Tier invariant: Tamsin has heard Vell's variant (the round above taught it), but a
    // master's barb is offered only against an opponent of that tier, so not against Pike.
    try std.testing.expect(world.has_fact(tamsin, duel.heard_rel, vell_barb.to_int()));

    var pike_barbs: [8]duel_mod.Candidate = undefined;
    const pike_barb_count = duel.challenges(&vm, tamsin, bosun_pike, &pike_barbs);
    try std.testing.expectEqual(@as(usize, 2), pike_barb_count);

    try writer.print("\n   [Tier Invariant Check]\n", .{});
    try writer.print("   -> Tamsin tries Vell's master barb against Bosun Pike:\n", .{});
    var saw_vell_barb = false;
    for (pike_barbs[0..pike_barb_count]) |cand| {
        if (cand.entity == vell_barb) saw_vell_barb = true;
    }
    try std.testing.expect(!saw_vell_barb);
    try writer.print("   -> Engine Pruning Verified: the master barb is filtered out against a tier 0 opponent.\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 5: Organic Conversational Repetition Fatigue
    // -------------------------------------------------------------------------
    try writer.print("[Step 5: Organic Conversational Repetition Fatigue with the Barkeep]\n", .{});
    // Inquiry 1: Welcoming
    const mood1 = try fatigue.record(tamsin, barkeep);
    try writer.print("   -> [Inquiry 1] Tamsin: \"Tell me about Harbourmaster Odell.\"\n", .{});
    try writer.print("      Barkeep Mood: {s}\n", .{fatigue.label(mood1)});
    try writer.print("      Barkeep: \"Odell? Counts every barrel twice and trusts nobody once.\"\n", .{});
    try std.testing.expectEqual(@as(?usize, null), mood1);
    try std.testing.expect(!world.has_fact(barkeep, fatigue.stage_rels[ANNOYED], null));

    // Inquiry 2: Annoyed (expires after 100 ticks)
    const mood2 = try fatigue.record(tamsin, barkeep);
    try writer.print("   -> [Inquiry 2] Tamsin: \"Tell me more about Harbourmaster Odell.\"\n", .{});
    try writer.print("      Barkeep Mood: {s} (AnnoyedWith asserted for 100 ticks)\n", .{fatigue.label(mood2)});
    try writer.print("      Barkeep: \"I've told you already. His office is above the customs shed.\"\n", .{});
    try std.testing.expectEqual(@as(?usize, ANNOYED), mood2);
    try std.testing.expect(world.has_fact(barkeep, fatigue.stage_rels[ANNOYED], tamsin.to_int()));

    // Inquiry 3: Furious (expires after 250 ticks)
    const mood3 = try fatigue.record(tamsin, barkeep);
    try writer.print("   -> [Inquiry 3] Tamsin: \"About Harbourmaster Odell...\"\n", .{});
    try writer.print("      Barkeep Mood: {s} (FuriousWith asserted for 250 ticks)\n", .{fatigue.label(mood3)});
    try writer.print("      Barkeep: \"Ask me once more and you'll be drinking from the canal!\"\n", .{});
    try std.testing.expectEqual(@as(?usize, FURIOUS), mood3);
    try std.testing.expect(world.has_fact(barkeep, fatigue.stage_rels[FURIOUS], tamsin.to_int()));

    // Inquiry 4 while furious: NPC refuses to talk
    const mood4 = fatigue.mood(barkeep, tamsin);
    try writer.print("   -> [Inquiry 4 while Furious] The barkeep sets down a mug, hard, and turns away.\n", .{});
    try std.testing.expectEqual(@as(?usize, FURIOUS), mood4);

    // Save snapshot before temporal cool-off
    try timeline.record(&world);

    // -------------------------------------------------------------------------
    // Step 6: Temporal Mood Decay via Tick Expiration
    // -------------------------------------------------------------------------
    try writer.print("\n[Step 6: Temporal Mood Decay via Master Simulation Ticks]\n", .{});
    try writer.print("   -> Simulating 260 ticks on BeSpoke spine...\n", .{});
    var tick_i: usize = 0;
    while (tick_i < 260) : (tick_i += 1) {
        _ = try bespoke.host.tick(&vm, &compiled);
    }

    try writer.print("   -> Current Tick: {d}\n", .{world.current_tick});
    const mood_after_wait = fatigue.mood(barkeep, tamsin);
    try writer.print("   -> Barkeep Mood after 260 ticks: {s}\n", .{fatigue.label(mood_after_wait)});
    try std.testing.expectEqual(@as(?usize, null), mood_after_wait);
    try std.testing.expect(!world.has_fact(barkeep, fatigue.stage_rels[FURIOUS], tamsin.to_int()));
    try std.testing.expect(!world.has_fact(barkeep, fatigue.stage_rels[ANNOYED], tamsin.to_int()));
    try writer.print("   -> AnnoyedWith and FuriousWith reached their expiry ticks and left the world.\n", .{});
    try writer.print("   -> Barkeep: \"Back again? The cider's still cold.\"\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 7: Tangled World State Dialogue & Time-Travel Rewind
    // -------------------------------------------------------------------------
    try writer.print("[Step 7: Tangled World State Dialogue & Time-Travel Rewind]\n", .{});

    // Three approaches: 1 = Wits, 2 = Fists, 3 = Teamwork.
    try world.remember(tamsin, path_chosen_rel, 1, 0); // Wits path
    try writer.print("   -> PathChosen(Tamsin, Wits) active.\n", .{});
    try writer.print("   -> Talking to a Brackwater citizen...\n", .{});

    const is_wits = (world.get_property(tamsin, path_chosen_rel) orelse 0) == 1;
    const swagger_lvl = world.get_property(tamsin, swagger_rel) orelse 0;

    if (is_wits and swagger_lvl >= 2) {
        try writer.print("   -> Unlocked Tangled Option: \"I won with my wits, and I matched Mistress Vell herself!\"\n", .{});
        try writer.print("   -> Citizen: \"Then you've earned this. The harbour's tide chart, with every sandbar marked!\"\n", .{});
        const chart_ent = try world.intern_entity("TideChart");
        const carries_rel = try world.intern_relation("Carries", .set);
        try world.remember(tamsin, carries_rel, chart_ent.to_int(), 0);
    }
    try std.testing.expect(world.has_fact(tamsin, try world.intern_relation("Carries", .set), null));

    // Time-Travel Rewind to Snapshot 0 (Epistemological zero state)
    try writer.print("\n   [Deterministic Time-Travel Rewind Verification]\n", .{});
    _ = try timeline.restore(&world, 0);

    try writer.print("   -> Restored Snapshot 0 (Tick {d}).\n", .{world.current_tick});
    try writer.print("   -> Tamsin HeardBarb Count: {s}\n", .{
        if (!world.has_fact(tamsin, duel.heard_rel, null)) "0 (Clean)" else "Leaked!",
    });
    try writer.print("   -> Tamsin MasteredComeback Count: {s}\n", .{
        if (!world.has_fact(tamsin, duel.mastered_rel, null)) "0 (Clean)" else "Leaked!",
    });
    try writer.print("   -> Tamsin DuelFumbles: {d}\n", .{duel.fumbles(tamsin)});
    try std.testing.expect(!world.has_fact(tamsin, duel.heard_rel, null));
    try std.testing.expect(!world.has_fact(tamsin, duel.mastered_rel, null));
    try std.testing.expectEqual(@as(u32, 0), duel.fumbles(tamsin));

    try writer.print("\n>>> ALL BRACKWATER BARBS DUEL & REPETITION TESTS PASSED! <<<\n", .{});
}

/// The active duel is host state expressed as facts: which opponent and challenge the next
/// reply answers. A rewind restores them with the generated dialogue set (D-046).
const DuelState = struct {
    opponent: bespoke.RelationKind,
    challenge: bespoke.RelationKind,
};

fn clear_active_duel(world: *bespoke.World, fighter: bespoke.EntityId, state: DuelState) void {
    if (world.get_property(fighter, state.opponent)) |opponent_raw| {
        bespoke.dialogue.clear_open(world, bespoke.EntityId.from_int(opponent_raw)) catch {};
    }
    _ = world.forget(fighter, state.opponent, null);
    _ = world.forget(fighter, state.challenge, null);
}

/// Offers the replies the fighter has mastered as a runtime-generated choice set. The action
/// id is the reply entity, so selection resolves without a host-side candidate table.
fn open_round(
    session: *bespoke.host.Session,
    vm: *bespoke.VM,
    world: *bespoke.World,
    duel: *const duel_mod.Duel,
    fighter: bespoke.EntityId,
    state: DuelState,
) !void {
    const opponent_raw = world.get_property(fighter, state.opponent) orelse return;
    const challenge_raw = world.get_property(fighter, state.challenge) orelse return;
    const opponent = bespoke.EntityId.from_int(opponent_raw);
    const challenge = bespoke.EntityId.from_int(challenge_raw);

    var candidates: [9]duel_mod.Candidate = undefined;
    const count = duel.replies(vm, fighter, challenge, &candidates);
    if (count == 0) return;

    var choices: [9]bespoke.dialogue.Choice = undefined;
    for (0..count) |i| choices[i] = .{ .text = candidates[i].text, .action = candidates[i].entity.to_int() };
    _ = try vm.open_generated_dialogue(opponent, world.get_entity_name(challenge) orelse "", choices[0..count]);
    try session.record_now();
}

fn start_duel(
    session: *bespoke.host.Session,
    vm: *bespoke.VM,
    world: *bespoke.World,
    duel: *const duel_mod.Duel,
    fighter: bespoke.EntityId,
    state: DuelState,
    opponent: bespoke.EntityId,
    challenge: bespoke.EntityId,
) !void {
    if (challenge == bespoke.EntityId.none) return;
    clear_active_duel(world, fighter, state);
    try world.remember(fighter, state.opponent, opponent.to_int(), 0);
    try world.remember(fighter, state.challenge, challenge.to_int(), 0);
    try world.remember(fighter, duel.advantage_rel, 0, 0);
    try world.remember(opponent, duel.advantage_rel, 0, 0);
    try open_round(session, vm, world, duel, fighter, state);
}

fn resolve_choice(
    session: *bespoke.host.Session,
    vm: *bespoke.VM,
    world: *bespoke.World,
    duel: *duel_mod.Duel,
    fighter: bespoke.EntityId,
    state: DuelState,
    index: usize,
    window: *bespoke.display.DisplayWindow,
) !void {
    const selection = (try session.choose_dialogue(index)) orelse return;
    const opponent_raw = world.get_property(fighter, state.opponent) orelse return;
    const challenge_raw = world.get_property(fighter, state.challenge) orelse return;
    const opponent = bespoke.EntityId.from_int(opponent_raw);
    const challenge = bespoke.EntityId.from_int(challenge_raw);
    const reply = if (selection.action == 0) bespoke.EntityId.none else bespoke.EntityId.from_int(selection.action);
    const round = try duel.resolve_round(opponent, fighter, challenge, reply);
    const name = world.get_entity_name(opponent) orelse "The opponent";

    var buf: [192]u8 = undefined;
    if (round.winner) |winner| {
        const msg = if (winner == fighter)
            std.fmt.bufPrint(&buf, "Victory! {s} yields. Duels won: {d}.", .{ name, duel.wins(fighter) }) catch "Victory!"
        else
            std.fmt.bufPrint(&buf, "Defeat. {s} wins this duel.", .{name}) catch "Defeat.";
        clear_active_duel(world, fighter, state);
        try session.record_now();
        window.set_cue_banner(msg, 180);
        return;
    }

    const msg = std.fmt.bufPrint(&buf, "{s} Advantage: Tamsin {d}, {s} {d}.", .{
        if (round.parried) "Parried!" else "Missed! The counter is learned.",
        duel.advantage(fighter),
        name,
        duel.advantage(opponent),
    }) catch "Round resolved.";
    window.set_cue_banner(msg, 120);
    try open_round(session, vm, world, duel, fighter, state);
}

/// Executes interactive 60 Hz playability with graphical display or falls back to headless simulation
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();

    if (compiled.duels.items.len != 1) return error.MissingSwordDuel;
    const duel_decl = &compiled.duels.items[0];
    var duel = try duel_mod.Duel.init(&world, duel_decl.config);
    var fatigue = try duel_mod.InquiryFatigue.init(&world, duel_decl.fatigue);

    const tidewalk_scene = try world.intern_entity("Tidewalk");
    const yard_scene = try world.intern_entity("Fencing Yard");
    const lantern_scene = try world.intern_entity("Drowned Lantern");

    const tamsin = try world.intern_entity("Tamsin");
    const bosun_pike = try world.intern_entity("BosunPike");
    const vell = try world.intern_entity("Vell");
    const barkeep = try world.intern_entity("Barkeep");

    try duel_decl.apply_tiers(&duel);
    const duel_state = DuelState{
        .opponent = try world.intern_relation("ActiveDuelOpponent", .property),
        .challenge = try world.intern_relation("ActiveDuelChallenge", .property),
    };

    const walk_w = try spatial.graph.add_waypoint(tidewalk_scene, 0, 0, "TidewalkWest");
    const walk_m = try spatial.graph.add_waypoint(tidewalk_scene, 20, 0, "TidewalkMid");
    const walk_e = try spatial.graph.add_waypoint(tidewalk_scene, 40, 0, "TidewalkEast");

    const gate_wp = try spatial.graph.add_waypoint(yard_scene, 0, 0, "YardGate");
    const circle_wp = try spatial.graph.add_waypoint(yard_scene, 20, 0, "YardCircle");

    const door_wp = try spatial.graph.add_waypoint(lantern_scene, 0, 0, "LanternDoor");
    const counter_wp = try spatial.graph.add_waypoint(lantern_scene, 20, 0, "CounterMark");

    try spatial.graph.connect(walk_w, walk_m, null);
    try spatial.graph.connect(walk_m, walk_e, null);
    try spatial.graph.connect(gate_wp, circle_wp, null);
    try spatial.graph.connect(door_wp, counter_wp, null);

    try spatial.register_entity(tamsin, walk_m, 10);
    try spatial.register_entity(bosun_pike, walk_e, 11);
    try spatial.register_entity(vell, circle_wp, 12);
    try spatial.register_entity(barkeep, counter_wp, 13);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(tidewalk_scene);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - Brackwater Barbs", 1280, 720);
    defer window.deinit();
    window.set_theme(&sword_theme);

    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
    try stdout.print("Brackwater Barbs Controls:\n", .{});
    try stdout.print("   - [1] - [5]:              Select Dialogue / Comeback\n", .{});
    try stdout.print("   - [D]:                    Duel Bosun Pike on the Tidewalk\n", .{});
    try stdout.print("   - [C]:                    Challenge Mistress Vell\n", .{});
    try stdout.print("   - [T]:                    Talk to Barkeep (Repetition Fatigue)\n", .{});
    try stdout.print("   - [W]:                    Wait 50 Simulation Ticks (Cool off mood)\n", .{});
    try stdout.print("   - [Timeline Scrubber]:    Click or drag timeline bar\n", .{});
    try stdout.print("   - [F1 / Tab]:             Toggle Debug Fact Overlay & REPL\n", .{});

    var display_bridge = bespoke.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("Tamsin")) |player| display_bridge.set_active_character(player);
    display_bridge.attach_audio_bridge(window.audio_bridge);
    // The clock now runs at the shared tick interval (D-028) instead of once per display frame.
    var session = try bespoke.host.Session.init(allocator, &world, &spatial, &vm, &compiled, &display_bridge, &window);
    defer session.deinit();

    window.set_cue_banner("Brackwater: draw your blade and trade barbs!", 180);

    var is_running = true;
    while (is_running) {
        const action = window.poll_events(session.frame());
        if (action == .quit) {
            is_running = false;
        } else if (!try session.handle_common(action)) {
            switch (action) {
                .dialogue_choice => |choice_idx| {
                    try resolve_choice(&session, &vm, &world, &duel, tamsin, duel_state, choice_idx, &window);
                },
                .custom => |id| if (std.meta.intToEnum(SwordKey, id)) |key| switch (key) {
                    .duel_pike => {
                        try vm.transition_to_scene(tidewalk_scene);
                        _ = try spatial.transition_actor(tamsin, tidewalk_scene, walk_m);
                        try start_duel(&session, &vm, &world, &duel, tamsin, duel_state, bosun_pike, duel.challenge(0, 0));
                        window.set_cue_banner("Bosun Pike draws a rapier. Choose a comeback.", 120);
                    },
                    .duel_vell => {
                        try vm.transition_to_scene(yard_scene);
                        _ = try spatial.transition_actor(tamsin, yard_scene, circle_wp);
                        try start_duel(&session, &vm, &world, &duel, tamsin, duel_state, vell, duel.challenge(4, 1));
                        window.set_cue_banner("Mistress Vell raises her blade. Choose a comeback.", 120);
                    },
                    .talk_barkeep => {
                        if (world.get_property(tamsin, duel_state.opponent) != null) {
                            window.set_cue_banner("Finish the duel first.", 90);
                        } else {
                            try vm.transition_to_scene(lantern_scene);
                            _ = try spatial.transition_actor(tamsin, lantern_scene, door_wp);
                            const mood = try fatigue.record(tamsin, barkeep);
                            const line = if (mood) |stage|
                                (if (stage == ANNOYED)
                                    "I've told you already. His office is above the customs shed."
                                else
                                    "Ask me once more and you'll be drinking from the canal!")
                            else
                                "Odell? Counts every barrel twice and trusts nobody once.";
                            var buf: [192]u8 = undefined;
                            const msg = std.fmt.bufPrint(&buf, "Barkeep [{s}]: \"{s}\"", .{ fatigue.label(mood), line }) catch "Barkeep";
                            try session.record_now();
                            window.set_cue_banner(msg, 150);
                        }
                    },
                    .wait_50 => {
                        if (world.get_property(tamsin, duel_state.opponent) != null) {
                            window.set_cue_banner("Finish the duel first.", 90);
                        } else {
                            var waited: usize = 0;
                            while (waited < 50) : (waited += 1) _ = try session.advance();
                            var buf: [128]u8 = undefined;
                            const msg = std.fmt.bufPrint(&buf, "Waited 50 ticks. Barkeep mood: {s}.", .{fatigue.label(fatigue.mood(barkeep, tamsin))}) catch "Waited 50 ticks.";
                            window.set_cue_banner(msg, 120);
                        }
                    },
                } else |_| {},
                else => {},
            }
        }

        if (session.tick_due()) _ = try session.advance();

        session.render();
        std.time.sleep(16 * std.time.ns_per_ms);
    }
}

// -----------------------------------------------------------------------------
// Unit Tests
// -----------------------------------------------------------------------------

test "P15-01: every Brackwater comeback counters its barb and Vell's variant" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.duels.items.len);

    var duel = try duel_mod.Duel.init(&world, compiled.duels.items[0].config);
    try compiled.duels.items[0].apply_tiers(&duel);

    try testing.expectEqual(@as(usize, 15), duel.config.pairs.len);
    try testing.expectEqual(@as(usize, 3), duel.config.fallbacks.len);
    for (duel.config.pairs, 0..) |_, i| {
        const variant = duel.challenge(i, 1);
        try testing.expect(duel.counters(duel.reply(i), duel.challenge(i, 0)));
        try testing.expectEqual(duel.challenge(i, 0), duel.base_of(variant));
        try testing.expect(duel.counters(duel.reply(i), variant));
    }
}

test "P15-02: tier invariant keeps Vell's master barbs off tier 0 opponents" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var chunk = bespoke.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    var vm = bespoke.VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.duels.items.len);

    var duel = try duel_mod.Duel.init(&world, compiled.duels.items[0].config);
    try compiled.duels.items[0].apply_tiers(&duel);
    const tamsin = try world.intern_entity("Tamsin");
    const bosun_pike = try world.intern_entity("BosunPike");
    const vell = try world.intern_entity("Vell");

    // Tamsin learns base barb 4 and Vell's variant of it.
    try duel.hear(tamsin, duel.challenge(3, 0));
    try duel.hear(tamsin, duel.challenge(3, 1));

    // Against Bosun Pike (tier 0) only the base barb is offered.
    var pike_candidates: [4]duel_mod.Candidate = undefined;
    const pike_count = duel.challenges(&vm, tamsin, bosun_pike, &pike_candidates);
    try testing.expectEqual(@as(usize, 1), pike_count);
    try testing.expectEqual(duel.challenge(3, 0), pike_candidates[0].entity);

    // Against Vell (tier 1) both are offered.
    var vell_candidates: [4]duel_mod.Candidate = undefined;
    const vell_count = duel.challenges(&vm, tamsin, vell, &vell_candidates);
    try testing.expectEqual(@as(usize, 2), vell_count);
}

test "P15-03: conversational repetition fatigue asserts decaying mood facts" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.duels.items.len);

    var fatigue = try duel_mod.InquiryFatigue.init(&world, compiled.duels.items[0].fatigue);
    const tamsin = try world.intern_entity("Tamsin");
    const barkeep = try world.intern_entity("Barkeep");

    try testing.expectEqual(@as(?usize, null), try fatigue.record(tamsin, barkeep));
    try testing.expectEqual(@as(?usize, null), fatigue.mood(barkeep, tamsin));

    // Inquiry 2: Annoyed (100 ticks)
    try testing.expectEqual(@as(?usize, ANNOYED), try fatigue.record(tamsin, barkeep));
    try testing.expectEqual(@as(?usize, ANNOYED), fatigue.mood(barkeep, tamsin));

    // Inquiry 3: Furious (250 ticks)
    try testing.expectEqual(@as(?usize, FURIOUS), try fatigue.record(tamsin, barkeep));
    try testing.expectEqual(@as(?usize, FURIOUS), fatigue.mood(barkeep, tamsin));

    // Annoyance expires first, fury later
    var tick: usize = 0;
    while (tick < 100) : (tick += 1) _ = world.step_tick();
    try testing.expect(!world.has_fact(barkeep, fatigue.stage_rels[ANNOYED], tamsin.to_int()));
    try testing.expectEqual(@as(?usize, FURIOUS), fatigue.mood(barkeep, tamsin));
    while (tick < 250) : (tick += 1) _ = world.step_tick();
    try testing.expectEqual(@as(?usize, null), fatigue.mood(barkeep, tamsin));
}

test "P32-23: a declared duel offers generated replies and reaches a win at three advantage" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.duels.items.len);

    var duel = try duel_mod.Duel.init(&world, compiled.duels.items[0].config);
    try compiled.duels.items[0].apply_tiers(&duel);
    try testing.expectEqual(@as(?u32, 3), duel.config.win_at);

    const tamsin = try world.intern_entity("Tamsin");
    const bosun_pike = try world.intern_entity("BosunPike");
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();

    const challenge = duel.challenge(0, 0);
    var candidates: [9]duel_mod.Candidate = undefined;
    try testing.expectEqual(@as(usize, 1), duel.replies(&vm, tamsin, challenge, &candidates));
    try testing.expectEqualStrings(duel.config.fallbacks[0], candidates[0].text);

    var choices: [1]bespoke.dialogue.Choice = .{.{ .text = candidates[0].text, .action = candidates[0].entity.to_int() }};
    _ = try vm.open_generated_dialogue(bosun_pike, world.get_entity_name(challenge).?, &choices);
    const open = vm.dialogue_view().?;
    try testing.expectEqualStrings(world.get_entity_name(challenge).?, open.prompt);
    try testing.expectEqualStrings(duel.config.fallbacks[0], open.text(0));

    const selection = (try vm.choose(0)).?;
    try testing.expectEqual(@as(u32, 0), selection.action);
    const lost = try duel.resolve_round(bosun_pike, tamsin, challenge, bespoke.EntityId.none);
    try testing.expect(!lost.parried);
    try testing.expectEqual(@as(u32, 1), duel.advantage(bosun_pike));

    // With the lesson forgotten, her next fumble uses the second fallback line (D-076); the
    // fumbled round teaches the comeback again.
    _ = world.forget(tamsin, duel.mastered_rel, null);
    try testing.expectEqual(@as(usize, 1), duel.replies(&vm, tamsin, challenge, &candidates));
    try testing.expectEqualStrings(duel.config.fallbacks[1], candidates[0].text);
    _ = try duel.resolve_round(bosun_pike, tamsin, challenge, bespoke.EntityId.none);
    try testing.expectEqual(@as(u32, 2), duel.fumbles(tamsin));
    try world.remember(bosun_pike, duel.advantage_rel, 0, 0);
    try world.remember(tamsin, duel.advantage_rel, 0, 0);

    try testing.expectEqual(@as(usize, 1), duel.replies(&vm, tamsin, challenge, &candidates));
    try testing.expect(candidates[0].counters);

    var round_index: usize = 0;
    while (round_index < 3) : (round_index += 1) {
        const round = try duel.resolve_round(bosun_pike, tamsin, challenge, candidates[0].entity);
        try testing.expect(round.parried);
        if (round_index < 2) {
            try testing.expect(round.winner == null);
        } else {
            try testing.expectEqual(tamsin, round.winner.?);
        }
    }
    try testing.expectEqual(@as(u32, 1), duel.wins(tamsin));
}

test "P15-04: headless simulation of Brackwater Barbs passes cleanly" {
    const testing = std.testing;
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try run_headless(testing.allocator, buf.writer());
    try testing.expect(buf.items.len > 0);
}
