//! Characterization goldens for the proofs of concept (P32-07, docs/SEPARATION.md).
//!
//! Each proof's headless run is a scripted demonstration with assertions. This test captures
//! its full transcript and compares it byte for byte with `proofs/golden/<proof>.txt`, so that
//! extracting a mechanic from a proof into the engine (or purging proof content from the
//! engine) cannot silently change what the proof does or says.
//!
//! Headless runs are deterministic (integer ticks, seeded PRNG, no wall-clock reads), so no
//! normalization is applied. If a proof gains run-varying output, normalize it here rather
//! than weakening the comparison.
//!
//! Regenerate deliberately, and review the diff: `zig build test-proofs -Dupdate-goldens`.
//! On a mismatch the actual output is written to `proofs/golden/<proof>.actual.txt`.
const std = @import("std");
const ListWriter = @import("bespoke").ListWriter;
const options = @import("golden_options");

const tavern_heist = @import("tavern_heist.zig");
const spitting_contest = @import("spitting_contest.zig");
const borrowed_beard = @import("borrowed_beard.zig");
const sword_fighting = @import("sword_fighting.zig");
const village = @import("village.zig");
const lamp_point = @import("lamp_point.zig");
const three_tides = @import("three_tides.zig");
const weathercock = @import("weathercock.zig");
const bell_tower = @import("bell_tower.zig");
const grog_puzzle = @import("grog_puzzle.zig");
const saltmarket = @import("saltmarket.zig");
const grid_puzzle = @import("grid_puzzle.zig");
const observatory_puzzle = @import("observatory_puzzle.zig");
const word_foundry = @import("word_foundry.zig");
const golden_digest = @import("golden_digest.zig");
const bespoke = @import("bespoke");

/// Every proof runner writes through `std.Io.Writer` since Zig 0.16 (P37-01).
const Writer = *std.Io.Writer;

fn tavern(allocator: std.mem.Allocator, w: anytype) anyerror!void {
    try tavern_heist.run(allocator, std.testing.io, w, true);
}

const RunFn = *const fn (std.mem.Allocator, Writer) anyerror!void;

/// Proof runners take `writer: anytype`; this instantiates one for the test's writer type so
/// the table can hold plain function pointers.
fn bind(comptime f: anytype) RunFn {
    return &struct {
        fn call(allocator: std.mem.Allocator, w: Writer) anyerror!void {
            return f(allocator, w);
        }
    }.call;
}

const proofs = [_]struct { name: []const u8, run: RunFn }{
    .{ .name = "tavern_heist", .run = bind(tavern) },
    .{ .name = "spitting_contest", .run = bind(spitting_contest.run_headless) },
    .{ .name = "borrowed_beard", .run = bind(borrowed_beard.run_headless) },
    .{ .name = "sword_fighting", .run = bind(sword_fighting.run_headless) },
    .{ .name = "village", .run = bind(village.run_headless) },
    .{ .name = "lamp_point", .run = bind(lamp_point.run_headless) },
    .{ .name = "three_tides", .run = bind(three_tides.run_headless) },
    .{ .name = "weathercock", .run = bind(weathercock.run_headless) },
    .{ .name = "bell_tower", .run = bind(bell_tower.run_headless) },
    .{ .name = "grog_puzzle", .run = bind(grog_puzzle.run_headless) },
    .{ .name = "saltmarket", .run = bind(saltmarket.run_headless) },
    .{ .name = "grid_puzzle", .run = bind(grid_puzzle.run_headless) },
    .{ .name = "observatory_puzzle", .run = bind(observatory_puzzle.run_headless) },
    .{ .name = "word_foundry", .run = bind(word_foundry.run_headless) },
};

fn first_difference(expected: []const u8, actual: []const u8) struct { line: usize, want: []const u8, got: []const u8 } {
    var want_it = std.mem.splitScalar(u8, expected, '\n');
    var got_it = std.mem.splitScalar(u8, actual, '\n');
    var line: usize = 1;
    while (true) : (line += 1) {
        const want = want_it.next();
        const got = got_it.next();
        if (want == null and got == null) return .{ .line = line, .want = "", .got = "" };
        if (want == null or got == null or !std.mem.eql(u8, want.?, got.?)) {
            return .{ .line = line, .want = want orelse "<end of golden>", .got = got orelse "<end of output>" };
        }
    }
}

