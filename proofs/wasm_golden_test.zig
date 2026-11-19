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
const ListWriter = @import("bespoke").ListWriter;
const bespoke = @import("bespoke");
const options = @import("golden_options");
const wasm = bespoke.wasm;
const wasm_deck = @import("wasm_deck.zig");
const canvas = bespoke.display.canvas;
const band = bespoke.display.band;

const GOLDEN_NAME = "wasm.txt";
const ACTUAL_NAME = "wasm.actual.txt";
const DECK_COUNT: u8 = wasm_deck.decks.len;

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
    .{ .label = "scrubbed", .step = .{ .event = .{ .kind = .pointer_down, .x = 640, .y = 60 } } },
    .{ .label = "rewound", .step = .{ .event = .{ .kind = .key_down, .key_code = 'R' } } },
    .{ .label = "paused", .step = .{ .event = .{ .kind = .key_down, .key_code = ' ' } } },
    // The state inspector (P30-04, D-070): open it, move the selection, and close it.
    .{ .label = "inspector", .step = .{ .event = .{ .kind = .key_down, .key_code = 'I' } } },
    .{ .label = "inspector-next", .step = .{ .event = .{ .kind = .key_down, .key_code = wasm.InspectorKey.right } } },
    .{ .label = "inspector-closed", .step = .{ .event = .{ .kind = .key_down, .key_code = 'I' } } },
    .{ .label = "two-finger", .step = .{ .event = .{ .kind = .touch_start, .x = 100, .y = 100, .touch_points = 2 } } },
};

fn tick(rt: *wasm.WasmRuntime, n: u8) !void {
    for (0..n) |_| _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'N' });
}

fn record(allocator: std.mem.Allocator, out: *std.array_list.Managed(u8), index: u8) !void {
    const rt = try allocator.create(wasm.WasmRuntime);
    defer allocator.destroy(rt);
    rt.* = try Decks.init(allocator, index);
    defer rt.deinit();

    // P43-05: every beat is band-checked as it is drawn. The browser frame is the desktop
    // window's frame at 1280x720 (D-097), so the probes read it the way the render golden reads
    // a proof scene, and the banner's own log lines are chrome the rule skips (D-127).
    var text_probe = canvas.TextProbe{};
    var rect_probe = canvas.RectProbe{};
    const probes = wasm.WasmRuntime.CanvasProbes{ .text = &text_probe, .rect = &rect_probe };

    for (SCRIPT) |entry| {
        switch (entry.step) {
            .ticks => |n| try tick(rt, n),
            .event => |ev| _ = try rt.dispatch_event(ev),
            .walks => {
                // Every mark on stage in order, letting the player arrive at each. Positions come
                // from the runtime's own projection (D-069), as a visitor's clicks would.
                const count = rt.spatial.graph.waypoints.items.len;
                for (0..count) |i| {
                    const wp = rt.spatial.graph.waypoints.items[i];
                    const proj = rt.projection();
                    if (!proj.shows(wp.room)) continue;
                    const pt = proj.point(wp.pos.x, wp.pos.y);
                    _ = try rt.dispatch_event(.{ .kind = .pointer_down, .x = pt.x, .y = pt.y });
                    try tick(rt, 4);
                }
            },
            .hotspots => {
                for (rt.spatial.hotspots.items) |hs| {
                    const proj = rt.projection();
                    if (!proj.shows(hs.room)) continue;
                    const pt = proj.point(hs.pos.x, hs.pos.y);
                    _ = try rt.dispatch_event(.{ .kind = .pointer_down, .x = pt.x, .y = pt.y });
                }
            },
        }
        text_probe.count = 0;
        rect_probe.count = 0;
        rect_probe.overflowed = false;
        rt.render_frame_probed(probes);
        const check = band.Check.measure(rt.window.height, &text_probe, &rect_probe);
        if (check.verdict != .clear) {
            var label_buf: [96]u8 = undefined;
            check.report(try std.fmt.bufPrint(&label_buf, "deck/{d}/{s}", .{ index, entry.label }));
            return switch (check.verdict) {
                .overflow => error.RectProbeOverflow,
                .art => error.ArtInMessageBand,
                .text => error.TextInMessageBand,
                .clear => unreachable,
            };
        }
        var lw1 = ListWriter.init(out);
        try lw1.writer.print("deck/{d}/{s}: {x:0>16} facts={d} tick={d} banner=\"{s}\"\n", .{
            index,
            entry.label,
            std.hash.Wyhash.hash(0, rt.framebuffer),
            rt.world.fact_count(),
            rt.clock(),
            rt.get_banner(),
        });
    }
}

test "P32-04: every proof deck shows the browser frames recorded in its wasm golden" {
    const allocator = std.testing.allocator;
    var dir = try std.Io.Dir.cwd().createDirPathOpen(std.testing.io, options.golden_dir, .{});
    defer dir.close(std.testing.io);

    var actual = std.array_list.Managed(u8).init(allocator);
    defer actual.deinit();
    var index: u8 = 0;
    while (index < DECK_COUNT) : (index += 1) try record(allocator, &actual, index);

    if (options.update_goldens) {
        try dir.writeFile(std.testing.io, .{ .sub_path = GOLDEN_NAME, .data = actual.items });
        dir.deleteFile(std.testing.io, ACTUAL_NAME) catch {};
        return;
    }
    const expected = dir.readFileAlloc(std.testing.io, GOLDEN_NAME, allocator, .limited(1 << 20)) catch |err| {
        std.debug.print("wasm golden {s}/{s} unreadable ({s}); run `zig build test-proofs -Dupdate-goldens`\n", .{ options.golden_dir, GOLDEN_NAME, @errorName(err) });
        return error.WasmGoldenMissing;
    };
    defer allocator.free(expected);
    if (std.mem.eql(u8, expected, actual.items)) {
        dir.deleteFile(std.testing.io, ACTUAL_NAME) catch {};
        return;
    }
    try dir.writeFile(std.testing.io, .{ .sub_path = ACTUAL_NAME, .data = actual.items });
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
