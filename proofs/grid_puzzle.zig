//! The Castle Fire Escape, the Phase 25 grid proof (P25-03, D-054, D-055).
//!
//! Wren is shut in the long gallery of Hollin Keep. The only way out is a door hidden behind a
//! hanging tapestry, so she must burn the tapestry to find it, then save the wooden door from the
//! same fire with a bucket of trough water. The grid, its flammable cells, the fire, smoke, and
//! flow rates, the hazard reactions, and all dialogue live in the script. This host owns staging,
//! input, and the two rules a script cannot yet express because it cannot read cells: the door is
//! revealed when the tapestry beside it catches, and it collapses if it burns.
const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");
const host = bespoke.host;
const grid = bespoke.grid;

pub const GRID_PUZZLE_SCRIPT =
    \\scene: Hollin Keep Gallery
    \\cast: Wren
    \\props: Trough, Bucket, WallTorch, Tapestry, HiddenDoor
    \\marks: TroughMark, TorchMark, TapestryWest, TapestryMid, TapestryEast, DoorMark
    \\
    \\relation Carries(holder, item)
    \\relation WaypointBlocked(mark)
    \\
    \\remember Carries(Wren, Bucket)
    \\remember WaypointBlocked(DoorMark)
    \\
    \\grid GalleryFloor in "Hollin Keep Gallery":
    \\  size 6 1
    \\  cell 8
    \\  flammable 2 0 4 1
    \\  place TroughMark 0 0
    \\  place TorchMark 1 0
    \\  place TapestryWest 2 0
    \\  place TapestryMid 3 0
    \\  place TapestryEast 4 0
    \\  place DoorMark 5 0
    \\  burn 8
    \\  spread 3
    \\  dissipate 4
    \\  flow 1
    \\
    \\on cue LooksAt(Wren, Trough):
    \\  say Wren: "Rainwater, cold and deep enough for a bucket."
    \\
    \\on cue LooksAt(Wren, Tapestry):
    \\  say Wren: "A moth-eaten hunting scene over dry rushes. Air moves behind it."
    \\
    \\on cue LooksAt(Wren, WallTorch):
    \\  say Wren: "The only light in the gallery, and the only flame."
    \\
    \\on cue Fills(Wren, Bucket):
    \\  Bucket is full
    \\  say Wren: "The bucket is full and heavy."
    \\
    \\on cue Ignites(Wren, Tapestry):
    \\  say Wren: "The torch touches the hem. It goes up like hay."
    \\
    \\on cue Reveals(Wren, HiddenDoor):
    \\  forget WaypointBlocked(DoorMark)
    \\  say Wren: "There, behind the burning cloth: a door!"
    \\
    \\on cue Throws(Wren, Bucket):
    \\  Bucket is not full
    \\  say Wren: "Water across the door before it catches!"
    \\
    \\on cue Collapses(Wren, HiddenDoor):
    \\  HiddenDoor is burned
    \\  say Wren: "The lintel gives way. That door is lost."
    \\
    \\when Wren is InBurningCell:
    \\  Wren is scorched
    \\  say Wren: "Fire! My cloak is alight!"
    \\
    \\when Wren is InSmokeCell:
    \\  say Wren: "Smoke. Keep low and keep moving."
    \\
    \\when Wren arrives at DoorMark:
    \\  Wren is escaped
    \\  say Wren: "Night air. I am out of the keep."
;

/// Cell indexes in the script's one-row grid. `proofs/art.zig` draws the same layout; the
/// layout test below fails if the script and these constants drift apart.
pub const TAPESTRY_FIRST_CELL: u16 = 2;
pub const TAPESTRY_EAST_CELL: u16 = 4;
pub const DOOR_CELL: u16 = 5;

const Ids = struct {
    scene: bespoke.EntityId,
    wren: bespoke.EntityId,
    trough: bespoke.EntityId,
    bucket: bespoke.EntityId,
    torch: bespoke.EntityId,
    tapestry: bespoke.EntityId,
    door: bespoke.EntityId,
    trough_wp: u16,
    torch_wp: u16,
    tapestry_east_wp: u16,
    door_wp: u16,
};

fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const scene = world.lookup_entity("Hollin Keep Gallery").?;
    const ids = Ids{
        .scene = scene,
        .wren = world.lookup_entity("Wren").?,
        .trough = world.lookup_entity("Trough").?,
        .bucket = world.lookup_entity("Bucket").?,
        .torch = world.lookup_entity("WallTorch").?,
        .tapestry = world.lookup_entity("Tapestry").?,
        .door = world.lookup_entity("HiddenDoor").?,
        .trough_wp = spatial.graph.find_waypoint_in_room(scene, "TroughMark").?,
        .torch_wp = spatial.graph.find_waypoint_in_room(scene, "TorchMark").?,
        .tapestry_east_wp = spatial.graph.find_waypoint_in_room(scene, "TapestryEast").?,
        .door_wp = spatial.graph.find_waypoint_in_room(scene, "DoorMark").?,
    };
    // Marks were placed on cell centres by the script; hotspots sit above the corridor.
    spatial.clear_hotspots();
    try spatial.add_hotspot(ids.trough, scene, .{ .x = 4, .y = -4 }, 4, "Trough", "A stone trough of rainwater.");
    try spatial.add_hotspot(ids.torch, scene, .{ .x = 12, .y = -6 }, 4, "Wall Torch", "A pitch torch in an iron bracket.");
    try spatial.add_hotspot(ids.tapestry, scene, .{ .x = 28, .y = -6 }, 10, "Tapestry", "A long hunting tapestry over dry rushes.");
    try spatial.register_entity(ids.wren, ids.trough_wp, 4);
    return ids;
}

fn declaration(compiled: *const bespoke.CompiledProgram) !grid.Declaration {
    if (compiled.grids.items.len != 1) return error.MissingGalleryGrid;
    return compiled.grids.items[0];
}

fn cell(index: u16) grid.Cell {
    return .{ .x = index, .y = 0 };
}

fn has(world: *const bespoke.World, decl: grid.Declaration, index: u16, attribute: grid.Attribute) bool {
    return grid.has_attribute(world, decl.grid, cell(index), attribute);
}

fn fires_burning(world: *const bespoke.World, decl: grid.Declaration) bool {
    var i: u16 = 0;
    while (i < decl.grid.width) : (i += 1) if (has(world, decl, i, .burning)) return true;
    return false;
}

/// The host's two door rules, run after every tick. The door is found when the tapestry cell
/// beside it ignites (it stops being flammable); it is lost if its own cell burns, which turns
/// the cell blocking so no walk can reach the mark.
fn after_tick(world: *bespoke.World, vm: *bespoke.VM, compiled: *const bespoke.CompiledProgram, ids: Ids) !void {
    const decl = try declaration(compiled);
    if (host.has_state(world, ids.door, "burned")) return;
    if (has(world, decl, DOOR_CELL, .burning)) {
        try grid.set_attribute(world, decl.grid, cell(DOOR_CELL), .blocking, true);
        _ = try vm.fire_cue(compiled, "Collapses", ids.wren, ids.door, null);
        return;
    }
    const relation = world.lookup_relation("WaypointBlocked") orelse return;
    const door_mark = world.lookup_entity("DoorMark") orelse return;
    // The cue's handler forgets the lock during the next tick, before this rule runs again,
    // so it fires once.
    if (world.has_fact(door_mark, relation, null) and !has(world, decl, TAPESTRY_EAST_CELL, .flammable)) {
        _ = try vm.fire_cue(compiled, "Reveals", ids.wren, ids.door, null);
    }
}

const Stage = struct {
    world: *bespoke.World,
    spatial: *bespoke.SpatialSystem,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    ids: Ids,

    /// One host tick, the door rules, and any line spoken during it.
    fn tick(self: Stage, writer: anytype) !void {
        _ = try host.tick(self.vm, self.compiled);
        try after_tick(self.world, self.vm, self.compiled, self.ids);
        var buf: [256]u8 = undefined;
        if (host.speech_this_tick(self.world, self.vm, &buf)) |line| try writer.print("  [{d:>2}] {s}\n", .{ self.world.current_tick, line });
    }

    fn tick_until(self: Stage, writer: anytype, comptime done: fn (Stage) bool, limit: usize, err: anyerror) !void {
        var guard: usize = 0;
        while (!done(self)) : (guard += 1) {
            if (guard >= limit) return err;
            try self.tick(writer);
        }
    }

    fn walk(self: Stage, dest: u16) !bool {
        return self.spatial.walk_to_with_world(self.world, self.ids.wren, dest);
    }

    fn ignite_tapestry(self: Stage, writer: anytype) !void {
        const decl = try declaration(self.compiled);
        if (!(try grid.ignite(self.world, decl, cell(TAPESTRY_FIRST_CELL)))) return error.TapestryWouldNotCatch;
        _ = try self.vm.fire_cue(self.compiled, "Ignites", self.ids.wren, self.ids.tapestry, null);
        try self.tick(writer);
    }

    fn at(self: Stage, wp: u16) bool {
        return self.spatial.get_current_waypoint(self.ids.wren) == wp and !self.spatial.is_moving(self.ids.wren);
    }
};

