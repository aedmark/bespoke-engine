//! The Larkspur Observatory, the Phase 33 social agency proof (P33-03, D-038, D-056).
//!
//! 1958, a mountain observatory, and the photographic plate that shows a new comet is gone.
//! Ines Varga, a junior astronomer, investigates while three staff go about their routines:
//! Director Halloran steers her away from the darkroom, Dr. Pell plants an alibi if she reads the
//! telescope log before she holds the exposure slip, and Moss the night porter warns anyone who
//! lingers by the generator shed. The agendas, their triggers, the encounters, and the evidence
//! rebuttals all live in the script; this host owns staging, input, and the society tick.
const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");
const host = bespoke.host;
const agency = bespoke.agency;
const society = bespoke.society;

pub const OBSERVATORY_SCRIPT =
    \\scene: Larkspur Observatory
    \\cast: Ines, Halloran, Pell, Moss
    \\props: StainedGlove, ExposureSlip, TelescopeLog
    \\marks: CablePlatform, Stair, Terrace, MessHall, Dormitory, GeneratorShed, Darkroom, Dome, TelescopeFloor, Archive, Office, Library
    \\
    \\grid LarkspurPlan in "Larkspur Observatory":
    \\  size 6 2
    \\  cell 8
    \\  place CablePlatform 0 0
    \\  place Stair 1 0
    \\  place Terrace 2 0
    \\  place MessHall 3 0
    \\  place Dormitory 4 0
    \\  place GeneratorShed 5 0
    \\  place Library 0 1
    \\  place Office 1 1
    \\  place Archive 2 1
    \\  place TelescopeFloor 3 1
    \\  place Dome 4 1
    \\  place Darkroom 5 1
    \\
    \\relation Carries(holder, item)
    \\relation Investigated(who, place)
    \\relation Read(who, item)
    \\relation Warned(who)
    \\relation Believes(who, claim)
    \\relation NearShed(who)
    \\
    \\society LarkspurStaff:
    \\  need Rest low 100 0 0 22 stay Dormitory 14 90 sleeping true "weary" "rest"
    \\  member Halloran 0 working:
    \\    need Rest 95 none none
    \\    routine working 6 Office, Dome
    \\  member Pell 0 working:
    \\    need Rest 95 none none
    \\    routine working 5 Library, MessHall
    \\  member Moss 0 working:
    \\    need Rest 95 none none
    \\    routine working 8 Stair, GeneratorShed, Terrace
    \\  gathering Terrace
    \\  flight Stair Dormitory 4
    \\
    \\agenda Dissuade:
    \\  actor Halloran
    \\  target Ines
    \\  priority 5
    \\  once
    \\  requires Investigated(Ines, Darkroom)
    \\  unless Warned(Ines)
    \\
    \\agenda PlantAlibi:
    \\  actor Pell
    \\  target Ines
    \\  priority 3
    \\  once
    \\  requires Read(Ines, TelescopeLog)
    \\  unless Carries(Ines, ExposureSlip)
    \\
    \\agenda ShedWarning:
    \\  actor Moss
    \\  target Ines
    \\  priority 1
    \\  cooldown 40
    \\  requires NearShed(Ines)
    \\
    \\on cue Searches(Ines, Darkroom):
    \\  remember Investigated(Ines, Darkroom)
    \\  say Ines: "Trays of developer, still wet. Someone printed a plate tonight."
    \\
    \\on cue Takes(Ines, StainedGlove):
    \\  remember Carries(Ines, StainedGlove)
    \\  say Ines: "A cotton glove, stained brown with developer. Monogrammed H."
    \\
    \\on cue Takes(Ines, ExposureSlip):
    \\  remember Carries(Ines, ExposureSlip)
    \\  say Ines: "The exposure slip: plate 41, logged at 02:10 from the dome."
    \\
    \\on cue Reads(Ines, TelescopeLog):
    \\  remember Read(Ines, TelescopeLog)
    \\  say Ines: "Plate 41 was exposed at 02:10. Who was at the telescope?"
    \\
    \\when Ines arrives at GeneratorShed:
    \\  remember NearShed(Ines) for 30 ticks
    \\
    \\on cue Intercepts(Halloran, Ines, Dissuade):
    \\  remember Warned(Ines)
    \\  if Carries(Ines, StainedGlove):
    \\    Halloran is exposed
    \\    say Halloran: "That glove... I can explain. The plate is safe in my office."
    \\  if not Carries(Ines, StainedGlove):
    \\    Ines is dissuaded
    \\    say Halloran: "The darkroom is no place to wander at night, Miss Varga. Go to bed."
    \\
    \\on cue Intercepts(Pell, Ines, PlantAlibi):
    \\  remember Believes(Ines, PellInLibrary)
    \\  say Pell: "I was in the library from midnight to three. Ask anyone."
    \\
    \\on cue Intercepts(Moss, Ines, ShedWarning):
    \\  say Moss: "Mind the cables, miss. The director was down here at two, swearing at the fuses."
    \\
    \\on cue TalksTo(Ines, Pell):
    \\  if Carries(Ines, ExposureSlip):
    \\    Pell is cornered
    \\    say Pell: "02:10 from the dome? Then it was not me at the telescope. Ask Halloran."
