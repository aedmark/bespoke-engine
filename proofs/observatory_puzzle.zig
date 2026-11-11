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
    \\  if not Carries(Ines, ExposureSlip):
    \\    say Pell: "Not now, Miss Varga. Some of us have plates to measure."
    \\
    \\on cue TalksTo(Ines, Halloran):
    \\  say Halloran: "It is late, Miss Varga. Whatever it is can wait for morning."
    \\
    \\on cue TalksTo(Ines, Moss):
    \\  say Moss: "Evening, miss. Cold one on the mountain tonight."
    \\
    \\command Takes: "take <thing>"
    \\command Takes: "pick up <thing>"
    \\command Reads: "read <thing>"
    \\command Searches: "search <thing>"
    \\alias Halloran: "director"
    \\alias Pell: "rival"
    \\alias Moss: "porter"
    \\
    \\on cue LooksAt(Ines, TelescopeLog):
    \\  say Ines: "The night's log, open at plate 41."
    \\
    \\on cue LooksAt(Ines, StainedGlove):
    \\  say Ines: "Developer stains, and an H stitched at the cuff."
    \\
    \\on cue TalksTo(Ines, Pell, ExposureSlip):
    \\  if Carries(Ines, ExposureSlip):
    \\    Pell is cornered
    \\    say Pell: "02:10 from the dome? Then it was not me at the telescope. Ask Halloran."
    \\  if not Carries(Ines, ExposureSlip):
    \\    say Pell: "What slip? I have no idea what you mean."
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

/// Where Ines must stand for a typed action, as a refusal, or null when it may run. Typed
/// commands need this because the whole observatory is one room: every prop is in scope from
/// every mark, so the noun rules alone would let Ines take the slip from the cable car.
fn refusal(spatial: *const bespoke.SpatialSystem, ids: Ids, command: bespoke.command.Command) ?[]const u8 {
    if (std.mem.eql(u8, command.cue, "WalksTo")) return null;
    if (spatial.is_moving(ids.ines)) return "Ines must stop walking first.";
    const here = spatial.get_current_waypoint(ids.ines);
    const a = command.a orelse return null;
    if (std.mem.eql(u8, command.cue, "Takes")) {
        if (a == ids.glove and here != ids.darkroom_wp) return "The glove is in the Darkroom.";
        if (a == ids.slip and here != ids.archive_wp) return "The slip is in the Archive.";
    } else if (std.mem.eql(u8, command.cue, "Reads")) {
        if (a == ids.log and here != ids.telescope_wp) return "The log is on the TelescopeFloor.";
    } else if (std.mem.eql(u8, command.cue, "Searches")) {
        if (a == ids.darkroom and here != ids.darkroom_wp) return "Ines must be in the Darkroom to search it.";
    } else if (std.mem.eql(u8, command.cue, "TalksTo")) {
        if (a == ids.pell and !within_reach(spatial, ids.ines, ids.pell)) return "Pell is too far away. Get within one mark of him.";
    }
    return null;
}

pub const Typed = struct { text: ?[]const u8 = null, fired: bool = false, walking: bool = false };

/// One typed line for Ines: interpret, check where she stands, then dispatch.
fn type_line(vm: *bespoke.VM, compiled: *const bespoke.CompiledProgram, interp: *bespoke.command.Interpreter, spatial: *const bespoke.SpatialSystem, ids: Ids, line: []const u8, buf: []u8) !Typed {
    switch (host.interpret_command(vm, compiled, interp, ids.ines, line, buf)) {
        .reply => |text| return .{ .text = text },
        .command => |command| {
            if (refusal(spatial, ids, command)) |why| return .{ .text = why };
            const reply = try host.dispatch_command(vm, compiled, ids.ines, command);
            return .{ .text = reply.text, .fired = reply.fired, .walking = reply.walking };
        },
    }
}

