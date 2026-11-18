const std = @import("std");
const bespoke = @import("bespoke");
const harbour = @import("game.zig");
const Game = harbour.Game;

fn flush(out: *std.Io.Writer, game: *Game) !void {
    try out.writeAll(game.text[0..game.text_len]);
    game.text_len = 0;
}

fn action(out: *std.Io.Writer, game: *Game, line: []const u8) !void {
    try out.print("> {s}\n", .{line});
    try game.command(line);
    try flush(out, game);
}

fn move(out: *std.Io.Writer, game: *Game, line: []const u8, destination: usize) !void {
    try out.print("> {s}\n", .{line});
    try game.move(line, destination);
    try flush(out, game);
}

fn demo(init: std.process.Init, out: *std.Io.Writer, save_path: []const u8) !void {
    var game: Game = undefined;
    try game.init(init.gpa);
    defer game.deinit();
    try flush(out, &game);
    try game.advance(8);
    if (!game.has("Quay", "PortOpen") or game.property("Dispatcher", "HarbourGold").? <= 10) return error.SocietyDidNotAdvance;
    try flush(out, &game);
    try action(out, &game, "signal packet");
    if (game.has("Packet", "PacketClear")) return error.PrematureClear;
    for (harbour.stops, 0..) |stop, i| {
        if (i != 0) try move(out, &game, if (i % 2 == 0) "go to forward" else "go forward", i);
        try action(out, &game, stop.task);
        if (i == 5) {
            const checkpoint_gold = game.property("Dispatcher", "HarbourGold");
            const checkpoint_fatigue = game.property("Dispatcher", "HarbourFatigue");
            {
                const file = try std.Io.Dir.cwd().createFile(init.io, save_path, .{ .exclusive = true });
                defer file.close(init.io);
                var buf: [4096]u8 = undefined;
                var writer = file.writer(init.io, &buf);
                _ = try bespoke.save.write_save_state(init.gpa, &writer.interface, &game.world, &game.spatial, &game.vm, .{ .timestamp = 0 });
                try writer.interface.flush();
            }
            try out.writeAll("[Saved at Customs]\n");
            try move(out, &game, "go forward", 6);
            try action(out, &game, "turn lever");
            try game.advance(12);
            if (!game.has("PumpHouse", "Cleared")) return error.MissingPumpProgress;
            if (game.property("Dispatcher", "HarbourGold") == checkpoint_gold and
                game.property("Dispatcher", "HarbourFatigue") == checkpoint_fatigue) return error.SocietyDidNotAdvance;
            {
                const file = try std.Io.Dir.cwd().openFile(init.io, save_path, .{});
                defer file.close(init.io);
                var buf: [4096]u8 = undefined;
                var reader = file.reader(init.io, &buf);
                _ = try bespoke.save.read_save_state(init.gpa, &reader.interface, &game.world, &game.spatial, &game.vm);
            }
            game.interpreter = .{};
            if (game.room() != 5 or game.has("PumpHouse", "Cleared") or
                !game.has("Customs", "Cleared") or game.property("Dispatcher", "HarbourGold") != checkpoint_gold or
                game.property("Dispatcher", "HarbourFatigue") != checkpoint_fatigue)
                return error.SaveDidNotRestore;
            try out.writeAll("[Restored Customs, pump and society state]\n");
        }
    }
    if (!game.has("Packet", "PacketClear")) return error.UnclearedPacket;
}

fn benchmark(init: std.process.Init, out: *std.Io.Writer) !void {
    for ([_]usize{ 0, 4096 }) |extra| {
        var game: Game = undefined;
        try game.init(init.gpa);
        defer game.deinit();
        try game.prepareSample(extra);
        const initial = game.world.fact_count();
        var times: [harbour.samples]i96 = undefined;
        for (&times) |*ns| {
            const start = std.Io.Timestamp.now(init.io, .awake);
            try game.advance(harbour.sample_ticks);
            ns.* = start.durationTo(std.Io.Timestamp.now(init.io, .awake)).toNanoseconds();
        }
        if (!game.has("Packet", "PacketClear")) return error.UnclearedPacket;
        std.mem.sort(i96, &times, {}, std.sort.asc(i96));
        try out.print("{{\"extra\":{d},\"facts\":{d},\"endFacts\":{d},\"ticks\":{d},\"ms\":{d}}}\n", .{
            extra,                                                              initial, game.world.fact_count(), harbour.sample_ticks,
            @as(f64, @floatFromInt(times[times.len / 2])) / std.time.ns_per_ms,
        });
    }
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const option = args.next() orelse return error.ExpectedSavePathOrBenchmark;
    var writer = std.Io.File.stdout().writer(init.io, &.{});
    if (std.mem.eql(u8, option, "--bench")) return benchmark(init, &writer.interface);
    return demo(init, &writer.interface, option);
}