;

const Ids = struct {
    scene: bespoke.EntityId,
    ines: bespoke.EntityId,
    halloran: bespoke.EntityId,
    pell: bespoke.EntityId,
    moss: bespoke.EntityId,
    glove: bespoke.EntityId,
    slip: bespoke.EntityId,
    log: bespoke.EntityId,
    darkroom: bespoke.EntityId,
    dissuade: bespoke.EntityId,
    plant_alibi: bespoke.EntityId,
    shed_warning: bespoke.EntityId,
    archive_wp: u16,
    darkroom_wp: u16,
    telescope_wp: u16,
    shed_wp: u16,
};

/// Two floors of six rooms, placed by the script's `LarkspurPlan` grid: the public floor above
/// (platform to the generator shed) and the working floor below (library to darkroom). The
/// marks are listed so the compiler's chain runs along the public floor, down the shed stair,
/// and back along the working floor; the host adds the other two stairs.
const Layout = struct {
    const links = [_][2][]const u8{ .{ "CablePlatform", "Library" }, .{ "MessHall", "TelescopeFloor" } };
};

fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const scene = world.lookup_entity("Larkspur Observatory").?;
    const find = struct {
        fn wp(sp: *bespoke.SpatialSystem, room: bespoke.EntityId, name: []const u8) !u16 {
            return sp.graph.find_waypoint_in_room(room, name) orelse error.MissingObservatoryMark;
        }
    };
    for (Layout.links) |link| try spatial.graph.connect(try find.wp(spatial, scene, link[0]), try find.wp(spatial, scene, link[1]), null);

    const ids = Ids{
        .scene = scene,
        .ines = world.lookup_entity("Ines").?,
        .halloran = world.lookup_entity("Halloran").?,
        .pell = world.lookup_entity("Pell").?,
        .moss = world.lookup_entity("Moss").?,
        .glove = world.lookup_entity("StainedGlove").?,
        .slip = world.lookup_entity("ExposureSlip").?,
        .log = world.lookup_entity("TelescopeLog").?,
        .darkroom = world.lookup_entity("Darkroom").?,
        .dissuade = world.lookup_entity("Dissuade").?,
        .plant_alibi = world.lookup_entity("PlantAlibi").?,
        .shed_warning = world.lookup_entity("ShedWarning").?,
        .archive_wp = try find.wp(spatial, scene, "Archive"),
        .darkroom_wp = try find.wp(spatial, scene, "Darkroom"),
        .telescope_wp = try find.wp(spatial, scene, "TelescopeFloor"),
        .shed_wp = try find.wp(spatial, scene, "GeneratorShed"),
    };
    spatial.clear_hotspots();
    try spatial.add_hotspot(ids.glove, scene, .{ .x = 44, .y = 15 }, 3, "Stained Glove", "A glove on the darkroom bench.");
    try spatial.add_hotspot(ids.slip, scene, .{ .x = 20, .y = 15 }, 3, "Exposure Slip", "A slip pinned in the plate archive.");
    try spatial.add_hotspot(ids.log, scene, .{ .x = 28, .y = 15 }, 3, "Telescope Log", "The night's observing log.");
    try spatial.register_entity(ids.ines, try find.wp(spatial, scene, "CablePlatform"), 4);
    try spatial.register_entity(ids.halloran, try find.wp(spatial, scene, "Office"), 3);
    try spatial.register_entity(ids.pell, try find.wp(spatial, scene, "Library"), 3);
    try spatial.register_entity(ids.moss, try find.wp(spatial, scene, "Stair"), 2);
    return ids;
}

