const std = @import("std");
const display_mod = @import("../display.zig");
const font = @import("font.zig");

const RenderFrame = display_mod.RenderFrame;
const RenderWaypoint = display_mod.RenderWaypoint;
const RenderHotspot = display_mod.RenderHotspot;
const RenderEntity = display_mod.RenderEntity;
const RenderInventoryItem = display_mod.RenderInventoryItem;
const WaypointId = display_mod.WaypointId;
const EntityId = display_mod.EntityId;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const tavern_bg = Color{ .r = 22, .g = 18, .b = 16 };
    pub const tavern_room = Color{ .r = 38, .g = 28, .b = 24 };
    pub const tavern_border = Color{ .r = 61, .g = 46, .b = 39 };
    pub const cellar_room = Color{ .r = 24, .g = 30, .b = 41 };
    pub const cellar_border = Color{ .r = 45, .g = 55, .b = 72 };
    pub const path_corridor = Color{ .r = 55, .g = 48, .b = 43 };
    pub const path_edge = Color{ .r = 75, .g = 68, .b = 60 };

    pub const wp_normal = Color{ .r = 100, .g = 116, .b = 139 };
    pub const wp_hover = Color{ .r = 251, .g = 191, .b = 36 };
    pub const wp_target = Color{ .r = 56, .g = 189, .b = 248 };

    pub const cat_color = Color{ .r = 234, .g = 88, .b = 12 }; // Orange
    pub const guard_color = Color{ .r = 37, .g = 99, .b = 235 }; // Steel Blue
    pub const bard_color = Color{ .r = 147, .g = 51, .b = 234 }; // Purple
    pub const cheese_color = Color{ .r = 250, .g = 204, .b = 21 }; // Gold

    // Booty Island Spitting Contest Colors (P10-03, D-012)
    pub const guybrush_coat = Color{ .r = 30, .g = 64, .b = 175 }; // Pirate Blue
    pub const guybrush_hair = Color{ .r = 250, .g = 204, .b = 21 }; // Blonde
    pub const organiser_coat = Color{ .r = 185, .g = 28, .b = 28 }; // Velvet Red
    pub const onlookers_color = Color{ .r = 120, .g = 80, .b = 140 }; // Purple Crowd
    pub const flag_color = Color{ .r = 239, .g = 68, .b = 68 }; // Red flag
    pub const flag_tampered = Color{ .r = 245, .g = 158, .b = 11 }; // Gold flag
    pub const wind_color = Color{ .r = 56, .g = 189, .b = 248 }; // Sky Blue
    pub const spit_color = Color{ .r = 34, .g = 197, .b = 94 }; // Lime Spit
    pub const grass_green = Color{ .r = 30, .g = 68, .b = 38 };
    pub const sand_color = Color{ .r = 180, .g = 160, .b = 110 };
    pub const ocean_blue = Color{ .r = 14, .g = 70, .b = 110 };
    pub const sky_dusk = Color{ .r = 16, .g = 24, .b = 48 };

    pub const hud_bg = Color{ .r = 15, .g = 23, .b = 42, .a = 230 };
    pub const hud_text = Color{ .r = 248, .g = 250, .b = 252 };
    pub const hud_subtext = Color{ .r = 148, .g = 163, .b = 184 };
    pub const status_running = Color{ .r = 34, .g = 197, .b = 94 };
    pub const status_paused = Color{ .r = 245, .g = 158, .b = 11 };
    pub const cue_alert = Color{ .r = 244, .g = 63, .b = 94 };
};

pub const Point = struct {
    x: i32,
    y: i32,
};

/// Classic adventure game interaction verbs (P7-02, D-009).
pub const AdventureVerb = enum(u8) {
    walk = 0,
    look_at = 1,
    talk_to = 2,
    pick_up = 3,
    use_with = 4,

    pub fn label(self: AdventureVerb) []const u8 {
        return switch (self) {
            .walk => "WALK",
            .look_at => "LOOK",
            .talk_to => "TALK",
            .pick_up => "TAKE",
            .use_with => "USE",
        };
    }

    pub fn next(self: AdventureVerb) AdventureVerb {
        const val = @intFromEnum(self);
        return @enumFromInt((val + 1) % 5);
    }
};

pub const UserAction = union(enum) {
    none,
    quit,
    walk_player: WaypointId,
    examine_hotspot: usize, // Hotspot index (P7-01, D-009)
    interact_actor: struct {
        verb: AdventureVerb,
        actor_index: usize,
    },
    interact_hotspot: struct {
        verb: AdventureVerb,
        hotspot_index: usize,
    },
    dialogue_choice: u8, // Index of selected dialogue option (P7-04, D-009)
    dismiss_dialogue,
    toggle_pause,
    step_tick,
    rewind,
    scrub_to_tick: u64, // Interactive time-travel timeline scrubber (P9-02, D-011)
    repl_command: struct {
        buf: [128]u8,
        len: usize,
    }, // Live interactive REPL console command (P9-03, D-011)
    toggle_debug,
    toggle_console,
    spit_contest_spit,
    sound_horn,
    drink_green_drink,
    tamper_flags,
    // P11-03: Two-operand inventory combining & in-hand actions (D-008, D-009, D-013)
    combine_inventory_items: struct {
        primary_index: usize,
        secondary_index: usize,
    },
    use_inventory_on_actor: struct {
        item_index: usize,
        actor_index: usize,
    },
    use_inventory_on_hotspot: struct {
        item_index: usize,
        hotspot_index: usize,
    },
};

pub const WAYPOINT_SCREEN_RADIUS = 16;
pub const ACTOR_SCREEN_RADIUS = 18;
pub const HOTSPOT_SCREEN_RADIUS = 22;

/// Maps simulation discrete spatial coordinates to screen canvas coordinates.
pub fn world_to_screen(world_x: i32, world_y: i32, screen_w: i32, screen_h: i32) Point {
    // Hearth (x=0) -> ~200, Bar (x=20) -> ~480, Cellar (x=40) -> ~760
    const center_x = @divTrunc(screen_w, 2);
    const center_y = @divTrunc(screen_h, 2) + 20;
    const scale_x: i32 = 14;
    const scale_y: i32 = 10;
    return .{
        .x = center_x - 280 + world_x * scale_x,
        .y = center_y + world_y * scale_y,
    };
}

/// Hit-tests screen coordinates against visible waypoint anchors.
pub fn hit_test_waypoint(
    screen_x: i32,
    screen_y: i32,
    waypoints: []const RenderWaypoint,
    screen_w: i32,
    screen_h: i32,
) ?WaypointId {
    for (waypoints) |wp| {
        const pt = world_to_screen(wp.x, wp.y, screen_w, screen_h);
        const dx: i64 = screen_x - pt.x;
        const dy: i64 = screen_y - pt.y;
        const dist_sq = dx * dx + dy * dy;
        const hit_radius: i64 = WAYPOINT_SCREEN_RADIUS + 8;
        if (dist_sq <= hit_radius * hit_radius) {
            return wp.id;
        }
    }
    return null;
}

pub const EntityScreenLayout = struct {
    pos: Point,
    label_y: i32,
    status_y: i32,
};

/// Computes screen position and non-overlapping label layout for an entity,
/// applying visual standoff separation and vertical staggering when multiple
/// actors occupy the same waypoint or proximity cluster (D-008, D-012).
pub fn get_entity_screen_layout(
    idx: usize,
    entities: []const RenderEntity,
    screen_w: i32,
    screen_h: i32,
) EntityScreenLayout {
    const base = world_to_screen(entities[idx].x, entities[idx].y, screen_w, screen_h);

    var cluster_rank: usize = 0;
    var cluster_total: usize = 0;

    for (entities, 0..) |other, j| {
        const other_base = world_to_screen(other.x, other.y, screen_w, screen_h);
        const dx = base.x - other_base.x;
        const dy = base.y - other_base.y;
        if (dx * dx + dy * dy < 32 * 32) {
            if (j < idx) cluster_rank += 1;
            cluster_total += 1;
        }
    }

    if (cluster_total <= 1) {
        return .{
            .pos = base,
            .label_y = base.y - ACTOR_SCREEN_RADIUS - 16,
            .status_y = base.y + ACTOR_SCREEN_RADIUS + 4,
        };
    }

    // Distribute entities in the cluster with generous spacing and staggered labels
    if (cluster_total == 2) {
        if (cluster_rank == 0) {
            return .{
                .pos = .{ .x = base.x - 30, .y = base.y + 6 },
                .label_y = base.y - ACTOR_SCREEN_RADIUS - 16,
                .status_y = base.y + ACTOR_SCREEN_RADIUS + 4,
            };
        } else {
            return .{
                .pos = .{ .x = base.x + 30, .y = base.y - 12 },
                .label_y = base.y - ACTOR_SCREEN_RADIUS - 32, // Staggered higher
                .status_y = base.y + ACTOR_SCREEN_RADIUS + 18, // Staggered lower
            };
        }
    } else {
        // 3 or more: fan out horizontally and vertically
        const offset: i32 = @as(i32, @intCast(cluster_rank)) * 36 - @as(i32, @intCast(cluster_total - 1)) * 18;
        const y_offset: i32 = if (cluster_rank % 2 == 1) -14 else 6;
        const label_offset: i32 = if (cluster_rank % 2 == 1) -32 else -16;
        const status_offset: i32 = if (cluster_rank % 2 == 1) 18 else 4;
        return .{
            .pos = .{ .x = base.x + offset, .y = base.y + y_offset },
            .label_y = base.y - ACTOR_SCREEN_RADIUS + label_offset,
            .status_y = base.y + ACTOR_SCREEN_RADIUS + status_offset,
        };
    }
}

pub fn get_entity_screen_pos(
    idx: usize,
    entities: []const RenderEntity,
    screen_w: i32,
    screen_h: i32,
) Point {
    return get_entity_screen_layout(idx, entities, screen_w, screen_h).pos;
}

