const std = @import("std");
const lexer_mod = @import("lexer.zig");
pub const Lexer = lexer_mod.Lexer;
pub const Token = lexer_mod.Token;
pub const TokenTag = lexer_mod.TokenTag;
const draft_mod = @import("../draft.zig");
const grid_mod = @import("../grid.zig");
const agency_mod = @import("../agency.zig");
const decision_mod = @import("../decision.zig");
const dilemma_mod = @import("../dilemma.zig");
const hint_mod = @import("../hint.zig");
const value_mod = @import("../value.zig");
const limits_mod = @import("../limits.zig");
const spell_mod = @import("../spell.zig");
const command_mod = @import("../command.zig");
const phrase_mod = @import("../phrase.zig");
const mml = @import("../mml.zig");
const image_mod = @import("../image.zig");
const png_mod = @import("../png.zig");
const art_import = @import("../art_import.zig");

/// Reads a file a script names, such as `image X from "lamp.png"` (P46-04, D-156). Only the
/// command line supplies one; the browser and `check_source` compile with none, so a script
/// that names a file there gets a diagnostic rather than a silent gap.
pub const FileSource = struct {
    context: *anyopaque,
    read: *const fn (context: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8,
};
const diagnostic_mod = @import("diagnostic.zig");
const Suggestions = diagnostic_mod.Suggestions;
pub const Note = draft_mod.Note;
pub const Notes = draft_mod.Notes;

pub const FactPattern = struct {
    relation: []const u8,
    args: []const []const u8, // e.g. ["Holder", "Item"] or ["victim", "_"]
};

pub const Expr = union(enum) {
    roll_gte: struct { count: u8, sides: u8, threshold: u32 },
    not_fact: FactPattern,
    has_fact: FactPattern,
    /// `2 of Clue(_)`: at least `threshold` facts match the pattern (P44-02).
    count_at_least: struct { pattern: FactPattern, threshold: u32 },
    /// `6 points of Clue(_)`: the matched facts' third slots total at least `threshold`.
    points_at_least: struct { pattern: FactPattern, threshold: u32 },
};

pub const Stmt = union(enum) {
    remember: struct {
        relation: []const u8,
        args: []const []const u8,
        ttl_ticks: u32,
    },
    forget: struct {
        relation: []const u8,
        args: []const []const u8,
    },
    walk: struct {
        entity: []const u8,
        target: []const u8,
    },
    face: struct {
        entity: []const u8,
        target: []const u8,
    },
    wait_ticks: u32,
    wait_until: Expr,
    loop_stmt: []const Stmt,
    if_stmt: struct {
        cond: Expr,
        body: []const Stmt,
    },
    interrupt_with: struct {
        entity: []const u8,
        body: []const Stmt,
    },
    say: struct {
        speaker: []const u8,
        text: []const u8,
    },
    animate: struct {
        target: []const u8,
        clip: []const u8,
        is_stop: bool = false,
    },
    transition_scene: struct {
        target_scene: []const u8,
    },
    choice_block: []const DialogueChoice,
    resume_stmt: void,
    /// `weave <Draft> on <Target>`: caster is the executing fiber's owner (P22-01, D-029).
    weave: struct {
        draft: []const u8,
        target: []const u8,
    },
    /// `play score <Name>`, or `stop score` when null (P28-03, D-062).
    play_score: ?[]const u8,
};

/// `draft <Name>(n1, n2, n3, n4) [reverse <Inverse>]` (P22-01, D-029).
pub const DraftDecl = struct {
    name: []const u8,
    notes: Notes,
    reverse_name: ?[]const u8 = null,
};

/// Source position of a `weave` statement, kept so undeclared drafts report where they were used.
const WeaveRef = struct {
    draft: []const u8,
    line: u32,
    column: u32,
};

pub const DialogueChoice = struct {
    text: []const u8,
    guard: ?Expr = null,
    where_patterns: []const FactPattern = &[_]FactPattern{},
    body: []const Stmt,
};

pub const Routine = struct {
    name: []const u8,
    entity: []const u8,
    body: []const Stmt,
    /// Where the name begins, so a semantic error can point at the declaration.
    line: u32 = 0,
    column: u32 = 0,
};

pub const CueHandler = struct {
    cue_name: []const u8,
    params: []const []const u8,
    where_patterns: []const FactPattern,
    body: []const Stmt,
};

pub const WhenEdge = enum {
    rising, // when Condition: (or when currently Condition:)
    falling, // when Condition stops being State:
    on_expire, // when Entity forgets Relation:
    on_arrive, // when Actor arrives at Mark:
};

/// Relation naming the single trigger pattern of an arrival rule: `ArrivesAt(Actor, Mark)`.
/// It is never asserted as a fact; codegen resolves the mark to a waypoint id (P32-18, D-036).
pub const ARRIVES_RELATION = "ArrivesAt";

pub const WhenRule = struct {
    edge: WhenEdge = .rising,
    trigger_patterns: []const FactPattern,
    body: []const Stmt,
};

pub const RelationDecl = struct {
    name: []const u8,
    is_property: bool,
};

pub const SceneDef = struct {
    name: []const u8,
    cast: std.array_list.Managed([]const u8),
    props: std.array_list.Managed([]const u8),
    marks: std.array_list.Managed([]const u8),
    /// `backdrop: <Image>` (P46-03): the image's name as written, resolved after parsing.
    backdrop: ?Token = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) SceneDef {
        return .{
            .name = name,
            .cast = std.array_list.Managed([]const u8).init(allocator),
            .props = std.array_list.Managed([]const u8).init(allocator),
            .marks = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *SceneDef) void {
        self.cast.deinit();
        self.props.deinit();
        self.marks.deinit();
    }
};

pub const SocietyNeedDecl = struct {
    name: []const u8,
    worse: []const u8,
    max: u32,
    rate: u32,
    resting_rate: u32,
    seek: u32,
    satisfy: union(enum) {
        trade: struct {
            provider: ?[]const u8,
            price: u32,
            relief: u32,
            floor: u32,
            critical: ?u32,
            theft_relief: u32,
            theft_floor: u32,
            item: []const u8,
        },
        stay: struct {
            at: []const u8,
            restore: u32,
            until: u32,
            activity: []const u8,
            unaware: bool,
            state: []const u8,
            verb: []const u8,
        },
    },
};

pub const SocietyMemberNeedDecl = struct {
    name: []const u8,
    value: u32,
    rate: ?u32,
    provider: ?[]const u8,
};

pub const SocietyWorkDecl = struct { at: []const u8, every: u64, earn: u32, restock: bool };
pub const SocietyMerchantDecl = struct { post: []const u8, goods: []const u8 };

pub const SocietyMemberDecl = struct {
    name: []const u8,
    gold: u32,
    idle: []const u8,
    needs: []const SocietyMemberNeedDecl,
    routine_activity: ?[]const u8,
    stops: []const []const u8,
    period: u64,
    work: ?SocietyWorkDecl,
    merchant: ?SocietyMerchantDecl,
    broadcaster: bool,
    owns: []const []const u8,
    carries: []const []const u8,
};

pub const SocietyDecl = struct {
    name: []const u8,
    needs: []const SocietyNeedDecl,
    members: []const SocietyMemberDecl,
    enforcer: ?[]const u8,
    holding: ?[]const u8,
    gathering: []const u8,
    flight_to: []const u8,
    flight_then: ?[]const u8,
    flight_every: u64,
    friends: []const [2][]const u8,
    radii: [4]i32 = .{ 14, 12, 15, 14 },
    grudge_ticks: [2]u64 = .{ 60, 50 },
    warrant_priority: u16 = 10,
    currency_unit: []const u8 = "g",
    relations: [14][]const u8 = .{
        "Gold",    "Activity",   "Tending",    "Friend",    "Rival",      "Grudge",     "Owns",
        "Carries", "StolenFrom", "CrimeScene", "Witnessed", "KnowsRumor", "WarrantFor", "Arrested",
    },
};

pub const DuelPairDecl = struct {
    name: []const u8,
    challenge: []const u8,
    reply: []const u8,
    variants: []const []const u8,
};

pub const FatigueStageDecl = struct {
    relation: []const u8,
    at: u32,
    ttl: u64,
    label: []const u8,
};

pub const DuelTierDecl = struct { opponent: []const u8, tier: u32 };

/// Fallback lines one duel may declare; `duel.MAX_FALLBACKS` is defined from this so the
/// parser and the runtime agree without the parser importing the duel module.
pub const DUEL_MAX_FALLBACKS: usize = 8;

pub const DuelDecl = struct {
    name: []const u8,
    pairs: []const DuelPairDecl,
    /// Each `fallback` line appends one; the duel rotates through them (D-076).
    fallbacks: []const []const u8,
    win_at: ?u32,
    relations: [7][]const u8 = .{ "HeardChallenge", "MasteredReply", "Counters", "VariantOf", "DuelTier", "Advantage", "DuelsWon" },
    tiers: []const DuelTierDecl,
    fatigue_count_relation: []const u8,
    fatigue_calm_label: []const u8,
    fatigue_stages: []const FatigueStageDecl,
};

pub const DegradationStageDecl = struct {
    name: []const u8,
    duration_ticks: u64,
};

pub const DegradationVesselDecl = struct {
    name: []const u8,
    capacity: u32,
    initial_volume: u32,
    initial_stage: []const u8,
};

/// `degradation` owns the complete script authority for one container profile.
pub const DegradationDecl = struct {
    name: []const u8,
    substance: []const u8,
    stages: []const DegradationStageDecl,
    vessels: []const DegradationVesselDecl,
    spill_per_moving_tick: u32 = 0,
    relations: [5][]const u8 = .{ "Contains", "Volume", "ContainerStage", "ContainerExposure", "ContainerFailedAt" },
};

/// One attribute rectangle in a grid's initial layout (P25-01). A single cell has width and
/// height 1.
pub const GridRectDecl = struct {
    attribute: []const u8,
    x: u32,
    y: u32,
    width: u32 = 1,
    height: u32 = 1,
};

/// Moves a scene mark to the centre of a grid cell, tying the waypoint graph to the grid.
pub const GridPlaceDecl = struct {
    mark: []const u8,
    x: u32,
    y: u32,
};

/// `grid <Name> in <Room>:` owns one room's discrete overlay and its initial cell layout.
pub const GridDecl = struct {
    name: []const u8,
    room: []const u8,
    width: u32,
    height: u32,
    cell_size: u32,
    origin_x: i32 = 0,
    origin_y: i32 = 0,
    rects: []const GridRectDecl,
    places: []const GridPlaceDecl,
    /// Automata rates (P25-02); zero disables a rule.
    burn_ticks: u32 = 0,
    spread_ticks: u32 = 0,
    dissipate_ticks: u32 = 0,
    flow_ticks: u32 = 0,
};

/// One agenda trigger line (P33-01, D-056): `requires` must hold, `unless` must not. `_` is a
/// wildcard; a one-argument pattern matches any object.
pub const AgendaClauseDecl = struct {
    pattern: FactPattern,
    negated: bool,
};

/// `command <Cue>: "frame"` adds a typed-command frame (P26-01, D-057).
pub const CommandDecl = struct {
    cue: []const u8,
    text: []const u8,
};

/// `alias <Entity>: "phrase", "phrase"` adds words a typed noun may use (P26-01, D-057).
pub const AliasDecl = struct {
    entity: []const u8,
    phrases: []const []const u8,
};

/// `agenda <Name>:` owns one actor's intention to intercept a target.
pub const AgendaDecl = struct {
    name: []const u8,
    actor: []const u8,
    target: []const u8,
    priority: u16 = 0,
    cooldown_ticks: u32 = 0,
    once: bool = false,
    clauses: []const AgendaClauseDecl,
};

/// One `hint <tier> "text"` line: authored text for a generated tier (P44-01, D-134).
pub const GoalHintDecl = struct {
    tier: u32,
    text: []const u8,
};

/// One `need <Name> [after <Need>...]:` block: the fact pattern that satisfies it, its
/// prerequisites, the room the room tier names, and any authored text.
pub const GoalNeedDecl = struct {
    name: []const u8,
    pattern: FactPattern,
    after: []const []const u8 = &.{},
    room: ?[]const u8 = null,
    hints: []const GoalHintDecl = &.{},
};

/// `goal <Name>:` owns the needs a player meets to close one line of investigation
/// (P44-01, D-134). Need and prerequisite order is declaration order, which is the tie-break
/// the hint search uses.
pub const GoalDecl = struct {
    name: []const u8,
    needs: []const GoalNeedDecl,
};

/// One word of a `spellbook`, in its kind's declaration order (P44-04). The tier is that
/// position, counted from one.
pub const SpellWordDecl = struct {
    kind: spell_mod.Kind,
    name: []const u8,
};

/// One `spell <Name>: <Power>, <Element>, <Form>` row: a combination that resolves to the cue
/// named after it.
pub const SpellPatternDecl = struct {
    name: []const u8,
    power: []const u8,
    element: []const u8,
    form: []const u8,
};

/// `spellbook <Name>:` owns the word sets and the combinations they spell (P44-04). One book
/// per script; `src/spell.zig` owns validation and resolution.
pub const SpellbookDecl = struct {
    name: []const u8,
    words: []const SpellWordDecl,
    spells: []const SpellPatternDecl,
};

/// One trigger or scoring line of a `decision` (P44-05). `negated` lines are `unless`.
pub const DecisionClauseDecl = struct {
    pattern: FactPattern,
    negated: bool,
};

/// One `picks <N> when <clause>` or `drops <N> when <clause>` line of an option. `points` is
/// signed: a drop is stored negative so the module sums one kind of line.
pub const DecisionPickDecl = struct {
    points: i32,
    pattern: FactPattern,
    negated: bool,
};

/// One `option <Name>:` block. The name is what the actor must know to be offered it.
pub const DecisionOptionDecl = struct {
    name: []const u8,
    picks: []const DecisionPickDecl,
};

/// `decision <Name>:` offers an actor the options it knows and fires one cue with the winner
/// (P44-05). `src/decision.zig` owns validation and scoring.
pub const DecisionDecl = struct {
    name: []const u8,
    actor: []const u8,
    cue: []const u8,
    clauses: []const DecisionClauseDecl,
    options: []const DecisionOptionDecl,
};

/// `axis <Virtue> between <Pole> and <Pole>` declares a value axis (P45-01, D-144). The virtue
/// names the axis and its property relation; +10 is the virtue held fully, and the two poles
/// name the ways it fails. The engine names no axis: every one comes from a script.
pub const AxisDecl = struct {
    name: []const u8,
    poles: [2][]const u8,
    /// `drift step N` indented under the axis (P48-13, D-183); null keeps the default.
    drift_step: ?u8 = null,
};

/// One `leans <N> toward <Axis> when|unless <Fact>` line of a dilemma (P45-03).
pub const DilemmaLeanDecl = struct {
    points: u32,
    toward: []const u8,
    pattern: FactPattern,
    negated: bool,
};

/// One `drifts <N> toward|away from <Axis> when|unless <Fact>` line (P45-04, D-148).
pub const DilemmaDriftDecl = struct {
    points: u32,
    away: bool,
    axis: []const u8,
    pattern: FactPattern,
    negated: bool,
};

/// One `appeals <N> to <Value> [toward <Axis>]` line (P45-05, D-149). Without `toward` the value
/// is one of the two weighed axes and the appeal leans toward it; with `toward`, any declared
/// value may be appealed to and the appeal leans toward the named weighed axis.
pub const DilemmaAppealDecl = struct {
    points: u32,
    axis: []const u8,
    toward: []const u8,
    at: Token,
};

/// One tier's `"line" -> Action`.
pub const DilemmaResponseDecl = struct {
    line: []const u8,
    action: []const u8,
};

/// `dilemma <Name>:` weighs an axis against a counter-axis and answers by tier (P45-03, D-146).
/// `responses` is indexed by `dilemma.Tier`; the parser refuses a block that misses a tier.
pub const DilemmaDecl = struct {
    name: []const u8,
    actor: []const u8,
    cue: []const u8,
    clauses: []const DecisionClauseDecl,
    axis: []const u8,
    counter: []const u8,
    leans: []const DilemmaLeanDecl,
    drifts: []const DilemmaDriftDecl,
    appeals: []const DilemmaAppealDecl,
    responses: [dilemma_mod.TIER_COUNT]DilemmaResponseDecl,
    /// `tiers S and M` and `drift cap N` (P48-13, D-183); null keeps the defaults.
    tiers: ?[2]u8 = null,
    drift_cap: ?u8 = null,
};

/// `red lines <Character>: <Option>, <Option>` lists options a character never takes in any
/// decision (P45-02, D-145).
pub const RedLinesDecl = struct {
    actor: []const u8,
    options: []const []const u8,
};

/// `path <Name>:` owns the facts and routines available to one operational approach
/// (P24-01). One path is selected at runtime; the others stay muted.
pub const PathDecl = struct {
    name: []const u8,
    facts: []const Stmt,
    routines: []const Routine,
};

/// One `palette:` line (P46-03, D-155): a quoted code and a colour, or `transparent`.
pub const PaletteEntry = struct { code: Token, colour: ?image_mod.Colour };

/// An `image <Name> [frames <W>x<H>]:` block as written: its rows are resolved against the
/// palette once the whole script is read, so the palette may come later in the file.
pub const ImageSource = struct {
    name: []const u8,
    at: Token,
    frame_width: u32 = 0,
    frame_height: u32 = 0,
    frames_at: ?Token = null,
    rows: []const Token,
    /// `from "<file>.png"` in place of rows (P46-04).
    file: ?Token = null,
};

pub const StepSource = struct { frame: u32, duration: u32, at: Token };

/// A `sprite <Person or Prop>: <Image>` block with its animation lines.
pub const SpriteSource = struct {
    target: []const u8,
    at: Token,
    image: Token,
    animations: [image_mod.ANIM_COUNT][]const StepSource = @splat(@as([]const StepSource, &.{})),
};

/// Art resolved from the declarations above: pixels are palette indices, and bindings name
/// their scene or entity by text for codegen to intern. Everything is in the parser's arena.
pub const ArtDecl = struct {
    palette: []const image_mod.Colour = &.{},
    /// The codes the `palette:` block declared, in order; colours a PNG added have none. Read
    /// by `bespoke import` so new codes do not collide with a script's own (P46-04).
    palette_codes: []const []const u8 = &.{},
    images: []const image_mod.Image = &.{},
    backdrops: []const BackdropBinding = &.{},
    sprites: []const SpriteBinding = &.{},
    areas: []const AreaBinding = &.{},
    looks: []const LookBinding = &.{},
    parts: []const PartBinding = &.{},
};
/// `area <Prop>: x y w h` in art pixels (P46-05, D-158).
pub const AreaBinding = struct { target: []const u8, x: u16, y: u16, w: u16, h: u16, at: Token };
pub const BackdropBinding = struct { scene: []const u8, image: u16 };
pub const SpriteBinding = struct { target: []const u8, image: u16, animations: [image_mod.ANIM_COUNT][]const image_mod.Step };
/// `look <Name>: <Image>` with its animation lines (P48-11, D-181).
pub const LookSource = struct {
    name: []const u8,
    at: Token,
    image: Token,
    animations: [image_mod.ANIM_COUNT][]const StepSource = @splat(@as([]const StepSource, &.{})),
};
pub const LookBinding = struct { name: []const u8, image: u16, animations: [image_mod.ANIM_COUNT][]const image_mod.Step };
/// `part <Part> of <Host> at <dx> <dy>` (P48-11, D-181).
pub const PartBinding = struct { part: []const u8, host: []const u8, dx: i16, dy: i16, at: Token };

pub const NameDecl = struct { entity: []const u8, text: []const u8 };
pub const PhraseDecl = struct { key: []const u8, text: []const u8 };

pub const AST = struct {
    /// Pixel art and what it is attached to (P46-03, D-155).
    art: ArtDecl = .{},
    /// `save version N` (P48-08, D-162); 1 when the script declares none.
    save_version: ?u32 = null,
    /// `name <Thing>: "<text>"` lines (P48-09, D-179).
    display_names: std.ArrayListUnmanaged(NameDecl) = .empty,
    /// `phrase <Key>: "<text>"` lines (P48-09, D-179), already checked against the phrase table.
    phrases: std.ArrayListUnmanaged(PhraseDecl) = .empty,
    entities: std.array_list.Managed([]const u8),
    relations: std.array_list.Managed(RelationDecl),
    initial_stmts: std.array_list.Managed(Stmt),
    routines: std.array_list.Managed(Routine),
    cue_handlers: std.array_list.Managed(CueHandler),
    when_rules: std.array_list.Managed(WhenRule),
    scenes: std.array_list.Managed([]const u8),
    scene_defs: std.array_list.Managed(SceneDef),
    cast: std.array_list.Managed([]const u8),
    props: std.array_list.Managed([]const u8),
    marks: std.array_list.Managed([]const u8),
    drafts: std.array_list.Managed(DraftDecl),
    societies: std.array_list.Managed(SocietyDecl),
    duels: std.array_list.Managed(DuelDecl),
    degradations: std.array_list.Managed(DegradationDecl),
    paths: std.array_list.Managed(PathDecl),
    grids: std.array_list.Managed(GridDecl),
    agendas: std.array_list.Managed(AgendaDecl),
    goals: std.array_list.Managed(GoalDecl),
    spellbooks: std.array_list.Managed(SpellbookDecl),
    decisions: std.array_list.Managed(DecisionDecl),
    axes: std.array_list.Managed(AxisDecl),
    red_lines: std.array_list.Managed(RedLinesDecl),
    dilemmas: std.array_list.Managed(DilemmaDecl),
    commands: std.array_list.Managed(CommandDecl),
    aliases: std.array_list.Managed(AliasDecl),
    /// Script music in declaration order (P28-03, D-062). Strings borrow the source.
    scores: std.array_list.Managed(mml.ScoreDecl),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AST {
        return AST{
            .entities = std.array_list.Managed([]const u8).init(allocator),
            .relations = std.array_list.Managed(RelationDecl).init(allocator),
            .initial_stmts = std.array_list.Managed(Stmt).init(allocator),
            .routines = std.array_list.Managed(Routine).init(allocator),
            .cue_handlers = std.array_list.Managed(CueHandler).init(allocator),
            .when_rules = std.array_list.Managed(WhenRule).init(allocator),
            .scenes = std.array_list.Managed([]const u8).init(allocator),
            .scene_defs = std.array_list.Managed(SceneDef).init(allocator),
            .cast = std.array_list.Managed([]const u8).init(allocator),
            .props = std.array_list.Managed([]const u8).init(allocator),
            .marks = std.array_list.Managed([]const u8).init(allocator),
            .drafts = std.array_list.Managed(DraftDecl).init(allocator),
            .societies = std.array_list.Managed(SocietyDecl).init(allocator),
            .duels = std.array_list.Managed(DuelDecl).init(allocator),
            .degradations = std.array_list.Managed(DegradationDecl).init(allocator),
            .paths = std.array_list.Managed(PathDecl).init(allocator),
            .grids = std.array_list.Managed(GridDecl).init(allocator),
            .agendas = std.array_list.Managed(AgendaDecl).init(allocator),
            .goals = std.array_list.Managed(GoalDecl).init(allocator),
            .spellbooks = std.array_list.Managed(SpellbookDecl).init(allocator),
            .decisions = std.array_list.Managed(DecisionDecl).init(allocator),
            .axes = std.array_list.Managed(AxisDecl).init(allocator),
            .red_lines = std.array_list.Managed(RedLinesDecl).init(allocator),
            .dilemmas = std.array_list.Managed(DilemmaDecl).init(allocator),
            .commands = std.array_list.Managed(CommandDecl).init(allocator),
            .aliases = std.array_list.Managed(AliasDecl).init(allocator),
            .scores = std.array_list.Managed(mml.ScoreDecl).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AST) void {
        self.entities.deinit();
        self.relations.deinit();
        self.initial_stmts.deinit();
        self.routines.deinit();
        self.cue_handlers.deinit();
        self.when_rules.deinit();
        self.scenes.deinit();
        for (self.scene_defs.items) |*sd| {
            sd.deinit();
        }
        self.scene_defs.deinit();
        self.cast.deinit();
        self.props.deinit();
        self.marks.deinit();
        self.drafts.deinit();
        self.societies.deinit();
        self.duels.deinit();
        self.degradations.deinit();
        self.paths.deinit();
        self.grids.deinit();
        self.agendas.deinit();
        self.goals.deinit();
        self.spellbooks.deinit();
        self.decisions.deinit();
        self.axes.deinit();
        self.red_lines.deinit();
        self.dilemmas.deinit();
        self.commands.deinit();
        self.aliases.deinit();
        self.scores.deinit();
    }
};

pub const Diagnostic = diagnostic_mod.Diagnostic;

/// Source position of an arrival rule's mark, kept so undeclared marks report where they were used.
const ArrivalRef = struct {
    mark: []const u8,
    line: u32,
    column: u32,
};

/// Source position of a `play score` statement, so an undeclared score reports where it was
/// played; scores may be declared after the statement that plays them.
const ScoreRef = struct {
    score: []const u8,
    line: u32,
    column: u32,
};

pub const Parser = struct {
    lexer: *Lexer,
    current: Token,
    allocator: std.mem.Allocator,
    diagnostic: ?Diagnostic = null,
    suggestion: ?[]const u8 = null,
    /// `limit` lines (P48-13, D-183), and every item a limit counts, checked once the whole
    /// script is read so a `limit` line may come anywhere. `value` is the item's place among
    /// its owner's items, or a hint's tier.
    limit_lines: std.ArrayListUnmanaged(struct { kind: limits_mod.Kind, value: usize, at: Token }) = .empty,
    counted: std.ArrayListUnmanaged(struct { kind: limits_mod.Kind, value: usize, at: Token }) = .empty,
    diag_buf: [256]u8 = undefined,
    weave_refs: std.array_list.Managed(WeaveRef),
    arrival_refs: std.array_list.Managed(ArrivalRef),
    score_refs: std.array_list.Managed(ScoreRef),
    /// Art declarations as written, resolved at the end of `parse_program` (P46-03).
    palette_at: ?Token = null,
    /// Where `image X from "file"` reads from; null outside the command line (P46-04).
    files: ?FileSource = null,
    palette_src: std.ArrayListUnmanaged(PaletteEntry) = .empty,
    image_srcs: std.ArrayListUnmanaged(ImageSource) = .empty,
    sprite_srcs: std.ArrayListUnmanaged(SpriteSource) = .empty,
    area_srcs: std.ArrayListUnmanaged(AreaBinding) = .empty,
    look_srcs: std.ArrayListUnmanaged(LookSource) = .empty,
    part_srcs: std.ArrayListUnmanaged(PartBinding) = .empty,

    pub fn init(allocator: std.mem.Allocator, lexer: *Lexer) !Parser {
        var p = Parser{
            .lexer = lexer,
            .current = undefined,
            .allocator = allocator,
            .diagnostic = null,
            .diag_buf = undefined,
            .weave_refs = std.array_list.Managed(WeaveRef).init(allocator),
            .arrival_refs = std.array_list.Managed(ArrivalRef).init(allocator),
            .score_refs = std.array_list.Managed(ScoreRef).init(allocator),
        };
        try p.advance();
        return p;
    }

    pub fn set_error(self: *Parser, comptime fmt: []const u8, args: anytype) error{UnexpectedToken} {
        return self.error_at(self.current, fmt, args);
    }

    fn error_at(self: *Parser, tok: Token, comptime fmt: []const u8, args: anytype) error{UnexpectedToken} {
        self.record_error(tok, fmt, args);
        return error.UnexpectedToken;
    }

    fn record_error(self: *Parser, tok: Token, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.bufPrint(&self.diag_buf, fmt, args) catch "syntax error";
        self.diagnostic = .{
            .line = tok.opening_line(),
            .column = tok.col,
            .message = msg,
        };
    }

    pub fn get_diagnostic(self: *const Parser) ?Diagnostic {
        return self.diagnostic;
    }

    fn advance(self: *Parser) !void {
        self.current = try self.lexer.next();
        // Skip superfluous newlines
        while (self.current.tag == .newline) {
            self.current = try self.lexer.next();
        }
    }

    fn expect(self: *Parser, tag: TokenTag) !Token {
        if (self.current.tag != tag) {
            if (self.current.tag == .identifier) self.suggest_keyword(self.current.slice, &.{tag});
            if (self.current.slice.len == 0) {
                return self.set_error("expected {s}, found {s}", .{ token_label(tag), token_label(self.current.tag) });
            }
            return self.set_error("expected {s}, found '{s}'", .{ token_label(tag), self.current.slice });
        }
        const tok = self.current;
        try self.advance();
        return tok;
    }

    fn token_label(tag: TokenTag) []const u8 {
        const name = @tagName(tag);
        if (std.mem.startsWith(u8, name, "kw_")) {
            return switch (tag) {
                inline else => |t| if (comptime std.mem.startsWith(u8, @tagName(t), "kw_"))
                    "'" ++ @tagName(t)[3..] ++ "'"
                else
                    unreachable,
            };
        }
        return switch (tag) {
            .lparen => "'('",
            .rparen => "')'",
            .lbracket => "'['",
            .rbracket => "']'",
            .comma => "','",
            .colon => "':'",
            .gte => "'>='",
            .eof => "end of file",
            .indent => "an indented block",
            .dedent => "end of the indented block",
            .identifier => "a name",
            .number => "a number",
            .dice => "a dice expression such as 2d6",
            .string_literal => "a quoted string",
            else => name,
        };
    }

    fn suggest_keyword(self: *Parser, input: []const u8, allowed: []const TokenTag) void {
        const keywords = lexer_mod.keyword_map();
        var hints = Suggestions{};
        for (keywords.keys(), keywords.values()) |candidate, tag| {
            if (std.mem.indexOfScalar(TokenTag, allowed, tag) != null) hints.consider(input, candidate);
        }
        self.suggestion = hints.result();
    }

    fn parse_name(self: *Parser) ![]const u8 {
        // A quoted name is taken whole, so it may hold characters a word cannot, such as the
        // apostrophe in "Keeper's Lodge" (D-101). Unquoted names are unchanged.
        if (self.current.tag == .string_literal) return (try self.expect(.string_literal)).slice;
        return self.finish_name(try self.expect(.identifier));
    }

    /// Joins the rest of an unquoted name once its first word has been consumed.
    fn finish_name(self: *Parser, first_tok: Token) ![]const u8 {
        const first = first_tok.slice;
        const line = first_tok.line;
        if ((self.current.tag != .identifier and self.current.tag != .number) or self.current.line != line) {
            return first;
        }
        var buf = std.array_list.Managed(u8).init(self.allocator);
        try buf.appendSlice(first);
        while ((self.current.tag == .identifier or self.current.tag == .number) and self.current.line == line) {
            try buf.append(' ');
            try buf.appendSlice(self.current.slice);
            try self.advance();
        }
        return try buf.toOwnedSlice();
    }

    pub fn parse_program(self: *Parser) !AST {
        var ast = AST.init(self.allocator);

        while (self.current.tag != .eof) {
            switch (self.current.tag) {
                .kw_entity => {
                    try self.advance(); // consume 'entity'
                    while (true) {
                        const name = (try self.expect(.identifier)).slice;
                        try ast.entities.append(name);
                        if (self.current.tag == .comma) {
                            try self.advance();
                        } else break;
                    }
                },
                .kw_relation, .kw_property => {
                    const is_prop = self.current.tag == .kw_property;
                    try self.advance();
                    const name = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.lparen);
                    while (self.current.tag != .rparen and self.current.tag != .eof) {
                        _ = try self.advance();
                    }
                    _ = try self.expect(.rparen);
                    try ast.relations.append(.{ .name = name, .is_property = is_prop });
                },
                .kw_remember => {
                    const stmt = try self.parse_remember_stmt();
                    try ast.initial_stmts.append(stmt);
                },
                .kw_transition => {
                    try self.advance(); // consume 'transition'
                    _ = try self.expect(.kw_to);
                    _ = try self.expect(.kw_scene);
                    if (self.current.tag == .colon) try self.advance();
                    const target_scene = try self.parse_name();
                    try ast.initial_stmts.append(.{ .transition_scene = .{ .target_scene = target_scene } });
                },
                .kw_choice => {
                    var choices = std.array_list.Managed(DialogueChoice).init(self.allocator);
                    while (self.current.tag == .kw_choice) {
                        try self.advance(); // consume 'choice'
                        const text = if (self.current.tag == .string_literal)
                            (try self.expect(.string_literal)).slice
                        else
                            try self.parse_name();
                        var guard: ?Expr = null;
                        if (self.current.tag == .kw_if) {
                            try self.advance();
                            guard = try self.parse_expr();
                        }
                        var where_patterns = std.array_list.Managed(FactPattern).init(self.allocator);
                        if (self.current.tag == .kw_where) {
                            try self.advance();
                            while (true) {
                                const pat = try self.parse_fact_pattern();
                                try where_patterns.append(pat);
                                if (self.current.tag == .kw_and) {
                                    try self.advance();
                                } else break;
                            }
                        }
                        _ = try self.expect(.colon);
                        _ = try self.expect(.indent);
                        const body = try self.parse_stmt_list();
                        _ = try self.expect(.dedent);
                        try choices.append(.{
                            .text = text,
                            .guard = guard,
                            .where_patterns = try where_patterns.toOwnedSlice(),
                            .body = body,
                        });
                    }
                    try ast.initial_stmts.append(.{ .choice_block = try choices.toOwnedSlice() });
                },
                .kw_draft => {
                    const decl = try self.parse_draft_decl(ast.drafts.items);
                    try ast.drafts.append(decl);
                    try ast.entities.append(decl.name);
                    if (decl.reverse_name) |rn| try ast.entities.append(rn);
                },
                .kw_weave => {
                    return self.set_error("'weave' must appear inside a routine, cue, or rule body; it needs a caster", .{});
                },
                .kw_society => try ast.societies.append(try self.parse_society_decl()),
                .kw_duel => try ast.duels.append(try self.parse_duel_decl()),
                .kw_degradation => try ast.degradations.append(try self.parse_degradation_decl()),
                .kw_path => try ast.paths.append(try self.parse_path_decl()),
                .kw_command => {
                    try self.advance();
                    const cue = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.colon);
                    const text = (try self.expect(.string_literal)).slice;
                    _ = command_mod.parse_frame(cue, text) catch
                        return self.set_error("command '{s}' frame \"{s}\" must start with a lowercase word, use at most two <thing> slots, and never put two slots together", .{ cue, text });
                    try ast.commands.append(.{ .cue = cue, .text = text });
                },
                .kw_score => {
                    const decl = try self.parse_score_decl();
                    for (ast.scores.items) |prior| {
                        if (std.mem.eql(u8, prior.name, decl.name)) return self.set_error("score '{s}' is declared twice", .{decl.name});
                        for (prior.scenes) |ps| for (decl.scenes) |ds| {
                            if (std.mem.eql(u8, ps, ds)) return self.set_error("scene '{s}' already plays score '{s}'", .{ ds, prior.name });
                        };
                    }
                    try ast.scores.append(decl);
                },
                .kw_play, .kw_stop => try ast.initial_stmts.append(try self.parse_music_stmt()),
                .kw_alias => {
                    try self.advance();
                    const entity = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.colon);
                    var phrases = std.array_list.Managed([]const u8).init(self.allocator);
                    while (true) {
                        const phrase = (try self.expect(.string_literal)).slice;
                        if (phrase.len == 0) return self.set_error("alias for '{s}' has an empty phrase", .{entity});
                        try phrases.append(phrase);
                        if (self.current.tag != .comma) break;
                        try self.advance();
                    }
                    if (phrases.items.len > command_mod.MAX_ALIAS_PHRASES)
                        return self.set_error("alias for '{s}' has more than {d} phrases", .{ entity, command_mod.MAX_ALIAS_PHRASES });
                    try ast.aliases.append(.{ .entity = entity, .phrases = try phrases.toOwnedSlice() });
                },
                .kw_agenda => {
                    const decl = try self.parse_agenda_decl();
                    for (ast.agendas.items) |prior| {
                        if (std.mem.eql(u8, prior.name, decl.name)) return self.set_error("agenda '{s}' is declared twice", .{decl.name});
                    }
                    try ast.agendas.append(decl);
                },
                .kw_goal => {
                    try self.count_item(.goals, ast.goals.items.len + 1, self.current);
                    const decl = try self.parse_goal_decl();
                    for (ast.goals.items) |prior| {
                        if (std.mem.eql(u8, prior.name, decl.name)) return self.set_error("goal '{s}' is declared twice", .{decl.name});
                    }
                    try ast.goals.append(decl);
                },
                .kw_spellbook => {
                    const decl = try self.parse_spellbook_decl();
                    for (ast.spellbooks.items) |prior| {
                        if (std.mem.eql(u8, prior.name, decl.name)) return self.set_error("spellbook '{s}' is declared twice", .{decl.name});
                    }
                    try ast.spellbooks.append(decl);
                },
                .kw_decision => {
                    try self.count_item(.decisions, ast.decisions.items.len + 1, self.current);
                    const decl = try self.parse_decision_decl();
                    for (ast.decisions.items) |prior| {
                        if (std.mem.eql(u8, prior.name, decl.name)) return self.set_error("decision '{s}' is declared twice", .{decl.name});
                    }
                    try ast.decisions.append(decl);
                },
                .kw_dilemma => {
                    try self.count_item(.dilemmas, ast.dilemmas.items.len + 1, self.current);
                    const decl = try self.parse_dilemma_decl();
                    for (ast.dilemmas.items) |prior| {
                        if (std.mem.eql(u8, prior.name, decl.name)) return self.set_error("dilemma '{s}' is declared twice", .{decl.name});
                    }
                    try ast.dilemmas.append(decl);
                },
                .kw_axis => {
                    try self.count_item(.axes, ast.axes.items.len + 1, self.current);
                    const decl = try self.parse_axis_decl();
                    for (ast.axes.items) |prior| {
                        if (std.mem.eql(u8, prior.name, decl.name)) return self.set_error("axis '{s}' is declared twice", .{decl.name});
                    }
                    try ast.axes.append(decl);
                },
                .kw_grid => {
                    const decl = try self.parse_grid_decl();
                    for (ast.grids.items) |prior| {
                        if (std.mem.eql(u8, prior.name, decl.name)) return self.set_error("grid '{s}' is declared twice", .{decl.name});
                        if (std.mem.eql(u8, prior.room, decl.room)) return self.set_error("room '{s}' already has grid '{s}'", .{ decl.room, prior.name });
                    }
                    try ast.grids.append(decl);
                },
                .kw_routine => try ast.routines.append(try self.parse_routine_decl()),
                .kw_on => {
                    try self.advance(); // consume 'on'
                    _ = try self.expect(.kw_cue);
                    const cue_name = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.lparen);
                    var params = std.array_list.Managed([]const u8).init(self.allocator);
                    while (self.current.tag != .rparen and self.current.tag != .eof) {
                        try params.append(self.current.slice);
                        try self.advance();
                        if (self.current.tag == .comma) try self.advance();
                    }
                    if (params.items.len == 0) {
                        return self.set_error("a cue handler needs an actor parameter", .{});
                    }
                    _ = try self.expect(.rparen);

                    var where_patterns = std.array_list.Managed(FactPattern).init(self.allocator);
                    if (self.current.tag == .kw_where) {
                        try self.advance();
                        while (true) {
                            const pat = try self.parse_fact_pattern();
                            try where_patterns.append(pat);
                            if (self.current.tag == .kw_and) {
                                try self.advance();
                            } else break;
                        }
                    }

                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);

                    try ast.cue_handlers.append(.{
                        .cue_name = cue_name,
                        .params = try params.toOwnedSlice(),
                        .where_patterns = try where_patterns.toOwnedSlice(),
                        .body = body,
                    });
                },
                .kw_verb => {
                    try self.advance(); // consume 'verb' (P7-02, D-009)
                    const verb_name = (try self.expect(.identifier)).slice;
                    _ = try self.expect(.lparen);
                    var params = std.array_list.Managed([]const u8).init(self.allocator);
                    while (self.current.tag != .rparen and self.current.tag != .eof) {
                        try params.append(self.current.slice);
                        try self.advance();
                        if (self.current.tag == .comma) try self.advance();
                    }
                    if (params.items.len == 0) {
                        return self.set_error("a cue handler needs an actor parameter", .{});
                    }
                    _ = try self.expect(.rparen);

                    var where_patterns = std.array_list.Managed(FactPattern).init(self.allocator);
                    if (self.current.tag == .kw_where) {
                        try self.advance();
                        while (true) {
                            const pat = try self.parse_fact_pattern();
                            try where_patterns.append(pat);
                            if (self.current.tag == .kw_and) {
                                try self.advance();
                            } else break;
                        }
                    }

                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);

                    try ast.cue_handlers.append(.{
                        .cue_name = verb_name,
                        .params = try params.toOwnedSlice(),
                        .where_patterns = try where_patterns.toOwnedSlice(),
                        .body = body,
                    });
                },
                .kw_when => {
                    try self.advance();
                    var edge: WhenEdge = .rising;
                    if (self.current.tag == .kw_currently) {
                        try self.advance();
                    }
                    var trigger_patterns = std.array_list.Managed(FactPattern).init(self.allocator);

                    if (self.current.tag == .identifier) {
                        const first_name = try self.parse_name();
                        if (self.current.tag == .kw_forgets) {
                            try self.advance();
                            const rel_name = try self.parse_name();
                            edge = .on_expire;
                            var pat_args = try self.allocator.alloc([]const u8, 2);
                            pat_args[0] = first_name;
                            pat_args[1] = "_";
                            try trigger_patterns.append(.{
                                .relation = rel_name,
                                .args = pat_args,
                            });
                        } else if (self.current.tag == .kw_arrives) {
                            try self.advance();
                            // `at` stays an ordinary word so names may still contain it.
                            if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.slice, "at")) {
                                return self.set_error("expected 'at' after 'arrives', found '{s}'", .{self.current.slice});
                            }
                            try self.advance();
                            const mark_tok = self.current;
                            const mark_name = try self.parse_name();
                            try self.arrival_refs.append(.{ .mark = mark_name, .line = mark_tok.opening_line(), .column = mark_tok.col });
                            edge = .on_arrive;
                            var pat_args = try self.allocator.alloc([]const u8, 2);
                            pat_args[0] = first_name;
                            pat_args[1] = mark_name;
                            try trigger_patterns.append(.{
                                .relation = ARRIVES_RELATION,
                                .args = pat_args,
                            });
                        } else if (self.current.tag == .kw_stops) {
                            try self.advance();
                            if (self.current.tag == .kw_being) try self.advance();
                            const state_name = try self.state_word(try self.parse_name());
                            edge = .falling;
                            var pat_args = try self.allocator.alloc([]const u8, 1);
                            pat_args[0] = first_name;
                            try trigger_patterns.append(.{
                                .relation = state_name,
                                .args = pat_args,
                            });
                        } else if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
                            try self.advance();
                            const state_name = try self.state_word(try self.parse_name());
                            edge = .rising;
                            var pat_args = try self.allocator.alloc([]const u8, 1);
                            pat_args[0] = first_name;
                            try trigger_patterns.append(.{
                                .relation = state_name,
                                .args = pat_args,
                            });
                        } else if (self.current.tag == .lparen or self.current.tag == .lbracket) {
                            const pat = try self.finish_fact_pattern(first_name);
                            try trigger_patterns.append(pat);
                            while (self.current.tag == .kw_and) {
                                try self.advance();
                                try trigger_patterns.append(try self.parse_fact_pattern());
                            }
                        } else {
                            var pat_args = try self.allocator.alloc([]const u8, 1);
                            pat_args[0] = first_name;
                            try trigger_patterns.append(.{
                                .relation = first_name,
                                .args = pat_args,
                            });
                        }
                    } else {
                        while (true) {
                            const pat = try self.parse_fact_pattern();
                            try trigger_patterns.append(pat);
                            if (self.current.tag == .kw_and) {
                                try self.advance();
                            } else break;
                        }
                    }

                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);

                    try ast.when_rules.append(.{
                        .edge = edge,
                        .trigger_patterns = try trigger_patterns.toOwnedSlice(),
                        .body = body,
                    });
                },
                .kw_scene => {
                    try self.advance();
                    if (self.current.tag == .colon) try self.advance();
                    const name = try self.parse_name();
                    if (self.current.tag == .colon) try self.advance();
                    try ast.scenes.append(name);
                    try ast.entities.append(name);
                    try ast.scene_defs.append(SceneDef.init(self.allocator, name));
                },
                .kw_cast => {
                    try self.advance();
                    if (self.current.tag == .colon) try self.advance();
                    while (true) {
                        const name = try self.parse_name();
                        try ast.cast.append(name);
                        try ast.entities.append(name);
                        if (ast.scene_defs.items.len > 0) {
                            try ast.scene_defs.items[ast.scene_defs.items.len - 1].cast.append(name);
                        }
                        if (self.current.tag == .comma) {
                            try self.advance();
                        } else break;
                    }
                },
                .kw_props => {
                    try self.advance();
                    if (self.current.tag == .colon) try self.advance();
                    while (true) {
                        const name = try self.parse_name();
                        try ast.props.append(name);
                        try ast.entities.append(name);
                        if (ast.scene_defs.items.len > 0) {
                            try ast.scene_defs.items[ast.scene_defs.items.len - 1].props.append(name);
                        }
                        if (self.current.tag == .comma) {
                            try self.advance();
                        } else break;
                    }
                },
                .kw_marks => {
                    try self.advance();
                    if (self.current.tag == .colon) try self.advance();
                    while (true) {
                        const name = try self.parse_name();
                        try ast.marks.append(name);
                        try ast.entities.append(name);
                        if (ast.scene_defs.items.len > 0) {
                            try ast.scene_defs.items[ast.scene_defs.items.len - 1].marks.append(name);
                        }
                        if (self.current.tag == .comma) {
                            try self.advance();
                        } else break;
                    }
                },
                .kw_during => {
                    try self.advance();
                    const name_line = self.current.line;
                    const name_column = self.current.col;
                    const name = try self.parse_name();
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);
                    try ast.routines.append(.{
                        .name = name,
                        .entity = name,
                        .body = body,
                        .line = name_line,
                        .column = name_column,
                    });
                },
                .kw_now => {
                    const stmt = try self.parse_now_stmt();
                    try ast.initial_stmts.append(stmt);
                },
                .identifier => {
                    const start = self.current;
                    try self.advance();
                    // Art lines are matched by text and the token after them, so `image`,
                    // `palette`, `sprite`, and `backdrop` stay usable as names (P46-03).
                    if (try self.art_declaration(&ast, start)) continue;
                    // `name Thing: "text"` and `phrase Key: "text"` (P48-09, D-179). Matched by
                    // text and the tokens after them, so both stay usable as names.
                    if (std.mem.eql(u8, start.slice, "name") and self.current.line == start.line and
                        (self.current.tag == .identifier or self.current.tag == .string_literal))
                    {
                        const thing = self.current;
                        const entity = try self.parse_name();
                        _ = try self.expect(.colon);
                        const text = (try self.expect(.string_literal)).slice;
                        if (text.len == 0) return self.error_at(thing, "'{s}' needs a name to show, such as name {s}: \"...\"", .{ entity, entity });
                        for (ast.display_names.items) |prior| {
                            if (std.mem.eql(u8, prior.entity, entity)) return self.error_at(thing, "'{s}' is named twice", .{entity});
                        }
                        try ast.display_names.append(self.allocator, .{ .entity = entity, .text = text });
                        continue;
                    }
                    if (std.mem.eql(u8, start.slice, "phrase") and self.current.line == start.line and self.current.tag == .identifier) {
                        const key_tok = self.current;
                        try self.advance();
                        _ = try self.expect(.colon);
                        const text_tok = self.current;
                        const text = (try self.expect(.string_literal)).slice;
                        const key = phrase_mod.find(key_tok.slice) orelse {
                            var hints = Suggestions{};
                            for (phrase_mod.ENTRIES) |entry| hints.consider(key_tok.slice, entry.name);
                            self.suggestion = hints.result();
                            return self.error_at(key_tok, "the engine has no phrase '{s}'", .{key_tok.slice});
                        };
                        phrase_mod.validate(key, text) catch |err| return switch (err) {
                            error.UnknownPhraseSlot => self.error_at(text_tok, "phrase '{s}' can use only the placeholders in \"{s}\"", .{ key_tok.slice, phrase_mod.entry(key).english }),
                            else => self.error_at(text_tok, "a '{{' in phrase '{s}' has no closing '}}'", .{key_tok.slice}),
                        };
                        for (ast.phrases.items) |prior| {
                            if (std.mem.eql(u8, prior.key, key_tok.slice)) return self.error_at(key_tok, "phrase '{s}' is given twice", .{key_tok.slice});
                        }
                        try ast.phrases.append(self.allocator, .{ .key = key_tok.slice, .text = text });
                        continue;
                    }
                    // `limit <name> N` raises a sanity ceiling (P48-13, D-183). One word, matched
                    // by text with a name after it, so `limit` stays usable elsewhere.
                    if (std.mem.eql(u8, start.slice, "limit") and self.current.tag == .identifier and self.current.line == start.line) {
                        try self.parse_limit(start);
                        continue;
                    }
                    // `save version N` names which saves this build can load (P48-08, D-162).
                    // Two words, not keywords, so `save` and `version` stay usable as names.
                    if (std.mem.eql(u8, start.slice, "save") and self.current.tag == .identifier and
                        self.current.line == start.line and std.mem.eql(u8, self.current.slice, "version"))
                    {
                        try self.advance();
                        const number = self.current;
                        if (number.tag != .number or number.line != start.line) return self.error_at(number, "'save version' needs a whole number, such as 'save version 2'", .{});
                        try self.advance();
                        if (ast.save_version != null) return self.error_at(start, "'save version' is declared twice", .{});
                        const value = std.fmt.parseInt(u32, number.slice, 10) catch 0;
                        if (value == 0) return self.error_at(number, "a save version is a whole number from 1", .{});
                        ast.save_version = value;
                        continue;
                    }
                    // `red lines` is two words, not keywords, so `red` stays usable as a name.
                    if (std.mem.eql(u8, start.slice, "red") and self.current.tag == .identifier and
                        self.current.line == start.line and std.mem.eql(u8, self.current.slice, "lines"))
                    {
                        try self.advance();
                        const decl = try self.finish_red_lines();
                        for (ast.red_lines.items) |prior| {
                            if (std.mem.eql(u8, prior.actor, decl.actor)) return self.set_error("red lines for '{s}' are declared twice", .{decl.actor});
                        }
                        try ast.red_lines.append(decl);
                        continue;
                    }
                    const ident = try self.finish_name(start);
                    if (self.current.tag == .kw_with) {
                        _ = try self.advance();
                    }
                    if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
                        try self.advance();
                        if (self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "a")) {
                            try self.advance();
                            if (self.current.tag == .kw_state) {
                                const state_line = self.current.line;
                                try self.advance();
                                try ast.relations.append(.{ .name = try self.state_word(ident), .is_property = false });
                                while (self.current.line == state_line and self.current.tag != .eof) {
                                    try self.advance();
                                }
                                continue;
                            }
                        }
                        const stmt = try self.finish_state_stmt(ident);
                        try ast.initial_stmts.append(stmt);
                    } else {
                        self.suggest_keyword(start.slice, &.{ .kw_entity, .kw_relation, .kw_property, .kw_remember, .kw_transition, .kw_choice, .kw_draft, .kw_society, .kw_duel, .kw_degradation, .kw_path, .kw_command, .kw_score, .kw_play, .kw_stop, .kw_alias, .kw_agenda, .kw_grid, .kw_routine, .kw_on, .kw_verb, .kw_when, .kw_scene, .kw_cast, .kw_props, .kw_marks, .kw_now });
                        return self.error_at(start, "unexpected top-level text '{s}'", .{ident});
                    }
                },
                // Scene headings use visual indentation for cast/props/marks, but those lines are
                // still top-level declarations rather than a parser-owned block.
                .indent, .dedent => try self.advance(),
                else => {
                    return self.set_error("unexpected top-level token {s} ('{s}')", .{
                        @tagName(self.current.tag),
                        self.current.slice,
                    });
                },
            }
        }

        // Every woven draft must be declared somewhere in the program (P22-01, D-029).
        for (self.weave_refs.items) |ref| {
            if (!draft_declared(ast.drafts.items, ref.draft)) {
                var hints = Suggestions{};
                for (ast.drafts.items) |decl| {
                    hints.consider(ref.draft, decl.name);
                    if (decl.reverse_name) |name| hints.consider(ref.draft, name);
                }
                self.suggestion = hints.result();
                const msg = std.fmt.bufPrint(&self.diag_buf, "weave of undeclared draft '{s}'", .{ref.draft}) catch "weave of undeclared draft";
                self.diagnostic = .{ .line = ref.line, .column = ref.column, .message = msg };
                return error.UnexpectedToken;
            }
        }

        // A played score must be declared somewhere in the program (P28-03, D-062).
        for (self.score_refs.items) |ref| {
            const declared = for (ast.scores.items) |decl| {
                if (std.mem.eql(u8, decl.name, ref.score)) break true;
            } else false;
            if (!declared) {
                var hints = Suggestions{};
                for (ast.scores.items) |decl| hints.consider(ref.score, decl.name);
                self.suggestion = hints.result();
                const msg = std.fmt.bufPrint(&self.diag_buf, "play of undeclared score '{s}'", .{ref.score}) catch "play of undeclared score";
                self.diagnostic = .{ .line = ref.line, .column = ref.column, .message = msg };
                return error.UnexpectedToken;
            }
        }

        // An arrival rule must name a declared mark: an unknown one could never fire (D-036).
        for (self.arrival_refs.items) |ref| {
            if (!mark_declared(&ast, ref.mark)) {
                var hints = Suggestions{};
                for (ast.marks.items) |mark| hints.consider(ref.mark, mark);
                for (ast.scene_defs.items) |scene| {
                    for (scene.marks.items) |mark| hints.consider(ref.mark, mark);
                }
                self.suggestion = hints.result();
                const msg = std.fmt.bufPrint(&self.diag_buf, "arrival at undeclared mark '{s}'", .{ref.mark}) catch "arrival at undeclared mark";
                self.diagnostic = .{ .line = ref.line, .column = ref.column, .message = msg };
                return error.UnexpectedToken;
            }
        }

        try self.check_limits();
        try self.resolve_art(&ast);
        return ast;
    }

    fn mark_declared(ast: *const AST, name: []const u8) bool {
        for (ast.marks.items) |m| {
            if (std.mem.eql(u8, m, name)) return true;
        }
        for (ast.scene_defs.items) |scene| {
            for (scene.marks.items) |m| {
                if (std.mem.eql(u8, m, name)) return true;
            }
        }
        return false;
    }

    fn take_atom(self: *Parser) ![]const u8 {
        return switch (self.current.tag) {
            .identifier, .string_literal, .number => blk: {
                const value = self.current.slice;
                try self.advance();
                break :blk value;
            },
            else => self.set_error("expected value, found {s} ('{s}')", .{ @tagName(self.current.tag), self.current.slice }),
        };
    }

    fn take_word(self: *Parser, expected: []const u8) !void {
        if (!std.mem.eql(u8, self.current.slice, expected)) {
            var hints = Suggestions{};
            hints.consider(self.current.slice, expected);
            self.suggestion = hints.result();
            return self.set_error("expected '{s}', found '{s}'", .{ expected, self.current.slice });
        }
        try self.advance();
    }

    fn take_u32(self: *Parser) !u32 {
        const tok = try self.expect(.number);
        return std.fmt.parseInt(u32, tok.slice, 10) catch self.error_at(tok, "invalid integer '{s}'", .{tok.slice});
    }

    fn take_u64(self: *Parser) !u64 {
        const tok = try self.expect(.number);
        return std.fmt.parseInt(u64, tok.slice, 10) catch self.error_at(tok, "invalid integer '{s}'", .{tok.slice});
    }

    fn take_i32(self: *Parser) !i32 {
        const tok = try self.expect(.number);
        return std.fmt.parseInt(i32, tok.slice, 10) catch self.error_at(tok, "invalid integer '{s}'", .{tok.slice});
    }

    fn take_bool(self: *Parser) !bool {
        const tok = self.current;
        const value = try self.take_atom();
        if (std.mem.eql(u8, value, "true")) return true;
        if (std.mem.eql(u8, value, "false")) return false;
        return self.error_at(tok, "expected true or false, found '{s}'", .{value});
    }

    fn take_optional_name(self: *Parser) !?[]const u8 {
        const value = try self.take_atom();
        return if (std.mem.eql(u8, value, "none")) null else value;
    }

    fn take_line_names(self: *Parser, line: u32) ![]const []const u8 {
        var names = std.array_list.Managed([]const u8).init(self.allocator);
        while (self.current.line == line and self.current.tag != .dedent and self.current.tag != .eof) {
            if (self.current.tag == .comma) {
                try self.advance();
                continue;
            }
            try names.append(try self.take_atom());
        }
        return try names.toOwnedSlice();
    }

    /// P32-22 declaration grammar. Values are positional so every field is explicit and package
    /// serialization has one canonical representation; nested member lines hold per-member data.
    fn parse_society_decl(self: *Parser) !SocietyDecl {
        try self.advance(); // society
        const name = try self.take_atom();
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);

        var needs = std.array_list.Managed(SocietyNeedDecl).init(self.allocator);
        var members = std.array_list.Managed(SocietyMemberDecl).init(self.allocator);
        var friends = std.array_list.Managed([2][]const u8).init(self.allocator);
        var enforcer: ?[]const u8 = null;
        var holding: ?[]const u8 = null;
        var gathering: ?[]const u8 = null;
        var flight_to: ?[]const u8 = null;
        var flight_then: ?[]const u8 = null;
        var flight_every: u64 = 4;
        var radii = [4]i32{ 14, 12, 15, 14 };
        var grudge_ticks = [2]u64{ 60, 50 };
        var warrant_priority: u16 = 10;
        var currency_unit: []const u8 = "g";
        var relations = (SocietyDecl{ .name = "", .needs = &.{}, .members = &.{}, .enforcer = null, .holding = null, .gathering = "", .flight_to = "", .flight_then = null, .flight_every = 4, .friends = &.{} }).relations;

        while (self.current.tag != .dedent and self.current.tag != .eof) {
            const directive = self.current.slice;
            if (std.mem.eql(u8, directive, "need")) {
                try self.advance();
                const need_name = try self.take_atom();
                const worse = try self.take_atom();
                const max = try self.take_u32();
                const rate = try self.take_u32();
                const resting_rate = try self.take_u32();
                const seek = try self.take_u32();
                const kind = try self.take_atom();
                if (std.mem.eql(u8, kind, "trade")) {
                    try needs.append(.{
                        .name = need_name,
                        .worse = worse,
                        .max = max,
                        .rate = rate,
                        .resting_rate = resting_rate,
                        .seek = seek,
                        .satisfy = .{ .trade = .{
                            .provider = try self.take_optional_name(),
                            .price = try self.take_u32(),
                            .relief = try self.take_u32(),
                            .floor = try self.take_u32(),
                            .critical = blk: {
                                const value = try self.take_optional_name();
                                break :blk if (value) |v| std.fmt.parseInt(u32, v, 10) catch return self.set_error("invalid critical value '{s}'", .{v}) else null;
                            },
                            .theft_relief = try self.take_u32(),
                            .theft_floor = try self.take_u32(),
                            .item = try self.take_atom(),
                        } },
                    });
                } else if (std.mem.eql(u8, kind, "stay")) {
                    try needs.append(.{
                        .name = need_name,
                        .worse = worse,
                        .max = max,
                        .rate = rate,
                        .resting_rate = resting_rate,
                        .seek = seek,
                        .satisfy = .{ .stay = .{
                            .at = try self.take_atom(),
                            .restore = try self.take_u32(),
                            .until = try self.take_u32(),
                            .activity = try self.take_atom(),
                            .unaware = try self.take_bool(),
                            .state = try self.take_atom(),
                            .verb = try self.take_atom(),
                        } },
                    });
                } else return self.set_error("society need '{s}' must use trade or stay", .{need_name});
            } else if (std.mem.eql(u8, directive, "member")) {
                try self.advance();
                const member_name = try self.take_atom();
                const gold = try self.take_u32();
                const idle = try self.take_atom();
                _ = try self.expect(.colon);
                _ = try self.expect(.indent);
                var member_needs = std.array_list.Managed(SocietyMemberNeedDecl).init(self.allocator);
                var routine_activity: ?[]const u8 = null;
                var stops: []const []const u8 = &.{};
                var period: u64 = 1;
                var work: ?SocietyWorkDecl = null;
                var merchant: ?SocietyMerchantDecl = null;
                var broadcaster = false;
                var owns: []const []const u8 = &.{};
                var carries: []const []const u8 = &.{};
                while (self.current.tag != .dedent and self.current.tag != .eof) {
                    const member_directive = self.current.slice;
                    const line = self.current.line;
                    try self.advance();
                    if (std.mem.eql(u8, member_directive, "need")) {
                        try member_needs.append(.{ .name = try self.take_atom(), .value = try self.take_u32(), .rate = blk: {
                            const v = try self.take_optional_name();
                            break :blk if (v) |text| std.fmt.parseInt(u32, text, 10) catch return self.set_error("invalid member need rate '{s}'", .{text}) else null;
                        }, .provider = try self.take_optional_name() });
                    } else if (std.mem.eql(u8, member_directive, "routine")) {
                        routine_activity = try self.take_optional_name();
                        period = try self.take_u64();
                        stops = try self.take_line_names(line);
                    } else if (std.mem.eql(u8, member_directive, "work")) {
                        work = .{ .at = try self.take_atom(), .every = try self.take_u64(), .earn = try self.take_u32(), .restock = try self.take_bool() };
                    } else if (std.mem.eql(u8, member_directive, "merchant")) {
                        merchant = .{ .post = try self.take_atom(), .goods = try self.take_atom() };
                    } else if (std.mem.eql(u8, member_directive, "broadcaster")) {
                        broadcaster = true;
                    } else if (std.mem.eql(u8, member_directive, "owns")) {
                        owns = try self.take_line_names(line);
                    } else if (std.mem.eql(u8, member_directive, "carries")) {
                        carries = try self.take_line_names(line);
                    } else return self.set_error("unknown society member directive '{s}'", .{member_directive});
                }
                _ = try self.expect(.dedent);
                try members.append(.{ .name = member_name, .gold = gold, .idle = idle, .needs = try member_needs.toOwnedSlice(), .routine_activity = routine_activity, .stops = stops, .period = period, .work = work, .merchant = merchant, .broadcaster = broadcaster, .owns = owns, .carries = carries });
            } else {
                try self.advance();
                if (std.mem.eql(u8, directive, "enforcer")) enforcer = try self.take_optional_name() else if (std.mem.eql(u8, directive, "holding")) holding = try self.take_optional_name() else if (std.mem.eql(u8, directive, "gathering")) gathering = try self.take_atom() else if (std.mem.eql(u8, directive, "flight")) {
                    flight_to = try self.take_atom();
                    flight_then = try self.take_optional_name();
                    flight_every = try self.take_u64();
                } else if (std.mem.eql(u8, directive, "friend")) {
                    try friends.append(.{ try self.take_atom(), try self.take_atom() });
                } else if (std.mem.eql(u8, directive, "radii")) {
                    for (&radii) |*value| value.* = try self.take_i32();
                } else if (std.mem.eql(u8, directive, "grudges")) {
                    grudge_ticks = .{ try self.take_u64(), try self.take_u64() };
                } else if (std.mem.eql(u8, directive, "priority")) {
                    warrant_priority = @intCast(try self.take_u32());
                } else if (std.mem.eql(u8, directive, "currency")) {
                    currency_unit = try self.take_atom();
                } else if (std.mem.eql(u8, directive, "relations")) {
                    for (&relations) |*relation| relation.* = try self.take_atom();
                } else return self.set_error("unknown society directive '{s}'", .{directive});
            }
        }
        _ = try self.expect(.dedent);
        if (gathering == null or flight_to == null) return self.set_error("society '{s}' needs gathering and flight directives", .{name});
        return .{ .name = name, .needs = try needs.toOwnedSlice(), .members = try members.toOwnedSlice(), .enforcer = enforcer, .holding = holding, .gathering = gathering.?, .flight_to = flight_to.?, .flight_then = flight_then, .flight_every = flight_every, .friends = try friends.toOwnedSlice(), .radii = radii, .grudge_ticks = grudge_ticks, .warrant_priority = warrant_priority, .currency_unit = currency_unit, .relations = relations };
    }

    fn parse_duel_decl(self: *Parser) !DuelDecl {
        try self.advance(); // duel
        const name = try self.take_atom();
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);
        var pairs = std.array_list.Managed(DuelPairDecl).init(self.allocator);
        var tiers = std.array_list.Managed(DuelTierDecl).init(self.allocator);
        var stages = std.array_list.Managed(FatigueStageDecl).init(self.allocator);
        var fallbacks = std.array_list.Managed([]const u8).init(self.allocator);
        var win_at: ?u32 = null;
        var relations = (DuelDecl{ .name = "", .pairs = &.{}, .fallbacks = &.{}, .win_at = null, .tiers = &.{}, .fatigue_count_relation = "Inquiries", .fatigue_calm_label = "calm", .fatigue_stages = &.{} }).relations;
        var count_relation: []const u8 = "Inquiries";
        var calm_label: []const u8 = "calm";

        while (self.current.tag != .dedent and self.current.tag != .eof) {
            const directive = self.current.slice;
            try self.advance();
            if (std.mem.eql(u8, directive, "pair")) {
                const pair_name = try self.take_atom();
                _ = try self.expect(.colon);
                _ = try self.expect(.indent);
                var challenge: ?[]const u8 = null;
                var reply: ?[]const u8 = null;
                var variants = std.array_list.Managed([]const u8).init(self.allocator);
                while (self.current.tag != .dedent and self.current.tag != .eof) {
                    const field = self.current.slice;
                    try self.advance();
                    if (std.mem.eql(u8, field, "challenge")) challenge = try self.take_atom() else if (std.mem.eql(u8, field, "reply")) reply = try self.take_atom() else if (std.mem.eql(u8, field, "variant")) {
                        const tier = try self.take_u32();
                        if (tier != variants.items.len + 1) return self.set_error("duel variants must declare contiguous tiers starting at 1", .{});
                        try variants.append(try self.take_atom());
                    } else return self.set_error("unknown duel pair field '{s}'", .{field});
                }
                _ = try self.expect(.dedent);
                if (challenge == null or reply == null) return self.set_error("duel pair '{s}' needs challenge and reply", .{pair_name});
                try pairs.append(.{ .name = pair_name, .challenge = challenge.?, .reply = reply.?, .variants = try variants.toOwnedSlice() });
            } else if (std.mem.eql(u8, directive, "fallback")) {
                if (fallbacks.items.len == DUEL_MAX_FALLBACKS) return self.set_error("duel '{s}' has more than {d} fallback lines", .{ name, DUEL_MAX_FALLBACKS });
                try fallbacks.append(try self.take_atom());
            } else if (std.mem.eql(u8, directive, "win")) {
                const value = try self.take_optional_name();
                win_at = if (value) |v| std.fmt.parseInt(u32, v, 10) catch return self.set_error("invalid duel win value '{s}'", .{v}) else null;
            } else if (std.mem.eql(u8, directive, "relations")) {
                for (&relations) |*relation| relation.* = try self.take_atom();
            } else if (std.mem.eql(u8, directive, "tier")) {
                try tiers.append(.{ .opponent = try self.take_atom(), .tier = try self.take_u32() });
            } else if (std.mem.eql(u8, directive, "fatigue")) {
                count_relation = try self.take_atom();
                calm_label = try self.take_atom();
                _ = try self.expect(.colon);
                _ = try self.expect(.indent);
                while (self.current.tag != .dedent and self.current.tag != .eof) {
                    try self.take_word("stage");
                    try stages.append(.{ .relation = try self.take_atom(), .at = try self.take_u32(), .ttl = try self.take_u64(), .label = try self.take_atom() });
                }
                _ = try self.expect(.dedent);
            } else return self.set_error("unknown duel directive '{s}'", .{directive});
        }
        _ = try self.expect(.dedent);
        if (pairs.items.len == 0 or stages.items.len == 0) return self.set_error("duel '{s}' needs at least one pair and fatigue stage", .{name});
        return .{ .name = name, .pairs = try pairs.toOwnedSlice(), .fallbacks = try fallbacks.toOwnedSlice(), .win_at = win_at, .relations = relations, .tiers = try tiers.toOwnedSlice(), .fatigue_count_relation = count_relation, .fatigue_calm_label = calm_label, .fatigue_stages = try stages.toOwnedSlice() };
    }

    /// P23-01 declaration grammar. The ordered stage list defines progression; each vessel
    /// explicitly names its initial stage so scripts remain authoritative over setup.
    /// `score <Name>: "<lead MML>"`, or a block of `lead`, `bass`, `chords`, and `drums` lines
    /// with MML strings and `scene <Scene>` lines (P28-03, D-062). Each part is parsed here, so
    /// an MML error reports its script line and column.
    fn parse_score_decl(self: *Parser) !mml.ScoreDecl {
        try self.advance(); // score
        const name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.colon);
        var decl = mml.ScoreDecl{ .name = name };
        if (self.current.tag == .string_literal) {
            const tok = self.current;
            try self.advance();
            decl.parts[0] = tok.slice;
            try self.check_score_part(name, 0, tok);
            return decl;
        }
        _ = try self.expect(.indent);
        var scenes = std.array_list.Managed([]const u8).init(self.allocator);
        var seen = @as([mml.PART_COUNT]bool, @splat(false));
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            if (self.current.tag == .kw_scene) {
                try self.advance();
                const scene = try self.parse_name();
                for (scenes.items) |prior| {
                    if (std.mem.eql(u8, prior, scene)) return self.set_error("score '{s}' names scene '{s}' twice", .{ name, scene });
                }
                if (scenes.items.len == mml.MAX_SCORE_SCENES) return self.set_error("score '{s}' names more than {d} scenes", .{ name, mml.MAX_SCORE_SCENES });
                try scenes.append(scene);
                continue;
            }
            const directive = self.current.slice;
            const index = for (mml.PART_NAMES, 0..) |part, i| {
                if (self.current.tag == .identifier and std.mem.eql(u8, part, directive)) break i;
            } else return self.set_error("unknown score directive '{s}'; use lead, bass, chords, drums, or scene", .{directive});
            if (seen[index]) return self.set_error("score '{s}' declares {s} twice", .{ name, directive });
            seen[index] = true;
            try self.advance();
            if (self.current.tag != .string_literal) return self.set_error("score '{s}' {s} needs an MML string", .{ name, directive });
            const tok = self.current;
            try self.advance();
            decl.parts[index] = tok.slice;
            try self.check_score_part(name, index, tok);
        }
        _ = try self.expect(.dedent);
        decl.scenes = try scenes.toOwnedSlice();
        return decl;
    }

    /// Parses one part's MML and maps an error inside the string to the script position: the
    /// token's column is its opening quote, so MML column 1 is one column to its right.
    fn check_score_part(self: *Parser, name: []const u8, index: usize, tok: Token) !void {
        var diag = mml.Diagnostic{};
        var score = mml.parse(self.allocator, tok.slice, mml.part_kind(index), &diag) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidScore => {
                const msg = std.fmt.bufPrint(&self.diag_buf, "score '{s}' {s}: {s}", .{ name, mml.PART_NAMES[index], diag.message }) catch "invalid MML";
                self.diagnostic = .{
                    .line = tok.opening_line() + diag.line - 1,
                    .column = if (diag.line == 1) tok.col + diag.column else diag.column,
                    .message = msg,
                };
                return error.UnexpectedToken;
            },
        };
        score.deinit();
    }

    /// `play score <Name>` or `stop score` (P28-03, D-062).
    fn parse_music_stmt(self: *Parser) !Stmt {
        const is_play = self.current.tag == .kw_play;
        try self.advance();
        _ = try self.expect(.kw_score);
        if (!is_play) return .{ .play_score = null };
        const tok = try self.expect(.identifier);
        try self.score_refs.append(.{ .score = tok.slice, .line = tok.opening_line(), .column = tok.col });
        return .{ .play_score = tok.slice };
    }

    fn parse_degradation_decl(self: *Parser) !DegradationDecl {
        try self.advance(); // degradation
        const name = try self.take_atom();
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);
        var substance: ?[]const u8 = null;
        var stages = std.array_list.Managed(DegradationStageDecl).init(self.allocator);
        var vessels = std.array_list.Managed(DegradationVesselDecl).init(self.allocator);
        var spill_per_moving_tick: u32 = 0;
        var relations = (DegradationDecl{ .name = "", .substance = "", .stages = &.{}, .vessels = &.{} }).relations;

        while (self.current.tag != .dedent and self.current.tag != .eof) {
            const directive = self.current.slice;
            try self.advance();
            if (std.mem.eql(u8, directive, "substance")) {
                if (substance != null) return self.set_error("degradation '{s}' declares substance twice", .{name});
                substance = try self.take_atom();
            } else if (std.mem.eql(u8, directive, "stage")) {
                try stages.append(.{ .name = try self.take_atom(), .duration_ticks = try self.take_u64() });
            } else if (std.mem.eql(u8, directive, "vessel")) {
                try vessels.append(.{
                    .name = try self.take_atom(),
                    .capacity = try self.take_u32(),
                    .initial_volume = try self.take_u32(),
                    .initial_stage = try self.take_atom(),
                });
            } else if (std.mem.eql(u8, directive, "spill")) {
                spill_per_moving_tick = try self.take_u32();
            } else if (std.mem.eql(u8, directive, "relations")) {
                for (&relations) |*relation| relation.* = try self.take_atom();
            } else return self.set_error("unknown degradation directive '{s}'", .{directive});
        }
        _ = try self.expect(.dedent);
        if (substance == null or stages.items.len < 2 or vessels.items.len == 0)
            return self.set_error("degradation '{s}' needs a substance, at least two stages, and a vessel", .{name});
        return .{
            .name = name,
            .substance = substance.?,
            .stages = try stages.toOwnedSlice(),
            .vessels = try vessels.toOwnedSlice(),
            .spill_per_moving_tick = spill_per_moving_tick,
            .relations = relations,
        };
    }

    /// P25-01 grammar. `size` and `cell` are required; attribute lines name a cell or, with a
    /// trailing width and height, a rectangle. Bounds are checked here so a script error points
    /// at the grid rather than surfacing later as an engine validation failure.
    fn parse_grid_decl(self: *Parser) !GridDecl {
        try self.advance(); // grid
        const name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.kw_in);
        // A string literal names a multi-word scene (`grid Racks in "Wine Cellar":`).
        const room = try self.take_atom();
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);
        var width: ?u32 = null;
        var height: u32 = 0;
        var cell_size: ?u32 = null;
        var origin_x: i32 = 0;
        var origin_y: i32 = 0;
        var rects = std.array_list.Managed(GridRectDecl).init(self.allocator);
        var places = std.array_list.Managed(GridPlaceDecl).init(self.allocator);
        var rates = @as([4]?u32, @splat(null));
        const rate_names = [_][]const u8{ "burn", "spread", "dissipate", "flow" };

        while (self.current.tag != .dedent and self.current.tag != .eof) {
            const directive = self.current.slice;
            try self.advance();
            if (std.mem.eql(u8, directive, "size")) {
                if (width != null) return self.set_error("grid '{s}' declares size twice", .{name});
                width = try self.take_u32();
                height = try self.take_u32();
            } else if (std.mem.eql(u8, directive, "cell")) {
                if (cell_size != null) return self.set_error("grid '{s}' declares cell twice", .{name});
                cell_size = try self.take_u32();
            } else if (std.mem.eql(u8, directive, "origin")) {
                origin_x = try self.take_i32();
                origin_y = try self.take_i32();
            } else if (rate_index(&rate_names, directive)) |r| {
                if (rates[r] != null) return self.set_error("grid '{s}' declares {s} twice", .{ name, directive });
                rates[r] = try self.take_u32();
            } else if (std.mem.eql(u8, directive, "place")) {
                try places.append(.{ .mark = try self.take_atom(), .x = try self.take_u32(), .y = try self.take_u32() });
            } else if (grid_mod.Attribute.from_name(directive) != null) {
                var rect = GridRectDecl{ .attribute = directive, .x = try self.take_u32(), .y = try self.take_u32() };
                if (self.current.tag == .number) {
                    rect.width = try self.take_u32();
                    rect.height = try self.take_u32();
                }
                try rects.append(rect);
            } else return self.set_error("unknown grid directive '{s}'", .{directive});
        }
        _ = try self.expect(.dedent);

        const w = width orelse return self.set_error("grid '{s}' needs a size", .{name});
        const size = cell_size orelse return self.set_error("grid '{s}' needs a cell size", .{name});
        if (w == 0 or height == 0 or size == 0 or w > std.math.maxInt(u16) or height > std.math.maxInt(u16) or
            @as(u64, w) * height > grid_mod.MAX_CELLS)
            return self.set_error("grid '{s}' size must be positive with at most {d} cells", .{ name, grid_mod.MAX_CELLS });
        for (rects.items) |rect| {
            if (rect.width == 0 or rect.height == 0 or @as(u64, rect.x) + rect.width > w or @as(u64, rect.y) + rect.height > height)
                return self.set_error("grid '{s}' {s} cells lie outside the grid", .{ name, rect.attribute });
        }
        for (places.items) |place| {
            if (place.x >= w or place.y >= height) return self.set_error("grid '{s}' places '{s}' outside the grid", .{ name, place.mark });
        }
        return .{
            .name = name,
            .room = room,
            .width = w,
            .height = height,
            .cell_size = size,
            .origin_x = origin_x,
            .origin_y = origin_y,
            .rects = try rects.toOwnedSlice(),
            .places = try places.toOwnedSlice(),
            .burn_ticks = rates[0] orelse 0,
            .spread_ticks = rates[1] orelse 0,
            .dissipate_ticks = rates[2] orelse 0,
            .flow_ticks = rates[3] orelse 0,
        };
    }

    /// P33-01 grammar. `actor`, `target`, and at least one trigger line are required.
    fn parse_agenda_decl(self: *Parser) !AgendaDecl {
        try self.advance(); // agenda
        const name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);
        var actor: ?[]const u8 = null;
        var target: ?[]const u8 = null;
        var decl = AgendaDecl{ .name = name, .actor = "", .target = "", .clauses = &.{} };
        var clauses = std.array_list.Managed(AgendaClauseDecl).init(self.allocator);
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            const directive = self.current.slice;
            try self.advance();
            if (std.mem.eql(u8, directive, "actor")) {
                if (actor != null) return self.set_error("agenda '{s}' declares actor twice", .{name});
                actor = (try self.expect(.identifier)).slice;
            } else if (std.mem.eql(u8, directive, "target")) {
                if (target != null) return self.set_error("agenda '{s}' declares target twice", .{name});
                target = (try self.expect(.identifier)).slice;
            } else if (std.mem.eql(u8, directive, "priority")) {
                const value = try self.take_u32();
                if (value > std.math.maxInt(u16)) return self.set_error("agenda '{s}' priority is above {d}", .{ name, std.math.maxInt(u16) });
                decl.priority = @intCast(value);
            } else if (std.mem.eql(u8, directive, "cooldown")) {
                decl.cooldown_ticks = try self.take_u32();
            } else if (std.mem.eql(u8, directive, "once")) {
                decl.once = true;
            } else if (std.mem.eql(u8, directive, "requires") or std.mem.eql(u8, directive, "unless")) {
                const pattern = try self.parse_fact_pattern();
                if (pattern.args.len == 0 or pattern.args.len > 2)
                    return self.set_error("agenda '{s}' trigger {s} needs one or two arguments", .{ name, pattern.relation });
                try clauses.append(.{ .pattern = pattern, .negated = directive[0] == 'u' });
            } else return self.set_error("unknown agenda directive '{s}'", .{directive});
        }
        _ = try self.expect(.dedent);
        decl.actor = actor orelse return self.set_error("agenda '{s}' needs an actor", .{name});
        decl.target = target orelse return self.set_error("agenda '{s}' needs a target", .{name});
        if (std.mem.eql(u8, decl.actor, decl.target)) return self.set_error("agenda '{s}' cannot target its own actor", .{name});
        if (clauses.items.len == 0 or clauses.items.len > agency_mod.MAX_CLAUSES)
            return self.set_error("agenda '{s}' needs between 1 and {d} trigger lines", .{ name, agency_mod.MAX_CLAUSES });
        decl.clauses = try clauses.toOwnedSlice();
        return decl;
    }

    fn parse_goal_decl(self: *Parser) !GoalDecl {
        try self.advance(); // goal
        const name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);
        var needs = std.array_list.Managed(GoalNeedDecl).init(self.allocator);
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            const directive = self.current.slice;
            if (self.current.tag != .identifier or !std.mem.eql(u8, directive, "need"))
                return self.set_error("goal '{s}' expects a 'need <Name>:' block, found '{s}'", .{ name, directive });
            try self.advance();
            try self.count_item(.needs, needs.items.len + 1, self.current);
            const need_name = (try self.expect(.identifier)).slice;
            for (needs.items) |prior| {
                if (std.mem.eql(u8, prior.name, need_name))
                    return self.set_error("goal '{s}' declares need '{s}' twice", .{ name, need_name });
            }
            var after = std.array_list.Managed([]const u8).init(self.allocator);
            if (self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "after")) {
                try self.advance();
                while (true) {
                    try after.append((try self.expect(.identifier)).slice);
                    if (self.current.tag != .comma) break;
                    try self.advance();
                }
                if (after.items.len > hint_mod.MAX_AFTER)
                    return self.set_error("need '{s}' waits on more than {d} prerequisites", .{ need_name, hint_mod.MAX_AFTER });
            }
            _ = try self.expect(.colon);
            _ = try self.expect(.indent);
            var pattern: ?FactPattern = null;
            var room: ?[]const u8 = null;
            var hints = std.array_list.Managed(GoalHintDecl).init(self.allocator);
            while (self.current.tag != .dedent and self.current.tag != .eof) {
                const need_directive = self.current.slice;
                if (self.current.tag != .identifier)
                    return self.set_error("need '{s}' expects 'met', 'room', or 'hint', found '{s}'", .{ need_name, need_directive });
                try self.advance();
                if (std.mem.eql(u8, need_directive, "met")) {
                    if (pattern != null) return self.set_error("need '{s}' declares met twice", .{need_name});
                    const fact = try self.parse_fact_pattern();
                    if (fact.args.len == 0 or fact.args.len > 2)
                        return self.set_error("need '{s}' met pattern needs one or two arguments", .{need_name});
                    pattern = fact;
                } else if (std.mem.eql(u8, need_directive, "room")) {
                    if (room != null) return self.set_error("need '{s}' declares room twice", .{need_name});
                    room = (try self.expect(.identifier)).slice;
                } else if (std.mem.eql(u8, need_directive, "hint")) {
                    const tier_tok = self.current;
                    const tier = try self.take_u32();
                    if (hint_mod.Tier.fromInt(tier) == null)
                        return self.error_at(tier_tok, "need '{s}' hint tier is {d}; tiers count from 1 (room), 2 (thing), and 3 (relation), and a script may write more up to {d}", .{ need_name, tier, hint_mod.MAX_TIERS });
                    try self.count_item(.hints, tier, tier_tok);
                    for (hints.items) |prior| {
                        if (prior.tier == tier) return self.set_error("need '{s}' already has a tier {d} hint", .{ need_name, tier });
                    }
                    const text = (try self.expect(.string_literal)).slice;
                    if (text.len == 0 or text.len > hint_mod.MAX_HINT_TEXT)
                        return self.set_error("need '{s}' hint text must be 1 to {d} bytes", .{ need_name, hint_mod.MAX_HINT_TEXT });
                    try hints.append(.{ .tier = tier, .text = text });
                } else return self.set_error("unknown need directive '{s}'", .{need_directive});
            }
            _ = try self.expect(.dedent);
            const met = pattern orelse return self.set_error("need '{s}' needs a 'met <Fact>' line", .{need_name});
            try needs.append(.{
                .name = need_name,
                .pattern = met,
                .after = try after.toOwnedSlice(),
                .room = room,
                .hints = try hints.toOwnedSlice(),
            });
        }
        _ = try self.expect(.dedent);
        if (needs.items.len == 0) return self.set_error("goal '{s}' needs at least one need", .{name});
        if (needs.items.len > hint_mod.MAX_NEEDS)
            return self.set_error("goal '{s}' has more than {d} needs", .{ name, hint_mod.MAX_NEEDS });
        return .{ .name = name, .needs = try needs.toOwnedSlice() };
    }

    /// Parses `spellbook <Name>:`: word lines in three kinds and the rows that combine them.
    /// A word is checked against its kind and a row against the declared words here, so a
    /// misspelled or misplaced word names the line that got it wrong (P44-04).
    fn parse_spellbook_decl(self: *Parser) !SpellbookDecl {
        try self.advance(); // spellbook
        const name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);
        var words = std.array_list.Managed(SpellWordDecl).init(self.allocator);
        var spells = std.array_list.Managed(SpellPatternDecl).init(self.allocator);
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            const directive = self.current.slice;
            if (self.current.tag != .identifier)
                return self.set_error("spellbook '{s}' expects 'power', 'element', 'form', or 'spell', found '{s}'", .{ name, directive });
            try self.advance();
            if (std.mem.eql(u8, directive, "power") or std.mem.eql(u8, directive, "element") or std.mem.eql(u8, directive, "form")) {
                const kind: spell_mod.Kind = if (std.mem.eql(u8, directive, "power"))
                    .power
                else if (std.mem.eql(u8, directive, "element"))
                    .element
                else
                    .form;
                var count: usize = 0;
                while (self.current.tag != .dedent and self.current.tag != .eof) {
                    try self.count_item(.words, count + 1, self.current);
                    const word_name = (try self.expect(.identifier)).slice;
                    if (word_name.len > spell_mod.MAX_WORD_TEXT)
                        return self.set_error("spellbook '{s}' word '{s}' is longer than {d} bytes", .{ name, word_name, spell_mod.MAX_WORD_TEXT });
                    for (words.items) |prior| {
                        if (std.mem.eql(u8, prior.name, word_name))
                            return self.set_error("spellbook '{s}' declares word '{s}' twice", .{ name, word_name });
                    }
                    for (spells.items) |prior| {
                        if (std.mem.eql(u8, prior.name, word_name))
                            return self.set_error("spellbook '{s}' word '{s}' reuses a spell name", .{ name, word_name });
                    }
                    count += 1;
                    if (count > spell_mod.MAX_WORDS_PER_KIND)
                        return self.set_error("spellbook '{s}' declares more than {d} {s} words", .{ name, spell_mod.MAX_WORDS_PER_KIND, directive });
                    try words.append(.{ .kind = kind, .name = word_name });
                    if (self.current.tag != .comma) break;
                    try self.advance();
                }
                if (count == 0) return self.set_error("spellbook '{s}' declares no {s} words", .{ name, directive });
            } else if (std.mem.eql(u8, directive, "spell")) {
                try self.count_item(.spells, spells.items.len + 1, self.current);
                const spell_name = (try self.expect(.identifier)).slice;
                _ = try self.expect(.colon);
                const power = (try self.expect(.identifier)).slice;
                if (self.current.tag == .comma) try self.advance();
                const element = (try self.expect(.identifier)).slice;
                if (self.current.tag == .comma) try self.advance();
                const form = (try self.expect(.identifier)).slice;
                if (self.current.tag == .comma)
                    return self.set_error("spell '{s}' takes exactly three words: a power, an element, and a form", .{spell_name});
                for (spells.items) |prior| {
                    if (std.mem.eql(u8, prior.name, spell_name))
                        return self.set_error("spellbook '{s}' declares spell '{s}' twice", .{ name, spell_name });
                }
                for (words.items) |prior| {
                    if (std.mem.eql(u8, prior.name, spell_name))
                        return self.set_error("spell '{s}' reuses the word '{s}'", .{ spell_name, spell_name });
                }
                try spells.append(.{ .name = spell_name, .power = power, .element = element, .form = form });
            } else return self.set_error("unknown spellbook directive '{s}'; expected 'power', 'element', 'form', or 'spell'", .{directive});
        }
        _ = try self.expect(.dedent);
        if (words.items.len == 0) return self.set_error("spellbook '{s}' declares no words", .{name});
        if (spells.items.len == 0) return self.set_error("spellbook '{s}' declares no spells", .{name});
        if (spells.items.len > spell_mod.MAX_SPELLS)
            return self.set_error("spellbook '{s}' declares more than {d} spells", .{ name, spell_mod.MAX_SPELLS });
        for (spells.items, 0..) |source, si| {
            const rows = [_]struct { kind: spell_mod.Kind, word: []const u8 }{
                .{ .kind = .power, .word = source.power },
                .{ .kind = .element, .word = source.element },
                .{ .kind = .form, .word = source.form },
            };
            for (rows) |row| {
                const found = spell_word_kind(words.items, row.word) orelse
                    return self.set_error("spell '{s}' names '{s}', which is not a word of spellbook '{s}'", .{ source.name, row.word, name });
                if (found != row.kind)
                    return self.set_error("spell '{s}' puts '{s}' in the {s} slot, but '{s}' is a word of another kind", .{ source.name, row.word, row.kind.label(), row.word });
            }
            for (spells.items[0..si]) |prior| {
                if (std.mem.eql(u8, prior.power, source.power) and std.mem.eql(u8, prior.element, source.element) and std.mem.eql(u8, prior.form, source.form))
                    return self.set_error("spell '{s}' uses the same three words as spell '{s}'", .{ source.name, prior.name });
            }
        }
        return .{ .name = name, .words = try words.toOwnedSlice(), .spells = try spells.toOwnedSlice() };
    }

    fn spell_word_kind(words: []const SpellWordDecl, name: []const u8) ?spell_mod.Kind {
        for (words) |word| if (std.mem.eql(u8, word.name, name)) return word.kind;
        return null;
    }

    /// Parses `decision <Name>:`: an actor, a cue, trigger lines, and scored options (P44-05).
    /// A malformed line names the decision or option that owns it, so a misplaced score reports
    /// where it went wrong rather than at the end of the block.
    fn parse_decision_decl(self: *Parser) !DecisionDecl {
        try self.advance(); // decision
        const name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);
        var actor: ?[]const u8 = null;
        var cue: ?[]const u8 = null;
        var clauses = std.array_list.Managed(DecisionClauseDecl).init(self.allocator);
        var options = std.array_list.Managed(DecisionOptionDecl).init(self.allocator);
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            // Directives are matched by text, as agendas are: `unless` is a keyword token.
            const directive = self.current.slice;
            try self.advance();
            if (std.mem.eql(u8, directive, "actor")) {
                if (actor != null) return self.set_error("decision '{s}' declares actor twice", .{name});
                actor = (try self.expect(.identifier)).slice;
            } else if (std.mem.eql(u8, directive, "fires")) {
                if (cue != null) return self.set_error("decision '{s}' declares fires twice", .{name});
                cue = (try self.expect(.identifier)).slice;
            } else if (std.mem.eql(u8, directive, "requires") or std.mem.eql(u8, directive, "unless")) {
                try clauses.append(.{
                    .pattern = try self.decision_clause("decision", name),
                    .negated = std.mem.eql(u8, directive, "unless"),
                });
                if (clauses.items.len > decision_mod.MAX_CLAUSES)
                    return self.set_error("decision '{s}' has more than {d} trigger lines", .{ name, decision_mod.MAX_CLAUSES });
            } else if (std.mem.eql(u8, directive, "option")) {
                try self.count_item(.options, options.items.len + 1, self.current);
                const option_name = (try self.expect(.identifier)).slice;
                for (options.items) |prior| {
                    if (std.mem.eql(u8, prior.name, option_name))
                        return self.set_error("decision '{s}' declares option '{s}' twice", .{ name, option_name });
                }
                _ = try self.expect(.colon);
                _ = try self.expect(.indent);
                var picks = std.array_list.Managed(DecisionPickDecl).init(self.allocator);
                while (self.current.tag != .dedent and self.current.tag != .eof) {
                    const line = self.current.slice;
                    if (self.current.tag != .identifier or !(std.mem.eql(u8, line, "picks") or std.mem.eql(u8, line, "drops")))
                        return self.set_error("option '{s}' expects a 'picks' or 'drops' line, found '{s}'", .{ option_name, line });
                    try self.advance();
                    const points = try self.take_u32();
                    if (points == 0 or points > decision_mod.MAX_POINTS)
                        return self.set_error("option '{s}' scores {d}; use 1 to {d}", .{ option_name, points, decision_mod.MAX_POINTS });
                    // `when` and `unless` are keyword tokens, so match the text, not the tag.
                    const modifier = self.current.slice;
                    if (!(std.mem.eql(u8, modifier, "when") or std.mem.eql(u8, modifier, "unless")))
                        return self.set_error("option '{s}' needs 'when' or 'unless' after its points", .{option_name});
                    const negated = std.mem.eql(u8, modifier, "unless");
                    try self.advance();
                    const signed: i32 = if (std.mem.eql(u8, line, "drops")) -@as(i32, @intCast(points)) else @intCast(points);
                    try picks.append(.{
                        .points = signed,
                        .pattern = try self.decision_clause("option", option_name),
                        .negated = negated,
                    });
                    if (picks.items.len > decision_mod.MAX_PICKS)
                        return self.set_error("option '{s}' scores more than {d} lines", .{ option_name, decision_mod.MAX_PICKS });
                }
                _ = try self.expect(.dedent);
                if (picks.items.len == 0) return self.set_error("option '{s}' scores no lines", .{option_name});
                try options.append(.{ .name = option_name, .picks = try picks.toOwnedSlice() });
            } else return self.set_error("unknown decision directive '{s}'; expected 'actor', 'fires', 'requires', 'unless', or 'option'", .{directive});
        }
        _ = try self.expect(.dedent);
        if (clauses.items.len == 0)
            return self.set_error("decision '{s}' needs at least one 'requires' or 'unless' line", .{name});
        if (options.items.len == 0 or options.items.len > decision_mod.MAX_OPTIONS)
            return self.set_error("decision '{s}' needs between 1 and {d} options", .{ name, decision_mod.MAX_OPTIONS });
        return .{
            .name = name,
            .actor = actor orelse return self.set_error("decision '{s}' needs an actor", .{name}),
            .cue = cue orelse return self.set_error("decision '{s}' needs a cue, as 'fires <Name>'", .{name}),
            .clauses = try clauses.toOwnedSlice(),
            .options = try options.toOwnedSlice(),
        };
    }

    /// Parses `dilemma <Name>:` (P45-03). Tier lines name the axis they lean toward, so the
    /// block reads from the axis to the counter-axis; a missing tier is an error here, so no
    /// weighing can fall silent.
    fn parse_dilemma_decl(self: *Parser) !DilemmaDecl {
        try self.advance(); // dilemma
        const name_tok = try self.expect(.identifier);
        const name = name_tok.slice;
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);
        var actor: ?[]const u8 = null;
        var cue: ?[]const u8 = null;
        var axis: ?[]const u8 = null;
        var counter: ?[]const u8 = null;
        var clauses = std.array_list.Managed(DecisionClauseDecl).init(self.allocator);
        var leans = std.array_list.Managed(DilemmaLeanDecl).init(self.allocator);
        var drifts = std.array_list.Managed(DilemmaDriftDecl).init(self.allocator);
        var appeals = std.array_list.Managed(DilemmaAppealDecl).init(self.allocator);
        const TierLine = struct { strength: enum { strong, moderate, neutral }, toward: []const u8, response: DilemmaResponseDecl, at: Token };
        var tiers = std.array_list.Managed(TierLine).init(self.allocator);
        // Where each lean names its axis, so a wrong name is reported on its own line.
        var lean_at = std.array_list.Managed(Token).init(self.allocator);
        var tier_bounds: ?[2]u8 = null;
        var drift_cap: ?u8 = null;
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            // Directives are matched by text: `unless` and `when` are keyword tokens.
            const directive_tok = self.current;
            const directive = directive_tok.slice;
            try self.advance();
            if (std.mem.eql(u8, directive, "actor")) {
                if (actor != null) return self.dilemma_fail(self.current, name, &.{"declares actor twice"});
                actor = (try self.expect(.identifier)).slice;
            } else if (std.mem.eql(u8, directive, "fires")) {
                if (cue != null) return self.dilemma_fail(self.current, name, &.{"declares fires twice"});
                cue = (try self.expect(.identifier)).slice;
            } else if (std.mem.eql(u8, directive, "requires") or std.mem.eql(u8, directive, "unless")) {
                try clauses.append(.{
                    .pattern = try self.decision_clause("dilemma", name),
                    .negated = std.mem.eql(u8, directive, "unless"),
                });
                if (clauses.items.len > dilemma_mod.MAX_CLAUSES)
                    return self.dilemma_fail(self.current, name, &.{std.fmt.comptimePrint("has more than {d} trigger lines", .{dilemma_mod.MAX_CLAUSES})});
            } else if (std.mem.eql(u8, directive, "weighs")) {
                if (axis != null) return self.dilemma_fail(self.current, name, &.{"declares weighs twice"});
                axis = (try self.expect(.identifier)).slice;
                if (!std.mem.eql(u8, self.current.slice, "against"))
                    return self.dilemma_fail(self.current, name, &.{"expects 'weighs <Axis> against <Axis>'"});
                try self.advance();
                counter = (try self.expect(.identifier)).slice;
            } else if (std.mem.eql(u8, directive, "leans")) {
                const points = try self.take_u32();
                if (points == 0 or points > dilemma_mod.MAX_LEAN)
                    return self.dilemma_fail(self.current, name, &.{std.fmt.comptimePrint("leans more than {d} or less than 1; use 1 to {d}", .{ dilemma_mod.MAX_LEAN, dilemma_mod.MAX_LEAN })});
                if (!std.mem.eql(u8, self.current.slice, "toward"))
                    return self.dilemma_fail(self.current, name, &.{"expects 'leans <N> toward <Axis> when <Fact>'"});
                try self.advance();
                const toward_tok = try self.expect(.identifier);
                try lean_at.append(toward_tok);
                const toward = toward_tok.slice;
                const modifier = self.current.slice;
                if (!(std.mem.eql(u8, modifier, "when") or std.mem.eql(u8, modifier, "unless")))
                    return self.dilemma_fail(self.current, name, &.{ "needs 'when' or 'unless' after 'toward ", toward, "'" });
                try self.advance();
                try leans.append(.{
                    .points = points,
                    .toward = toward,
                    .pattern = try self.decision_clause("dilemma", name),
                    .negated = std.mem.eql(u8, modifier, "unless"),
                });
                if (leans.items.len > dilemma_mod.MAX_LEANS)
                    return self.dilemma_fail(self.current, name, &.{std.fmt.comptimePrint("has more than {d} lean lines", .{dilemma_mod.MAX_LEANS})});
            } else if (std.mem.eql(u8, directive, "appeals")) {
                const points = try self.take_u32();
                if (points == 0 or points > dilemma_mod.MAX_APPEAL)
                    return self.dilemma_fail(self.current, name, &.{std.fmt.comptimePrint("appeals more than {d} or less than 1; use 1 to {d}", .{ dilemma_mod.MAX_APPEAL, dilemma_mod.MAX_APPEAL })});
                if (!std.mem.eql(u8, self.current.slice, "to"))
                    return self.dilemma_fail(self.current, name, &.{"expects 'appeals <N> to <Axis>'"});
                try self.advance();
                const axis_tok = try self.expect(.identifier);
                for (appeals.items) |prior| {
                    if (std.mem.eql(u8, prior.axis, axis_tok.slice))
                        return self.dilemma_fail(axis_tok, name, &.{ "declares an appeal to '", axis_tok.slice, "' twice" });
                }
                var toward = axis_tok.slice;
                var toward_at = axis_tok;
                if (std.mem.eql(u8, self.current.slice, "toward") and self.current.line == axis_tok.line) {
                    try self.advance();
                    toward_at = try self.expect(.identifier);
                    toward = toward_at.slice;
                }
                try appeals.append(.{ .points = points, .axis = axis_tok.slice, .toward = toward, .at = toward_at });
                if (appeals.items.len > dilemma_mod.MAX_APPEALS)
                    return self.dilemma_fail(axis_tok, name, &.{std.fmt.comptimePrint("has more than {d} appeal lines", .{dilemma_mod.MAX_APPEALS})});
            } else if (std.mem.eql(u8, directive, "drifts")) {
                const points = try self.take_u32();
                if (points == 0 or points > dilemma_mod.MAX_DRIFT)
                    return self.dilemma_fail(self.current, name, &.{std.fmt.comptimePrint("drifts more than {d} or less than 1; use 1 to {d}", .{ dilemma_mod.MAX_DRIFT, dilemma_mod.MAX_DRIFT })});
                var away = false;
                if (std.mem.eql(u8, self.current.slice, "away")) {
                    try self.advance();
                    if (!std.mem.eql(u8, self.current.slice, "from"))
                        return self.dilemma_fail(self.current, name, &.{"expects 'drifts <N> toward <Axis>' or 'drifts <N> away from <Axis>'"});
                    away = true;
                } else if (!std.mem.eql(u8, self.current.slice, "toward"))
                    return self.dilemma_fail(self.current, name, &.{"expects 'drifts <N> toward <Axis>' or 'drifts <N> away from <Axis>'"});
                try self.advance();
                const drift_axis = (try self.expect(.identifier)).slice;
                const modifier = self.current.slice;
                if (!(std.mem.eql(u8, modifier, "when") or std.mem.eql(u8, modifier, "unless")))
                    return self.dilemma_fail(self.current, name, &.{ "needs 'when' or 'unless' after the axis '", drift_axis, "'" });
                try self.advance();
                try drifts.append(.{
                    .points = points,
                    .away = away,
                    .axis = drift_axis,
                    .pattern = try self.decision_clause("dilemma", name),
                    .negated = std.mem.eql(u8, modifier, "unless"),
                });
                if (drifts.items.len > dilemma_mod.MAX_DRIFTS)
                    return self.dilemma_fail(self.current, name, &.{std.fmt.comptimePrint("has more than {d} drift lines", .{dilemma_mod.MAX_DRIFTS})});
            } else if (std.mem.eql(u8, directive, "tiers")) {
                // `tiers 8 and 4`: the strong and moderate boundaries, mirrored (D-183).
                if (tier_bounds != null) return self.dilemma_fail(directive_tok, name, &.{"declares tiers twice"});
                const strong_tok = self.current;
                const strong = try self.take_u32();
                if (self.current.tag != .kw_and) return self.dilemma_fail(self.current, name, &.{"expects 'tiers <strong> and <moderate>', such as 'tiers 7 and 3'"});
                try self.advance();
                const moderate = try self.take_u32();
                if (moderate == 0 or moderate >= strong or strong > dilemma_mod.MAX_TIER_AT)
                    return self.dilemma_fail(strong_tok, name, &.{std.fmt.comptimePrint("has tiers out of order or out of range; the strong boundary comes first and is at most {d}, and the moderate one is from 1 and below it", .{dilemma_mod.MAX_TIER_AT})});
                tier_bounds = .{ @intCast(strong), @intCast(moderate) };
            } else if (std.mem.eql(u8, directive, "drift")) {
                // `drift cap 3`: the steps this dilemma may move each axis (D-183).
                if (!(self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "cap")))
                    return self.dilemma_fail(self.current, name, &.{"expects 'drift cap <N>'"});
                try self.advance();
                if (drift_cap != null) return self.dilemma_fail(directive_tok, name, &.{"declares its drift cap twice"});
                const cap_tok = self.current;
                const n = try self.take_u32();
                if (n == 0 or n > dilemma_mod.MAX_DRIFT_CAP)
                    return self.dilemma_fail(cap_tok, name, &.{std.fmt.comptimePrint("has a drift cap outside 1 to {d} steps", .{dilemma_mod.MAX_DRIFT_CAP})});
                drift_cap = @intCast(n);
            } else if (std.mem.eql(u8, directive, "strong") or std.mem.eql(u8, directive, "moderate") or std.mem.eql(u8, directive, "neutral")) {
                const neutral = std.mem.eql(u8, directive, "neutral");
                const toward = if (neutral) "" else (try self.expect(.identifier)).slice;
                _ = try self.expect(.colon);
                const line = (try self.expect(.string_literal)).slice;
                _ = try self.expect(.arrow);
                const action = (try self.expect(.identifier)).slice;
                try tiers.append(.{
                    .strength = if (neutral) .neutral else if (std.mem.eql(u8, directive, "strong")) .strong else .moderate,
                    .toward = toward,
                    .response = .{ .line = line, .action = action },
                    .at = directive_tok,
                });
            } else return self.set_error("unknown dilemma directive '{s}'; expected 'actor', 'fires', 'requires', 'unless', 'weighs', 'leans', 'appeals', 'drifts', 'tiers', 'drift cap', 'strong', 'moderate', or 'neutral'", .{directive});
        }
        _ = try self.expect(.dedent);
        if (clauses.items.len == 0)
            return self.dilemma_fail(self.current, name, &.{"needs at least one 'requires' or 'unless' line"});
        const axis_name = axis orelse return self.dilemma_fail(name_tok, name, &.{"needs 'weighs <Axis> against <Axis>'"});
        const counter_name = counter.?;
        if (std.mem.eql(u8, axis_name, counter_name))
            return self.dilemma_fail(name_tok, name, &.{ "weighs '", axis_name, "' against itself" });
        for (appeals.items) |appeal| {
            if (!std.mem.eql(u8, appeal.toward, axis_name) and !std.mem.eql(u8, appeal.toward, counter_name))
                return self.dilemma_fail(appeal.at, name, &.{ "appeals toward '", appeal.toward, "', which it does not weigh; add 'toward <Axis>' naming a weighed axis" });
        }
        for (leans.items, lean_at.items) |lean, at| {
            if (!std.mem.eql(u8, lean.toward, axis_name) and !std.mem.eql(u8, lean.toward, counter_name))
                return self.dilemma_fail(at, name, &.{ "leans toward '", lean.toward, "', which it does not weigh" });
        }

        // Order the tiers from the axis to the counter-axis, refusing a repeat or a gap.
        var responses: [dilemma_mod.TIER_COUNT]?DilemmaResponseDecl = @splat(null);
        for (tiers.items) |tier| {
            const index: usize = switch (tier.strength) {
                .neutral => @backingInt(dilemma_mod.Tier.neutral),
                .strong, .moderate => blk: {
                    const toward_axis = std.mem.eql(u8, tier.toward, axis_name);
                    if (!toward_axis and !std.mem.eql(u8, tier.toward, counter_name))
                        return self.dilemma_fail(tier.at, name, &.{ "has a tier toward '", tier.toward, "', which it does not weigh" });
                    const t: dilemma_mod.Tier = if (tier.strength == .strong)
                        (if (toward_axis) .strong_axis else .strong_counter)
                    else
                        (if (toward_axis) .moderate_axis else .moderate_counter);
                    break :blk @backingInt(t);
                },
            };
            if (responses[index] != null)
                return self.dilemma_fail(tier.at, name, &.{ "gives the ", tier_strength(index), tier_axis(index, axis_name, counter_name), " tier twice" });
            responses[index] = tier.response;
        }
        var ordered: [dilemma_mod.TIER_COUNT]DilemmaResponseDecl = undefined;
        for (responses, 0..) |response, i| {
            ordered[i] = response orelse
                return self.dilemma_fail(name_tok, name, &.{ "has no line for the ", tier_strength(i), tier_axis(i, axis_name, counter_name), " tier" });
        }
        return .{
            .name = name,
            .actor = actor orelse return self.dilemma_fail(name_tok, name, &.{"needs an actor"}),
            .cue = cue orelse return self.dilemma_fail(name_tok, name, &.{"needs a cue, as 'fires <Name>'"}),
            .clauses = try clauses.toOwnedSlice(),
            .axis = axis_name,
            .counter = counter_name,
            .leans = try leans.toOwnedSlice(),
            .drifts = try drifts.toOwnedSlice(),
            .appeals = try appeals.toOwnedSlice(),
            .responses = ordered,
            .tiers = tier_bounds,
            .drift_cap = drift_cap,
        };
    }

    /// A tier as the script writes it, in two pieces: `strong ` + `Justice`, or `neutral` + ``.
    fn tier_strength(index: usize) []const u8 {
        return switch (index) {
            0, 4 => "strong ",
            1, 3 => "moderate ",
            else => "neutral",
        };
    }

    fn tier_axis(index: usize, axis: []const u8, counter: []const u8) []const u8 {
        return switch (index) {
            0, 1 => axis,
            3, 4 => counter,
            else => "",
        };
    }

    /// One message shape for every dilemma diagnostic, so the block adds one formatting
    /// instantiation to the browser module rather than one per message (D-141).
    fn dilemma_fail(self: *Parser, tok: Token, name: []const u8, pieces: []const []const u8) error{UnexpectedToken} {
        var detail: [160]u8 = undefined;
        var len: usize = 0;
        for (pieces) |piece| {
            const n = @min(piece.len, detail.len - len);
            @memcpy(detail[len..][0..n], piece[0..n]);
            len += n;
        }
        return self.error_at(tok, "dilemma '{s}' {s}", .{ name, detail[0..len] });
    }

    /// Finishes `red lines <Character>: <Option>, ...` once `red lines` has been read. The options
    /// run to the end of the line.
    /// Parses one art line or block whose first word, `start`, is already consumed. Returns false
    /// when `start` does not begin one, leaving the token stream untouched.
    fn art_declaration(self: *Parser, ast: *AST, start: Token) !bool {
        const same_line = self.current.line == start.line;
        const word = start.slice;
        if (std.mem.eql(u8, word, "palette") and same_line and self.current.tag == .colon) {
            try self.parse_palette(start);
            return true;
        }
        if (std.mem.eql(u8, word, "backdrop") and same_line and self.current.tag == .colon) {
            try self.advance();
            if (ast.scene_defs.items.len == 0) return self.error_at(start, "a backdrop belongs to a scene; put it under a 'scene:' line", .{});
            const scene = &ast.scene_defs.items[ast.scene_defs.items.len - 1];
            if (scene.backdrop != null) return self.error_at(start, "scene '{s}' declares a backdrop twice", .{scene.name});
            scene.backdrop = try self.take_image_name();
            return true;
        }
        const named = same_line and (self.current.tag == .identifier or self.current.tag == .string_literal);
        if (std.mem.eql(u8, word, "image") and named) {
            try self.parse_image(start);
            return true;
        }
        if (std.mem.eql(u8, word, "sprite") and named) {
            try self.parse_sprite(start);
            return true;
        }
        if (std.mem.eql(u8, word, "look") and named) {
            try self.parse_look();
            return true;
        }
        if (std.mem.eql(u8, word, "part") and named) {
            try self.parse_part();
            return true;
        }
        if (std.mem.eql(u8, word, "area") and named) {
            try self.parse_area();
            return true;
        }
        return false;
    }

    /// An image name is one word or a quoted name, so `frames` can follow it on the line.
    fn take_image_name(self: *Parser) !Token {
        if (self.current.tag == .string_literal) return self.expect(.string_literal);
        return self.expect(.identifier);
    }

    fn parse_palette(self: *Parser, start: Token) !void {
        if (self.palette_at != null) return self.error_at(start, "the palette is declared twice; a game has one palette (D-152)", .{});
        self.palette_at = start;
        try self.advance(); // colon
        _ = try self.expect(.indent);
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            const code = self.current;
            if (code.tag != .string_literal) return self.set_error("a palette line starts with a quoted colour code, such as \"b\"", .{});
            try self.advance();
            if (self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "transparent") and self.current.line == code.line) {
                try self.advance();
                try self.palette_src.append(self.allocator, .{ .code = code, .colour = null });
                continue;
            }
            var rgb: [3]u8 = undefined;
            for (&rgb) |*channel| {
                const tok = self.current;
                if (tok.tag != .number or tok.line != code.line)
                    return self.error_at(code, "palette code \"{s}\" needs 'transparent' or three numbers from 0 to 255 for red, green, and blue", .{code.slice});
                const value = std.fmt.parseInt(u32, tok.slice, 10) catch 256;
                if (value > 255) return self.error_at(tok, "palette code \"{s}\" has a colour value of {s}; each of red, green, and blue is 0 to 255", .{ code.slice, tok.slice });
                channel.* = @intCast(value);
                try self.advance();
            }
            try self.palette_src.append(self.allocator, .{ .code = code, .colour = .{ .r = rgb[0], .g = rgb[1], .b = rgb[2] } });
        }
        _ = try self.expect(.dedent);
    }

    fn parse_image(self: *Parser, start: Token) !void {
        const name_tok = try self.take_image_name();
        var src = ImageSource{ .name = name_tok.slice, .at = name_tok, .rows = &.{} };
        try self.image_from(&src, start);
        if (self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "frames") and self.current.line == start.line) {
            src.frames_at = self.current;
            try self.advance();
            // `12x20` lexes as the number 12 and the word x20; `12 x 20` is accepted too.
            src.frame_width = try self.take_u32();
            const x_tok = self.current;
            if (x_tok.tag != .identifier or x_tok.slice.len == 0 or x_tok.slice[0] != 'x')
                return self.error_at(x_tok, "image '{s}' expects 'frames <width>x<height>', such as 'frames 16x24'", .{src.name});
            try self.advance();
            if (x_tok.slice.len > 1) {
                src.frame_height = std.fmt.parseInt(u32, x_tok.slice[1..], 10) catch
                    return self.error_at(x_tok, "image '{s}' expects 'frames <width>x<height>', such as 'frames 16x24'", .{src.name});
            } else src.frame_height = try self.take_u32();
        }
        try self.image_from(&src, start);
        if (src.file != null) {
            for (self.image_srcs.items) |prior| {
                if (std.mem.eql(u8, prior.name, src.name)) return self.error_at(name_tok, "image '{s}' is declared twice", .{src.name});
            }
            try self.image_srcs.append(self.allocator, src);
            return;
        }
        if (self.current.tag != .colon) return self.error_at(self.current, "image '{s}' expects ':' and its pixel rows below it, or 'from \"<file>.png\"'", .{src.name});
        try self.advance();
        if (self.current.tag != .indent) return self.error_at(name_tok, "image '{s}' has no pixel rows; list them indented below it, one quoted row per line", .{src.name});
        try self.advance();
        var rows = std.array_list.Managed(Token).init(self.allocator);
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            if (self.current.tag != .string_literal) return self.set_error("image '{s}' rows are quoted strings of palette codes", .{src.name});
            try rows.append(self.current);
            try self.advance();
        }
        _ = try self.expect(.dedent);
        src.rows = try rows.toOwnedSlice();
        for (self.image_srcs.items) |prior| {
            if (std.mem.eql(u8, prior.name, src.name)) return self.error_at(name_tok, "image '{s}' is declared twice", .{src.name});
        }
        try self.image_srcs.append(self.allocator, src);
    }

    /// `from "<file>"` on the image's line, before or after `frames`.
    fn image_from(self: *Parser, src: *ImageSource, start: Token) !void {
        if (src.file != null) return;
        if (!(self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "from") and self.current.line == start.line)) return;
        try self.advance();
        if (self.current.tag != .string_literal) return self.error_at(self.current, "image '{s}' expects a quoted file name after 'from'", .{src.name});
        src.file = self.current;
        try self.advance();
    }

    /// Reads and decodes one `image X from "file"`. With a declared palette (`rule`, its colours
    /// after the transparent entry), every opaque pixel must be one of them (D-166).
    fn image_from_file(self: *Parser, src: ImageSource, rule: ?[]const image_mod.Colour) !struct { width: usize, height: usize, pixels: []image_mod.Pixel } {
        const file_tok = src.file.?;
        const path = file_tok.slice;
        // The browser module has no file source and carries no PNG decoder: the runtime never
        // decodes PNG (D-151), so this path is compiled out of freestanding builds.
        const no_files = comptime @import("builtin").os.tag == .freestanding;
        const files = (if (no_files) null else self.files) orelse return self.error_at(file_tok, "image '{s}' reads \"{s}\", which only a compile from the command line can do; 'bespoke import' writes its rows into the script instead", .{ src.name, path });
        const bytes = files.read(files.context, self.allocator, path) catch |err|
            return self.error_at(file_tok, "image '{s}' cannot read \"{s}\" ({s})", .{ src.name, path, @errorName(err) });
        const rgba = png_mod.decode(self.allocator, bytes) catch |err| {
            const why: []const u8 = switch (err) {
                error.PngSignature => "it is not a PNG",
                error.PngChecksum, error.PngTruncated, error.PngCorrupt => "it is damaged",
                error.PngTooLarge => std.fmt.comptimePrint("it is larger than a sheet may be ({d} on a side, {d} pixels)", .{ image_mod.MAX_SHEET_SIDE, image_mod.MAX_SHEET_PIXELS }),
                error.PngInterlaced => "it is interlaced; save it without interlacing",
                error.PngUnsupported => "it uses 16-bit channels or a chunk this engine does not read; save it with 8-bit channels",
                error.PngMissingPalette => "it is indexed but has no palette",
                error.OutOfMemory => return error.OutOfMemory,
            };
            return self.error_at(file_tok, "image '{s}' cannot use \"{s}\": {s}", .{ src.name, path, why });
        };
        var where = art_import.Where{};
        const pixels = art_import.to_pixels(self.allocator, rgba, rule, &where) catch |err| switch (err) {
            error.PartialTransparency => return self.error_at(file_tok, "image '{s}': pixel ({d}, {d}) of \"{s}\" is partly transparent; art pixels are opaque or fully transparent (D-166)", .{ src.name, where.x, where.y, path }),
            error.NotInPalette => {
                const c = rgba.pixels[(@as(usize, where.y) * rgba.width + where.x) * 4 ..][0..3];
                return self.error_at(file_tok, "image '{s}': pixel ({d}, {d}) of \"{s}\" is {d} {d} {d}, which the script's 'palette:' does not hold; add it or recolour the pixel (D-166)", .{ src.name, where.x, where.y, path, c[0], c[1], c[2] });
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        return .{ .width = rgba.width, .height = rgba.height, .pixels = pixels };
    }

    /// `area <Prop>: x y w h`, a rectangle in art pixels on the prop's scene (P46-05, D-158).
    fn parse_area(self: *Parser) !void {
        const at = self.current;
        const target = try self.parse_name();
        if (self.current.tag != .colon) return self.error_at(self.current, "area '{s}' expects ':' and x, y, width, and height in art pixels", .{target});
        try self.advance();
        var v: [4]u32 = undefined;
        for (&v) |*n| {
            if (self.current.tag != .number or self.current.line != at.line)
                return self.error_at(at, "area '{s}' expects ':' and x, y, width, and height in art pixels", .{target});
            n.* = try self.take_u32();
        }
        if (v[2] == 0 or v[3] == 0 or v[0] + v[2] > image_mod.ART_WIDTH or v[1] + v[3] > image_mod.ART_HEIGHT)
            return self.error_at(at, "area '{s}' is {d}x{d} at ({d}, {d}); an area is at least 1x1 and inside the {d}x{d} art", .{ target, v[2], v[3], v[0], v[1], image_mod.ART_WIDTH, image_mod.ART_HEIGHT });
        for (self.area_srcs.items) |prior| {
            if (std.mem.eql(u8, prior.target, target)) return self.error_at(at, "'{s}' has two areas; declare one", .{target});
        }
        try self.area_srcs.append(self.allocator, .{ .target = target, .x = @intCast(v[0]), .y = @intCast(v[1]), .w = @intCast(v[2]), .h = @intCast(v[3]), .at = at });
    }

    fn parse_sprite(self: *Parser, start: Token) !void {
        _ = start;
        const at = self.current;
        const target = try self.parse_name();
        if (self.current.tag != .colon) return self.error_at(self.current, "sprite '{s}' expects ':' and the image it is drawn from", .{target});
        try self.advance();
        var src = SpriteSource{ .target = target, .at = at, .image = try self.take_image_name() };
        src.animations = try self.parse_animations("sprite", target);
        for (self.sprite_srcs.items) |prior| {
            if (std.mem.eql(u8, prior.target, target)) return self.error_at(at, "'{s}' has two sprites; declare one", .{target});
        }
        try self.sprite_srcs.append(self.allocator, src);
    }

    /// The indented `idle:` and `walk <dir>:` lines under a sprite or look (P46-03, P48-11).
    fn parse_animations(self: *Parser, what: []const u8, owner: []const u8) ![image_mod.ANIM_COUNT][]const StepSource {
        var animations: [image_mod.ANIM_COUNT][]const StepSource = @splat(@as([]const StepSource, &.{}));
        if (self.current.tag != .indent) return animations;
        try self.advance();
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            const anim_tok = self.current;
            try self.advance();
            const anim: image_mod.Anim = if (anim_tok.tag == .identifier and std.mem.eql(u8, anim_tok.slice, "idle"))
                .idle
            else if (anim_tok.tag == .kw_walk) blk: {
                const dir = self.current;
                try self.advance();
                const which: ?image_mod.Anim = if (std.mem.eql(u8, dir.slice, "up")) .walk_up else if (std.mem.eql(u8, dir.slice, "down")) .walk_down else if (std.mem.eql(u8, dir.slice, "left")) .walk_left else if (std.mem.eql(u8, dir.slice, "right")) .walk_right else null;
                break :blk which orelse return self.error_at(dir, "{s} '{s}' walks up, down, left, or right, not '{s}'", .{ what, owner, dir.slice });
            } else return self.error_at(anim_tok, "{s} '{s}' has animations 'idle' and 'walk up', 'walk down', 'walk left', 'walk right', not '{s}'", .{ what, owner, anim_tok.slice });
            const slot = &animations[@intFromEnum(anim)];
            if (slot.len > 0) return self.error_at(anim_tok, "{s} '{s}' declares the '{s}' animation twice", .{ what, owner, @tagName(anim) });
            _ = try self.expect(.colon);
            var steps = std.array_list.Managed(StepSource).init(self.allocator);
            while (true) {
                const frame_tok = self.current;
                const frame = try self.take_u32();
                // Six display frames is ten frames a second (D-152).
                var duration: u32 = 6;
                if (self.current.tag == .kw_for) {
                    try self.advance();
                    const dur_tok = self.current;
                    duration = try self.take_u32();
                    if (duration == 0 or duration > image_mod.MAX_DURATION)
                        return self.error_at(dur_tok, "{s} '{s}' shows a frame for {d} display frames; use 1 to {d}", .{ what, owner, duration, image_mod.MAX_DURATION });
                }
                try steps.append(.{ .frame = frame, .duration = duration, .at = frame_tok });
                if (steps.items.len > image_mod.MAX_STEPS)
                    return self.error_at(frame_tok, "{s} '{s}' has more than {d} steps in one animation", .{ what, owner, image_mod.MAX_STEPS });
                if (self.current.tag != .comma) break;
                try self.advance();
            }
            slot.* = try steps.toOwnedSlice();
        }
        _ = try self.expect(.dedent);
        return animations;
    }

    /// `look <Name>: <Image>` and its animations (P48-11, D-181).
    fn parse_look(self: *Parser) !void {
        const at = self.current;
        const name = try self.parse_name();
        if (self.current.tag != .colon) return self.error_at(self.current, "look '{s}' expects ':' and the image it shows", .{name});
        try self.advance();
        var src = LookSource{ .name = name, .at = at, .image = try self.take_image_name() };
        src.animations = try self.parse_animations("look", name);
        for (self.look_srcs.items) |prior| {
            if (std.mem.eql(u8, prior.name, name)) return self.error_at(at, "look '{s}' is declared twice", .{name});
        }
        try self.look_srcs.append(self.allocator, src);
    }

    /// `part <Part> of <Host> at <dx> <dy>`, the offset in art pixels (P48-11, D-181).
    fn parse_part(self: *Parser) !void {
        const at = self.current;
        // One word each: `parse_name` would read `Clapper of Bell` as one multi-word name.
        const part = (try self.expect(.identifier)).slice;
        if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.slice, "of"))
            return self.error_at(self.current, "part '{s}' expects 'of <host> at <x> <y>'", .{part});
        try self.advance();
        const host = (try self.expect(.identifier)).slice;
        if (self.current.tag != .identifier or !std.mem.eql(u8, self.current.slice, "at"))
            return self.error_at(self.current, "part '{s}' expects 'at <x> <y>' after its host", .{part});
        try self.advance();
        var offset: [2]i16 = undefined;
        for (&offset) |*v| {
            // `-18` is one number token (the lexer reads a minus before a digit as its sign).
            const tok = try self.expect(.number);
            const n = std.fmt.parseInt(i32, tok.slice, 10) catch return self.error_at(tok, "invalid integer '{s}'", .{tok.slice});
            if (@abs(n) > image_mod.MAX_PART_OFFSET) return self.error_at(tok, "part '{s}' sits at most {d} art pixels from its host", .{ part, image_mod.MAX_PART_OFFSET });
            v.* = @intCast(n);
        }
        if (std.mem.eql(u8, part, host)) return self.error_at(at, "part '{s}' cannot be its own host", .{part});
        for (self.part_srcs.items) |prior| {
            if (std.mem.eql(u8, prior.part, part)) return self.error_at(at, "'{s}' is a part twice; declare one", .{part});
        }
        try self.part_srcs.append(self.allocator, .{ .part = part, .host = host, .dx = offset[0], .dy = offset[1], .at = at });
    }

    fn image_index(self: *Parser, tok: Token, what: []const u8, owner: []const u8) !u16 {
        for (self.image_srcs.items, 0..) |src, i| {
            if (std.mem.eql(u8, src.name, tok.slice)) return @intCast(i);
        }
        var hints = Suggestions{};
        for (self.image_srcs.items) |src| hints.consider(tok.slice, src.name);
        self.suggestion = hints.result();
        return self.error_at(tok, "{s} '{s}' names image '{s}', which is not declared", .{ what, owner, tok.slice });
    }

    /// Turns the art declarations into pixels and bindings, naming the first thing
    /// wrong at its own line. Runs once the whole script is read, so declarations may come in
    /// any order (P46-03, D-155).
    fn count_item(self: *Parser, kind: limits_mod.Kind, value: usize, at: Token) !void {
        try self.counted.append(self.allocator, .{ .kind = kind, .value = value, .at = at });
    }

    /// `limit <name> N` (P48-13, D-183): the name is one of the nine ceilings, and N lies
    /// between its default and its safety cap.
    fn parse_limit(self: *Parser, start: Token) !void {
        const name_tok = self.current;
        try self.advance();
        const kind = limits_mod.find(name_tok.slice) orelse {
            var hints = Suggestions{};
            for (limits_mod.ENTRIES) |entry| hints.consider(name_tok.slice, entry.name);
            self.suggestion = hints.result();
            return self.error_at(name_tok, "there is no limit on '{s}'; a script may raise goals, needs, decisions, options, dilemmas, axes, spells, words, or hints", .{name_tok.slice});
        };
        const entry = limits_mod.ENTRIES[@intFromEnum(kind)];
        const number = self.current;
        if (number.tag != .number or number.line != start.line) return self.error_at(number, "'limit {s}' needs a whole number, such as 'limit {s} {d}'", .{ entry.name, entry.name, entry.default * 2 });
        const value = try self.take_u32();
        if (value < entry.default or value > limits_mod.cap_of(kind))
            return self.error_at(number, "'limit {s}' is {d}; it may raise the default of {d} {s} up to {d}", .{ entry.name, value, entry.default, entry.counts, limits_mod.cap_of(kind) });
        for (self.limit_lines.items) |prior| {
            if (prior.kind == kind) return self.error_at(start, "'limit {s}' is declared twice", .{entry.name});
        }
        try self.limit_lines.append(self.allocator, .{ .kind = kind, .value = value, .at = start });
    }

    /// Every counted item against its limit, in source order of the items, so the first one
    /// past a limit is the one named.
    fn check_limits(self: *Parser) !void {
        var limits = limits_mod.Limits{};
        for (self.limit_lines.items) |line| limits.values[@intFromEnum(line.kind)] = line.value;
        for (self.counted.items) |item| {
            const limit = limits.get(item.kind);
            if (item.value <= limit) continue;
            const entry = limits_mod.ENTRIES[@intFromEnum(item.kind)];
            // Suggest the limit the whole script needs, not just this item, so following the
            // help clears every item of the kind at once.
            var needed = item.value;
            for (self.counted.items) |other| if (other.kind == item.kind) {
                needed = @max(needed, other.value);
            };
            return self.error_at(item.at, "{d} {s} is past the limit of {d}; add 'limit {s} {d}' to raise it, up to {d} (D-183)", .{ item.value, entry.counts, limit, entry.name, needed, limits_mod.cap_of(item.kind) });
        }
    }

    fn resolve_art(self: *Parser, ast: *AST) !void {
        var palette = std.ArrayListUnmanaged(image_mod.Colour).empty;
        var code_width: usize = 0;
        for (self.palette_src.items, 0..) |entry, i| {
            const code = entry.code.slice;
            if (i == 0 and entry.colour != null)
                return self.error_at(entry.code, "the palette's first line is its transparent code, such as '\".\" transparent'; index 0 is never drawn", .{});
            if (i > 0 and entry.colour == null)
                return self.error_at(entry.code, "only the palette's first line is transparent", .{});
            if (code.len == 0 or code.len > 2) return self.error_at(entry.code, "palette code \"{s}\" is one or two characters", .{code});
            for (code) |c| if (c <= ' ' or c > '~' or c == '"') return self.error_at(entry.code, "palette code \"{s}\" uses a character a code cannot hold; use printable characters other than a space", .{code});
            if (i == 0) code_width = code.len else if (code.len != code_width)
                return self.error_at(entry.code, "palette code \"{s}\" is {d} characters wide, but the first code is {d}; every code is the same width", .{ code, code.len, code_width });
            for (self.palette_src.items[0..i]) |prior| if (std.mem.eql(u8, prior.code.slice, code))
                return self.error_at(entry.code, "palette code \"{s}\" is declared twice", .{code});
            if (i == image_mod.MAX_COLOURS) return self.error_at(entry.code, "the palette has more than {d} colours (D-152)", .{image_mod.MAX_COLOURS});
            try palette.append(self.allocator, entry.colour orelse .{ .r = 0, .g = 0, .b = 0 });
        }
        // A declared palette is the style rule PNG colours must follow; a script whose art all
        // comes from files may declare none, and its PNGs keep every colour (D-166).
        const rule: ?[]const image_mod.Colour = if (palette.items.len > 0) palette.items[1..] else null;

        var images = std.array_list.Managed(image_mod.Image).init(self.allocator);
        var total_pixels: usize = 0;
        for (self.image_srcs.items) |src| {
            image_mod.validate_name(src.name) catch return self.error_at(src.at, "image name '{s}' is 1 to {d} printable characters", .{ src.name, image_mod.MAX_NAME });
            const decoded = if (src.file != null) try self.image_from_file(src, rule) else null;
            if (decoded == null and self.palette_src.items.len == 0) return self.error_at(src.at, "image '{s}' needs a 'palette:' declaration for its codes", .{src.name});
            const first = if (decoded == null) src.rows[0] else src.at;
            if (decoded == null and (first.slice.len == 0 or first.slice.len % code_width != 0))
                return self.error_at(first, "image '{s}' has a row of {d} characters, which is not a whole number of {d}-character codes", .{ src.name, first.slice.len, code_width });
            const width = if (decoded) |d| d.width else first.slice.len / code_width;
            const height = if (decoded) |d| d.height else src.rows.len;
            const fw: usize = if (src.frames_at == null) width else src.frame_width;
            const fh: usize = if (src.frames_at == null) height else src.frame_height;
            const size_at = src.frames_at orelse src.at;
            if (width > image_mod.MAX_SHEET_SIDE or height > image_mod.MAX_SHEET_SIDE or width * height > image_mod.MAX_SHEET_PIXELS)
                return self.error_at(src.at, "image '{s}' is {d}x{d}; a sheet is at most {d} on a side and {d} pixels", .{ src.name, width, height, image_mod.MAX_SHEET_SIDE, image_mod.MAX_SHEET_PIXELS });
            total_pixels += width * height;
            if (total_pixels > image_mod.MAX_ART_PIXELS)
                return self.error_at(src.at, "image '{s}' takes the game's art past {d} pixels in all (D-182)", .{ src.name, image_mod.MAX_ART_PIXELS });
            if (fw == 0 or fh == 0 or fw > image_mod.ART_WIDTH or fh > image_mod.ART_HEIGHT)
                return self.error_at(size_at, "image '{s}' has frames of {d}x{d}; a frame is 1 to {d} wide and 1 to {d} tall (D-152)", .{ src.name, fw, fh, image_mod.ART_WIDTH, image_mod.ART_HEIGHT });
            if (width % fw != 0 or height % fh != 0)
                return self.error_at(size_at, "image '{s}' is {d}x{d}, which frames of {d}x{d} do not tile", .{ src.name, width, height, fw, fh });
            const pixels = if (decoded) |d| d.pixels else try self.allocator.alloc(image_mod.Pixel, width * height);
            if (decoded == null) for (src.rows, 0..) |row, y| {
                if (row.slice.len != first.slice.len)
                    return self.error_at(row, "image '{s}' row {d} is {d} characters wide; its first row is {d}", .{ src.name, y + 1, row.slice.len, first.slice.len });
                for (0..width) |x| {
                    const code = row.slice[x * code_width ..][0..code_width];
                    const index = for (self.palette_src.items, 0..) |entry, i| {
                        if (std.mem.eql(u8, entry.code.slice, code)) break i;
                    } else return self.error_at(row, "image '{s}' row {d} uses code \"{s}\", which the palette does not declare", .{ src.name, y + 1, code });
                    pixels[y * width + x] = if (index == 0) image_mod.TRANSPARENT else image_mod.Pixel.opaque_colour(palette.items[index]);
                }
            };
            try images.append(.{
                .name = src.name,
                .width = @intCast(width),
                .height = @intCast(height),
                .frame_width = @intCast(fw),
                .frame_height = @intCast(fh),
                .pixels = pixels,
            });
        }
        if (images.items.len > image_mod.MAX_IMAGES) return self.error_at(self.image_srcs.items[image_mod.MAX_IMAGES].at, "a game has at most {d} images", .{image_mod.MAX_IMAGES});

        var backdrops = std.array_list.Managed(BackdropBinding).init(self.allocator);
        for (ast.scene_defs.items) |scene| {
            const tok = scene.backdrop orelse continue;
            const index = try self.image_index(tok, "scene", scene.name);
            const image = images.items[index];
            if (image.width != image_mod.ART_WIDTH or image.height != image_mod.ART_HEIGHT or image.frame_count() != 1)
                return self.error_at(tok, "backdrop '{s}' of scene '{s}' is {d}x{d}; a backdrop is one {d}x{d} frame (D-152)", .{ tok.slice, scene.name, image.width, image.height, image_mod.ART_WIDTH, image_mod.ART_HEIGHT });
            try backdrops.append(.{ .scene = scene.name, .image = index });
        }

        // Looks first, so a sprite may name one (P48-11, D-181).
        var looks = std.array_list.Managed(LookBinding).init(self.allocator);
        for (self.look_srcs.items) |src| {
            image_mod.validate_name(src.name) catch return self.error_at(src.at, "look name '{s}' is 1 to {d} printable characters", .{ src.name, image_mod.MAX_NAME });
            for (self.image_srcs.items) |img| {
                if (std.mem.eql(u8, img.name, src.name)) return self.error_at(src.at, "look '{s}' has the name of an image; give it its own", .{src.name});
            }
            const index = try self.image_index(src.image, "look", src.name);
            try looks.append(.{ .name = src.name, .image = index, .animations = try self.resolve_steps(src.animations, images.items[index].frame_count(), src.image.slice) });
        }

        var sprites = std.array_list.Managed(SpriteBinding).init(self.allocator);
        for (self.sprite_srcs.items) |src| {
            const on_stage = for (ast.cast.items) |name| {
                if (std.mem.eql(u8, name, src.target)) break true;
            } else for (ast.props.items) |name| {
                if (std.mem.eql(u8, name, src.target)) break true;
            } else for (self.part_srcs.items) |part| {
                if (std.mem.eql(u8, part.part, src.target)) break true;
            } else false;
            if (!on_stage) {
                var hints = Suggestions{};
                for (ast.cast.items) |name| hints.consider(src.target, name);
                for (ast.props.items) |name| hints.consider(src.target, name);
                self.suggestion = hints.result();
                return self.error_at(src.at, "sprite '{s}' is for a person or prop no scene declares in 'cast:' or 'props:', and no 'part' line names it", .{src.target});
            }
            // A sprite may show a look, which brings its image and animations.
            const named_look = for (looks.items) |look| {
                if (std.mem.eql(u8, look.name, src.image.slice)) break look;
            } else null;
            if (named_look) |look| {
                for (src.animations) |steps| {
                    if (steps.len > 0) return self.error_at(steps[0].at, "sprite '{s}' shows look '{s}', which has its own animations; move these lines to the look", .{ src.target, look.name });
                }
                try sprites.append(.{ .target = src.target, .image = look.image, .animations = look.animations });
                continue;
            }
            const index = try self.image_index(src.image, "sprite", src.target);
            try sprites.append(.{ .target = src.target, .image = index, .animations = try self.resolve_steps(src.animations, images.items[index].frame_count(), src.image.slice) });
        }
        for (self.part_srcs.items) |part| {
            const host_on_stage = for (ast.cast.items) |name| {
                if (std.mem.eql(u8, name, part.host)) break true;
            } else for (ast.props.items) |name| {
                if (std.mem.eql(u8, name, part.host)) break true;
            } else false;
            if (!host_on_stage) return self.error_at(part.at, "part '{s}' is attached to '{s}', which no scene declares in 'cast:' or 'props:'", .{ part.part, part.host });
        }
        for (self.area_srcs.items) |a| {
            const is_prop = for (ast.props.items) |name| {
                if (std.mem.eql(u8, name, a.target)) break true;
            } else false;
            if (!is_prop) {
                var hints = Suggestions{};
                for (ast.props.items) |name| hints.consider(a.target, name);
                self.suggestion = hints.result();
                return self.error_at(a.at, "area '{s}' is for a prop no scene declares in 'props:'", .{a.target});
            }
        }
        const codes = try self.allocator.alloc([]const u8, self.palette_src.items.len);
        for (self.palette_src.items, codes) |entry, *code| code.* = entry.code.slice;
        ast.art = .{
            .palette_codes = codes,
            .palette = try palette.toOwnedSlice(self.allocator),
            .images = try images.toOwnedSlice(),
            .backdrops = try backdrops.toOwnedSlice(),
            .sprites = try sprites.toOwnedSlice(),
            .areas = self.area_srcs.items,
            .looks = try looks.toOwnedSlice(),
            .parts = self.part_srcs.items,
        };
    }

    /// Animation lines checked against the image's frames and turned into steps.
    fn resolve_steps(self: *Parser, animations: [image_mod.ANIM_COUNT][]const StepSource, frames: u32, image_name: []const u8) ![image_mod.ANIM_COUNT][]const image_mod.Step {
        var out: [image_mod.ANIM_COUNT][]const image_mod.Step = undefined;
        for (animations, &out) |steps, *slot| {
            const own = try self.allocator.alloc(image_mod.Step, steps.len);
            for (steps, own) |step, *o| {
                if (step.frame >= frames)
                    return self.error_at(step.at, "image '{s}' has {d} frame(s), numbered from 0; frame {d} does not exist", .{ image_name, frames, step.frame });
                o.* = .{ .frame = @intCast(step.frame), .duration = @intCast(step.duration) };
            }
            slot.* = own;
        }
        return out;
    }

    fn finish_red_lines(self: *Parser) !RedLinesDecl {
        const actor = try self.parse_name();
        if (self.current.tag != .colon) return self.set_error("red lines for '{s}' expect ':' and the options it never takes", .{actor});
        const line = self.current.line;
        try self.advance();
        var options = std.array_list.Managed([]const u8).init(self.allocator);
        while (self.current.line == line and (self.current.tag == .identifier or self.current.tag == .string_literal)) {
            try options.append(try self.parse_name());
            if (self.current.tag != .comma) break;
            try self.advance();
        }
        if (options.items.len == 0) return self.set_error("red lines for '{s}' name no option", .{actor});
        if (self.current.line == line and self.current.tag != .newline and self.current.tag != .eof)
            return self.set_error("red lines for '{s}' expect option names separated by commas", .{actor});
        return .{ .actor = actor, .options = try options.toOwnedSlice() };
    }

    /// Parses `axis <Virtue> between <Pole> and <Pole>` (P45-01). A pole may be quoted or run
    /// to the end of its phrase, so `Condoning Harm` needs no quotes.
    fn parse_axis_decl(self: *Parser) !AxisDecl {
        try self.advance(); // axis
        const name = (try self.expect(.identifier)).slice;
        const between = try self.expect(.identifier);
        if (!std.mem.eql(u8, between.slice, "between"))
            return self.set_error("axis '{s}' expects 'between <Pole> and <Pole>'", .{name});
        const first = try self.parse_name();
        if (self.current.tag != .kw_and)
            return self.set_error("axis '{s}' expects 'and' between its two poles", .{name});
        try self.advance();
        const second = try self.parse_name();
        if (std.mem.eql(u8, first, second))
            return self.set_error("axis '{s}' names '{s}' as both poles", .{ name, first });
        for ([_][]const u8{ first, second }) |pole| {
            if (std.mem.eql(u8, pole, name))
                return self.set_error("axis '{s}' names its virtue as a pole", .{name});
        }
        var drift_step: ?u8 = null;
        if (self.current.tag == .indent) {
            try self.advance();
            while (self.current.tag != .dedent and self.current.tag != .eof) {
                const line = self.current;
                if (!(line.tag == .identifier and std.mem.eql(u8, line.slice, "drift"))) return self.error_at(line, "axis '{s}' takes only 'drift step <N>' below it", .{name});
                try self.advance();
                if (!(self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "step"))) return self.error_at(self.current, "axis '{s}' expects 'drift step <N>'", .{name});
                try self.advance();
                if (drift_step != null) return self.error_at(line, "axis '{s}' declares its drift step twice", .{name});
                const number = self.current;
                const n = try self.take_u32();
                if (n == 0 or n > value_mod.MAX_DRIFT_STEP) return self.error_at(number, "axis '{s}' drift step is {d}; use 1 to {d} points a step", .{ name, n, value_mod.MAX_DRIFT_STEP });
                drift_step = @intCast(n);
            }
            _ = try self.expect(.dedent);
        }
        return .{ .name = name, .poles = .{ first, second }, .drift_step = drift_step };
    }

    fn decision_clause(self: *Parser, owner_kind: []const u8, owner: []const u8) !FactPattern {
        const pattern = try self.parse_fact_pattern();
        if (pattern.args.len == 0 or pattern.args.len > 2)
            return self.set_error("{s} '{s}' line '{s}' needs one or two arguments", .{ owner_kind, owner, pattern.relation });
        return pattern;
    }

    fn rate_index(names: []const []const u8, directive: []const u8) ?usize {
        for (names, 0..) |n, i| if (std.mem.eql(u8, n, directive)) return i;
        return null;
    }

    /// Parses `draft <Name>(n1, n2, n3, n4) [reverse <Inverse>]` and rejects any sequence that
    /// would make note lookup ambiguous: a played sequence must name exactly one draft, read in
    /// either direction, so `VM.weave_notes` never needs a tie-break (D-029).
    fn parse_draft_decl(self: *Parser, prior: []const DraftDecl) !DraftDecl {
        try self.advance(); // consume 'draft'
        const name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.lparen);
        var notes: Notes = undefined;
        var count: usize = 0;
        while (self.current.tag != .rparen and self.current.tag != .eof) {
            if (count == notes.len) {
                return self.set_error("draft '{s}' has more than {d} notes", .{ name, notes.len });
            }
            const tok = try self.expect(.identifier);
            notes[count] = Note.from_name(tok.slice) orelse {
                return self.set_error("unknown note '{s}' in draft '{s}'; expected one of C D E F G A B", .{ tok.slice, name });
            };
            count += 1;
            if (self.current.tag == .comma) try self.advance();
        }
        if (count != notes.len) {
            return self.set_error("draft '{s}' has {d} notes; drafts have exactly {d}", .{ name, count, notes.len });
        }
        _ = try self.expect(.rparen);

        var reverse_name: ?[]const u8 = null;
        if (self.current.tag == .identifier and std.mem.eql(u8, self.current.slice, "reverse")) {
            try self.advance();
            reverse_name = (try self.expect(.identifier)).slice;
        }

        if (reverse_name) |rn| {
            if (std.mem.eql(u8, rn, name)) {
                return self.set_error("draft '{s}' cannot be its own reverse", .{name});
            }
            if (draft_mod.is_palindrome(notes)) {
                return self.set_error("draft '{s}' is a palindrome; its reverse '{s}' would play the same notes", .{ name, rn });
            }
        }

        for (prior) |p| {
            const new_names = [_]?[]const u8{ name, reverse_name };
            for (new_names) |maybe_new| {
                const nn = maybe_new orelse continue;
                if (std.mem.eql(u8, nn, p.name) or (p.reverse_name != null and std.mem.eql(u8, nn, p.reverse_name.?))) {
                    return self.set_error("draft name '{s}' is already declared", .{nn});
                }
            }
            if (draft_mod.notes_eql(notes, p.notes) or draft_mod.notes_eql(notes, draft_mod.reversed(p.notes))) {
                return self.set_error("draft '{s}' plays the same notes as draft '{s}' (forward or reversed)", .{ name, p.name });
            }
        }

        return .{ .name = name, .notes = notes, .reverse_name = reverse_name };
    }

    fn draft_declared(drafts: []const DraftDecl, name: []const u8) bool {
        for (drafts) |d| {
            if (std.mem.eql(u8, d.name, name)) return true;
            if (d.reverse_name) |rn| if (std.mem.eql(u8, rn, name)) return true;
        }
        return false;
    }

    fn parse_routine_decl(self: *Parser) !Routine {
        try self.advance(); // consume 'routine'
        const name_line = self.current.line;
        const name_column = self.current.col;
        const name = try self.parse_name();
        _ = try self.expect(.lparen);
        const entity = try self.parse_name();
        _ = try self.expect(.rparen);
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);

        const body = try self.parse_stmt_list();
        _ = try self.expect(.dedent);

        return .{
            .name = name,
            .entity = entity,
            .body = body,
            .line = name_line,
            .column = name_column,
        };
    }

    /// A path block may assert facts and declare the routines that belong to that route.
    /// Facts run when the path is selected; routines are guarded by the active path at runtime.
    fn parse_path_decl(self: *Parser) !PathDecl {
        try self.advance(); // consume 'path'
        const name = (try self.expect(.identifier)).slice;
        _ = try self.expect(.colon);
        _ = try self.expect(.indent);

        var facts = std.array_list.Managed(Stmt).init(self.allocator);
        var routines = std.array_list.Managed(Routine).init(self.allocator);
        while (self.current.tag != .dedent and self.current.tag != .eof) {
            switch (self.current.tag) {
                .kw_remember => try facts.append(try self.parse_remember_stmt()),
                .kw_now => try facts.append(try self.parse_now_stmt()),
                .kw_forget => {
                    try self.advance();
                    const pat = try self.parse_fact_pattern();
                    try facts.append(.{ .forget = .{
                        .relation = pat.relation,
                        .args = pat.args,
                    } });
                },
                .kw_routine => try routines.append(try self.parse_routine_decl()),
                else => return self.set_error("expected a fact statement or routine in path block, found {s} ('{s}')", .{
                    @tagName(self.current.tag),
                    self.current.slice,
                }),
            }
        }
        _ = try self.expect(.dedent);

        return .{
            .name = name,
            .facts = try facts.toOwnedSlice(),
            .routines = try routines.toOwnedSlice(),
        };
    }

    fn parse_stmt_list(self: *Parser) ![]const Stmt {
        var list = std.array_list.Managed(Stmt).init(self.allocator);

        while (self.current.tag != .dedent and self.current.tag != .eof) {
            switch (self.current.tag) {
                .kw_remember => {
                    try list.append(try self.parse_remember_stmt());
                },
                .kw_forget => {
                    try self.advance();
                    const pat = try self.parse_fact_pattern();
                    try list.append(.{ .forget = .{
                        .relation = pat.relation,
                        .args = pat.args,
                    } });
                },
                .kw_now => {
                    try list.append(try self.parse_now_stmt());
                },
                .kw_transition => {
                    try self.advance(); // consume 'transition'
                    _ = try self.expect(.kw_to);
                    _ = try self.expect(.kw_scene);
                    if (self.current.tag == .colon) try self.advance();
                    const target_scene = try self.parse_name();
                    try list.append(.{ .transition_scene = .{ .target_scene = target_scene } });
                },
                .kw_choice => {
                    var choices = std.array_list.Managed(DialogueChoice).init(self.allocator);
                    while (self.current.tag == .kw_choice) {
                        try self.advance(); // consume 'choice'
                        const text = if (self.current.tag == .string_literal)
                            (try self.expect(.string_literal)).slice
                        else
                            try self.parse_name();
                        var guard: ?Expr = null;
                        if (self.current.tag == .kw_if) {
                            try self.advance();
                            guard = try self.parse_expr();
                        }
                        var where_patterns = std.array_list.Managed(FactPattern).init(self.allocator);
                        if (self.current.tag == .kw_where) {
                            try self.advance();
                            while (true) {
                                const pat = try self.parse_fact_pattern();
                                try where_patterns.append(pat);
                                if (self.current.tag == .kw_and) {
                                    try self.advance();
                                } else break;
                            }
                        }
                        _ = try self.expect(.colon);
                        _ = try self.expect(.indent);
                        const body = try self.parse_stmt_list();
                        _ = try self.expect(.dedent);
                        try choices.append(.{
                            .text = text,
                            .guard = guard,
                            .where_patterns = try where_patterns.toOwnedSlice(),
                            .body = body,
                        });
                    }
                    try list.append(.{ .choice_block = try choices.toOwnedSlice() });
                },
                .kw_walk => {
                    try self.advance();
                    const ent = try self.parse_name();
                    _ = try self.expect(.kw_to);
                    const target = try self.parse_name();
                    try list.append(.{ .walk = .{ .entity = ent, .target = target } });
                },
                .kw_face => {
                    try self.advance();
                    const ent = try self.parse_name();
                    _ = try self.expect(.kw_toward);
                    const target = try self.parse_name();
                    try list.append(.{ .face = .{ .entity = ent, .target = target } });
                },
                .kw_wait => {
                    try self.advance();
                    if (self.current.tag == .number) {
                        const num_tok = self.current;
                        try self.advance();
                        _ = try self.expect(.kw_ticks);
                        const ticks = try self.parse_number(u32, num_tok, "tick count", num_tok.slice);
                        try list.append(.{ .wait_ticks = ticks });
                    } else if (self.current.tag == .kw_until) {
                        try self.advance();
                        const expr = try self.parse_expr();
                        try list.append(.{ .wait_until = expr });
                    } else {
                        self.suggest_keyword(self.current.slice, &.{.kw_until});
                        return self.set_error("expected a tick count or 'until' after 'wait', found '{s}'", .{self.current.slice});
                    }
                },
                .kw_loop => {
                    try self.advance();
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const loop_body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);
                    try list.append(.{ .loop_stmt = loop_body });
                },
                .kw_if => {
                    try self.advance();
                    const cond = try self.parse_expr();
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const if_body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);
                    try list.append(.{ .if_stmt = .{ .cond = cond, .body = if_body } });
                },
                .kw_interrupt => {
                    try self.advance();
                    const ent = try self.parse_name();
                    _ = try self.expect(.kw_with);
                    _ = try self.expect(.colon);
                    _ = try self.expect(.indent);
                    const int_body = try self.parse_stmt_list();
                    _ = try self.expect(.dedent);
                    try list.append(.{ .interrupt_with = .{ .entity = ent, .body = int_body } });
                },
                .kw_say => {
                    try self.advance(); // consume 'say' (P7-04, D-009)
                    const speaker = try self.parse_name();
                    if (self.current.tag == .kw_to) {
                        try self.advance();
                        _ = try self.parse_name();
                    }
                    _ = try self.expect(.colon);
                    const text = if (self.current.tag == .string_literal)
                        (try self.expect(.string_literal)).slice
                    else if (self.current.tag == .lparen) blk: {
                        try self.advance();
                        var paren_buf = std.array_list.Managed(u8).init(self.allocator);
                        while (self.current.tag != .rparen and self.current.tag != .eof) {
                            if (paren_buf.items.len > 0) try paren_buf.append(' ');
                            try paren_buf.appendSlice(self.current.slice);
                            try self.advance();
                        }
                        if (self.current.tag == .rparen) try self.advance();
                        break :blk try paren_buf.toOwnedSlice();
                    } else (try self.parse_name());
                    try list.append(.{ .say = .{ .speaker = speaker, .text = text } });
                },
                .kw_animate => {
                    try self.advance();
                    if (self.current.tag == .lparen) {
                        try self.advance();
                        const target = try self.parse_name();
                        _ = try self.expect(.comma);
                        const clip = try self.parse_name();
                        _ = try self.expect(.rparen);
                        try list.append(.{ .animate = .{ .target = target, .clip = clip, .is_stop = false } });
                    } else {
                        const clip = try self.parse_name();
                        try list.append(.{ .animate = .{ .target = "Scene", .clip = clip, .is_stop = false } });
                    }
                },
                .kw_play => try list.append(try self.parse_music_stmt()),
                .kw_stop => {
                    try self.advance();
                    if (self.current.tag == .kw_score) {
                        try self.advance();
                        try list.append(.{ .play_score = null });
                        continue;
                    }
                    _ = try self.expect(.kw_animate);
                    const clip = try self.parse_name();
                    try list.append(.{ .animate = .{ .target = "Scene", .clip = clip, .is_stop = true } });
                },
                .kw_resume => {
                    try self.advance();
                    while (self.current.tag == .identifier) {
                        _ = try self.parse_name();
                    }
                    try list.append(.{ .resume_stmt = {} });
                },
                .kw_done => {
                    try self.advance();
                    try list.append(.{ .resume_stmt = {} });
                },
                .kw_weave => {
                    try self.advance(); // consume 'weave'
                    const draft_tok = self.current;
                    const draft_name = try self.parse_name();
                    _ = try self.expect(.kw_on);
                    const target = try self.parse_name();
                    try self.weave_refs.append(.{ .draft = draft_name, .line = draft_tok.opening_line(), .column = draft_tok.col });
                    try list.append(.{ .weave = .{ .draft = draft_name, .target = target } });
                },
                .identifier => {
                    const start = self.current;
                    const subj = try self.parse_name();
                    if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
                        try self.advance();
                        const stmt = try self.finish_state_stmt(subj);
                        try list.append(stmt);
                    } else {
                        self.suggest_keyword(start.slice, &.{ .kw_remember, .kw_forget, .kw_now, .kw_transition, .kw_choice, .kw_walk, .kw_face, .kw_wait, .kw_loop, .kw_if, .kw_interrupt, .kw_say, .kw_animate, .kw_play, .kw_stop, .kw_resume, .kw_done, .kw_weave });
                        return self.error_at(start, "unexpected statement '{s}'", .{subj});
                    }
                },
                else => {
                    return self.set_error("unexpected statement token {s} ('{s}')", .{
                        @tagName(self.current.tag),
                        self.current.slice,
                    });
                },
            }
        }

        return try list.toOwnedSlice();
    }

    fn parse_now_stmt(self: *Parser) !Stmt {
        try self.advance(); // consume 'now'
        const target = try self.parse_name();
        if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
            try self.advance();
        }
        return self.finish_state_stmt(target);
    }

    /// A state word after `is` names a relation, so it takes the relation's capital (D-161):
    /// `now Lamp is lit` and `Lit(Lamp)` are one fact. A word already capitalised is unchanged
    /// and keeps pointing into the source; a lowercase one is copied into the parser's arena.
    fn state_word(self: *Parser, word: []const u8) ![]const u8 {
        if (word.len == 0 or !std.ascii.isLower(word[0])) return word;
        const copy = try self.allocator.dupe(u8, word);
        copy[0] = std.ascii.toUpper(copy[0]);
        return copy;
    }

    fn finish_state_stmt(self: *Parser, target: []const u8) !Stmt {
        var is_neg = false;
        if (self.current.tag == .kw_not) {
            is_neg = true;
            try self.advance();
        }
        const state = try self.state_word(try self.parse_name());
        if (self.current.tag == .kw_with) {
            try self.advance();
        }
        if (self.current.tag == .kw_in) {
            try self.advance();
            if (self.current.tag == .kw_the) try self.advance();
            if (self.current.tag == .identifier or self.current.tag == .kw_scene) _ = try self.advance();
        }
        var args = try self.allocator.alloc([]const u8, 1);
        args[0] = target;
        if (is_neg) {
            return Stmt{
                .forget = .{
                    .relation = state,
                    .args = args,
                },
            };
        } else {
            return Stmt{
                .remember = .{
                    .relation = state,
                    .args = args,
                    .ttl_ticks = 0,
                },
            };
        }
    }

    fn parse_remember_stmt(self: *Parser) !Stmt {
        try self.advance(); // consume 'remember'
        if (self.current.tag == .colon) try self.advance();
        const pat = try self.parse_fact_pattern();
        var ttl: u32 = 0;
        if (self.current.tag == .kw_for) {
            try self.advance();
            const num_tok = try self.expect(.number);
            _ = try self.expect(.kw_ticks);
            ttl = try self.parse_number(u32, num_tok, "tick count", num_tok.slice);
        }
        return Stmt{
            .remember = .{
                .relation = pat.relation,
                .args = pat.args,
                .ttl_ticks = ttl,
            },
        };
    }

    fn finish_fact_pattern(self: *Parser, rel_name: []const u8) !FactPattern {
        const is_bracket = self.current.tag == .lbracket;
        if (is_bracket) {
            try self.advance();
        } else {
            _ = try self.expect(.lparen);
        }
        var args = std.array_list.Managed([]const u8).init(self.allocator);
        const end_tag = if (is_bracket) TokenTag.rbracket else TokenTag.rparen;
        while (self.current.tag != end_tag and self.current.tag != .eof) {
            try args.append(self.current.slice);
            try self.advance();
            if (self.current.tag == .comma) try self.advance();
        }
        _ = try self.expect(end_tag);

        return FactPattern{
            .relation = rel_name,
            .args = try args.toOwnedSlice(),
        };
    }

    fn parse_fact_pattern(self: *Parser) !FactPattern {
        const rel_name = (try self.expect(.identifier)).slice;
        return self.finish_fact_pattern(rel_name);
    }

    fn parse_number(self: *Parser, comptime T: type, tok: Token, what: []const u8, bytes: []const u8) !T {
        return std.fmt.parseInt(T, bytes, 10) catch |err| {
            self.record_error(tok, "invalid {s}: '{s}'", .{ what, tok.slice });
            return err;
        };
    }

    fn parse_expr(self: *Parser) !Expr {
        if (self.current.tag == .kw_roll) {
            try self.advance();
            const dice_tok = try self.expect(.dice); // e.g. "2d6"
            // Parse "2d6"
            var it = std.mem.splitScalar(u8, dice_tok.slice, 'd');
            const count_str = it.next() orelse "1";
            const sides_str = it.next() orelse "6";
            const count = try self.parse_number(u8, dice_tok, "dice expression", count_str);
            const sides = try self.parse_number(u8, dice_tok, "dice expression", sides_str);

            _ = try self.expect(.gte);
            const num_tok = try self.expect(.number);
            const thresh = try self.parse_number(u32, num_tok, "roll threshold", num_tok.slice);
            return Expr{ .roll_gte = .{ .count = count, .sides = sides, .threshold = thresh } };
        } else if (self.current.tag == .kw_not) {
            try self.advance();
            const pat = try self.parse_fact_pattern();
            return Expr{ .not_fact = pat };
        } else if (self.current.tag == .number) {
            const threshold_tok = self.current;
            try self.advance();
            const threshold = try self.parse_number(u32, threshold_tok, "aggregate threshold", threshold_tok.slice);
            const word = (try self.expect(.identifier)).slice;
            const weighted = std.mem.eql(u8, word, "points");
            if (weighted) {
                const of = (try self.expect(.identifier)).slice;
                if (!std.mem.eql(u8, of, "of"))
                    return self.set_error("points condition expects 'points of <Fact>'", .{});
            } else if (!std.mem.eql(u8, word, "of")) {
                return self.set_error("aggregate condition expects '<n> of <Fact>' or '<n> points of <Fact>'", .{});
            }
            const pattern = try self.parse_fact_pattern();
            if (pattern.args.len == 0 or pattern.args.len > 2)
                return self.set_error("aggregate condition pattern needs one or two arguments", .{});
            return if (weighted)
                Expr{ .points_at_least = .{ .pattern = pattern, .threshold = threshold } }
            else
                Expr{ .count_at_least = .{ .pattern = pattern, .threshold = threshold } };
        } else if (self.current.tag == .identifier) {
            const first = try self.parse_name();
            if (self.current.tag == .kw_is or self.current.tag == .kw_are) {
                try self.advance();
                var is_neg = false;
                if (self.current.tag == .kw_not) {
                    is_neg = true;
                    try self.advance();
                }
                const state = try self.state_word(try self.parse_name());
                if (self.current.tag == .kw_with) try self.advance();
                var pat_args = try self.allocator.alloc([]const u8, 1);
                pat_args[0] = first;
                if (is_neg) {
                    return Expr{ .not_fact = .{ .relation = state, .args = pat_args } };
                } else {
                    return Expr{ .has_fact = .{ .relation = state, .args = pat_args } };
                }
            } else if (self.current.tag == .kw_say) {
                try self.advance(); // e.g. "Hero says 'Hello!'"
                const txt = if (self.current.tag == .string_literal)
                    (try self.expect(.string_literal)).slice
                else
                    try self.parse_name();
                var pat_args = try self.allocator.alloc([]const u8, 2);
                pat_args[0] = first;
                pat_args[1] = txt;
                return Expr{ .has_fact = .{ .relation = "Said", .args = pat_args } };
            } else {
                const pat = try self.finish_fact_pattern(first);
                return Expr{ .has_fact = pat };
            }
        } else {
            const pat = try self.parse_fact_pattern();
            return Expr{ .has_fact = pat };
        }
    }
};

