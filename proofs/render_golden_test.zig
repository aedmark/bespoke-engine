//! Render characterization for the proofs of concept (P32-02a, docs/SEPARATION.md).
//!
//! The transcript goldens (P32-07) pin what each proof does and says, not what its window
//! draws. This test draws every scene of every proof into an offscreen window and compares a
//! hash of the pixels with `proofs/golden/render.txt`, so moving proof art out of the engine
//! (P32-02b) cannot change a pixel unnoticed.
//!
//! Each scene is staged from the proof's own script: its marks and props as compiled, and its
//! cast spread over the scene's marks. That is the default state of the scene. Art that
//! depends on puzzle progress (a moved plough, a tampered flag) is not covered.
//!
//! The hashes come from SDL's software rasterizer and are stable for one SDL build. If an SDL
//! upgrade changes every hash at once with no change here, regenerate and say so in review.
//!
//! Regenerate deliberately: `zig build test-proofs -Dupdate-goldens`, then review the diff.
//! On a mismatch, `proofs/golden/render.actual.txt` and one `<scene>.actual.bmp` per changed
//! scene are written beside the golden.
const std = @import("std");
const bespoke = @import("bespoke");
const options = @import("golden_options");
const art = @import("art.zig");

const spitting_contest = @import("spitting_contest.zig");
const gk3_moustache = @import("gk3_moustache.zig");
const sword_fighting = @import("sword_fighting.zig");
const village = @import("village.zig");
const goat_puzzle = @import("goat_puzzle.zig");
const dott_puzzle = @import("dott_puzzle.zig");
const darko_puzzle = @import("darko_puzzle.zig");
const loom_puzzle = @import("loom_puzzle.zig");
const grog_puzzle = @import("grog_puzzle.zig");
const grid_puzzle = @import("grid_puzzle.zig");
const observatory_puzzle = @import("observatory_puzzle.zig");

const WIDTH: i32 = 1280;
const HEIGHT: i32 = 720;
const GOLDEN_NAME = "render.txt";
const ACTUAL_NAME = "render.actual.txt";

const scripted = [_]struct { name: []const u8, script: []const u8 }{
    .{ .name = "spitting_contest", .script = spitting_contest.SPITTING_CONTEST_SCRIPT },
    .{ .name = "gk3_moustache", .script = gk3_moustache.GK3_MOUSTACHE_SCRIPT },
    .{ .name = "sword_fighting", .script = sword_fighting.SWORD_FIGHTING_SCRIPT },
    .{ .name = "village", .script = village.VILLAGE_SCRIPT },
    .{ .name = "goat_puzzle", .script = goat_puzzle.GOAT_PUZZLE_SCRIPT },
    .{ .name = "dott_puzzle", .script = dott_puzzle.DOTT_PUZZLE_SCRIPT },
    .{ .name = "darko_puzzle", .script = darko_puzzle.DARKO_PUZZLE_SCRIPT },
    .{ .name = "loom_puzzle", .script = loom_puzzle.BELL_TOWER_SCRIPT },
    .{ .name = "grog_puzzle", .script = grog_puzzle.GROG_PUZZLE_SCRIPT },
    .{ .name = "grid_puzzle", .script = grid_puzzle.GRID_PUZZLE_SCRIPT },
    .{ .name = "observatory_puzzle", .script = observatory_puzzle.OBSERVATORY_SCRIPT },
};

/// A `scene:` block's name and `cast:` line, read from script text. The compiler does not
/// keep the cast list, and the proofs place their actors in Zig, so the test reads it here.
const SceneCast = struct { scene: []const u8, cast: []const u8 };

fn next_scene(lines: *std.mem.SplitIterator(u8, .scalar)) ?SceneCast {
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "scene:")) continue;
        var found = SceneCast{ .scene = std.mem.trim(u8, line["scene:".len..], " "), .cast = "" };
        // The cast line, if any, follows directly; a blank line ends the scene header.
        while (lines.peek()) |peek_raw| {
            const peek = std.mem.trim(u8, peek_raw, " \t\r");
            if (peek.len == 0 or std.mem.startsWith(u8, peek, "scene:")) break;
            _ = lines.next();
            if (std.mem.startsWith(u8, peek, "cast:")) found.cast = std.mem.trim(u8, peek["cast:".len..], " ");
        }
        return found;
    }
    return null;
}

