//! Dialogue duel and inquiry fatigue (P32-17, D-017, D-035).
//!
//! Two data-driven conversational mechanics over World facts:
//!
//!   1. `Duel`: a challenge/response contest. The host supplies a table of pairs (a challenge
//!      line, the one reply that counters it, and optional tier variants of the challenge).
//!      Fighters learn challenges by hearing them and replies by losing to them. Opponents carry
//!      a tier; a tier variant of a challenge is only usable against an opponent of that tier.
//!      A countered challenge moves advantage to the defender, a failed reply to the attacker.
//!   2. `InquiryFatigue`: an NPC's patience with one speaker. Each inquiry raises a count kept
//!      per (speaker, NPC); configured stages assert mood facts with a TTL, so moods decay with
//!      the tick clock.
//!
//! The duel offers its lines as fact-guarded dialogue choices: every challenge and reply is a
//! `DialogueChoice` whose `where` patterns name the knowledge facts, filtered by
//! `VM.prune_dialogue_choices` (D-015). Challenges and replies are interned entities, so the
//! same facts are reachable from script choices.
//!
//! All state lives in World facts, never in these structs, so a world snapshot captures a duel
//! in progress and rewind restores it exactly. The structs hold only the borrowed configuration
//! and interned ids. Call `init` before the first snapshot a host may restore: the knowledge
//! base (`Counters`, `VariantOf`) is asserted there as permanent facts.
//!
//! The module names no character, line, or setting.
const std = @import("std");
const world_mod = @import("world.zig");
const vm_mod = @import("vm.zig");
const bytecode_mod = @import("bytecode.zig");
const parser_mod = @import("compiler/parser.zig");

const World = world_mod.World;
const EntityId = world_mod.EntityId;
const RelationKind = world_mod.RelationKind;
const VM = vm_mod.VM;

/// Fixed capacities. Ids are copied into fixed arrays so the duel owns no heap memory.
pub const MAX_PAIRS: usize = 64;
/// The base tier plus up to three variant tiers.
pub const MAX_TIERS: usize = 4;
pub const MAX_STAGES: usize = 8;
/// Fallback lines one duel may rotate through; the package stores the count in a byte.
pub const MAX_FALLBACKS: usize = parser_mod.DUEL_MAX_FALLBACKS;

const MAX_CHOICES: usize = MAX_PAIRS * MAX_TIERS;
const NAME_BUF_LEN: usize = 160;

/// Tier values as pattern text: fact patterns carry their arguments as strings (D-015).
const TIER_TEXT = [MAX_TIERS][]const u8{ "0", "1", "2", "3" };

pub const Error = error{ InvalidDuelConfig, InvalidFatigueConfig, NameTooLong };

/// One challenge and the reply that counters it.
pub const Pair = struct {
    /// Stem for the interned entity names: `<name>Challenge`, `<name>Reply`, and
    /// `<name>ChallengeT<tier>` for each variant.
    name: []const u8,
    challenge: []const u8,
    reply: []const u8,
    /// `variants[i]` is the challenge as an opponent of tier `i + 1` phrases it. The same reply
    /// counters every variant.
    variants: []const []const u8 = &.{},
};

/// Relation names the duel interns. Override them to theme the fact vocabulary.
pub const Relations = struct {
    heard: []const u8 = "HeardChallenge",
    mastered: []const u8 = "MasteredReply",
    counters: []const u8 = "Counters",
    variant_of: []const u8 = "VariantOf",
    tier: []const u8 = "DuelTier",
    advantage: []const u8 = "Advantage",
    wins: []const u8 = "DuelsWon",
    /// Property counting the fallback lines a fighter has spoken; picks the next one (D-076).
    fumbles: []const u8 = "DuelFumbles",
};

/// Slices are borrowed: pair names and texts must outlive the `Duel`.
pub const Config = struct {
    pairs: []const Pair,
    /// Lines offered, one at a time, as the only reply when a fighter has mastered none. The
    /// fighter's fumble count picks the line, so the rotation is a fact: it saves, rewinds, and
    /// replays like any other state (D-076).
    fallbacks: []const []const u8 = &.{},
    /// A fighter whose advantage reaches this wins the duel: their win count rises and both
    /// advantages reset. Null leaves winning to the host.
    win_at: ?u32 = null,
    relations: Relations = .{},
};

pub const Candidate = struct {
    text: []const u8,
    /// The challenge or reply entity; `.none` for the fallback reply.
    entity: EntityId,
    /// Replies only: this reply counters the active challenge.
    counters: bool = false,
};

