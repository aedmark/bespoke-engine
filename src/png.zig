//! PNG decoding for art import (P46-04, D-151, D-156).
//!
//! Only the command line decodes PNG: `bespoke import` and a script compiled from a file that
//! names `image X from "file.png"`. The runtime never does (D-151 point 3), so the browser
//! module and packages never carry this code's output as anything but palette indices.
//!
//! Every PNG is untrusted input. The decoder checks the signature and every chunk's CRC, refuses
//! anything past the art limits before allocating for it (D-153), inflates into a buffer of
//! exactly the size the header implies, and names what it refuses. It reads the formats pixel
//! art is saved in: indexed, grey, and true colour, with or without alpha, at 8 bits a channel
//! (1, 2, and 4 bits for indexed and grey). 16-bit channels and interlaced images are refused
//! rather than reduced, because either change could alter a pixel the author drew.
const std = @import("std");
const image = @import("image.zig");

/// A PNG file larger than this is refused before it is parsed: a 2048x512 sheet of raw RGBA is
/// 4 MiB, and art compresses far below that.
pub const MAX_FILE: usize = 4 * 1024 * 1024;

pub const Error = error{
    PngSignature,
    PngChecksum,
    PngTruncated,
    PngTooLarge,
    PngUnsupported,
    PngInterlaced,
    PngMissingPalette,
    PngCorrupt,
    OutOfMemory,
};

/// Decoded pixels, row by row, four bytes each: red, green, blue, alpha.
pub const Rgba = struct {
    width: u16,
    height: u16,
    pixels: []u8,

    pub fn deinit(self: *Rgba, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
        self.* = undefined;
    }
};

const SIGNATURE = [8]u8{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };

const ColorType = enum(u8) { grey = 0, rgb = 2, indexed = 3, grey_alpha = 4, rgba = 6 };

const Header = struct {
    width: u32,
    height: u32,
    depth: u8,
    color: ColorType,

    fn channels(self: Header) u32 {
        return switch (self.color) {
            .grey, .indexed => 1,
            .grey_alpha => 2,
            .rgb => 3,
            .rgba => 4,
        };
    }

    /// Bytes in one unfiltered row, and the filter's byte step (at least one byte).
    fn stride(self: Header) usize {
        return (@as(usize, self.width) * self.channels() * self.depth + 7) / 8;
    }

    fn step(self: Header) usize {
        return @max(1, self.channels() * self.depth / 8);
    }
};

fn be32(bytes: []const u8) u32 {
    return std.mem.readInt(u32, bytes[0..4], .big);
}

pub fn decode(allocator: std.mem.Allocator, file: []const u8) Error!Rgba {
    if (file.len > MAX_FILE) return Error.PngTooLarge;
    if (file.len < SIGNATURE.len or !std.mem.eql(u8, file[0..8], &SIGNATURE)) return Error.PngSignature;

    var header: ?Header = null;
    var plte: []const u8 = &.{};
    var trns: []const u8 = &.{};
    var idat = std.ArrayListUnmanaged(u8).empty;
    defer idat.deinit(allocator);
    var at: usize = 8;
    var ended = false;
    while (!ended) {
        if (file.len - at < 12) return Error.PngTruncated;
        const len = be32(file[at..]);
        if (len > file.len - at - 12) return Error.PngTruncated;
        const kind = file[at + 4 ..][0..4];
        const data = file[at + 8 ..][0..len];
        const crc = be32(file[at + 8 + len ..]);
        if (std.hash.Crc32.hash(file[at + 4 .. at + 8 + len]) != crc) return Error.PngChecksum;
        at += 12 + len;

        if (std.mem.eql(u8, kind, "IHDR")) {
            if (header != null or len != 13) return Error.PngCorrupt;
            header = try read_header(data);
        } else if (header == null) {
            // IHDR comes first (PNG 5.6).
            return Error.PngCorrupt;
        } else if (std.mem.eql(u8, kind, "PLTE")) {
            if (len == 0 or len % 3 != 0 or len / 3 > 256) return Error.PngCorrupt;
            plte = data;
        } else if (std.mem.eql(u8, kind, "tRNS")) {
            trns = data;
        } else if (std.mem.eql(u8, kind, "IDAT")) {
            try idat.appendSlice(allocator, data);
        } else if (std.mem.eql(u8, kind, "IEND")) {
            ended = true;
        } else if (kind[0] & 0x20 == 0) {
            // An unknown critical chunk changes how the image reads; ancillary ones do not.
            return Error.PngUnsupported;
        }
    }
    const h = header orelse return Error.PngCorrupt;
    if (h.color == .indexed and plte.len == 0) return Error.PngMissingPalette;

    // Inflate into exactly the bytes the header implies, plus one to notice extra data.
    const stride = h.stride();
    const raw_len = @as(usize, h.height) * (1 + stride);
    const raw = try allocator.alloc(u8, raw_len + 1);
    defer allocator.free(raw);
    var in: std.Io.Reader = .fixed(idat.items);
    var out: std.Io.Writer = .fixed(raw);
    var inflate: std.compress.flate.Decompress = .init(&in, .zlib, &.{});
    const got = inflate.reader.streamRemaining(&out) catch return Error.PngCorrupt;
    if (got != raw_len) return Error.PngCorrupt;

    try unfilter(raw[0..raw_len], h);

    const pixels = try allocator.alloc(u8, @as(usize, h.width) * h.height * 4);
    errdefer allocator.free(pixels);
    try expand(raw[0..raw_len], h, plte, trns, pixels);
    return .{ .width = @intCast(h.width), .height = @intCast(h.height), .pixels = pixels };
}

