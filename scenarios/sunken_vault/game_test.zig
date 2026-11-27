//! Native tests for The Sunken Vault (P49-03): turn clock, darkness, timed torch/flood events,
//! save/restore round-trip, hints, and 60 Hz colour cycling on static PNG backdrops.
const std = @import("std");
const bespoke = @import("bespoke");
const testing = std.testing;

const SCRIPT_PATH = "scripts/main.bespoke";

const Game = struct {
    source: []u8,
    world: bespoke.World,
    spatial: bespoke.SpatialSystem,
    compiled: bespoke.CompiledProgram,
    vm: bespoke.VM,
    interp: bespoke.command.Interpreter = .{},
    actor: bespoke.EntityId = .none,

    fn init(self: *Game) !void {
        self.interp = .{};
        self.source = try std.Io.Dir.cwd().readFileAlloc(testing.io, SCRIPT_PATH, testing.allocator, .limited(1 << 20));
        errdefer testing.allocator.free(self.source);
        self.world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
        errdefer self.world.deinit();
        self.spatial = bespoke.SpatialSystem.init(testing.allocator);
        errdefer self.spatial.deinit();
        var files = bespoke.runner.ScriptFiles.for_script(testing.io, SCRIPT_PATH);
        self.compiled = try bespoke.compiler.compile_source_with(testing.allocator, &self.world, &self.spatial, self.source, files.source());
        errdefer self.compiled.deinit();
        self.vm = try bespoke.host.init_vm(testing.allocator, &self.world, &self.spatial, &self.compiled);
        errdefer self.vm.deinit();
        try bespoke.host.initialize_subsystems(&self.world, &self.compiled);
        self.actor = try bespoke.host.start_script(&self.world, &self.spatial, &self.vm, &self.compiled);
        _ = try bespoke.host.tick(&self.vm, &self.compiled);
    }

    fn deinit(self: *Game) void {
        self.vm.deinit();
        self.compiled.deinit();
        self.spatial.deinit();
        self.world.deinit();
        testing.allocator.free(self.source);
    }

    fn command(self: *Game, line: []const u8) !bespoke.host.CommandReply {
        var buf: [256]u8 = undefined;
        const reply = try bespoke.host.run_command(&self.vm, &self.compiled, &self.interp, self.actor, line, &buf);
        if (reply.turn) {
            _ = try bespoke.host.tick(&self.vm, &self.compiled);
            var guard: usize = 0;
            while (self.spatial.is_moving(self.actor) and guard < 256) : (guard += 1) {
                _ = try bespoke.host.tick(&self.vm, &self.compiled);
            }
        }
        return reply;
    }

    fn holds(self: *const Game, relation: []const u8, subject: []const u8, object: ?[]const u8) bool {
        const rel = self.world.lookup_relation(relation) orelse return false;
        const subj = self.world.lookup_entity(subject) orelse return false;
        const obj: ?u32 = if (object) |o| (self.world.lookup_entity(o) orelse return false).to_int() else null;
        return self.world.find_first(subj, rel, obj) != null;
    }

    fn scene(self: *const Game) []const u8 {
        const s = self.vm.current_scene orelse return "";
        return self.world.get_entity_name(s) orelse "";
    }
};

test "the script compiles with turn clock, 6 PNG backdrops, and 4 colour cycles" {
    var game: Game = undefined;
    try game.init();
    defer game.deinit();
    try testing.expect(game.compiled.turn_clock);
    try testing.expectEqual(@as(usize, 6), game.compiled.art.backdrops.len);
    try testing.expectEqual(@as(usize, 4), game.compiled.art.cycles.len);
}

test "refusals take no turn, darkness blocks progress, and torch expires after 18 turns" {
    var game: Game = undefined;
    try game.init();
    defer game.deinit();

    const start_tick = game.world.current_tick;
    try testing.expect(!(try game.command("xyzzy")).turn);
    try testing.expect(!(try game.command("take crown")).turn);
    try testing.expectEqual(start_tick, game.world.current_tick);

    // Grab flint, torch, key; descend unlit into FloodedCrypt.
    try testing.expect((try game.command("east")).turn);
    try testing.expect((try game.command("take flint")).turn);
    try testing.expect((try game.command("take torch")).turn);
    try testing.expect((try game.command("take key")).turn);
    try testing.expect((try game.command("west")).turn);
    try testing.expect((try game.command("down")).turn);
    try testing.expect((try game.command("north")).turn);
    try testing.expectEqualStrings("FloodedCrypt", game.scene());

    // Darkness refuses unlocking or advancing north.
    try testing.expect((try game.command("unlock gate with key")).turn);
    try testing.expect(!game.holds("GateUnlocked", "IronGate", null));
    try testing.expect((try game.command("north")).turn);
    try testing.expectEqualStrings("FloodedCrypt", game.scene());

    // Lighting the torch lasts 18 turns.
    try testing.expect((try game.command("light torch")).turn);
    try testing.expect(game.holds("Burning", "Torch", null));
    for (0..17) |_| _ = try game.command("wait");
    try testing.expect(game.holds("Burning", "Torch", null));
    _ = try game.command("wait");
    try testing.expect(!game.holds("Burning", "Torch", null));
}