pub const Round = struct {
    parried: bool,
    /// Set when `Config.win_at` was reached this round.
    winner: ?EntityId = null,
};

pub const Duel = struct {
    world: *World,
    config: Config,
    pair_count: usize,
    challenge_ids: [MAX_PAIRS][MAX_TIERS]EntityId,
    reply_ids: [MAX_PAIRS]EntityId,

    heard_rel: RelationKind,
    mastered_rel: RelationKind,
    counters_rel: RelationKind,
    variant_of_rel: RelationKind,
    tier_rel: RelationKind,
    advantage_rel: RelationKind,
    wins_rel: RelationKind,
    fumbles_rel: RelationKind,

    pub fn init(world: *World, config: Config) !Duel {
        if (config.pairs.len == 0 or config.pairs.len > MAX_PAIRS) return Error.InvalidDuelConfig;
        if (config.win_at) |w| {
            if (w == 0) return Error.InvalidDuelConfig;
        }
        if (config.fallbacks.len > MAX_FALLBACKS) return Error.InvalidDuelConfig;
        for (config.pairs) |pair| {
            if (pair.name.len == 0 or pair.variants.len > MAX_TIERS - 1) return Error.InvalidDuelConfig;
        }

        const r = config.relations;
        var self = Duel{
            .world = world,
            .config = config,
            .pair_count = config.pairs.len,
            .challenge_ids = undefined,
            .reply_ids = undefined,
            .heard_rel = try world.intern_relation(r.heard, .set),
            .mastered_rel = try world.intern_relation(r.mastered, .set),
            .counters_rel = try world.intern_relation(r.counters, .set),
            .variant_of_rel = try world.intern_relation(r.variant_of, .set),
            .tier_rel = try world.intern_relation(r.tier, .property),
            .advantage_rel = try world.intern_relation(r.advantage, .property),
            .wins_rel = try world.intern_relation(r.wins, .property),
            .fumbles_rel = try world.intern_relation(r.fumbles, .property),
        };
        for (&self.challenge_ids) |*row| @memset(row, EntityId.none);
        @memset(&self.reply_ids, EntityId.none);

        var buf: [NAME_BUF_LEN]u8 = undefined;
        for (config.pairs, 0..) |pair, p| {
            const base = try world.intern_entity(try format_name(&buf, "{s}Challenge", .{pair.name}));
            const reply_ent = try world.intern_entity(try format_name(&buf, "{s}Reply", .{pair.name}));
            self.challenge_ids[p][0] = base;
            self.reply_ids[p] = reply_ent;
            try world.remember(reply_ent, self.counters_rel, base.to_int(), 0);

            for (pair.variants, 1..) |_, tier| {
                const variant = try world.intern_entity(
                    try format_name(&buf, "{s}ChallengeT{d}", .{ pair.name, tier }),
                );
                self.challenge_ids[p][tier] = variant;
                try world.remember(variant, self.variant_of_rel, base.to_int(), 0);
            }
        }
        return self;
    }

    /// The challenge entity of pair `pair_index` at `tier` (0 is the base challenge), or
    /// `.none` if the pair has no such variant.
    pub fn challenge(self: *const Duel, pair_index: usize, tier: usize) EntityId {
        if (pair_index >= self.pair_count or tier >= MAX_TIERS) return .none;
        return self.challenge_ids[pair_index][tier];
    }

    pub fn reply(self: *const Duel, pair_index: usize) EntityId {
        if (pair_index >= self.pair_count) return .none;
        return self.reply_ids[pair_index];
    }

    /// Resolves a tier variant to its base challenge; a base challenge resolves to itself.
    pub fn base_of(self: *const Duel, challenge_ent: EntityId) EntityId {
        if (self.world.find_first(challenge_ent, self.variant_of_rel, null)) |fact| {
            return EntityId.from_int(fact.object_or_value);
        }
        return challenge_ent;
    }

    pub fn counters(self: *const Duel, reply_ent: EntityId, challenge_ent: EntityId) bool {
        if (reply_ent == .none) return false;
        return self.world.has_fact(reply_ent, self.counters_rel, self.base_of(challenge_ent).to_int());
    }

    pub fn set_tier(self: *Duel, opponent: EntityId, tier: u32) !void {
        if (tier >= MAX_TIERS) return Error.InvalidDuelConfig;
        try self.world.remember(opponent, self.tier_rel, tier, 0);
    }

    pub fn hear(self: *Duel, fighter: EntityId, challenge_ent: EntityId) !void {
        try self.world.remember(fighter, self.heard_rel, challenge_ent.to_int(), 0);
    }

    pub fn master(self: *Duel, fighter: EntityId, reply_ent: EntityId) !void {
        try self.world.remember(fighter, self.mastered_rel, reply_ent.to_int(), 0);
    }

    pub fn advantage(self: *const Duel, fighter: EntityId) u32 {
        return self.world.get_property(fighter, self.advantage_rel) orelse 0;
    }

    pub fn wins(self: *const Duel, fighter: EntityId) u32 {
        return self.world.get_property(fighter, self.wins_rel) orelse 0;
    }

    /// How many fallback lines `fighter` has spoken.
    pub fn fumbles(self: *const Duel, fighter: EntityId) u32 {
        return self.world.get_property(fighter, self.fumbles_rel) orelse 0;
    }

    /// Lists the challenges `fighter` may throw at `target`, in table order (base, then
    /// variants). A fighter may throw only what they have heard, and a tier variant only at an
    /// opponent of exactly that tier. Returns the number written to `out`.
    pub fn challenges(
        self: *const Duel,
        vm: *VM,
        fighter: EntityId,
        target: EntityId,
        out: []Candidate,
    ) usize {
        const fighter_name = self.world.get_entity_name(fighter) orelse return 0;
        const target_name = self.world.get_entity_name(target) orelse return 0;

        // Pattern storage lives on this frame; `prune_dialogue_choices` only reads it.
        var args: [MAX_CHOICES][2][2][]const u8 = undefined;
        var patterns: [MAX_CHOICES][2]parser_mod.FactPattern = undefined;
        var choices: [MAX_CHOICES]parser_mod.DialogueChoice = undefined;
        var ids: [MAX_CHOICES]EntityId = undefined;
        var n: usize = 0;

        for (self.config.pairs, 0..) |pair, p| {
            var tier: usize = 0;
            while (tier <= pair.variants.len) : (tier += 1) {
                const ent = self.challenge_ids[p][tier];
                const ent_name = self.world.get_entity_name(ent) orelse continue;
                args[n][0] = .{ fighter_name, ent_name };
                patterns[n][0] = .{ .relation = self.config.relations.heard, .args = &args[n][0] };
                var pattern_count: usize = 1;
                if (tier > 0) {
                    args[n][1] = .{ target_name, TIER_TEXT[tier] };
                    patterns[n][1] = .{ .relation = self.config.relations.tier, .args = &args[n][1] };
                    pattern_count = 2;
                }
                choices[n] = .{
                    .text = if (tier == 0) pair.challenge else pair.variants[tier - 1],
                    .where_patterns = patterns[n][0..pattern_count],
                    .body = &.{},
                };
                ids[n] = ent;
                n += 1;
            }
        }

        var pruned: [MAX_CHOICES]vm_mod.PrunedChoice = undefined;
        const kept = vm.prune_dialogue_choices(choices[0..n], &pruned);
        const count = @min(kept, out.len);
        for (pruned[0..count], 0..) |choice, i| {
            out[i] = .{ .text = choice.text, .entity = ids[choice.original_index] };
        }
        return count;
    }

    /// Lists the replies `fighter` has mastered, in table order, marking the one that counters
    /// `active_challenge`. With none mastered, offers one fallback line, chosen by the fighter's
    /// fumble count so successive rounds rotate through the list.
    pub fn replies(
        self: *const Duel,
        vm: *VM,
        fighter: EntityId,
        active_challenge: EntityId,
        out: []Candidate,
    ) usize {
        const fighter_name = self.world.get_entity_name(fighter) orelse return 0;

        var args: [MAX_PAIRS][2][]const u8 = undefined;
        var patterns: [MAX_PAIRS][1]parser_mod.FactPattern = undefined;
        var choices: [MAX_PAIRS]parser_mod.DialogueChoice = undefined;
        var n: usize = 0;
        // Indexes `choices` back to the pair table; pairs with no entity name are skipped.
        var pair_of: [MAX_PAIRS]usize = undefined;

        for (self.config.pairs, 0..) |pair, p| {
            const ent_name = self.world.get_entity_name(self.reply_ids[p]) orelse continue;
            args[n] = .{ fighter_name, ent_name };
            patterns[n][0] = .{ .relation = self.config.relations.mastered, .args = &args[n] };
            choices[n] = .{ .text = pair.reply, .where_patterns = &patterns[n], .body = &.{} };
            pair_of[n] = p;
            n += 1;
        }

        var pruned: [MAX_PAIRS]vm_mod.PrunedChoice = undefined;
        const kept = vm.prune_dialogue_choices(choices[0..n], &pruned);
        const count = @min(kept, out.len);
        for (pruned[0..count], 0..) |choice, i| {
            const reply_ent = self.reply_ids[pair_of[choice.original_index]];
            out[i] = .{
                .text = choice.text,
                .entity = reply_ent,
                .counters = self.counters(reply_ent, active_challenge),
            };
        }

        if (kept == 0 and out.len > 0) {
            const lines = self.config.fallbacks;
            if (lines.len > 0) {
                out[0] = .{ .text = lines[self.fumbles(fighter) % lines.len], .entity = .none };
                return 1;
            }
        }
        return count;
    }

    /// Resolves one round: `attacker` throws `challenge_ent`, `defender` answers with
    /// `reply_ent` (`.none` for the fallback). The defender always learns the challenge. A
    /// reply that counters moves one point of advantage to the defender; otherwise the
    /// attacker gains it and the defender learns the correct reply from the attacker's taunt.
    pub fn resolve_round(
        self: *Duel,
        attacker: EntityId,
        defender: EntityId,
        challenge_ent: EntityId,
        reply_ent: EntityId,
    ) !Round {
        try self.hear(defender, challenge_ent);
        // A fallback reply advances the defender's rotation to the next line.
        if (reply_ent == .none) try self.world.remember(defender, self.fumbles_rel, self.fumbles(defender) + 1, 0);

        const parried = self.counters(reply_ent, challenge_ent);
        const gainer = if (parried) defender else attacker;
        const loser = if (parried) attacker else defender;

        if (!parried) {
            if (self.reply_for(self.base_of(challenge_ent))) |correct| {
                try self.master(defender, correct);
            }
        }

        const gained = self.advantage(gainer) + 1;
        try self.world.remember(gainer, self.advantage_rel, gained, 0);
        const lost = self.advantage(loser);
        if (lost > 0) try self.world.remember(loser, self.advantage_rel, lost - 1, 0);

        var round = Round{ .parried = parried };
        if (self.config.win_at) |win_at| {
            if (gained >= win_at) {
                try self.world.remember(gainer, self.wins_rel, self.wins(gainer) + 1, 0);
                try self.world.remember(gainer, self.advantage_rel, 0, 0);
                try self.world.remember(loser, self.advantage_rel, 0, 0);
                round.winner = gainer;
            }
        }
        return round;
    }

    fn reply_for(self: *const Duel, base_challenge: EntityId) ?EntityId {
        for (0..self.pair_count) |p| {
            if (self.challenge_ids[p][0] == base_challenge) return self.reply_ids[p];
        }
        return null;
    }
};

