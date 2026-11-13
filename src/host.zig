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
const container_mod = @import("container.zig");
const grid_mod = @import("grid.zig");
const agency_mod = @import("agency.zig");
const command_mod = @import("command.zig");
const audio_mod = @import("audio.zig");
const mml_mod = @import("mml.zig");

const World = world_mod.World;
const EntityId = world_mod.EntityId;
const VM = vm_mod.VM;
const SpatialSystem = spatial_mod.SpatialSystem;
const CompiledProgram = codegen.CompiledProgram;
const TemporalHypervisor = hypervisor_mod.TemporalHypervisor;

/// Cue id the compiler emits for `say` statements (D-009).
pub const SAY_CUE_ID: u16 = 2;

/// Seeds script-declared subsystems into a world. Repeated calls preserve restored fact state.
pub fn initialize_subsystems(world: *World, compiled: *const CompiledProgram) !void {
    for (compiled.degradations.items) |declaration| {
        _ = try container_mod.ContainerSystem.init(world, declaration.config);
    }
    for (compiled.grids.items) |declaration| try grid_mod.seed(world, declaration);
    try agency_mod.seed(world, compiled.agendas.items);
}

/// One engine lifecycle tick: initialize declared subsystems, step the VM, advance subsystem
/// rules, then re-dispatch weaves queued by scripts (D-029). Hosts should tick through this,
/// never `step_tick` alone, or declared simulation rules and in-script weaves will not run.
pub fn tick(vm: *VM, compiled: *const CompiledProgram) !usize {
    try initialize_subsystems(vm.world, compiled);
    try vm.step_tick();
    for (compiled.degradations.items) |declaration| {
        const system = try container_mod.ContainerSystem.init(vm.world, declaration.config);
        try system.step(vm.world, vm.spatial);
    }
    // Grid automata run after the VM tick has pruned expired fires and smoke (D-055). Hazard
    // states follow, so scripts react to them on the next tick. Programs without grids skip
    // both, keeping their relation tables unchanged.
    if (compiled.grids.items.len > 0) {
        for (compiled.grids.items) |declaration| try grid_mod.step(vm.world, declaration);
        if (vm.spatial) |sp| try sp.update_grid_hazards(vm.world);
    }
    // Agendas see this tick's facts, cell hazards included (D-056). Pursuers then move, and
    // each interception becomes `Intercepts(Actor, Target, Agenda)`, whose handler runs next
    // tick like any fired cue.
    if (compiled.agendas.items.len > 0) {
        try agency_mod.step(vm.world, vm.spatial, vm.allocator, compiled.agendas.items);
        if (vm.spatial) |sp| {
            var met: [agency_mod.MAX_AGENDAS]agency_mod.Interception = undefined;
            const n = try agency_mod.pursue(vm.world, sp, compiled.agendas.items, &met);
            for (met[0..n]) |m| _ = try vm.fire_cue(compiled, "Intercepts", m.actor, m.target, m.agenda);
        }
    }
    return try vm.dispatch_pending_weaves(compiled);
}

/// What a typed line did (P26-02, D-057). `text` is a reply to show now; when `fired` is set,
/// the cue's handler speaks after the next tick, like any fired cue.
pub const CommandReply = struct {
    text: ?[]const u8 = null,
    fired: bool = false,
    walking: bool = false,
};

/// Interprets one typed line for `actor` and dispatches it: `interpret_command` then
/// `dispatch_command`. Hosts that must check a command before it runs (a proof whose actions
/// depend on where the actor stands) call the two halves themselves.
pub fn run_command(
    vm: *VM,
    compiled: *const CompiledProgram,
    interp: *command_mod.Interpreter,
    actor: EntityId,
    input: []const u8,
    buf: []u8,
) !CommandReply {
    return switch (interpret_command(vm, compiled, interp, actor, input, buf)) {
        .reply => |text| .{ .text = text },
        .command => |command| try dispatch_command(vm, compiled, actor, command),
    };
}

