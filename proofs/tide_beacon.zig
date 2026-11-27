//! The Tide Beacon (P49-01, D-190): four simultaneous palette colour cycles on one static
//! 320x180 PNG backdrop and an inline Keeper sprite.
//!
//! Waterfall foam, ocean surf, brazier embers, and stars all animate on the 60 Hz display clock
//! without touching simulation state, so pausing ticks ([Space]), scrubbing, or rewinding keeps
//! world facts deterministic.
const std = @import("std");
const bespoke = @import("bespoke");
const golden = @import("golden_digest.zig");
const host = bespoke.host;
const r = bespoke.display.renderer;

/// The compiled package: script, palette, 4 colour cycles, backdrop PNG, and Keeper sprite.
pub const PACKAGE = @embedFile("tide_beacon_bspk");
/// The script as written, for tools that read scene headers from text (the render golden).
pub const SCRIPT = @embedFile("art/tide_beacon/tide_beacon.bespoke");

pub const SCENE = "Moonlit Cove";

const MARKS = [_]struct { mark: []const u8, x: i32 }{
    .{ .mark = "Pier", .x = -6 },
    .{ .mark = "Ledge", .x = 34 },
};
const ROW: i32 = 4;

const PROPS = [_]struct { entity: []const u8, name: []const u8, x: i32, text: []const u8 }{
    .{ .entity = "Brazier", .name = "Brazier", .x = 4, .text = "An iron signal brazier on the pier." },
    .{ .entity = "TidePool", .name = "Tide Pool", .x = 20, .text = "A moonlit tide pool between the pier and the cliff." },
    .{ .entity = "Waterfall", .name = "Waterfall", .x = 42, .text = "Cold cliffwater pouring down the basalt rock." },
};

/// Places the pier and rocky ledge, props, and Keeper in Moonlit Cove.
pub fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem, registered: bool) !void {
    const scene = world.lookup_entity(SCENE) orelse return error.SceneMissing;
    spatial.graph.edges.clearRetainingCapacity();
    var prev: ?bespoke.WaypointId = null;
    for (MARKS) |m| {
        const wp = spatial.graph.find_waypoint_in_room(scene, m.mark) orelse return error.MarkMissing;
        host.place_waypoint(spatial, wp, m.x, ROW);
        if (prev) |p| try spatial.graph.connect(p, wp, null);
        prev = wp;
    }
    spatial.clear_hotspots();
    for (PROPS) |p| {
        const id = world.lookup_entity(p.entity) orelse return error.PropMissing;
        try spatial.add_hotspot(id, scene, .{ .x = p.x, .y = ROW }, 6, p.name, p.text);
    }
    const keeper = world.lookup_entity("CoveKeeper") orelse return error.CastMissing;
    const pier = spatial.graph.find_waypoint_in_room(scene, "Pier") orelse return error.MarkMissing;
    if (registered) {
        _ = try spatial.transition_actor(keeper, scene, pier);
    } else try spatial.register_entity(keeper, pier, 6);
}

fn footer(frame: *const bespoke.RenderFrame) ?r.FooterHint {
    _ = frame;
    return .{ .text = "LOOK at Waterfall, Tide Pool, or Brazier | USE Brazier to stoke | [Space] pauses ticks while cycles animate" };
}

/// Leaves soundtrack null so the script's own `score Cove:` plays.
pub const theme = r.Theme{ .footer = footer };

pub const INTRO = "Moonlit Cove: four palette colour cycles animate one static 320x180 backdrop at 60 Hz. LOOK at the waterfall, tide pool, or brazier, USE the brazier to stoke it, or press [Space] to pause ticks while the cycles keep moving.";