/// Proof status a scene's art may react to, by stable name. P32-03 moves this status out of
/// `RenderFrame`; only `Status.apply` changes with it, never the names.
const STATUS_VARIANTS = [_][]const u8{
    "spit_is_thick",          "pegs_tampered",         "wind_blowing",         "judge_distracted",
    "fence_taped",            "fence_has_hair",         "cat_startled",         "cat_hair_collected",
    "gabriel_disguised",      "bike_rented",            "goat_is_tangled",      "goat_is_charging",
    "goat_is_retreating",     "george_knocked_down",    "plough_moved",         "dott_tree_chopped",
    "dott_wine_aged",         "dott_battery_charged",   "dott_flag_sewn",       "dott_laverne_freed",
    "dott_laverne_disguised", "dott_puzzle_solved",     "tangent_active",       "singularity_collapsed",
    "darko_water_flooded",    "darko_letter_delivered", "darko_vortex_reached", "darko_artifact_returned",
    "darko_puzzle_solved",    "bell_brazier_lit",       "bell_chain_loosed",    "bell_fork_taken",
    "bell_ringing",           "bell_beacon_lit",        "village_crime_active", "village_warrant_active",
    "village_arrest_made",    "cheese_holder",          "charmed_target",       "countdown",
    "villagers",              "gallery_door_revealed",  "gallery_fire",
};

const Status = struct {
    /// Sets one named piece of status on a copy of a captured frame. Returns false when the
    /// frame has nothing to attach it to (no actor to hold the cheese, say).
    fn apply(frame: *bespoke.RenderFrame, variant: []const u8) bool {
        const st = frame.host_status_mut(art.Status);
        inline for (@typeInfo(art.Status).Struct.fields) |field| {
            if (field.type == bool and std.mem.eql(u8, field.name, variant)) {
                @field(st, field.name) = true;
                return true;
            }
        }
        const first = if (frame.entity_count > 0) frame.entities[0].entity else return false;
        if (std.mem.eql(u8, variant, "cheese_holder")) {
            st.cheese_holder = first;
        } else if (std.mem.eql(u8, variant, "charmed_target")) {
            st.charmed_target = first;
        } else if (std.mem.eql(u8, variant, "countdown")) {
            const text = "00:00:12:34";
            @memcpy(st.tangent_countdown[0..text.len], text);
            st.tangent_countdown_len = text.len;
            st.tangent_active = true;
        } else if (std.mem.eql(u8, variant, "gallery_fire")) {
            // Mid-escape: a spent smoking cell, two fires, and water on the door.
            const A = bespoke.grid.Attribute;
            const bit = struct {
                fn of(attribute: A) u8 {
                    return @as(u8, 1) << @intCast(@intFromEnum(attribute));
                }
            }.of;
            st.gallery_cells = .{ 0, 0, bit(.smoke), bit(.burning) | bit(.smoke), bit(.burning), bit(.liquid) };
            st.gallery_door_revealed = true;
        } else if (std.mem.eql(u8, variant, "villagers")) {
            const n = @min(frame.entity_count, 3);
            for (0..n) |i| {
                var d = art.VillagerDrive{
                    .entity = frame.entities[i].entity,
                    .hunger = @intCast(30 + 25 * i),
                    .energy = @intCast(90 - 30 * i),
                    .gold = @intCast(5 * i),
                    .activity = @intCast(i),
                    .knows_rumor = i == 1,
                    .is_witness = i == 2,
                };
                const name = frame.entities[i].get_name();
                const len = @min(name.len, d.name.len);
                @memcpy(d.name[0..len], name[0..len]);
                d.name_len = @intCast(len);
                st.villager_drives[i] = d;
                var e = art.SocialEdge{ .kind = @intCast(i) };
                @memcpy(e.from_name[0..len], name[0..len]);
                e.from_len = @intCast(len);
                const to = frame.entities[(i + 1) % n].get_name();
                const tlen = @min(to.len, e.to_name.len);
                @memcpy(e.to_name[0..tlen], to[0..tlen]);
                e.to_len = @intCast(tlen);
                st.social_edges[i] = e;
            }
            st.villager_drive_count = n;
            st.social_edge_count = n;
        } else return false;
        return true;
    }
};

