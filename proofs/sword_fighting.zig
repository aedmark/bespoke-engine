const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const SwordKey = enum(u16) { duel_pike, duel_vell, talk_barkeep, wait_50, duel_gannet, duel_dory };

const sword_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_d, .action = @intFromEnum(SwordKey.duel_pike), .sfx = art.sfx(.sword_clash) },
    .{ .key = bespoke.display.renderer.c.SDLK_c, .action = @intFromEnum(SwordKey.duel_vell), .sfx = art.sfx(.sword_clash) },
    .{ .key = bespoke.display.renderer.c.SDLK_t, .action = @intFromEnum(SwordKey.talk_barkeep) },
    .{ .key = bespoke.display.renderer.c.SDLK_w, .action = @intFromEnum(SwordKey.wait_50) },
    .{ .key = bespoke.display.renderer.c.SDLK_g, .action = @intFromEnum(SwordKey.duel_gannet), .sfx = art.sfx(.sword_clash) },
    .{ .key = bespoke.display.renderer.c.SDLK_h, .action = @intFromEnum(SwordKey.duel_dory), .sfx = art.sfx(.sword_clash) },
});

/// The Brackwater Barbs script: a fencing duel of barbs and comebacks, and a barkeep who
/// tires of repeated questions (P35-02 replaced the borrowed duel with this original).
pub const SWORD_FIGHTING_SCRIPT =
    \\scene: Tidewalk
    \\cast: Tamsin, BosunPike, OldGannet, DoryQuill
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
    \\  fallback "Is that a sea gull on your head or are you just happy to see me?"
    \\  fallback "I'd give you an answer but my parrot usually does all the talking..."
    \\  fallback "Hold that thought! ...I might be getting a nosebleed."
    \\  fallback "I think I hear my mom calling me for dinner."
    \\  fallback "I wish I'd thought of that one..."
    \\  win 3
    \\  relations HeardBarb MasteredComeback Counters VellVariant FencingTier Advantage DuelsWon
    \\  tier Vell 1
    \\  fatigue Inquiries "welcoming":
    \\    stage AnnoyedWith 2 100 "annoyed"
    \\    stage FuriousWith 3 250 "furious"
    \\
    \\relation MasteredComeback(fighter, comeback)
    \\
    \\~ Mistress Vell knows every comeback. The Tidewalk fencers' barbs and comebacks are dealt
    \\~ at random when the game starts (D-082); an answer a fencer knows parries Tamsin's barb
    \\~ and teaches her it.
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
    \\on cue WinsDuel(DoryQuill, Tamsin):
    \\  say DoryQuill: "Back to the nets with you, minnow."
    \\
    \\on cue WinsDuel(Tamsin, DoryQuill):
    \\  say DoryQuill: "Hooked and landed. Fair catch."
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
    \\routine PatrolDory(DoryQuill):
    \\  loop:
    \\    walk DoryQuill to TidewalkMid
    \\    wait 35 ticks
    \\    walk DoryQuill to TidewalkWest
    \\    wait 15 ticks
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
    // The script's top-level lines teach Vell every comeback; the console run walks a known
    // path, so it uses the fixed deal rather than a random one (D-082).
    try bespoke.host.run_initial_statements(&world, &vm, &compiled);
    try fixed_knowledge(&duel, bosun_pike, old_gannet);

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
/// The Tidewalk fencers, in key order: D, G, and H start their duels.
pub const FENCERS = [_][]const u8{ "BosunPike", "OldGannet", "DoryQuill" };

/// What each Tidewalk fencer says when it has no comeback for Tamsin's barb, three lines each
/// in its own voice, in rotation (D-085; the maintainer approved them 2026-11-13). Mistress
/// Vell knows every comeback and needs none; Tamsin keeps the duel's shared joke pool.
pub const STUMPED_LINES = [FENCERS.len][3][]const u8{
    .{
        "Belay that! I'll answer when I'm good and ready!",
        "The wind took my words. Clean overboard.",
        "Don't rush me, I'm counting the knots in my reply.",
    },
    .{
        "Hmm? Speak up, my ears went out with the tide.",
        "I had a good one for that. Forty years ago.",
        "Back in my day, nobody said things like that.",
    },
    .{
        "That one slipped right through my nets.",
        "Give me a moment, I'm still untangling that.",
        "I'd throw that one back. Too small to answer.",
    },
};