fn at_torch(s: Stage) bool {
    return s.at(s.ids.torch_wp);
}
fn scorched(s: Stage) bool {
    return host.has_state(s.world, s.ids.wren, "scorched");
}
fn door_found(s: Stage) bool {
    const relation = s.world.lookup_relation("WaypointBlocked") orelse return true;
    return !s.world.has_fact(s.world.lookup_entity("DoorMark").?, relation, null);
}
fn door_lost(s: Stage) bool {
    return host.has_state(s.world, s.ids.door, "burned");
}
fn fire_out(s: Stage) bool {
    return !fires_burning(s.world, declaration(s.compiled) catch return true);
}
fn escaped(s: Stage) bool {
    return host.has_state(s.world, s.ids.wren, "escaped");
}

fn expect_true(value: bool, err: anyerror) !void {
    if (!value) return err;
}

fn print_row(writer: anytype, world: *const bespoke.World, decl: grid.Declaration) !void {
    try writer.writeAll("  -> Gallery: ");
    var i: u16 = 0;
    while (i < decl.grid.width) : (i += 1) {
        const glyph: u8 = if (has(world, decl, i, .burning))
            'F'
        else if (has(world, decl, i, .blocking))
            '#'
        else if (has(world, decl, i, .liquid))
            '~'
        else if (has(world, decl, i, .smoke))
            's'
        else if (has(world, decl, i, .flammable))
            't'
        else
            '.';
        try writer.writeByte(glyph);
    }
    try writer.writeAll("  (t tapestry, F fire, s smoke, ~ water, # rubble)\n");
}

fn checkpoint(allocator: std.mem.Allocator, stage: Stage, out: *std.ArrayList(u8)) !void {
    out.clearRetainingCapacity();
    _ = try bespoke.write_save_state(allocator, out.writer(), stage.world, stage.spatial, stage.vm, .{ .description = "Castle Fire Escape opening" });
}

fn restore(allocator: std.mem.Allocator, stage: Stage, bytes: []const u8) !void {
    var stream = std.io.fixedBufferStream(bytes);
    _ = try bespoke.read_save_state(allocator, stream.reader(), stage.world, stage.spatial, stage.vm);
}

