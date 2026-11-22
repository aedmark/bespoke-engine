//! Turning decoded PNG pixels into palette art (P46-04, D-156).
//!
//! A pixel maps onto the game palette by its exact colour: fully transparent pixels become index
//! 0, fully opaque ones reuse the palette entry of the same colour or add one, and a partly
//! transparent pixel is refused, because the palette has no alpha (D-152) and rounding it either
//! way would change what the author drew. An image that would push the palette past 256 colours
//! is refused. `bespoke import` writes the result as an inline `image` block with palette codes,
//! and a compile from a file maps `image X from "file.png"` the same way.
const std = @import("std");
const image = @import("image.zig");
const png = @import("png.zig");

pub const MapError = error{ PartialTransparency, TooManyColours, OutOfMemory };

/// Where a refused pixel is, for the message.
pub const Where = struct { x: u16 = 0, y: u16 = 0 };

/// Maps `rgba` onto `palette`, appending the colours it lacks. `palette` must hold index 0,
/// the transparent entry, whose stored colour is never matched. Returns one index per pixel.
pub fn map(allocator: std.mem.Allocator, rgba: png.Rgba, palette: *std.ArrayListUnmanaged(image.Colour), where: *Where) MapError![]u8 {
    std.debug.assert(palette.items.len >= 1);
    const count = @as(usize, rgba.width) * rgba.height;
    const out = try allocator.alloc(u8, count);
    errdefer allocator.free(out);
    for (0..count) |i| {
        const px = rgba.pixels[i * 4 ..][0..4];
        if (px[3] == 0) {
            out[i] = image.TRANSPARENT;
            continue;
        }
        if (px[3] != 255) {
            where.* = .{ .x = @intCast(i % rgba.width), .y = @intCast(i / rgba.width) };
            return MapError.PartialTransparency;
        }
        const colour = image.Colour{ .r = px[0], .g = px[1], .b = px[2] };
        const found = for (palette.items[1..], 1..) |c, n| {
            if (std.meta.eql(c, colour)) break n;
        } else null;
        if (found) |n| {
            out[i] = @intCast(n);
        } else {
            if (palette.items.len == image.MAX_COLOURS) {
                where.* = .{ .x = @intCast(i % rgba.width), .y = @intCast(i / rgba.width) };
                return MapError.TooManyColours;
            }
            try palette.append(allocator, colour);
            out[i] = @intCast(palette.items.len - 1);
        }
    }
    return out;
}

/// Codes tried for new colours, in order: letters and digits first, then the other printable
/// characters a code may hold. `.` is left for the transparent code.
const ONE = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!$%&'()*+,-/:;<=>?@[\\]^_`{|}~#";
const TWO_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

pub const CodeError = error{ OutOfCodes, OutOfMemory };

/// Gives every palette entry a code: `existing` keeps the codes a script already declared, in
/// order, and the rest get the first unused codes of `width` characters. Index 0 is `.` or `..`
/// when no script names it.
pub fn assign_codes(allocator: std.mem.Allocator, existing: []const []const u8, total: usize, width: usize) CodeError![]const []const u8 {
    std.debug.assert(width == 1 or width == 2);
    const codes = try allocator.alloc([]const u8, total);
    var made: usize = 0;
    errdefer {
        for (codes[existing.len..made]) |c| allocator.free(c);
        allocator.free(codes);
    }
    @memcpy(codes[0..existing.len], existing);
    made = existing.len;
    var candidate: usize = 0;
    while (made < total) {
        const code: []u8 = if (made == 0) try allocator.dupe(u8, if (width == 1) "." else "..") else blk: {
            while (true) : (candidate += 1) {
                var buf: [2]u8 = undefined;
                const text: []const u8 = if (width == 1) one: {
                    if (candidate >= ONE.len) return CodeError.OutOfCodes;
                    buf[0] = ONE[candidate];
                    break :one buf[0..1];
                } else two: {
                    if (candidate >= TWO_ALPHABET.len * TWO_ALPHABET.len) return CodeError.OutOfCodes;
                    buf = .{ TWO_ALPHABET[candidate / TWO_ALPHABET.len], TWO_ALPHABET[candidate % TWO_ALPHABET.len] };
                    break :two buf[0..2];
                };
                const used = for (codes[0..made]) |c| {
                    if (std.mem.eql(u8, c, text)) break true;
                } else false;
                if (!used) {
                    candidate += 1;
                    break :blk try allocator.dupe(u8, text);
                }
            }
        };
        codes[made] = code;
        made += 1;
    }
    return codes;
}