test "P44-02: parser recognizes count and points conditions" {
    const testing = std.testing;
    const source =
        \\entity Hero
        \\relation Clue(clue, points)
        \\routine Audit(Hero):
        \\  if 2 of Clue(_):
        \\    wait until 6 points of Clue(Hero, _)
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), source);
    defer lexer.deinit();
    var parser = try Parser.init(arena.allocator(), &lexer);
    var ast = try parser.parse_program();
    defer ast.deinit();

    const body = ast.routines.items[0].body;
    const count = body[0].if_stmt.cond.count_at_least;
    try testing.expectEqual(@as(u32, 2), count.threshold);
    try testing.expectEqualStrings("Clue", count.pattern.relation);
    try testing.expectEqualStrings("_", count.pattern.args[0]);

    const points = body[0].if_stmt.body[0].wait_until.points_at_least;
    try testing.expectEqual(@as(u32, 6), points.threshold);
    try testing.expectEqualStrings("Clue", points.pattern.relation);
    try testing.expectEqualStrings("Hero", points.pattern.args[0]);
    try testing.expectEqualStrings("_", points.pattern.args[1]);
}

test "P4-02: parser parses complete tavern heist AST" {
    const testing = std.testing;
    const script =
        \\entity Guard, Bard, Cat, Cheese
        \\relation Carries(holder, item)
        \\relation CharmedBy(listener, musician)
        \\
        \\remember Carries(Guard, Cheese)
        \\
        \\routine Patrol(Guard):
        \\  loop:
        \\    walk Guard to Cellar
        \\    wait 120 ticks
        \\
        \\on cue PlayLute(Bard, target):
        \\  if roll 2d6 >= 8:
        \\    remember CharmedBy(target, Bard) for 180 ticks
        \\
        \\when CharmedBy(listener, musician):
        \\  interrupt listener with:
        \\    face listener toward musician
        \\    wait until not CharmedBy(listener, musician)
        \\
        \\on cue Steal(Cat, victim) where CharmedBy(victim, _) and Carries(victim, loot):
        \\  forget Carries(victim, loot)
        \\  remember Carries(Cat, loot)
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();
    _ = &ast;

    try testing.expectEqual(@as(usize, 4), ast.entities.items.len);
    try testing.expectEqual(@as(usize, 2), ast.relations.items.len);
    try testing.expectEqual(@as(usize, 1), ast.initial_stmts.items.len);
    try testing.expectEqual(@as(usize, 1), ast.routines.items.len);
    try testing.expectEqual(@as(usize, 2), ast.cue_handlers.items.len);
    try testing.expectEqual(@as(usize, 1), ast.when_rules.items.len);
}

