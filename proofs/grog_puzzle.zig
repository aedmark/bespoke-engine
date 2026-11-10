//! Caustic Grog, the Phase 23 container degradation proof (P23-03, D-050, D-051).
//!
//! Mara must carry volatile grog from a dockside barrel to Ivo's corroded cell lock. The liquid
//! eats through each cup and spills while its holder moves, so she transfers it twice before the
//! remaining volume drops below the lock's delivery threshold. All setting, dialogue, degradation
//! stages, capacities, and spill tuning live in the script; this proof owns only staging and input.
const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");
const host = bespoke.host;
const container = bespoke.container;

pub const GROG_PUZZLE_SCRIPT =
    \\scene: Saltglass Stockade
    \\cast: Mara, Ivo
    \\props: GrogBarrel, CupA, CupB, CupC, CellLock
    \\marks: BarrelMark, GalleryOne, GalleryTwo, LockMark
    \\
    \\relation Carries(holder, item)
    \\
    \\remember Carries(Mara, CupA)
    \\remember Carries(Mara, CupB)
    \\remember Carries(Mara, CupC)
    \\Ivo is imprisoned
    \\
    \\degradation CausticGrogCups:
    \\  substance CausticGrog
    \\  stage Sound 4
    \\  stage Pitted 3
    \\  stage Buckling 2
    \\  stage Failed 0
    \\  vessel CupA 10 10 Sound
    \\  vessel CupB 10 0 Sound
    \\  vessel CupC 10 0 Sound
    \\  spill 1
    \\
    \\on cue LooksAt(Mara, GrogBarrel):
    \\  say Mara: "The dockmaster's grog is strong enough to etch iron. The cups are less fortunate."
    \\
    \\on cue LooksAt(Mara, CellLock):
    \\  if CellLock is dissolved:
    \\    say Ivo: "The lock is gone. I owe you a drink that stays in its cup."
    \\  if CellLock is not dissolved:
    \\    say Ivo: "Four measures should reach the tumblers. Hurry before the cups surrender."
    \\
    \\on cue Pours(Mara, CupA, CupB):
    \\  say Mara: "Cup A hisses. I throw the grog into Cup B without losing a drop."
    \\
    \\on cue Pours(Mara, CupB, CupC):
    \\  say Mara: "Cup B starts to pit. Cup C gets the whole burning measure."
    \\
    \\on cue Dissolves(Mara, CellLock):
    \\  CellLock is dissolved
    \\  Ivo is not imprisoned
    \\  say Ivo: "The grog bites through the lock. Salt air at last!"
;

const Ids = struct {
    scene: bespoke.EntityId,
    mara: bespoke.EntityId,
    ivo: bespoke.EntityId,
    barrel: bespoke.EntityId,
    cup_a: bespoke.EntityId,
    cup_b: bespoke.EntityId,
    cup_c: bespoke.EntityId,
    lock: bespoke.EntityId,
    sound: bespoke.EntityId,
    failed: bespoke.EntityId,
    barrel_wp: u16,
    gallery_one_wp: u16,
    gallery_two_wp: u16,
    lock_wp: u16,
};

fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const scene = world.lookup_entity("Saltglass Stockade").?;
    const ids = Ids{
        .scene = scene,
        .mara = world.lookup_entity("Mara").?,
        .ivo = world.lookup_entity("Ivo").?,
        .barrel = world.lookup_entity("GrogBarrel").?,
        .cup_a = world.lookup_entity("CupA").?,
        .cup_b = world.lookup_entity("CupB").?,
        .cup_c = world.lookup_entity("CupC").?,
        .lock = world.lookup_entity("CellLock").?,
        .sound = world.lookup_entity("Sound").?,
        .failed = world.lookup_entity("Failed").?,
        .barrel_wp = spatial.graph.find_waypoint_in_room(scene, "BarrelMark").?,
        .gallery_one_wp = spatial.graph.find_waypoint_in_room(scene, "GalleryOne").?,
        .gallery_two_wp = spatial.graph.find_waypoint_in_room(scene, "GalleryTwo").?,
        .lock_wp = spatial.graph.find_waypoint_in_room(scene, "LockMark").?,
    };
    host.place_waypoint(spatial, ids.barrel_wp, 0, 4);
    host.place_waypoint(spatial, ids.gallery_one_wp, 20, 4);
    host.place_waypoint(spatial, ids.gallery_two_wp, 40, 4);
    host.place_waypoint(spatial, ids.lock_wp, 60, 4);
    spatial.graph.edges.clearRetainingCapacity();
    try spatial.graph.connect(ids.barrel_wp, ids.gallery_one_wp, null);
    try spatial.graph.connect(ids.gallery_one_wp, ids.gallery_two_wp, null);
    try spatial.graph.connect(ids.gallery_two_wp, ids.lock_wp, null);
    spatial.hotspots.clearRetainingCapacity();
    try spatial.add_hotspot(ids.barrel, scene, .{ .x = 0, .y = -4 }, 7, "Grog Barrel", "A tarred barrel breathing sharp green fumes.");
    try spatial.add_hotspot(ids.lock, scene, .{ .x = 60, .y = -3 }, 7, "Cell Lock", "A thick iron lock between Ivo and the docks.");
    try spatial.register_entity(ids.mara, ids.barrel_wp, 10);
    try spatial.register_entity(ids.ivo, ids.lock_wp, 1);
    return ids;
}

fn system_for(world: *bespoke.World, compiled: *const bespoke.CompiledProgram) !container.ContainerSystem {
    if (compiled.degradations.items.len != 1) return error.MissingGrogProfile;
    return container.ContainerSystem.init(world, compiled.degradations.items[0].config);
}

fn stage_name(world: *const bespoke.World, system: container.ContainerSystem, vessel: bespoke.EntityId) []const u8 {
    const raw = world.get_property(vessel, system.rel.stage) orelse return "unknown";
    return world.get_entity_name(bespoke.EntityId.from_int(raw)) orelse "unknown";
}

fn volume(world: *const bespoke.World, system: container.ContainerSystem, vessel: bespoke.EntityId) u32 {
    return world.get_property(vessel, system.rel.volume) orelse 0;
}

fn solved(world: *const bespoke.World, ids: Ids) bool {
    return host.has_state(world, ids.lock, "dissolved");
}

fn expect_true(value: bool, err: anyerror) !void {
    if (!value) return err;
}