/// Chance, in percent, that a fencer other than a barb's dealt owner also throws it.
const SHARED_BARB_PERCENT: u8 = 35;
/// Chance, in percent, that a fencer knows any one comeback.
const COMEBACK_PERCENT: u8 = 45;

/// Deals the Tidewalk fencers' knowledge at random (D-082). Each barb goes to one fencer,
/// and each other fencer also throws it at `SHARED_BARB_PERCENT`, so some barbs belong to
/// one fencer alone. Each fencer knows each comeback at `COMEBACK_PERCENT`, and a comeback
/// no one drew goes to a random fencer. Every barb is thrown and every comeback is known
/// by someone, so all of them stay learnable. Knowledge is facts: call this before the first
/// snapshot, and rewind and saves keep the deal.
pub fn deal_knowledge(duel: *duel_mod.Duel, fencers: []const bespoke.EntityId, seed: u64) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rnd = prng.random();
    for (0..duel.config.pairs.len) |p| {
        const owner = rnd.uintLessThan(usize, fencers.len);
        for (fencers, 0..) |fencer, i| {
            if (i == owner or rnd.uintLessThan(u8, 100) < SHARED_BARB_PERCENT) try duel.hear(fencer, duel.challenge(p, 0));
        }
        var known = false;
        for (fencers) |fencer| {
            if (rnd.uintLessThan(u8, 100) < COMEBACK_PERCENT) {
                try duel.master(fencer, duel.reply(p));
                known = true;
            }
        }
        if (!known) try duel.master(fencers[rnd.uintLessThan(usize, fencers.len)], duel.reply(p));
    }
}