test "P8-01: multi-clause when rule parsing" {
    const testing = std.testing;
    const script =
        \\entity Guard, Bard, Cheese
        \\relation Carries(holder, item)
        \\relation CharmedBy(listener, musician)
        \\
        \\when Carries(Guard, Cheese) and CharmedBy(Guard, Bard):
        \\  interrupt Guard with:
        \\    face Guard toward Bard
        \\    wait 10 ticks
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 1), ast.when_rules.items.len);
    const rule = ast.when_rules.items[0];
    try testing.expectEqual(@as(usize, 2), rule.trigger_patterns.len);
    try testing.expectEqualStrings("Carries", rule.trigger_patterns[0].relation);
    try testing.expectEqualStrings("CharmedBy", rule.trigger_patterns[1].relation);
}

test "P10-01: parser parses stageplay taxonomy, state declarations, and falling-edge/expiration rules" {
    const testing = std.testing;
    const script =
        \\scene: Spitting Competition
        \\cast: Hero, Organiser, Onlookers
        \\props: Flags
        \\marks: Starting Line, Looking Offstage
        \\
        \\Tampered with is a state, which can be tampered with or not tampered with.
        \\Distracted is a state, which can be distracted or not distracted.
        \\
        \\remember: Carries(Hero, Horn) ~ inline comment
        \\now Flags are tampered with
        \\
        \\routine EggingCrowd(Organiser):
        \\  loop:
        \\    walk Organiser to Onlookers
        \\    say Organiser to Onlookers: "Come on!"
        \\    wait 30 ticks
        \\
        \\when currently Wind is blowing:
        \\  interrupt Organiser with:
        \\    animate wind-blowing
        \\
        \\when Wind stops being blowing:
        \\  interrupt Organiser with:
        \\    stop animate wind-blowing
        \\
        \\when Organiser forgets Distracted:
        \\  interrupt Organiser with:
        \\    walk Organiser to Starting Line
        \\    resume previous action
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 1), ast.scenes.items.len);
    try testing.expectEqualStrings("Spitting Competition", ast.scenes.items[0]);

    try testing.expectEqual(@as(usize, 3), ast.cast.items.len);
    try testing.expectEqualStrings("Hero", ast.cast.items[0]);
    try testing.expectEqualStrings("Organiser", ast.cast.items[1]);
    try testing.expectEqualStrings("Onlookers", ast.cast.items[2]);

    try testing.expectEqual(@as(usize, 1), ast.props.items.len);
    try testing.expectEqualStrings("Flags", ast.props.items[0]);

    try testing.expectEqual(@as(usize, 2), ast.marks.items.len);
    try testing.expectEqualStrings("Starting Line", ast.marks.items[0]);
    try testing.expectEqualStrings("Looking Offstage", ast.marks.items[1]);

    try testing.expectEqual(@as(usize, 3), ast.when_rules.items.len);
    try testing.expectEqual(WhenEdge.rising, ast.when_rules.items[0].edge);
    try testing.expectEqual(WhenEdge.falling, ast.when_rules.items[1].edge);
    try testing.expectEqual(WhenEdge.on_expire, ast.when_rules.items[2].edge);
}

