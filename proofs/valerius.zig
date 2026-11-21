//! Valerius and the Bread, the Phase 45 dilemma proof (P45-06, D-144 to D-150).
//!
//! In a hard winter at the hill-fort of Greyhold, Sergeant Brann catches Tam, a hungry boy from
//! the lower town, with a loaf from the garrison store. Tam's older sister Hesper (the player)
//! stands before Captain Valerius. Valerius holds Justice 4, Mercy 3, and Loyalty 6, and two red
//! lines: he never hangs a child and never takes a bribe. The theft weighs neutral until Hesper
//! learns what moves him and appeals to it: Mercy ends in a pardon worked off in the kitchens,
//! Loyalty to his men and the town below ends with the store opened and Tam set to guard it. The
//! outcome drifts Valerius's Mercy, and in spring, when Tam returns as a recruit, the drifted
//! value decides whether Valerius trusts him. The story and the numbers live in the script; this
//! proof owns staging, the spring move, and input.
const std = @import("std");
const bespoke = @import("bespoke");
const golden = @import("golden_digest.zig");
const art = @import("art.zig");
const host = bespoke.host;

pub const VALERIUS_SCRIPT =
    \\scene: Greyhold Store
    \\cast: Valerius, Hesper, Brann, Tam
    \\props: Loaf
    \\marks: StoreDoor, Aisle, Counter, Chimney
    \\
    \\scene: Greyhold Gate
    \\marks: Gatehouse, Wall, Road
    \\
    \\relation Carries(holder, item)
    \\relation Knows(who, what)
    \\relation Caught(who)
    \\relation Robbed(what)
    \\relation Hearing(who)
    \\relation Offered(what)
    \\relation Sentenced(who)
    \\relation Repaid(who)
    \\relation Fed(who)
    \\relation Guarded(who)
    \\relation Recruit(who)
    \\relation Settled(who)
    \\
    \\axis Justice between Cruelty and Leniency
    \\axis Mercy between Vengeance and "Condoning Harm"
    \\axis Loyalty between Servility and Treachery
    \\
    \\remember Justice(Valerius, 4)
    \\remember Mercy(Valerius, 3)
    \\remember Loyalty(Valerius, 6)
    \\remember Carries(Hesper, Purse)
    \\remember Caught(Tam)
    \\remember Robbed(Store)
    \\remember Knows(Hesper, Valerius)
    \\remember Knows(Valerius, Hang)
    \\remember Knows(Valerius, HearTheCase)
    \\remember Knows(Valerius, TakeTheCoin)
    \\remember Knows(Valerius, RefuseTheCoin)
    \\
    \\red lines Valerius: Hang, TakeTheCoin
    \\
    \\decision BrannsCounsel:
    \\  actor Valerius
    \\  fires Counselled
    \\  requires Caught(Tam)
    \\  option Hang:
    \\    picks 9 when Robbed(Store)
    \\  option HearTheCase:
    \\    picks 1 when Caught(Tam)
    \\
    \\decision HespersPurse:
    \\  actor Valerius
    \\  fires PurseOffered
    \\  requires Offered(Purse)
    \\  option TakeTheCoin:
    \\    picks 9 when Robbed(Store)
    \\  option RefuseTheCoin:
    \\    picks 1 when Offered(Purse)
    \\
    \\dilemma StolenLoaf:
    \\  actor Valerius
    \\  fires Judged
    \\  requires Hearing(Tam)
    \\  weighs Justice against Mercy
    \\  appeals 4 to Mercy
    \\  appeals 8 to Loyalty toward Mercy
    \\  drifts 5 toward Mercy when Repaid(Tam)
    \\  drifts 10 toward Mercy when Fed(LowerTown)
    \\  strong Justice: "Twenty lashes in the yard, and the town will watch." -> Flog
    \\  moderate Justice: "A week in the cells, and his sister pays for the loaf." -> Cells
    \\  neutral: "Give me a reason, Hesper. The law, or the boy?" -> Weigh
    \\  moderate Mercy: "Then he works the kitchens until the loaf is paid." -> Pardon
    \\  strong Mercy: "My men went hungry too. Open the store to the lower town, and the boy guards the door." -> OpenStore
    \\
    \\dilemma TheRecruit:
    \\  actor Valerius
    \\  fires Answered
    \\  requires Recruit(Tam)
    \\  weighs Mercy against Justice
    \\  leans 3 toward Mercy when Repaid(Tam)
    \\  leans 6 toward Mercy when Guarded(Tam)
    \\  strong Mercy: "Greyhold owes you a loaf and a spear. Welcome to the wall." -> Enlist
    \\  moderate Mercy: "You stand the night watch, where I can see you." -> Probation
    \\  neutral: "Hesper, will you vouch for him?" -> Hesitate
    \\  moderate Justice: "A thief does not hold my gate." -> Refuse
    \\  strong Justice: "Leave Greyhold before dark." -> Banish
    \\
    \\command Waits: "wait for spring"
    \\
    \\on cue Counselled(Valerius, HearTheCase):
    \\  say Brann: "He took bread from the garrison store, Captain. Hang him, and no one tries it again."
    \\  say Valerius: "Put the rope away, Sergeant. He is a child, and I will hear it."
    \\  remember Hearing(Tam)
    \\
    \\on cue LooksAt(Hesper, Loaf):
    \\  say Hesper: "One grey loaf. Tam had not eaten in three days."
    \\
    \\on cue TalksTo(Hesper, Tam):
    \\  say Tam: "I only took the one loaf, Hes."
    \\
    \\on cue TalksTo(Hesper, Brann):
    \\  say Brann: "The captain decides. I only caught him."
    \\
    \\on cue TalksTo(Hesper, Valerius, Mercy):
    \\  say Valerius: "I was a hungry boy in a hard winter once. Someone fed me."
    \\  remember Knows(Hesper, "Mercy of Valerius")
    \\
    \\on cue TalksTo(Hesper, Valerius, Loyalty):
    \\  say Valerius: "Every man on this wall eats before I do. So does the town below it, when I can manage it."
    \\  remember Knows(Hesper, "Loyalty of Valerius")
    \\
    \\on cue TalksTo(Hesper, Valerius, Justice):
    \\  say Valerius: "The store feeds the garrison. A theft from it is a theft from every man here."
    \\  remember Knows(Hesper, "Justice of Valerius")
    \\
    \\on cue Presents(Hesper, Valerius, Purse):
    \\  say Hesper: "Take my purse for the loaf, Captain, and let him go."
    \\  remember Offered(Purse)
    \\
    \\on cue PurseOffered(Valerius, RefuseTheCoin):
    \\  say Valerius: "Put your coin away. Greyhold's captain is not for sale."
    \\  forget Offered(Purse)
    \\
    \\on cue Appeals(Hesper, Valerius, Mercy):
    \\  say Hesper: "He is hungry, Captain. You know what that is."
    \\
    \\on cue Appeals(Hesper, Valerius, Loyalty):
    \\  say Hesper: "The lower town feeds this fort in summer. It is starving now, and so are your men."
    \\
    \\on cue Judged(Valerius, Pardon):
    \\  say Tam: "I'll scrub every pot in Greyhold."
    \\  remember Repaid(Tam)
    \\  remember Sentenced(Tam)
    \\
    \\on cue Judged(Valerius, OpenStore):
    \\  say Brann: "The store is open, Captain. The lower town eats tonight."
    \\  remember Fed(LowerTown)
    \\  remember Guarded(Tam)
    \\  remember Sentenced(Tam)
    \\
    \\on cue Waits(Hesper):
    \\  if Sentenced(Tam):
    \\    say Hesper: "The snow goes. In spring, Tam walks back up the hill to the gate."
    \\    forget Hearing(Tam)
    \\    transition to scene: Greyhold Gate
    \\    remember Recruit(Tam)
    \\  if not Sentenced(Tam):
    \\    say Hesper: "Not while Tam's fate is still open."
    \\
    \\on cue Answered(Valerius, Enlist):
    \\  say Tam: "I won't let the store go hungry again."
    \\  remember Settled(Tam)
    \\
    \\on cue Answered(Valerius, Probation):
    \\  say Tam: "I'll earn the day watch, Captain."
    \\  remember Settled(Tam)
