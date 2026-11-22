//! The one drawing surface for the desktop window and the browser (P36-02, D-097).
//!
//! A canvas is an RGBA8888 pixel buffer it does not own, with the drawing calls proof art and
//! the engine's frame use. It imports no SDL, opens no file, and reads no clock, so the same
//! frame drawn on desktop and in the browser is the same bytes. The desktop window uploads the
//! buffer to an SDL texture to show it; the browser hands it to an HTML canvas.
const std = @import("std");
const font = @import("font.zig");
const image = @import("../image.zig");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const stage_bg = Color{ .r = 18, .g = 20, .b = 26 };
    pub const stage_floor = Color{ .r = 34, .g = 38, .b = 48 };
    pub const stage_border = Color{ .r = 61, .g = 46, .b = 39 };
    pub const panel_border = Color{ .r = 61, .g = 46, .b = 39 };
    pub const path_corridor = Color{ .r = 55, .g = 48, .b = 43 };
    pub const path_edge = Color{ .r = 75, .g = 68, .b = 60 };

    pub const wp_normal = Color{ .r = 100, .g = 116, .b = 139 };
    pub const wp_hover = Color{ .r = 251, .g = 191, .b = 36 };
    pub const wp_target = Color{ .r = 56, .g = 189, .b = 248 };

    pub const item_gold = Color{ .r = 250, .g = 204, .b = 21 };

    pub const vortex_purple = Color{ .r = 147, .g = 51, .b = 234 };
    pub const countdown_warn = Color{ .r = 239, .g = 68, .b = 68 };

    pub const hud_bg = Color{ .r = 15, .g = 23, .b = 42, .a = 230 };
    pub const hud_text = Color{ .r = 248, .g = 250, .b = 252 };
    pub const hud_subtext = Color{ .r = 148, .g = 163, .b = 184 };
    pub const status_running = Color{ .r = 34, .g = 197, .b = 94 };
    pub const status_paused = Color{ .r = 245, .g = 158, .b = 11 };
    pub const cue_alert = Color{ .r = 244, .g = 63, .b = 94 };

    // The browser runtime's names (D-022), kept while its own overlays still use them.
    pub const hud_bg_solid = Color{ .r = 15, .g = 23, .b = 42 };
    pub const hud_border = Color{ .r = 71, .g = 85, .b = 105 };
    pub const gold = Color{ .r = 250, .g = 204, .b = 21 };
    pub const sky_blue = Color{ .r = 56, .g = 189, .b = 248 };
    pub const emerald = Color{ .r = 34, .g = 197, .b = 94 };
    pub const crimson = Color{ .r = 244, .g = 63, .b = 94 };
    pub const amber = Color{ .r = 245, .g = 158, .b = 11 };
    pub const slate = Color{ .r = 148, .g = 163, .b = 184 };
};

/// Where one string was drawn, how much room it took, and the layer it belongs to, as
/// `draw_text` lays it out. The string's start is kept so a failing check can name it.
pub const TextDraw = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    /// The layer drawn on, so the band check can tell the stage's strings from the window's
    /// own log, bars, and panels (D-127, P43-05).
    kind: RectKind = .prop,
    text: [48]u8 = undefined,
    text_len: usize = 0,

    pub fn get_text(self: *const TextDraw) []const u8 {
        return self.text[0..self.text_len];
    }
};

/// Collects the strings a canvas draws, so a test can prove that no proof text, a room name,
/// a sign, or a prompt, reaches into the message band (D-124). Each draw records the layer it
/// was made on. A canvas records only while a probe is lent to it; drawing is otherwise
/// unchanged.
pub const TextProbe = struct {
    pub const cap = 256;
    draws: [cap]TextDraw = undefined,
    count: usize = 0,

    pub fn record(self: *TextProbe, kind: RectKind, text: []const u8, x: i32, y: i32, scale: i32) void {
        if (self.count == cap) return;
        var draw = TextDraw{
            .x = x,
            .y = y,
            .w = font.text_width(text, scale),
            .h = font.FONT_HEIGHT * scale,
            .kind = kind,
        };
        draw.text_len = @min(text.len, draw.text.len);
        @memcpy(draw.text[0..draw.text_len], text[0..draw.text_len]);
        self.draws[self.count] = draw;
        self.count += 1;
    }
};

