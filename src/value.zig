//! Value axes (P45-01, D-144): author-declared virtues a character holds from -10 to +10.
//!
//! The engine names no axis. A script declares `axis Mercy between Vengeance and "Condoning
//! Harm"`, which makes `Mercy` a property relation bounded to the range, so
//! `remember Mercy(Oswin, 8)` stores one row per character and a later write overwrites it
//! (D-007). +10 is the virtue held fully; the two poles name the ways it fails and are labels for
//! later items (P45-03 lines), not ends of the number line. The value slot holds the integer as
//! two's complement, and `World` clamps every write into the range, so a host call, a loaded
//! save, or later drift (P45-04) can never store a value the compiler would have rejected.
const std = @import("std");
const limits_mod = @import("limits.zig");
const world_mod = @import("world.zig");
const World = world_mod.World;
const EntityId = world_mod.EntityId;
const RelationKind = world_mod.RelationKind;

pub const MIN: i32 = -10;
pub const MAX: i32 = 10;
/// Axes one program declares: a sanity ceiling a script raises with `limit`, and `MAX_` the
/// fixed safety cap past which a package's count is corrupt input (D-183).
pub const DEFAULT_AXES: usize = limits_mod.default_of(.axes);
pub const MAX_AXES: usize = limits_mod.cap_of(.axes);

/// Drift points that move a value on this axis one step (D-148, D-183): an author setting,
/// `drift step N` under the axis. One number per axis, because a character's points on it
/// pile up across every dilemma that drifts it.
pub const DEFAULT_DRIFT_STEP: u8 = 5;
pub const MAX_DRIFT_STEP: u8 = 20;

pub const Error = error{InvalidAxis};

/// One declared axis. `relation` is the property relation named after the virtue; `poles` are
/// entities so a package stores them as references and a later line can name one.
pub const Axis = struct {
    relation: RelationKind,
    poles: [2]EntityId,
    drift_step: u8 = DEFAULT_DRIFT_STEP,
};

/// Checks one axis against the world it belongs to: the relation exists, is a property, and
/// carries exactly this module's range; the poles are distinct entities.
pub fn validate(world: *const World, axis: Axis) Error!void {
    const meta = world.get_relation_meta(axis.relation) orelse return Error.InvalidAxis;
    if (meta.rel_type != .property) return Error.InvalidAxis;
    const bound = world.value_bound(axis.relation) orelse return Error.InvalidAxis;
    if (bound.min != MIN or bound.max != MAX) return Error.InvalidAxis;
    for (axis.poles) |pole| {
        if (pole == .none or world.get_entity_name(pole) == null) return Error.InvalidAxis;
    }
    if (axis.poles[0] == axis.poles[1]) return Error.InvalidAxis;
    if (axis.drift_step == 0 or axis.drift_step > MAX_DRIFT_STEP) return Error.InvalidAxis;
}

/// The drift step of the axis whose relation is `relation`, or the default for an axis the
/// list does not hold.
pub fn drift_step_of(axes: []const Axis, relation: RelationKind) u8 {
    for (axes) |axis| if (axis.relation == relation) return axis.drift_step;
    return DEFAULT_DRIFT_STEP;
}

pub fn validate_all(world: *const World, axes: []const Axis) Error!void {
    if (axes.len > MAX_AXES) return Error.InvalidAxis;
    for (axes, 0..) |axis, i| {
        try validate(world, axis);
        for (axes[0..i]) |prior| if (prior.relation == axis.relation) return Error.InvalidAxis;
    }
}

/// Declares an axis in a world: interns its property relation and bounds it. A relation of the
/// same name that is already a set cannot become an axis.
pub fn declare(world: *World, name: []const u8, poles: [2][]const u8) !Axis {
    if (world.lookup_relation(name)) |existing| {
        if (world.get_relation_meta(existing).?.rel_type != .property) return Error.InvalidAxis;
    }
    const relation = try world.intern_relation_kind(name, .property, .number);
    world.bound_relation(relation, MIN, MAX) catch return Error.InvalidAxis;
    // The axis is also an entity of the same name, so a typed `appeal to mercy` or `ask Oswin
    // about mercy` can name it (P45-05).
    _ = try world.intern_entity(name);
    const axis = Axis{
        .relation = relation,
        .poles = .{ try world.intern_entity(poles[0]), try world.intern_entity(poles[1]) },
    };
    try validate(world, axis);
    return axis;
}

/// The entity a character's value on an axis is known as: `Mercy of Oswin` (P45-05, D-149).
/// Knowing a value is `Knows(Player, <that entity>)`, the knowledge model every hint and
/// presentation reads, so a value is learned per character rather than per axis.
pub fn known_value(world: *World, axis: RelationKind, character: EntityId) !EntityId {
    var buf: [128]u8 = undefined;
    return world.intern_entity(try known_value_name(world, axis, character, &buf));
}

/// The name of that entity without interning it, for readers that hold a const World.
pub fn known_value_name(world: *const World, axis: RelationKind, character: EntityId, buf: []u8) ![]const u8 {
    const axis_name = (world.get_relation_meta(axis) orelse return Error.InvalidAxis).name;
    const character_name = world.get_entity_name(character) orelse return Error.InvalidAxis;
    return std.fmt.bufPrint(buf, "{s} of {s}", .{ axis_name, character_name }) catch Error.InvalidAxis;
}

/// The axis an entity names, when it is an axis's entity (`Mercy`), or null.
pub fn axis_of_entity(world: *const World, entity: EntityId) ?RelationKind {
    const name = world.get_entity_name(entity) orelse return null;
    const relation = world.lookup_relation(name) orelse return null;
    const bound = world.value_bound(relation) orelse return null;
    if (bound.min != MIN or bound.max != MAX) return null;
    return relation;
}

/// Encodes a script literal for the value slot, or null when it is not a whole number in range.
pub fn encode_literal(text: []const u8) ?u32 {
    const value = std.fmt.parseInt(i32, text, 10) catch return null;
    if (value < MIN or value > MAX) return null;
    return @bitCast(value);
}

/// A character's value on an axis, or null when it holds none.
pub fn value_of(world: *const World, character: EntityId, axis: Axis) ?i32 {
    const raw = world.get_property(character, axis.relation) orelse return null;
    return @bitCast(raw);
}

test "P45-01: an axis bounds its property and reads signed values" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const axis = try declare(&world, "Mercy", .{ "Vengeance", "Condoning Harm" });
    const oswin = try world.intern_entity("Oswin");
    try testing.expect(value_of(&world, oswin, axis) == null);
    try world.remember(oswin, axis.relation, encode_literal("-3").?, 0);
    try testing.expectEqual(@as(i32, -3), value_of(&world, oswin, axis).?);
    try world.remember(oswin, axis.relation, encode_literal("8").?, 0);
    try testing.expectEqual(@as(i32, 8), value_of(&world, oswin, axis).?);
    try testing.expectEqual(@as(usize, 1), world.fact_count());
    try testing.expect(encode_literal("11") == null);
    try testing.expect(encode_literal("-11") == null);
    try testing.expect(encode_literal("Mercy") == null);
    try testing.expectEqualStrings("Condoning Harm", world.get_entity_name(axis.poles[1]).?);

    // A set relation of the same name cannot become an axis.
    _ = try world.intern_relation("Carries", .set);
    try testing.expectError(Error.InvalidAxis, declare(&world, "Carries", .{ "Hoarding", "Squandering" }));
    try validate_all(&world, &.{axis});
    try testing.expectError(Error.InvalidAxis, validate_all(&world, &.{ axis, axis }));
}