pub const Interpreted = union(enum) {
    /// Show this and do nothing else (an empty line gives an empty reply).
    reply: ?[]const u8,
    command: command_mod.Command,
};

fn command_room(vm: *VM, actor: EntityId) ?EntityId {
    var room: ?EntityId = vm.current_scene;
    if (vm.spatial) |sp| {
        if (sp.get_current_waypoint(actor)) |wp| {
            if (sp.graph.get_waypoint(wp)) |w| room = w.room;
        }
    }
    return room;
}

/// Interprets one typed line (P26-02, D-057). Nouns resolve in the actor's room (its
/// waypoint's room, else the VM's current scene) and its holdings.
pub fn interpret_command(
    vm: *VM,
    compiled: *const CompiledProgram,
    interp: *command_mod.Interpreter,
    actor: EntityId,
    input: []const u8,
    buf: []u8,
) Interpreted {
    const world = vm.world;
    const room = command_room(vm, actor);
    const frames = command_mod.FrameList.build(compiled.commands.items);
    const scope = command_mod.Scope.gather(world, vm.spatial, room, actor);
    const outcome = interp.interpret(world, compiled.aliases.items, frames.slice(), &scope, input);
    return switch (outcome) {
        .command => |c| .{ .command = c },
        else => .{ .reply = outcome.message(world, buf) },
    };
}

/// Runs an interpreted command. `WalksTo` starts a world-aware walk to a mark or to an agent's
/// waypoint and also fires its cue if handled. A command nothing answers replies
/// "Nothing happens."
pub fn dispatch_command(vm: *VM, compiled: *const CompiledProgram, actor: EntityId, command: command_mod.Command) !CommandReply {
    const world = vm.world;
    var reply = CommandReply{};
    var blocked = false;
    if (std.mem.eql(u8, command.cue, "WalksTo")) {
        if (vm.spatial) |sp| {
            if (walk_target(world, sp, command_room(vm, actor), command.a)) |dest| {
                reply.walking = try sp.walk_to_with_world(world, actor, dest);
                blocked = !reply.walking;
            }
        }
    }
    reply.fired = (try vm.fire_cue(compiled, command.cue, actor, command.a, command.b)) != null;
    if (!reply.fired and !reply.walking) {
        reply.text = if (blocked) "You can't get there from here." else "Nothing happens.";
    }
    return reply;
}

/// Fills `out` with the words the command bar may complete for `actor`: frame words and the
/// name and alias words of everything in scope (P26-03). Call after each tick or refresh.
pub fn command_words(vm: *VM, compiled: *const CompiledProgram, actor: EntityId, out: *command_mod.WordList) void {
    const room = command_room(vm, actor);
    const frames = command_mod.FrameList.build(compiled.commands.items);
    const scope = command_mod.Scope.gather(vm.world, vm.spatial, room, actor);
    command_mod.completion_words(vm.world, compiled.aliases.items, frames.slice(), &scope, out);
}

/// The waypoint a `WalksTo` target names: a mark in the room, or the waypoint an agent last
/// reached.
fn walk_target(world: *const World, sp: *const SpatialSystem, room: ?EntityId, target: ?EntityId) ?spatial_mod.WaypointId {
    const entity = target orelse return null;
    if (sp.get_current_waypoint(entity)) |wp| return wp;
    const name = world.get_entity_name(entity) orelse return null;
    if (room) |r| return sp.graph.find_waypoint_in_room(r, name);
    return sp.graph.find_waypoint(name);
}

