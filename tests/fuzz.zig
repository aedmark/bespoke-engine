//! Bounded mutation tests for local engine input boundaries (P39-01).
const std = @import("std");
const bespoke = @import("bespoke");
const testing = std.testing;

const max_input = 4096;
const script = @embedFile("fixtures/fuzz/room.bespoke");
const values = @embedFile("fixtures/fuzz/values.bespoke");
const package = @embedFile("fixtures/compat/v0.1.0-package-v14.bspk");
const axis_package = @embedFile("fixtures/compat/v0.3.1-package-v19.bspk");
const red_line_package = @embedFile("fixtures/compat/v0.3.1-package-v20.bspk");
const dilemma_package = @embedFile("fixtures/compat/v0.3.1-package-v21.bspk");
const drift_package = @embedFile("fixtures/compat/v0.3.1-package-v22.bspk");
const appeal_package = @embedFile("fixtures/compat/v0.3.1-package-v23.bspk");
const art_package = @embedFile("fixtures/compat/v0.4.0-package-v24.bspk");
const sprite_package = @embedFile("fixtures/compat/v0.4.0-package-v25.bspk");
const area_package = @embedFile("fixtures/compat/v0.4.0-package-v26.bspk");
const handler_chain_package = @embedFile("fixtures/compat/v0.4.0-package-v27.bspk");
const bound_body_package = @embedFile("fixtures/compat/v0.4.0-package-v28.bspk");
const save = @embedFile("fixtures/compat/v0.1.0-save-v2.sav");
const melody = @embedFile("fixtures/fuzz/melody.txt");
const drums = @embedFile("fixtures/fuzz/drums.txt");
const command = @embedFile("fixtures/fuzz/command.txt");
const png_indexed = @embedFile("fixtures/png/indexed.png");
const png_rgba = @embedFile("fixtures/png/rgba.png");
const png_grey = @embedFile("fixtures/png/grey.png");
const png_colours = @embedFile("fixtures/png/too_many_colours.png");

const Check = fn (std.mem.Allocator, []const u8) anyerror!bool;

fn campaign(comptime check: Check, seeds: []const []const u8) !void {
    for (seeds) |seed| {
        try testing.expect(seed.len <= max_input);
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        try testing.expect(try check(arena.allocator(), seed));
    }
    try mutate(check, seeds);
}

fn mutate(comptime check: Check, seeds: []const []const u8) !void {
    const start = std.Io.Clock.awake.now(testing.io);
    var prng = std.Random.DefaultPrng.init(0x39_01);
    const random = prng.random();
    var buffer: [max_input]u8 = undefined;
    while (start.durationTo(std.Io.Clock.awake.now(testing.io)).toNanoseconds() < std.time.ns_per_s) {
        const seed = seeds[random.uintLessThan(usize, seeds.len)];
        @memcpy(buffer[0..seed.len], seed);
        var len = seed.len;
        const edits = random.intRangeAtMost(usize, 1, 4);
        for (0..edits) |_| switch (random.uintLessThan(u8, 4)) {
            0 => if (len > 0) {
                const pos = random.uintLessThan(usize, len);
                buffer[pos] ^= @as(u8, 1) << random.int(u3);
            },
            1 => if (len > 0) {
                len = random.uintLessThan(usize, len);
            },
            2 => if (len < buffer.len) {
                const pos = random.uintLessThan(usize, len + 1);
                std.mem.copyBackwards(u8, buffer[pos + 1 .. len + 1], buffer[pos..len]);
                buffer[pos] = random.int(u8);
                len += 1;
            },
            3 => if (len > 0) {
                const pos = random.uintLessThan(usize, len);
                std.mem.copyForwards(u8, buffer[pos .. len - 1], buffer[pos + 1 .. len]);
                len -= 1;
            },
            else => unreachable,
        };
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        _ = try check(arena.allocator(), buffer[0..len]);
    }
}

fn lex(allocator: std.mem.Allocator, input: []const u8) !bool {
    var lexer = bespoke.compiler.Lexer.init(allocator, input);
    defer lexer.deinit();
    // Each byte can cause at most one token and one indentation token.
    for (0..2 * input.len + 1) |_| {
        const token = lexer.next() catch return false;
        if (token.tag == .eof) return true;
    }
    return error.LexerDidNotReachEnd;
}

fn parse(allocator: std.mem.Allocator, input: []const u8) !bool {
    var lexer = bespoke.compiler.Lexer.init(allocator, input);
    defer lexer.deinit();
    var parser = bespoke.compiler.Parser.init(allocator, &lexer) catch return false;
    _ = parser.parse_program() catch return false;
    return true;
}

fn compile(allocator: std.mem.Allocator, input: []const u8) !bool {
    return bespoke.compiler.check_source(allocator, input).is_valid;
}

