//! Browser-runtime characterization for the proof decks (P32-04, docs/SEPARATION.md).
//!
//! Each deck of the WebAssembly runtime is loaded natively and driven through a fixed script
//! of browser events (walks to every mark, a verb cycle, clicks on every prop, the catalyst
//! key, ticks, a scrub, a rewind, a pause). After each step the canvas pixels, the fact count,
//! the tick, and the banner are recorded and compared with `proofs/golden/wasm.txt`, so
//! moving the decks out of the engine (P32-04) cannot change what the browser shows.
//!
//! Regenerate deliberately: `zig build test-proofs -Dupdate-goldens`, then review the diff.
//! On a mismatch, `proofs/golden/wasm.actual.txt` is written beside the golden.
const std = @import("std");
const bespoke = @import("bespoke");
const options = @import("golden_options");
const wasm = bespoke.wasm;
const wasm_deck = @import("wasm_deck.zig");

const GOLDEN_NAME = "wasm.txt";
const ACTUAL_NAME = "wasm.actual.txt";
const DECK_COUNT: u8 = 7;

/// How a deck is loaded. P32-04 changes where decks are defined; only this adapter changes.
const Decks = struct {
    fn init(allocator: std.mem.Allocator, index: u8) !wasm.WasmRuntime {
        return wasm.WasmRuntime.init(allocator, &wasm_deck.decks, index);
    }
};

const Step = union(enum) {
    walks,
    hotspots,
    event: wasm.BrowserInputEvent,
    ticks: u8,
};

const SCRIPT = [_]struct { label: []const u8, step: Step }{
    .{ .label = "loaded", .step = .{ .ticks = 0 } },
    .{ .label = "walked", .step = .walks },
    .{ .label = "verb", .step = .{ .event = .{ .kind = .right_click } } },
    .{ .label = "props", .step = .hotspots },
    .{ .label = "catalyst", .step = .{ .event = .{ .kind = .key_down, .key_code = 'S' } } },
    .{ .label = "ticked", .step = .{ .ticks = 3 } },
    .{ .label = "scrubbed", .step = .{ .event = .{ .kind = .pointer_down, .x = 320, .y = 30 } } },
    .{ .label = "rewound", .step = .{ .event = .{ .kind = .key_down, .key_code = 'R' } } },
    .{ .label = "paused", .step = .{ .event = .{ .kind = .key_down, .key_code = ' ' } } },
    .{ .label = "two-finger", .step = .{ .event = .{ .kind = .touch_start, .x = 100, .y = 100, .touch_points = 2 } } },
};

fn tick(rt: *wasm.WasmRuntime, n: u8) !void {
    for (0..n) |_| _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'N' });
}

fn record(allocator: std.mem.Allocator, out: *std.ArrayList(u8), index: u8) !void {
    const rt = try allocator.create(wasm.WasmRuntime);
    defer allocator.destroy(rt);
    rt.* = try Decks.init(allocator, index);
    defer rt.deinit();

    for (SCRIPT) |entry| {
        switch (entry.step) {
            .ticks => |n| try tick(rt, n),
            .event => |ev| _ = try rt.dispatch_event(ev),
            .walks => {
                // Every mark in order, letting the player arrive at each.
                const count = rt.spatial.graph.waypoints.items.len;
                for (0..count) |i| {
                    const wp = rt.spatial.graph.waypoints.items[i];
                    const pt = wasm.world_to_canvas(wp.pos.x, wp.pos.y);
                    _ = try rt.dispatch_event(.{ .kind = .pointer_down, .x = pt.x, .y = pt.y });
                    try tick(rt, 4);
                }
            },
            .hotspots => {
                for (rt.spatial.hotspots.items) |hs| {
                    const pt = wasm.world_to_canvas(hs.pos.x, hs.pos.y);
                    _ = try rt.dispatch_event(.{ .kind = .pointer_down, .x = pt.x, .y = pt.y });
                }
            },
        }
        rt.render_frame();
        try out.writer().print("deck/{d}/{s}: {x:0>16} facts={d} tick={d} banner=\"{s}\"\n", .{
            index,
            entry.label,
            std.hash.Wyhash.hash(0, &rt.canvas.pixels),
            rt.world.fact_count(),
            rt.world.current_tick,
            rt.get_banner(),
        });
    }
}

test "P32-04: every proof deck shows the browser frames recorded in its wasm golden" {
    const allocator = std.testing.allocator;
    var dir = try std.fs.cwd().makeOpenPath(options.golden_dir, .{});
    defer dir.close();

    var actual = std.ArrayList(u8).init(allocator);
    defer actual.deinit();
    var index: u8 = 0;
    while (index < DECK_COUNT) : (index += 1) try record(allocator, &actual, index);

    if (options.update_goldens) {
        try dir.writeFile(.{ .sub_path = GOLDEN_NAME, .data = actual.items });
        dir.deleteFile(ACTUAL_NAME) catch {};
        return;
    }
    const expected = dir.readFileAlloc(allocator, GOLDEN_NAME, 1 << 20) catch |err| {
        std.debug.print("wasm golden {s}/{s} unreadable ({s}); run `zig build test-proofs -Dupdate-goldens`\n", .{ options.golden_dir, GOLDEN_NAME, @errorName(err) });
        return error.WasmGoldenMissing;
    };
    defer allocator.free(expected);
    if (std.mem.eql(u8, expected, actual.items)) {
        dir.deleteFile(ACTUAL_NAME) catch {};
        return;
    }
    try dir.writeFile(.{ .sub_path = ACTUAL_NAME, .data = actual.items });
    var want_lines = std.mem.splitScalar(u8, expected, '\n');
    var got_lines = std.mem.splitScalar(u8, actual.items, '\n');
    var changed: usize = 0;
    while (true) {
        const want = want_lines.next();
        const got = got_lines.next();
        if (want == null and got == null) break;
        if (want != null and got != null and std.mem.eql(u8, want.?, got.?)) continue;
        changed += 1;
        std.debug.print("\nwasm differs:\n  golden: {s}\n  actual: {s}\n", .{ want orelse "<none>", got orelse "<none>" });
    }
    std.debug.print("\n{d} line(s) differ; record written to {s}/{s}\n", .{ changed, options.golden_dir, ACTUAL_NAME });
    return error.WasmGoldenMismatch;
}