;

pub const Ids = struct {
    store: bespoke.EntityId,
    gate: bespoke.EntityId,
    valerius: bespoke.EntityId,
    hesper: bespoke.EntityId,
    brann: bespoke.EntityId,
    tam: bespoke.EntityId,
    loaf: bespoke.EntityId,
    door_wp: u16,
    aisle_wp: u16,
    counter_wp: u16,
    hearth_wp: u16,
    gatehouse_wp: u16,
    wall_wp: u16,
    road_wp: u16,
};

/// Places both rooms' marks and the cast in the winter store, so the headless run, the window,
/// the browser deck, and the render golden draw the same scenes.
pub fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const store = world.lookup_entity("Greyhold Store").?;
    const gate = world.lookup_entity("Greyhold Gate").?;
    const ids = Ids{
        .store = store,
        .gate = gate,
        .valerius = world.lookup_entity("Valerius").?,
        .hesper = world.lookup_entity("Hesper").?,
        .brann = world.lookup_entity("Brann").?,
        .tam = world.lookup_entity("Tam").?,
        .loaf = world.lookup_entity("Loaf").?,
        .door_wp = spatial.graph.find_waypoint_in_room(store, "StoreDoor").?,
        .aisle_wp = spatial.graph.find_waypoint_in_room(store, "Aisle").?,
        .counter_wp = spatial.graph.find_waypoint_in_room(store, "Counter").?,
        .hearth_wp = spatial.graph.find_waypoint_in_room(store, "Chimney").?,
        .gatehouse_wp = spatial.graph.find_waypoint_in_room(gate, "Gatehouse").?,
        .wall_wp = spatial.graph.find_waypoint_in_room(gate, "Wall").?,
        .road_wp = spatial.graph.find_waypoint_in_room(gate, "Road").?,
    };
    // One row per room, at world y 4, well above the message band (D-123, D-133).
    host.place_waypoint(spatial, ids.door_wp, 4, 4);
    host.place_waypoint(spatial, ids.aisle_wp, 12, 4);
    host.place_waypoint(spatial, ids.counter_wp, 22, 4);
    host.place_waypoint(spatial, ids.hearth_wp, 36, 4);
    host.place_waypoint(spatial, ids.gatehouse_wp, 4, 4);
    host.place_waypoint(spatial, ids.wall_wp, 20, 4);
    host.place_waypoint(spatial, ids.road_wp, 36, 4);
    spatial.graph.edges.clearRetainingCapacity();
    try spatial.graph.connect(ids.door_wp, ids.aisle_wp, null);
    try spatial.graph.connect(ids.aisle_wp, ids.counter_wp, null);
    try spatial.graph.connect(ids.counter_wp, ids.hearth_wp, null);
    try spatial.graph.connect(ids.gatehouse_wp, ids.wall_wp, null);
    try spatial.graph.connect(ids.wall_wp, ids.road_wp, null);
    spatial.clear_hotspots();
    try spatial.add_hotspot(ids.loaf, store, .{ .x = 22, .y = -2 }, 6, "Loaf", "A grey garrison loaf, one corner torn off.");
    try spatial.register_entity(ids.hesper, ids.aisle_wp, 6);
    try spatial.register_entity(ids.tam, ids.door_wp, 6);
    try spatial.register_entity(ids.valerius, ids.counter_wp, 6);
    try spatial.register_entity(ids.brann, ids.hearth_wp, 6);
    return ids;
}