/// One step of an NPC's patience. Reached when the inquiry count is at least `at`; asserts
/// `relation(npc, speaker)` for `ttl` ticks (0 is permanent).
pub const Stage = struct {
    relation: []const u8,
    at: u32,
    ttl: u64,
    label: []const u8 = "",
};

/// Slices are borrowed: relation names and labels must outlive the `InquiryFatigue`.
pub const FatigueConfig = struct {
    /// Ordered by rising `at`; a later stage outranks an earlier one.
    stages: []const Stage,
    /// Property relation holding the count, on a per-(speaker, NPC) entity.
    count_relation: []const u8 = "Inquiries",
    /// Label for an NPC with no active stage.
    calm_label: []const u8 = "calm",
};

/// An opponent tier assigned by a script-declared duel.
pub const TierAssignment = struct {
    opponent: EntityId,
    tier: u32,
};

/// Complete immutable program data for one declared duel, including its fatigue ladder.
/// The compiler owns the arrays; strings point into the World's intern table.
pub const Declaration = struct {
    config: Config,
    fatigue: FatigueConfig,
    tiers: []const TierAssignment = &.{},

    pub fn apply_tiers(self: *const Declaration, duel: *Duel) !void {
        for (self.tiers) |assignment| try duel.set_tier(assignment.opponent, assignment.tier);
    }

    pub fn deinit_owned(self: *Declaration, allocator: std.mem.Allocator) void {
        for (self.config.pairs) |pair| allocator.free(pair.variants);
        allocator.free(self.config.pairs);
        allocator.free(self.config.fallbacks);
        allocator.free(self.fatigue.stages);
        allocator.free(self.tiers);
        self.* = undefined;
    }
};

