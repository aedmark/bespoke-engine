//! The Lamplighter's Round (P46-05): an original proof drawn entirely from imported PNG art.
//!
//! At dusk Nell lights the lamps of Tallow Lane and Market Steps before Constable Pike walks his
//! round. Hobb the chandler gives her a taper, the oil cask fills her can, and one fill lights
//! one lamp, so she returns to the cask before crossing to the market.
//!
//! The script and its PNG files live in `proofs/art/lamplighter/`. The build compiles them with
//! `bespoke compile` into the package embedded here (D-156), so the desktop window, the headless
//! golden, and the browser deck all load the same package, and nothing at run time decodes PNG
//! (D-151). Backdrops, people, and the oil cask are declared sprites the engine draws; the
//! lamps change art when lit, which declared sprites do not do, so this proof's theme picks the
//! lamp sheet's dark or lit frame from the shared status (D-041). That choice lives here, not in
//! the engine (D-031).
const std = @import("std");
const bespoke = @import("bespoke");
const golden = @import("golden_digest.zig");
const art = @import("art.zig");
const host = bespoke.host;
const image = bespoke.image;
const r = bespoke.display.renderer;

/// The compiled package: script, palette, images, and sprites.
pub const PACKAGE = @embedFile("lamplighter_bspk");
/// The script as written, for tools that read scene headers from text (the render golden).
pub const SCRIPT = @embedFile("art/lamplighter/lamplighter.bespoke");

pub const LANE = "Tallow Lane";
pub const STEPS = "Market Steps";

/// The archway at the lane's end and the foot of the market steps join the two streets.
pub const EXITS = [_]host.Exit{
    .{ .scene = LANE, .mark = "LaneEnd", .to_scene = STEPS, .to_mark = "StepsFoot" },
    .{ .scene = STEPS, .mark = "StepsFoot", .to_scene = LANE, .to_mark = "LaneEnd" },
};

/// Mark positions on one row at world y 4, which stands sprites on the backdrops' cobbles
/// (art row 107) and leaves the message band clear (D-124). Hobb's stoop is under the shop
/// window, the doorstep under the painted door, the lane's end under the archway, and Pike's
/// place beside the fountain. Marks are not props: the window, door, archway, fountain, and
/// hall are props with areas on the art (D-158), so a click on one never means a mark.
const MARKS = [_]struct { scene: []const u8, mark: []const u8, x: i32 }{
    .{ .scene = LANE, .mark = "Stoop", .x = 3 },
    .{ .scene = LANE, .mark = "Doorstep", .x = 8 },
    .{ .scene = LANE, .mark = "LanePost", .x = 24 },
    .{ .scene = LANE, .mark = "LaneEnd", .x = 48 },
    .{ .scene = STEPS, .mark = "StepsFoot", .x = 2 },
    .{ .scene = STEPS, .mark = "FountainSide", .x = 9 },
    .{ .scene = STEPS, .mark = "StepsPost", .x = 34 },
};
const ROW: i32 = 4;

/// Each prop's spot is near its area's foot; the area itself (in the script) is what a click
/// reaches and what a walk to the prop aims for.
const PROPS = [_]struct { scene: []const u8, entity: []const u8, name: []const u8, x: i32, text: []const u8 }{
    .{ .scene = LANE, .entity = "OilCask", .name = "Oil Cask", .x = 14, .text = "Hobb's lamp oil, by the shop door." },
    .{ .scene = LANE, .entity = "LaneLamp", .name = "Lane Lamp", .x = 29, .text = "The Tallow Lane lamp." },
    .{ .scene = LANE, .entity = "ShopWindow", .name = "Shop Window", .x = 0, .text = "Hobb's candles in the window." },
    .{ .scene = LANE, .entity = "ShopDoor", .name = "Shop Door", .x = 8, .text = "The chandlery door." },
    .{ .scene = LANE, .entity = "Archway", .name = "Archway", .x = 48, .text = "The arch through to Market Steps." },
    .{ .scene = STEPS, .entity = "StepsLamp", .name = "Steps Lamp", .x = 39, .text = "The lamp at the foot of the market steps." },
    .{ .scene = STEPS, .entity = "Fountain", .name = "Fountain", .x = 17, .text = "The market fountain." },
    .{ .scene = STEPS, .entity = "MarketHall", .name = "Market Hall", .x = 40, .text = "The market hall at the top of the steps." },
};