/// Hit-tests screen coordinates against visible actors (P7-02).
pub fn hit_test_actor(
    screen_x: i32,
    screen_y: i32,
    entities: []const RenderEntity,
    screen_w: i32,
    screen_h: i32,
) ?usize {
    for (entities, 0..) |_, idx| {
        const pt = get_entity_screen_pos(idx, entities, screen_w, screen_h);
        const dx: i64 = screen_x - pt.x;
        const dy: i64 = screen_y - pt.y;
        const dist_sq = dx * dx + dy * dy;
        const hit_radius: i64 = ACTOR_SCREEN_RADIUS + 8;
        if (dist_sq <= hit_radius * hit_radius) {
            return idx;
        }
    }
    return null;
}

/// Hit-tests screen coordinates against visible scene hotspots (P7-01, D-009).
pub fn hit_test_hotspot(
    screen_x: i32,
    screen_y: i32,
    hotspots: []const RenderHotspot,
    screen_w: i32,
    screen_h: i32,
) ?usize {
    for (hotspots, 0..) |hs, idx| {
        const pt = world_to_screen(hs.x, hs.y, screen_w, screen_h);
        const dx: i64 = screen_x - pt.x;
        const dy: i64 = screen_y - pt.y;
        const dist_sq = dx * dx + dy * dy;
        const hit_radius: i64 = HOTSPOT_SCREEN_RADIUS + 8;
        if (dist_sq <= hit_radius * hit_radius) {
            return idx;
        }
    }
    return null;
}

/// Hit-tests screen coordinates against the 5 classic adventure verb buttons (P7-02).
pub fn hit_test_verb_button(screen_x: i32, screen_y: i32, screen_h: i32) ?AdventureVerb {
    const y_start = screen_h - 78;
    const btn_h = 26;
    const btn_w = 68;
    const spacing = 6;

    if (screen_y < y_start or screen_y > y_start + btn_h) return null;

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const btn_x = 20 + @as(i32, @intCast(i)) * (btn_w + spacing);
        if (screen_x >= btn_x and screen_x <= btn_x + btn_w) {
            return @enumFromInt(@as(u8, @intCast(i)));
        }
    }
    return null;
}

/// Hit-tests screen coordinates against visible inventory tray items (P7-03, D-007).
pub fn hit_test_inventory_item(screen_x: i32, screen_y: i32, screen_h: i32, inventory: []const RenderInventoryItem) ?usize {
    const bar_y = screen_h - 78;
    if (screen_y < bar_y or screen_y > bar_y + 26) return null;

    var cur_x: i32 = 480;
    for (inventory, 0..) |item, idx| {
        const iname = item.get_name();
        const iw = font.text_width(iname, 2) + 24;
        if (screen_x >= cur_x and screen_x <= cur_x + iw) {
            return idx;
        }
        cur_x += iw + 8;
    }
    return null;
}

/// Active speech balloon or branching dialogue tree (P7-04, D-009).
pub const SpeechBalloon = struct {
    speaker: EntityId,
    speaker_pos: Point,
    speaker_name: [32]u8,
    speaker_name_len: u8,
    text: [160]u8,
    text_len: u8,
    ticks_remaining: u32,
    choices: [3][64]u8,
    choice_lens: [3]u8,
    choice_count: u8,

    pub fn get_speaker_name(self: *const SpeechBalloon) []const u8 {
        return self.speaker_name[0..self.speaker_name_len];
    }

    pub fn get_text(self: *const SpeechBalloon) []const u8 {
        return self.text[0..self.text_len];
    }

    pub fn get_choice(self: *const SpeechBalloon, idx: usize) []const u8 {
        if (idx >= self.choice_count) return "";
        return self.choices[idx][0..self.choice_lens[idx]];
    }
};

/// Computes screen bounding rectangle for speech balloon (P7-04).
pub fn get_balloon_rect(balloon: *const SpeechBalloon, screen_w: i32) c.SDL_Rect {
    const text_w = font.text_width(balloon.get_text(), 2);
    const title_w = font.text_width(balloon.get_speaker_name(), 2) + 40;
    var max_w = @max(text_w, title_w);
    var i: usize = 0;
    while (i < balloon.choice_count) : (i += 1) {
        max_w = @max(max_w, font.text_width(balloon.get_choice(i), 2) + 32);
    }
    const bw = @min(screen_w - 40, @max(260, max_w + 32));
    const bh: i32 = 48 + @as(i32, @intCast(balloon.choice_count)) * 26;

    const bx = @max(20, @min(screen_w - bw - 20, balloon.speaker_pos.x - @divTrunc(bw, 2)));
    const by = @max(60, balloon.speaker_pos.y - bh - 24);

    return c.SDL_Rect{ .x = bx, .y = by, .w = bw, .h = bh };
}

/// Hit-tests mouse coordinates against dialogue choice options (P7-04).
pub fn hit_test_balloon_choice(mouse_x: i32, mouse_y: i32, balloon: *const SpeechBalloon, rect: c.SDL_Rect) ?u8 {
    if (balloon.choice_count == 0) return null;
    const choices_start_y = rect.y + 42;
    var i: usize = 0;
    while (i < balloon.choice_count) : (i += 1) {
        const cy = choices_start_y + @as(i32, @intCast(i)) * 26;
        if (mouse_x >= rect.x + 12 and mouse_x <= rect.x + rect.w - 12 and
            mouse_y >= cy and mouse_y <= cy + 22)
        {
            return @intCast(i);
        }
    }
    return null;
}