/// Frees what `assign_codes` allocated beyond the `existing` codes it borrowed.
pub fn free_codes(allocator: std.mem.Allocator, codes: []const []const u8, existing: usize) void {
    for (codes[existing..]) |c| allocator.free(c);
    allocator.free(codes);
}

/// Writes palette lines for entries `from..` of `palette`, indented as inside a `palette:` block.
pub fn write_palette_lines(writer: *std.Io.Writer, palette: []const image.Colour, codes: []const []const u8, from: usize) !void {
    for (palette[from..], codes[from..], from..) |c, code, i| {
        if (i == 0) {
            try writer.print("  \"{s}\" transparent\n", .{code});
        } else try writer.print("  \"{s}\" {d} {d} {d}\n", .{ code, c.r, c.g, c.b });
    }
}

/// Writes `image <name> [frames WxH]:` and one quoted row of codes per pixel row.
pub fn write_image_block(writer: *std.Io.Writer, name: []const u8, frames: ?[2]u16, width: u16, height: u16, pixels: []const u8, codes: []const []const u8) !void {
    if (frames) |f| {
        try writer.print("image {s} frames {d}x{d}:\n", .{ name, f[0], f[1] });
    } else try writer.print("image {s}:\n", .{name});
    for (0..height) |y| {
        try writer.writeAll("  \"");
        for (pixels[y * width ..][0..width]) |index| try writer.writeAll(codes[index]);
        try writer.writeAll("\"\n");
    }
}

test "P46-04: pixels map by exact colour, transparent to index 0, and partial alpha is refused" {
    const allocator = std.testing.allocator;
    var palette = std.ArrayListUnmanaged(image.Colour).empty;
    defer palette.deinit(allocator);
    try palette.append(allocator, .{ .r = 0, .g = 0, .b = 0 });
    try palette.append(allocator, .{ .r = 9, .g = 9, .b = 9 });
    var px = [_]u8{ 1, 2, 3, 0, 9, 9, 9, 255, 200, 0, 0, 255, 200, 0, 0, 255 };
    var where = Where{};
    const out = try map(allocator, .{ .width = 2, .height = 2, .pixels = &px }, &palette, &where);
    defer allocator.free(out);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 2 }, out);
    try std.testing.expectEqual(@as(usize, 3), palette.items.len);
    px[3] = 128;
    try std.testing.expectError(MapError.PartialTransparency, map(allocator, .{ .width = 2, .height = 2, .pixels = &px }, &palette, &where));
    try std.testing.expectEqual(Where{ .x = 0, .y = 0 }, where);
}

test "P46-04: new codes skip the ones a script already uses and stay one width" {
    const allocator = std.testing.allocator;
    const existing = [_][]const u8{ ".", "a", "c" };
    const codes = try assign_codes(allocator, &existing, 5, 1);
    defer free_codes(allocator, codes, existing.len);
    try std.testing.expectEqualStrings("b", codes[3]);
    try std.testing.expectEqualStrings("d", codes[4]);
    const fresh = try assign_codes(allocator, &.{}, 3, 2);
    defer free_codes(allocator, fresh, 0);
    try std.testing.expectEqualStrings("..", fresh[0]);
    try std.testing.expectEqualStrings("aa", fresh[1]);
    try std.testing.expectEqualStrings("ab", fresh[2]);
    try std.testing.expectError(CodeError.OutOfCodes, assign_codes(allocator, &.{}, ONE.len + 2, 1));
}
