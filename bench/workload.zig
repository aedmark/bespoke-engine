//! P41-01: identical headless simulation on native Linux and browser Wasm.
const std = @import("std");
const bespoke = @import("bespoke");

pub const ticks_per_sample = 256;
pub const samples = 3;
const warmup_ticks = 16;

pub const Case = struct {
    name: []const u8,
    ballast: u32,
    registry: u32,
    workers: u32,
};

pub const cases = [_]Case{
    .{ .name = "baseline", .ballast = 1024, .registry = 256, .workers = 16 },
    .{ .name = "fact-heavy", .ballast = 7168, .registry = 256, .workers = 16 },
    .{ .name = "entity-heavy", .ballast = 1024, .registry = 2048, .workers = 16 },
    .{ .name = "fiber-heavy", .ballast = 1024, .registry = 256, .workers = 256 },
    .{ .name = "combined", .ballast = 7168, .registry = 2048, .workers = 256 },
};

// Every fiber does one late hit, one miss, and refreshes a TTL fact. The ballast
// varies the cost of linear scans without making the synthetic world grow while timed.
const script =
    \\scene BenchRoom:
    \\  marks: BenchMark
    \\entity Probe, Ready, Missing, Worker
    \\relation Signal(subject, value)
    \\relation Heartbeat(subject)
    \\relation Unexpected(subject)
    \\routine Pulse(Worker):
    \\  loop:
    \\    if Signal(Probe, Ready):
    \\      remember Heartbeat(Worker) for 2 ticks
    \\    if Signal(Probe, Missing):
    \\      remember Unexpected(Worker)
    \\    wait 1 ticks
;

pub const Workload = struct {
    world: bespoke.World,
    spatial: bespoke.SpatialSystem,
    program: bespoke.CompiledProgram,
    vm: bespoke.VM,
    case: Case,

    pub fn init(self: *Workload, alloc: std.mem.Allocator, case: Case) !void {
        self.case = case;
        self.world = try bespoke.World.init(alloc, bespoke.world.DEFAULT_ARENA_SIZE);
        errdefer self.world.deinit();
        self.spatial = bespoke.SpatialSystem.init(alloc);
        errdefer self.spatial.deinit();
        self.program = try bespoke.compiler.compile_source(alloc, &self.world, &self.spatial, script);
        errdefer self.program.deinit();
        self.vm = try bespoke.host.init_vm(alloc, &self.world, &self.spatial, &self.program);
        errdefer self.vm.deinit();

        var ids: [2048]bespoke.EntityId = undefined;
        var name_buf: [32]u8 = undefined;
        for (ids[0..case.registry], 0..) |*id, i| {
            const name = try std.fmt.bufPrint(&name_buf, "Entity{d}", .{i});
            id.* = try self.world.intern_entity(name);
            if (i < case.workers) {
                _ = try bespoke.host.start_routine(&self.world, &self.spatial, &self.vm, &self.program, "Pulse", name, 10);
            }
        }
        const payload = try self.world.intern_relation("Payload", .set);
        for (0..case.ballast) |i| {
            try self.world.remember(ids[i % case.registry], payload, @intCast(i), 0);
        }
        try self.world.remember(self.world.lookup_entity("Probe").?, self.world.lookup_relation("Signal").?, self.world.lookup_entity("Ready").?.to_int(), 0);
        try self.advance(warmup_ticks);
    }

    pub fn deinit(self: *Workload) void {
        self.vm.deinit();
        self.program.deinit();
        self.spatial.deinit();
        self.world.deinit();
    }

    pub fn advance(self: *Workload, ticks: u32) !void {
        for (0..ticks) |_| _ = try bespoke.host.tick(&self.vm, &self.program);
    }

    pub fn verify(self: *const Workload, ticks: u32) !void {
        // The harness observes internal counts; it does not make them part of the host API.
        if (self.world.current_tick != warmup_ticks + ticks or
            self.facts() != self.case.ballast + 2 or
            self.entities() != self.case.registry + 6 or
            self.fibers() != self.case.workers) return error.UnexpectedWorkloadCounts;
        for (self.vm.fibers.items) |fiber| {
            if (fiber.state != .waiting_ticks) return error.UnexpectedFiberState;
        }
        const worker = self.world.lookup_entity("Worker").?;
        const pulse = self.world.find_first(worker, self.world.lookup_relation("Heartbeat").?, null) orelse return error.NoHeartbeat;
        if (pulse.expires_at_tick != self.world.current_tick + 2 or
            self.world.has_fact(worker, self.world.lookup_relation("Unexpected").?, null)) return error.UnexpectedWorkloadState;
    }

    pub fn facts(self: *const Workload) usize {
        return self.world.fact_count();
    }

    pub fn entities(self: *const Workload) usize {
        return self.world.entity_names.items.len;
    }

    pub fn fibers(self: *const Workload) usize {
        return self.vm.fibers.items.len;
    }
};
