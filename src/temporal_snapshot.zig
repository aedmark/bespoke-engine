//! Serializable state for a `TemporalHypervisor` (P31-04, D-048).
//!
//! The primary world, spatial state, and VM are snapshotted by their own layers. This module
//! captures the state those layers do not own: the branch world, the collapse countdown, the
//! branch lifecycle, the teleological dependency graph, and the dream residue buffer. A host
//! that restores a world snapshot without restoring this envelope would leave the branch ahead
//! of the primary timeline.
const std = @import("std");
const dice_mod = @import("dice.zig");
const ListWriter = @import("list_writer.zig").ListWriter;
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const hypervisor_mod = @import("hypervisor.zig");

const World = world_mod.World;
const EntityId = world_mod.EntityId;
const RelationKind = world_mod.RelationKind;
const WaypointId = spatial_mod.WaypointId;
const TemporalHypervisor = hypervisor_mod.TemporalHypervisor;
const BranchCollapseState = hypervisor_mod.BranchCollapseState;
const DreamFact = hypervisor_mod.DreamFact;
const TeleologicalDependency = hypervisor_mod.TeleologicalDependency;

pub const MAGIC = [4]u8{ 'B', 'T', 'S', 'V' };
/// Version 2 adds the run's seed and, with a live branch, the branch's generator after its
/// world (P48-14, D-184). Version 1 envelopes load with the default seed and, for a live
/// branch, dice seeded as a new branch at the primary world's tick would be.
pub const VERSION: u32 = 2;

/// Upper bound for a branch-world snapshot read from disk or a timeline buffer.
pub const MAX_BRANCH_BYTES: u32 = 64 * 1024 * 1024;
/// Upper bound for dependency and residue rows, so a corrupt count cannot exhaust memory.
pub const MAX_RECORDS: u32 = 1_000_000;

pub const Error = error{
    InvalidTemporalSnapshot,
    InconsistentTemporalState,
};

