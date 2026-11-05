const std = @import("std");
const display_mod = @import("../display.zig");
const font = @import("font.zig");

const RenderFrame = display_mod.RenderFrame;
const RenderWaypoint = display_mod.RenderWaypoint;
const RenderHotspot = display_mod.RenderHotspot;
const RenderEntity = display_mod.RenderEntity;
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

/// Hit-tests screen coordinates against visible actors (P7-02).
pub fn hit_test_actor(
    screen_x: i32,
    screen_y: i32,
    entities: []const RenderEntity,
    screen_w: i32,
    screen_h: i32,
) ?usize {
    for (entities, 0..) |e, idx| {
        const pt = world_to_screen(e.x, e.y, screen_w, screen_h);
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
                        // Right-click cycles the active adventure verb (P7-02, D-009)
                        self.active_verb = self.active_verb.next();
                    } else if (event.button.button == c.SDL_BUTTON_LEFT) {
                        // 1. Check Verb Bar buttons
                        const clicked_verb = hit_test_verb_button(event.button.x, event.button.y, self.height);
                        if (clicked_verb) |verb| {
                            self.active_verb = verb;
                            return .none;
                        }

                        // 2. Check Actors
                        const clicked_actor = hit_test_actor(
                            event.button.x,
                            event.button.y,
                            frame.entities[0..frame.entity_count],
                            self.width,
                            self.height,
                        );
                        if (clicked_actor) |actor_idx| {
                            action = .{ .interact_actor = .{ .verb = self.active_verb, .actor_index = actor_idx } };
                        } else {
                            // 3. Check Hotspots / Props
                            const clicked_hs = hit_test_hotspot(
                                event.button.x,
                                event.button.y,
                                frame.hotspots[0..frame.hotspot_count],
                                self.width,
                                self.height,
                            );
                            if (clicked_hs) |hs_idx| {
                                action = .{ .interact_hotspot = .{ .verb = self.active_verb, .hotspot_index = hs_idx } };
                            } else {
                                // 4. Check Waypoints
                                const clicked_wp = hit_test_waypoint(
                                    event.button.x,
                                    event.button.y,
                                    frame.waypoints[0..frame.waypoint_count],
                                    self.width,
                                    self.height,
                                );
                                if (clicked_wp) |wp_id| {
                                    if (self.active_verb == .walk) {
                                        self.target_wp = wp_id;
                                        action = .{ .walk_player = wp_id };
                                    }
                                }
                            }
                        }
                    }
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_SPACE => action = .toggle_pause,
                        c.SDLK_n => action = .step_tick,
                        c.SDLK_r => action = .rewind,
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

        // 1. Clear background
        self.fill_rect(0, 0, self.width, self.height, Color.tavern_bg);

        // 2. Render Rooms (Tavern Hall & Wine Cellar)
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

            // Waypoint anchor body
            const body_color = if (is_hovered) Color.wp_hover else Color.wp_normal;
            self.fill_circle(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, body_color);
            self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.white);
            self.fill_circle(pt.x, pt.y, 4, Color.white);

            // Waypoint text label
            const name = wp.get_name();
            const text_w = font.text_width(name, 2);
            self.draw_text(name, pt.x - @divTrunc(text_w, 2), pt.y + WAYPOINT_SCREEN_RADIUS + 8, 2, Color.hud_text);
        }

        // 5. Render Actors
        for (frame.entities[0..frame.entity_count]) |e| {
            const name = e.get_name();
            const pt = world_to_screen(e.x, e.y, self.width, self.height);

            if (std.mem.eql(u8, name, "Cat")) {
                // Cat (Player): Orange token with cat ears
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.cat_color);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Ears
                self.fill_rect(pt.x - 12, pt.y - ACTOR_SCREEN_RADIUS - 4, 6, 6, Color.cat_color);
                self.fill_rect(pt.x + 6, pt.y - ACTOR_SCREEN_RADIUS - 4, 6, 6, Color.cat_color);

                // Label
                self.draw_text("Cat (Player)", pt.x - 36, pt.y - ACTOR_SCREEN_RADIUS - 16, 2, Color.cat_color);

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
                self.draw_text("Guard", pt.x - 16, pt.y - ACTOR_SCREEN_RADIUS - 16, 2, Color.guard_color);

                // Carried Cheese
                if (frame.cheese_holder == e.entity) {
                    self.fill_circle(pt.x + 14, pt.y - 10, 8, Color.cheese_color);
                    self.draw_circle_outline(pt.x + 14, pt.y - 10, 8, Color.white);
                    self.draw_text("Cheese", pt.x + 24, pt.y - 14, 2, Color.cheese_color);
                }

                // Charmed status
                if (frame.charmed_target == e.entity) {
                    self.draw_text("[Charmed!]", pt.x - 28, pt.y + ACTOR_SCREEN_RADIUS + 4, 2, Color.cue_alert);
                }
            } else if (std.mem.eql(u8, name, "Bard")) {
                // Bard: Purple token
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.bard_color);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Feather cap / lute indicator
                self.fill_rect(pt.x - 2, pt.y - ACTOR_SCREEN_RADIUS - 6, 4, 8, Color.white);

                // Label
                self.draw_text("Bard", pt.x - 12, pt.y - ACTOR_SCREEN_RADIUS - 16, 2, Color.bard_color);
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

        // Inventory Tray (P7-03)
        self.draw_text("ITEMS:", 400, bar_y + 6, 2, Color.hud_subtext);
        var item_x: i32 = 480;
        if (frame.inventory_count == 0) {
            self.draw_text("(Empty)", item_x, bar_y + 6, 2, Color{ .r = 100, .g = 116, .b = 139 });
        } else {
            for (frame.inventory[0..frame.inventory_count]) |item| {
                const iname = item.get_name();
                const iw = font.text_width(iname, 2) + 24;
                self.fill_rect(item_x, bar_y, iw, 26, Color{ .r = 45, .g = 35, .b = 20 });
                self.draw_rect_outline(item_x, bar_y, iw, 26, Color.cheese_color);
                self.fill_circle(item_x + 10, bar_y + 13, 5, Color.cheese_color);
                self.draw_text(iname, item_x + 18, bar_y + 6, 2, Color.cheese_color);
                item_x += iw + 8;
            }
        }

        // 8. Bottom Controls HUD Bar
        self.fill_rect(0, self.height - 44, self.width, 44, Color.hud_bg);
        self.draw_line(0, self.height - 44, self.width, self.height - 44, Color.tavern_border);
        self.draw_text(
            "[Left Click]: Perform Action | [Right Click]: Cycle Verb | [Space]: Pause | [R]: Rewind",
            20,
            self.height - 28,
            2,
            Color.hud_subtext,
        );

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

        // 10. Present Frame
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
}