/// What a rectangle belongs to. `.prop` is the proof art the band check measures; `.mark`,
/// `.actor`, and `.walkway` are the engine's own stage furniture, `.backdrop` is the scenery
/// D-124 lets extend behind the log, and `.chrome` and `.overlay` are the window's panels,
/// bars, and drawers, which the check skips by kind.
pub const RectKind = enum { backdrop, prop, actor, mark, walkway, chrome, overlay };

/// One rectangle or sprite a canvas drew, with the kind of layer it belongs to and the name of
/// the thing drawn when the renderer knows it.
pub const RectDraw = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    kind: RectKind,
    name: [32]u8 = undefined,
    name_len: usize = 0,

    pub fn get_name(self: *const RectDraw) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// Collects the rectangles and sprites a canvas draws, so the proof render test measures the
/// art a frame really paints rather than a marker's nominal size (P43-02). Text is not recorded
/// here: `TextProbe` covers it, and a glyph's dots would swamp this probe. A canvas records only
/// while a probe is lent to it; drawing is otherwise unchanged.
pub const RectProbe = struct {
    pub const cap = 2048;
    draws: [cap]RectDraw = undefined,
    count: usize = 0,
    /// Set when more rectangles were drawn than the probe holds, so a check fails rather than
    /// silently measuring a partial frame.
    overflowed: bool = false,

    pub fn record(self: *RectProbe, kind: RectKind, name: []const u8, x: i32, y: i32, w: i32, h: i32) void {
        if (w <= 0 or h <= 0) return;
        if (self.count == cap) {
            self.overflowed = true;
            return;
        }
        var draw = RectDraw{ .x = x, .y = y, .w = w, .h = h, .kind = kind };
        draw.name_len = @min(name.len, draw.name.len);
        @memcpy(draw.name[0..draw.name_len], name[0..draw.name_len]);
        self.draws[self.count] = draw;
        self.count += 1;
    }
};

