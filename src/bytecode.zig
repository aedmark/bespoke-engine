const std = @import("std");
const ListWriter = @import("list_writer.zig").ListWriter;
const world = @import("world.zig");
const EntityId = world.EntityId;
const RelationKind = world.RelationKind;

/// Bytecode instruction opcodes for the BeSpoke virtual machine (D-002).
pub const Opcode = enum(u8) {
    // --- Control Flow ---
    nop = 0x00,
    halt = 0x01,
    jump = 0x02, // operand: i16 offset
    jump_if_false = 0x03, // operand: i16 offset
    loop = 0x04, // operand: u16 offset
    call = 0x05, // operand: u16 target pc
    ret = 0x06,

    // --- Stack & Constants ---
    push_const = 0x10, // operand: u32 immediate value
    push_entity = 0x11, // operand: u32 EntityId
    push_relation = 0x12, // operand: u16 RelationKind
    pop = 0x13,
    dup = 0x14,
    /// First instruction of a cue handler whose body reads its arguments (P48-02, D-161).
    /// `VM.fire_cue` consumes it, pushing the handler's three arguments in the order the
    /// handler declares them and then its guard's eight bindings (0 for none), so they sit at
    /// stack indexes 0 to 10 beneath everything the body pushes. Reached any other way, it is
    /// an error: the arguments it stands for were never supplied.
    bind_cue_args = 0x15,
    /// Pushes a copy of stack entry `index` (operand: u8) of the running fiber: a handler
    /// argument (0 to 2) or a guard binding (3 to 10) placed by `bind_cue_args` (D-161).
    push_local = 0x16,

    // --- Arithmetic, Logic & Comparisons ---
    add = 0x20,
    sub = 0x21,
    mul = 0x22,
    div = 0x23,
    eq = 0x24,
    neq = 0x25,
    lt = 0x26,
    lte = 0x27,
    gt = 0x28,
    gte = 0x29,
    not = 0x2A,

    // --- Tabletop / Gameplay Primitives ---
    roll_dice = 0x2F, // operand: count: u8, sides: u8 (e.g. 2d6)

    // --- Relational Database Operations (D-003, D-007) ---
    /// Pops: object_or_val: u32, relation: u16, subject: u32. Operand: ttl_ticks: u32.
    remember = 0x30,
    /// Pops: [object_or_val: u32 if has_obj], relation: u16, subject: u32. Operand: has_obj: u8.
    forget = 0x31,
    /// Query whether a fact exists. Operand: wildcard_mask: u8 (bit 0: subj, bit 1: rel, bit 2: obj).
    /// Pops provided arguments, pushes 1 (true) or 0 (false).
    query_has = 0x32,
    /// Query a single property value. Pops: relation: u16, subject: u32. Pushes: value: u32.
    query_property = 0x33,
    /// Count facts matching a pattern (P44-02). Pops provided arguments per the mask.
    /// Operands: wildcard_mask: u8, threshold: u32. Pushes 1 when the count reaches it, else 0.
    query_count = 0x34,
    /// Sum the third slot of facts matching a pattern (P44-02). Pops provided arguments per
    /// the mask. Operands: wildcard_mask: u8, threshold: u32. Pushes 1 when the total reaches
    /// it, else 0. The pattern names one term to match and treats the third slot as points.
    query_points = 0x35,

    // --- Temporal & Fiber Scheduling (D-004) ---
    /// Yields execution of the active fiber until the next tick.
    yield = 0x40,
    /// Pops: duration_ticks: u32. Suspends active fiber until current_tick + duration.
    wait_ticks = 0x41,
    /// Suspends active fiber until condition block at cond_pc evaluates to non-zero. Operand: cond_pc: u16.
    wait_until = 0x42,
    /// Pops: destination_wp: u16, entity: u32. Initiates spatial walk and suspends fiber until arrival (P3-02).
    walk_to = 0x43,
    /// Transitions simulation to target scene entity and emits the SceneTransition cue; fibers keep running (P12-01, D-139).
    /// Operand: target_scene: u32 (EntityId).
    transition_scene = 0x44,

    // --- Interruption Primitives (D-004) ---
    /// Preempts target entity's active routine, pushing an interrupt frame.
    /// Pops: target_entity: u32. Operand: handler_pc: u16.
    interrupt = 0x48,
    /// Restores the prior execution frame on the interrupt stack.
    resume_routine = 0x49,

    // --- Peripheral / Motor Signals (D-001) ---
    /// Emits a cue/command event to the peripheral bridge buffer.
    /// Operand: cue_id: u16, arg_count: u8. Pops arg_count values from stack.
    emit_cue = 0x50,

    // --- Musical Drafts (P22-01, D-029) ---
    /// Queues a weave for host re-dispatch; the caster is the executing fiber's owner.
    /// Pops: target: u32, draft: u32 (EntityIds). No operand.
    weave = 0x51,

    // --- Executable Dialogue Lifecycle (P32-30, D-046) ---
    /// Begins a scripted choice set for the executing fiber. No operand.
    choices_begin = 0x52,
    /// Appends one offered choice to the open set. Operands: text: u32, body_pc: u16.
    offer_choice = 0x53,
    /// Ends the set. Operand: end_pc: u16. Suspends the fiber when the set offered any choice.
    choices_end = 0x54,
    /// Appends one offered choice and its source-order inspector branch.
    /// Operands: text: u32, body_pc: u16, source_index: u8 (P27-02, D-058).
    offer_choice_inspected = 0x55,
    /// Records a pruned source-order branch and the first guard that rejected it.
    /// Operands: text: u32, source_index: u8, failure_text: u32 (P27-02, D-058).
    reject_choice = 0x56,
};

