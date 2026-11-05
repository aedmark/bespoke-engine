const std = @import("std");
const display_mod = @import("../display.zig");
const font = @import("font.zig");

const RenderFrame = display_mod.RenderFrame;
const RenderWaypoint = display_mod.RenderWaypoint;
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

pub const UserAction = union(enum) {
    none,
    quit,
    walk_player: WaypointId,
    toggle_pause,
    step_tick,
    rewind,
};

pub const WAYPOINT_SCREEN_RADIUS = 16;
pub const ACTOR_SCREEN_RADIUS = 18;

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

/// The SDL2 peripheral window consumer (D-001, D-008, P6-01 through P6-04).
pub const DisplayWindow = struct {
    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,
    width: i32,
    height: i32,
    hovered_wp: ?WaypointId = null,
    target_wp: ?WaypointId = null,
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

    /// Polls peripheral input events and returns high-level simulation intents (P6-01, P6-03).
    pub fn poll_events(self: *DisplayWindow, frame: *const RenderFrame) UserAction {
        if (self.is_headless) return .none;

        var event: c.SDL_Event = undefined;
        var action: UserAction = .none;

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => return .quit,
                c.SDL_MOUSEMOTION => {
                    self.hovered_wp = hit_test_waypoint(
                        event.motion.x,
                        event.motion.y,
                        frame.waypoints[0..frame.waypoint_count],
                        self.width,
                        self.height,
                    );
                },
                c.SDL_MOUSEBUTTONDOWN => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        const clicked_wp = hit_test_waypoint(
                            event.button.x,
                            event.button.y,
                            frame.waypoints[0..frame.waypoint_count],
                            self.width,
                            self.height,
                        );
                        if (clicked_wp) |wp_id| {
                            self.target_wp = wp_id;
                            action = .{ .walk_player = wp_id };
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

        // 3. Render Corridors / Edges between Waypoints
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

        // 7. Bottom Controls HUD Bar
        self.fill_rect(0, self.height - 44, self.width, 44, Color.hud_bg);
        self.draw_line(0, self.height - 44, self.width, self.height - 44, Color.tavern_border);
        self.draw_text(
            "[Left Click]: Move Cat | [Space]: Pause | [N]: Step Tick | [R]: Rewind | [Esc]: Quit",
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

        // 9. Present Frame
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
}
