//! The Long Gallery, the Phase 44 proof that a host can show a room the player is not in
//! (P44-06, D-138).
//!
//! Audra keeps the long gallery; Corin and Pell are locked in the studio next door, where
//! Corin's agenda walks him across the room to catch Pell. The world steps every room on the
//! tick clock, so the studio plays out while Audra stands still. What was missing was a view:
//! `DisplayBridge.capture_scene` fills a frame from a named room without moving the VM, and this
//! proof draws that frame while `vm.current_scene` stays on the gallery. The transcript checks
//! the studio's contents, the capture's read-only rule, and a rewind replay; the render golden
//! draws the watched frame.
const std = @import("std");
const bespoke = @import("bespoke");
const golden = @import("golden_digest.zig");
const art = @import("art.zig");
const host = bespoke.host;
const ListWriter = bespoke.ListWriter;
const display = bespoke.display;

pub const LONG_GALLERY_SCRIPT =
    \\scene: Long Gallery
    \\cast: Audra
    \\props: VelvetRope
    \\marks: Window, Bench
    \\
    \\scene: Locked Studio
    \\cast: Corin, Pell
    \\props: EaselBoard
    \\marks: Easel, Corner
    \\
    \\relation Hides(who)
    \\relation Found(who)
    \\
    \\remember Hides(Pell)
    \\
    \\agenda FindPell:
    \\  actor Corin
    \\  target Pell
    \\  once
    \\  requires Hides(Pell)
    \\
    \\on cue Intercepts(Corin, Pell, FindPell):
    \\  say Corin: "Caught you at the easel."
    \\  remember Found(Pell)
    \\  forget Hides(Pell)
;

/// The theme's binding for V, which toggles the watched view.
const WATCH_ACTION: u16 = 1;

const Ids = struct {
    gallery: bespoke.EntityId,
    studio: bespoke.EntityId,
    audra: bespoke.EntityId,
    corin: bespoke.EntityId,
    pell: bespoke.EntityId,
    window_wp: u16,
    easel_wp: u16,
    corner_wp: u16,
};

pub fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const find = struct {
        fn wp(sp: *bespoke.SpatialSystem, room: bespoke.EntityId, name: []const u8) !u16 {
            return sp.graph.find_waypoint_in_room(room, name) orelse error.MissingGalleryMark;
        }
    };
    const ids = Ids{
        .gallery = world.lookup_entity("Long Gallery").?,
        .studio = world.lookup_entity("Locked Studio").?,
        .audra = world.lookup_entity("Audra").?,
        .corin = world.lookup_entity("Corin").?,
        .pell = world.lookup_entity("Pell").?,
        .window_wp = 0,
        .easel_wp = 0,
        .corner_wp = 0,
    };
    var staged = ids;
    staged.window_wp = try find.wp(spatial, ids.gallery, "Window");
    staged.easel_wp = try find.wp(spatial, ids.studio, "Easel");
    staged.corner_wp = try find.wp(spatial, ids.studio, "Corner");
    try spatial.graph.connect(staged.easel_wp, staged.corner_wp, null);
    try spatial.add_hotspot(world.lookup_entity("VelvetRope").?, ids.gallery, .{ .x = 4, .y = -5 }, 3, "Velvet Rope", "A rope across the gallery's far end.");
    try spatial.add_hotspot(world.lookup_entity("EaselBoard").?, ids.studio, .{ .x = 12, .y = -5 }, 3, "Easel Board", "A board turned to the wall.");
    try spatial.register_entity(staged.audra, staged.window_wp, 4);
    try spatial.register_entity(staged.corin, staged.easel_wp, 4);
    try spatial.register_entity(staged.pell, staged.corner_wp, 4);
    return staged;
}

fn expect_true(value: bool, err: anyerror) !void {
    if (!value) return err;
}

fn name_of(world: *const bespoke.World, entity: bespoke.EntityId) []const u8 {
    return world.get_entity_name(entity) orelse "?";
}

/// What one run of the studio produced, so the rewind pass can compare two runs.
const Outcome = struct {
    ticks: u64 = 0,
    found_tick: ?u64 = null,
    line: [96]u8 = @splat(0),
    line_len: usize = 0,
    watched: bool = false,

    fn line_text(self: *const Outcome) []const u8 {
        return self.line[0..self.line_len];
    }
};

fn waypoint_name(frame: *const bespoke.RenderFrame, id: u16) []const u8 {
    // By pointer: a copy's `get_name` slice would point at the loop temporary.
    for (frame.waypoints[0..frame.waypoint_count]) |*waypoint| {
        if (waypoint.id == id) return waypoint.get_name();
    }
    return "somewhere";
}