/// Moves the cast to the gate once the script has changed scene to spring: Valerius on the
/// wall, Hesper and Tam on the road. The headless run, the window, and the deck share it, so
/// the script's `transition to scene` stages the same way everywhere. Returns true when it moved
/// anyone.
pub fn follow_into_spring(world: *const bespoke.World, spatial: *bespoke.SpatialSystem, vm: *const bespoke.VM) !bool {
    const scene = vm.current_scene orelse return false;
    const gate = world.lookup_entity("Greyhold Gate") orelse return false;
    if (scene != gate) return false;
    const valerius = world.lookup_entity("Valerius") orelse return false;
    const agent = spatial.agents.get(valerius) orelse return false;
    const here = spatial.graph.get_waypoint(agent.current_wp) orelse return false;
    if (here.room == gate) return false;
    const places = [_]struct { name: []const u8, mark: []const u8 }{
        .{ .name = "Valerius", .mark = "Wall" },
        .{ .name = "Brann", .mark = "Gatehouse" },
        .{ .name = "Hesper", .mark = "Road" },
        .{ .name = "Tam", .mark = "Road" },
    };
    for (places) |p| {
        const who = world.lookup_entity(p.name) orelse continue;
        const wp = spatial.graph.find_waypoint_in_room(gate, p.mark) orelse continue;
        _ = try spatial.transition_actor(who, gate, wp);
    }
    return true;
}