const Stage = struct {
    world: *bespoke.World,
    spatial: *bespoke.SpatialSystem,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    staff: *society.Society,
    ids: Ids,
    interp: *bespoke.command.Interpreter,

    /// Types a line as the player would, prints the reply, and ticks so a fired cue speaks
    /// and a walk finishes.
    fn typed(self: Stage, writer: anytype, line: []const u8) !Typed {
        try writer.print("  > {s}\n", .{line});
        var buf: [160]u8 = undefined;
        const result = try type_line(self.vm, self.compiled, self.interp, self.spatial, self.ids, line, &buf);
        if (result.text) |text| try writer.print("    {s}\n", .{text});
        if (result.fired) try self.tick(writer);
        var guard: usize = 0;
        while (self.spatial.is_moving(self.ids.ines)) : (guard += 1) {
            if (guard >= 60) return error.WalkTooLong;
            try self.tick(writer);
        }
        return result;
    }

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

fn pell_near(s: Stage) bool {
    return !s.spatial.is_moving(s.ids.ines) and within_reach(s.spatial, s.ids.ines, s.ids.pell);
}

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
    var interp = bespoke.command.Interpreter{};
    const stage = Stage{ .world = &world, .spatial = &spatial, .vm = &vm, .compiled = &compiled, .staff = &soc, .ids = ids, .interp = &interp };

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

    try writer.writeAll("\n[Rewind] Restore the saved opening for a typed playthrough.\n");
    var again = std.io.fixedBufferStream(opening.items);
    _ = try bespoke.read_save_state(allocator, again.reader(), &world, &spatial, &vm);
    interp = .{};

    try writer.writeAll("\n[Typed] The same evidence, by keyboard.\n");
    const which = try stage.typed(writer, "examine the telescope");
    try expect_true(which.text != null and std.mem.startsWith(u8, which.text.?, "Which do you mean"), error.NoDisambiguation);
    try expect_true((try stage.typed(writer, "log")).fired, error.AnswerNotDispatched);
    _ = try stage.typed(writer, "xyzzy");
    const too_far = try stage.typed(writer, "take the slip");
    try expect_true(too_far.text != null and !too_far.fired, error.TookFromAfar);
    _ = try stage.typed(writer, "go to the archive");
    try expect_true(spatial.get_current_waypoint(ids.ines) == ids.archive_wp, error.TypedWalkFailed);
    try expect_true((try stage.typed(writer, "pick up the exposure slip")).fired, error.TypedTakeFailed);
    try stage.tick_until(writer, pell_near, 80, error.PellNeverNear);
    try expect_true((try stage.typed(writer, "ask the rival about the slip")).fired, error.TypedAskFailed);
    try expect_true(host.has_state(&world, ids.pell, "cornered"), error.CaseOpen);

    try writer.writeAll("\n===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: plate 41 is in Halloran's office.         \n");
    try writer.writeAll("===================================================================\n\n");
}

const action_search: u16 = 1;
const action_take: u16 = 2;
const action_read: u16 = 3;
const action_confront: u16 = 4;
const keys = [_]bespoke.display.renderer.KeyBinding{
    .{ .key = bespoke.display.renderer.c.SDLK_1, .action = action_search },
    .{ .key = bespoke.display.renderer.c.SDLK_2, .action = action_take },
    .{ .key = bespoke.display.renderer.c.SDLK_3, .action = action_read },
    .{ .key = bespoke.display.renderer.c.SDLK_4, .action = action_confront },
};
const theme = art.with_keys(&keys);

/// True when two actors stand on the same mark or on marks joined by an edge, close enough to
/// talk without chasing a walking actor's sprite with the mouse.
fn within_reach(spatial: *const bespoke.SpatialSystem, a: bespoke.EntityId, b: bespoke.EntityId) bool {
    const wa = spatial.get_current_waypoint(a) orelse return false;
    const wb = spatial.get_current_waypoint(b) orelse return false;
    if (wa == wb) return true;
    for (spatial.graph.edges.items) |edge| if (edge.from == wa and edge.to == wb) return true;
    return false;
}

