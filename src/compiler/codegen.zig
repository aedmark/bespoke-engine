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

    pub fn deinit(self: *CompiledProgram) void {
        for (self.societies.items) |*society| society.deinit_owned(self.chunk.allocator);
        self.societies.deinit();
        for (self.duels.items) |*duel| duel.deinit_owned(self.chunk.allocator);
        self.duels.deinit();
        for (self.degradations.items) |*degradation| degradation.deinit_owned(self.chunk.allocator);
        self.degradations.deinit();
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

        // 2. Intern declared relations
        for (ast.relations.items) |rel| {
            _ = try mut_self.world.intern_relation(
                rel.name,
                if (rel.is_property) .property else .set,
            );
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
        if (ast.initial_stmts.items.len > 0) {
            initial_entry = mut_self.chunk.count();
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

                for (choices) |choice| {
                    var skip_pcs = std.ArrayList(usize).init(self.allocator);
                    defer skip_pcs.deinit();

                    if (choice.guard) |guard| {
                        try self.compile_expr(guard);
                        const pc = try self.chunk.emit_op(.jump_if_false);
                        try self.chunk.emit_i16(0);
                        try skip_pcs.append(pc);
                    }
                    for (choice.where_patterns) |pattern| {
                        try self.compile_expr(.{ .has_fact = pattern });
                        const pc = try self.chunk.emit_op(.jump_if_false);
                        try self.chunk.emit_i16(0);
                        try skip_pcs.append(pc);
                    }

                    const text_id = try self.world.intern_entity(choice.text);
                    const offer_pc = try self.chunk.emit_offer_choice(text_id, 0);
                    try offer_pcs.append(offer_pc);

                    const after_offer = self.chunk.count();
                    for (skip_pcs.items) |skip_pc| {
                        const offset: i16 = @intCast(after_offer - (skip_pc + 3));
                        std.mem.writeInt(i16, self.chunk.code.items[skip_pc + 1 ..][0..2], offset, .little);
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
    try testing.expectEqualStrings("Only with coin", vm.dialogue_view().?.text(1));

    var snap = std.ArrayList(u8).init(alloc);
    defer snap.deinit();
    try world.save_state(snap.writer());
    var stream = std.io.fixedBufferStream(snap.items);
    try world.restore_state(stream.reader());
    try testing.expectEqualStrings("Only with coin", vm.dialogue_view().?.text(1));

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

test "P23-01: degradation declarations compile into executable container profiles" {
    const testing = std.testing;
    const source =
        \\degradation TestProfile:
        \\  substance TestReagent
        \\  stage Sound 3
        \\  stage Etched 2
        \\  stage Failed 0
        \\  vessel TestVial 8 5 Sound
        \\  relations HoldsReagent ReagentVolume VialState ReagentExposure VialFailedAt
    ;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try @import("../compiler.zig").compile_source(testing.allocator, &world, null, source);
    defer compiled.deinit();

    try testing.expectEqual(@as(usize, 1), compiled.degradations.items.len);
    const declaration = &compiled.degradations.items[0];
    const system = try container_mod.ContainerSystem.init(&world, declaration.config);
    const vial = world.lookup_entity("TestVial").?;
    try testing.expectEqual(world.lookup_entity("Sound").?.to_int(), world.get_property(vial, system.rel.stage).?);
    try testing.expectEqual(@as(u32, 5), world.get_property(vial, system.rel.volume).?);
    try testing.expectEqualStrings("VialState", world.get_relation_meta(system.rel.stage).?.name);
}
