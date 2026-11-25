const std = @import("std");
const Suggestions = @import("diagnostic.zig").Suggestions;
const ListWriter = @import("../list_writer.zig").ListWriter;
const parser_mod = @import("parser.zig");
const lexer_mod = @import("lexer.zig");
const bytecode_mod = @import("../bytecode.zig");
const world_mod = @import("../world.zig");
const save_mod = @import("../save.zig");
const reserved_mod = @import("../reserved.zig");
const spatial_mod = @import("../spatial.zig");

pub const AST = parser_mod.AST;
pub const Stmt = parser_mod.Stmt;
pub const Expr = parser_mod.Expr;
pub const FactPattern = parser_mod.FactPattern;
pub const BytecodeChunk = bytecode_mod.BytecodeChunk;
pub const Opcode = bytecode_mod.Opcode;
pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const SpatialSystem = spatial_mod.SpatialSystem;
pub const WhenEdge = parser_mod.WhenEdge;
const draft_mod = @import("../draft.zig");
const society_mod = @import("../society.zig");
const duel_mod = @import("../duel.zig");
const container_mod = @import("../container.zig");
const grid_mod = @import("../grid.zig");
const agency_mod = @import("../agency.zig");
const hint_mod = @import("../hint.zig");
const spell_mod = @import("../spell.zig");
const decision_mod = @import("../decision.zig");
const value_mod = @import("../value.zig");
const dilemma_mod = @import("../dilemma.zig");
const image_mod = @import("../image.zig");
const command_mod = @import("../command.zig");
const mml = @import("../mml.zig");
const dialogue_lifecycle = @import("../dialogue.zig");
pub const CompiledDraft = draft_mod.CompiledDraft;

/// Compiled reactive simulation rule representation (P8-02, D-010).
pub const CompiledWhenRule = struct {
    clauses: []const world_mod.PatternClause,
    target_entity: EntityId,
    priority: u16,
    handler_pc: usize,
    edge: WhenEdge = .rising,
    /// `when each` (D-170, D-186): fires per row; `owner_slot` is the variable of the first
    /// clause's subject, whose bound entity runs the row's body.
    each: bool = false,
    owner_slot: ?u8 = null,
};

/// Where a cast member starts: the first mark of the scene that lists it (D-065). The program
/// only records this; `host.place_cast` registers the actor, so hosts that place their own
/// actors (the proofs) are unaffected.
pub const CastPlace = struct {
    actor: EntityId,
    mark: spatial_mod.WaypointId,
};

/// Most parameters a cue handler binds: the actor and two targets (D-013).
pub const MAX_CUE_PARAMS = 3;

/// A cue handler's `where` guard (Q-006, D-072). Each variable parameter has a pattern
/// variable slot, filled from the fired cue's arguments before the clauses are joined, so
/// `on cue Steal(Cat, victim) where CharmedBy(victim, _)` asks about the actual victim.
/// Named parameters have no slot: their clauses already hold the entity as a constant.
pub const CueGuard = struct {
    handler_pc: usize,
    param_slots: [MAX_CUE_PARAMS]?u8 = .{ null, null, null },
    clauses: []const world_mod.PatternClause,
};

/// The handler a fired cue runs, with what its body reads (P48-02, D-161): the cue's
/// arguments in the order the handler declares them (a form matched with its targets swapped
/// swaps them back), and the variables its `where` guard bound, by guard slot.
pub const CueMatch = struct {
    pc: usize,
    args: [MAX_CUE_PARAMS]EntityId = .{ .none, .none, .none },
    bindings: world_mod.VariableBindings = .{},
};

/// Stack index of a handler's first guard binding: `bind_cue_args` pushes the three arguments
/// first (D-161).
pub const CUE_BINDING_BASE: u8 = MAX_CUE_PARAMS;

pub const CompiledProgram = struct {
    chunk: BytecodeChunk,
    routine_entries: std.StringHashMap(usize),
    routine_entities: std.StringHashMap([]const u8),
    when_rule_entries: std.array_list.Managed(usize),
    cue_handler_entries: std.StringHashMap(usize),
    allocated_cue_keys: std.array_list.Managed([]const u8),
    /// Owned copies of routine names and entities; a `during` name with spaces is built in the
    /// parser's arena, which is freed before the program is used (P44-07).
    allocated_routine_names: std.array_list.Managed([]const u8),
    reactive_rules: std.array_list.Managed(CompiledWhenRule),
    initial_entry: ?usize = null,
    /// Draft note table (P22-01, D-029). Program data, not world state: never saved in `.sav`.
    drafts: std.array_list.Managed(CompiledDraft),
    /// Script-declared reusable subsystem configuration (P32-22, P32-24).
    societies: std.array_list.Managed(society_mod.Declaration),
    duels: std.array_list.Managed(duel_mod.Declaration),
    degradations: std.array_list.Managed(container_mod.Declaration),
    /// Grid overlays with their initial cell layouts (P25-01, D-054). Geometry is also
    /// registered in the SpatialSystem the program was compiled or loaded into.
    grids: std.array_list.Managed(grid_mod.Declaration),
    /// Agendas in declaration order, which breaks contention ties (P33-01, D-056).
    agendas: std.array_list.Managed(agency_mod.Declaration),
    /// Goals and their needs in declaration order, which is the hint search's tie-break
    /// (P44-01, D-134).
    goals: std.array_list.Managed(hint_mod.Declaration),
    /// Spellbooks with their words and combinations, in declaration order (P44-04).
    spellbooks: std.array_list.Managed(spell_mod.Declaration),
    /// Decisions in declaration order, which breaks score ties and orders choices (P44-05).
    decisions: std.array_list.Managed(decision_mod.Declaration),
    /// Value axes in declaration order (P45-01, D-144). Each bounds its property relation in
    /// the world the program was compiled or loaded into.
    axes: std.array_list.Managed(value_mod.Axis),
    /// Red lines per character, which veto decision options before scoring (P45-02, D-145).
    red_lines: std.array_list.Managed(decision_mod.RedLineDeclaration),
    /// Dilemmas in declaration order (P45-03, D-146).
    dilemmas: std.array_list.Managed(dilemma_mod.Declaration),
    /// Typed-command frames and noun aliases, in declaration order (P26-01, D-057).
    commands: std.array_list.Managed(command_mod.CommandDecl),
    aliases: std.array_list.Managed(command_mod.AliasDecl),
    /// Script music in declaration order, as validated MML text (P28-03, D-062).
    scores: std.array_list.Managed(mml.ScoreDecl),
    /// Each cast member's starting mark, in source order (D-065). Empty without a SpatialSystem.
    cast: std.ArrayListUnmanaged(CastPlace) = .empty,
    /// `where` guards of cue handlers, in source order (D-072). Handlers without one are absent.
    cue_guards: std.ArrayListUnmanaged(CueGuard) = .empty,
    /// Handlers that share a signature, in source order (D-160): `cue_handler_entries` names
    /// the first, and this maps each handler's pc to the next one's. A failed guard falls
    /// through along the chain before the search moves to a broader signature. Owned by
    /// `chunk.allocator`.
    cue_handler_chain: std.AutoHashMapUnmanaged(usize, usize) = .empty,
    /// The script's `save version N` (P48-08, D-162), 1 when it declares none.
    save_version: u32 = 1,
    /// `rewinds reroll`: a rewind restores everything but the dice (D-184).
    rewinds_reroll: bool = false,
    /// `clock: turns` (D-188): hosts advance the clock only when the player acts.
    turn_clock: bool = false,
    /// Identifies this build for saves (D-162): see `program_fingerprint`. Never 0 once compiled
    /// or loaded, since 0 marks a save whose program is unknown.
    fingerprint: u64 = 0,
    /// The game's palette and indexed images (P46-01, D-152). Presentation only: never written
    /// to the world, so it cannot change a replay. Owned by `chunk.allocator`.
    art: image_mod.Art = .{},

    /// Which build this is, for saves to record and loads to check (D-162).
    pub fn identity(self: *const CompiledProgram) save_mod.ProgramIdentity {
        return .{ .fingerprint = self.fingerprint, .save_version = self.save_version };
    }

    pub fn deinit(self: *CompiledProgram) void {
        self.art.deinit_owned(self.chunk.allocator);
        for (self.cue_guards.items) |guard| self.chunk.allocator.free(guard.clauses);
        self.cue_guards.deinit(self.chunk.allocator);
        self.cue_handler_chain.deinit(self.chunk.allocator);
        self.cast.deinit(self.chunk.allocator);
        for (self.scores.items) |*score| score.deinit_owned(self.chunk.allocator);
        self.scores.deinit();
        for (self.societies.items) |*society| society.deinit_owned(self.chunk.allocator);
        self.societies.deinit();
        for (self.duels.items) |*duel| duel.deinit_owned(self.chunk.allocator);
        self.duels.deinit();
        for (self.degradations.items) |*degradation| degradation.deinit_owned(self.chunk.allocator);
        self.degradations.deinit();
        for (self.grids.items) |*grid| grid.deinit_owned(self.chunk.allocator);
        self.grids.deinit();
        for (self.agendas.items) |*agenda| agenda.deinit_owned(self.chunk.allocator);
        self.agendas.deinit();
        for (self.goals.items) |*goal| goal.deinit_owned(self.chunk.allocator);
        self.goals.deinit();
        for (self.spellbooks.items) |*book| book.deinit_owned(self.chunk.allocator);
        self.spellbooks.deinit();
        for (self.decisions.items) |*decision| decision.deinit_owned(self.chunk.allocator);
        self.decisions.deinit();
        self.axes.deinit();
        for (self.red_lines.items) |*decl| decl.deinit_owned(self.chunk.allocator);
        self.red_lines.deinit();
        for (self.dilemmas.items) |*decl| decl.deinit_owned(self.chunk.allocator);
        self.dilemmas.deinit();
        for (self.commands.items) |*c| c.deinit_owned(self.chunk.allocator);
        self.commands.deinit();
        for (self.aliases.items) |*a| a.deinit_owned(self.chunk.allocator);
        self.aliases.deinit();
        self.drafts.deinit();
        self.chunk.deinit();
        self.routine_entries.deinit();
        self.routine_entities.deinit();
        self.when_rule_entries.deinit();
        self.cue_handler_entries.deinit();
        for (self.allocated_cue_keys.items) |k| {
            self.chunk.allocator.free(k);
        }
        self.allocated_cue_keys.deinit();
        for (self.allocated_routine_names.items) |name| {
            self.chunk.allocator.free(name);
        }
        self.allocated_routine_names.deinit();
        for (self.reactive_rules.items) |r| {
            self.chunk.allocator.free(r.clauses);
        }
        self.reactive_rules.deinit();
    }

    /// Finds the handler for `Weave(caster, draft, target)` (P22-01, D-029). Matching is exact and
    /// ordered: unlike `find_cue_handler` it neither swaps operands (draft and target are not
    /// commutative) nor falls back to the bare cue name, because a fallback would run some other
    /// draft's effect where the weave should fizzle. A two-parameter `Weave(caster, draft)`
    /// handler serves as a target-agnostic effect.
    pub fn find_weave_handler(
        self: *const CompiledProgram,
        caster: []const u8,
        draft: []const u8,
        target: []const u8,
    ) ?usize {
        var buf: [256]u8 = undefined;
        if (std.fmt.bufPrint(&buf, "{s}:{s}:{s}:{s}", .{ draft_mod.WEAVE_CUE, caster, draft, target })) |sig| {
            if (self.cue_handler_entries.get(sig)) |pc| return pc;
        } else |_| {}
        if (std.fmt.bufPrint(&buf, "{s}:{s}:{s}", .{ draft_mod.WEAVE_CUE, caster, draft })) |sig| {
            if (self.cue_handler_entries.get(sig)) |pc| return pc;
        } else |_| {}
        return null;
    }

    pub fn find_draft_by_notes(self: *const CompiledProgram, notes: draft_mod.Notes) ?CompiledDraft {
        return draft_mod.find_by_notes(self.drafts.items, notes);
    }

    pub fn find_draft(self: *const CompiledProgram, entity: EntityId) ?CompiledDraft {
        return draft_mod.find_by_entity(self.drafts.items, entity);
    }

    /// Entry point of a path's fact initializer, or null when the script declares no such path.
    /// Path routines use ordinary routine names; only the initializer needs the reserved key.
    pub fn find_path(self: *const CompiledProgram, name: []const u8) ?usize {
        var buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}{s}", .{ PATH_ROUTINE_PREFIX, name }) catch return null;
        return self.routine_entries.get(key);
    }

    /// Finds the handler for a fired cue by name alone, without evaluating `where` guards
    /// (D-009, D-013, D-037). Hosts dispatch through `select_cue_handler`, which also checks
    /// guards; this form answers "which handler does this signature name".
    pub fn find_cue_handler(
        self: *const CompiledProgram,
        cue_name: []const u8,
        actor: ?[]const u8,
        target_a: ?[]const u8,
        target_b: ?[]const u8,
    ) ?usize {
        const who = actor orelse return null;
        const found = self.resolve_cue(null, cue_name, who, target_a, target_b, .{ .none, .none, .none }) orelse return null;
        return found.pc;
    }

    /// Finds the handler a fired cue runs (D-009, D-013, D-037, D-072). Tried in order, most
    /// specific first: the exact signature (for two targets, also with the targets swapped),
    /// signatures whose parameters were declared as variables (stored as `*`), then the
    /// actor-only handler `on cue X(Actor):`. A handler with a `where` guard is taken only if the
    /// guard holds with its variable parameters bound to this cue's arguments; otherwise the
    /// search continues with the next, less specific signature. A cue no declared signature
    /// covers has no handler: there is no fallback to a handler written for a different actor
    /// or target.
    pub fn select_cue_handler(
        self: *const CompiledProgram,
        world: *const World,
        cue_name: []const u8,
        actor: EntityId,
        target_a: ?EntityId,
        target_b: ?EntityId,
    ) ?usize {
        const found = self.select_cue_match(world, cue_name, actor, target_a, target_b) orelse return null;
        return found.pc;
    }

    /// `select_cue_handler` with what the chosen handler's body reads (D-161).
    pub fn select_cue_match(
        self: *const CompiledProgram,
        world: *const World,
        cue_name: []const u8,
        actor: EntityId,
        target_a: ?EntityId,
        target_b: ?EntityId,
    ) ?CueMatch {
        const who = world.get_entity_name(actor) orelse return null;
        const name_a = if (target_a) |ta| world.get_entity_name(ta) else null;
        const name_b = if (target_b) |tb| world.get_entity_name(tb) else null;
        return self.resolve_cue(world, cue_name, who, name_a, name_b, .{
            actor,
            target_a orelse .none,
            target_b orelse .none,
        });
    }

    /// One search over the signature forms. With a World, each found handler's guard is checked
    /// against `ids`, reordered to match the form: a swapped form binds the second parameter
    /// to the second target, so a guard reads the arguments in the order its handler declares.
    fn resolve_cue(
        self: *const CompiledProgram,
        world: ?*const World,
        cue_name: []const u8,
        who: []const u8,
        target_a: ?[]const u8,
        target_b: ?[]const u8,
        ids: [3]EntityId,
    ) ?CueMatch {
        const straight = [3]EntityId{ ids[0], ids[1], ids[2] };
        const swapped = [3]EntityId{ ids[0], ids[2], ids[1] };

        if (target_a != null and target_b != null) {
            const a = target_a.?;
            const b = target_b.?;
            const Form = struct { parts: [3][]const u8, swap: bool };
            const forms = [_]Form{
                .{ .parts = .{ who, a, b }, .swap = false },                       .{ .parts = .{ who, b, a }, .swap = true },
                .{ .parts = .{ who, a, CUE_WILDCARD }, .swap = false },            .{ .parts = .{ who, CUE_WILDCARD, b }, .swap = false },
                .{ .parts = .{ who, b, CUE_WILDCARD }, .swap = true },             .{ .parts = .{ who, CUE_WILDCARD, a }, .swap = true },
                .{ .parts = .{ who, CUE_WILDCARD, CUE_WILDCARD }, .swap = false }, .{ .parts = .{ CUE_WILDCARD, a, b }, .swap = false },
                .{ .parts = .{ CUE_WILDCARD, b, a }, .swap = true },               .{ .parts = .{ CUE_WILDCARD, CUE_WILDCARD, CUE_WILDCARD }, .swap = false },
            };
            for (forms) |f| {
                if (self.first_admitted(world, self.lookup_cue(cue_name, &f.parts), if (f.swap) &swapped else &straight)) |pc| return pc;
            }
        }

        if (target_a) |a| {
            const forms = [_][2][]const u8{
                .{ who, a },
                .{ who, CUE_WILDCARD },
                .{ CUE_WILDCARD, a },
                .{ CUE_WILDCARD, CUE_WILDCARD },
            };
            for (forms) |f| {
                if (self.first_admitted(world, self.lookup_cue(cue_name, &f), straight[0..2])) |pc| return pc;
            }
        }

        if (self.first_admitted(world, self.lookup_cue(cue_name, &.{who}), straight[0..1])) |pc| return pc;
        if (self.first_admitted(world, self.lookup_cue(cue_name, &.{CUE_WILDCARD}), straight[0..1])) |pc| return pc;
        return null;
    }

    /// The first handler of one signature, in source order, whose guard admits `args`
    /// (D-160). Starts at `head`, the handler `cue_handler_entries` names, and follows the
    /// chain; null when every handler of the signature declines.
    fn first_admitted(self: *const CompiledProgram, world: ?*const World, head: ?usize, args: []const EntityId) ?CueMatch {
        var next = head;
        while (next) |pc| : (next = self.cue_handler_chain.get(pc)) {
            if (self.guard_admits(world, pc, args)) |bindings| {
                var found = CueMatch{ .pc = pc, .bindings = bindings };
                for (args, 0..) |arg, i| found.args[i] = arg;
                return found;
            }
        }
        return null;
    }

    /// The `where` guard of the handler at `pc`, if it has one (D-072).
    pub fn find_cue_guard(self: *const CompiledProgram, pc: usize) ?*const CueGuard {
        for (self.cue_guards.items) |*guard| {
            if (guard.handler_pc == pc) return guard;
        }
        return null;
    }

    /// The guard's bindings when the handler at `pc` has no guard (none), no World was given
    /// (name-only lookup), or its guard's clauses match the World with each variable parameter
    /// bound to its argument; null when the guard fails.
    fn guard_admits(self: *const CompiledProgram, world: ?*const World, pc: usize, args: []const EntityId) ?world_mod.VariableBindings {
        const w = world orelse return .{};
        const guard = self.find_cue_guard(pc) orelse return .{};
        var bindings = world_mod.VariableBindings{};
        for (guard.param_slots, 0..) |slot, i| {
            const s = slot orelse continue;
            if (i >= args.len) return null;
            if (!bindings.set(s, args[i].to_int())) return null;
        }
        return w.find_first_match_from(guard.clauses, bindings);
    }

    fn lookup_cue(self: *const CompiledProgram, cue_name: []const u8, parts: []const []const u8) ?usize {
        var buf: [192]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        w.writeAll(cue_name) catch return null;
        for (parts) |part| {
            w.writeByte(':') catch return null;
            w.writeAll(part) catch return null;
        }
        return self.cue_handler_entries.get(w.buffered());
    }
};

/// A build's fingerprint (P48-08, D-162): its bytecode and the world's entity and relation
/// names in id order, which together fix what every id in the bytecode means. A comment or a
/// blank line changes neither; any change to what the program does or names changes one. The
/// package loader recomputes it the same way for packages that predate the field.
pub fn program_fingerprint(code: []const u8, world: *const World) u64 {
    var h = std.hash.Wyhash.init(0x6265_7370_6f6b_6531);
    h.update(code);
    for (world.entity_names.items) |name| {
        h.update(name);
        h.update(&.{0});
    }
    h.update(&.{0xff});
    for (world.relation_meta.items) |meta| {
        h.update(meta.name);
        h.update(&.{ 0, @intFromEnum(meta.rel_type) });
    }
    const value = h.final();
    return if (value == 0) 1 else value;
}

/// The reserved property that picks a thing's look (P48-11, D-181).
pub const LOOKS_RELATION = "Looks";

/// A lowercase first letter marks a variable wherever a name of a thing can stand (D-037,
/// D-161). `true` and `false` are values, not names.
pub fn is_variable_name(name: []const u8) bool {
    if (name.len == 0 or !std.ascii.isLower(name[0])) return false;
    return !std.mem.eql(u8, name, "true") and !std.mem.eql(u8, name, "false");
}

/// True when any text in `value`, a parsed statement or anything inside one, is exactly
/// `name`. Conservative: dialogue text that happens to equal the name also counts, which only
/// costs a handler an unneeded `bind_cue_args`.
fn mentions(value: anytype, name: []const u8) bool {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .slice) {
                if (ptr.child == u8) return std.mem.eql(u8, value, name);
                for (value) |item| {
                    if (mentions(item, name)) return true;
                }
                return false;
            }
            if (ptr.size == .one) return mentions(value.*, name);
            return false;
        },
        .@"struct" => |st| {
            inline for (st.field_names) |field_name| {
                if (mentions(@field(value, field_name), name)) return true;
            }
            return false;
        },
        .@"union" => {
            switch (value) {
                inline else => |payload| return mentions(payload, name),
            }
        },
        .optional => return if (value) |inner| mentions(inner, name) else false,
        else => return false,
    }
}

/// Stands in a handler signature for a parameter declared as a variable (D-037).
pub const CUE_WILDCARD = "*";

/// Routine-table key for a path's fact initializer. The `#` prefix cannot appear in a DSL
/// identifier, so it cannot collide with a routine name (P24-01).
pub const PATH_ROUTINE_PREFIX = "#path:";

/// A cue handler parameter is a variable when it starts with `?`, `_`, or a lowercase letter,
/// the same rule `when` trigger patterns use. Entity names start with an uppercase letter.
fn cue_param_key(param: []const u8) []const u8 {
    if (param.len == 0) return CUE_WILDCARD;
    return if (param[0] == '?' or param[0] == '_' or std.ascii.isLower(param[0])) CUE_WILDCARD else param;
}

pub const Warning = struct {
    context: []const u8,
    message: []const u8,
};

