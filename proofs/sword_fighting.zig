const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const SwordKey = enum(u16) { duel_pike, duel_vell, talk_barkeep, wait_50, duel_gannet };

const sword_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_d, .action = @intFromEnum(SwordKey.duel_pike), .sfx = art.sfx(.sword_clash) },
    .{ .key = bespoke.display.renderer.c.SDLK_c, .action = @intFromEnum(SwordKey.duel_vell), .sfx = art.sfx(.sword_clash) },
    .{ .key = bespoke.display.renderer.c.SDLK_t, .action = @intFromEnum(SwordKey.talk_barkeep) },
    .{ .key = bespoke.display.renderer.c.SDLK_w, .action = @intFromEnum(SwordKey.wait_50) },
    .{ .key = bespoke.display.renderer.c.SDLK_g, .action = @intFromEnum(SwordKey.duel_gannet), .sfx = art.sfx(.sword_clash) },
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
    \\relation MasteredComeback(fighter, comeback)
    \\
    \\~ What each opponent knows: an answer it knows parries Tamsin's barb and teaches her it.
    \\remember MasteredComeback(BosunPike, Barb1Reply)
    \\remember MasteredComeback(BosunPike, Barb2Reply)
    \\remember MasteredComeback(BosunPike, Barb3Reply)
    \\remember MasteredComeback(BosunPike, Barb4Reply)
    \\remember MasteredComeback(BosunPike, Barb5Reply)
    \\remember MasteredComeback(BosunPike, Barb6Reply)
    \\remember MasteredComeback(BosunPike, Barb7Reply)
    \\remember MasteredComeback(BosunPike, Barb8Reply)
    \\remember MasteredComeback(OldGannet, Barb1Reply)
    \\remember MasteredComeback(OldGannet, Barb9Reply)
    \\remember MasteredComeback(OldGannet, Barb10Reply)
    \\remember MasteredComeback(OldGannet, Barb11Reply)
    \\remember MasteredComeback(OldGannet, Barb12Reply)
    \\remember MasteredComeback(OldGannet, Barb13Reply)
    \\remember MasteredComeback(OldGannet, Barb14Reply)
    \\remember MasteredComeback(OldGannet, Barb15Reply)
    \\remember MasteredComeback(Vell, Barb1Reply)
    \\remember MasteredComeback(Vell, Barb2Reply)
    \\remember MasteredComeback(Vell, Barb3Reply)
    \\remember MasteredComeback(Vell, Barb4Reply)
    \\remember MasteredComeback(Vell, Barb5Reply)
    \\remember MasteredComeback(Vell, Barb6Reply)
    \\remember MasteredComeback(Vell, Barb7Reply)
    \\remember MasteredComeback(Vell, Barb8Reply)
    \\remember MasteredComeback(Vell, Barb9Reply)
    \\remember MasteredComeback(Vell, Barb10Reply)
    \\remember MasteredComeback(Vell, Barb11Reply)
    \\remember MasteredComeback(Vell, Barb12Reply)
    \\remember MasteredComeback(Vell, Barb13Reply)
    \\remember MasteredComeback(Vell, Barb14Reply)
    \\remember MasteredComeback(Vell, Barb15Reply)
    \\
    \\on cue WinsDuel(BosunPike, Tamsin):
    \\  say BosunPike: "Ha! Go back to your mop, landlubber."
    \\
    \\on cue WinsDuel(Tamsin, BosunPike):
    \\  say BosunPike: "Enough! Take the Tidewalk, it's yours."
    \\
    \\on cue WinsDuel(OldGannet, Tamsin):
    \\  say OldGannet: "Forty years on these docks. Did you think you'd be the one?"
    \\
    \\on cue WinsDuel(Tamsin, OldGannet):
    \\  say OldGannet: "Bah. My knees gave out before my wits did."
    \\
    \\on cue WinsDuel(Vell, Tamsin):
    \\  say Vell: "Come back when your tongue is as sharp as your blade."
    \\
    \\on cue WinsDuel(Tamsin, Vell):
    \\  say Vell: "Well struck. Brackwater has a new champion."
    \\
    \\routine PatrolTidewalk(BosunPike):
    \\  loop:
    \\    walk BosunPike to TidewalkWest
    \\    wait 30 ticks
    \\    walk BosunPike to TidewalkEast
    \\    wait 30 ticks
    \\
    \\routine PatrolGannet(OldGannet):
    \\  loop:
    \\    wait 20 ticks
    \\    walk OldGannet to TidewalkMid
    \\    wait 25 ticks
    \\    walk OldGannet to TidewalkEast
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
    // The script's top-level lines declare what each opponent knows (D-078).
    try bespoke.host.run_initial_statements(&world, &vm, &compiled);

    // Snapshot 0: Baseline state
    try timeline.record(&world);

    // -------------------------------------------------------------------------
    // Step 1: Epistemological Zero Baseline: a lost round teaches only the barb
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
    // Pike presses on with his next barb; he does not answer his own (D-078).
    const pike_next = duel.next_challenge(barb_1, bosun_pike);
    try writer.print("   -> Pike presses on: \"{s}\"\n", .{duel.challenge_text(pike_next).?});
    try writer.print("   -> Relational Learning: HeardBarb(Tamsin, 1); no comeback learned from a lost round.\n\n", .{});

    try std.testing.expect(world.has_fact(tamsin, duel.heard_rel, barb_1.to_int()));
    try std.testing.expect(!world.has_fact(tamsin, duel.mastered_rel, null));

    // -------------------------------------------------------------------------
    // Step 2: Initiative: throwing heard barbs teaches the comebacks heard back
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

    // Gannet knows Comeback 1 (the script says so); answering teaches it to Tamsin.
    try writer.print("   -> Tamsin throws Barb 1: \"{s}\"\n", .{duel.config.pairs[0].challenge});
    const gannet_answer = duel.answer(old_gannet, barb_1);
    try std.testing.expectEqual(reply_1, gannet_answer);
    const round_gannet = try duel.resolve_round(tamsin, old_gannet, barb_1, gannet_answer);
    try std.testing.expect(round_gannet.parried);
    try writer.print("   -> Gannet parries: \"{s}\"\n", .{duel.config.pairs[0].reply});
    try std.testing.expect(world.has_fact(tamsin, duel.mastered_rel, reply_1.to_int()));
    try writer.print("   -> Tamsin heard it: MasteredComeback(Tamsin, 1)\n", .{});

    // Gannet takes the initiative with Barb 5, which Tamsin cannot answer yet.
    try writer.print("   -> Gannet attacks with Barb 5: \"{s}\"\n", .{duel.config.pairs[4].challenge});
    _ = try duel.resolve_round(old_gannet, tamsin, barb_5, .none);
    try std.testing.expect(world.has_fact(tamsin, duel.heard_rel, barb_5.to_int()));
    try std.testing.expect(!world.has_fact(tamsin, duel.mastered_rel, reply_5.to_int()));

    // She tries Barb 5 on Bosun Pike, who knows Comebacks 1 to 8.
    try writer.print("   -> Later, Tamsin throws Barb 5 at Bosun Pike.\n", .{});
    const pike_answer = duel.answer(bosun_pike, barb_5);
    _ = try duel.resolve_round(tamsin, bosun_pike, barb_5, pike_answer);
    try std.testing.expect(world.has_fact(tamsin, duel.mastered_rel, reply_5.to_int()));
    try writer.print("   -> Pike parries: \"{s}\"\n", .{duel.config.pairs[4].reply});
    try writer.print("   -> Tamsin commits Comeback 5 to memory!\n\n", .{});

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