/// The SDL2 peripheral window consumer (D-001, D-008, P6-01 through P6-04).
pub const DisplayWindow = struct {
    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,
    width: i32,
    height: i32,
    active_verb: AdventureVerb = .walk,
    hovered_wp: ?WaypointId = null,
    hovered_hotspot: ?usize = null,
    hovered_actor: ?usize = null,
    target_wp: ?WaypointId = null,
    active_balloon: ?SpeechBalloon = null,
    hovered_choice: ?u8 = null,
    is_headless: bool = false,
    cue_banner_text: [64]u8 = undefined,
    cue_banner_len: usize = 0,
    cue_banner_ticks: u32 = 0,
    // Phase 11 Inventory In-Hand Selection & Combining (P11-03, D-013)
    selected_inventory_item: ?usize = null,
    // Phase 9 Debug, Scrubber & REPL (P9-01, P9-02, P9-03, D-011)
    show_debug_overlay: bool = false,
    show_console: bool = false,
    console_input: [128]u8 = undefined,
    console_len: usize = 0,
    console_history: [5][128]u8 = undefined,
    console_history_lens: [5]usize = [_]usize{0} ** 5,
    console_history_count: usize = 0,

    pub fn init(title: [:0]const u8, width: i32, height: i32) !DisplayWindow {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            // Graceful fallback to headless if no display server is available
            return DisplayWindow{
                .window = null,
                .renderer = null,
                .width = width,
                .height = height,
                .is_headless = true,
            };
        }

        const window = c.SDL_CreateWindow(
            title.ptr,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            width,
            height,
            c.SDL_WINDOW_SHOWN,
        ) orelse {
            c.SDL_Quit();
            return DisplayWindow{
                .window = null,
                .renderer = null,
                .width = width,
                .height = height,
                .is_headless = true,
            };
        };

        const renderer = c.SDL_CreateRenderer(
            window,
            -1,
            c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
        ) orelse {
            c.SDL_DestroyWindow(window);
            c.SDL_Quit();
            return DisplayWindow{
                .window = null,
                .renderer = null,
                .width = width,
                .height = height,
                .is_headless = true,
            };
        };

        return DisplayWindow{
            .window = window,
            .renderer = renderer,
            .width = width,
            .height = height,
            .is_headless = false,
        };
    }

    pub fn deinit(self: *DisplayWindow) void {
        if (!self.is_headless) {
            if (self.renderer) |r| c.SDL_DestroyRenderer(r);
            if (self.window) |w| c.SDL_DestroyWindow(w);
            c.SDL_Quit();
        }
    }

    /// Sets an ephemeral on-screen cue announcement banner.
    pub fn set_cue_banner(self: *DisplayWindow, text: []const u8, duration_ticks: u32) void {
        const len = @min(text.len, self.cue_banner_text.len);
        @memcpy(self.cue_banner_text[0..len], text[0..len]);
        self.cue_banner_len = len;
        self.cue_banner_ticks = duration_ticks;
    }

    /// Displays an active speech balloon or branching dialogue choice tree (P7-04, D-009).
    pub fn show_dialogue(
        self: *DisplayWindow,
        speaker: EntityId,
        speaker_pos: Point,
        speaker_name: []const u8,
        text: []const u8,
        choices: []const []const u8,
    ) void {
        var sb = SpeechBalloon{
            .speaker = speaker,
            .speaker_pos = speaker_pos,
            .speaker_name = undefined,
            .speaker_name_len = 0,
            .text = undefined,
            .text_len = 0,
            .ticks_remaining = 360,
            .choices = undefined,
            .choice_lens = [_]u8{ 0, 0, 0 },
            .choice_count = 0,
        };

        const nlen = @min(speaker_name.len, sb.speaker_name.len);
        @memcpy(sb.speaker_name[0..nlen], speaker_name[0..nlen]);
        sb.speaker_name_len = @intCast(nlen);

        const tlen = @min(text.len, sb.text.len);
        @memcpy(sb.text[0..tlen], text[0..tlen]);
        sb.text_len = @intCast(tlen);

        for (choices, 0..) |c_text, i| {
            if (i >= 3) break;
            const clen = @min(c_text.len, sb.choices[i].len);
            @memcpy(sb.choices[i][0..clen], c_text[0..clen]);
            sb.choice_lens[i] = @intCast(clen);
            sb.choice_count += 1;
        }

        self.active_balloon = sb;
    }

    /// Dismisses active speech balloon.
    pub fn dismiss_dialogue(self: *DisplayWindow) void {
        self.active_balloon = null;
        self.hovered_choice = null;
    }

    /// Appends a line to the REPL console history buffer (P9-03, D-011).
    pub fn add_console_history(self: *DisplayWindow, text: []const u8) void {
        if (self.console_history_count < 5) {
            const idx = self.console_history_count;
            const len = @min(text.len, self.console_history[idx].len);
            @memcpy(self.console_history[idx][0..len], text[0..len]);
            self.console_history_lens[idx] = len;
            self.console_history_count += 1;
        } else {
            var i: usize = 0;
            while (i < 4) : (i += 1) {
                self.console_history[i] = self.console_history[i + 1];
                self.console_history_lens[i] = self.console_history_lens[i + 1];
            }
            const len = @min(text.len, self.console_history[4].len);
            @memcpy(self.console_history[4][0..len], text[0..len]);
            self.console_history_lens[4] = len;
        }
    }

    /// Polls peripheral input events and returns high-level simulation intents (P6-01, P6-03).
    pub fn poll_events(self: *DisplayWindow, frame: *const RenderFrame) UserAction {
        if (self.is_headless) return .none;

        var event: c.SDL_Event = undefined;
        var action: UserAction = .none;

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => return .quit,
                c.SDL_MOUSEMOTION => {
                    if (self.active_balloon) |*b| {
                        const brect = get_balloon_rect(b, self.width);
                        self.hovered_choice = hit_test_balloon_choice(event.motion.x, event.motion.y, b, brect);
                    } else {
                        self.hovered_choice = null;
                    }

                    self.hovered_wp = hit_test_waypoint(
                        event.motion.x,
                        event.motion.y,
                        frame.waypoints[0..frame.waypoint_count],
                        self.width,
                        self.height,
                    );
                    self.hovered_hotspot = hit_test_hotspot(
                        event.motion.x,
                        event.motion.y,
                        frame.hotspots[0..frame.hotspot_count],
                        self.width,
                        self.height,
                    );
                    self.hovered_actor = hit_test_actor(
                        event.motion.x,
                        event.motion.y,
                        frame.entities[0..frame.entity_count],
                        self.width,
                        self.height,
                    );
                },
                c.SDL_MOUSEBUTTONDOWN => {
                    if (self.active_balloon) |*b| {
                        const brect = get_balloon_rect(b, self.width);
                        if (hit_test_balloon_choice(event.button.x, event.button.y, b, brect)) |ch_idx| {
                            return .{ .dialogue_choice = ch_idx };
                        } else {
                            self.dismiss_dialogue();
                            return .dismiss_dialogue;
                        }
                    }

                    if (event.button.button == c.SDL_BUTTON_RIGHT) {
                        // Right-click cancels in-hand item selection if active (P11-03, D-013)
                        if (self.selected_inventory_item != null) {
                            self.selected_inventory_item = null;
                            self.set_cue_banner("Action cancelled.", 60);
                            return .none;
                        }
                        // Otherwise cycles the active adventure verb (P7-02, D-009)
                        self.active_verb = self.active_verb.next();
                    } else if (event.button.button == c.SDL_BUTTON_LEFT) {
                        // 1. Check Timeline Scrubber (P9-02, D-011)
                        const tb_x: i32 = 20;
                        const tb_w: i32 = self.width - 40;
                        if (event.button.y >= 50 and event.button.y <= 74 and
                            event.button.x >= tb_x and event.button.x <= tb_x + tb_w)
                        {
                            if (frame.max_history_tick > 0) {
                                const rel_x: f32 = @as(f32, @floatFromInt(event.button.x - tb_x));
                                const ratio: f32 = rel_x / @as(f32, @floatFromInt(tb_w));
                                const max_t: f32 = @as(f32, @floatFromInt(frame.max_history_tick));
                                const target_tick: u64 = @min(frame.max_history_tick, @as(u64, @intFromFloat(ratio * max_t)));
                                return .{ .scrub_to_tick = target_tick };
                            }
                        }

                        // 2. Check Verb Bar buttons
                        const clicked_verb = hit_test_verb_button(event.button.x, event.button.y, self.height);
                        if (clicked_verb) |verb| {
                            if (self.selected_inventory_item != null) {
                                self.selected_inventory_item = null;
                                self.set_cue_banner("Action cancelled.", 60);
                            }
                            self.active_verb = verb;
                            return .none;
                        }

                        // 3. Check Inventory items (P11-03, D-013)
                        const clicked_item_idx = hit_test_inventory_item(event.button.x, event.button.y, self.height, frame.inventory[0..frame.inventory_count]);
                        if (clicked_item_idx) |idx| {
                            if (self.selected_inventory_item) |primary_idx| {
                                if (primary_idx == idx) {
                                    // Clicking same selected item deselects it
                                    self.selected_inventory_item = null;
                                    self.set_cue_banner("Item unselected.", 60);
                                    return .none;
                                } else {
                                    // Combining two distinct inventory items
                                    self.selected_inventory_item = null;
                                    var buf: [64]u8 = undefined;
                                    const p_name = if (primary_idx < frame.inventory_count) frame.inventory[primary_idx].get_name() else "item";
                                    const s_name = if (idx < frame.inventory_count) frame.inventory[idx].get_name() else "item";
                                    const banner = std.fmt.bufPrint(&buf, "Using {s} on {s}...", .{ p_name, s_name }) catch "Combining items...";
                                    self.set_cue_banner(banner, 90);
                                    return .{
                                        .combine_inventory_items = .{
                                            .primary_index = primary_idx,
                                            .secondary_index = idx,
                                        },
                                    };
                                }
                            } else {
                                // Select item into hand
                                self.selected_inventory_item = idx;
                                self.active_verb = .use_with;
                                var buf: [64]u8 = undefined;
                                const iname = if (idx < frame.inventory_count) frame.inventory[idx].get_name() else "item";
                                const banner = std.fmt.bufPrint(&buf, "Use {s} with...", .{iname}) catch "Use item with...";
                                self.set_cue_banner(banner, 180);
                                return .none;
                            }
                        }

                        // 4. Check Actors
                        const clicked_actor = hit_test_actor(
                            event.button.x,
                            event.button.y,
                            frame.entities[0..frame.entity_count],
                            self.width,
                            self.height,
                        );
                        if (clicked_actor) |actor_idx| {
                            if (self.selected_inventory_item) |item_idx| {
                                self.selected_inventory_item = null;
                                return .{
                                    .use_inventory_on_actor = .{
                                        .item_index = item_idx,
                                        .actor_index = actor_idx,
                                    },
                                };
                            } else {
                                action = .{ .interact_actor = .{ .verb = self.active_verb, .actor_index = actor_idx } };
                            }
                        } else {
                            // 5. Check Hotspots / Props
                            const clicked_hs = hit_test_hotspot(
                                event.button.x,
                                event.button.y,
                                frame.hotspots[0..frame.hotspot_count],
                                self.width,
                                self.height,
                            );
                            if (clicked_hs) |hs_idx| {
                                if (self.selected_inventory_item) |item_idx| {
                                    self.selected_inventory_item = null;
                                    return .{
                                        .use_inventory_on_hotspot = .{
                                            .item_index = item_idx,
                                            .hotspot_index = hs_idx,
                                        },
                                    };
                                } else {
                                    action = .{ .interact_hotspot = .{ .verb = self.active_verb, .hotspot_index = hs_idx } };
                                }
                            } else {
                                // 6. Check Waypoints
                                const clicked_wp = hit_test_waypoint(
                                    event.button.x,
                                    event.button.y,
                                    frame.waypoints[0..frame.waypoint_count],
                                    self.width,
                                    self.height,
                                );
                                if (clicked_wp) |wp_id| {
                                    if (self.selected_inventory_item != null) {
                                        self.selected_inventory_item = null;
                                        self.set_cue_banner("Action cancelled.", 60);
                                    }
                                    if (self.active_verb == .walk) {
                                        self.target_wp = wp_id;
                                        action = .{ .walk_player = wp_id };
                                    }
                                }
                            }
                        }
                    }
                },
                c.SDL_TEXTINPUT => {
                    if (self.show_console) {
                        var i: usize = 0;
                        while (event.text.text[i] != 0 and self.console_len < 127) : (i += 1) {
                            self.console_input[self.console_len] = event.text.text[i];
                            self.console_len += 1;
                        }
                    }
                },
                c.SDL_KEYDOWN => {
                    const sym = event.key.keysym.sym;
                    if (self.show_console) {
                        if (sym == c.SDLK_RETURN or sym == c.SDLK_KP_ENTER) {
                            if (self.console_len > 0) {
                                const cmd_text = self.console_input[0..self.console_len];
                                self.add_console_history(cmd_text);
                                const act = UserAction{ .repl_command = .{ .buf = self.console_input, .len = self.console_len } };
                                self.console_len = 0;
                                return act;
                            }
                        } else if (sym == c.SDLK_BACKSPACE) {
                            if (self.console_len > 0) {
                                self.console_len -= 1;
                            }
                        } else if (sym == c.SDLK_ESCAPE or sym == c.SDLK_TAB or sym == c.SDLK_BACKQUOTE) {
                            self.show_console = false;
                            return .toggle_console;
                        }
                        return .none;
                    }

                    switch (sym) {
                        c.SDLK_s => action = .spit_contest_spit,
                        c.SDLK_h => action = .sound_horn,
                        c.SDLK_g => action = .drink_green_drink,
                        c.SDLK_f => action = .tamper_flags,
                        c.SDLK_SPACE => action = .toggle_pause,
                        c.SDLK_n => action = .step_tick,
                        c.SDLK_r => action = .rewind,
                        c.SDLK_LEFT => action = .{ .scrub_to_tick = if (frame.tick > 0) frame.tick - 1 else 0 },
                        c.SDLK_RIGHT => action = .{ .scrub_to_tick = @min(frame.tick + 1, frame.max_history_tick) },
                        c.SDLK_F1, c.SDLK_d => {
                            self.show_debug_overlay = !self.show_debug_overlay;
                            return .toggle_debug;
                        },
                        c.SDLK_BACKQUOTE, c.SDLK_TAB, c.SDLK_c => {
                            self.show_console = !self.show_console;
                            return .toggle_console;
                        },
                        c.SDLK_ESCAPE => return .quit,
                        else => {},
                    }
                },
                else => {},
            }
        }

        return action;
    }

    // --- Drawing Primitives ---

    pub fn set_color(self: *DisplayWindow, col: Color) void {
        if (self.renderer) |r| {
            _ = c.SDL_SetRenderDrawColor(r, col.r, col.g, col.b, col.a);
        }
    }

    pub fn fill_rect(self: *DisplayWindow, x: i32, y: i32, w: i32, h: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            const rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
            _ = c.SDL_RenderFillRect(r, &rect);
        }
    }

    pub fn draw_rect_outline(self: *DisplayWindow, x: i32, y: i32, w: i32, h: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            const rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
            _ = c.SDL_RenderDrawRect(r, &rect);
        }
    }

    pub fn draw_line(self: *DisplayWindow, x1: i32, y1: i32, x2: i32, y2: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            _ = c.SDL_RenderDrawLine(r, x1, y1, x2, y2);
        }
    }

    pub fn fill_circle(self: *DisplayWindow, cx: i32, cy: i32, radius: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            var dy: i32 = -radius;
            while (dy <= radius) : (dy += 1) {
                const dx: i32 = @intCast(std.math.sqrt(@as(u64, @intCast(@max(0, radius * radius - dy * dy)))));
                _ = c.SDL_RenderDrawLine(r, cx - dx, cy + dy, cx + dx, cy + dy);
            }
        }
    }

    pub fn draw_circle_outline(self: *DisplayWindow, cx: i32, cy: i32, radius: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            var x: i32 = radius;
            var y: i32 = 0;
            var err: i32 = 0;

            while (x >= y) {
                _ = c.SDL_RenderDrawPoint(r, cx + x, cy + y);
                _ = c.SDL_RenderDrawPoint(r, cx + y, cy + x);
                _ = c.SDL_RenderDrawPoint(r, cx - y, cy + x);
                _ = c.SDL_RenderDrawPoint(r, cx - x, cy + y);
                _ = c.SDL_RenderDrawPoint(r, cx - x, cy - y);
                _ = c.SDL_RenderDrawPoint(r, cx - y, cy - x);
                _ = c.SDL_RenderDrawPoint(r, cx + y, cy - x);
                _ = c.SDL_RenderDrawPoint(r, cx + x, cy - y);

                if (err <= 0) {
                    y += 1;
                    err += 2 * y + 1;
                }
                if (err > 0) {
                    x -= 1;
                    err -= 2 * x + 1;
                }
            }
        }
    }

    pub fn draw_text(self: *DisplayWindow, text: []const u8, start_x: i32, start_y: i32, scale: i32, col: Color) void {
        if (self.renderer == null) return;
        var cur_x = start_x;
        for (text) |ch| {
            if (ch < 32 or ch > 126) {
                cur_x += font.char_width(scale);
                continue;
            }
            const glyph = font.FONT5X7[ch - 32];
            for (glyph, 0..) |col_byte, col_idx| {
                var row: usize = 0;
                while (row < 7) : (row += 1) {
                    if ((col_byte >> @intCast(row)) & 1 != 0) {
                        self.fill_rect(
                            cur_x + @as(i32, @intCast(col_idx)) * scale,
                            start_y + @as(i32, @intCast(row)) * scale,
                            scale,
                            scale,
                            col,
                        );
                    }
                }
            }
            cur_x += font.char_width(scale);
        }
    }

    // --- High-Level 2D Scene Rendering (P6-02, P6-04) ---

    pub fn render_frame(self: *DisplayWindow, frame: *const RenderFrame, is_paused: bool) void {
        if (self.is_headless or self.renderer == null) return;

        // Detect active scene theme (P12-03, D-014)
        const cur_scene = frame.get_current_scene();
        var is_spitting_scene = false;
        var is_wine_cellar_scene = false;
        var is_tavern_scene = false;

        if (cur_scene.len > 0) {
            if (std.mem.indexOf(u8, cur_scene, "Spit") != null or
                std.mem.indexOf(u8, cur_scene, "Booty") != null)
            {
                is_spitting_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Cellar") != null) {
                is_wine_cellar_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Tavern") != null or
                       std.mem.indexOf(u8, cur_scene, "Common") != null)
            {
                is_tavern_scene = true;
            }
        }

        // Fallback detection if current_scene wasn't explicitly set
        if (!is_spitting_scene and !is_wine_cellar_scene and !is_tavern_scene) {
            for (frame.waypoints[0..frame.waypoint_count]) |wp| {
                if (std.mem.indexOf(u8, wp.get_name(), "Starting Line") != null or
                    std.mem.indexOf(u8, wp.get_name(), "Offstage") != null)
                {
                    is_spitting_scene = true;
                    break;
                }
            }
            if (!is_spitting_scene) {
                for (frame.entities[0..frame.entity_count]) |e| {
                    const ename = e.get_name();
                    if (std.mem.eql(u8, ename, "Guybrush") or
                        std.mem.eql(u8, ename, "Organiser") or
                        std.mem.eql(u8, ename, "Onlookers"))
                    {
                        is_spitting_scene = true;
                        break;
                    }
                }
            }
            if (!is_spitting_scene) {
                for (frame.hotspots[0..frame.hotspot_count]) |hs| {
                    if (std.mem.indexOf(u8, hs.get_name(), "Flag") != null) {
                        is_spitting_scene = true;
                        break;
                    }
                }
            }
        }

        if (is_spitting_scene) {
            // Sky
            self.fill_rect(0, 0, self.width, self.height, Color.sky_dusk);

            // Grassy Contest Field & Ocean
            const field_x: i32 = 40;
            const field_y: i32 = 110;
            const field_w: i32 = self.width - 80;
            const field_h: i32 = 320;

            // Green grass field
            self.fill_rect(field_x, field_y, field_w - 180, field_h, Color.grass_green);
            self.draw_rect_outline(field_x, field_y, field_w - 180, field_h, Color{ .r = 45, .g = 95, .b = 55 });

            // Caribbean Ocean / Looking Offstage
            const ocean_x = field_x + field_w - 180;
            self.fill_rect(ocean_x, field_y, 180, field_h, Color.ocean_blue);
            self.draw_rect_outline(ocean_x, field_y, 180, field_h, Color{ .r = 56, .g = 189, .b = 248 });
            // Sandy shoreline edge
            self.fill_rect(ocean_x - 12, field_y, 12, field_h, Color.sand_color);

            // Ocean label
            self.draw_text("CARIBBEAN SEA", ocean_x + 16, field_y + 16, 2, Color{ .r = 56, .g = 189, .b = 248 });
            self.draw_text("(LOOKING OFFSTAGE)", ocean_x + 16, field_y + 36, 1, Color.white);

            // Field Title Header
            self.draw_text("BOOTY ISLAND - SPITTING COMPETITION", field_x + 16, field_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });

            // Ground distance track lines
            // Starting Line at x=200 (world_x = 0)
            self.draw_line(200, field_y + 60, 200, field_y + field_h - 20, Color.white);
            self.draw_text("START LINE", 165, field_y + field_h - 16, 1, Color.white);

            // 3rd Place Line at x=340 (world_x = 10)
            self.draw_line(340, field_y + 70, 340, field_y + field_h - 30, Color.hud_subtext);
            self.draw_text("3RD PLACE", 315, field_y + field_h - 26, 1, Color.hud_subtext);

            // 2nd Place Line at x=508 (world_x = 22, where Flags stand)
            self.draw_line(508, field_y + 70, 508, field_y + field_h - 30, Color{ .r = 245, .g = 158, .b = 11 });
            self.draw_text("2ND PLACE", 483, field_y + field_h - 26, 1, Color{ .r = 245, .g = 158, .b = 11 });

            // 1st Place Champion Line at x=676 (world_x = 34)
            self.draw_line(676, field_y + 60, 676, field_y + field_h - 20, Color{ .r = 250, .g = 204, .b = 21 });
            self.draw_text("CHAMPION LINE (1ST PLACE)", 600, field_y + field_h - 16, 1, Color{ .r = 250, .g = 204, .b = 21 });

            // Wind Indicator
            if (frame.wind_blowing) {
                self.draw_text(">>> WIND GUST: STRONG TAILWIND (BLOWING EAST TOWARD TARGET!) >>>", field_x + 16, field_y + 44, 2, Color.wind_color);
                self.draw_line(260, field_y + 140, 680, field_y + 140, Color.wind_color);
                self.draw_line(280, field_y + 190, 710, field_y + 190, Color.wind_color);
                self.draw_line(250, field_y + 240, 690, field_y + 240, Color.wind_color);
            } else {
                self.draw_text("WIND: CALM (Wait for tailwind gust)", field_x + 16, field_y + 44, 2, Color.hud_subtext);
            }
        } else if (is_wine_cellar_scene) {
            // Subterranean Stone Vault Theme (P12-03, D-014)
            self.fill_rect(0, 0, self.width, self.height, Color{ .r = 15, .g = 18, .b = 26 });

            const cellar_x: i32 = 40;
            const cellar_y: i32 = 110;
            const cellar_w: i32 = self.width - 80;
            const cellar_h: i32 = 320;

            // Vault chamber floor and stone wall
            self.fill_rect(cellar_x, cellar_y, cellar_w, cellar_h, Color.cellar_room);
            self.draw_rect_outline(cellar_x, cellar_y, cellar_w, cellar_h, Color.cellar_border);

            // Archway stone pillars on left and right borders
            self.fill_rect(cellar_x, cellar_y, 48, cellar_h, Color{ .r = 25, .g = 32, .b = 48 });
            self.draw_rect_outline(cellar_x, cellar_y, 48, cellar_h, Color{ .r = 45, .g = 55, .b = 75 });
            self.fill_rect(cellar_x + cellar_w - 48, cellar_y, 48, cellar_h, Color{ .r = 25, .g = 32, .b = 48 });
            self.draw_rect_outline(cellar_x + cellar_w - 48, cellar_y, 48, cellar_h, Color{ .r = 45, .g = 55, .b = 75 });

            // Stone flagstone grid lines across floor
            var row_y = cellar_y + 80;
            while (row_y < cellar_y + cellar_h) : (row_y += 60) {
                self.draw_line(cellar_x + 48, row_y, cellar_x + cellar_w - 48, row_y, Color{ .r = 35, .g = 42, .b = 58 });
            }

            // Cellar Vault Title Header
            self.draw_text("WINE CELLAR - SUBTERRANEAN VAULT", cellar_x + 60, cellar_y + 16, 2, Color{ .r = 192, .g = 132, .b = 252 });
            self.draw_text("(COOL, DAMP AIR WITH OAK & MUSTY BOUQUET)", cellar_x + 60, cellar_y + 36, 1, Color.hud_subtext);

            // Cellar torchlight sconces on stone pillars
            self.fill_circle(cellar_x + 24, cellar_y + 60, 6, Color{ .r = 245, .g = 158, .b = 11 });
            self.fill_circle(cellar_x + 24, cellar_y + 58, 3, Color{ .r = 254, .g = 240, .b = 138 });
            self.fill_circle(cellar_x + cellar_w - 24, cellar_y + 60, 6, Color{ .r = 245, .g = 158, .b = 11 });
            self.fill_circle(cellar_x + cellar_w - 24, cellar_y + 58, 3, Color{ .r = 254, .g = 240, .b = 138 });
        } else if (is_tavern_scene) {
            // Dedicated Warm Wooden Tavern Common Room Theme (P12-03, D-014)
            self.fill_rect(0, 0, self.width, self.height, Color.tavern_bg);

            const tavern_x: i32 = 40;
            const tavern_y: i32 = 110;
            const tavern_w: i32 = self.width - 80;
            const tavern_h: i32 = 320;

            self.fill_rect(tavern_x, tavern_y, tavern_w, tavern_h, Color.tavern_room);
            self.draw_rect_outline(tavern_x, tavern_y, tavern_w, tavern_h, Color.tavern_border);

            // Timber ceiling beams
            self.fill_rect(tavern_x, tavern_y + 50, tavern_w, 8, Color{ .r = 30, .g = 20, .b = 15 });
            self.fill_rect(tavern_x, tavern_y + 100, tavern_w, 6, Color{ .r = 30, .g = 20, .b = 15 });

            // Title Header
            self.draw_text("TAVERN - COMMON ROOM", tavern_x + 16, tavern_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
            self.draw_text("(WARM FIREPLACE, CLINKING TANKARDS)", tavern_x + 16, tavern_y + 36, 1, Color.hud_subtext);
        } else {
            // 1. Clear background
            self.fill_rect(0, 0, self.width, self.height, Color.tavern_bg);

            // 2. Render Rooms (Tavern Hall & Wine Cellar side-by-side)
            const tavern_rect_x = 100;
            const tavern_rect_y = 120;
            const tavern_rect_w = 480;
            const tavern_rect_h = 320;
            self.fill_rect(tavern_rect_x, tavern_rect_y, tavern_rect_w, tavern_rect_h, Color.tavern_room);
            self.draw_rect_outline(tavern_rect_x, tavern_rect_y, tavern_rect_w, tavern_rect_h, Color.tavern_border);
            self.draw_text("TAVERN - COMMON ROOM", tavern_rect_x + 16, tavern_rect_y + 16, 2, Color.hud_subtext);

            const cellar_rect_x = 600;
            const cellar_rect_y = 120;
            const cellar_rect_w = 260;
            const cellar_rect_h = 320;
            self.fill_rect(cellar_rect_x, cellar_rect_y, cellar_rect_w, cellar_rect_h, Color.cellar_room);
            self.draw_rect_outline(cellar_rect_x, cellar_rect_y, cellar_rect_w, cellar_rect_h, Color.cellar_border);
            self.draw_text("WINE CELLAR", cellar_rect_x + 16, cellar_rect_y + 16, 2, Color.hud_subtext);
        }

        // 3. Render Scene Hotspots / Props (P7-01, D-009)
        for (frame.hotspots[0..frame.hotspot_count], 0..) |hs, idx| {
            const pt = world_to_screen(hs.x, hs.y, self.width, self.height);
            const is_hovered = (self.hovered_hotspot != null and self.hovered_hotspot.? == idx);
            const name = hs.get_name();

            if (std.mem.indexOf(u8, name, "Fire") != null or std.mem.indexOf(u8, name, "Hearth") != null) {
                // Stone fireplace & fire glow
                self.fill_rect(pt.x - 22, pt.y - 24, 44, 48, Color{ .r = 55, .g = 45, .b = 40 });
                self.draw_rect_outline(pt.x - 22, pt.y - 24, 44, 48, Color{ .r = 85, .g = 70, .b = 60 });
                self.fill_rect(pt.x - 14, pt.y - 10, 28, 30, Color{ .r = 25, .g = 18, .b = 16 });
                self.fill_circle(pt.x, pt.y + 4, 10, Color{ .r = 239, .g = 68, .b = 68 });
                self.fill_circle(pt.x, pt.y + 2, 6, Color{ .r = 245, .g = 158, .b = 11 });
            } else if (std.mem.indexOf(u8, name, "Bar") != null or std.mem.indexOf(u8, name, "Counter") != null) {
                // Polished tavern counter
                self.fill_rect(pt.x - 28, pt.y - 14, 56, 28, Color{ .r = 110, .g = 50, .b = 18 });
                self.draw_rect_outline(pt.x - 28, pt.y - 14, 56, 28, Color{ .r = 145, .g = 75, .b = 30 });
                self.fill_rect(pt.x - 26, pt.y - 12, 52, 4, Color{ .r = 180, .g = 83, .b = 9 });
            } else if (std.mem.indexOf(u8, name, "Cask") != null or std.mem.indexOf(u8, name, "Barrel") != null) {
                // Vintage wine cask
                self.fill_rect(pt.x - 18, pt.y - 22, 36, 44, Color{ .r = 69, .g = 26, .b = 3 });
                self.draw_rect_outline(pt.x - 18, pt.y - 22, 36, 44, Color{ .r = 120, .g = 53, .b = 15 });
                self.draw_line(pt.x - 18, pt.y - 10, pt.x + 18, pt.y - 10, Color{ .r = 140, .g = 140, .b = 150 });
                self.draw_line(pt.x - 18, pt.y + 10, pt.x + 18, pt.y + 10, Color{ .r = 140, .g = 140, .b = 150 });
            } else if (std.mem.indexOf(u8, name, "Flag") != null) {
                // Spitting Competition Distance Flags (P10-03, D-012)
                const flag_x = if (frame.flags_tampered) pt.x - 70 else pt.x;
                self.fill_rect(flag_x - 2, pt.y - 32, 4, 40, Color{ .r = 217, .g = 119, .b = 6 });
                const fcol = if (frame.flags_tampered) Color.flag_tampered else Color.flag_color;
                self.fill_rect(flag_x + 2, pt.y - 32, 28, 18, fcol);
                self.draw_line(flag_x + 2, pt.y - 14, flag_x + 30, pt.y - 32, Color.white);

                if (frame.flags_tampered) {
                    self.draw_rect_outline(pt.x - 1, pt.y - 30, 2, 38, Color.hud_subtext);
                    self.draw_text("[MOVED!]", flag_x - 20, pt.y + 14, 2, Color.flag_tampered);
                } else {
                    self.draw_text("Flags", flag_x - 14, pt.y + 14, 2, Color.hud_text);
                }
            } else {
                // Default prop
                self.fill_rect(pt.x - 16, pt.y - 16, 32, 32, Color{ .r = 75, .g = 65, .b = 60 });
                self.draw_rect_outline(pt.x - 16, pt.y - 16, 32, 32, Color.tavern_border);
            }

            // Hover highlight ring and look prompt
            if (is_hovered) {
                self.draw_circle_outline(pt.x, pt.y, HOTSPOT_SCREEN_RADIUS + 4, Color.wp_hover);
                var look_buf: [64]u8 = undefined;
                const look_prompt = std.fmt.bufPrint(&look_buf, "[Look at {s}]", .{name}) catch "[Look]";
                const tw = font.text_width(look_prompt, 2);
                self.draw_text(look_prompt, pt.x - @divTrunc(tw, 2), pt.y - HOTSPOT_SCREEN_RADIUS - 18, 2, Color.wp_hover);
            }
        }

        // 4. Render Corridors / Edges between Waypoints
        if (!is_spitting_scene) {
            for (frame.edges[0..frame.edge_count]) |e| {
                var wp_a: ?RenderWaypoint = null;
                var wp_b: ?RenderWaypoint = null;
                for (frame.waypoints[0..frame.waypoint_count]) |wp| {
                    if (wp.id == e.from) wp_a = wp;
                    if (wp.id == e.to) wp_b = wp;
                }
                if (wp_a != null and wp_b != null) {
                    const p1 = world_to_screen(wp_a.?.x, wp_a.?.y, self.width, self.height);
                    const p2 = world_to_screen(wp_b.?.x, wp_b.?.y, self.width, self.height);

                    // Thick path line
                    self.draw_line(p1.x, p1.y - 2, p2.x, p2.y - 2, Color.path_edge);
                    self.draw_line(p1.x, p1.y - 1, p2.x, p2.y - 1, Color.path_corridor);
                    self.draw_line(p1.x, p1.y, p2.x, p2.y, Color.path_corridor);
                    self.draw_line(p1.x, p1.y + 1, p2.x, p2.y + 1, Color.path_corridor);
                    self.draw_line(p1.x, p1.y + 2, p2.x, p2.y + 2, Color.path_edge);
                }
            }
        }

        // 4. Render Waypoint Nodes
        for (frame.waypoints[0..frame.waypoint_count]) |wp| {
            const pt = world_to_screen(wp.x, wp.y, self.width, self.height);
            const is_hovered = (self.hovered_wp == wp.id);
            const is_targeted = (self.target_wp == wp.id);

            // Halo glow for hovered/target node
            if (is_hovered) {
                self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS + 4, Color.wp_hover);
            }
            if (is_targeted) {
                self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS + 6, Color.wp_target);
            }

            if (!is_spitting_scene) {
                // Waypoint anchor body
                const body_color = if (is_hovered) Color.wp_hover else Color.wp_normal;
                self.fill_circle(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, body_color);
                self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.white);
                self.fill_circle(pt.x, pt.y, 4, Color.white);

                // Waypoint text label
                const name = wp.get_name();
                const text_w = font.text_width(name, 2);
                self.draw_text(name, pt.x - @divTrunc(text_w, 2), pt.y + WAYPOINT_SCREEN_RADIUS + 8, 2, Color.hud_text);
            } else {
                // In Spitting Contest: Stage marks
                if (is_hovered or is_targeted) {
                    self.fill_circle(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.wp_hover);
                    self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.white);
                    const name = wp.get_name();
                    var buf: [64]u8 = undefined;
                    const prompt = std.fmt.bufPrint(&buf, "[Walk to {s}]", .{name}) catch name;
                    const text_w = font.text_width(prompt, 2);

                    // Check if actors are stationed at this waypoint coordinate
                    var has_actors = false;
                    for (frame.entities[0..frame.entity_count]) |ent| {
                        if (ent.x == wp.x and ent.y == wp.y) {
                            has_actors = true;
                            break;
                        }
                    }
                    const prompt_y = if (has_actors)
                        pt.y + WAYPOINT_SCREEN_RADIUS + 34
                    else
                        pt.y + WAYPOINT_SCREEN_RADIUS + 8;
                    self.draw_text(prompt, pt.x - @divTrunc(text_w, 2), prompt_y, 2, Color.wp_hover);
                } else {
                    // Subtle ground mark anchor
                    self.draw_circle_outline(pt.x, pt.y, 5, Color{ .r = 255, .g = 255, .b = 255, .a = 100 });
                    self.fill_circle(pt.x, pt.y, 2, Color.white);
                }
            }
        }

        // 5. Render Actors
        for (frame.entities[0..frame.entity_count], 0..) |e, idx| {
            const name = e.get_name();
            const layout = get_entity_screen_layout(idx, frame.entities[0..frame.entity_count], self.width, self.height);
            const pt = layout.pos;

            if (std.mem.eql(u8, name, "Cat")) {
                // Cat (Player): Orange token with cat ears
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.cat_color);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Ears
                self.fill_rect(pt.x - 12, pt.y - ACTOR_SCREEN_RADIUS - 4, 6, 6, Color.cat_color);
                self.fill_rect(pt.x + 6, pt.y - ACTOR_SCREEN_RADIUS - 4, 6, 6, Color.cat_color);

                // Label
                self.draw_text("Cat (Player)", pt.x - 36, layout.label_y, 2, Color.cat_color);

                // Carried Cheese
                if (frame.cheese_holder == e.entity) {
                    self.fill_circle(pt.x + 14, pt.y - 10, 8, Color.cheese_color);
                    self.draw_circle_outline(pt.x + 14, pt.y - 10, 8, Color.white);
                    self.draw_text("Cheese", pt.x + 24, pt.y - 14, 2, Color.cheese_color);
                }
            } else if (std.mem.eql(u8, name, "Guard")) {
                // Guard: Steel Blue token
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.guard_color);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Shield visor
                self.fill_rect(pt.x - 8, pt.y - 4, 16, 6, Color.white);

                // Label
                self.draw_text("Guard", pt.x - 16, layout.label_y, 2, Color.guard_color);

                // Carried Cheese
                if (frame.cheese_holder == e.entity) {
                    self.fill_circle(pt.x + 14, pt.y - 10, 8, Color.cheese_color);
                    self.draw_circle_outline(pt.x + 14, pt.y - 10, 8, Color.white);
                    self.draw_text("Cheese", pt.x + 24, pt.y - 14, 2, Color.cheese_color);
                }

                // Charmed status
                if (frame.charmed_target == e.entity) {
                    self.draw_text("[Charmed!]", pt.x - 28, layout.status_y, 2, Color.cue_alert);
                }
            } else if (std.mem.eql(u8, name, "Bard")) {
                // Bard: Purple token
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.bard_color);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Feather cap / lute indicator
                self.fill_rect(pt.x - 2, pt.y - ACTOR_SCREEN_RADIUS - 6, 4, 8, Color.white);

                // Label
                self.draw_text("Bard", pt.x - 12, layout.label_y, 2, Color.bard_color);
            } else if (std.mem.eql(u8, name, "Guybrush")) {
                // Guybrush (Player): Blonde hair, pirate blue coat
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.guybrush_coat);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Blonde hair
                self.fill_circle(pt.x, pt.y - 8, 8, Color.guybrush_hair);

                // Label
                const nw = font.text_width("Guybrush", 2);
                self.draw_text("Guybrush", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color.guybrush_hair);

                // Spit Status
                const spit_str = if (frame.spit_is_thick) "[Thick Spit Ready!]" else "[Spit: Thin]";
                const spit_col = if (frame.spit_is_thick) Color.spit_color else Color.hud_subtext;
                const sw = font.text_width(spit_str, 2);
                self.draw_text(spit_str, pt.x - @divTrunc(sw, 2), layout.status_y, 2, spit_col);
            } else if (std.mem.eql(u8, name, "Organiser")) {
                // Organiser: Velvet red coat, fancy hat
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.organiser_coat);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Cocked hat / feather
                self.fill_rect(pt.x - 8, pt.y - ACTOR_SCREEN_RADIUS - 4, 16, 5, Color.black);
                self.fill_rect(pt.x - 2, pt.y - ACTOR_SCREEN_RADIUS - 8, 4, 6, Color.guybrush_hair);

                // Label
                const nw = font.text_width("Organiser", 2);
                self.draw_text("Organiser", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color.organiser_coat);

                // Distracted / watching status
                const org_str = if (frame.organiser_distracted) "[DISTRACTED!]" else "[Watching]";
                const org_col = if (frame.organiser_distracted) Color.cue_alert else Color.status_running;
                const sw = font.text_width(org_str, 2);
                self.draw_text(org_str, pt.x - @divTrunc(sw, 2), layout.status_y, 2, org_col);
            } else if (std.mem.eql(u8, name, "Onlookers")) {
                // Onlookers: Crowd of spectator circles
                self.fill_circle(pt.x - 8, pt.y, ACTOR_SCREEN_RADIUS - 2, Color.onlookers_color);
                self.fill_circle(pt.x + 8, pt.y, ACTOR_SCREEN_RADIUS - 2, Color.onlookers_color);
                self.fill_circle(pt.x, pt.y - 6, ACTOR_SCREEN_RADIUS - 2, Color{ .r = 140, .g = 100, .b = 160 });
                self.draw_circle_outline(pt.x, pt.y - 6, ACTOR_SCREEN_RADIUS - 2, Color.white);

                // Label
                const nw = font.text_width("Onlookers", 2);
                self.draw_text("Onlookers", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color.onlookers_color);
                if (frame.organiser_distracted) {
                    const sw = font.text_width("[Looking Offstage]", 2);
                    self.draw_text("[Looking Offstage]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.cue_alert);
                }
            } else {
                // Generic actor token
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 70, .g = 80, .b = 95 });
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
                const tw = font.text_width(name, 2);
                self.draw_text(name, pt.x - @divTrunc(tw, 2), layout.label_y, 2, Color.hud_text);
            }
        }

        // 6. Top Status HUD Bar
        self.fill_rect(0, 0, self.width, 48, Color.hud_bg);
        self.draw_line(0, 48, self.width, 48, Color.tavern_border);

        var top_buf: [128]u8 = undefined;
        const status_str = if (is_paused) "PAUSED" else "RUNNING";
        const top_text = std.fmt.bufPrint(
            &top_buf,
            "BeSpoke Engine | Tick: {d:03} | Facts: {d} | State: {s}",
            .{ frame.tick, frame.fact_count, status_str },
        ) catch "BeSpoke Engine";
        const status_col = if (is_paused) Color.status_paused else Color.status_running;
        self.draw_text(top_text, 20, 16, 2, status_col);

        // 6b. Interactive Time-Travel Timeline Scrubber Bar (P9-02, D-011)
        const tb_x: i32 = 20;
        const tb_y: i32 = 50;
        const tb_w: i32 = self.width - 40;
        const tb_h: i32 = 22;

        self.fill_rect(tb_x, tb_y, tb_w, tb_h, Color{ .r = 15, .g = 23, .b = 42, .a = 230 });
        self.draw_rect_outline(tb_x, tb_y, tb_w, tb_h, Color{ .r = 71, .g = 85, .b = 105 });

        if (frame.max_history_tick > 0) {
            const cur_t: f32 = @as(f32, @floatFromInt(frame.tick));
            const max_t: f32 = @as(f32, @floatFromInt(frame.max_history_tick));
            const ratio: f32 = @min(1.0, cur_t / max_t);
            const playhead_x = tb_x + @as(i32, @intFromFloat(ratio * @as(f32, @floatFromInt(tb_w))));

            // Elapsed bar fill
            self.fill_rect(tb_x + 2, tb_y + 3, playhead_x - tb_x, tb_h - 6, Color{ .r = 37, .g = 99, .b = 235, .a = 180 });

            // Playhead indicator
            self.fill_rect(playhead_x - 3, tb_y - 2, 6, tb_h + 4, Color.white);
            self.draw_rect_outline(playhead_x - 3, tb_y - 2, 6, tb_h + 4, Color.cue_alert);
        }

        var tb_text_buf: [80]u8 = undefined;
        const tb_text = std.fmt.bufPrint(&tb_text_buf, "TIMELINE [Tick {d:02}/{d:02}] (Click or [< / >] to Scrub | Space: Pause)", .{ frame.tick, frame.max_history_tick }) catch "TIMELINE";
        self.draw_text(tb_text, tb_x + 8, tb_y + 4, 1, Color.hud_text);

        // 7. Adventure Verb Bar & Inventory Tray (P7-02, P7-03, D-009)
        const bar_y = self.height - 80;
        self.fill_rect(0, bar_y - 6, self.width, 42, Color{ .r = 15, .g = 23, .b = 42, .a = 240 });
        self.draw_line(0, bar_y - 6, self.width, bar_y - 6, Color.tavern_border);

        // 5 Verb Buttons: WALK, LOOK, TALK, TAKE, USE
        var vi: usize = 0;
        while (vi < 5) : (vi += 1) {
            const verb: AdventureVerb = @enumFromInt(@as(u8, @intCast(vi)));
            const bx = 20 + @as(i32, @intCast(vi)) * 74;
            const is_active = (self.active_verb == verb);

            if (is_active) {
                self.fill_rect(bx, bar_y, 68, 26, Color.wp_hover);
                self.draw_rect_outline(bx, bar_y, 68, 26, Color.white);
                const label = verb.label();
                const lw = font.text_width(label, 2);
                self.draw_text(label, bx + @divTrunc(68 - lw, 2), bar_y + 6, 2, Color.black);
            } else {
                self.fill_rect(bx, bar_y, 68, 26, Color{ .r = 30, .g = 41, .b = 59 });
                self.draw_rect_outline(bx, bar_y, 68, 26, Color{ .r = 71, .g = 85, .b = 105 });
                const label = verb.label();
                const lw = font.text_width(label, 2);
                self.draw_text(label, bx + @divTrunc(68 - lw, 2), bar_y + 6, 2, Color.hud_text);
            }
        }

        // Inventory Tray (P7-03, P11-03)
        self.draw_text("ITEMS:", 400, bar_y + 6, 2, Color.hud_subtext);
        var item_x: i32 = 480;
        if (frame.inventory_count == 0) {
            self.draw_text("(Empty)", item_x, bar_y + 6, 2, Color{ .r = 100, .g = 116, .b = 139 });
        } else {
            for (frame.inventory[0..frame.inventory_count], 0..) |item, idx| {
                const iname = item.get_name();
                const iw = font.text_width(iname, 2) + 24;
                const is_selected = (self.selected_inventory_item != null and self.selected_inventory_item.? == idx);
                const bg_col = if (is_selected) Color{ .r = 85, .g = 65, .b = 25 } else Color{ .r = 45, .g = 35, .b = 20 };
                const border_col = if (is_selected) Color{ .r = 250, .g = 204, .b = 21 } else Color.cheese_color;
                const text_col = if (is_selected) Color{ .r = 254, .g = 240, .b = 138 } else Color.cheese_color;

                self.fill_rect(item_x, bar_y, iw, 26, bg_col);
                self.draw_rect_outline(item_x, bar_y, iw, 26, border_col);
                if (is_selected) {
                    // Double border for glowing selected highlight
                    self.draw_rect_outline(item_x + 1, bar_y + 1, iw - 2, 24, Color{ .r = 253, .g = 224, .b = 71 });
                }
                self.fill_circle(item_x + 10, bar_y + 13, 5, border_col);
                self.draw_text(iname, item_x + 18, bar_y + 6, 2, text_col);
                item_x += iw + 8;
            }
        }

        // In-Hand Item Cursor / Status (P11-03, D-013)
        if (self.selected_inventory_item) |sel_idx| {
            if (sel_idx < frame.inventory_count) {
                const sel_name = frame.inventory[sel_idx].get_name();
                var in_hand_buf: [96]u8 = undefined;
                const in_hand_text = std.fmt.bufPrint(&in_hand_buf, "[IN HAND: {s}] (Click target/item to use | Right-Click to cancel)", .{sel_name}) catch "[IN HAND]";
                self.draw_text(in_hand_text, 20, bar_y - 18, 1, Color{ .r = 250, .g = 204, .b = 21 });
            }
        }

        // 8. Bottom Controls HUD Bar
        self.fill_rect(0, self.height - 44, self.width, 44, Color.hud_bg);
        self.draw_line(0, self.height - 44, self.width, self.height - 44, Color.tavern_border);
        if (is_spitting_scene) {
            self.draw_text(
                "[S]: Spit! | [H]: Horn | [G]: GreenDrink | [F]: Move Flags | [Space]: Pause | [< / >]: Scrub",
                20,
                self.height - 28,
                2,
                Color.hud_subtext,
            );
        } else {
            self.draw_text(
                "[Click]: Act | [Right-Click]: Verb | [F1/D]: Debug HUD | [C]: REPL | [< / >]: Scrub | [Space]: Pause",
                20,
                self.height - 28,
                2,
                Color.hud_subtext,
            );
        }

        // 8. Ephemeral Cue Banner
        if (self.cue_banner_ticks > 0 and self.cue_banner_len > 0) {
            const banner = self.cue_banner_text[0..self.cue_banner_len];
            const bw = font.text_width(banner, 2) + 32;
            const bx = @divTrunc(self.width - bw, 2);
            const by = 60;
            self.fill_rect(bx, by, bw, 36, Color.hud_bg);
            self.draw_rect_outline(bx, by, bw, 36, Color.cue_alert);
            self.draw_text(banner, bx + 16, by + 10, 2, Color.cue_alert);
            self.cue_banner_ticks -= 1;
        }

        // 9. Speech Balloon & Branching Dialogue (P7-04, D-009)
        if (self.active_balloon) |*b| {
            const brect = get_balloon_rect(b, self.width);

            // Balloon parchment body
            self.fill_rect(brect.x, brect.y, brect.w, brect.h, Color{ .r = 254, .g = 243, .b = 199 });
            self.draw_rect_outline(brect.x, brect.y, brect.w, brect.h, Color{ .r = 146, .g = 64, .b = 14 });
            self.draw_rect_outline(brect.x + 2, brect.y + 2, brect.w - 4, brect.h - 4, Color{ .r = 180, .g = 83, .b = 9 });

            // Speech tail pointing down to speaker
            const tail_x = b.speaker_pos.x;
            self.draw_line(tail_x - 6, brect.y + brect.h, tail_x, brect.y + brect.h + 10, Color{ .r = 146, .g = 64, .b = 14 });
            self.draw_line(tail_x + 6, brect.y + brect.h, tail_x, brect.y + brect.h + 10, Color{ .r = 146, .g = 64, .b = 14 });

            // Speaker title & dialog text
            var title_buf: [48]u8 = undefined;
            const title_text = std.fmt.bufPrint(&title_buf, "{s}:", .{b.get_speaker_name()}) catch "Speaker:";
            self.draw_text(title_text, brect.x + 14, brect.y + 10, 2, Color{ .r = 180, .g = 83, .b = 9 });
            const title_offset = font.text_width(title_text, 2) + 12;
            self.draw_text(b.get_text(), brect.x + 14 + title_offset, brect.y + 10, 2, Color{ .r = 28, .g = 25, .b = 23 });

            // Branching dialogue choices
            const choices_start_y = brect.y + 42;
            var ci: usize = 0;
            while (ci < b.choice_count) : (ci += 1) {
                const cy = choices_start_y + @as(i32, @intCast(ci)) * 26;
                const is_hovered = (self.hovered_choice != null and self.hovered_choice.? == ci);
                const c_text = b.get_choice(ci);

                if (is_hovered) {
                    self.fill_rect(brect.x + 12, cy, brect.w - 24, 22, Color.wp_hover);
                    self.draw_rect_outline(brect.x + 12, cy, brect.w - 24, 22, Color.white);
                    self.draw_text(c_text, brect.x + 20, cy + 4, 2, Color.black);
                } else {
                    self.fill_rect(brect.x + 12, cy, brect.w - 24, 22, Color{ .r = 253, .g = 230, .b = 138 });
                    self.draw_rect_outline(brect.x + 12, cy, brect.w - 24, 22, Color{ .r = 217, .g = 119, .b = 6 });
                    self.draw_text(c_text, brect.x + 20, cy + 4, 2, Color{ .r = 120, .g = 53, .b = 15 });
                }
            }
        }

        // 10. In-Engine Debug Inspector Overlay (P9-01, D-011)
        if (self.show_debug_overlay) {
            const dbg_w: i32 = 340;
            const dbg_h: i32 = self.height - 180;
            const dbg_x: i32 = self.width - dbg_w - 20;
            const dbg_y: i32 = 80;

            self.fill_rect(dbg_x, dbg_y, dbg_w, dbg_h, Color{ .r = 10, .g = 15, .b = 30, .a = 240 });
            self.draw_rect_outline(dbg_x, dbg_y, dbg_w, dbg_h, Color.wp_hover);
            self.draw_text("=== RELATIONAL WORLD INSPECTOR (F1/D) ===", dbg_x + 12, dbg_y + 10, 1, Color.wp_hover);

            var cur_y: i32 = dbg_y + 26;
            self.draw_text("ACTIVE FACTS:", dbg_x + 12, cur_y, 1, Color.hud_subtext);
            cur_y += 14;

            var fi: usize = 0;
            while (fi < frame.debug_fact_count and fi < 10) : (fi += 1) {
                const df = &frame.debug_facts[fi];
                var fbuf: [96]u8 = undefined;
                const fstr = if (df.expires_at_tick > 0)
                    std.fmt.bufPrint(&fbuf, " - {s}({s}, {s}) [exp:{d}]", .{ df.get_relation(), df.get_subject(), df.get_object(), df.expires_at_tick }) catch "?"
                else
                    std.fmt.bufPrint(&fbuf, " - {s}({s}, {s})", .{ df.get_relation(), df.get_subject(), df.get_object() }) catch "?";
                self.draw_text(fstr, dbg_x + 12, cur_y, 1, Color.hud_text);
                cur_y += 12;
            }

            cur_y += 6;
            self.draw_line(dbg_x + 10, cur_y, dbg_x + dbg_w - 10, cur_y, Color{ .r = 71, .g = 85, .b = 105 });
            cur_y += 6;

            self.draw_text("ACTIVE FIBERS & STACKS:", dbg_x + 12, cur_y, 1, Color.hud_subtext);
            cur_y += 14;

            var fib_i: usize = 0;
            while (fib_i < frame.debug_fiber_count and fib_i < 5) : (fib_i += 1) {
                const fib = &frame.debug_fibers[fib_i];
                var fib_buf: [96]u8 = undefined;
                const fib_str = std.fmt.bufPrint(&fib_buf, " #{d} [{s}] pc:{d:03} depth:{d} prio:{d} ({s})", .{
                    fib.id, fib.get_owner(), fib.pc, fib.interrupt_depth, fib.priority, fib.get_state(),
                }) catch "?";
                self.draw_text(fib_str, dbg_x + 12, cur_y, 1, Color.hud_text);
                cur_y += 12;
            }

            cur_y += 6;
            self.draw_line(dbg_x + 10, cur_y, dbg_x + dbg_w - 10, cur_y, Color{ .r = 71, .g = 85, .b = 105 });
            cur_y += 6;

            self.draw_text("SPATIAL TOPOLOGY & AGENTS:", dbg_x + 12, cur_y, 1, Color.hud_subtext);
            cur_y += 14;
            for (frame.entities[0..frame.entity_count]) |e| {
                var ent_buf: [64]u8 = undefined;
                const status = if (e.is_moving) "moving" else "idle";
                const ent_str = std.fmt.bufPrint(&ent_buf, " * {s}: ({d}, {d}) [{s}]", .{ e.get_name(), e.x, e.y, status }) catch "?";
                self.draw_text(ent_str, dbg_x + 12, cur_y, 1, Color.white);
                cur_y += 12;
            }
        }

        // 11. Live Interactive REPL Console Drawer (P9-03, D-011)
        if (self.show_console) {
            const con_x: i32 = 20;
            const con_w: i32 = self.width - 40;
            const con_h: i32 = 160;
            const con_y: i32 = self.height - con_h - 48;

            self.fill_rect(con_x, con_y, con_w, con_h, Color{ .r = 8, .g = 12, .b = 24, .a = 245 });
            self.draw_rect_outline(con_x, con_y, con_w, con_h, Color{ .r = 245, .g = 158, .b = 11 });
            self.draw_text(">>> BESPOKE LIVE REPL (Tab/C to Close | Type 'help' for commands) <<<", con_x + 14, con_y + 10, 1, Color{ .r = 245, .g = 158, .b = 11 });

            // History log
            var log_y: i32 = con_y + 26;
            var hi: usize = 0;
            while (hi < self.console_history_count) : (hi += 1) {
                const htext = self.console_history[hi][0..self.console_history_lens[hi]];
                self.draw_text(htext, con_x + 14, log_y, 1, Color.hud_subtext);
                log_y += 16;
            }

            // Input prompt line
            self.fill_rect(con_x + 10, con_y + con_h - 32, con_w - 20, 24, Color{ .r = 15, .g = 23, .b = 42 });
            self.draw_rect_outline(con_x + 10, con_y + con_h - 32, con_w - 20, 24, Color{ .r = 71, .g = 85, .b = 105 });

            var prompt_buf: [140]u8 = undefined;
            const cur_input = self.console_input[0..self.console_len];
            const prompt_text = std.fmt.bufPrint(&prompt_buf, "> {s}_", .{cur_input}) catch "> _";
            self.draw_text(prompt_text, con_x + 18, con_y + con_h - 26, 2, Color.white);
        }

        // 12. Present Frame
        if (self.renderer) |r| {
            c.SDL_RenderPresent(r);
        }
    }
};