/// Decoded temporal state. `branch_world` owns an independent World arena; `apply` moves it into
/// the live hypervisor. The struct can be decoded before the primary world is mutated, which is
/// what keeps a failed temporal restore from changing the running simulation.
pub const TemporalSnapshot = struct {
    allocator: std.mem.Allocator,
    branch_world: ?World = null,
    branch_active: bool = false,
    collapse_budget_ticks: u64 = 0,
    ticks_elapsed: u64 = 0,
    collapse_state: BranchCollapseState = .dormant,
    receiver_entity: ?EntityId = null,
    keystone_entity: ?EntityId = null,
    convergence_waypoint: ?WaypointId = null,
    teleological_dependencies: std.array_list.Managed(TeleologicalDependency),
    dream_residue_facts: std.array_list.Managed(DreamFact),
    run_seed: u64 = dice_mod.DEFAULT_SEED,
    branch_dice: ?dice_mod.Dice = null,

    pub fn init(allocator: std.mem.Allocator) TemporalSnapshot {
        return .{
            .allocator = allocator,
            .teleological_dependencies = std.array_list.Managed(TeleologicalDependency).init(allocator),
            .dream_residue_facts = std.array_list.Managed(DreamFact).init(allocator),
        };
    }

    pub fn deinit(self: *TemporalSnapshot) void {
        if (self.branch_world) |*world| {
            world.deinit();
            self.branch_world = null;
        }
        self.teleological_dependencies.deinit();
        self.dream_residue_facts.deinit();
    }

    /// Serializes a live hypervisor. The branch-world bytes follow the metadata and both lists.
    pub fn write(hypervisor: *const TemporalHypervisor, writer: anytype) !void {
        if (hypervisor.branch_active != (hypervisor.branch_world != null)) {
            return Error.InconsistentTemporalState;
        }
        if (hypervisor.teleological_dependencies.items.len > MAX_RECORDS or
            hypervisor.dream_residue_facts.items.len > MAX_RECORDS)
        {
            return Error.InconsistentTemporalState;
        }

        try writer.writeAll(&MAGIC);
        try writer.writeInt(u32, VERSION, .little);
        try writer.writeByte(if (hypervisor.branch_active) 1 else 0);

        try writer.writeInt(u64, hypervisor.collapse_budget_ticks, .little);
        try writer.writeInt(u64, hypervisor.ticks_elapsed, .little);
        try writer.writeByte(@intFromEnum(hypervisor.collapse_state));
        try writeEntity(writer, hypervisor.receiver_entity);
        try writeEntity(writer, hypervisor.keystone_entity);
        try writeWaypoint(writer, hypervisor.convergence_waypoint);

        try writer.writeInt(u32, @intCast(hypervisor.teleological_dependencies.items.len), .little);
        for (hypervisor.teleological_dependencies.items) |dependency| {
            try writer.writeInt(u16, dependency.prerequisite_relation.to_int(), .little);
            try writer.writeInt(u16, dependency.target_goal_relation.to_int(), .little);
        }

        try writer.writeInt(u32, @intCast(hypervisor.dream_residue_facts.items.len), .little);
        for (hypervisor.dream_residue_facts.items) |fact| {
            try writer.writeInt(u32, fact.subject.to_int(), .little);
            try writer.writeInt(u16, fact.relation.to_int(), .little);
            try writer.writeInt(u32, fact.object_or_value, .little);
        }

        if (hypervisor.branch_world) |*branch| {
            var bytes = std.array_list.Managed(u8).init(hypervisor.allocator);
            defer bytes.deinit();
            var lw1 = ListWriter.init(&bytes);
            try branch.save_state(&lw1.writer);
            if (bytes.items.len > MAX_BRANCH_BYTES) return Error.InconsistentTemporalState;
            try writer.writeInt(u32, @intCast(bytes.items.len), .little);
            try writer.writeAll(bytes.items);
        }
        try writer.writeInt(u64, hypervisor.run_seed, .little);
        if (hypervisor.branch_world != null) {
            const dice = hypervisor.branch_dice orelse return Error.InconsistentTemporalState;
            try dice.write(writer);
        }
    }

    /// Decodes and validates a temporal section without mutating `primary_world` or a hypervisor.
    /// The returned branch World is independent and is freed by `deinit` if `apply` is not called.
    pub fn read(
        allocator: std.mem.Allocator,
        primary_world: *const World,
        reader: anytype,
    ) !TemporalSnapshot {
        var snapshot = TemporalSnapshot.init(allocator);
        errdefer snapshot.deinit();

        var magic: [4]u8 = undefined;
        try reader.readSliceAll(&magic);
        if (!std.mem.eql(u8, &magic, &MAGIC)) return Error.InvalidTemporalSnapshot;
        const version = try reader.takeInt(u32, .little);
        if (version == 0 or version > VERSION) return Error.InvalidTemporalSnapshot;

        const active_byte = try reader.takeByte();
        if (active_byte > 1) return Error.InvalidTemporalSnapshot;
        snapshot.branch_active = active_byte == 1;

        snapshot.collapse_budget_ticks = try reader.takeInt(u64, .little);
        snapshot.ticks_elapsed = try reader.takeInt(u64, .little);
        const collapse_byte = try reader.takeByte();
        snapshot.collapse_state = switch (collapse_byte) {
            0 => .dormant,
            1 => .active,
            2 => .budget_expired,
            // Value 3 was the removed D-044 `.collapsed_singularity` spelling for expiry.
            // Read it as the canonical state so released version-1 envelopes remain readable
            // under D-106; writers never emit 3 again.
            3 => .budget_expired,
            4 => .resolved_and_merged,
            else => return Error.InvalidTemporalSnapshot,
        };
        if (snapshot.branch_active != (snapshot.collapse_state == .active)) {
            return Error.InvalidTemporalSnapshot;
        }

        snapshot.receiver_entity = try readEntity(reader);
        snapshot.keystone_entity = try readEntity(reader);
        snapshot.convergence_waypoint = try readWaypoint(reader);

        const dependency_count = try reader.takeInt(u32, .little);
        if (dependency_count > MAX_RECORDS) return Error.InvalidTemporalSnapshot;
        try snapshot.teleological_dependencies.ensureTotalCapacity(dependency_count);
        for (0..dependency_count) |_| {
            const prerequisite = RelationKind.from_int(try reader.takeInt(u16, .little));
            const goal = RelationKind.from_int(try reader.takeInt(u16, .little));
            snapshot.teleological_dependencies.appendAssumeCapacity(.{
                .prerequisite_relation = prerequisite,
                .target_goal_relation = goal,
            });
        }

        const residue_count = try reader.takeInt(u32, .little);
        if (residue_count > MAX_RECORDS) return Error.InvalidTemporalSnapshot;
        try snapshot.dream_residue_facts.ensureTotalCapacity(residue_count);
        for (0..residue_count) |_| {
            snapshot.dream_residue_facts.appendAssumeCapacity(.{
                .subject = EntityId.from_int(try reader.takeInt(u32, .little)),
                .relation = RelationKind.from_int(try reader.takeInt(u16, .little)),
                .object_or_value = try reader.takeInt(u32, .little),
            });
        }

        if (snapshot.branch_active) {
            const branch_len = try reader.takeInt(u32, .little);
            if (branch_len == 0 or branch_len > MAX_BRANCH_BYTES) return Error.InvalidTemporalSnapshot;
            const branch_bytes = try allocator.alloc(u8, branch_len);
            defer allocator.free(branch_bytes);
            try reader.readSliceAll(branch_bytes);

            var branch = try World.init(allocator, primary_world.arena_buffer.len);
            var branch_owned = true;
            errdefer if (branch_owned) branch.deinit();
            try branch.value_bounds.appendSlice(branch.allocator(), primary_world.value_bounds.items);
            var stream: std.Io.Reader = .fixed(branch_bytes);
            try branch.restore_state(&stream);
            var names = primary_world.display_names.iterator();
            while (names.next()) |entry| try branch.set_display_name(EntityId.from_int(entry.key_ptr.*), entry.value_ptr.*);
            var phrases = primary_world.phrase_overrides.iterator();
            while (phrases.next()) |entry| try branch.set_phrase(entry.key_ptr.*, entry.value_ptr.*);
            snapshot.branch_world = branch;
            branch_owned = false;
        }
        if (version >= 2) {
            snapshot.run_seed = try reader.takeInt(u64, .little);
            if (snapshot.branch_active) snapshot.branch_dice = dice_mod.Dice.read(reader) catch |err| return switch (err) {
                error.InvalidDice => Error.InvalidTemporalSnapshot,
                else => err,
            };
        } else if (snapshot.branch_world) |*branch| {
            snapshot.branch_dice = dice_mod.Dice.init(dice_mod.branch_seed(snapshot.run_seed, branch.current_tick));
        }

        // An inactive branch has no world of its own to validate against. The caller validates
        // those references against the primary world after restoring it.
        if (snapshot.branch_world) |*branch| try snapshot.validate(branch);
        return snapshot;
    }

    /// Moves decoded state into a live hypervisor. Existing branch state is released first.
    pub fn apply(self: *TemporalSnapshot, hypervisor: *TemporalHypervisor) !void {
        // Reserve before moving the branch World so a capacity failure cannot leave the
        // hypervisor with a new branch and old metadata.
        try hypervisor.teleological_dependencies.ensureTotalCapacity(self.teleological_dependencies.items.len);
        try hypervisor.dream_residue_facts.ensureTotalCapacity(self.dream_residue_facts.items.len);

        if (hypervisor.branch_world) |*branch| branch.deinit();
        hypervisor.branch_world = self.branch_world;
        self.branch_world = null;

        hypervisor.branch_active = self.branch_active;
        hypervisor.run_seed = self.run_seed;
        hypervisor.branch_dice = self.branch_dice;
        hypervisor.collapse_budget_ticks = self.collapse_budget_ticks;
        hypervisor.ticks_elapsed = self.ticks_elapsed;
        hypervisor.collapse_state = self.collapse_state;

        hypervisor.receiver_entity = self.receiver_entity;
        hypervisor.keystone_entity = self.keystone_entity;
        hypervisor.convergence_waypoint = self.convergence_waypoint;

        hypervisor.teleological_dependencies.clearRetainingCapacity();
        hypervisor.teleological_dependencies.appendSliceAssumeCapacity(self.teleological_dependencies.items);
        hypervisor.dream_residue_facts.clearRetainingCapacity();
        hypervisor.dream_residue_facts.appendSliceAssumeCapacity(self.dream_residue_facts.items);
    }

    pub fn validate(self: *const TemporalSnapshot, primary_world: *const World) !void {
        const world = if (self.branch_world) |*branch| branch else primary_world;
        if (self.branch_active != (self.branch_world != null)) {
            return Error.InvalidTemporalSnapshot;
        }
        try validateEntity(world, self.receiver_entity);
        try validateEntity(world, self.keystone_entity);
        for (self.teleological_dependencies.items) |dependency| {
            try validateRelation(world, dependency.prerequisite_relation);
            try validateRelation(world, dependency.target_goal_relation);
        }
        for (self.dream_residue_facts.items) |fact| {
            try validateEntity(world, fact.subject);
            try validateRelation(world, fact.relation);
        }
    }
};

