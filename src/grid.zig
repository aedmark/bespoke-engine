//! Discrete 2D grid overlay for room topologies (P25-01) and its cellular automata (P25-02).
//!
//! A grid is static program data: its entity, room, dimensions, cell size, and origin never
//! change at runtime. Cell attributes are World facts on the grid entity, one row per set
//! attribute, so save, rewind, and branch restore capture every change P25-02's rules make
//! without a grid-specific snapshot. A cell with no attribute has no fact, which keeps the fact
//! table proportional to the populated cells rather than to the grid area (D-054).
//!
//! Automata timers are fact lifetimes (D-055): a burning cell is a `CellBurning` fact that
//! expires `burn` ticks after ignition, and smoke is a `CellSmoke` fact that expires `dissipate`
//! ticks after the fire last fed it. The remaining lifetime gives a fire's age, so no timer
//! state lives outside the World.

const std = @import("std");
const world_mod = @import("world.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;

/// Upper bound on cells per grid. Cell indexes are stored in the fact's `u32` value slot and
/// the World arena has a fixed fact capacity, so an unbounded grid could exhaust it on seeding.
pub const MAX_CELLS: u32 = 4096;
/// Upper bound on grids per program; one grid per room.
pub const MAX_GRIDS: usize = 32;

pub const Error = error{
    InvalidGrid,
    CellOutOfBounds,
    DuplicateRoomGrid,
    DuplicateGrid,
};

/// The fixed attribute vocabulary. Each attribute is a set relation on the grid entity whose
/// value is the cell index.
pub const Attribute = enum(u8) {
    flammable = 0,
    liquid = 1,
    blocking = 2,
    /// Package version 8 added the two automata attributes (P25-02).
    burning = 3,
    smoke = 4,

    pub fn relation_name(self: Attribute) []const u8 {
        return switch (self) {
            .flammable => "CellFlammable",
            .liquid => "CellLiquid",
            .blocking => "CellBlocking",
            .burning => "CellBurning",
            .smoke => "CellSmoke",
        };
    }

    fn bit(self: Attribute) u8 {
        return @as(u8, 1) << @intCast(@intFromEnum(self));
    }

    pub fn from_name(name: []const u8) ?Attribute {
        inline for (@typeInfo(Attribute).Enum.fields) |field| {
            if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

/// Unary marker asserted once a grid's declared initial layout has been written. Seeding is
/// keyed on this marker rather than on attribute presence, because a runtime rule may clear
/// every attribute of a cell (fire consuming a tapestry) and that cleared state must survive
/// re-initialisation after a restore.
pub const SEEDED_RELATION = "GridSeeded";

pub const Cell = struct {
    x: u16,
    y: u16,
};

/// Grid geometry in room coordinates. Cell (x, y) covers
/// `[origin.x + x*cell_size, origin.x + (x+1)*cell_size)` on each axis.
pub const Grid = struct {
    entity: EntityId,
    room: EntityId,
    width: u16,
    height: u16,
    cell_size: u32,
    origin_x: i32 = 0,
    origin_y: i32 = 0,

    pub fn cell_count(self: Grid) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }

    pub fn in_bounds(self: Grid, x: u32, y: u32) bool {
        return x < self.width and y < self.height;
    }

    /// Row-major index; the value stored in an attribute fact.
    pub fn index_of(self: Grid, cell: Cell) !u32 {
        if (!self.in_bounds(cell.x, cell.y)) return Error.CellOutOfBounds;
        return @as(u32, cell.y) * self.width + cell.x;
    }

    pub fn cell_of_index(self: Grid, index: u32) ?Cell {
        if (index >= self.cell_count()) return null;
        return .{ .x = @intCast(index % self.width), .y = @intCast(index / self.width) };
    }

    /// The cell containing a room-space point, or null outside the grid.
    pub fn cell_at(self: Grid, x: i32, y: i32) ?Cell {
        const size: i64 = self.cell_size;
        const dx = @as(i64, x) - self.origin_x;
        const dy = @as(i64, y) - self.origin_y;
        if (dx < 0 or dy < 0) return null;
        const cx = @divFloor(dx, size);
        const cy = @divFloor(dy, size);
        if (cx >= self.width or cy >= self.height) return null;
        return .{ .x = @intCast(cx), .y = @intCast(cy) };
    }

    /// Room-space centre of a cell, for placing marks and drawing overlays.
    pub fn cell_center(self: Grid, cell: Cell) struct { x: i32, y: i32 } {
        const half: i32 = @intCast(self.cell_size / 2);
        const size: i32 = @intCast(self.cell_size);
        return .{
            .x = self.origin_x + @as(i32, cell.x) * size + half,
            .y = self.origin_y + @as(i32, cell.y) * size + half,
        };
    }
};

pub fn validate_grid(grid: Grid) !void {
    if (grid.entity == .none or grid.room == .none) return Error.InvalidGrid;
    if (grid.width == 0 or grid.height == 0 or grid.cell_size == 0) return Error.InvalidGrid;
    if (grid.cell_count() > MAX_CELLS) return Error.InvalidGrid;
    // Cell maths runs in i32 room space; reject grids whose far edge would overflow it.
    const span_x = @as(i64, grid.width) * grid.cell_size + grid.origin_x;
    const span_y = @as(i64, grid.height) * grid.cell_size + grid.origin_y;
    if (span_x > std.math.maxInt(i32) or span_y > std.math.maxInt(i32)) return Error.InvalidGrid;
}

/// One attribute set on one cell in a declaration's initial layout.
pub const InitialCell = struct {
    index: u32,
    attribute: Attribute,
};

/// Tick rates for the grid's automata. Zero disables a rule; every field defaults to off, so a
/// grid without rules is a static overlay exactly as in P25-01.
pub const Rules = struct {
    /// Ticks a cell burns before it is spent. Zero: fires never burn out.
    burn_ticks: u32 = 0,
    /// A fire ignites its flammable, dry 4-neighbours once it has burned this many ticks.
    /// Zero: fire does not spread.
    spread_ticks: u32 = 0,
    /// Ticks smoke lingers after its fire last fed it. Zero: fires make no smoke.
    dissipate_ticks: u32 = 0,
    /// Liquid floods its non-blocking 4-neighbours on every tick divisible by this. Zero: still.
    flow_ticks: u32 = 0,

    pub fn any(self: Rules) bool {
        return self.burn_ticks != 0 or self.spread_ticks != 0 or self.dissipate_ticks != 0 or self.flow_ticks != 0;
    }
};

/// Compiler-owned declaration: geometry, the initial attribute layout seeded into World, and
/// the automata rules `step` applies.
pub const Declaration = struct {
    grid: Grid,
    cells: []const InitialCell,
    rules: Rules = .{},

    pub fn deinit_owned(self: *Declaration, allocator: std.mem.Allocator) void {
        allocator.free(self.cells);
        self.* = undefined;
    }

    pub fn validate(self: Declaration) !void {
        try validate_grid(self.grid);
        for (self.cells, 0..) |cell, i| {
            if (cell.index >= self.grid.cell_count()) return Error.CellOutOfBounds;
            for (self.cells[0..i]) |prior| {
                if (prior.index == cell.index and prior.attribute == cell.attribute) return Error.InvalidGrid;
            }
        }
    }
};

fn attribute_relation(world: *World, attribute: Attribute) !RelationKind {
    const relation = try world.intern_relation(attribute.relation_name(), .set);
    // A script may already have declared the name as a property; property overwrite would
    // collapse a grid's cells into one row, so refuse rather than corrupt the layout.
    if (world.get_relation_meta(relation).?.rel_type != .set) return Error.InvalidGrid;
    return relation;
}

/// Writes a declaration's initial layout once. Repeated calls, including after a restore,
/// leave the World unchanged so runtime cell changes are never reseeded.
pub fn seed(world: *World, declaration: Declaration) !void {
    // `host.tick` calls this every tick; check the marker before the quadratic validation so
    // an already-seeded grid costs one fact scan.
    const marker = try world.intern_relation(SEEDED_RELATION, .set);
    if (world.has_fact(declaration.grid.entity, marker, null)) return;
    try declaration.validate();
    for (declaration.cells) |cell| {
        const relation = try attribute_relation(world, cell.attribute);
        // Declared fires and smoke start their lifetimes at seeding, like any other ignition.
        const ttl: u64 = switch (cell.attribute) {
            .burning => declaration.rules.burn_ticks,
            .smoke => declaration.rules.dissipate_ticks,
            else => 0,
        };
        try world.remember(declaration.grid.entity, relation, cell.index, ttl);
    }
    try world.remember(declaration.grid.entity, marker, 0, 0);
}

/// Attribute masks and timer expiries for every cell, read in one pass over the fact table.
/// Per-cell `has_fact` calls would scan the table once per cell and neighbour each tick.
const CellState = struct {
    masks: [MAX_CELLS]u8 = [_]u8{0} ** MAX_CELLS,
    burning_expires: [MAX_CELLS]u64 = [_]u64{0} ** MAX_CELLS,
    smoke_expires: [MAX_CELLS]u64 = [_]u64{0} ** MAX_CELLS,

    fn has(self: *const CellState, index: u32, attribute: Attribute) bool {
        return self.masks[index] & attribute.bit() != 0;
    }

    fn load(self: *CellState, world: *const World, grid: Grid) void {
        var relations: [@typeInfo(Attribute).Enum.fields.len]?RelationKind = undefined;
        inline for (@typeInfo(Attribute).Enum.fields, 0..) |field, i| {
            relations[i] = world.lookup_relation(Attribute.relation_name(@enumFromInt(field.value)));
        }
        const slice = world.facts.slice();
        const subjects = slice.items(.subject);
        const relation_column = slice.items(.relation);
        const objects = slice.items(.object_or_value);
        const expirations = slice.items(.expires_at_tick);
        for (0..world.facts.len) |row| {
            if (subjects[row] != grid.entity) continue;
            const index = objects[row];
            if (index >= grid.cell_count()) continue;
            for (relations, 0..) |maybe_relation, a| {
                const relation = maybe_relation orelse continue;
                if (relation_column[row] != relation) continue;
                const attribute: Attribute = @enumFromInt(a);
                self.masks[index] |= attribute.bit();
                if (attribute == .burning) self.burning_expires[index] = expirations[row];
                if (attribute == .smoke) self.smoke_expires[index] = expirations[row];
            }
        }
    }
};

fn neighbours(grid: Grid, index: u32) struct { items: [4]u32, len: usize } {
    const cell = grid.cell_of_index(index).?;
    var out: [4]u32 = undefined;
    var len: usize = 0;
    // Fixed order: up, left, right, down. Results do not depend on it (decisions are
    // collected before any mutation), but a fixed order keeps traces reproducible.
    if (cell.y > 0) {
        out[len] = index - grid.width;
        len += 1;
    }
    if (cell.x > 0) {
        out[len] = index - 1;
        len += 1;
    }
    if (cell.x + 1 < grid.width) {
        out[len] = index + 1;
        len += 1;
    }
    if (cell.y + 1 < grid.height) {
        out[len] = index + grid.width;
        len += 1;
    }
    return .{ .items = out, .len = len };
}

/// Ignites a cell as a host action (a torch, a spell). A cell must be flammable and dry; a
/// burning cell is left alone so its lifetime is not restarted. Returns whether it caught.
pub fn ignite(world: *World, declaration: Declaration, cell: Cell) !bool {
    const grid = declaration.grid;
    const index = try grid.index_of(cell);
    if (!has_attribute(world, grid, cell, .flammable) or has_attribute(world, grid, cell, .liquid) or
        has_attribute(world, grid, cell, .burning)) return false;
    _ = world.forget(grid.entity, try attribute_relation(world, .flammable), index);
    try world.remember(grid.entity, try attribute_relation(world, .burning), index, declaration.rules.burn_ticks);
    return true;
}

/// Advances one grid by one tick (P25-02, D-055). Runs after `VM.step_tick`, so expired fires
/// and smoke are already pruned. Every decision reads the state at the start of the step and
/// all changes apply afterwards, so the result is independent of cell order:
/// 1. A fire that has burned `spread` ticks ignites flammable, dry, unlit neighbours; an
///    ignited cell stops being flammable, so a spent cell cannot relight.
/// 2. On ticks divisible by `flow`, liquid floods non-blocking dry neighbours.
/// 3. Liquid douses any fire in its cell.
/// 4. Each remaining fire refreshes its cell's smoke lifetime.
pub fn step(world: *World, declaration: Declaration) !void {
    const rules = declaration.rules;
    if (!rules.any()) return;
    const grid = declaration.grid;
    const count = grid.cell_count();
    const now = world.current_tick;

    var state = CellState{};
    state.load(world, grid);
    var ignite_set = std.StaticBitSet(MAX_CELLS).initEmpty();
    var flood_set = std.StaticBitSet(MAX_CELLS).initEmpty();
    const flows = rules.flow_ticks != 0 and now % rules.flow_ticks == 0;

    var index: u32 = 0;
    while (index < count) : (index += 1) {
        if (rules.spread_ticks != 0 and state.has(index, .burning)) {
            const expires = state.burning_expires[index];
            // A permanent fire has no ignition tick to measure from; treat it as old enough.
            const age: u64 = if (expires == 0 or rules.burn_ticks == 0)
                std.math.maxInt(u64)
            else
                rules.burn_ticks -| (expires -| now);
            if (age >= rules.spread_ticks) {
                const near = neighbours(grid, index);
                for (near.items[0..near.len]) |n| {
                    if (state.has(n, .flammable) and !state.has(n, .liquid) and !state.has(n, .burning)) ignite_set.set(n);
                }
            }
        }
        if (flows and state.has(index, .liquid)) {
            const near = neighbours(grid, index);
            for (near.items[0..near.len]) |n| {
                if (!state.has(n, .blocking) and !state.has(n, .liquid)) flood_set.set(n);
            }
        }
    }

    const flammable = try attribute_relation(world, .flammable);
    const burning = try attribute_relation(world, .burning);
    const liquid = try attribute_relation(world, .liquid);
    var it = ignite_set.iterator(.{});
    while (it.next()) |n| {
        const cell: u32 = @intCast(n);
        _ = world.forget(grid.entity, flammable, cell);
        try world.remember(grid.entity, burning, cell, rules.burn_ticks);
        state.masks[cell] = (state.masks[cell] & ~Attribute.flammable.bit()) | Attribute.burning.bit();
        state.burning_expires[cell] = if (rules.burn_ticks == 0) 0 else now + rules.burn_ticks;
    }
    it = flood_set.iterator(.{});
    while (it.next()) |n| {
        const cell: u32 = @intCast(n);
        try world.remember(grid.entity, liquid, cell, 0);
        state.masks[cell] |= Attribute.liquid.bit();
    }

    const smoke = if (rules.dissipate_ticks != 0) try attribute_relation(world, .smoke) else null;
    index = 0;
    while (index < count) : (index += 1) {
        if (!state.has(index, .burning)) continue;
        if (state.has(index, .liquid)) {
            _ = world.forget(grid.entity, burning, index);
            continue;
        }
        // Refreshing a permanent fact with a lifetime would demote it, so declared permanent
        // smoke stays permanent.
        if (smoke) |relation| {
            if (!(state.has(index, .smoke) and state.smoke_expires[index] == 0)) {
                try world.remember(grid.entity, relation, index, rules.dissipate_ticks);
            }
        }
    }
}

/// True when the cell carries the attribute in the current World.
pub fn has_attribute(world: *const World, grid: Grid, cell: Cell, attribute: Attribute) bool {
    const index = grid.index_of(cell) catch return false;
    const relation = world.lookup_relation(attribute.relation_name()) orelse return false;
    return world.has_fact(grid.entity, relation, index);
}

/// Sets or clears one cell attribute. This is the mutation P25-02's automata rules use.
pub fn set_attribute(world: *World, grid: Grid, cell: Cell, attribute: Attribute, on: bool) !void {
    const index = try grid.index_of(cell);
    const relation = try attribute_relation(world, attribute);
    if (on) {
        try world.remember(grid.entity, relation, index, 0);
    } else {
        _ = world.forget(grid.entity, relation, index);
    }
}

const testing = std.testing;

fn test_grid(world: *World) !Grid {
    return .{
        .entity = try world.intern_entity("TestGrid"),
        .room = try world.intern_entity("TestRoom"),
        .width = 4,
        .height = 3,
        .cell_size = 10,
        .origin_x = -5,
        .origin_y = 0,
    };
}

test "P25-01: grid geometry maps room points to cells and back" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const grid = try test_grid(&world);
    try validate_grid(grid);

    try testing.expectEqual(Cell{ .x = 0, .y = 0 }, grid.cell_at(-5, 0).?);
    try testing.expectEqual(Cell{ .x = 0, .y = 0 }, grid.cell_at(4, 9).?);
    try testing.expectEqual(Cell{ .x = 1, .y = 0 }, grid.cell_at(5, 9).?);
    try testing.expectEqual(Cell{ .x = 3, .y = 2 }, grid.cell_at(34, 29).?);
    try testing.expect(grid.cell_at(-6, 0) == null);
    try testing.expect(grid.cell_at(35, 0) == null);
    try testing.expect(grid.cell_at(0, 30) == null);

    try testing.expectEqual(@as(u32, 9), try grid.index_of(.{ .x = 1, .y = 2 }));
    try testing.expectEqual(Cell{ .x = 1, .y = 2 }, grid.cell_of_index(9).?);
    try testing.expect(grid.cell_of_index(12) == null);
    try testing.expectError(Error.CellOutOfBounds, grid.index_of(.{ .x = 4, .y = 0 }));

    const center = grid.cell_center(.{ .x = 2, .y = 1 });
    try testing.expectEqual(@as(i32, 20), center.x);
    try testing.expectEqual(@as(i32, 15), center.y);
    try testing.expectEqual(Cell{ .x = 2, .y = 1 }, grid.cell_at(center.x, center.y).?);
}

test "P25-01: grid validation rejects empty, oversized, and unanchored grids" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var grid = try test_grid(&world);
    grid.width = 0;
    try testing.expectError(Error.InvalidGrid, validate_grid(grid));
    grid.width = 65;
    grid.height = 64;
    try testing.expectError(Error.InvalidGrid, validate_grid(grid));
    grid = try test_grid(&world);
    grid.cell_size = 0;
    try testing.expectError(Error.InvalidGrid, validate_grid(grid));
    grid = try test_grid(&world);
    grid.room = .none;
    try testing.expectError(Error.InvalidGrid, validate_grid(grid));
}

test "P25-01: cell attributes are sparse World facts seeded once and rewound with the World" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const grid = try test_grid(&world);
    const cells = [_]InitialCell{
        .{ .index = 1, .attribute = .flammable },
        .{ .index = 1, .attribute = .blocking },
        .{ .index = 6, .attribute = .liquid },
    };
    const declaration = Declaration{ .grid = grid, .cells = &cells };

    const before = world.fact_count();
    try seed(&world, declaration);
    // Three attribute rows plus the seeded marker; empty cells cost nothing.
    try testing.expectEqual(before + 4, world.fact_count());
    try testing.expect(has_attribute(&world, grid, .{ .x = 1, .y = 0 }, .flammable));
    try testing.expect(has_attribute(&world, grid, .{ .x = 1, .y = 0 }, .blocking));
    try testing.expect(has_attribute(&world, grid, .{ .x = 2, .y = 1 }, .liquid));
    try testing.expect(!has_attribute(&world, grid, .{ .x = 0, .y = 0 }, .flammable));
    try testing.expect(!has_attribute(&world, grid, .{ .x = 9, .y = 9 }, .flammable));

    var snapshot = std.ArrayList(u8).init(testing.allocator);
    defer snapshot.deinit();
    try world.save_state(snapshot.writer());

    // A runtime change, then re-initialisation: the cleared cell stays cleared.
    try set_attribute(&world, grid, .{ .x = 1, .y = 0 }, .flammable, false);
    try set_attribute(&world, grid, .{ .x = 3, .y = 2 }, .flammable, true);
    try seed(&world, declaration);
    try testing.expect(!has_attribute(&world, grid, .{ .x = 1, .y = 0 }, .flammable));
    try testing.expect(has_attribute(&world, grid, .{ .x = 3, .y = 2 }, .flammable));

    var stream = std.io.fixedBufferStream(snapshot.items);
    try world.restore_state(stream.reader());
    try testing.expect(has_attribute(&world, grid, .{ .x = 1, .y = 0 }, .flammable));
    try testing.expect(!has_attribute(&world, grid, .{ .x = 3, .y = 2 }, .flammable));
    try testing.expectError(Error.CellOutOfBounds, set_attribute(&world, grid, .{ .x = 4, .y = 0 }, .liquid, true));
}

