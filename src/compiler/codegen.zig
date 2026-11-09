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

    pub fn deinit(self: *CompiledProgram) void {
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
    pub fn find_cue_handler(
        self: *const CompiledProgram,
        cue_name: []const u8,
        actor: ?[]const u8,
        target_a: ?[]const u8,
        target_b: ?[]const u8,
    ) ?usize {
        var buf: [128]u8 = undefined;

        // 1. Try ternary signature (Actor + ItemA + ItemB)
        if (actor != null and target_a != null and target_b != null) {
            if (std.fmt.bufPrint(&buf, "{s}:{s}:{s}:{s}", .{ cue_name, actor.?, target_a.?, target_b.? })) |sig| {
                if (self.cue_handler_entries.get(sig)) |pc| return pc;
            } else |_| {}
            // Commutative permutation
            if (std.fmt.bufPrint(&buf, "{s}:{s}:{s}:{s}", .{ cue_name, actor.?, target_b.?, target_a.? })) |sig| {
                if (self.cue_handler_entries.get(sig)) |pc| return pc;
            } else |_| {}
        }

        // 2. Try binary signature (Actor + TargetA)
        if (actor != null and target_a != null) {
            if (std.fmt.bufPrint(&buf, "{s}:{s}:{s}", .{ cue_name, actor.?, target_a.? })) |sig| {
                if (self.cue_handler_entries.get(sig)) |pc| return pc;
            } else |_| {}
        }

        // 3. Try unary signature (Actor only)
        if (actor != null) {
            if (std.fmt.bufPrint(&buf, "{s}:{s}", .{ cue_name, actor.? })) |sig| {
                if (self.cue_handler_entries.get(sig)) |pc| return pc;
            } else |_| {}
        }

        // 4. Fallback to cue name alone
        return self.cue_handler_entries.get(cue_name);
    }
};

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

            // Register fallback key
            if (!mut_self.cue_handler_entries.contains(cue.cue_name)) {
                try mut_self.cue_handler_entries.put(cue.cue_name, entry_pc);
            }

            if (cue.params.len == 1) {
                const sig = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}", .{ cue.cue_name, cue.params[0] });
                try mut_self.allocated_cue_keys.append(sig);
                try mut_self.cue_handler_entries.put(sig, entry_pc);
            } else if (cue.params.len == 2) {
                const sig = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}:{s}", .{ cue.cue_name, cue.params[0], cue.params[1] });
                try mut_self.allocated_cue_keys.append(sig);
                try mut_self.cue_handler_entries.put(sig, entry_pc);
            } else if (cue.params.len >= 3) {
                // Primary signature: Uses:Actor:ItemA:ItemB
                const sig1 = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}:{s}:{s}", .{ cue.cue_name, cue.params[0], cue.params[1], cue.params[2] });
                try mut_self.allocated_cue_keys.append(sig1);
                try mut_self.cue_handler_entries.put(sig1, entry_pc);

                // Commutative permutation for in-hand item combining: Uses:Actor:ItemB:ItemA
                const sig2 = try std.fmt.allocPrint(mut_self.allocator, "{s}:{s}:{s}:{s}", .{ cue.cue_name, cue.params[0], cue.params[2], cue.params[1] });
                try mut_self.allocated_cue_keys.append(sig2);
                try mut_self.cue_handler_entries.put(sig2, entry_pc);
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
        };
    }

    fn compile_stmt(self: *Codegen, stmt: Stmt) !void {
        switch (stmt) {
            .remember => |rem| {
                const subj = try self.resolve_entity(rem.args[0]);
                const rel = try self.resolve_relation(rem.relation);
                const obj = try self.resolve_entity_or_value(rem.args[1]);

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
                var jump_end_pcs = std.ArrayList(usize).init(self.allocator);
                defer jump_end_pcs.deinit();

                for (choices) |choice| {
                    var jump_skip_pc: ?usize = null;
                    if (choice.guard) |guard| {
                        try self.compile_expr(guard);
                        jump_skip_pc = try self.chunk.emit_op(.jump_if_false);
                        try self.chunk.emit_i16(0); // placeholder
                    }

                    for (choice.body) |s| {
                        try self.compile_stmt(s);
                    }

                    const j_end = try self.chunk.emit_op(.jump);
                    try self.chunk.emit_i16(0);
                    try jump_end_pcs.append(j_end);

                    if (jump_skip_pc) |skip_pc| {
                        const dest_pc = self.chunk.count();
                        const offset: i16 = @intCast(dest_pc - (skip_pc + 3));
                        std.mem.writeInt(i16, self.chunk.code.items[skip_pc + 1 ..][0..2], offset, .little);
                    }
                }

                const end_pc = self.chunk.count();
                for (jump_end_pcs.items) |j_end| {
                    const offset: i16 = @intCast(end_pc - (j_end + 3));
                    std.mem.writeInt(i16, self.chunk.code.items[j_end + 1 ..][0..2], offset, .little);
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
    try vm.step_tick();

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

    try testing.expect(compiled.cue_handler_entries.contains("TalkTo"));
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
    try vm.step_tick();
    try testing.expectEqual(@as(usize, 0), vm.fibers.items[0].interrupt_stack.items.len);

    // Bard charms Guard -> both clauses match -> reactive rule edge-triggers interrupt!
    try world.remember(guard, charmed, bard.to_int(), 10);
    try vm.step_tick();
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
    try vm.step_tick();
    try testing.expect(world.has_fact(brazier, lit, player.to_int()));

    // Reversed notes resolve to Douse: the complementary effect.
    try testing.expect((try vm.weave_notes(&compiled, player, .{ .E, .G, .E, .C }, brazier)) != null);
    try vm.step_tick();
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
    try vm.step_tick(); // wait 1 tick
    try vm.step_tick(); // executes weave opcode
    try testing.expectEqual(@as(usize, 1), vm.pending_weaves.items.len);
    try testing.expectEqual(kindle, vm.pending_weaves.items[0].draft);
    try testing.expectEqual(player, vm.pending_weaves.items[0].caster);
    try testing.expect(!world.has_fact(brazier, lit, null));

    try testing.expectEqual(@as(usize, 1), try vm.dispatch_pending_weaves(&compiled));
    try testing.expectEqual(@as(usize, 0), vm.pending_weaves.items.len);
    try vm.step_tick(); // handler fiber runs
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