fn writeEntity(writer: anytype, value: ?EntityId) !void {
    try writer.writeInt(u32, if (value) |entity| entity.to_int() else 0, .little);
}

fn readEntity(reader: anytype) !?EntityId {
    const raw = try reader.takeInt(u32, .little);
    return if (raw == 0) null else EntityId.from_int(raw);
}

fn writeWaypoint(writer: anytype, value: ?WaypointId) !void {
    try writer.writeInt(u16, value orelse 0, .little);
}

fn readWaypoint(reader: anytype) !?WaypointId {
    const raw = try reader.takeInt(u16, .little);
    return if (raw == 0) null else raw;
}

fn validateEntity(world: *const World, value: ?EntityId) !void {
    if (value) |entity| {
        if (entity.to_int() > world.entity_names.items.len) return Error.InvalidTemporalSnapshot;
    }
}

fn validateRelation(world: *const World, value: RelationKind) !void {
    if (value == .none or value.to_int() > world.relation_meta.items.len) {
        return Error.InvalidTemporalSnapshot;
    }
}

// --- Unit Tests (P31-04, D-048) ---

test "P31-04: temporal snapshot round-trips branch world, countdown, teleology, and residue" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 1024 * 1024);
    defer primary.deinit();

    const hero = try primary.intern_entity("Hero");
    const engine = try primary.intern_entity("Engine");
    const vortex = try primary.intern_entity("Vortex");
    const in_room = try primary.intern_relation("InRoom", .property);
    _ = try primary.remember(hero, in_room, vortex.to_int(), 0);

    const pipe = try primary.intern_relation("Pipe", .set);
    const flood = try primary.intern_relation("Flood", .set);

    var hypervisor = TemporalHypervisor.init(testing.allocator, &primary);
    defer hypervisor.deinit();

    _ = try hypervisor.fork_branch(10, hero, engine);
    hypervisor.set_convergence_target(42);
    try hypervisor.register_teleological_dependency(pipe, flood);
    try hypervisor.add_dream_residue(.{ .subject = hero, .relation = flood, .object_or_value = 1 });
    _ = try hypervisor.step_tick(null);
    _ = try hypervisor.step_tick(null);

    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    var lw2 = ListWriter.init(&bytes);
    try TemporalSnapshot.write(&hypervisor, &lw2.writer);

    var stream: std.Io.Reader = .fixed(bytes.items);
    var decoded = try TemporalSnapshot.read(testing.allocator, &primary, &stream);
    defer decoded.deinit();

    try testing.expect(decoded.branch_active);
    try testing.expectEqual(@as(u64, 10), decoded.collapse_budget_ticks);
    try testing.expectEqual(@as(u64, 2), decoded.ticks_elapsed);
    try testing.expectEqual(@as(usize, 1), decoded.teleological_dependencies.items.len);
    try testing.expectEqual(@as(usize, 1), decoded.dream_residue_facts.items.len);

    var restored = TemporalHypervisor.init(testing.allocator, &primary);
    defer restored.deinit();
    try decoded.apply(&restored);

    try testing.expect(restored.branch_active);
    try testing.expectEqual(@as(u64, 2), restored.ticks_elapsed);
    try testing.expectEqual(@as(?WaypointId, 42), restored.convergence_waypoint);
    try testing.expectEqual(@as(usize, 1), restored.teleological_dependencies.items.len);
    try testing.expectEqual(@as(usize, 1), restored.dream_residue_facts.items.len);
    try testing.expect(restored.branch_world.?.has_fact(hero, in_room, vortex.to_int()));
}