/// Deterministic proof: show terminal failure, rewind it, round-trip a full save, then complete
/// the moving three-cup sprint with exact volume accounting.
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("       BeSpoke Engine: Caustic Grog (Container Degradation)        \n");
    try writer.writeAll("       (TTL Stages * Atomic Pours * Transit Spill * Rewind)        \n");
    try writer.writeAll("===================================================================\n\n");

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, GROG_PUZZLE_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);
    var system = try system_for(&world, &compiled);

    var timeline = host.Timeline.init(allocator);
    defer timeline.deinit();
    try timeline.record(&world);

    try writer.writeAll("[Failure demonstration] Mara waits beside the barrel.\n");
    var guard: usize = 0;
    while (world.get_property(ids.cup_a, system.rel.stage).? != ids.failed.to_int() and guard < 12) : (guard += 1) {
        _ = try host.tick(&vm, &compiled);
    }
    try expect_true(guard < 12, error.CupDidNotFail);
    try writer.print("  -> Cup A: {s}, volume {d}, failed at waypoint {d}.\n", .{
        stage_name(&world, system, ids.cup_a),
        volume(&world, system, ids.cup_a),
        world.get_property(ids.cup_a, system.rel.failed_at).?,
    });
    try expect_true(world.get_property(ids.cup_a, system.rel.failed_at).? == ids.barrel_wp, error.WrongFailureWaypoint);

    try writer.writeAll("\n[Rewind] Restore the opening before corrosion began.\n");
    _ = try timeline.restore(&world, 0);
    system = try system_for(&world, &compiled);
    try writer.print("  -> Cup A: {s}, volume {d}; failure fact absent.\n", .{
        stage_name(&world, system, ids.cup_a),
        volume(&world, system, ids.cup_a),
    });
    try expect_true(volume(&world, system, ids.cup_a) == 10 and world.get_property(ids.cup_a, system.rel.failed_at) == null, error.RewindFailed);

    try writer.writeAll("\n[Save] Round-trip World, Spatial, and VM before the sprint.\n");
    var save_bytes = std.ArrayList(u8).init(allocator);
    defer save_bytes.deinit();
    _ = try bespoke.write_save_state(allocator, save_bytes.writer(), &world, &spatial, &vm, .{ .description = "Caustic Grog opening" });
    _ = try host.tick(&vm, &compiled);
    var save_stream = std.io.fixedBufferStream(save_bytes.items);
    _ = try bespoke.read_save_state(allocator, save_stream.reader(), &world, &spatial, &vm);
    system = try system_for(&world, &compiled);
    try writer.print("  -> Restored tick {d}, Cup A volume {d}, Mara at BarrelMark.\n", .{ world.current_tick, volume(&world, system, ids.cup_a) });
    try expect_true(spatial.get_current_waypoint(ids.mara).? == ids.barrel_wp and volume(&world, system, ids.cup_a) == 10, error.SaveRestoreFailed);

    try writer.writeAll("\n[Sprint] Run for the lock, transferring before each cup fails.\n");
    try expect_true(try spatial.walk_to(ids.mara, ids.lock_wp), error.WalkFailed);
    _ = try host.tick(&vm, &compiled);
    _ = try host.tick(&vm, &compiled);
    try writer.print("  -> Gallery One: Cup A has {d} measures ({s}).\n", .{ volume(&world, system, ids.cup_a), stage_name(&world, system, ids.cup_a) });
    try expect_true(try system.pour(&world, ids.cup_a, ids.cup_b) == 8, error.FirstPourFailed);
    _ = try vm.fire_cue(&compiled, "Pours", ids.mara, ids.cup_a, ids.cup_b);
    _ = try host.tick(&vm, &compiled);
    var speech_buf: [256]u8 = undefined;
    if (host.speech_this_tick(&world, &vm, &speech_buf)) |line| try writer.print("  -> {s}\n", .{line});
    _ = try host.tick(&vm, &compiled);
    try writer.print("  -> Gallery Two: Cup B has {d} measures ({s}).\n", .{ volume(&world, system, ids.cup_b), stage_name(&world, system, ids.cup_b) });
    try expect_true(try system.pour(&world, ids.cup_b, ids.cup_c) == 6, error.SecondPourFailed);
    _ = try vm.fire_cue(&compiled, "Pours", ids.mara, ids.cup_b, ids.cup_c);
    _ = try host.tick(&vm, &compiled);
    if (host.speech_this_tick(&world, &vm, &speech_buf)) |line| try writer.print("  -> {s}\n", .{line});
    _ = try host.tick(&vm, &compiled);
    _ = try host.tick(&vm, &compiled);
    try writer.print("  -> LockMark: Cup C delivers {d} measures ({s}); threshold is 4.\n", .{ volume(&world, system, ids.cup_c), stage_name(&world, system, ids.cup_c) });
    try expect_true(spatial.get_current_waypoint(ids.mara).? == ids.lock_wp, error.DidNotReachLock);
    try expect_true(system.has_volume_at_least(&world, ids.cup_c, 4), error.NotEnoughGrog);

    _ = try vm.fire_cue(&compiled, "Dissolves", ids.mara, ids.lock, null);
    _ = try host.tick(&vm, &compiled);
    if (host.speech_this_tick(&world, &vm, &speech_buf)) |line| try writer.print("  -> {s}\n", .{line});
    try expect_true(solved(&world, ids), error.LockNotDissolved);

    try writer.writeAll("\n===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: Ivo is free. Volume and history agree.    \n");
    try writer.writeAll("===================================================================\n\n");
}