/// One typed line for Hesper; the engine's frames and the script's own resolve it.
pub fn type_line(vm: *bespoke.VM, compiled: *const bespoke.CompiledProgram, interp: *bespoke.command.Interpreter, ids: Ids, line: []const u8, buf: []u8) !host.CommandReply {
    return host.run_command(vm, compiled, interp, ids.hesper, line, buf);
}

/// The lines of each playthrough. Both learn a value before the appeal that uses it, and both
/// first try an appeal Hesper has not earned, so the refusal is in the transcript.
pub const MERCY_PATH = [_][]const u8{ "appeal to mercy", "present the purse to valerius", "ask valerius about mercy", "appeal to mercy", "wait for spring" };
pub const LOYALTY_PATH = [_][]const u8{ "ask valerius about loyalty", "appeal to loyalty", "wait for spring" };

fn value_of(world: *const bespoke.World, ids: Ids, axis: []const u8) i32 {
    const rel = world.lookup_relation(axis) orelse return 0;
    return @bitCast(world.get_property(ids.valerius, rel) orelse 0);
}

fn chosen_name(world: *const bespoke.World, dilemma: []const u8) []const u8 {
    const entity = world.lookup_entity(dilemma) orelse return "none";
    const action = bespoke.dilemma.chosen(world, entity) orelse return "none";
    return world.get_entity_name(action) orelse "none";
}

const Story = struct {
    world: bespoke.World,
    spatial: bespoke.SpatialSystem,
    compiled: bespoke.CompiledProgram,
    vm: bespoke.VM,
    ids: Ids,
    interp: bespoke.command.Interpreter = .{},

    fn init(self: *Story, allocator: std.mem.Allocator) !void {
        self.world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
        self.spatial = bespoke.SpatialSystem.init(allocator);
        self.compiled = try bespoke.compile_source(allocator, &self.world, &self.spatial, VALERIUS_SCRIPT);
        self.ids = try configure(&self.world, &self.spatial);
        self.vm = bespoke.VM.init(allocator, &self.world, &self.compiled.chunk);
        self.vm.spatial = &self.spatial;
        self.interp = .{};
        try self.vm.transition_to_scene(self.ids.store);
        try self.vm.load_compiled_rules(&self.compiled);
        try host.initialize_subsystems(&self.world, &self.compiled);
        try host.run_initial_statements(&self.world, &self.vm, &self.compiled);
    }

    fn deinit(self: *Story) void {
        self.vm.deinit();
        self.compiled.deinit();
        self.spatial.deinit();
        self.world.deinit();
    }

    /// One tick, the spring move, and whatever was said, indented under the line that caused it.
    fn tick(self: *Story, writer: anytype) !void {
        _ = try host.tick(&self.vm, &self.compiled);
        _ = try follow_into_spring(&self.world, &self.spatial, &self.vm);
        var buf: [512]u8 = undefined;
        if (host.speech_this_tick(&self.world, &self.vm, &buf)) |line| try writer.print("  {s}\n", .{line});
    }

    fn say(self: *Story, writer: anytype, line: []const u8) !void {
        try writer.print("> {s}\n", .{line});
        var buf: [160]u8 = undefined;
        const reply = try type_line(&self.vm, &self.compiled, &self.interp, self.ids, line, &buf);
        if (reply.text) |text| try writer.print("  {s}\n", .{text});
        try self.tick(writer);
        try self.tick(writer);
    }
};