pub const InquiryFatigue = struct {
    world: *World,
    config: FatigueConfig,
    stage_count: usize,
    stage_rels: [MAX_STAGES]RelationKind,
    count_rel: RelationKind,

    pub fn init(world: *World, config: FatigueConfig) !InquiryFatigue {
        if (config.stages.len == 0 or config.stages.len > MAX_STAGES) return Error.InvalidFatigueConfig;
        var self = InquiryFatigue{
            .world = world,
            .config = config,
            .stage_count = config.stages.len,
            .stage_rels = undefined,
            .count_rel = try world.intern_relation(config.count_relation, .property),
        };
        var previous_at: u32 = 0;
        for (config.stages, 0..) |stage, i| {
            if (stage.at <= previous_at or stage.relation.len == 0) return Error.InvalidFatigueConfig;
            previous_at = stage.at;
            self.stage_rels[i] = try world.intern_relation(stage.relation, .set);
        }
        return self;
    }

    /// Counts one inquiry by `speaker` to `npc` and asserts the stage that count reaches.
    /// Returns the stage index, or null while the NPC is still calm.
    pub fn record(self: *InquiryFatigue, speaker: EntityId, npc: EntityId) !?usize {
        var buf: [NAME_BUF_LEN]u8 = undefined;
        // The count is keyed by an entity interned per (speaker, NPC): a property fact has one
        // subject, and a count on the speaker alone would make every NPC tire together.
        const key = try self.world.intern_entity(try self.key_name(&buf, speaker, npc));
        const n = (self.world.get_property(key, self.count_rel) orelse 0) + 1;
        try self.world.remember(key, self.count_rel, n, 0);

        var reached: ?usize = null;
        for (self.config.stages, 0..) |stage, i| {
            if (n >= stage.at) reached = i;
        }
        if (reached) |i| {
            try self.world.remember(npc, self.stage_rels[i], speaker.to_int(), self.config.stages[i].ttl);
        }
        return reached;
    }

    /// The highest stage `npc` currently holds toward `speaker`, or null when calm.
    pub fn mood(self: *const InquiryFatigue, npc: EntityId, speaker: EntityId) ?usize {
        var i = self.stage_count;
        while (i > 0) {
            i -= 1;
            if (self.world.has_fact(npc, self.stage_rels[i], speaker.to_int())) return i;
        }
        return null;
    }

    pub fn count(self: *const InquiryFatigue, speaker: EntityId, npc: EntityId) u32 {
        var buf: [NAME_BUF_LEN]u8 = undefined;
        const name = self.key_name(&buf, speaker, npc) catch return 0;
        const key = self.world.lookup_entity(name) orelse return 0;
        return self.world.get_property(key, self.count_rel) orelse 0;
    }

    pub fn label(self: *const InquiryFatigue, stage: ?usize) []const u8 {
        const i = stage orelse return self.config.calm_label;
        return if (i < self.stage_count) self.config.stages[i].label else self.config.calm_label;
    }

    fn key_name(self: *const InquiryFatigue, buf: []u8, speaker: EntityId, npc: EntityId) ![]const u8 {
        const speaker_name = self.world.get_entity_name(speaker) orelse return Error.InvalidFatigueConfig;
        const npc_name = self.world.get_entity_name(npc) orelse return Error.InvalidFatigueConfig;
        return format_name(buf, "{s}->{s}", .{ speaker_name, npc_name });
    }
};

