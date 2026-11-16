//! The Saltmarket, the Phase 24 path-divergence proof (P24-03, P35-09).
//!
//! Three approaches reach Pilot Ashe's lost logbook in Broker Quince's stall by different routes. The
//! selected path asserts facts that lock the other two gates, so the same spatial graph is
//! navigable only through that approach. Quince's dialogue repertoire is pruned by the same route.
//! The script owns the paths, facts, routines, and dialogue; this proof owns staging and input.
const std = @import("std");
const bespoke = @import("bespoke");
const golden = @import("golden_digest.zig");
const host = bespoke.host;
const r = bespoke.display.renderer;

pub const SALTMARKET_SCRIPT =
    \\scene: Saltmarket
    \\cast: Tamsin, BrokerQuince
    \\props: Logbook
    \\marks: Entrance, StallMark, CunningGate, MuscleGate, CrewGate, LogbookMark
    \\
    \\relation Chosen(actor, approach)
    \\relation Solved(actor, approach)
    \\relation Acquired(actor, item)
    \\relation WaypointBlocked(mark)
    \\
    \\path Cunning:
    \\  remember Chosen(Tamsin, Cunning)
    \\  remember WaypointBlocked(MuscleGate)
    \\  remember WaypointBlocked(CrewGate)
    \\  routine SolveCunning(Tamsin):
    \\    say Tamsin: "The tally book's margin points to a false bill of lading. The logbook is tucked behind it."
    \\    remember Solved(Tamsin, Cunning)
    \\    remember Acquired(Tamsin, Logbook)
    \\
    \\path Muscle:
    \\  remember Chosen(Tamsin, Muscle)
    \\  remember WaypointBlocked(CunningGate)
    \\  remember WaypointBlocked(CrewGate)
    \\  routine SolveMuscle(Tamsin):
    \\    say Tamsin: "Quince's porter folds under one good shove. The back room gives up the logbook."
    \\    remember Solved(Tamsin, Muscle)
    \\    remember Acquired(Tamsin, Logbook)
    \\
    \\path Crew:
    \\  remember Chosen(Tamsin, Crew)
    \\  remember WaypointBlocked(CunningGate)
    \\  remember WaypointBlocked(MuscleGate)
    \\  routine SolveCrew(Tamsin):
    \\    say Tamsin: "The net-menders know the back way in. We split the reward and walk out together."
    \\    remember Solved(Tamsin, Crew)
    \\    remember Acquired(Tamsin, Logbook)
    \\
    \\on cue Talk(Tamsin, BrokerQuince):
    \\  choice "Read the tally book" if PathActive(Cunning):
    \\    say BrokerQuince: "The tally book was always the map, Miss Tamsin."
    \\  choice "Force the stall" if PathActive(Muscle):
    \\    say BrokerQuince: "Not the bills of lading! Take the logbook!"
    \\  choice "Recruit the net-menders" if PathActive(Crew):
    \\    say BrokerQuince: "A share for every hand. That is how the Saltmarket survives."
    \\  choice "Leave Quince's stall":
    \\    say BrokerQuince: "Come back when you know what you want."
;

pub const PathSpec = struct {
    name: []const u8,
    gate: []const u8,
    blocked: [2][]const u8,
    routine: []const u8,
    choice: []const u8,
    banner: []const u8,
};

pub const paths = [_]PathSpec{
    .{
        .name = "Cunning",
        .gate = "CunningGate",
        .blocked = .{ "MuscleGate", "CrewGate" },
        .routine = "SolveCunning",
        .choice = "Read the tally book",
        .banner = "Cunning selected. Walk to the logbook, talk to Quince, then press [S].",
    },
    .{
        .name = "Muscle",
        .gate = "MuscleGate",
        .blocked = .{ "CunningGate", "CrewGate" },
        .routine = "SolveMuscle",
        .choice = "Force the stall",
        .banner = "Muscle selected. Walk to the logbook, talk to Quince, then press [S].",
    },
    .{
        .name = "Crew",
        .gate = "CrewGate",
        .blocked = .{ "CunningGate", "MuscleGate" },
        .routine = "SolveCrew",
        .choice = "Recruit the net-menders",
        .banner = "Crew selected. Walk to the logbook, talk to Quince, then press [S].",
    },
};