/// Bytecode format limits for `BSP1` format 1: jumps and PC operands are 16-bit (P48-25 / D-189).
pub const MAX_BYTECODE_LEN: usize = std.math.maxInt(u16);
/// Fixed slot capacity of `EmittedCue.args`.
pub const MAX_CUE_ARGS: u8 = 4;

pub const ValidationError = error{
    BytecodeTooLarge,
    InvalidOpcode,
    TruncatedBytecode,
    InvalidJumpTarget,
    InvalidOperand,
};

/// Decodes a raw byte into a known `Opcode` without risking enum UB on untrusted bytes.
pub fn decode_opcode(byte: u8) ?Opcode {
    return std.enums.fromInt(Opcode, byte);
}

fn take_u16(code: []const u8, pc: *usize) ValidationError!u16 {
    if (code.len - pc.* < 2) return error.TruncatedBytecode;
    const val = std.mem.readInt(u16, code[pc.*..][0..2], .little);
    pc.* += 2;
    return val;
}

fn take_i16(code: []const u8, pc: *usize) ValidationError!i16 {
    if (code.len - pc.* < 2) return error.TruncatedBytecode;
    const val = std.mem.readInt(i16, code[pc.*..][0..2], .little);
    pc.* += 2;
    return val;
}

fn skip_bytes(code: []const u8, pc: *usize, n: usize) ValidationError!void {
    if (code.len - pc.* < n) return error.TruncatedBytecode;
    pc.* += n;
}

/// Verifies instruction boundaries, opcodes, operand lengths, and jump targets across `code`.
pub fn validate(code: []const u8) ValidationError!void {
    if (code.len > MAX_BYTECODE_LEN) return error.BytecodeTooLarge;
    var pc: usize = 0;
    while (pc < code.len) {
        const op = decode_opcode(code[pc]) orelse return error.InvalidOpcode;
        pc += 1;
        switch (op) {
            .nop,
            .halt,
            .ret,
            .pop,
            .dup,
            .bind_cue_args,
            .add,
            .sub,
            .mul,
            .div,
            .eq,
            .neq,
            .lt,
            .lte,
            .gt,
            .gte,
            .not,
            .query_property,
            .yield,
            .wait_ticks,
            .walk_to,
            .resume_routine,
            .weave,
            .choices_begin,
            => {},
            .push_local, .forget, .query_has => try skip_bytes(code, &pc, 1),
            .push_relation => try skip_bytes(code, &pc, 2),
            .push_const, .push_entity, .remember, .transition_scene => try skip_bytes(code, &pc, 4),
            .query_count, .query_points => try skip_bytes(code, &pc, 5),
            .roll_dice => {
                if (code.len - pc < 2) return error.TruncatedBytecode;
                const count = code[pc];
                const sides = code[pc + 1];
                pc += 2;
                if (count > 0 and sides == 0) return error.InvalidOperand;
            },
            .jump, .jump_if_false => {
                const offset = try take_i16(code, &pc);
                if (offset == std.math.minInt(i16)) return error.InvalidJumpTarget;
                const target = @as(isize, @intCast(pc)) + @as(isize, offset);
                if (target < 0 or target > @as(isize, @intCast(code.len))) return error.InvalidJumpTarget;
            },
            .loop => {
                const offset = try take_u16(code, &pc);
                if (offset > pc) return error.InvalidJumpTarget;
            },
            .call, .wait_until, .interrupt => {
                const target = try take_u16(code, &pc);
                if (target >= code.len) return error.InvalidJumpTarget;
            },
            .emit_cue => {
                _ = try take_u16(code, &pc);
                if (pc >= code.len) return error.TruncatedBytecode;
                const arg_count = code[pc];
                pc += 1;
                if (arg_count > MAX_CUE_ARGS) return error.InvalidOperand;
            },
            .offer_choice => {
                try skip_bytes(code, &pc, 4);
                const body_pc = try take_u16(code, &pc);
                if (body_pc > code.len) return error.InvalidJumpTarget;
            },
            .choices_end => {
                const end_pc = try take_u16(code, &pc);
                if (end_pc > code.len) return error.InvalidJumpTarget;
            },
            .offer_choice_inspected => {
                try skip_bytes(code, &pc, 4);
                const body_pc = try take_u16(code, &pc);
                if (body_pc > code.len) return error.InvalidJumpTarget;
                try skip_bytes(code, &pc, 1);
            },
            .reject_choice => try skip_bytes(code, &pc, 9),
        }
    }
}

