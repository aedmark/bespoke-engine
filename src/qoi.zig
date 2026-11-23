//! The art codec: standard QOI streams of RGBA pixels (P48-12, D-166, D-182).
//!
//! QOI codes each pixel as a run of the previous one, a slot in a 64-entry table of recent
//! colours, a small difference from the previous pixel, or the literal colour. Flat pixel art
//! is mostly runs and table hits, so it compresses well, and the decoder is a few dozen lines,
//! which matters in the browser module that carries it (D-166 point 3). Each stream is a whole
//! QOI file, `qoif` header and end marker included, so outside tools can read and write one.
//!
//! The decoder reads untrusted package bytes. It is told the size the image record promises and
//! the most pixels it may produce, checks the header against both before it allocates, and
//! never reads past the slice it is given.
const std = @import("std");
const image = @import("image.zig");
const Pixel = image.Pixel;

pub const Error = error{ QoiHeader, QoiTruncated, QoiTrailing, QoiAlpha, OutOfMemory };

const MAGIC = "qoif";
pub const HEADER_LEN = 14;
const END = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 1 };

const OP_INDEX: u8 = 0x00;
const OP_DIFF: u8 = 0x40;
const OP_LUMA: u8 = 0x80;
const OP_RUN: u8 = 0xc0;
const OP_RGB: u8 = 0xfe;
const OP_RGBA: u8 = 0xff;
const MASK: u8 = 0xc0;
const MAX_RUN = 62;

fn slot(p: Pixel) u8 {
    return @intCast((@as(u32, p.r) * 3 + @as(u32, p.g) * 5 + @as(u32, p.b) * 7 + @as(u32, p.a) * 11) % 64);
}

/// The stream for `pixels`, row by row, `width` by `height`. Caller owns the bytes.
pub fn encode(allocator: std.mem.Allocator, pixels: []const Pixel, width: u32, height: u32) error{OutOfMemory}![]u8 {
    std.debug.assert(pixels.len == @as(usize, width) * height);
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    // The worst case is five bytes a pixel; reserving it keeps the loop free of failure paths.
    try out.ensureTotalCapacity(allocator, HEADER_LEN + pixels.len * 5 + END.len);
    out.appendSliceAssumeCapacity(MAGIC);
    var be: [4]u8 = undefined;
    std.mem.writeInt(u32, &be, width, .big);
    out.appendSliceAssumeCapacity(&be);
    std.mem.writeInt(u32, &be, height, .big);
    out.appendSliceAssumeCapacity(&be);
    out.appendSliceAssumeCapacity(&.{ 4, 0 });

    var table: [64]Pixel = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0 });
    var prev = Pixel{ .r = 0, .g = 0, .b = 0, .a = 255 };
    var run: u8 = 0;
    for (pixels, 0..) |p, i| {
        if (std.meta.eql(p, prev)) {
            run += 1;
            if (run == MAX_RUN or i == pixels.len - 1) {
                out.appendAssumeCapacity(OP_RUN | (run - 1));
                run = 0;
            }
            continue;
        }
        if (run > 0) {
            out.appendAssumeCapacity(OP_RUN | (run - 1));
            run = 0;
        }
        const s = slot(p);
        if (std.meta.eql(table[s], p)) {
            out.appendAssumeCapacity(OP_INDEX | s);
        } else {
            table[s] = p;
            if (p.a == prev.a) {
                const dr: i16 = @as(i8, @bitCast(p.r -% prev.r));
                const dg: i16 = @as(i8, @bitCast(p.g -% prev.g));
                const db: i16 = @as(i8, @bitCast(p.b -% prev.b));
                const dr_dg = dr - dg;
                const db_dg = db - dg;
                if (dr >= -2 and dr <= 1 and dg >= -2 and dg <= 1 and db >= -2 and db <= 1) {
                    out.appendAssumeCapacity(OP_DIFF | @as(u8, @intCast(dr + 2)) << 4 | @as(u8, @intCast(dg + 2)) << 2 | @as(u8, @intCast(db + 2)));
                } else if (dg >= -32 and dg <= 31 and dr_dg >= -8 and dr_dg <= 7 and db_dg >= -8 and db_dg <= 7) {
                    out.appendSliceAssumeCapacity(&.{ OP_LUMA | @as(u8, @intCast(dg + 32)), @as(u8, @intCast(dr_dg + 8)) << 4 | @as(u8, @intCast(db_dg + 8)) });
                } else {
                    out.appendSliceAssumeCapacity(&.{ OP_RGB, p.r, p.g, p.b });
                }
            } else {
                out.appendSliceAssumeCapacity(&.{ OP_RGBA, p.r, p.g, p.b, p.a });
            }
        }
        prev = p;
    }
    out.appendSliceAssumeCapacity(&END);
    return out.toOwnedSlice(allocator);
}

