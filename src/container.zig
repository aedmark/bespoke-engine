//! Fact-backed container degradation (P23-01).
//!
//! A container keeps one stable entity identity throughout its lifecycle. Its volume, current
//! degradation stage, exposure timer, and terminal failure location are World facts, so save,
//! rewind, and branch restore capture the complete state without subsystem-specific snapshots.

const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const SpatialSystem = spatial_mod.SpatialSystem;

pub const MAX_STAGES: usize = 8;
pub const MAX_VESSELS: usize = 32;

pub const Error = error{
    InvalidConfig,
    UnknownVessel,
    SameVessel,
    SourceEmpty,
    TargetNotEmpty,
    InsufficientCapacity,
    VesselFailed,
    InvalidState,
};

/// A stable stage entity and the exposure time before the vessel advances to the next stage.
/// The terminal stage must be last and have a duration of zero.
pub const Stage = struct {
    entity: EntityId,
    duration_ticks: u64,
};

/// One physical vessel governed by a degradation profile.
pub const Vessel = struct {
    entity: EntityId,
    capacity: u32,
    initial_volume: u32 = 0,
    initial_stage: usize = 0,
};

/// Themeable fact vocabulary. Every declaration may use distinct names when scripts need to
/// distinguish independent container agendas.
pub const Relations = struct {
    contains: []const u8 = "Contains",
    volume: []const u8 = "Volume",
    stage: []const u8 = "ContainerStage",
    exposure: []const u8 = "ContainerExposure",
    failed_at: []const u8 = "ContainerFailedAt",
};

/// Immutable script program data. All mutable lifecycle state belongs to World facts.
pub const Config = struct {
    substance: EntityId,
    stages: []const Stage,
    vessels: []const Vessel,
    spill_per_moving_tick: u32 = 0,
    relations: Relations = .{},
};

/// Compiler-owned declaration data.
pub const Declaration = struct {
    config: Config,

    pub fn deinit_owned(self: *Declaration, allocator: std.mem.Allocator) void {
        allocator.free(self.config.stages);
        allocator.free(self.config.vessels);
        self.* = undefined;
    }
};

pub const RelationIds = struct {
    contains: RelationKind,
    volume: RelationKind,
    stage: RelationKind,
    exposure: RelationKind,
    failed_at: RelationKind,
};