test "P31-04: temporal snapshot preserves a resolved branch without a branch world" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 1024 * 1024);
    defer primary.deinit();
    const hero = try primary.intern_entity("Hero");
    const engine = try primary.intern_entity("Engine");

    var hypervisor = TemporalHypervisor.init(testing.allocator, &primary);
    defer hypervisor.deinit();
    _ = try hypervisor.fork_branch(5, hero, engine);
    try hypervisor.collapse_branch(false);
    hypervisor.collapse_state = .budget_expired;

    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    var lw3 = ListWriter.init(&bytes);
    try TemporalSnapshot.write(&hypervisor, &lw3.writer);

    var stream: std.Io.Reader = .fixed(bytes.items);
    var decoded = try TemporalSnapshot.read(testing.allocator, &primary, &stream);
    defer decoded.deinit();
    try testing.expect(!decoded.branch_active);
    try testing.expect(decoded.branch_world == null);
    try testing.expectEqual(BranchCollapseState.budget_expired, decoded.collapse_state);

    // D-044's removed `.collapsed_singularity` spelling used wire value 3. Readers retain its
    // expiry meaning for D-106 compatibility, while canonical writers use value 2.
    bytes.items[4 + 4 + 1 + 8 + 8] = 3;
    var legacy_stream: std.Io.Reader = .fixed(bytes.items);
    var legacy = try TemporalSnapshot.read(testing.allocator, &primary, &legacy_stream);
    defer legacy.deinit();
    try testing.expectEqual(BranchCollapseState.budget_expired, legacy.collapse_state);

    var restored = TemporalHypervisor.init(testing.allocator, &primary);
    defer restored.deinit();
    try decoded.apply(&restored);
    try testing.expect(!restored.branch_active);
    try testing.expect(restored.branch_world == null);
    try testing.expectEqual(BranchCollapseState.budget_expired, restored.collapse_state);
}

