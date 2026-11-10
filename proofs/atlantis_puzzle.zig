//! The Fate of Atlantis: Algiers Bazaar, the Phase 24 path-divergence proof (P24-03).
//!
//! Three operational approaches reach Omar's lost dialogue manuscript by different routes. The
//! selected path asserts facts that lock the other two gates, so the same spatial graph is
//! navigable only through that approach. Omar's dialogue repertoire is pruned by the same route.
//! The script owns the paths, facts, routines, and dialogue; this proof owns staging and input.
const std = @import("std");
const bespoke = @import("bespoke");
const host = bespoke.host;
const r = bespoke.display.renderer;

pub const ATLANTIS_PUZZLE_SCRIPT =
    \\scene: Algiers Bazaar
    \\cast: Indy, Omar
    \\props: Manuscript
    \\marks: Entrance, StallMark, WitsGate, FistsGate, TeamGate, ManuscriptMark
    \\
    \\relation Chosen(actor, approach)
    \\relation Solved(actor, approach)
    \\relation Acquired(actor, item)
    \\relation WaypointBlocked(mark)
    \\
    \\path Wits:
    \\  remember Chosen(Indy, Wits)
    \\  remember WaypointBlocked(FistsGate)
    \\  remember WaypointBlocked(TeamGate)
    \\  routine SolveWits(Indy):
    \\    say Indy: "The ledger's margin points to a false invoice. The manuscript is behind it."
    \\    remember Solved(Indy, Wits)
    \\    remember Acquired(Indy, Manuscript)
    \\
    \\path Fists:
    \\  remember Chosen(Indy, Fists)
    \\  remember WaypointBlocked(WitsGate)
    \\  remember WaypointBlocked(TeamGate)
    \\  routine SolveFists(Indy):
    \\    say Indy: "Omar's guard folds under a straight right. The back room gives up the manuscript."
    \\    remember Solved(Indy, Fists)
    \\    remember Acquired(Indy, Manuscript)
    \\
    \\path Team:
    \\  remember Chosen(Indy, Team)
    \\  remember WaypointBlocked(WitsGate)
    \\  remember WaypointBlocked(FistsGate)
    \\  routine SolveTeam(Indy):
    \\    say Indy: "The diggers know the back passage. We split the take and walk out together."
    \\    remember Solved(Indy, Team)
    \\    remember Acquired(Indy, Manuscript)
    \\
    \\on cue Talk(Indy, Omar):
    \\  choice "Follow the ledger" if PathActive(Wits):
    \\    say Omar: "The ledger was always the map, Dr. Jones."
    \\  choice "Force the stall" if PathActive(Fists):
    \\    say Omar: "No! Not the invoices! Take the manuscript!"
    \\  choice "Recruit the diggers" if PathActive(Team):
    \\    say Omar: "A share for every hand. That is how a bazaar survives."
    \\  choice "Leave Omar's stall":
    \\    say Omar: "Come back when you know what you want."
;

const PathSpec = struct {
    name: []const u8,
    gate: []const u8,
    blocked: [2][]const u8,
    routine: []const u8,
    choice: []const u8,
    banner: []const u8,
};

const paths = [_]PathSpec{
    .{
        .name = "Wits",
        .gate = "WitsGate",
        .blocked = .{ "FistsGate", "TeamGate" },
        .routine = "SolveWits",
        .choice = "Follow the ledger",
        .banner = "Wits selected. Walk to ManuscriptMark, talk to Omar, then press [S].",
    },
    .{
        .name = "Fists",
        .gate = "FistsGate",
        .blocked = .{ "WitsGate", "TeamGate" },
        .routine = "SolveFists",
        .choice = "Force the stall",
        .banner = "Fists selected. Walk to ManuscriptMark, talk to Omar, then press [S].",
    },
    .{
        .name = "Team",
        .gate = "TeamGate",
        .blocked = .{ "WitsGate", "FistsGate" },
        .routine = "SolveTeam",
        .choice = "Recruit the diggers",
        .banner = "Team selected. Walk to ManuscriptMark, talk to Omar, then press [S].",
    },
};

const Ids = struct {
    scene: bespoke.EntityId,
    indy: bespoke.EntityId,
    omar: bespoke.EntityId,
    manuscript: bespoke.EntityId,
    entrance_wp: u16,
    stall_wp: u16,
    manuscript_wp: u16,
};

fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const scene = world.lookup_entity("Algiers Bazaar").?;
    const ids = Ids{
        .scene = scene,
        .indy = world.lookup_entity("Indy").?,
        .omar = world.lookup_entity("Omar").?,
        .manuscript = world.lookup_entity("Manuscript").?,
        .entrance_wp = spatial.graph.find_waypoint_in_room(scene, "Entrance").?,
        .stall_wp = spatial.graph.find_waypoint_in_room(scene, "StallMark").?,
        .manuscript_wp = spatial.graph.find_waypoint_in_room(scene, "ManuscriptMark").?,
    };

    host.place_waypoint(spatial, ids.entrance_wp, 0, 0);
    host.place_waypoint(spatial, ids.stall_wp, 0, 10);
    host.place_waypoint(spatial, spatial.graph.find_waypoint_in_room(scene, "WitsGate").?, 20, -10);
    host.place_waypoint(spatial, spatial.graph.find_waypoint_in_room(scene, "FistsGate").?, 20, 0);
    host.place_waypoint(spatial, spatial.graph.find_waypoint_in_room(scene, "TeamGate").?, 20, 10);
    host.place_waypoint(spatial, ids.manuscript_wp, 40, 0);

    spatial.graph.edges.clearRetainingCapacity();
    const wits_gate = spatial.graph.find_waypoint_in_room(scene, "WitsGate").?;
    const fists_gate = spatial.graph.find_waypoint_in_room(scene, "FistsGate").?;
    const team_gate = spatial.graph.find_waypoint_in_room(scene, "TeamGate").?;
    try spatial.graph.connect(ids.entrance_wp, ids.stall_wp, null);
    try spatial.graph.connect(ids.entrance_wp, wits_gate, null);
    try spatial.graph.connect(ids.entrance_wp, fists_gate, null);
    try spatial.graph.connect(ids.entrance_wp, team_gate, null);
    try spatial.graph.connect(wits_gate, ids.manuscript_wp, null);
    try spatial.graph.connect(fists_gate, ids.manuscript_wp, null);
    try spatial.graph.connect(team_gate, ids.manuscript_wp, null);

    spatial.clear_hotspots();
    try spatial.add_hotspot(ids.manuscript, scene, .{ .x = 40, .y = -4 }, 6, "Lost Manuscript", "A folio of Atlantis dialogue hidden behind Omar's invoices.");
    try spatial.register_entity(ids.indy, ids.entrance_wp, 10);
    try spatial.register_entity(ids.omar, ids.stall_wp, 1);
    return ids;
}

fn path_entity(world: *const bespoke.World, name: []const u8) bespoke.EntityId {
    return world.lookup_entity(name).?;
}

fn run_path(allocator: std.mem.Allocator, writer: anytype, spec: PathSpec) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, ATLANTIS_PUZZLE_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);

    _ = (try vm.select_path(&compiled, spec.name)) orelse return error.PathNotSelected;
    _ = try host.tick(&vm, &compiled);

    const route = path_entity(&world, spec.name);
    const path_active = world.lookup_relation("PathActive").?;
    const chosen = world.lookup_relation("Chosen").?;
    const blocked = world.lookup_relation("WaypointBlocked").?;
    const solved = world.lookup_relation("Solved").?;
    const acquired = world.lookup_relation("Acquired").?;
    try std.testing.expect(world.has_fact(route, path_active, null));
    try std.testing.expect(world.has_fact(ids.indy, chosen, route.to_int()));

    for (spec.blocked) |gate_name| {
        const gate = path_entity(&world, gate_name);
        try std.testing.expect(world.has_fact(gate, blocked, null));
    }
    try std.testing.expect(!world.has_fact(path_entity(&world, spec.gate), blocked, null));

    try writer.print("  locks: {s}, {s}\n", .{ spec.blocked[0], spec.blocked[1] });
    try writer.print("  route: Entrance -> {s} -> ManuscriptMark\n", .{spec.gate});

    if (!try spatial.walk_to_with_world(&world, ids.indy, ids.manuscript_wp)) return error.NoRoute;
    const gate_wp = spatial.graph.find_waypoint_in_room(ids.scene, spec.gate).?;
    var passed_gate = false;
    var ticks: usize = 0;
    while (ticks < 12) : (ticks += 1) {
        _ = try host.tick(&vm, &compiled);
        const here = spatial.get_current_waypoint(ids.indy).?;
        if (here == gate_wp) passed_gate = true;
        if (here == ids.manuscript_wp) break;
    }
    if (!passed_gate) return error.DidNotPassSelectedGate;
    if (spatial.get_current_waypoint(ids.indy) != ids.manuscript_wp) return error.DidNotReachManuscript;

    try vm.set_dialogue_speaker(ids.indy, ids.omar);
    _ = try vm.fire_cue(&compiled, "Talk", ids.indy, ids.omar, null);
    _ = try host.tick(&vm, &compiled);
    const open = vm.dialogue_view() orelse return error.NoOmarDialogue;
    if (open.count != 2) return error.WrongDialogueRepertoire;
    if (!std.mem.eql(u8, open.text(0), spec.choice)) return error.WrongDialogueChoice;
    if (!std.mem.eql(u8, open.text(1), "Leave Omar's stall")) return error.MissingLeaveChoice;
    try writer.print("  dialogue: {s} (rival choices pruned)\n", .{spec.choice});

    _ = (try vm.choose(0)) orelse return error.ChoiceNotSelected;
    _ = try host.tick(&vm, &compiled);
    var speech_buf: [256]u8 = undefined;
    if (host.speech_this_tick(&world, &vm, &speech_buf)) |line| {
        try writer.print("  {s}\n", .{line});
    }

    const routine_entry = compiled.routine_entries.get(spec.routine) orelse return error.UnknownPathRoutine;
    _ = try vm.spawn_routine(ids.indy, routine_entry);
    _ = try host.tick(&vm, &compiled);
    try std.testing.expect(world.has_fact(ids.indy, solved, route.to_int()));
    try std.testing.expect(world.has_fact(ids.indy, acquired, ids.manuscript.to_int()));

    for (paths) |other| {
        if (std.mem.eql(u8, other.name, spec.name)) continue;
        const other_entry = compiled.routine_entries.get(other.routine) orelse return error.UnknownPathRoutine;
        _ = try vm.spawn_routine(ids.indy, other_entry);
        _ = try host.tick(&vm, &compiled);
        if (world.has_fact(ids.indy, solved, path_entity(&world, other.name).to_int())) {
            return error.InactivePathRoutineRan;
        }
    }

    try writer.print("  solve: Solved(Indy, {s}); Acquired(Indy, Manuscript)\n", .{spec.name});
    try writer.writeAll("  rival path routines: muted\n\n");
}

pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("      BeSpoke Engine: The Fate of Atlantis - Algiers Bazaar       \n");
    try writer.writeAll("      (Three Paths * Waypoint Locks * Route Dialogue)             \n");
    try writer.writeAll("===================================================================\n\n");

    for (paths) |spec| {
        try writer.print("Path {s}:\n", .{spec.name});
        try run_path(allocator, writer, spec);
    }

    try writer.writeAll("===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: all three approaches reach the manuscript.\n");
    try writer.writeAll("===================================================================\n\n");
}

const action_wits: u16 = 1;
const action_fists: u16 = 2;
const action_team: u16 = 3;
const action_talk: u16 = 4;
const action_solve: u16 = 5;

const keys = [_]r.KeyBinding{
    .{ .key = r.c.SDLK_1, .action = action_wits },
    .{ .key = r.c.SDLK_2, .action = action_fists },
    .{ .key = r.c.SDLK_3, .action = action_team },
    .{ .key = r.c.SDLK_t, .action = action_talk },
    .{ .key = r.c.SDLK_s, .action = action_solve },
};

fn bazaar_backdrop(w: *r.DisplayWindow, frame: *const bespoke.RenderFrame) bool {
    _ = frame;
    w.fill_rect(0, 0, w.width, w.height, r.Color{ .r = 58, .g = 38, .b = 24 });
    w.fill_rect(0, w.height - 150, w.width, 150, r.Color{ .r = 158, .g = 122, .b = 70 });
    w.fill_rect(90, 110, w.width - 180, 34, r.Color{ .r = 38, .g = 112, .b = 118 });
    w.fill_rect(110, 144, w.width - 220, 10, r.Color{ .r = 212, .g = 172, .b = 82 });
    return true;
}

const theme = r.Theme{
    .backdrop = bazaar_backdrop,
    .keys = &keys,
};

fn path_spec_for(action: u32) ?PathSpec {
    if (action == 0 or action > @as(u32, @intCast(paths.len))) return null;
    return paths[@intCast(action - 1)];
}

fn select_path(
    session: *host.Session,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    action: u32,
) !?PathSpec {
    const spec = path_spec_for(action) orelse return null;
    _ = (try vm.select_path(compiled, spec.name)) orelse return null;
    _ = try session.advance();
    return spec;
}

fn solve_path(
    spatial: *const bespoke.SpatialSystem,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    ids: Ids,
    spec: PathSpec,
) !bool {
    if (spatial.get_current_waypoint(ids.indy) != ids.manuscript_wp) return false;
    const entry = compiled.routine_entries.get(spec.routine) orelse return error.UnknownPathRoutine;
    _ = try vm.spawn_routine(ids.indy, entry);
    return true;
}

pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, ATLANTIS_PUZZLE_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Fate of Atlantis: Algiers", 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    if (window.is_headless) return run_headless(allocator, stdout);

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_active_character(ids.indy);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();

    const selector = [_]bespoke.dialogue.Choice{
        .{ .text = "Wits: follow the ledger", .action = action_wits },
        .{ .text = "Fists: force the stall", .action = action_fists },
        .{ .text = "Team: recruit the diggers", .action = action_team },
    };
    _ = try vm.open_generated_dialogue(ids.omar, "Choose your approach, Indy.", &selector);
    try session.record_now();
    window.set_cue_banner("Choose a path: [1] Wits, [2] Fists, [3] Team. Then talk and solve.", 600);

    try stdout.writeAll("\nAlgiers Bazaar: choose [1] Wits, [2] Fists, or [3] Team. Click ManuscriptMark to walk.\n");
    try stdout.writeAll("[T] talks to Omar with the selected repertoire; [S] solves at ManuscriptMark.\n\n");

    var selected: ?PathSpec = null;
    while (true) {
        const action = window.poll_events(session.frame());
        if (action == .quit) break;
        if (!(try session.handle_common(action))) switch (action) {
            .dialogue_choice => |choice_idx| {
                if (selected == null) {
                    const selection = (try session.choose_dialogue(choice_idx)) orelse continue;
                    selected = try select_path(&session, &vm, &compiled, selection.action);
                    if (selected) |spec| window.set_cue_banner(spec.banner, 240);
                } else {
                    _ = try session.choose_dialogue(choice_idx);
                }
            },
            .dismiss_dialogue => {
                if (selected == null) {
                    _ = try vm.open_generated_dialogue(ids.omar, "Choose your approach, Indy.", &selector);
                    try session.record_now();
                }
            },
            .custom => |which| {
                if (which == action_wits or which == action_fists or which == action_team) {
                    const choice_index: usize = @intCast(which - action_wits);
                    if (selected == null) {
                        const selection = (try session.choose_dialogue(choice_index)) orelse continue;
                        selected = try select_path(&session, &vm, &compiled, selection.action);
                        if (selected) |spec| window.set_cue_banner(spec.banner, 240);
                    } else {
                        _ = try session.choose_dialogue(choice_index);
                    }
                } else if (which == action_talk) {
                    if (selected) |_| {
                        if (session.dialogue_view() == null) {
                            _ = try vm.fire_cue(&compiled, "Talk", ids.indy, ids.omar, null);
                            _ = try session.advance();
                        }
                    } else {
                        window.set_cue_banner("Choose a path first.", 90);
                    }
                } else if (which == action_solve) {
                    if (selected) |spec| {
                        if (try solve_path(&spatial, &vm, &compiled, ids, spec)) {
                            _ = try session.advance();
                            const acquired = world.lookup_relation("Acquired").?;
                            if (world.has_fact(ids.indy, acquired, ids.manuscript.to_int())) {
                                window.set_cue_banner("The manuscript is yours.", 240);
                            } else {
                                window.set_cue_banner("The path routine did not run.", 120);
                            }
                        } else {
                            window.set_cue_banner("Walk to ManuscriptMark before solving.", 90);
                        }
                    } else {
                        window.set_cue_banner("Choose a path first.", 90);
                    }
                }
            },
            .walk_player => |waypoint| {
                if (selected == null) {
                    window.set_cue_banner("Choose a path first.", 90);
                } else {
                    _ = try spatial.walk_to_with_world(&world, ids.indy, waypoint);
                }
            },
            else => {},
        };
        if (action != .none and action != .step_tick and action != .toggle_pause) session.refresh();
        if (session.tick_due()) _ = try session.advance();
        session.render();
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P24-03: all three Algiers approaches acquire the manuscript" {
    try run_headless(std.testing.allocator, std.io.null_writer);
}

test "P24-03: the generated selector chooses the Wits route" {
    var world = try bespoke.World.init(std.testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(std.testing.allocator, &world, &spatial, ATLANTIS_PUZZLE_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);

    var vm = bespoke.VM.init(std.testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);

    const selector = [_]bespoke.dialogue.Choice{
        .{ .text = "Wits: follow the ledger", .action = action_wits },
        .{ .text = "Fists: force the stall", .action = action_fists },
        .{ .text = "Team: recruit the diggers", .action = action_team },
    };
    _ = try vm.open_generated_dialogue(ids.omar, "Choose your approach, Indy.", &selector);
    const selection = (try vm.choose(0)).?;
    try std.testing.expectEqual(@as(u32, action_wits), selection.action);

    const spec = path_spec_for(selection.action).?;
    try std.testing.expectEqualStrings("Wits", spec.name);
    _ = try vm.select_path(&compiled, spec.name);
    _ = try host.tick(&vm, &compiled);

    const path_active = world.lookup_relation("PathActive").?;
    const blocked = world.lookup_relation("WaypointBlocked").?;
    try std.testing.expect(world.has_fact(world.lookup_entity("Wits").?, path_active, null));
    try std.testing.expect(world.has_fact(world.lookup_entity("FistsGate").?, blocked, null));
    try std.testing.expect(world.has_fact(world.lookup_entity("TeamGate").?, blocked, null));
    try std.testing.expect(!world.has_fact(world.lookup_entity("WitsGate").?, blocked, null));
}
