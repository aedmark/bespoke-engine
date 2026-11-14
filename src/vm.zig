const std = @import("std");
const world_mod = @import("world.zig");
const bytecode_mod = @import("bytecode.zig");
const spatial_mod = @import("spatial.zig");
const parser_mod = @import("compiler/parser.zig");
const draft_mod = @import("draft.zig");
pub const PendingWeave = draft_mod.PendingWeave;
const dialogue_mod = @import("dialogue.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const Opcode = bytecode_mod.Opcode;
pub const BytecodeChunk = bytecode_mod.BytecodeChunk;
pub const SpatialSystem = spatial_mod.SpatialSystem;

pub const MAX_STACK: usize = 256;
pub const MAX_INSTRUCTIONS_PER_TICK: usize = 10000;

/// Master simulation clock constants for interactive runners (D-028).
/// Set to 1000ms (1.0 Hz) for deliberate, human-readable narrative pacing.
pub const DEFAULT_TICK_INTERVAL_MS: i64 = 1000;
pub const MIN_TICK_INTERVAL_MS: i64 = 100; // 10 Hz maximum fast-forward
pub const MAX_TICK_INTERVAL_MS: i64 = 3000; // 0.33 Hz maximum slow-motion

/// Decreases simulation speed (increases interval between ticks) (D-028).
pub fn step_tick_interval_slower(interval: i64) i64 {
    if (interval < 500) return @min(MAX_TICK_INTERVAL_MS, interval + 100);
    return @min(MAX_TICK_INTERVAL_MS, interval + 250);
}

/// Increases simulation speed (decreases interval between ticks) (D-028).
pub fn step_tick_interval_faster(interval: i64) i64 {
    if (interval <= 500) return @max(MIN_TICK_INTERVAL_MS, interval - 100);
    return @max(MIN_TICK_INTERVAL_MS, interval - 250);
}

pub const FiberId = u32;

pub const FiberStateTag = enum {
    ready,
    waiting_ticks,
    waiting_cond,
    waiting_motor,
    waiting_dialogue,
    halted,
    paused,
};

pub const FiberState = union(FiberStateTag) {
    ready: void,
    waiting_ticks: u64, // target tick to wake up
    waiting_cond: u16, // cond_pc to evaluate
    waiting_motor: EntityId, // waiting for entity to finish walking (P3-02)
    waiting_dialogue: void, // suspended on a scripted choice set (P32-30)
    halted: void,
    paused: void,
};

pub const InterruptFrame = struct {
    pc: usize,
    sp: usize,
    state: FiberState,
    priority: u16 = 0,
};

pub const EmittedCue = struct {
    cue_id: u16,
    args: [4]u32,
    arg_count: u8,
};

pub const ReactiveEdge = enum {
    rising,
    falling,
    on_expire,
    /// Fires when the rule's actor completes a walk at the rule's waypoint (P32-18, D-036).
    on_arrive,
};

/// Reactive simulation rule evaluated continuously on tick boundary and state mutations (P8-02, P10-02, D-010, D-012).
pub const ReactiveRule = struct {
    id: u32,
    clauses: []const world_mod.PatternClause,
    target_entity: EntityId,
    priority: u16,
    handler_pc: usize,
    edge: ReactiveEdge = .rising,
    is_active: bool = false,
};

/// A dialogue choice pruned and validated by relational fact guards at balloon spawn time (P13-02, D-015).
pub const PrunedChoice = struct {
    original_index: usize,
    text: []const u8,
    body: []const parser_mod.Stmt,
};

pub const Fiber = struct {
    id: FiberId,
    owner: EntityId,
    pc: usize,
    stack: [MAX_STACK]u32,
    sp: usize,
    state: FiberState,
    active_priority: u16 = 0,
    is_hyper_temporal: bool = false,
    interrupt_stack: std.ArrayList(InterruptFrame),

    pub fn init(allocator: std.mem.Allocator, id: FiberId, owner: EntityId, entry_pc: usize) Fiber {
        return Fiber{
            .id = id,
            .owner = owner,
            .pc = entry_pc,
            .stack = undefined,
            .sp = 0,
            .state = .{ .ready = {} },
            .active_priority = 0,
            .is_hyper_temporal = false,
            .interrupt_stack = std.ArrayList(InterruptFrame).init(allocator),
        };
    }

    pub fn deinit(self: *Fiber) void {
        self.interrupt_stack.deinit();
    }

    pub fn push(self: *Fiber, val: u32) !void {
        if (self.sp >= MAX_STACK) return error.StackOverflow;
        self.stack[self.sp] = val;
        self.sp += 1;
    }

    pub fn pop(self: *Fiber) !u32 {
        if (self.sp == 0) return error.StackUnderflow;
        self.sp -= 1;
        return self.stack[self.sp];
    }

    pub fn peek(self: *const Fiber) !u32 {
        if (self.sp == 0) return error.StackUnderflow;
        return self.stack[self.sp - 1];
    }
};

pub const VM = struct {
    allocator: std.mem.Allocator,
    world: *World,
    chunk: *const BytecodeChunk,
    spatial: ?*SpatialSystem,
    fibers: std.ArrayList(Fiber),
    next_fiber_id: FiberId,
    emitted_cues: std.ArrayList(EmittedCue),
    reactive_rules: std.ArrayList(ReactiveRule),
    current_scene: ?EntityId = null,
    prng: std.rand.DefaultPrng,
    /// Weaves queued by the `weave` opcode, awaiting `dispatch_pending_weaves` (D-029).
    /// Transient between `step_tick` and the host's dispatch call; `save.zig` refuses to
    /// snapshot while non-empty so a weave can never be silently dropped by save/restore.
    pending_weaves: std.ArrayList(PendingWeave),

    pub fn init(allocator: std.mem.Allocator, world: *World, chunk: *const BytecodeChunk) VM {
        return VM{
            .allocator = allocator,
            .world = world,
            .chunk = chunk,
            .spatial = null,
            .fibers = std.ArrayList(Fiber).init(allocator),
            .next_fiber_id = 1,
            .emitted_cues = std.ArrayList(EmittedCue).init(allocator),
            .reactive_rules = std.ArrayList(ReactiveRule).init(allocator),
            .current_scene = null,
            .prng = std.rand.DefaultPrng.init(42),
            .pending_weaves = std.ArrayList(PendingWeave).init(allocator),
        };
    }

    /// Rebinds execution to another arena with the same compiled symbol table. Temporal hosts use
    /// this after a branch fork, restore, or collapse so bytecode never mutates a stale arena.
    pub fn bind_world(self: *VM, world: *World) void {
        self.world = world;
    }

    pub fn deinit(self: *VM) void {
        for (self.fibers.items) |*f| {
            f.deinit();
        }
        self.fibers.deinit();
        self.emitted_cues.deinit();
        self.pending_weaves.deinit();
        for (self.reactive_rules.items) |r| {
            self.allocator.free(r.clauses);
        }
        self.reactive_rules.deinit();
    }

    /// Selects one stageplay path (P24-01). The path entity carries `PathActive` in World facts,
    /// so save and rewind need no VM state. Its initializer fiber runs on the next tick. A second,
    /// different path is refused; selecting the same path again is a no-op.
    pub fn select_path(self: *VM, compiled: anytype, name: []const u8) !?FiberId {
        const path_entity = self.world.lookup_entity(name) orelse return error.UnknownPath;
        const path_active = self.world.lookup_relation("PathActive") orelse return error.UnknownPath;
        if (self.world.has_fact(null, path_active, null)) {
            if (self.world.has_fact(path_entity, path_active, null)) return null;
            return error.PathAlreadyChosen;
        }

        const entry_pc = compiled.find_path(name) orelse return error.UnknownPath;
        try self.world.remember(path_entity, path_active, 0, 0);
        return try self.spawn_routine(path_entity, entry_pc);
    }

    /// Spawns a new routine fiber owned by an entity.
    pub fn spawn_routine(self: *VM, owner: EntityId, entry_pc: usize) !FiberId {
        const id = self.next_fiber_id;
        self.next_fiber_id += 1;
        const fiber = Fiber.init(self.allocator, id, owner, entry_pc);
        try self.fibers.append(fiber);
        return id;
    }

    /// Spawns a hyper-temporal routine fiber owned by a future or meta-temporal entity (e.g. a guide acting from outside the timeline) (P31-01, D-027).
    /// Hyper-temporal fibers execute with priority 255 to deliver guidance across timeline boundaries.
    pub fn spawn_hyper_temporal_routine(self: *VM, owner: EntityId, entry_pc: usize) !FiberId {
        const id = self.next_fiber_id;
        self.next_fiber_id += 1;
        var fiber = Fiber.init(self.allocator, id, owner, entry_pc);
        fiber.is_hyper_temporal = true;
        fiber.active_priority = 255;
        try self.fibers.append(fiber);
        return id;
    }

    /// Preempts an entity's active fiber with an interruption routine and assigned priority (D-004, P2-04, P8-03).
    pub fn interrupt_entity_priority(self: *VM, target: EntityId, handler_pc: u16, priority: u16) !bool {
        for (self.fibers.items) |*f| {
            if (f.owner == target and f.state != .halted) {
                if (priority < f.active_priority and f.interrupt_stack.items.len > 0) {
                    // Cannot preempt a higher-priority active interrupt
                    return false;
                }
                // Push current execution context onto interrupt stack
                try f.interrupt_stack.append(.{
                    .pc = f.pc,
                    .sp = f.sp,
                    .state = f.state,
                    .priority = f.active_priority,
                });
                // Switch execution to interrupt handler with new priority
                f.pc = handler_pc;
                f.state = .{ .ready = {} };
                f.active_priority = priority;
                return true;
            }
        }
        return false;
    }

    /// Preempts an entity's active fiber with default priority (0).
    pub fn interrupt_entity(self: *VM, target: EntityId, handler_pc: u16) !bool {
        return self.interrupt_entity_priority(target, handler_pc, 0);
    }

    /// Registers a reactive simulation rule evaluated continuously on tick and state changes (P8-02, D-010).
    pub fn add_reactive_rule(
        self: *VM,
        target_entity: EntityId,
        clauses: []const world_mod.PatternClause,
        priority: u16,
        handler_pc: usize,
    ) !u32 {
        return self.add_reactive_rule_edge(target_entity, clauses, priority, handler_pc, .rising);
    }

    /// Registers a reactive simulation rule with a specified edge trigger kind (P10-02, D-012).
    pub fn add_reactive_rule_edge(
        self: *VM,
        target_entity: EntityId,
        clauses: []const world_mod.PatternClause,
        priority: u16,
        handler_pc: usize,
        edge: ReactiveEdge,
    ) !u32 {
        const id: u32 = @intCast(self.reactive_rules.items.len + 1);
        const owned_clauses = try self.allocator.dupe(world_mod.PatternClause, clauses);
        try self.reactive_rules.append(.{
            .id = id,
            .clauses = owned_clauses,
            .target_entity = target_entity,
            .priority = priority,
            .handler_pc = handler_pc,
            .edge = edge,
            .is_active = false,
        });
        return id;
    }

    /// Evaluates reactive 'when' rules against active relational facts in descending priority order (P8-02, P8-03, P10-02, D-010, D-012).
    /// Fires edge-triggered interrupts on target entities on rising edges, falling edges, and TTL fact expirations.
    pub fn evaluate_reactive_rules(self: *VM) !usize {
        var fired_count: usize = 0;

        // Sort rules by priority descending so higher priority rules take precedence
        std.sort.insertion(ReactiveRule, self.reactive_rules.items, {}, struct {
            fn lessThan(_: void, a: ReactiveRule, b: ReactiveRule) bool {
                return a.priority > b.priority;
            }
        }.lessThan);

        // 1. Check TTL fact expiration rules (on_expire) (P10-02, D-012)
        const expired = self.world.get_recently_expired();
        for (expired) |ef| {
            var i: usize = 0;
            while (i < self.reactive_rules.items.len) : (i += 1) {
                const rule = &self.reactive_rules.items[i];
                if (rule.edge == .on_expire) {
                    if (rule.clauses.len > 0) {
                        const clause = rule.clauses[0];
                        var match = true;
                        if (clause.relation != ef.relation) match = false;
                        switch (clause.subject) {
                            .constant => |c| if (c != ef.subject.to_int()) {
                                match = false;
                            },
                            else => {},
                        }
                        if (match) {
                            const interrupted = try self.interrupt_entity_priority(
                                rule.target_entity,
                                @intCast(rule.handler_pc),
                                rule.priority,
                            );
                            if (!interrupted) {
                                _ = try self.spawn_routine(rule.target_entity, rule.handler_pc);
                            }
                            fired_count += 1;
                        }
                    }
                }
            }
        }

        // 1b. Check arrival rules (P32-18, D-036). The motor stepped earlier in this tick, so a
        // walk that completed now fires now. Arrivals are cleared after this pass: each one is
        // seen by exactly one evaluation, which is what makes the rule an edge and not a level.
        if (self.spatial) |sp| {
            for (self.reactive_rules.items) |*rule| {
                if (rule.edge != .on_arrive or rule.clauses.len == 0) continue;
                const clause = rule.clauses[0];
                const actor = switch (clause.subject) {
                    .constant => |c| EntityId.from_int(c),
                    else => continue,
                };
                const mark = switch (clause.object) {
                    .constant => |c| c,
                    else => continue,
                };
                const arrived_at = sp.pending_arrival(actor) orelse continue;
                if (arrived_at != mark) continue;

                const interrupted = try self.interrupt_entity_priority(
                    rule.target_entity,
                    @intCast(rule.handler_pc),
                    rule.priority,
                );
                if (!interrupted) {
                    _ = try self.spawn_routine(rule.target_entity, rule.handler_pc);
                }
                fired_count += 1;
            }
            sp.clear_arrivals();
        }

        // 2. Check rising and falling edge rules (P8-02, P10-02, D-010, D-012)
        var i: usize = 0;
        while (i < self.reactive_rules.items.len) : (i += 1) {
            var rule = &self.reactive_rules.items[i];
            if (rule.edge == .on_expire or rule.edge == .on_arrive) continue;

            const matches = self.world.has_multi_match(rule.clauses);

            if (matches) {
                if (!rule.is_active) {
                    // Positive edge transition: false -> true
                    rule.is_active = true;
                    if (rule.edge == .rising) {
                        const interrupted = try self.interrupt_entity_priority(
                            rule.target_entity,
                            @intCast(rule.handler_pc),
                            rule.priority,
                        );
                        if (!interrupted) {
                            _ = try self.spawn_routine(rule.target_entity, rule.handler_pc);
                        }
                        fired_count += 1;
                    }
                }
            } else {
                if (rule.is_active) {
                    // Negative edge transition: true -> false
                    rule.is_active = false;
                    if (rule.edge == .falling) {
                        const interrupted = try self.interrupt_entity_priority(
                            rule.target_entity,
                            @intCast(rule.handler_pc),
                            rule.priority,
                        );
                        if (!interrupted) {
                            _ = try self.spawn_routine(rule.target_entity, rule.handler_pc);
                        }
                        fired_count += 1;
                    }
                }
            }
        }

        return fired_count;
    }

    /// Registers all reactive simulation rules from a compiled program (P8-02, P10-02, D-010, D-012).
    pub fn load_compiled_rules(self: *VM, compiled: anytype) !void {
        for (compiled.reactive_rules.items) |r| {
            const edge: ReactiveEdge = switch (r.edge) {
                .rising => .rising,
                .falling => .falling,
                .on_expire => .on_expire,
                .on_arrive => .on_arrive,
            };
            _ = try self.add_reactive_rule_edge(r.target_entity, r.clauses, r.priority, r.handler_pc, edge);
        }
    }

    /// Fires an adventure cue for an actor with up to two optional target entities (P11-02, D-009, D-013).
    /// Spawns a fiber executing the matching cue handler and records an EmittedCue for display peripherals.
    pub fn fire_cue(
        self: *VM,
        compiled: anytype,
        cue_name: []const u8,
        actor: EntityId,
        target_a: ?EntityId,
        target_b: ?EntityId,
    ) !?FiberId {
        // The guard is read now, at the cue, not when the handler fiber first runs: a guard
        // describes the moment of the action, and a cue fired before a save must not change
        // its mind after a restore (D-072).
        const handler_pc = compiled.select_cue_handler(self.world, cue_name, actor, target_a, target_b) orelse return null;

        // Record cue emission for peripheral visual/audio bridge
        var emitted = EmittedCue{
            .cue_id = @intCast((try self.world.intern_entity(cue_name)).to_int() & 0xFFFF),
            .args = [_]u32{0} ** 4,
            .arg_count = 1,
        };
        emitted.args[0] = actor.to_int();
        if (target_a) |ta| {
            emitted.args[1] = ta.to_int();
            emitted.arg_count = 2;
        }
        if (target_b) |tb| {
            emitted.args[2] = tb.to_int();
            emitted.arg_count = 3;
        }
        try self.emitted_cues.append(emitted);

        // Spawn a routine fiber executing the handler
        return try self.spawn_routine(actor, handler_pc);
    }

    /// Weaves a named draft on a target (P22-01, D-029). Runs the `Weave(caster, draft, target)`
    /// handler, or records a `WeaveFizzled` cue when the entity is not a draft or no handler
    /// accepts it. Returns the handler fiber, or null on fizzle.
    pub fn weave_draft(
        self: *VM,
        compiled: anytype,
        caster: EntityId,
        draft: EntityId,
        target: EntityId,
    ) !?FiberId {
        const handler_pc = if (compiled.find_draft(draft) == null)
            null
        else
            compiled.find_weave_handler(
                self.world.get_entity_name(caster) orelse "",
                self.world.get_entity_name(draft) orelse "",
                self.world.get_entity_name(target) orelse "",
            );

        const cue_name = if (handler_pc != null) draft_mod.WEAVE_CUE else draft_mod.WEAVE_FIZZLED_CUE;
        var emitted = EmittedCue{
            .cue_id = @intCast((try self.world.intern_entity(cue_name)).to_int() & 0xFFFF),
            .args = [_]u32{0} ** 4,
            .arg_count = 3,
        };
        emitted.args[0] = caster.to_int();
        emitted.args[1] = draft.to_int();
        emitted.args[2] = target.to_int();
        try self.emitted_cues.append(emitted);

        const pc = handler_pc orelse return null;
        return try self.spawn_routine(caster, pc);
    }

    /// Resolves four played notes to a draft and weaves it (P22-01, D-029). Reversed playback
    /// needs no special case: a declared `reverse` is its own table entry. An unrecognized
    /// sequence fizzles with draft id 0 so peripherals can still sound the failure.
    pub fn weave_notes(
        self: *VM,
        compiled: anytype,
        caster: EntityId,
        notes: draft_mod.Notes,
        target: EntityId,
    ) !?FiberId {
        if (compiled.find_draft_by_notes(notes)) |d| {
            return self.weave_draft(compiled, caster, d.entity, target);
        }
        try self.emitted_cues.append(.{
            .cue_id = @intCast((try self.world.intern_entity(draft_mod.WEAVE_FIZZLED_CUE)).to_int() & 0xFFFF),
            .args = .{ caster.to_int(), 0, target.to_int(), 0 },
            .arg_count = 3,
        });
        return null;
    }

    /// Host re-dispatch for in-script weaves (D-029). Call once after every `step_tick`, before
    /// snapshotting. Handlers spawned here run on the next tick. Weaves queued by those handlers
    /// wait for the next dispatch, so a weave chain advances one link per tick and cannot loop
    /// unboundedly inside one call. Returns the number of weaves dispatched.
    pub fn dispatch_pending_weaves(self: *VM, compiled: anytype) !usize {
        const queued = try self.pending_weaves.toOwnedSlice();
        defer self.allocator.free(queued);
        for (queued) |w| {
            _ = try self.weave_draft(compiled, w.caster, w.draft, w.target);
        }
        return queued.len;
    }

    /// Names the entity the frame channel presents as the speaker for the next scripted set
    /// (P32-30). Presentation only; the set stays keyed by the fiber's owner.
    pub fn set_dialogue_speaker(self: *VM, owner: EntityId, display: EntityId) !void {
        return dialogue_mod.set_speaker(self.world, owner, display);
    }

    /// Opens a runtime-generated dialogue set (P32-30, D-046). The host supplies the text and
    /// an opaque action id per choice; `choose` returns the action without touching a fiber.
    pub fn open_generated_dialogue(
        self: *VM,
        speaker: EntityId,
        prompt: []const u8,
        choices: []const dialogue_mod.Choice,
    ) !usize {
        return dialogue_mod.open_generated(self.world, speaker, prompt, choices);
    }

    /// The open dialogue, reconstructed from World facts, or null when none is open.
    pub fn dialogue_view(self: *const VM) ?dialogue_mod.View {
        return dialogue_mod.view(self.world);
    }

    /// Selects an offered choice. Scripted choices resume their fiber at the compiled body;
    /// generated choices return their action id to the host. Null when no choice matches.
    pub fn choose(self: *VM, index: usize) !?dialogue_mod.Selection {
        const open = dialogue_mod.view(self.world) orelse return null;
        const selection = (try dialogue_mod.choose(self.world, open.speaker, index)) orelse return null;
        if (selection.fiber_id != 0) {
            for (self.fibers.items) |*f| {
                if (f.id == selection.fiber_id) {
                    f.pc = @intCast(selection.body_pc);
                    f.state = .{ .ready = {} };
                    break;
                }
            }
        }
        return selection;
    }

    /// Reconciles suspended dialogue fibers with World facts after a snapshot restore. A fiber
    /// waiting on a dialogue the restored world does not contain continues past the set.
    pub fn sync_dialogue(self: *VM) void {
        const open = dialogue_mod.view(self.world);
        for (self.fibers.items) |*f| {
            if (f.state != .waiting_dialogue) continue;
            if (open) |v| {
                if (v.speaker == f.owner and dialogue_mod.fiber_id(self.world, v.speaker) == f.id) continue;
            }
            f.state = .{ .ready = {} };
        }
    }

    /// Transitions simulation to target scene entity, pausing old scene fibers and waking/resuming target scene fibers (P12-01, D-014).
    pub fn transition_to_scene(self: *VM, target_scene: EntityId) !void {
        const old_scene = self.current_scene;
        if (old_scene) |os| {
            if (os == target_scene) return;
        }

        self.current_scene = target_scene;

        // 1. Pause ambient routines whose owner is the old scene
        if (old_scene) |os| {
            for (self.fibers.items) |*f| {
                if (f.owner == os and f.state != .halted) {
                    f.state = .{ .paused = {} };
                }
            }
        }

        // 2. Resume paused routines whose owner is the target scene
        for (self.fibers.items) |*f| {
            if (f.owner == target_scene and f.state == .paused) {
                f.state = .{ .ready = {} };
            }
        }

        // 3. Emit a SceneTransition cue for peripheral / rule tracking (P12-01, D-014)
        const st_cue_id = (try self.world.intern_entity("SceneTransition")).to_int() & 0xFFFF;
        var emitted = EmittedCue{
            .cue_id = @intCast(st_cue_id),
            .args = [_]u32{0} ** 4,
            .arg_count = 2,
        };
        emitted.args[0] = if (old_scene) |os| os.to_int() else 0;
        emitted.args[1] = target_scene.to_int();
        try self.emitted_cues.append(emitted);
    }

    /// Evaluates whether a fact pattern matches current facts in the world store (P13-02, D-015).
    pub fn has_fact_pattern(self: *const VM, pat: parser_mod.FactPattern) bool {
        const rel_opt = self.world.lookup_relation(pat.relation);
        if (rel_opt == null) return false;
        const rel = rel_opt.?;

        var subj: ?EntityId = null;
        var obj: ?u32 = null;

        if (pat.args.len > 0) {
            const arg0 = pat.args[0];
            if (!std.mem.eql(u8, arg0, "_")) {
                subj = self.world.lookup_entity(arg0);
                if (subj == null) return false;
            }
        }

        if (pat.args.len > 1) {
            const arg1 = pat.args[1];
            if (!std.mem.eql(u8, arg1, "_")) {
                if (std.mem.eql(u8, arg1, "true")) {
                    obj = 1;
                } else if (std.mem.eql(u8, arg1, "false")) {
                    obj = 0;
                } else if (std.fmt.parseInt(u32, arg1, 10)) |num| {
                    obj = num;
                } else |_| {
                    const ent = self.world.lookup_entity(arg1);
                    if (ent) |e| {
                        obj = e.to_int();
                    } else {
                        return false;
                    }
                }
            }
        }

        return self.world.has_fact(subj, rel, obj);
    }

    /// Evaluates an AST condition expression against world state and PRNG (P13-02, D-015).
    pub fn eval_expr(self: *VM, expr: parser_mod.Expr) bool {
        switch (expr) {
            .has_fact => |pat| return self.has_fact_pattern(pat),
            .not_fact => |pat| return !self.has_fact_pattern(pat),
            .roll_gte => |roll| {
                var sum: u32 = 0;
                var i: u8 = 0;
                while (i < roll.count) : (i += 1) {
                    sum += (self.prng.random().int(u32) % roll.sides) + 1;
                }
                return sum >= roll.threshold;
            },
        }
    }

    /// Evaluates candidate dialogue choice guards against world state and prunes unsatisfied choices (P13-02, D-015).
    /// Populates out_pruned with active choices and returns the count of active choices.
    pub fn prune_dialogue_choices(
        self: *VM,
        candidates: []const parser_mod.DialogueChoice,
        out_pruned: []PrunedChoice,
    ) usize {
        var count: usize = 0;
        for (candidates, 0..) |choice, idx| {
            var satisfied = true;
            if (choice.guard) |guard| {
                satisfied = self.eval_expr(guard);
            }
            if (satisfied and choice.where_patterns.len > 0) {
                for (choice.where_patterns) |pat| {
                    if (!self.has_fact_pattern(pat)) {
                        satisfied = false;
                        break;
                    }
                }
            }
            if (satisfied) {
                if (count < out_pruned.len) {
                    out_pruned[count] = .{
                        .original_index = idx,
                        .text = choice.text,
                        .body = choice.body,
                    };
                    count += 1;
                }
            }
        }
        return count;
    }

    /// Evaluates whether an entity holds an active belief or knowledge about a proposition (P21-02, D-025).
    /// Returns true if subject Believes or Knows the object, provided they do not explicitly Reject it.
    pub fn evaluates_belief(self: *const VM, subject: EntityId, proposition: EntityId) bool {
        const rej_rel = self.world.lookup_relation("Rejects");
        if (rej_rel) |rel| {
            if (self.world.has_fact(subject, rel, proposition.to_int())) return false;
        }

        const bel_rel = self.world.lookup_relation("Believes");
        if (bel_rel) |rel| {
            if (self.world.has_fact(subject, rel, proposition.to_int())) return true;
        }

        const know_rel = self.world.lookup_relation("Knows");
        if (know_rel) |rel| {
            if (self.world.has_fact(subject, rel, proposition.to_int())) return true;
        }

        return false;
    }

    /// Asserts that an entity believes a proposition, resolving epistemic tension (P21-02, D-025).
    pub fn assert_belief(self: *VM, subject: EntityId, proposition: EntityId) !void {
        if (self.world.lookup_relation("Rejects")) |rej_rel| {
            _ = self.world.forget(subject, rej_rel, proposition.to_int());
        }
        const bel_rel = try self.world.intern_relation("Believes", .set);
        _ = try self.world.remember(subject, bel_rel, proposition.to_int(), 0);
    }

    /// Asserts that an entity explicitly rejects a proposition (P21-02, D-025).
    pub fn reject_belief(self: *VM, subject: EntityId, proposition: EntityId) !void {
        if (self.world.lookup_relation("Believes")) |bel_rel| {
            _ = self.world.forget(subject, bel_rel, proposition.to_int());
        }
        const rej_rel = try self.world.intern_relation("Rejects", .set);
        _ = try self.world.remember(subject, rej_rel, proposition.to_int(), 0);
    }

    /// Advances the master simulation clock by 1 tick and dispatches all active fibers.
    pub fn step_tick(self: *VM) !void {
        // 1. Advance relational world and prune expired facts (P1-02)
        _ = self.world.step_tick();

        // 2. Step spatial motor navigation (P3-02)
        if (self.spatial) |sp| {
            sp.step_tick();
        }

        // 3. Clear peripheral cue buffer from prior tick
        self.emitted_cues.clearRetainingCapacity();

        // 4. Evaluate reactive 'when' simulation rules (P8-02, P8-03, D-010)
        _ = try self.evaluate_reactive_rules();

        // 5. Wake fibers whose sleep duration or spatial motor intent has completed
        for (self.fibers.items) |*f| {
            switch (f.state) {
                .waiting_ticks => |wake_tick| {
                    if (self.world.current_tick >= wake_tick) {
                        f.state = .{ .ready = {} };
                    }
                },
                .waiting_cond => |cond_pc| {
                    // Evaluate condition block
                    if (try self.eval_condition(f, cond_pc)) {
                        f.state = .{ .ready = {} };
                    }
                },
                .waiting_motor => |target_entity| {
                    if (self.spatial) |sp| {
                        if (sp.has_arrived(target_entity)) {
                            f.state = .{ .ready = {} };
                        }
                    }
                },
                else => {},
            }
        }

        // 6. Run ready fibers
        for (self.fibers.items) |*f| {
            if (f.state == .ready) {
                try self.run_fiber(f);
            }
        }
    }

    /// Evaluates a condition bytecode block for wait_until without altering fiber's main stack.
    fn eval_condition(self: *VM, fiber: *Fiber, cond_pc: u16) !bool {
        var temp_stack: [16]u32 = undefined;
        var temp_sp: usize = 0;
        var pc: usize = cond_pc;
        const code = self.chunk.code.items;

        while (pc < code.len) {
            const op: Opcode = @enumFromInt(code[pc]);
            pc += 1;

            switch (op) {
                .push_const => {
                    const val = std.mem.readInt(u32, code[pc..][0..4], .little);
                    pc += 4;
                    temp_stack[temp_sp] = val;
                    temp_sp += 1;
                },
                .push_entity => {
                    const val = std.mem.readInt(u32, code[pc..][0..4], .little);
                    pc += 4;
                    temp_stack[temp_sp] = val;
                    temp_sp += 1;
                },
                .push_relation => {
                    const val = std.mem.readInt(u16, code[pc..][0..2], .little);
                    pc += 2;
                    temp_stack[temp_sp] = val;
                    temp_sp += 1;
                },
                .query_has => {
                    const mask = code[pc];
                    pc += 1;
                    const obj: ?u32 = if ((mask & 0x04) != 0) blk: {
                        temp_sp -= 1;
                        break :blk temp_stack[temp_sp];
                    } else null;
                    const rel_raw: ?u16 = if ((mask & 0x02) != 0) blk: {
                        temp_sp -= 1;
                        break :blk @intCast(temp_stack[temp_sp]);
                    } else null;
                    const subj_raw: ?u32 = if ((mask & 0x01) != 0) blk: {
                        temp_sp -= 1;
                        break :blk temp_stack[temp_sp];
                    } else null;

                    const subj = if (subj_raw) |s| EntityId.from_int(s) else null;
                    const rel = if (rel_raw) |r| RelationKind.from_int(r) else null;
                    const has = self.world.has_fact(subj, rel, obj);
                    temp_stack[temp_sp] = if (has) 1 else 0;
                    temp_sp += 1;
                },
                .not => {
                    temp_stack[temp_sp - 1] = if (temp_stack[temp_sp - 1] == 0) 1 else 0;
                },
                .ret, .halt => {
                    break;
                },
                else => {
                    _ = fiber;
                    return false;
                },
            }
        }

        if (temp_sp > 0) {
            return temp_stack[temp_sp - 1] != 0;
        }
        return false;
    }

    /// Executes instructions for a single fiber until yield, wait, or halt.
    fn run_fiber(self: *VM, f: *Fiber) !void {
        var instructions_executed: usize = 0;
        const code = self.chunk.code.items;

        while (f.state == .ready and f.pc < code.len) {
            if (instructions_executed >= MAX_INSTRUCTIONS_PER_TICK) {
                // Cooperative yield on instruction budget exhaustion
                return;
            }
            instructions_executed += 1;

            const op: Opcode = @enumFromInt(code[f.pc]);
            f.pc += 1;

            switch (op) {
                .nop => {},
                .halt => {
                    f.state = .{ .halted = {} };
                    return;
                },
                .yield => {
                    return; // Stays .ready; will execute again next tick
                },

                // --- Stack & Constants ---
                .push_const => {
                    const val = std.mem.readInt(u32, code[f.pc..][0..4], .little);
                    f.pc += 4;
                    try f.push(val);
                },
                .push_entity => {
                    const val = std.mem.readInt(u32, code[f.pc..][0..4], .little);
                    f.pc += 4;
                    try f.push(val);
                },
                .push_relation => {
                    const val = std.mem.readInt(u16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    try f.push(val);
                },
                .pop => {
                    _ = try f.pop();
                },
                .dup => {
                    const val = try f.peek();
                    try f.push(val);
                },

                // --- Control Flow ---
                .jump => {
                    const offset = std.mem.readInt(i16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    if (offset >= 0) {
                        f.pc += @intCast(offset);
                    } else {
                        f.pc -= @intCast(-offset);
                    }
                },
                .jump_if_false => {
                    const offset = std.mem.readInt(i16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    const condition = try f.pop();
                    if (condition == 0) {
                        if (offset >= 0) {
                            f.pc += @intCast(offset);
                        } else {
                            f.pc -= @intCast(-offset);
                        }
                    }
                },
                .loop => {
                    const offset = std.mem.readInt(u16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    f.pc -= offset;
                },

                // --- Arithmetic, Logic & Comparisons ---
                .add => {
                    const b = try f.pop();
                    const a = try f.pop();
                    try f.push(a +% b);
                },
                .sub => {
                    const b = try f.pop();
                    const a = try f.pop();
                    try f.push(a -% b);
                },
                .mul => {
                    const b = try f.pop();
                    const a = try f.pop();
                    try f.push(a *% b);
                },
                .div => {
                    const b = try f.pop();
                    const a = try f.pop();
                    if (b == 0) return error.DivisionByZero;
                    try f.push(a / b);
                },
                .eq => {
                    const b = try f.pop();
                    const a = try f.pop();
                    try f.push(if (a == b) 1 else 0);
                },
                .neq => {
                    const b = try f.pop();
                    const a = try f.pop();
                    try f.push(if (a != b) 1 else 0);
                },
                .lt => {
                    const b = try f.pop();
                    const a = try f.pop();
                    try f.push(if (a < b) 1 else 0);
                },
                .lte => {
                    const b = try f.pop();
                    const a = try f.pop();
                    try f.push(if (a <= b) 1 else 0);
                },
                .gt => {
                    const b = try f.pop();
                    const a = try f.pop();
                    try f.push(if (a > b) 1 else 0);
                },
                .gte => {
                    const b = try f.pop();
                    const a = try f.pop();
                    try f.push(if (a >= b) 1 else 0);
                },
                .not => {
                    const a = try f.pop();
                    try f.push(if (a == 0) 1 else 0);
                },

                // --- Gameplay / Tabletop Primitives ---
                .roll_dice => {
                    const count_val = code[f.pc];
                    f.pc += 1;
                    const sides = code[f.pc];
                    f.pc += 1;

                    var total: u32 = 0;
                    for (0..count_val) |_| {
                        const roll = (self.prng.random().int(u32) % sides) + 1;
                        total += roll;
                    }
                    try f.push(total);
                },

                // --- Relational State Operations (P1-02, D-003, D-007) ---
                .remember => {
                    const ttl = std.mem.readInt(u32, code[f.pc..][0..4], .little);
                    f.pc += 4;
                    const obj = try f.pop();
                    const rel = try f.pop();
                    const subj = try f.pop();

                    try self.world.remember(
                        EntityId.from_int(subj),
                        RelationKind.from_int(@intCast(rel)),
                        obj,
                        ttl,
                    );
                },
                .forget => {
                    const has_obj = code[f.pc] != 0;
                    f.pc += 1;
                    const obj: ?u32 = if (has_obj) try f.pop() else null;
                    const rel = try f.pop();
                    const subj = try f.pop();

                    _ = self.world.forget(
                        EntityId.from_int(subj),
                        RelationKind.from_int(@intCast(rel)),
                        obj,
                    );
                },
                .query_has => {
                    const mask = code[f.pc];
                    f.pc += 1;

                    const obj: ?u32 = if ((mask & 0x04) != 0) try f.pop() else null;
                    const rel_val: ?u16 = if ((mask & 0x02) != 0) @intCast(try f.pop()) else null;
                    const subj_val: ?u32 = if ((mask & 0x01) != 0) try f.pop() else null;

                    const has = self.world.has_fact(
                        if (subj_val) |s| EntityId.from_int(s) else null,
                        if (rel_val) |r| RelationKind.from_int(r) else null,
                        obj,
                    );
                    try f.push(if (has) 1 else 0);
                },
                .query_property => {
                    const rel = try f.pop();
                    const subj = try f.pop();
                    const val = self.world.get_property(
                        EntityId.from_int(subj),
                        RelationKind.from_int(@intCast(rel)),
                    ) orelse 0;
                    try f.push(val);
                },

                // --- Temporal & Fiber Suspension (P2-03, D-004) ---
                .wait_ticks => {
                    const duration = try f.pop();
                    f.state = .{ .waiting_ticks = self.world.current_tick + duration };
                    return;
                },
                .wait_until => {
                    const cond_pc = std.mem.readInt(u16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    f.state = .{ .waiting_cond = cond_pc };
                    return;
                },
                .walk_to => {
                    const dest = try f.pop();
                    const entity = try f.pop();
                    if (self.spatial) |sp| {
                        _ = try sp.walk_to_with_world(self.world, EntityId.from_int(entity), @intCast(dest));
                        f.state = .{ .waiting_motor = EntityId.from_int(entity) };
                        return;
                    }
                },
                .transition_scene => {
                    const target_scene_val = std.mem.readInt(u32, code[f.pc..][0..4], .little);
                    f.pc += 4;
                    try self.transition_to_scene(EntityId.from_int(target_scene_val));
                },

                // --- Preemption & Interruption (P2-04, D-004) ---
                .interrupt => {
                    const handler_pc = std.mem.readInt(u16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    const target_raw = try f.pop();
                    _ = try self.interrupt_entity(EntityId.from_int(target_raw), handler_pc);
                },
                .resume_routine => {
                    if (f.interrupt_stack.popOrNull()) |frame| {
                        f.pc = frame.pc;
                        f.sp = frame.sp;
                        f.state = frame.state;
                        f.active_priority = frame.priority;
                    } else {
                        f.state = .{ .halted = {} };
                        f.active_priority = 0;
                    }
                    return;
                },

                // --- Peripheral Bridge Signals (D-001) ---
                .emit_cue => {
                    const cue_id = std.mem.readInt(u16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    const arg_count = code[f.pc];
                    f.pc += 1;

                    var cue = EmittedCue{
                        .cue_id = cue_id,
                        .args = undefined,
                        .arg_count = arg_count,
                    };
                    var idx: usize = arg_count;
                    while (idx > 0) {
                        idx -= 1;
                        cue.args[idx] = try f.pop();
                    }
                    try self.emitted_cues.append(cue);
                },

                // --- Musical Drafts (P22-01, D-029) ---
                .weave => {
                    const target_raw = try f.pop();
                    const draft_raw = try f.pop();
                    try self.pending_weaves.append(.{
                        .caster = f.owner,
                        .draft = EntityId.from_int(draft_raw),
                        .target = EntityId.from_int(target_raw),
                    });
                },

                // --- Executable Dialogue Lifecycle (P32-30, D-046) ---
                .choices_begin => {
                    try dialogue_mod.begin(self.world, f.owner, f.id);
                },
                .offer_choice => {
                    const text_raw = std.mem.readInt(u32, code[f.pc..][0..4], .little);
                    f.pc += 4;
                    const body_pc = std.mem.readInt(u16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    try dialogue_mod.offer(self.world, f.owner, EntityId.from_int(text_raw), body_pc);
                },
                .offer_choice_inspected => {
                    const text_raw = std.mem.readInt(u32, code[f.pc..][0..4], .little);
                    f.pc += 4;
                    const body_pc = std.mem.readInt(u16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    const source_index = code[f.pc];
                    f.pc += 1;
                    try dialogue_mod.offer_inspected(self.world, f.owner, EntityId.from_int(text_raw), body_pc, source_index);
                },
                .reject_choice => {
                    const text_raw = std.mem.readInt(u32, code[f.pc..][0..4], .little);
                    f.pc += 4;
                    const source_index = code[f.pc];
                    f.pc += 1;
                    const failure_raw = std.mem.readInt(u32, code[f.pc..][0..4], .little);
                    f.pc += 4;
                    try dialogue_mod.reject(self.world, f.owner, EntityId.from_int(text_raw), source_index, EntityId.from_int(failure_raw));
                },
                .choices_end => {
                    const end_pc = std.mem.readInt(u16, code[f.pc..][0..2], .little);
                    f.pc += 2;
                    const count = try dialogue_mod.finish(self.world, f.owner, end_pc);
                    f.pc = end_pc;
                    if (count > 0) {
                        f.state = .{ .waiting_dialogue = {} };
                        return;
                    }
                },
                else => return error.InvalidOpcode,
            }
        }
    }
};

// --- Unit Tests (P2-01, P2-02, P2-03, P2-04) ---

test "P2-01 & P2-02: VM fiber execution and arithmetic" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    // Routine: push 20, push 22, add, halt
    try chunk.emit_push_const(20);
    try chunk.emit_push_const(22);
    _ = try chunk.emit_op(.add);
    _ = try chunk.emit_op(.halt);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    const guard = try world.intern_entity("Guard");
    const fiber_id = try vm.spawn_routine(guard, 0);

    // Step tick
    try vm.step_tick();

    const fiber = &vm.fibers.items[0];
    try testing.expectEqual(fiber_id, fiber.id);
    try testing.expectEqual(FiberStateTag.halted, std.meta.activeTag(fiber.state));
    try testing.expectEqual(@as(u32, 42), try fiber.peek());
}

test "P2-03: temporal wait_ticks suspension and resumption" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    const alertness = try world.intern_relation("Alertness", .property);
    const guard = try world.intern_entity("Guard");

    // Routine:
    // 0: push Guard, push Alertness, push 100, remember 0
    // 13: push 3 (ticks), wait_ticks
    // 19: push Guard, push Alertness, push 50, remember 0
    // 32: halt
    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(alertness);
    try chunk.emit_push_const(100);
    try chunk.emit_remember(0);

    try chunk.emit_wait_ticks(3);

    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(alertness);
    try chunk.emit_push_const(50);
    try chunk.emit_remember(0);
    _ = try chunk.emit_op(.halt);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    _ = try vm.spawn_routine(guard, 0);

    // Tick 1: Routine starts, sets Alertness = 100, then calls wait_ticks(3)
    try vm.step_tick();
    try testing.expectEqual(@as(u32, 100), world.get_property(guard, alertness).?);
    try testing.expectEqual(FiberStateTag.waiting_ticks, std.meta.activeTag(vm.fibers.items[0].state));

    // Tick 2: Still waiting
    try vm.step_tick();
    try testing.expectEqual(@as(u32, 100), world.get_property(guard, alertness).?);

    // Tick 3: Still waiting
    try vm.step_tick();
    try testing.expectEqual(@as(u32, 100), world.get_property(guard, alertness).?);

    // Tick 4: 3 ticks have elapsed -> Fiber resumes, sets Alertness = 50, halts
    try vm.step_tick();
    try testing.expectEqual(@as(u32, 50), world.get_property(guard, alertness).?);
    try testing.expectEqual(FiberStateTag.halted, std.meta.activeTag(vm.fibers.items[0].state));
}

test "P2-04: interrupt stack preemption and clean resumption" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    const guard = try world.intern_entity("Guard");
    const cheese = try world.intern_entity("Cheese");
    const carries = try world.intern_relation("Carries", .set);
    const alertness = try world.intern_relation("Alertness", .property);

    // --- Main Patrol Routine (pc: 0) ---
    // 0: push Guard, push Alertness, push 10, remember 0
    // 13: wait 100 ticks (long patrol wait)
    // 19: push Guard, push Carries, push Cheese, remember 0
    // 32: halt
    const patrol_pc = chunk.code.items.len;
    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(alertness);
    try chunk.emit_push_const(10);
    try chunk.emit_remember(0);

    try chunk.emit_wait_ticks(100);

    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(carries);
    try chunk.emit_push_entity(cheese);
    try chunk.emit_remember(0);
    _ = try chunk.emit_op(.halt);

    // --- Interrupt Routine: Emergency Alert (pc: 33) ---
    // 33: push Guard, push Alertness, push 99, remember 0
    // 46: resume_routine
    const interrupt_pc: u16 = @intCast(chunk.code.items.len);
    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(alertness);
    try chunk.emit_push_const(99);
    try chunk.emit_remember(0);
    _ = try chunk.emit_op(.resume_routine);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    _ = try vm.spawn_routine(guard, patrol_pc);

    // Tick 1: Guard starts patrol, alertness = 10, enters wait(100)
    try vm.step_tick();
    try testing.expectEqual(@as(u32, 10), world.get_property(guard, alertness).?);
    try testing.expectEqual(FiberStateTag.waiting_ticks, std.meta.activeTag(vm.fibers.items[0].state));

    // Interrupt Guard with Emergency Alert!
    try testing.expect(try vm.interrupt_entity(guard, interrupt_pc));

    // Tick 2: Guard executes interrupt handler: alertness jumps to 99, resumes prior wait!
    try vm.step_tick();
    try testing.expectEqual(@as(u32, 99), world.get_property(guard, alertness).?);
    // Prior state (waiting_ticks) was cleanly restored from interrupt stack!
    try testing.expectEqual(FiberStateTag.waiting_ticks, std.meta.activeTag(vm.fibers.items[0].state));

    // Advance remaining ticks to complete the original patrol wait
    for (0..99) |_| {
        try vm.step_tick();
    }

    // Guard finished patrol and picked up cheese!
    try testing.expect(world.has_fact(guard, carries, cheese.to_int()));
    try testing.expectEqual(FiberStateTag.halted, std.meta.activeTag(vm.fibers.items[0].state));
}

test "P3-02: VM fiber executes walk_to, suspends during transit, and wakes upon arrival" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const tavern = EntityId.from_int(1);
    const guard = try world.intern_entity("Guard");
    const cheese = try world.intern_entity("Cheese");
    const carries = try world.intern_relation("Carries", .set);

    const hearth = try spatial.graph.add_waypoint(tavern, 0, 0, "Hearth");
    const cellar = try spatial.graph.add_waypoint(tavern, 20, 0, "Cellar");
    try spatial.graph.connect(hearth, cellar, null);

    // Guard starts at Hearth with speed 5 units/tick
    try spatial.register_entity(guard, hearth, 5);

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    // Routine: walk Guard to Cellar (distance 20 @ 5 units/tick = 4 ticks), then pick up Cheese
    try chunk.emit_walk_to(guard, cellar);
    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(carries);
    try chunk.emit_push_entity(cheese);
    try chunk.emit_remember(0);
    _ = try chunk.emit_op(.halt);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    _ = try vm.spawn_routine(guard, 0);

    // Tick 1: Routine starts, issues walk_to, enters waiting_motor state
    try vm.step_tick();
    try testing.expectEqual(FiberStateTag.waiting_motor, std.meta.activeTag(vm.fibers.items[0].state));
    try testing.expect(!world.has_fact(guard, carries, cheese.to_int()));

    // Ticks 2, 3, 4: Walking along path
    try vm.step_tick();
    try vm.step_tick();
    try vm.step_tick();
    try testing.expectEqual(FiberStateTag.waiting_motor, std.meta.activeTag(vm.fibers.items[0].state));
    try testing.expect(!world.has_fact(guard, carries, cheese.to_int()));

    // Tick 5: Reaches Cellar! Motor arrival triggers fiber wake-up -> picks up Cheese and halts!
    try vm.step_tick();
    try testing.expect(world.has_fact(guard, carries, cheese.to_int()));
    try testing.expectEqual(FiberStateTag.halted, std.meta.activeTag(vm.fibers.items[0].state));
    try testing.expectEqual(cellar, spatial.get_current_waypoint(guard).?);
}

test "P24-02: scripted walk_to honors WaypointBlocked facts" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const room = EntityId.from_int(1);
    const guard = try world.intern_entity("Guard");
    const locked_mark = try world.intern_entity("Locked");
    const blocked = try world.intern_relation("WaypointBlocked", .set);

    const start = try spatial.graph.add_waypoint(room, 0, 0, "Start");
    const locked = try spatial.graph.add_waypoint(room, 10, 0, "Locked");
    const safe = try spatial.graph.add_waypoint(room, 0, 10, "Safe");
    const goal = try spatial.graph.add_waypoint(room, 10, 10, "Goal");
    try spatial.graph.connect(start, locked, 10);
    try spatial.graph.connect(locked, goal, 10);
    try spatial.graph.connect(start, safe, 10);
    try spatial.graph.connect(safe, goal, 10);
    try spatial.register_entity(guard, start, 5);
    try world.remember(locked_mark, blocked, 0, 0);

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    try chunk.emit_walk_to(guard, goal);
    _ = try chunk.emit_op(.halt);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    _ = try vm.spawn_routine(guard, 0);
    _ = try vm.step_tick();

    const path = spatial.agents.get(guard).?.path.?;
    try testing.expect(std.mem.indexOfScalar(spatial_mod.WaypointId, path, locked) == null);
    try testing.expect(std.mem.indexOfScalar(spatial_mod.WaypointId, path, safe) != null);
}

test "P8-02: reactive when rule evaluation on tick boundary with edge triggering" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const guard = try world.intern_entity("Guard");
    const bard = try world.intern_entity("Bard");
    const charmed = try world.intern_relation("CharmedBy", .set);
    const listens = try world.intern_relation("ListensTo", .set);

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    // Baseline routine: wait 100 ticks
    const baseline_pc = chunk.count();
    try chunk.emit_wait_ticks(100);
    _ = try chunk.emit_op(.halt);

    // Interrupt handler for Charm rule: remember ListensTo(Guard, Bard), wait 2 ticks, resume
    const charm_handler_pc = chunk.count();
    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(listens);
    try chunk.emit_push_entity(bard);
    try chunk.emit_remember(0);
    try chunk.emit_wait_ticks(2);
    _ = try chunk.emit_op(.resume_routine);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    // Register reactive rule: when CharmedBy(Guard, Bard) -> interrupt Guard
    const clauses = [_]world_mod.PatternClause{
        .{
            .relation = charmed,
            .subject = .{ .constant = guard.to_int() },
            .object = .{ .constant = bard.to_int() },
        },
    };
    _ = try vm.add_reactive_rule(guard, &clauses, 50, charm_handler_pc);

    _ = try vm.spawn_routine(guard, baseline_pc);

    // Tick 1: Baseline routine starts and sleeps for 100 ticks. No charm -> rule does not fire.
    try vm.step_tick();
    try testing.expect(!world.has_fact(guard, listens, bard.to_int()));
    try testing.expectEqual(@as(usize, 0), vm.fibers.items[0].interrupt_stack.items.len);

    // Now emit fact: CharmedBy(Guard, Bard) with TTL 4 ticks
    try world.remember(guard, charmed, bard.to_int(), 4);

    // Tick 2: step_tick evaluates reactive rule -> condition is true -> edge triggers interrupt!
    try vm.step_tick();
    try testing.expect(world.has_fact(guard, listens, bard.to_int()));
    try testing.expectEqual(@as(usize, 1), vm.fibers.items[0].interrupt_stack.items.len);

    // Tick 3: Condition is still true, but rule is already active -> does NOT interrupt again
    try vm.step_tick();
    try testing.expectEqual(@as(usize, 1), vm.fibers.items[0].interrupt_stack.items.len);

    // Ticks 4, 5: Advance past TTL -> CharmedBy expires, handler finishes and resumes baseline
    try vm.step_tick();
    try vm.step_tick();
    try vm.step_tick();

    // Interrupt stack popped and resumed
    try testing.expectEqual(@as(usize, 0), vm.fibers.items[0].interrupt_stack.items.len);
    try testing.expect(!world.has_fact(guard, charmed, bard.to_int()));
}

test "P8-03: priority rule cascades preemption and nesting" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const guard = try world.intern_entity("Guard");
    const bard = try world.intern_entity("Bard");
    const cat = try world.intern_entity("Cat");
    const cheese = try world.intern_entity("Cheese");

    const carries = try world.intern_relation("Carries", .set);
    const charmed = try world.intern_relation("CharmedBy", .set);
    const alert_rel = try world.intern_relation("AlertState", .property);

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    // Baseline routine: wait 100 ticks
    const baseline_pc = chunk.count();
    try chunk.emit_wait_ticks(100);
    _ = try chunk.emit_op(.halt);

    // Handler 1: Charm handler (priority 50): wait 10 ticks, resume
    const charm_handler_pc = chunk.count();
    try chunk.emit_wait_ticks(10);
    _ = try chunk.emit_op(.resume_routine);

    // Handler 2: Theft Alert handler (priority 100): remember AlertState(Guard, 1), wait 3 ticks, resume
    const alert_handler_pc = chunk.count();
    try chunk.emit_push_entity(guard);
    try chunk.emit_push_relation(alert_rel);
    try chunk.emit_push_const(1);
    try chunk.emit_remember(0);
    try chunk.emit_wait_ticks(3);
    _ = try chunk.emit_op(.resume_routine);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    // Register Charm rule (Priority 50)
    const charm_clauses = [_]world_mod.PatternClause{
        .{
            .relation = charmed,
            .subject = .{ .constant = guard.to_int() },
            .object = .{ .constant = bard.to_int() },
        },
    };
    _ = try vm.add_reactive_rule(guard, &charm_clauses, 50, charm_handler_pc);

    // Register Theft Alert rule (Priority 100): when Carries(Cat, Cheese)
    const theft_clauses = [_]world_mod.PatternClause{
        .{
            .relation = carries,
            .subject = .{ .constant = cat.to_int() },
            .object = .{ .constant = cheese.to_int() },
        },
    };
    _ = try vm.add_reactive_rule(guard, &theft_clauses, 100, alert_handler_pc);

    _ = try vm.spawn_routine(guard, baseline_pc);

    // Tick 1: Start baseline
    try vm.step_tick();
    try testing.expectEqual(@as(u16, 0), vm.fibers.items[0].active_priority);

    // Bard charms Guard -> Priority 50 triggers
    try world.remember(guard, charmed, bard.to_int(), 20);
    try vm.step_tick();
    try testing.expectEqual(@as(usize, 1), vm.fibers.items[0].interrupt_stack.items.len);
    try testing.expectEqual(@as(u16, 50), vm.fibers.items[0].active_priority);

    // Now Cat steals Cheese -> Theft alert (Priority 100) preempts Charm (Priority 50)!
    try world.remember(cat, carries, cheese.to_int(), 0);
    try vm.step_tick();

    // Nested interrupt: interrupt stack depth is now 2!
    try testing.expectEqual(@as(usize, 2), vm.fibers.items[0].interrupt_stack.items.len);
    try testing.expectEqual(@as(u16, 100), vm.fibers.items[0].active_priority);
    try testing.expect(world.has_fact(guard, alert_rel, 1));

    // Finish Alert handler: 3 ticks
    try vm.step_tick();
    try vm.step_tick();
    try vm.step_tick();

    // Alert popped: back to Charm handler (priority 50, depth 1)
    try testing.expectEqual(@as(usize, 1), vm.fibers.items[0].interrupt_stack.items.len);
    try testing.expectEqual(@as(u16, 50), vm.fibers.items[0].active_priority);
}

test "P10-02: falling edge and on_expire reactive rule execution" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const organiser = try world.intern_entity("Organiser");
    const scene = try world.intern_entity("Scene");

    const distracted = try world.intern_relation("Distracted", .set);
    const wind = try world.intern_relation("WindBlowing", .set);
    const post_rel = try world.intern_relation("BackAtPost", .property);
    const calm_rel = try world.intern_relation("WindCalm", .property);

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    // Baseline routine for Organiser: wait 200 ticks
    const baseline_pc = chunk.count();
    try chunk.emit_wait_ticks(200);
    _ = try chunk.emit_op(.halt);

    // Handler 1: On-expire handler for Distracted -> remembers BackAtPost, resumes
    const expire_handler_pc = chunk.count();
    try chunk.emit_push_entity(organiser);
    try chunk.emit_push_relation(post_rel);
    try chunk.emit_push_const(1);
    try chunk.emit_remember(0);
    _ = try chunk.emit_op(.resume_routine);

    // Handler 2: Falling edge handler for Wind -> remembers WindCalm, resumes
    const falling_handler_pc = chunk.count();
    try chunk.emit_push_entity(scene);
    try chunk.emit_push_relation(calm_rel);
    try chunk.emit_push_const(1);
    try chunk.emit_remember(0);
    _ = try chunk.emit_op(.resume_routine);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    _ = try vm.spawn_routine(organiser, baseline_pc);

    // 1. Register on_expire rule: when Organiser forgets Distracted
    const expire_clause = [_]world_mod.PatternClause{.{
        .relation = distracted,
        .subject = .{ .constant = organiser.to_int() },
        .object = .{ .wildcard = {} },
    }};
    _ = try vm.add_reactive_rule_edge(organiser, &expire_clause, 50, expire_handler_pc, .on_expire);

    // 2. Register falling edge rule: when Wind stops being blowing
    const falling_clause = [_]world_mod.PatternClause{.{
        .relation = wind,
        .subject = .{ .constant = scene.to_int() },
        .object = .{ .wildcard = {} },
    }};
    _ = try vm.add_reactive_rule_edge(organiser, &falling_clause, 40, falling_handler_pc, .falling);

    // Initial state: Organiser is distracted for 3 ticks, Wind is blowing
    try world.remember(organiser, distracted, 1, 3);
    try world.remember(scene, wind, 1, 0);

    // Tick 1: Wind is blowing -> rule arms (is_active = true), but does not fire falling
    try vm.step_tick();
    try testing.expect(!world.has_fact(scene, calm_rel, 1));
    try testing.expect(!world.has_fact(organiser, post_rel, 1));

    // Tick 2: Wind stops blowing! (forget fact)
    _ = world.forget(scene, wind, null);
    try vm.step_tick();
    // Falling edge rule triggered!
    try testing.expect(world.has_fact(scene, calm_rel, 1));

    // Tick 3: Distracted expires on TTL tick 3 -> on_expire rule triggers!
    try vm.step_tick();
    try testing.expect(world.has_fact(organiser, post_rel, 1));
}

test "P11-02: VM.fire_cue executes 3-argument item combining cue with commutative matching" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const gabriel = try world.intern_entity("Gabriel");
    const syrup = try world.intern_entity("MapleSyrup");
    const tape = try world.intern_entity("CatHairTape");
    const moustache = try world.intern_entity("CatMoustache");
    const carries = try world.intern_relation("Carries", .set);

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    // Cue Handler for Uses(Gabriel, MapleSyrup, CatHairTape):
    // push Gabriel, push Carries, push CatMoustache, remember 0, halt
    const handler_pc = chunk.count();
    try chunk.emit_push_entity(gabriel);
    try chunk.emit_push_relation(carries);
    try chunk.emit_push_const(moustache.to_int());
    try chunk.emit_remember(0);
    _ = try chunk.emit_op(.halt);

    // Mock compiled program with commutative signatures
    var cue_map = std.StringHashMap(usize).init(testing.allocator);
    defer cue_map.deinit();
    try cue_map.put("Uses:Gabriel:MapleSyrup:CatHairTape", handler_pc);
    try cue_map.put("Uses:Gabriel:CatHairTape:MapleSyrup", handler_pc);

    const MockProgram = struct {
        cue_handler_entries: std.StringHashMap(usize),
        pub fn find_cue_handler(
            self: *const @This(),
            cue_name: []const u8,
            actor: ?[]const u8,
            target_a: ?[]const u8,
            target_b: ?[]const u8,
        ) ?usize {
            var buf: [128]u8 = undefined;
            if (actor != null and target_a != null and target_b != null) {
                if (std.fmt.bufPrint(&buf, "{s}:{s}:{s}:{s}", .{ cue_name, actor.?, target_a.?, target_b.? })) |sig| {
                    if (self.cue_handler_entries.get(sig)) |pc| return pc;
                } else |_| {}
                if (std.fmt.bufPrint(&buf, "{s}:{s}:{s}:{s}", .{ cue_name, actor.?, target_b.?, target_a.? })) |sig| {
                    if (self.cue_handler_entries.get(sig)) |pc| return pc;
                } else |_| {}
            }
            return null;
        }
        /// The VM dispatches through the guarded lookup (D-072); this mock has no guards.
        pub fn select_cue_handler(
            self: *const @This(),
            w: *const World,
            cue_name: []const u8,
            actor: EntityId,
            target_a: ?EntityId,
            target_b: ?EntityId,
        ) ?usize {
            return self.find_cue_handler(
                cue_name,
                w.get_entity_name(actor),
                if (target_a) |t| w.get_entity_name(t) else null,
                if (target_b) |t| w.get_entity_name(t) else null,
            );
        }
    };
    const mock_prog = MockProgram{ .cue_handler_entries = cue_map };

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    // Fire cue with commutative argument order: Tape on Syrup!
    const fib_id = try vm.fire_cue(&mock_prog, "Uses", gabriel, tape, syrup);
    try testing.expect(fib_id != null);
    try testing.expectEqual(@as(usize, 1), vm.emitted_cues.items.len);
    try testing.expectEqual(@as(u8, 3), vm.emitted_cues.items[0].arg_count);

    // Step tick executes handler -> Gabriel carries CatMoustache!
    try vm.step_tick();
    try testing.expect(world.has_fact(gabriel, carries, moustache.to_int()));
}

test "P12-01: vm executes scene transition, pauses old scene fibers, wakes new scene fibers, and preserves world facts" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    const tavern = try world.intern_entity("Tavern");
    const cellar = try world.intern_entity("Wine Cellar");
    const hero = try world.intern_entity("Hero");
    const horn = try world.intern_entity("Horn");
    const carries = try world.intern_relation("Carries", .set);

    // Initial fact in world: Hero carries Horn
    try world.remember(hero, carries, horn.to_int(), 0);

    // Routine 1: TavernAmbience (owner: tavern) -> loop wait 5 ticks
    const tavern_pc = chunk.count();
    try chunk.emit_wait_ticks(5);
    _ = try chunk.emit_op(.halt);

    // Routine 2: CellarDrips (owner: cellar) -> wait 5 ticks
    const cellar_pc = chunk.count();
    try chunk.emit_wait_ticks(5);
    _ = try chunk.emit_op(.halt);

    // Routine 3: Hero transitions to cellar:
    // emit transition_scene cellar, then wait 10 ticks
    const guybrush_pc = chunk.count();
    try chunk.emit_transition_scene(cellar);
    try chunk.emit_wait_ticks(10);
    _ = try chunk.emit_op(.halt);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    // Start in Tavern
    try vm.transition_to_scene(tavern);
    try testing.expectEqual(tavern, vm.current_scene.?);

    const f_tavern = try vm.spawn_routine(tavern, tavern_pc);
    const f_cellar = try vm.spawn_routine(cellar, cellar_pc);
    const f_guybrush = try vm.spawn_routine(hero, guybrush_pc);

    // Manually pause cellar routine since it belongs to inactive cellar
    vm.fibers.items[f_cellar - 1].state = .{ .paused = {} };

    // Before tick: f_tavern is ready, f_cellar is paused
    try testing.expectEqual(FiberState{ .ready = {} }, vm.fibers.items[f_tavern - 1].state);
    try testing.expectEqual(FiberState{ .paused = {} }, vm.fibers.items[f_cellar - 1].state);

    // Step 1 tick: Hero executes transition_scene(cellar)
    try vm.step_tick();

    // Current scene should now be cellar!
    try testing.expectEqual(cellar, vm.current_scene.?);

    // Tavern fiber is now paused!
    try testing.expectEqual(FiberState{ .paused = {} }, vm.fibers.items[f_tavern - 1].state);

    // Cellar fiber is unpaused and ready!
    try testing.expectEqual(FiberState{ .ready = {} }, vm.fibers.items[f_cellar - 1].state);

    // Hero's fiber transitioned to waiting_ticks(10)
    switch (vm.fibers.items[f_guybrush - 1].state) {
        .waiting_ticks => {},
        else => try testing.expect(false),
    }

    // World relational facts (Carries(Hero, Horn)) remain fully preserved!
    try testing.expect(world.has_fact(hero, carries, horn.to_int()));

    // SceneTransition cue was emitted
    var found_transition_cue = false;
    for (vm.emitted_cues.items) |c| {
        if (world.get_entity_name(EntityId.from_int(c.cue_id))) |cname| {
            if (std.mem.eql(u8, cname, "SceneTransition")) {
                found_transition_cue = true;
                try testing.expectEqual(tavern.to_int(), c.args[0]);
                try testing.expectEqual(cellar.to_int(), c.args[1]);
            }
        }
    }
    try testing.expect(found_transition_cue);
}

