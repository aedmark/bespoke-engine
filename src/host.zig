//! Host kit: shared plumbing for programs that drive the engine (P32-16, D-033).
//!
//! Every proof of concept, and any game built on BeSpoke, needs the same few things around
//! the VM: tick and re-dispatch weaves, read what the script said this tick, run top-level
//! statements, record a timeline for rewind, and run an interactive loop that handles pause,
//! single-step, scrub, rewind, and save actions. These used to be copied into each proof with
//! drifting behaviour. They live here once, named by function, with no game content.
const std = @import("std");
const world_mod = @import("world.zig");
const vm_mod = @import("vm.zig");
const spatial_mod = @import("spatial.zig");
const display_mod = @import("display.zig");
const codegen = @import("compiler/codegen.zig");
const dialogue_mod = @import("dialogue.zig");
const hypervisor_mod = @import("hypervisor.zig");
const temporal_mod = @import("temporal_snapshot.zig");

const World = world_mod.World;
const EntityId = world_mod.EntityId;
const VM = vm_mod.VM;
const SpatialSystem = spatial_mod.SpatialSystem;
const CompiledProgram = codegen.CompiledProgram;
const TemporalHypervisor = hypervisor_mod.TemporalHypervisor;

/// Cue id the compiler emits for `say` statements (D-009).
pub const SAY_CUE_ID: u16 = 2;

/// One host tick: step the VM, then re-dispatch weaves queued by scripts (D-029). Returns how
/// many in-script weaves were dispatched. Hosts should tick through this, never `step_tick`
/// alone, or in-script weaves never fire and saves are refused.
pub fn tick(vm: *VM, compiled: *const CompiledProgram) !usize {
    try vm.step_tick();
    return try vm.dispatch_pending_weaves(compiled);
}

/// Collects `say` lines into one string. `VM.step_tick` clears `emitted_cues` at the start of
/// every tick, so speech must be collected after each tick; a cue index taken before a tick is
/// meaningless after it (the bug this replaces in the old per-proof readers).
pub const SpeechLog = struct {
    stream: std.io.FixedBufferStream([]u8),
    count: usize = 0,
    last_speaker: u32 = 0,

    pub fn init(buf: []u8) SpeechLog {
        return .{ .stream = std.io.fixedBufferStream(buf) };
    }

    /// Appends every `say` cue emitted during the most recent tick.
    pub fn collect(self: *SpeechLog, world: *const World, vm: *const VM) void {
        self.collect_from(world, vm, null);
    }

    /// Appends the `say` cues of the most recent tick, optionally only those by `speaker`.
    /// Lines read `Speaker: "line"`; consecutive lines by the same speaker drop the repeated
    /// name (`Hero: "a"  "b"  Other: "c"`), so every line stays attributed to whoever said it.
    /// Text that does not fit the buffer is dropped rather than failing the tick.
    pub fn collect_from(self: *SpeechLog, world: *const World, vm: *const VM, speaker: ?EntityId) void {
        for (vm.emitted_cues.items) |cue| {
            if (cue.cue_id != SAY_CUE_ID or cue.arg_count < 2) continue;
            if (speaker) |only| if (cue.args[0] != only.to_int()) continue;
            const name = world.get_entity_name(EntityId.from_int(cue.args[0])) orelse "Someone";
            const text = world.get_entity_name(EntityId.from_int(cue.args[1])) orelse "";
            const w = self.stream.writer();
            if (self.count > 0) w.writeAll("  ") catch return;
            if (self.count == 0 or cue.args[0] != self.last_speaker) w.print("{s}: ", .{name}) catch return;
            w.print("\"{s}\"", .{text}) catch return;
            self.last_speaker = cue.args[0];
            self.count += 1;
        }
    }

    pub fn message(self: *SpeechLog) ?[]const u8 {
        return if (self.count > 0) self.stream.getWritten() else null;
    }
};

/// What the script said during the most recent tick, formatted like `SpeechLog`. Call it right
/// after a tick; the next tick clears the cues it reads.
pub fn speech_this_tick(world: *const World, vm: *const VM, buf: []u8) ?[]const u8 {
    var log = SpeechLog.init(buf);
    log.collect(world, vm);
    return log.message();
}

