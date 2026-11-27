//! The pixel editor's PNG writer (P47-02, D-196): 8-bit RGBA, no interlacing, one IDAT of
//! zlib-wrapped deflate from std. Studio code, not engine API; the engine only reads PNG
//! (D-151, D-156). `encode_checked` reads every result back through the engine's own
//! `png.decode`, the decoder the compiler uses, and refuses to hand over bytes that do not
//! decode to the pixels given, so a write can never change what the game draws by surprise.
const std = @import("std");
const bespoke = @import("bespoke");

const Allocator = std.mem.Allocator;
const flate = std.compress.flate;

pub const Error = error{ BadSize, PartialAlpha, RoundTripMismatch } || Allocator.Error;

const SIGNATURE = [_]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };

/// `rgba` is `width * height` pixels, four bytes each. Alpha must be 0 or 255, the only values
/// art may hold (D-166); a transparent pixel is written as 0, 0, 0, 0 whatever its colour bytes,
/// so the file says only what the game can draw.
pub fn encode_checked(allocator: Allocator, width: u32, height: u32, rgba: []const u8) Error![]u8 {
    if (width == 0 or height == 0 or width > bespoke.image.MAX_SHEET_SIDE or height > bespoke.image.MAX_SHEET_SIDE) return error.BadSize;
    if (@as(usize, width) * height > bespoke.image.MAX_SHEET_PIXELS) return error.BadSize;
    if (rgba.len != @as(usize, width) * height * 4) return error.BadSize;

    // Scanlines with filter byte 0 (None); flat pixel art compresses well without filters.
    const stride = @as(usize, width) * 4 + 1;
    const raw = try allocator.alloc(u8, stride * height);
    defer allocator.free(raw);
    for (0..height) |y| {
        const line = raw[y * stride ..][0..stride];
        line[0] = 0;
        const src = rgba[y * @as(usize, width) * 4 ..][0 .. @as(usize, width) * 4];
        var x: usize = 0;
        while (x < src.len) : (x += 4) {
            const a = src[x + 3];
            if (a != 0 and a != 255) return error.PartialAlpha;
            if (a == 0) @memset(line[1 + x ..][0..4], 0) else @memcpy(line[1 + x ..][0..4], src[x..][0..4]);
        }
    }

    // The compressor needs room for its header in the output before it writes anything.
    var zlib = try std.Io.Writer.Allocating.initCapacity(allocator, 4096);
    defer zlib.deinit();
    {
        const window = try allocator.alloc(u8, flate.max_window_len);
        defer allocator.free(window);
        // The compressor holds large hash tables; keep it off the 8 MB wasm stack's hot path.
        const c = try allocator.create(flate.Compress);
        defer allocator.destroy(c);
        c.* = flate.Compress.init(&zlib.writer, window, .zlib, .default) catch return error.OutOfMemory;
        c.writer.writeAll(raw) catch return error.OutOfMemory;
        c.finish() catch return error.OutOfMemory;
    }

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;
    w.writeAll(&SIGNATURE) catch return error.OutOfMemory;
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);
    std.mem.writeInt(u32, ihdr[4..8], height, .big);
    ihdr[8] = 8; // bit depth
    ihdr[9] = 6; // RGBA
    ihdr[10] = 0; // deflate
    ihdr[11] = 0; // adaptive filtering
    ihdr[12] = 0; // no interlace
    chunk(w, "IHDR", &ihdr) catch return error.OutOfMemory;
    chunk(w, "IDAT", zlib.written()) catch return error.OutOfMemory;
    chunk(w, "IEND", "") catch return error.OutOfMemory;
    const bytes = out.toOwnedSlice() catch return error.OutOfMemory;
    errdefer allocator.free(bytes);

    // The check: the engine's decoder must give back exactly these pixels.
    var back = bespoke.png.decode(allocator, bytes) catch return error.RoundTripMismatch;
    defer back.deinit(allocator);
    if (back.width != width or back.height != height) return error.RoundTripMismatch;
    for (0..@as(usize, width) * height) |i| {
        const want = rgba[i * 4 ..][0..4];
        const got = back.pixels[i * 4 ..][0..4];
        if (want[3] == 0) {
            if (got[3] != 0) return error.RoundTripMismatch;
        } else if (!std.mem.eql(u8, want, got)) return error.RoundTripMismatch;
    }
    return bytes;
}

fn chunk(w: *std.Io.Writer, kind: *const [4]u8, data: []const u8) !void {
    try w.writeInt(u32, @intCast(data.len), .big);
    try w.writeAll(kind);
    try w.writeAll(data);
    var crc = std.hash.Crc32.init();
    crc.update(kind);
    crc.update(data);
    try w.writeInt(u32, crc.final(), .big);
}

const testing = std.testing;

test "an encoded sheet decodes through the engine's reader to the same pixels" {
    const w = 5;
    const h = 3;
    var px: [w * h * 4]u8 = undefined;
    for (0..w * h) |i| {
        const c: u8 = @intCast(i * 17);
        px[i * 4 ..][0..4].* = if (i % 4 == 0) .{ 9, 9, 9, 0 } else .{ c, 255 - c, c / 2, 255 };
    }
    const bytes = try encode_checked(testing.allocator, w, h, &px);
    defer testing.allocator.free(bytes);
    var back = try bespoke.png.decode(testing.allocator, bytes);
    defer back.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, w), back.width);
    for (0..w * h) |i| {
        if (i % 4 == 0) {
            try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, back.pixels[i * 4 ..][0..4]);
        } else try testing.expectEqualSlices(u8, px[i * 4 ..][0..4], back.pixels[i * 4 ..][0..4]);
    }
}

test "partial alpha and bad sizes are refused before anything is written" {
    var px = [_]u8{ 1, 2, 3, 128 };
    try testing.expectError(error.PartialAlpha, encode_checked(testing.allocator, 1, 1, &px));
    try testing.expectError(error.BadSize, encode_checked(testing.allocator, 2, 1, &px));
    try testing.expectError(error.BadSize, encode_checked(testing.allocator, 0, 1, &px));
}

test "a full-size sheet compresses and round-trips" {
    const w = 320;
    const h = 180;
    const px = try testing.allocator.alloc(u8, w * h * 4);
    defer testing.allocator.free(px);
    for (0..w * h) |i| px[i * 4 ..][0..4].* = .{ @intCast(i % 7 * 30), @intCast(i / w % 5 * 40), 90, 255 };
    const bytes = try encode_checked(testing.allocator, w, h, px);
    defer testing.allocator.free(bytes);
    try testing.expect(bytes.len < px.len / 4);
}
