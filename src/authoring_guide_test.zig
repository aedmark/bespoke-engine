//! Keeps `docs/AUTHORING.md` true (P29-02, D-064). Every ```bespoke block in the guide must
//! compile on its own, and the three walkthrough scripts, found by their `<!-- example: x -->`
//! markers, must do what the guide says they do. A guide edit that breaks an example fails
//! `zig build test`. Fragments that are not whole scripts are fenced as `text`.
//!
//! The guide is read at test time from the engine checkout recorded by the build, because
//! `@embedFile` cannot reach outside `src/`.
const std = @import("std");
const bespoke = @import("root.zig");
const build_options = @import("build_options");
const testing = std.testing;

const GUIDE_PATH = "docs/AUTHORING.md";
const FENCE = "```bespoke\n";

fn read_guide(allocator: std.mem.Allocator) ![]u8 {
    var root = try std.fs.openDirAbsolute(build_options.engine_root, .{});
    defer root.close();
    return root.readFileAlloc(allocator, GUIDE_PATH, 1 << 20);
}

/// The body of the ```bespoke block that follows `start` in `text`, and where it ends.
fn next_block(text: []const u8, start: usize) ?struct { body: []const u8, line: usize, end: usize } {
    const open = std.mem.indexOfPos(u8, text, start, FENCE) orelse return null;
    const body_start = open + FENCE.len;
    const close = std.mem.indexOfPos(u8, text, body_start, "```") orelse return null;
    const line = std.mem.count(u8, text[0..open], "\n") + 1;
    return .{ .body = text[body_start..close], .line = line, .end = close + 3 };
}

fn example(text: []const u8, name: []const u8) ![]const u8 {
    var buf: [64]u8 = undefined;
    const marker = try std.fmt.bufPrint(&buf, "<!-- example: {s} -->", .{name});
    const at = std.mem.indexOf(u8, text, marker) orelse return error.ExampleMarkerMissing;
    return (next_block(text, at) orelse return error.ExampleBlockMissing).body;
}

/// A guide script running headless the way `bespoke run` starts it: top-level statements
/// first, then every routine on its actor, with actors placed on the first mark.
const Play = struct {
    world: bespoke.World,
    spatial: bespoke.SpatialSystem,
    compiled: bespoke.CompiledProgram,
    vm: bespoke.VM,
    interp: bespoke.command.Interpreter = .{},
    hero: bespoke.EntityId,
    said: std.ArrayList(u8),
    reply_buf: [160]u8 = undefined,

    fn init(self: *Play, source: []const u8) !void {
        self.world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
        self.spatial = bespoke.SpatialSystem.init(testing.allocator);
        self.compiled = try bespoke.compile_source(testing.allocator, &self.world, &self.spatial, source);
        try bespoke.host.initialize_subsystems(&self.world, &self.compiled);
        self.vm = bespoke.VM.init(testing.allocator, &self.world, &self.compiled.chunk);
        self.vm.spatial = &self.spatial;
        try self.vm.load_compiled_rules(&self.compiled);
        self.interp = .{};
        self.said = std.ArrayList(u8).init(testing.allocator);
        try bespoke.host.run_initial_statements(&self.world, &self.vm, &self.compiled);
        const first_mark = self.spatial.graph.waypoints.items[0].id;
        var it = self.compiled.routine_entries.iterator();
        while (it.next()) |entry| {
            const actor = try self.world.intern_entity(self.compiled.routine_entities.get(entry.key_ptr.*).?);
            if (!self.spatial.agents.contains(actor)) try self.spatial.register_entity(actor, first_mark, 10);
            _ = try self.vm.spawn_routine(actor, entry.value_ptr.*);
        }
        self.hero = try self.world.intern_entity(bespoke.runner.player_actor(&self.compiled).?);
    }

    fn deinit(self: *Play) void {
        self.said.deinit();
        self.vm.deinit();
        self.compiled.deinit();
        self.spatial.deinit();
        self.world.deinit();
    }

    fn run(self: *Play, ticks: usize) !void {
        for (0..ticks) |_| {
            _ = try bespoke.host.tick(&self.vm, &self.compiled);
            var buf: [512]u8 = undefined;
            if (bespoke.host.speech_this_tick(&self.world, &self.vm, &buf)) |line| {
                try self.said.appendSlice(line);
                try self.said.append('\n');
            }
        }
    }

    /// Types a line as the player would, then ticks so a fired handler runs and speaks.
    fn typed(self: *Play, line: []const u8) !?[]const u8 {
        const reply = try bespoke.host.run_command(&self.vm, &self.compiled, &self.interp, self.hero, line, &self.reply_buf);
        try self.run(2);
        return reply.text;
    }

    fn heard(self: *const Play, line: []const u8) bool {
        return std.mem.indexOf(u8, self.said.items, line) != null;
    }

    fn holds(self: *const Play, relation: []const u8, subject: []const u8, object: ?[]const u8) bool {
        const rel = self.world.lookup_relation(relation) orelse return false;
        const subj = self.world.lookup_entity(subject) orelse return false;
        const obj: ?u32 = if (object) |o| (self.world.lookup_entity(o) orelse return false).to_int() else null;
        return self.world.find_first(subj, rel, obj) != null;
    }

    fn offered(self: *const Play) []const []const u8 {
        const S = struct {
            var texts: [9][]const u8 = undefined;
        };
        const open = bespoke.dialogue.view(&self.world) orelse return &.{};
        for (0..open.count) |i| S.texts[i] = open.text(i);
        return S.texts[0..open.count];
    }

    fn choose(self: *Play, index: usize) !void {
        try testing.expect(try bespoke.runner.answer_dialogue(&self.vm, index));
        try self.run(2);
    }

    fn score(self: *const Play) []const u8 {
        const id = bespoke.display.current_score_entity(&self.world, self.vm.current_scene) orelse return "";
        return self.world.get_entity_name(id) orelse "";
    }
};

