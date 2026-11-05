const std = @import("std");
const world_mod = @import("world.zig");
const bytecode_mod = @import("bytecode.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const Opcode = bytecode_mod.Opcode;
pub const BytecodeChunk = bytecode_mod.BytecodeChunk;

pub const MAX_STACK: usize = 256;
pub const MAX_INSTRUCTIONS_PER_TICK: usize = 10000;

pub const FiberId = u32;

pub const FiberStateTag = enum {
    ready,
    waiting_ticks,
    waiting_cond,
    halted,
    paused,
};

pub const FiberState = union(FiberStateTag) {
    ready: void,
    waiting_ticks: u64, // target tick to wake up
    waiting_cond: u16, // cond_pc to evaluate
    halted: void,
    paused: void,
};

pub const InterruptFrame = struct {
    pc: usize,
    sp: usize,
    state: FiberState,
};

pub const EmittedCue = struct {
    cue_id: u16,
    args: [4]u32,
    arg_count: u8,
};

pub const Fiber = struct {
    id: FiberId,
    owner: EntityId,
    pc: usize,
    stack: [MAX_STACK]u32,
    sp: usize,
    state: FiberState,
    interrupt_stack: std.ArrayList(InterruptFrame),

    pub fn init(allocator: std.mem.Allocator, id: FiberId, owner: EntityId, entry_pc: usize) Fiber {
        return Fiber{
            .id = id,
            .owner = owner,
            .pc = entry_pc,
            .stack = undefined,
            .sp = 0,
            .state = .{ .ready = {} },
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
    fibers: std.ArrayList(Fiber),
    next_fiber_id: FiberId,
    emitted_cues: std.ArrayList(EmittedCue),
    prng: std.rand.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, world: *World, chunk: *const BytecodeChunk) VM {
        return VM{
            .allocator = allocator,
            .world = world,
            .chunk = chunk,
            .fibers = std.ArrayList(Fiber).init(allocator),
            .next_fiber_id = 1,
            .emitted_cues = std.ArrayList(EmittedCue).init(allocator),
            .prng = std.rand.DefaultPrng.init(42),
        };
    }

    pub fn deinit(self: *VM) void {
        for (self.fibers.items) |*f| {
            f.deinit();
        }
        self.fibers.deinit();
        self.emitted_cues.deinit();
    }

    /// Spawns a new routine fiber owned by an entity.
    pub fn spawn_routine(self: *VM, owner: EntityId, entry_pc: usize) !FiberId {
        const id = self.next_fiber_id;
        self.next_fiber_id += 1;
        const fiber = Fiber.init(self.allocator, id, owner, entry_pc);
        try self.fibers.append(fiber);
        return id;
    }

    /// Preempts an entity's active fiber with an interruption routine (D-004, P2-04).
    pub fn interrupt_entity(self: *VM, target: EntityId, handler_pc: u16) !bool {
        for (self.fibers.items) |*f| {
            if (f.owner == target and f.state != .halted) {
                // Push current execution context onto interrupt stack
                try f.interrupt_stack.append(.{
                    .pc = f.pc,
                    .sp = f.sp,
                    .state = f.state,
                });
                // Switch execution to interrupt handler
                f.pc = handler_pc;
                f.state = .{ .ready = {} };
                return true;
            }
        }
        return false;
    }

    /// Advances the master simulation clock by 1 tick and dispatches all active fibers.
    pub fn step_tick(self: *VM) !void {
        // 1. Advance relational world and prune expired facts (P1-02)
        _ = self.world.step_tick();

        // 2. Clear peripheral cue buffer from prior tick
        self.emitted_cues.clearRetainingCapacity();

        // 3. Wake fibers whose sleep duration has expired
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
                else => {},
            }
        }

        // 4. Run ready fibers
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
                    // Pop obj, rel, subj
                    const obj = temp_stack[temp_sp - 1];
                    temp_sp -= 1;
                    const rel_raw = temp_stack[temp_sp - 1];
                    temp_sp -= 1;
                    const subj_raw = temp_stack[temp_sp - 1];
                    temp_sp -= 1;

                    const subj = EntityId.from_int(subj_raw);
                    const rel = RelationKind.from_int(@intCast(rel_raw));
                    const has = self.world.has_fact(
                        if (subj_raw != 0) subj else null,
                        if (rel_raw != 0) rel else null,
                        if (obj != 0) obj else null,
                    );
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
                    } else {
                        f.state = .{ .halted = {} };
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
