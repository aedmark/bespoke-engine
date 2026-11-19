//! Render characterization for the proofs of concept (P32-02a, docs/SEPARATION.md).
//!
//! The transcript goldens (P32-07) pin what each proof does and says, not what its window
//! draws. This test draws every scene of every proof into an offscreen window and compares a
//! hash of the pixels with `proofs/golden/render.txt`, so moving proof art out of the engine
//! (P32-02b) cannot change a pixel unnoticed.
//!
//! Each scene is staged from the proof's own script and, where the host places marks, props,
//! exit marks, or cast starts in Zig, from that proof's own layout function too (P43-01). The
//! cast is then spread over the scene's marks. That is the default state of the scene. Art that
//! depends on puzzle progress (a moved anchor, a tampered flag) is not covered.
//!
//! Every staged frame is drawn again at 1920x1080 in a second window and the band is checked
//! there too (P43-03); only the 1280x720 pixels are hashed. A 640x360 window needs no pass of
//! its own: it draws this same 1280x720 frame and shows it at half size, so its band is the band
//! checked here, moved to rows 252 to 291 (Q-014, and the guard test below).
//!
//! The hashes come from SDL's software rasterizer and are stable for one SDL build. If an SDL
//! upgrade changes every hash at once with no change here, regenerate and say so in review.
//!
//! Regenerate deliberately: `zig build test-proofs -Dupdate-goldens`, then review the diff.
//! On a mismatch, `proofs/golden/render.actual.txt` and one `<scene>.actual.bmp` per changed
//! scene are written beside the golden.
const std = @import("std");
const ListWriter = @import("bespoke").ListWriter;
const bespoke = @import("bespoke");
const options = @import("golden_options");
const art = @import("art.zig");

const spitting_contest = @import("spitting_contest.zig");
const borrowed_beard = @import("borrowed_beard.zig");
const sword_fighting = @import("sword_fighting.zig");
const village = @import("village.zig");
const lamp_point = @import("lamp_point.zig");
const three_tides = @import("three_tides.zig");
const weathercock = @import("weathercock.zig");
const bell_tower = @import("bell_tower.zig");
const grog_puzzle = @import("grog_puzzle.zig");
const grid_puzzle = @import("grid_puzzle.zig");
const observatory_puzzle = @import("observatory_puzzle.zig");

const WIDTH: i32 = 1280;
const HEIGHT: i32 = 720;
/// The second size every staged frame is drawn at and band-checked (P43-03).
const ALT_WIDTH: i32 = 1920;
const ALT_HEIGHT: i32 = 1080;
/// The short size: its window shows the 1280x720 frame scaled to half, because a native 640x360
/// layout cannot fit the band and a proof stage at once (Q-014).
const SHORT_WIDTH: i32 = 640;
const SHORT_HEIGHT: i32 = 360;
const GOLDEN_NAME = "render.txt";
const ACTUAL_NAME = "render.actual.txt";

const scripted = [_]struct { name: []const u8, script: []const u8 }{
    .{ .name = "spitting_contest", .script = spitting_contest.SPITTING_CONTEST_SCRIPT },
    .{ .name = "borrowed_beard", .script = borrowed_beard.BORROWED_BEARD_SCRIPT },
    .{ .name = "sword_fighting", .script = sword_fighting.SWORD_FIGHTING_SCRIPT },
    .{ .name = "village", .script = village.VILLAGE_SCRIPT },
    .{ .name = "lamp_point", .script = lamp_point.LAMP_POINT_SCRIPT },
    .{ .name = "three_tides", .script = three_tides.THREE_TIDES_SCRIPT },
    .{ .name = "weathercock", .script = weathercock.WEATHERCOCK_SCRIPT },
    .{ .name = "bell_tower", .script = bell_tower.BELL_TOWER_SCRIPT },
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
        // A quoted name (D-101) is the name without its quotes, as the compiler reads it.
        var found = SceneCast{ .scene = std.mem.trim(u8, line["scene:".len..], " \""), .cast = "" };
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
    "gap_taped",            "gap_has_fur",         "dog_startled",         "dog_fur_collected",
    "tamsin_disguised",      "berth_taken",            "donkey_tangled",      "donkey_charging",
    "donkey_retreating",     "tamsin_knocked_down",    "anchor_moved",         "tides_tree_felled",
    "tides_port_aged",         "tides_well_charged",   "tides_banner_sewn",       "tides_juno_freed",
    "tides_juno_disguised", "tides_puzzle_solved",     "branch_active",       "branch_collapsed",
    "weathercock_flooded",    "weathercock_note_delivered", "keystone_converged", "keystone_returned",
    "weathercock_solved",    "bell_brazier_lit",       "bell_chain_loosed",    "bell_fork_taken",
    "bell_ringing",           "bell_beacon_lit",        "village_crime_active", "village_warrant_active",
    "village_arrest_made",    "cheese_holder",          "charmed_target",       "countdown",
    "villagers",              "gallery_door_revealed",  "gallery_fire",
};