test "P25-01: declaration validation rejects out-of-range and duplicate cells" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const grid = try test_grid(&world);
    const outside = [_]InitialCell{.{ .index = 12, .attribute = .liquid }};
    try testing.expectError(Error.CellOutOfBounds, (Declaration{ .grid = grid, .cells = &outside }).validate());
    const twice = [_]InitialCell{ .{ .index = 2, .attribute = .liquid }, .{ .index = 2, .attribute = .liquid } };
    try testing.expectError(Error.InvalidGrid, (Declaration{ .grid = grid, .cells = &twice }).validate());
}

fn layout_mask(world: *const World, grid: Grid) [16]u8 {
    var state = CellState{};
    state.load(world, grid);
    var out: [16]u8 = undefined;
    @memcpy(&out, state.masks[0..16]);
    return out;
}

test "P25-02: fire spreads along flammable cells, burns out, and leaves dissipating smoke" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const grid = Grid{ .entity = try world.intern_entity("FireRow"), .room = try world.intern_entity("FireRoom"), .width = 4, .height = 1, .cell_size = 10 };
    const cells = [_]InitialCell{
        .{ .index = 0, .attribute = .flammable }, .{ .index = 1, .attribute = .flammable },
        .{ .index = 2, .attribute = .flammable }, .{ .index = 3, .attribute = .flammable },
    };
    const declaration = Declaration{ .grid = grid, .cells = &cells, .rules = .{ .burn_ticks = 3, .spread_ticks = 1, .dissipate_ticks = 2 } };
    try seed(&world, declaration);
    try testing.expect(try ignite(&world, declaration, .{ .x = 0, .y = 0 }));
    // A burning cell is not relit; its lifetime keeps running.
    try testing.expect(!(try ignite(&world, declaration, .{ .x = 0, .y = 0 })));

    var snapshot = std.ArrayList(u8).init(testing.allocator);
    defer snapshot.deinit();
    var at_tick_three: [16]u8 = undefined;
    var tick: u32 = 1;
    while (tick <= 3) : (tick += 1) {
        _ = world.step_tick();
        try step(&world, declaration);
        if (tick == 1) {
            try world.save_state(snapshot.writer());
            try testing.expect(has_attribute(&world, grid, .{ .x = 1, .y = 0 }, .burning));
            try testing.expect(!has_attribute(&world, grid, .{ .x = 2, .y = 0 }, .burning));
            try testing.expect(has_attribute(&world, grid, .{ .x = 0, .y = 0 }, .smoke));
        }
    }
    at_tick_three = layout_mask(&world, grid);
    // Cell 0 burned its three ticks and is spent: neither burning nor flammable.
    try testing.expect(!has_attribute(&world, grid, .{ .x = 0, .y = 0 }, .burning));
    try testing.expect(!has_attribute(&world, grid, .{ .x = 0, .y = 0 }, .flammable));
    try testing.expect(has_attribute(&world, grid, .{ .x = 0, .y = 0 }, .smoke));
    try testing.expect(has_attribute(&world, grid, .{ .x = 3, .y = 0 }, .burning));

    // Rewinding to tick 1 and replaying reproduces the same layout (D-001).
    var stream = std.io.fixedBufferStream(snapshot.items);
    try world.restore_state(stream.reader());
    try testing.expectEqual(@as(u64, 1), world.current_tick);
    _ = world.step_tick();
    try step(&world, declaration);
    _ = world.step_tick();
    try step(&world, declaration);
    try testing.expectEqualSlices(u8, &at_tick_three, &layout_mask(&world, grid));

    while (world.current_tick < 12) {
        _ = world.step_tick();
        try step(&world, declaration);
    }
    // Everything burned and every plume has dissipated.
    try testing.expectEqualSlices(u8, &([_]u8{0} ** 16), &layout_mask(&world, grid));
}