pub const ContainerSystem = struct {
    config: Config,
    rel: RelationIds,

    /// Validates immutable program data, interns its fact vocabulary, and seeds vessels that do
    /// not already have lifecycle facts. Existing facts are preserved when rebuilding a runtime
    /// around restored World state.
    pub fn init(world: *World, config: Config) !ContainerSystem {
        try validate(config);
        const names = config.relations;
        var self = ContainerSystem{
            .config = config,
            .rel = .{
                .contains = try world.intern_relation(names.contains, .set),
                .volume = try world.intern_relation(names.volume, .property),
                .stage = try world.intern_relation(names.stage, .property),
                .exposure = try world.intern_relation(names.exposure, .property),
                .failed_at = try world.intern_relation(names.failed_at, .property),
            },
        };
        if (world.get_relation_meta(self.rel.contains).?.rel_type != .set or
            world.get_relation_meta(self.rel.volume).?.rel_type != .property or
            world.get_relation_meta(self.rel.stage).?.rel_type != .property or
            world.get_relation_meta(self.rel.exposure).?.rel_type != .property or
            world.get_relation_meta(self.rel.failed_at).?.rel_type != .property)
        {
            return Error.InvalidConfig;
        }

        for (config.vessels) |vessel| {
            if (world.get_property(vessel.entity, self.rel.stage) != null) continue;
            const stage = config.stages[vessel.initial_stage];
            try world.remember(vessel.entity, self.rel.stage, stage.entity.to_int(), 0);
            try world.remember(vessel.entity, self.rel.volume, vessel.initial_volume, 0);
            if (vessel.initial_volume > 0) {
                try world.remember(vessel.entity, self.rel.contains, config.substance.to_int(), 0);
                try arm_exposure(&self, world, vessel.entity, stage);
            }
        }
        return self;
    }

    /// Atomically transfers all liquid between compatible vessels. Both entities retain their
    /// damage stages. The emptied source stops degrading; the destination restarts exposure at
    /// its current stage, never at the pristine stage.
    pub fn pour(self: *const ContainerSystem, world: *World, source: EntityId, target: EntityId) !u32 {
        if (source == target) return Error.SameVessel;
        _ = self.vessel_definition(source) orelse return Error.UnknownVessel;
        const target_def = self.vessel_definition(target) orelse return Error.UnknownVessel;
        if (!world.has_fact(source, self.rel.contains, self.config.substance.to_int())) return Error.SourceEmpty;
        const amount = world.get_property(source, self.rel.volume) orelse return Error.InvalidState;
        if (amount == 0) return Error.SourceEmpty;
        const target_volume = world.get_property(target, self.rel.volume) orelse return Error.InvalidState;
        if (target_volume != 0 or world.has_fact(target, self.rel.contains, null)) return Error.TargetNotEmpty;
        if (amount > target_def.capacity) return Error.InsufficientCapacity;
        const target_stage_value = world.get_property(target, self.rel.stage) orelse return Error.InvalidState;
        const target_stage_index = self.stage_index(EntityId.from_int(target_stage_value)) orelse return Error.InvalidState;
        if (target_stage_index == self.config.stages.len - 1) return Error.VesselFailed;

        // Add the two potentially allocating target facts before changing either volume. If an
        // arena-capacity error occurs, errdefer removes them and the source remains untouched.
        try world.remember(target, self.rel.contains, self.config.substance.to_int(), 0);
        errdefer _ = world.forget(target, self.rel.contains, self.config.substance.to_int());
        const target_stage = self.config.stages[target_stage_index];
        try arm_exposure(self, world, target, target_stage);
        errdefer _ = world.forget(target, self.rel.exposure, target_stage.entity.to_int());

        try world.remember(target, self.rel.volume, amount, 0);
        try world.remember(source, self.rel.volume, 0, 0);
        _ = world.forget(source, self.rel.contains, self.config.substance.to_int());
        _ = world.forget(source, self.rel.exposure, null);
        return amount;
    }

    /// True when a governed vessel currently contains the configured substance at or above the
    /// caller's delivery threshold.
    pub fn has_volume_at_least(self: *const ContainerSystem, world: *const World, vessel_entity: EntityId, threshold: u32) bool {
        if (!self.owns(vessel_entity) or !world.has_fact(vessel_entity, self.rel.contains, self.config.substance.to_int())) return false;
        return (world.get_property(vessel_entity, self.rel.volume) orelse 0) >= threshold;
    }

    /// Applies movement spill, then advances governed vessels whose current exposure fact
    /// expired in the most recent World tick. Spill goes first so a vessel emptied on the same
    /// tick as its deadline stops degrading. The stage scan avoids World.recently_expired because
    /// that diagnostic ring is intentionally bounded.
    pub fn step(self: *const ContainerSystem, world: *World, spatial: ?*const SpatialSystem) !void {
        if (self.config.spill_per_moving_tick > 0) if (spatial) |space| {
            for (self.config.vessels) |definition| {
                if (!world.has_fact(definition.entity, self.rel.contains, self.config.substance.to_int())) continue;
                if (!self.is_moving(world, space, definition.entity)) continue;
                const volume = world.get_property(definition.entity, self.rel.volume) orelse continue;
                const remaining = volume -| self.config.spill_per_moving_tick;
                try world.remember(definition.entity, self.rel.volume, remaining, 0);
                if (remaining == 0) {
                    _ = world.forget(definition.entity, self.rel.contains, self.config.substance.to_int());
                    _ = world.forget(definition.entity, self.rel.exposure, null);
                }
            }
        };

        for (self.config.vessels) |definition| {
            const vessel = definition.entity;
            if (!world.has_fact(vessel, self.rel.contains, self.config.substance.to_int())) continue;
            const stage_value = world.get_property(vessel, self.rel.stage) orelse continue;
            if (world.has_fact(vessel, self.rel.exposure, stage_value)) continue;
            const current = self.stage_index(EntityId.from_int(stage_value)) orelse continue;
            const next = current + 1;
            if (next >= self.config.stages.len) continue;
            const stage = self.config.stages[next];
            try world.remember(vessel, self.rel.stage, stage.entity.to_int(), 0);

            if (next == self.config.stages.len - 1) {
                _ = world.forget(vessel, self.rel.contains, self.config.substance.to_int());
                try world.remember(vessel, self.rel.volume, 0, 0);
                if (spatial) |space| if (space.get_current_waypoint(vessel)) |waypoint| {
                    try world.remember(vessel, self.rel.failed_at, waypoint, 0);
                };
            } else {
                try arm_exposure(self, world, vessel, stage);
            }
        }
    }

    pub fn stage_index(self: *const ContainerSystem, entity: EntityId) ?usize {
        for (self.config.stages, 0..) |stage, index| if (stage.entity == entity) return index;
        return null;
    }

    pub fn owns(self: *const ContainerSystem, entity: EntityId) bool {
        return self.vessel_definition(entity) != null;
    }

    pub fn vessel_definition(self: *const ContainerSystem, entity: EntityId) ?Vessel {
        for (self.config.vessels) |definition| if (definition.entity == entity) return definition;
        return null;
    }

    fn arm_exposure(self: *const ContainerSystem, world: *World, vessel: EntityId, stage: Stage) !void {
        if (stage.duration_ticks == 0) return;
        try world.remember(vessel, self.rel.exposure, stage.entity.to_int(), stage.duration_ticks);
    }

    fn is_moving(self: *const ContainerSystem, world: *const World, spatial: *const SpatialSystem, vessel_entity: EntityId) bool {
        _ = self;
        if (spatial.is_moving(vessel_entity)) return true;
        const carries = world.lookup_relation("Carries") orelse return false;
        var carriers = world.query(null, carries, vessel_entity.to_int());
        while (carriers.next()) |fact| if (spatial.is_moving(fact.subject)) return true;
        return false;
    }
};

