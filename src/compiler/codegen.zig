const std = @import("std");
const parser_mod = @import("parser.zig");
const lexer_mod = @import("lexer.zig");
const bytecode_mod = @import("../bytecode.zig");
const world_mod = @import("../world.zig");
const spatial_mod = @import("../spatial.zig");

pub const AST = parser_mod.AST;
pub const Stmt = parser_mod.Stmt;
pub const Expr = parser_mod.Expr;
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
};

pub const CompiledProgram = struct {
    chunk: BytecodeChunk,
    routine_entries: std.StringHashMap(usize),
    routine_entities: std.StringHashMap([]const u8),
    when_rule_entries: std.ArrayList(usize),
    cue_handler_entries: std.StringHashMap(usize),
    allocated_cue_keys: std.ArrayList([]const u8),
    reactive_rules: std.ArrayList(CompiledWhenRule),
    initial_entry: ?usize = null,
    /// Draft note table (P22-01, D-029). Program data, not world state: never saved in `.sav`.
    drafts: std.ArrayList(CompiledDraft),
    /// Script-declared reusable subsystem configuration (P32-22, P32-24).
    societies: std.ArrayList(society_mod.Declaration),
    duels: std.ArrayList(duel_mod.Declaration),
    degradations: std.ArrayList(container_mod.Declaration),
    /// Grid overlays with their initial cell layouts (P25-01, D-054). Geometry is also
    /// registered in the SpatialSystem the program was compiled or loaded into.
    grids: std.ArrayList(grid_mod.Declaration),
    /// Agendas in declaration order, which breaks contention ties (P33-01, D-056).
    agendas: std.ArrayList(agency_mod.Declaration),
    /// Typed-command frames and noun aliases, in declaration order (P26-01, D-057).
    commands: std.ArrayList(command_mod.CommandDecl),
    aliases: std.ArrayList(command_mod.AliasDecl),
    /// Script music in declaration order, as validated MML text (P28-03, D-062).
    scores: std.ArrayList(mml.ScoreDecl),

    pub fn deinit(self: *CompiledProgram) void {
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

    /// Finds entry PC for a cue handler matching cue name and arguments (P11-01, P11-02, D-013).
    /// Supports ternary item-combining with commutative matching (ItemA on ItemB == ItemB on ItemA).
    /// Finds the handler for a fired cue (D-009, D-013, D-037). Tried in order, most specific
    /// first: the exact signature (for two targets, also with the targets swapped), signatures
    /// whose parameters were declared as variables (stored as `*`), then the actor-only
    /// handler `on cue X(Actor):`. A cue no declared signature covers has no handler: there is
    /// no fallback to a handler written for a different actor or target.
    pub fn find_cue_handler(
        self: *const CompiledProgram,
        cue_name: []const u8,
        actor: ?[]const u8,
        target_a: ?[]const u8,
        target_b: ?[]const u8,
    ) ?usize {
        const who = actor orelse return null;

        if (target_a != null and target_b != null) {
            const a = target_a.?;
            const b = target_b.?;
            const forms = [_][3][]const u8{
                .{ who, a, b },                       .{ who, b, a },
                .{ who, a, CUE_WILDCARD },            .{ who, CUE_WILDCARD, b },
                .{ who, b, CUE_WILDCARD },            .{ who, CUE_WILDCARD, a },
                .{ who, CUE_WILDCARD, CUE_WILDCARD }, .{ CUE_WILDCARD, a, b },
                .{ CUE_WILDCARD, b, a },              .{ CUE_WILDCARD, CUE_WILDCARD, CUE_WILDCARD },
            };
            for (forms) |f| {
                if (self.lookup_cue(cue_name, &f)) |pc| return pc;
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
                if (self.lookup_cue(cue_name, &f)) |pc| return pc;
            }
        }

        if (self.lookup_cue(cue_name, &.{who})) |pc| return pc;
        return self.lookup_cue(cue_name, &.{CUE_WILDCARD});
    }

    fn lookup_cue(self: *const CompiledProgram, cue_name: []const u8, parts: []const []const u8) ?usize {
        var buf: [192]u8 = undefined;
        var stream = std.io.fixedBufferStream(&buf);
        const w = stream.writer();
        w.writeAll(cue_name) catch return null;
        for (parts) |part| {
            w.writeByte(':') catch return null;
            w.writeAll(part) catch return null;
        }
        return self.cue_handler_entries.get(stream.getWritten());
    }
};

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

pub const Codegen = struct {
    allocator: std.mem.Allocator,
    world: *World,
    spatial: ?*SpatialSystem,
    chunk: BytecodeChunk,
    routine_entries: std.StringHashMap(usize),
    routine_entities: std.StringHashMap([]const u8),
    when_rule_entries: std.ArrayList(usize),
    cue_handler_entries: std.StringHashMap(usize),
    allocated_cue_keys: std.ArrayList([]const u8),
    reactive_rules: std.ArrayList(CompiledWhenRule),
    societies: std.ArrayList(society_mod.Declaration),
    duels: std.ArrayList(duel_mod.Declaration),
    degradations: std.ArrayList(container_mod.Declaration),
    grids: std.ArrayList(grid_mod.Declaration),
    agendas: std.ArrayList(agency_mod.Declaration),
    commands: std.ArrayList(command_mod.CommandDecl),
    aliases: std.ArrayList(command_mod.AliasDecl),
    scores: std.ArrayList(mml.ScoreDecl),

    pub fn init(allocator: std.mem.Allocator, world: *World, spatial: ?*SpatialSystem) Codegen {
        return Codegen{
            .allocator = allocator,
            .world = world,
            .spatial = spatial,
            .chunk = BytecodeChunk.init(allocator),
            .routine_entries = std.StringHashMap(usize).init(allocator),
            .routine_entities = std.StringHashMap([]const u8).init(allocator),
            .when_rule_entries = std.ArrayList(usize).init(allocator),
            .cue_handler_entries = std.StringHashMap(usize).init(allocator),
            .allocated_cue_keys = std.ArrayList([]const u8).init(allocator),
            .reactive_rules = std.ArrayList(CompiledWhenRule).init(allocator),
            .societies = std.ArrayList(society_mod.Declaration).init(allocator),
            .duels = std.ArrayList(duel_mod.Declaration).init(allocator),
            .degradations = std.ArrayList(container_mod.Declaration).init(allocator),
            .grids = std.ArrayList(grid_mod.Declaration).init(allocator),
            .agendas = std.ArrayList(agency_mod.Declaration).init(allocator),
            .commands = std.ArrayList(command_mod.CommandDecl).init(allocator),
            .aliases = std.ArrayList(command_mod.AliasDecl).init(allocator),
            .scores = std.ArrayList(mml.ScoreDecl).init(allocator),
        };
    }

    /// Compiles an entire AST into a CompiledProgram (P4-03).
    pub fn compile(mut_self: *Codegen, ast: *const AST) !CompiledProgram {
        // 1. Intern declared entities, scenes, cast, props, marks
        for (ast.entities.items) |name| {
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.scenes.items) |name| {
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.cast.items) |name| {
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.props.items) |name| {
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.marks.items) |name| {
            _ = try mut_self.world.intern_entity(name);
        }
        for (ast.paths.items) |path| {
            _ = try mut_self.world.intern_entity(path.name);
        }

        // Register stage marks and props in SpatialSystem if present
        if (mut_self.spatial) |sp| {
            if (ast.scene_defs.items.len > 0) {
                for (ast.scene_defs.items) |*sc_def| {
                    const sent = mut_self.world.lookup_entity(sc_def.name) orelse try mut_self.world.intern_entity(sc_def.name);
                    var prev_wp: ?u16 = null;
                    for (sc_def.marks.items, 0..) |mname, idx| {
                        const wx: i32 = @as(i32, @intCast(idx)) * 20;
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

                    for (sc_def.props.items, 0..) |pname, idx| {
                        const pent = mut_self.world.lookup_entity(pname) orelse try mut_self.world.intern_entity(pname);
                        const px: i32 = 10 + @as(i32, @intCast(idx)) * 20;
                        sp.add_hotspot(pent, sent, .{ .x = px, .y = -6 }, 10, pname, pname) catch {};
                    }
                }
            } else {
                const sent = if (ast.scenes.items.len > 0)
                    mut_self.world.lookup_entity(ast.scenes.items[0]) orelse try mut_self.world.intern_entity(ast.scenes.items[0])
                else
                    try mut_self.world.intern_entity("DefaultScene");

                var prev_wp: ?u16 = null;
                for (ast.marks.items, 0..) |mname, idx| {
                    const wx: i32 = @as(i32, @intCast(idx)) * 20;
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
                    const px: i32 = 10 + @as(i32, @intCast(idx)) * 20;
                    sp.add_hotspot(pent, sent, .{ .x = px, .y = -6 }, 10, pname, pname) catch {};
                }
            }
        }

        for (ast.societies.items) |decl| try mut_self.societies.append(try mut_self.compile_society(decl));
        for (ast.duels.items) |decl| try mut_self.duels.append(try mut_self.compile_duel(decl));
        for (ast.degradations.items) |decl| try mut_self.degradations.append(try mut_self.compile_degradation(decl));
        for (ast.grids.items) |decl| try mut_self.grids.append(try mut_self.compile_grid(decl));
        for (ast.agendas.items) |decl| try mut_self.agendas.append(try mut_self.compile_agenda(decl));
        try agency_mod.validate_all(mut_self.agendas.items);
        for (ast.commands.items) |decl| try mut_self.commands.append(try mut_self.compile_command(decl));
        for (ast.aliases.items) |decl| try mut_self.aliases.append(try mut_self.compile_alias(decl));
        for (ast.scores.items) |decl| {
            var owned = try mml.ScoreDecl.dupe(mut_self.allocator, decl);
            mut_self.scores.append(owned) catch |err| {
                owned.deinit_owned(mut_self.allocator);
                return err;
            };
        }

        // 2. Intern declared relations
        for (ast.relations.items) |rel| {
            _ = try mut_self.world.intern_relation(
                rel.name,
                if (rel.is_property) .property else .set,
            );
        }
        if (ast.paths.items.len > 0) {
            _ = try mut_self.world.intern_relation("PathActive", .property);
        }
        // Music relations (P28-03, D-062): interned before any statement so `PlayingScore` is a
        // property (one score at a time) even where a rule mentions it first.
        if (ast.scores.items.len > 0) {
            _ = try mut_self.world.intern_relation(mml.PLAYING_RELATION, .property);
            _ = try mut_self.world.intern_relation(mml.SCENE_RELATION, .set);
            _ = try mut_self.world.intern_entity(mml.MUSIC_ENTITY);
        }

        // 2b. Build the draft note table; a declared reverse becomes its own entry (D-029)
        var drafts = std.ArrayList(CompiledDraft).init(mut_self.allocator);
        errdefer drafts.deinit();
        for (ast.drafts.items) |d| {
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
            initial_entry = mut_self.chunk.count();
            // Scene defaults are World facts, seeded before the script's own statements, so the
            // display can pick a scene's score from World alone and saves carry the binding.
            for (ast.scores.items) |decl| {
                const score_entity = try mut_self.world.intern_entity(decl.name);
                const scene_rel = try mut_self.world.intern_relation(mml.SCENE_RELATION, .set);
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
            const entry_pc = mut_self.chunk.count();
            try mut_self.routine_entries.put(routine.name, entry_pc);
            try mut_self.routine_entities.put(routine.name, routine.entity);

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
                const path_entity = try mut_self.world.intern_entity(path.name);
                const init_key = try std.fmt.allocPrint(mut_self.allocator, "{s}{s}", .{ PATH_ROUTINE_PREFIX, path.name });
                try mut_self.allocated_cue_keys.append(init_key);
                try mut_self.routine_entries.put(init_key, mut_self.chunk.count());
                try mut_self.routine_entities.put(init_key, path.name);

                for (path.facts) |stmt| {
                    try mut_self.compile_stmt(stmt);
                }
                _ = try mut_self.chunk.emit_op(.halt);

                for (path.routines) |routine| {
                    if (mut_self.routine_entries.contains(routine.name)) return error.DuplicateRoutineName;
                    try mut_self.routine_entries.put(routine.name, mut_self.chunk.count());
                    try mut_self.routine_entities.put(routine.name, routine.entity);

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
            var var_map = std.StringHashMap(u8).init(mut_self.allocator);
            defer var_map.deinit();
            var next_var: u8 = 0;

            var clauses = std.ArrayList(world_mod.PatternClause).init(mut_self.allocator);
            for (rule.trigger_patterns) |pat| {
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
                    try mut_self.resolve_pattern_term(pat.args[1], &var_map, &next_var)
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

            if (rule.body.len > 0 and rule.body[0] == .interrupt_with) {
                const iw = rule.body[0].interrupt_with;
                target_entity = try mut_self.resolve_entity(iw.entity);
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
            });
        }

        // 6. Compile cue handlers (P11-01, P11-02, D-013)
        for (ast.cue_handlers.items) |cue| {
            const entry_pc = mut_self.chunk.count();

            // One key per declared signature. Parameters declared as variables are stored as
            // `*`; there is no key for the bare cue name, so an unmatched cue finds nothing
            // (D-037).
            if (cue.params.len == 1) {
                const sig = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}", .{ cue.cue_name, cue_param_key(cue.params[0]) });
                try mut_self.allocated_cue_keys.append(sig);
                try mut_self.cue_handler_entries.put(sig, entry_pc);
            } else if (cue.params.len == 2) {
                const sig = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}:{s}", .{ cue.cue_name, cue_param_key(cue.params[0]), cue_param_key(cue.params[1]) });
                try mut_self.allocated_cue_keys.append(sig);
                try mut_self.cue_handler_entries.put(sig, entry_pc);
            } else if (cue.params.len >= 3) {
                // Uses:Actor:ItemA:ItemB; lookup also tries the two items swapped (D-013).
                const sig = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}:{s}:{s}", .{ cue.cue_name, cue_param_key(cue.params[0]), cue_param_key(cue.params[1]), cue_param_key(cue.params[2]) });
                try mut_self.allocated_cue_keys.append(sig);
                try mut_self.cue_handler_entries.put(sig, entry_pc);
            }

            for (cue.body) |stmt| {
                try mut_self.compile_stmt(stmt);
            }
            _ = try mut_self.chunk.emit_op(.halt);
        }

        return CompiledProgram{
            .chunk = mut_self.chunk,
            .routine_entries = mut_self.routine_entries,
            .routine_entities = mut_self.routine_entities,
            .when_rule_entries = mut_self.when_rule_entries,
            .cue_handler_entries = mut_self.cue_handler_entries,
            .allocated_cue_keys = mut_self.allocated_cue_keys,
            .reactive_rules = mut_self.reactive_rules,
            .initial_entry = initial_entry,
            .drafts = drafts,
            .societies = mut_self.societies,
            .duels = mut_self.duels,
            .degradations = mut_self.degradations,
            .grids = mut_self.grids,
            .agendas = mut_self.agendas,
            .commands = mut_self.commands,
            .aliases = mut_self.aliases,
            .scores = mut_self.scores,
        };
    }

    fn intern_program_text(self: *Codegen, text_value: []const u8) ![]const u8 {
        const entity = try self.world.intern_entity(text_value);
        return self.world.get_entity_name(entity) orelse return error.InvalidProgramText;
    }

    fn society_member_index(decl: parser_mod.SocietyDecl, name: []const u8) !usize {
        for (decl.members, 0..) |member, index| {
            if (std.mem.eql(u8, member.name, name)) return index;
        }
        return error.UnknownSocietyMember;
    }

    fn activity_from_name(name: []const u8) !society_mod.Activity {
        const fields = std.meta.fields(society_mod.Activity);
        inline for (fields) |field| if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
        return error.UnknownSocietyActivity;
    }

    fn society_waypoint(self: *Codegen, name: []const u8) !spatial_mod.WaypointId {
        const spatial = self.spatial orelse return error.SocietyNeedsSpatialSystem;
        return spatial.graph.find_waypoint(name) orelse error.UnknownSocietyPlace;
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
                        .provider = if (trade.provider) |name| try society_member_index(decl, name) else null,
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
                        .activity = try activity_from_name(stay.activity),
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
                    .provider = if (member_need.provider) |provider| try society_member_index(decl, provider) else null,
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
                .idle = try activity_from_name(source.idle),
                .routine = .{
                    .activity = if (source.routine_activity) |activity| try activity_from_name(activity) else null,
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
            .enforcer = if (decl.enforcer) |name| try society_member_index(decl, name) else null,
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
                .fallback = if (decl.fallback) |fallback| try self.intern_program_text(fallback) else null,
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
        var cells = std.ArrayList(grid_mod.InitialCell).init(self.allocator);
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
                const id = self.find_waypoint(place.mark) orelse return error.UnknownGridMark;
                const wp = sp.graph.get_waypoint(id).?;
                if (wp.room != grid.room) return error.GridMarkOutsideRoom;
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
                .initial_stage = initial_stage orelse return error.UnknownDegradationStage,
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
                const subj = try self.resolve_entity(rem.args[0]);
                const rel = try self.resolve_relation(rem.relation);
                const obj = if (rem.args.len > 1)
                    try self.resolve_entity_or_value(rem.args[1])
                else
                    0;

                try self.chunk.emit_push_entity(subj);
                try self.chunk.emit_push_relation(rel);
                try self.chunk.emit_push_const(obj);
                try self.chunk.emit_remember(rem.ttl_ticks);
            },
            .forget => |fg| {
                const subj = try self.resolve_entity(fg.args[0]);
                const rel = try self.resolve_relation(fg.relation);
                const has_obj = fg.args.len > 1 and !std.mem.eql(u8, fg.args[1], "_");

                try self.chunk.emit_push_entity(subj);
                try self.chunk.emit_push_relation(rel);
                if (has_obj) {
                    const obj = try self.resolve_entity_or_value(fg.args[1]);
                    try self.chunk.emit_push_const(obj);
                }
                _ = try self.chunk.emit_op(.forget);
                try self.chunk.emit_u8(if (has_obj) 1 else 0);
            },
            .walk => |w| {
                const ent = try self.resolve_entity(w.entity);
                const wp_id = try self.resolve_waypoint(w.target);
                try self.chunk.emit_walk_to(ent, wp_id);
            },
            .face => |f| {
                const ent = try self.resolve_entity(f.entity);
                const target_id = try self.resolve_entity(f.target);
                // Emit peripheral cue for face direction
                try self.chunk.emit_push_entity(ent);
                try self.chunk.emit_push_entity(target_id);
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
                const target = try self.resolve_entity(iw.entity);

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
                try self.chunk.emit_push_entity(target);
                _ = try self.chunk.emit_op(.interrupt);
                try self.chunk.emit_u16(handler_pc);
            },
            .say => |s| {
                const speaker = try self.resolve_entity(s.speaker);
                const text_id = try self.world.intern_entity(s.text);
                try self.chunk.emit_push_entity(speaker);
                try self.chunk.emit_push_entity(text_id);
                _ = try self.chunk.emit_op(.emit_cue);
                try self.chunk.emit_u16(2); // cue 2 = say
                try self.chunk.emit_u8(2); // 2 args (speaker, text_entity)
            },
            .animate => |a| {
                const target_id = try self.resolve_entity(a.target);
                const clip_id = try self.world.intern_entity(a.clip);
                try self.chunk.emit_push_entity(target_id);
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
                const rel = try self.world.intern_relation(mml.PLAYING_RELATION, .property);
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
                var offer_pcs = std.ArrayList(usize).init(self.allocator);
                defer offer_pcs.deinit();
                var body_pcs = std.ArrayList(usize).init(self.allocator);
                defer body_pcs.deinit();
                var body_jumps = std.ArrayList(usize).init(self.allocator);
                defer body_jumps.deinit();

                _ = try self.chunk.emit_op(.choices_begin);

                for (choices, 0..) |choice, source_index| {
                    if (source_index >= dialogue_lifecycle.MAX_CHOICES) return error.DialogueTooLarge;
                    const source_index_u8: u8 = @intCast(source_index);
                    const text_id = try self.world.intern_entity(choice.text);
                    const FailureJump = struct { jump_pc: usize, failure_text: EntityId };
                    var failures = std.ArrayList(FailureJump).init(self.allocator);
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

                    var rejection_exits = std.ArrayList(usize).init(self.allocator);
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
        };
        defer self.allocator.free(text);
        return self.world.intern_entity(text);
    }

    fn compile_expr(self: *Codegen, expr: Expr) !void {
        switch (expr) {
            .roll_gte => |r| {
                try self.chunk.emit_roll_dice(r.count, r.sides);
                try self.chunk.emit_push_const(r.threshold);
                _ = try self.chunk.emit_op(.gte);
            },
            .has_fact => |pat| {
                const subj = try self.resolve_entity(pat.args[0]);
                const rel = try self.resolve_relation(pat.relation);
                var mask: u8 = 0x03; // bit 0 (subj) | bit 1 (rel)
                try self.chunk.emit_push_entity(subj);
                try self.chunk.emit_push_relation(rel);
                if (pat.args.len > 1 and !std.mem.eql(u8, pat.args[1], "_")) {
                    const obj = try self.resolve_entity_or_value(pat.args[1]);
                    try self.chunk.emit_push_const(obj);
                    mask |= 0x04; // bit 2 (obj)
                }
                _ = try self.chunk.emit_op(.query_has);
                try self.chunk.emit_u8(mask);
            },
            .not_fact => |pat| {
                const subj = try self.resolve_entity(pat.args[0]);
                const rel = try self.resolve_relation(pat.relation);
                var mask: u8 = 0x03;
                try self.chunk.emit_push_entity(subj);
                try self.chunk.emit_push_relation(rel);
                if (pat.args.len > 1 and !std.mem.eql(u8, pat.args[1], "_")) {
                    const obj = try self.resolve_entity_or_value(pat.args[1]);
                    try self.chunk.emit_push_const(obj);
                    mask |= 0x04;
                }
                _ = try self.chunk.emit_op(.query_has);
                try self.chunk.emit_u8(mask);
                _ = try self.chunk.emit_op(.not);
            },
        }
    }

    fn resolve_entity(self: *Codegen, name: []const u8) !EntityId {
        return try self.world.intern_entity(name);
    }

    fn resolve_relation(self: *Codegen, name: []const u8) !RelationKind {
        return try self.world.intern_relation(name, .set);
    }

    fn resolve_entity_or_value(self: *Codegen, name: []const u8) !u32 {
        if (std.fmt.parseInt(u32, name, 10)) |val| {
            return val;
        } else |_| {
            const ent = try self.resolve_entity(name);
            return ent.to_int();
        }
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
        \\entity Gabriel, MapleSyrup, CatHairTape, CatMoustache
        \\relation Carries(holder, item)
        \\
        \\on cue Uses(Gabriel, MapleSyrup, CatHairTape):
        \\  remember Carries(Gabriel, CatMoustache)
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
    const pc1 = compiled.find_cue_handler("Uses", "Gabriel", "MapleSyrup", "CatHairTape");
    const pc2 = compiled.find_cue_handler("Uses", "Gabriel", "CatHairTape", "MapleSyrup");
    try testing.expect(pc1 != null);
    try testing.expect(pc2 != null);
    try testing.expectEqual(pc1.?, pc2.?);

    // 2. Non-matching pair returns fallback or null
    const pc3 = compiled.find_cue_handler("Uses", "Gabriel", "MapleSyrup", "NonExistent");
    _ = pc3;
    // Since fallback "Uses" is registered for base cue name, check specific signature
    try testing.expect(compiled.cue_handler_entries.get("Uses:Gabriel:MapleSyrup:NonExistent") == null);
}

test "P12-01: codegen compiles multi-scene transitions and registers scoped marks" {
    const testing = std.testing;
    const source =
        \\scene: Tavern
        \\cast: Guybrush
        \\props: HearthProp
        \\marks: Counter, Door
        \\
        \\scene: Wine Cellar
        \\cast: Guard
        \\props: KegProp
        \\marks: KegMark, Hatch
        \\
        \\routine EnterCellar(Guybrush):
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
    try testing.expectEqual(@as(u8, @intFromEnum(Opcode.transition_scene)), op_byte);
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
    const save_mod = @import("../save.zig");

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    var vm = vm_mod.VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    const p = try world.intern_entity("Player");
    try vm.pending_weaves.append(.{ .caster = p, .draft = p, .target = p });

    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    try testing.expectError(
        error.PendingWeavesNotDispatched,
        save_mod.write_save_state(testing.allocator, buf.writer(), &world, null, &vm, .{}),
    );
}

test "P32-28: Option C predicate presence for states without synthetic true entity" {
    const testing = std.testing;
    const vm_mod = @import("../vm.zig");
    const source =
        \\entity Guybrush, Flags
        \\scene: Beach
        \\
        \\Tampered is a state.
        \\
        \\now Flags are Tampered
        \\
        \\routine Check(Guybrush):
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
    const guybrush = try world.intern_entity("Guybrush");

    var vm = vm_mod.VM.init(alloc, &world, &compiled.chunk);
    defer vm.deinit();

    // 2. Execute initial declarative statements (`now Flags are Tampered`)
    if (compiled.initial_entry) |init_pc| {
        _ = try vm.spawn_routine(guybrush, init_pc);
        _ = try vm.step_tick();
    }

    // Initial statement remembered with object_or_value = 0
    try testing.expect(world.has_fact(flags, tampered, null));
    try testing.expect(world.has_fact(flags, tampered, 0));

    // 3. Execute routine Check on VM to test `if Flags are Tampered:` and `now Flags are not Tampered`
    const entry_pc = compiled.routine_entries.get("Check").?;
    _ = try vm.spawn_routine(guybrush, entry_pc);
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

    var snap = std.ArrayList(u8).init(alloc);
    defer snap.deinit();
    try world.save_state(snap.writer());
    var stream = std.io.fixedBufferStream(snap.items);
    try world.restore_state(stream.reader());
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

    try testing.expectError(error.PathAlreadyChosen, vm.select_path(&compiled, "Fists"));
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
    try testing.expectEqual(world_mod.RelationType.property, world.get_relation_meta(world.lookup_relation("PlayingScore").?).?.rel_type);

    var vm = @import("../vm.zig").VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    try host.run_initial_statements(&world, &vm, &compiled);
    const calm_id = world.lookup_entity("Calm").?;
    const chase_id = world.lookup_entity("Chase").?;
    try testing.expectEqual(@as(?EntityId, calm_id), display.current_score_entity(&world, vm.current_scene));

    const warden = try world.intern_entity("Warden");
    _ = try vm.spawn_routine(warden, compiled.routine_entries.get("Watch").?);
    var snapshot = std.ArrayList(u8).init(testing.allocator);
    defer snapshot.deinit();
    var seen = std.ArrayList(?EntityId).init(testing.allocator);
    defer seen.deinit();
    for (0..12) |t| {
        _ = try host.tick(&vm, &compiled);
        const now = display.current_score_entity(&world, vm.current_scene);
        if (seen.items.len == 0 or seen.items[seen.items.len - 1] != now) try seen.append(now);
        if (t == 3) try world.save_state(snapshot.writer());
    }
    // Calm, then the Chase override, which persists into the Rampart (no scene score there);
    // `stop score` in the Rampart leaves silence, and the Gatehouse brings Calm back.
    try testing.expectEqualSlices(?EntityId, &.{ calm_id, chase_id, null, calm_id }, seen.items);

    // A rewind restores the override along with the rest of the World.
    var stream = std.io.fixedBufferStream(snapshot.items);
    try world.restore_state(stream.reader());
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