pub const Codegen = struct {
    // Borrowed AST text, mapped back to the source by the checker before the arena is freed.
    // These fields never enter CompiledProgram.
    error_context: []const u8 = "",
    error_suggestion: ?[]const u8 = null,
    /// Set with the context when the error points at a parsed name, including a quoted or
    /// multi-word name the parser built in its arena.
    error_line: u32 = 0,
    error_column: u32 = 0,
    /// A second source name the diagnostic cites, such as the earlier handler that makes a
    /// later one unreachable (D-160). Mapped to a line by the checker, like `error_context`.
    error_related: []const u8 = "",
    /// Looks named in `remember Looks(...)` lines, checked against the declared looks (D-181).
    look_uses: std.ArrayListUnmanaged([]const u8) = .empty,
    /// Things worth an author's attention that do not stop the compile (P48-10, D-180). Each
    /// names the source text it is about, mapped to a line by the checker.
    warnings: std.ArrayListUnmanaged(Warning) = .empty,
    /// The engine's author-facing relations, with the release that added each; a test may
    /// substitute its own (D-180).
    engine_relations: []const reserved_mod.AuthorRelation = &reserved_mod.AUTHOR_FACING,
    /// Backs `error_suggestion` when the help is built rather than found, such as the
    /// capitalised spelling of an unbound lowercase name (D-161).
    suggestion_buf: [64]u8 = undefined,
    /// While a cue handler body compiles: each name its body may read, with the stack index
    /// `bind_cue_args` puts it at (D-161). Null in every other body.
    locals: ?*const std.StringHashMap(u8) = null,
    /// While a `when` rule body compiles: the rule's trigger patterns, so a variable from
    /// them is reported as unbindable rather than unbound (D-161).
    when_patterns: ?[]const parser_mod.FactPattern = null,
    allocator: std.mem.Allocator,
    world: *World,
    spatial: ?*SpatialSystem,
    chunk: BytecodeChunk,
    routine_entries: std.StringHashMap(usize),
    routine_entities: std.StringHashMap([]const u8),
    when_rule_entries: std.array_list.Managed(usize),
    cue_handler_entries: std.StringHashMap(usize),
    allocated_cue_keys: std.array_list.Managed([]const u8),
    allocated_routine_names: std.array_list.Managed([]const u8),
    reactive_rules: std.array_list.Managed(CompiledWhenRule),
    societies: std.array_list.Managed(society_mod.Declaration),
    duels: std.array_list.Managed(duel_mod.Declaration),
    degradations: std.array_list.Managed(container_mod.Declaration),
    grids: std.array_list.Managed(grid_mod.Declaration),
    agendas: std.array_list.Managed(agency_mod.Declaration),
    goals: std.array_list.Managed(hint_mod.Declaration),
    spellbooks: std.array_list.Managed(spell_mod.Declaration),
    decisions: std.array_list.Managed(decision_mod.Declaration),
    axes: std.array_list.Managed(value_mod.Axis),
    red_lines: std.array_list.Managed(decision_mod.RedLineDeclaration),
    dilemmas: std.array_list.Managed(dilemma_mod.Declaration),
    commands: std.array_list.Managed(command_mod.CommandDecl),
    aliases: std.array_list.Managed(command_mod.AliasDecl),
    scores: std.array_list.Managed(mml.ScoreDecl),
    cast: std.ArrayListUnmanaged(CastPlace) = .empty,
    cue_guards: std.ArrayListUnmanaged(CueGuard) = .empty,
    cue_handler_chain: std.AutoHashMapUnmanaged(usize, usize) = .empty,

    pub fn init(allocator: std.mem.Allocator, world: *World, spatial: ?*SpatialSystem) Codegen {
        return Codegen{
            .allocator = allocator,
            .world = world,
            .spatial = spatial,
            .chunk = BytecodeChunk.init(allocator),
            .routine_entries = std.StringHashMap(usize).init(allocator),
            .routine_entities = std.StringHashMap([]const u8).init(allocator),
            .when_rule_entries = std.array_list.Managed(usize).init(allocator),
            .cue_handler_entries = std.StringHashMap(usize).init(allocator),
            .allocated_cue_keys = std.array_list.Managed([]const u8).init(allocator),
            .allocated_routine_names = std.array_list.Managed([]const u8).init(allocator),
            .reactive_rules = std.array_list.Managed(CompiledWhenRule).init(allocator),
            .societies = std.array_list.Managed(society_mod.Declaration).init(allocator),
            .duels = std.array_list.Managed(duel_mod.Declaration).init(allocator),
            .degradations = std.array_list.Managed(container_mod.Declaration).init(allocator),
            .grids = std.array_list.Managed(grid_mod.Declaration).init(allocator),
            .agendas = std.array_list.Managed(agency_mod.Declaration).init(allocator),
            .goals = std.array_list.Managed(hint_mod.Declaration).init(allocator),
            .spellbooks = std.array_list.Managed(spell_mod.Declaration).init(allocator),
            .decisions = std.array_list.Managed(decision_mod.Declaration).init(allocator),
            .axes = std.array_list.Managed(value_mod.Axis).init(allocator),
            .red_lines = std.array_list.Managed(decision_mod.RedLineDeclaration).init(allocator),
            .dilemmas = std.array_list.Managed(dilemma_mod.Declaration).init(allocator),
            .commands = std.array_list.Managed(command_mod.CommandDecl).init(allocator),
            .aliases = std.array_list.Managed(command_mod.AliasDecl).init(allocator),
            .scores = std.array_list.Managed(mml.ScoreDecl).init(allocator),
        };
    }

    /// Adds a cue handler under its signature key (D-160). The first handler of a signature is
    /// the key's entry; each later one is chained after the last, in source order, so a failed
    /// guard falls through to it. A handler after an unguarded one of the same signature could
    /// never run, so it is refused, citing the earlier handler. Takes ownership of `sig`.
    fn register_cue_handler(
        mut_self: *Codegen,
        sources: *std.AutoHashMap(usize, parser_mod.CueHandler),
        sig: []const u8,
        cue: parser_mod.CueHandler,
        entry_pc: usize,
    ) !void {
        try sources.put(entry_pc, cue);
        const head = mut_self.cue_handler_entries.get(sig) orelse {
            errdefer mut_self.allocator.free(sig);
            try mut_self.allocated_cue_keys.append(sig);
            try mut_self.cue_handler_entries.put(sig, entry_pc);
            return;
        };
        mut_self.allocator.free(sig);
        var tail = head;
        while (true) {
            const earlier = sources.get(tail).?;
            if (earlier.where_patterns.len == 0) {
                mut_self.error_related = earlier.cue_name;
                return error.UnreachableCueHandler;
            }
            tail = mut_self.cue_handler_chain.get(tail) orelse break;
        }
        try mut_self.cue_handler_chain.put(mut_self.allocator, tail, entry_pc);
    }

    /// Compiles an entire AST into a CompiledProgram (P4-03).
    /// Registers a routine under owned copies of its name and entity. Single-word names point
    /// into the source, which outlives the program, but a `during` name with spaces is built in
    /// the parser's arena and would dangle once `compile_source` frees it (P44-07).
    fn register_routine(mut_self: *Codegen, routine: parser_mod.Routine, entry_pc: usize) !void {
        // Top-level, path, and `during` declarations share one name space. A later declaration
        // would silently replace an earlier entry, so refuse it at the duplicate itself.
        if (mut_self.routine_entries.contains(routine.name)) {
            mut_self.error_line = routine.line;
            mut_self.error_column = routine.column;
            return error.DuplicateRoutineName;
        }
        const name = try mut_self.chunk.allocator.dupe(u8, routine.name);
        const entity = try mut_self.chunk.allocator.dupe(u8, routine.entity);
        try mut_self.allocated_routine_names.append(name);
        try mut_self.allocated_routine_names.append(entity);
        try mut_self.routine_entries.put(name, entry_pc);
        try mut_self.routine_entities.put(name, entity);
    }

    pub fn compile(mut_self: *Codegen, ast: *const AST) !CompiledProgram {
        // The look names borrow AST text and are checked before compile returns, so the list
        // lives only for this call.
        defer mut_self.look_uses.deinit(mut_self.allocator);
        // 1. Intern declared entities, scenes, cast, props, marks
        for (ast.entities.items) |name| {
            try mut_self.check_thing_name(name);
            mut_self.error_context = name;
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.scenes.items) |name| {
            mut_self.error_context = name;
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.cast.items) |name| {
            mut_self.error_context = name;
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.props.items) |name| {
            mut_self.error_context = name;
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.marks.items) |name| {
            mut_self.error_context = name;
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.paths.items) |path| {
            mut_self.error_context = path.name;
            _ = try mut_self.world.intern_entity(path.name);
        }

        // Register stage marks and props in SpatialSystem if present
        if (mut_self.spatial) |sp| {
            if (ast.scene_defs.items.len > 0) {
                for (ast.scene_defs.items) |*sc_def| {
                    const sent = mut_self.world.lookup_entity(sc_def.name) orelse try mut_self.world.intern_entity(sc_def.name);
                    var prev_wp: ?u16 = null;
                    var first_wp: ?u16 = null;
                    for (sc_def.marks.items, 0..) |mname, idx| {
                        const wx: i32 = stage_x(idx, sc_def.marks.items.len);
                        var found = false;
                        for (sp.graph.waypoints.items) |wp| {
                            if (std.mem.eql(u8, wp.name, mname)) {
                                found = true;
                                prev_wp = wp.id;
                                break;
                            }
                        }
                        if (!found) {
                            const wp_id = try sp.graph.add_waypoint(sent, wx, 0, mname);
                            if (prev_wp) |p| {
                                sp.graph.connect(p, wp_id, null) catch {};
                            }
                            prev_wp = wp_id;
                        }
                        if (idx == 0) first_wp = prev_wp;
                    }

                    for (sc_def.props.items, 0..) |pname, idx| {
                        const pent = mut_self.world.lookup_entity(pname) orelse try mut_self.world.intern_entity(pname);
                        const px: i32 = 10 + stage_x(idx, sc_def.props.items.len);
                        sp.add_hotspot(pent, sent, .{ .x = px, .y = -6 }, 10, pname, pname) catch {};
                    }

                    // A cast member starts on the first mark of the first scene that lists it
                    // (D-065). A scene without marks has nowhere to put anyone.
                    if (first_wp) |start| {
                        for (sc_def.cast.items) |cname| {
                            const cent = mut_self.world.lookup_entity(cname) orelse try mut_self.world.intern_entity(cname);
                            const seen = for (mut_self.cast.items) |c| {
                                if (c.actor.to_int() == cent.to_int()) break true;
                            } else false;
                            if (!seen) try mut_self.cast.append(mut_self.allocator, .{ .actor = cent, .mark = start });
                        }
                    }
                }
            } else {
                const sent = if (ast.scenes.items.len > 0)
                    mut_self.world.lookup_entity(ast.scenes.items[0]) orelse try mut_self.world.intern_entity(ast.scenes.items[0])
                else
                    try mut_self.world.intern_entity("DefaultScene");

                var prev_wp: ?u16 = null;
                for (ast.marks.items, 0..) |mname, idx| {
                    const wx: i32 = stage_x(idx, ast.marks.items.len);
                    var found = false;
                    for (sp.graph.waypoints.items) |wp| {
                        if (std.mem.eql(u8, wp.name, mname)) {
                            found = true;
                            prev_wp = wp.id;
                            break;
                        }
                    }
                    if (!found) {
                        const wp_id = try sp.graph.add_waypoint(sent, wx, 0, mname);
                        if (prev_wp) |p| {
                            sp.graph.connect(p, wp_id, null) catch {};
                        }
                        prev_wp = wp_id;
                    }
                }

                for (ast.props.items, 0..) |pname, idx| {
                    const pent = mut_self.world.lookup_entity(pname) orelse try mut_self.world.intern_entity(pname);
                    const px: i32 = 10 + stage_x(idx, ast.props.items.len);
                    sp.add_hotspot(pent, sent, .{ .x = px, .y = -6 }, 10, pname, pname) catch {};
                }
            }
        }

        for (ast.societies.items) |decl| {
            mut_self.error_context = decl.name;
            try mut_self.societies.append(try mut_self.compile_society(decl));
        }
        for (ast.duels.items) |decl| {
            mut_self.error_context = decl.name;
            try mut_self.duels.append(try mut_self.compile_duel(decl));
        }
        for (ast.degradations.items) |decl| {
            mut_self.error_context = decl.name;
            try mut_self.degradations.append(try mut_self.compile_degradation(decl));
        }
        for (ast.grids.items) |decl| {
            mut_self.error_context = decl.name;
            try mut_self.grids.append(try mut_self.compile_grid(decl));
        }
        for (ast.agendas.items) |decl| {
            mut_self.error_context = decl.name;
            try mut_self.agendas.append(try mut_self.compile_agenda(decl));
        }
        try agency_mod.validate_all(mut_self.agendas.items);
        for (ast.goals.items) |decl| {
            mut_self.error_context = decl.name;
            try mut_self.goals.append(try mut_self.compile_goal(decl, ast.scene_defs.items));
        }
        try hint_mod.validate_all(mut_self.goals.items);
        for (ast.spellbooks.items) |decl| {
            mut_self.error_context = decl.name;
            try mut_self.spellbooks.append(try mut_self.compile_spellbook(decl));
        }
        try spell_mod.validate_all(mut_self.spellbooks.items);
        for (ast.decisions.items) |decl| {
            mut_self.error_context = decl.name;
            try mut_self.decisions.append(try mut_self.compile_decision(decl));
        }
        try decision_mod.validate_all(mut_self.decisions.items);
        for (ast.red_lines.items) |decl| {
            mut_self.error_context = decl.actor;
            const options = try mut_self.allocator.alloc(EntityId, decl.options.len);
            for (decl.options, 0..) |name, i| options[i] = try mut_self.world.intern_entity(name);
            mut_self.red_lines.append(.{ .red_lines = .{
                .actor = try mut_self.world.intern_entity(decl.actor),
                .options = options,
            } }) catch |err| {
                mut_self.allocator.free(options);
                return err;
            };
            // Validating each prefix points the diagnostic at the declaration that broke it:
            // every check only gets stricter as red lines are added.
            decision_mod.validate_red_lines(mut_self.decisions.items, mut_self.red_lines.items) catch return error.InvalidRedLine;
        }
        for (ast.commands.items) |decl| {
            mut_self.error_context = decl.text;
            try mut_self.commands.append(try mut_self.compile_command(decl));
        }
        for (ast.aliases.items) |decl| {
            mut_self.error_context = decl.entity;
            try mut_self.aliases.append(try mut_self.compile_alias(decl));
        }
        for (ast.scores.items) |decl| {
            mut_self.error_context = decl.name;
            var owned = try mml.ScoreDecl.dupe(mut_self.allocator, decl);
            mut_self.scores.append(owned) catch |err| {
                owned.deinit_owned(mut_self.allocator);
                return err;
            };
        }

        // 2. Intern declared relations
        for (ast.relations.items) |rel| {
            try mut_self.check_thing_name(rel.name);
            mut_self.error_context = rel.name;
            const declared = try mut_self.world.intern_relation(
                rel.name,
                if (rel.is_property) .property else .set,
            );
            // A name a later engine release adopted stays the script's own (D-180).
            if (reserved_mod.newer_than_language(mut_self.engine_relations, rel.name)) |entry| {
                mut_self.world.claim_relation(declared);
                const message = try std.fmt.allocPrint(mut_self.allocator, "BeSpoke {d}.{d} also uses '{s}'; this game keeps its own, and the engine's '{s}' is off for it", .{ entry.since.major, entry.since.minor, rel.name, rel.name });
                try mut_self.warnings.append(mut_self.allocator, .{ .context = rel.name, .message = message });
            }
        }
        // Axes are interned before any statement, so a `remember` on one meets a bounded
        // property wherever it appears (P45-01, D-144). An axis may not reuse a declared
        // relation's name: the two declarations would disagree on what the value slot means.
        for (ast.axes.items) |decl| {
            mut_self.error_context = decl.name;
            for (ast.relations.items) |rel| {
                if (std.mem.eql(u8, rel.name, decl.name)) return error.InvalidAxis;
            }
            var axis = try value_mod.declare(mut_self.world, decl.name, decl.poles);
            if (decl.drift_step) |step| axis.drift_step = step;
            try mut_self.axes.append(axis);
        }
        value_mod.validate_all(mut_self.world, mut_self.axes.items) catch return error.InvalidAxis;
        // Dilemmas weigh declared axes, so they compile once the axes are bounded (P45-03).
        for (ast.dilemmas.items) |decl| {
            mut_self.error_context = decl.name;
            try mut_self.dilemmas.append(try mut_self.compile_dilemma(decl));
            dilemma_mod.validate_all(mut_self.world, mut_self.dilemmas.items, mut_self.decisions.items, mut_self.red_lines.items) catch return error.InvalidDilemma;
        }
        if (ast.paths.items.len > 0) {
            _ = try mut_self.world.intern_relation("PathActive", .property);
        }
        // Music relations (P28-03, D-062): interned before any statement so `PlayingScore` is a
        // property (one score at a time) even where a rule mentions it first.
        if (ast.scores.items.len > 0) {
            _ = try mut_self.world.intern_relation_kind(mml.PLAYING_RELATION, .property, .entity);
            _ = try mut_self.world.intern_relation_kind(mml.SCENE_RELATION, .set, .entity);
            _ = try mut_self.world.intern_entity(mml.MUSIC_ENTITY);
        }

        // 2b. Build the draft note table; a declared reverse becomes its own entry (D-029)
        var drafts = std.array_list.Managed(CompiledDraft).init(mut_self.allocator);
        errdefer drafts.deinit();
        for (ast.drafts.items) |d| {
            mut_self.error_context = d.name;
            const ent = try mut_self.world.intern_entity(d.name);
            const inv: ?EntityId = if (d.reverse_name) |rn| try mut_self.world.intern_entity(rn) else null;
            try drafts.append(.{ .entity = ent, .notes = d.notes, .inverse = inv });
            if (inv) |ie| {
                try drafts.append(.{ .entity = ie, .notes = draft_mod.reversed(d.notes), .inverse = ent });
            }
        }

        // 3. Compile initial declarative statements
        var initial_entry: ?usize = null;
        var scene_bindings: usize = 0;
        for (ast.scores.items) |decl| scene_bindings += decl.scenes.len;
        if (ast.initial_stmts.items.len > 0 or scene_bindings > 0) {
            mut_self.error_context = "";
            initial_entry = mut_self.chunk.count();
            // Scene defaults are World facts, seeded before the script's own statements, so the
            // display can pick a scene's score from World alone and saves carry the binding.
            for (ast.scores.items) |decl| {
                const score_entity = try mut_self.world.intern_entity(decl.name);
                const scene_rel = try mut_self.world.intern_relation_kind(mml.SCENE_RELATION, .set, .entity);
                for (decl.scenes) |scene| {
                    try mut_self.chunk.emit_push_entity(try mut_self.world.intern_entity(scene));
                    try mut_self.chunk.emit_push_relation(scene_rel);
                    try mut_self.chunk.emit_push_const(score_entity.to_int());
                    try mut_self.chunk.emit_remember(0);
                }
            }
            for (ast.initial_stmts.items) |stmt| {
                try mut_self.compile_stmt(stmt);
            }
            _ = try mut_self.chunk.emit_op(.halt);
        }

        // 4. Compile routines
        for (ast.routines.items) |routine| {
            mut_self.error_context = routine.name;
            const entry_pc = mut_self.chunk.count();
            try mut_self.register_routine(routine, entry_pc);

            for (routine.body) |stmt| {
                try mut_self.compile_stmt(stmt);
            }
            _ = try mut_self.chunk.emit_op(.halt);
        }

        // 4b. Compile path initializers and guarded path routines (P24-01). The initializer runs
        // after PathActive is asserted; a path routine checks that fact before its first body
        // instruction, so spawning an inactive route halts without touching the world.
        if (ast.paths.items.len > 0) {
            const path_active = try mut_self.world.intern_relation("PathActive", .property);
            for (ast.paths.items) |path| {
                mut_self.error_context = path.name;
                const path_entity = try mut_self.world.intern_entity(path.name);
                const init_key = try std.fmt.allocPrint(mut_self.allocator, "{s}{s}", .{ PATH_ROUTINE_PREFIX, path.name });
                if (mut_self.routine_entries.contains(init_key)) return error.DuplicateRoutineName;
                try mut_self.allocated_cue_keys.append(init_key);
                try mut_self.routine_entries.put(init_key, mut_self.chunk.count());
                try mut_self.routine_entities.put(init_key, path.name);

                for (path.facts) |stmt| {
                    try mut_self.compile_stmt(stmt);
                }
                _ = try mut_self.chunk.emit_op(.halt);

                for (path.routines) |routine| {
                    mut_self.error_context = routine.name;
                    try mut_self.register_routine(routine, mut_self.chunk.count());

                    const guard_pc = try mut_self.emit_path_guard(path_entity, path_active);
                    for (routine.body) |stmt| {
                        try mut_self.compile_stmt(stmt);
                    }
                    const halt_pc = mut_self.chunk.count();
                    _ = try mut_self.chunk.emit_op(.halt);
                    const offset: i16 = @intCast(halt_pc - (guard_pc + 3));
                    std.mem.writeInt(i16, mut_self.chunk.code.items[guard_pc + 1 ..][0..2], offset, .little);
                }
            }
        }

        // 5. Compile when rules into reactive simulation rules (P8-02, D-010)
        for (ast.when_rules.items) |rule| {
            mut_self.error_context = "";
            var var_map = std.StringHashMap(u8).init(mut_self.allocator);
            defer var_map.deinit();
            var next_var: u8 = 0;

            var clauses = std.array_list.Managed(world_mod.PatternClause).init(mut_self.allocator);
            for (rule.trigger_patterns) |pat| {
                mut_self.error_context = pat.relation;
                const rel = try mut_self.resolve_relation(pat.relation);
                if (rule.edge == .on_arrive) {
                    // An arrival trigger names an actor and a mark, not a fact: the object is
                    // the mark's waypoint id, matched against the motor agent (D-036).
                    const actor = try mut_self.resolve_entity(pat.args[0]);
                    const mark = mut_self.find_waypoint(pat.args[1]) orelse return error.UnknownArrivalMark;
                    try clauses.append(.{
                        .relation = rel,
                        .subject = .{ .constant = actor.to_int() },
                        .object = .{ .constant = mark },
                    });
                    continue;
                }
                const subj = try mut_self.resolve_pattern_term(pat.args[0], &var_map, &next_var);
                const obj = if (pat.args.len > 1)
                    try mut_self.resolve_object_term(pat.relation, pat.args[1], &var_map, &next_var)
                else
                    world_mod.PatternTerm{ .wildcard = {} };

                try clauses.append(.{
                    .relation = rel,
                    .subject = subj,
                    .object = obj,
                });
            }

            // Determine target entity, priority, and compile handler body
            var target_entity: EntityId = .none;
            var priority: u16 = 50;

            for (clauses.items) |c| {
                if (mut_self.world.get_relation_meta(c.relation)) |meta| {
                    if (std.mem.indexOf(u8, meta.name, "Alert") != null or
                        std.mem.indexOf(u8, meta.name, "Theft") != null)
                    {
                        priority = 100;
                    }
                }
            }

            const entry_pc = mut_self.chunk.count();
            try mut_self.when_rule_entries.append(entry_pc);

            // A `when each` body reads its row (D-170): each trigger variable sits at its guard
            // slot above the three unused argument places, as in a cue handler (D-161). A once
            // rule's body still cannot read them.
            var each_locals = std.StringHashMap(u8).init(mut_self.allocator);
            defer each_locals.deinit();
            var owner_slot: ?u8 = null;
            if (rule.each) {
                var it = var_map.iterator();
                while (it.next()) |entry| try each_locals.put(entry.key_ptr.*, CUE_BINDING_BASE + entry.value_ptr.*);
                if (clauses.items.len > 0) switch (clauses.items[0].subject) {
                    .variable => |slot| owner_slot = slot,
                    else => {},
                };
                var reads = false;
                var names = each_locals.keyIterator();
                while (names.next()) |name| {
                    for (rule.body) |stmt| {
                        if (mentions(stmt, name.*)) reads = true;
                    }
                }
                if (reads) {
                    _ = try mut_self.chunk.emit_op(.bind_cue_args);
                    mut_self.locals = &each_locals;
                }
            } else {
                mut_self.when_patterns = rule.trigger_patterns;
            }
            defer mut_self.when_patterns = null;
            defer mut_self.locals = null;
            if (rule.body.len > 0 and rule.body[0] == .interrupt_with) {
                const iw = rule.body[0].interrupt_with;
                target_entity = try mut_self.resolve_entity(iw.entity);
                // The named target runs the body, whatever the row's first subject is.
                owner_slot = null;
                for (iw.body) |s| {
                    try mut_self.compile_stmt(s);
                }
            } else {
                if (clauses.items.len > 0) {
                    switch (clauses.items[0].subject) {
                        .constant => |c| target_entity = EntityId.from_int(c),
                        else => {},
                    }
                }
                for (rule.body) |s| {
                    try mut_self.compile_stmt(s);
                }
            }
            _ = try mut_self.chunk.emit_op(.resume_routine);

            try mut_self.reactive_rules.append(.{
                .clauses = try clauses.toOwnedSlice(),
                .target_entity = target_entity,
                .priority = priority,
                .handler_pc = entry_pc,
                .edge = rule.edge,
                .each = rule.each,
                .owner_slot = owner_slot,
            });
        }

        // 6. Compile cue handlers (P11-01, P11-02, D-013)
        // Where each compiled handler came from, so a repeated signature can name the
        // handler that already covers it (D-160).
        var handler_sources = std.AutoHashMap(usize, parser_mod.CueHandler).init(mut_self.allocator);
        defer handler_sources.deinit();
        for (ast.cue_handlers.items) |cue| {
            mut_self.error_context = cue.cue_name;
            const entry_pc = mut_self.chunk.count();

            // One key per declared signature. Parameters declared as variables are stored as
            // `*`; there is no key for the bare cue name, so an unmatched cue finds nothing
            // (D-037).
            if (cue.params.len == 1) {
                const sig = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}", .{ cue.cue_name, cue_param_key(cue.params[0]) });
                try mut_self.register_cue_handler(&handler_sources, sig, cue, entry_pc);
            } else if (cue.params.len == 2) {
                const sig = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}:{s}", .{ cue.cue_name, cue_param_key(cue.params[0]), cue_param_key(cue.params[1]) });
                try mut_self.register_cue_handler(&handler_sources, sig, cue, entry_pc);
            } else if (cue.params.len >= 3) {
                // Uses:Actor:ItemA:ItemB; lookup also tries the two items swapped (D-013).
                const sig = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}:{s}:{s}", .{ cue.cue_name, cue_param_key(cue.params[0]), cue_param_key(cue.params[1]), cue_param_key(cue.params[2]) });
                try mut_self.register_cue_handler(&handler_sources, sig, cue, entry_pc);
            }

            // What the body may read (D-161): each variable parameter by its position, then
            // each variable only the guard binds, by its guard slot above the arguments.
            var locals = std.StringHashMap(u8).init(mut_self.allocator);
            defer locals.deinit();
            for (cue.params, 0..) |param, i| {
                if (i >= MAX_CUE_PARAMS) break;
                if (is_variable_name(param) and !locals.contains(param)) try locals.put(param, @intCast(i));
            }
            if (cue.where_patterns.len > 0) {
                try mut_self.cue_guards.append(mut_self.allocator, try mut_self.compile_cue_guard(cue, entry_pc, &locals));
            }

            // Only a body that mentions a local starts with `bind_cue_args`, so every other
            // handler compiles to the bytes it always did.
            var reads_locals = false;
            var names = locals.keyIterator();
            while (names.next()) |name| {
                for (cue.body) |stmt| {
                    if (mentions(stmt, name.*)) reads_locals = true;
                }
            }
            if (reads_locals) _ = try mut_self.chunk.emit_op(.bind_cue_args);
            mut_self.locals = if (reads_locals) &locals else null;
            defer mut_self.locals = null;
            for (cue.body) |stmt| {
                try mut_self.compile_stmt(stmt);
            }
            _ = try mut_self.chunk.emit_op(.halt);
        }

        // What players read: display names and the game's phrases (P48-09, D-179). Program data
        // on the World, like value bounds; the package carries it.
        for (ast.display_names.items) |decl| {
            mut_self.error_context = decl.entity;
            // A name for something the script never mentions is a typo, not a new thing.
            const entity = mut_self.world.lookup_entity(decl.entity) orelse return error.NameForUnknownThing;
            try mut_self.world.set_display_name(entity, decl.text);
        }
        for (ast.phrases.items) |decl| try mut_self.world.set_phrase(decl.key, decl.text);

        for (mut_self.look_uses.items) |name| {
            const known = for (ast.art.looks) |look| {
                if (std.mem.eql(u8, look.name, name)) break true;
            } else false;
            if (!known) {
                var hints = Suggestions{};
                for (ast.art.looks) |look| hints.consider(name, look.name);
                mut_self.error_context = name;
                mut_self.error_suggestion = hints.result();
                return error.UnknownLook;
            }
        }

        // Art last: nothing after it can fail, so the owned copy never needs an errdefer here
        // (P46-03, D-155). Bindings name their scene or entity by text; interning finds the
        // entity the scene, cast, or props line already made.
        const art = try mut_self.compile_art(&ast.art);
        return CompiledProgram{
            .chunk = mut_self.chunk,
            .routine_entries = mut_self.routine_entries,
            .routine_entities = mut_self.routine_entities,
            .when_rule_entries = mut_self.when_rule_entries,
            .cue_handler_entries = mut_self.cue_handler_entries,
            .allocated_cue_keys = mut_self.allocated_cue_keys,
            .allocated_routine_names = mut_self.allocated_routine_names,
            .reactive_rules = mut_self.reactive_rules,
            .initial_entry = initial_entry,
            .drafts = drafts,
            .societies = mut_self.societies,
            .duels = mut_self.duels,
            .degradations = mut_self.degradations,
            .grids = mut_self.grids,
            .agendas = mut_self.agendas,
            .goals = mut_self.goals,
            .spellbooks = mut_self.spellbooks,
            .decisions = mut_self.decisions,
            .axes = mut_self.axes,
            .red_lines = mut_self.red_lines,
            .dilemmas = mut_self.dilemmas,
            .commands = mut_self.commands,
            .aliases = mut_self.aliases,
            .scores = mut_self.scores,
            .cast = mut_self.cast,
            .cue_guards = mut_self.cue_guards,
            .cue_handler_chain = mut_self.cue_handler_chain,
            .save_version = ast.save_version orelse 1,
            .rewinds_reroll = ast.rewinds_reroll,
            .turn_clock = ast.turn_clock orelse false,
            .fingerprint = program_fingerprint(mut_self.chunk.code.items, mut_self.world),
            .art = art,
        };
    }

    fn compile_art(self: *Codegen, decl: *const parser_mod.ArtDecl) !image_mod.Art {
        if (decl.palette.len == 0 and decl.images.len == 0 and decl.areas.len == 0) return .{};
        const backdrops = try self.allocator.alloc(image_mod.Backdrop, decl.backdrops.len);
        defer self.allocator.free(backdrops);
        for (decl.backdrops, backdrops) |b, *out| out.* = .{ .scene = try self.world.intern_entity(b.scene), .image = b.image };
        const sprites = try self.allocator.alloc(image_mod.Sprite, decl.sprites.len);
        defer self.allocator.free(sprites);
        for (decl.sprites, sprites) |sp, *out| out.* = .{
            .entity = try self.world.intern_entity(sp.target),
            .image = sp.image,
            .animations = sp.animations,
        };
        const areas = try self.allocator.alloc(image_mod.Area, decl.areas.len);
        defer self.allocator.free(areas);
        for (decl.areas, areas) |a, *out| out.* = .{ .entity = try self.world.intern_entity(a.target), .x = a.x, .y = a.y, .w = a.w, .h = a.h };
        const looks = try self.allocator.alloc(image_mod.Look, decl.looks.len);
        defer self.allocator.free(looks);
        for (decl.looks, looks) |l, *out| out.* = .{ .name = l.name, .image = l.image, .animations = l.animations };
        const parts = try self.allocator.alloc(image_mod.Part, decl.parts.len);
        defer self.allocator.free(parts);
        for (decl.parts, parts) |pt, *out| out.* = .{ .entity = try self.world.intern_entity(pt.part), .host = try self.world.intern_entity(pt.host), .dx = pt.dx, .dy = pt.dy };
        return image_mod.Art.dupe(self.allocator, .{
            .images = decl.images,
            .backdrops = backdrops,
            .sprites = sprites,
            .areas = areas,
            .looks = looks,
            .parts = parts,
        }) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            // The parser checked everything `validate` checks, so this is a compiler fault.
            else => error.InvalidArt,
        };
    }

    fn intern_program_text(self: *Codegen, text_value: []const u8) ![]const u8 {
        const entity = try self.world.intern_entity(text_value);
        return self.world.get_entity_name(entity) orelse return error.InvalidProgramText;
    }

    fn society_member_index(self: *Codegen, decl: parser_mod.SocietyDecl, name: []const u8) !usize {
        for (decl.members, 0..) |member, index| {
            if (std.mem.eql(u8, member.name, name)) return index;
        }
        var hints = Suggestions{};
        for (decl.members) |member| hints.consider(name, member.name);
        self.error_context = name;
        self.error_suggestion = hints.result();
        return error.UnknownSocietyMember;
    }

    fn activity_from_name(self: *Codegen, name: []const u8) !society_mod.Activity {
        if (std.meta.stringToEnum(society_mod.Activity, name)) |activity| return activity;
        self.error_context = name;
        var hints = Suggestions{};
        for (std.meta.fieldNames(society_mod.Activity)) |candidate| hints.consider(name, candidate);
        self.error_suggestion = hints.result();
        return error.UnknownSocietyActivity;
    }

    fn society_waypoint(self: *Codegen, name: []const u8) !spatial_mod.WaypointId {
        const spatial = self.spatial orelse return error.SocietyNeedsSpatialSystem;
        return spatial.graph.find_waypoint(name) orelse {
            self.note_unknown_waypoint(name);
            return error.UnknownSocietyPlace;
        };
    }

    fn note_unknown_waypoint(self: *Codegen, name: []const u8) void {
        self.error_context = name;
        const sp = self.spatial orelse return;
        var hints = Suggestions{};
        for (sp.graph.waypoints.items) |wp| hints.consider(name, wp.name);
        self.error_suggestion = hints.result();
    }

    fn compile_society(self: *Codegen, decl: parser_mod.SocietyDecl) !society_mod.Declaration {
        const needs = try self.allocator.alloc(society_mod.Need, decl.needs.len);
        errdefer self.allocator.free(needs);
        for (decl.needs, 0..) |source, i| {
            const worse: society_mod.Worse = if (std.mem.eql(u8, source.worse, "high")) .high else if (std.mem.eql(u8, source.worse, "low")) .low else return error.InvalidSocietyWorse;
            needs[i] = .{
                .name = try self.intern_program_text(source.name),
                .worse = worse,
                .max = source.max,
                .rate = source.rate,
                .resting_rate = source.resting_rate,
                .seek = source.seek,
                .satisfy = switch (source.satisfy) {
                    .trade => |trade| .{ .trade = .{
                        .provider = if (trade.provider) |name| try self.society_member_index(decl, name) else null,
                        .price = trade.price,
                        .relief = trade.relief,
                        .floor = trade.floor,
                        .critical = trade.critical,
                        .theft_relief = trade.theft_relief,
                        .theft_floor = trade.theft_floor,
                        .item = try self.intern_program_text(trade.item),
                    } },
                    .stay => |stay| .{ .stay = .{
                        .at = try self.society_waypoint(stay.at),
                        .restore = stay.restore,
                        .until = stay.until,
                        .activity = try self.activity_from_name(stay.activity),
                        .unaware = stay.unaware,
                        .state = try self.intern_program_text(stay.state),
                        .verb = try self.intern_program_text(stay.verb),
                    } },
                },
            };
        }

        const members = try self.allocator.alloc(society_mod.Member, decl.members.len);
        var built_members: usize = 0;
        errdefer {
            for (members[0..built_members]) |member| {
                self.allocator.free(member.needs);
                self.allocator.free(member.routine.stops);
                self.allocator.free(member.owns);
                self.allocator.free(member.carries);
            }
            self.allocator.free(members);
        }
        for (decl.members, 0..) |source, i| {
            if (source.needs.len != decl.needs.len) return error.InvalidSocietyMemberNeeds;
            const member_needs = try self.allocator.alloc(society_mod.MemberNeed, source.needs.len);
            errdefer self.allocator.free(member_needs);
            for (source.needs, 0..) |member_need, ni| {
                if (!std.mem.eql(u8, member_need.name, decl.needs[ni].name)) return error.InvalidSocietyMemberNeeds;
                member_needs[ni] = .{
                    .value = member_need.value,
                    .rate = member_need.rate,
                    .provider = if (member_need.provider) |provider| try self.society_member_index(decl, provider) else null,
                };
            }
            const stops = try self.allocator.alloc(spatial_mod.WaypointId, source.stops.len);
            errdefer self.allocator.free(stops);
            for (source.stops, 0..) |stop, si| stops[si] = try self.society_waypoint(stop);
            const owns = try self.allocator.alloc(EntityId, source.owns.len);
            errdefer self.allocator.free(owns);
            for (source.owns, 0..) |item, oi| owns[oi] = try self.world.intern_entity(item);
            const carries = try self.allocator.alloc(EntityId, source.carries.len);
            errdefer self.allocator.free(carries);
            for (source.carries, 0..) |item, ci| carries[ci] = try self.world.intern_entity(item);
            members[i] = .{
                .entity = try self.world.intern_entity(source.name),
                .needs = member_needs,
                .gold = source.gold,
                .idle = try self.activity_from_name(source.idle),
                .routine = .{
                    .activity = if (source.routine_activity) |activity| try self.activity_from_name(activity) else null,
                    .stops = stops,
                    .period = source.period,
                    .work = if (source.work) |work| .{
                        .at = try self.society_waypoint(work.at),
                        .every = work.every,
                        .earn = work.earn,
                        .restock = work.restock,
                    } else null,
                },
                .merchant = if (source.merchant) |merchant| .{
                    .post = try self.society_waypoint(merchant.post),
                    .goods = try self.world.intern_entity(merchant.goods),
                } else null,
                .broadcaster = source.broadcaster,
                .owns = owns,
                .carries = carries,
            };
            built_members += 1;
        }

        const friends = try self.allocator.alloc(society_mod.FriendLink, decl.friends.len);
        errdefer self.allocator.free(friends);
        for (decl.friends, 0..) |friend, i| friends[i] = .{
            .a = try self.world.intern_entity(friend[0]),
            .b = try self.world.intern_entity(friend[1]),
        };
        const relation_names = decl.relations;
        return .{ .config = .{
            .needs = needs,
            .members = members,
            .enforcer = if (decl.enforcer) |name| try self.society_member_index(decl, name) else null,
            .holding = if (decl.holding) |place| try self.society_waypoint(place) else null,
            .gathering = try self.society_waypoint(decl.gathering),
            .flight = .{ .to = try self.society_waypoint(decl.flight_to), .then = if (decl.flight_then) |place| try self.society_waypoint(place) else null, .every = decl.flight_every },
            .radii = .{ .witness = decl.radii[0], .culprit = decl.radii[1], .rumor = decl.radii[2], .arrest = decl.radii[3] },
            .witness_grudge_ticks = decl.grudge_ticks[0],
            .rumor_grudge_ticks = decl.grudge_ticks[1],
            .warrant_priority = decl.warrant_priority,
            .currency_unit = try self.intern_program_text(decl.currency_unit),
            .relations = .{
                .currency = try self.intern_program_text(relation_names[0]),
                .activity = try self.intern_program_text(relation_names[1]),
                .tending = try self.intern_program_text(relation_names[2]),
                .friend = try self.intern_program_text(relation_names[3]),
                .rival = try self.intern_program_text(relation_names[4]),
                .grudge = try self.intern_program_text(relation_names[5]),
                .owns = try self.intern_program_text(relation_names[6]),
                .carries = try self.intern_program_text(relation_names[7]),
                .stolen_from = try self.intern_program_text(relation_names[8]),
                .crime_scene = try self.intern_program_text(relation_names[9]),
                .witnessed = try self.intern_program_text(relation_names[10]),
                .knows_rumor = try self.intern_program_text(relation_names[11]),
                .warrant_for = try self.intern_program_text(relation_names[12]),
                .arrested = try self.intern_program_text(relation_names[13]),
            },
            .friends = friends,
        } };
    }

    fn compile_duel(self: *Codegen, decl: parser_mod.DuelDecl) !duel_mod.Declaration {
        const pairs = try self.allocator.alloc(duel_mod.Pair, decl.pairs.len);
        var built_pairs: usize = 0;
        errdefer {
            for (pairs[0..built_pairs]) |pair| self.allocator.free(pair.variants);
            self.allocator.free(pairs);
        }
        for (decl.pairs, 0..) |source, i| {
            const variants = try self.allocator.alloc([]const u8, source.variants.len);
            errdefer self.allocator.free(variants);
            for (source.variants, 0..) |variant, vi| variants[vi] = try self.intern_program_text(variant);
            pairs[i] = .{
                .name = try self.intern_program_text(source.name),
                .challenge = try self.intern_program_text(source.challenge),
                .reply = try self.intern_program_text(source.reply),
                .variants = variants,
            };
            built_pairs += 1;
        }
        const fallbacks = try self.allocator.alloc([]const u8, decl.fallbacks.len);
        errdefer self.allocator.free(fallbacks);
        for (decl.fallbacks, 0..) |line, i| fallbacks[i] = try self.intern_program_text(line);
        const stages = try self.allocator.alloc(duel_mod.Stage, decl.fatigue_stages.len);
        errdefer self.allocator.free(stages);
        for (decl.fatigue_stages, 0..) |source, i| stages[i] = .{
            .relation = try self.intern_program_text(source.relation),
            .at = source.at,
            .ttl = source.ttl,
            .label = try self.intern_program_text(source.label),
        };
        const tiers = try self.allocator.alloc(duel_mod.TierAssignment, decl.tiers.len);
        errdefer self.allocator.free(tiers);
        for (decl.tiers, 0..) |source, i| tiers[i] = .{ .opponent = try self.world.intern_entity(source.opponent), .tier = source.tier };
        const r = decl.relations;
        return .{
            .config = .{
                .pairs = pairs,
                .fallbacks = fallbacks,
                .win_at = decl.win_at,
                .relations = .{
                    .heard = try self.intern_program_text(r[0]),
                    .mastered = try self.intern_program_text(r[1]),
                    .counters = try self.intern_program_text(r[2]),
                    .variant_of = try self.intern_program_text(r[3]),
                    .tier = try self.intern_program_text(r[4]),
                    .advantage = try self.intern_program_text(r[5]),
                    .wins = try self.intern_program_text(r[6]),
                },
            },
            .fatigue = .{
                .stages = stages,
                .count_relation = try self.intern_program_text(decl.fatigue_count_relation),
                .calm_label = try self.intern_program_text(decl.fatigue_calm_label),
            },
            .tiers = tiers,
        };
    }

    /// Expands attribute rectangles into the sparse initial layout and, when compiling into a
    /// SpatialSystem, registers the overlay and moves placed marks to their cell centres. Marks
    /// keep their graph edges, whose costs follow the new positions; packages carry placement
    /// in the existing waypoint table.
    fn compile_grid(self: *Codegen, decl: parser_mod.GridDecl) !grid_mod.Declaration {
        const grid = grid_mod.Grid{
            .entity = try self.world.intern_entity(decl.name),
            .room = try self.world.intern_entity(decl.room),
            .width = @intCast(decl.width),
            .height = @intCast(decl.height),
            .cell_size = decl.cell_size,
            .origin_x = decl.origin_x,
            .origin_y = decl.origin_y,
        };
        var cells = std.array_list.Managed(grid_mod.InitialCell).init(self.allocator);
        errdefer cells.deinit();
        for (decl.rects) |rect| {
            const attribute = grid_mod.Attribute.from_name(rect.attribute) orelse return error.UnknownGridAttribute;
            var y = rect.y;
            while (y < rect.y + rect.height) : (y += 1) {
                var x = rect.x;
                while (x < rect.x + rect.width) : (x += 1) {
                    const index = try grid.index_of(.{ .x = @intCast(x), .y = @intCast(y) });
                    // Overlapping rectangles name the same cell twice; keep one row.
                    var seen = false;
                    for (cells.items) |prior| {
                        if (prior.index == index and prior.attribute == attribute) seen = true;
                    }
                    if (!seen) try cells.append(.{ .index = index, .attribute = attribute });
                }
            }
        }
        const declaration = grid_mod.Declaration{ .grid = grid, .cells = try cells.toOwnedSlice(), .rules = .{
            .burn_ticks = decl.burn_ticks,
            .spread_ticks = decl.spread_ticks,
            .dissipate_ticks = decl.dissipate_ticks,
            .flow_ticks = decl.flow_ticks,
        } };
        errdefer self.allocator.free(declaration.cells);
        try declaration.validate();

        if (self.spatial) |sp| {
            try sp.add_grid(grid);
            for (decl.places) |place| {
                const id = self.find_waypoint(place.mark) orelse {
                    self.note_unknown_waypoint(place.mark);
                    return error.UnknownGridMark;
                };
                const wp = sp.graph.get_waypoint(id).?;
                if (wp.room != grid.room) {
                    self.error_context = place.mark;
                    return error.GridMarkOutsideRoom;
                }
                const center = grid.cell_center(.{ .x = @intCast(place.x), .y = @intCast(place.y) });
                try sp.graph.move_waypoint(id, .{ .x = center.x, .y = center.y });
            }
        }
        return declaration;
    }

    fn compile_command(self: *Codegen, decl: parser_mod.CommandDecl) !command_mod.CommandDecl {
        const cue = try self.allocator.dupe(u8, decl.cue);
        errdefer self.allocator.free(cue);
        const text = try self.allocator.dupe(u8, decl.text);
        errdefer self.allocator.free(text);
        const owned = command_mod.CommandDecl{ .cue = cue, .text = text };
        _ = try owned.frame();
        return owned;
    }

    /// Phrases are stored lowercase so typed words, which the tokenizer lowercases, match them.
    fn compile_alias(self: *Codegen, decl: parser_mod.AliasDecl) !command_mod.AliasDecl {
        const phrases = try self.allocator.alloc([]const u8, decl.phrases.len);
        var made: usize = 0;
        errdefer {
            for (phrases[0..made]) |p| self.allocator.free(p);
            self.allocator.free(phrases);
        }
        for (decl.phrases, 0..) |phrase, i| {
            const lower = try self.allocator.alloc(u8, phrase.len);
            for (phrase, 0..) |ch, j| lower[j] = std.ascii.toLower(ch);
            phrases[i] = lower;
            made += 1;
        }
        const alias = command_mod.AliasDecl{ .entity = try self.world.intern_entity(decl.entity), .phrases = phrases };
        try alias.validate();
        return alias;
    }

    fn compile_agenda(self: *Codegen, decl: parser_mod.AgendaDecl) !agency_mod.Declaration {
        const clauses = try self.allocator.alloc(agency_mod.Clause, decl.clauses.len);
        errdefer self.allocator.free(clauses);
        for (decl.clauses, 0..) |source, i| {
            const args = source.pattern.args;
            clauses[i] = .{
                .relation = try self.intern_program_text(source.pattern.relation),
                .subject = try self.agenda_term(args[0]),
                .object = if (args.len > 1) try self.agenda_term(args[1]) else null,
                .negated = source.negated,
            };
        }
        const agenda = agency_mod.Agenda{
            .entity = try self.world.intern_entity(decl.name),
            .actor = try self.world.intern_entity(decl.actor),
            .target = try self.world.intern_entity(decl.target),
            .priority = decl.priority,
            .cooldown_ticks = decl.cooldown_ticks,
            .once = decl.once,
            .clauses = clauses,
        };
        try agency_mod.validate(agenda);
        return .{ .agenda = agenda };
    }

    fn agenda_term(self: *Codegen, name: []const u8) !?world_mod.EntityId {
        if (std.mem.eql(u8, name, "_")) return null;
        return try self.world.intern_entity(name);
    }

    fn compile_goal(self: *Codegen, decl: parser_mod.GoalDecl, scenes: []const parser_mod.SceneDef) !hint_mod.Declaration {
        const needs = try self.allocator.alloc(hint_mod.Need, decl.needs.len);
        var built: usize = 0;
        errdefer {
            for (needs[0..built]) |need| {
                for (need.hints) |hint| self.allocator.free(hint.text);
                self.allocator.free(need.hints);
                self.allocator.free(need.after);
            }
            self.allocator.free(needs);
        }
        for (decl.needs, 0..) |source, i| {
            needs[i] = try self.compile_need(source, scenes);
            built += 1;
        }
        return .{ .goal = .{
            .entity = try self.world.intern_entity(decl.name),
            .needs = needs,
        } };
    }

    fn compile_need(self: *Codegen, source: parser_mod.GoalNeedDecl, scenes: []const parser_mod.SceneDef) !hint_mod.Need {
        const args = source.pattern.args;
        const after = try self.allocator.alloc(EntityId, source.after.len);
        errdefer self.allocator.free(after);
        for (source.after, 0..) |name, j| after[j] = try self.world.intern_entity(name);
        const hints = try self.allocator.alloc(hint_mod.Authored, source.hints.len);
        var made: usize = 0;
        errdefer {
            for (hints[0..made]) |hint| self.allocator.free(hint.text);
            self.allocator.free(hints);
        }
        for (source.hints, 0..) |hint, j| {
            const tier = hint_mod.Tier.fromInt(hint.tier) orelse {
                self.error_context = source.name;
                return error.InvalidGoal;
            };
            hints[j] = .{ .tier = tier, .text = try self.allocator.dupe(u8, hint.text) };
            made += 1;
        }
        return .{
            .entity = try self.world.intern_entity(source.name),
            .relation = try self.intern_program_text(source.pattern.relation),
            .subject = try self.agenda_term(args[0]),
            .object = if (args.len > 1) try self.agenda_term(args[1]) else null,
            .after = after,
            .room = try self.goal_room(source, scenes),
            .hints = hints,
        };
    }

    /// A need names its room, or inherits the scene that declares the prop or mark it names.
    /// A proof whose rooms are finer than its scenes declares `room` explicitly.
    fn goal_room(self: *Codegen, source: parser_mod.GoalNeedDecl, scenes: []const parser_mod.SceneDef) !EntityId {
        if (source.room) |room| return try self.world.intern_entity(room);
        const named = if (source.pattern.args.len > 1) source.pattern.args[1] else source.pattern.args[0];
        for (scenes) |scene| {
            for (scene.props.items) |prop| {
                if (std.mem.eql(u8, prop, named)) return try self.world.intern_entity(scene.name);
            }
            for (scene.marks.items) |mark| {
                if (std.mem.eql(u8, mark, named)) return try self.world.intern_entity(scene.name);
            }
        }
        var suggestions = Suggestions{};
        for (scenes) |scene| suggestions.consider(named, scene.name);
        self.error_context = named;
        self.error_suggestion = suggestions.result();
        return error.UnknownHintRoom;
    }

    /// Turns a parsed book into program data: words in declaration order carry their tier, and
    /// each spell row carries the entities its three words name (P44-04).
    fn compile_spellbook(self: *Codegen, decl: parser_mod.SpellbookDecl) !spell_mod.Declaration {
        const words = try self.allocator.alloc(spell_mod.Word, decl.words.len);
        errdefer self.allocator.free(words);
        var tiers = [3]u16{ 0, 0, 0 };
        for (decl.words, 0..) |source, i| {
            const slot = source.kind.index();
            tiers[slot] += 1;
            words[i] = .{
                .entity = try self.world.intern_entity(source.name),
                .kind = source.kind,
                .tier = tiers[slot],
            };
        }
        const spells = try self.allocator.alloc(spell_mod.Spell, decl.spells.len);
        errdefer self.allocator.free(spells);
        for (decl.spells, 0..) |source, i| {
            spells[i] = .{
                .entity = try self.world.intern_entity(source.name),
                .words = .{
                    try self.world.intern_entity(source.power),
                    try self.world.intern_entity(source.element),
                    try self.world.intern_entity(source.form),
                },
            };
        }
        const declaration = spell_mod.Declaration{ .book = .{
            .entity = try self.world.intern_entity(decl.name),
            .words = words,
            .spells = spells,
        } };
        spell_mod.validate(declaration) catch return error.InvalidSpellbook;
        return declaration;
    }

    /// Turns a parsed decision into program data: trigger lines, then options in declaration
    /// order, which breaks score ties (P44-05).
    fn compile_decision(self: *Codegen, decl: parser_mod.DecisionDecl) !decision_mod.Declaration {
        const clauses = try self.allocator.alloc(decision_mod.Clause, decl.clauses.len);
        errdefer self.allocator.free(clauses);
        for (decl.clauses, 0..) |source, i| clauses[i] = try self.compile_clause(source.pattern, source.negated);

        const options = try self.allocator.alloc(decision_mod.Option, decl.options.len);
        var built: usize = 0;
        errdefer {
            for (options[0..built]) |option| self.allocator.free(option.picks);
            self.allocator.free(options);
        }
        for (decl.options, 0..) |source, i| {
            const picks = try self.allocator.alloc(decision_mod.Pick, source.picks.len);
            errdefer self.allocator.free(picks);
            for (source.picks, 0..) |line, pi| picks[pi] = .{
                .points = line.points,
                .clause = try self.compile_clause(line.pattern, line.negated),
            };
            options[i] = .{ .entity = try self.world.intern_entity(source.name), .picks = picks };
            built += 1;
        }

        const decision = decision_mod.Decision{
            .entity = try self.world.intern_entity(decl.name),
            .actor = try self.world.intern_entity(decl.actor),
            .cue = try self.world.intern_entity(decl.cue),
            .clauses = clauses,
            .options = options,
        };
        decision_mod.validate(decision) catch return error.InvalidDecision;
        return .{ .decision = decision };
    }

    /// Turns a parsed dilemma into program data. Both axes must be declared, and no tier may act
    /// on its actor's red lines; each refusal names the source text that caused it.
    fn compile_dilemma(self: *Codegen, decl: parser_mod.DilemmaDecl) !dilemma_mod.Declaration {
        var axes: [2]world_mod.RelationKind = undefined;
        for ([_][]const u8{ decl.axis, decl.counter }, 0..) |name, i| {
            const rel = self.world.lookup_relation(name);
            if (rel == null or self.world.value_bound(rel.?) == null) {
                self.error_context = name;
                return error.UnknownDilemmaAxis;
            }
            axes[i] = rel.?;
        }
        const actor = try self.world.intern_entity(decl.actor);
        var responses: [dilemma_mod.TIER_COUNT]dilemma_mod.Response = undefined;
        for (decl.responses, 0..) |source, i| {
            const action = try self.world.intern_entity(source.action);
            if (decision_mod.vetoed(self.red_lines.items, actor, action)) {
                self.error_context = source.action;
                return error.DilemmaCrossesRedLine;
            }
            responses[i] = .{ .line = try self.world.intern_entity(source.line), .action = action };
        }
        const clauses = try self.allocator.alloc(decision_mod.Clause, decl.clauses.len);
        errdefer self.allocator.free(clauses);
        for (decl.clauses, 0..) |source, i| clauses[i] = try self.compile_clause(source.pattern, source.negated);
        const leans = try self.allocator.alloc(dilemma_mod.Lean, decl.leans.len);
        errdefer self.allocator.free(leans);
        for (decl.leans, 0..) |source, i| {
            const magnitude: i32 = @intCast(source.points);
            leans[i] = .{
                .points = if (std.mem.eql(u8, source.toward, decl.axis)) magnitude else -magnitude,
                .clause = try self.compile_clause(source.pattern, source.negated),
            };
        }
        // A drift line may move any declared axis, not only the two the dilemma weighs: an
        // outcome of a mercy dilemma can change a character's loyalty (D-148).
        const drifts = try self.allocator.alloc(dilemma_mod.Drift, decl.drifts.len);
        errdefer self.allocator.free(drifts);
        for (decl.drifts, 0..) |source, i| {
            const rel = self.world.lookup_relation(source.axis);
            if (rel == null or self.world.value_bound(rel.?) == null) {
                self.error_context = source.axis;
                return error.UnknownDilemmaAxis;
            }
            const rels = try dilemma_mod.drift_relations(self.world, rel.?);
            const magnitude: i32 = @intCast(source.points);
            drifts[i] = .{
                .axis = rel.?,
                .points = if (source.away) -magnitude else magnitude,
                .clause = try self.compile_clause(source.pattern, source.negated),
                .accumulator = rels.accumulator,
                .spent = rels.spent,
                .step = value_mod.drift_step_of(self.axes.items, rel.?),
            };
        }
        // An appeal names the value appealed to, which may be any declared axis, and leans
        // toward one of the two weighed axes, which the parser has checked; an appeal toward the
        // counter-axis lowers the delta (D-149, amended by D-150).
        const appeals = try self.allocator.alloc(dilemma_mod.Appeal, decl.appeals.len);
        errdefer self.allocator.free(appeals);
        for (decl.appeals, 0..) |source, i| {
            const rel = self.world.lookup_relation(source.axis);
            if (rel == null or self.world.value_bound(rel.?) == null) {
                self.error_context = source.axis;
                return error.UnknownDilemmaAxis;
            }
            const toward_axis = std.mem.eql(u8, source.toward, decl.axis);
            const magnitude: i32 = @intCast(source.points);
            appeals[i] = .{
                .axis = rel.?,
                .entity = try self.world.intern_entity(source.axis),
                .points = if (toward_axis) magnitude else -magnitude,
            };
            _ = try value_mod.known_value(self.world, rel.?, actor);
        }
        // The values an appeal or a hint can name for this actor exist from the start, so a
        // script can write `remember Knows(Player, "Mercy of Oswin")` (D-149).
        for (axes) |axis| _ = try value_mod.known_value(self.world, axis, actor);
        return .{ .dilemma = .{
            .entity = try self.world.intern_entity(decl.name),
            .actor = actor,
            .cue = try self.world.intern_entity(decl.cue),
            .clauses = clauses,
            .axis = axes[0],
            .counter = axes[1],
            .leans = leans,
            .drifts = drifts,
            .appeals = appeals,
            .responses = responses,
            .strong_at = if (decl.tiers) |t| t[0] else dilemma_mod.DEFAULT_STRONG_AT,
            .moderate_at = if (decl.tiers) |t| t[1] else dilemma_mod.DEFAULT_MODERATE_AT,
            .drift_cap = decl.drift_cap orelse dilemma_mod.DEFAULT_DRIFT_CAP,
        } };
    }

    fn compile_clause(self: *Codegen, pattern: parser_mod.FactPattern, negated: bool) !decision_mod.Clause {
        return .{
            .relation = try self.intern_program_text(pattern.relation),
            .subject = try self.agenda_term(pattern.args[0]),
            .object = if (pattern.args.len > 1) try self.agenda_term(pattern.args[1]) else null,
            .negated = negated,
        };
    }

    fn compile_degradation(self: *Codegen, decl: parser_mod.DegradationDecl) !container_mod.Declaration {
        const stages = try self.allocator.alloc(container_mod.Stage, decl.stages.len);
        errdefer self.allocator.free(stages);
        for (decl.stages, 0..) |source, i| stages[i] = .{
            .entity = try self.world.intern_entity(source.name),
            .duration_ticks = source.duration_ticks,
        };
        const vessels = try self.allocator.alloc(container_mod.Vessel, decl.vessels.len);
        errdefer self.allocator.free(vessels);
        for (decl.vessels, 0..) |source, i| {
            var initial_stage: ?usize = null;
            for (decl.stages, 0..) |stage, si| if (std.mem.eql(u8, stage.name, source.initial_stage)) {
                initial_stage = si;
                break;
            };
            vessels[i] = .{
                .entity = try self.world.intern_entity(source.name),
                .capacity = source.capacity,
                .initial_volume = source.initial_volume,
                .initial_stage = initial_stage orelse {
                    self.error_context = source.initial_stage;
                    var hints = Suggestions{};
                    for (decl.stages) |stage| hints.consider(source.initial_stage, stage.name);
                    self.error_suggestion = hints.result();
                    return error.UnknownDegradationStage;
                },
            };
        }
        const r = decl.relations;
        const config = container_mod.Config{
            .substance = try self.world.intern_entity(decl.substance),
            .stages = stages,
            .vessels = vessels,
            .spill_per_moving_tick = decl.spill_per_moving_tick,
            .relations = .{
                .contains = try self.intern_program_text(r[0]),
                .volume = try self.intern_program_text(r[1]),
                .stage = try self.intern_program_text(r[2]),
                .exposure = try self.intern_program_text(r[3]),
                .failed_at = try self.intern_program_text(r[4]),
            },
        };
        try container_mod.validate(config);
        return .{ .config = config };
    }

    /// Emits `PathActive(path)` followed by a forward jump that a path routine patches to its
    /// trailing halt. The difficulty is the guard, not the body: inactive routes must not run.
    fn emit_path_guard(self: *Codegen, path_entity: EntityId, path_active: RelationKind) !usize {
        try self.chunk.emit_push_entity(path_entity);
        try self.chunk.emit_push_relation(path_active);
        _ = try self.chunk.emit_op(.query_has);
        try self.chunk.emit_u8(0x03);
        const jump_pc = try self.chunk.emit_op(.jump_if_false);
        try self.chunk.emit_i16(0);
        return jump_pc;
    }

    fn compile_stmt(self: *Codegen, stmt: Stmt) !void {
        switch (stmt) {
            .remember => |rem| {
                const subj = try self.entity_arg(rem.args[0]);
                const rel = try self.resolve_relation(rem.relation);
                // A look named outright must exist; checked once the art is read (D-181).
                if (std.mem.eql(u8, rem.relation, LOOKS_RELATION) and rem.args.len > 1 and self.local_index(rem.args[1]) == null)
                    try self.look_uses.append(self.allocator, rem.args[1]);
                if (rem.args.len > 1) try self.note_object_kind(rem.relation, rem.args[1]);
                const obj_local = if (rem.args.len > 1) self.local_index(rem.args[1]) else null;
                const obj = if (obj_local == null) try self.fact_object(rem.relation, rem.args) else 0;

                try self.emit_entity_arg(rem.args[0], subj);
                try self.chunk.emit_push_relation(rel);
                if (obj_local) |index| try self.chunk.emit_push_local(index) else try self.chunk.emit_push_const(obj);
                try self.chunk.emit_remember(rem.ttl_ticks);
            },
            .forget => |fg| {
                const subj = try self.entity_arg(fg.args[0]);
                const rel = try self.resolve_relation(fg.relation);
                const has_obj = fg.args.len > 1 and !std.mem.eql(u8, fg.args[1], "_");
                if (has_obj) try self.note_object_kind(fg.relation, fg.args[1]);

                try self.emit_entity_arg(fg.args[0], subj);
                try self.chunk.emit_push_relation(rel);
                if (has_obj) {
                    if (self.local_index(fg.args[1])) |index| {
                        try self.chunk.emit_push_local(index);
                    } else {
                        const obj = try self.fact_value(fg.relation, fg.args[1]);
                        try self.chunk.emit_push_const(obj);
                    }
                }
                _ = try self.chunk.emit_op(.forget);
                try self.chunk.emit_u8(if (has_obj) 1 else 0);
            },
            .walk => |w| {
                const ent = try self.entity_arg(w.entity);
                const wp_id = try self.resolve_waypoint(w.target);
                try self.emit_entity_arg(w.entity, ent);
                try self.chunk.emit_push_const(wp_id);
                _ = try self.chunk.emit_op(.walk_to);
            },
            .face => |f| {
                const ent = try self.entity_arg(f.entity);
                const target_id = try self.entity_arg(f.target);
                // Emit peripheral cue for face direction
                try self.emit_entity_arg(f.entity, ent);
                try self.emit_entity_arg(f.target, target_id);
                _ = try self.chunk.emit_op(.emit_cue);
                try self.chunk.emit_u16(1); // cue 1 = face
                try self.chunk.emit_u8(2); // 2 args
            },
            .wait_ticks => |ticks| {
                try self.chunk.emit_wait_ticks(ticks);
            },
            .wait_until => |expr| {
                // Emit condition block inline, with a jump over it
                const jump_over_pc = try self.chunk.emit_op(.jump);
                try self.chunk.emit_i16(0); // placeholder

                const cond_start_pc: u16 = @intCast(self.chunk.count());
                try self.compile_expr(expr);
                _ = try self.chunk.emit_op(.ret);

                // Patch jump over
                const jump_dest = self.chunk.count();
                const offset: i16 = @intCast(jump_dest - (jump_over_pc + 3));
                std.mem.writeInt(i16, self.chunk.code.items[jump_over_pc + 1 ..][0..2], offset, .little);

                // Emit wait_until pointing to cond_start_pc
                _ = try self.chunk.emit_op(.wait_until);
                try self.chunk.emit_u16(cond_start_pc);
            },
            .loop_stmt => |stmts| {
                const loop_start_pc = self.chunk.count();
                for (stmts) |s| {
                    try self.compile_stmt(s);
                }
                const loop_end_pc = self.chunk.count();
                const back_offset: u16 = @intCast((loop_end_pc + 3) - loop_start_pc);
                _ = try self.chunk.emit_op(.loop);
                try self.chunk.emit_u16(back_offset);
            },
            .if_stmt => |ifs| {
                try self.compile_expr(ifs.cond);
                const jump_false_pc = try self.chunk.emit_op(.jump_if_false);
                try self.chunk.emit_i16(0); // placeholder

                for (ifs.body) |s| {
                    try self.compile_stmt(s);
                }

                // Patch jump offset
                const dest_pc = self.chunk.count();
                const offset: i16 = @intCast(dest_pc - (jump_false_pc + 3));
                std.mem.writeInt(i16, self.chunk.code.items[jump_false_pc + 1 ..][0..2], offset, .little);
            },
            .interrupt_with => |iw| {
                const target = try self.entity_arg(iw.entity);

                // Jump over the interrupt handler in linear execution
                const jump_over_pc = try self.chunk.emit_op(.jump);
                try self.chunk.emit_i16(0);

                const handler_pc: u16 = @intCast(self.chunk.count());
                for (iw.body) |s| {
                    try self.compile_stmt(s);
                }
                _ = try self.chunk.emit_op(.resume_routine);

                // Patch jump over
                const dest_pc = self.chunk.count();
                const offset: i16 = @intCast(dest_pc - (jump_over_pc + 3));
                std.mem.writeInt(i16, self.chunk.code.items[jump_over_pc + 1 ..][0..2], offset, .little);

                // Emit interrupt opcode
                try self.emit_entity_arg(iw.entity, target);
                _ = try self.chunk.emit_op(.interrupt);
                try self.chunk.emit_u16(handler_pc);
            },
            .say => |s| {
                const speaker = try self.entity_arg(s.speaker);
                const text_id = try self.world.intern_entity(s.text);
                try self.emit_entity_arg(s.speaker, speaker);
                try self.chunk.emit_push_entity(text_id);
                _ = try self.chunk.emit_op(.emit_cue);
                try self.chunk.emit_u16(2); // cue 2 = say
                try self.chunk.emit_u8(2); // 2 args (speaker, text_entity)
            },
            .animate => |a| {
                const target_id = try self.entity_arg(a.target);
                const clip_id = try self.world.intern_entity(a.clip);
                try self.emit_entity_arg(a.target, target_id);
                try self.chunk.emit_push_entity(clip_id);
                _ = try self.chunk.emit_op(.emit_cue);
                try self.chunk.emit_u16(if (a.is_stop) 4 else 3); // cue 3 = animate, cue 4 = stop animate
                try self.chunk.emit_u8(2); // 2 args (target, clip)
            },
            .transition_scene => |ts| {
                const scene_ent = try self.resolve_entity(ts.target_scene);
                try self.chunk.emit_transition_scene(scene_ent);
            },
            .play_score => |name| {
                // `PlayingScore` is a property of `Music`, so playing replaces the previous
                // override and `stop score` removes it, returning to the scene default.
                const music = try self.resolve_entity(mml.MUSIC_ENTITY);
                const rel = try self.world.intern_relation_kind(mml.PLAYING_RELATION, .property, .entity);
                try self.chunk.emit_push_entity(music);
                try self.chunk.emit_push_relation(rel);
                if (name) |score| {
                    try self.chunk.emit_push_const((try self.resolve_entity(score)).to_int());
                    try self.chunk.emit_remember(0);
                } else {
                    _ = try self.chunk.emit_op(.forget);
                    try self.chunk.emit_u8(0);
                }
            },
            .choice_block => |choices| {
                // A choice set emits a pruned option table first, then one body per eligible
                // choice. The VM stores the table as World facts and suspends; selection
                // resumes the fiber at the chosen body. Bodies jump past the whole set.
                var offer_pcs = std.array_list.Managed(usize).init(self.allocator);
                defer offer_pcs.deinit();
                var body_pcs = std.array_list.Managed(usize).init(self.allocator);
                defer body_pcs.deinit();
                var body_jumps = std.array_list.Managed(usize).init(self.allocator);
                defer body_jumps.deinit();

                _ = try self.chunk.emit_op(.choices_begin);

                for (choices, 0..) |choice, source_index| {
                    if (source_index >= dialogue_lifecycle.MAX_CHOICES) {
                        self.error_context = choice.text;
                        return error.DialogueTooLarge;
                    }
                    const source_index_u8: u8 = @intCast(source_index);
                    const text_id = try self.world.intern_entity(choice.text);
                    const FailureJump = struct { jump_pc: usize, failure_text: EntityId };
                    var failures = std.array_list.Managed(FailureJump).init(self.allocator);
                    defer failures.deinit();

                    if (choice.guard) |guard| {
                        try self.compile_expr(guard);
                        const pc = try self.chunk.emit_op(.jump_if_false);
                        try self.chunk.emit_i16(0);
                        try failures.append(.{ .jump_pc = pc, .failure_text = try self.guard_failure_text(guard) });
                    }
                    for (choice.where_patterns) |pattern| {
                        try self.compile_expr(.{ .has_fact = pattern });
                        const pc = try self.chunk.emit_op(.jump_if_false);
                        try self.chunk.emit_i16(0);
                        try failures.append(.{ .jump_pc = pc, .failure_text = try self.guard_failure_text(.{ .has_fact = pattern }) });
                    }

                    const offer_pc = try self.chunk.emit_offer_choice_inspected(text_id, 0, source_index_u8);
                    try offer_pcs.append(offer_pc);
                    const success_jump = try self.chunk.emit_op(.jump);
                    try self.chunk.emit_i16(0);

                    var rejection_exits = std.array_list.Managed(usize).init(self.allocator);
                    defer rejection_exits.deinit();
                    for (failures.items) |failure| {
                        const reject_pc = self.chunk.count();
                        const reject_offset: i16 = @intCast(reject_pc - (failure.jump_pc + 3));
                        std.mem.writeInt(i16, self.chunk.code.items[failure.jump_pc + 1 ..][0..2], reject_offset, .little);
                        try self.chunk.emit_reject_choice(text_id, source_index_u8, failure.failure_text);
                        const exit_pc = try self.chunk.emit_op(.jump);
                        try self.chunk.emit_i16(0);
                        try rejection_exits.append(exit_pc);
                    }

                    const after_choice = self.chunk.count();
                    const success_offset: i16 = @intCast(after_choice - (success_jump + 3));
                    std.mem.writeInt(i16, self.chunk.code.items[success_jump + 1 ..][0..2], success_offset, .little);
                    for (rejection_exits.items) |exit_pc| {
                        const exit_offset: i16 = @intCast(after_choice - (exit_pc + 3));
                        std.mem.writeInt(i16, self.chunk.code.items[exit_pc + 1 ..][0..2], exit_offset, .little);
                    }
                }

                const choices_end_pc = try self.chunk.emit_choices_end(0);

                for (choices) |choice| {
                    try body_pcs.append(self.chunk.count());
                    for (choice.body) |s| try self.compile_stmt(s);
                    const jump_pc = try self.chunk.emit_op(.jump);
                    try self.chunk.emit_i16(0);
                    try body_jumps.append(jump_pc);
                }

                const end_pc = self.chunk.count();
                std.mem.writeInt(u16, self.chunk.code.items[choices_end_pc + 1 ..][0..2], @intCast(end_pc), .little);
                for (offer_pcs.items, body_pcs.items) |offer_pc, body_pc| {
                    std.mem.writeInt(u16, self.chunk.code.items[offer_pc + 5 ..][0..2], @intCast(body_pc), .little);
                }
                for (body_jumps.items) |jump_pc| {
                    const offset: i16 = @intCast(end_pc - (jump_pc + 3));
                    std.mem.writeInt(i16, self.chunk.code.items[jump_pc + 1 ..][0..2], offset, .little);
                }
            },
            .resume_stmt => {
                _ = try self.chunk.emit_op(.resume_routine);
            },
            .weave => |wv| {
                const draft_ent = try self.resolve_entity(wv.draft);
                const target_ent = try self.resolve_entity(wv.target);
                try self.chunk.emit_weave(draft_ent, target_ent);
            },
        }
    }

    /// Interns a stable explanation of the condition that pruned a dialogue branch (P27-02).
    fn guard_failure_text(self: *Codegen, expr: Expr) !EntityId {
        const text = switch (expr) {
            .has_fact => |pat| if (pat.args.len > 1)
                try std.fmt.allocPrint(self.allocator, "missing {s}({s}, {s})", .{ pat.relation, pat.args[0], pat.args[1] })
            else
                try std.fmt.allocPrint(self.allocator, "missing {s}({s})", .{ pat.relation, pat.args[0] }),
            .not_fact => |pat| if (pat.args.len > 1)
                try std.fmt.allocPrint(self.allocator, "blocked by {s}({s}, {s})", .{ pat.relation, pat.args[0], pat.args[1] })
            else
                try std.fmt.allocPrint(self.allocator, "blocked by {s}({s})", .{ pat.relation, pat.args[0] }),
            .roll_gte => |roll| try std.fmt.allocPrint(self.allocator, "failed {d}d{d} >= {d}", .{ roll.count, roll.sides, roll.threshold }),
            .count_at_least => |c| blk: {
                const label = try self.pattern_text(c.pattern);
                defer self.allocator.free(label);
                break :blk try std.fmt.allocPrint(self.allocator, "needs {d} of {s}", .{ c.threshold, label });
            },
            .points_at_least => |c| blk: {
                const label = try self.pattern_text(c.pattern);
                defer self.allocator.free(label);
                break :blk try std.fmt.allocPrint(self.allocator, "needs {d} points of {s}", .{ c.threshold, label });
            },
        };
        defer self.allocator.free(text);
        return self.world.intern_entity(text);
    }

    /// Emits the arguments a fact query pops, and returns its wildcard mask: bit 0 subject,
    /// bit 1 relation, bit 2 object. The relation is always pushed. Aggregates treat `_` in
    /// the subject slot as a wildcard; ordinary conditions keep their historical binding.
    fn emit_pattern_args(self: *Codegen, pat: FactPattern, wildcard_subject: bool) !u8 {
        var mask: u8 = 0x02; // bit 1 (rel)
        if (!wildcard_subject or !std.mem.eql(u8, pat.args[0], "_")) {
            try self.emit_entity_arg(pat.args[0], try self.entity_arg(pat.args[0]));
            mask |= 0x01;
        }
        try self.chunk.emit_push_relation(try self.resolve_relation(pat.relation));
        if (pat.args.len > 1 and !std.mem.eql(u8, pat.args[1], "_")) {
            try self.note_object_kind(pat.relation, pat.args[1]);
            if (self.local_index(pat.args[1])) |index| {
                try self.chunk.emit_push_local(index);
            } else {
                try self.chunk.emit_push_const(try self.fact_value(pat.relation, pat.args[1]));
            }
            mask |= 0x04;
        }
        return mask;
    }

    fn pattern_text(self: *Codegen, pat: FactPattern) ![]u8 {
        return if (pat.args.len > 1)
            std.fmt.allocPrint(self.allocator, "{s}({s}, {s})", .{ pat.relation, pat.args[0], pat.args[1] })
        else
            std.fmt.allocPrint(self.allocator, "{s}({s})", .{ pat.relation, pat.args[0] });
    }

    fn compile_expr(self: *Codegen, expr: Expr) !void {
        switch (expr) {
            .roll_gte => |r| {
                try self.chunk.emit_roll_dice(r.count, r.sides);
                try self.chunk.emit_push_const(r.threshold);
                _ = try self.chunk.emit_op(.gte);
            },
            .has_fact => |pat| {
                const mask = try self.emit_pattern_args(pat, false);
                _ = try self.chunk.emit_op(.query_has);
                try self.chunk.emit_u8(mask);
            },
            .not_fact => |pat| {
                const mask = try self.emit_pattern_args(pat, false);
                _ = try self.chunk.emit_op(.query_has);
                try self.chunk.emit_u8(mask);
                _ = try self.chunk.emit_op(.not);
            },
            .count_at_least => |c| {
                const mask = try self.emit_pattern_args(c.pattern, true);
                try self.chunk.emit_query_aggregate(.query_count, mask, c.threshold);
            },
            .points_at_least => |c| {
                const mask = try self.emit_pattern_args(c.pattern, true);
                try self.chunk.emit_query_aggregate(.query_points, mask, c.threshold);
            },
        }
    }

    /// A name of a thing used as a constant. A lowercase name is a variable (D-161): one this
    /// body can read is refused here, where no value can stand in for it; any other is not
    /// bound at all, and the help offers the capitalised name the author probably meant.
    fn resolve_entity(self: *Codegen, name: []const u8) !EntityId {
        if (is_variable_name(name)) {
            self.error_context = name;
            if (self.local_index(name) != null) return error.VariableNotAllowedHere;
            if (self.when_patterns) |patterns| {
                for (patterns) |pat| {
                    for (pat.args) |arg| {
                        if (std.mem.eql(u8, arg, name)) return error.WhenBodyVariable;
                    }
                }
            }
            self.suggest_capitalised(name);
            return error.UnboundVariable;
        }
        return try self.world.intern_entity(name);
    }

    /// A declared thing's name must start with a capital letter (D-161).
    fn check_thing_name(self: *Codegen, name: []const u8) !void {
        if (name.len == 0 or !std.ascii.isLower(name[0])) return;
        self.error_context = name;
        self.suggest_capitalised(name);
        return error.LowercaseName;
    }

    fn suggest_capitalised(self: *Codegen, name: []const u8) void {
        if (name.len > self.suggestion_buf.len) return;
        @memcpy(self.suggestion_buf[0..name.len], name);
        self.suggestion_buf[0] = std.ascii.toUpper(name[0]);
        self.error_suggestion = self.suggestion_buf[0..name.len];
    }

    fn local_index(self: *const Codegen, name: []const u8) ?u8 {
        const locals = self.locals orelse return null;
        return locals.get(name);
    }

    /// Pushes an entity argument: a handler local when the name is one (D-161), else the
    /// named entity.
    fn emit_entity_arg(self: *Codegen, name: []const u8, entity: ?EntityId) !void {
        if (self.local_index(name)) |index| return self.chunk.emit_push_local(index);
        try self.chunk.emit_push_entity(entity.?);
    }

    /// Resolves an entity argument unless it is a handler local, which is read at run time.
    /// Resolution order decides entity ids, so callers resolve before pushing, as before.
    fn entity_arg(self: *Codegen, name: []const u8) !?EntityId {
        if (self.local_index(name) != null) return null;
        return try self.resolve_entity(name);
    }

    fn resolve_relation(self: *Codegen, name: []const u8) !RelationKind {
        // `Looks(Thing, Look)` is a reserved property: a thing shows one look (D-181).
        if (std.mem.eql(u8, name, LOOKS_RELATION)) return try self.world.intern_relation_kind(name, .property, .entity);
        return try self.world.intern_relation(name, .set);
    }

    /// The value slot a `remember` writes. A fact on an axis needs a character and a value;
    /// any other one-argument fact is a state and stores nothing.
    fn fact_object(self: *Codegen, relation: []const u8, args: []const []const u8) !u32 {
        if (args.len > 1) return self.fact_value(relation, args[1]);
        if (self.axis_bound(relation)) {
            self.error_context = relation;
            return error.InvalidAxisValue;
        }
        return 0;
    }

    /// Fixes `relation`'s object kind from one written object (P48-08, D-178): a number,
    /// `true`, `false`, or an axis value makes it a number relation, and an entity name or a cue
    /// parameter an entity relation. A variable a guard or trigger binds, and `_`, say nothing.
    /// A relation used both ways is refused at the use that disagrees.
    fn note_object_kind(self: *Codegen, relation: []const u8, arg: []const u8) !void {
        if (arg.len == 0 or std.mem.eql(u8, arg, "_")) return;
        const kind: world_mod.ObjectKind = blk: {
            if (self.axis_bound(relation)) break :blk .number;
            if (self.local_index(arg)) |index| {
                if (index < CUE_BINDING_BASE) break :blk .entity;
                return;
            }
            if (std.mem.eql(u8, arg, "true") or std.mem.eql(u8, arg, "false")) break :blk .number;
            if (std.ascii.isDigit(arg[0]) or (arg[0] == '-' and arg.len > 1 and std.ascii.isDigit(arg[1]))) break :blk .number;
            if (is_variable_name(arg) or arg[0] == '?') return;
            break :blk .entity;
        };
        const rel = try self.resolve_relation(relation);
        self.world.declare_object_kind(rel, kind) catch |err| {
            self.error_context = arg;
            return err;
        };
    }

    fn axis_bound(self: *Codegen, relation: []const u8) bool {
        const rel = self.world.lookup_relation(relation) orelse return false;
        return self.world.value_bound(rel) != null;
    }

    /// The object of a fact written or tested with a literal. On an axis it must be a whole
    /// number from -10 to +10, stored as two's complement; a literal outside the range is a
    /// compile error rather than a clamp, since the author wrote a value the axis cannot hold
    /// (D-144). Elsewhere it is an entity or an unsigned value, as before.
    fn fact_value(self: *Codegen, relation: []const u8, arg: []const u8) !u32 {
        if (self.axis_bound(relation)) {
            return value_mod.encode_literal(arg) orelse {
                self.error_context = arg;
                return error.InvalidAxisValue;
            };
        }
        return self.resolve_entity_or_value(arg);
    }

    fn resolve_entity_or_value(self: *Codegen, name: []const u8) !u32 {
        // Only an axis value may be negative; elsewhere `-3` would become an entity name.
        if (name.len > 1 and name[0] == '-' and std.ascii.isDigit(name[1])) {
            self.error_context = name;
            return error.NegativeValueOutsideAxis;
        }
        if (std.fmt.parseInt(u32, name, 10)) |val| {
            return val;
        } else |_| {
            const ent = try self.resolve_entity(name);
            return ent.to_int();
        }
    }

    /// Compiles a cue handler's `where` guard into join clauses (Q-006, D-072). Variable
    /// parameters take the first variable slots, in parameter order, before any variable that
    /// appears only in the guard, so dispatch can bind them to the cue's arguments. A guard
    /// pattern names a state (one argument) or a fact (two); the join has eight slots in all.
    fn compile_cue_guard(self: *Codegen, cue: parser_mod.CueHandler, entry_pc: usize, locals: *std.StringHashMap(u8)) !CueGuard {
        if (cue.params.len > MAX_CUE_PARAMS) {
            self.error_context = cue.params[MAX_CUE_PARAMS];
            return error.TooManyCueParameters;
        }
        var var_map = std.StringHashMap(u8).init(self.allocator);
        defer var_map.deinit();
        var next_var: u8 = 0;
        var guard = CueGuard{ .handler_pc = entry_pc, .clauses = &.{} };
        for (cue.params, 0..) |param, i| {
            if (std.mem.eql(u8, cue_param_key(param), CUE_WILDCARD) and !std.mem.eql(u8, param, "_")) {
                if (var_map.get(param)) |slot| {
                    guard.param_slots[i] = slot;
                } else {
                    try var_map.put(param, next_var);
                    guard.param_slots[i] = next_var;
                    next_var += 1;
                }
            }
        }

        const clauses = try self.allocator.alloc(world_mod.PatternClause, cue.where_patterns.len);
        errdefer self.allocator.free(clauses);
        for (cue.where_patterns, clauses) |pattern, *clause| {
            self.error_context = pattern.relation;
            if (pattern.args.len == 0 or pattern.args.len > 2) return error.InvalidCueGuardPattern;
            clause.* = .{
                .relation = try self.resolve_relation(pattern.relation),
                .subject = try self.resolve_pattern_term(pattern.args[0], &var_map, &next_var),
                .object = if (pattern.args.len == 2)
                    try self.resolve_object_term(pattern.relation, pattern.args[1], &var_map, &next_var)
                else
                    .{ .wildcard = {} },
            };
            // `VariableBindings` holds eight slots; a ninth variable could never bind.
            if (next_var > 8) return error.TooManyCueGuardVariables;
        }
        guard.clauses = clauses;
        // A variable only the guard names (`loot`) is read from its binding (D-161).
        var bound = var_map.iterator();
        while (bound.next()) |entry| {
            if (!locals.contains(entry.key_ptr.*)) try locals.put(entry.key_ptr.*, CUE_BINDING_BASE + entry.value_ptr.*);
        }
        self.error_context = cue.cue_name;
        return guard;
    }

    /// A pattern's object term: an axis literal is encoded and range-checked like a written one;
    /// a variable or wildcard is unchanged.
    fn resolve_object_term(
        self: *Codegen,
        relation: []const u8,
        arg: []const u8,
        var_map: *std.StringHashMap(u8),
        next_var: *u8,
    ) !world_mod.PatternTerm {
        try self.note_object_kind(relation, arg);
        const literal = arg.len > 0 and (std.ascii.isDigit(arg[0]) or arg[0] == '-');
        if (literal and self.axis_bound(relation)) return .{ .constant = try self.fact_value(relation, arg) };
        return self.resolve_pattern_term(arg, var_map, next_var);
    }

    fn resolve_pattern_term(
        self: *Codegen,
        arg: []const u8,
        var_map: *std.StringHashMap(u8),
        next_var: *u8,
    ) !world_mod.PatternTerm {
        if (std.mem.eql(u8, arg, "_")) {
            return .{ .wildcard = {} };
        }
        if (arg.len > 0 and (arg[0] == '?' or std.ascii.isLower(arg[0]))) {
            if (var_map.get(arg)) |v_idx| {
                return .{ .variable = v_idx };
            }
            const v_idx = next_var.*;
            next_var.* += 1;
            try var_map.put(arg, v_idx);
            return .{ .variable = v_idx };
        }
        if (arg.len > 1 and arg[0] == '-' and std.ascii.isDigit(arg[1])) {
            self.error_context = arg;
            return error.NegativeValueOutsideAxis;
        }
        if (std.fmt.parseInt(u32, arg, 10)) |num| {
            return .{ .constant = num };
        } else |_| {
            const ent = try self.resolve_entity(arg);
            return .{ .constant = ent.to_int() };
        }
    }

    fn find_waypoint(self: *Codegen, name: []const u8) ?u16 {
        const sp = self.spatial orelse return null;
        for (sp.graph.waypoints.items) |wp| {
            if (std.mem.eql(u8, wp.name, name)) return wp.id;
        }
        return null;
    }

    fn resolve_waypoint(self: *Codegen, name: []const u8) !u16 {
        if (self.spatial) |sp| {
            for (sp.graph.waypoints.items) |wp| {
                if (std.mem.eql(u8, wp.name, name)) {
                    return wp.id;
                }
            }
        }
        return 1; // default to first waypoint if spatial not configured
    }
};