test "P31-04: temporal snapshot rejects a corrupt branch header" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 1024 * 1024);
    defer primary.deinit();

    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    try bytes.appendSlice(&MAGIC);
    var lw4 = ListWriter.init(&bytes);
    try lw4.writer.writeInt(u32, VERSION + 1, .little);

    var stream: std.Io.Reader = .fixed(bytes.items);
    try testing.expectError(Error.InvalidTemporalSnapshot, TemporalSnapshot.read(testing.allocator, &primary, &stream));
}

test "P48-25: restored branch keeps value_bounds, display_names, and phrase_overrides" {
    const testing = std.testing;
    var primary = try World.init(testing.allocator, 256 * 1024);
    defer primary.deinit();

    const hero = try primary.intern_entity("Hero");
    const keystone = try primary.intern_entity("Keystone");
    const mercy = try primary.intern_relation_kind("Mercy", .property, .number);
    try primary.bound_relation(mercy, -10, 10);
    try primary.set_display_name(hero, "Alistair");
    try primary.set_phrase("thing_fallback", "curio");

    var hv = TemporalHypervisor.init(testing.allocator, &primary);
    defer hv.deinit();
    const branch = try hv.fork_branch(10, hero, keystone);
    try branch.remember(hero, mercy, 5, 0);

    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    var lw = ListWriter.init(&bytes);
    try TemporalSnapshot.write(&hv, &lw.writer);

    var stream: std.Io.Reader = .fixed(bytes.items);
    var decoded = try TemporalSnapshot.read(testing.allocator, &primary, &stream);
    defer decoded.deinit();

    const b = &decoded.branch_world.?;
    try testing.expect(b.value_bound(mercy) != null);
    try b.remember(hero, mercy, 99, 0);
    try testing.expectEqual(@as(?u32, 10), b.get_property(hero, mercy));
    try testing.expectEqualStrings("Alistair", b.display_text(hero).?);
    try testing.expectEqualStrings("curio", b.phrase_override("thing_fallback").?);
}
