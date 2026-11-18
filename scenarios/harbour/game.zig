//! Shared reference-game host. All engine access uses docs/API.md.
const std = @import("std");
const bespoke = @import("bespoke");

pub const Stop = struct { id: []const u8, mark: []const u8, title: []const u8, task: []const u8 };
pub const stops = [_]Stop{
    .{ .id = "Quay", .mark = "QuayDesk", .title = "Quay", .task = "read tide board" },
    .{ .id = "WatchOffice", .mark = "OfficeDesk", .title = "Watch office", .task = "read duty book" },
    .{ .id = "Market", .mark = "MarketStall", .title = "Market", .task = "read market slate" },
    .{ .id = "Chandlery", .mark = "ChandleryBench", .title = "Chandlery", .task = "take wick" },
    .{ .id = "NetLoft", .mark = "LoftTable", .title = "Net loft", .task = "take flag" },
    .{ .id = "Customs", .mark = "CustomsDesk", .title = "Customs", .task = "read manifest" },
    .{ .id = "PumpHouse", .mark = "PumpBench", .title = "Pump house", .task = "turn lever" },
    .{ .id = "SignalSteps", .mark = "SignalRail", .title = "Signal steps", .task = "read bell code" },
    .{ .id = "Breakwater", .mark = "BreakwaterPost", .title = "Breakwater", .task = "secure mooring" },
    .{ .id = "BeaconHouse", .mark = "BeaconBench", .title = "Beacon house", .task = "signal packet" },
};

const exits = blk: {
    var list: [2 * (stops.len - 1)]bespoke.host.Exit = undefined;
    for (0..stops.len - 1) |i| {
        list[2 * i] = .{ .scene = stops[i].id, .mark = stops[i].id ++ "Forward", .to_scene = stops[i + 1].id, .to_mark = stops[i + 1].mark };
        list[2 * i + 1] = .{ .scene = stops[i + 1].id, .mark = stops[i + 1].id ++ "Back", .to_scene = stops[i].id, .to_mark = stops[i].mark };
    }
    break :blk list;
};

pub const sample_ticks = 8192;
pub const samples = 3;

pub const Game = struct {
    world: bespoke.World,
    spatial: bespoke.SpatialSystem,
    program: bespoke.CompiledProgram,
    vm: bespoke.VM,
    society: bespoke.host.ScriptSociety,
    player: bespoke.EntityId,
    interpreter: bespoke.command.Interpreter = .{},
    text: [4096]u8 = undefined,
    text_len: usize = 0,

    pub fn init(self: *Game, alloc: std.mem.Allocator) !void {
        self.interpreter = .{};
        self.text_len = 0;
        self.world = try bespoke.World.init(alloc, bespoke.world.DEFAULT_ARENA_SIZE);
        errdefer self.world.deinit();
        self.spatial = bespoke.SpatialSystem.init(alloc);
        errdefer self.spatial.deinit();
        self.program = try bespoke.compiler.compile_source(alloc, &self.world, &self.spatial, @embedFile("main.bespoke"));
        errdefer self.program.deinit();
        self.vm = try bespoke.host.init_vm(alloc, &self.world, &self.spatial, &self.program);
        errdefer self.vm.deinit();
        self.player = try bespoke.host.start_script(&self.world, &self.spatial, &self.vm, &self.program);
        self.society = try bespoke.host.ScriptSociety.init(&self.world, &self.program, 0);
        self.describe();
    }

    pub fn deinit(self: *Game) void {
        self.vm.deinit();
        self.program.deinit();
        self.spatial.deinit();
        self.world.deinit();
    }

    pub fn append(self: *Game, comptime fmt: []const u8, args: anytype) void {
        const line = std.fmt.bufPrint(self.text[self.text_len..], fmt ++ "\n", args) catch return;
        self.text_len += line.len;
    }

    pub fn property(self: *const Game, entity: []const u8, relation: []const u8) ?u32 {
        const subject = self.world.lookup_entity(entity) orelse return null;
        const kind = self.world.lookup_relation(relation) orelse return null;
        return self.world.get_property(subject, kind);
    }

    pub fn has(self: *const Game, entity: []const u8, relation: []const u8) bool {
        const subject = self.world.lookup_entity(entity) orelse return false;
        const kind = self.world.lookup_relation(relation) orelse return false;
        return self.world.has_fact(subject, kind, null);
    }

    pub fn room(self: *const Game) usize {
        const id = bespoke.EntityId.from_int(self.property("Watcher", "HarbourAt").?);
        const name = self.world.get_entity_name(id).?;
        for (stops, 0..) |stop, i| if (std.mem.eql(u8, name, stop.id)) return i;
        unreachable;
    }

    pub fn describe(self: *Game) void {
        const stop = stops[self.room()];
        self.append("{s}. Try: {s}.", .{ stop.title, stop.task });
    }

    pub fn command(self: *Game, line: []const u8) !void {
        var buf: [256]u8 = undefined;
        const reply = try bespoke.host.run_command(&self.vm, &self.program, &self.interpreter, self.player, line, &buf);
        if (reply.text) |message| self.append("{s}", .{message});
        if (reply.fired) try self.tick();
    }

    pub fn tick(self: *Game) !void {
        const walking = self.spatial.is_moving(self.player);
        _ = try bespoke.host.tick(&self.vm, &self.program);
        try self.society.step(&self.vm);
        var speech: [16]bespoke.host.SpeechLine = undefined;
        const count = bespoke.host.speech_lines(&self.world, &self.vm, &speech);
        for (speech[0..count]) |line| {
            if (std.mem.eql(u8, line.speaker, "Scene")) self.append("{s}", .{line.text}) else self.append("{s}: {s}", .{ line.speaker, line.text });
        }
        if (walking and !self.spatial.is_moving(self.player)) {
            if (try bespoke.host.take_exit_here(&self.world, &self.spatial, &self.vm, &exits, self.player)) |exit| {
                const at = self.world.lookup_relation("HarbourAt").?;
                try self.world.remember(self.player, at, self.world.lookup_entity(exit.to_scene).?.to_int(), 0);
                self.describe();
            }
        }
    }

    pub fn ballast(self: *Game, count: usize) !void {
        const relation = try self.world.intern_relation("ArchiveRow", .set);
        for (0..count) |i| try self.world.remember(self.player, relation, @intCast(i), 0);
    }

    pub fn advance(self: *Game, ticks: usize) !void {
        for (0..ticks) |_| try self.tick();
    }

    pub fn move(self: *Game, line: []const u8, destination: usize) !void {
        try self.command(line);
        for (0..32) |_| {
            if (self.room() == destination) return;
            try self.tick();
        }
        return error.UnreachableStop;
    }

    pub fn prepareSample(self: *Game, extra: usize) !void {
        for (stops, 0..) |stop, i| {
            if (i != 0) try self.move("go forward", i);
            try self.command(stop.task);
        }
        if (!self.has("Packet", "PacketClear")) return error.UnclearedPacket;
        try self.ballast(extra);
        try self.advance(16);
        self.text_len = 0;
    }
};