fn format_name(buf: []u8, comptime fmt: []const u8, args: anytype) ![]const u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch Error.NameTooLong;
}

// -----------------------------------------------------------------------------
// Unit tests: a riddle contest, a second theme unrelated to any proof (P32-17).
// -----------------------------------------------------------------------------

const RIDDLES = [_]Pair{
    .{
        .name = "Echo",
        .challenge = "I speak without a mouth. What am I?",
        .reply = "An echo.",
        .variants = &.{ "Voiceless I answer; name me.", "What returns every word and keeps none?" },
    },
    .{
        .name = "River",
        .challenge = "I run but never walk. What am I?",
        .reply = "A river.",
        .variants = &.{"Bedded yet sleepless, mouthed yet silent; name me."},
    },
    .{
        .name = "Shadow",
        .challenge = "I follow you all day and vanish at night. What am I?",
        .reply = "A shadow.",
    },
};

const RIDDLE_CONFIG = Config{
    .pairs = &RIDDLES,
    .fallbacks = &.{ "I do not know.", "Ask me another." },
    .win_at = 2,
    .relations = .{ .heard = "HeardRiddle", .mastered = "KnowsAnswer", .tier = "Rank", .wins = "ContestsWon" },
};

const TestBed = struct {
    world: World,
    chunk: bytecode_mod.BytecodeChunk,

    fn init() !TestBed {
        return .{
            .world = try World.init(std.testing.allocator, 1024 * 1024),
            .chunk = bytecode_mod.BytecodeChunk.init(std.testing.allocator),
        };
    }

    fn deinit(self: *TestBed) void {
        self.chunk.deinit();
        self.world.deinit();
    }
};