pub const Ids = struct {
    scene: bespoke.EntityId,
    tamsin: bespoke.EntityId,
    quince: bespoke.EntityId,
    logbook: bespoke.EntityId,
    entrance_wp: u16,
    stall_wp: u16,
    logbook_wp: u16,
};

pub fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const scene = world.lookup_entity("Saltmarket").?;
    const ids = Ids{
        .scene = scene,
        .tamsin = world.lookup_entity("Tamsin").?,
        .quince = world.lookup_entity("BrokerQuince").?,
        .logbook = world.lookup_entity("Logbook").?,
        .entrance_wp = spatial.graph.find_waypoint_in_room(scene, "Entrance").?,
        .stall_wp = spatial.graph.find_waypoint_in_room(scene, "StallMark").?,
        .logbook_wp = spatial.graph.find_waypoint_in_room(scene, "LogbookMark").?,
    };

    host.place_waypoint(spatial, ids.entrance_wp, 0, 0);
    host.place_waypoint(spatial, ids.stall_wp, 0, 10);
    host.place_waypoint(spatial, spatial.graph.find_waypoint_in_room(scene, "CunningGate").?, 20, -10);
    host.place_waypoint(spatial, spatial.graph.find_waypoint_in_room(scene, "MuscleGate").?, 20, 0);
    host.place_waypoint(spatial, spatial.graph.find_waypoint_in_room(scene, "CrewGate").?, 20, 10);
    host.place_waypoint(spatial, ids.logbook_wp, 40, 0);

    spatial.graph.edges.clearRetainingCapacity();
    const cunning_gate = spatial.graph.find_waypoint_in_room(scene, "CunningGate").?;
    const muscle_gate = spatial.graph.find_waypoint_in_room(scene, "MuscleGate").?;
    const crew_gate = spatial.graph.find_waypoint_in_room(scene, "CrewGate").?;
    try spatial.graph.connect(ids.entrance_wp, ids.stall_wp, null);
    try spatial.graph.connect(ids.entrance_wp, cunning_gate, null);
    try spatial.graph.connect(ids.entrance_wp, muscle_gate, null);
    try spatial.graph.connect(ids.entrance_wp, crew_gate, null);
    try spatial.graph.connect(cunning_gate, ids.logbook_wp, null);
    try spatial.graph.connect(muscle_gate, ids.logbook_wp, null);
    try spatial.graph.connect(crew_gate, ids.logbook_wp, null);

    spatial.clear_hotspots();
    try spatial.add_hotspot(ids.logbook, scene, .{ .x = 40, .y = -4 }, 6, "Lost Logbook", "Pilot Ashe's logbook, hidden behind the broker's bills of lading.");
    try spatial.register_entity(ids.tamsin, ids.entrance_wp, 10);
    try spatial.register_entity(ids.quince, ids.stall_wp, 1);
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
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SALTMARKET_SCRIPT);
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
    try std.testing.expect(world.has_fact(ids.tamsin, chosen, route.to_int()));

    for (spec.blocked) |gate_name| {
        const gate = path_entity(&world, gate_name);
        try std.testing.expect(world.has_fact(gate, blocked, null));
    }
    try std.testing.expect(!world.has_fact(path_entity(&world, spec.gate), blocked, null));

    try writer.print("  locks: {s}, {s}\n", .{ spec.blocked[0], spec.blocked[1] });
    try writer.print("  route: Entrance -> {s} -> LogbookMark\n", .{spec.gate});

    if (!try spatial.walk_to_with_world(&world, ids.tamsin, ids.logbook_wp)) return error.NoRoute;
    const gate_wp = spatial.graph.find_waypoint_in_room(ids.scene, spec.gate).?;
    var passed_gate = false;
    var ticks: usize = 0;
    while (ticks < 12) : (ticks += 1) {
        _ = try host.tick(&vm, &compiled);
        const here = spatial.get_current_waypoint(ids.tamsin).?;
        if (here == gate_wp) passed_gate = true;
        if (here == ids.logbook_wp) break;
    }
    if (!passed_gate) return error.DidNotPassSelectedGate;
    if (spatial.get_current_waypoint(ids.tamsin) != ids.logbook_wp) return error.DidNotReachLogbook;

    try vm.set_dialogue_speaker(ids.tamsin, ids.quince);
    _ = try vm.fire_cue(&compiled, "Talk", ids.tamsin, ids.quince, null);
    _ = try host.tick(&vm, &compiled);
    const open = vm.dialogue_view() orelse return error.NoQuinceDialogue;
    if (open.count != 2) return error.WrongDialogueRepertoire;
    if (!std.mem.eql(u8, open.text(0), spec.choice)) return error.WrongDialogueChoice;
    if (!std.mem.eql(u8, open.text(1), "Leave Quince's stall")) return error.MissingLeaveChoice;
    try writer.print("  dialogue: {s} (rival choices pruned)\n", .{spec.choice});

    _ = (try vm.choose(0)) orelse return error.ChoiceNotSelected;
    _ = try host.tick(&vm, &compiled);
    var speech_buf: [256]u8 = undefined;
    if (host.speech_this_tick(&world, &vm, &speech_buf)) |line| {
        try writer.print("  {s}\n", .{line});
    }

    const routine_entry = compiled.routine_entries.get(spec.routine) orelse return error.UnknownPathRoutine;
    _ = try vm.spawn_routine(ids.tamsin, routine_entry);
    _ = try host.tick(&vm, &compiled);
    try std.testing.expect(world.has_fact(ids.tamsin, solved, route.to_int()));
    try std.testing.expect(world.has_fact(ids.tamsin, acquired, ids.logbook.to_int()));

    for (paths) |other| {
        if (std.mem.eql(u8, other.name, spec.name)) continue;
        const other_entry = compiled.routine_entries.get(other.routine) orelse return error.UnknownPathRoutine;
        _ = try vm.spawn_routine(ids.tamsin, other_entry);
        _ = try host.tick(&vm, &compiled);
        if (world.has_fact(ids.tamsin, solved, path_entity(&world, other.name).to_int())) {
            return error.InactivePathRoutineRan;
        }
    }

    try writer.print("  solve: Solved(Tamsin, {s}); Acquired(Tamsin, Logbook)\n", .{spec.name});
    try writer.writeAll("  rival path routines: muted\n\n");
    try golden.final_facts(allocator, writer, &world);
}

pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("      BeSpoke Engine: The Saltmarket                               \n");
    try writer.writeAll("      (Three Paths * Waypoint Locks * Route Dialogue)             \n");
    try writer.writeAll("===================================================================\n\n");

    for (paths) |spec| {
        try writer.print("Path {s}:\n", .{spec.name});
        try run_path(allocator, writer, spec);
    }

    try writer.writeAll("===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: all three approaches reach the logbook.\n");
    try writer.writeAll("===================================================================\n\n");
}

const action_cunning: u16 = 1;
const action_muscle: u16 = 2;
const action_crew: u16 = 3;
const action_talk: u16 = 4;
const action_solve: u16 = 5;

const keys = [_]r.KeyBinding{
    .{ .key = r.key('1'), .action = action_cunning },
    .{ .key = r.key('2'), .action = action_muscle },
    .{ .key = r.key('3'), .action = action_crew },
    .{ .key = r.key('t'), .action = action_talk },
    .{ .key = r.key('s'), .action = action_solve },
};

fn saltmarket_backdrop(w: *r.Canvas, frame: *const bespoke.RenderFrame) bool {
    _ = frame;
    w.fill_rect(0, 0, w.width, w.height, r.Color{ .r = 58, .g = 38, .b = 24 });
    w.fill_rect(0, w.height - 150, w.width, 150, r.Color{ .r = 158, .g = 122, .b = 70 });
    w.fill_rect(90, 110, w.width - 180, 34, r.Color{ .r = 38, .g = 112, .b = 118 });
    w.fill_rect(110, 144, w.width - 220, 10, r.Color{ .r = 212, .g = 172, .b = 82 });
    return true;
}

