//! The image stage (P46-02, P46-03): one small room drawn entirely from indexed pixel art that
//! its own script declares (D-152, D-155). It is a test fixture, not a playable proof: the
//! render golden and the browser deck golden hash its frames, and its walking lamplighter is
//! the animated replay P46-03 asks for.
//!
//! The backdrop is a lamp room at night: a plastered wall with a moonlit window over a plank
//! floor. The lantern is a two-frame sheet (dark, then lit) that idles mostly lit with a short
//! gutter. The lamplighter has two idle frames and a two-frame walk each way; walking up or
//! down falls back to idle, which the fallback rule covers.
//!
//! The pixels are generated here at compile time and written into the script as palette-code
//! rows, exactly as an author would type them, so the script is the art's only source. PNG
//! import (P46-04) will let an author keep art in files instead.
const std = @import("std");
const image = @import("bespoke").image;

pub const SCENE = "Lamp Room";

/// Palette codes and colours, index 0 first. The script's `palette:` block is written from this.
const Entry = struct { code: u8, rgb: ?[3]u8 };
const PALETTE = [_]Entry{
    .{ .code = '.', .rgb = null },
    .{ .code = 'n', .rgb = .{ 22, 24, 40 } }, // night
    .{ .code = 'm', .rgb = .{ 70, 78, 110 } }, // moonlight
    .{ .code = 'w', .rgb = .{ 92, 74, 66 } }, // wall
    .{ .code = 'f', .rgb = .{ 66, 48, 38 } }, // floor
    .{ .code = 's', .rgb = .{ 40, 28, 24 } }, // frame and seams
    .{ .code = 'o', .rgb = .{ 160, 170, 196 } }, // moon
    .{ .code = 'b', .rgb = .{ 176, 128, 56 } }, // brass
    .{ .code = 'l', .rgb = .{ 250, 214, 96 } }, // flame
    .{ .code = 'g', .rgb = .{ 54, 58, 64 } }, // cold glass
    .{ .code = 'k', .rgb = .{ 222, 176, 140 } }, // skin
    .{ .code = 'c', .rgb = .{ 52, 86, 74 } }, // coat
    .{ .code = 'h', .rgb = .{ 112, 66, 40 } }, // hair
    .{ .code = 'd', .rgb = .{ 30, 26, 30 } }, // boots
};

fn idx(comptime code: u8) u8 {
    inline for (PALETTE, 0..) |e, i| if (e.code == code) return i;
    @compileError("no palette code");
}

const FLOOR_TOP = 104;

fn backdrop_pixel(x: usize, y: usize, frame: usize) u8 {
    _ = frame;
    if (y >= FLOOR_TOP) {
        // Planks with a seam every twelve rows, offset joints every forty columns.
        if ((y - FLOOR_TOP) % 12 == 0) return idx('s');
        const course = (y - FLOOR_TOP) / 12;
        if ((x + course * 20) % 40 == 0) return idx('s');
        return idx('f');
    }
    if (y == FLOOR_TOP - 1) return idx('s'); // skirting
    // The window: a dark frame round four panes of night, with the moon in the top right pane.
    if (x >= 200 and x < 248 and y >= 24 and y < 72) {
        if (x < 202 or x >= 246 or y < 26 or y >= 70 or x == 223 or x == 224 or y == 47 or y == 48) return idx('s');
        const dx: i32 = @as(i32, @intCast(x)) - 234;
        const dy: i32 = @as(i32, @intCast(y)) - 36;
        if (dx * dx + dy * dy <= 25) return idx('o');
        return if (y > 60) idx('m') else idx('n');
    }
    return idx('w');
}

const LANTERN_W = 12;
const LANTERN_H = 20;

/// One lantern frame: a ring, a cap, a glass body, and a base. Frame 1 is lit.
fn lantern_pixel(x: usize, y: usize, frame: usize) u8 {
    const lit = frame == 1;
    if (y < 3) return if ((x == 5 or x == 6) and y != 1) idx('b') else if ((x == 4 or x == 7) and y == 1) idx('b') else 0;
    if (y < 5) return if (x >= 3 and x < 9) idx('b') else 0;
    if (y < 16) {
        if (x == 2 or x == 9) return idx('b');
        if (x > 2 and x < 9) {
            if (!lit) return idx('g');
            return if (y >= 8 and y < 14 and x >= 4 and x < 8) idx('l') else idx('m');
        }
        return 0;
    }
    if (y < 18) return if (x >= 1 and x < 11) idx('b') else 0;
    return if (x >= 2 and x < 10) idx('s') else 0;
}

const FIGURE_W = 12;
const FIGURE_H = 24;
const FIGURE_FRAMES = 6;