/// The width and height a stream's header names, or `QoiHeader`.
pub fn header_size(bytes: []const u8) Error!struct { width: u32, height: u32 } {
    if (bytes.len < HEADER_LEN or !std.mem.eql(u8, bytes[0..4], MAGIC)) return Error.QoiHeader;
    const channels = bytes[12];
    const colorspace = bytes[13];
    if ((channels != 3 and channels != 4) or colorspace > 1) return Error.QoiHeader;
    return .{ .width = std.mem.readInt(u32, bytes[4..8], .big), .height = std.mem.readInt(u32, bytes[8..12], .big) };
}

/// Decodes a stream that must be exactly `width` by `height`. Every alpha is 0 or 255 (D-166)
/// and a transparent pixel comes back as all zeroes, so equal art compares equal. The end
/// marker must close the stream with nothing after it. Caller owns the pixels.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, width: u32, height: u32) Error![]Pixel {
    const size = try header_size(bytes);
    if (size.width != width or size.height != height) return Error.QoiHeader;
    const count = @as(usize, width) * height;
    // A stream codes at most 62 pixels a byte, so a short one cannot claim a huge image and
    // make the allocation below before its bytes are seen.
    if (count > (bytes.len - HEADER_LEN) * MAX_RUN) return Error.QoiTruncated;
    const pixels = try allocator.alloc(Pixel, count);
    errdefer allocator.free(pixels);

    var table: [64]Pixel = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0 });
    var p = Pixel{ .r = 0, .g = 0, .b = 0, .a = 255 };
    var at: usize = HEADER_LEN;
    var i: usize = 0;
    while (i < count) {
        if (at >= bytes.len) return Error.QoiTruncated;
        const b1 = bytes[at];
        at += 1;
        if (b1 == OP_RGB) {
            if (bytes.len - at < 3) return Error.QoiTruncated;
            p.r = bytes[at];
            p.g = bytes[at + 1];
            p.b = bytes[at + 2];
            at += 3;
        } else if (b1 == OP_RGBA) {
            if (bytes.len - at < 4) return Error.QoiTruncated;
            p = .{ .r = bytes[at], .g = bytes[at + 1], .b = bytes[at + 2], .a = bytes[at + 3] };
            at += 4;
        } else switch (b1 & MASK) {
            OP_INDEX => p = table[b1],
            OP_DIFF => {
                p.r +%= (b1 >> 4 & 3) -% 2;
                p.g +%= (b1 >> 2 & 3) -% 2;
                p.b +%= (b1 & 3) -% 2;
            },
            OP_LUMA => {
                if (at >= bytes.len) return Error.QoiTruncated;
                const b2 = bytes[at];
                at += 1;
                const dg = (b1 & 0x3f) -% 32;
                p.r +%= dg -% 8 +% (b2 >> 4 & 0x0f);
                p.g +%= dg;
                p.b +%= dg -% 8 +% (b2 & 0x0f);
            },
            else => {
                // A run repeats the current pixel; one that would overrun the image is corrupt.
                const run: usize = (b1 & 0x3f) + 1;
                if (run > count - i) return Error.QoiTruncated;
                if (p.a != 0 and p.a != 255) return Error.QoiAlpha;
                @memset(pixels[i .. i + run], canonical(p));
                i += run;
                table[slot(p)] = p;
                continue;
            },
        }
        if (p.a != 0 and p.a != 255) return Error.QoiAlpha;
        table[slot(p)] = p;
        pixels[i] = canonical(p);
        i += 1;
    }
    if (bytes.len - at < END.len or !std.mem.eql(u8, bytes[at..][0..END.len], &END)) return Error.QoiTruncated;
    if (bytes.len - at != END.len) return Error.QoiTrailing;
    return pixels;
}