fn play(allocator: std.mem.Allocator, writer: anytype, title: []const u8, lines: []const []const u8) !void {
    try writer.print("[{s}]\n", .{title});
    var story: Story = undefined;
    try story.init(allocator);
    defer story.deinit();
    const ids = story.ids;
    for (0..3) |_| try story.tick(writer);
    try writer.print("  (Brann's counsel: {s}; Hang scored 9 and is a red line.)\n", .{chosen_name(&story.world, "BrannsCounsel")});
    const mercy_before = value_of(&story.world, ids, "Mercy");
    // The winter's `Chose` clears when spring re-arms the dilemma, so read it first.
    var winter: []const u8 = "none";
    for (lines) |line| {
        if (std.mem.eql(u8, line, "wait for spring")) winter = chosen_name(&story.world, "StolenLoaf");
        try story.say(writer, line);
    }
    for (0..2) |_| try story.tick(writer);
    try writer.print("  (Winter: {s}. Valerius's Mercy {d} -> {d} by drift; Justice {d}. Spring: {s}.)\n\n", .{
        winter,
        mercy_before,
        value_of(&story.world, ids, "Mercy"),
        value_of(&story.world, ids, "Justice"),
        chosen_name(&story.world, "TheRecruit"),
    });
    if (!story.world.has_fact(ids.tam, story.world.lookup_relation("Settled").?, null)) return error.SpringUnsettled;
    if (story.vm.current_scene != ids.gate) return error.SpringNotReached;
    try golden.final_facts(allocator, writer, &story.world);
    try writer.writeAll("\n");
}

/// Deterministic proof: both appeals from the same opening, each with its refusal, learning,
/// winter judgement, drift, and spring answer.
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("          BeSpoke Engine: Valerius and the Bread (Values)          \n");
    try writer.writeAll("      (Value Axes * Red Lines * Dilemma Tiers * Drift * Appeals)    \n");
    try writer.writeAll("===================================================================\n\n");
    try play(allocator, writer, "The appeal to Mercy", &MERCY_PATH);
    try play(allocator, writer, "The appeal to Loyalty", &LOYALTY_PATH);
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: two appeals, two winters, two springs.    \n");
    try writer.writeAll("===================================================================\n");
}

const theme = art.theme;

/// One window session's game logic, separate from the event loop so tests can drive it.
const Play = struct {
    world: *bespoke.World,
    spatial: *bespoke.SpatialSystem,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    session: *host.Session,
    interp: *bespoke.command.Interpreter,
    window: *bespoke.display.DisplayWindow,
    ids: Ids,

    fn advance(self: Play) !void {
        _ = try self.session.advance();
        if (try follow_into_spring(self.world, self.spatial, self.vm)) self.session.refresh();
        var buf: [512]u8 = undefined;
        if (host.speech_this_tick(self.world, self.vm, &buf)) |line| self.window.set_cue_banner(line, 360);
        self.refresh_words();
    }

    fn refresh_words(self: Play) void {
        host.command_words(self.vm, self.compiled, self.ids.hesper, &self.window.command_words);
    }

    fn handle(self: Play, action: bespoke.display.renderer.UserAction) !void {
        switch (action) {
            .typed_command => |t| {
                var buf: [160]u8 = undefined;
                const reply = try type_line(self.vm, self.compiled, self.interp, self.ids, t.buf[0..t.len], &buf);
                if (reply.text) |text| self.window.set_cue_banner(text, 240);
                if (reply.fired) try self.advance();
                self.refresh_words();
            },
            .interact_actor => |a| {
                const frame = self.session.frame();
                if (a.actor_index < frame.entity_count) {
                    _ = try self.vm.fire_cue(self.compiled, "TalksTo", self.ids.hesper, frame.entities[a.actor_index].entity, null);
                    try self.advance();
                }
            },
            .examine_hotspot, .interact_hotspot => {
                const frame = self.session.frame();
                const index: usize = switch (action) {
                    .examine_hotspot => |i| i,
                    .interact_hotspot => |h| h.hotspot_index,
                    else => unreachable,
                };
                if (index < frame.hotspot_count) {
                    _ = try self.vm.fire_cue(self.compiled, "LooksAt", self.ids.hesper, frame.hotspots[index].entity, null);
                    try self.advance();
                }
            },
            else => {},
        }
    }

    fn banner(self: Play) []const u8 {
        return self.window.cue_banner_text[0..self.window.cue_banner_len];
    }
};

pub const INTRO = "Greyhold: press Enter and type, such as \"ask valerius about mercy\" or \"appeal to mercy\". Then \"wait for spring\".";

