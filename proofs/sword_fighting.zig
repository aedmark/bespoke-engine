const std = @import("std");
const bespoke = @import("bespoke");

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

pub const InsultPair = struct {
    id: u8,
    standard_insult: []const u8,
    counter_reply: []const u8,
    carla_insult: []const u8,
};

/// The canonical 16 Monkey Island 1 Insults, Counter Replies, and Carla Sword Master Variants
pub const MONKEY_ISLAND_INSULTS = [_]InsultPair{
    .{
        .id = 1,
        .standard_insult = "You fight like a dairy farmer!",
        .counter_reply = "How appropriate. You fight like a cow!",
        .carla_insult = "I will milk every drop of blood from your body!",
    },
    .{
        .id = 2,
        .standard_insult = "This is the END for you, you gutter-crawling cur!",
        .counter_reply = "And I've got a little TIP for you, get the POINT?",
        .carla_insult = "I've got the courage and skill of a master!",
    },
    .{
        .id = 3,
        .standard_insult = "I've spoken with apes more polite than you!",
        .counter_reply = "I'm glad to hear you attended your family reunion.",
        .carla_insult = "Now I know what filth and stupidity really are.",
    },
    .{
        .id = 4,
        .standard_insult = "Soon you'll be wearing my sword like a shish kebab!",
        .counter_reply = "First you'd better stop waving it like a feather duster.",
        .carla_insult = "My sword is famous all across the Caribbean!",
    },
    .{
        .id = 5,
        .standard_insult = "People fall at my feet when they see me coming!",
        .counter_reply = "Even BEFORE they smell your breath?",
        .carla_insult = "My wisest enemies run away at the first sight of me!",
    },
    .{
        .id = 6,
        .standard_insult = "I'm not going to take your insolence sitting down!",
        .counter_reply = "Your hemorhoids are flaring up again eh?",
        .carla_insult = "I usually work with people who have more courage than you.",
    },
    .{
        .id = 7,
        .standard_insult = "I once owned a dog that was smarter than you.",
        .counter_reply = "He must have taught you everything you know.",
        .carla_insult = "Only once have I met such a coward!",
    },
    .{
        .id = 8,
        .standard_insult = "Nobody's ever drawn blood from me and nobody ever will.",
        .counter_reply = "You run THAT fast?",
        .carla_insult = "No one has ever faced ME and lived to tell about it!",
    },
    .{
        .id = 9,
        .standard_insult = "Have you stopped wearing diapers yet?",
        .counter_reply = "Why, did you want to borrow one?",
        .carla_insult = "I hope you have a boat ready for a quick escape.",
    },
    .{
        .id = 10,
        .standard_insult = "There are no words for how disgusting you are.",
        .counter_reply = "Yes there are, you just never learned them.",
        .carla_insult = "There are no clever moves that can help you now.",
    },
    .{
        .id = 11,
        .standard_insult = "You make me want to puke.",
        .counter_reply = "You make me think somebody already did.",
        .carla_insult = "If your brother's like you, better to marry a pig.",
    },
    .{
        .id = 12,
        .standard_insult = "My handkerchief will wipe up your blood!",
        .counter_reply = "So you got that job as a janitor, after all.",
        .carla_insult = "My name is feared in every dirty salon!",
    },
    .{
        .id = 13,
        .standard_insult = "I got this scar on my face during a mighty struggle!",
        .counter_reply = "I hope now you've learned to stop picking your nose.",
        .carla_insult = "My face is a portrait of ruthless brutality!",
    },
    .{
        .id = 14,
        .standard_insult = "I've heard you are a contemptible sneak.",
        .counter_reply = "Too bad no one's ever heard of YOU at all.",
        .carla_insult = "I will make sure no one remembers your name.",
    },
    .{
        .id = 15,
        .standard_insult = "You're no match for my brains, you poor fool.",
        .counter_reply = "I'd be in real trouble if you used them.",
        .carla_insult = "I've got a long, sharp lesson for you to learn today.",
    },
    .{
        .id = 16,
        .standard_insult = "You have the manners of a beggar.",
        .counter_reply = "I wanted to make sure you'd feel at home with me.",
        .carla_insult = "Every word you say to me is an insult.",
    },
};

pub const FALLBACK_REPLY = "I am shaking, I am shaking!";

pub const NpcMood = enum {
    welcoming,
    annoyed,
    furious,
};