fn staff(world: *bespoke.World, compiled: *const bespoke.CompiledProgram) !society.Society {
    if (compiled.societies.items.len != 1) return error.MissingStaffSociety;
    return society.Society.init(world, compiled.societies.items[0].config);
}

const Stage = struct {
    world: *bespoke.World,
    spatial: *bespoke.SpatialSystem,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    staff: *society.Society,
    ids: Ids,

    /// One host tick, the society tick, and any lines spoken.
    fn tick(self: Stage, writer: anytype) !void {
        _ = try host.tick(self.vm, self.compiled);
        try self.staff.step(self.world, self.spatial, self.vm);
        var buf: [512]u8 = undefined;
        if (host.speech_this_tick(self.world, self.vm, &buf)) |line| try writer.print("  [{d:>3}] {s}\n", .{ self.world.current_tick, line });
    }

    fn tick_until(self: Stage, writer: anytype, comptime done: fn (Stage) bool, limit: usize, err: anyerror) !void {
        var guard: usize = 0;
        while (!done(self)) : (guard += 1) {
            if (guard >= limit) return err;
            try self.tick(writer);
        }
    }

    /// Ticks until `done`, then once more: an interception resolves its agenda inside a tick and
    /// fires `Intercepts`, whose handler runs on the next tick.
    fn encounter(self: Stage, writer: anytype, comptime done: fn (Stage) bool, limit: usize, err: anyerror) !void {
        try self.tick_until(writer, done, limit, err);
        try self.tick(writer);
    }

    fn walk(self: Stage, writer: anytype, dest: u16, limit: usize) !void {
        if (!(try self.spatial.walk_to_with_world(self.world, self.ids.ines, dest))) return error.WalkRefused;
        var guard: usize = 0;
        while (self.spatial.is_moving(self.ids.ines)) : (guard += 1) {
            if (guard >= limit) return error.WalkTooLong;
            try self.tick(writer);
        }
    }

    fn act(self: Stage, writer: anytype, cue: []const u8, target: bespoke.EntityId) !void {
        _ = try self.vm.fire_cue(self.compiled, cue, self.ids.ines, target, null);
        try self.tick(writer);
    }

    fn stage_name(self: Stage, agenda: bespoke.EntityId) []const u8 {
        const stage = agency.stage_of(self.world, agenda) orelse return "unseeded";
        return agency.STAGE_NAMES[@intFromEnum(stage)];
    }

    fn report(self: Stage, writer: anytype) !void {
        try writer.print("  -> Agendas: Dissuade {s}, PlantAlibi {s}, ShedWarning {s}\n", .{
            self.stage_name(self.ids.dissuade), self.stage_name(self.ids.plant_alibi), self.stage_name(self.ids.shed_warning),
        });
    }
};

fn dissuade_over(s: Stage) bool {
    return agency.stage_of(s.world, s.ids.dissuade) == .done;
}
fn alibi_over(s: Stage) bool {
    return agency.stage_of(s.world, s.ids.plant_alibi) == .done;
}
fn moss_spoke(s: Stage) bool {
    const relation = s.world.lookup_relation(agency.COOLDOWN_RELATION) orelse return false;
    return s.world.has_fact(s.ids.shed_warning, relation, null);
}

fn holds(world: *const bespoke.World, subject: bespoke.EntityId, relation: []const u8, object: ?bespoke.EntityId) bool {
    const rel = world.lookup_relation(relation) orelse return false;
    return world.has_fact(subject, rel, if (object) |o| o.to_int() else null);
}

fn expect_true(value: bool, err: anyerror) !void {
    if (!value) return err;
}