const action_pour_ab: u16 = 1;
const action_pour_bc: u16 = 2;
const action_unlock: u16 = 3;
const keys = [_]bespoke.display.renderer.KeyBinding{
    .{ .key = bespoke.display.renderer.c.SDLK_1, .action = action_pour_ab, .sfx = art.sfx(.sizzle) },
    .{ .key = bespoke.display.renderer.c.SDLK_2, .action = action_pour_bc, .sfx = art.sfx(.sizzle) },
    .{ .key = bespoke.display.renderer.c.SDLK_l, .action = action_unlock, .sfx = art.sfx(.sizzle) },
};
const theme = art.with_keys(&keys);

/// Native window proof. The ordinary Session supplies pause, save/load, scrub, and rewind.
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, GROG_PUZZLE_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - Caustic Grog", 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    if (window.is_headless) return run_headless(allocator, stdout);
    try stdout.writeAll("\nCaustic Grog: click LockMark to run; [1] pours A to B, [2] pours B to C, [L] uses the grog on the lock.\n");
    try stdout.writeAll("Pause/save/load, single-step, scrub, rewind, debug, and console use the standard engine controls.\n\n");

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    bridge.attach_audio_bridge(window.audio_bridge);
    bridge.set_active_character(ids.mara);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();
    window.set_cue_banner("Reach LockMark with four measures. Transfer twice before the cups fail.", 240);
    var announced = false;

    while (true) {
        const action = window.poll_events(session.frame());
        if (action == .quit) break;
        if (!(try session.handle_common(action))) switch (action) {
            .walk_player => |waypoint| _ = try spatial.walk_to(ids.mara, waypoint),
            .custom => |which| {
                var system = try system_for(&world, &compiled);
                const pair = switch (which) {
                    action_pour_ab => .{ ids.cup_a, ids.cup_b },
                    action_pour_bc => .{ ids.cup_b, ids.cup_c },
                    else => null,
                };
                if (pair) |p| {
                    const poured = system.pour(&world, p[0], p[1]) catch |err| {
                        var msg: [96]u8 = undefined;
                        window.set_cue_banner(std.fmt.bufPrint(&msg, "Pour refused: {s}", .{@errorName(err)}) catch "Pour refused.", 120);
                        session.refresh();
                        continue;
                    };
                    _ = try vm.fire_cue(&compiled, "Pours", ids.mara, p[0], p[1]);
                    _ = try session.advance();
                    var msg: [96]u8 = undefined;
                    window.set_cue_banner(std.fmt.bufPrint(&msg, "Transferred {d} measures without loss.", .{poured}) catch "Transferred.", 120);
                } else if (which == action_unlock) {
                    if (spatial.get_current_waypoint(ids.mara) != ids.lock_wp) {
                        window.set_cue_banner("Mara must stand at LockMark.", 90);
                    } else if (!system.has_volume_at_least(&world, ids.cup_c, 4)) {
                        window.set_cue_banner("Cup C does not hold four measures.", 90);
                    } else {
                        _ = try vm.fire_cue(&compiled, "Dissolves", ids.mara, ids.lock, null);
                        _ = try session.advance();
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
                    _ = try vm.fire_cue(&compiled, "LooksAt", ids.mara, frame.hotspots[index].entity, null);
                    _ = try session.advance();
                }
            },
            else => {},
        };
        if (!announced and solved(&world, ids)) {
            announced = true;
            window.set_cue_banner("The cell is open. Ivo is free.", 300);
        }
        if (action != .none and action != .step_tick and action != .toggle_pause) session.refresh();
        if (session.tick_due()) _ = try session.advance();
        session.render();
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P23-03: Caustic Grog solves, saves, and rewinds" {
    try run_headless(std.testing.allocator, std.io.null_writer);
}

test "P23-03: script owns one complete degradation profile" {
    var world = try bespoke.World.init(std.testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(std.testing.allocator, &world, &spatial, GROG_PUZZLE_SCRIPT);
    defer compiled.deinit();
    try std.testing.expectEqual(@as(usize, 1), compiled.degradations.items.len);
    try std.testing.expectEqual(@as(usize, 3), compiled.degradations.items[0].config.vessels.len);
    try std.testing.expectEqual(@as(u32, 1), compiled.degradations.items[0].config.spill_per_moving_tick);
}