/// Where the `idx`th of `count` marks (or props, offset by 10) sits along a scene: 20 units
/// apart from 0, which keeps three within the 1280x720 stage. More than three are spread over
/// the same 40 units instead, since a fourth at 60 would fall off the right edge (D-100).
pub fn stage_x(idx: usize, count: usize) i32 {
    const i: i32 = @intCast(idx);
    if (count <= 3) return i * 20;
    return @divTrunc(i * 40, @as(i32, @intCast(count - 1)));
}

test "D-100: marks and props stay on the stage however many a scene lists" {
    try std.testing.expectEqual(@as(i32, 40), stage_x(2, 3));
    try std.testing.expectEqual(@as(i32, 40), stage_x(4, 5));
    try std.testing.expectEqual(@as(i32, 20), stage_x(2, 5));
    for (4..12) |n| {
        for (0..n) |k| try std.testing.expect(stage_x(k, n) <= 40);
    }
}

test "P4-03: end-to-end compilation from source text to bytecode chunk" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const source =
        \\entity Guard, Cheese
        \\relation Carries(holder, item)
        \\remember Carries(Guard, Cheese)
        \\
        \\routine Patrol(Guard):
        \\  wait 10 ticks
        \\  remember Carries(Guard, Cheese)
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();

    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();

    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    var codegen = Codegen.init(alloc, &world, null);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    try testing.expect(compiled.chunk.count() > 10);
    try testing.expect(compiled.routine_entries.contains("Patrol"));

    // Execute the compiled chunk on the VM to verify runtime execution
    var vm = vm_mod.VM.init(alloc, &world, &compiled.chunk);
    defer vm.deinit();

    _ = try vm.spawn_routine(try world.intern_entity("Guard"), 0);
    _ = try vm.step_tick();

    try testing.expect(world.has_fact(
        try world.intern_entity("Guard"),
        try world.intern_relation("Carries", .set),
        (try world.intern_entity("Cheese")).to_int(),
    ));
}