/// Deterministic proof: an uninformed night in which two agendas contend for Ines, the
/// director talks her down, and Pell plants a false alibi; a rewind; then an informed night in
/// which the evidence turns both encounters and the porter's warning closes the case.
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("       BeSpoke Engine: The Larkspur Observatory (Social Agency)    \n");
    try writer.writeAll("       (Agendas * Omissions * Pursuit * Soft Interrupts * Rewind)  \n");
    try writer.writeAll("===================================================================\n\n");

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, OBSERVATORY_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);
    try host.initialize_subsystems(&world, &compiled);
    var soc = try staff(&world, &compiled);
    const stage = Stage{ .world = &world, .spatial = &spatial, .vm = &vm, .compiled = &compiled, .staff = &soc, .ids = ids };

    var opening = std.ArrayList(u8).init(allocator);
    defer opening.deinit();
    _ = try bespoke.write_save_state(allocator, opening.writer(), &world, &spatial, &vm, .{ .description = "Larkspur opening" });
    try stage.report(writer);

    try writer.writeAll("\n[Night 1] Ines searches the darkroom, then reads the log empty-handed.\n");
    try stage.walk(writer, ids.darkroom_wp, 40);
    try stage.act(writer, "Searches", ids.darkroom);
    try stage.report(writer);
    try expect_true(agency.stage_of(&world, ids.dissuade) == .pursuing, error.DirectorDidNotPursue);
    try stage.walk(writer, ids.telescope_wp, 40);
    try stage.act(writer, "Reads", ids.log);
    // Both agendas now hold; the director's pursuit is under way, so Pell must wait.
    try stage.report(writer);
    try expect_true(agency.stage_of(&world, ids.plant_alibi) == .idle, error.PellPreempted);
    try expect_true(agency.triggered(&world, compiled.agendas.items[1].agenda), error.AlibiNotTriggered);
    try writer.writeAll("  -> Both agendas hold; Halloran (priority 5) already pursues Ines, so Pell (3) waits.\n");
    try stage.encounter(writer, dissuade_over, 60, error.DirectorNeverArrived);
    try expect_true(host.has_state(&world, ids.ines, "dissuaded"), error.NotDissuaded);
    try stage.encounter(writer, alibi_over, 60, error.PellNeverArrived);
    try stage.report(writer);
    try expect_true(holds(&world, ids.ines, "Believes", world.lookup_entity("PellInLibrary")), error.NoFalseAlibi);
    try writer.writeAll("  -> Ines was talked out of the darkroom and believes Pell's alibi.\n");

    try writer.writeAll("\n[Rewind] Restore the saved opening.\n");
    var stream = std.io.fixedBufferStream(opening.items);
    _ = try bespoke.read_save_state(allocator, stream.reader(), &world, &spatial, &vm);
    try expect_true(!holds(&world, ids.ines, "Believes", null) and agency.stage_of(&world, ids.dissuade) == .idle, error.RewindFailed);
    try stage.report(writer);

    try writer.writeAll("\n[Night 2] Ines takes the evidence first.\n");
    try stage.walk(writer, ids.archive_wp, 40);
    try stage.act(writer, "Takes", ids.slip);
    try stage.walk(writer, ids.telescope_wp, 40);
    try stage.act(writer, "Reads", ids.log);
    // Holding the slip, the omission Pell's agenda needs is gone: no alibi is offered.
    try stage.tick(writer);
    try stage.report(writer);
    try expect_true(agency.stage_of(&world, ids.plant_alibi) == .idle, error.AlibiDespiteSlip);
    try stage.walk(writer, ids.darkroom_wp, 40);
    try stage.act(writer, "Takes", ids.glove);
    try stage.act(writer, "Searches", ids.darkroom);
    try stage.encounter(writer, dissuade_over, 60, error.DirectorNeverArrived);
    try expect_true(host.has_state(&world, ids.halloran, "exposed"), error.DirectorNotExposed);

    try writer.writeAll("\n[Night 2] Ines lingers by the generator shed.\n");
    try stage.walk(writer, ids.shed_wp, 40);
    try stage.encounter(writer, moss_spoke, 60, error.PorterNeverCame);
    try stage.report(writer);

    try writer.writeAll("\n[Night 2] Ines confronts Pell with the slip.\n");
    try stage.act(writer, "TalksTo", ids.pell);
    try expect_true(host.has_state(&world, ids.pell, "cornered") and !holds(&world, ids.ines, "Believes", null), error.CaseOpen);

    try writer.writeAll("\n===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: plate 41 is in Halloran's office.         \n");
    try writer.writeAll("===================================================================\n\n");
}