test "P25-02: liquid flows around blocking cells on its cadence and douses fire" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    // Row 0: liquid, blocking, dry. Row 1: dry, burning (permanent), dry.
    const grid = Grid{ .entity = try world.intern_entity("FloodGrid"), .room = try world.intern_entity("FloodRoom"), .width = 3, .height = 2, .cell_size = 10 };
    const cells = [_]InitialCell{
        .{ .index = 0, .attribute = .liquid },
        .{ .index = 1, .attribute = .blocking },
        .{ .index = 4, .attribute = .burning },
    };
    const declaration = Declaration{ .grid = grid, .cells = &cells, .rules = .{ .flow_ticks = 2 } };
    try seed(&world, declaration);

    _ = world.step_tick();
    try step(&world, declaration);
    try testing.expect(!has_attribute(&world, grid, .{ .x = 0, .y = 1 }, .liquid)); // tick 1: off cadence
    _ = world.step_tick();
    try step(&world, declaration);
    try testing.expect(has_attribute(&world, grid, .{ .x = 0, .y = 1 }, .liquid));
    try testing.expect(!has_attribute(&world, grid, .{ .x = 1, .y = 0 }, .liquid)); // blocking stays dry
    try testing.expect(has_attribute(&world, grid, .{ .x = 1, .y = 1 }, .burning));
    _ = world.step_tick();
    try step(&world, declaration);
    _ = world.step_tick();
    try step(&world, declaration);
    try testing.expect(has_attribute(&world, grid, .{ .x = 1, .y = 1 }, .liquid));
    try testing.expect(!has_attribute(&world, grid, .{ .x = 1, .y = 1 }, .burning));
    // A wet cell cannot be ignited.
    try set_attribute(&world, grid, .{ .x = 1, .y = 1 }, .flammable, true);
    try testing.expect(!(try ignite(&world, declaration, .{ .x = 1, .y = 1 })));
}

test "P25-02: a grid without rules is a static overlay" {
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    const grid = try test_grid(&world);
    const cells = [_]InitialCell{ .{ .index = 0, .attribute = .burning }, .{ .index = 1, .attribute = .flammable }, .{ .index = 5, .attribute = .liquid } };
    const declaration = Declaration{ .grid = grid, .cells = &cells };
    try seed(&world, declaration);
    const before = layout_mask(&world, grid);
    for (0..6) |_| {
        _ = world.step_tick();
        try step(&world, declaration);
    }
    try testing.expectEqualSlices(u8, &before, &layout_mask(&world, grid));
}