fn frame_entity(frame: *const bespoke.RenderFrame, name: []const u8) bool {
    for (frame.entities[0..frame.entity_count]) |entity| {
        if (std.mem.eql(u8, entity.get_name(), name)) return true;
    }
    return false;
}

fn print_frame(writer: anytype, label: []const u8, frame: *const bespoke.RenderFrame) !void {
    try writer.print("[{s}] {s} at tick {d}\n", .{ label, frame.get_current_scene(), frame.tick });
    for (frame.entities[0..frame.entity_count]) |entity| {
        try writer.print("  {s} at {s}{s}\n", .{
            entity.get_name(),
            waypoint_name(frame, entity.current_wp),
            if (entity.is_moving) ", moving" else "",
        });
    }
}

/// Ticks the gallery until Corin has caught Pell, reporting the watched studio once.
fn play(
    world: *bespoke.World,
    spatial: *bespoke.SpatialSystem,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    ids: Ids,
    writer: anytype,
    watch: *display.DisplayBridge,
    outcome: *Outcome,
) !void {
    const found_rel = world.lookup_relation("Found") orelse return error.NoFoundRelation;
    var speech_buf: [256]u8 = undefined;
    var ticks: usize = 0;
    while (ticks < 24) : (ticks += 1) {
        outcome.ticks += 1;
        _ = try host.tick(vm, compiled);

        if (host.speech_this_tick(world, vm, &speech_buf)) |line| {
            try writer.print("[Speech {d}] {s}\n", .{ world.current_tick, line });
            if (outcome.line_len == 0) {
                const len = @min(line.len, outcome.line.len);
                @memcpy(outcome.line[0..len], line[0..len]);
                outcome.line_len = len;
            }
        }

        // A watched capture reads the studio and leaves the VM on the gallery.
        if (!outcome.watched and spatial.agents.get(ids.corin).?.is_moving) {
            outcome.watched = true;
            try expect_true(vm.current_scene.? == ids.gallery, error.WatchMovedThePlayer);
            watch.capture_scene(world, spatial, vm, ids.studio);
            watch.swap();
            const frame = watch.get_frame();
            try expect_true(std.mem.eql(u8, frame.get_current_scene(), "Locked Studio"), error.WatchedFrameIsNotTheStudio);
            try expect_true(frame_entity(frame, "Corin"), error.WatchedFrameMissesCorin);
            try expect_true(frame_entity(frame, "Pell"), error.WatchedFrameMissesPell);
            try expect_true(!frame_entity(frame, "Audra"), error.WatchedFrameShowsThePlayer);
            try print_frame(writer, "Watching", frame);
            try expect_true(vm.current_scene.? == ids.gallery, error.WatchMovedThePlayer);
        }

        if (world.has_fact(ids.pell, found_rel, 0)) {
            outcome.found_tick = world.current_tick;
            break;
        }
    }
}