/// A fixed deal for the console run and the tests that walk a known path: Bosun Pike throws
/// and answers barbs 1 to 8, Old Gannet barb 1 and 9 to 15 (the split D-078 fixed in the
/// script before D-082 dealt it at random).
pub fn fixed_knowledge(duel: *duel_mod.Duel, pike: bespoke.EntityId, gannet: bespoke.EntityId) !void {
    for (0..duel.config.pairs.len) |p| {
        const fencer = if (p < 8) pike else gannet;
        try duel.hear(fencer, duel.challenge(p, 0));
        try duel.master(fencer, duel.reply(p));
    }
    try duel.hear(gannet, duel.challenge(0, 0));
    try duel.master(gannet, duel.reply(0));
}

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
    /// Barbs the opponent has thrown in this duel; it draws the next from the rest (D-083).
    foe_thrown_rel: bespoke.RelationKind,
    /// The seed and the count of draws made from it (D-083). Every random pick hashes the
    /// seed with the count, and both are facts, so a rewind replays the same picks.
    seed_rel: bespoke.RelationKind,
    draws_rel: bespoke.RelationKind,

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
            .foe_thrown_rel = try world.intern_relation("OpponentThrewThisDuel", .set),
            .seed_rel = try world.intern_relation("DuelSeed", .property),
            .draws_rel = try world.intern_relation("DuelDraws", .property),
        };
    }

    /// Sets the seed for every random pick (D-083). Call before the first snapshot; without it
    /// the seed is 0, which is still deterministic.
    pub fn set_seed(self: *Bout, seed: u32) !void {
        try self.world.remember(self.player, self.seed_rel, seed, 0);
    }

    /// A pick below `n`, from the seed and the draw count, which it advances.
    fn draw(self: *Bout, n: usize) !usize {
        if (n <= 1) return 0;
        const seed = self.world.get_property(self.player, self.seed_rel) orelse 0;
        const k = self.world.get_property(self.player, self.draws_rel) orelse 0;
        try self.world.remember(self.player, self.draws_rel, k +% 1, 0);
        const word = [2]u32{ seed, k };
        return @intCast(std.hash.Wyhash.hash(0x5EA5, std.mem.asBytes(&word)) % n);
    }

    /// Shuffles `items` in place with `draw` (Fisher-Yates).
    fn shuffle(self: *Bout, comptime T: type, items: []T) !void {
        var i = items.len;
        while (i > 1) {
            i -= 1;
            const j = try self.draw(i + 1);
            std.mem.swap(T, &items[i], &items[j]);
        }
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
    /// tier, and not yet thrown in this duel, in table order. `open` offers a random handful.
    pub fn usable_barbs(self: *const Bout, vm: *bespoke.VM, out: []duel_mod.Candidate) usize {
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

    /// The barb `foe` throws next (D-082, D-083): a random draw from the barbs it may throw that
    /// it has not thrown this duel, or from all of them once it has thrown every one. A
    /// Tidewalk fencer throws only barbs it knows (has heard), so each fencer has its own
    /// repertoire and learns Tamsin's barbs by hearing them; a master throws every barb at its
    /// tier. A fencer that knows none throws from the whole table.
    pub fn next_barb(self: *Bout, foe: bespoke.EntityId) !bespoke.EntityId {
        const tier = self.world.get_property(foe, self.duel.tier_rel) orelse 0;
        var pool: [64]bespoke.EntityId = undefined;
        var fresh: [64]bespoke.EntityId = undefined;
        var pool_n: usize = 0;
        var fresh_n: usize = 0;
        for (0..@min(self.duel.config.pairs.len, pool.len)) |p| {
            var barb = self.duel.challenge(p, 0);
            if (self.is_master(foe)) {
                const variant = self.duel.challenge(p, tier);
                if (variant != .none) barb = variant;
            } else if (!self.world.has_fact(foe, self.duel.heard_rel, barb.to_int())) continue;
            pool[pool_n] = barb;
            pool_n += 1;
            if (!self.world.has_fact(self.player, self.foe_thrown_rel, barb.to_int())) {
                fresh[fresh_n] = barb;
                fresh_n += 1;
            }
        }
        if (fresh_n > 0) return fresh[try self.draw(fresh_n)];
        if (pool_n > 0) return pool[try self.draw(pool_n)];
        return self.duel.challenge(try self.draw(self.duel.config.pairs.len), 0);
    }

    /// Sets the barb the opponent throws next and marks it thrown this duel.
    fn attack_with(self: *Bout, barb: bespoke.EntityId) !void {
        try self.world.remember(self.player, self.challenge_rel, barb.to_int(), 0);
        try self.world.remember(self.player, self.foe_thrown_rel, barb.to_int(), 0);
    }

    /// Starts a duel. The player leads if she has a barb to throw at this opponent and the
    /// opponent is not a master; otherwise the opponent opens with `opening`, or with its next
    /// barb (`next_barb`) when `opening` is `.none`.
    pub fn start(self: *Bout, vm: *bespoke.VM, foe: bespoke.EntityId, opening: bespoke.EntityId) !void {
        self.clear();
        try self.world.remember(self.player, self.opponent_rel, foe.to_int(), 0);
        try self.world.remember(self.player, self.duel.advantage_rel, 0, 0);
        try self.world.remember(foe, self.duel.advantage_rel, 0, 0);
        var barbs: [64]duel_mod.Candidate = undefined;
        if (!self.is_master(foe) and self.usable_barbs(vm, &barbs) > 0) {
            try self.world.remember(self.player, self.attacking_rel, 1, 0);
        } else {
            try self.attack_with(if (opening == .none) try self.next_barb(foe) else opening);
        }
    }

    /// Ends the duel and closes its choice set.
    pub fn clear(self: *Bout) void {
        if (self.opponent()) |foe| bespoke.dialogue.clear_open(self.world, foe) catch {};
        _ = self.world.forget(self.player, self.opponent_rel, null);
        _ = self.world.forget(self.player, self.challenge_rel, null);
        _ = self.world.forget(self.player, self.attacking_rel, null);
        _ = self.world.forget(self.player, self.thrown_rel, null);
        _ = self.world.forget(self.player, self.foe_thrown_rel, null);
    }

    /// Action ids at and above this are joke answers: `JOKE_ACTION + i` is fallback line `i`.
    /// Entity ids stay far below it.
    pub const JOKE_ACTION: u32 = 0x8000_0000;
    /// Joke answers offered in every defence, after the player's known comebacks.
    pub const JOKES_OFFERED: usize = 2;
    /// Jokes offered while the player attacks, after her barbs: picking one concedes the round.
    pub const FLUBS_OFFERED: usize = 1;

    /// Opens the round's choices as a generated dialogue set: the barbs the player may throw
    /// while she attacks, else her comebacks to the opponent's barb followed by two joke
    /// answers. Jokes show in every defence, not only when she lacks the counter, so their
    /// presence never gives away what she knows; a joke always loses the round. Each action id
    /// is the chosen barb or comeback entity, or `JOKE_ACTION` plus the joke's line index.
    pub fn open(self: *Bout, vm: *bespoke.VM) !void {
        const foe = self.opponent() orelse return;
        // The panel holds nine choices, so a player who knows more lines than fit is offered
        // a fresh random handful each turn (D-083): every line she knows turns up in time, and
        // the order never hints at which one is right.
        var all: [64]duel_mod.Candidate = undefined;
        var candidates: [9]duel_mod.Candidate = undefined;
        var prompt: []const u8 = "";
        var count: usize = 0;
        if (self.player_attacks()) {
            const n = self.usable_barbs(vm, &all);
            try self.shuffle(duel_mod.Candidate, all[0..n]);
            // Leave a slot for the flub (D-082).
            count = @min(n, candidates.len - FLUBS_OFFERED);
            @memcpy(candidates[0..count], all[0..count]);
            prompt = "Your turn: throw a barb.";
        } else {
            const raw = self.world.get_property(self.player, self.challenge_rel) orelse return;
            const barb = bespoke.EntityId.from_int(raw);
            // The engine's lone fallback is dropped; the jokes replace it.
            var n: usize = 0;
            const listed = self.duel.replies(vm, self.player, barb, &all);
            for (all[0..listed]) |cand| {
                if (cand.entity == .none) continue;
                all[n] = cand;
                n += 1;
            }
            try self.shuffle(duel_mod.Candidate, all[0..n]);
            count = @min(n, candidates.len - JOKES_OFFERED);
            // A countering comeback she knows is always among those offered, at a random place.
            for (all[count..n]) |cand| if (cand.counters) {
                all[try self.draw(count)] = cand;
            };
            @memcpy(candidates[0..count], all[0..count]);
            prompt = self.duel.challenge_text(barb) orelse "";
        }
        var choices: [9]bespoke.dialogue.Choice = undefined;
        for (0..count) |i| choices[i] = .{ .text = candidates[i].text, .action = candidates[i].entity.to_int() };
        const lines = self.duel.config.fallbacks;
        if (lines.len > 0) {
            // The fumble count rotates the jokes, so successive rounds offer new ones and the
            // rotation rewinds with the world (D-076). An attacker gets one: a flub that hands
            // the opponent the round and the next attack, so the player can hear a new barb.
            const offered: usize = if (self.player_attacks()) FLUBS_OFFERED else JOKES_OFFERED;
            const first = self.duel.fumbles(self.player) * JOKES_OFFERED;
            for (0..@min(offered, lines.len)) |k| {
                const index = (first + k) % lines.len;
                choices[count] = .{ .text = lines[index], .action = JOKE_ACTION + @as(u32, @intCast(index)) };
                count += 1;
            }
        }
        if (count == 0) return;
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
    /// What `foe` just said with no comeback: its own line from `STUMPED_LINES`, picked by its
    /// fumble count (raised by the round, so it rewinds with the world), or a line from the
    /// shared pool for anyone without lines of its own.
    fn stumped_line(self: *const Bout, foe: bespoke.EntityId) []const u8 {
        const name = self.world.get_entity_name(foe) orelse return self.spoken_fallback(foe);
        for (FENCERS, 0..) |fencer, i| {
            if (!std.mem.eql(u8, fencer, name)) continue;
            const lines = STUMPED_LINES[i];
            return lines[(self.duel.fumbles(foe) + lines.len - 1) % lines.len];
        }
        return self.spoken_fallback(foe);
    }

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
        const joke: ?[]const u8 = if (action >= JOKE_ACTION and action - JOKE_ACTION < self.duel.config.fallbacks.len)
            self.duel.config.fallbacks[action - JOKE_ACTION]
        else
            null;
        const picked = if (action == 0 or joke != null) bespoke.EntityId.none else bespoke.EntityId.from_int(action);
        const player_led = self.player_attacks();

        var said: []const u8 = "";
        var player_said: []const u8 = "";
        var barb: bespoke.EntityId = undefined;
        var round: duel_mod.Round = undefined;
        if (player_led and joke != null) {
            // A flub concedes the round (D-082): the opponent scores and attacks next.
            barb = .none;
            player_said = joke.?;
            round = try self.duel.concede(self.player, foe);
        } else if (player_led) {
            // The opponent answers the player's barb with what it knows; a real answer teaches
            // the player that comeback (D-078).
            barb = picked;
            player_said = self.duel.challenge_text(barb) orelse "";
            try self.world.remember(self.player, self.thrown_rel, barb.to_int(), 0);
            const reply = self.duel.answer(foe, barb);
            round = try self.duel.resolve_round(self.player, foe, barb, reply);
            said = if (reply != .none) (self.duel.reply_text(barb) orelse "") else self.stumped_line(foe);
        } else {
            const raw = self.world.get_property(self.player, self.challenge_rel) orelse return .{};
            barb = bespoke.EntityId.from_int(raw);
            round = try self.duel.resolve_round(foe, self.player, barb, picked);
            player_said = if (joke) |line| line else if (picked == .none) self.spoken_fallback(self.player) else self.reply_line(picked);
        }
        const player_won_round = if (player_led) joke == null and !round.parried else round.parried;

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
        var left: [64]duel_mod.Candidate = undefined;
        if (player_won_round and !self.is_master(foe) and self.usable_barbs(vm, &left) > 0) {
            try self.world.remember(self.player, self.attacking_rel, 1, 0);
        } else {
            _ = self.world.forget(self.player, self.attacking_rel, null);
            try self.attack_with(try self.next_barb(foe));
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
    const dory_quill = try world.intern_entity("DoryQuill");
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
    const walk_w = spatial.graph.find_waypoint_in_room(tidewalk_scene, "TidewalkWest") orelse return error.MissingMark;
    try spatial.register_entity(dory_quill, walk_w, 11);
    try spatial.register_entity(vell, circle_wp, 12);
    try spatial.register_entity(barkeep, counter_wp, 13);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    // The script's top-level lines declare what each opponent knows (D-078); its routines walk
    // Pike and Gannet along the Tidewalk and the barkeep behind the counter. Actors placed above
    // keep their marks.
    _ = try bespoke.host.start_script(&world, &spatial, &vm, &compiled);
    // A fresh deal of the fencers' barbs and comebacks each launch (D-082), before the first
    // snapshot, so rewinding keeps it.
    const launch_seed: u64 = @bitCast(std.time.milliTimestamp());
    try deal_knowledge(&duel, &.{ bosun_pike, old_gannet, dory_quill }, launch_seed);
    // The same launch seeds every pick of barbs and offered lines (D-083).
    try bout.set_seed(@truncate(launch_seed));
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
    try stdout.print("   - [1] - [9]:              Pick a barb, comeback, or joke\n", .{});
    try stdout.print("   - [D]:                    Duel Bosun Pike on the Tidewalk\n", .{});
    try stdout.print("   - [G]:                    Duel Old Gannet on the Tidewalk\n", .{});
    try stdout.print("   - [H]:                    Duel Dory Quill on the Tidewalk\n", .{});
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
                        try start_bout(&session, &vm, &bout, bosun_pike, .none);
                        window.set_cue_banner("Bosun Pike draws a rapier.", 120);
                    },
                    .duel_gannet => {
                        try vm.transition_to_scene(tidewalk_scene);
                        _ = try spatial.transition_actor(tamsin, tidewalk_scene, walk_m);
                        try start_bout(&session, &vm, &bout, old_gannet, .none);
                        window.set_cue_banner("Old Gannet squares up.", 120);
                    },
                    .duel_dory => {
                        try vm.transition_to_scene(tidewalk_scene);
                        _ = try spatial.transition_actor(tamsin, tidewalk_scene, walk_m);
                        try start_bout(&session, &vm, &bout, dory_quill, .none);
                        window.set_cue_banner("Dory Quill levels her boathook.", 120);
                    },
                    .duel_vell => {
                        try vm.transition_to_scene(yard_scene);
                        _ = try spatial.transition_actor(tamsin, yard_scene, circle_wp);
                        try start_bout(&session, &vm, &bout, vell, .none);
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
    try testing.expectEqual(@as(usize, 8), duel.config.fallbacks.len);
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
    try fixed_knowledge(&duel, try world.intern_entity("BosunPike"), try world.intern_entity("OldGannet"));

    const tamsin = try world.intern_entity("Tamsin");
    const pike = try world.intern_entity("BosunPike");
    const vell = try world.intern_entity("Vell");
    var bout = try Bout.init(&world, &duel, tamsin);
    var buf: [320]u8 = undefined;

    // Duel 1: Tamsin knows nothing, so Pike leads. Each fumble loses a point, teaches no
    // comeback, and Pike presses on with a different barb from his repertoire, drawn at
    // random (D-083), never the answer to the last.
    try bout.start(&vm, pike, duel.challenge(0, 0));
    try testing.expect(!bout.player_attacks());
    var result: Bout.Result = undefined;
    var seen: [3]u32 = .{ 0, 0, 0 };
    for (0..3) |round| {
        try bout.open(&vm);
        const open = vm.dialogue_view().?;
        const thrown = world.get_property(tamsin, bout.challenge_rel).?;
        if (round == 0) try testing.expectEqual(duel.challenge(0, 0).to_int(), thrown);
        try testing.expect(world.has_fact(pike, duel.heard_rel, thrown));
        for (seen[0..round]) |earlier| try testing.expect(earlier != thrown);
        seen[round] = thrown;
        try testing.expectEqualStrings(duel.challenge_text(bespoke.EntityId.from_int(thrown)).?, open.prompt);
        // She knows no comeback, so two jokes are her answers, a new pair each round.
        try testing.expectEqual(@as(usize, Bout.JOKES_OFFERED), open.count);
        try testing.expectEqualStrings(duel.config.fallbacks[2 * round], open.text(0));
        try testing.expectEqualStrings(duel.config.fallbacks[2 * round + 1], open.text(1));
        result = try bout.choose(&vm, open.actions[1], &buf);
        try testing.expectEqualStrings(duel.config.fallbacks[2 * round + 1], result.lines[0].text);
        if (result.winner == null) try testing.expectEqualStrings("Their point.", result.lines[1].text);
        try testing.expect(!world.has_fact(tamsin, duel.mastered_rel, null));
        try testing.expect(!result.says(duel.reply_text(bespoke.EntityId.from_int(thrown)).?));
    }
    try testing.expectEqual(pike, result.winner.?);
    try testing.expect(bout.opponent() == null);

    // The script speaks the victory line from its WinsDuel handler.
    _ = (try vm.fire_cue(&compiled, "WinsDuel", pike, tamsin, null)).?;
    _ = try bespoke.host.tick(&vm, &compiled);
    var speech: [256]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, bespoke.host.speech_this_tick(&world, &vm, &speech).?, "Go back to your mop") != null);

    // Duel 2: she has heard three barbs, so she leads, with a flub after them (D-082). Pike
    // knows Comeback 1, parries, and she learns it by hearing it; then Pike attacks with a
    // barb from his repertoire.
    try bout.start(&vm, pike, .none);
    try testing.expect(bout.player_attacks());
    try bout.open(&vm);
    try testing.expectEqual(@as(usize, 3 + Bout.FLUBS_OFFERED), vm.dialogue_view().?.count);
    try testing.expect(vm.dialogue_view().?.actions[3] >= Bout.JOKE_ACTION);
    result = try bout.choose(&vm, duel.challenge(0, 0).to_int(), &buf);
    try testing.expect(world.has_fact(tamsin, duel.mastered_rel, duel.reply(0).to_int()));
    try testing.expect(result.says(duel.config.pairs[0].reply));
    try testing.expect(!bout.player_attacks());
    try bout.open(&vm);
    try testing.expect(world.has_fact(pike, duel.heard_rel, world.get_property(tamsin, bout.challenge_rel).?));

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
    try fixed_knowledge(&duel, try world.intern_entity("BosunPike"), try world.intern_entity("OldGannet"));

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
    // Four messages, each shown on its own (D-080): Tamsin's barb in her voice, Gannet's own
    // stumped line (D-085), the outcome, the points.
    try testing.expectEqual(@as(usize, 4), result.line_count);
    try testing.expectEqualStrings("Tamsin", result.lines[0].speaker);
    try testing.expectEqualStrings(duel.config.pairs[1].challenge, result.lines[0].text);
    try testing.expectEqualStrings("OldGannet", result.lines[1].speaker);
    try testing.expectEqualStrings(STUMPED_LINES[1][0], result.lines[1].text);
    try testing.expectEqualStrings("Your point.", result.lines[2].text);
    try testing.expectEqualStrings("Points: you 1, Old Gannet 0.", result.lines[3].text);
    try testing.expectEqual(@as(usize, 0), bout.usable_barbs(&vm, &barbs));
    try testing.expect(!bout.player_attacks());

    // Gannet's barb lands; Tamsin keeps the point she scored (D-079). Her fumble is echoed in
    // her voice, and Gannet says nothing in reply. Knowing a comeback, she still sees two jokes
    // after it, so the jokes never give away whether she knows the answer.
    try duel.master(tamsin, duel.reply(0));
    try bout.open(&vm);
    const defence = vm.dialogue_view().?;
    try testing.expectEqual(@as(usize, 1 + Bout.JOKES_OFFERED), defence.count);
    try testing.expectEqualStrings(duel.config.pairs[0].reply, defence.text(0));
    try testing.expect(defence.actions[1] >= Bout.JOKE_ACTION);
    result = try bout.choose(&vm, 0, &buf);
    try testing.expectEqualStrings("Tamsin", result.lines[0].speaker);
    try testing.expectEqualStrings(duel.config.fallbacks[0], result.lines[0].text);
    try testing.expectEqualStrings("Their point.", result.lines[1].text);
    try testing.expectEqual(@as(u32, 1), duel.advantage(tamsin));
    try testing.expectEqual(@as(u32, 1), duel.advantage(gannet));

    // A new duel lets every barb be thrown again: the three she learned plus Gannet's own
    // barb 10, which she heard him throw. Three barbs Gannet cannot answer win it.
    try world.remember(tamsin, duel.heard_rel, duel.challenge(2, 0).to_int(), 0);
    try world.remember(tamsin, duel.heard_rel, duel.challenge(3, 0).to_int(), 0);
    try bout.start(&vm, gannet, duel.challenge(8, 0));
    try testing.expectEqual(@as(usize, 4), bout.usable_barbs(&vm, &barbs));
    for (1..4) |p| result = try bout.choose(&vm, duel.challenge(p, 0).to_int(), &buf);
    try testing.expectEqual(tamsin, result.winner.?);
}

test "D-082: the deal leaves every barb thrown and every comeback known, with some exclusive" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();
    var duel = try duel_mod.Duel.init(&world, compiled.duels.items[0].config);
    var fencers: [FENCERS.len]bespoke.EntityId = undefined;
    for (FENCERS, 0..) |name, i| fencers[i] = try world.intern_entity(name);

    var deals: [2]u64 = .{ 0, 0 };
    for (1..41) |seed| {
        for (fencers) |f| {
            _ = world.forget(f, duel.heard_rel, null);
            _ = world.forget(f, duel.mastered_rel, null);
        }
        try deal_knowledge(&duel, &fencers, seed);
        var exclusive: usize = 0;
        var shape = std.hash.Wyhash.init(0);
        for (0..duel.config.pairs.len) |p| {
            var throwers: usize = 0;
            var knowers: usize = 0;
            for (fencers) |f| {
                if (world.has_fact(f, duel.heard_rel, duel.challenge(p, 0).to_int())) throwers += 1;
                if (world.has_fact(f, duel.mastered_rel, duel.reply(p).to_int())) knowers += 1;
                shape.update(&.{ @intFromBool(world.has_fact(f, duel.heard_rel, duel.challenge(p, 0).to_int())), @intFromBool(world.has_fact(f, duel.mastered_rel, duel.reply(p).to_int())) });
            }
            try testing.expect(throwers >= 1);
            try testing.expect(knowers >= 1);
            if (throwers == 1) exclusive += 1;
        }
        try testing.expect(exclusive >= 1);
        if (seed <= 2) deals[seed - 1] = shape.final();
    }
    // Different seeds deal differently.
    try testing.expect(deals[0] != deals[1]);
}