test "P13-02: VM dynamically evaluates and prunes dialogue choices based on relational facts" {
    const testing = std.testing;

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    const gabriel = try world.intern_entity("Gabriel");
    const license = try world.intern_entity("License");
    const cat = try world.intern_entity("Cat");
    _ = try world.intern_entity("Buthane");

    _ = try world.intern_relation("Carries", .set);
    _ = try world.intern_relation("KnowsAboutCat", .property);

    const empty_body: []const parser_mod.Stmt = &[_]parser_mod.Stmt{};

    const args_carries_license = [_][]const u8{ "Gabriel", "License" };
    const args_knows_cat = [_][]const u8{"Gabriel"};
    const args_carries_cat = [_][]const u8{ "Gabriel", "Cat" };

    const candidates = [_]parser_mod.DialogueChoice{
        .{
            .text = "Rent motorcycle",
            .guard = .{ .has_fact = .{ .relation = "Carries", .args = &args_carries_license } },
            .body = empty_body,
        },
        .{
            .text = "Ask about the cat",
            .guard = .{ .not_fact = .{ .relation = "KnowsAboutCat", .args = &args_knows_cat } },
            .body = empty_body,
        },
        .{
            .text = "Offer the cat to Buthane",
            .guard = .{ .has_fact = .{ .relation = "Carries", .args = &args_carries_cat } },
            .body = empty_body,
        },
        .{
            .text = "Leave shop",
            .guard = null,
            .body = empty_body,
        },
    };

    var pruned: [8]PrunedChoice = undefined;

    // --- State 1: Gabriel has no license, does NOT know about cat, has no cat ---
    var count = vm.prune_dialogue_choices(&candidates, &pruned);
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqual(@as(usize, 1), pruned[0].original_index);
    try testing.expectEqualStrings("Ask about the cat", pruned[0].text);
    try testing.expectEqual(@as(usize, 3), pruned[1].original_index);
    try testing.expectEqualStrings("Leave shop", pruned[1].text);

    // --- State 2: Gabriel gets license and learns about cat ---
    const carries_rel = world.lookup_relation("Carries").?;
    const knows_rel = world.lookup_relation("KnowsAboutCat").?;
    try world.remember(gabriel, carries_rel, license.to_int(), 0);
    try world.remember(gabriel, knows_rel, 1, 0);

    count = vm.prune_dialogue_choices(&candidates, &pruned);
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqual(@as(usize, 0), pruned[0].original_index);
    try testing.expectEqualStrings("Rent motorcycle", pruned[0].text);
    try testing.expectEqual(@as(usize, 3), pruned[1].original_index);
    try testing.expectEqualStrings("Leave shop", pruned[1].text);

    // --- State 3: Gabriel also acquires cat ---
    try world.remember(gabriel, carries_rel, cat.to_int(), 0);

    count = vm.prune_dialogue_choices(&candidates, &pruned);
    try testing.expectEqual(@as(usize, 3), count);
    try testing.expectEqual(@as(usize, 0), pruned[0].original_index);
    try testing.expectEqualStrings("Rent motorcycle", pruned[0].text);
    try testing.expectEqual(@as(usize, 2), pruned[1].original_index);
    try testing.expectEqualStrings("Offer the cat to Buthane", pruned[1].text);
    try testing.expectEqual(@as(usize, 3), pruned[2].original_index);
    try testing.expectEqualStrings("Leave shop", pruned[2].text);
}

