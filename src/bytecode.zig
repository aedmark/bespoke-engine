const std = @import("std");
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

    // --- Temporal & Fiber Scheduling (D-004) ---
    /// Yields execution of the active fiber until the next tick.
    yield = 0x40,
    /// Pops: duration_ticks: u32. Suspends active fiber until current_tick + duration.
    wait_ticks = 0x41,
    /// Suspends active fiber until condition block at cond_pc evaluates to non-zero. Operand: cond_pc: u16.
    wait_until = 0x42,

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
};

/// A compiled container of bytecode instructions and constant data.
pub const BytecodeChunk = struct {
    code: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BytecodeChunk {
        return BytecodeChunk{
            .code = std.ArrayList(u8).init(allocator),
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
        try self.code.writer().writeInt(u16, val, .little);
    }

    pub fn emit_i16(self: *BytecodeChunk, val: i16) !void {
        try self.code.writer().writeInt(i16, val, .little);
    }

    pub fn emit_u32(self: *BytecodeChunk, val: u32) !void {
        try self.code.writer().writeInt(u32, val, .little);
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

    pub fn emit_push_relation(self: *BytecodeChunk, relation: RelationKind) !void {
        _ = try self.emit_op(.push_relation);
        try self.emit_u16(relation.to_int());
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

    pub fn emit_roll_dice(self: *BytecodeChunk, count_val: u8, sides: u8) !void {
        _ = try self.emit_op(.roll_dice);
        try self.emit_u8(count_val);
        try self.emit_u8(sides);
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
    _ = try chunk.emit_op(.halt);

    const bytes = chunk.code.items;
    try testing.expectEqual(@as(u8, @intFromEnum(Opcode.nop)), bytes[0]);
    try testing.expectEqual(@as(u8, @intFromEnum(Opcode.push_const)), bytes[1]);
    const const_val = std.mem.readInt(u32, bytes[2..6], .little);
    try testing.expectEqual(@as(u32, 42), const_val);

    try testing.expectEqual(@as(u8, @intFromEnum(Opcode.push_entity)), bytes[6]);
    const entity_val = std.mem.readInt(u32, bytes[7..11], .little);
    try testing.expectEqual(@as(u32, 101), entity_val);
}