fn read_header(data: []const u8) Error!Header {
    const width = be32(data[0..]);
    const height = be32(data[4..]);
    const depth = data[8];
    const color_raw = data[9];
    if (data[10] != 0 or data[11] != 0) return Error.PngUnsupported;
    if (data[12] == 1) return Error.PngInterlaced;
    if (data[12] != 0) return Error.PngCorrupt;
    if (width == 0 or height == 0) return Error.PngCorrupt;
    // The sheet limits of D-153, checked before anything is allocated for the pixels.
    if (width > image.MAX_SHEET_SIDE or height > image.MAX_SHEET_SIDE or @as(u64, width) * height > image.MAX_SHEET_PIXELS) return Error.PngTooLarge;
    const color = std.enums.fromInt(ColorType, color_raw) orelse return Error.PngCorrupt;
    const valid = switch (color) {
        .grey, .indexed => depth == 1 or depth == 2 or depth == 4 or depth == 8,
        .rgb, .grey_alpha, .rgba => depth == 8,
    };
    if (!valid) return if (depth == 16) Error.PngUnsupported else Error.PngCorrupt;
    return .{ .width = width, .height = height, .depth = depth, .color = color };
}

/// Reverses the five PNG row filters in place (PNG 9.2).
fn unfilter(raw: []u8, h: Header) Error!void {
    const stride = h.stride();
    const step = h.step();
    var prev: ?[]const u8 = null;
    for (0..h.height) |y| {
        const row_start = y * (1 + stride);
        const filter = raw[row_start];
        const row = raw[row_start + 1 ..][0..stride];
        switch (filter) {
            0 => {},
            1 => for (step..stride) |i| {
                row[i] +%= row[i - step];
            },
            2 => if (prev) |p| for (row, p) |*b, up| {
                b.* +%= up;
            },
            3 => for (row, 0..) |*b, i| {
                const left: u16 = if (i >= step) row[i - step] else 0;
                const up: u16 = if (prev) |p| p[i] else 0;
                b.* +%= @intCast((left + up) / 2);
            },
            4 => for (row, 0..) |*b, i| {
                const left: i16 = if (i >= step) row[i - step] else 0;
                const up: i16 = if (prev) |p| p[i] else 0;
                const corner: i16 = if (i >= step) (if (prev) |p| p[i - step] else 0) else 0;
                b.* +%= paeth(left, up, corner);
            },
            else => return Error.PngCorrupt,
        }
        prev = row;
    }
}

fn paeth(a: i16, b: i16, c: i16) u8 {
    const p = a + b - c;
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);
    const pick = if (pa <= pb and pa <= pc) a else if (pb <= pc) b else c;
    return @intCast(pick);
}

/// One sample of `depth` bits at sample index `n` of a row.
fn sample(row: []const u8, depth: u8, n: usize) u8 {
    if (depth == 8) return row[n];
    const per_byte = 8 / depth;
    const byte = row[n / per_byte];
    const shift: u3 = @intCast(8 - depth - (n % per_byte) * depth);
    const mask: u8 = @intCast((@as(u16, 1) << @intCast(depth)) - 1);
    return (byte >> shift) & mask;
}

fn expand(raw: []const u8, h: Header, plte: []const u8, trns: []const u8, out: []u8) Error!void {
    const stride = h.stride();
    const max: u16 = (@as(u16, 1) << @intCast(h.depth)) - 1;
    for (0..h.height) |y| {
        const row = raw[y * (1 + stride) + 1 ..][0..stride];
        for (0..h.width) |x| {
            const px = out[(y * h.width + x) * 4 ..][0..4];
            switch (h.color) {
                .indexed => {
                    const i = sample(row, h.depth, x);
                    if (@as(usize, i) * 3 + 3 > plte.len) return Error.PngCorrupt;
                    px.* = .{ plte[i * 3], plte[i * 3 + 1], plte[i * 3 + 2], if (i < trns.len) trns[i] else 255 };
                },
                .grey => {
                    const s = sample(row, h.depth, x);
                    const g: u8 = @intCast(@as(u16, s) * 255 / max);
                    const keyed = trns.len >= 2 and std.mem.readInt(u16, trns[0..2], .big) == s;
                    px.* = .{ g, g, g, if (keyed) 0 else 255 };
                },
                .grey_alpha => px.* = .{ row[x * 2], row[x * 2], row[x * 2], row[x * 2 + 1] },
                .rgb => {
                    const c = row[x * 3 ..][0..3];
                    const keyed = trns.len >= 6 and std.mem.readInt(u16, trns[0..2], .big) == c[0] and
                        std.mem.readInt(u16, trns[2..4], .big) == c[1] and std.mem.readInt(u16, trns[4..6], .big) == c[2];
                    px.* = .{ c[0], c[1], c[2], if (keyed) 0 else 255 };
                },
                .rgba => px.* = row[x * 4 ..][0..4].*,
            }
        }
    }
}