/// The lamplighter, 12x24: frames 0 and 1 idle (1 breathes in), 2 and 3 walk right, 4 and 5
/// walk left. A left frame is its right frame mirrored.
fn figure_pixel(x_in: usize, y: usize, frame: usize) u8 {
    const left = frame >= 4;
    const x = if (left) FIGURE_W - 1 - x_in else x_in;
    const stride = frame == 2 or frame == 4;
    const lift: usize = if (frame == 1) 1 else 0;
    const facing = frame >= 2;
    // Hair and head, one row lower while breathing in.
    if (y >= 1 + lift and y < 3 + lift) return if (x >= 4 and x < 9) idx('h') else 0;
    if (y >= 3 + lift and y < 7 + lift) {
        if (x < 4 or x >= 9) return 0;
        if (facing and x == 8 and y == 4 + lift) return idx('d'); // an eye toward the walk
        return idx('k');
    }
    // Coat, with the arm swinging on a stride.
    if (y >= 7 and y < 17) {
        if (x >= 3 and x < 10) return idx('c');
        if (stride and x == 10 and y >= 9 and y < 14) return idx('c');
        if (!stride and x == 2 and y >= 9 and y < 14) return idx('c');
        return 0;
    }
    // Legs and boots: apart on a stride, together otherwise.
    const col: u8 = if (y >= 22) idx('d') else idx('c');
    if (stride) return if ((x >= 2 and x < 5) or (x >= 8 and x < 11)) col else 0;
    return if ((x >= 4 and x < 6) or (x >= 7 and x < 9)) col else 0;
}

const HEADER =
    \\scene: Lamp Room
    \\cast: Lamplighter
    \\props: Lantern
    \\marks: Door, Window
    \\backdrop: LampRoom
    \\
    \\routine Rounds(Lamplighter):
    \\  wait 1 ticks
    \\  walk Lamplighter to Window
    \\
    \\sprite Lamplighter: LamplighterSheet
    \\  idle: 0 for 40, 1 for 20
    \\  walk right: 2 for 8, 3 for 8
    \\  walk left: 4 for 8, 5 for 8
    \\
    \\sprite Lantern: LanternSheet
    \\  idle: 1 for 50, 0 for 4
    \\
    \\palette:
    \\
;

/// Writes `image <name> [frames WxH]:` and its rows from `pixel(x, y, frame)`, the frames side
/// by side in one row of the sheet.
fn image_block(comptime name: []const u8, comptime fw: usize, comptime fh: usize, comptime frames: usize, comptime pixel: fn (usize, usize, usize) u8) []const u8 {
    @setEvalBranchQuota(20_000_000);
    const head = if (frames == 1)
        std.fmt.comptimePrint("\nimage {s}:\n", .{name})
    else
        std.fmt.comptimePrint("\nimage {s} frames {d}x{d}:\n", .{ name, fw, fh });
    const row_len = 2 + 1 + fw * frames + 1 + 1; // two spaces, quotes round the codes, newline
    var out: [head.len + row_len * fh]u8 = undefined;
    @memcpy(out[0..head.len], head);
    var at = head.len;
    for (0..fh) |y| {
        @memcpy(out[at..][0..3], "  \"");
        at += 3;
        for (0..frames) |f| {
            for (0..fw) |x| {
                out[at] = PALETTE[pixel(x, y, f)].code;
                at += 1;
            }
        }
        @memcpy(out[at..][0..2], "\"\n");
        at += 2;
    }
    const final = out;
    return &final;
}

fn palette_block() []const u8 {
    comptime var text: []const u8 = "";
    inline for (PALETTE) |e| {
        text = text ++ if (e.rgb) |rgb|
            std.fmt.comptimePrint("  \"{c}\" {d} {d} {d}\n", .{ e.code, rgb[0], rgb[1], rgb[2] })
        else
            std.fmt.comptimePrint("  \"{c}\" transparent\n", .{e.code});
    }
    return text;
}

pub const SCRIPT: []const u8 = HEADER ++ palette_block() ++
    image_block("LampRoom", image.ART_WIDTH, image.ART_HEIGHT, 1, backdrop_pixel) ++
    image_block("LanternSheet", LANTERN_W, LANTERN_H, 2, lantern_pixel) ++
    image_block("LamplighterSheet", FIGURE_W, FIGURE_H, FIGURE_FRAMES, figure_pixel);

test "P46-03: the image stage's script declares its art and compiles it into the program" {
    const bespoke = @import("bespoke");
    var world = try bespoke.World.init(std.testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(std.testing.allocator, &world, &spatial, SCRIPT);
    defer compiled.deinit();
    const art = compiled.art;
    try std.testing.expectEqual(@as(usize, 3), art.images.len);
    const room = world.lookup_entity(SCENE).?;
    try std.testing.expectEqualStrings("LampRoom", art.backdrop_for(room).?.name);
    const lamplighter = art.sprite_for(world.lookup_entity("Lamplighter").?).?;
    try std.testing.expectEqual(@as(u32, FIGURE_FRAMES), art.images[lamplighter.image].frame_count());
    try std.testing.expectEqual(@as(u16, 3), lamplighter.frame_at(.walk_right, 8));
    try std.testing.expectEqual(@as(u16, 0), lamplighter.frame_at(.walk_up, 0));
    const lantern = art.sprite_for(world.lookup_entity("Lantern").?).?;
    const flame = PALETTE[idx('l')].rgb.?;
    try std.testing.expectEqual(image.Pixel{ .r = flame[0], .g = flame[1], .b = flame[2], .a = 255 }, art.images[lantern.image].frame_pixel(1, 5, 10));
}