test "P12-01: parser parses scene transition statements" {
    const testing = std.testing;
    const script =
        \\scene: Tavern
        \\cast: Hero
        \\transition to scene: Wine Cellar
        \\
        \\routine EnterCellar(Hero):
        \\  transition to scene Wine Cellar
        \\  wait 10 ticks
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    // Verify top-level initial transition statement
    try testing.expectEqual(@as(usize, 1), ast.initial_stmts.items.len);
    switch (ast.initial_stmts.items[0]) {
        .transition_scene => |ts| try testing.expectEqualStrings("Wine Cellar", ts.target_scene),
        else => try testing.expect(false),
    }

    // Verify routine statement transition
    try testing.expectEqual(@as(usize, 1), ast.routines.items.len);
    const routine = ast.routines.items[0];
    try testing.expectEqualStrings("EnterCellar", routine.name);
    try testing.expectEqual(@as(usize, 2), routine.body.len);
    switch (routine.body[0]) {
        .transition_scene => |ts| try testing.expectEqualStrings("Wine Cellar", ts.target_scene),
        else => try testing.expect(false),
    }
}

test "P12-02: parser groups multiple scenes with scoped cast, props, and marks" {
    const testing = std.testing;
    const script =
        \\scene: Tavern
        \\cast: Hero, Barkeep
        \\props: Mug
        \\marks: Hearth, Counter
        \\
        \\scene: Wine Cellar
        \\cast: Guard
        \\props: Cask
        \\marks: CaskMark, SecretDoor
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 2), ast.scene_defs.items.len);

    const s1 = ast.scene_defs.items[0];
    try testing.expectEqualStrings("Tavern", s1.name);
    try testing.expectEqual(@as(usize, 2), s1.cast.items.len);
    try testing.expectEqualStrings("Hero", s1.cast.items[0]);
    try testing.expectEqualStrings("Barkeep", s1.cast.items[1]);
    try testing.expectEqual(@as(usize, 1), s1.props.items.len);
    try testing.expectEqualStrings("Mug", s1.props.items[0]);
    try testing.expectEqual(@as(usize, 2), s1.marks.items.len);
    try testing.expectEqualStrings("Hearth", s1.marks.items[0]);
    try testing.expectEqualStrings("Counter", s1.marks.items[1]);

    const s2 = ast.scene_defs.items[1];
    try testing.expectEqualStrings("Wine Cellar", s2.name);
    try testing.expectEqual(@as(usize, 1), s2.cast.items.len);
    try testing.expectEqualStrings("Guard", s2.cast.items[0]);
    try testing.expectEqual(@as(usize, 1), s2.props.items.len);
    try testing.expectEqualStrings("Cask", s2.props.items[0]);
    try testing.expectEqual(@as(usize, 2), s2.marks.items.len);
    try testing.expectEqualStrings("CaskMark", s2.marks.items[0]);
    try testing.expectEqualStrings("SecretDoor", s2.marks.items[1]);
}