/// Fires a cue for `actor` (and an optional target), runs one tick, and returns what the
/// script said in reply, if anything.
pub fn act(
    world: *World,
    vm: *VM,
    compiled: *const CompiledProgram,
    cue: []const u8,
    actor: EntityId,
    target: ?EntityId,
    buf: []u8,
) !?[]const u8 {
    var log = SpeechLog.init(buf);
    _ = try vm.fire_cue(compiled, cue, actor, target, null);
    _ = try tick(vm, compiled);
    log.collect(world, vm);
    return log.message();
}

/// Runs the script's top-level statements to completion on a root fiber. Bounded so a script
/// whose top level waits forever cannot hang the host.
pub fn run_initial_statements(world: *World, vm: *VM, compiled: *const CompiledProgram) !void {
    const init_pc = compiled.initial_entry orelse return;
    const root_ent = try world.intern_entity("SimulationRoot");
    const fid = try vm.spawn_routine(root_ent, init_pc);
    var guard: usize = 0;
    while (vm.fibers.items[fid - 1].state != .halted and guard < 64) : (guard += 1) {
        _ = try tick(vm, compiled);
    }
}

/// True when `subject` holds the state `state` (a `X is state` fact), regardless of value.
pub fn has_state(world: *const World, subject: EntityId, state: []const u8) bool {
    const rel = world.lookup_relation(state) orelse return false;
    return world.has_fact(subject, rel, null);
}

/// Moves a waypoint to world coordinates, for hosts that lay out compiler-generated marks.
pub fn place_waypoint(spatial: *SpatialSystem, wp_id: u16, x: i32, y: i32) void {
    if (spatial.graph.get_waypoint(wp_id)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = x, .y = y };
}