/// A compiled container of bytecode instructions and constant data.
pub const BytecodeChunk = struct {
    code: std.array_list.Managed(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BytecodeChunk {
        return BytecodeChunk{
            .code = std.array_list.Managed(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BytecodeChunk) void {
        self.code.deinit();
    }

    pub fn count(self: *const BytecodeChunk) usize {
        return self.code.items.len;
    }

    pub fn emit_op(self: *BytecodeChunk, op: Opcode) !usize {
        const pc = self.code.items.len;
        try self.code.append(@intFromEnum(op));
        return pc;
    }

    pub fn emit_u8(self: *BytecodeChunk, val: u8) !void {
        try self.code.append(val);
    }

    pub fn emit_u16(self: *BytecodeChunk, val: u16) !void {
        var lw1 = ListWriter.init(&self.code);
        try lw1.writer.writeInt(u16, val, .little);
    }

    pub fn emit_i16(self: *BytecodeChunk, val: i16) !void {
        var lw2 = ListWriter.init(&self.code);
        try lw2.writer.writeInt(i16, val, .little);
    }

    pub fn emit_u32(self: *BytecodeChunk, val: u32) !void {
        var lw3 = ListWriter.init(&self.code);
        try lw3.writer.writeInt(u32, val, .little);
    }

    // Convenience emitters
    pub fn emit_push_const(self: *BytecodeChunk, val: u32) !void {
        _ = try self.emit_op(.push_const);
        try self.emit_u32(val);
    }

    pub fn emit_push_entity(self: *BytecodeChunk, entity: EntityId) !void {
        _ = try self.emit_op(.push_entity);
        try self.emit_u32(entity.to_int());
    }

    pub fn emit_push_local(self: *BytecodeChunk, index: u8) !void {
        _ = try self.emit_op(.push_local);
        try self.emit_u8(index);
    }

    pub fn emit_push_relation(self: *BytecodeChunk, relation: RelationKind) !void {
        _ = try self.emit_op(.push_relation);
        try self.emit_u16(relation.to_int());
    }

    /// Emits a count or points threshold over the facts a pattern matches (P44-02).
    pub fn emit_query_aggregate(self: *BytecodeChunk, op: Opcode, mask: u8, threshold: u32) !void {
        std.debug.assert(op == .query_count or op == .query_points);
        _ = try self.emit_op(op);
        try self.emit_u8(mask);
        try self.emit_u32(threshold);
    }

    pub fn emit_jump(self: *BytecodeChunk, op: Opcode, offset: i16) !void {
        _ = try self.emit_op(op);
        try self.emit_i16(offset);
    }

    pub fn emit_remember(self: *BytecodeChunk, ttl_ticks: u32) !void {
        _ = try self.emit_op(.remember);
        try self.emit_u32(ttl_ticks);
    }

    pub fn emit_wait_ticks(self: *BytecodeChunk, ticks: u32) !void {
        try self.emit_push_const(ticks);
        _ = try self.emit_op(.wait_ticks);
    }

    pub fn emit_walk_to(self: *BytecodeChunk, entity: EntityId, dest: u16) !void {
        try self.emit_push_entity(entity);
        try self.emit_push_const(dest);
        _ = try self.emit_op(.walk_to);
    }

    pub fn emit_roll_dice(self: *BytecodeChunk, count_val: u8, sides: u8) !void {
        _ = try self.emit_op(.roll_dice);
        try self.emit_u8(count_val);
        try self.emit_u8(sides);
    }

    pub fn emit_weave(self: *BytecodeChunk, draft: EntityId, target: EntityId) !void {
        try self.emit_push_entity(draft);
        try self.emit_push_entity(target);
        _ = try self.emit_op(.weave);
    }

    pub fn emit_transition_scene(self: *BytecodeChunk, scene_id: EntityId) !void {
        _ = try self.emit_op(.transition_scene);
        try self.emit_u32(scene_id.to_int());
    }

    /// Returns the opcode pc; the u16 body operand sits at `pc + 5` for patching.
    pub fn emit_offer_choice(self: *BytecodeChunk, text: EntityId, body_pc: u16) !usize {
        const pc = try self.emit_op(.offer_choice);
        try self.emit_u32(text.to_int());
        try self.emit_u16(body_pc);
        return pc;
    }

    /// Returns the opcode pc; the u16 body operand sits at `pc + 5` for patching.
    pub fn emit_offer_choice_inspected(self: *BytecodeChunk, text: EntityId, body_pc: u16, source_index: u8) !usize {
        const pc = try self.emit_op(.offer_choice_inspected);
        try self.emit_u32(text.to_int());
        try self.emit_u16(body_pc);
        try self.emit_u8(source_index);
        return pc;
    }

    pub fn emit_reject_choice(self: *BytecodeChunk, text: EntityId, source_index: u8, failure_text: EntityId) !void {
        _ = try self.emit_op(.reject_choice);
        try self.emit_u32(text.to_int());
        try self.emit_u8(source_index);
        try self.emit_u32(failure_text.to_int());
    }

    /// Returns the opcode pc; the u16 end operand sits at `pc + 1` for patching.
    pub fn emit_choices_end(self: *BytecodeChunk, end_pc: u16) !usize {
        const pc = try self.emit_op(.choices_end);
        try self.emit_u16(end_pc);
        return pc;
    }
};

test "bytecode chunk emission and opcode reading" {
    const testing = std.testing;
    var chunk = BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    _ = try chunk.emit_op(.nop);
    try chunk.emit_push_const(42);
    try chunk.emit_push_entity(EntityId.from_int(101));
    try chunk.emit_push_relation(RelationKind.from_int(7));
    try chunk.emit_remember(120);
    try chunk.emit_transition_scene(EntityId.from_int(202));
    _ = try chunk.emit_op(.halt);

    const bytes = chunk.code.items;
    try testing.expectEqual(@as(u8, @intFromEnum(Opcode.nop)), bytes[0]);
    try testing.expectEqual(@as(u8, @intFromEnum(Opcode.push_const)), bytes[1]);
    const const_val = std.mem.readInt(u32, bytes[2..6], .little);
    try testing.expectEqual(@as(u32, 42), const_val);

    try testing.expectEqual(@as(u8, @intFromEnum(Opcode.push_entity)), bytes[6]);
    const entity_val = std.mem.readInt(u32, bytes[7..11], .little);
    try testing.expectEqual(@as(u32, 101), entity_val);

    // Verify transition_scene opcode and payload
    // remember is at byte 14 (op 0x30, 4 bytes payload -> 14..19)
    // transition_scene is at byte 19: opcode 0x44, 4 bytes payload 202
    try testing.expectEqual(@as(u8, @intFromEnum(Opcode.transition_scene)), bytes[19]);
    const scene_val = std.mem.readInt(u32, bytes[20..24], .little);
    try testing.expectEqual(@as(u32, 202), scene_val);
    try validate(bytes);
}

test "bytecode validate rejects malformed opcodes, operands, jumps, and oversize chunks" {
    const testing = std.testing;
    try testing.expectError(error.InvalidOpcode, validate(&.{0xFF}));
    try testing.expectError(error.TruncatedBytecode, validate(&.{ @intFromEnum(Opcode.push_const), 1, 2 }));
    try testing.expectError(error.InvalidOperand, validate(&.{ @intFromEnum(Opcode.emit_cue), 2, 0, 5 }));
    try testing.expectError(error.InvalidOperand, validate(&.{ @intFromEnum(Opcode.roll_dice), 2, 0 }));
    try testing.expectError(error.InvalidJumpTarget, validate(&.{ @intFromEnum(Opcode.jump), 0x00, 0x80 })); // minInt(i16)
    try testing.expectError(error.InvalidJumpTarget, validate(&.{ @intFromEnum(Opcode.jump), 0xF0, 0xFF })); // underflow
    try testing.expectError(error.InvalidJumpTarget, validate(&.{ @intFromEnum(Opcode.jump), 0x10, 0x00 })); // past end
    try testing.expectError(error.InvalidJumpTarget, validate(&.{ @intFromEnum(Opcode.loop), 0x10, 0x00 })); // underflow
    try testing.expectError(error.InvalidJumpTarget, validate(&.{ @intFromEnum(Opcode.wait_until), 0x10, 0x00 }));
    try testing.expectError(error.InvalidJumpTarget, validate(&.{ @intFromEnum(Opcode.offer_choice), 0, 0, 0, 0, 0x10, 0x00 }));
    try testing.expectError(error.InvalidJumpTarget, validate(&.{ @intFromEnum(Opcode.choices_end), 0x10, 0x00 }));

    const huge = try testing.allocator.alloc(u8, MAX_BYTECODE_LEN + 1);
    defer testing.allocator.free(huge);
    @memset(huge, @intFromEnum(Opcode.nop));
    try testing.expectError(error.BytecodeTooLarge, validate(huge));
}