const action_search: u16 = 1;
const action_take: u16 = 2;
const action_read: u16 = 3;
const keys = [_]bespoke.display.renderer.KeyBinding{
    .{ .key = bespoke.display.renderer.c.SDLK_1, .action = action_search },
    .{ .key = bespoke.display.renderer.c.SDLK_2, .action = action_take },
    .{ .key = bespoke.display.renderer.c.SDLK_3, .action = action_read },
};
const theme = art.with_keys(&keys);

/// Native window proof. The ordinary Session supplies pause, save/load, scrub, and rewind.
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, OBSERVATORY_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);
    try host.initialize_subsystems(&world, &compiled);
    var soc = try staff(&world, &compiled);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Larkspur Observatory", 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    if (window.is_headless) return run_headless(allocator, stdout);
    try stdout.writeAll("\nLarkspur Observatory: click marks to walk; [1] searches the darkroom, [2] takes the evidence where Ines stands, [3] reads the telescope log. Talk to Pell to confront him.\n");
    try stdout.writeAll("Pause/save/load, single-step, scrub, rewind, debug, and console use the standard engine controls.\n\n");

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    bridge.attach_audio_bridge(window.audio_bridge);
    bridge.set_active_character(ids.ines);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();
    window.set_cue_banner("Plate 41 is missing. Find it before the staff decide what you believe.", 240);

    while (true) {
        const action = window.poll_events(session.frame());
        if (action == .quit) break;
        if (!(try session.handle_common(action))) switch (action) {
            .walk_player => |waypoint| {
                if (!(try spatial.walk_to_with_world(&world, ids.ines, waypoint))) window.set_cue_banner("That way is blocked.", 90);
            },
            .custom => |which| {
                const here = spatial.get_current_waypoint(ids.ines);
                if (which == action_search and here == ids.darkroom_wp) {
                    _ = try vm.fire_cue(&compiled, "Searches", ids.ines, ids.darkroom, null);
                    _ = try session.advance();
                } else if (which == action_take and (here == ids.darkroom_wp or here == ids.archive_wp)) {
                    _ = try vm.fire_cue(&compiled, "Takes", ids.ines, if (here == ids.darkroom_wp) ids.glove else ids.slip, null);
                    _ = try session.advance();
                } else if (which == action_read and here == ids.telescope_wp) {
                    _ = try vm.fire_cue(&compiled, "Reads", ids.ines, ids.log, null);
                    _ = try session.advance();
                } else window.set_cue_banner("Nothing to do with that here.", 90);
            },
            .interact_actor => |act| {
                const frame = session.frame();
                if (act.actor_index < frame.entity_count) {
                    _ = try vm.fire_cue(&compiled, "TalksTo", ids.ines, frame.entities[act.actor_index].entity, null);
                    _ = try session.advance();
                }
            },
            else => {},
        };
        if (action != .none and action != .step_tick and action != .toggle_pause) session.refresh();
        if (session.tick_due()) {
            _ = try session.advance();
            try soc.step(&world, &spatial, &vm);
        }
        session.render();
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P33-03: Larkspur Observatory contends, rewinds, and closes the case" {
    try run_headless(std.testing.allocator, std.io.null_writer);
}

test "P33-03: script declares three agendas with distinct priorities" {
    var world = try bespoke.World.init(std.testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(std.testing.allocator, &world, &spatial, OBSERVATORY_SCRIPT);
    defer compiled.deinit();
    try std.testing.expectEqual(@as(usize, 3), compiled.agendas.items.len);
    try std.testing.expect(compiled.agendas.items[0].agenda.priority > compiled.agendas.items[1].agenda.priority);
    try std.testing.expectEqual(@as(usize, 12), spatial.graph.waypoints.items.len);
}