test "P32-07: every proof's headless transcript matches its golden file" {
    const allocator = std.testing.allocator;
    var dir = try std.Io.Dir.cwd().createDirPathOpen(std.testing.io, options.golden_dir, .{});
    defer dir.close(std.testing.io);

    var failures: usize = 0;
    for (proofs) |p| {
        var out = std.array_list.Managed(u8).init(allocator);
        defer out.deinit();
        var lw1 = ListWriter.init(&out);
        try p.run(allocator, &lw1.writer);

        var golden_name_buf: [64]u8 = undefined;
        var actual_name_buf: [64]u8 = undefined;
        const golden_name = try std.fmt.bufPrint(&golden_name_buf, "{s}.txt", .{p.name});
        const actual_name = try std.fmt.bufPrint(&actual_name_buf, "{s}.actual.txt", .{p.name});

        if (options.update_goldens) {
            try dir.writeFile(std.testing.io, .{ .sub_path = golden_name, .data = out.items });
            dir.deleteFile(std.testing.io, actual_name) catch {};
            continue;
        }

        const expected = dir.readFileAlloc(std.testing.io, golden_name, allocator, .limited(1 << 22)) catch |err| {
            std.debug.print("golden {s}/{s} unreadable ({s}); run `zig build test-proofs -Dupdate-goldens`\n", .{ options.golden_dir, golden_name, @errorName(err) });
            failures += 1;
            continue;
        };
        defer allocator.free(expected);

        if (std.mem.eql(u8, expected, out.items)) {
            dir.deleteFile(std.testing.io, actual_name) catch {};
            continue;
        }
        failures += 1;
        try dir.writeFile(std.testing.io, .{ .sub_path = actual_name, .data = out.items });
        const d = first_difference(expected, out.items);
        std.debug.print(
            "\nproof '{s}' differs from its golden at line {d}:\n  golden: {s}\n  actual: {s}\n  full output: {s}/{s}\n",
            .{ p.name, d.line, d.want, d.got, options.golden_dir, actual_name },
        );
    }
    try std.testing.expectEqual(@as(usize, 0), failures);
}

test "P32-07: the golden comparison reports the first differing line" {
    const d = first_difference("a\nb\nc", "a\nx\nc");
    try std.testing.expectEqual(@as(usize, 2), d.line);
    try std.testing.expectEqualStrings("b", d.want);
    try std.testing.expectEqualStrings("x", d.got);
    try std.testing.expectEqualStrings("<end of output>", first_difference("a\nb", "a").got);
}

/// Changes one final fact: a scalar no transcript line prints.
fn tamper_one_fact(world: *bespoke.World) anyerror!void {
    const rel = try world.intern_relation("GoldenTamper", .property);
    _ = try world.remember(try world.intern_entity("GoldenTamper"), rel, 1, 0);
}

test "P34-01: one altered final fact fails a proof's golden on its digest line alone" {
    if (options.update_goldens) return;
    const allocator = std.testing.allocator;
    var dir = try std.Io.Dir.cwd().openDir(std.testing.io, options.golden_dir, .{});
    defer dir.close(std.testing.io);
    for (proofs) |p| {
        var name_buf: [64]u8 = undefined;
        const expected = try dir.readFileAlloc(std.testing.io, try std.fmt.bufPrint(&name_buf, "{s}.txt", .{p.name}), allocator, .limited(1 << 22));
        defer allocator.free(expected);

        golden_digest.tamper = tamper_one_fact;
        defer golden_digest.tamper = null;
        var out = std.array_list.Managed(u8).init(allocator);
        defer out.deinit();
        var lw2 = ListWriter.init(&out);
        try p.run(allocator, &lw2.writer);

        // The transcript differs, and only on a "final facts" line.
        try std.testing.expect(!std.mem.eql(u8, expected, out.items));
        const d = first_difference(expected, out.items);
        try std.testing.expect(std.mem.startsWith(u8, d.want, "final facts: "));
        try std.testing.expect(std.mem.startsWith(u8, d.got, "final facts: "));
    }
}