/// One window session's game logic, separate from the event loop so tests can drive it with
/// synthetic actions on an offscreen window.
const Play = struct {
    world: *bespoke.World,
    spatial: *bespoke.SpatialSystem,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    staff: *society.Society,
    session: *host.Session,
    interp: *bespoke.command.Interpreter,
    window: *bespoke.display.DisplayWindow,
    ids: Ids,

    /// One tick with the society, then whatever the script said, on the banner. The window draws
    /// no script speech by itself, so every tick goes through here.
    fn advance(self: Play) !void {
        _ = try self.session.advance();
        try self.staff.step(self.world, self.spatial, self.vm);
        var buf: [512]u8 = undefined;
        if (host.speech_this_tick(self.world, self.vm, &buf)) |line| self.window.set_cue_banner(line, 300);
        self.refresh_words();
    }

    fn refresh_words(self: Play) void {
        host.command_words(self.vm, self.compiled, self.ids.ines, &self.window.command_words);
    }

    fn act(self: Play, cue: []const u8, target: bespoke.EntityId) !void {
        _ = try self.vm.fire_cue(self.compiled, cue, self.ids.ines, target, null);
        try self.advance();
    }

    fn hint(self: Play, text: []const u8) void {
        self.window.set_cue_banner(text, 150);
    }

    /// Handles one proof action; engine actions are the session's.
    fn handle(self: Play, action: bespoke.display.renderer.UserAction) !void {
        const ids = self.ids;
        switch (action) {
            .walk_player => |waypoint| {
                if (!(try self.spatial.walk_to_with_world(self.world, ids.ines, waypoint))) self.hint("That way is blocked.");
            },
            .custom => |which| {
                const here = self.spatial.get_current_waypoint(ids.ines);
                if (self.spatial.is_moving(ids.ines)) {
                    self.hint("Ines must stop walking first.");
                } else if (which == action_search) {
                    if (here == ids.darkroom_wp) try self.act("Searches", ids.darkroom) else self.hint("[1] searches the Darkroom. Walk there first.");
                } else if (which == action_take) {
                    if (here == ids.darkroom_wp) {
                        try self.act("Takes", ids.glove);
                    } else if (here == ids.archive_wp) {
                        try self.act("Takes", ids.slip);
                    } else self.hint("[2] takes the glove in the Darkroom or the slip in the Archive.");
                } else if (which == action_read) {
                    if (here == ids.telescope_wp) try self.act("Reads", ids.log) else self.hint("[3] reads the log on the TelescopeFloor. Walk there first.");
                } else if (which == action_confront) {
                    if (within_reach(self.spatial, ids.ines, ids.pell)) try self.act("TalksTo", ids.pell) else self.hint("Pell is too far away. Get within one mark of him.");
                }
            },
            .typed_command => |t| {
                var buf: [160]u8 = undefined;
                const result = try type_line(self.vm, self.compiled, self.interp, self.spatial, ids, t.buf[0..t.len], &buf);
                if (result.text) |text| self.window.set_cue_banner(text, 240);
                if (result.fired) try self.advance();
                self.refresh_words();
            },
            .interact_actor => |a| {
                const frame = self.session.frame();
                if (a.actor_index < frame.entity_count) try self.act("TalksTo", frame.entities[a.actor_index].entity);
            },
            else => {},
        }
    }

    fn banner(self: Play) []const u8 {
        return self.window.cue_banner_text[0..self.window.cue_banner_len];
    }
};

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
    try stdout.writeAll("\nLarkspur Observatory: click marks to walk; [1] searches the darkroom, [2] takes the evidence where Ines stands, [3] reads the telescope log, [4] confronts Pell when he is on Ines's mark or the next one. Clicking a staff member talks to them. [Enter] opens the command bar: try 'go to the archive', 'take the slip', 'ask pell about the slip'.\n");
    try stdout.writeAll("Pause/save/load, single-step, scrub, rewind, debug, and console use the standard engine controls.\n\n");

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    bridge.attach_audio_bridge(window.audio_bridge);
    bridge.set_active_character(ids.ines);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();
    window.set_cue_banner("Plate 41 is missing. Find it before the staff decide what you believe.", 240);
    window.enable_command_bar(true);
    var interp = bespoke.command.Interpreter{};
    const play = Play{ .world = &world, .spatial = &spatial, .vm = &vm, .compiled = &compiled, .staff = &soc, .session = &session, .interp = &interp, .window = &window, .ids = ids };
    play.refresh_words();

    while (true) {
        const action = window.poll_events(session.frame());
        if (action == .quit) break;
        if (!(try session.handle_common(action))) try play.handle(action);
        if (action != .none and action != .step_tick and action != .toggle_pause) session.refresh();
        if (session.tick_due()) try play.advance();
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

test "P33-03: window actions give feedback and Pell can be confronted within reach" {
    const allocator = std.testing.allocator;
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
    var window = try bespoke.display.DisplayWindow.init_offscreen(1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    bridge.set_active_character(ids.ines);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();
    var interp = bespoke.command.Interpreter{};
    const play = Play{ .world = &world, .spatial = &spatial, .vm = &vm, .compiled = &compiled, .staff = &soc, .session = &session, .interp = &interp, .window = &window, .ids = ids };
    const has = struct {
        fn text(p: Play, needle: []const u8) bool {
            return std.mem.indexOf(u8, p.banner(), needle) != null;
        }
    }.text;

    // A key pressed in the wrong place says where it works.
    try play.handle(.{ .custom = action_read });
    try std.testing.expect(has(play, "TelescopeFloor"));
    // Pell starts in the Library, one stair from Ines: within reach, and without the slip he
    // brushes her off instead of saying nothing.
    try play.handle(.{ .custom = action_confront });
    try std.testing.expect(has(play, "Not now"));

    // Walk to the archive; the script's line for taking the slip reaches the banner.
    try play.handle(.{ .walk_player = ids.archive_wp });
    var guard: usize = 0;
    while (spatial.is_moving(ids.ines)) : (guard += 1) {
        try std.testing.expect(guard < 40);
        try play.advance();
    }
    try play.handle(.{ .custom = action_take });
    try std.testing.expect(has(play, "exposure slip"));

    // Wait, ticking, until Pell's routine brings him within one mark, then confront him.
    guard = 0;
    while (!within_reach(&spatial, ids.ines, ids.pell)) : (guard += 1) {
        try std.testing.expect(guard < 80);
        try play.advance();
    }
    while (spatial.is_moving(ids.ines)) try play.advance();
    try play.handle(.{ .custom = action_confront });
    try std.testing.expect(has(play, "Ask Halloran"));
    try std.testing.expect(host.has_state(&world, ids.pell, "cornered"));
}

test "P33-03: reach is the same mark or one edge away" {
    var world = try bespoke.World.init(std.testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(std.testing.allocator, &world, &spatial, OBSERVATORY_SCRIPT);
    defer compiled.deinit();
    _ = try configure(&world, &spatial);
    const scene = world.lookup_entity("Larkspur Observatory").?;
    const a = try world.intern_entity("ReachProbeA");
    const b = try world.intern_entity("ReachProbeB");
    try spatial.register_entity(a, spatial.graph.find_waypoint_in_room(scene, "CablePlatform").?, 1);
    try spatial.register_entity(b, spatial.graph.find_waypoint_in_room(scene, "Terrace").?, 1);
    try std.testing.expect(!within_reach(&spatial, a, b)); // two edges apart
    _ = try spatial.transition_actor(b, scene, spatial.graph.find_waypoint_in_room(scene, "Stair").?);
    try std.testing.expect(within_reach(&spatial, a, b)); // neighbours
    _ = try spatial.transition_actor(b, scene, spatial.graph.find_waypoint_in_room(scene, "Library").?);
    try std.testing.expect(within_reach(&spatial, a, b)); // joined by the host's stair
}

test "P26-03: typed commands in the window reply on the banner and respect where Ines stands" {
    const allocator = std.testing.allocator;
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
    var window = try bespoke.display.DisplayWindow.init_offscreen(1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    window.enable_command_bar(true);
    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();
    var interp = bespoke.command.Interpreter{};
    const play = Play{ .world = &world, .spatial = &spatial, .vm = &vm, .compiled = &compiled, .staff = &soc, .session = &session, .interp = &interp, .window = &window, .ids = ids };
    play.refresh_words();

    const typed = struct {
        fn line(p: Play, text: []const u8) !void {
            var t = bespoke.display.renderer.UserAction{ .typed_command = .{ .buf = undefined, .len = text.len } };
            @memcpy(t.typed_command.buf[0..text.len], text);
            try p.handle(t);
        }
    }.line;

    try typed(play, "examine telescope");
    try std.testing.expect(std.mem.startsWith(u8, play.banner(), "Which do you mean"));
    try typed(play, "log");
    try std.testing.expect(std.mem.indexOf(u8, play.banner(), "plate 41") != null);
    try typed(play, "take slip");
    try std.testing.expectEqualStrings("The slip is in the Archive.", play.banner());
    // Completion words follow scope: "exposure" is in the list while the slip is in the room.
    var found = false;
    for (0..window.command_words.len) |i| {
        if (std.mem.eql(u8, window.command_words.word(i), "exposure")) found = true;
    }
    try std.testing.expect(found);
}