/// A program's script scores as a playable soundtrack (P28-03, D-062): one `Music` per score,
/// named after it, in declaration order. Register `&soundtrack` with
/// `AudioBridge.set_soundtrack`; the audio thread then reads this value, so it must not move or
/// be deinitialised while registered. The frame's `current_score` picks the track by name.
pub const ScriptSoundtrack = struct {
    allocator: std.mem.Allocator,
    parsed: []mml_mod.Score,
    scores: []audio_mod.MmlScore,
    music: []audio_mod.Music,
    soundtrack: audio_mod.Soundtrack,

    pub fn init(allocator: std.mem.Allocator, compiled: *const codegen.CompiledProgram) !ScriptSoundtrack {
        const decls = compiled.scores.items;
        const parsed = try allocator.alloc(mml_mod.Score, decls.len * mml_mod.PART_COUNT);
        var parsed_made: usize = 0;
        errdefer {
            for (parsed[0..parsed_made]) |*p| p.deinit();
            allocator.free(parsed);
        }
        const scores = try allocator.alloc(audio_mod.MmlScore, decls.len);
        errdefer allocator.free(scores);
        const music = try allocator.alloc(audio_mod.Music, decls.len);
        errdefer allocator.free(music);
        for (decls, 0..) |decl, i| {
            scores[i] = .{};
            for (decl.parts, 0..) |text, part| {
                // Compiled and loaded scores were validated already; a failure here is a bug in
                // that validation, reported rather than played.
                var diag = mml_mod.Diagnostic{};
                const slot = &parsed[i * mml_mod.PART_COUNT + part];
                slot.* = mml_mod.parse(allocator, text, mml_mod.part_kind(part), &diag) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidScore => return error.InvalidScoreConfig,
                };
                parsed_made += 1;
                scores[i].parts[part] = audio_mod.MmlTrack.of(slot);
            }
            music[i] = .{ .name = decl.name, .score = &scores[i] };
        }
        return .{
            .allocator = allocator,
            .parsed = parsed,
            .scores = scores,
            .music = music,
            .soundtrack = .{ .tracks = music },
        };
    }

    pub fn has_scores(self: *const ScriptSoundtrack) bool {
        return self.music.len > 0;
    }

    pub fn deinit(self: *ScriptSoundtrack) void {
        for (self.parsed) |*p| p.deinit();
        self.allocator.free(self.parsed);
        self.allocator.free(self.scores);
        self.allocator.free(self.music);
    }
};

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

/// Puts each cast member on the first mark of its scene (D-065), so a person the script lists
/// can be seen, named, and talked to before any routine moves them. An actor the host already
/// placed keeps its place, so call this after placing actors by hand and before starting
/// routines. Repeated calls change nothing.
pub fn place_cast(spatial: *SpatialSystem, compiled: *const CompiledProgram) !void {
    for (compiled.cast.items) |place| {
        if (spatial.agents.contains(place.actor)) continue;
        try spatial.register_entity(place.actor, place.mark, CAST_SPEED);
    }
}

/// Walking speed for cast members placed by `place_cast`; the same speed the stock runner
/// gives routine actors.
pub const CAST_SPEED: u32 = 10;

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
        try initialize_subsystems(s.active_world(), compiled);
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

test "P23-01: host lifecycle initializes and advances declared degradation" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\degradation TestProfile:
        \\  substance TestReagent
        \\  stage Sound 1
        \\  stage Etched 1
        \\  stage Failed 0
        \\  vessel TestVial 4 3 Sound
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();

    try initialize_subsystems(&world, &compiled);
    const vial = world.lookup_entity("TestVial").?;
    const stage_rel = world.lookup_relation("ContainerStage").?;
    try testing.expectEqual(world.lookup_entity("Sound").?.to_int(), world.get_property(vial, stage_rel).?);
    _ = try tick(&vm, &compiled);
    try testing.expectEqual(world.lookup_entity("Etched").?.to_int(), world.get_property(vial, stage_rel).?);
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