const STARTS = [_]struct { who: []const u8, scene: []const u8, mark: []const u8 }{
    .{ .who = "Nell", .scene = LANE, .mark = "LanePost" },
    .{ .who = "Hobb", .scene = LANE, .mark = "Stoop" },
    .{ .who = "Pike", .scene = STEPS, .mark = "FountainSide" },
};

/// Lays out both streets, their props, and the cast. The cast is registered on desktop
/// (`registered` false) and moved in the browser, where the script has already placed them.
pub fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem, registered: bool) !void {
    var prev: ?bespoke.WaypointId = null;
    var prev_scene: []const u8 = "";
    spatial.graph.edges.clearRetainingCapacity();
    for (MARKS) |m| {
        const scene = world.lookup_entity(m.scene) orelse return error.SceneMissing;
        const wp = spatial.graph.find_waypoint_in_room(scene, m.mark) orelse return error.MarkMissing;
        host.place_waypoint(spatial, wp, m.x, ROW);
        if (prev != null and std.mem.eql(u8, prev_scene, m.scene)) try spatial.graph.connect(prev.?, wp, null);
        prev = wp;
        prev_scene = m.scene;
    }
    spatial.clear_hotspots();
    for (PROPS) |p| {
        const scene = world.lookup_entity(p.scene) orelse return error.SceneMissing;
        const id = world.lookup_entity(p.entity) orelse return error.PropMissing;
        try spatial.add_hotspot(id, scene, .{ .x = p.x, .y = ROW }, 6, p.name, p.text);
    }
    for (STARTS) |s| {
        const scene = world.lookup_entity(s.scene) orelse return error.SceneMissing;
        const who = world.lookup_entity(s.who) orelse return error.CastMissing;
        const wp = spatial.graph.find_waypoint_in_room(scene, s.mark) orelse return error.MarkMissing;
        if (registered) {
            _ = try spatial.transition_actor(who, scene, wp);
        } else try spatial.register_entity(who, wp, 6);
    }
}

// --- Presentation -------------------------------------------------------------------------

/// The program whose lamp sheet the theme draws. Each host sets it once its package is loaded.
pub var program_art: ?*const image.Art = null;

/// Draws a street lamp from the imported lamp sheet inside the lamp's area (D-158): dark, lit,
/// or, for the market lamp, dark with a jackdaw in it. Every other prop is the engine's to draw,
/// or part of the backdrop.
fn prop(cv: *bespoke.display.Canvas, frame: *const bespoke.RenderFrame, view: r.PropView) bool {
    const a = program_art orelse return false;
    const name = view.hotspot.get_name();
    const st = art.status_of(frame);
    const lane = std.mem.eql(u8, name, "Lane Lamp");
    if (!lane and !std.mem.eql(u8, name, "Steps Lamp")) return false;
    const lit = if (lane) st.lane_lamp_lit else st.steps_lamp_lit;
    // Frame 0 dark, 1 lit, 2 dark with Mrs Jessop in it.
    const shown: u32 = if (lit) 1 else if (!lane and st.jackdaw_nesting) 2 else 0;
    const sheet = a.find("LampSheet") orelse return false;
    const area = a.area_for(view.hotspot.entity) orelse return false;
    const box = r.area_rect(area);
    cv.draw_image(a.palette, sheet, shown, box.x, box.y);
    view.labels.add_obstacle(box.x, box.y, box.w, box.h);
    return true;
}

fn footer(frame: *const bespoke.RenderFrame) ?r.FooterHint {
    _ = frame;
    return .{ .text = "TALK to Hobb | USE the cask, then a lamp | walk through the archway" };
}

pub const theme = r.Theme{ .prop = prop, .footer = footer, .soundtrack = &art.soundtrack };

// --- The round, as a list of moves ---------------------------------------------------------

pub const Move = union(enum) {
    /// A heading in the transcript: the story's beginning, middle, and end.
    chapter: []const u8,
    walk: []const u8,
    cue: struct { name: []const u8, target: []const u8 },
    /// Ticks with nothing done, for lines that come on their own.
    wait: u8,
};