test "D-082: a flub hands the fencer the round and a new barb from its own repertoire" {
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
    const dory = try world.intern_entity("DoryQuill");
    // Dory throws only barbs 4 and 11; Tamsin knows barb 1.
    try duel.hear(dory, duel.challenge(3, 0));
    try duel.hear(dory, duel.challenge(10, 0));
    try duel.hear(tamsin, duel.challenge(0, 0));
    var bout = try Bout.init(&world, &duel, tamsin);
    var buf: [320]u8 = undefined;

    try bout.start(&vm, dory, .none);
    try testing.expect(bout.player_attacks());
    try bout.open(&vm);
    const offer = vm.dialogue_view().?;
    try testing.expectEqual(@as(usize, 2), offer.count);
    const flub = offer.actions[1];
    try testing.expect(flub >= Bout.JOKE_ACTION);

    const result = try bout.choose(&vm, flub, &buf);
    try testing.expectEqualStrings("Tamsin", result.lines[0].speaker);
    try testing.expectEqualStrings(offer.text(1), result.lines[0].text);
    try testing.expectEqualStrings("Their point.", result.lines[1].text);
    try testing.expectEqual(@as(u32, 1), duel.advantage(dory));
    try testing.expect(!bout.player_attacks());
    // Dory attacks from her own repertoire, and never repeats a barb within the duel while she
    // has another (D-083).
    try bout.open(&vm);
    const first = world.get_property(tamsin, bout.challenge_rel).?;
    try testing.expect(first == duel.challenge(3, 0).to_int() or first == duel.challenge(10, 0).to_int());
    _ = try bout.choose(&vm, 0, &buf);
    try bout.open(&vm);
    const second = world.get_property(tamsin, bout.challenge_rel).?;
    try testing.expect(second != first);
    try testing.expect(second == duel.challenge(3, 0).to_int() or second == duel.challenge(10, 0).to_int());
}

