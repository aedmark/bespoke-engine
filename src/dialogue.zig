//! Executable dialogue lifecycle (P32-30, D-046).
//!
//! A conversation is a World-fact state machine, so save snapshots and timeline rewinds carry
//! it without host bookkeeping:
//!
//!   DialogueRevision(speaker, n)      bumped whenever a set opens
//!   DialogueOpen(speaker, count)      number of offered choices; 0 means drafting
//!   DialoguePrompt(speaker, text)     prompt entity, or absent
//!   DialogueFiber(speaker, id)        suspended scripted fiber; 0 for generated sets
//!   DialogueEnd(speaker, pc)          instruction after the choice set
//!   DialogueOption(speaker#n, text)   offered text entity
//!   DialogueBody(speaker#n, pc)       scripted body entry; 0 for generated sets
//!   DialogueAction(speaker#n, id)     host action id for generated sets; 0 otherwise
//!   DialogueChosen(speaker, index)    last selection, cleared by the next set
//!   DialogueBranchCount(speaker, n)   source choices captured for the inspector
//!   DialogueBranchText(speaker~n, text)
//!   DialogueBranchActive(speaker~n, 0 | 1)
//!   DialogueBranchFailure(speaker~n, text) first failed guard for a pruned branch
//!
//! Scripted sets are emitted by the compiler as `choices_begin` / `offer_choice` /
//! `choices_end`. Generated sets are opened by a host with `open_generated`, which writes the
//! same facts with action ids instead of body pcs. `choose` clears the open set and returns
//! the selection; the VM resumes the fiber for scripted sets, and the host resolves the action
//! for generated ones. The module names no speaker, line, or game.
const std = @import("std");
const world_mod = @import("world.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;

pub const MAX_CHOICES: usize = 9;
pub const MAX_TEXT: usize = 160;

pub const Error = error{DialogueTooLarge};

/// One runtime-generated choice. The engine stores the text and action id as facts; the host
/// keeps ownership of what the action means.
pub const Choice = struct {
    text: []const u8,
    action: u32 = 0,
};

pub const Selection = struct {
    index: usize,
    speaker: EntityId,
    fiber_id: u32,
    body_pc: u32,
    action: u32,

    /// True when the selection resumes a compiled choice body rather than a host action.
    pub fn is_scripted(self: Selection) bool {
        return self.fiber_id != 0;
    }
};

pub const Branch = struct {
    text: []const u8 = "",
    active: bool = false,
    failure: []const u8 = "",
};

pub const View = struct {
    /// The entity the option facts are keyed by; `choose` selects through it.
    speaker: EntityId,
    /// The entity the host presents as speaking. Usually an NPC, not the fiber owner.
    display_speaker: EntityId,
    revision: u32,
    prompt: []const u8,
    count: usize,
    texts: [MAX_CHOICES][]const u8,
    actions: [MAX_CHOICES]u32,
    branch_count: usize,
    branches: [MAX_CHOICES]Branch,

    pub fn text(self: *const View, index: usize) []const u8 {
        return if (index < self.count) self.texts[index] else "";
    }

    pub fn action(self: *const View, index: usize) u32 {
        return if (index < self.count) self.actions[index] else 0;
    }

    pub fn branch(self: *const View, index: usize) Branch {
        return if (index < self.branch_count) self.branches[index] else .{};
    }
};

const Names = struct {
    open: []const u8 = "DialogueOpen",
    prompt: []const u8 = "DialoguePrompt",
    fiber: []const u8 = "DialogueFiber",
    end: []const u8 = "DialogueEnd",
    revision: []const u8 = "DialogueRevision",
    option: []const u8 = "DialogueOption",
    body: []const u8 = "DialogueBody",
    action: []const u8 = "DialogueAction",
    chosen: []const u8 = "DialogueChosen",
    speaker: []const u8 = "DialogueSpeaker",
    branch_count: []const u8 = "DialogueBranchCount",
    branch_text: []const u8 = "DialogueBranchText",
    branch_active: []const u8 = "DialogueBranchActive",
    branch_failure: []const u8 = "DialogueBranchFailure",
};

pub const Relations = struct {
    open: RelationKind,
    prompt: RelationKind,
    fiber: RelationKind,
    end: RelationKind,
    revision: RelationKind,
    option: RelationKind,
    body: RelationKind,
    action: RelationKind,
    chosen: RelationKind,
    speaker: RelationKind,
};

const BranchRelations = struct {
    branch_count: RelationKind,
    branch_text: RelationKind,
    branch_active: RelationKind,
    branch_failure: RelationKind,
};

const NAMES = Names{};
const NAME_BUF_LEN = 192;

/// Interns (idempotently) every relation the lifecycle writes.
pub fn relations(world: *World) !Relations {
    return .{
        .open = try world.intern_relation(NAMES.open, .property),
        .prompt = try world.intern_relation(NAMES.prompt, .property),
        .fiber = try world.intern_relation(NAMES.fiber, .property),
        .end = try world.intern_relation(NAMES.end, .property),
        .revision = try world.intern_relation(NAMES.revision, .property),
        .option = try world.intern_relation(NAMES.option, .set),
        .body = try world.intern_relation(NAMES.body, .property),
        .action = try world.intern_relation(NAMES.action, .property),
        .chosen = try world.intern_relation(NAMES.chosen, .property),
        .speaker = try world.intern_relation(NAMES.speaker, .property),
    };
}

/// Looks up the relations without mutating the World, for read-only capture.
fn lookup_relations(world: *const World) ?Relations {
    return .{
        .open = world.lookup_relation(NAMES.open) orelse return null,
        .prompt = world.lookup_relation(NAMES.prompt) orelse return null,
        .fiber = world.lookup_relation(NAMES.fiber) orelse return null,
        .end = world.lookup_relation(NAMES.end) orelse return null,
        .revision = world.lookup_relation(NAMES.revision) orelse return null,
        .option = world.lookup_relation(NAMES.option) orelse return null,
        .body = world.lookup_relation(NAMES.body) orelse return null,
        .action = world.lookup_relation(NAMES.action) orelse return null,
        .chosen = world.lookup_relation(NAMES.chosen) orelse return null,
        .speaker = world.lookup_relation(NAMES.speaker) orelse return null,
    };
}

fn branch_relations(world: *World) !BranchRelations {
    return .{
        .branch_count = try world.intern_relation(NAMES.branch_count, .property),
        .branch_text = try world.intern_relation(NAMES.branch_text, .property),
        .branch_active = try world.intern_relation(NAMES.branch_active, .property),
        .branch_failure = try world.intern_relation(NAMES.branch_failure, .property),
    };
}

fn lookup_branch_relations(world: *const World) ?BranchRelations {
    return .{
        .branch_count = world.lookup_relation(NAMES.branch_count) orelse return null,
        .branch_text = world.lookup_relation(NAMES.branch_text) orelse return null,
        .branch_active = world.lookup_relation(NAMES.branch_active) orelse return null,
        .branch_failure = world.lookup_relation(NAMES.branch_failure) orelse return null,
    };
}

/// Names the entity a host presents as the speaker for sets owned by `owner` (P32-30).
/// Presentation only: option facts stay keyed by the owner so selection is unambiguous.
pub fn set_speaker(world: *World, owner: EntityId, display: EntityId) !void {
    const r = try relations(world);
    try world.remember(owner, r.speaker, display.to_int(), 0);
}

/// Starts a scripted set owned by the executing fiber. Any previous set by this speaker is
/// discarded, so a conversation has one open set at a time.
pub fn begin(world: *World, speaker: EntityId, fiber: u32) !void {
    const r = try relations(world);
    try clear_open(world, speaker);
    const revision = (world.get_property(speaker, r.revision) orelse 0) +% 1;
    try world.remember(speaker, r.revision, revision, 0);
    try world.remember(speaker, r.fiber, fiber, 0);
    try world.remember(speaker, r.open, 0, 0);
}

/// Appends one scripted choice. The body pc is where the VM resumes after selection.
pub fn offer(world: *World, speaker: EntityId, text: EntityId, body_pc: u16) !void {
    const r = try relations(world);
    const count = world.get_property(speaker, r.open) orelse 0;
    if (count >= MAX_CHOICES) return Error.DialogueTooLarge;
    const option = try option_entity(world, speaker, count);
    try world.remember(option, r.option, text.to_int(), 0);
    try world.remember(option, r.body, body_pc, 0);
    try world.remember(option, r.action, 0, 0);
    try world.remember(speaker, r.open, count + 1, 0);
}

/// Appends one offered choice and records its source-order branch for the paused inspector.
pub fn offer_inspected(world: *World, speaker: EntityId, text: EntityId, body_pc: u16, source_index: usize) !void {
    try offer(world, speaker, text, body_pc);
    try record_branch(world, speaker, source_index, text, true, null);
}

/// Records a choice rejected by its first failed guard. It is diagnostic state only and never
/// enters the selectable option table.
pub fn reject(world: *World, speaker: EntityId, text: EntityId, source_index: usize, failure: EntityId) !void {
    try record_branch(world, speaker, source_index, text, false, failure);
}

/// Ends a scripted set. Returns how many choices were offered. With none, the VM continues at
/// `end_pc`; with any, the fiber suspends and the facts describe the open set.
pub fn finish(world: *World, speaker: EntityId, after_pc: u16) !usize {
    const r = try relations(world);
    const count = world.get_property(speaker, r.open) orelse 0;
    if (count == 0) {
        try clear_open(world, speaker);
        return 0;
    }
    try world.remember(speaker, r.end, after_pc, 0);
    return count;
}

/// Opens a host-generated set. Text and action ids are copied into World facts, so the host's
/// candidate slices need not outlive the call. Returns the number of choices.
pub fn open_generated(
    world: *World,
    speaker: EntityId,
    prompt: []const u8,
    choices: []const Choice,
) !usize {
    if (choices.len > MAX_CHOICES) return Error.DialogueTooLarge;
    const r = try relations(world);
    try clear_open(world, speaker);

    const revision = (world.get_property(speaker, r.revision) orelse 0) +% 1;
    try world.remember(speaker, r.revision, revision, 0);

    if (prompt.len > 0) {
        const prompt_ent = try world.intern_entity(prompt);
        try world.remember(speaker, r.prompt, prompt_ent.to_int(), 0);
    }

    for (choices, 0..) |choice, i| {
        const option = try option_entity(world, speaker, i);
        const text = try world.intern_entity(choice.text);
        try world.remember(option, r.option, text.to_int(), 0);
        try world.remember(option, r.action, choice.action, 0);
        try world.remember(option, r.body, 0, 0);
    }

    if (choices.len > 0) {
        try world.remember(speaker, r.open, @intCast(choices.len), 0);
    }
    return choices.len;
}

/// The open set, or null. Read-only; safe during frame capture.
pub fn view(world: *const World) ?View {
    const r = lookup_relations(world) orelse return null;
    const open = world.find_first(null, r.open, null) orelse return null;
    const count: usize = @intCast(open.object_or_value);
    if (count == 0 or count > MAX_CHOICES) return null;

    const speaker = open.subject;
    var out = View{
        .speaker = speaker,
        .display_speaker = EntityId.from_int(world.get_property(speaker, r.speaker) orelse speaker.to_int()),
        .revision = world.get_property(speaker, r.revision) orelse 0,
        .prompt = "",
        .count = count,
        .texts = [_][]const u8{""} ** MAX_CHOICES,
        .actions = [_]u32{0} ** MAX_CHOICES,
        .branch_count = 0,
        .branches = [_]Branch{.{}} ** MAX_CHOICES,
    };

    if (world.get_property(speaker, r.prompt)) |prompt_id| {
        if (prompt_id != 0) out.prompt = world.get_entity_name(EntityId.from_int(prompt_id)) orelse "";
    }

    for (0..count) |i| {
        const option = option_entity_lookup(world, speaker, i) orelse break;
        if (world.get_property(option, r.option)) |text_id| {
            out.texts[i] = world.get_entity_name(EntityId.from_int(text_id)) orelse "";
        }
        out.actions[i] = world.get_property(option, r.action) orelse 0;
    }

    const branch_r = lookup_branch_relations(world);
    const branch_count: usize = if (branch_r) |br| @intCast(world.get_property(speaker, br.branch_count) orelse 0) else 0;
    if (branch_r != null and branch_count > 0 and branch_count <= MAX_CHOICES) {
        const br = branch_r.?;
        out.branch_count = branch_count;
        for (0..branch_count) |i| {
            const entity = branch_entity_lookup(world, speaker, i) orelse continue;
            if (world.get_property(entity, br.branch_text)) |text_id| {
                out.branches[i].text = world.get_entity_name(EntityId.from_int(text_id)) orelse "";
            }
            out.branches[i].active = (world.get_property(entity, br.branch_active) orelse 0) != 0;
            if (world.get_property(entity, br.branch_failure)) |failure_id| {
                out.branches[i].failure = world.get_entity_name(EntityId.from_int(failure_id)) orelse "";
            }
        }
    } else {
        // Generated and pre-P27-02 scripted sets have no diagnostics; every offered choice is
        // active and remains inspectable.
        out.branch_count = count;
        for (0..count) |i| out.branches[i] = .{ .text = out.texts[i], .active = true };
    }
    return out;
}

/// Selects one offered choice, clears the open set, records the selection, and returns what
/// the VM or host must do. Null when no set is open or the index is not offered.
pub fn choose(world: *World, speaker: EntityId, index: usize) !?Selection {
    const r = try relations(world);
    const count = world.get_property(speaker, r.open) orelse return null;
    if (count == 0 or index >= count) return null;

    const option = try option_entity(world, speaker, index);
    const body_pc = world.get_property(option, r.body) orelse 0;
    const action = world.get_property(option, r.action) orelse 0;
    const fiber = world.get_property(speaker, r.fiber) orelse 0;

    try clear_open(world, speaker);
    _ = world.forget(speaker, r.speaker, null);
    try world.remember(speaker, r.chosen, @intCast(index), 0);

    return .{
        .index = index,
        .speaker = speaker,
        .fiber_id = fiber,
        .body_pc = body_pc,
        .action = action,
    };
}

/// Removes every fact belonging to the open set, keeping the speaker's revision and last
/// selection. Safe when no set is open.
pub fn clear_open(world: *World, speaker: EntityId) !void {
    const r = try relations(world);
    const count = world.get_property(speaker, r.open) orelse 0;
    var i: usize = 0;
    while (i < count and i < MAX_CHOICES) : (i += 1) {
        const option = try option_entity(world, speaker, i);
        _ = world.forget(option, r.option, null);
        _ = world.forget(option, r.body, null);
        _ = world.forget(option, r.action, null);
    }
    if (lookup_branch_relations(world)) |br| {
        const branch_count = world.get_property(speaker, br.branch_count) orelse 0;
        i = 0;
        while (i < branch_count and i < MAX_CHOICES) : (i += 1) {
            const entity = try branch_entity(world, speaker, i);
            _ = world.forget(entity, br.branch_text, null);
            _ = world.forget(entity, br.branch_active, null);
            _ = world.forget(entity, br.branch_failure, null);
        }
        _ = world.forget(speaker, br.branch_count, null);
    }
    _ = world.forget(speaker, r.open, null);
    _ = world.forget(speaker, r.prompt, null);
    _ = world.forget(speaker, r.fiber, null);
    _ = world.forget(speaker, r.end, null);
}

/// The fiber suspended on the open set, or 0 for a generated set or no set.
pub fn fiber_id(world: *const World, speaker: EntityId) u32 {
    const r = lookup_relations(world) orelse return 0;
    return world.get_property(speaker, r.fiber) orelse 0;
}

/// The instruction after the open set's choices, or 0 when none is stored.
pub fn end_pc(world: *const World, speaker: EntityId) u16 {
    const r = lookup_relations(world) orelse return 0;
    return @intCast(world.get_property(speaker, r.end) orelse 0);
}

fn option_entity(world: *World, speaker: EntityId, index: usize) !EntityId {
    var buf: [NAME_BUF_LEN]u8 = undefined;
    const name = try option_name(&buf, world, speaker, index);
    return world.intern_entity(name);
}

fn record_branch(
    world: *World,
    speaker: EntityId,
    source_index: usize,
    text: EntityId,
    active: bool,
    failure: ?EntityId,
) !void {
    if (source_index >= MAX_CHOICES) return Error.DialogueTooLarge;
    const r = try branch_relations(world);
    const entity = try branch_entity(world, speaker, source_index);
    try world.remember(entity, r.branch_text, text.to_int(), 0);
    try world.remember(entity, r.branch_active, @intFromBool(active), 0);
    if (failure) |failed| try world.remember(entity, r.branch_failure, failed.to_int(), 0);
    const previous = world.get_property(speaker, r.branch_count) orelse 0;
    if (source_index + 1 > previous) try world.remember(speaker, r.branch_count, @intCast(source_index + 1), 0);
}

fn branch_entity(world: *World, speaker: EntityId, index: usize) !EntityId {
    var buf: [NAME_BUF_LEN]u8 = undefined;
    const name = try branch_name(&buf, world, speaker, index);
    return world.intern_entity(name);
}

fn branch_entity_lookup(world: *const World, speaker: EntityId, index: usize) ?EntityId {
    var buf: [NAME_BUF_LEN]u8 = undefined;
    const name = branch_name(&buf, world, speaker, index) catch return null;
    return world.lookup_entity(name);
}

fn branch_name(buf: []u8, world: *const World, speaker: EntityId, index: usize) ![]const u8 {
    const speaker_name = world.get_entity_name(speaker) orelse return Error.DialogueTooLarge;
    return std.fmt.bufPrint(buf, "{s}~{d}", .{ speaker_name, index }) catch Error.DialogueTooLarge;
}

fn option_entity_lookup(world: *const World, speaker: EntityId, index: usize) ?EntityId {
    var buf: [NAME_BUF_LEN]u8 = undefined;
    const name = option_name(&buf, world, speaker, index) catch return null;
    return world.lookup_entity(name);
}

fn option_name(buf: []u8, world: *const World, speaker: EntityId, index: usize) ![]const u8 {
    const speaker_name = world.get_entity_name(speaker) orelse return Error.DialogueTooLarge;
    return std.fmt.bufPrint(buf, "{s}#{d}", .{ speaker_name, index }) catch Error.DialogueTooLarge;
}

// --- Tests: the fact layer with a second theme, no proof names (P32-30). ---

test "P32-30: scripted dialogue facts offer, select, and clear" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const speaker = try world.intern_entity("Instructor");
    const partner = try world.intern_entity("Student");
    const first = try world.intern_entity("Open the valve.");
    const second = try world.intern_entity("Read the gauge.");
    try set_speaker(&world, speaker, partner);

    try begin(&world, speaker, 7);
    try offer(&world, speaker, first, 100);
    try offer(&world, speaker, second, 200);
    try testing.expectEqual(@as(usize, 2), try finish(&world, speaker, 300));

    const open = view(&world).?;
    try testing.expectEqual(speaker, open.speaker);
    try testing.expectEqual(partner, open.display_speaker);
    try testing.expectEqual(@as(usize, 2), open.count);
    try testing.expectEqualStrings("Open the valve.", open.text(0));
    try testing.expectEqualStrings("Read the gauge.", open.text(1));
    try testing.expectEqual(@as(u32, 7), fiber_id(&world, speaker));
    try testing.expectEqual(@as(u16, 300), end_pc(&world, speaker));

    const selected = (try choose(&world, speaker, 1)).?;
    try testing.expectEqual(@as(usize, 1), selected.index);
    try testing.expectEqual(@as(u32, 7), selected.fiber_id);
    try testing.expectEqual(@as(u32, 200), selected.body_pc);
    try testing.expect(view(&world) == null);
    const r = try relations(&world);
    try testing.expectEqual(@as(?u32, 1), world.get_property(speaker, r.chosen));
}

test "P32-30: generated dialogue stores text and host action ids" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const speaker = try world.intern_entity("Rival");
    const choices = [_]Choice{
        .{ .text = "Parry high.", .action = 11 },
        .{ .text = "Parry low.", .action = 12 },
    };
    try testing.expectEqual(@as(usize, 2), try open_generated(&world, speaker, "Choose a guard.", &choices));

    const open = view(&world).?;
    try testing.expectEqualStrings("Choose a guard.", open.prompt);
    try testing.expectEqual(@as(u32, 12), open.action(1));

    const selected = (try choose(&world, speaker, 1)).?;
    try testing.expectEqual(@as(u32, 0), selected.fiber_id);
    try testing.expectEqual(@as(u32, 12), selected.action);
    try testing.expect(view(&world) == null);
}

test "P32-30: an empty scripted set leaves no dialogue open" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const speaker = try world.intern_entity("Instructor");
    try begin(&world, speaker, 3);
    try testing.expectEqual(@as(usize, 0), try finish(&world, speaker, 40));
    try testing.expect(view(&world) == null);
}