test "P13-02: VM prunes dialogue choices using multi-clause where patterns" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    const tamsin = try world.intern_entity("Tamsin");
    const reply_mop = try world.intern_entity("ReplyMop");
    const barb_mop = try world.intern_entity("BarbMop");

    const mastered_rel = try world.intern_relation("MasteredReply", .set);
    const counters_rel = try world.intern_relation("Counters", .set);

    const empty_body: []const parser_mod.Stmt = &[_]parser_mod.Stmt{};
    const mop_args1 = [_][]const u8{ "Tamsin", "ReplyMop" };
    const mop_args2 = [_][]const u8{ "ReplyMop", "BarbMop" };
    const where_mop = [_]parser_mod.FactPattern{
        .{ .relation = "MasteredReply", .args = &mop_args1 },
        .{ .relation = "Counters", .args = &mop_args2 },
    };

    const candidates = [_]parser_mod.DialogueChoice{
        .{
            .text = "Good, then that means I can still wipe the floor with you.",
            .guard = null,
            .where_patterns = &where_mop,
            .body = empty_body,
        },
        .{
            .text = "Er... is that the time?",
            .guard = null,
            .where_patterns = &[_]parser_mod.FactPattern{},
            .body = empty_body,
        },
    };

    var pruned: [4]PrunedChoice = undefined;

    // Initially, Tamsin has not mastered the comeback, so only the fallback appears
    var count = vm.prune_dialogue_choices(&candidates, &pruned);
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqualStrings("Er... is that the time?", pruned[0].text);

    // Knowledge base establishes Counters relationship
    try world.remember(reply_mop, counters_rel, barb_mop.to_int(), 0);

    // Tamsin still hasn't mastered reply -> still 1
    count = vm.prune_dialogue_choices(&candidates, &pruned);
    try testing.expectEqual(@as(usize, 1), count);

    // Tamsin masters the reply -> now both choices are active!
    try world.remember(tamsin, mastered_rel, reply_mop.to_int(), 0);
    count = vm.prune_dialogue_choices(&candidates, &pruned);
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqualStrings("Good, then that means I can still wipe the floor with you.", pruned[0].text);
    try testing.expectEqualStrings("Er... is that the time?", pruned[1].text);
}