test "P13-01: parser parses conditionally guarded dialogue choice blocks" {
    const testing = std.testing;
    const script =
        \\routine TalkToClerk(Hero):
        \\  choice "I'd like to rent a motorcycle." if Carries(Hero, License):
        \\    say Clerk: "Here are the keys."
        \\  choice "Do you know whose cat that is?" if not KnowsAboutCat(Hero):
        \\    say Clerk: "It belongs to the rector."
        \\    remember KnowsAboutCat(Hero, true)
        \\  choice "Just browsing, thanks.":
        \\    say Clerk: "Good day!"
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();

    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 1), ast.routines.items.len);
    const r = ast.routines.items[0];
    try testing.expectEqualStrings("TalkToClerk", r.name);
    try testing.expectEqual(@as(usize, 1), r.body.len);

    switch (r.body[0]) {
        .choice_block => |choices| {
            try testing.expectEqual(@as(usize, 3), choices.len);

            // Choice 0: Carries(Hero, License) guard
            try testing.expectEqualStrings("I'd like to rent a motorcycle.", choices[0].text);
            try testing.expect(choices[0].guard != null);
            switch (choices[0].guard.?) {
                .has_fact => |pat| {
                    try testing.expectEqualStrings("Carries", pat.relation);
                    try testing.expectEqual(@as(usize, 2), pat.args.len);
                    try testing.expectEqualStrings("Hero", pat.args[0]);
                    try testing.expectEqualStrings("License", pat.args[1]);
                },
                else => try testing.expect(false),
            }
            try testing.expectEqual(@as(usize, 1), choices[0].body.len);

            // Choice 1: not KnowsAboutCat(Hero) guard
            try testing.expectEqualStrings("Do you know whose cat that is?", choices[1].text);
            try testing.expect(choices[1].guard != null);
            switch (choices[1].guard.?) {
                .not_fact => |pat| {
                    try testing.expectEqualStrings("KnowsAboutCat", pat.relation);
                    try testing.expectEqual(@as(usize, 1), pat.args.len);
                    try testing.expectEqualStrings("Hero", pat.args[0]);
                },
                else => try testing.expect(false),
            }
            try testing.expectEqual(@as(usize, 2), choices[1].body.len);

            // Choice 2: unconditional
            try testing.expectEqualStrings("Just browsing, thanks.", choices[2].text);
            try testing.expect(choices[2].guard == null);
            try testing.expectEqual(@as(usize, 1), choices[2].body.len);
        },
        else => try testing.expect(false),
    }
}