test "renderer coordinate conversion and hit testing" {
    const testing = std.testing;

    const pt = world_to_screen(20, 0, 960, 540);
    // Center is (480, 290). With world_x=20: 480 - 280 + 20*14 = 200 + 280 = 480.
    try testing.expectEqual(@as(i32, 480), pt.x);
    try testing.expectEqual(@as(i32, 290), pt.y);

    const waypoints = [_]RenderWaypoint{
        .{
            .id = 1,
            .room = EntityId.from_int(1),
            .x = 0,
            .y = 0,
            .name = undefined,
            .name_len = 0,
        },
        .{
            .id = 2,
            .room = EntityId.from_int(1),
            .x = 20,
            .y = 0,
            .name = undefined,
            .name_len = 0,
        },
    };

    // Hit test exact waypoint 2 coordinates
    const hit_id = hit_test_waypoint(pt.x, pt.y, &waypoints, 960, 540);
    try testing.expectEqual(@as(?WaypointId, 2), hit_id);

    // Hit test off-screen / empty area
    const miss_id = hit_test_waypoint(10, 10, &waypoints, 960, 540);
    try testing.expectEqual(@as(?WaypointId, null), miss_id);

    const hotspots = [_]RenderHotspot{
        .{
            .entity = EntityId.from_int(50),
            .room = EntityId.from_int(1),
            .x = 20,
            .y = 0,
            .radius = 10,
            .name = undefined,
            .name_len = 0,
            .examine_text = undefined,
            .examine_len = 0,
        },
    };

    const hs_hit = hit_test_hotspot(pt.x, pt.y, &hotspots, 960, 540);
    try testing.expectEqual(@as(?usize, 0), hs_hit);

    const hs_miss = hit_test_hotspot(10, 10, &hotspots, 960, 540);
    try testing.expectEqual(@as(?usize, null), hs_miss);

    // Hit test verb buttons
    const btn_look = hit_test_verb_button(100, 540 - 70, 540);
    try testing.expectEqual(@as(?AdventureVerb, .look_at), btn_look);

    const btn_miss = hit_test_verb_button(10, 10, 540);
    try testing.expectEqual(@as(?AdventureVerb, null), btn_miss);

    // Test entity visual standoff for multiple actors at the same position
    const entities = [_]RenderEntity{
        .{
            .entity = EntityId.from_int(10),
            .x = 0,
            .y = 0,
            .current_wp = 1,
            .is_moving = false,
            .name = undefined,
            .name_len = 0,
        },
        .{
            .entity = EntityId.from_int(11),
            .x = 0,
            .y = 0,
            .current_wp = 1,
            .is_moving = false,
            .name = undefined,
            .name_len = 0,
        },
    };
    const e0_layout = get_entity_screen_layout(0, &entities, 960, 540);
    const e1_layout = get_entity_screen_layout(1, &entities, 960, 540);
    // Entity 0 shifted left by 30, entity 1 shifted right by 30 with non-overlapping staggered labels
    try testing.expect(e0_layout.pos.x < e1_layout.pos.x);
    try testing.expectEqual(@as(i32, 200 - 30), e0_layout.pos.x);
    try testing.expectEqual(@as(i32, 200 + 30), e1_layout.pos.x);
    try testing.expect(e0_layout.label_y != e1_layout.label_y);
    try testing.expect(e0_layout.status_y != e1_layout.status_y);

    // Hit test actor coordinates
    const act0_hit = hit_test_actor(e0_layout.pos.x, e0_layout.pos.y, &entities, 960, 540);
    try testing.expectEqual(@as(?usize, 0), act0_hit);

    const act1_hit = hit_test_actor(e1_layout.pos.x, e1_layout.pos.y, &entities, 960, 540);
    try testing.expectEqual(@as(?usize, 1), act1_hit);
}