test "P7-02: codegen compiles verb declarations and say statements into cue emitters" {
    const testing = std.testing;
    const source =
        \\entity Guard
        \\verb TalkTo(speaker, target):
        \\  say speaker: "Greetings traveler!"
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();

    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();

    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    var codegen = Codegen.init(alloc, &world, null);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    try testing.expect(compiled.cue_handler_entries.contains("TalkTo:*:*"));
    try testing.expect(!compiled.cue_handler_entries.contains("TalkTo"));
}

test "P8-02: codegen compiles multi-clause when rules into reactive rules executed on VM" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const source =
        \\entity Guard, Bard, Cheese
        \\relation Carries(holder, item)
        \\relation CharmedBy(listener, musician)
        \\
        \\routine StandWatch(Guard):
        \\  wait 20 ticks
        \\
        \\when Carries(Guard, Cheese) and CharmedBy(Guard, Bard):
        \\  interrupt Guard with:
        \\    wait 5 ticks
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();

    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();

    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    var codegen = Codegen.init(alloc, &world, null);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    try testing.expectEqual(@as(usize, 1), compiled.reactive_rules.items.len);
    const rule = compiled.reactive_rules.items[0];
    try testing.expectEqual(@as(usize, 2), rule.clauses.len);

    // Verify VM loads and evaluates compiled reactive rules
    var vm = vm_mod.VM.init(alloc, &world, &compiled.chunk);
    defer vm.deinit();
    try vm.load_compiled_rules(&compiled);

    const guard = try world.intern_entity("Guard");
    const bard = try world.intern_entity("Bard");
    const cheese = try world.intern_entity("Cheese");
    const carries = try world.intern_relation("Carries", .set);
    const charmed = try world.intern_relation("CharmedBy", .set);

    _ = try vm.spawn_routine(guard, compiled.routine_entries.get("StandWatch").?);

    // Tick 1: Guard starts StandWatch. Only carries cheese, not charmed -> rule does not fire
    try world.remember(guard, carries, cheese.to_int(), 0);
    _ = try vm.step_tick();
    try testing.expectEqual(@as(usize, 0), vm.fibers.items[0].interrupt_stack.items.len);

    // Bard charms Guard -> both clauses match -> reactive rule edge-triggers interrupt!
    try world.remember(guard, charmed, bard.to_int(), 10);
    _ = try vm.step_tick();
    try testing.expectEqual(@as(usize, 1), vm.fibers.items[0].interrupt_stack.items.len);
}