/// Save thumbnails, through whatever API P32-03d gives them; only this adapter changes.
const Thumbs = struct {
    fn make(world: *const bespoke.World, spatial: *const bespoke.SpatialSystem, scene: []const u8) [bespoke.save.THUMB_SIZE]u8 {
        return bespoke.save.generate_thumbnail(world, spatial, scene, &art.thumbnails);
    }
};

const Recorder = struct {
    allocator: std.mem.Allocator,
    window: *bespoke.display.DisplayWindow,
    out: std.ArrayList(u8),
    /// When set, a scene whose hash is not the one recorded here is also saved as a BMP.
    dump_against: ?[]const u8 = null,
    /// Also draw each scene in its progress states.
    variants: bool = true,

    /// Draws the current frame and appends `<label>: <hash>` to the record.
    fn draw(self: *Recorder, label: []const u8, world: *bespoke.World, spatial: *bespoke.SpatialSystem, vm: *bespoke.VM) !void {
        var bridge = bespoke.DisplayBridge.init();
        bridge.set_status_hook(art.capture_status);
        bridge.capture_frame(world, spatial, vm);
        bridge.swap();
        try self.draw_frame(label, bridge.get_frame());

        // Progress states (P32-03a): the same scene with one piece of proof status set. Only
        // states that change the picture are recorded, so the golden lists what each scene's
        // art reacts to.
        if (!self.variants) return;
        const default_hash = self.window.frame_hash().?;
        for (STATUS_VARIANTS) |variant| {
            var frame = bridge.get_frame().*;
            if (!Status.apply(&frame, variant)) continue;
            self.window.render_frame(&frame, true);
            if (self.window.frame_hash().? == default_hash) continue;
            var label_buf: [160]u8 = undefined;
            try self.draw_frame(try std.fmt.bufPrint(&label_buf, "{s} +{s}", .{ label, variant }), &frame);
        }
    }

    /// Records the 16x12 save thumbnail for a scene (P32-03d): its backdrop and actor dots.
    fn thumbnail(self: *Recorder, proof: []const u8, scene: []const u8, world: *const bespoke.World, spatial: *const bespoke.SpatialSystem) !void {
        const thumb = Thumbs.make(world, spatial, scene);
        try self.out.writer().print("thumb/{s}/{s}: {x:0>16}\n", .{ proof, scene, std.hash.Wyhash.hash(0, &thumb) });
    }

    fn draw_frame(self: *Recorder, label: []const u8, frame: *const bespoke.RenderFrame) !void {
        self.window.render_frame(frame, true);
        const hash = self.window.frame_hash() orelse return error.NoOffscreenFrame;
        try self.out.writer().print("{s}: {x:0>16}\n", .{ label, hash });

        const expected = self.dump_against orelse return;
        var hash_buf: [16]u8 = undefined;
        const hash_text = try std.fmt.bufPrint(&hash_buf, "{x:0>16}", .{hash});
        if (hash_of(expected, label)) |want| {
            if (std.mem.eql(u8, want, hash_text)) return;
        }
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrintZ(&path_buf, "{s}/{s}.actual.bmp", .{ options.golden_dir, label });
        // Labels read `<proof>/<scene name>`; flatten them into one file name.
        for (path_buf[options.golden_dir.len + 1 .. path.len]) |*ch| {
            if (ch.* == '/' or ch.* == ' ') ch.* = '_';
        }
        try self.window.save_frame_bmp(path);
    }
};