test "full victory route with drained sluice and hints" {
    var game: Game = undefined;
    try game.init();
    defer game.deinit();

    var hint_buf: [160]u8 = undefined;
    const h1 = (try bespoke.host.hint(&game.world, &game.compiled, game.actor, bespoke.hint.Tier.fromInt(1).?, &hint_buf)).?;
    try testing.expect(std.mem.indexOf(u8, h1.text, "guardhouse") != null);

    const route = [_][]const u8{
        "east",
        "take flint",
        "take torch",
        "take key",
        "read ledger",
        "west",
        "down",
        "east",
        "turn wheel",
        "west",
        "light torch",
        "north",
        "unlock gate with key",
        "north",
        "take crown",
        "south",
        "south",
        "up",
    };
    for (route) |cmd| try testing.expect((try game.command(cmd)).turn);
    try testing.expectEqualStrings("Courtyard", game.scene());
    try testing.expect(game.holds("Victory", "Scene", null));
    try testing.expect(!game.holds("VaultFlooded", "Vault", null));
    try testing.expect((try bespoke.host.hint(&game.world, &game.compiled, game.actor, bespoke.hint.Tier.fromInt(1).?, &hint_buf)) == null);
}

test "taking crown without draining sluice floods the vault in 9 turns" {
    var game: Game = undefined;
    try game.init();
    defer game.deinit();

    const setup_cmds = [_][]const u8{
        "east", "take flint", "take torch", "take key",
        "west", "down", "light torch", "north",
        "unlock gate with key", "north", "take crown",
    };
    for (setup_cmds) |cmd| try testing.expect((try game.command(cmd)).turn);
    try testing.expect(game.holds("SealBroken", "Vault", null));
    try testing.expect(!game.holds("VaultFlooded", "Vault", null));

    for (0..8) |_| try testing.expect((try game.command("wait")).turn);
    try testing.expect(!game.holds("VaultFlooded", "Vault", null));
    try testing.expect((try game.command("wait")).turn);
    try testing.expect(game.holds("VaultFlooded", "Vault", null));
}

test "mid-run save and restore preserves turn state and finishes to victory" {
    var game: Game = undefined;
    try game.init();
    defer game.deinit();

    const first_half = [_][]const u8{
        "east", "take flint", "take torch", "take key",
        "west", "down", "east", "turn wheel",
        "west", "light torch", "north",
    };
    for (first_half) |cmd| try testing.expect((try game.command(cmd)).turn);

    var save_buf: [65536]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&save_buf);
    _ = try bespoke.save.write_save_state(
        testing.allocator,
        &writer,
        &game.world,
        &game.spatial,
        &game.vm,
        .{ .program = game.compiled.identity() },
    );
    const saved = writer.buffered();

    var restored: Game = undefined;
    try restored.init();
    defer restored.deinit();
    var reader: std.Io.Reader = .fixed(saved);
    const meta = try bespoke.save.read_save_state_for(
        testing.allocator,
        &reader,
        &restored.world,
        &restored.spatial,
        &restored.vm,
        restored.compiled.identity(),
    );
    try testing.expect(!meta.routines_restarted);
    try testing.expectEqual(game.world.current_tick, restored.world.current_tick);
    try testing.expect(restored.holds("Burning", "Torch", null));
    try testing.expect(restored.holds("SluiceDrained", "SluiceWheel", null));

    const second_half = [_][]const u8{
        "unlock gate with key", "north", "take crown", "south", "south", "up",
    };
    for (second_half) |cmd| try testing.expect((try restored.command(cmd)).turn);
    try testing.expect(restored.holds("Victory", "Scene", null));
}

test "colour cycling animates pixels on the 60 Hz display clock without touching facts" {
    var game: Game = undefined;
    try game.init();
    defer game.deinit();

    var window = try bespoke.display.DisplayWindow.init_offscreen(testing.io, 1280, 720);
    defer window.deinit();
    window.set_art(&game.compiled.art);

    var bridge = bespoke.DisplayBridge.init();
    bridge.capture_frame(&game.world, &game.spatial, &game.vm);
    bridge.swap();

    const facts_before = game.world.fact_count();
    window.animation_clock = 0;
    window.render_frame(bridge.get_frame(), true);
    const h0 = window.frame_hash().?;
    window.animation_clock = 12;
    window.render_frame(bridge.get_frame(), true);
    const h12 = window.frame_hash().?;
    try testing.expect(h0 != h12);
    try testing.expectEqual(facts_before, game.world.fact_count());
}