test "P11-01 / P11-02: codegen compiles 3-parameter item-combining cues with commutative matching" {
    const testing = std.testing;
    const source =
        \\entity Hero, Honey, FurTape, FakeBeard
        \\relation Carries(holder, item)
        \\
        \\on cue Uses(Hero, Honey, FurTape):
        \\  remember Carries(Hero, FakeBeard)
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();

    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();

    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    var codegen = Codegen.init(alloc, &world, null);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    // 1. Both permutations match the exact same handler PC (D-013)
    const pc1 = compiled.find_cue_handler("Uses", "Hero", "Honey", "FurTape");
    const pc2 = compiled.find_cue_handler("Uses", "Hero", "FurTape", "Honey");
    try testing.expect(pc1 != null);
    try testing.expect(pc2 != null);
    try testing.expectEqual(pc1.?, pc2.?);

    // 2. Non-matching pair returns fallback or null
    const pc3 = compiled.find_cue_handler("Uses", "Hero", "Honey", "NonExistent");
    _ = pc3;
    // Since fallback "Uses" is registered for base cue name, check specific signature
    try testing.expect(compiled.cue_handler_entries.get("Uses:Hero:Honey:NonExistent") == null);
}

test "P12-01: codegen compiles multi-scene transitions and registers scoped marks" {
    const testing = std.testing;
    const source =
        \\scene: Tavern
        \\cast: Hero
        \\props: HearthProp
        \\marks: Counter, Door
        \\
        \\scene: Wine Cellar
        \\cast: Guard
        \\props: KegProp
        \\marks: KegMark, Hatch
        \\
        \\routine EnterCellar(Hero):
        \\  transition to scene: Wine Cellar
        \\  wait 10 ticks
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();

    var spatial = spatial_mod.SpatialSystem.init(alloc);
    defer spatial.deinit();

    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();

    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    var codegen = Codegen.init(alloc, &world, &spatial);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    // Verify scene entities interned
    const tavern_id = world.lookup_entity("Tavern").?;
    const cellar_id = world.lookup_entity("Wine Cellar").?;

    // Verify waypoints scoped to their respective rooms
    try testing.expectEqual(@as(usize, 2), spatial.graph.count_waypoints_in_room(tavern_id));
    try testing.expectEqual(@as(usize, 2), spatial.graph.count_waypoints_in_room(cellar_id));

    // Verify props scoped to their respective rooms
    try testing.expectEqual(@as(usize, 1), spatial.count_hotspots_in_room(tavern_id));
    try testing.expectEqual(@as(usize, 1), spatial.count_hotspots_in_room(cellar_id));

    // Verify routine compiled and contains transition_scene opcode (0x44)
    const pc = compiled.routine_entries.get("EnterCellar").?;
    const op_byte = compiled.chunk.code.items[pc];
    try testing.expectEqual(@as(u8, @backingInt(Opcode.transition_scene)), op_byte);
    const target_scene_val = std.mem.readInt(u32, compiled.chunk.code.items[pc + 1 ..][0..4], .little);
    try testing.expectEqual(cellar_id.to_int(), target_scene_val);
}