test "P32-17: every reply counters its challenge and each tier variant" {
    const testing = std.testing;
    var bed = try TestBed.init();
    defer bed.deinit();
    const duel = try Duel.init(&bed.world, RIDDLE_CONFIG);

    for (RIDDLES, 0..) |pair, p| {
        try testing.expect(duel.counters(duel.reply(p), duel.challenge(p, 0)));
        for (pair.variants, 1..) |_, tier| {
            try testing.expectEqual(duel.challenge(p, 0), duel.base_of(duel.challenge(p, tier)));
            try testing.expect(duel.counters(duel.reply(p), duel.challenge(p, tier)));
        }
        // A reply counters only its own pair.
        const other = (p + 1) % RIDDLES.len;
        try testing.expect(!duel.counters(duel.reply(p), duel.challenge(other, 0)));
    }
    try testing.expectEqual(EntityId.none, duel.challenge(2, 1));
}

test "P32-17: a tier variant is offered only against an opponent of that tier" {
    const testing = std.testing;
    var bed = try TestBed.init();
    defer bed.deinit();
    var vm = VM.init(testing.allocator, &bed.world, &bed.chunk);
    defer vm.deinit();
    var duel = try Duel.init(&bed.world, RIDDLE_CONFIG);

    const pupil = try bed.world.intern_entity("Pupil");
    const novice = try bed.world.intern_entity("Novice");
    const elder = try bed.world.intern_entity("Elder");
    const oracle = try bed.world.intern_entity("Oracle");
    try duel.set_tier(elder, 1);
    try duel.set_tier(oracle, 2);

    var out: [8]Candidate = undefined;
    try testing.expectEqual(@as(usize, 0), duel.challenges(&vm, pupil, novice, &out));

    try duel.hear(pupil, duel.challenge(0, 0));
    try duel.hear(pupil, duel.challenge(0, 1));
    try duel.hear(pupil, duel.challenge(0, 2));

    try testing.expectEqual(@as(usize, 1), duel.challenges(&vm, pupil, novice, &out));
    try testing.expectEqual(duel.challenge(0, 0), out[0].entity);

    try testing.expectEqual(@as(usize, 2), duel.challenges(&vm, pupil, elder, &out));
    try testing.expectEqual(duel.challenge(0, 1), out[1].entity);
    try testing.expectEqualStrings(RIDDLES[0].variants[0], out[1].text);

    try testing.expectEqual(@as(usize, 2), duel.challenges(&vm, pupil, oracle, &out));
    try testing.expectEqual(duel.challenge(0, 2), out[1].entity);

    // Output is truncated to the caller's buffer.
    try testing.expectEqual(@as(usize, 1), duel.challenges(&vm, pupil, oracle, out[0..1]));
}