test "P29-02: every bespoke block in the authoring guide compiles" {
    const text = try read_guide(testing.allocator);
    defer testing.allocator.free(text);
    var at: usize = 0;
    var blocks: usize = 0;
    while (next_block(text, at)) |block| : (at = block.end) {
        blocks += 1;
        var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
        defer world.deinit();
        var spatial = bespoke.SpatialSystem.init(testing.allocator);
        defer spatial.deinit();
        var compiled = bespoke.compile_source(testing.allocator, &world, &spatial, block.body) catch |err| {
            const result = bespoke.check_source(testing.allocator, block.body);
            if (result.diagnostic()) |d| {
                std.debug.print("{s}: block at line {d}: {d}:{d}: {s}\n", .{ GUIDE_PATH, block.line, d.line, d.column, d.message });
            } else std.debug.print("{s}: block at line {d}: {s}\n", .{ GUIDE_PATH, block.line, @errorName(err) });
            return err;
        };
        compiled.deinit();
    }
    // The three walkthroughs and the reference examples; a lost fence would hide examples.
    try testing.expect(blocks >= 6);
}

test "P29-02: the scene walkthrough walks the hero aboard and changes scene" {
    const text = try read_guide(testing.allocator);
    defer testing.allocator.free(text);
    var play: Play = undefined;
    try play.init(try example(text, "scene"));
    defer play.deinit();
    try testing.expectEqualStrings("Quay", play.world.get_entity_name(play.vm.current_scene.?).?);
    try play.run(12);
    try testing.expect(play.heard("Pilot: \"Mind the gap.\""));
    try testing.expect(play.holds("Boarded", "Hero", null));
    try testing.expectEqualStrings("Ferry", play.world.get_entity_name(play.vm.current_scene.?).?);
}

test "P29-02: the dialogue walkthrough offers only the choices the facts allow" {
    const text = try read_guide(testing.allocator);
    defer testing.allocator.free(text);
    var play: Play = undefined;
    try play.init(try example(text, "dialogue"));
    defer play.deinit();

    try testing.expect(try play.typed("talk to the pilot") == null);
    try testing.expect(play.heard("Pilot: \"Crossing tonight?\""));
    const first = play.offered();
    try testing.expectEqual(@as(usize, 2), first.len);
    try testing.expectEqualStrings("I have no ticket.", first[0]);
    try play.choose(0);
    try testing.expect(play.holds("Refused", "Hero", null));
    try testing.expect(play.offered().len == 0);

    _ = try play.typed("ask pilot about the ticket");
    try testing.expect(play.heard("Pilot: \"The office sells them.\""));
    _ = try play.typed("take ticket");
    try testing.expect(play.holds("Carries", "Hero", "Ticket"));
    _ = try play.typed("talk to pilot");
    try testing.expectEqualStrings("Show the ticket.", play.offered()[0]);
    try play.choose(0);
    try testing.expect(play.holds("Paid", "Hero", null));
    try testing.expect(play.heard("Pilot: \"Step aboard.\""));
}

test "P29-02: the puzzle walkthrough needs the bell rung while the lantern burns" {
    const text = try read_guide(testing.allocator);
    defer testing.allocator.free(text);
    var play: Play = undefined;
    try play.init(try example(text, "puzzle"));
    defer play.deinit();
    try testing.expectEqualStrings("Waiting", play.score());

    // Out of order: the bell alone does nothing but a remark.
    _ = try play.typed("use bell");
    try testing.expect(play.heard("Pilot: \"Nobody sees a bell in the fog.\""));
    try testing.expect(!play.holds("Signalled", "Quay", null));

    _ = try play.typed("use the match on the lantern");
    try testing.expect(play.holds("Lit", "Lantern", null));
    _ = try play.typed("use bell");
    try play.run(2);
    try testing.expect(play.holds("Signalled", "Quay", null));
    try testing.expectEqualStrings("Arrival", play.score());
    try play.run(4);
    try testing.expect(play.heard("Pilot: \"The ferry has seen you.\""));

    // The window closes: the light lasts 30 ticks.
    try play.run(30);
    try testing.expect(!play.holds("Lit", "Lantern", null));
    try testing.expect(play.heard("Hero: \"The lantern is out.\""));
}