test "P13-01: parser parses relational where-clause guarded dialogue choices" {
    const testing = std.testing;
    const script =
        \\routine BarbDuel(Tamsin):
        \\  choice "Good, then that means I can still wipe the floor with you." where MasteredReply(Tamsin, ReplyMop) and Counters(ReplyMop, BarbMop):
        \\    say Tamsin: "Good, then that means I can still wipe the floor with you."
        \\  choice "Er... is that the time?":
        \\    say Tamsin: "Er... is that the time?"
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, script);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    var ast = try parser.parse_program();
    defer ast.deinit();

    try testing.expectEqual(@as(usize, 1), ast.routines.items.len);
    const r = ast.routines.items[0];
    switch (r.body[0]) {
        .choice_block => |choices| {
            try testing.expectEqual(@as(usize, 2), choices.len);
            try testing.expectEqualStrings("Good, then that means I can still wipe the floor with you.", choices[0].text);
            try testing.expectEqual(@as(usize, 2), choices[0].where_patterns.len);
            try testing.expectEqualStrings("MasteredReply", choices[0].where_patterns[0].relation);
            try testing.expectEqualStrings("Counters", choices[0].where_patterns[1].relation);
            try testing.expectEqualStrings("Er... is that the time?", choices[1].text);
            try testing.expectEqual(@as(usize, 0), choices[1].where_patterns.len);
        },
        else => try testing.expect(false),
    }
}

