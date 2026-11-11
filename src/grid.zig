//! Discrete 2D grid overlay for room topologies (P25-01).
//!
//! A grid is static program data: its entity, room, dimensions, cell size, and origin never
//! change at runtime. Cell attributes are World facts on the grid entity, one row per set
//! attribute, so save, rewind, and branch restore capture every change P25-02's rules make
//! without a grid-specific snapshot. A cell with no attribute has no fact, which keeps the fact
//! table proportional to the populated cells rather than to the grid area (D-054).

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

    pub fn relation_name(self: Attribute) []const u8 {
        return switch (self) {
            .flammable => "CellFlammable",
            .liquid => "CellLiquid",
            .blocking => "CellBlocking",
        };
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

/// Compiler-owned declaration: geometry plus the initial attribute layout seeded into World.
pub const Declaration = struct {
    grid: Grid,
    cells: []const InitialCell,

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
        try world.remember(declaration.grid.entity, relation, cell.index, 0);
    }
    try world.remember(declaration.grid.entity, marker, 0, 0);
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
