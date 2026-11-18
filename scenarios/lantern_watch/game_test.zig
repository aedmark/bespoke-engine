const std = @import("std");
const bespoke = @import("bespoke");
const testing = std.testing;
fn loadScript(dry: bool) ![]u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(testing.io, "scripts/main.bespoke", testing.allocator, .limited(1 << 20));
    if (!dry) return source;
    defer testing.allocator.free(source);
    const weather = "remember Raining(Tower)\n";
    const at = std.mem.indexOf(u8, source, weather) orelse return error.MissingWeatherSetup;
    return std.mem.concat(testing.allocator, u8, &.{ source[0..at], source[at + weather.len ..] });
}

const Watch = struct {
    source: []u8,
    world: bespoke.World,
    spatial: bespoke.SpatialSystem,
    program: bespoke.CompiledProgram,
    vm: bespoke.VM,
    actor: bespoke.EntityId,
    interpreter: bespoke.command.Interpreter = .{},

    fn init(self: *Watch, dry: bool) !void {
        self.interpreter = .{};
        self.source = try loadScript(dry);
        errdefer testing.allocator.free(self.source);
        self.world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
        errdefer self.world.deinit();
        self.spatial = bespoke.SpatialSystem.init(testing.allocator);
        errdefer self.spatial.deinit();
        self.program = try bespoke.compiler.compile_source(testing.allocator, &self.world, &self.spatial, self.source);
        errdefer self.program.deinit();
        self.vm = try bespoke.host.init_vm(testing.allocator, &self.world, &self.spatial, &self.program);
        errdefer self.vm.deinit();
        self.actor = try bespoke.host.start_script(&self.world, &self.spatial, &self.vm, &self.program);
    }

    fn deinit(self: *Watch) void {
        self.vm.deinit();
        self.program.deinit();
        self.spatial.deinit();
        self.world.deinit();
        testing.allocator.free(self.source);
    }

    fn typeLine(self: *Watch, line: []const u8) !void {
        errdefer std.debug.print("command: {s}\n", .{line});
        var buffer: [256]u8 = undefined;
        const reply = try bespoke.host.run_command(&self.vm, &self.program, &self.interpreter, self.actor, line, &buffer);
        if (reply.text) |text| std.debug.print("parser reply: {s}\n", .{text});
        try testing.expect(reply.fired or reply.walking);
        try self.tick();
    }

    fn tick(self: *Watch) !void {
        _ = try bespoke.host.tick(&self.vm, &self.program);
    }

    fn has(self: *const Watch, rel_name: []const u8, subject: []const u8, object: ?[]const u8) bool {
        const rel = self.world.lookup_relation(rel_name) orelse return false;
        const subj = self.world.lookup_entity(subject) orelse return false;
        const obj = if (object) |name| (self.world.lookup_entity(name) orelse return false).to_int() else null;
        return self.world.find_first(subj, rel, obj) != null;
    }

    fn heard(self: *const Watch, words: []const u8) bool {
        var lines: [12]bespoke.host.SpeechLine = undefined;
        const n = bespoke.host.speech_lines(&self.world, &self.vm, &lines);
        for (lines[0..n]) |line| if (std.mem.indexOf(u8, line.text, words) != null) return true;
        return false;
    }

    fn hearKnock(self: *Watch, words: []const u8) !void {
        for (0..16) |_| {
            if (self.heard(words)) return;
            try self.tick();
        }
        try testing.expect(self.heard(words));
    }

    fn nextQuietKnock(self: *Watch) !void {
        // Wait for the old knock to expire so a second call proves a new one occurs.
        for (0..16) |_| {
            if (!self.has("Knocking", "Tower", null)) break;
            try self.tick();
        }
        try testing.expect(!self.has("Knocking", "Tower", null));
        for (0..16) |_| {
            try self.tick();
            try testing.expect(!self.heard("knocks on the outside"));
            if (self.has("Knocking", "Tower", null)) return;
        }
        try testing.expect(self.has("Knocking", "Tower", null));
    }

    fn go(self: *Watch, command: []const u8, mark: []const u8) !void {
        try self.typeLine(command);
        for (0..16) |_| {
            if (self.has("Standing", "Watcher", mark)) return;
            try self.tick();
        }
        try testing.expect(self.has("Standing", "Watcher", mark));
    }
};

