//! Bounded mutation tests for local engine input boundaries (P39-01).
const std = @import("std");
const bespoke = @import("bespoke");
const testing = std.testing;

const max_input = 4096;
const script = @embedFile("fixtures/fuzz/room.bespoke");
const values = @embedFile("fixtures/fuzz/values.bespoke");
const package = @embedFile("fixtures/compat/format-1-package.bspk");
const dice_save = @embedFile("fixtures/compat/format-1-save-dice.sav");
const each_save = @embedFile("fixtures/compat/format-1-save-each.sav");
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
    try campaign(loadPackage, &.{package});
}

/// The same loader with the package checksum recomputed first, so a mutation reaches the
/// section table, each section's reader, and the VM tick loop instead of stopping at the CRC
/// (P48-17, D-189).
fn loadPackageResealed(allocator: std.mem.Allocator, input: []const u8) !bool {
    const copy = try allocator.dupe(u8, input);
    defer allocator.free(copy);
    const header_len = @sizeOf(bespoke.package.PackageHeader);
    if (copy.len >= header_len) std.mem.writeInt(u32, copy[8..12], std.hash.Crc32.hash(copy[header_len..]), .little);
    var world = try bespoke.World.init(allocator, 256 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var reader: std.Io.Reader = .fixed(copy);
    var program = bespoke.package.load_package(allocator, &reader, &world, &spatial) catch return false;
    defer program.deinit();
    var vm = bespoke.host.init_vm(allocator, &world, &spatial, &program) catch return false;
    defer vm.deinit();
    _ = bespoke.host.start_script(&world, &spatial, &vm, &program) catch return false;
    _ = bespoke.host.tick(&vm, &program) catch return false;
    _ = bespoke.host.tick(&vm, &program) catch return false;
    return true;
}

test "P48-17 package loader past its checksum" {
    try campaign(loadPackageResealed, &.{package});
}

test "P39-01 save loader" {
    try campaign(loadSave, &.{ dice_save, each_save });
}

/// The same loader with the save checksum recomputed first, so a mutation reaches the world,
/// spatial, and VM readers (including rule flags and `when each` rows) instead of stopping
/// at the envelope CRC (P48-24).
fn loadSaveResealed(allocator: std.mem.Allocator, input: []const u8) !bool {
    const copy = try allocator.dupe(u8, input);
    defer allocator.free(copy);
    if (copy.len >= 16) std.mem.writeInt(u32, copy[8..12], std.hash.Crc32.hash(copy[16..]), .little);
    var world = try bespoke.World.init(allocator, 256 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var chunk = bespoke.bytecode.BytecodeChunk.init(allocator);
    defer chunk.deinit();
    var vm = bespoke.VM.init(allocator, &world, &chunk);
    defer vm.deinit();
    const clause = [_]bespoke.world.PatternClause{.{
        .relation = bespoke.world.RelationKind.from_int(1),
        .subject = .{ .variable = 0 },
        .object = .{ .wildcard = {} },
    }};
    _ = try vm.add_reactive_rule(.none, &clause, 50, 0);
    vm.reactive_rules.items[0].each = true;
    var reader: std.Io.Reader = .fixed(copy);
    _ = bespoke.save.read_save_state(allocator, &reader, &world, &spatial, &vm) catch return false;
    return true;
}

test "P48-24 save loader past its checksum" {
    try campaign(loadSaveResealed, &.{ dice_save, each_save });
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

/// The art codec (P48-12, D-182): a seed must decode; a mutation may be refused, never crash
/// or read past its bytes. The size comes from the stream's own header, bounded as a package's
/// image record bounds it.
fn decodeQoi(allocator: std.mem.Allocator, input: []const u8) !bool {
    const size = bespoke.qoi.header_size(input) catch return false;
    if (size.width == 0 or size.height == 0 or @as(u64, size.width) * size.height > bespoke.image.MAX_SHEET_PIXELS) return false;
    const pixels = bespoke.qoi.decode(allocator, input, size.width, size.height) catch return false;
    allocator.free(pixels);
    return true;
}

test "P48-12 QOI decoder" {
    // Seeds: the PNG fixtures re-encoded, so every op appears.
    var seeds: [3][]u8 = undefined;
    for (&seeds, [_][]const u8{ png_indexed, png_rgba, png_grey }) |*seed, png_bytes| {
        var rgba = try bespoke.png.decode(testing.allocator, png_bytes);
        defer rgba.deinit(testing.allocator);
        var where = bespoke.art_import.Where{};
        const pixels = try bespoke.art_import.to_pixels(testing.allocator, rgba, null, &where);
        defer testing.allocator.free(pixels);
        seed.* = try bespoke.qoi.encode(testing.allocator, pixels, rgba.width, rgba.height);
    }
    defer for (seeds) |seed| testing.allocator.free(seed);
    try campaign(decodeQoi, &.{ seeds[0], seeds[1], seeds[2] });
}

test "P46-04 PNG decoder past its checksums" {
    try campaign(decodePngResealed, &.{ png_indexed, png_rgba, png_grey, png_colours });
}