/// The round from dusk to nightfall, with the refusals a first-time player meets: the oil before
/// asking Hobb, a jackdaw in the market lamp, and a can that needs filling twice.
pub const ROUND = [_]Move{
    .{ .chapter = "Dusk" },
    .{ .wait = 4 },
    .{ .walk = "Doorstep" },
    .{ .cue = .{ .name = "LooksAt", .target = "OilCan" } },
    .{ .cue = .{ .name = "Uses", .target = "OilCask" } },
    .{ .cue = .{ .name = "TalksTo", .target = "Hobb" } },
    .{ .cue = .{ .name = "Uses", .target = "OilCask" } },
    .{ .cue = .{ .name = "LooksAt", .target = "OilCan" } },
    .{ .walk = "LanePost" },
    .{ .cue = .{ .name = "Uses", .target = "LaneLamp" } },
    .{ .cue = .{ .name = "LooksAt", .target = "OilCan" } },
    .{ .chapter = "Mrs Jessop" },
    .{ .walk = "Doorstep" },
    .{ .cue = .{ .name = "Uses", .target = "OilCask" } },
    .{ .walk = "LaneEnd" },
    .{ .walk = "StepsPost" },
    .{ .cue = .{ .name = "Uses", .target = "StepsLamp" } },
    .{ .walk = "FountainSide" },
    .{ .cue = .{ .name = "TalksTo", .target = "Pike" } },
    .{ .walk = "StepsFoot" },
    .{ .walk = "Doorstep" },
    .{ .cue = .{ .name = "TalksTo", .target = "Hobb" } },
    .{ .walk = "LaneEnd" },
    .{ .walk = "StepsPost" },
    .{ .cue = .{ .name = "Uses", .target = "StepsLamp" } },
    .{ .chapter = "Nightfall" },
    .{ .cue = .{ .name = "Uses", .target = "StepsLamp" } },
    .{ .wait = 12 },
    .{ .cue = .{ .name = "TalksTo", .target = "Pike" } },
};

/// A world loaded from the package, staged, and started.
const Round = struct {
    world: bespoke.World,
    spatial: bespoke.SpatialSystem,
    compiled: bespoke.CompiledProgram,
    vm: bespoke.VM,
    nell: bespoke.EntityId,

    fn init(self: *Round, allocator: std.mem.Allocator) !void {
        self.world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
        errdefer self.world.deinit();
        self.spatial = bespoke.SpatialSystem.init(allocator);
        errdefer self.spatial.deinit();
        var stream: std.Io.Reader = .fixed(PACKAGE);
        self.compiled = try bespoke.load_package(allocator, &stream, &self.world, &self.spatial);
        errdefer self.compiled.deinit();
        try configure(&self.world, &self.spatial, false);
        self.vm = bespoke.VM.init(allocator, &self.world, &self.compiled.chunk);
        errdefer self.vm.deinit();
        self.vm.spatial = &self.spatial;
        self.nell = self.world.lookup_entity("Nell").?;
        try self.vm.transition_to_scene(self.world.lookup_entity(LANE).?);
        try self.vm.load_compiled_rules(&self.compiled);
        try host.initialize_subsystems(&self.world, &self.compiled);
        try host.run_initial_statements(&self.world, &self.vm, &self.compiled);
        _ = try host.start_routine(&self.world, &self.spatial, &self.vm, &self.compiled, "Dusk", "Hobb", 6);
    }

    fn deinit(self: *Round) void {
        self.vm.deinit();
        self.compiled.deinit();
        self.spatial.deinit();
        self.world.deinit();
    }

    fn tick(self: *Round, writer: anytype) !void {
        _ = try host.tick(&self.vm, &self.compiled);
        var buf: [512]u8 = undefined;
        if (host.speech_this_tick(&self.world, &self.vm, &buf)) |line| try writer.print("  {s}\n", .{line});
    }

    /// Walks Nell to a mark in her room, ticking until she arrives, then takes a doorway there.
    fn walk(self: *Round, writer: anytype, mark: []const u8) !void {
        const here = self.spatial.get_current_waypoint(self.nell) orelse return error.NellOffStage;
        const room = self.spatial.graph.get_waypoint(here).?.room;
        const wp = self.spatial.graph.find_waypoint_in_room(room, mark) orelse return error.MarkMissing;
        try writer.print("> walk to {s}\n", .{mark});
        _ = try self.spatial.walk_to(self.nell, wp);
        var guard: usize = 0;
        while (self.spatial.is_moving(self.nell)) : (guard += 1) {
            if (guard > 60) return error.WalkStalled;
            try self.tick(writer);
        }
        if (try host.take_exit_here(&self.world, &self.spatial, &self.vm, &EXITS, self.nell)) |exit| {
            try writer.print("  (Nell goes through to {s}.)\n", .{exit.to_scene});
        }
    }

    fn act(self: *Round, writer: anytype, cue: []const u8, target: []const u8) !void {
        try writer.print("> {s} {s}\n", .{ cue, target });
        _ = try self.vm.fire_cue(&self.compiled, cue, self.nell, self.world.lookup_entity(target).?, null);
        try self.tick(writer);
        try self.tick(writer);
    }
};