fn record_script(rec: *Recorder, name: []const u8, script: []const u8) !void {
    const allocator = rec.allocator;
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, script);
    defer compiled.deinit();
    // Seed grid layouts so a grid scene shows its opening cells. Only grids: seeding other
    // subsystems here would redraw scenes whose goldens predate it.
    for (compiled.grids.items) |declaration| try bespoke.grid.seed(&world, declaration);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    // Stage every scene's cast on that scene's marks, one mark apart.
    var lines = std.mem.splitScalar(u8, script, '\n');
    while (next_scene(&lines)) |sc| {
        const room = world.lookup_entity(sc.scene) orelse continue;
        var marks = std.ArrayList(bespoke.WaypointId).init(allocator);
        defer marks.deinit();
        for (spatial.graph.waypoints.items) |wp| {
            if (wp.room == room) try marks.append(wp.id);
        }
        if (marks.items.len == 0) continue;
        var cast = std.mem.splitScalar(u8, sc.cast, ',');
        var i: usize = 0;
        while (cast.next()) |raw_name| : (i += 1) {
            const actor = world.lookup_entity(std.mem.trim(u8, raw_name, " ")) orelse continue;
            // An actor listed in two scenes is staged in the first.
            if (spatial.agents.contains(actor)) continue;
            try spatial.register_entity(actor, marks.items[i % marks.items.len], 10);
        }
    }

    lines = std.mem.splitScalar(u8, script, '\n');
    while (next_scene(&lines)) |sc| {
        const room = world.lookup_entity(sc.scene) orelse continue;
        try vm.transition_to_scene(room);
        try rec.thumbnail(name, sc.scene, &world, &spatial);
        var label_buf: [128]u8 = undefined;
        try rec.draw(try std.fmt.bufPrint(&label_buf, "{s}/{s}", .{ name, sc.scene }), &world, &spatial, &vm);
    }
}