test "P25-02: host lifecycle spreads a scripted fire to an actor and fires a hazard rule" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\relation Scorched(actor)
        \\scene: Gallery
        \\marks: GalleryEnd, GalleryStand
        \\
        \\grid GalleryFloor in Gallery:
        \\  size 3 1
        \\  cell 10
        \\  flammable 1 0 2 1
        \\  burning 0 0
        \\  place GalleryEnd 0 0
        \\  place GalleryStand 2 0
        \\  burn 4
        \\  spread 1
        \\  dissipate 3
        \\
        \\when Hero is InBurningCell:
        \\  remember Scorched(Hero)
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try initialize_subsystems(&world, &compiled);

    const hero = try world.intern_entity("Hero");
    try spatial.register_entity(hero, spatial.graph.find_waypoint("GalleryStand").?, 5);
    const scorched = world.lookup_relation("Scorched").?;
    const grid = spatial.grid_in_room(world.lookup_entity("Gallery").?).?;

    // Tick 1 lights cell 1, tick 2 lights the hero's cell 2, tick 3's rules see the hazard.
    _ = try tick(&vm, &compiled);
    try testing.expect(grid_mod.has_attribute(&world, grid, .{ .x = 1, .y = 0 }, .burning));
    try testing.expect(!world.has_fact(hero, scorched, null));
    _ = try tick(&vm, &compiled);
    try testing.expect(world.has_fact(hero, world.lookup_relation("InBurningCell").?, null));
    _ = try tick(&vm, &compiled);
    _ = try tick(&vm, &compiled);
    try testing.expect(world.has_fact(hero, scorched, null));
    try testing.expect(world.has_fact(hero, world.lookup_relation("InSmokeCell").?, null));
}

