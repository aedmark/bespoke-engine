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

    /// Advances governed vessels whose current exposure fact expired in the most recent World
    /// tick. This scans vessels instead of World.recently_expired because that diagnostic ring is
    /// intentionally bounded and must not limit simultaneous simulation transitions.
    pub fn step(self: *const ContainerSystem, world: *World, spatial: ?*const SpatialSystem) !void {
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
        for (self.config.vessels) |vessel| if (vessel.entity == entity) return true;
        return false;
    }

    fn arm_exposure(self: *const ContainerSystem, world: *World, vessel: EntityId, stage: Stage) !void {
        if (stage.duration_ticks == 0) return;
        try world.remember(vessel, self.rel.exposure, stage.entity.to_int(), stage.duration_ticks);
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