test "P32-17: failed replies teach, counters shift advantage, and the threshold wins" {
    const testing = std.testing;
    var bed = try TestBed.init();
    defer bed.deinit();
    var vm = VM.init(testing.allocator, &bed.world, &bed.chunk);
    defer vm.deinit();
    var duel = try Duel.init(&bed.world, RIDDLE_CONFIG);

    const pupil = try bed.world.intern_entity("Pupil");
    const elder = try bed.world.intern_entity("Elder");
    try duel.set_tier(elder, 1);

    var out: [8]Candidate = undefined;
    try testing.expectEqual(@as(usize, 1), duel.replies(&vm, pupil, duel.challenge(1, 0), &out));
    try testing.expectEqualStrings("I do not know.", out[0].text);
    try testing.expectEqual(EntityId.none, out[0].entity);

    // The fallback fails: the pupil hears the riddle, learns its answer, and the elder leads.
    const lost = try duel.resolve_round(elder, pupil, duel.challenge(1, 1), out[0].entity);
    try testing.expect(!lost.parried);
    try testing.expect(lost.winner == null);
    try testing.expect(bed.world.has_fact(pupil, duel.heard_rel, duel.challenge(1, 1).to_int()));
    try testing.expect(bed.world.has_fact(pupil, duel.mastered_rel, duel.reply(1).to_int()));
    try testing.expectEqual(@as(u32, 1), duel.advantage(elder));

    try duel.master(pupil, duel.reply(2));
    try testing.expectEqual(@as(usize, 2), duel.replies(&vm, pupil, duel.challenge(1, 1), &out));
    try testing.expectEqual(duel.reply(1), out[0].entity);
    try testing.expect(out[0].counters);
    try testing.expect(!out[1].counters);

    // A wrong but mastered reply still fails.
    const wrong = try duel.resolve_round(elder, pupil, duel.challenge(1, 1), duel.reply(2));
    try testing.expect(!wrong.parried);
    try testing.expectEqual(elder, wrong.winner.?);
    try testing.expectEqual(@as(u32, 1), duel.wins(elder));
    try testing.expectEqual(@as(u32, 0), duel.advantage(elder));

    // Two counters in a row take the next contest, and the loser's lead drains first.
    _ = try duel.resolve_round(elder, pupil, duel.challenge(2, 0), .none);
    try testing.expectEqual(@as(u32, 1), duel.advantage(elder));
    const first = try duel.resolve_round(elder, pupil, duel.challenge(1, 1), duel.reply(1));
    try testing.expect(first.parried);
    try testing.expectEqual(@as(u32, 0), duel.advantage(elder));
    try testing.expectEqual(@as(u32, 1), duel.advantage(pupil));
    const second = try duel.resolve_round(elder, pupil, duel.challenge(2, 0), duel.reply(2));
    try testing.expectEqual(pupil, second.winner.?);
    try testing.expectEqual(@as(u32, 1), duel.wins(pupil));
}

test "D-076: fallback lines rotate per fighter, one per fumbled round" {
    const testing = std.testing;
    var bed = try TestBed.init();
    defer bed.deinit();
    var vm = VM.init(testing.allocator, &bed.world, &bed.chunk);
    defer vm.deinit();
    var duel = try Duel.init(&bed.world, RIDDLE_CONFIG);

    const pupil = try bed.world.intern_entity("Pupil");
    const novice = try bed.world.intern_entity("Novice");
    const elder = try bed.world.intern_entity("Elder");

    var out: [4]Candidate = undefined;
    const expected = [_][]const u8{ "I do not know.", "Ask me another.", "I do not know." };
    for (expected) |line| {
        try testing.expectEqual(@as(usize, 1), duel.replies(&vm, pupil, duel.challenge(0, 0), &out));
        try testing.expectEqualStrings(line, out[0].text);
        // The novice has fumbled nothing, so its rotation has not moved.
        try testing.expectEqual(@as(usize, 1), duel.replies(&vm, novice, duel.challenge(0, 0), &out));
        try testing.expectEqualStrings(expected[0], out[0].text);
        // A fumble teaches nothing new here: the pupil forgets the answer each round so the
        // fallback stays the only reply.
        _ = try duel.resolve_round(elder, pupil, duel.challenge(0, 0), .none);
        _ = bed.world.forget(pupil, duel.mastered_rel, null);
    }
    try testing.expectEqual(@as(u32, 3), duel.fumbles(pupil));
    try testing.expectEqual(@as(u32, 0), duel.fumbles(novice));

    // A countered round does not advance the rotation.
    try duel.master(pupil, duel.reply(0));
    _ = try duel.resolve_round(elder, pupil, duel.challenge(0, 0), duel.reply(0));
    try testing.expectEqual(@as(u32, 3), duel.fumbles(pupil));

    var too_many: [MAX_FALLBACKS + 1][]const u8 = undefined;
    @memset(&too_many, "Er...");
    var config = RIDDLE_CONFIG;
    config.fallbacks = &too_many;
    try testing.expectError(Error.InvalidDuelConfig, Duel.init(&bed.world, config));
}

test "P32-17: duel state is facts, so a snapshot restore rewinds it" {
    const testing = std.testing;
    var bed = try TestBed.init();
    defer bed.deinit();
    var duel = try Duel.init(&bed.world, RIDDLE_CONFIG);

    const pupil = try bed.world.intern_entity("Pupil");
    const elder = try bed.world.intern_entity("Elder");

    var snapshot = std.ArrayList(u8).init(testing.allocator);
    defer snapshot.deinit();
    try bed.world.save_state(snapshot.writer());

    _ = try duel.resolve_round(elder, pupil, duel.challenge(0, 0), .none);
    try testing.expect(bed.world.has_fact(pupil, duel.mastered_rel, null));

    var stream = std.io.fixedBufferStream(snapshot.items);
    try bed.world.restore_state(stream.reader());

    try testing.expect(!bed.world.has_fact(pupil, duel.heard_rel, null));
    try testing.expect(!bed.world.has_fact(pupil, duel.mastered_rel, null));
    try testing.expectEqual(@as(u32, 0), duel.advantage(elder));
    // The knowledge base was asserted before the snapshot and survives it.
    try testing.expect(duel.counters(duel.reply(0), duel.challenge(0, 0)));
}