test "P33-01: host lifecycle seeds agendas and starts pursuit when an omission holds" {
    const compiler = @import("compiler.zig");
    const agency = @import("agency.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\relation Investigated(who, place)
        \\relation Warned(who)
        \\agenda WarnOff:
        \\  actor Keeper
        \\  target Hero
        \\  cooldown 5
        \\  requires Investigated(Hero, Shed)
        \\  unless Warned(Hero)
        \\
        \\on cue Snoops(Hero, Shed):
        \\  remember Investigated(Hero, Shed)
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    try vm.load_compiled_rules(&compiled);
    try initialize_subsystems(&world, &compiled);

    const warn_off = world.lookup_entity("WarnOff").?;
    try testing.expectEqual(agency.Stage.idle, agency.stage_of(&world, warn_off).?);
    _ = try tick(&vm, &compiled);
    try testing.expectEqual(agency.Stage.idle, agency.stage_of(&world, warn_off).?);

    _ = try vm.fire_cue(&compiled, "Snoops", world.lookup_entity("Hero").?, world.lookup_entity("Shed").?, null);
    _ = try tick(&vm, &compiled);
    try testing.expectEqual(agency.Stage.pursuing, agency.stage_of(&world, warn_off).?);

    // The encounter (P33-02) resolves it; the cooldown holds it idle although the trigger holds.
    try agency.resolve(&world, compiled.agendas.items[0].agenda);
    _ = try tick(&vm, &compiled);
    try testing.expectEqual(agency.Stage.idle, agency.stage_of(&world, warn_off).?);
}

test "P33-02: host lifecycle walks a pursuer to its target and fires Intercepts" {
    const compiler = @import("compiler.zig");
    const agency = @import("agency.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene: Estate
        \\cast: Keeper, Hero
        \\marks: Lodge, Lawn, Boathouse
        \\
        \\relation Investigated(who, place)
        \\relation Warned(who)
        \\agenda WarnOff:
        \\  actor Keeper
        \\  target Hero
        \\  requires Investigated(Hero, Boathouse)
        \\  unless Warned(Hero)
        \\
        \\on cue Snoops(Hero, Boathouse):
        \\  remember Investigated(Hero, Boathouse)
        \\
        \\on cue Intercepts(Keeper, Hero, WarnOff):
        \\  remember Warned(Hero)
        \\  say Keeper: "The boathouse is no place for guests."
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try initialize_subsystems(&world, &compiled);
    const keeper = world.lookup_entity("Keeper").?;
    const hero = world.lookup_entity("Hero").?;
    try spatial.register_entity(keeper, spatial.graph.find_waypoint("Lodge").?, 10);
    try spatial.register_entity(hero, spatial.graph.find_waypoint("Boathouse").?, 10);

    _ = try vm.fire_cue(&compiled, "Snoops", hero, world.lookup_entity("Boathouse").?, null);
    var spoke = false;
    var ticks: usize = 0;
    var buf: [128]u8 = undefined;
    while (!spoke) : (ticks += 1) {
        try testing.expect(ticks < 20);
        _ = try tick(&vm, &compiled);
        if (speech_this_tick(&world, &vm, &buf)) |line| spoke = std.mem.indexOf(u8, line, "boathouse") != null;
    }
    try testing.expectEqual(spatial.graph.find_waypoint("Boathouse").?, spatial.get_current_waypoint(keeper).?);
    try testing.expect(world.has_fact(hero, world.lookup_relation("Warned").?, null));
    // Warned ends the omission, so the agenda stays idle after its encounter.
    _ = try tick(&vm, &compiled);
    try testing.expectEqual(agency.Stage.idle, agency.stage_of(&world, world.lookup_entity("WarnOff").?).?);
}

test "P26-02: typed lines fire script cues, walk, and reply when nothing answers" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene: Galley
        \\cast: Cook, Mate
        \\props: Ladle, Kettle, Grog, Mug
        \\marks: Stove, Hatch
        \\
        \\command Pours: "pour <thing> into <thing>"
        \\alias Kettle: "pot"
        \\
        \\on cue LooksAt(Cook, Kettle):
        \\  say Cook: "Soot and old soup."
        \\
        \\on cue Pours(Cook, Grog, Mug):
        \\  say Cook: "Mind the fumes."
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    const galley = world.lookup_entity("Galley").?;
    try vm.transition_to_scene(galley);
    const cook = world.lookup_entity("Cook").?;
    const stove = spatial.graph.find_waypoint("Stove").?;
    try spatial.register_entity(cook, stove, 10);
    try spatial.register_entity(world.lookup_entity("Mate").?, stove, 10);
    const carries = try world.intern_relation("Carries", .set);
    try world.remember(cook, carries, world.lookup_entity("Grog").?.to_int(), 0);

    var interp = command_mod.Interpreter{};
    var buf: [128]u8 = undefined;
    var speech: [128]u8 = undefined;

    var reply = try run_command(&vm, &compiled, &interp, cook, "examine the pot", &buf);
    try testing.expect(reply.fired and reply.text == null);
    _ = try tick(&vm, &compiled);
    try testing.expectEqualStrings("Cook: \"Soot and old soup.\"", speech_this_tick(&world, &vm, &speech).?);

    reply = try run_command(&vm, &compiled, &interp, cook, "pour grog into mug", &buf);
    try testing.expect(reply.fired);
    _ = try tick(&vm, &compiled);
    try testing.expectEqualStrings("Cook: \"Mind the fumes.\"", speech_this_tick(&world, &vm, &speech).?);

    reply = try run_command(&vm, &compiled, &interp, cook, "examine ladle", &buf);
    try testing.expectEqualStrings("Nothing happens.", reply.text.?);

    reply = try run_command(&vm, &compiled, &interp, cook, "go to hatch", &buf);
    try testing.expect(reply.walking and reply.text == null);
    try testing.expectEqual(spatial.graph.find_waypoint("Hatch").?, spatial.agents.get(cook).?.target_wp.?);

    reply = try run_command(&vm, &compiled, &interp, cook, "talk to the xyzzy", &buf);
    try testing.expectEqualStrings("I don't know the word \"xyzzy\".", reply.text.?);
}

test "P28-03: script scores become a soundtrack the frame's score name selects" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = spatial_mod.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene Hall:
        \\  marks: Door
        \\score Calm:
        \\  lead "o5 l8 L c e g e"
        \\  drums "L k4 h4"
        \\  scene Hall
        \\score Chase: "t160 L c16 d16"
        \\transition to scene Hall
        \\routine Alarm(Guard):
        \\  wait 1 ticks
        \\  play score Chase
    );
    defer compiled.deinit();
    var music = try ScriptSoundtrack.init(testing.allocator, &compiled);
    defer music.deinit();
    try testing.expect(music.has_scores());
    try testing.expectEqual(@as(usize, 2), music.soundtrack.tracks.len);
    try testing.expectEqualStrings("Chase", music.soundtrack.tracks[1].name);
    try testing.expectEqual(@as(usize, 2), music.scores[0].part(.percussion).events.len);

    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try run_initial_statements(&world, &vm, &compiled);

    var audio = audio_mod.AudioBridge.init();
    audio.set_soundtrack(&music.soundtrack);
    var bridge = display_mod.DisplayBridge.init();
    bridge.attach_audio_bridge(&audio);
    var pcm: [512]i16 = undefined;

    // The scene's score plays first.
    bridge.capture_frame(&world, &spatial, &vm);
    try testing.expectEqualStrings("Calm", bridge.back_buffer.get_current_score());
    audio.render_samples(&pcm);
    try testing.expectEqual(@as(?u8, 0), audio.synth.current_track);
    try testing.expectEqual(@as(?*const audio_mod.MmlScore, &music.scores[0]), audio.synth.mml.score);

    // `play score` overrides it; the bridge crossfades to the named track.
    _ = try vm.spawn_routine(try world.intern_entity("Guard"), compiled.routine_entries.get("Alarm").?);
    for (0..3) |_| _ = try tick(&vm, &compiled);
    bridge.capture_frame(&world, &spatial, &vm);
    try testing.expectEqualStrings("Chase", bridge.back_buffer.get_current_score());
    var fade: [8192]i16 = undefined;
    audio.render_samples(&fade);
    try testing.expectEqual(@as(?u8, 1), audio.synth.current_track);

    // A name the soundtrack lacks falls back to the scene rule, which a script soundtrack has
    // not got, so it is silence rather than a wrong track.
    try testing.expectEqual(@as(?u8, null), audio.track_for("Hall", "Unknown"));
    try testing.expectEqual(@as(?u8, 0), audio.track_for("Anywhere", "Calm"));

    // A program without scores makes an empty soundtrack.
    var plain = try compiler.compile_source(testing.allocator, &world, null, "entity Lamp\n");
    defer plain.deinit();
    var none = try ScriptSoundtrack.init(testing.allocator, &plain);
    defer none.deinit();
    try testing.expect(!none.has_scores());
}