fn run_headless_inner(allocator: std.mem.Allocator, writer: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, LONG_GALLERY_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    // The opening is the initializer's. Saving before the scene and the initializer keeps the
    // world a host would branch from, and the restore below stages the same opening again.
    var opening = std.array_list.Managed(u8).init(allocator);
    defer opening.deinit();
    var opening_writer = ListWriter.init(&opening);
    _ = try bespoke.write_save_state(allocator, &opening_writer.writer, &world, &spatial, &vm, .{ .description = "The Long Gallery opening" });

    // First pass: silent, so the replay starts from the saved world alone.
    var first = Outcome{};
    var sink = std.array_list.Managed(u8).init(allocator);
    defer sink.deinit();
    var sink_writer = ListWriter.init(&sink);
    var sink_bridge = display.DisplayBridge.init();
    try vm.transition_to_scene(ids.gallery);
    try host.run_initial_statements(&world, &vm, &compiled);
    try play(&world, &spatial, &vm, &compiled, ids, &sink_writer.writer, &sink_bridge, &first);
    try expect_true(first.found_tick != null and first.watched, error.StudioNeverPlayedOut);

    var restore_stream: std.Io.Reader = .fixed(opening.items);
    _ = try bespoke.read_save_state(allocator, &restore_stream, &world, &spatial, &vm);
    try expect_true(vm.current_scene == null, error.RewindKeptTheScene);
    try vm.transition_to_scene(ids.gallery);

    try writer.writeAll("===================================================================\n");
    try writer.writeAll("       BeSpoke Engine: The Long Gallery (A Room You Are Not In)\n");
    try writer.writeAll("===================================================================\n\n");
    try writer.writeAll("[Opening] Audra keeps the gallery. The studio door is locked from the far side.\n");

    var watch = display.DisplayBridge.init();
    var second = Outcome{};
    try host.run_initial_statements(&world, &vm, &compiled);
    try play(&world, &spatial, &vm, &compiled, ids, writer, &watch, &second);
    try expect_true(second.found_tick != null, error.StudioNeverPlayedOut);

    // The same opening replays to the same speech, the same catch, and the same tick.
    try expect_true(first.found_tick.? == second.found_tick.?, error.ReplayDiverged);
    try expect_true(std.mem.eql(u8, first.line_text(), second.line_text()), error.ReplayDiverged);

    // The gallery frame still holds only Audra, and the player never left it.
    var gallery_view = display.DisplayBridge.init();
    gallery_view.capture_scene(&world, &spatial, &vm, ids.gallery);
    gallery_view.swap();
    const gallery_frame = gallery_view.get_frame();
    try expect_true(frame_entity(gallery_frame, "Audra"), error.GalleryFrameMissesThePlayer);
    try expect_true(!frame_entity(gallery_frame, "Corin"), error.GalleryFrameShowsTheStudio);
    try expect_true(vm.current_scene.? == ids.gallery, error.WatchMovedThePlayer);

    try writer.print("\n[Caught] Pell at tick {d}: {s}\n", .{ second.found_tick.?, second.line_text() });
    try writer.writeAll("[Rewind] The same opening replays to the same line and the same tick.\n");
    try writer.writeAll("\n===================================================================\n");
    try writer.writeAll("  VERIFICATION COMPLETE: one room watched, another lived in.\n");
    try writer.writeAll("===================================================================\n\n");
    try golden.final_facts(allocator, writer, &world);
}

pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try run_headless_inner(allocator, writer);
}

pub fn run_interactive(allocator: std.mem.Allocator, io: std.Io, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, LONG_GALLERY_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.gallery);
    try host.run_initial_statements(&world, &vm, &compiled);

    var window = try display.DisplayWindow.init(io, "BeSpoke Engine - The Long Gallery", 1280, 720);
    defer window.deinit();
    var theme = art.theme;
    theme.keys = &.{.{ .key = display.renderer.key('v'), .action = WATCH_ACTION }};
    window.set_theme(&theme);
    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
    try stdout.print("The Long Gallery Controls:\n", .{});
    try stdout.print("   - [V]:                   Watch the locked studio, or return to the gallery\n", .{});
    try stdout.print("   - [Space] / [N]:         Pause / single-step the clock\n", .{});
    try stdout.print("   - [R] / [< >]:           Rewind / scrub the timeline\n", .{});
    try stdout.print("   - [Esc]:                 Exit\n\n", .{});

    var bridge = display.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    bridge.attach_audio_bridge(window.audio_bridge);
    bridge.set_active_character(ids.audra);
    var session = try host.Session.init(allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();

    var watch = display.DisplayBridge.init();
    watch.set_status_hook(art.capture_status);
    var watching = false;
    window.set_cue_banner("Audra keeps the gallery. Press V to look into the locked studio.", 200);

    while (true) {
        const action = window.poll_events(if (watching) watch.get_frame() else session.frame());
        if (action == .quit) break;

        switch (action) {
            .custom => |id| if (id == WATCH_ACTION) {
                watching = !watching;
                if (watching) {
                    watch.capture_scene(&world, &spatial, &vm, ids.studio);
                    watch.swap();
                }
                window.set_cue_banner(if (watching) "Watching the locked studio." else "Back in the gallery.", 120);
            },
            else => {},
        }

        // While watching, the only live controls are the toggle and the window's own quit.
        if (!watching) _ = try session.handle_common(action);

        if (session.tick_due()) {
            _ = try session.advance();
            if (watching) {
                watch.capture_scene(&world, &spatial, &vm, ids.studio);
                watch.swap();
            }
            session.refresh();
        }

        if (watching) {
            window.render_frame(watch.get_frame(), false);
        } else {
            session.render();
        }
        display.renderer.c.SDL_Delay(16);
    }
}

test "P44-06: the studio plays out while the player stays in the gallery" {
    var null_buf: [64]u8 = undefined;
    var null_sink: std.Io.Writer.Discarding = .init(&null_buf);
    try run_headless(std.testing.allocator, &null_sink.writer);
}