pub const DialogueCandidate = struct {
    text: []const u8,
    id: u32,
    is_valid_counter: bool = false,
};

/// The Relational Sword Duel and Conversational System
pub const DialogueDuelSystem = struct {
    world: *bespoke.World,

    // Relation kinds
    heard_insult_rel: bespoke.RelationKind,
    mastered_reply_rel: bespoke.RelationKind,
    counters_rel: bespoke.RelationKind,
    sword_master_variant_rel: bespoke.RelationKind,
    is_sword_master_rel: bespoke.RelationKind,
    advantage_rel: bespoke.RelationKind,
    duels_won_rel: bespoke.RelationKind,
    swagger_rel: bespoke.RelationKind,
    inquired_rel: bespoke.RelationKind,
    annoyed_with_rel: bespoke.RelationKind,
    furious_with_rel: bespoke.RelationKind,
    path_chosen_rel: bespoke.RelationKind,

    pub fn init(world: *bespoke.World) !DialogueDuelSystem {
        const heard = try world.intern_relation("HeardInsult", .set);
        const mastered = try world.intern_relation("MasteredReply", .set);
        const counters = try world.intern_relation("Counters", .set);
        const sm_variant = try world.intern_relation("SwordMasterVariant", .set);
        const is_sm = try world.intern_relation("IsSwordMaster", .property);
        const adv = try world.intern_relation("Advantage", .property);
        const duels = try world.intern_relation("DuelsWon", .property);
        const swg = try world.intern_relation("Swagger", .property);
        const inq = try world.intern_relation("Inquired", .property);
        const ann = try world.intern_relation("AnnoyedWith", .set);
        const fur = try world.intern_relation("FuriousWith", .set);
        const path = try world.intern_relation("PathChosen", .property);

        var sys = DialogueDuelSystem{
            .world = world,
            .heard_insult_rel = heard,
            .mastered_reply_rel = mastered,
            .counters_rel = counters,
            .sword_master_variant_rel = sm_variant,
            .is_sword_master_rel = is_sm,
            .advantage_rel = adv,
            .duels_won_rel = duels,
            .swagger_rel = swg,
            .inquired_rel = inq,
            .annoyed_with_rel = ann,
            .furious_with_rel = fur,
            .path_chosen_rel = path,
        };

        try sys.populate_canonical_knowledge_base();
        return sys;
    }

    /// Populates ground truth knowledge base into the relational fact arena
    pub fn populate_canonical_knowledge_base(self: *DialogueDuelSystem) !void {
        for (MONKEY_ISLAND_INSULTS) |pair| {
            // Counters(reply_id, standard_insult_id)
            const reply_ent = bespoke.EntityId.from_int(pair.id);
            try self.world.remember(reply_ent, self.counters_rel, pair.id, 0);

            // Carla variants: SwordMasterVariant(100 + pair.id, pair.id)
            const carla_ent = bespoke.EntityId.from_int(100 + pair.id);
            try self.world.remember(carla_ent, self.sword_master_variant_rel, pair.id, 0);
        }
    }

    /// Resolves an insult ID (which may be a Carla Sword Master variant) to its standard counterpart
    pub fn resolve_standard_insult(self: *const DialogueDuelSystem, insult_id: u32) u32 {
        if (insult_id > 100) {
            const carla_ent = bespoke.EntityId.from_int(insult_id);
            var it = self.world.query(carla_ent, self.sword_master_variant_rel, null);
            if (it.next()) |fact| {
                return fact.object_or_value;
            }
        }
        return insult_id;
    }

    /// Checks if a reply counters a given insult
    pub fn does_reply_counter(self: *const DialogueDuelSystem, reply_id: u32, insult_id: u32) bool {
        const std_insult = self.resolve_standard_insult(insult_id);
        const reply_ent = bespoke.EntityId.from_int(reply_id);
        return self.world.has_fact(reply_ent, self.counters_rel, std_insult);
    }

    /// Queries which insults a fighter is epistemologically aware of and can speak.
    /// Crucial Pete/Arantor rule: if target is a regular pirate, Sword Master insults will not fly!
    pub fn query_available_insults(
        self: *const DialogueDuelSystem,
        fighter: bespoke.EntityId,
        target: bespoke.EntityId,
        out_candidates: []DialogueCandidate,
    ) usize {
        const target_is_master = self.world.has_fact(target, self.is_sword_master_rel, 1);
        var count: usize = 0;

        var it = self.world.query(fighter, self.heard_insult_rel, null);
        while (it.next()) |fact| {
            const insult_id = fact.object_or_value;
            const is_master_variant = insult_id > 100;

            // Pete invariant: using a Sword Master insult on a regular pirate will not fly!
            if (is_master_variant and !target_is_master) {
                continue;
            }

            if (count < out_candidates.len) {
                var text: []const u8 = "Unknown insult";
                for (MONKEY_ISLAND_INSULTS) |pair| {
                    if (is_master_variant and (100 + pair.id == insult_id)) {
                        text = pair.carla_insult;
                        break;
                    } else if (pair.id == insult_id) {
                        text = pair.standard_insult;
                        break;
                    }
                }
                out_candidates[count] = .{
                    .text = text,
                    .id = insult_id,
                    .is_valid_counter = false,
                };
                count += 1;
            }
        }

        return count;
    }

    /// Queries which replies Guybrush has mastered in response to an opponent's insult.
    /// If no replies have been mastered, presents the iconic fallback line.
    pub fn query_available_replies(
        self: *const DialogueDuelSystem,
        fighter: bespoke.EntityId,
        active_insult_id: u32,
        out_candidates: []DialogueCandidate,
    ) usize {
        const std_insult = self.resolve_standard_insult(active_insult_id);
        var count: usize = 0;

        var it = self.world.query(fighter, self.mastered_reply_rel, null);
        while (it.next()) |fact| {
            const reply_id = fact.object_or_value;
            const is_counter = self.world.has_fact(bespoke.EntityId.from_int(reply_id), self.counters_rel, std_insult);

            if (count < out_candidates.len) {
                var text: []const u8 = "Unknown reply";
                for (MONKEY_ISLAND_INSULTS) |pair| {
                    if (pair.id == reply_id) {
                        text = pair.counter_reply;
                        break;
                    }
                }
                out_candidates[count] = .{
                    .text = text,
                    .id = reply_id,
                    .is_valid_counter = is_counter,
                };
                count += 1;
            }
        }

        // If no mastered replies exist, offer the shaking fallback
        if (count == 0 and out_candidates.len > 0) {
            out_candidates[0] = .{
                .text = FALLBACK_REPLY,
                .id = 0,
                .is_valid_counter = false,
            };
            return 1;
        }

        return count;
    }

    /// Resolves an insult duel round between attacker and defender.
    /// Teaches heard insults and mastered counters through relational unification.
    pub fn resolve_round(
        self: *DialogueDuelSystem,
        attacker: bespoke.EntityId,
        defender: bespoke.EntityId,
        insult_id: u32,
        reply_id: u32,
    ) !bool {
        // Defender hears the insult if not already known
        try self.world.remember(defender, self.heard_insult_rel, insult_id, 0);

        const is_parry = if (reply_id == 0) false else self.does_reply_counter(reply_id, insult_id);

        const std_insult = self.resolve_standard_insult(insult_id);
        const cur_adv_def = self.world.get_property(defender, self.advantage_rel) orelse 0;
        const cur_adv_atk = self.world.get_property(attacker, self.advantage_rel) orelse 0;

        if (is_parry) {
            // Defender successfully parried
            try self.world.remember(defender, self.advantage_rel, cur_adv_def + 1, 0);
            if (cur_adv_atk > 0) {
                try self.world.remember(attacker, self.advantage_rel, cur_adv_atk - 1, 0);
            }
            return true;
        } else {
            // Attacker struck defender.
            // Attacker taunts with counter reply, so defender learns it!
            try self.world.remember(defender, self.mastered_reply_rel, std_insult, 0);
            try self.world.remember(attacker, self.advantage_rel, cur_adv_atk + 1, 0);
            if (cur_adv_def > 0) {
                try self.world.remember(defender, self.advantage_rel, cur_adv_def - 1, 0);
            }
            return false;
        }
    }

    /// Checks the conversational irritation state of an NPC toward a speaker
    pub fn get_npc_mood(
        self: *const DialogueDuelSystem,
        npc: bespoke.EntityId,
        speaker: bespoke.EntityId,
    ) NpcMood {
        if (self.world.has_fact(npc, self.furious_with_rel, speaker.to_int())) {
            return .furious;
        }
        if (self.world.has_fact(npc, self.annoyed_with_rel, speaker.to_int())) {
            return .annoyed;
        }
        return .welcoming;
    }

    /// Records an inquiry and updates conversational repetition fatigue with TTL mood decay
    pub fn record_inquiry(
        self: *DialogueDuelSystem,
        speaker: bespoke.EntityId,
        npc: bespoke.EntityId,
        topic_id: u32,
        annoyance_ttl: u32,
        fury_ttl: u32,
    ) !NpcMood {
        _ = topic_id;
        const cur_count = self.world.get_property(speaker, self.inquired_rel) orelse 0;
        const new_count = cur_count + 1;
        _ = self.world.forget(speaker, self.inquired_rel, null);
        try self.world.remember(speaker, self.inquired_rel, new_count, 0);

        if (new_count == 1) {
            return .welcoming;
        } else if (new_count == 2) {
            try self.world.remember(npc, self.annoyed_with_rel, speaker.to_int(), annoyance_ttl);
            return .annoyed;
        } else {
            try self.world.remember(npc, self.furious_with_rel, speaker.to_int(), fury_ttl);
            return .furious;
        }
    }
};

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

    var duel_sys = try DialogueDuelSystem.init(&world);

    // Intern key actors
    const guybrush = try world.intern_entity("Guybrush");
    const pirate_bob = try world.intern_entity("PirateBob");
    const pirate_pegleg = try world.intern_entity("PiratePegleg");
    const carla = try world.intern_entity("Carla");
    const barkeep = try world.intern_entity("Barkeep");
    const citizen = try world.intern_entity("Citizen");
    _ = citizen;

    // Carla is the legendary Sword Master
    try world.remember(carla, duel_sys.is_sword_master_rel, 1, 0);

    var history_snapshots = std.ArrayList(std.ArrayList(u8)).init(allocator);
    defer {
        for (history_snapshots.items) |*buf| buf.deinit();
        history_snapshots.deinit();
    }

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    // Snapshot 0: Baseline state
    var snap0 = std.ArrayList(u8).init(allocator);
    try world.save_state(snap0.writer());
    try history_snapshots.append(snap0);

    // -------------------------------------------------------------------------
    // Step 1: Epistemological Zero Baseline & Learning First Insult and Reply
    // -------------------------------------------------------------------------
    try writer.print("[Step 1: Epistemological Zero Baseline]\n", .{});
    try writer.print("   -> Guybrush enters Mêlée Island with 0 known insults and 0 mastered replies.\n", .{});

    var candidate_replies: [8]DialogueCandidate = undefined;
    var reply_count = duel_sys.query_available_replies(guybrush, 1, &candidate_replies);

    try writer.print("   -> Pirate Bob approaches on the High Road and draws cutlass!\n", .{});
    try writer.print("   -> Bob throws Insult 1: \"{s}\"\n", .{MONKEY_ISLAND_INSULTS[0].standard_insult});
    try writer.print("   -> Active Choices Available to Guybrush ({d}):\n", .{reply_count});
    for (candidate_replies[0..reply_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\"\n", .{ i + 1, cand.text });
    }
    try std.testing.expectEqual(@as(usize, 1), reply_count);
    try std.testing.expectEqualStrings(FALLBACK_REPLY, candidate_replies[0].text);

    // Guybrush uses fallback reply
    try writer.print("   -> Guybrush stammers: \"{s}\"\n", .{FALLBACK_REPLY});
    const parried_step1 = try duel_sys.resolve_round(pirate_bob, guybrush, 1, 0);
    try std.testing.expect(!parried_step1);

    try writer.print("   -> Bob strikes! Taunts: \"{s}\"\n", .{MONKEY_ISLAND_INSULTS[0].counter_reply});
    try writer.print("   -> Relational Learning Triggered:\n", .{});
    try writer.print("      - Remembered HeardInsult(Guybrush, 1): \"{s}\"\n", .{MONKEY_ISLAND_INSULTS[0].standard_insult});
    try writer.print("      - Remembered MasteredReply(Guybrush, 1): \"{s}\"\n\n", .{MONKEY_ISLAND_INSULTS[0].counter_reply});

    try std.testing.expect(world.has_fact(guybrush, duel_sys.heard_insult_rel, 1));
    try std.testing.expect(world.has_fact(guybrush, duel_sys.mastered_reply_rel, 1));

    // -------------------------------------------------------------------------
    // Step 2: Initiative & Throwing Heard Insults
    // -------------------------------------------------------------------------
    try writer.print("[Step 2: Offensive Initiative with Learned Insults]\n", .{});
    var candidate_insults: [8]DialogueCandidate = undefined;
    const insult_count = duel_sys.query_available_insults(guybrush, pirate_pegleg, &candidate_insults);

    try writer.print("   -> Guybrush confronts Pirate Pegleg!\n", .{});
    try writer.print("   -> Available Offensive Insults for Guybrush ({d}):\n", .{insult_count});
    for (candidate_insults[0..insult_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\"\n", .{ i + 1, cand.text });
    }
    try std.testing.expectEqual(@as(usize, 1), insult_count);
    try std.testing.expectEqualStrings(MONKEY_ISLAND_INSULTS[0].standard_insult, candidate_insults[0].text);

    try writer.print("   -> Guybrush throws Insult 1: \"{s}\"\n", .{MONKEY_ISLAND_INSULTS[0].standard_insult});
    try writer.print("   -> Pegleg fails to counter and retorts with Insult 5: \"{s}\"\n", .{MONKEY_ISLAND_INSULTS[4].standard_insult});

    // Defender hears Insult 5 and learns Reply 5 through combat
    try world.remember(guybrush, duel_sys.heard_insult_rel, 5, 0);
    try world.remember(guybrush, duel_sys.mastered_reply_rel, 5, 0);
    try writer.print("   -> Guybrush commits Insult 5 and Reply 5 to memory!\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 3: Dynamic Relational Counter-Strike & Advantage Progression
    // -------------------------------------------------------------------------
    try writer.print("[Step 3: Relational Query Pruning & Duel Victory]\n", .{});
    try writer.print("   -> Pirate Bob challenges Guybrush again!\n", .{});
    try writer.print("   -> Bob throws Insult 1: \"{s}\"\n", .{MONKEY_ISLAND_INSULTS[0].standard_insult});

    reply_count = duel_sys.query_available_replies(guybrush, 1, &candidate_replies);
    try writer.print("   -> Guybrush's Mastered Dialogue Options ({d}):\n", .{reply_count});
    var correct_choice_idx: ?usize = null;
    for (candidate_replies[0..reply_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\" (Counters Insult? {s})\n", .{
            i + 1,
            cand.text,
            if (cand.is_valid_counter) "YES!" else "no",
        });
        if (cand.is_valid_counter) correct_choice_idx = i;
    }
    try std.testing.expect(reply_count >= 2);
    try std.testing.expect(correct_choice_idx != null);

    const chosen = candidate_replies[correct_choice_idx.?];
    try writer.print("   -> Guybrush parries with Choice {d}: \"{s}\"\n", .{ correct_choice_idx.? + 1, chosen.text });
    const parried_step3 = try duel_sys.resolve_round(pirate_bob, guybrush, 1, chosen.id);
    try std.testing.expect(parried_step3);

    // Score advantage to 3 to win duel
    try world.remember(guybrush, duel_sys.advantage_rel, 3, 0);
    try world.remember(guybrush, duel_sys.duels_won_rel, 1, 0);
    try world.remember(guybrush, duel_sys.swagger_rel, 2, 0);

    try writer.print("   -> Clang! Bob's cutlass flies from his hand! Guybrush wins the duel!\n", .{});
    try writer.print("   -> Facts asserted: Advantage(Guybrush, 3), DuelsWon(Guybrush, 1), Swagger(Guybrush, 2)\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 4: Carla the Sword Master & The Pete/Arantor Target Invariant
    // -------------------------------------------------------------------------
    try writer.print("[Step 4: Carla the Sword Master & Target Invariant Verification]\n", .{});
    try writer.print("   -> Guybrush crosses the rope bridge to Carla's Sword Master Sanctuary.\n", .{});

    // Carla throws elevated master insult 105 (Variant of Insult 5)
    const carla_insult_id: u32 = 105;
    const carla_insult_text = MONKEY_ISLAND_INSULTS[4].carla_insult;
    try writer.print("   -> Carla sneers: \"{s}\"\n", .{carla_insult_text});

    reply_count = duel_sys.query_available_replies(guybrush, carla_insult_id, &candidate_replies);
    try writer.print("   -> Relational Query maps Carla variant (105) to Standard Insult 5:\n", .{});
    for (candidate_replies[0..reply_count], 0..) |cand, i| {
        try writer.print("      [{d}] \"{s}\" (Counters Carla? {s})\n", .{
            i + 1,
            cand.text,
            if (cand.is_valid_counter) "YES!" else "no",
        });
    }
    try std.testing.expect(duel_sys.does_reply_counter(5, carla_insult_id));

    // Guybrush parries Carla's elevated master insult
    const parried_carla = try duel_sys.resolve_round(carla, guybrush, carla_insult_id, 5);
    try std.testing.expect(parried_carla);
    try writer.print("   -> Guybrush parries Carla: \"{s}\"\n", .{MONKEY_ISLAND_INSULTS[4].counter_reply});
    try writer.print("   -> Carla is stunned: \"A sharp tongue as well as a sharp blade!\"\n", .{});

    // Test Pete Invariant: Guybrush hears Carla's insult 105.
    // If Guybrush tries to use Carla's Sword Master insult on regular pirate Bob, it will not fly!
    try world.remember(guybrush, duel_sys.heard_insult_rel, carla_insult_id, 0);

    var bob_insults: [8]DialogueCandidate = undefined;
    const bob_insult_count = duel_sys.query_available_insults(guybrush, pirate_bob, &bob_insults);

    try writer.print("\n   [Pete/Arantor Invariant Check]\n", .{});
    try writer.print("   -> Guybrush tries to use Sword Master insult against regular Pirate Bob:\n", .{});
    var saw_carla_insult = false;
    for (bob_insults[0..bob_insult_count]) |cand| {
        if (cand.id == carla_insult_id) saw_carla_insult = true;
    }
    try std.testing.expect(!saw_carla_insult);
    try writer.print("   -> Engine Pruning Verified: Sword Master insult filtered from regular pirate targets!\n", .{});
    try writer.print("   -> (As Pete noted: \"if you try to use a Sword Master insult on a regular pirate it won't fly\")\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 5: Organic Conversational Repetition Fatigue
    // -------------------------------------------------------------------------
    try writer.print("[Step 5: Organic Conversational Repetition Fatigue with the Barkeep]\n", .{});
    const topic_marley: u32 = 77;

    // Inquiry 1: Welcoming
    const mood1 = try duel_sys.record_inquiry(guybrush, barkeep, topic_marley, 100, 250);
    try writer.print("   -> [Inquiry 1] Guybrush: \"Tell me about Governor Marley.\"\n", .{});
    try writer.print("      Barkeep Mood: {s}\n", .{@tagName(mood1)});
    try writer.print("      Barkeep: \"Governor Marley? Sharp as a cutlass and twice as quick.\"\n", .{});
    try std.testing.expectEqual(NpcMood.welcoming, mood1);
    try std.testing.expect(!world.has_fact(barkeep, duel_sys.annoyed_with_rel, null));

    // Inquiry 2: Terse / Annoyed (TTL 100 ticks)
    const mood2 = try duel_sys.record_inquiry(guybrush, barkeep, topic_marley, 100, 250);
    try writer.print("   -> [Inquiry 2] Guybrush: \"Tell me more about Governor Marley.\"\n", .{});
    try writer.print("      Barkeep Mood: {s} (AnnoyedWith asserted for 100 ticks)\n", .{@tagName(mood2)});
    try writer.print("      Barkeep: \"Look, I already told you. Her mansion is on the hill.\"\n", .{});
    try std.testing.expectEqual(NpcMood.annoyed, mood2);
    try std.testing.expect(world.has_fact(barkeep, duel_sys.annoyed_with_rel, guybrush.to_int()));

    // Inquiry 3: Furious / Slamming door (TTL 250 ticks)
    const mood3 = try duel_sys.record_inquiry(guybrush, barkeep, topic_marley, 100, 250);
    try writer.print("   -> [Inquiry 3] Guybrush: \"About Governor Marley...\"\n", .{});
    try writer.print("      Barkeep Mood: {s} (FuriousWith asserted for 250 ticks)\n", .{@tagName(mood3)});
    try writer.print("      Barkeep: \"Are ye deaf, pirate? Buy a grog or get out of my tavern!\"\n", .{});
    try std.testing.expectEqual(NpcMood.furious, mood3);
    try std.testing.expect(world.has_fact(barkeep, duel_sys.furious_with_rel, guybrush.to_int()));

    // Inquiry 4 while furious: NPC refuses to talk
    const mood4 = duel_sys.get_npc_mood(barkeep, guybrush);
    try writer.print("   -> [Inquiry 4 while Furious] Barkeep slams mug on counter and turns his back!\n", .{});
    try std.testing.expectEqual(NpcMood.furious, mood4);

    // Save snapshot before temporal cool-off
    var snap_furious = std.ArrayList(u8).init(allocator);
    try world.save_state(snap_furious.writer());
    try history_snapshots.append(snap_furious);

    // -------------------------------------------------------------------------
    // Step 6: Temporal Mood Decay via Tick Expiration
    // -------------------------------------------------------------------------
    try writer.print("\n[Step 6: Temporal Mood Decay via Master Simulation Ticks]\n", .{});
    try writer.print("   -> Simulating 260 ticks on BeSpoke spine...\n", .{});
    var tick_i: usize = 0;
    while (tick_i < 260) : (tick_i += 1) {
        try vm.step_tick();
    }

    try writer.print("   -> Current Tick: {d}\n", .{world.current_tick});
    const mood_after_wait = duel_sys.get_npc_mood(barkeep, guybrush);
    try writer.print("   -> Barkeep Mood after 260 ticks: {s}\n", .{@tagName(mood_after_wait)});
    try std.testing.expectEqual(NpcMood.welcoming, mood_after_wait);
    try std.testing.expect(!world.has_fact(barkeep, duel_sys.furious_with_rel, guybrush.to_int()));
    try std.testing.expect(!world.has_fact(barkeep, duel_sys.annoyed_with_rel, guybrush.to_int()));
    try writer.print("   -> AnnoyedWith and FuriousWith TTL expired cleanly from SoA arena!\n", .{});
    try writer.print("   -> Barkeep: \"Welcome back, lad! Thirsty for grog?\"\n\n", .{});

    // -------------------------------------------------------------------------
    // Step 7: Tangled World State Dialogue & Time-Travel Rewind
    // -------------------------------------------------------------------------
    try writer.print("[Step 7: Tangled World State Dialogue & Time-Travel Rewind]\n", .{});

    // Indiana Jones FOA 3 paths: 1 = Wits, 2 = Fists, 3 = Teamwork
    try world.remember(guybrush, duel_sys.path_chosen_rel, 1, 0); // Wits path
    try writer.print("   -> PathChosen(Guybrush, Wits) active.\n", .{});
    try writer.print("   -> Talking to Citizen of Mêlée...\n", .{});

    const is_wits = (world.get_property(guybrush, duel_sys.path_chosen_rel) orelse 0) == 1;
    const swagger_lvl = world.get_property(guybrush, duel_sys.swagger_rel) orelse 0;

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
    var rewind_stream = std.io.fixedBufferStream(history_snapshots.items[0].items);
    try world.restore_state(rewind_stream.reader());

    try writer.print("   -> Restored Snapshot 0 (Tick {d}).\n", .{world.current_tick});
    try writer.print("   -> Guybrush HeardInsults Count: {s}\n", .{
        if (!world.has_fact(guybrush, duel_sys.heard_insult_rel, null)) "0 (Clean)" else "Leaked!",
    });
    try writer.print("   -> Guybrush MasteredReplies Count: {s}\n", .{
        if (!world.has_fact(guybrush, duel_sys.mastered_reply_rel, null)) "0 (Clean)" else "Leaked!",
    });
    try std.testing.expect(!world.has_fact(guybrush, duel_sys.heard_insult_rel, null));
    try std.testing.expect(!world.has_fact(guybrush, duel_sys.mastered_reply_rel, null));

    try writer.print("\n>>> ALL MONKEY ISLAND INSULT SWORD FIGHTING & REPETITION TESTS PASSED! <<<\n", .{});
}

/// Executes interactive 60 Hz playability with graphical display or falls back to headless simulation
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SWORD_FIGHTING_SCRIPT);
    defer compiled.deinit();

    const duel_sys = try DialogueDuelSystem.init(&world);

    const road_scene = try world.intern_entity("High Road");
    const sanctuary_scene = try world.intern_entity("Sword Master Sanctuary");
    const bar_scene = try world.intern_entity("Scumm Bar");

    const guybrush = try world.intern_entity("Guybrush");
    const pirate_bob = try world.intern_entity("PirateBob");
    const carla = try world.intern_entity("Carla");
    const barkeep = try world.intern_entity("Barkeep");

    try world.remember(carla, duel_sys.is_sword_master_rel, 1, 0);

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
    display_bridge.attach_audio_bridge(window.audio_bridge);
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.swap();

    window.set_cue_banner("Mêlée Island: Draw cutlasses and test relational dialogue!", 180);

    var is_running = true;
    var is_paused = false;
    while (is_running) {
        const action = window.poll_events(display_bridge.get_frame());
        _ = window.handle_save_action(action, &world, &spatial, &vm, &display_bridge, &is_paused);
        switch (action) {
            .quit => is_running = false,
            .toggle_pause => is_paused = !is_paused,
            else => {},
        }

        if (!is_paused) {
            try vm.step_tick();
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        window.render_frame(display_bridge.get_frame(), is_paused);
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

    const duel_sys = try DialogueDuelSystem.init(&world);

    // Verify all 16 counters match their standard insult
    for (MONKEY_ISLAND_INSULTS) |pair| {
        try testing.expect(duel_sys.does_reply_counter(pair.id, pair.id));
        // Verify Carla variant resolves to standard insult
        try testing.expectEqual(@as(u32, pair.id), duel_sys.resolve_standard_insult(100 + pair.id));
        try testing.expect(duel_sys.does_reply_counter(pair.id, 100 + pair.id));
    }
}

test "P15-02: Pete/Arantor Sword Master target invariant prevents master insults on regular pirates" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const duel_sys = try DialogueDuelSystem.init(&world);
    const guybrush = try world.intern_entity("Guybrush");
    const pirate_bob = try world.intern_entity("PirateBob");
    const carla = try world.intern_entity("Carla");
    try world.remember(carla, duel_sys.is_sword_master_rel, 1, 0);

    // Guybrush learns Carla's insult 104 and standard insult 4
    try world.remember(guybrush, duel_sys.heard_insult_rel, 4, 0);
    try world.remember(guybrush, duel_sys.heard_insult_rel, 104, 0);

    // Querying against regular pirate Bob: only standard insult 4 is permitted
    var bob_candidates: [4]DialogueCandidate = undefined;
    const bob_count = duel_sys.query_available_insults(guybrush, pirate_bob, &bob_candidates);
    try testing.expectEqual(@as(usize, 1), bob_count);
    try testing.expectEqual(@as(u32, 4), bob_candidates[0].id);

    // Querying against Sword Master Carla: both are permitted
    var carla_candidates: [4]DialogueCandidate = undefined;
    const carla_count = duel_sys.query_available_insults(guybrush, carla, &carla_candidates);
    try testing.expectEqual(@as(usize, 2), carla_count);
}

test "P15-03: conversational repetition fatigue asserts decaying mood facts" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var duel_sys = try DialogueDuelSystem.init(&world);
    const guybrush = try world.intern_entity("Guybrush");
    const barkeep = try world.intern_entity("Barkeep");
    const topic_grog: u32 = 42;

    // Inquiry 1: Welcoming
    const m1 = try duel_sys.record_inquiry(guybrush, barkeep, topic_grog, 10, 20);
    try testing.expectEqual(NpcMood.welcoming, m1);
    try testing.expectEqual(NpcMood.welcoming, duel_sys.get_npc_mood(barkeep, guybrush));

    // Inquiry 2: Annoyed (TTL 10 ticks)
    const m2 = try duel_sys.record_inquiry(guybrush, barkeep, topic_grog, 10, 20);
    try testing.expectEqual(NpcMood.annoyed, m2);
    try testing.expectEqual(NpcMood.annoyed, duel_sys.get_npc_mood(barkeep, guybrush));

    // Inquiry 3: Furious (TTL 20 ticks)
    const m3 = try duel_sys.record_inquiry(guybrush, barkeep, topic_grog, 10, 20);
    try testing.expectEqual(NpcMood.furious, m3);
    try testing.expectEqual(NpcMood.furious, duel_sys.get_npc_mood(barkeep, guybrush));

    // Step world 25 ticks: Annoyed and Furious expire
    _ = world.step_tick();
    world.current_tick += 25;
    _ = world.step_tick();

    try testing.expectEqual(NpcMood.welcoming, duel_sys.get_npc_mood(barkeep, guybrush));
}

test "P15-04: headless simulation of Monkey Island Insult Sword Fighting passes cleanly" {
    const testing = std.testing;
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try run_headless(testing.allocator, buf.writer());
    try testing.expect(buf.items.len > 0);
}