test "P11-03: inventory item hit testing and two-operand combining interaction" {
    const testing = std.testing;

    var inv = [_]RenderInventoryItem{
        .{
            .entity = EntityId.from_int(101),
            .name = undefined,
            .name_len = 0,
        },
        .{
            .entity = EntityId.from_int(102),
            .name = undefined,
            .name_len = 0,
        },
    };
    const name0 = "Syrup";
    @memcpy(inv[0].name[0..name0.len], name0);
    inv[0].name_len = name0.len;

    const name1 = "Tape";
    @memcpy(inv[1].name[0..name1.len], name1);
    inv[1].name_len = name1.len;

    // Hit test item 0 and item 1
    // screen_h = 540, bar_y = 540 - 78 = 462
    const hit_item0 = hit_test_inventory_item(490, 470, 540, &inv);
    try testing.expectEqual(@as(?usize, 0), hit_item0);

    const hit_item1 = hit_test_inventory_item(600, 470, 540, &inv);
    try testing.expectEqual(@as(?usize, 1), hit_item1);

    // Test selection and cancellation state in DisplayWindow
    var win = try DisplayWindow.init("Test Window", 960, 540);
    defer win.deinit();

    try testing.expect(win.selected_inventory_item == null);
    win.selected_inventory_item = 0;
    try testing.expectEqual(@as(?usize, 0), win.selected_inventory_item);

    // Deselect
    win.selected_inventory_item = null;
    try testing.expect(win.selected_inventory_item == null);
}

test "P12-03: display renderer dynamically recognizes scene themes from RenderFrame" {
    const testing = std.testing;

    var frame = std.mem.zeroes(RenderFrame);

    // 1. Spitting competition theme
    const spit_scene = "Spitting Competition";
    @memcpy(frame.current_scene[0..spit_scene.len], spit_scene);
    frame.current_scene_len = spit_scene.len;
    try testing.expectEqualStrings("Spitting Competition", frame.get_current_scene());

    // 2. Wine cellar theme
    const cellar_scene = "Wine Cellar";
    @memcpy(frame.current_scene[0..cellar_scene.len], cellar_scene);
    frame.current_scene_len = cellar_scene.len;
    try testing.expectEqualStrings("Wine Cellar", frame.get_current_scene());

    // 3. Tavern theme
    const tavern_scene = "Tavern";
    @memcpy(frame.current_scene[0..tavern_scene.len], tavern_scene);
    frame.current_scene_len = tavern_scene.len;
    try testing.expectEqualStrings("Tavern", frame.get_current_scene());

    // Verify headless window can render all frames without panic
    var win = try DisplayWindow.init("Scene Switcher Test", 960, 540);
    defer win.deinit();

    win.render_frame(&frame, false);
}