test "P15-03: parser captures accurate line and column diagnostics on syntax errors" {
    const testing = std.testing;
    const invalid_script =
        \\routine Patrol Guard):
        \\  walk Guard to Cellar
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, invalid_script);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    const result = parser.parse_program();
    try testing.expectError(error.UnexpectedToken, result);

    const diag = parser.get_diagnostic();
    try testing.expect(diag != null);
    try testing.expectEqual(@as(u32, 1), diag.?.line);
    try testing.expectEqual(@as(u32, 21), diag.?.column);
    try testing.expect(std.mem.indexOf(u8, diag.?.message, "expected '('") != null);
}

fn expect_draft_error(source: []const u8, needle: []const u8, line: u32) !void {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    try testing.expectError(error.UnexpectedToken, parser.parse_program());
    const diag = parser.get_diagnostic().?;
    if (std.mem.indexOf(u8, diag.message, needle) == null) {
        std.debug.print("diagnostic was: {s}\n", .{diag.message});
        return error.TestUnexpectedResult;
    }
    try testing.expectEqual(line, diag.line);
}

test "P22-01: parser parses draft declarations with reverse and weave statements" {
    const testing = std.testing;
    const source =
        \\entity Player, Brazier
        \\draft Kindle(C, E, G, E) reverse Douse
        \\draft Mend(D, A, A, D)
        \\routine Ritual(Player):
        \\  weave Kindle on Brazier
        \\  weave Douse on Brazier
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 2), ast.drafts.items.len);
    const kindle = ast.drafts.items[0];
    try testing.expectEqualStrings("Kindle", kindle.name);
    try testing.expectEqualStrings("Douse", kindle.reverse_name.?);
    try testing.expect(std.mem.eql(Note, &kindle.notes, &[_]Note{ .C, .E, .G, .E }));
    try testing.expect(ast.drafts.items[1].reverse_name == null);

    const body = ast.routines.items[0].body;
    try testing.expectEqual(@as(usize, 2), body.len);
    try testing.expectEqualStrings("Kindle", body[0].weave.draft);
    try testing.expectEqualStrings("Brazier", body[0].weave.target);
    try testing.expectEqualStrings("Douse", body[1].weave.draft);
}