test "P46-04: the Paeth predictor picks the nearest of left, up, and corner" {
    try std.testing.expectEqual(@as(u8, 10), paeth(10, 20, 20));
    try std.testing.expectEqual(@as(u8, 20), paeth(10, 20, 10));
    try std.testing.expectEqual(@as(u8, 5), paeth(5, 5, 5));
}

test "P46-04: sub-byte samples read from the high bits first" {
    try std.testing.expectEqual(@as(u8, 0b10), sample(&.{0b1001_0011}, 2, 0));
    try std.testing.expectEqual(@as(u8, 0b11), sample(&.{0b1001_0011}, 2, 3));
    try std.testing.expectEqual(@as(u8, 0b1001), sample(&.{0b1001_0011}, 4, 0));
    try std.testing.expectEqual(@as(u8, 1), sample(&.{0b1000_0000}, 1, 0));
}

fn fixture(name: []const u8) ![]u8 {
    var path_buf: [96]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "tests/fixtures/png/{s}", .{name});
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(MAX_FILE));
}

fn decode_fixture(name: []const u8) !Rgba {
    const file = try fixture(name);
    defer std.testing.allocator.free(file);
    return decode(std.testing.allocator, file);
}

test "P46-04: an indexed 4-bit PNG decodes its palette and transparency" {
    var rgba = try decode_fixture("indexed.png");
    defer rgba.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 8), rgba.width);
    try std.testing.expectEqual(@as(u16, 4), rgba.height);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, rgba.pixels[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 34, 32, 52, 255 }, rgba.pixels[4..8]);
    // Row 1, column 5 is index 3.
    try std.testing.expectEqualSlices(u8, &.{ 251, 242, 54, 255 }, rgba.pixels[(8 + 5) * 4 ..][0..4]);
}

test "P46-04: a true-colour PNG decodes through all five row filters" {
    var rgba = try decode_fixture("rgba.png");
    defer rgba.deinit(std.testing.allocator);
    const want = [_][]const u8{ ".rrrr.", "rybbyr", "ryyyyr", ".rrrr." };
    for (want, 0..) |row, y| for (row, 0..) |ch, x| {
        const px = rgba.pixels[(y * 6 + x) * 4 ..][0..4];
        const expect: [4]u8 = switch (ch) {
            '.' => .{ 0, 0, 0, 0 },
            'r' => .{ 200, 40, 40, 255 },
            'y' => .{ 240, 220, 60, 255 },
            else => .{ 30, 30, 90, 255 },
        };
        try std.testing.expectEqualSlices(u8, &expect, px);
    };
}

test "P46-04: a 2-bit grey PNG scales its levels and keys its transparent level" {
    var rgba = try decode_fixture("grey.png");
    defer rgba.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, rgba.pixels[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 85, 85, 85, 255 }, rgba.pixels[4..8]);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, rgba.pixels[12..16]);
}

test "P46-04: the decoder names what it refuses" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(Error.PngInterlaced, decode_fixture("interlaced.png"));
    try std.testing.expectError(Error.PngUnsupported, decode_fixture("deep.png"));
    try std.testing.expectError(Error.PngSignature, decode(allocator, "GIF89a"));

    const good = try fixture("rgba.png");
    defer allocator.free(good);
    const copy = try allocator.dupe(u8, good);
    defer allocator.free(copy);
    // A flipped bit in the header's data fails its CRC.
    copy[16 + 3] ^= 1;
    try std.testing.expectError(Error.PngChecksum, decode(allocator, copy));
    @memcpy(copy, good);
    try std.testing.expectError(Error.PngTruncated, decode(allocator, copy[0 .. copy.len - 5]));

    // A header claiming a sheet past the limits, with a valid CRC, is refused before allocation.
    var big: [33]u8 = @splat(0);
    @memcpy(big[0..8], &SIGNATURE);
    std.mem.writeInt(u32, big[8..12], 13, .big);
    @memcpy(big[12..16], "IHDR");
    std.mem.writeInt(u32, big[16..20], 4096, .big);
    std.mem.writeInt(u32, big[20..24], 4096, .big);
    big[24] = 8;
    big[25] = 6;
    std.mem.writeInt(u32, big[29..33], std.hash.Crc32.hash(big[12..29]), .big);
    try std.testing.expectError(Error.PngTooLarge, decode(allocator, &big));
}