pub fn validate(config: Config) !void {
    if (config.substance == .none or config.stages.len < 2 or config.stages.len > MAX_STAGES or
        config.vessels.len == 0 or config.vessels.len > MAX_VESSELS)
    {
        return Error.InvalidConfig;
    }
    for (config.stages, 0..) |stage, i| {
        if (stage.entity == .none) return Error.InvalidConfig;
        if ((i == config.stages.len - 1) != (stage.duration_ticks == 0)) return Error.InvalidConfig;
        for (config.stages[0..i]) |prior| if (prior.entity == stage.entity) return Error.InvalidConfig;
    }
    for (config.vessels, 0..) |vessel, i| {
        if (vessel.entity == .none or vessel.capacity == 0 or vessel.initial_volume > vessel.capacity or
            vessel.initial_stage >= config.stages.len - 1)
        {
            return Error.InvalidConfig;
        }
        for (config.vessels[0..i]) |prior| if (prior.entity == vessel.entity) return Error.InvalidConfig;
    }
    const r = config.relations;
    if (r.contains.len == 0 or r.volume.len == 0 or r.stage.len == 0 or r.exposure.len == 0 or r.failed_at.len == 0)
        return Error.InvalidConfig;
    const names = [_][]const u8{ r.contains, r.volume, r.stage, r.exposure, r.failed_at };
    for (names, 0..) |name, i| for (names[0..i]) |prior| if (std.mem.eql(u8, name, prior)) return Error.InvalidConfig;
}