test "P22-01: weaving by notes, reversed notes, in-script weaves, and fizzles end to end" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const source =
        \\entity Player, Brazier, Stone
        \\relation Lit(thing, by)
        \\draft Kindle(C, E, G, E) reverse Douse
        \\draft Mend(D, A, A, D)
        \\
        \\on cue Weave(Player, Kindle, Brazier):
        \\  remember Lit(Brazier, Player)
        \\
        \\on cue Weave(Player, Douse, Brazier):
        \\  forget Lit(Brazier, _)
        \\
        \\routine Ritual(Player):
        \\  wait 1 ticks
        \\  weave Kindle on Brazier
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();
    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();
    var codegen = Codegen.init(alloc, &world, null);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    // Kindle, Douse (declared reverse), Mend (palindrome, no reverse)
    try testing.expectEqual(@as(usize, 3), compiled.drafts.items.len);

    var vm = vm_mod.VM.init(alloc, &world, &compiled.chunk);
    defer vm.deinit();

    const player = world.lookup_entity("Player").?;
    const brazier = world.lookup_entity("Brazier").?;
    const stone = world.lookup_entity("Stone").?;
    const kindle = world.lookup_entity("Kindle").?;
    const lit = world.lookup_relation("Lit").?;

    // Forward notes resolve to Kindle and run its handler.
    try testing.expect((try vm.weave_notes(&compiled, player, .{ .C, .E, .G, .E }, brazier)) != null);
    _ = try vm.step_tick();
    try testing.expect(world.has_fact(brazier, lit, player.to_int()));

    // Reversed notes resolve to Douse: the complementary effect.
    try testing.expect((try vm.weave_notes(&compiled, player, .{ .E, .G, .E, .C }, brazier)) != null);
    _ = try vm.step_tick();
    try testing.expect(!world.has_fact(brazier, lit, null));

    // Unknown notes, a draft with no handler, and a handler-less target all fizzle.
    vm.emitted_cues.clearRetainingCapacity();
    try testing.expect((try vm.weave_notes(&compiled, player, .{ .C, .C, .C, .C }, brazier)) == null);
    try testing.expect((try vm.weave_notes(&compiled, player, .{ .D, .A, .A, .D }, brazier)) == null);
    try testing.expect((try vm.weave_draft(&compiled, player, kindle, stone)) == null);
    // A non-draft entity never reaches a handler, even if one were keyed on its name.
    try testing.expect((try vm.weave_draft(&compiled, player, brazier, brazier)) == null);
    const fizzle_id: u16 = @intCast(world.lookup_entity(draft_mod.WEAVE_FIZZLED_CUE).?.to_int() & 0xFFFF);
    try testing.expectEqual(@as(usize, 4), vm.emitted_cues.items.len);
    for (vm.emitted_cues.items) |c| try testing.expectEqual(fizzle_id, c.cue_id);
    try testing.expect(!world.has_fact(stone, lit, null));

    // In-script weave queues for host re-dispatch instead of running mid-tick.
    _ = try vm.spawn_routine(player, compiled.routine_entries.get("Ritual").?);
    _ = try vm.step_tick(); // wait 1 tick
    _ = try vm.step_tick(); // executes weave opcode
    try testing.expectEqual(@as(usize, 1), vm.pending_weaves.items.len);
    try testing.expectEqual(kindle, vm.pending_weaves.items[0].draft);
    try testing.expectEqual(player, vm.pending_weaves.items[0].caster);
    try testing.expect(!world.has_fact(brazier, lit, null));

    try testing.expectEqual(@as(usize, 1), try vm.dispatch_pending_weaves(&compiled));
    try testing.expectEqual(@as(usize, 0), vm.pending_weaves.items.len);
    _ = try vm.step_tick(); // handler fiber runs
    try testing.expect(world.has_fact(brazier, lit, player.to_int()));
}

test "P22-01: saving with undispatched weaves is refused" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    var vm = vm_mod.VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    const p = try world.intern_entity("Player");
    try vm.pending_weaves.append(.{ .caster = p, .draft = p, .target = p });

    var buf = std.array_list.Managed(u8).init(testing.allocator);
    defer buf.deinit();
    var lw1 = ListWriter.init(&buf);
    try testing.expectError(
        error.PendingWeavesNotDispatched,
        save_mod.write_save_state(testing.allocator, &lw1.writer, &world, null, &vm, .{}),
    );
}

test "P32-28: Option C predicate presence for states without synthetic true entity" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const source =
        \\entity Hero, Flags
        \\scene: Beach
        \\
        \\Tampered is a state.
        \\
        \\now Flags are Tampered
        \\
        \\routine Check(Hero):
        \\  if Flags are Tampered:
        \\    now Flags are not Tampered
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();

    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();

    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();

    var codegen = Codegen.init(alloc, &world, null);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    // 1. Verify entity "true" was never interned (D-043, Option C)
    try testing.expect(world.lookup_entity("true") == null);

    const flags = try world.intern_entity("Flags");
    const tampered = try world.intern_relation("Tampered", .set);
    const hero = try world.intern_entity("Hero");

    var vm = vm_mod.VM.init(alloc, &world, &compiled.chunk);
    defer vm.deinit();

    // 2. Execute initial declarative statements (`now Flags are Tampered`)
    if (compiled.initial_entry) |init_pc| {
        _ = try vm.spawn_routine(hero, init_pc);
        _ = try vm.step_tick();
    }

    // Initial statement remembered with object_or_value = 0
    try testing.expect(world.has_fact(flags, tampered, null));
    try testing.expect(world.has_fact(flags, tampered, 0));

    // 3. Execute routine Check on VM to test `if Flags are Tampered:` and `now Flags are not Tampered`
    const entry_pc = compiled.routine_entries.get("Check").?;
    _ = try vm.spawn_routine(hero, entry_pc);
    _ = try vm.step_tick();

    // 4. Verify "now Flags are not Tampered" cleared the state
    try testing.expect(!world.has_fact(flags, tampered, null));

    // 5. Verify host asserting with object_or_value = 0 is immediately recognized
    try world.remember(flags, tampered, 0, 0);
    try testing.expect(world.has_fact(flags, tampered, null));
}

test "P32-30: a scripted choice set suspends, prunes, and resumes at the chosen body" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const dialogue_mod = @import("../dialogue.zig");
    const source =
        \\entity Actor, Host, Coin
        \\relation Carries(holder, item)
        \\
        \\on cue Talk(Actor, Host):
        \\  say Host: "Choose."
        \\  choice "Always":
        \\    say Host: "Always body."
        \\  choice "Only with coin" if Carries(Actor, Coin):
        \\    say Host: "Coin body."
        \\  choice "Without coin" if not Carries(Actor, Coin):
        \\    say Host: "No coin body."
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();
    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();
    var codegen = Codegen.init(alloc, &world, null);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    const actor = try world.intern_entity("Actor");
    const host = try world.intern_entity("Host");
    var vm = vm_mod.VM.init(alloc, &world, &compiled.chunk);
    defer vm.deinit();

    try vm.set_dialogue_speaker(actor, host);
    _ = try vm.fire_cue(&compiled, "Talk", actor, host, null);
    _ = try vm.step_tick();

    const open = vm.dialogue_view().?;
    try testing.expectEqual(@as(usize, 2), open.count);
    try testing.expectEqualStrings("Always", open.text(0));
    try testing.expectEqualStrings("Without coin", open.text(1));
    try testing.expectEqual(host, open.display_speaker);
    try testing.expectEqual(@as(usize, 3), open.branch_count);
    try testing.expect(open.branch(0).active);
    try testing.expect(!open.branch(1).active);
    try testing.expectEqualStrings("Only with coin", open.branch(1).text);
    try testing.expectEqualStrings("missing Carries(Actor, Coin)", open.branch(1).failure);
    try testing.expect(open.branch(2).active);
    try testing.expectEqualStrings("Choose.", world.get_entity_name(EntityId.from_int(vm.emitted_cues.items[0].args[1])).?);

    const selection = (try vm.choose(1)).?;
    try testing.expect(selection.is_scripted());
    _ = try vm.step_tick();
    try testing.expect(vm.dialogue_view() == null);

    var found = false;
    for (vm.emitted_cues.items) |cue| {
        if (world.get_entity_name(EntityId.from_int(cue.args[1]))) |text| {
            if (std.mem.eql(u8, text, "No coin body.")) found = true;
        }
    }
    try testing.expect(found);

    // The same set with the guard true offers the other variant, and a world snapshot carries
    // the open set because every option is a fact (P32-30).
    const coin = try world.intern_entity("Coin");
    try world.remember(actor, try world.intern_relation("Carries", .set), coin.to_int(), 0);
    try vm.set_dialogue_speaker(actor, host);
    _ = try vm.fire_cue(&compiled, "Talk", actor, host, null);
    _ = try vm.step_tick();
    const with_coin = vm.dialogue_view().?;
    try testing.expectEqualStrings("Only with coin", with_coin.text(1));
    try testing.expect(with_coin.branch(1).active);
    try testing.expect(!with_coin.branch(2).active);
    try testing.expectEqualStrings("blocked by Carries(Actor, Coin)", with_coin.branch(2).failure);

    var snap = std.array_list.Managed(u8).init(alloc);
    defer snap.deinit();
    var lw2 = ListWriter.init(&snap);
    try world.save_state(&lw2.writer);
    var stream: std.Io.Reader = .fixed(snap.items);
    try world.restore_state(&stream);
    try testing.expectEqualStrings("Only with coin", vm.dialogue_view().?.text(1));
    try testing.expectEqualStrings("blocked by Carries(Actor, Coin)", vm.dialogue_view().?.branch(2).failure);

    const coin_selection = (try vm.choose(1)).?;
    try testing.expectEqual(@as(u32, 1), coin_selection.index);
    _ = try vm.step_tick();
    try testing.expect(vm.dialogue_view() == null);

    const generated = [_]dialogue_mod.Choice{
        .{ .text = "Parry high.", .action = 11 },
        .{ .text = "Parry low.", .action = 12 },
    };
    _ = try vm.open_generated_dialogue(host, "Choose a guard.", &generated);
    const generated_view = vm.dialogue_view().?;
    try testing.expectEqualStrings("Choose a guard.", generated_view.prompt);
    try testing.expectEqual(@as(u32, 12), generated_view.action(1));
    try testing.expectEqual(@as(usize, 2), generated_view.branch_count);
    try testing.expect(generated_view.branch(0).active);
    const generated_selection = (try vm.choose(1)).?;
    try testing.expect(!generated_selection.is_scripted());
    try testing.expectEqual(@as(u32, 12), generated_selection.action);
}

test "P32-22/P32-24: society and duel declarations compile into executable program data" {
    const testing = std.testing;
    const source =
        \\scene: Test Square
        \\cast: Alice, Merchant, Rival
        \\marks: Home, Market, Square
        \\
        \\society TestSociety:
        \\  need Hunger high 100 1 0 50 trade Merchant 2 20 0 80 30 0 "a meal"
        \\  member Alice 5 working:
        \\    need Hunger 10 none Merchant
        \\    routine working 2 Home, Square
        \\  member Merchant 10 working:
        \\    need Hunger 10 none Merchant
        \\    routine working 2 Market
        \\    merchant Market Goods
        \\    owns Goods
        \\    carries Goods
        \\  gathering Square
        \\  flight Home none 4
        \\  friend Alice Merchant
        \\
        \\duel TestDuel:
        \\  pair Riddle:
        \\    challenge "What speaks without a mouth?"
        \\    reply "An echo."
        \\    variant 1 "Voiceless, I answer."
        \\  fallback "I do not know."
        \\  win 3
        \\  tier Rival 1
        \\  fatigue Inquiries "calm":
        \\    stage AnnoyedWith 2 10 "annoyed"
    ;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var world = try World.init(alloc, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(alloc);
    defer spatial.deinit();
    var lexer = lexer_mod.Lexer.init(alloc, source);
    defer lexer.deinit();
    var parser = try parser_mod.Parser.init(alloc, &lexer);
    const ast = try parser.parse_program();
    var codegen = Codegen.init(alloc, &world, &spatial);
    var compiled = try codegen.compile(&ast);
    defer compiled.deinit();

    try testing.expectEqual(@as(usize, 1), compiled.societies.items.len);
    var society = try society_mod.Society.init(&world, compiled.societies.items[0].config);
    try testing.expectEqual(@as(usize, 0), society.need_index("Hunger").?);
    const alice = world.lookup_entity("Alice").?;
    try testing.expectEqual(@as(u32, 10), society.get_need(&world, alice, 0));

    try testing.expectEqual(@as(usize, 1), compiled.duels.items.len);
    const duel_decl = &compiled.duels.items[0];
    var duel = try duel_mod.Duel.init(&world, duel_decl.config);
    try duel_decl.apply_tiers(&duel);
    const rival = world.lookup_entity("Rival").?;
    try testing.expectEqual(@as(u32, 1), world.get_property(rival, duel.tier_rel).?);
    var fatigue = try duel_mod.InquiryFatigue.init(&world, duel_decl.fatigue);
    try testing.expectEqual(@as(?usize, null), try fatigue.record(alice, rival));
}

test "P25-01: grid declarations compile into overlays, layouts, and placed marks" {
    const testing = std.testing;
    const host = @import("../host.zig");
    const grid_mod_t = @import("../grid.zig");
    const source =
        \\scene: Great Hall
        \\marks: HallDoor, HallHearth, HallStair
        \\
        \\grid HallFloor in "Great Hall":
        \\  size 4 3
        \\  cell 20
        \\  flammable 1 0 2 2
        \\  flammable 2 1
        \\  liquid 0 2
        \\  blocking 3 0
        \\  place HallDoor 0 0
        \\  place HallStair 3 0
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try @import("../compiler.zig").compile_source(testing.allocator, &world, &spatial, source);
    defer compiled.deinit();

    try testing.expectEqual(@as(usize, 1), compiled.grids.items.len);
    const declaration = compiled.grids.items[0];
    // The 2x2 rectangle and the overlapping single cell expand to four flammable rows.
    try testing.expectEqual(@as(usize, 6), declaration.cells.len);
    const room = world.lookup_entity("Great Hall").?;
    const grid = spatial.grid_in_room(room).?;
    try testing.expectEqual(world.lookup_entity("HallFloor").?, grid.entity);

    // Placed marks sit at cell centres; the unplaced hearth keeps its compiler position.
    const door = spatial.graph.find_waypoint("HallDoor").?;
    const stair = spatial.graph.find_waypoint("HallStair").?;
    try testing.expectEqual(GridCellT{ .x = 0, .y = 0 }, spatial.waypoint_cell(door).?.cell);
    try testing.expectEqual(GridCellT{ .x = 3, .y = 0 }, spatial.waypoint_cell(stair).?.cell);
    try testing.expectEqual(@as(i32, 70), spatial.graph.get_waypoint(stair).?.pos.x);

    try host.initialize_subsystems(&world, &compiled);
    try testing.expect(grid_mod_t.has_attribute(&world, grid, .{ .x = 2, .y = 1 }, .flammable));
    try testing.expect(grid_mod_t.has_attribute(&world, grid, .{ .x = 0, .y = 2 }, .liquid));
    try testing.expect(!grid_mod_t.has_attribute(&world, grid, .{ .x = 0, .y = 0 }, .flammable));
    try testing.expect(spatial.waypoint_blocked(&world, stair));
    try testing.expect(!spatial.waypoint_blocked(&world, door));

    // Seeding is idempotent: a cleared cell stays cleared through re-initialisation.
    try grid_mod_t.set_attribute(&world, grid, .{ .x = 3, .y = 0 }, .blocking, false);
    try host.initialize_subsystems(&world, &compiled);
    try testing.expect(!spatial.waypoint_blocked(&world, stair));
}

const GridCellT = @import("../grid.zig").Cell;

test "P25-01: grid declarations reject malformed and out-of-range layouts" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    const bad = [_][]const u8{
        "grid G in Room:\n  cell 10\n",
        "grid G in Room:\n  size 2 2\n",
        "grid G in Room:\n  size 2 2\n  cell 10\n  flammable 1 1 2 1\n",
        "grid G in Room:\n  size 2 2\n  cell 10\n  place Somewhere 2 0\n",
        "grid G in Room:\n  size 2 2\n  cell 10\n  wet 0 0\n",
        "grid G in Room:\n  size 65 64\n  cell 10\n",
        "grid G in Room:\n  size 1 1\n  cell 10\ngrid H in Room:\n  size 1 1\n  cell 10\n",
    };
    for (bad) |source| {
        const result = compiler.check_source(testing.allocator, source);
        try testing.expect(result.diagnostic() != null);
    }

    // A placed mark must exist and belong to the grid's room.
    const misplaced =
        \\scene: Yard
        \\marks: YardGate
        \\
        \\scene: Keep
        \\marks: KeepDoor
        \\
        \\grid KeepFloor in Keep:
        \\  size 2 2
        \\  cell 10
        \\  place YardGate 0 0
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    try testing.expectError(error.GridMarkOutsideRoom, compiler.compile_source(testing.allocator, &world, &spatial, misplaced));
}