/// One duel in progress, shared by the desktop window, the browser deck, and the tests. The
/// state is facts on the player (opponent, the barb in play, who attacks), so a rewind restores
/// the round with its generated choice set (D-046). Turns follow the round (D-078): whoever wins
/// a round attacks next. A fencing master (tier 1 or above) always attacks, because she knows
/// every comeback and a parried attack would only hand the lead back and forth.
pub const Bout = struct {
    world: *bespoke.World,
    duel: *duel_mod.Duel,
    player: bespoke.EntityId,
    opponent_rel: bespoke.RelationKind,
    challenge_rel: bespoke.RelationKind,
    /// 1 while the player attacks; absent while the opponent does.
    attacking_rel: bespoke.RelationKind,
    /// Barbs the player has thrown in this duel. Each barb is thrown once per duel, so one
    /// barb the opponent cannot answer does not win three rounds by itself.
    thrown_rel: bespoke.RelationKind,

    /// One message for the host to show on its own (D-080): who said it, if anyone, and what.
    pub const Line = struct {
        /// An entity name, or empty for narration such as the round's outcome.
        speaker: []const u8 = "",
        text: []const u8,
    };

    pub const Result = struct {
        /// What happened, in order, as an adventure game shows an exchange: the player's chosen
        /// line in her own voice, the opponent's reply, the round's outcome, the points.
        lines: [4]Line = undefined,
        line_count: usize = 0,
        /// Set when the duel ended this round.
        winner: ?bespoke.EntityId = null,
        loser: ?bespoke.EntityId = null,

        pub fn slice(self: *const Result) []const Line {
            return self.lines[0..self.line_count];
        }

        /// True when any line contains `needle`.
        pub fn says(self: *const Result, needle: []const u8) bool {
            for (self.slice()) |line| if (std.mem.indexOf(u8, line.text, needle) != null) return true;
            return false;
        }

        fn add(self: *Result, speaker: []const u8, text: []const u8) void {
            if (text.len == 0 or self.line_count == self.lines.len) return;
            self.lines[self.line_count] = .{ .speaker = speaker, .text = text };
            self.line_count += 1;
        }
    };

    pub fn init(world: *bespoke.World, duel: *duel_mod.Duel, player: bespoke.EntityId) !Bout {
        return .{
            .world = world,
            .duel = duel,
            .player = player,
            .opponent_rel = try world.intern_relation("ActiveDuelOpponent", .property),
            .challenge_rel = try world.intern_relation("ActiveDuelChallenge", .property),
            .attacking_rel = try world.intern_relation("PlayerAttacks", .property),
            .thrown_rel = try world.intern_relation("ThrownThisDuel", .set),
        };
    }

    pub fn opponent(self: *const Bout) ?bespoke.EntityId {
        const raw = self.world.get_property(self.player, self.opponent_rel) orelse return null;
        return bespoke.EntityId.from_int(raw);
    }

    pub fn player_attacks(self: *const Bout) bool {
        return self.world.get_property(self.player, self.attacking_rel) != null;
    }

    fn is_master(self: *const Bout, who: bespoke.EntityId) bool {
        return (self.world.get_property(who, self.duel.tier_rel) orelse 0) > 0;
    }

    /// The barbs the player may still throw at the current opponent: heard, usable at its
    /// tier, and not yet thrown in this duel. Table order; capped at the panel's nine.
    pub fn usable_barbs(self: *const Bout, vm: *bespoke.VM, out: *[9]duel_mod.Candidate) usize {
        const foe = self.opponent() orelse return 0;
        var all: [64]duel_mod.Candidate = undefined;
        const n = self.duel.challenges(vm, self.player, foe, &all);
        var count: usize = 0;
        for (all[0..n]) |cand| {
            if (count == out.len) break;
            if (self.world.has_fact(self.player, self.thrown_rel, cand.entity.to_int())) continue;
            out[count] = cand;
            count += 1;
        }
        return count;
    }

    /// Starts a duel. The player leads if she has a barb to throw at this opponent and the
    /// opponent is not a master; otherwise the opponent opens with `opening`.
    pub fn start(self: *Bout, vm: *bespoke.VM, foe: bespoke.EntityId, opening: bespoke.EntityId) !void {
        self.clear();
        try self.world.remember(self.player, self.opponent_rel, foe.to_int(), 0);
        try self.world.remember(self.player, self.challenge_rel, opening.to_int(), 0);
        try self.world.remember(self.player, self.duel.advantage_rel, 0, 0);
        try self.world.remember(foe, self.duel.advantage_rel, 0, 0);
        var barbs: [9]duel_mod.Candidate = undefined;
        if (!self.is_master(foe) and self.usable_barbs(vm, &barbs) > 0) {
            try self.world.remember(self.player, self.attacking_rel, 1, 0);
        }
    }

    /// Ends the duel and closes its choice set.
    pub fn clear(self: *Bout) void {
        if (self.opponent()) |foe| bespoke.dialogue.clear_open(self.world, foe) catch {};
        _ = self.world.forget(self.player, self.opponent_rel, null);
        _ = self.world.forget(self.player, self.challenge_rel, null);
        _ = self.world.forget(self.player, self.attacking_rel, null);
        _ = self.world.forget(self.player, self.thrown_rel, null);
    }

    /// Opens the round's choices as a generated dialogue set: the barbs the player may throw
    /// while she attacks, else her comebacks to the opponent's barb. Each action id is the
    /// chosen barb or comeback entity (0 for a fallback line).
    pub fn open(self: *Bout, vm: *bespoke.VM) !void {
        const foe = self.opponent() orelse return;
        var candidates: [9]duel_mod.Candidate = undefined;
        var prompt: []const u8 = "";
        var count: usize = 0;
        if (self.player_attacks()) {
            count = self.usable_barbs(vm, &candidates);
            prompt = "Your turn: throw a barb.";
        } else {
            const raw = self.world.get_property(self.player, self.challenge_rel) orelse return;
            const barb = bespoke.EntityId.from_int(raw);
            count = self.duel.replies(vm, self.player, barb, &candidates);
            prompt = self.duel.challenge_text(barb) orelse "";
        }
        if (count == 0) return;
        var choices: [9]bespoke.dialogue.Choice = undefined;
        for (0..count) |i| choices[i] = .{ .text = candidates[i].text, .action = candidates[i].entity.to_int() };
        _ = try vm.open_generated_dialogue(foe, prompt, choices[0..count]);
    }

    /// The text of a comeback, by its entity.
    fn reply_line(self: *const Bout, reply_ent: bespoke.EntityId) []const u8 {
        for (self.duel.config.pairs, 0..) |pair, p| {
            if (self.duel.reply(p) == reply_ent) return pair.reply;
        }
        return "";
    }

    /// The fallback line `foe` just spoke: its fumble count was raised by the round.
    fn spoken_fallback(self: *const Bout, foe: bespoke.EntityId) []const u8 {
        const lines = self.duel.config.fallbacks;
        if (lines.len == 0) return "...";
        return lines[(self.duel.fumbles(foe) + lines.len - 1) % lines.len];
    }

    /// Resolves the player's choice and sets up the next round. `buf` holds the points line.
    pub fn choose(self: *Bout, vm: *bespoke.VM, action: u32, buf: []u8) !Result {
        const foe = self.opponent() orelse return .{};
        const foe_name = self.world.get_entity_name(foe) orelse "";
        var name_buf: [48]u8 = undefined;
        const name = bespoke.display.dialogue_panel.display_name(self.world.get_entity_name(foe) orelse "The opponent", &name_buf);
        const picked = if (action == 0) bespoke.EntityId.none else bespoke.EntityId.from_int(action);
        const player_led = self.player_attacks();

        var said: []const u8 = "";
        var player_said: []const u8 = "";
        var barb: bespoke.EntityId = undefined;
        var round: duel_mod.Round = undefined;
        if (player_led) {
            // The opponent answers the player's barb with what it knows; a real answer teaches
            // the player that comeback (D-078).
            barb = picked;
            player_said = self.duel.challenge_text(barb) orelse "";
            try self.world.remember(self.player, self.thrown_rel, barb.to_int(), 0);
            const reply = self.duel.answer(foe, barb);
            round = try self.duel.resolve_round(self.player, foe, barb, reply);
            said = if (reply != .none) (self.duel.reply_text(barb) orelse "") else self.spoken_fallback(foe);
        } else {
            const raw = self.world.get_property(self.player, self.challenge_rel) orelse return .{};
            barb = bespoke.EntityId.from_int(raw);
            round = try self.duel.resolve_round(foe, self.player, barb, picked);
            player_said = if (picked == .none) self.spoken_fallback(self.player) else self.reply_line(picked);
        }
        const player_won_round = if (player_led) !round.parried else round.parried;

        var result = Result{};
        result.add(self.world.get_entity_name(self.player) orelse "", player_said);
        result.add(foe_name, said);
        if (round.winner) |winner| {
            self.clear();
            result.winner = winner;
            result.loser = if (winner == self.player) foe else self.player;
            return result;
        }

        // The round's winner attacks next, except that a master always attacks and a player
        // with no barb left to throw must defend. An opponent who attacks presses on with its
        // next barb, never the answer to the last one.
        var left: [9]duel_mod.Candidate = undefined;
        if (player_won_round and !self.is_master(foe) and self.usable_barbs(vm, &left) > 0) {
            try self.world.remember(self.player, self.attacking_rel, 1, 0);
        } else {
            _ = self.world.forget(self.player, self.attacking_rel, null);
            try self.world.remember(self.player, self.challenge_rel, self.duel.next_challenge(barb, foe).to_int(), 0);
        }

        result.add("", if (player_won_round) "Your point." else "Their point.");
        result.add("", std.fmt.bufPrint(buf, "Points: you {d}, {s} {d}.", .{ self.duel.advantage(self.player), name, self.duel.advantage(foe) }) catch "");
        return result;
    }
};