test "P23-01: exposure degrades a stable vessel through fact-backed stages" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const reagent = try world.intern_entity("TestReagent");
    const vial = try world.intern_entity("TestVial");
    const sound = try world.intern_entity("Sound");
    const etched = try world.intern_entity("Etched");
    const failed = try world.intern_entity("Failed");
    const stages = [_]Stage{ .{ .entity = sound, .duration_ticks = 2 }, .{ .entity = etched, .duration_ticks = 1 }, .{ .entity = failed, .duration_ticks = 0 } };
    const vessels = [_]Vessel{.{ .entity = vial, .capacity = 8, .initial_volume = 5 }};
    const system = try ContainerSystem.init(&world, .{ .substance = reagent, .stages = &stages, .vessels = &vessels });
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    const room = try world.intern_entity("TestRoom");
    const bench = try spatial.graph.add_waypoint(room, 0, 0, "TestBench");
    try spatial.register_entity(vial, bench, 1);

    try testing.expectEqual(sound.to_int(), world.get_property(vial, system.rel.stage).?);
    _ = world.step_tick();
    try system.step(&world, &spatial);
    try testing.expectEqual(sound.to_int(), world.get_property(vial, system.rel.stage).?);
    _ = world.step_tick();
    try system.step(&world, &spatial);
    try testing.expectEqual(etched.to_int(), world.get_property(vial, system.rel.stage).?);
    _ = world.step_tick();
    try system.step(&world, &spatial);
    try testing.expectEqual(failed.to_int(), world.get_property(vial, system.rel.stage).?);
    try testing.expectEqual(@as(u32, 0), world.get_property(vial, system.rel.volume).?);
    try testing.expectEqual(@as(u32, bench), world.get_property(vial, system.rel.failed_at).?);
    try testing.expect(!world.has_fact(vial, system.rel.contains, reagent.to_int()));
}

test "P23-01: snapshot restore rewinds stage, volume, and exposure deadline together" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const reagent = try world.intern_entity("TestReagent");
    const vial = try world.intern_entity("TestVial");
    const sound = try world.intern_entity("Sound");
    const etched = try world.intern_entity("Etched");
    const failed = try world.intern_entity("Failed");
    const stages = [_]Stage{ .{ .entity = sound, .duration_ticks = 2 }, .{ .entity = etched, .duration_ticks = 2 }, .{ .entity = failed, .duration_ticks = 0 } };
    const vessels = [_]Vessel{.{ .entity = vial, .capacity = 8, .initial_volume = 5 }};
    const system = try ContainerSystem.init(&world, .{ .substance = reagent, .stages = &stages, .vessels = &vessels });

    _ = world.step_tick();
    try system.step(&world, null);
    var snapshot = std.ArrayList(u8).init(testing.allocator);
    defer snapshot.deinit();
    try world.save_state(snapshot.writer());

    _ = world.step_tick();
    try system.step(&world, null);
    try testing.expectEqual(etched.to_int(), world.get_property(vial, system.rel.stage).?);
    var stream = std.io.fixedBufferStream(snapshot.items);
    try world.restore_state(stream.reader());
    try testing.expectEqual(sound.to_int(), world.get_property(vial, system.rel.stage).?);
    try testing.expectEqual(@as(u32, 5), world.get_property(vial, system.rel.volume).?);

    _ = world.step_tick();
    try system.step(&world, null);
    try testing.expectEqual(etched.to_int(), world.get_property(vial, system.rel.stage).?);
}

test "P23-01: independent profiles may use distinct fact vocabularies" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const reagent = try world.intern_entity("Coolant");
    const flask = try world.intern_entity("Flask");
    const stable = try world.intern_entity("Stable");
    const broken = try world.intern_entity("Broken");
    const stages = [_]Stage{ .{ .entity = stable, .duration_ticks = 3 }, .{ .entity = broken, .duration_ticks = 0 } };
    const vessels = [_]Vessel{.{ .entity = flask, .capacity = 3 }};
    const system = try ContainerSystem.init(&world, .{
        .substance = reagent,
        .stages = &stages,
        .vessels = &vessels,
        .relations = .{ .contains = "HoldsCoolant", .volume = "CoolantVolume", .stage = "FlaskState", .exposure = "CoolantExposure", .failed_at = "FlaskFailedAt" },
    });
    try testing.expectEqualStrings("FlaskState", world.get_relation_meta(system.rel.stage).?.name);
    try testing.expect(world.lookup_relation("ContainerStage") == null);
}