test "P22-01: parser rejects malformed and ambiguous drafts with located diagnostics" {
    try expect_draft_error("draft Kindle(C, E, H, E)", "unknown note 'H'", 1);
    try expect_draft_error("draft Kindle(C, E, G)", "has 3 notes", 1);
    try expect_draft_error("draft Kindle(C, E, G, E, C)", "more than 4 notes", 1);
    try expect_draft_error("draft Mend(D, A, A, D) reverse Rend", "palindrome", 1);
    try expect_draft_error("draft Kindle(C, E, G, E) reverse Kindle", "its own reverse", 1);
    try expect_draft_error(
        \\draft Kindle(C, E, G, E)
        \\draft Ember(E, G, E, C)
    , "same notes as draft 'Kindle'", 2);
    try expect_draft_error(
        \\draft Kindle(C, E, G, E) reverse Douse
        \\draft Douse(F, F, G, A)
    , "already declared", 2);
}

test "P22-01: parser rejects weaving undeclared drafts and top-level weaves" {
    try expect_draft_error(
        \\entity Player, Brazier
        \\routine Ritual(Player):
        \\  wait 1 ticks
        \\  weave Kindle on Brazier
    , "undeclared draft 'Kindle'", 4);
    try expect_draft_error(
        \\draft Kindle(C, E, G, E)
        \\weave Kindle on Brazier
    , "inside a routine", 2);
}

test "P24-01: parser parses path declarations with locked facts and path-owned routines" {
    const testing = std.testing;
    const source =
        \\entity Hero
        \\relation ChosenWits(flag)
        \\relation ChosenFists(flag)
        \\path Wits:
        \\  remember ChosenWits(Hero)
        \\  routine WitsPlan(Hero):
        \\    remember ChosenWits(Hero)
        \\path Fists:
        \\  now Hero is ChosenFists
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 2), ast.paths.items.len);
    try testing.expectEqualStrings("Wits", ast.paths.items[0].name);
    try testing.expectEqual(@as(usize, 1), ast.paths.items[0].facts.len);
    switch (ast.paths.items[0].facts[0]) {
        .remember => |r| try testing.expectEqualStrings("ChosenWits", r.relation),
        else => try testing.expect(false),
    }
    try testing.expectEqual(@as(usize, 1), ast.paths.items[0].routines.len);
    try testing.expectEqualStrings("WitsPlan", ast.paths.items[0].routines[0].name);
    try testing.expectEqualStrings("Hero", ast.paths.items[0].routines[0].entity);

    try testing.expectEqualStrings("Fists", ast.paths.items[1].name);
    try testing.expectEqual(@as(usize, 1), ast.paths.items[1].facts.len);
    try testing.expectEqual(@as(usize, 0), ast.paths.items[1].routines.len);
    switch (ast.paths.items[1].facts[0]) {
        .remember => |r| try testing.expectEqualStrings("ChosenFists", r.relation),
        else => try testing.expect(false),
    }
}

test "P44-07: a routine header takes multi-word names for itself and its actor" {
    const testing = std.testing;
    const source =
        \\routine Cheer(Judge Marrow):
        \\  remember Cheered("Judge Marrow")
        \\routine Judge Marrow(Judge Marrow):
        \\  remember Cheered("Judge Marrow")
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), source);
    defer lexer.deinit();
    var parser = try Parser.init(arena.allocator(), &lexer);
    const ast = try parser.parse_program();

    try testing.expectEqual(@as(usize, 2), ast.routines.items.len);
    try testing.expectEqualStrings("Cheer", ast.routines.items[0].name);
    try testing.expectEqualStrings("Judge Marrow", ast.routines.items[0].entity);
    // The multi-word name is the literal replacement for `during Judge Marrow:`.
    try testing.expectEqualStrings("Judge Marrow", ast.routines.items[1].name);
    try testing.expectEqualStrings("Judge Marrow", ast.routines.items[1].entity);
}

test "D-101: a quoted name keeps characters a word cannot, in scene, cast, props, marks, and transitions" {
    const testing = std.testing;
    const source =
        \\scene: "Keeper's Lodge"
        \\cast: Hero, "Old Keeper's Dog"
        \\props: "Hero's Ledger"
        \\marks: LodgeDoor, "Keeper's Corner"
        \\
        \\scene: Upper Yard
        \\cast: Mate
        \\
        \\on cue Uses(Hero, LodgeDoor):
        \\  transition to scene: "Keeper's Lodge"
    ;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var lexer = Lexer.init(arena.allocator(), source);
    defer lexer.deinit();
    var parser = try Parser.init(arena.allocator(), &lexer);
    const ast = try parser.parse_program();
    try testing.expectEqualStrings("Keeper's Lodge", ast.scenes.items[0]);
    // An unquoted name of several words still joins its words with single spaces.
    try testing.expectEqualStrings("Upper Yard", ast.scenes.items[1]);
    try testing.expectEqualStrings("Old Keeper's Dog", ast.cast.items[1]);
    try testing.expectEqualStrings("Hero's Ledger", ast.props.items[0]);
    var found_mark = false;
    for (ast.scene_defs.items[0].marks.items) |m| {
        if (std.mem.eql(u8, m, "Keeper's Corner")) found_mark = true;
    }
    try testing.expect(found_mark);
    switch (ast.cue_handlers.items[0].body[0]) {
        .transition_scene => |ts| try testing.expectEqualStrings("Keeper's Lodge", ts.target_scene),
        else => return error.TestUnexpectedResult,
    }
}

test "P38-01: parser rejects undocumented top-level text and body statements" {
    const cases = [_][]const u8{
        "mystery words\n",
        "routine Audit(Hero):\n  mystery words\n",
        "routine Audit(Hero):\n  wait forever\n",
        "routine Audit(Hero):\n  else:\n    wait 1 ticks\n",
    };
    for (cases) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var lexer = Lexer.init(arena.allocator(), source);
        defer lexer.deinit();
        var parser = try Parser.init(arena.allocator(), &lexer);
        try std.testing.expectError(error.UnexpectedToken, parser.parse_program());
        try std.testing.expect(parser.get_diagnostic() != null);
    }
}

fn expect_spellbook_error(source: []const u8, needle: []const u8) !void {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    try testing.expectError(error.UnexpectedToken, parser.parse_program());
    const diag = parser.get_diagnostic().?;
    if (std.mem.indexOf(u8, diag.message, needle) == null) {
        std.debug.print("diagnostic was: {s}\n", .{diag.message});
        return error.TestUnexpectedResult;
    }
}

test "P44-04: a spellbook declaration reads words in three kinds and the rows that combine them" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source =
        \\spellbook Grimoire:
        \\  power Spark, Forge
        \\  element Ember
        \\  form Bolt, Ward
        \\  spell Kindle: Forge, Ember, Bolt
    ;
    var lexer = Lexer.init(arena.allocator(), source);
    defer lexer.deinit();
    var parser = try Parser.init(arena.allocator(), &lexer);
    var ast = try parser.parse_program();
    defer ast.deinit();

    try testing.expectEqual(@as(usize, 1), ast.spellbooks.items.len);
    const book = ast.spellbooks.items[0];
    try testing.expectEqualStrings("Grimoire", book.name);
    try testing.expectEqual(@as(usize, 5), book.words.len);
    try testing.expectEqual(spell_mod.Kind.power, book.words[0].kind);
    try testing.expectEqualStrings("Forge", book.words[1].name);
    try testing.expectEqual(spell_mod.Kind.element, book.words[2].kind);
    try testing.expectEqual(spell_mod.Kind.form, book.words[4].kind);
    try testing.expectEqual(@as(usize, 1), book.spells.len);
    try testing.expectEqualStrings("Kindle", book.spells[0].name);
    try testing.expectEqualStrings("Forge", book.spells[0].power);
    try testing.expectEqualStrings("Ember", book.spells[0].element);
    try testing.expectEqualStrings("Bolt", book.spells[0].form);
}

test "P44-04: parser rejects a misplaced or undeclared word, a repeated name, and a fourth word" {
    try expect_spellbook_error(
        \\spellbook G:
        \\  power Spark
        \\  element Ember
        \\  form Bolt
        \\  spell Kindle: Ember, Spark, Bolt
    , "puts 'Ember' in the power slot, but 'Ember' is a word of another kind");
    try expect_spellbook_error(
        \\spellbook G:
        \\  power Spark
        \\  element Ember
        \\  form Bolt
        \\  spell Kindle: Spark, Ember, Spark
    , "puts 'Spark' in the form slot, but 'Spark' is a word of another kind");
    try expect_spellbook_error(
        \\spellbook G:
        \\  power Spark
        \\  element Ember
        \\  form Bolt
        \\  spell Kindle: Spark, Ember, Smoke
    , "not a word of spellbook 'G'");
    try expect_spellbook_error(
        \\spellbook G:
        \\  power Spark, Spark
        \\  element Ember
        \\  form Bolt
        \\  spell Kindle: Spark, Ember, Bolt
    , "declares word 'Spark' twice");
    try expect_spellbook_error(
        \\spellbook G:
        \\  power Spark
        \\  element Ember
        \\  form Bolt
        \\  spell Kindle: Spark, Ember, Bolt
        \\  spell Kindle: Spark, Ember, Bolt
    , "declares spell 'Kindle' twice");
    try expect_spellbook_error(
        \\spellbook G:
        \\  power Spark
        \\  element Ember
        \\  form Bolt
        \\  spell Kindle: Spark, Ember, Bolt, Ward
    , "takes exactly three words");
    try expect_spellbook_error(
        \\spellbook G:
        \\  power Spark
        \\  element Ember
        \\  form Bolt
        \\  spell Kindle: Spark, Ember, Bolt
        \\  spell Douse: Spark, Ember, Bolt
    , "uses the same three words");
    try expect_spellbook_error(
        \\spellbook G:
        \\  power Spark
        \\  element Ember
        \\  form Bolt
        \\  spell Kindle: Spark, Ember, Bolt
        \\  power Kindle
    , "word 'Kindle' reuses a spell name");
    try expect_spellbook_error(
        \\spellbook G:
        \\  power Spark
        \\  element Ember
        \\  form Bolt
        \\  charm Kindle: Spark, Ember, Bolt
    , "unknown spellbook directive 'charm'");
}

test "P44-05: a decision declaration reads its actor, cue, trigger lines, and scored options" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source =
        \\decision LeadAtTable:
        \\  actor Maren
        \\  fires CardPlayed
        \\  requires Turn(Maren)
        \\  unless Closed(Trick)
        \\  option SaltTwo:
        \\    picks 4 when SuitLed(Salt)
        \\    drops 2 when High(SaltThree)
        \\  option ReedOne:
        \\    picks 1 when NotLast(Maren)
    ;
    var lexer = Lexer.init(arena.allocator(), source);
    defer lexer.deinit();
    var parser = try Parser.init(arena.allocator(), &lexer);
    var ast = try parser.parse_program();
    defer ast.deinit();

    try testing.expectEqual(@as(usize, 1), ast.decisions.items.len);
    const decision = ast.decisions.items[0];
    try testing.expectEqualStrings("LeadAtTable", decision.name);
    try testing.expectEqualStrings("Maren", decision.actor);
    try testing.expectEqualStrings("CardPlayed", decision.cue);
    try testing.expectEqual(@as(usize, 2), decision.clauses.len);
    try testing.expectEqualStrings("Turn", decision.clauses[0].pattern.relation);
    try testing.expectEqual(false, decision.clauses[0].negated);
    try testing.expectEqual(true, decision.clauses[1].negated);
    try testing.expectEqual(@as(usize, 2), decision.options.len);
    try testing.expectEqualStrings("SaltTwo", decision.options[0].name);
    try testing.expectEqual(@as(usize, 2), decision.options[0].picks.len);
    try testing.expectEqual(@as(i32, 4), decision.options[0].picks[0].points);
    try testing.expectEqual(false, decision.options[0].picks[0].negated);
    try testing.expectEqual(@as(i32, -2), decision.options[0].picks[1].points);
    try testing.expectEqualStrings("High", decision.options[0].picks[1].pattern.relation);
    try testing.expectEqualStrings("ReedOne", decision.options[1].name);
}

test "P44-05: parser rejects a decision without a cue, an option without scores, and a repeated option" {
    try expect_decision_error(
        \\decision NoCue:
        \\  actor Maren
        \\  requires Turn(Maren)
        \\  option SaltTwo:
        \\    picks 1 when Open(Table)
    , "needs a cue");
    try expect_decision_error(
        \\decision NoOptions:
        \\  actor Maren
        \\  fires CardPlayed
        \\  requires Turn(Maren)
    , "between 1 and");
    try expect_decision_error(
        \\decision NoScores:
        \\  actor Maren
        \\  fires CardPlayed
        \\  requires Turn(Maren)
        \\  option SaltTwo:
        \\    picks 1 when Open(Table)
        \\  option SaltTwo:
        \\    picks 1 when Open(Table)
    , "declares option 'SaltTwo' twice");
    try expect_decision_error(
        \\decision NoTrigger:
        \\  actor Maren
        \\  fires CardPlayed
        \\  option SaltTwo:
        \\    picks 1 when Open(Table)
    , "at least one 'requires'");
    try expect_decision_error(
        \\decision TooManyPoints:
        \\  actor Maren
        \\  fires CardPlayed
        \\  requires Turn(Maren)
        \\  option SaltTwo:
        \\    picks 101 when Open(Table)
    , "use 1 to");
}

fn expect_decision_error(source: []const u8, needle: []const u8) !void {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try Parser.init(alloc, &lexer);
    try testing.expectError(error.UnexpectedToken, parser.parse_program());
    const diag = parser.get_diagnostic().?;
    if (std.mem.indexOf(u8, diag.message, needle) == null) {
        std.debug.print("diagnostic was: {s}\n", .{diag.message});
        return error.TestUnexpectedResult;
    }
}