test "D-065: place_cast puts each cast member on its own scene's first mark" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, world_mod.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene Gatehouse:
        \\  cast: Warden, Porter
        \\  marks: Gate, Stair
        \\
        \\scene Rampart:
        \\  cast: Sentry, Warden
        \\  marks: Tower, Walk
        \\
        \\scene Void:
        \\  cast: Ghost
    );
    defer compiled.deinit();
    // The Warden is listed twice and starts in the first scene; the Ghost's scene has no mark.
    try testing.expectEqual(@as(usize, 3), compiled.cast.items.len);

    const porter = world.lookup_entity("Porter").?;
    const sentry = world.lookup_entity("Sentry").?;
    const warden = world.lookup_entity("Warden").?;
    const stair = spatial.graph.find_waypoint("Stair").?;
    try spatial.register_entity(porter, stair, 7);
    try place_cast(&spatial, &compiled);
    try place_cast(&spatial, &compiled);

    const gate = spatial.graph.find_waypoint("Gate").?;
    const tower = spatial.graph.find_waypoint("Tower").?;
    try testing.expectEqual(gate, spatial.get_current_waypoint(warden).?);
    try testing.expectEqual(tower, spatial.get_current_waypoint(sentry).?);
    // An actor the host placed keeps its mark.
    try testing.expectEqual(stair, spatial.get_current_waypoint(porter).?);
    try testing.expect(!spatial.agents.contains(world.lookup_entity("Ghost").?));
    try testing.expectEqual(@as(usize, 3), spatial.agents.count());
}