test "the stuck bell cannot warn the ship before the player repairs it" {
    var watch: Watch = undefined;
    try watch.init(false);
    defer watch.deinit();
    try watch.typeLine("ring the bell");
    try testing.expect(watch.has("Seized", "Bell", null));
    try testing.expect(watch.heard("the bell doesn't move"));
    try testing.expect(!watch.has("Warned", "Ship", null));
    try watch.typeLine("examine bell");
    try testing.expect(watch.heard("salt has seized"));
    try watch.typeLine("oil bell");
    try testing.expect(watch.has("Seized", "Bell", null));
    try watch.typeLine("take oilcan");
    try testing.expect(!watch.has("Carries", "Watcher", "Oilcan"));
    try watch.go("go watch room", "WatchRoom");
    try watch.typeLine("take oilcan");
    try testing.expect(watch.has("Carries", "Watcher", "Oilcan"));
    try watch.typeLine("oil bell");
    try testing.expect(watch.has("Seized", "Bell", null));
    try watch.go("go to bell landing", "BellLanding");
    try watch.typeLine("use oilcan on bell");
    try testing.expect(!watch.has("Seized", "Bell", null));
    try testing.expect(!watch.has("Warned", "Ship", null));
    try watch.typeLine("ring bell");
    try testing.expect(watch.has("Warned", "Ship", null));
    try testing.expect(watch.heard("a ship's bell answers"));
    try testing.expect(watch.heard("The bell tells them what they need to know. We all sleep soundly tonight."));
    try watch.typeLine("light hand lamp");
    try testing.expect(watch.has("Shining", "HandLamp", null));
    try watch.nextQuietKnock();
    try watch.nextQuietKnock();
    try watch.typeLine("listen");
    try testing.expect(watch.heard("The knocks come in threes."));
    try testing.expect(!watch.has("Entered", "Tower", null));
    try testing.expect(!watch.has("Shining", "Beacon", null));
}

test "the logbook earns help with the bell but the Keeper never opens the shutter" {
    var watch: Watch = undefined;
    try watch.init(false);
    defer watch.deinit();
    try watch.typeLine("show logbook to keeper");
    try testing.expect(!watch.has("Helping", "Keeper", null));
    try watch.go("go to watch room", "WatchRoom");
    try watch.typeLine("read logbook");
    try testing.expect(watch.heard("A light answered from below."));
    try watch.typeLine("show logbook to keeper");
    try testing.expect(watch.has("Helping", "Keeper", null));
    try watch.go("go to gallery", "Gallery");
    try watch.typeLine("ask keeper to open shutter");
    try testing.expect(watch.heard("And soon you will too."));
    try watch.nextQuietKnock();
    try testing.expect(!watch.has("Shining", "Beacon", null));
    try testing.expect(!watch.has("Entered", "Tower", null));
}

test "the Keeper can free the bell with the player without the oilcan" {
    var watch: Watch = undefined;
    try watch.init(false);
    defer watch.deinit();
    try watch.go("go watch room", "WatchRoom");
    try watch.typeLine("read logbook");
    try watch.typeLine("show logbook to keeper");
    try watch.go("go bell landing", "BellLanding");
    for (0..12) |_| {
        if (watch.has("Ready", "Keeper", null)) break;
        try watch.tick();
    }
    try testing.expect(watch.has("Ready", "Keeper", null));
    try testing.expect(watch.has("Seized", "Bell", null));
    try watch.typeLine("ring bell");
    try testing.expect(watch.heard("The Keeper leans into the yoke."));
    try testing.expect(watch.has("Warned", "Ship", null));
    try testing.expect(!watch.has("Carries", "Watcher", "Oilcan"));
}

test "both go forms confirm physical arrival through narration" {
    var watch: Watch = undefined;
    try watch.init(false);
    defer watch.deinit();
    try watch.go("Go to watch room", "WatchRoom");
    try testing.expect(watch.heard("You enter the watch room."));
    try watch.go("go gallery", "Gallery");
    try testing.expect(watch.heard("You reach the gallery."));
    try watch.go("go watch room", "WatchRoom");
    try testing.expect(watch.heard("You enter the watch room."));
}

test "ignoring the bell and opening the beacon in rain lets the knocker in" {
    var watch: Watch = undefined;
    try watch.init(false);
    defer watch.deinit();
    try watch.go("go to gallery", "Gallery");
    try watch.typeLine("open shutter");
    try watch.hearKnock("from inside the door");
    try testing.expect(watch.has("Entered", "Tower", null));
    try testing.expect(!watch.has("Warned", "Ship", null));
}

test "closing the shutter before the next knock prevents entry" {
    var watch: Watch = undefined;
    try watch.init(false);
    defer watch.deinit();
    try watch.go("go to gallery", "Gallery");
    try watch.nextQuietKnock();
    try watch.typeLine("open shutter");
    try watch.typeLine("close shutter");
    try watch.nextQuietKnock();
    try testing.expect(!watch.has("Entered", "Tower", null));
}

test "it knocks even in clear weather; the beacon alone is not enough" {
    var watch: Watch = undefined;
    try watch.init(true);
    defer watch.deinit();
    try watch.go("go to gallery", "Gallery");
    try watch.typeLine("open shutter");
    try watch.nextQuietKnock();
    try testing.expect(watch.has("Shining", "Beacon", null));
    try testing.expect(!watch.has("Entered", "Tower", null));
}