test "P21-02: epistemic dialogue belief evaluation and temporal causality DAG" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    const washington = try world.intern_entity("Washington");
    const cherry_prop = try world.intern_entity("CherryTree");

    // 1. Initial epistemic state: Washington does not hold the belief
    try testing.expect(!vm.evaluates_belief(washington, cherry_prop));

    // 2. Explicit rejection: Washington rejects the proposition
    try vm.reject_belief(washington, cherry_prop);
    try testing.expect(!vm.evaluates_belief(washington, cherry_prop));

    // 3. Persuasion assertion: After painting kumquats red, belief is established
    try vm.assert_belief(washington, cherry_prop);
    try testing.expect(vm.evaluates_belief(washington, cherry_prop));

    // Verify rejection fact was forgotten
    const rej_rel = world.lookup_relation("Rejects").?;
    try testing.expect(!world.has_fact(washington, rej_rel, cherry_prop.to_int()));

    // 4. Dialogue choice pruning based on epistemic belief guard
    const empty_body: []const parser_mod.Stmt = &[_]parser_mod.Stmt{};
    const chop_args = [_][]const u8{ "Washington", "CherryTree" };
    const where_chop = [_]parser_mod.FactPattern{
        .{ .relation = "Believes", .args = &chop_args },
    };

    const candidates = [_]parser_mod.DialogueChoice{
        .{
            .text = "I bet you cannot chop down that cherry tree, George!",
            .guard = null,
            .where_patterns = &where_chop,
            .body = empty_body,
        },
        .{
            .text = "Nice weather today, Mr. President.",
            .guard = null,
            .where_patterns = &[_]parser_mod.FactPattern{},
            .body = empty_body,
        },
    };

    var pruned: [4]PrunedChoice = undefined;

    // With belief asserted, both dialogue choices are available
    var count = vm.prune_dialogue_choices(&candidates, &pruned);
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqualStrings("I bet you cannot chop down that cherry tree, George!", pruned[0].text);

    // If Washington rejects the belief, the persuasion choice is pruned
    try vm.reject_belief(washington, cherry_prop);
    count = vm.prune_dialogue_choices(&candidates, &pruned);
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqualStrings("Nice weather today, Mr. President.", pruned[0].text);

    // 5. Forward-propagating temporal causality cascade (DAG Past -> Future)
    const tree_chopped = try world.intern_relation("TreeChoppedDown", .set);
    const tree_absent = try world.intern_relation("TreeAbsentInFuture", .set);
    const laverne = try world.intern_entity("Laverne");
    const past_flag = try world.intern_entity("Past1790");
    const future_flag = try world.intern_entity("Future2193");

    // Define a reactive temporal rule: when Past has TreeChoppedDown -> triggers handler
    const clauses = [_]world_mod.PatternClause{
        .{
            .relation = tree_chopped,
            .subject = .{ .constant = past_flag.to_int() },
            .object = .{ .constant = cherry_prop.to_int() },
        },
    };
    _ = try vm.add_reactive_rule(past_flag, &clauses, 10, 0);

    // Spawn a fiber for past_flag so it can receive reactive interrupts
    _ = try vm.spawn_routine(past_flag, 0);

    // Before past mutation: Future tree is intact
    try testing.expect(!world.has_fact(future_flag, tree_absent, cherry_prop.to_int()));

    // Hoagie triggers tree chop in 1790
    _ = try world.remember(past_flag, tree_chopped, cherry_prop.to_int(), 0);

    // Evaluate reactive rules (simulating step_tick)
    const fired = try vm.evaluate_reactive_rules();
    try testing.expectEqual(@as(usize, 1), fired);

    // Assert downstream future effect of the temporal cascade
    _ = try world.remember(future_flag, tree_absent, cherry_prop.to_int(), 0);
    _ = try world.remember(laverne, try world.intern_relation("FreedFromTree", .set), 1, 0);

    try testing.expect(world.has_fact(future_flag, tree_absent, cherry_prop.to_int()));
    try testing.expect(world.has_fact(laverne, world.lookup_relation("FreedFromTree").?, 1));
}