const Stage = struct {
    world: bespoke.World,
    spatial: bespoke.SpatialSystem,
    compiled: bespoke.CompiledProgram,
    vm: bespoke.VM,
    keeper: bespoke.EntityId,

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
        self.keeper = self.world.lookup_entity("CoveKeeper").?;
        try self.vm.transition_to_scene(self.world.lookup_entity(SCENE).?);
        try self.vm.load_compiled_rules(&self.compiled);
        try host.initialize_subsystems(&self.world, &self.compiled);
        try host.run_initial_statements(&self.world, &self.vm, &self.compiled);
        _ = try host.start_routine(&self.world, &self.spatial, &self.vm, &self.compiled, "Watch", "CoveKeeper", 6);
    }

    fn deinit(self: *Stage) void {
        self.vm.deinit();
        self.compiled.deinit();
        self.spatial.deinit();
        self.world.deinit();
    }

    fn tick(self: *Stage, writer: anytype) !void {
        _ = try host.tick(&self.vm, &self.compiled);
        var buf: [512]u8 = undefined;
        if (host.speech_this_tick(&self.world, &self.vm, &buf)) |line| try writer.print("  {s}\n", .{line});
    }

    fn act(self: *Stage, writer: anytype, cue: []const u8, target: []const u8) !void {
        try writer.print("> {s} {s}\n", .{ cue, target });
        _ = try self.vm.fire_cue(&self.compiled, cue, self.keeper, self.world.lookup_entity(target).?, null);
        try self.tick(writer);
    }

    fn walk(self: *Stage, writer: anytype, mark: []const u8) !void {
        const scene = self.world.lookup_entity(SCENE).?;
        const wp = self.spatial.graph.find_waypoint_in_room(scene, mark) orelse return error.MarkMissing;
        try writer.print("> walk to {s}\n", .{mark});
        _ = try self.spatial.walk_to(self.keeper, wp);
        var guard: usize = 0;
        while (self.spatial.is_moving(self.keeper)) : (guard += 1) {
            if (guard > 60) return error.WalkStalled;
            try self.tick(writer);
        }
    }
};

pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("===================================================================\n");
    try writer.writeAll("            BeSpoke Engine: The Tide Beacon (Colour Cycling)       \n");
    try writer.writeAll("   (4 Palette Cycles * PNG Backdrop * Inline Sprite * 60 Hz Clock) \n");
    try writer.writeAll("===================================================================\n\n");
    var stage: Stage = undefined;
    try stage.init(allocator);
    defer stage.deinit();
    const art_of = stage.compiled.art;
    try writer.print("  (Art: {d} images, {d} backdrop, {d} sprite, {d} colour cycles.)\n\n", .{
        art_of.images.len, art_of.backdrops.len, art_of.sprites.len, art_of.cycles.len,
    });
    try stage.act(writer, "LooksAt", "Waterfall");
    try stage.act(writer, "LooksAt", "TidePool");
    try stage.act(writer, "LooksAt", "Brazier");
    try stage.walk(writer, "Ledge");
    try stage.walk(writer, "Pier");
    try stage.act(writer, "Uses", "Brazier");
    try stage.act(writer, "LooksAt", "Brazier");
    const brazier = stage.world.lookup_entity("Brazier").?;
    if (!stage.world.has_fact(brazier, stage.world.lookup_relation("Stoked").?, null)) return error.BrazierNotStoked;
    try writer.writeAll("\n");
    try golden.final_facts(allocator, writer, &stage.world);
    try writer.writeAll("\n===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: 4 colour cycles active, brazier stoked.   \n");
    try writer.writeAll("===================================================================\n");
}

fn cue_for(verb: r.AdventureVerb) ?[]const u8 {
    return switch (verb) {
        .look_at => "LooksAt",
        .use_with, .pick_up => "Uses",
        .talk_to, .walk => null,
    };
}

