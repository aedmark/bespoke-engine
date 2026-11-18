const std = @import("std");
const bench = @import("workload.zig");

pub fn main(init: std.process.Init) !void {
    var writer = std.Io.File.stdout().writer(init.io, &.{});
    const out = &writer.interface;
    for (bench.cases) |case| {
        var load: bench.Workload = undefined;
        try load.init(init.gpa, case);
        defer load.deinit();
        var durations: [bench.samples]i96 = undefined;
        for (&durations) |*duration| {
            const start = std.Io.Timestamp.now(init.io, .awake);
            try load.advance(bench.ticks_per_sample);
            duration.* = start.durationTo(std.Io.Timestamp.now(init.io, .awake)).toNanoseconds();
        }
        try load.verify(bench.samples * bench.ticks_per_sample);
        std.mem.sort(i96, &durations, {}, std.sort.asc(i96));
        const ns = durations[durations.len / 2];
        if (ns <= 0) return error.InvalidBenchmarkTime;
        try out.print(
            "{{\"name\":\"{s}\",\"facts\":{d},\"entities\":{d},\"fibers\":{d},\"ticks\":{d},\"samples\":{d},\"ms\":{d}}}\n",
            .{ case.name, load.facts(), load.entities(), load.fibers(), bench.ticks_per_sample, bench.samples, @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms },
        );
    }
}