/// World snapshots indexed by position, for scrubbing and rewind (D-011, D-033).
///
/// Scrubbing restores a past snapshot without discarding later ones, so the player can scrub
/// back and forth freely. The future is discarded only when the clock advances from a past
/// point (`discard_after`), which records a divergent timeline.
pub const Timeline = struct {
    pub const Snapshot = struct {
        world: std.ArrayList(u8),
        temporal: ?std.ArrayList(u8) = null,

        pub fn deinit(self: *Snapshot) void {
            self.world.deinit();
            if (self.temporal) |*temporal| temporal.deinit();
        }
    };

    snapshots: std.ArrayList(Snapshot),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Timeline {
        return .{ .snapshots = std.ArrayList(Snapshot).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *Timeline) void {
        for (self.snapshots.items) |*snapshot| snapshot.deinit();
        self.snapshots.deinit();
    }

    pub fn len(self: *const Timeline) usize {
        return self.snapshots.items.len;
    }

    /// Index of the newest snapshot (0 when only the initial state is recorded).
    pub fn last_index(self: *const Timeline) usize {
        return if (self.snapshots.items.len == 0) 0 else self.snapshots.items.len - 1;
    }

    pub fn record(self: *Timeline, world: *const World) !void {
        try self.record_with_temporal(world, null);
    }

    /// Records the world and, when supplied, the complete temporal hypervisor state.
    pub fn record_with_temporal(
        self: *Timeline,
        world: *const World,
        hypervisor: ?*const TemporalHypervisor,
    ) !void {
        var snapshot = Snapshot{ .world = std.ArrayList(u8).init(self.allocator) };
        errdefer snapshot.deinit();
        try world.save_state(snapshot.world.writer());
        if (hypervisor) |live| {
            var temporal = std.ArrayList(u8).init(self.allocator);
            errdefer temporal.deinit();
            try temporal_mod.TemporalSnapshot.write(live, temporal.writer());
            snapshot.temporal = temporal;
        }
        try self.snapshots.append(snapshot);
    }

    /// Restores snapshot `index` (clamped to the newest) into `world`, keeping later snapshots.
    /// Returns the index restored, or null when the timeline is empty.
    pub fn restore(self: *const Timeline, world: *World, index: usize) !?usize {
        return self.restore_with_temporal(world, null, index);
    }

    /// Restores the world and temporal hypervisor together. When a hypervisor is supplied, the
    /// snapshot must contain a temporal envelope; a world-only snapshot would desynchronize it.
    pub fn restore_with_temporal(
        self: *const Timeline,
        world: *World,
        hypervisor: ?*TemporalHypervisor,
        index: usize,
    ) !?usize {
        if (self.snapshots.items.len == 0) return null;
        const i = @min(index, self.snapshots.items.len - 1);
        const snapshot = &self.snapshots.items[i];
        var world_stream = std.io.fixedBufferStream(snapshot.world.items);
        try world.restore_state(world_stream.reader());

        if (hypervisor) |live| {
            const temporal_bytes = &(snapshot.temporal orelse return error.MissingTemporalSnapshot);
            var temporal_stream = std.io.fixedBufferStream(temporal_bytes.items);
            var temporal = try temporal_mod.TemporalSnapshot.read(self.allocator, world, temporal_stream.reader());
            defer temporal.deinit();
            try temporal.validate(world);
            try temporal.apply(live);
        }
        return i;
    }

    /// Drops every snapshot after `index`.
    pub fn discard_after(self: *Timeline, index: usize) void {
        if (index + 1 >= self.snapshots.items.len) return;
        for (self.snapshots.items[index + 1 ..]) |*snapshot| snapshot.deinit();
        self.snapshots.shrinkRetainingCapacity(index + 1);
    }

    /// Drops every recorded snapshot, leaving the timeline empty.
    pub fn reset(self: *Timeline) void {
        for (self.snapshots.items) |*snapshot| snapshot.deinit();
        self.snapshots.clearRetainingCapacity();
    }

    /// Drops the newest snapshot and restores the one before it. Returns the index restored.
    pub fn step_back(self: *Timeline, world: *World) !?usize {
        return self.step_back_with_temporal(world, null);
    }

    pub fn step_back_with_temporal(self: *Timeline, world: *World, hypervisor: ?*TemporalHypervisor) !?usize {
        if (self.snapshots.items.len < 2) return null;
        self.discard_after(self.snapshots.items.len - 2);
        return try self.restore_with_temporal(world, hypervisor, self.snapshots.items.len - 1);
    }
};

/// Interactive loop scaffold (D-033). A host owns its loop and its game-specific actions; the
/// session handles the actions every game shares and the timing of ticks:
///
///     while (true) {
///         const action = window.poll_events(session.frame());
///         if (action == .quit) break;
///         if (!try session.handle_common(action)) switch (action) { ...game actions... };
///         if (session.tick_due()) { ...pre-tick rules...; _ = try session.advance(); ...post-tick... }
///         session.render();
///     }
///
/// `cursor` is the timeline index the world currently shows. Advancing from a past cursor
/// discards the newer snapshots first.
pub const Session = struct {
    world: *World,
    spatial: *SpatialSystem,
    vm: *VM,
    compiled: *const CompiledProgram,
    bridge: *display_mod.DisplayBridge,
    window: *display_mod.DisplayWindow,
    hypervisor: ?*TemporalHypervisor = null,
    timeline: Timeline,
    cursor: usize = 0,
    is_paused: bool = false,
    step_requested: bool = false,
    last_tick_ms: i64,

    /// Records the initial state as snapshot 0 and publishes the first frame.
    pub fn init(
        allocator: std.mem.Allocator,
        world: *World,
        spatial: *SpatialSystem,
        vm: *VM,
        compiled: *const CompiledProgram,
        bridge: *display_mod.DisplayBridge,
        window: *display_mod.DisplayWindow,
    ) !Session {
        return initWithHypervisor(allocator, world, spatial, vm, compiled, bridge, window, null);
    }

    /// Initializes a session whose timeline and save drawer must carry temporal hypervisor state.
    pub fn initWithHypervisor(
        allocator: std.mem.Allocator,
        world: *World,
        spatial: *SpatialSystem,
        vm: *VM,
        compiled: *const CompiledProgram,
        bridge: *display_mod.DisplayBridge,
        window: *display_mod.DisplayWindow,
        hypervisor: ?*TemporalHypervisor,
    ) !Session {
        var s = Session{
            .world = world,
            .spatial = spatial,
            .vm = vm,
            .compiled = compiled,
            .bridge = bridge,
            .window = window,
            .hypervisor = hypervisor,
            .timeline = Timeline.init(allocator),
            .last_tick_ms = std.time.milliTimestamp(),
        };
        s.sync_active_world();
        try s.record_snapshot();
        s.refresh();
        return s;
    }

    pub fn deinit(self: *Session) void {
        self.timeline.deinit();
    }

    pub fn frame(self: *const Session) *const display_mod.RenderFrame {
        return self.bridge.get_frame();
    }

    /// Returns the arena that receives gameplay actions. Temporal sessions route actions to a
    /// live branch; ordinary sessions and resolved branches use the primary world.
    pub fn active_world(self: *Session) *World {
        if (self.hypervisor) |hypervisor| return hypervisor.active_world();
        return self.world;
    }

    /// Rebinds the VM after a branch fork, temporal restore, or collapse. This is idempotent and
    /// may be called after a host advances its hypervisor outside `Session.advance`.
    pub fn sync_active_world(self: *Session) void {
        self.vm.bind_world(self.active_world());
    }

    /// The open dialogue, reconstructed from World facts, or null (P32-30, D-046).
    pub fn dialogue_view(self: *const Session) ?dialogue_mod.View {
        const world = if (self.hypervisor) |hypervisor|
            if (hypervisor.branch_active and hypervisor.branch_world != null) &hypervisor.branch_world.? else self.world
        else
            self.world;
        return dialogue_mod.view(world);
    }

    /// Selects an offered choice. Scripted choices resume the suspended fiber and advance one
    /// tick so the chosen body runs; generated choices record the selection for the host.
    pub fn choose_dialogue(self: *Session, index: usize) !?dialogue_mod.Selection {
        const selection = (try self.vm.choose(index)) orelse return null;
        if (selection.is_scripted()) {
            _ = try self.advance();
        } else {
            try self.record_now();
        }
        return selection;
    }

    /// Captures and publishes the current state.
    pub fn refresh(self: *Session) void {
        self.sync_active_world();
        self.bridge.capture_frame(self.active_world(), self.spatial, self.vm);
        self.bridge.set_max_history_tick(self.timeline.last_index());
        self.bridge.swap();
    }

    /// Handles pause, single-step, scrub, rewind, and save/load actions. Returns true when the
    /// action was consumed; the host handles everything else.
    pub fn handle_common(self: *Session, action: display_mod.UserAction) !bool {
        const restoring = switch (action) {
            .quick_load, .load_slot => true,
            else => false,
        };
        if (self.window.handle_save_action_with_temporal(action, self.world, self.spatial, self.vm, self.bridge, &self.is_paused, self.hypervisor)) {
            self.sync_active_world();
            self.vm.sync_dialogue();
            if (restoring) {
                // A loaded save has no persisted timeline. Start a new one from the loaded state
                // so a later rewind cannot jump into the pre-load future.
                self.timeline.reset();
                try self.record_snapshot();
                self.cursor = 0;
            }
            self.refresh();
            return true;
        }
        switch (action) {
            .toggle_pause => self.is_paused = !self.is_paused,
            .step_tick => self.step_requested = true,
            .scrub_to_tick => |target| {
                if (try self.jump_to(target)) |i| {
                    var buf: [64]u8 = undefined;
                    const text = std.fmt.bufPrint(&buf, "Time-travel: tick {d} of {d} (paused)", .{ i, self.timeline.last_index() }) catch "Time-travel";
                    self.window.set_cue_banner(text, 90);
                }
            },
            .rewind => {
                if (try self.timeline.step_back_with_temporal(self.world, self.hypervisor)) |i| {
                    self.cursor = i;
                    self.sync_active_world();
                    self.vm.sync_dialogue();
                    self.refresh();
                    self.window.set_cue_banner("Stepped back one snapshot.", 60);
                }
            },
            else => return false,
        }
        return true;
    }

    /// Shows snapshot `index` (clamped), pauses, and keeps the future for further scrubbing.
    /// Hosts with their own rewind gesture (jump to the opening, say) call this before
    /// `handle_common` sees the action. Returns the index shown.
    pub fn jump_to(self: *Session, index: usize) !?usize {
        const i = (try self.timeline.restore_with_temporal(self.world, self.hypervisor, index)) orelse return null;
        self.cursor = i;
        self.sync_active_world();
        self.vm.sync_dialogue();
        self.is_paused = true;
        self.refresh();
        return i;
    }

    /// True when the clock should advance now: the interval elapsed while running, or a single
    /// step was requested. Consumes the step request and restarts the interval.
    pub fn tick_due(self: *Session) bool {
        const now = std.time.milliTimestamp();
        const due = self.step_requested or (!self.is_paused and now - self.last_tick_ms >= self.window.current_tick_interval_ms);
        if (due) {
            self.step_requested = false;
            self.last_tick_ms = now;
        }
        return due;
    }

    /// Advances one host tick, records it, and publishes the frame. Returns the weaves
    /// re-dispatched. Advancing from a scrubbed-back cursor first discards the newer future.
    pub fn advance(self: *Session) !usize {
        self.timeline.discard_after(self.cursor);
        self.sync_active_world();
        const dispatched = try tick(self.vm, self.compiled);
        try self.record_snapshot();
        self.cursor = self.timeline.last_index();
        self.refresh();
        return dispatched;
    }

    /// Records the current state as a new snapshot without ticking, for host actions that change
    /// the world between ticks (a woven phrase, a REPL command).
    pub fn record_now(self: *Session) !void {
        self.timeline.discard_after(self.cursor);
        try self.record_snapshot();
        self.cursor = self.timeline.last_index();
        self.refresh();
    }

    fn record_snapshot(self: *Session) !void {
        if (self.hypervisor) |hypervisor| {
            try self.timeline.record_with_temporal(self.world, hypervisor);
        } else {
            try self.timeline.record(self.world);
        }
    }

    pub fn render(self: *Session) void {
        self.window.render_frame(self.bridge.get_frame(), self.is_paused);
    }
};

// --- Tests (P32-16) ---

const testing = std.testing;

test "P32-16: SpeechLog collects every say line of a tick, speaker first" {
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const chunk_mod = @import("bytecode.zig");
    var chunk = chunk_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    const hero = try world.intern_entity("Hero");
    const a = try world.intern_entity("First line.");
    const b = try world.intern_entity("Second line.");
    try vm.emitted_cues.append(.{ .cue_id = SAY_CUE_ID, .args = .{ hero.to_int(), a.to_int(), 0, 0 }, .arg_count = 2 });
    try vm.emitted_cues.append(.{ .cue_id = 7, .args = .{ 0, 0, 0, 0 }, .arg_count = 0 });
    try vm.emitted_cues.append(.{ .cue_id = SAY_CUE_ID, .args = .{ hero.to_int(), b.to_int(), 0, 0 }, .arg_count = 2 });

    var buf: [128]u8 = undefined;
    var log = SpeechLog.init(&buf);
    try testing.expect(log.message() == null);
    log.collect(&world, &vm);
    try testing.expectEqualStrings("Hero: \"First line.\"  \"Second line.\"", log.message().?);

    const other = try world.intern_entity("Other");
    const c = try world.intern_entity("Third line.");
    try vm.emitted_cues.append(.{ .cue_id = SAY_CUE_ID, .args = .{ other.to_int(), c.to_int(), 0, 0 }, .arg_count = 2 });
    var buf2: [128]u8 = undefined;
    var mixed = SpeechLog.init(&buf2);
    mixed.collect(&world, &vm);
    try testing.expectEqualStrings("Hero: \"First line.\"  \"Second line.\"  Other: \"Third line.\"", mixed.message().?);
    var buf3: [128]u8 = undefined;
    var only = SpeechLog.init(&buf3);
    only.collect_from(&world, &vm, other);
    try testing.expectEqualStrings("Other: \"Third line.\"", only.message().?);

    var tiny: [8]u8 = undefined;
    var small = SpeechLog.init(&tiny);
    small.collect(&world, &vm); // overflow is dropped, never an error
}

test "P32-16: act fires a cue, ticks, and returns the scripted reply" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\entity Hero, Lamp
        \\relation Lit(thing, state)
        \\remember Lit(Lamp, Hero)
        \\on cue LooksAt(Hero, Lamp):
        \\  say Hero: "It glows."
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();

    try run_initial_statements(&world, &vm, &compiled);
    const hero = world.lookup_entity("Hero").?;
    const lamp = world.lookup_entity("Lamp").?;
    try testing.expect(has_state(&world, lamp, "Lit"));
    try testing.expect(!has_state(&world, hero, "Lit"));

    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("Hero: \"It glows.\"", (try act(&world, &vm, &compiled, "LooksAt", hero, lamp, &buf)).?);
    // A second act still hears its reply: speech is read after the tick, not by a stale index.
    try testing.expectEqualStrings("Hero: \"It glows.\"", (try act(&world, &vm, &compiled, "LooksAt", hero, lamp, &buf)).?);
}