test "P32-17: invalid duel and fatigue configs are rejected" {
    const testing = std.testing;
    var bed = try TestBed.init();
    defer bed.deinit();

    try testing.expectError(Error.InvalidDuelConfig, Duel.init(&bed.world, .{ .pairs = &.{} }));
    try testing.expectError(Error.InvalidDuelConfig, Duel.init(&bed.world, .{ .pairs = &RIDDLES, .win_at = 0 }));
    const too_many_tiers = [_]Pair{.{ .name = "X", .challenge = "c", .reply = "r", .variants = &.{ "1", "2", "3", "4" } }};
    try testing.expectError(Error.InvalidDuelConfig, Duel.init(&bed.world, .{ .pairs = &too_many_tiers }));

    try testing.expectError(Error.InvalidFatigueConfig, InquiryFatigue.init(&bed.world, .{ .stages = &.{} }));
    const unordered = [_]Stage{
        .{ .relation = "Curt", .at = 3, .ttl = 5 },
        .{ .relation = "Cold", .at = 3, .ttl = 5 },
    };
    try testing.expectError(Error.InvalidFatigueConfig, InquiryFatigue.init(&bed.world, .{ .stages = &unordered }));
}

test "P32-17: inquiry fatigue is counted per speaker and NPC, and moods decay" {
    const testing = std.testing;
    var bed = try TestBed.init();
    defer bed.deinit();

    const stages = [_]Stage{
        .{ .relation = "WaryOf", .at = 2, .ttl = 5, .label = "wary" },
        .{ .relation = "CurtWith", .at = 4, .ttl = 10, .label = "curt" },
        .{ .relation = "ShunsForGood", .at = 5, .ttl = 0, .label = "shunning" },
    };
    var fatigue = try InquiryFatigue.init(&bed.world, .{ .stages = &stages, .calm_label = "open" });

    const pupil = try bed.world.intern_entity("Pupil");
    const rival = try bed.world.intern_entity("Rival");
    const archivist = try bed.world.intern_entity("Archivist");
    const ferryman = try bed.world.intern_entity("Ferryman");

    try testing.expectEqual(@as(?usize, null), try fatigue.record(pupil, archivist));
    try testing.expectEqual(@as(?usize, 0), try fatigue.record(pupil, archivist));
    try testing.expectEqualStrings("wary", fatigue.label(fatigue.mood(archivist, pupil)));

    // Another NPC and another speaker each start from their own count.
    try testing.expectEqual(@as(?usize, null), try fatigue.record(pupil, ferryman));
    try testing.expectEqual(@as(?usize, null), try fatigue.record(rival, archivist));
    try testing.expectEqual(@as(?usize, null), fatigue.mood(ferryman, pupil));
    try testing.expectEqual(@as(?usize, null), fatigue.mood(archivist, rival));
    try testing.expectEqual(@as(u32, 2), fatigue.count(pupil, archivist));
    try testing.expectEqual(@as(u32, 1), fatigue.count(rival, archivist));
    try testing.expectEqual(@as(u32, 0), fatigue.count(rival, ferryman));

    try testing.expectEqual(@as(?usize, 0), try fatigue.record(pupil, archivist));
    try testing.expectEqual(@as(?usize, 1), try fatigue.record(pupil, archivist));
    try testing.expectEqual(@as(?usize, 1), fatigue.mood(archivist, pupil));

    // Both timed moods expire with the clock.
    var tick: usize = 0;
    while (tick < 11) : (tick += 1) _ = bed.world.step_tick();
    try testing.expectEqualStrings("open", fatigue.label(fatigue.mood(archivist, pupil)));

    // The count does not decay, so the next inquiry reaches the permanent stage.
    try testing.expectEqual(@as(?usize, 2), try fatigue.record(pupil, archivist));
    tick = 0;
    while (tick < 50) : (tick += 1) _ = bed.world.step_tick();
    try testing.expectEqual(@as(?usize, 2), fatigue.mood(archivist, pupil));
}