fn canonical(p: Pixel) Pixel {
    return if (p.a == 0) image.TRANSPARENT else p;
}

const testing = std.testing;

fn px(r: u8, g: u8, b: u8) Pixel {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}

test "P48-12: QOI round-trips every op and refuses what a package must not hold" {
    // Runs, table hits, small and luma differences, literal colours, and transparency.
    const t = image.TRANSPARENT;
    const source = [_]Pixel{
        t,               t,               px(10, 20, 30), px(10, 20, 30), px(11, 19, 30), px(30, 40, 50),
        px(200, 1, 255), px(10, 20, 30),  t,              px(0, 0, 0),    px(0, 0, 0),    px(0, 0, 0),
    };
    const bytes = try encode(testing.allocator, &source, 6, 2);
    defer testing.allocator.free(bytes);
    try testing.expectEqualStrings("qoif", bytes[0..4]);
    try testing.expectEqual(@as(u32, 6), (try header_size(bytes)).width);
    const back = try decode(testing.allocator, bytes, 6, 2);
    defer testing.allocator.free(back);
    try testing.expectEqualSlices(Pixel, &source, back);

    // The header must name the size the record promises.
    try testing.expectError(Error.QoiHeader, decode(testing.allocator, bytes, 2, 6));
    try testing.expectError(Error.QoiHeader, decode(testing.allocator, bytes[0..10], 6, 2));
    // A cut stream and bytes after the end marker are refused.
    try testing.expectError(Error.QoiTruncated, decode(testing.allocator, bytes[0 .. bytes.len - 1], 6, 2));
    const longer = try std.mem.concat(testing.allocator, u8, &.{ bytes, &.{0} });
    defer testing.allocator.free(longer);
    try testing.expectError(Error.QoiTrailing, decode(testing.allocator, longer, 6, 2));
    // A pixel with partial alpha is not art (D-166).
    const half = [_]Pixel{.{ .r = 1, .g = 2, .b = 3, .a = 128 }};
    const half_bytes = try encode(testing.allocator, &half, 1, 1);
    defer testing.allocator.free(half_bytes);
    try testing.expectError(Error.QoiAlpha, decode(testing.allocator, half_bytes, 1, 1));
}

test "P48-12: a short QOI stream cannot claim a large image" {
    var header: [HEADER_LEN + 9]u8 = undefined;
    @memcpy(header[0..4], MAGIC);
    std.mem.writeInt(u32, header[4..8], 2048, .big);
    std.mem.writeInt(u32, header[8..12], 512, .big);
    header[12] = 4;
    header[13] = 0;
    header[14] = OP_RUN | 61;
    @memcpy(header[15..], &END);
    try testing.expectError(Error.QoiTruncated, decode(testing.allocator, &header, 2048, 512));
}

test "P48-12: a long run of one colour encodes in a few bytes" {
    const pixels: [320 * 180]Pixel = @splat(px(40, 60, 80));
    const bytes = try encode(testing.allocator, &pixels, 320, 180);
    defer testing.allocator.free(bytes);
    try testing.expect(bytes.len < 1000);
    const back = try decode(testing.allocator, bytes, 320, 180);
    defer testing.allocator.free(back);
    try testing.expectEqualSlices(Pixel, &pixels, back);
}