const Status = struct {
    /// Sets one named piece of status on a copy of a captured frame. Returns false when the
    /// frame has nothing to attach it to (no actor to hold the cheese, say).
    fn apply(frame: *bespoke.RenderFrame, variant: []const u8) bool {
        const st = frame.host_status_mut(art.Status);
        const info = @typeInfo(art.Status).@"struct";
        inline for (info.field_names, info.field_types) |name, field_type| {
            if (field_type == bool and std.mem.eql(u8, name, variant)) {
                @field(st, name) = true;
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
            @memcpy(st.branch_countdown[0..text.len], text);
            st.branch_countdown_len = text.len;
            st.branch_active = true;
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

/// A window the same frames are drawn into at another size, with its own probes, so the band
/// check covers more than the golden's 1280x720 without adding a golden (P43-03).
const AltWindow = struct {
    window: *bespoke.display.DisplayWindow,
    text: bespoke.display.canvas.TextProbe = .{},
    rect: bespoke.display.canvas.RectProbe = .{},
};

/// The one thing under the pointer in a hover pass, with the verb and the item in hand
/// (P43-04). One target is set at a time, so the window highlights exactly what the pass
/// means, as the click handler would.
const HoverState = struct {
    wp: ?bespoke.WaypointId = null,
    hotspot: ?usize = null,
    actor: ?usize = null,
    verb: bespoke.display.renderer.AdventureVerb = .walk,
    item: ?usize = null,
};

/// Clears the panel a pass opened, so the next scene builds the balloon its own frame names
/// instead of keeping this pass's (D-127).
fn reset_dialogue(w: *bespoke.display.DisplayWindow) void {
    w.dismiss_dialogue();
    w.balloon_from_frame = false;
    w.balloon_revision = 0;
}

fn apply_hover(w: *bespoke.display.DisplayWindow, hover: HoverState) void {
    w.hovered_wp = hover.wp;
    w.hovered_hotspot = hover.hotspot;
    w.hovered_actor = hover.actor;
    w.hovered_party_member = null;
    w.active_verb = hover.verb;
    w.selected_inventory_item = hover.item;
}

const Recorder = struct {
    allocator: std.mem.Allocator,
    window: *bespoke.display.DisplayWindow,
    out: std.array_list.Managed(u8),
    /// Every string the last frame drew, for the band check (D-124).
    text: bespoke.display.canvas.TextProbe = .{},
    /// Every rectangle and sprite the last frame drew, for the band check (P43-02).
    rect: bespoke.display.canvas.RectProbe = .{},
    /// When set, each frame is drawn again at this window's size and band-checked there.
    alt: ?*AltWindow = null,
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
        const default_hash = self.window.frame_hash().?;

        // Progress states (P32-03a): the same scene with one piece of proof status set. Only
        // states that change the picture are recorded, so the golden lists what each scene's
        // art reacts to.
        if (self.variants) for (STATUS_VARIANTS) |variant| {
            var frame = bridge.get_frame().*;
            if (!Status.apply(&frame, variant)) continue;
            self.window.render_frame(&frame, true);
            if (self.window.frame_hash().? == default_hash) continue;
            var label_buf: [160]u8 = undefined;
            try self.draw_frame(try std.fmt.bufPrint(&label_buf, "{s} +{s}", .{ label, variant }), &frame);
        };

        // The hovered and talking frames face the band check too, once per scene and after
        // every hash is recorded, so no golden moves (P43-04).
        try self.check_prompts(label, bridge.get_frame());
    }

    /// Records the 16x12 save thumbnail for a scene (P32-03d): its backdrop and actor dots.
    fn thumbnail(self: *Recorder, proof: []const u8, scene: []const u8, world: *const bespoke.World, spatial: *const bespoke.SpatialSystem) !void {
        const thumb = Thumbs.make(world, spatial, scene);
        var lw1 = ListWriter.init(&self.out);
        try lw1.writer.print("thumb/{s}/{s}: {x:0>16}\n", .{ proof, scene, std.hash.Wyhash.hash(0, &thumb) });
    }

    /// D-124: no proof art, room name, sign, or prompt reaches into the message band at its
    /// tallest, four rows over a command bar. The frame is drawn with the log cleared, so a
    /// string found in those rows is proof drawing.
    ///
    /// Art is measured by what the frame drew (P43-02, Q-013): every rectangle, line, circle,
    /// and sprite is recorded with its layer, and the check fails on a prop, mark, or person
    /// that reaches the band. Backdrop scenery (D-124's one exemption), walkways, the window's
    /// chrome, and full-window overlays are other layers and are skipped by kind. `verbose`
    /// names the offender; the canary test calls it quietly, so a passing run prints nothing.
    fn check_band(self: *Recorder, label: []const u8, verbose: bool) !void {
        try self.check_band_at(label, HEIGHT, &self.text, &self.rect, verbose);
    }

    /// The same check at any window height, reading that render's own probes (P43-03).
    fn check_band_at(self: *Recorder, label: []const u8, height: i32, text: *const bespoke.display.canvas.TextProbe, rect: *const bespoke.display.canvas.RectProbe, verbose: bool) !void {
        // The State drawer covers the stage, band included, and is not proof art.
        if (self.window.show_save_drawer) return;
        const renderer = bespoke.display.renderer;
        const band_top = renderer.message_band_top(height);
        const band_bottom = renderer.message_band_bottom(height);

        if (rect.overflowed) {
            if (verbose) std.debug.print(
                "\n'{s}': the frame drew more rectangles than the probe holds ({d})\n",
                .{ label, bespoke.display.canvas.RectProbe.cap },
            );
            return error.RectProbeOverflow;
        }

        // Every offender in the frame is named before the test stops, so one run lists all the
        // art a layout change puts in the band rather than the first one found.
        var art_reaches = false;
        for (rect.draws[0..rect.count]) |d| {
            if (d.kind != .prop and d.kind != .mark and d.kind != .actor) continue;
            if (d.y + d.h > band_top and d.y < band_bottom) {
                if (verbose) std.debug.print(
                    "\n'{s}': art \"{s}\" at ({d}, {d}) size {d}x{d} reaches the message band's rows {d} to {d}\n",
                    .{ label, if (d.get_name().len > 0) d.get_name() else "shape", d.x, d.y, d.w, d.h, band_top, band_bottom },
                );
                art_reaches = true;
            }
        }
        if (art_reaches) return error.ArtInMessageBand;

        for (text.draws[0..text.count]) |d| {
            if (d.y < band_bottom and d.y + d.h > band_top) {
                if (verbose) std.debug.print(
                    "\n'{s}': text \"{s}\" at ({d}, {d}) reaches the message band's rows {d} to {d}\n",
                    .{ label, d.get_text(), d.x, d.y, band_top, band_bottom },
                );
                return error.TextInMessageBand;
            }
        }
    }

    /// Draws the same frame into the alt window, with the log cleared and its own probes lent,
    /// then measures the band there. The primary window and its hash are untouched.
    fn check_alt(self: *Recorder, label: []const u8, frame: *const bespoke.RenderFrame, alt: *AltWindow, verbose: bool) !void {
        alt.window.clear_log();
        alt.text.count = 0;
        alt.rect.count = 0;
        alt.rect.overflowed = false;
        const canvas: ?*bespoke.display.Canvas = if (alt.window.canvas) |*cv| cv else null;
        if (canvas) |cv| {
            cv.text_probe = &alt.text;
            cv.rect_probe = &alt.rect;
            cv.rect_kind = .prop;
            cv.rect_name = "";
        }
        defer {
            if (canvas) |cv| {
                cv.text_probe = null;
                cv.rect_probe = null;
            }
        }
        alt.window.render_frame(frame, true);
        try self.check_band_at(label, alt.window.height, &alt.text, &alt.rect, verbose);
    }

    /// P43-04: a hover prompt is world text, so it obeys the same band rule. The lowest mark,
    /// prop, and person in the frame sit nearest the band and are the ones a layout change
    /// pushes into it; the widest prompt is a person with an item in hand. Each hover is drawn
    /// after the scene's hash is recorded, so no golden moves.
    fn check_prompts(self: *Recorder, label: []const u8, frame: *const bespoke.RenderFrame) !void {
        const renderer = bespoke.display.renderer;
        const width = self.window.width;
        const height = self.window.height;

        var lowest_wp: ?bespoke.WaypointId = null;
        var lowest_wp_row: i32 = std.math.minInt(i32);
        for (frame.waypoints[0..frame.waypoint_count]) |wp| {
            const row = renderer.world_to_screen(wp.x, wp.y, width, height).y;
            if (lowest_wp == null or row > lowest_wp_row) {
                lowest_wp = wp.id;
                lowest_wp_row = row;
            }
        }
        var lowest_prop: ?usize = null;
        var lowest_prop_row: i32 = std.math.minInt(i32);
        for (frame.hotspots[0..frame.hotspot_count], 0..) |hs, idx| {
            const row = renderer.world_to_screen(hs.x, hs.y, width, height).y;
            if (lowest_prop == null or row > lowest_prop_row) {
                lowest_prop = idx;
                lowest_prop_row = row;
            }
        }
        var lowest_person: ?usize = null;
        var lowest_person_row: i32 = std.math.minInt(i32);
        for (frame.entities[0..frame.entity_count], 0..) |e, idx| {
            const row = renderer.world_to_screen(e.x, e.y, width, height).y;
            if (lowest_person == null or row > lowest_person_row) {
                lowest_person = idx;
                lowest_person_row = row;
            }
        }

        if (lowest_wp) |id| try self.check_hover(label, frame, .{ .wp = id, .verb = .walk });
        if (lowest_prop) |idx| try self.check_hover(label, frame, .{ .hotspot = idx, .verb = .look_at });
        if (lowest_person) |idx| {
            // An item in hand reads "[Use X on Y]", the widest prompt a person carries; with
            // empty hands, TALK still names them.
            const carrying = frame.inventory_count > 0;
            try self.check_hover(label, frame, .{
                .actor = idx,
                .verb = if (carrying) .use_with else .talk_to,
                .item = if (carrying) 0 else null,
            });
        }
        try self.check_talking(label, frame);
    }

    fn check_hover(self: *Recorder, label: []const u8, frame: *const bespoke.RenderFrame, hover: HoverState) !void {
        apply_hover(self.window, hover);
        defer apply_hover(self.window, .{});
        self.render_probed(frame);
        try self.check_band(label, true);
        if (self.alt) |alt| {
            apply_hover(alt.window, hover);
            defer apply_hover(alt.window, .{});
            try self.check_alt(label, frame, alt, true);
        }
    }

    /// P43-04: the dialogue panel may cover the band's air, because it is lifted clear of the
    /// log's own rows (D-099) and the player opened it. This pass draws one, fails when the
    /// panel does not reach the band (so the pass cannot go quiet), and band-checks the stage
    /// under it.
    fn check_talking(self: *Recorder, label: []const u8, frame: *const bespoke.RenderFrame) !void {
        var open = frame.*;
        open.dialogue.active = true;
        open.dialogue.revision = 1;
        const speaker = "Harbour Warden";
        @memcpy(open.dialogue.speaker_name[0..speaker.len], speaker);
        open.dialogue.speaker_name_len = speaker.len;
        const prompt = "The tide turns under the pier and the mooring rope is paying out fast. What do you do?";
        @memcpy(open.dialogue.prompt[0..prompt.len], prompt);
        open.dialogue.prompt_len = prompt.len;
        const choices = [_][]const u8{
            "Haul the rope in before the boat drifts",
            "Ask the harbour warden what he saw",
            "Leave it be; the boat is not yours",
        };
        for (choices, 0..) |text, i| {
            @memcpy(open.dialogue.choices[i][0..text.len], text);
            open.dialogue.choice_lens[i] = @intCast(text.len);
        }
        open.dialogue.choice_count = @intCast(choices.len);

        self.render_probed(&open);
        defer {
            reset_dialogue(self.window);
            if (self.alt) |alt| reset_dialogue(alt.window);
        }
        if (self.window.active_balloon == null) return error.NoDialoguePanel;
        const band_top = bespoke.display.renderer.message_band_top(self.window.height);
        const panel = self.window.dialogue_panel_for(&self.window.active_balloon.?);
        // The panel really is over the band's air, or the pass proves nothing.
        try std.testing.expect(panel.rect.y < band_top);
        try self.check_band(label, true);
        if (self.alt) |alt| try self.check_alt(label, &open, alt, true);
    }

    /// Draws `frame` into the primary window with this recorder's probes lent, the log cleared
    /// first, so the band check reads only what the frame drew. These frames carry no messages
    /// anyway, so the hash is unchanged.
    fn render_probed(self: *Recorder, frame: *const bespoke.RenderFrame) void {
        self.window.clear_log();
        self.text.count = 0;
        self.rect.count = 0;
        self.rect.overflowed = false;
        const canvas: ?*bespoke.display.Canvas = if (self.window.canvas) |*cv| cv else null;
        if (canvas) |cv| {
            cv.text_probe = &self.text;
            cv.rect_probe = &self.rect;
            cv.rect_kind = .prop;
            cv.rect_name = "";
        }
        defer {
            if (canvas) |cv| {
                cv.text_probe = null;
                cv.rect_probe = null;
            }
        }
        self.window.render_frame(frame, true);
    }

    fn draw_frame(self: *Recorder, label: []const u8, frame: *const bespoke.RenderFrame) !void {
        self.render_probed(frame);
        try self.check_band(label, true);
        if (self.alt) |alt| try self.check_alt(label, frame, alt, true);
        const hash = self.window.frame_hash() orelse return error.NoOffscreenFrame;
        var lw2 = ListWriter.init(&self.out);
        try lw2.writer.print("{s}: {x:0>16}\n", .{ label, hash });

        const expected = self.dump_against orelse return;
        var hash_buf: [16]u8 = undefined;
        const hash_text = try std.fmt.bufPrint(&hash_buf, "{x:0>16}", .{hash});
        if (hash_of(expected, label)) |want| {
            if (std.mem.eql(u8, want, hash_text)) return;
        }
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.mem.printSentinel(&path_buf, "{s}/{s}.actual.bmp", .{ options.golden_dir, label }, 0);
        // Labels read `<proof>/<scene name>`; flatten them into one file name.
        for (path_buf[options.golden_dir.len + 1 .. path.len]) |*ch| {
            if (ch.* == '/' or ch.* == ' ') ch.* = '_';
        }
        try self.window.save_frame_bmp(path);
    }
};

/// Stages each proof the way its own host does: the marks, props, exit marks, and cast starts
/// its script does not declare. Every proof whose host places any of those in Zig is listed
/// here, through the proof's own layout function, so this test never restates a coordinate
/// (D-124). The Well of Three Tides is absent because its script declares every mark and prop;
/// its host only connects the marks, starts the cast, and registers the era portals.
fn stage_host(name: []const u8, world: *bespoke.World, spatial: *bespoke.SpatialSystem) !void {
    if (std.mem.eql(u8, name, "spitting_contest")) return spitting_contest.stage(world, spatial);
    if (std.mem.eql(u8, name, "borrowed_beard")) return borrowed_beard.stage(world, spatial, false);
    if (std.mem.eql(u8, name, "sword_fighting")) return sword_fighting.place_cast(world, spatial, false);
    if (std.mem.eql(u8, name, "village")) {
        const scene = world.lookup_entity("Living Village") orelse return error.SceneNotCompiled;
        _ = try village.lay_out_settlement(world, spatial, scene);
        return;
    }
    if (std.mem.eql(u8, name, "lamp_point")) {
        _ = try lamp_point.Stage.init(world, spatial, false);
        return;
    }
    if (std.mem.eql(u8, name, "weathercock")) {
        _ = try weathercock.Layout.init(world, spatial);
        return;
    }
    if (std.mem.eql(u8, name, "bell_tower")) {
        _ = try bell_tower.configure(world, spatial);
        return;
    }
    if (std.mem.eql(u8, name, "grog_puzzle")) {
        _ = try grog_puzzle.configure(world, spatial);
        return;
    }
    if (std.mem.eql(u8, name, "grid_puzzle")) {
        _ = try grid_puzzle.configure(world, spatial);
        return;
    }
    if (std.mem.eql(u8, name, "observatory_puzzle")) {
        _ = try observatory_puzzle.configure(world, spatial);
        return;
    }
}

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

    // Each proof's host stages what its script does not: marks placed in Zig, props, exit marks,
    // and cast starts. Without it the frames and the band check would show a scene no player
    // sees (D-124). The cast loop below leaves an actor the host already placed alone.
    try stage_host(name, &world, &spatial);

    // Stage every scene's cast on that scene's marks, one mark apart.
    var lines = std.mem.splitScalar(u8, script, '\n');
    while (next_scene(&lines)) |sc| {
        // Every scene the script declares is drawn; one the compiler did not create is a test
        // failure, not a silently missing golden line.
        const room = world.lookup_entity(sc.scene) orelse return error.SceneNotCompiled;
        var marks = std.array_list.Managed(bespoke.WaypointId).init(allocator);
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
        // Every scene the script declares is drawn; one the compiler did not create is a test
        // failure, not a silently missing golden line.
        const room = world.lookup_entity(sc.scene) orelse return error.SceneNotCompiled;
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

fn record_all(allocator: std.mem.Allocator, window: *bespoke.display.DisplayWindow, dump_against: ?[]const u8, variants: bool) !std.array_list.Managed(u8) {
    // The same frames are drawn and band-checked at 1920x1080 in a second window (P43-03); its
    // pixels are thrown away, so no golden grows.
    var big = try bespoke.display.DisplayWindow.init_offscreen(std.testing.io, ALT_WIDTH, ALT_HEIGHT);
    defer big.deinit();
    big.set_theme(&art.theme);
    var alt = AltWindow{ .window = &big };
    var rec = Recorder{ .allocator = allocator, .window = window, .alt = &alt, .out = std.array_list.Managed(u8).init(allocator), .dump_against = dump_against, .variants = variants };
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
    var dir = try std.Io.Dir.cwd().createDirPathOpen(std.testing.io, options.golden_dir, .{});
    defer dir.close(std.testing.io);

    var window = try bespoke.display.DisplayWindow.init_offscreen(std.testing.io, WIDTH, HEIGHT);
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
        if (std.mem.indexOf(u8, actual.items, line) == null) {
            std.debug.print("\nthe second pass records '{s}', which the first pass did not\n", .{line});
            return error.RenderNotRepeatable;
        }
    }

    if (options.update_goldens) {
        try dir.writeFile(std.testing.io, .{ .sub_path = GOLDEN_NAME, .data = actual.items });
        dir.deleteFile(std.testing.io, ACTUAL_NAME) catch {};
        return;
    }

    const expected = dir.readFileAlloc(std.testing.io, GOLDEN_NAME, allocator, .limited(1 << 20)) catch |err| {
        std.debug.print("render golden {s}/{s} unreadable ({s}); run `zig build test-proofs -Dupdate-goldens`\n", .{ options.golden_dir, GOLDEN_NAME, @errorName(err) });
        return error.RenderGoldenMissing;
    };
    defer allocator.free(expected);

    if (std.mem.eql(u8, expected, actual.items)) {
        dir.deleteFile(std.testing.io, ACTUAL_NAME) catch {};
        return;
    }

    try dir.writeFile(std.testing.io, .{ .sub_path = ACTUAL_NAME, .data = actual.items });
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

test "D-124: the proof band check fails on a string drawn inside the message band" {
    var window = try bespoke.display.DisplayWindow.init_offscreen(std.testing.io, WIDTH, HEIGHT);
    defer window.deinit();
    var rec = Recorder{
        .allocator = std.testing.allocator,
        .window = &window,
        .out = std.array_list.Managed(u8).init(std.testing.allocator),
    };
    defer rec.out.deinit();

    const band_top = bespoke.display.renderer.message_band_top(HEIGHT);
    try std.testing.expectEqual(@as(i32, 504), band_top);
    // A name whose last row stops above the band passes; one four pixels lower fails.
    rec.text.draws[0] = .{ .x = 40, .y = band_top - 14, .w = 60, .h = 14 };
    rec.text.count = 1;
    try rec.check_band("canary", false);
    rec.text.draws[0].y = band_top - 4;
    try std.testing.expectError(error.TextInMessageBand, rec.check_band("canary", false));
    rec.text.count = 0;

    // Prop art, a mark disc, and a person placed low all fail, named by what was drawn.
    rec.rect.record(.prop, "Chalk Line", 40, band_top - 4, 32, 32);
    try std.testing.expectError(error.ArtInMessageBand, rec.check_band("canary", false));
    rec.rect.count = 0;
    rec.rect.record(.mark, "Cottages", 40, band_top - 12, 33, 33);
    try std.testing.expectError(error.ArtInMessageBand, rec.check_band("canary", false));
    rec.rect.count = 0;
    rec.rect.record(.actor, "Innkeeper", 40, band_top - 14, 37, 37);
    try std.testing.expectError(error.ArtInMessageBand, rec.check_band("canary", false));
    rec.rect.count = 0;

    // Backdrop scenery, walkways, and window chrome may reach the band: D-124 keeps the
    // backdrop out of scope, and the log and bars are the window's own furniture.
    rec.rect.record(.backdrop, "roof", 40, band_top - 4, 600, 200);
    rec.rect.record(.walkway, "path", 0, band_top, WIDTH, 78);
    rec.rect.record(.chrome, "log", 0, band_top, WIDTH, 78);
    rec.rect.record(.overlay, "modal", 0, band_top, WIDTH, 78);
    try rec.check_band("canary", false);
    rec.rect.count = 0;

    // A frame the probe could not hold fails rather than passing on a partial measurement.
    rec.rect.overflowed = true;
    try std.testing.expectError(error.RectProbeOverflow, rec.check_band("canary", false));
    rec.rect.overflowed = false;
}

test "P43-03: a short window shows the whole frame, so its band is the 1280x720 band scaled" {
    const renderer = bespoke.display.renderer;
    // A native 640x360 layout cannot fit the band and a stage: the band's top is row 144 while
    // world y 0 draws at row 200. A short window therefore draws all 720 rows and shows them
    // scaled, so the band lands at rows 252 to 291 of the pixels a viewer sees (Q-014).
    try std.testing.expectEqual(@as(i32, 144), renderer.message_band_top(360));
    const band_top = renderer.message_band_top(HEIGHT);
    const band_bottom = renderer.message_band_bottom(HEIGHT);
    try std.testing.expectEqual(@as(i32, 252), @divTrunc(band_top * SHORT_HEIGHT, HEIGHT));
    try std.testing.expectEqual(@as(i32, 291), @divTrunc(band_bottom * SHORT_HEIGHT, HEIGHT));

    var win = try bespoke.display.DisplayWindow.init_offscreen_scaled(std.testing.io, SHORT_WIDTH, SHORT_HEIGHT, WIDTH, HEIGHT);
    defer win.deinit();
    // Drawing stays at the golden's size, which is why the sweep needs no 640x360 pass: the
    // frame it would measure is the one already checked at 1280x720.
    try std.testing.expectEqual(WIDTH, win.width);
    try std.testing.expectEqual(HEIGHT, win.height);
    try std.testing.expectEqual(SHORT_WIDTH, win.scaled_canvas.?.width);
    try std.testing.expectEqual(SHORT_HEIGHT, win.scaled_canvas.?.height);
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