/// The Tavern Heist builds its stage in Zig, not from scene declarations; this mirrors the
/// rooms, marks, props, and cast placement in `proofs/tavern_heist.zig`.
fn record_tavern(rec: *Recorder) !void {
    const allocator = rec.allocator;
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    const tavern = try world.intern_entity("Tavern");
    const cellar_room = try world.intern_entity("CellarRoom");
    const hearth_wp = try spatial.graph.add_waypoint(tavern, 0, 0, "Hearth");
    const bar_wp = try spatial.graph.add_waypoint(tavern, 20, 0, "Bar");
    const cellar_wp = try spatial.graph.add_waypoint(cellar_room, 40, 0, "Cellar");
    try spatial.graph.connect(hearth_wp, bar_wp, null);
    try spatial.graph.connect(bar_wp, cellar_wp, null);
    try spatial.add_hotspot(try world.intern_entity("Fireplace"), tavern, .{ .x = 0, .y = -6 }, 8, "Fireplace", "A warm stone fireplace crackling with cozy embers.");
    try spatial.add_hotspot(try world.intern_entity("BarCounter"), tavern, .{ .x = 20, .y = -6 }, 8, "Bar Counter", "A sturdy oak counter with empty tankards and spilled ale.");
    try spatial.add_hotspot(try world.intern_entity("WineCask"), cellar_room, .{ .x = 40, .y = -6 }, 8, "Wine Cask", "A massive oak barrel filled with vintage elven wine.");
    try spatial.register_entity(try world.intern_entity("Guard"), hearth_wp, 10);
    try spatial.register_entity(try world.intern_entity("Bard"), bar_wp, 0);
    try spatial.register_entity(try world.intern_entity("Cat"), hearth_wp, 15);

    var chunk = bespoke.BytecodeChunk.init(allocator);
    defer chunk.deinit();
    var vm = bespoke.VM.init(allocator, &world, &chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    vm.current_scene = tavern;
    try rec.thumbnail("tavern_heist", "Tavern", &world, &spatial);
    // A save made with no scene set uses the empty scene name.
    try rec.thumbnail("tavern_heist", "", &world, &spatial);
    try rec.draw("tavern_heist/Tavern", &world, &spatial, &vm);
    vm.current_scene = cellar_room;
    try rec.draw("tavern_heist/CellarRoom", &world, &spatial, &vm);
}

/// The State tab of the drawer (P27-01/P27-02, D-058) over a staged observatory: the opening
/// facts, a timed cascade, and an open dialogue with active and pruned branches.
fn record_inspector(rec: *Recorder) !void {
    const allocator = rec.allocator;
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, observatory_puzzle.OBSERVATORY_SCRIPT);
    defer compiled.deinit();
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(world.lookup_entity("Larkspur Observatory").?);
    try bespoke.host.run_initial_statements(&world, &vm, &compiled);
    try bespoke.host.initialize_subsystems(&world, &compiled);
    const ines = world.lookup_entity("Ines").?;
    const e = struct {
        fn id(w: *bespoke.World, name: []const u8) !u32 {
            return (try w.intern_entity(name)).to_int();
        }
    };
    try world.remember(ines, world.lookup_relation("Carries").?, try e.id(&world, "ExposureSlip"), 0);
    try world.remember(ines, world.lookup_relation("Believes").?, try e.id(&world, "PellInLibrary"), 0);
    try world.remember(ines, world.lookup_relation("Investigated").?, try e.id(&world, "Darkroom"), 0);
    try world.remember(world.lookup_entity("Halloran").?, try world.intern_relation("Watching", .set), ines.to_int(), 40);
    try world.remember(ines, world.lookup_relation("NearShed").?, 0, 1);
    try world.remember(ines, try world.intern_relation("Suspicious", .set), 0, 90);
    _ = world.step_tick(); // NearShed expires this tick and shows grey

    const pell = world.lookup_entity("Pell").?;
    try bespoke.dialogue.set_speaker(&world, ines, pell);
    try bespoke.dialogue.begin(&world, ines, 99);
    try bespoke.dialogue.offer_inspected(&world, ines, try world.intern_entity("Ask about the exposure slip"), 100, 0);
    try bespoke.dialogue.reject(
        &world,
        ines,
        try world.intern_entity("Accuse Pell of breaking the lens"),
        1,
        try world.intern_entity("missing Knows(Ines, BrokenLens)"),
    );
    try bespoke.dialogue.offer_inspected(&world, ines, try world.intern_entity("Leave the matter for now"), 200, 2);
    _ = try bespoke.dialogue.finish(&world, ines, 300);

    var bridge = bespoke.DisplayBridge.init();
    bridge.set_status_hook(art.capture_status);
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();
    rec.window.show_save_drawer = true;
    rec.window.save_menu_mode = .state;
    rec.window.inspector_focus = ines;
    defer {
        rec.window.show_save_drawer = false;
        rec.window.save_menu_mode = .save;
        rec.window.inspector_focus = null;
        rec.window.inspector_filter = .{};
        rec.window.inspector_selected = 0;
        rec.window.inspector_history_len = 0;
    }
    try rec.draw_frame("inspector/Larkspur Observatory", bridge.get_frame());
    // P27-03 (D-059): the Watching filter on Halloran, with Ines remembered as the way back.
    rec.window.inspector_filter = bespoke.display.state_graph.Filter.of_relation("Watching");
    rec.window.inspector_focus = world.lookup_entity("Halloran").?;
    rec.window.inspector_history[0] = ines;
    rec.window.inspector_history_len = 1;
    try rec.draw_frame("inspector-filtered/Larkspur Observatory", bridge.get_frame());
}

fn record_all(allocator: std.mem.Allocator, window: *bespoke.display.DisplayWindow, dump_against: ?[]const u8, variants: bool) !std.ArrayList(u8) {
    var rec = Recorder{ .allocator = allocator, .window = window, .out = std.ArrayList(u8).init(allocator), .dump_against = dump_against, .variants = variants };
    errdefer rec.out.deinit();
    try record_tavern(&rec);
    for (scripted) |p| try record_script(&rec, p.name, p.script);
    try record_inspector(&rec);
    return rec.out;
}