fn start_bout(session: *bespoke.host.Session, vm: *bespoke.VM, bout: *Bout, foe: bespoke.EntityId, opening: bespoke.EntityId) !void {
    try bout.start(vm, foe, opening);
    try bout.open(vm);
    try session.record_now();
}

/// Plays the chosen barb or comeback. When the duel ends, the script's `WinsDuel` handler
/// speaks the opponent's line, which the banner shows after the tick that runs it.
fn play_choice(
    session: *bespoke.host.Session,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    bout: *Bout,
    index: usize,
    window: *bespoke.display.DisplayWindow,
) !void {
    const selection = (try session.choose_dialogue(index)) orelse return;
    var buf: [320]u8 = undefined;
    const result = try bout.choose(vm, selection.action, &buf);
    // Each line waits for a click (D-080); the next round's choices show once all are read.
    for (result.slice()) |line| window.queue_message(line.speaker, line.text);
    if (result.winner) |winner| {
        _ = try vm.fire_cue(compiled, "WinsDuel", winner, result.loser, null);
        _ = try session.advance();
        var spoken: [4]bespoke.host.SpeechLine = undefined;
        const n = bespoke.host.speech_lines(vm.world, vm, &spoken);
        for (spoken[0..n]) |line| window.queue_message(line.speaker, line.text);
        try session.record_now();
        return;
    }
    try bout.open(vm);
    try session.record_now();
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
    const old_gannet = try world.intern_entity("OldGannet");
    const vell = try world.intern_entity("Vell");
    const barkeep = try world.intern_entity("Barkeep");

    try duel_decl.apply_tiers(&duel);
    var bout = try Bout.init(&world, &duel, tamsin);

    // The script's `marks:` lines already created and chained each scene's waypoints; a host
    // that adds its own copies gets duplicate marks with no path between the two sets.
    const walk_m = spatial.graph.find_waypoint_in_room(tidewalk_scene, "TidewalkMid") orelse return error.MissingMark;
    const walk_e = spatial.graph.find_waypoint_in_room(tidewalk_scene, "TidewalkEast") orelse return error.MissingMark;
    const circle_wp = spatial.graph.find_waypoint_in_room(yard_scene, "YardCircle") orelse return error.MissingMark;
    const door_wp = spatial.graph.find_waypoint_in_room(lantern_scene, "LanternDoor") orelse return error.MissingMark;
    const counter_wp = spatial.graph.find_waypoint_in_room(lantern_scene, "CounterMark") orelse return error.MissingMark;

    try spatial.register_entity(tamsin, walk_m, 10);
    try spatial.register_entity(bosun_pike, walk_e, 11);
    try spatial.register_entity(old_gannet, walk_e, 11);
    try spatial.register_entity(vell, circle_wp, 12);
    try spatial.register_entity(barkeep, counter_wp, 13);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    // The script's top-level lines declare what each opponent knows (D-078); its routines walk
    // Pike and Gannet along the Tidewalk and the barkeep behind the counter. Actors placed above
    // keep their marks.
    _ = try bespoke.host.start_script(&world, &spatial, &vm, &compiled);
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
    try stdout.print("   - [Click a mark]:         Walk Tamsin there\n", .{});
    try stdout.print("   - [1] - [5]:              Select Dialogue / Comeback\n", .{});
    try stdout.print("   - [D]:                    Duel Bosun Pike on the Tidewalk\n", .{});
    try stdout.print("   - [G]:                    Duel Old Gannet on the Tidewalk\n", .{});
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
                .walk_player => |wp_id| {
                    if (bout.opponent() != null) {
                        window.set_cue_banner("Finish the duel first.", 90);
                    } else if (!try spatial.walk_to(tamsin, wp_id)) {
                        window.set_cue_banner("Tamsin can't get there from here.", 60);
                    }
                },
                .dialogue_choice => |choice_idx| {
                    try play_choice(&session, &vm, &compiled, &bout, choice_idx, &window);
                },
                .custom => |id| if (std.meta.intToEnum(SwordKey, id)) |key| switch (key) {
                    .duel_pike => {
                        try vm.transition_to_scene(tidewalk_scene);
                        _ = try spatial.transition_actor(tamsin, tidewalk_scene, walk_m);
                        try start_bout(&session, &vm, &bout, bosun_pike, duel.challenge(0, 0));
                        window.set_cue_banner("Bosun Pike draws a rapier.", 120);
                    },
                    .duel_gannet => {
                        try vm.transition_to_scene(tidewalk_scene);
                        _ = try spatial.transition_actor(tamsin, tidewalk_scene, walk_m);
                        try start_bout(&session, &vm, &bout, old_gannet, duel.challenge(8, 0));
                        window.set_cue_banner("Old Gannet squares up.", 120);
                    },
                    .duel_vell => {
                        try vm.transition_to_scene(yard_scene);
                        _ = try spatial.transition_actor(tamsin, yard_scene, circle_wp);
                        try start_bout(&session, &vm, &bout, vell, duel.challenge(4, 1));
                        window.set_cue_banner("Mistress Vell raises her blade.", 120);
                    },
                    .talk_barkeep => {
                        if (bout.opponent() != null) {
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
                        if (bout.opponent() != null) {
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

test "P32-23/D-078: turns follow the round, opponents press on, and hearing teaches" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();

    var duel = try duel_mod.Duel.init(&world, compiled.duels.items[0].config);
    try compiled.duels.items[0].apply_tiers(&duel);
    try testing.expectEqual(@as(?u32, 3), duel.config.win_at);
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    try bespoke.host.run_initial_statements(&world, &vm, &compiled);

    const tamsin = try world.intern_entity("Tamsin");
    const pike = try world.intern_entity("BosunPike");
    const vell = try world.intern_entity("Vell");
    var bout = try Bout.init(&world, &duel, tamsin);
    var buf: [320]u8 = undefined;

    // Duel 1: Tamsin knows nothing, so Pike leads. Each fumble loses a point, teaches no
    // comeback, and Pike presses on with his next barb, never the answer to the last.
    try bout.start(&vm, pike, duel.challenge(0, 0));
    try testing.expect(!bout.player_attacks());
    var result: Bout.Result = undefined;
    for (0..3) |round| {
        try bout.open(&vm);
        const open = vm.dialogue_view().?;
        try testing.expectEqualStrings(duel.config.pairs[round].challenge, open.prompt);
        try testing.expectEqualStrings(duel.config.fallbacks[round], open.text(0));
        result = try bout.choose(&vm, 0, &buf);
        try testing.expect(!world.has_fact(tamsin, duel.mastered_rel, null));
        try testing.expect(!result.says(duel.config.pairs[round].reply));
    }
    try testing.expectEqual(pike, result.winner.?);
    try testing.expect(bout.opponent() == null);

    // The script speaks the victory line from its WinsDuel handler.
    _ = (try vm.fire_cue(&compiled, "WinsDuel", pike, tamsin, null)).?;
    _ = try bespoke.host.tick(&vm, &compiled);
    var speech: [256]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, bespoke.host.speech_this_tick(&world, &vm, &speech).?, "Go back to your mop") != null);

    // Duel 2: she has heard three barbs, so she leads. Pike knows Comeback 1, parries, and
    // she learns it by hearing it; then Pike attacks with his next barb.
    try bout.start(&vm, pike, duel.challenge(0, 0));
    try testing.expect(bout.player_attacks());
    try bout.open(&vm);
    try testing.expectEqual(@as(usize, 3), vm.dialogue_view().?.count);
    result = try bout.choose(&vm, duel.challenge(0, 0).to_int(), &buf);
    try testing.expect(world.has_fact(tamsin, duel.mastered_rel, duel.reply(0).to_int()));
    try testing.expect(result.says(duel.config.pairs[0].reply));
    try testing.expect(!bout.player_attacks());
    try bout.open(&vm);
    try testing.expectEqualStrings(duel.config.pairs[1].challenge, vm.dialogue_view().?.prompt);

    // A master always attacks, even when the player has barbs to throw.
    try bout.start(&vm, vell, duel.challenge(4, 1));
    try testing.expect(!bout.player_attacks());
}

test "D-079: each barb is thrown once per duel, points add up, and distinct barbs win" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();
    var duel = try duel_mod.Duel.init(&world, compiled.duels.items[0].config);
    try compiled.duels.items[0].apply_tiers(&duel);
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    try bespoke.host.run_initial_statements(&world, &vm, &compiled);

    const tamsin = try world.intern_entity("Tamsin");
    const gannet = try world.intern_entity("OldGannet");
    var bout = try Bout.init(&world, &duel, tamsin);
    var buf: [320]u8 = undefined;
    var barbs: [9]duel_mod.Candidate = undefined;

    // Tamsin has heard one barb Gannet cannot answer. It wins a round, but it cannot be thrown
    // again, so Gannet attacks next instead of losing to the same line three times.
    try world.remember(tamsin, duel.heard_rel, duel.challenge(1, 0).to_int(), 0);
    try bout.start(&vm, gannet, duel.challenge(8, 0));
    try testing.expect(bout.player_attacks());
    var result = try bout.choose(&vm, duel.challenge(1, 0).to_int(), &buf);
    try testing.expect(result.winner == null);
    // Four messages, each shown on its own (D-080): Tamsin's barb in her voice, Gannet's
    // fallback, the outcome, the points.
    try testing.expectEqual(@as(usize, 4), result.line_count);
    try testing.expectEqualStrings("Tamsin", result.lines[0].speaker);
    try testing.expectEqualStrings(duel.config.pairs[1].challenge, result.lines[0].text);
    try testing.expectEqualStrings("OldGannet", result.lines[1].speaker);
    try testing.expectEqualStrings(duel.config.fallbacks[0], result.lines[1].text);
    try testing.expectEqualStrings("Your point.", result.lines[2].text);
    try testing.expectEqualStrings("Points: you 1, Old Gannet 0.", result.lines[3].text);
    try testing.expectEqual(@as(usize, 0), bout.usable_barbs(&vm, &barbs));
    try testing.expect(!bout.player_attacks());

    // Gannet's barb lands; Tamsin keeps the point she scored (D-079). Her fumble is echoed in
    // her voice, and Gannet says nothing in reply.
    try bout.open(&vm);
    result = try bout.choose(&vm, 0, &buf);
    try testing.expectEqualStrings("Tamsin", result.lines[0].speaker);
    try testing.expectEqualStrings(duel.config.fallbacks[0], result.lines[0].text);
    try testing.expectEqualStrings("Their point.", result.lines[1].text);
    try testing.expectEqual(@as(u32, 1), duel.advantage(tamsin));
    try testing.expectEqual(@as(u32, 1), duel.advantage(gannet));

    // A new duel lets every barb be thrown again. Three barbs Gannet cannot answer win it.
    try world.remember(tamsin, duel.heard_rel, duel.challenge(2, 0).to_int(), 0);
    try world.remember(tamsin, duel.heard_rel, duel.challenge(3, 0).to_int(), 0);
    try bout.start(&vm, gannet, duel.challenge(8, 0));
    try testing.expectEqual(@as(usize, 3), bout.usable_barbs(&vm, &barbs));
    for (1..4) |p| result = try bout.choose(&vm, duel.challenge(p, 0).to_int(), &buf);
    try testing.expectEqual(tamsin, result.winner.?);
}

test "P35-02: the Tidewalk fencers patrol once the script's routines start" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();

    const tidewalk = try world.intern_entity("Tidewalk");
    const east = spatial.graph.find_waypoint_in_room(tidewalk, "TidewalkEast").?;
    const pike = try world.intern_entity("BosunPike");
    const gannet = try world.intern_entity("OldGannet");
    try spatial.register_entity(pike, east, 11);
    try spatial.register_entity(gannet, east, 11);

    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    _ = try bespoke.host.start_script(&world, &spatial, &vm, &compiled);

    // The desktop window once skipped `start_script`, so both fencers stood on TidewalkEast.
    var pike_left = false;
    var gannet_left = false;
    for (0..60) |_| {
        _ = try bespoke.host.tick(&vm, &compiled);
        if (spatial.agents.get(pike).?.current_wp != east) pike_left = true;
        if (spatial.agents.get(gannet).?.current_wp != east) gannet_left = true;
    }
    try testing.expect(pike_left);
    try testing.expect(gannet_left);
}

test "P15-04: headless simulation of Brackwater Barbs passes cleanly" {
    const testing = std.testing;
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try run_headless(testing.allocator, buf.writer());
    try testing.expect(buf.items.len > 0);
}