pub const Canvas = struct {
    /// `width * height * 4` bytes, row by row, R G B A. Borrowed: the owner keeps it alive.
    pixels: []u8,
    width: i32,
    height: i32,
    /// When set, every string drawn is also recorded in the probe (D-124).
    text_probe: ?*TextProbe = null,
    /// When set, every rectangle, line, circle, and sprite drawn is recorded (P43-02).
    rect_probe: ?*RectProbe = null,
    /// The layer the next draws belong to, and the name of the thing being drawn.
    rect_kind: RectKind = .walkway,
    rect_name: []const u8 = "",
    /// Suppresses recording for text glyphs and full-canvas clears, which are not art.
    text_depth: u8 = 0,
    suppress_rects: u8 = 0,

    pub fn init(pixels: []u8, width: i32, height: i32) Canvas {
        std.debug.assert(pixels.len >= @as(usize, @intCast(width * height * 4)));
        return .{ .pixels = pixels, .width = width, .height = height };
    }

    pub fn clear(self: *Canvas, col: Color) void {
        self.suppress_rects += 1;
        defer self.suppress_rects -= 1;
        self.fill_rect(0, 0, self.width, self.height, .{ .r = col.r, .g = col.g, .b = col.b, .a = col.a });
    }

    inline fn note_rect(self: *Canvas, x: i32, y: i32, w: i32, h: i32) void {
        if (self.text_depth != 0 or self.suppress_rects != 0) return;
        if (self.rect_probe) |probe| probe.record(self.rect_kind, self.rect_name, x, y, w, h);
    }

    /// Writes one pixel, blending a translucent colour over what is there as SDL's
    /// `SDL_BLENDMODE_BLEND` does (D-097): `dst = src * a + dst * (1 - a)`, and the alpha
    /// `a + dst_a * (1 - a)`. An opaque colour replaces the pixel. Off-canvas writes are dropped,
    /// so callers may draw shapes that cross the edge.
    pub inline fn set_pixel(self: *Canvas, x: i32, y: i32, col: Color) void {
        if (x < 0 or x >= self.width or y < 0 or y >= self.height) return;
        const idx: usize = @intCast((y * self.width + x) * 4);
        const px = self.pixels[idx..][0..4];
        if (col.a == 255) {
            px.* = .{ col.r, col.g, col.b, 255 };
            return;
        }
        if (col.a == 0) return;
        const a: u32 = col.a;
        const inv: u32 = 255 - a;
        px[0] = blend(col.r, px[0], a, inv);
        px[1] = blend(col.g, px[1], a, inv);
        px[2] = blend(col.b, px[2], a, inv);
        px[3] = @intCast(a + (@as(u32, px[3]) * inv + 127) / 255);
    }

    inline fn blend(src: u8, dst: u8, a: u32, inv: u32) u8 {
        return @intCast((@as(u32, src) * a + @as(u32, dst) * inv + 127) / 255);
    }

    pub fn get_pixel(self: *const Canvas, x: i32, y: i32) Color {
        if (x < 0 or x >= self.width or y < 0 or y >= self.height) return Color.black;
        const idx: usize = @intCast((y * self.width + x) * 4);
        return .{ .r = self.pixels[idx], .g = self.pixels[idx + 1], .b = self.pixels[idx + 2], .a = self.pixels[idx + 3] };
    }

    pub fn fill_rect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, col: Color) void {
        const x0 = @max(0, x);
        const y0 = @max(0, y);
        const x1 = @min(self.width, x + w);
        const y1 = @min(self.height, y + h);
        if (x0 >= x1 or y0 >= y1) return;
        self.note_rect(x0, y0, x1 - x0, y1 - y0);
        if (col.a == 255) {
            // Opaque rows are a repeated 4-byte pattern: write the first pixel, then double the
            // copied span, which keeps a full-canvas clear fast in a Debug build.
            var py = y0;
            while (py < y1) : (py += 1) {
                const start: usize = @intCast((py * self.width + x0) * 4);
                const len: usize = @intCast((x1 - x0) * 4);
                const row = self.pixels[start..][0..len];
                row[0..4].* = .{ col.r, col.g, col.b, 255 };
                var filled: usize = 4;
                while (filled < len) {
                    const n = @min(filled, len - filled);
                    @memcpy(row[filled..][0..n], row[0..n]);
                    filled += n;
                }
            }
            return;
        }
        var py = y0;
        while (py < y1) : (py += 1) {
            var px = x0;
            while (px < x1) : (px += 1) self.set_pixel(px, py, col);
        }
    }

    pub fn draw_rect_outline(self: *Canvas, x: i32, y: i32, w: i32, h: i32, col: Color) void {
        if (w <= 0 or h <= 0) return;
        self.draw_line(x, y, x + w - 1, y, col);
        self.draw_line(x, y + h - 1, x + w - 1, y + h - 1, col);
        self.draw_line(x, y, x, y + h - 1, col);
        self.draw_line(x + w - 1, y, x + w - 1, y + h - 1, col);
    }

    pub fn draw_point(self: *Canvas, x: i32, y: i32, col: Color) void {
        self.set_pixel(x, y, col);
    }

    /// Bresenham's line, both ends included.
    pub fn draw_line(self: *Canvas, x0_in: i32, y0_in: i32, x1: i32, y1: i32, col: Color) void {
        var x0 = x0_in;
        var y0 = y0_in;
        self.note_rect(@min(x0, x1), @min(y0, y1), @intCast(@abs(x1 - x0) + 1), @intCast(@abs(y1 - y0) + 1));
        const dx: i32 = @intCast(@abs(x1 - x0));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err: i32 = dx + dy;
        while (true) {
            self.set_pixel(x0, y0, col);
            if (x0 == x1 and y0 == y1) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                x0 += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    /// A filled disc drawn as one horizontal span per row, so a translucent colour covers each
    /// pixel once.
    pub fn fill_circle(self: *Canvas, cx: i32, cy: i32, radius: i32, col: Color) void {
        if (radius <= 0) return;
        self.note_rect(cx - radius, cy - radius, radius * 2 + 1, radius * 2 + 1);
        var dy: i32 = -radius;
        while (dy <= radius) : (dy += 1) {
            const dx: i32 = @intCast(std.math.sqrt(@as(u64, @intCast(@max(0, radius * radius - dy * dy)))));
            var px = cx - dx;
            while (px <= cx + dx) : (px += 1) self.set_pixel(px, cy + dy, col);
        }
    }

    /// The midpoint circle, eight octants per step.
    pub fn draw_circle_outline(self: *Canvas, cx: i32, cy: i32, radius: i32, col: Color) void {
        if (radius <= 0) return;
        self.note_rect(cx - radius, cy - radius, radius * 2 + 1, radius * 2 + 1);
        var x: i32 = radius;
        var y: i32 = 0;
        var err: i32 = 0;
        while (x >= y) {
            self.set_pixel(cx + x, cy + y, col);
            self.set_pixel(cx + y, cy + x, col);
            self.set_pixel(cx - y, cy + x, col);
            self.set_pixel(cx - x, cy + y, col);
            self.set_pixel(cx - x, cy - y, col);
            self.set_pixel(cx - y, cy - x, col);
            self.set_pixel(cx + y, cy - x, col);
            self.set_pixel(cx + x, cy - y, col);
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

    /// Text in the 5x7 font, each lit dot a `scale`-sized square.
    pub fn draw_text(self: *Canvas, text: []const u8, start_x: i32, start_y: i32, scale: i32, col: Color) void {
        if (self.text_probe) |probe| probe.record(self.rect_kind, text, start_x, start_y, scale);
        self.text_depth += 1;
        defer self.text_depth -= 1;
        var cur_x = start_x;
        for (text) |byte| {
            // UTF-8 (D-179): a continuation byte belongs to the character before it, and a
            // character the font lacks draws as one placeholder until a wider font lands (P48-21).
            if (byte >= 0x80 and byte & 0xC0 == 0x80) continue;
            const ch: u8 = if (byte >= 0x80) font.PLACEHOLDER else byte;
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

    /// Draws one frame of an indexed image with its top-left corner at (x, y) in frame pixels
    /// (P46-02, D-152). Each art pixel is an `image.SCALE`-square block of its palette colour;
    /// index 0 leaves the canvas as it was. Palette colours are opaque, so a block replaces what
    /// is under it and no blending is needed. Blocks that cross the edge are clipped.
    ///
    /// The probe records one rectangle per call: the frame's opaque bounds on screen, under the
    /// current layer and the caller's `rect_name` (the image's name when none is set). A sprite
    /// with transparent margins is measured by the pixels it paints, so the band check reads
    /// image art the way it reads drawn props (P43-02).
    ///
    /// `img` must be valid against `palette` (`image.Art.validate`), as every image from a
    /// package is; `frame` must be below `img.frame_count()`.
    pub fn draw_image(self: *Canvas, palette: []const image.Colour, img: *const image.Image, frame: u32, x: i32, y: i32) void {
        std.debug.assert(frame < img.frame_count());
        const s: i32 = image.SCALE;
        const fw: i32 = img.frame_width;
        const fh: i32 = img.frame_height;
        // The art rows and columns that land on the canvas, so a sprite mostly off screen costs
        // only its visible part.
        const ax0: i32 = @max(0, -@divFloor(x, s) - 1);
        const ay0: i32 = @max(0, -@divFloor(y, s) - 1);
        const ax1: i32 = @min(fw, @divFloor(self.width - x, s) + 1);
        const ay1: i32 = @min(fh, @divFloor(self.height - y, s) + 1);
        var min_x: i32 = fw;
        var min_y: i32 = fh;
        var max_x: i32 = -1;
        var max_y: i32 = -1;
        var ay = ay0;
        while (ay < ay1) : (ay += 1) {
            const py0 = @max(0, y + ay * s);
            const py1 = @min(self.height, y + ay * s + s);
            if (py0 >= py1) continue;
            var ax = ax0;
            while (ax < ax1) : (ax += 1) {
                const index = img.frame_pixel(frame, @intCast(ax), @intCast(ay));
                if (index == image.TRANSPARENT) continue;
                const px0 = @max(0, x + ax * s);
                const px1 = @min(self.width, x + ax * s + s);
                if (px0 >= px1) continue;
                std.debug.assert(index < palette.len);
                const c = palette[index];
                min_x = @min(min_x, ax);
                max_x = @max(max_x, ax);
                min_y = @min(min_y, ay);
                max_y = @max(max_y, ay);
                var py = py0;
                while (py < py1) : (py += 1) {
                    var px = px0;
                    while (px < px1) : (px += 1) {
                        const idx: usize = @intCast((py * self.width + px) * 4);
                        self.pixels[idx..][0..4].* = .{ c.r, c.g, c.b, 255 };
                    }
                }
            }
        }
        if (max_x < 0) return;
        const left = @max(0, x + min_x * s);
        const top = @max(0, y + min_y * s);
        const right = @min(self.width, x + (max_x + 1) * s);
        const bottom = @min(self.height, y + (max_y + 1) * s);
        const name = self.rect_name;
        if (name.len == 0) self.rect_name = img.name;
        defer self.rect_name = name;
        self.note_rect(left, top, right - left, bottom - top);
    }

    /// Hash of the drawn pixels, for goldens that compare frames.
    pub fn hash(self: *const Canvas) u64 {
        const len: usize = @intCast(self.width * self.height * 4);
        return std.hash.Wyhash.hash(0, self.pixels[0..len]);
    }
};

const testing = std.testing;

test "P36-02: the canvas clips at its edges and draws each primitive where asked" {
    var buf: [16 * 8 * 4]u8 = undefined;
    var cv = Canvas.init(&buf, 16, 8);
    cv.clear(Color.black);
    cv.fill_rect(-4, -4, 6, 6, Color.white);
    try testing.expectEqual(Color.white, cv.get_pixel(0, 0));
    try testing.expectEqual(Color.white, cv.get_pixel(1, 1));
    try testing.expectEqual(Color.black, cv.get_pixel(2, 2));
    cv.fill_rect(14, 6, 10, 10, Color.gold);
    try testing.expectEqual(Color.gold, cv.get_pixel(15, 7));
    cv.draw_line(0, 7, 15, 7, Color.sky_blue);
    try testing.expectEqual(Color.sky_blue, cv.get_pixel(8, 7));
    cv.draw_rect_outline(4, 1, 5, 4, Color.crimson);
    try testing.expectEqual(Color.crimson, cv.get_pixel(4, 1));
    try testing.expectEqual(Color.crimson, cv.get_pixel(8, 4));
    try testing.expectEqual(Color.black, cv.get_pixel(6, 2));
    cv.clear(Color.black);
    cv.fill_circle(8, 4, 3, Color.emerald);
    try testing.expectEqual(Color.emerald, cv.get_pixel(8, 4));
    try testing.expectEqual(Color.emerald, cv.get_pixel(11, 4));
    try testing.expectEqual(Color.black, cv.get_pixel(11, 1));
    cv.draw_circle_outline(8, 4, 3, Color.amber);
    try testing.expectEqual(Color.amber, cv.get_pixel(8, 1));
    try testing.expectEqual(Color.emerald, cv.get_pixel(8, 4));
    // Shapes wholly off the canvas draw nothing and do not fault.
    cv.fill_circle(-50, -50, 10, Color.white);
    cv.draw_line(-10, -10, -1, -20, Color.white);
    cv.draw_text("A", 100, 100, 2, Color.white);
}

test "P43-02: the rect probe records shapes with their layer, skips text and clears, and flags overflow" {
    var buf: [16 * 8 * 4]u8 = undefined;
    var cv = Canvas.init(&buf, 16, 8);
    var probe = RectProbe{};
    cv.rect_probe = &probe;

    // A full-canvas clear is background, not art.
    cv.clear(Color.black);
    try testing.expectEqual(@as(usize, 0), probe.count);

    cv.rect_kind = .prop;
    cv.rect_name = "Cask";
    cv.fill_rect(2, 1, 6, 4, Color.gold);
    try testing.expectEqual(@as(usize, 1), probe.count);
    try testing.expectEqual(RectKind.prop, probe.draws[0].kind);
    try testing.expectEqualStrings("Cask", probe.draws[0].get_name());
    try testing.expectEqual(@as(i32, 2), probe.draws[0].x);
    try testing.expectEqual(@as(i32, 4), probe.draws[0].h);

    // Glyph dots are text, which the text probe covers, not art rectangles.
    cv.draw_text("A", 0, 0, 1, Color.white);
    try testing.expectEqual(@as(usize, 1), probe.count);

    // Text records the layer it was drawn on, so the band check can tell the stage's strings
    // from the window's own log, bars, and panel (D-127, P43-05).
    var text_probe = TextProbe{};
    cv.text_probe = &text_probe;
    cv.rect_kind = .mark;
    cv.draw_text("Stage", 0, 0, 1, Color.white);
    cv.rect_kind = .chrome;
    cv.draw_text("Panel", 0, 0, 1, Color.white);
    try testing.expectEqual(@as(usize, 2), text_probe.count);
    try testing.expectEqual(RectKind.mark, text_probe.draws[0].kind);
    try testing.expectEqual(RectKind.chrome, text_probe.draws[1].kind);
    try testing.expectEqualStrings("Panel", text_probe.draws[1].get_text());
    cv.text_probe = null;
    cv.rect_kind = .prop;

    cv.rect_kind = .chrome;
    cv.fill_circle(8, 4, 3, Color.amber);
    try testing.expectEqual(@as(usize, 2), probe.count);
    try testing.expectEqual(RectKind.chrome, probe.draws[1].kind);
    try testing.expectEqual(@as(i32, 7), probe.draws[1].h);

    cv.rect_kind = .backdrop;
    cv.draw_line(0, 7, 15, 7, Color.white);
    try testing.expectEqual(@as(usize, 3), probe.count);

    // A shape wholly off the canvas draws nothing and records nothing.
    cv.rect_kind = .prop;
    cv.fill_rect(-10, -10, 4, 4, Color.white);
    try testing.expectEqual(@as(usize, 3), probe.count);

    // A frame the probe cannot hold is flagged, not silently cut short.
    var small = RectProbe{};
    small.count = RectProbe.cap;
    small.record(.prop, "Late", 0, 0, 4, 4);
    try testing.expect(small.overflowed);
}

test "P36-02: a translucent colour blends as SDL's blend mode does, and text is drawn in the 5x7 font" {
    var buf: [8 * 8 * 4]u8 = undefined;
    var cv = Canvas.init(&buf, 8, 8);
    cv.clear(Color.black);
    cv.set_pixel(0, 0, .{ .r = 255, .g = 0, .b = 100, .a = 128 });
    const p = cv.get_pixel(0, 0);
    try testing.expectEqual(@as(u8, 128), p.r);
    try testing.expectEqual(@as(u8, 0), p.g);
    try testing.expectEqual(@as(u8, 50), p.b);
    try testing.expectEqual(@as(u8, 255), p.a);
    cv.set_pixel(1, 0, .{ .r = 255, .g = 255, .b = 255, .a = 0 });
    try testing.expectEqual(Color.black, cv.get_pixel(1, 0));
    cv.clear(Color.black);
    cv.draw_text("I", 0, 0, 1, Color.white);
    var lit: usize = 0;
    var y: i32 = 0;
    while (y < 7) : (y += 1) {
        var x: i32 = 0;
        while (x < 5) : (x += 1) {
            if (cv.get_pixel(x, y).r == 255) lit += 1;
        }
    }
    try testing.expect(lit > 4);
}

test "P46-02: an image frame draws each art pixel as a 4x4 block and leaves index 0 alone" {
    const palette = [_]image.Colour{ .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 200, .g = 10, .b = 20 }, .{ .r = 5, .g = 6, .b = 7 } };
    // Two 2x2 frames side by side; the second is red with one transparent corner.
    const pixels = [_]u8{ 2, 2, 0, 1, 2, 2, 1, 1 };
    const sheet = image.Image{ .name = "Tile", .width = 4, .height = 2, .frame_width = 2, .frame_height = 2, .pixels = &pixels };
    try sheet.validate(palette.len);
    var buf: [16 * 16 * 4]u8 = undefined;
    var cv = Canvas.init(&buf, 16, 16);
    cv.clear(Color.white);
    cv.draw_image(&palette, &sheet, 1, 4, 4);
    const red = Color{ .r = 200, .g = 10, .b = 20 };
    // The transparent corner (art 0,0) covers frame pixels 4..7 and shows the white beneath.
    try testing.expectEqual(Color.white, cv.get_pixel(4, 4));
    try testing.expectEqual(Color.white, cv.get_pixel(7, 7));
    try testing.expectEqual(red, cv.get_pixel(8, 4));
    try testing.expectEqual(red, cv.get_pixel(11, 7));
    try testing.expectEqual(red, cv.get_pixel(4, 8));
    try testing.expectEqual(red, cv.get_pixel(11, 11));
    try testing.expectEqual(Color.white, cv.get_pixel(12, 12));
    try testing.expectEqual(Color.white, cv.get_pixel(3, 3));
}

test "P46-02: an image clips at the canvas edge and the probe records its opaque bounds" {
    const palette = [_]image.Colour{ .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 9, .g = 9, .b = 9 } };
    // A 4x4 frame whose only opaque pixels are the middle two of its third row.
    const pixels = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0 };
    const sprite = image.Image{ .name = "Ledge", .width = 4, .height = 4, .frame_width = 4, .frame_height = 4, .pixels = &pixels };
    var buf: [16 * 16 * 4]u8 = undefined;
    var cv = Canvas.init(&buf, 16, 16);
    var probe = RectProbe{};
    cv.rect_probe = &probe;
    cv.clear(Color.black);
    cv.rect_kind = .prop;
    cv.draw_image(&palette, &sprite, 0, 0, 0);
    try testing.expectEqual(@as(usize, 1), probe.count);
    const d = probe.draws[0];
    try testing.expectEqualStrings("Ledge", d.get_name());
    try testing.expectEqual(RectKind.prop, d.kind);
    try testing.expectEqual(@as(i32, 4), d.x);
    try testing.expectEqual(@as(i32, 8), d.y);
    try testing.expectEqual(@as(i32, 8), d.w);
    try testing.expectEqual(@as(i32, 4), d.h);

    // Hanging off the right and bottom edges: only the visible part is painted and recorded,
    // under the caller's name when it set one.
    probe.count = 0;
    cv.rect_name = "Cliff";
    cv.draw_image(&palette, &sprite, 0, 10, 6);
    try testing.expectEqual(@as(usize, 1), probe.count);
    try testing.expectEqualStrings("Cliff", probe.draws[0].get_name());
    try testing.expectEqual(@as(i32, 14), probe.draws[0].x);
    try testing.expectEqual(@as(i32, 2), probe.draws[0].w);
    try testing.expectEqual(Color{ .r = 9, .g = 9, .b = 9, .a = 255 }, cv.get_pixel(15, 15));
    try testing.expectEqualStrings("Cliff", cv.rect_name);

    // Wholly off the canvas, or wholly transparent where it lands: nothing is recorded.
    probe.count = 0;
    cv.draw_image(&palette, &sprite, 0, -40, -40);
    cv.draw_image(&palette, &sprite, 0, 0, -12);
    try testing.expectEqual(@as(usize, 0), probe.count);
}