/// Native window proof. The ordinary Session supplies pause, save/load, scrub, and rewind.
pub fn run_interactive(allocator: std.mem.Allocator, io: std.Io, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, VALERIUS_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.store);
    try vm.load_compiled_rules(&compiled);
    try host.initialize_subsystems(&world, &compiled);
    try host.run_initial_statements(&world, &vm, &compiled);

    var window = try bespoke.display.DisplayWindow.init(io, "BeSpoke Engine - Valerius and the Bread", 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    if (window.is_headless) return run_headless(allocator, stdout);
    try stdout.writeAll("\nValerius and the Bread: [Enter] opens the command bar. Try 'ask valerius about mercy', 'ask valerius about loyalty', 'appeal to mercy', 'appeal to loyalty', 'present the purse to valerius', and, once Tam is sentenced, 'wait for spring'. Clicking a person talks to them.\n");
    try stdout.writeAll("Pause/save/load, single-step, scrub, rewind, debug, and console use the standard engine controls.\n\n");

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    bridge.attach_audio_bridge(window.audio_bridge);
    bridge.set_active_character(ids.hesper);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();
    window.set_cue_banner(INTRO, 300);
    window.enable_command_bar(true);
    var interp = bespoke.command.Interpreter{};
    const p = Play{ .world = &world, .spatial = &spatial, .vm = &vm, .compiled = &compiled, .session = &session, .interp = &interp, .window = &window, .ids = ids };
    p.refresh_words();

    while (true) {
        const action = window.poll_events(session.frame());
        if (action == .quit) break;
        if (!(try session.handle_common(action))) try p.handle(action);
        if (action != .none and action != .step_tick and action != .toggle_pause) session.refresh();
        if (session.tick_due()) try p.advance();
        session.render();
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P45-06: both appeals reach spring with different winters and springs" {
    var buf: [64]u8 = undefined;
    var sink: std.Io.Writer.Discarding = .init(&buf);
    try run_headless(std.testing.allocator, &sink.writer);
}

test "P45-06: the script uses values, red lines, a five-tier dilemma, drift, and appeals" {
    var world = try bespoke.World.init(std.testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(std.testing.allocator, &world, &spatial, VALERIUS_SCRIPT);
    defer compiled.deinit();
    try std.testing.expectEqual(@as(usize, 3), compiled.axes.items.len);
    try std.testing.expectEqual(@as(usize, 2), compiled.red_lines.items[0].red_lines.options.len);
    try std.testing.expectEqual(@as(usize, 2), compiled.dilemmas.items.len);
    try std.testing.expectEqual(@as(usize, 2), compiled.dilemmas.items[0].dilemma.appeals.len);
    try std.testing.expectEqual(@as(usize, 2), compiled.dilemmas.items[0].dilemma.drifts.len);
}

test "P45-06: typed lines in the window reply on the banner" {
    const allocator = std.testing.allocator;
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, VALERIUS_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.store);
    try vm.load_compiled_rules(&compiled);
    try host.initialize_subsystems(&world, &compiled);
    try host.run_initial_statements(&world, &vm, &compiled);
    var window = try bespoke.display.DisplayWindow.init_offscreen(std.testing.io, 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    window.enable_command_bar(true);
    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();
    var interp = bespoke.command.Interpreter{};
    const p = Play{ .world = &world, .spatial = &spatial, .vm = &vm, .compiled = &compiled, .session = &session, .interp = &interp, .window = &window, .ids = ids };
    for (0..3) |_| try p.advance();
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "The law, or the boy?") != null);

    const typed = struct {
        fn line(pl: Play, text: []const u8) !void {
            var t = bespoke.display.renderer.UserAction{ .typed_command = .{ .buf = undefined, .len = text.len } };
            @memcpy(t.typed_command.buf[0..text.len], text);
            try pl.handle(t);
        }
    }.line;
    try typed(p, "appeal to loyalty");
    try std.testing.expectEqualStrings("You don't know what moves them.", p.banner());
    try typed(p, "ask valerius about loyalty");
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "Every man on this wall") != null);
    // Completion offers the value words.
    var found = false;
    for (0..window.command_words.len) |i| {
        if (std.mem.eql(u8, window.command_words.word(i), "loyalty")) found = true;
    }
    try std.testing.expect(found);
}