/// Deterministic proof: the round from the first refusal to Pike's good night.
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("          BeSpoke Engine: The Lamplighter's Round (Pixel Art)       \n");
    try writer.writeAll("  (PNG Import * Backdrops * Animated Sprites * Areas * Art by State) \n");
    try writer.writeAll("===================================================================\n\n");
    var round: Round = undefined;
    try round.init(allocator);
    defer round.deinit();
    const art_of = round.compiled.art;
    try writer.print("  (Art: {d} images, {d} colours, {d} backdrops, {d} sprites, all imported from PNG.)\n\n", .{
        art_of.images.len, art_of.palette.len, art_of.backdrops.len, art_of.sprites.len,
    });
    for (ROUND) |move| switch (move) {
        .chapter => |title| try writer.print("\n[{s}]\n", .{title}),
        .walk => |mark| try round.walk(writer, mark),
        .cue => |c| try round.act(writer, c.name, c.target),
        .wait => |n| for (0..n) |_| try round.tick(writer),
    };
    var guard: usize = 0;
    const pike = round.world.lookup_entity("Pike").?;
    while (round.spatial.is_moving(pike) and guard < 60) : (guard += 1) try round.tick(writer);
    if (!round.world.has_fact(round.nell, round.world.lookup_relation("RoundDone").?, null)) return error.RoundUnfinished;
    try writer.writeAll("\n");
    try golden.final_facts(allocator, writer, &round.world);
    try writer.writeAll("\n===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: dusk to nightfall, drawn from imported art. \n");
    try writer.writeAll("===================================================================\n");
}

pub const INTRO = "Dusk on Tallow Lane, and Nell Brindle is late: light both lamps before Pike walks his round. LOOK at your items to see how they stand.";

fn cue_for(verb: r.AdventureVerb) ?[]const u8 {
    return switch (verb) {
        .look_at => "LooksAt",
        .talk_to => "TalksTo",
        .use_with, .pick_up => "Uses",
        .walk => null,
    };
}

/// One window session's game logic, apart from the event loop so tests drive it as clicks do.
/// Every advance of the world, by the clock or by a click, puts what was said on the banner:
/// a click's tick is the tick its reply is spoken in.
const Play = struct {
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    session: *host.Session,
    window: *bespoke.display.DisplayWindow,
    nell: bespoke.EntityId,

    fn advance(self: Play) !void {
        _ = try self.session.advance();
        var buf: [512]u8 = undefined;
        if (host.speech_this_tick(self.world, self.vm, &buf)) |line| self.window.set_cue_banner(line, 300);
    }

    fn act(self: Play, cue: []const u8, target: bespoke.EntityId) !void {
        _ = try self.vm.fire_cue(self.compiled, cue, self.nell, target, null);
        try self.advance();
    }

    fn handle(self: Play, action: r.UserAction) !void {
        const frame = self.session.frame();
        switch (action) {
            .walk_player => |wp| _ = try self.session.walk_player(wp),
            .interact_actor => |a| if (cue_for(a.verb)) |cue| {
                if (a.actor_index < frame.entity_count) try self.act(cue, frame.entities[a.actor_index].entity);
            },
            .interact_hotspot => |h| if (cue_for(h.verb)) |cue| {
                if (h.hotspot_index < frame.hotspot_count) try self.act(cue, frame.hotspots[h.hotspot_index].entity);
            },
            .examine_hotspot => |i| if (i < frame.hotspot_count) try self.act("LooksAt", frame.hotspots[i].entity),
            // LOOK on a carried item: the can says whether it is full (the window already sends
            // this, and the browser fires the same cue itself).
            .interact_inventory => |it| if (it.verb == .look_at and it.item_index < frame.inventory_count) {
                try self.act("LooksAt", frame.inventory[it.item_index].entity);
            },
            else => {},
        }
    }

    fn banner(self: Play) []const u8 {
        return self.window.cue_banner_text[0..self.window.cue_banner_len];
    }
};