pub const theme = r.Theme{
    .backdrop = saltmarket_backdrop,
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
    if (spatial.get_current_waypoint(ids.tamsin) != ids.logbook_wp) return false;
    const entry = compiled.routine_entries.get(spec.routine) orelse return error.UnknownPathRoutine;
    _ = try vm.spawn_routine(ids.tamsin, entry);
    return true;
}

pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, SALTMARKET_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);
    try vm.load_compiled_rules(&compiled);
    try host.run_initial_statements(&world, &vm, &compiled);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Saltmarket", 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    if (window.is_headless) return run_headless(allocator, stdout);

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_active_character(ids.tamsin);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();

    const selector = [_]bespoke.dialogue.Choice{
        .{ .text = "Cunning: read the tally book", .action = action_cunning },
        .{ .text = "Muscle: force the stall", .action = action_muscle },
        .{ .text = "Crew: recruit the net-menders", .action = action_crew },
    };
    _ = try vm.open_generated_dialogue(ids.quince, "Choose your approach, Tamsin.", &selector);
    try session.record_now();
    window.set_cue_banner("Choose a way in: [1] Cunning, [2] Muscle, [3] Crew. Then talk and solve.", 600);

    try stdout.writeAll("\nSaltmarket: choose [1] Cunning, [2] Muscle, or [3] Crew. Click LogbookMark to walk.\n");
    try stdout.writeAll("[T] talks to Quince with the selected repertoire; [S] solves at LogbookMark.\n\n");

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
                    _ = try vm.open_generated_dialogue(ids.quince, "Choose your approach, Tamsin.", &selector);
                    try session.record_now();
                }
            },
            .custom => |which| {
                if (which == action_cunning or which == action_muscle or which == action_crew) {
                    const choice_index: usize = @intCast(which - action_cunning);
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
                            _ = try vm.fire_cue(&compiled, "Talk", ids.tamsin, ids.quince, null);
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
                            if (world.has_fact(ids.tamsin, acquired, ids.logbook.to_int())) {
                                window.set_cue_banner("The logbook is yours.", 240);
                            } else {
                                window.set_cue_banner("The path routine did not run.", 120);
                            }
                        } else {
                            window.set_cue_banner("Walk to the logbook before solving.", 90);
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
                    _ = try spatial.walk_to_with_world(&world, ids.tamsin, waypoint);
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

test "P24-03: all three Saltmarket approaches acquire the logbook" {
    try run_headless(std.testing.allocator, std.io.null_writer);
}

test "P24-03: the generated selector chooses the Cunning route" {
    var world = try bespoke.World.init(std.testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(std.testing.allocator, &world, &spatial, SALTMARKET_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);

    var vm = bespoke.VM.init(std.testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.scene);

    const selector = [_]bespoke.dialogue.Choice{
        .{ .text = "Cunning: read the tally book", .action = action_cunning },
        .{ .text = "Muscle: force the stall", .action = action_muscle },
        .{ .text = "Crew: recruit the net-menders", .action = action_crew },
    };
    _ = try vm.open_generated_dialogue(ids.quince, "Choose your approach, Tamsin.", &selector);
    const selection = (try vm.choose(0)).?;
    try std.testing.expectEqual(@as(u32, action_cunning), selection.action);

    const spec = path_spec_for(selection.action).?;
    try std.testing.expectEqualStrings("Cunning", spec.name);
    _ = try vm.select_path(&compiled, spec.name);
    _ = try host.tick(&vm, &compiled);

    const path_active = world.lookup_relation("PathActive").?;
    const blocked = world.lookup_relation("WaypointBlocked").?;
    try std.testing.expect(world.has_fact(world.lookup_entity("Cunning").?, path_active, null));
    try std.testing.expect(world.has_fact(world.lookup_entity("MuscleGate").?, blocked, null));
    try std.testing.expect(world.has_fact(world.lookup_entity("CrewGate").?, blocked, null));
    try std.testing.expect(!world.has_fact(world.lookup_entity("CunningGate").?, blocked, null));
}