const Play = struct {
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    session: *host.Session,
    window: *bespoke.display.DisplayWindow,
    keeper: bespoke.EntityId,

    fn advance(self: Play) !void {
        _ = try self.session.advance();
        var buf: [512]u8 = undefined;
        if (host.speech_this_tick(self.world, self.vm, &buf)) |line| self.window.set_cue_banner(line, 300);
    }

    fn act(self: Play, cue: []const u8, target: bespoke.EntityId) !void {
        _ = try self.vm.fire_cue(self.compiled, cue, self.keeper, target, null);
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
            else => {},
        }
    }
};

pub fn run_interactive(allocator: std.mem.Allocator, io: std.Io, stdout: anytype) !void {
    var stage: Stage = undefined;
    try stage.init(allocator);
    defer stage.deinit();

    var window = try bespoke.display.DisplayWindow.init(io, "BeSpoke Engine - The Tide Beacon", 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    if (window.is_headless) return run_headless(allocator, stdout);
    try stdout.writeAll("\nThe Tide Beacon: four palette colour cycles run at 60 Hz. LOOK at Waterfall, Tide Pool, or Brazier; USE Brazier to stoke it.\n");
    try stdout.writeAll("Pause/save/load, single-step, scrub, rewind, debug, and console use the standard engine controls.\n\n");

    var bridge = bespoke.DisplayBridge.init();
    bridge.attach_audio_bridge(window.audio_bridge);
    bridge.set_active_character(stage.keeper);
    var session = try host.Session.init(allocator, &stage.world, &stage.spatial, &stage.vm, &stage.compiled, &bridge, &window);
    defer session.deinit();
    session.player = stage.keeper;
    window.set_cue_banner(INTRO, 300);
    const p = Play{ .world = &stage.world, .vm = &stage.vm, .compiled = &stage.compiled, .session = &session, .window = &window, .keeper = stage.keeper };

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

test "P49-01: The Tide Beacon package carries 4 colour cycles and animates pixels on the display clock" {
    const allocator = std.testing.allocator;
    var stage: Stage = undefined;
    try stage.init(allocator);
    defer stage.deinit();
    const a = stage.compiled.art;
    try std.testing.expectEqual(@as(usize, 2), a.images.len);
    try std.testing.expectEqual(@as(usize, 1), a.backdrops.len);
    try std.testing.expectEqual(@as(usize, 1), a.sprites.len);
    try std.testing.expectEqual(@as(usize, 4), a.cycles.len);

    var window = try bespoke.display.DisplayWindow.init_offscreen(std.testing.io, 1280, 720);
    defer window.deinit();
    window.set_theme(&theme);
    var bridge = bespoke.DisplayBridge.init();
    bridge.set_active_character(stage.keeper);
    var session = try host.Session.init(allocator, &stage.world, &stage.spatial, &stage.vm, &stage.compiled, &bridge, &window);
    defer session.deinit();
    session.player = stage.keeper;
    const p = Play{ .world = &stage.world, .vm = &stage.vm, .compiled = &stage.compiled, .session = &session, .window = &window, .keeper = stage.keeper };

    const facts_before = stage.world.fact_count();
    window.animation_clock = 0;
    window.render_frame(session.frame(), true);
    const h0 = window.frame_hash().?;
    window.animation_clock = 12;
    window.render_frame(session.frame(), true);
    const h12 = window.frame_hash().?;
    try std.testing.expect(h0 != h12);
    try std.testing.expectEqual(facts_before, stage.world.fact_count());

    const brazier_idx = for (session.frame().hotspots[0..session.frame().hotspot_count], 0..) |hs, i| {
        if (std.mem.eql(u8, hs.get_name(), "Brazier")) break i;
    } else unreachable;
    try p.handle(.{ .interact_hotspot = .{ .verb = .use_with, .hotspot_index = brazier_idx } });
    const brazier = stage.world.lookup_entity("Brazier").?;
    try std.testing.expect(stage.world.has_fact(brazier, stage.world.lookup_relation("Stoked").?, null));
    try std.testing.expect(std.mem.indexOf(u8, window.cue_banner_text[0..window.cue_banner_len], "lantern oil") != null);
}
