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
const options = @import("golden_options");

const tavern_heist = @import("tavern_heist.zig");
const spitting_contest = @import("spitting_contest.zig");
const gk3_moustache = @import("gk3_moustache.zig");
const sword_fighting = @import("sword_fighting.zig");
const village = @import("village.zig");
const goat_puzzle = @import("goat_puzzle.zig");
const dott_puzzle = @import("dott_puzzle.zig");
const darko_puzzle = @import("darko_puzzle.zig");
const loom_puzzle = @import("loom_puzzle.zig");
const grog_puzzle = @import("grog_puzzle.zig");
const atlantis_puzzle = @import("atlantis_puzzle.zig");

const Writer = std.ArrayList(u8).Writer;

fn tavern(allocator: std.mem.Allocator, w: anytype) anyerror!void {
    try tavern_heist.run(allocator, w, true);
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
    .{ .name = "gk3_moustache", .run = bind(gk3_moustache.run_headless) },
    .{ .name = "sword_fighting", .run = bind(sword_fighting.run_headless) },
    .{ .name = "village", .run = bind(village.run_headless) },
    .{ .name = "goat_puzzle", .run = bind(goat_puzzle.run_headless) },
    .{ .name = "dott_puzzle", .run = bind(dott_puzzle.run_headless) },
    .{ .name = "darko_puzzle", .run = bind(darko_puzzle.run_headless) },
    .{ .name = "loom_puzzle", .run = bind(loom_puzzle.run_headless) },
    .{ .name = "grog_puzzle", .run = bind(grog_puzzle.run_headless) },
    .{ .name = "atlantis_puzzle", .run = bind(atlantis_puzzle.run_headless) },
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
    var dir = try std.fs.cwd().makeOpenPath(options.golden_dir, .{});
    defer dir.close();

    var failures: usize = 0;
    for (proofs) |p| {
        var out = std.ArrayList(u8).init(allocator);
        defer out.deinit();
        try p.run(allocator, out.writer());

        var golden_name_buf: [64]u8 = undefined;
        var actual_name_buf: [64]u8 = undefined;
        const golden_name = try std.fmt.bufPrint(&golden_name_buf, "{s}.txt", .{p.name});
        const actual_name = try std.fmt.bufPrint(&actual_name_buf, "{s}.actual.txt", .{p.name});

        if (options.update_goldens) {
            try dir.writeFile(.{ .sub_path = golden_name, .data = out.items });
            dir.deleteFile(actual_name) catch {};
            continue;
        }

        const expected = dir.readFileAlloc(allocator, golden_name, 1 << 22) catch |err| {
            std.debug.print("golden {s}/{s} unreadable ({s}); run `zig build test-proofs -Dupdate-goldens`\n", .{ options.golden_dir, golden_name, @errorName(err) });
            failures += 1;
            continue;
        };
        defer allocator.free(expected);

        if (std.mem.eql(u8, expected, out.items)) {
            dir.deleteFile(actual_name) catch {};
            continue;
        }
        failures += 1;
        try dir.writeFile(.{ .sub_path = actual_name, .data = out.items });
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