/// Deterministic proof: two failures (walking into the fire; letting the door burn), each
/// undone by restoring a full save, then the solution with fire, smoke, flow, and dousing.
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("       BeSpoke Engine: The Castle Fire Escape (Grid Automata)      \n");
    try writer.writeAll("       (Fire Spread * Smoke * Water Flow * Hazard Rules * Rewind)  \n");
    try writer.writeAll("===================================================================\n\n");

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, GRID_PUZZLE_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);
    try host.initialize_subsystems(&world, &compiled);
    const decl = try declaration(&compiled);
    const stage = Stage{ .world = &world, .spatial = &spatial, .vm = &vm, .compiled = &compiled, .ids = ids };

    var opening = std.ArrayList(u8).init(allocator);
    defer opening.deinit();
    try checkpoint(allocator, stage, &opening);
    try print_row(writer, &world, decl);
    try expect_true(!(try stage.walk(ids.door_wp)), error.HiddenDoorReachable);

    try writer.writeAll("\n[Failure 1] Wren lights the tapestry and runs straight through it.\n");
    try expect_true(try stage.walk(ids.torch_wp), error.WalkFailed);
    try stage.tick_until(writer, at_torch, 12, error.NeverReachedTorch);
    try stage.ignite_tapestry(writer);
    try expect_true(try stage.walk(ids.tapestry_east_wp), error.WalkFailed);
    try stage.tick_until(writer, scorched, 12, error.NeverScorched);
    try print_row(writer, &world, decl);

    try writer.writeAll("\n[Rewind] Restore the saved opening.\n");
    try restore(allocator, stage, opening.items);
    try expect_true(!scorched(stage) and has(&world, decl, TAPESTRY_FIRST_CELL, .flammable) and stage.at(ids.trough_wp), error.RewindFailed);
    try print_row(writer, &world, decl);

    try writer.writeAll("\n[Failure 2] Wren lights the tapestry from the torch and only watches.\n");
    try expect_true(try stage.walk(ids.torch_wp), error.WalkFailed);
    try stage.tick_until(writer, at_torch, 12, error.NeverReachedTorch);
    try stage.ignite_tapestry(writer);
    try stage.tick_until(writer, door_lost, 16, error.DoorNeverBurned);
    try print_row(writer, &world, decl);
    try expect_true(!(try stage.walk(ids.door_wp)), error.CollapsedDoorReachable);
    try writer.writeAll("  -> DoorMark sits in a blocking cell; no walk can reach it.\n");

    try writer.writeAll("\n[Rewind] Restore the saved opening again.\n");
    try restore(allocator, stage, opening.items);
    try expect_true(!door_lost(stage) and !has(&world, decl, DOOR_CELL, .blocking), error.RewindFailed);

    try writer.writeAll("\n[Solution] Fill the bucket, burn the tapestry, save the door, walk out.\n");
    _ = try vm.fire_cue(&compiled, "Fills", ids.wren, ids.bucket, null);
    try stage.tick(writer);
    try expect_true(try stage.walk(ids.torch_wp), error.WalkFailed);
    try stage.tick_until(writer, at_torch, 12, error.NeverReachedTorch);
    try stage.ignite_tapestry(writer);
    try stage.tick_until(writer, door_found, 12, error.DoorNeverFound);
    try print_row(writer, &world, decl);
    try expect_true(host.has_state(&world, ids.bucket, "full"), error.BucketEmpty);
    try grid.set_attribute(&world, decl.grid, cell(DOOR_CELL), .liquid, true);
    _ = try vm.fire_cue(&compiled, "Throws", ids.wren, ids.bucket, null);
    try stage.tick(writer);
    try print_row(writer, &world, decl);
    try stage.tick_until(writer, fire_out, 12, error.FireNeverOut);
    try print_row(writer, &world, decl);
    try expect_true(!door_lost(stage) and !scorched(stage), error.DoorLost);
    try expect_true(try stage.walk(ids.door_wp), error.DoorUnreachable);
    try stage.tick_until(writer, escaped, 16, error.NeverEscaped);
    try expect_true(!scorched(stage), error.Scorched);

    try writer.writeAll("\n===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: Wren is out. The keep burned as written.  \n");
    try writer.writeAll("===================================================================\n\n");
}

const action_fill: u16 = 1;
const action_torch: u16 = 2;
const action_throw: u16 = 3;
const keys = [_]bespoke.display.renderer.KeyBinding{
    .{ .key = bespoke.display.renderer.c.SDLK_1, .action = action_fill },
    .{ .key = bespoke.display.renderer.c.SDLK_2, .action = action_torch },
    .{ .key = bespoke.display.renderer.c.SDLK_3, .action = action_throw, .sfx = art.sfx(.sizzle) },
};
const theme = art.with_keys(&keys);

/// Shows what the script said during the last tick on the banner. The window draws no speech
/// by itself, so every tick that can carry a line is followed by this.
fn show_speech(window: *bespoke.display.DisplayWindow, world: *bespoke.World, vm: *bespoke.VM) void {
    var buf: [512]u8 = undefined;
    if (host.speech_this_tick(world, vm, &buf)) |line| window.set_cue_banner(line, 300);
}