/// Loads the package into a world staged for play: the window and its tests start here.
const Stage = struct {
    world: bespoke.World,
    spatial: bespoke.SpatialSystem,
    compiled: bespoke.CompiledProgram,
    vm: bespoke.VM,

    fn init(self: *Stage, allocator: std.mem.Allocator) !void {
        self.world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
        errdefer self.world.deinit();
        self.spatial = bespoke.SpatialSystem.init(allocator);
        errdefer self.spatial.deinit();
        var stream: std.Io.Reader = .fixed(PACKAGE);
        self.compiled = try bespoke.load_package(allocator, &stream, &self.world, &self.spatial);
        errdefer self.compiled.deinit();
        try configure(&self.world, &self.spatial, false);
        self.vm = bespoke.VM.init(allocator, &self.world, &self.compiled.chunk);
        errdefer self.vm.deinit();
        self.vm.spatial = &self.spatial;
        try self.vm.transition_to_scene(self.world.lookup_entity(LANE).?);
        try self.vm.load_compiled_rules(&self.compiled);
        try host.initialize_subsystems(&self.world, &self.compiled);
        try host.run_initial_statements(&self.world, &self.vm, &self.compiled);
        // The beginning: Hobb notices the clock (the deck starts it through `start_script`).
        _ = try host.start_routine(&self.world, &self.spatial, &self.vm, &self.compiled, "Dusk", "Hobb", 6);
    }

    fn deinit(self: *Stage) void {
        self.vm.deinit();
        self.compiled.deinit();
        self.spatial.deinit();
        self.world.deinit();
    }
};

