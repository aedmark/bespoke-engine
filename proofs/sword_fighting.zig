const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

/// Keys this proof binds through its theme (P32-02c); the engine returns them as
/// `UserAction.custom`.
const SwordKey = enum(u16) { duel_bob, duel_carla, talk_barkeep, wait_50 };

const sword_theme = art.with_keys(&.{
    .{ .key = bespoke.display.renderer.c.SDLK_d, .action = @intFromEnum(SwordKey.duel_bob), .sfx = art.sfx(.sword_clash) },
    .{ .key = bespoke.display.renderer.c.SDLK_c, .action = @intFromEnum(SwordKey.duel_carla), .sfx = art.sfx(.sword_clash) },
    .{ .key = bespoke.display.renderer.c.SDLK_t, .action = @intFromEnum(SwordKey.talk_barkeep) },
    .{ .key = bespoke.display.renderer.c.SDLK_w, .action = @intFromEnum(SwordKey.wait_50) },
});

/// BeSpoke DSL Script for Monkey Island Insult Sword Fighting and Organic NPC Repetition
pub const SWORD_FIGHTING_SCRIPT =
    \\scene: High Road
    \\cast: Guybrush, PirateBob, PiratePegleg
    \\marks: RoadLeft, RoadCenter, RoadRight
    \\
    \\scene: Sword Master Sanctuary
    \\cast: Carla
    \\marks: SanctuaryGate, ArenaCenter, HouseDoor
    \\
    \\scene: Scumm Bar
    \\cast: Barkeep, Citizen
    \\marks: BarEntrance, CounterMark, FireplaceMark
    \\
    \\duel InsultSwordFighting:
    \\  pair Insult1:
    \\    challenge "You fight like a dairy farmer!"
    \\    reply "How appropriate. You fight like a cow!"
    \\    variant 1 "I will milk every drop of blood from your body!"
    \\  pair Insult2:
    \\    challenge "This is the END for you, you gutter-crawling cur!"
    \\    reply "And I've got a little TIP for you, get the POINT?"
    \\    variant 1 "I've got the courage and skill of a master!"
    \\  pair Insult3:
    \\    challenge "I've spoken with apes more polite than you!"
    \\    reply "I'm glad to hear you attended your family reunion."
    \\    variant 1 "Now I know what filth and stupidity really are."
    \\  pair Insult4:
    \\    challenge "Soon you'll be wearing my sword like a shish kebab!"
    \\    reply "First you'd better stop waving it like a feather duster."
    \\    variant 1 "My sword is famous all across the Caribbean!"
    \\  pair Insult5:
    \\    challenge "People fall at my feet when they see me coming!"
    \\    reply "Even BEFORE they smell your breath?"
    \\    variant 1 "My wisest enemies run away at the first sight of me!"
    \\  pair Insult6:
    \\    challenge "I'm not going to take your insolence sitting down!"
    \\    reply "Your hemorhoids are flaring up again eh?"
    \\    variant 1 "I usually work with people who have more courage than you."
    \\  pair Insult7:
    \\    challenge "I once owned a dog that was smarter than you."
    \\    reply "He must have taught you everything you know."
    \\    variant 1 "Only once have I met such a coward!"
    \\  pair Insult8:
    \\    challenge "Nobody's ever drawn blood from me and nobody ever will."
    \\    reply "You run THAT fast?"
    \\    variant 1 "No one has ever faced ME and lived to tell about it!"
    \\  pair Insult9:
    \\    challenge "Have you stopped wearing diapers yet?"
    \\    reply "Why, did you want to borrow one?"
    \\    variant 1 "I hope you have a boat ready for a quick escape."
    \\  pair Insult10:
    \\    challenge "There are no words for how disgusting you are."
    \\    reply "Yes there are, you just never learned them."
    \\    variant 1 "There are no clever moves that can help you now."
    \\  pair Insult11:
    \\    challenge "You make me want to puke."
    \\    reply "You make me think somebody already did."
    \\    variant 1 "If your brother's like you, better to marry a pig."
    \\  pair Insult12:
    \\    challenge "My handkerchief will wipe up your blood!"
    \\    reply "So you got that job as a janitor, after all."
    \\    variant 1 "My name is feared in every dirty salon!"
    \\  pair Insult13:
    \\    challenge "I got this scar on my face during a mighty struggle!"
    \\    reply "I hope now you've learned to stop picking your nose."
    \\    variant 1 "My face is a portrait of ruthless brutality!"
    \\  pair Insult14:
    \\    challenge "I've heard you are a contemptible sneak."
    \\    reply "Too bad no one's ever heard of YOU at all."
    \\    variant 1 "I will make sure no one remembers your name."
    \\  pair Insult15:
    \\    challenge "You're no match for my brains, you poor fool."
    \\    reply "I'd be in real trouble if you used them."
    \\    variant 1 "I've got a long, sharp lesson for you to learn today."
    \\  pair Insult16:
    \\    challenge "You have the manners of a beggar."
    \\    reply "I wanted to make sure you'd feel at home with me."
    \\    variant 1 "Every word you say to me is an insult."
    \\  fallback "I am shaking, I am shaking!"
    \\  win 3
    \\  relations HeardInsult MasteredReply Counters SwordMasterVariant IsSwordMaster Advantage DuelsWon
    \\  tier Carla 1
    \\  fatigue Inquiries "welcoming":
    \\    stage AnnoyedWith 2 100 "annoyed"
    \\    stage FuriousWith 3 250 "furious"
    \\
    \\routine PatrolRoad(PirateBob):
    \\  loop:
    \\    walk PirateBob to RoadLeft
    \\    wait 30 ticks
    \\    walk PirateBob to RoadRight
    \\    wait 30 ticks
    \\
    \\routine BarkeepTending(Barkeep):
    \\  loop:
    \\    walk Barkeep to CounterMark
    \\    wait 40 ticks
    \\    say Barkeep: "Finest grog on Melee Island!"
    \\    wait 40 ticks
    \\
    \\on cue TalksTo(Guybrush, Barkeep):
    \\  choice "Tell me about Governor Marley." if not Inquired(Guybrush, Marley, _):
    \\    say Barkeep: "Governor Marley? Sharp as a cutlass and twice as quick."
    \\    remember Inquired(Guybrush, Marley, 1)
    \\  choice "Tell me more about Governor Marley." if Inquired(Guybrush, Marley, 1):
    \\    say Barkeep: "Look, I already told you. Her mansion is on the hill."
    \\    remember Inquired(Guybrush, Marley, 2)
    \\    remember AnnoyedWith(Barkeep, Guybrush) for 100 ticks
    \\  choice "About Governor Marley..." if AnnoyedWith(Barkeep, Guybrush):
    \\    say Barkeep: "Are ye deaf, pirate? Buy a grog or get out of my tavern!"
    \\    remember FuriousWith(Barkeep, Guybrush) for 250 ticks
    \\  choice "Got any jobs for a mighty pirate?":
    \\    say Barkeep: "Go see the pirate leaders in the back room."