test "P33-01: agenda declarations compile and reject malformed agendas" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\agenda WarnOff:
        \\  actor Keeper
        \\  target Hero
        \\  priority 3
        \\  once
        \\  requires Investigated(Hero, Shed)
        \\  unless Warned(_)
        \\agenda Gossip:
        \\  actor Maid
        \\  target Hero
        \\  requires Seen(Hero)
    );
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 2), compiled.agendas.items.len);
    const warn = compiled.agendas.items[0].agenda;
    try testing.expect(warn.once and warn.priority == 3);
    try testing.expectEqual(world.lookup_entity("Shed").?, warn.clauses[0].object.?);
    try testing.expect(warn.clauses[1].subject == null and warn.clauses[1].negated);
    try testing.expectEqualStrings("Gossip", world.get_entity_name(compiled.agendas.items[1].agenda.entity).?);

    const bad = [_][]const u8{
        "agenda A:\n  target Hero\n  requires Seen(Hero)\n",
        "agenda A:\n  actor Keeper\n  requires Seen(Hero)\n",
        "agenda A:\n  actor Keeper\n  target Hero\n",
        "agenda A:\n  actor Hero\n  target Hero\n  requires Seen(Hero)\n",
        "agenda A:\n  actor Keeper\n  target Hero\n  requires Seen(Hero, Shed, Barn)\n",
        "agenda A:\n  actor Keeper\n  target Hero\n  wants Seen(Hero)\n",
        "agenda A:\n  actor K\n  target H\n  requires S(H)\nagenda A:\n  actor K\n  target H\n  requires S(H)\n",
    };
    for (bad) |source| try testing.expect(compiler.check_source(testing.allocator, source).diagnostic() != null);
}

test "P26-01: command and alias declarations compile and reject malformed ones" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\command Pours: "pour <thing> into <thing>"
        \\command Takes: "take <thing>"
        \\alias ExposureSlip: "Plate Slip", "receipt"
    );
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 2), compiled.commands.items.len);
    const pour = try compiled.commands.items[0].frame();
    try testing.expectEqualStrings("Pours", pour.cue);
    try testing.expectEqual(@as(usize, 2), pour.slots());
    try testing.expectEqual(@as(usize, 1), compiled.aliases.items.len);
    const alias = compiled.aliases.items[0];
    try testing.expectEqual(world.lookup_entity("ExposureSlip").?, alias.entity);
    try testing.expectEqualStrings("plate slip", alias.phrases[0]); // stored lowercase

    const bad = [_][]const u8{
        "command Pours: \"<thing> into <thing>\"\n",
        "command Pours: \"give <thing> <thing>\"\n",
        "command Pours: pour\n",
        "alias Slip: \"\"\n",
        "alias Slip:\n",
    };
    for (bad) |source| try testing.expect(compiler.check_source(testing.allocator, source).diagnostic() != null);
}

test "P23-01: degradation declarations compile into executable container profiles" {
    const testing = std.testing;
    const source =
        \\degradation TestProfile:
        \\  substance TestReagent
        \\  stage Sound 3
        \\  stage Etched 2
        \\  stage Failed 0
        \\  vessel TestVial 8 5 Sound
        \\  spill 2
        \\  relations HoldsReagent ReagentVolume VialState ReagentExposure VialFailedAt
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try @import("../compiler.zig").compile_source(testing.allocator, &world, null, source);
    defer compiled.deinit();

    try testing.expectEqual(@as(usize, 1), compiled.degradations.items.len);
    const declaration = &compiled.degradations.items[0];
    try testing.expectEqual(@as(u32, 2), declaration.config.spill_per_moving_tick);
    const system = try container_mod.ContainerSystem.init(&world, declaration.config);
    const vial = world.lookup_entity("TestVial").?;
    try testing.expectEqual(world.lookup_entity("Sound").?.to_int(), world.get_property(vial, system.rel.stage).?);
    try testing.expectEqual(@as(u32, 5), world.get_property(vial, system.rel.volume).?);
    try testing.expectEqualStrings("VialState", world.get_relation_meta(system.rel.stage).?.name);
}

test "P24-01: selecting a path asserts its facts and mutes inactive routines" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const source =
        \\entity Hero
        \\relation ChosenWits(flag)
        \\relation ChosenFists(flag)
        \\relation WitsSolved(flag)
        \\relation FistsSolved(flag)
        \\path Wits:
        \\  remember ChosenWits(Hero)
        \\  routine WitsPlan(Hero):
        \\    remember WitsSolved(Hero)
        \\path Fists:
        \\  remember ChosenFists(Hero)
        \\  routine FistsPlan(Hero):
        \\    remember FistsSolved(Hero)
    ;

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try @import("../compiler.zig").compile_source(testing.allocator, &world, null, source);
    defer compiled.deinit();

    try testing.expect(compiled.find_path("Wits") != null);
    try testing.expect(compiled.find_path("Fists") != null);

    var vm = vm_mod.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();

    const selected = try vm.select_path(&compiled, "Wits");
    try testing.expect(selected != null);
    _ = try vm.step_tick(); // Run the path's fact initializer.

    const hero = world.lookup_entity("Hero").?;
    const wits = world.lookup_entity("Wits").?;
    const path_active = world.lookup_relation("PathActive").?;
    const chosen_wits = world.lookup_relation("ChosenWits").?;
    try testing.expect(world.has_fact(wits, path_active, null));
    try testing.expect(world.has_fact(hero, chosen_wits, null));

    _ = try vm.spawn_routine(hero, compiled.routine_entries.get("WitsPlan").?);
    _ = try vm.spawn_routine(hero, compiled.routine_entries.get("FistsPlan").?);
    _ = try vm.step_tick();

    const wits_solved = world.lookup_relation("WitsSolved").?;
    const fists_solved = world.lookup_relation("FistsSolved").?;
    try testing.expect(world.has_fact(hero, wits_solved, null));
    try testing.expect(!world.has_fact(hero, fists_solved, null));

    // Paths are final (D-103): another path is refused, the same one again is a no-op.
    try testing.expectError(error.PathAlreadyChosen, vm.select_path(&compiled, "Fists"));
    try testing.expect((try vm.select_path(&compiled, "Wits")) == null);
    try testing.expect(!world.has_fact(world.lookup_entity("Fists").?, path_active, null));
}

test "P24-02: active path mutates obstacle facts and prunes rival dialogue choices" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const source =
        \\entity Hero, Host, BackAlley, SafeRoute
        \\relation WaypointBlocked(mark)
        \\relation Trapped(actor)
        \\path Wits:
        \\  remember WaypointBlocked(BackAlley)
        \\  remember Trapped(Hero)
        \\path Fists:
        \\  remember WaypointBlocked(SafeRoute)
        \\on cue Talk(Hero, Host):
        \\  choice "Study the ledger" if PathActive(Wits):
        \\    say Host: "The ledger is open."
        \\  choice "Break the lock" if PathActive(Fists):
        \\    say Host: "The lock gives way."
        \\  choice "Leave":
        \\    say Host: "Later."
    ;

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try @import("../compiler.zig").compile_source(testing.allocator, &world, null, source);
    defer compiled.deinit();

    const hero = world.lookup_entity("Hero").?;
    const host = world.lookup_entity("Host").?;
    const back_alley = world.lookup_entity("BackAlley").?;
    const wits = world.lookup_entity("Wits").?;
    const blocked = world.lookup_relation("WaypointBlocked").?;
    const trapped = world.lookup_relation("Trapped").?;
    const path_active = world.lookup_relation("PathActive").?;

    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    const portal = try world.intern_entity("Portal");
    const room = EntityId.from_int(1);
    const back_alley_wp = try spatial.graph.add_waypoint(room, 0, 0, "BackAlley");
    try spatial.register_portal(portal, room, back_alley_wp);
    try spatial.register_entity(hero, back_alley_wp, 2);
    try testing.expect(spatial.can_access_portal(&world, hero));

    var vm = vm_mod.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    try vm.set_dialogue_speaker(hero, host);

    _ = try vm.select_path(&compiled, "Wits");
    _ = try vm.step_tick();
    try testing.expect(world.has_fact(wits, path_active, null));
    try testing.expect(world.has_fact(back_alley, blocked, null));
    try testing.expect(world.has_fact(hero, trapped, null));
    try testing.expect(!spatial.can_access_portal(&world, hero));

    _ = try vm.fire_cue(&compiled, "Talk", hero, host, null);
    _ = try vm.step_tick();

    const open = vm.dialogue_view().?;
    try testing.expectEqual(@as(usize, 2), open.count);
    try testing.expectEqualStrings("Study the ledger", open.text(0));
    try testing.expectEqualStrings("Leave", open.text(1));

    _ = world.forget(hero, trapped, null);
    try testing.expect(spatial.can_access_portal(&world, hero));
}

test "P28-03: score declarations compile, seed scene facts, and play and stop by World facts" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    const host = @import("../host.zig");
    const display = @import("../display.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\score Calm:
        \\  lead "t96 o5 l8 c e g e"
        \\  bass "o3 c2 g2"
        \\  drums "k4 h4"
        \\  scene Gatehouse
        \\score Chase: "t160 o5 l16 L c d e d"
        \\transition to scene Gatehouse
        \\routine Watch(Warden):
        \\  wait 2 ticks
        \\  play score Chase
        \\  wait 2 ticks
        \\  transition to scene Rampart
        \\  wait 2 ticks
        \\  stop score
        \\  wait 2 ticks
        \\  transition to scene Gatehouse
    );
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 2), compiled.scores.items.len);
    const calm = compiled.scores.items[0];
    try testing.expectEqualStrings("Calm", calm.name);
    try testing.expectEqualStrings("o3 c2 g2", calm.parts[1]);
    try testing.expectEqualStrings("", calm.parts[2]);
    try testing.expectEqualStrings("Gatehouse", calm.scenes[0]);
    // The one-line form is a lead-only score with no scenes.
    try testing.expectEqualStrings("t160 o5 l16 L c d e d", compiled.scores.items[1].parts[0]);
    try testing.expectEqual(@as(usize, 0), compiled.scores.items[1].scenes.len);
    // `PlayingScore` is a property, so a second `play score` replaces the first.
    try testing.expectEqual(world_mod.RelationType.property, world.get_relation_meta(world.lookup_relation("#PlayingScore").?).?.rel_type);

    var vm = @import("../vm.zig").VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    try host.run_initial_statements(&world, &vm, &compiled);
    const calm_id = world.lookup_entity("Calm").?;
    const chase_id = world.lookup_entity("Chase").?;
    try testing.expectEqual(@as(?EntityId, calm_id), display.current_score_entity(&world, vm.current_scene));

    const warden = try world.intern_entity("Warden");
    _ = try vm.spawn_routine(warden, compiled.routine_entries.get("Watch").?);
    var snapshot = std.array_list.Managed(u8).init(testing.allocator);
    defer snapshot.deinit();
    var seen = std.array_list.Managed(?EntityId).init(testing.allocator);
    defer seen.deinit();
    for (0..12) |t| {
        _ = try host.tick(&vm, &compiled);
        const now = display.current_score_entity(&world, vm.current_scene);
        if (seen.items.len == 0 or seen.items[seen.items.len - 1] != now) try seen.append(now);
        var lw3 = ListWriter.init(&snapshot);
        if (t == 3) try world.save_state(&lw3.writer);
    }
    // Calm, then the Chase override, which persists into the Rampart (no scene score there);
    // `stop score` in the Rampart leaves silence, and the Gatehouse brings Calm back.
    try testing.expectEqualSlices(?EntityId, &.{ calm_id, chase_id, null, calm_id }, seen.items);

    // A rewind restores the override along with the rest of the World.
    var stream: std.Io.Reader = .fixed(snapshot.items);
    try world.restore_state(&stream);
    try testing.expectEqual(@as(?EntityId, chase_id), display.current_score_entity(&world, vm.current_scene));
}

test "P28-03: score errors name the script position, the part, and the rule broken" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    const Case = struct { source: []const u8, line: u32, column: u32, message: []const u8 };
    const cases = [_]Case{
        // `x` is MML column 4; the string's quote is at script column 8, so `x` is at 12.
        .{ .source = "score A:\n  lead \"c4 x\"\n", .line = 2, .column = 12, .message = "score 'A' lead: unknown MML command" },
        .{ .source = "score A: \"o4 k\"\n", .line = 1, .column = 14, .message = "score 'A' lead: drum letters k, s, and h belong on a percussion track" },
        .{ .source = "score A:\n  drums \"c4\"\n", .line = 2, .column = 10, .message = "score 'A' drums: a percussion track plays k, s, and h, not notes" },
        .{ .source = "score A:\n  tune \"c\"\n", .line = 2, .column = 3, .message = "unknown score directive 'tune'; use lead, bass, chords, drums, or scene" },
        .{ .source = "score A:\n  lead \"c\"\n  lead \"d\"\n", .line = 3, .column = 3, .message = "score 'A' declares lead twice" },
        .{ .source = "score A:\n  bass c\n", .line = 2, .column = 8, .message = "score 'A' bass needs an MML string" },
        .{ .source = "score A: \"c\"\nscore A: \"d\"\n", .line = 3, .column = 1, .message = "score 'A' is declared twice" },
        .{ .source = "score A:\n  scene Hall\nscore B:\n  scene Hall\n", .line = 5, .column = 1, .message = "scene 'Hall' already plays score 'A'" },
        .{ .source = "routine R(X):\n  play score Missing\n", .line = 2, .column = 14, .message = "play of undeclared score 'Missing'" },
    };
    for (cases) |case| {
        const res = compiler.check_source(testing.allocator, case.source);
        const d = res.diagnostic() orelse {
            std.debug.print("expected an error for: {s}\n", .{case.source});
            return error.TestExpectedError;
        };
        try testing.expectEqualStrings(case.message, d.message);
        try testing.expectEqual(case.line, d.line);
        try testing.expectEqual(case.column, d.column);
    }
    // `stop animate` still parses beside `stop score`.
    try testing.expect(compiler.check_source(testing.allocator, "score A: \"c\"\nroutine R(X):\n  stop score\n  stop animate Sway\n  play score A\n").is_valid);
}

test "P38-01: documented core statements parse and compile" {
    const testing = std.testing;
    const source =
        \\scene: Audit Room
        \\cast: Hero
        \\props: Key
        \\marks: Door
        \\entity Ready, Calm, Wave
        \\relation Carries(holder, item)
        \\relation Seen(who)
        \\property Mood(who, value)
        \\draft Signal(C, D, E, F) reverse Silence
        \\score Audit: "t120 o4 l4 L c"
        \\routine Audit(Hero):
        \\  remember Carries(Hero, Key) for 2 ticks
        \\  forget Carries(Hero, Key)
        \\  now Hero is Ready
        \\  Hero is not Ready
        \\  walk Hero to Door
        \\  face Hero towards Door
        \\  wait 1 ticks
        \\  wait until not Seen(Hero)
        \\  if Carries[Hero, Key]:
        \\    say Hero to Key: "Found it."
        \\  if roll 1d6 >= 1:
        \\    animate(Hero, Wave)
        \\  interrupt Hero with:
        \\    animate Wave
        \\    stop animate Wave
        \\    resume previous action
        \\  choice "Continue":
        \\    weave Signal on Door
        \\  play score Audit
        \\  stop score
        \\  transition to scene: Audit Room
        \\during Crowd:
        \\  loop:
        \\    wait 1 ticks
        \\    done
    ;

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try @import("../compiler.zig").compile_source(testing.allocator, &world, &spatial, source);
    defer compiled.deinit();

    try testing.expect(compiled.routine_entries.contains("Audit"));
    try testing.expect(compiled.routine_entries.contains("Crowd"));
    try testing.expectEqual(@as(usize, 1), compiled.scores.items.len);
}

test "P44-01: goal declarations compile and reject malformed goals" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\entity Hero, TelescopeLog
        \\relation Carries(holder, item)
        \\relation Read(who, item)
        \\scene: PlateArchive
        \\props: ExposureSlip
        \\marks: Archive
        \\goal RecoverThePlate:
        \\  need TakeTheSlip:
        \\    met Carries(Hero, ExposureSlip)
        \\    hint 2 "Your notebook names the slip."
        \\  need ReadTheLog after TakeTheSlip:
        \\    met Read(Hero, TelescopeLog)
        \\    room Archive
    );
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.goals.items.len);
    const goal = compiled.goals.items[0].goal;
    try testing.expectEqualStrings("RecoverThePlate", world.get_entity_name(goal.entity).?);
    try testing.expectEqual(@as(usize, 2), goal.needs.len);
    const take = goal.needs[0];
    try testing.expectEqualStrings("TakeTheSlip", world.get_entity_name(take.entity).?);
    try testing.expectEqualStrings("Carries", take.relation);
    try testing.expectEqual(world.lookup_entity("Hero").?, take.subject.?);
    try testing.expectEqual(world.lookup_entity("ExposureSlip").?, take.object.?);
    // No `room` line: the scene that declares the prop sets the room.
    try testing.expectEqualStrings("PlateArchive", world.get_entity_name(take.room.?).?);
    try testing.expectEqual(@as(usize, 1), take.hints.len);
    try testing.expectEqual(hint_mod.Tier.thing, take.hints[0].tier);
    try testing.expectEqualStrings("Your notebook names the slip.", take.hints[0].text);
    try testing.expectEqual(@as(usize, 1), goal.needs[1].after.len);
    try testing.expectEqual(take.entity, goal.needs[1].after[0]);
    try testing.expectEqualStrings("Archive", world.get_entity_name(goal.needs[1].room.?).?);

    const bad = [_][]const u8{
        "goal G:\n  need A:\n    room Shed\n",
        "goal G:\n  need A:\n    met Seen(Hero)\n    room Shed\n  need A:\n    met Seen(Hero)\n    room Shed\n",
        "goal G:\n  need A:\n    met Seen(Hero)\n    room Shed\n    hint 0 \"no\"\n",
        "goal G:\n  need A:\n    met Seen(Hero)\n    room Shed\n    hint 2 \"one\"\n    hint 2 \"two\"\n",
        "goal G:\n  need A:\n    met Seen(Hero)\n    room Shed\n    wants X\n",
        "goal G:\n  need A after B:\n    met Seen(Hero)\n    room Shed\n",
        "goal G:\n  need A after B:\n    met Seen(Hero)\n    room Shed\n  need B after A:\n    met Seen(Shed)\n    room Shed\n",
    };
    for (bad) |source| try testing.expect(compiler.check_source(testing.allocator, source).diagnostic() != null);
}

test "P44-02: count and points conditions compile and read the fact table" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const compiler = @import("../compiler.zig");
    const source =
        \\entity Hero
        \\relation Clue(clue, points)
        \\relation SawEnough(who)
        \\relation WeighedEnough(who)
        \\relation Wrong(who)
        \\routine Audit(Hero):
        \\  if 2 of Clue(_):
        \\    remember SawEnough(Hero)
        \\  if 6 points of Clue(_):
        \\    remember WeighedEnough(Hero)
        \\  if 1 of Clue(Missing):
        \\    remember Wrong(Hero)
    ;

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null, source);
    defer compiled.deinit();

    const clue = world.lookup_relation("Clue").?;
    try world.remember(try world.intern_entity("Diary"), clue, 3, 0);
    try world.remember(try world.intern_entity("Ledger"), clue, 4, 0);

    const hero = world.lookup_entity("Hero").?;
    var vm = vm_mod.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    _ = try vm.spawn_routine(hero, compiled.routine_entries.get("Audit").?);
    _ = try vm.step_tick();

    try testing.expect(world.has_fact(hero, world.lookup_relation("SawEnough").?, null));
    try testing.expect(world.has_fact(hero, world.lookup_relation("WeighedEnough").?, null));
    try testing.expect(!world.has_fact(hero, world.lookup_relation("Wrong").?, null));

    const bad = [_][]const u8{
        "entity Hero\nrelation Clue(clue, points)\nroutine A(Hero):\n  if 2 Clue(_):\n    wait 1 ticks\n",
        "entity Hero\nrelation Clue(clue, points)\nroutine A(Hero):\n  if 2 of Clue():\n    wait 1 ticks\n",
        "entity Hero\nrelation Clue(clue, points)\nroutine A(Hero):\n  if 2 points Clue(_):\n    wait 1 ticks\n",
        "entity Hero\nrelation Clue(clue, points)\nroutine A(Hero):\n  if 2 of Clue(Hero, _, Extra):\n    wait 1 ticks\n",
    };
    for (bad) |text| try testing.expect(compiler.check_source(testing.allocator, text).diagnostic() != null);
}

test "P44-04: a spellbook compiles into tiered words and a resolvable spell" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\entity Maren
        \\spellbook Grimoire:
        \\  power Spark, Forge
        \\  element Ember, Water
        \\  form Bolt, Ward
        \\  spell Kindle: Forge, Ember, Bolt
        \\  spell Quench: Spark, Water, Ward
    );
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.spellbooks.items.len);
    const book = &compiled.spellbooks.items[0].book;
    try testing.expectEqualStrings("Grimoire", world.get_entity_name(book.entity).?);
    try testing.expectEqual(@as(usize, 6), book.words.len);
    try testing.expectEqual(spell_mod.Kind.element, book.words[2].kind);
    try testing.expectEqual(@as(u16, 1), book.words[2].tier);
    try testing.expectEqual(@as(u16, 2), book.words[3].tier);
    const forge = world.lookup_entity("Forge").?;
    const ember = world.lookup_entity("Ember").?;
    const bolt = world.lookup_entity("Bolt").?;
    const kindle = world.lookup_entity("Kindle").?;
    try testing.expectEqual(kindle, spell_mod.resolve(book, forge, ember, bolt).?.entity);
    try testing.expectEqual(kindle, spell_mod.named(book, kindle).?.entity);
    // Words are entities, so a handler or a typed line can name one.
    try testing.expectEqualStrings("Ward", world.get_entity_name(book.words[5].entity).?);
}