test "P23-01: simultaneous transitions are not limited by the expiration diagnostic ring" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 512 * 1024);
    defer world.deinit();
    const reagent = try world.intern_entity("TestReagent");
    const sound = try world.intern_entity("Sound");
    const failed = try world.intern_entity("Failed");
    const stages = [_]Stage{ .{ .entity = sound, .duration_ticks = 1 }, .{ .entity = failed, .duration_ticks = 0 } };
    var vessels: [17]Vessel = undefined;
    var names: [17][16]u8 = undefined;
    for (&vessels, 0..) |*vessel, i| {
        const name = try std.fmt.bufPrint(&names[i], "TestVial{d}", .{i});
        vessel.* = .{ .entity = try world.intern_entity(name), .capacity = 1, .initial_volume = 1 };
    }
    const system = try ContainerSystem.init(&world, .{ .substance = reagent, .stages = &stages, .vessels = &vessels });
    _ = world.step_tick();
    try system.step(&world, null);

    try testing.expectEqual(@as(usize, 16), world.get_recently_expired().len);
    for (vessels) |vessel| try testing.expectEqual(failed.to_int(), world.get_property(vessel.entity, system.rel.stage).?);
}

test "P23-01: invalid stage ladders, vessels, and relation vocabularies are refused" {
    const testing = std.testing;
    const substance = EntityId.from_int(1);
    const sound = EntityId.from_int(2);
    const failed = EntityId.from_int(3);
    const vessel = EntityId.from_int(4);
    const valid_stages = [_]Stage{ .{ .entity = sound, .duration_ticks = 1 }, .{ .entity = failed, .duration_ticks = 0 } };
    const bad_stages = [_]Stage{ .{ .entity = sound, .duration_ticks = 0 }, .{ .entity = failed, .duration_ticks = 0 } };
    const valid_vessels = [_]Vessel{.{ .entity = vessel, .capacity = 2 }};
    const bad_vessels = [_]Vessel{.{ .entity = vessel, .capacity = 1, .initial_volume = 2 }};
    try testing.expectError(Error.InvalidConfig, validate(.{ .substance = substance, .stages = &bad_stages, .vessels = &valid_vessels }));
    try testing.expectError(Error.InvalidConfig, validate(.{ .substance = substance, .stages = &valid_stages, .vessels = &bad_vessels }));
    try testing.expectError(Error.InvalidConfig, validate(.{
        .substance = substance,
        .stages = &valid_stages,
        .vessels = &valid_vessels,
        .relations = .{ .contains = "Same", .volume = "Same" },
    }));
}

test "P23-02: pouring conserves volume and resets only the destination exposure timer" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const substance = try world.intern_entity("TestReagent");
    const source = try world.intern_entity("SourceVial");
    const target = try world.intern_entity("TargetVial");
    const sound = try world.intern_entity("Sound");
    const etched = try world.intern_entity("Etched");
    const failed = try world.intern_entity("Failed");
    const stages = [_]Stage{ .{ .entity = sound, .duration_ticks = 5 }, .{ .entity = etched, .duration_ticks = 3 }, .{ .entity = failed, .duration_ticks = 0 } };
    const vessels = [_]Vessel{
        .{ .entity = source, .capacity = 8, .initial_volume = 6, .initial_stage = 1 },
        .{ .entity = target, .capacity = 8, .initial_stage = 1 },
    };
    const system = try ContainerSystem.init(&world, .{ .substance = substance, .stages = &stages, .vessels = &vessels });

    const before = world.get_property(source, system.rel.volume).? + world.get_property(target, system.rel.volume).?;
    try testing.expectEqual(@as(u32, 6), try system.pour(&world, source, target));
    const after = world.get_property(source, system.rel.volume).? + world.get_property(target, system.rel.volume).?;
    try testing.expectEqual(before, after);
    try testing.expectEqual(etched.to_int(), world.get_property(source, system.rel.stage).?);
    try testing.expectEqual(etched.to_int(), world.get_property(target, system.rel.stage).?);
    try testing.expect(!world.has_fact(source, system.rel.exposure, null));
    const exposure = world.find_first(target, system.rel.exposure, etched.to_int()).?;
    try testing.expectEqual(world.current_tick + 3, exposure.expires_at_tick);
    try testing.expect(system.has_volume_at_least(&world, target, 6));
    try testing.expect(!system.has_volume_at_least(&world, target, 7));
    for (0..3) |_| {
        _ = world.step_tick();
        try system.step(&world, null);
    }
    try testing.expectEqual(etched.to_int(), world.get_property(source, system.rel.stage).?);
}