fn loadPackage(allocator: std.mem.Allocator, input: []const u8) !bool {
    var world = try bespoke.World.init(allocator, 256 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var reader: std.Io.Reader = .fixed(input);
    var program = bespoke.package.load_package(allocator, &reader, &world, &spatial) catch return false;
    program.deinit();
    return true;
}

fn loadSave(allocator: std.mem.Allocator, input: []const u8) !bool {
    var world = try bespoke.World.init(allocator, 256 * 1024);
    defer world.deinit();
    var reader: std.Io.Reader = .fixed(input);
    _ = bespoke.save.read_save_state(allocator, &reader, &world, null, null) catch return false;
    return true;
}

fn parseScore(allocator: std.mem.Allocator, input: []const u8) !bool {
    var accepted = false;
    for ([_]bespoke.mml.TrackKind{ .melodic, .percussion }) |kind| {
        var diagnostic: bespoke.mml.Diagnostic = .{};
        var score = bespoke.mml.parse(allocator, input, kind, &diagnostic) catch continue;
        score.deinit();
        accepted = true;
    }
    return accepted;
}

fn interpret(allocator: std.mem.Allocator, input: []const u8) !bool {
    var world = try bespoke.World.init(allocator, 256 * 1024);
    defer world.deinit();
    const actor = try world.intern_entity("Hero");
    const item = try world.intern_entity("BrassKey");
    const carries = try world.intern_relation("Carries", .set);
    try world.remember(actor, carries, item.to_int(), 0);
    const scope = bespoke.command.Scope.gather(&world, null, null, actor);
    const frames = bespoke.command.FrameList.build(&.{});
    var interpreter: bespoke.command.Interpreter = .{};
    const outcome = interpreter.interpret(&world, &.{}, frames.slice(), &scope, input);
    var reply: [256]u8 = undefined;
    _ = outcome.message(&world, &reply);
    return outcome == .command;
}

test "P39-01 lexer" {
    try campaign(lex, &.{ script, values });
}

test "P39-01 parser" {
    try campaign(parse, &.{ script, values });
}

test "P39-01 codegen" {
    try campaign(compile, &.{ script, values });
}

test "P39-01 package loader" {
    try campaign(loadPackage, &.{ package, axis_package, red_line_package, dilemma_package, drift_package, appeal_package, art_package, sprite_package, area_package, handler_chain_package, bound_body_package });
}

/// Malformed art sections (P46-01): the version 24 fixture with one field broken each. Every
/// seed must be refused with the error that names it before mutation starts from them.
const art_breaks = [_]struct { seed: []const u8, err: anyerror }{
    .{ .seed = @embedFile("fixtures/fuzz/image-palette.bspk"), .err = error.InvalidImagePalette },
    .{ .seed = @embedFile("fixtures/fuzz/image-count.bspk"), .err = error.InvalidImageCount },
    .{ .seed = @embedFile("fixtures/fuzz/image-name.bspk"), .err = error.InvalidImageName },
    .{ .seed = @embedFile("fixtures/fuzz/image-frame.bspk"), .err = error.InvalidImageSize },
    .{ .seed = @embedFile("fixtures/fuzz/image-size.bspk"), .err = error.InvalidImageSize },
    .{ .seed = @embedFile("fixtures/fuzz/image-index.bspk"), .err = error.InvalidImageIndex },
};

test "P46-01 package loader refuses malformed art" {
    var seeds: [art_breaks.len][]const u8 = undefined;
    for (art_breaks, &seeds) |b, *seed| {
        seed.* = b.seed;
        var world = try bespoke.World.init(testing.allocator, 256 * 1024);
        defer world.deinit();
        var reader: std.Io.Reader = .fixed(b.seed);
        try testing.expectError(b.err, bespoke.package.load_package(testing.allocator, &reader, &world, null));
    }
    try mutate(loadPackage, &seeds);
}

test "P39-01 save loader" {
    try campaign(loadSave, &.{save});
}

test "P39-01 MML" {
    try campaign(parseScore, &.{ melody, drums });
}

test "P39-01 command interpreter" {
    try campaign(interpret, &.{command});
}

/// PNG import (P46-04): a seed must decode; a mutation may be refused, never crash. Decoded
/// pixels are also mapped onto a palette, so the mapping sees whatever the decoder lets through.
fn decodePng(allocator: std.mem.Allocator, input: []const u8) !bool {
    var rgba = bespoke.png.decode(allocator, input) catch return false;
    defer rgba.deinit(allocator);
    var palette = std.ArrayListUnmanaged(bespoke.image.Colour).empty;
    defer palette.deinit(allocator);
    try palette.append(allocator, .{ .r = 0, .g = 0, .b = 0 });
    var where = bespoke.art_import.Where{};
    if (bespoke.art_import.map(allocator, rgba, &palette, &where)) |pixels| allocator.free(pixels) else |_| {}
    return true;
}

test "P46-04 PNG decoder" {
    try campaign(decodePng, &.{ png_indexed, png_rgba, png_grey, png_colours });
}

/// The same decoder with every chunk's CRC recomputed first, so a mutation reaches the header,
/// palette, inflate, and filter code instead of stopping at the checksum.
fn decodePngResealed(allocator: std.mem.Allocator, input: []const u8) !bool {
    const copy = try allocator.dupe(u8, input);
    defer allocator.free(copy);
    var at: usize = 8;
    while (at + 12 <= copy.len) {
        const len = std.mem.readInt(u32, copy[at..][0..4], .big);
        if (len > copy.len - at - 12) break;
        const crc = std.hash.Crc32.hash(copy[at + 4 .. at + 8 + len]);
        std.mem.writeInt(u32, copy[at + 8 + len ..][0..4], crc, .big);
        at += 12 + len;
    }
    return decodePng(allocator, copy);
}

test "P46-04 PNG decoder past its checksums" {
    try campaign(decodePngResealed, &.{ png_indexed, png_rgba, png_grey, png_colours });
}