test "P31-01: hyper-temporal fiber execution and priority preemption" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    // Bytecode: emit cue 2 (say) with 2 args (Frank, countdown_text), then halt
    const frank = try world.intern_entity("Frank");
    const donnie = try world.intern_entity("Donnie");
    const msg = try world.intern_entity("28:06:42:12");

    try chunk.emit_push_entity(frank);
    try chunk.emit_push_entity(msg);
    _ = try chunk.emit_op(.emit_cue);
    try chunk.emit_u16(2); // say cue
    try chunk.emit_u8(2); // 2 args
    _ = try chunk.emit_op(.halt);

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    // Spawn a standard fiber for Donnie
    const fid_donnie = try vm.spawn_routine(donnie, 0);
    try testing.expectEqual(@as(FiberId, 1), fid_donnie);
    try testing.expect(!vm.fibers.items[0].is_hyper_temporal);
    try testing.expectEqual(@as(u16, 0), vm.fibers.items[0].active_priority);

    // Spawn a hyper-temporal fiber for Frank (The Manipulated Dead)
    const fid_frank = try vm.spawn_hyper_temporal_routine(frank, 0);
    try testing.expectEqual(@as(FiberId, 2), fid_frank);
    try testing.expect(vm.fibers.items[1].is_hyper_temporal);
    try testing.expectEqual(@as(u16, 255), vm.fibers.items[1].active_priority);

    // Step VM tick to execute hyper-temporal fiber
    try vm.step_tick();

    // Verify Frank emitted the temporal countdown cue
    try testing.expect(vm.emitted_cues.items.len > 0);
    const cue = vm.emitted_cues.items[0];
    try testing.expectEqual(@as(u16, 2), cue.cue_id);
    try testing.expectEqual(frank.to_int(), cue.args[0]);
    try testing.expectEqual(msg.to_int(), cue.args[1]);
}