test "P44-05: a decision compiles into trigger lines and scored options" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\entity Maren
        \\relation Turn(who)
        \\relation SuitLed(suit)
        \\relation High(card)
        \\decision LeadAtTable:
        \\  actor Maren
        \\  fires CardPlayed
        \\  requires Turn(Maren)
        \\  option SaltTwo:
        \\    picks 4 when SuitLed(Salt)
        \\    drops 2 when High(SaltThree)
        \\  option ReedOne:
        \\    picks 1 when SuitLed(Reed)
    );
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.decisions.items.len);
    const decision = &compiled.decisions.items[0].decision;
    try testing.expectEqualStrings("LeadAtTable", world.get_entity_name(decision.entity).?);
    try testing.expectEqualStrings("Maren", world.get_entity_name(decision.actor).?);
    try testing.expectEqualStrings("CardPlayed", world.get_entity_name(decision.cue).?);
    try testing.expectEqual(@as(usize, 1), decision.clauses.len);
    try testing.expectEqualStrings("Turn", decision.clauses[0].relation);
    try testing.expectEqual(world.lookup_entity("Maren").?, decision.clauses[0].subject.?);
    try testing.expect(decision.clauses[0].object == null);
    try testing.expectEqual(@as(usize, 2), decision.options.len);
    try testing.expectEqual(@as(usize, 2), decision.options[0].picks.len);
    try testing.expectEqual(@as(i32, 4), decision.options[0].picks[0].points);
    try testing.expectEqualStrings("SuitLed", decision.options[0].picks[0].clause.relation);
    try testing.expectEqual(@as(i32, -2), decision.options[0].picks[1].points);
    try testing.expectEqualStrings("High", decision.options[0].picks[1].clause.relation);
    try testing.expectEqual(world.lookup_entity("SaltThree").?, decision.options[0].picks[1].clause.subject.?);
    try testing.expectEqualStrings("ReedOne", world.get_entity_name(decision.options[1].entity).?);
}

test "P45-01: an author-declared axis compiles into a bounded property with signed values" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    // Neither axis name is known to the engine: the script alone declares them.
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\entity Oswin, Ines
        \\axis Justice between Cruelty and Leniency
        \\axis Candour between Bluntness and "Flattering Lies"
        \\remember Justice(Oswin, 8)
        \\remember Candour(Oswin, -3)
        \\remember Justice(Ines, -10)
        \\routine Soften(Oswin):
        \\  remember Justice(Oswin, 2)
        \\  if Candour(Oswin, -3):
        \\    remember Candour(Oswin, 10)
    );
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 2), compiled.axes.items.len);
    const justice = compiled.axes.items[0];
    const candour = compiled.axes.items[1];
    try testing.expectEqualStrings("Justice", world.get_relation_meta(justice.relation).?.name);
    try testing.expectEqual(world_mod.RelationType.property, world.get_relation_meta(candour.relation).?.rel_type);
    try testing.expectEqualStrings("Bluntness", world.get_entity_name(candour.poles[0]).?);
    try testing.expectEqualStrings("Flattering Lies", world.get_entity_name(candour.poles[1]).?);

    var vm = vm_mod.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    const oswin = world.lookup_entity("Oswin").?;
    const ines = world.lookup_entity("Ines").?;
    _ = try vm.spawn_routine(oswin, compiled.initial_entry.?);
    _ = try vm.step_tick();
    try testing.expectEqual(@as(i32, 8), value_mod.value_of(&world, oswin, justice).?);
    try testing.expectEqual(@as(i32, -3), value_mod.value_of(&world, oswin, candour).?);
    try testing.expectEqual(@as(i32, -10), value_mod.value_of(&world, ines, justice).?);

    // A later write overwrites the one row (D-007), and a negative literal in a condition
    // matches the stored value.
    _ = try vm.spawn_routine(oswin, compiled.routine_entries.get("Soften").?);
    _ = try vm.step_tick();
    try testing.expectEqual(@as(i32, 2), value_mod.value_of(&world, oswin, justice).?);
    try testing.expectEqual(@as(i32, 10), value_mod.value_of(&world, oswin, candour).?);
    var rows: usize = 0;
    const slice = world.facts.slice();
    for (slice.items(.subject)[0..world.facts.len], slice.items(.relation)[0..world.facts.len]) |subject, relation| {
        if (subject == oswin and (relation == justice.relation or relation == candour.relation)) rows += 1;
    }
    try testing.expectEqual(@as(usize, 2), rows);
}

test "P45-01: axis declarations and values are range-checked at compile time" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    const cases = [_]struct { source: []const u8, message: []const u8, line: u32, column: u32 }{
        .{ .source = "axis Mercy between Vengeance and Leniency\nremember Mercy(Oswin, 11)", .message = "a value on an axis needs a character and a whole number from -10 to +10", .line = 2, .column = 23 },
        .{ .source = "axis Mercy between Vengeance and Leniency\nremember Mercy(Oswin, -11)", .message = "a value on an axis needs a character and a whole number from -10 to +10", .line = 2, .column = 23 },
        .{ .source = "axis Mercy between Vengeance and Leniency\nremember Mercy(Oswin, Kindly)", .message = "a value on an axis needs a character and a whole number from -10 to +10", .line = 2, .column = 23 },
        .{ .source = "axis Mercy between Vengeance and Leniency\nremember Mercy(Oswin)", .message = "a value on an axis needs a character and a whole number from -10 to +10", .line = 2, .column = 10 },
        .{ .source = "axis Mercy between Vengeance and Leniency\nroutine Judge(Oswin):\n  if Mercy(Oswin, 12):\n    wait 1 ticks", .message = "a value on an axis needs a character and a whole number from -10 to +10", .line = 3, .column = 19 },
        .{ .source = "axis Mercy between Vengeance and Leniency\nwhen Mercy(Oswin, 40):\n  remember Pardoned(Oswin)", .message = "a value on an axis needs a character and a whole number from -10 to +10", .line = 2, .column = 19 },
        .{ .source = "property Mood(who, value)\nremember Mood(Oswin, -3)", .message = "only a value on a declared axis may be negative", .line = 2, .column = 22 },
        .{ .source = "property Mercy(who, value)\naxis Mercy between Vengeance and Leniency", .message = "invalid axis; its name is already a relation, or the script declares too many axes", .line = 2, .column = 6 },
        .{ .source = "axis Mercy between Vengeance and Leniency\naxis Mercy between Spite and Softness", .message = "axis 'Mercy' is declared twice", .line = 2, .column = 38 },
        .{ .source = "axis Mercy from Vengeance to Leniency", .message = "axis 'Mercy' expects 'between <Pole> and <Pole>'", .line = 1, .column = 17 },
        .{ .source = "axis Mercy between Vengeance or Leniency", .message = "axis 'Mercy' expects 'and' between its two poles", .line = 1, .column = 30 },
        .{ .source = "axis Mercy between Vengeance and Vengeance", .message = "axis 'Mercy' names 'Vengeance' as both poles", .line = 1, .column = 43 },
    };
    for (cases) |case| {
        const result = compiler.check_source(testing.allocator, case.source);
        errdefer std.debug.print("diagnostic source:\n{s}\ngot: {s} at {d}:{d}\n", .{ case.source, result.message(), result.line, result.column });
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings(case.message, result.message());
        try testing.expectEqual(case.line, result.line);
        try testing.expectEqual(case.column, result.column);
    }
    // The ends of the range are values an axis holds.
    try testing.expect(compiler.check_source(testing.allocator, "axis Mercy between Vengeance and Leniency\nremember Mercy(A, 10)\nremember Mercy(B, -10)\nremember Mercy(C, 0)").is_valid);
}

test "P45-02: red lines compile per character and are checked against its decisions" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const decision =
        \\decision Judge:
        \\  actor Oswin
        \\  fires Judged
        \\  requires Accused(Thief)
        \\  option Execute:
        \\    picks 9 when Stole(Thief)
        \\  option BurnGranary:
        \\    picks 4 when Stole(Thief)
        \\  option Pardon:
        \\    picks 2 when Hungry(Thief)
        \\
    ;
    var compiled = try compiler.compile_source(testing.allocator, &world, null, decision ++
        \\red lines Oswin: Execute, BurnGranary
    );
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.red_lines.items.len);
    const set = compiled.red_lines.items[0].red_lines;
    try testing.expectEqualStrings("Oswin", world.get_entity_name(set.actor).?);
    try testing.expectEqual(@as(usize, 2), set.options.len);
    try testing.expectEqualStrings("BurnGranary", world.get_entity_name(set.options[1]).?);

    const cases = [_]struct { source: []const u8, message: []const u8, line: u32 }{
        .{ .source = decision ++ "red lines Oswin: Exectue", .message = "invalid red lines; each must name an option a decision offers that character, and a decision needs one option left", .line = 11 },
        .{ .source = decision ++ "red lines Ines: Execute", .message = "invalid red lines; each must name an option a decision offers that character, and a decision needs one option left", .line = 11 },
        .{ .source = decision ++ "red lines Oswin: Execute, BurnGranary, Pardon", .message = "invalid red lines; each must name an option a decision offers that character, and a decision needs one option left", .line = 11 },
        .{ .source = decision ++ "red lines Oswin: Execute\nred lines Oswin: Pardon", .message = "red lines for 'Oswin' are declared twice", .line = 12 },
        .{ .source = decision ++ "red lines Oswin:", .message = "red lines for 'Oswin' name no option", .line = 11 },
        .{ .source = decision ++ "red lines Oswin Execute", .message = "red lines for 'Oswin Execute' expect ':' and the options it never takes", .line = 11 },
    };
    for (cases) |case| {
        const result = compiler.check_source(testing.allocator, case.source);
        errdefer std.debug.print("diagnostic source:\n{s}\ngot: {s} at {d}:{d}\n", .{ case.source, result.message(), result.line, result.column });
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings(case.message, result.message());
        try testing.expectEqual(case.line, result.line);
    }
}

test "P45-03: a dilemma compiles its axes, leans, and five tiers, and refuses a gap" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const axes =
        \\axis Justice between Cruelty and Leniency
        \\axis Mercy between Vengeance and Indulgence
        \\
    ;
    const head =
        \\dilemma StolenBread:
        \\  actor Oswin
        \\  fires Judged
        \\  requires Accused(Thief)
        \\  weighs Justice against Mercy
        \\  leans 3 toward Justice when Criminal(Thief)
        \\  leans 4 toward Mercy unless Fed(Town)
        \\
    ;
    const tiers =
        \\  strong Justice: "The law is the law." -> Hang
        \\  moderate Justice: "A night in the cells." -> Jail
        \\  neutral: "Show me why." -> Wait
        \\  moderate Mercy: "Pay for the loaf." -> Fine
        \\  strong Mercy: "Let him go." -> Pardon
        \\
    ;
    var compiled = try compiler.compile_source(testing.allocator, &world, null, axes ++ head ++ tiers);
    defer compiled.deinit();
    try testing.expectEqual(@as(usize, 1), compiled.dilemmas.items.len);
    const d = compiled.dilemmas.items[0].dilemma;
    try testing.expectEqualStrings("Justice", world.get_relation_meta(d.axis).?.name);
    try testing.expectEqualStrings("Mercy", world.get_relation_meta(d.counter).?.name);
    try testing.expectEqual(@as(i32, 3), d.leans[0].points);
    try testing.expectEqual(@as(i32, -4), d.leans[1].points);
    try testing.expect(d.leans[1].clause.negated);
    try testing.expectEqualStrings("Hang", world.get_entity_name(d.responses[0].action).?);
    try testing.expectEqualStrings("Show me why.", world.get_entity_name(d.responses[2].line).?);
    try testing.expectEqualStrings("Pardon", world.get_entity_name(d.responses[4].action).?);

    // Tier lines may come in any order; the compiler orders them by axis.
    var reordered = try compiler.compile_source(testing.allocator, &world, null, axes ++ head ++
        \\  strong Mercy: "Let him go." -> Pardon
        \\  neutral: "Show me why." -> Wait
        \\  moderate Mercy: "Pay for the loaf." -> Fine
        \\  moderate Justice: "A night in the cells." -> Jail
        \\  strong Justice: "The law is the law." -> Hang
    );
    defer reordered.deinit();
    try testing.expectEqualStrings("Fine", world.get_entity_name(reordered.dilemmas.items[0].dilemma.responses[3].action).?);

    const no_strong_mercy =
        \\  strong Justice: "The law is the law." -> Hang
        \\  moderate Justice: "A night in the cells." -> Jail
        \\  neutral: "Show me why." -> Wait
        \\  moderate Mercy: "Pay for the loaf." -> Fine
    ;
    const cases = [_]struct { source: []const u8, message: []const u8, line: u32 }{
        .{ .source = axes ++ head ++ no_strong_mercy, .message = "dilemma 'StolenBread' has no line for the strong Mercy tier", .line = 3 },
        .{ .source = axes ++ head ++ tiers ++ "  neutral: \"Again.\" -> Wait\n", .message = "dilemma 'StolenBread' gives the neutral tier twice", .line = 15 },
        .{ .source = axes ++ head ++ "  leans 3 toward Greed when Rich(Thief)\n" ++ tiers, .message = "dilemma 'StolenBread' leans toward 'Greed', which it does not weigh", .line = 10 },
        .{ .source = axes ++ head ++ "  leans 11 toward Justice when Rich(Thief)\n" ++ tiers, .message = "dilemma 'StolenBread' leans more than 10 or less than 1; use 1 to 10", .line = 10 },
        .{ .source = "axis Justice between Cruelty and Leniency\n" ++ head ++ tiers, .message = "a dilemma weighs an axis that no 'axis' line declares", .line = 6 },
        .{ .source = axes ++ "red lines Oswin: Hang\ndecision Gallows:\n  actor Oswin\n  fires Hanged\n  requires Accused(Thief)\n  option Hang:\n    picks 1 when Accused(Thief)\n  option Spare:\n    picks 1 when Accused(Thief)\n" ++ head ++ tiers, .message = "this action is on the actor's red lines, so no tier may take it", .line = 19 },
    };
    for (cases) |case| {
        const result = compiler.check_source(testing.allocator, case.source);
        errdefer std.debug.print("diagnostic source:\n{s}\ngot: {s} at {d}:{d}\n", .{ case.source, result.message(), result.line, result.column });
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings(case.message, result.message());
        try testing.expectEqual(case.line, result.line);
    }
}

test "P45-04: drift lines compile to signed points on a declared axis" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const head =
        \\axis Justice between Cruelty and Leniency
        \\axis Mercy between Vengeance and Indulgence
        \\axis Loyalty between Servility and Treachery
        \\dilemma StolenBread:
        \\  actor Oswin
        \\  fires Judged
        \\  requires Accused(Thief)
        \\  weighs Justice against Mercy
        \\
    ;
    const tiers =
        \\  strong Justice: "a" -> Hang
        \\  moderate Justice: "b" -> Jail
        \\  neutral: "c" -> Wait
        \\  moderate Mercy: "d" -> Fine
        \\  strong Mercy: "e" -> Pardon
        \\
    ;
    var compiled = try compiler.compile_source(testing.allocator, &world, null, head ++
        "  drifts 3 toward Mercy when Repaid(Thief)\n  drifts 4 away from Loyalty unless Paid(Guard)\n" ++ tiers);
    defer compiled.deinit();
    const drifts = compiled.dilemmas.items[0].dilemma.drifts;
    try testing.expectEqual(@as(usize, 2), drifts.len);
    try testing.expectEqual(@as(i32, 3), drifts[0].points);
    try testing.expectEqual(@as(i32, -4), drifts[1].points);
    try testing.expect(drifts[1].clause.negated);
    try testing.expectEqualStrings("Loyalty", world.get_relation_meta(drifts[1].axis).?.name);
    try testing.expectEqualStrings("#Mercy drift", world.get_relation_meta(drifts[0].accumulator).?.name);
    try testing.expectEqualStrings("#Loyalty drift steps", world.get_relation_meta(drifts[1].spent).?.name);

    const cases = [_]struct { source: []const u8, message: []const u8, line: u32 }{
        .{ .source = head ++ "  drifts 3 toward Greed when Rich(Thief)\n" ++ tiers, .message = "a dilemma weighs an axis that no 'axis' line declares", .line = 9 },
        .{ .source = head ++ "  drifts 11 toward Mercy when Rich(Thief)\n" ++ tiers, .message = "dilemma 'StolenBread' drifts more than 10 or less than 1; use 1 to 10", .line = 9 },
        .{ .source = head ++ "  drifts 3 towards Mercy when Rich(Thief)\n" ++ tiers, .message = "dilemma 'StolenBread' expects 'drifts <N> toward <Axis>' or 'drifts <N> away from <Axis>'", .line = 9 },
        .{ .source = head ++ "  drifts 3 toward Mercy if Rich(Thief)\n" ++ tiers, .message = "dilemma 'StolenBread' needs 'when' or 'unless' after the axis 'Mercy'", .line = 9 },
    };
    for (cases) |case| {
        const result = compiler.check_source(testing.allocator, case.source);
        errdefer std.debug.print("diagnostic source:\n{s}\ngot: {s} at {d}:{d}\n", .{ case.source, result.message(), result.line, result.column });
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings(case.message, result.message());
        try testing.expectEqual(case.line, result.line);
    }
}

test "P45-05: appeal lines compile toward a weighed axis and refuse any other" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const head =
        \\axis Justice between Cruelty and Leniency
        \\axis Mercy between Vengeance and Indulgence
        \\axis Loyalty between Servility and Treachery
        \\dilemma StolenBread:
        \\  actor Oswin
        \\  fires Judged
        \\  requires Accused(Thief)
        \\  weighs Justice against Mercy
        \\
    ;
    const tiers =
        \\  strong Justice: "a" -> Hang
        \\  moderate Justice: "b" -> Jail
        \\  neutral: "c" -> Wait
        \\  moderate Mercy: "d" -> Fine
        \\  strong Mercy: "e" -> Pardon
        \\
    ;
    var compiled = try compiler.compile_source(testing.allocator, &world, null, head ++ "  appeals 4 to Mercy\n  appeals 2 to Justice\n" ++ tiers);
    defer compiled.deinit();
    const appeals = compiled.dilemmas.items[0].dilemma.appeals;
    try testing.expectEqual(@as(usize, 2), appeals.len);
    try testing.expectEqual(@as(i32, -4), appeals[0].points);
    try testing.expectEqual(@as(i32, 2), appeals[1].points);
    try testing.expectEqualStrings("Mercy", world.get_entity_name(appeals[0].entity).?);
    // The values a player can learn about the actor exist as entities from the start.
    try testing.expect(world.lookup_entity("Mercy of Oswin") != null);
    try testing.expect(world.lookup_entity("Justice of Oswin") != null);

    const cases = [_]struct { source: []const u8, message: []const u8, line: u32 }{
        .{ .source = head ++ "  appeals 4 to Loyalty\n" ++ tiers, .message = "dilemma 'StolenBread' appeals toward 'Loyalty', which it does not weigh; add 'toward <Axis>' naming a weighed axis", .line = 9 },
        .{ .source = head ++ "  appeals 4 to Mercy\n  appeals 3 to Mercy\n" ++ tiers, .message = "dilemma 'StolenBread' declares an appeal to 'Mercy' twice", .line = 10 },
        .{ .source = head ++ "  appeals 11 to Mercy\n" ++ tiers, .message = "dilemma 'StolenBread' appeals more than 10 or less than 1; use 1 to 10", .line = 9 },
        .{ .source = head ++ "  appeals 4 toward Mercy\n" ++ tiers, .message = "dilemma 'StolenBread' expects 'appeals <N> to <Axis>'", .line = 9 },
    };
    for (cases) |case| {
        const result = compiler.check_source(testing.allocator, case.source);
        errdefer std.debug.print("diagnostic source:\n{s}\ngot: {s} at {d}:{d}\n", .{ case.source, result.message(), result.line, result.column });
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings(case.message, result.message());
        try testing.expectEqual(case.line, result.line);
    }
}

test "D-150: an appeal to an unweighed value names the weighed axis it moves" {
    const testing = std.testing;
    const compiler = @import("../compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const head =
        \\axis Justice between Cruelty and Leniency
        \\axis Mercy between Vengeance and Indulgence
        \\axis Loyalty between Servility and Treachery
        \\dilemma StolenBread:
        \\  actor Oswin
        \\  fires Judged
        \\  requires Accused(Thief)
        \\  weighs Justice against Mercy
        \\  appeals 4 to Mercy
        \\
    ;
    const tiers =
        \\  strong Justice: "a" -> Flog
        \\  moderate Justice: "b" -> Jail
        \\  neutral: "c" -> Wait
        \\  moderate Mercy: "d" -> Pardon
        \\  strong Mercy: "e" -> OpenStore
        \\
    ;
    var compiled = try compiler.compile_source(testing.allocator, &world, null, head ++ "  appeals 8 to Loyalty toward Mercy\n" ++ tiers);
    defer compiled.deinit();
    const appeals = compiled.dilemmas.items[0].dilemma.appeals;
    try testing.expectEqual(@as(usize, 2), appeals.len);
    try testing.expectEqualStrings("Loyalty", world.get_relation_meta(appeals[1].axis).?.name);
    try testing.expectEqual(@as(i32, -8), appeals[1].points);
    try testing.expect(world.lookup_entity("Loyalty of Oswin") != null);

    const twice = compiler.check_source(testing.allocator, head ++ "  appeals 8 to Loyalty toward Mercy\n  appeals 2 to Loyalty toward Justice\n" ++ tiers);
    try testing.expectEqualStrings("dilemma 'StolenBread' declares an appeal to 'Loyalty' twice", twice.message());
    const undeclared = compiler.check_source(testing.allocator, head ++ "  appeals 8 to Greed toward Mercy\n" ++ tiers);
    try testing.expectEqualStrings("a dilemma weighs an axis that no 'axis' line declares", undeclared.message());
}