;

const duel_mod = bespoke.duel;
const ANNOYED: usize = 0;
const FURIOUS: usize = 1;

/// Executes deterministic headless simulation of Monkey Island Insult Sword Fighting and Organic NPC Repetition
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("   BeSpoke Engine: Monkey Island 1 Insult Sword Fighting Scenario   \n", .{});
    try writer.print(" (Combinatorial Queries * Target Invariants * Repetition Fatigue) \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Lowering Mêlée Island stageplay script to bytecode...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();

    if (compiled.duels.items.len != 1) return error.MissingSwordDuel;
    const duel_decl = &compiled.duels.items[0];
    var duel = try duel_mod.Duel.init(&world, duel_decl.config);
    var fatigue = try duel_mod.InquiryFatigue.init(&world, duel_decl.fatigue);
    const swagger_rel = try world.intern_relation("Swagger", .property);
    const path_chosen_rel = try world.intern_relation("PathChosen", .property);

    // Intern key actors
    const guybrush = try world.intern_entity("Guybrush");
    const pirate_bob = try world.intern_entity("PirateBob");
    const pirate_pegleg = try world.intern_entity("PiratePegleg");
    const carla = try world.intern_entity("Carla");
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
    // Step 1: Epistemological Zero Baseline & Learning First Insult and Reply
    // -------------------------------------------------------------------------
    try writer.print("[Step 1: Epistemological Zero Baseline]\n", .{});
    try writer.print("   -> Guybrush enters Mêlée Island with 0 known insults and 0 mastered replies.\n", .{});

    const insult_1 = duel.challenge(0, 0);
    const reply_1 = duel.reply(0);
    const insult_5 = duel.challenge(4, 0);
    const reply_5 = duel.reply(4);

    var candidate_replies: [8]duel_mod.Candidate = undefined;
    var reply_count = duel.replies(&vm, guybrush, insult_1, &candidate_replies);

    try writer.print("   -> Pirate Bob approaches on the High Road and draws cutlass!\n", .{});
    try writer.print("   -> Bob throws Insult 1: \"{s}\"\n", .{duel.config.pairs[0].challenge});
    try writer.print("   -> Active Choices Available to Guybrush ({d}):\n", .{reply_count});
    for (candidate_replies[0..reply_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\"\n", .{ i + 1, cand.text });
    }
    try std.testing.expectEqual(@as(usize, 1), reply_count);
    try std.testing.expectEqualStrings(duel.config.fallback.?, candidate_replies[0].text);

    // Guybrush uses fallback reply
    try writer.print("   -> Guybrush stammers: \"{s}\"\n", .{duel.config.fallback.?});
    const round_step1 = try duel.resolve_round(pirate_bob, guybrush, insult_1, candidate_replies[0].entity);
    try std.testing.expect(!round_step1.parried);

    try writer.print("   -> Bob strikes! Taunts: \"{s}\"\n", .{duel.config.pairs[0].reply});
    try writer.print("   -> Relational Learning Triggered:\n", .{});
    try writer.print("      - Remembered HeardInsult(Guybrush, 1): \"{s}\"\n", .{duel.config.pairs[0].challenge});
    try writer.print("      - Remembered MasteredReply(Guybrush, 1): \"{s}\"\n\n", .{duel.config.pairs[0].reply});

    try std.testing.expect(world.has_fact(guybrush, duel.heard_rel, insult_1.to_int()));
    try std.testing.expect(world.has_fact(guybrush, duel.mastered_rel, reply_1.to_int()));

    // -------------------------------------------------------------------------
    // Step 2: Initiative & Throwing Heard Insults
    // -------------------------------------------------------------------------
    try writer.print("[Step 2: Offensive Initiative with Learned Insults]\n", .{});
    var candidate_insults: [8]duel_mod.Candidate = undefined;
    const insult_count = duel.challenges(&vm, guybrush, pirate_pegleg, &candidate_insults);

    try writer.print("   -> Guybrush confronts Pirate Pegleg!\n", .{});
    try writer.print("   -> Available Offensive Insults for Guybrush ({d}):\n", .{insult_count});
    for (candidate_insults[0..insult_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\"\n", .{ i + 1, cand.text });
    }
    try std.testing.expectEqual(@as(usize, 1), insult_count);
    try std.testing.expectEqualStrings(duel.config.pairs[0].challenge, candidate_insults[0].text);

    try writer.print("   -> Guybrush throws Insult 1: \"{s}\"\n", .{duel.config.pairs[0].challenge});
    try writer.print("   -> Pegleg fails to counter and retorts with Insult 5: \"{s}\"\n", .{duel.config.pairs[4].challenge});

    // Defender hears Insult 5 and learns Reply 5 through combat
    try duel.hear(guybrush, insult_5);
    try duel.master(guybrush, reply_5);
    try writer.print("   -> Guybrush commits Insult 5 and Reply 5 to memory!\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 3: Dynamic Relational Counter-Strike & Advantage Progression
    // -------------------------------------------------------------------------
    try writer.print("[Step 3: Relational Query Pruning & Duel Victory]\n", .{});
    try writer.print("   -> Pirate Bob challenges Guybrush again!\n", .{});
    try writer.print("   -> Bob throws Insult 1: \"{s}\"\n", .{duel.config.pairs[0].challenge});

    reply_count = duel.replies(&vm, guybrush, insult_1, &candidate_replies);
    try writer.print("   -> Guybrush's Mastered Dialogue Options ({d}):\n", .{reply_count});
    var correct_choice_idx: ?usize = null;
    for (candidate_replies[0..reply_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\" (Counters Insult? {s})\n", .{
            i + 1,
            cand.text,
            if (cand.counters) "YES!" else "no",
        });
        if (cand.counters) correct_choice_idx = i;
    }
    try std.testing.expect(reply_count >= 2);
    try std.testing.expect(correct_choice_idx != null);

    const chosen = candidate_replies[correct_choice_idx.?];
    try writer.print("   -> Guybrush parries with Choice {d}: \"{s}\"\n", .{ correct_choice_idx.? + 1, chosen.text });
    const round_step3 = try duel.resolve_round(pirate_bob, guybrush, insult_1, chosen.entity);
    try std.testing.expect(round_step3.parried);

    // Score advantage to 3 to win duel
    try world.remember(guybrush, duel.advantage_rel, 3, 0);
    try world.remember(guybrush, duel.wins_rel, 1, 0);
    try world.remember(guybrush, swagger_rel, 2, 0);

    try writer.print("   -> Clang! Bob's cutlass flies from his hand! Guybrush wins the duel!\n", .{});
    try writer.print("   -> Facts asserted: Advantage(Guybrush, 3), DuelsWon(Guybrush, 1), Swagger(Guybrush, 2)\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 4: Carla the Sword Master & The Pete/Arantor Target Invariant
    // -------------------------------------------------------------------------
    try writer.print("[Step 4: Carla the Sword Master & Target Invariant Verification]\n", .{});
    try writer.print("   -> Guybrush crosses the rope bridge to Carla's Sword Master Sanctuary.\n", .{});

    // Carla throws the Sword Master variant of Insult 5
    const carla_insult = duel.challenge(4, 1);
    const carla_insult_text = duel.config.pairs[4].variants[0];
    try writer.print("   -> Carla sneers: \"{s}\"\n", .{carla_insult_text});

    reply_count = duel.replies(&vm, guybrush, carla_insult, &candidate_replies);
    try writer.print("   -> Relational Query maps Carla variant (105) to Standard Insult 5:\n", .{});
    for (candidate_replies[0..reply_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\" (Counters Carla? {s})\n", .{
            i + 1,
            cand.text,
            if (cand.counters) "YES!" else "no",
        });
    }
    try std.testing.expect(duel.counters(reply_5, carla_insult));

    // Guybrush parries Carla's elevated master insult
    const round_carla = try duel.resolve_round(carla, guybrush, carla_insult, reply_5);
    try std.testing.expect(round_carla.parried);
    try writer.print("   -> Guybrush parries Carla: \"{s}\"\n", .{duel.config.pairs[4].reply});
    try writer.print("   -> Carla is stunned: \"A sharp tongue as well as a sharp blade!\"\n", .{});

    // Test Pete Invariant: Guybrush has heard Carla's variant (the round above taught it).
    // If Guybrush tries to use Carla's Sword Master insult on regular pirate Bob, it will not fly!
    try std.testing.expect(world.has_fact(guybrush, duel.heard_rel, carla_insult.to_int()));

    var bob_insults: [8]duel_mod.Candidate = undefined;
    const bob_insult_count = duel.challenges(&vm, guybrush, pirate_bob, &bob_insults);
    try std.testing.expectEqual(@as(usize, 2), bob_insult_count);

    try writer.print("\n   [Pete/Arantor Invariant Check]\n", .{});
    try writer.print("   -> Guybrush tries to use Sword Master insult against regular Pirate Bob:\n", .{});
    var saw_carla_insult = false;
    for (bob_insults[0..bob_insult_count]) |cand| {
        if (cand.entity == carla_insult) saw_carla_insult = true;
    }
    try std.testing.expect(!saw_carla_insult);
    try writer.print("   -> Engine Pruning Verified: Sword Master insult filtered from regular pirate targets!\n", .{});
    try writer.print("   -> (As Pete noted: \"if you try to use a Sword Master insult on a regular pirate it won't fly\")\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 5: Organic Conversational Repetition Fatigue
    // -------------------------------------------------------------------------
    try writer.print("[Step 5: Organic Conversational Repetition Fatigue with the Barkeep]\n", .{});
    // Inquiry 1: Welcoming
    const mood1 = try fatigue.record(guybrush, barkeep);
    try writer.print("   -> [Inquiry 1] Guybrush: \"Tell me about Governor Marley.\"\n", .{});
    try writer.print("      Barkeep Mood: {s}\n", .{fatigue.label(mood1)});
    try writer.print("      Barkeep: \"Governor Marley? Sharp as a cutlass and twice as quick.\"\n", .{});
    try std.testing.expectEqual(@as(?usize, null), mood1);
    try std.testing.expect(!world.has_fact(barkeep, fatigue.stage_rels[ANNOYED], null));

    // Inquiry 2: Terse / Annoyed (TTL 100 ticks)
    const mood2 = try fatigue.record(guybrush, barkeep);
    try writer.print("   -> [Inquiry 2] Guybrush: \"Tell me more about Governor Marley.\"\n", .{});
    try writer.print("      Barkeep Mood: {s} (AnnoyedWith asserted for 100 ticks)\n", .{fatigue.label(mood2)});
    try writer.print("      Barkeep: \"Look, I already told you. Her mansion is on the hill.\"\n", .{});
    try std.testing.expectEqual(@as(?usize, ANNOYED), mood2);
    try std.testing.expect(world.has_fact(barkeep, fatigue.stage_rels[ANNOYED], guybrush.to_int()));

    // Inquiry 3: Furious / Slamming door (TTL 250 ticks)
    const mood3 = try fatigue.record(guybrush, barkeep);
    try writer.print("   -> [Inquiry 3] Guybrush: \"About Governor Marley...\"\n", .{});
    try writer.print("      Barkeep Mood: {s} (FuriousWith asserted for 250 ticks)\n", .{fatigue.label(mood3)});
    try writer.print("      Barkeep: \"Are ye deaf, pirate? Buy a grog or get out of my tavern!\"\n", .{});
    try std.testing.expectEqual(@as(?usize, FURIOUS), mood3);
    try std.testing.expect(world.has_fact(barkeep, fatigue.stage_rels[FURIOUS], guybrush.to_int()));

    // Inquiry 4 while furious: NPC refuses to talk
    const mood4 = fatigue.mood(barkeep, guybrush);
    try writer.print("   -> [Inquiry 4 while Furious] Barkeep slams mug on counter and turns his back!\n", .{});
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
    const mood_after_wait = fatigue.mood(barkeep, guybrush);
    try writer.print("   -> Barkeep Mood after 260 ticks: {s}\n", .{fatigue.label(mood_after_wait)});
    try std.testing.expectEqual(@as(?usize, null), mood_after_wait);
    try std.testing.expect(!world.has_fact(barkeep, fatigue.stage_rels[FURIOUS], guybrush.to_int()));
    try std.testing.expect(!world.has_fact(barkeep, fatigue.stage_rels[ANNOYED], guybrush.to_int()));
    try writer.print("   -> AnnoyedWith and FuriousWith TTL expired cleanly from SoA arena!\n", .{});
    try writer.print("   -> Barkeep: \"Welcome back, lad! Thirsty for grog?\"\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 7: Tangled World State Dialogue & Time-Travel Rewind
    // -------------------------------------------------------------------------
    try writer.print("[Step 7: Tangled World State Dialogue & Time-Travel Rewind]\n", .{});

    // Indiana Jones FOA 3 paths: 1 = Wits, 2 = Fists, 3 = Teamwork
    try world.remember(guybrush, path_chosen_rel, 1, 0); // Wits path
    try writer.print("   -> PathChosen(Guybrush, Wits) active.\n", .{});
    try writer.print("   -> Talking to Citizen of Mêlée...\n", .{});

    const is_wits = (world.get_property(guybrush, path_chosen_rel) orelse 0) == 1;
    const swagger_lvl = world.get_property(guybrush, swagger_rel) orelse 0;

    if (is_wits and swagger_lvl >= 2) {
        try writer.print("   -> Unlocked Tangled Option: \"I've mastered the blade through pure wit and outmatched Carla herself!\"\n", .{});
        try writer.print("   -> Citizen: \"By the Governor, you truly are a mighty pirate! Here is the Mêlée treasure map!\"\n", .{});
        const map_ent = try world.intern_entity("TreasureMap");
        const carries_rel = try world.intern_relation("Carries", .set);
        try world.remember(guybrush, carries_rel, map_ent.to_int(), 0);
    }
    try std.testing.expect(world.has_fact(guybrush, try world.intern_relation("Carries", .set), null));

    // Time-Travel Rewind to Snapshot 0 (Epistemological zero state)
    try writer.print("\n   [Deterministic Time-Travel Rewind Verification]\n", .{});
    _ = try timeline.restore(&world, 0);

    try writer.print("   -> Restored Snapshot 0 (Tick {d}).\n", .{world.current_tick});
    try writer.print("   -> Guybrush HeardInsults Count: {s}\n", .{
        if (!world.has_fact(guybrush, duel.heard_rel, null)) "0 (Clean)" else "Leaked!",
    });
    try writer.print("   -> Guybrush MasteredReplies Count: {s}\n", .{
        if (!world.has_fact(guybrush, duel.mastered_rel, null)) "0 (Clean)" else "Leaked!",
    });
    try std.testing.expect(!world.has_fact(guybrush, duel.heard_rel, null));
    try std.testing.expect(!world.has_fact(guybrush, duel.mastered_rel, null));

    try writer.print("\n>>> ALL MONKEY ISLAND INSULT SWORD FIGHTING & REPETITION TESTS PASSED! <<<\n", .{});
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

    const msg = std.fmt.bufPrint(&buf, "{s} Advantage: Guybrush {d}, {s} {d}.", .{
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

    const road_scene = try world.intern_entity("High Road");
    const sanctuary_scene = try world.intern_entity("Sword Master Sanctuary");
    const bar_scene = try world.intern_entity("Scumm Bar");

    const guybrush = try world.intern_entity("Guybrush");
    const pirate_bob = try world.intern_entity("PirateBob");
    const carla = try world.intern_entity("Carla");
    const barkeep = try world.intern_entity("Barkeep");

    try duel_decl.apply_tiers(&duel);
    const duel_state = DuelState{
        .opponent = try world.intern_relation("ActiveDuelOpponent", .property),
        .challenge = try world.intern_relation("ActiveDuelChallenge", .property),
    };

    const road_l = try spatial.graph.add_waypoint(road_scene, 0, 0, "RoadLeft");
    const road_c = try spatial.graph.add_waypoint(road_scene, 20, 0, "RoadCenter");
    const road_r = try spatial.graph.add_waypoint(road_scene, 40, 0, "RoadRight");

    const gate_wp = try spatial.graph.add_waypoint(sanctuary_scene, 0, 0, "SanctuaryGate");
    const arena_wp = try spatial.graph.add_waypoint(sanctuary_scene, 20, 0, "ArenaCenter");

    const bar_ent_wp = try spatial.graph.add_waypoint(bar_scene, 0, 0, "BarEntrance");
    const counter_wp = try spatial.graph.add_waypoint(bar_scene, 20, 0, "CounterMark");

    try spatial.graph.connect(road_l, road_c, null);
    try spatial.graph.connect(road_c, road_r, null);
    try spatial.graph.connect(gate_wp, arena_wp, null);
    try spatial.graph.connect(bar_ent_wp, counter_wp, null);

    try spatial.register_entity(guybrush, road_c, 10);
    try spatial.register_entity(pirate_bob, road_r, 11);
    try spatial.register_entity(carla, arena_wp, 12);
    try spatial.register_entity(barkeep, counter_wp, 13);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(road_scene);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - Monkey Island: Insult Sword Fighting", 1280, 720);
    defer window.deinit();
    window.set_theme(&sword_theme);

    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
    try stdout.print("Monkey Island Scenario Controls:\n", .{});
    try stdout.print("   - [1] - [5]:              Select Dialogue / Counter Reply\n", .{});
    try stdout.print("   - [D]:                    Duel Regular Pirate (Bob)\n", .{});
    try stdout.print("   - [C]:                    Challenge Sword Master Carla\n", .{});
    try stdout.print("   - [T]:                    Talk to Barkeep (Repetition Fatigue)\n", .{});
    try stdout.print("   - [W]:                    Wait 50 Simulation Ticks (Cool off mood)\n", .{});
    try stdout.print("   - [Timeline Scrubber]:    Click or drag timeline bar\n", .{});
    try stdout.print("   - [F1 / Tab]:             Toggle Debug Fact Overlay & REPL\n", .{});

    var display_bridge = bespoke.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    // The player whose inventory the tray shows.
    if (world.lookup_entity("Guybrush")) |player| display_bridge.set_active_character(player);
    display_bridge.attach_audio_bridge(window.audio_bridge);
    // The clock now runs at the shared tick interval (D-028) instead of once per display frame.
    var session = try bespoke.host.Session.init(allocator, &world, &spatial, &vm, &compiled, &display_bridge, &window);
    defer session.deinit();

    window.set_cue_banner("Mêlée Island: Draw cutlasses and test relational dialogue!", 180);

    var is_running = true;
    while (is_running) {
        const action = window.poll_events(session.frame());
        if (action == .quit) {
            is_running = false;
        } else if (!try session.handle_common(action)) {
            switch (action) {
                .dialogue_choice => |choice_idx| {
                    try resolve_choice(&session, &vm, &world, &duel, guybrush, duel_state, choice_idx, &window);
                },
                .custom => |id| if (std.meta.intToEnum(SwordKey, id)) |key| switch (key) {
                    .duel_bob => {
                        try vm.transition_to_scene(road_scene);
                        _ = try spatial.transition_actor(guybrush, road_scene, road_c);
                        try start_duel(&session, &vm, &world, &duel, guybrush, duel_state, pirate_bob, duel.challenge(0, 0));
                        window.set_cue_banner("Pirate Bob draws his cutlass. Choose a reply.", 120);
                    },
                    .duel_carla => {
                        try vm.transition_to_scene(sanctuary_scene);
                        _ = try spatial.transition_actor(guybrush, sanctuary_scene, arena_wp);
                        try start_duel(&session, &vm, &world, &duel, guybrush, duel_state, carla, duel.challenge(4, 1));
                        window.set_cue_banner("Carla, the Sword Master, raises her blade. Choose a reply.", 120);
                    },
                    .talk_barkeep => {
                        if (world.get_property(guybrush, duel_state.opponent) != null) {
                            window.set_cue_banner("Finish the duel first.", 90);
                        } else {
                            try vm.transition_to_scene(bar_scene);
                            _ = try spatial.transition_actor(guybrush, bar_scene, bar_ent_wp);
                            const mood = try fatigue.record(guybrush, barkeep);
                            const line = if (mood) |stage|
                                (if (stage == ANNOYED)
                                    "Look, I already told you. Her mansion is on the hill."
                                else
                                    "Are ye deaf, pirate? Buy a grog or get out of my tavern!")
                            else
                                "Governor Marley? Sharp as a cutlass and twice as quick.";
                            var buf: [192]u8 = undefined;
                            const msg = std.fmt.bufPrint(&buf, "Barkeep [{s}]: \"{s}\"", .{ fatigue.label(mood), line }) catch "Barkeep";
                            try session.record_now();
                            window.set_cue_banner(msg, 150);
                        }
                    },
                    .wait_50 => {
                        if (world.get_property(guybrush, duel_state.opponent) != null) {
                            window.set_cue_banner("Finish the duel first.", 90);
                        } else {
                            var waited: usize = 0;
                            while (waited < 50) : (waited += 1) _ = try session.advance();
                            var buf: [128]u8 = undefined;
                            const msg = std.fmt.bufPrint(&buf, "Waited 50 ticks. Barkeep mood: {s}.", .{fatigue.label(fatigue.mood(barkeep, guybrush))}) catch "Waited 50 ticks.";
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

test "P15-01: canonical Monkey Island insults and counters are correctly mapped" {
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

    // All 16 counters match their standard insult and its Sword Master variant
    for (duel.config.pairs, 0..) |_, i| {
        const variant = duel.challenge(i, 1);
        try testing.expect(duel.counters(duel.reply(i), duel.challenge(i, 0)));
        try testing.expectEqual(duel.challenge(i, 0), duel.base_of(variant));
        try testing.expect(duel.counters(duel.reply(i), variant));
    }
}

test "P15-02: Pete/Arantor Sword Master target invariant prevents master insults on regular pirates" {
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
    const guybrush = try world.intern_entity("Guybrush");
    const pirate_bob = try world.intern_entity("PirateBob");
    const carla = try world.intern_entity("Carla");

    // Guybrush learns standard insult 4 and Carla's variant of it
    try duel.hear(guybrush, duel.challenge(3, 0));
    try duel.hear(guybrush, duel.challenge(3, 1));

    // Querying against regular pirate Bob: only standard insult 4 is permitted
    var bob_candidates: [4]duel_mod.Candidate = undefined;
    const bob_count = duel.challenges(&vm, guybrush, pirate_bob, &bob_candidates);
    try testing.expectEqual(@as(usize, 1), bob_count);
    try testing.expectEqual(duel.challenge(3, 0), bob_candidates[0].entity);

    // Querying against Sword Master Carla: both are permitted
    var carla_candidates: [4]duel_mod.Candidate = undefined;
    const carla_count = duel.challenges(&vm, guybrush, carla, &carla_candidates);
    try testing.expectEqual(@as(usize, 2), carla_count);
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
    const guybrush = try world.intern_entity("Guybrush");
    const barkeep = try world.intern_entity("Barkeep");

    try testing.expectEqual(@as(?usize, null), try fatigue.record(guybrush, barkeep));
    try testing.expectEqual(@as(?usize, null), fatigue.mood(barkeep, guybrush));

    // Inquiry 2: Annoyed (100 ticks)
    try testing.expectEqual(@as(?usize, ANNOYED), try fatigue.record(guybrush, barkeep));
    try testing.expectEqual(@as(?usize, ANNOYED), fatigue.mood(barkeep, guybrush));

    // Inquiry 3: Furious (250 ticks)
    try testing.expectEqual(@as(?usize, FURIOUS), try fatigue.record(guybrush, barkeep));
    try testing.expectEqual(@as(?usize, FURIOUS), fatigue.mood(barkeep, guybrush));

    // Annoyance expires first, fury later
    var tick: usize = 0;
    while (tick < 100) : (tick += 1) _ = world.step_tick();
    try testing.expect(!world.has_fact(barkeep, fatigue.stage_rels[ANNOYED], guybrush.to_int()));
    try testing.expectEqual(@as(?usize, FURIOUS), fatigue.mood(barkeep, guybrush));
    while (tick < 250) : (tick += 1) _ = world.step_tick();
    try testing.expectEqual(@as(?usize, null), fatigue.mood(barkeep, guybrush));
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

    const guybrush = try world.intern_entity("Guybrush");
    const pirate_bob = try world.intern_entity("PirateBob");
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();

    const challenge = duel.challenge(0, 0);
    var candidates: [9]duel_mod.Candidate = undefined;
    try testing.expectEqual(@as(usize, 1), duel.replies(&vm, guybrush, challenge, &candidates));
    try testing.expectEqualStrings(duel.config.fallback.?, candidates[0].text);

    var choices: [1]bespoke.dialogue.Choice = .{.{ .text = candidates[0].text, .action = candidates[0].entity.to_int() }};
    _ = try vm.open_generated_dialogue(pirate_bob, world.get_entity_name(challenge).?, &choices);
    const open = vm.dialogue_view().?;
    try testing.expectEqualStrings(world.get_entity_name(challenge).?, open.prompt);
    try testing.expectEqualStrings(duel.config.fallback.?, open.text(0));

    const selection = (try vm.choose(0)).?;
    try testing.expectEqual(@as(u32, 0), selection.action);
    const lost = try duel.resolve_round(pirate_bob, guybrush, challenge, bespoke.EntityId.none);
    try testing.expect(!lost.parried);
    try testing.expectEqual(@as(u32, 1), duel.advantage(pirate_bob));

    try testing.expectEqual(@as(usize, 1), duel.replies(&vm, guybrush, challenge, &candidates));
    try testing.expect(candidates[0].counters);

    var round_index: usize = 0;
    while (round_index < 3) : (round_index += 1) {
        const round = try duel.resolve_round(pirate_bob, guybrush, challenge, candidates[0].entity);
        try testing.expect(round.parried);
        if (round_index < 2) {
            try testing.expect(round.winner == null);
        } else {
            try testing.expectEqual(guybrush, round.winner.?);
        }
    }
    try testing.expectEqual(@as(u32, 1), duel.wins(guybrush));
}

test "P15-04: headless simulation of Monkey Island Insult Sword Fighting passes cleanly" {
    const testing = std.testing;
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try run_headless(testing.allocator, buf.writer());
    try testing.expect(buf.items.len > 0);
}