test "P23-02: rejected pours leave both vessels unchanged" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const substance = try world.intern_entity("TestReagent");
    const source = try world.intern_entity("SourceVial");
    const occupied = try world.intern_entity("OccupiedVial");
    const small = try world.intern_entity("SmallVial");
    const broken = try world.intern_entity("BrokenVial");
    const outsider = try world.intern_entity("OutsiderVial");
    const sound = try world.intern_entity("Sound");
    const failed = try world.intern_entity("Failed");
    const stages = [_]Stage{ .{ .entity = sound, .duration_ticks = 5 }, .{ .entity = failed, .duration_ticks = 0 } };
    const vessels = [_]Vessel{
        .{ .entity = source, .capacity = 8, .initial_volume = 6 },
        .{ .entity = occupied, .capacity = 8, .initial_volume = 1 },
        .{ .entity = small, .capacity = 3 },
        .{ .entity = broken, .capacity = 8 },
    };
    const system = try ContainerSystem.init(&world, .{ .substance = substance, .stages = &stages, .vessels = &vessels });

    try testing.expectError(Error.TargetNotEmpty, system.pour(&world, source, occupied));
    try testing.expectError(Error.InsufficientCapacity, system.pour(&world, source, small));
    try testing.expectError(Error.UnknownVessel, system.pour(&world, source, outsider));
    try world.remember(broken, system.rel.stage, failed.to_int(), 0);
    try testing.expectError(Error.VesselFailed, system.pour(&world, source, broken));
    try testing.expectEqual(@as(u32, 6), world.get_property(source, system.rel.volume).?);
    try testing.expectEqual(@as(u32, 1), world.get_property(occupied, system.rel.volume).?);
    try testing.expectEqual(@as(u32, 0), world.get_property(small, system.rel.volume).?);
    try testing.expect(world.has_fact(source, system.rel.contains, substance.to_int()));
}

test "P23-02: a carried vessel spills per moving tick and stops degrading when empty" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    const room = try world.intern_entity("TestRoom");
    const left = try spatial.graph.add_waypoint(room, 0, 0, "Left");
    const right = try spatial.graph.add_waypoint(room, 20, 0, "Right");
    try spatial.graph.connect(left, right, null);
    const carrier = try world.intern_entity("Carrier");
    try spatial.register_entity(carrier, left, 1);
    const substance = try world.intern_entity("TestReagent");
    const vessel = try world.intern_entity("TestVial");
    const sound = try world.intern_entity("Sound");
    const failed = try world.intern_entity("Failed");
    const stages = [_]Stage{ .{ .entity = sound, .duration_ticks = 2 }, .{ .entity = failed, .duration_ticks = 0 } };
    const vessels = [_]Vessel{.{ .entity = vessel, .capacity = 3, .initial_volume = 3 }};
    const system = try ContainerSystem.init(&world, .{ .substance = substance, .stages = &stages, .vessels = &vessels, .spill_per_moving_tick = 2 });
    const carries = try world.intern_relation("Carries", .set);
    try world.remember(carrier, carries, vessel.to_int(), 0);
    try testing.expect(try spatial.walk_to(carrier, right));

    _ = world.step_tick();
    try system.step(&world, &spatial);
    try testing.expectEqual(@as(u32, 1), world.get_property(vessel, system.rel.volume).?);
    _ = world.step_tick();
    try system.step(&world, &spatial);
    try testing.expectEqual(@as(u32, 0), world.get_property(vessel, system.rel.volume).?);
    try testing.expect(!world.has_fact(vessel, system.rel.contains, substance.to_int()));
    try testing.expect(!world.has_fact(vessel, system.rel.exposure, null));
    try testing.expectEqual(sound.to_int(), world.get_property(vessel, system.rel.stage).?);
}