/// Native window proof. The ordinary Session supplies walking, doorways, pause, save, and rewind.
pub fn run_interactive(allocator: std.mem.Allocator, io: std.Io, stdout: anytype) !void {
    var stage: Stage = undefined;
    try stage.init(allocator);
    defer stage.deinit();
    program_art = &stage.compiled.art;
    defer program_art = null;
    const nell = stage.world.lookup_entity("Nell").?;

    var window = try bespoke.display.DisplayWindow.init(io, "BeSpoke Engine - The Lamplighter's Round", 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    if (window.is_headless) return run_headless(allocator, stdout);
    try stdout.writeAll("\nThe Lamplighter's Round: click to walk; TALK to Hobb for a taper, USE the oil cask, then USE a lamp. The archway at the lane's end leads to Market Steps.\n");
    try stdout.writeAll("Pause/save/load, single-step, scrub, rewind, debug, and console use the standard engine controls.\n\n");

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    bridge.attach_audio_bridge(window.audio_bridge);
    bridge.set_active_character(nell);
    var session = try host.Session.init(allocator, &stage.world, &stage.spatial, &stage.vm, &stage.compiled, &bridge, &window);
    defer session.deinit();
    session.exits = &EXITS;
    session.player = nell;
    window.set_cue_banner(INTRO, 300);
    const p = Play{ .world = &stage.world, .vm = &stage.vm, .compiled = &stage.compiled, .session = &session, .window = &window, .nell = nell };

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

test "P46-05: clicks in the window act and their replies reach the banner" {
    const allocator = std.testing.allocator;
    var stage: Stage = undefined;
    try stage.init(allocator);
    defer stage.deinit();
    var window = try bespoke.display.DisplayWindow.init_offscreen(std.testing.io, 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    const nell = stage.world.lookup_entity("Nell").?;
    bridge.set_active_character(nell);
    var session = try host.Session.init(allocator, &stage.world, &stage.spatial, &stage.vm, &stage.compiled, &bridge, &window);
    defer session.deinit();
    session.exits = &EXITS;
    session.player = nell;
    const p = Play{ .world = &stage.world, .vm = &stage.vm, .compiled = &stage.compiled, .session = &session, .window = &window, .nell = nell };

    const index = struct {
        fn actor(pl: Play, name: []const u8) usize {
            const f = pl.session.frame();
            for (f.entities[0..f.entity_count], 0..) |e, i| if (std.mem.eql(u8, e.get_name(), name)) return i;
            unreachable;
        }
        fn prop(pl: Play, name: []const u8) usize {
            const f = pl.session.frame();
            for (f.hotspots[0..f.hotspot_count], 0..) |h, i| if (std.mem.eql(u8, h.get_name(), name)) return i;
            unreachable;
        }
    };
    const item = struct {
        fn at(pl: Play, name: []const u8) usize {
            const f = pl.session.frame();
            for (f.inventory[0..f.inventory_count], 0..) |it, i| if (std.mem.eql(u8, it.get_name(), name)) return i;
            unreachable;
        }
    };
    const look_can: r.UserAction = .{ .interact_inventory = .{ .verb = .look_at, .item_index = item.at(p, "OilCan") } };
    // The can is in Nell's tray from the start and says it is empty.
    try p.handle(look_can);
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "My oil can, empty") != null);
    // Hobb's oil is not Nell's to take until he has given her the taper (third hand-play).
    try p.handle(.{ .interact_hotspot = .{ .verb = .use_with, .hotspot_index = index.prop(p, "Oil Cask") } });
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "Ask before you help yourself") != null);
    try std.testing.expect(!stage.world.has_fact(nell, stage.world.lookup_relation("CanFull").?, null));
    try p.handle(.{ .interact_actor = .{ .verb = .talk_to, .actor_index = index.actor(p, "Hobb") } });
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "Here's a taper") != null);
    try p.handle(.{ .examine_hotspot = index.prop(p, "Oil Cask") });
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "Hobb's lamp oil") != null);
    try p.handle(.{ .interact_hotspot = .{ .verb = .use_with, .hotspot_index = index.prop(p, "Oil Cask") } });
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "Filled to the brim") != null);
    try p.handle(.{ .interact_inventory = .{ .verb = .look_at, .item_index = item.at(p, "OilCan") } });
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "full to the brim") != null);
    try p.handle(.{ .interact_hotspot = .{ .verb = .use_with, .hotspot_index = index.prop(p, "Lane Lamp") } });
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "Tallow Lane is lit, and my can is empty") != null);
    try p.handle(.{ .interact_inventory = .{ .verb = .look_at, .item_index = item.at(p, "OilCan") } });
    try std.testing.expect(std.mem.indexOf(u8, p.banner(), "My oil can, empty") != null);
    try std.testing.expect(art.status_of(session.frame()).lane_lamp_lit);

    // Clicks reach what is drawn: the middle of the painted window, Hobb's chest, and the lit
    // lamp's head, none of them at a spot or a mark.
    window.set_art(&stage.compiled.art);
    const f = session.frame();
    const hotspots = f.hotspots[0..f.hotspot_count];
    const people = f.entities[0..f.entity_count];
    const at = bespoke.display.renderer;
    try std.testing.expectEqual(@as(?usize, index.prop(p, "Shop Window")), at.hit_test_hotspot(57 * 4, 77 * 4, hotspots, 1280, 720, window.art));
    try std.testing.expectEqual(@as(?usize, index.prop(p, "Shop Door")), at.hit_test_hotspot(108 * 4, 70 * 4, hotspots, 1280, 720, window.art));
    try std.testing.expectEqual(@as(?usize, index.prop(p, "Lane Lamp")), at.hit_test_hotspot(201 * 4, 78 * 4, hotspots, 1280, 720, window.art));
    const hobb_feet = at.get_entity_screen_pos(index.actor(p, "Hobb"), people, 1280, 720);
    try std.testing.expectEqual(@as(?usize, index.actor(p, "Hobb")), at.hit_test_actor(hobb_feet.x, hobb_feet.y - 60, people, 1280, 720, window.art));
}

test "P46-05: the package carries the round's imported art" {
    var world = try bespoke.World.init(std.testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var stream: std.Io.Reader = .fixed(PACKAGE);
    var compiled = try bespoke.load_package(std.testing.allocator, &stream, &world, &spatial);
    defer compiled.deinit();
    const a = compiled.art;
    try std.testing.expectEqual(@as(usize, 7), a.images.len);
    try std.testing.expectEqual(@as(usize, 2), a.backdrops.len);
    try std.testing.expectEqual(@as(usize, 4), a.sprites.len);
    try std.testing.expectEqual(@as(u32, 3), a.find("LampSheet").?.frame_count());
    try std.testing.expect(a.backdrop_for(world.lookup_entity(LANE).?) != null);
    try configure(&world, &spatial, false);
}