test "D-083: offers rotate past nine, a known counter is always offered, and picks rewind" {
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
    try bout.set_seed(42);
    // Tamsin knows every barb and every comeback: more lines than the panel's nine.
    for (0..duel.config.pairs.len) |p| {
        try duel.hear(tamsin, duel.challenge(p, 0));
        try duel.master(tamsin, duel.reply(p));
    }

    // Attacking: eight barbs and the flub per turn, a different handful each time, and every
    // barb turns up within a few turns.
    var offered = [_]bool{false} ** 15;
    try bout.start(&vm, gannet, .none);
    for (0..12) |_| {
        _ = world.forget(tamsin, bout.thrown_rel, null);
        try bout.open(&vm);
        const v = vm.dialogue_view().?;
        try testing.expectEqual(@as(usize, 9), v.count);
        try testing.expect(v.actions[8] >= Bout.JOKE_ACTION);
        for (v.actions[0..8]) |a| offered[duel.pair_index_of(bespoke.EntityId.from_int(a)).?] = true;
    }
    for (offered) |seen| try testing.expect(seen);

    // Defending: seven comebacks and two jokes, and the counter is always among them.
    _ = world.forget(tamsin, bout.attacking_rel, null);
    for (0..duel.config.pairs.len) |p| {
        try world.remember(tamsin, bout.challenge_rel, duel.challenge(p, 0).to_int(), 0);
        try bout.open(&vm);
        const v = vm.dialogue_view().?;
        try testing.expectEqual(@as(usize, 9), v.count);
        var has_counter = false;
        for (v.actions[0..7]) |a| {
            if (a == duel.reply(p).to_int()) has_counter = true;
        }
        try testing.expect(has_counter);
    }

    // The picks come from facts, so restoring a snapshot replays them.
    var snapshot = std.ArrayList(u8).init(testing.allocator);
    defer snapshot.deinit();
    try world.save_state(snapshot.writer());
    const before = try bout.next_barb(gannet);
    var stream = std.io.fixedBufferStream(snapshot.items);
    try world.restore_state(stream.reader());
    try testing.expectEqual(before, try bout.next_barb(gannet));
}

test "D-085: each fencer rotates through its own three stumped lines" {
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
    var bout = try Bout.init(&world, &duel, tamsin);
    var buf: [320]u8 = undefined;
    // Tamsin knows four barbs; no fencer knows a comeback.
    for (0..4) |p| try duel.hear(tamsin, duel.challenge(p, 0));

    for (FENCERS, 0..) |name, f| {
        const fencer = try world.intern_entity(name);
        try bout.start(&vm, fencer, .none);
        // Three unanswerable barbs win the duel, and the fencer says its three lines in order.
        for (0..3) |p| {
            const result = try bout.choose(&vm, duel.challenge(p, 0).to_int(), &buf);
            try testing.expectEqualStrings(name, result.lines[1].speaker);
            try testing.expectEqualStrings(STUMPED_LINES[f][p], result.lines[1].text);
        }
        try testing.expect(bout.opponent() == null);
        // The next duel starts the rotation over.
        try bout.start(&vm, fencer, .none);
        const again = try bout.choose(&vm, duel.challenge(3, 0).to_int(), &buf);
        try testing.expectEqualStrings(STUMPED_LINES[f][0], again.lines[1].text);
        bout.clear();
    }
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