/// Native window proof. The ordinary Session supplies pause, save/load, scrub, and rewind.
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, GRID_PUZZLE_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);
    try host.initialize_subsystems(&world, &compiled);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Castle Fire Escape", 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    if (window.is_headless) return run_headless(allocator, stdout);
    try stdout.writeAll("\nCastle Fire Escape: click marks to walk; [1] fills the bucket at the trough, [2] puts the torch to the tapestry, [3] throws the bucket at the door.\n");
    try stdout.writeAll("Pause/save/load, single-step, scrub, rewind, debug, and console use the standard engine controls.\n\n");

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    bridge.attach_audio_bridge(window.audio_bridge);
    bridge.set_active_character(ids.wren);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();
    window.set_cue_banner("Find the way out of the gallery. Mind the fire you start.", 240);
    var announced_escape = false;

    while (true) {
        const action = window.poll_events(session.frame());
        if (action == .quit) break;
        if (!(try session.handle_common(action))) switch (action) {
            .walk_player => |waypoint| {
                if (!(try spatial.walk_to_with_world(&world, ids.wren, waypoint))) window.set_cue_banner("That way is blocked.", 90);
            },
            .custom => |which| {
                const decl = try declaration(&compiled);
                if (which == action_fill) {
                    if (spatial.get_current_waypoint(ids.wren) != ids.trough_wp) {
                        window.set_cue_banner("Wren must stand at the trough.", 90);
                    } else {
                        _ = try vm.fire_cue(&compiled, "Fills", ids.wren, ids.bucket, null);
                        _ = try session.advance();
                        show_speech(&window, &world, &vm);
                    }
                } else if (which == action_torch) {
                    if (spatial.get_current_waypoint(ids.wren) != ids.torch_wp) {
                        window.set_cue_banner("Wren must stand at the torch.", 90);
                    } else if (try grid.ignite(&world, decl, cell(TAPESTRY_FIRST_CELL))) {
                        _ = try vm.fire_cue(&compiled, "Ignites", ids.wren, ids.tapestry, null);
                        _ = try session.advance();
                        show_speech(&window, &world, &vm);
                    } else window.set_cue_banner("The tapestry will not catch.", 90);
                } else if (which == action_throw) {
                    if (!host.has_state(&world, ids.bucket, "full")) {
                        window.set_cue_banner("The bucket is empty.", 90);
                    } else {
                        try grid.set_attribute(&world, decl.grid, cell(DOOR_CELL), .liquid, true);
                        _ = try vm.fire_cue(&compiled, "Throws", ids.wren, ids.bucket, null);
                        _ = try session.advance();
                        show_speech(&window, &world, &vm);
                    }
                }
            },
            .examine_hotspot, .interact_hotspot => {
                const frame = session.frame();
                const index: usize = switch (action) {
                    .examine_hotspot => |i| i,
                    .interact_hotspot => |h| h.hotspot_index,
                    else => unreachable,
                };
                if (index < frame.hotspot_count) {
                    _ = try vm.fire_cue(&compiled, "LooksAt", ids.wren, frame.hotspots[index].entity, null);
                    _ = try session.advance();
                    show_speech(&window, &world, &vm);
                }
            },
            else => {},
        };
        if (action != .none and action != .step_tick and action != .toggle_pause) session.refresh();
        if (session.tick_due()) {
            _ = try session.advance();
            try after_tick(&world, &vm, &compiled, ids);
            show_speech(&window, &world, &vm);
        }
        if (!announced_escape and host.has_state(&world, ids.wren, "escaped")) {
            announced_escape = true;
            window.set_cue_banner("Wren is out of Hollin Keep.", 300);
        }
        session.render();
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P25-03: Castle Fire Escape fails twice, rewinds, and escapes" {
    try run_headless(std.testing.allocator, std.io.null_writer);
}

test "P25-03: script grid matches the cell layout the host and art assume" {
    var world = try bespoke.World.init(std.testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(std.testing.allocator, &world, &spatial, GRID_PUZZLE_SCRIPT);
    defer compiled.deinit();
    const decl = try declaration(&compiled);
    try std.testing.expectEqual(art.GALLERY_CELLS, decl.grid.width);
    try std.testing.expectEqual(@as(u16, 1), decl.grid.height);
    try std.testing.expectEqual(art.GALLERY_CELL_SIZE, decl.grid.cell_size);
    const ids = try configure(&world, &spatial);
    try std.testing.expectEqual(grid.Cell{ .x = DOOR_CELL, .y = 0 }, spatial.waypoint_cell(ids.door_wp).?.cell);
    try std.testing.expectEqual(grid.Cell{ .x = TAPESTRY_EAST_CELL, .y = 0 }, spatial.waypoint_cell(ids.tapestry_east_wp).?.cell);
    try std.testing.expect(decl.rules.flow_ticks > 0 and decl.rules.spread_ticks > 0);
}