/// Looks up `label` in a record of `<label>: <hash>` lines.
fn hash_of(record: []const u8, label: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, record, '\n');
    while (lines.next()) |line| {
        if (line.len > label.len + 2 and std.mem.startsWith(u8, line, label) and std.mem.eql(u8, line[label.len..][0..2], ": ")) {
            return line[label.len + 2 ..];
        }
    }
    return null;
}

test "P32-02a: every proof scene draws the pixels recorded in its render golden" {
    const allocator = std.testing.allocator;
    var dir = try std.fs.cwd().makeOpenPath(options.golden_dir, .{});
    defer dir.close();

    var window = try bespoke.display.DisplayWindow.init_offscreen(WIDTH, HEIGHT);
    defer window.deinit();
    window.set_theme(&art.theme);

    var actual = try record_all(allocator, &window, null, true);
    defer actual.deinit();

    // Drawing is a pure function of the frame: a second pass over the default states, drawn
    // after every progress state, must give the same hashes as the first.
    var again = try record_all(allocator, &window, null, false);
    defer again.deinit();
    var again_lines = std.mem.splitScalar(u8, again.items, '\n');
    while (again_lines.next()) |line| {
        if (line.len == 0) continue;
        try std.testing.expect(std.mem.indexOf(u8, actual.items, line) != null);
    }

    if (options.update_goldens) {
        try dir.writeFile(.{ .sub_path = GOLDEN_NAME, .data = actual.items });
        dir.deleteFile(ACTUAL_NAME) catch {};
        return;
    }

    const expected = dir.readFileAlloc(allocator, GOLDEN_NAME, 1 << 20) catch |err| {
        std.debug.print("render golden {s}/{s} unreadable ({s}); run `zig build test-proofs -Dupdate-goldens`\n", .{ options.golden_dir, GOLDEN_NAME, @errorName(err) });
        return error.RenderGoldenMissing;
    };
    defer allocator.free(expected);

    if (std.mem.eql(u8, expected, actual.items)) {
        dir.deleteFile(ACTUAL_NAME) catch {};
        return;
    }

    try dir.writeFile(.{ .sub_path = ACTUAL_NAME, .data = actual.items });
    // Third pass: save an image of each scene that changed, to look at.
    var dumped = try record_all(allocator, &window, expected, true);
    dumped.deinit();
    var changed: usize = 0;
    var lines = std.mem.splitScalar(u8, actual.items, '\n');
    while (lines.next()) |line| {
        const sep = std.mem.lastIndexOf(u8, line, ": ") orelse continue;
        const label = line[0..sep];
        const want = hash_of(expected, label);
        if (want != null and std.mem.eql(u8, want.?, line[sep + 2 ..])) continue;
        changed += 1;
        std.debug.print("\nscene '{s}' draws differently: golden {s}, actual {s}\n", .{ label, want orelse "<not recorded>", line[sep + 2 ..] });
    }
    std.debug.print("\n{d} scene(s) differ; record and one .actual.bmp per changed scene written to {s}\n", .{ changed, options.golden_dir });
    return error.RenderGoldenMismatch;
}

test "P32-02a: scene headers are read from script text" {
    const script =
        \\scene: First Room
        \\cast: Ann, Bob
        \\marks: Zeta
        \\
        \\scene: Empty Room
        \\marks: Yonder
        \\
        \\routine Idle(Ann):
        \\  wait 1 ticks
    ;
    var lines = std.mem.splitScalar(u8, script, '\n');
    const first = next_scene(&lines).?;
    try std.testing.expectEqualStrings("First Room", first.scene);
    try std.testing.expectEqualStrings("Ann, Bob", first.cast);
    const second = next_scene(&lines).?;
    try std.testing.expectEqualStrings("Empty Room", second.scene);
    try std.testing.expectEqualStrings("", second.cast);
    try std.testing.expect(next_scene(&lines) == null);

    try std.testing.expectEqualStrings("00ff", hash_of("a/b: 1234\na/bc: 00ff\n", "a/bc").?);
    try std.testing.expect(hash_of("a/b: 1234\n", "a") == null);
}