test "P32-16: Timeline scrubs without losing the future and discards it only on divergence" {
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var tl = Timeline.init(testing.allocator);
    defer tl.deinit();

    const flag = try world.intern_relation("Flag", .property);
    const e = try world.intern_entity("E");
    for (0..4) |i| {
        try world.remember(e, flag, @intCast(i), 0);
        try tl.record(&world);
    }
    try testing.expectEqual(@as(usize, 3), tl.last_index());

    try testing.expectEqual(@as(?usize, 1), try tl.restore(&world, 1));
    try testing.expectEqual(@as(?u32, 1), world.get_property(e, flag));
    try testing.expectEqual(@as(usize, 4), tl.len()); // future kept while scrubbing
    try testing.expectEqual(@as(?usize, 3), try tl.restore(&world, 99)); // clamped

    tl.discard_after(1);
    try testing.expectEqual(@as(usize, 2), tl.len());
    try testing.expectEqual(@as(?usize, 0), try tl.step_back(&world));
    try testing.expectEqual(@as(?u32, 0), world.get_property(e, flag));
    try testing.expectEqual(@as(?usize, null), try tl.step_back(&world));
}

test "P31-04: Timeline restores the hypervisor branch and countdown with the world" {
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const donnie = try world.intern_entity("Donnie");
    const engine = try world.intern_entity("Engine");
    var hypervisor = TemporalHypervisor.init(testing.allocator, &world);
    defer hypervisor.deinit();
    _ = try hypervisor.fork_branch(10, donnie, engine);

    var timeline = Timeline.init(testing.allocator);
    defer timeline.deinit();
    _ = try hypervisor.step_tick(null);
    _ = try hypervisor.step_tick(null);
    try timeline.record_with_temporal(&world, &hypervisor);
    try testing.expectEqual(@as(u64, 2), hypervisor.ticks_elapsed);

    _ = try hypervisor.step_tick(null);
    _ = try hypervisor.step_tick(null);
    try timeline.record_with_temporal(&world, &hypervisor);
    try testing.expectEqual(@as(u64, 4), hypervisor.ticks_elapsed);

    try testing.expectEqual(@as(?usize, 0), try timeline.restore_with_temporal(&world, &hypervisor, 0));
    try testing.expectEqual(@as(u64, 2), hypervisor.ticks_elapsed);
    try testing.expectEqual(@as(u64, 2), hypervisor.branch_world.?.current_tick);
    try testing.expect(hypervisor.branch_active);

    var plain = Timeline.init(testing.allocator);
    defer plain.deinit();
    try plain.record(&world);
    try testing.expectError(error.MissingTemporalSnapshot, plain.restore_with_temporal(&world, &hypervisor, 0));
}
