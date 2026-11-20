//! Host kit: shared plumbing for programs that drive the engine (P32-16, D-033).
//!
//! Every proof of concept, and any game built on BeSpoke, needs the same few things around
//! the VM: tick and re-dispatch weaves, read what the script said this tick, run top-level
//! statements, record a timeline for rewind, and run an interactive loop that handles pause,
//! single-step, scrub, rewind, and save actions. These used to be copied into each proof with
//! drifting behaviour. They live here once, named by function, with no game content.
const std = @import("std");
const ListWriter = @import("list_writer.zig").ListWriter;
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
const spell_mod = @import("spell.zig");
const decision_mod = @import("decision.zig");
const audio_mod = @import("audio.zig");
const mml_mod = @import("mml.zig");
const society_mod = @import("society.zig");

const World = world_mod.World;
const EntityId = world_mod.EntityId;
const VM = vm_mod.VM;
const SpatialSystem = spatial_mod.SpatialSystem;
const CompiledProgram = codegen.CompiledProgram;
const TemporalHypervisor = hypervisor_mod.TemporalHypervisor;

/// Builds the VM half of a custom host without exposing `CompiledProgram` storage. The returned
/// VM borrows `world`, `spatial`, and `compiled`; deinitialize it before any of them (P38-03,
/// D-107). Call `start_script` to seed and launch the program, or drive it explicitly.
pub fn init_vm(
    allocator: std.mem.Allocator,
    world: *World,
    spatial: *SpatialSystem,
    compiled: *const CompiledProgram,
) !VM {
    var vm = VM.init(allocator, world, &compiled.chunk);
    errdefer vm.deinit();
    vm.spatial = spatial;
    try vm.load_compiled_rules(compiled);
    return vm;
}

/// Cue id the compiler emits for `say` statements (D-009).
pub const SAY_CUE_ID: u16 = 2;

/// A host-owned instance of one script-declared society. Configure once before
/// play or save restore; initializing again reseeds the members' starting facts.
/// The program and the same world's entity and relation registries must outlive it.
pub const ScriptSociety = struct {
    core: society_mod.Society,
    world: *World,

    /// Selects a declaration by zero-based source order.
    pub fn init(world: *World, compiled: *const CompiledProgram, index: usize) !ScriptSociety {
        if (index >= compiled.societies.items.len) return error.SocietyNotDeclared;
        return .{ .core = try society_mod.Society.init(world, compiled.societies.items[index].config), .world = world };
    }

    /// Runs once after each host tick, using the VM's current world and spatial system.
    pub fn step(self: *ScriptSociety, vm: *VM) !void {
        if (vm.world != self.world) return error.SocietyWorldMismatch;
        try self.core.step(vm.world, vm.spatial orelse return error.SocietyNeedsSpatialSystem, vm);
    }
};

/// Seeds script-declared subsystems into a world. Repeated calls preserve restored fact state.
pub fn initialize_subsystems(world: *World, compiled: *const CompiledProgram) !void {
    for (compiled.degradations.items) |declaration| {
        _ = try container_mod.ContainerSystem.init(world, declaration.config);
    }
    for (compiled.grids.items) |declaration| try grid_mod.seed(world, declaration);
    try agency_mod.seed(world, compiled.agendas.items);
    try decision_mod.seed(world, compiled.decisions.items);
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
    // Decisions run after agendas, so an arriving actor can decide on the tick it arrives
    // (P44-05). The chosen option's cue runs on the next tick like any fired cue.
    if (compiled.decisions.items.len > 0) {
        const choices = try decision_mod.step(vm.world, compiled.decisions.items);
        for (choices.slice()) |choice| {
            const cue_name = vm.world.get_entity_name(choice.cue) orelse continue;
            _ = try vm.fire_cue(compiled, cue_name, choice.actor, choice.option, null);
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

/// Presents `evidence` to `person` for `actor` (P44-03). The engine records `Presented(person,
/// evidence)` before dispatching, so rules and readouts observe every presentation as World
/// state even when no handler answers. The script's `Presents(actor, person, evidence)` handler
/// decides what the character reveals, with `Knows`/`Believes`/`Rejects` naming what they know.
/// The parameters take evidence before person, the reverse of the cue's target order.
/// Returns whether a handler answered.
pub fn present(
    vm: *VM,
    compiled: *const CompiledProgram,
    actor: EntityId,
    evidence: EntityId,
    person: EntityId,
) !bool {
    const presented = try vm.world.intern_relation("Presented", .set);
    try vm.world.remember(person, presented, evidence.to_int(), 0);
    return (try vm.fire_cue(compiled, "Presents", actor, person, evidence)) != null;
}

/// Casts a spell for `caster` (P44-04). The spell's words are checked against what the caster
/// knows, and only an accepted combination fires the cue named after the spell, with the caster
/// and `target` as its arguments. A refused combination changes nothing, so a fizzle cannot
/// leak state the player has not earned. The text is matched against the book's spell names
/// ignoring ASCII case; the name of the first book is the one a script declares.
pub fn cast(
    vm: *VM,
    compiled: *const CompiledProgram,
    caster: EntityId,
    name: []const u8,
    target: EntityId,
) !spell_mod.Outcome {
    const book = spellbook(compiled) orelse return .{ .refused = .no_such_spell };
    const spell = spell_mod.named_text(book, vm.world, name) orelse return .{ .refused = .no_such_spell };
    return dispatch_spell(vm, compiled, caster, spell, target);
}

/// Combines three words for `caster` (P44-04), for a host that lets the player build a phrase
/// instead of naming a spell. The refusal and dispatch rules match `cast`.
pub fn combine(
    vm: *VM,
    compiled: *const CompiledProgram,
    caster: EntityId,
    power: EntityId,
    element: EntityId,
    form: EntityId,
    target: EntityId,
) !spell_mod.Outcome {
    const book = spellbook(compiled) orelse return .{ .refused = .no_such_spell };
    const spell = spell_mod.resolve(book, power, element, form) orelse return .{ .refused = .no_such_spell };
    return dispatch_spell(vm, compiled, caster, spell, target);
}

fn spellbook(compiled: *const CompiledProgram) ?*const spell_mod.Book {
    if (compiled.spellbooks.items.len == 0) return null;
    return &compiled.spellbooks.items[0].book;
}

fn dispatch_spell(vm: *VM, compiled: *const CompiledProgram, caster: EntityId, spell: spell_mod.Spell, target: EntityId) !spell_mod.Outcome {
    const cue = vm.world.get_entity_name(spell.entity) orelse return .{ .refused = .no_such_spell };
    const outcome = spell_mod.check(vm.world, caster, spell);
    switch (outcome) {
        .refused => return outcome,
        .cast => {
            _ = try vm.fire_cue(compiled, cue, caster, target, null);
            return outcome;
        },
    }
}

/// Runs an interpreted command. `WalksTo` starts a world-aware walk to a mark or to an agent's
/// waypoint and also fires its cue if handled. `Presents` records the presentation and fires
/// `Presents(actor, person, evidence)`. A command nothing answers replies "Nothing happens."
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
    if (std.mem.eql(u8, command.cue, "Presents")) {
        if (command.a) |evidence| {
            if (command.b) |person| reply.fired = try present(vm, compiled, actor, evidence, person);
        }
    } else {
        reply.fired = (try vm.fire_cue(compiled, command.cue, actor, command.a, command.b)) != null;
    }
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
    writer: std.Io.Writer,
    count: usize = 0,
    last_speaker: u32 = 0,

    pub fn init(buf: []u8) SpeechLog {
        return .{ .writer = .fixed(buf) };
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
            // The speaker reads as words, as names do everywhere on screen (D-093): `HarbourClerk`
            // speaks as "Harbour Clerk".
            var name_buf: [48]u8 = undefined;
            const name = @import("display/dialogue_panel.zig").display_name(world.get_entity_name(EntityId.from_int(cue.args[0])) orelse "Someone", &name_buf);
            const text = world.get_entity_name(EntityId.from_int(cue.args[1])) orelse "";
            const w = &self.writer;
            if (self.count > 0) w.writeAll("  ") catch return;
            if (self.count == 0 or cue.args[0] != self.last_speaker) w.print("{s}: ", .{name}) catch return;
            w.print("\"{s}\"", .{text}) catch return;
            self.last_speaker = cue.args[0];
            self.count += 1;
        }
    }

    pub fn message(self: *SpeechLog) ?[]const u8 {
        return if (self.count > 0) self.writer.buffered() else null;
    }
};

/// Milliseconds on the awake clock, read through the window's `Io` (Zig 0.16+). A session runs
/// only in a desktop or offscreen window, which is always made with one.
fn now_ms(window: *const display_mod.DisplayWindow) i64 {
    return std.Io.Timestamp.now(window.io.?, .awake).toMilliseconds();
}

/// One `say` line from the most recent tick: the speaker's entity name and the line.
pub const SpeechLine = struct { speaker: []const u8, text: []const u8 };

/// The `say` lines of the most recent tick, one entry per line, for hosts that show each line
/// on its own (D-080) instead of joined like `SpeechLog`. Slices borrow World names. Returns
/// how many it wrote, stopping when `out` is full.
pub fn speech_lines(world: *const World, vm: *const VM, out: []SpeechLine) usize {
    var n: usize = 0;
    for (vm.emitted_cues.items) |cue| {
        if (n == out.len) break;
        if (cue.cue_id != SAY_CUE_ID or cue.arg_count < 2) continue;
        out[n] = .{
            .speaker = world.get_entity_name(EntityId.from_int(cue.args[0])) orelse "Someone",
            .text = world.get_entity_name(EntityId.from_int(cue.args[1])) orelse "",
        };
        n += 1;
    }
    return n;
}

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
    while (!vm.routine_has_halted(fid) and guard < 64) : (guard += 1) {
        _ = try tick(vm, compiled);
    }
}

/// A stable 64-bit digest of the World's fact table (P34-01). Each fact contributes its
/// subject's name, its relation's name, its object or value, and its expiry tick, so the digest
/// does not depend on interning order; the per-fact hashes are sorted before they are combined,
/// so it does not depend on table order either. A golden that records it changes whenever any
/// fact does, including one no transcript line prints.
pub fn fact_digest(allocator: std.mem.Allocator, world: *const World) !u64 {
    const slice = world.facts.slice();
    const rows = try allocator.alloc(u64, world.facts.len);
    defer allocator.free(rows);
    for (rows, 0..) |*row, i| {
        var h = std.hash.Wyhash.init(0);
        h.update(world.get_entity_name(slice.items(.subject)[i]) orelse "");
        h.update(&[_]u8{0});
        const meta = world.get_relation_meta(slice.items(.relation)[i]);
        h.update(if (meta) |m| m.name else "");
        h.update(&[_]u8{0});
        h.update(std.mem.asBytes(&slice.items(.object_or_value)[i]));
        h.update(std.mem.asBytes(&slice.items(.expires_at_tick)[i]));
        row.* = h.final();
    }
    std.mem.sort(u64, rows, {}, std.sort.asc(u64));
    return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(rows));
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

/// The name a script uses for the whole stage rather than a person (D-094).
pub const STAGE_ACTOR = "Scene";

/// Walking speed for cast members placed by `place_cast`; the same speed the stock runner
/// gives routine actors.
pub const CAST_SPEED: u32 = 10;

/// The actor a host's clicks and typed commands act for: the actor of the first top-level routine in source
/// order (P29-02, D-064). Routines compile in source order, so the lowest entry wins; this holds
/// for packages too, which keep entry addresses. Path initializers are skipped; path routines
/// compile after every top-level routine, so they are chosen only when no top-level routine
/// exists. Null when the script declares no routine.
pub fn player_actor(compiled: *const CompiledProgram) ?[]const u8 {
    var best_pc: usize = std.math.maxInt(usize);
    var best: ?[]const u8 = null;
    var it = compiled.routine_entries.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (std.mem.startsWith(u8, name, codegen.PATH_ROUTINE_PREFIX)) continue;
        if (entry.value_ptr.* >= best_pc) continue;
        best_pc = entry.value_ptr.*;
        best = compiled.routine_entities.get(name);
    }
    return best;
}

/// Starts a compiled script the way every stock host does (P29-03, D-066): runs the top-level
/// statements, places the cast (D-065), then starts every routine on its actor, putting any
/// actor still unplaced on the script's first mark. Returns the player (`player_actor`, else an
/// entity named `Player`). Call once, after `vm.load_compiled_rules`.
pub fn start_script(world: *World, spatial: *SpatialSystem, vm: *VM, compiled: *const CompiledProgram) !EntityId {
    try run_initial_statements(world, vm, compiled);
    try place_cast(spatial, compiled);
    const first_mark: ?spatial_mod.WaypointId = if (spatial.graph.waypoints.items.len > 0) spatial.graph.waypoints.items[0].id else null;
    // Paths compile after every top-level routine (initializer first, then its routines), so an
    // entry at or past the first initializer belongs to a path. A path's initializer runs when
    // `VM.select_path` chooses it, and its routines when the host starts them (D-052); started
    // here, every path would lock the others' gates, and a muted routine whose guard had not run
    // yet would run its body once its path was chosen.
    var first_path_pc: usize = std.math.maxInt(usize);
    var paths_it = compiled.routine_entries.iterator();
    while (paths_it.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, codegen.PATH_ROUTINE_PREFIX)) first_path_pc = @min(first_path_pc, entry.value_ptr.*);
    }
    var it = compiled.routine_entries.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* >= first_path_pc) continue;
        const actor_name = compiled.routine_entities.get(entry.key_ptr.*) orelse "Player";
        const actor = try world.intern_entity(actor_name);
        // `Scene` names the whole stage (`say ... to Scene`, scene-wide `animate`); a routine
        // on it, such as the weather, runs without a body on a mark, so no one is drawn there.
        if (first_mark) |mark| {
            if (!std.mem.eql(u8, actor_name, STAGE_ACTOR) and !spatial.agents.contains(actor)) try spatial.register_entity(actor, mark, CAST_SPEED);
        }
        _ = try vm.spawn_routine(actor, entry.value_ptr.*);
    }
    return world.intern_entity(player_actor(compiled) orelse "Player");
}

/// Starts one named routine for one named actor. If the script did not place that actor through
/// `cast:`, the actor starts on the graph's first waypoint at `speed` (P38-03, D-107). This is
/// the supported test/custom-host boundary for routine lookup; program tables remain internal.
pub fn start_routine(
    world: *World,
    spatial: *SpatialSystem,
    vm: *VM,
    compiled: *const CompiledProgram,
    routine: []const u8,
    actor_name: []const u8,
    speed: u32,
) !vm_mod.FiberId {
    const entry = compiled.routine_entries.get(routine) orelse return error.UnknownRoutine;
    const actor = try world.intern_entity(actor_name);
    if (!spatial.agents.contains(actor)) {
        if (spatial.graph.waypoints.items.len == 0) return error.NoWaypoints;
        try spatial.register_entity(actor, spatial.graph.waypoints.items[0].id, speed);
    }
    return vm.spawn_routine(actor, entry);
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
        world: std.array_list.Managed(u8),
        temporal: ?std.array_list.Managed(u8) = null,

        pub fn deinit(self: *Snapshot) void {
            self.world.deinit();
            if (self.temporal) |*temporal| temporal.deinit();
        }
    };

    snapshots: std.array_list.Managed(Snapshot),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Timeline {
        return .{ .snapshots = std.array_list.Managed(Snapshot).init(allocator), .allocator = allocator };
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
        var snapshot = Snapshot{ .world = std.array_list.Managed(u8).init(self.allocator) };
        errdefer snapshot.deinit();
        var lw1 = ListWriter.init(&snapshot.world);
        try world.save_state(&lw1.writer);
        if (hypervisor) |live| {
            var temporal = std.array_list.Managed(u8).init(self.allocator);
            errdefer temporal.deinit();
            var lw2 = ListWriter.init(&temporal);
            try temporal_mod.TemporalSnapshot.write(live, &lw2.writer);
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
        var world_stream: std.Io.Reader = .fixed(snapshot.world.items);
        try world.restore_state(&world_stream);

        if (hypervisor) |live| {
            const temporal_bytes = &(snapshot.temporal orelse return error.MissingTemporalSnapshot);
            var temporal_stream: std.Io.Reader = .fixed(temporal_bytes.items);
            var temporal = try temporal_mod.TemporalSnapshot.read(self.allocator, world, &temporal_stream);
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
/// A doorway between scenes (D-094, D-100): when the player's walk ends on `mark` while
/// `scene` is on stage, the stage changes to `to_scene` and the player stands on `to_mark`. A
/// player placed on an exit mark stays put; only a walk that ends there, or a walk asked for
/// while already standing there, leaves. Desktop hosts and browser decks share one list per
/// game.
pub const Exit = struct {
    scene: []const u8,
    mark: []const u8,
    to_scene: []const u8,
    to_mark: []const u8,
    /// Where to add `mark` when the script declares no such mark: world coordinates in `scene`,
    /// joined to the nearest mark there. Script marks are spaced 20 units apart from 0, so a
    /// doorway past the last one would fall off the stage; this places it on screen.
    add_at: ?struct { x: i32, y: i32 } = null,
};

/// Adds the doorway marks `exits` ask for that the script did not declare.
pub fn add_exit_marks(world: *World, spatial: *SpatialSystem, exits: []const Exit) !void {
    for (exits) |exit| {
        const at = exit.add_at orelse continue;
        const scene = world.lookup_entity(exit.scene) orelse return error.UnknownScene;
        if (spatial.graph.find_waypoint_in_room(scene, exit.mark) != null) continue;
        var nearest: ?u16 = null;
        var best: i64 = std.math.maxInt(i64);
        for (spatial.graph.waypoints.items) |wp| {
            if (wp.room != scene) continue;
            const dx: i64 = wp.pos.x - at.x;
            const dy: i64 = wp.pos.y - at.y;
            if (dx * dx + dy * dy < best) {
                best = dx * dx + dy * dy;
                nearest = wp.id;
            }
        }
        const id = try spatial.graph.add_waypoint(scene, at.x, at.y, exit.mark);
        if (nearest) |n| try spatial.graph.connect(n, id, null);
    }
}

/// Takes the exit on the mark `player` stands on, if one leads out of the scene on stage.
/// Returns the exit taken.
pub fn take_exit_here(world: *const World, spatial: *SpatialSystem, vm: *VM, exits: []const Exit, player: EntityId) !?Exit {
    const scene = vm.current_scene orelse return null;
    const agent = spatial.agents.get(player) orelse return null;
    const here = spatial.graph.get_waypoint(agent.current_wp) orelse return null;
    const scene_name = world.get_entity_name(scene) orelse return null;
    for (exits) |exit| {
        if (!std.mem.eql(u8, exit.scene, scene_name) or !std.mem.eql(u8, exit.mark, here.name)) continue;
        const to = world.lookup_entity(exit.to_scene) orelse return null;
        try vm.transition_to_scene(to);
        _ = try spatial.transition_actor(player, to, spatial.graph.find_waypoint_in_room(to, exit.to_mark));
        return exit;
    }
    return null;
}

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
    /// The game's doorways and who walks through them (D-100); empty, none are taken.
    exits: []const Exit = &.{},
    player: ?EntityId = null,

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
            .last_tick_ms = now_ms(window),
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
        const now = now_ms(self.window);
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
        const walking_before = if (self.player) |p| self.spatial.is_moving(p) else false;
        const dispatched = try tick(self.vm, self.compiled);
        // A plain walk that ended on a doorway this tick leaves through it; a walk to act on
        // something (D-092) does not, though the mark beside a prop may be a doorway.
        if (walking_before and self.window.approach == null) {
            if (self.player) |p| if (!self.spatial.is_moving(p)) {
                _ = try self.leave_through(p);
            };
        }
        try self.record_snapshot();
        self.cursor = self.timeline.last_index();
        self.refresh();
        return dispatched;
    }

    /// Walks the player to `wp`, as a WALK click asks. Already standing on a doorway mark, the
    /// player leaves through it at once. Returns false when there is no way there.
    pub fn walk_player(self: *Session, wp: u16) !bool {
        const p = self.player orelse return false;
        // `walk_to` reports false for a walk to the mark the player already stands on, which
        // is how a click on a doorway underfoot asks to leave.
        const ok = try self.spatial.walk_to(p, wp);
        if (!self.spatial.is_moving(p) and try self.leave_through(p)) {
            try self.record_now();
            return true;
        }
        return ok;
    }

    fn leave_through(self: *Session, p: EntityId) !bool {
        const exit = (try take_exit_here(self.active_world(), self.spatial, self.vm, self.exits, p)) orelse return false;
        var name_buf: [48]u8 = undefined;
        var buf: [80]u8 = undefined;
        const name = @import("display/dialogue_panel.zig").display_name(exit.to_scene, &name_buf);
        self.window.set_cue_banner(std.fmt.bufPrint(&buf, "{s}.", .{name}) catch exit.to_scene, 0);
        self.refresh();
        return true;
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

test "D-080: speech_lines gives each say line of a tick on its own" {
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    const chunk_mod = @import("bytecode.zig");
    var chunk = chunk_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    const hero = try world.intern_entity("Hero");
    const other = try world.intern_entity("Other");
    const a = try world.intern_entity("First line.");
    const b = try world.intern_entity("Second line.");
    try vm.emitted_cues.append(.{ .cue_id = SAY_CUE_ID, .args = .{ hero.to_int(), a.to_int(), 0, 0 }, .arg_count = 2 });
    try vm.emitted_cues.append(.{ .cue_id = 7, .args = .{ 0, 0, 0, 0 }, .arg_count = 0 });
    try vm.emitted_cues.append(.{ .cue_id = SAY_CUE_ID, .args = .{ other.to_int(), b.to_int(), 0, 0 }, .arg_count = 2 });

    var lines: [4]SpeechLine = undefined;
    try testing.expectEqual(@as(usize, 2), speech_lines(&world, &vm, &lines));
    try testing.expectEqualStrings("Hero", lines[0].speaker);
    try testing.expectEqualStrings("First line.", lines[0].text);
    try testing.expectEqualStrings("Other", lines[1].speaker);
    try testing.expectEqualStrings("Second line.", lines[1].text);
    try testing.expectEqual(@as(usize, 1), speech_lines(&world, &vm, lines[0..1]));
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
    const hero = try world.intern_entity("Hero");
    const engine = try world.intern_entity("Engine");
    var hypervisor = TemporalHypervisor.init(testing.allocator, &world);
    defer hypervisor.deinit();
    _ = try hypervisor.fork_branch(10, hero, engine);

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

test "P44-03: a presentation records Presented and reveals only what the character knows" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene: Study
        \\cast: Hero, Pell
        \\props: Slip, Log
        \\marks: Desk
        \\
        \\relation Knows(who, what)
        \\relation Revealed(who, what)
        \\
        \\on cue Presents(Hero, Pell, Slip):
        \\  if Knows(Pell, Slip):
        \\    remember Revealed(Hero, Slip)
        \\    say Pell: "That is the slip from plate 41."
        \\  if not Knows(Pell, Slip):
        \\    say Pell: "What is this meant to prove?"
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    const study = world.lookup_entity("Study").?;
    try vm.transition_to_scene(study);
    const hero = world.lookup_entity("Hero").?;
    const pell = world.lookup_entity("Pell").?;
    const slip = world.lookup_entity("Slip").?;
    const log = world.lookup_entity("Log").?;
    const desk = spatial.graph.find_waypoint("Desk").?;
    try spatial.register_entity(hero, desk, 10);
    try spatial.register_entity(pell, desk, 10);
    const carries = try world.intern_relation("Carries", .set);
    try world.remember(hero, carries, slip.to_int(), 0);
    try world.remember(hero, carries, log.to_int(), 0);

    var interp = command_mod.Interpreter{};
    var buf: [160]u8 = undefined;
    var speech: [160]u8 = undefined;

    // The action records the presentation before the handler runs, and a character who does not
    // know the evidence reveals nothing.
    var reply = try run_command(&vm, &compiled, &interp, hero, "present the slip to pell", &buf);
    try testing.expect(reply.fired and reply.text == null);
    const presented = world.lookup_relation("Presented") orelse return error.MissingPresented;
    try testing.expect(world.has_fact(pell, presented, slip.to_int()));
    _ = try tick(&vm, &compiled);
    try testing.expectEqualStrings("Pell: \"What is this meant to prove?\"", speech_this_tick(&world, &vm, &speech).?);
    try testing.expect(!world.has_fact(hero, world.lookup_relation("Revealed").?, slip.to_int()));

    // Teaching him the evidence changes what the next presentation reveals. A set fact keeps
    // one row per piece of evidence, so showing the same slip again adds no second row.
    try world.remember(pell, try world.intern_relation("Knows", .set), slip.to_int(), 0);
    reply = try run_command(&vm, &compiled, &interp, hero, "show the slip to pell", &buf);
    try testing.expect(reply.fired);
    _ = try tick(&vm, &compiled);
    try testing.expectEqualStrings("Pell: \"That is the slip from plate 41.\"", speech_this_tick(&world, &vm, &speech).?);
    try testing.expect(world.has_fact(hero, world.lookup_relation("Revealed").?, slip.to_int()));
    var presentations: usize = 0;
    var it = world.query(pell, presented, null);
    while (it.next()) |_| presentations += 1;
    try testing.expectEqual(@as(usize, 1), presentations);

    // A second piece of evidence records even when no handler answers it.
    reply = try run_command(&vm, &compiled, &interp, hero, "present the log to pell", &buf);
    try testing.expect(!reply.fired);
    try testing.expectEqualStrings("Nothing happens.", reply.text.?);
    try testing.expect(world.has_fact(pell, presented, log.to_int()));
    presentations = 0;
    it = world.query(pell, presented, null);
    while (it.next()) |_| presentations += 1;
    try testing.expectEqual(@as(usize, 2), presentations);
}

test "P44-04: a cast fires the spell's cue only when the caster knows every word" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene: Study
        \\cast: Hero, Pell
        \\marks: Desk
        \\relation Ready(who)
        \\spellbook Grimoire:
        \\  power Forge
        \\  element Ember
        \\  form Bolt
        \\  spell Kindle: Forge, Ember, Bolt
        \\on cue Kindle(Hero, Pell):
        \\  remember Ready(Pell)
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    const study = world.lookup_entity("Study").?;
    try vm.transition_to_scene(study);
    const hero = world.lookup_entity("Hero").?;
    const pell = world.lookup_entity("Pell").?;
    const ready = try world.intern_relation("Ready", .set);

    // No word known: the power refuses first and the handler never runs.
    var outcome = try cast(&vm, &compiled, hero, "kindle", pell);
    try testing.expectEqual(spell_mod.Refusal.unlearned_power, outcome.refused);
    _ = try tick(&vm, &compiled);
    try testing.expect(!world.has_fact(pell, ready, 0));

    // Two of three words: the form refuses.
    const knows = try world.intern_relation("Knows", .set);
    try world.remember(hero, knows, world.lookup_entity("Forge").?.to_int(), 0);
    try world.remember(hero, knows, world.lookup_entity("Ember").?.to_int(), 0);
    outcome = try cast(&vm, &compiled, hero, "kindle", pell);
    try testing.expectEqual(spell_mod.Refusal.unlearned_form, outcome.refused);
    _ = try tick(&vm, &compiled);
    try testing.expect(!world.has_fact(pell, ready, 0));

    // The whole phrase, typed in any case, fires the cue named after the spell.
    try world.remember(hero, knows, world.lookup_entity("Bolt").?.to_int(), 0);
    outcome = try cast(&vm, &compiled, hero, "KINDLE", pell);
    try testing.expectEqual(world.lookup_entity("Kindle").?, outcome.cast.entity);
    _ = try tick(&vm, &compiled);
    try testing.expect(world.has_fact(pell, ready, 0));

    // A name the book lacks is refused, and no cue fires.
    outcome = try cast(&vm, &compiled, hero, "temper", pell);
    try testing.expectEqual(spell_mod.Refusal.no_such_spell, outcome.refused);
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

test "D-094: a routine on the Scene runs, but the Scene gets no body on a mark" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene Green:
        \\  cast: Hero
        \\  marks: Line, Wall
        \\
        \\routine Weather(Scene):
        \\  loop:
        \\    remember Breezy(Scene, true)
        \\    wait 5 ticks
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    _ = try start_script(&world, &spatial, &vm, &compiled);
    _ = try tick(&vm, &compiled);
    const scene = world.lookup_entity(STAGE_ACTOR).?;
    try testing.expect(!spatial.agents.contains(scene));
    try testing.expect(world.has_fact(scene, world.lookup_relation("Breezy").?, null));
}

test "P34-01: the fact digest ignores table and interning order and catches any changed fact" {
    var a = try World.init(testing.allocator, 256 * 1024);
    defer a.deinit();
    var b = try World.init(testing.allocator, 256 * 1024);
    defer b.deinit();
    // The same facts, interned and remembered in a different order.
    const a_hero = try a.intern_entity("Hero");
    const a_key = try a.intern_entity("Key");
    const a_has = try a.intern_relation("Has", .set);
    const a_at = try a.intern_relation("At", .property);
    _ = try a.remember(a_hero, a_has, a_key.to_int(), 0);
    _ = try a.remember(a_hero, a_at, 3, 0);
    const b_at = try b.intern_relation("At", .property);
    const b_has = try b.intern_relation("Has", .set);
    const b_hero = try b.intern_entity("Hero");
    const b_key = try b.intern_entity("Key");
    _ = try b.remember(b_hero, b_at, 3, 0);
    _ = try b.remember(b_hero, b_has, b_key.to_int(), 0);
    // Objects are raw ids, so give both worlds the same id for Key before comparing.
    try testing.expectEqual(a_key.to_int(), b_key.to_int());
    try testing.expectEqual(try fact_digest(testing.allocator, &a), try fact_digest(testing.allocator, &b));

    // A changed value, an extra fact, or a different expiry each change the digest.
    const before = try fact_digest(testing.allocator, &a);
    _ = try a.remember(a_hero, a_at, 4, 0);
    try testing.expect(before != try fact_digest(testing.allocator, &a));
    const after_move = try fact_digest(testing.allocator, &a);
    _ = try a.remember(a_key, a_at, 1, 5);
    try testing.expect(after_move != try fact_digest(testing.allocator, &a));
}

test "D-052: start_script leaves path initializers and path routines to the host" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene: Yard
        \\cast: Hero
        \\marks: Start, LeftGate, RightGate
        \\
        \\relation WaypointBlocked(mark)
        \\
        \\path Left:
        \\  remember WaypointBlocked(RightGate)
        \\  routine CrossLeft(Hero):
        \\    remember Crossed(Hero, LeftGate)
        \\
        \\path Right:
        \\  remember WaypointBlocked(LeftGate)
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    _ = try start_script(&world, &spatial, &vm, &compiled);
    for (0..3) |_| _ = try tick(&vm, &compiled);
    const blocked = world.lookup_relation("WaypointBlocked").?;
    try testing.expect(!world.has_fact(null, blocked, null));

    _ = (try vm.select_path(&compiled, "Left")).?;
    _ = try tick(&vm, &compiled);
    try testing.expect(world.has_fact(world.lookup_entity("RightGate").?, blocked, null));
    try testing.expect(!world.has_fact(world.lookup_entity("LeftGate").?, blocked, null));
    // The path's routine was not started either: choosing the path does not run it.
    try testing.expect(world.lookup_relation("Crossed") == null or !world.has_fact(null, world.lookup_relation("Crossed").?, null));
}

test "P44-07: the during spelling runs a routine owned by its multi-word name" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\entity Hero
        \\relation Cheered(who)
        \\
        \\during Judge Marrow:
        \\  remember Cheered("Judge Marrow")
    );
    defer compiled.deinit();

    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    _ = try start_script(&world, &spatial, &vm, &compiled);

    // The name has spaces, which `routine Name(Actor)` cannot, and it names the routine and its
    // owner alike.
    try testing.expectEqualStrings("Judge Marrow", world.get_entity_name(vm.fibers.items[0].owner).?);

    _ = try tick(&vm, &compiled);
    const judge = world.lookup_entity("Judge Marrow").?;
    try testing.expect(world.has_fact(judge, world.lookup_relation("Cheered").?, null));
}

test "P44-07: a routine header owns a multi-word actor" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, null,
        \\relation Cheered(who)
        \\
        \\routine Cheer(Judge Marrow):
        \\  remember Cheered("Judge Marrow")
    );
    defer compiled.deinit();

    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    _ = try start_script(&world, &spatial, &vm, &compiled);

    try testing.expectEqualStrings("Judge Marrow", world.get_entity_name(vm.fibers.items[0].owner).?);

    _ = try tick(&vm, &compiled);
    const judge = world.lookup_entity("Judge Marrow").?;
    try testing.expect(world.has_fact(judge, world.lookup_relation("Cheered").?, null));
}

test "D-100: a doorway mark is added on stage, and a walk ending on it, or asked for on it, changes rooms" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene: Quay
        \\cast: Hero
        \\marks: Steps, Pier
        \\
        \\scene: Hold
        \\marks: Hatch, Bilge
    );
    defer compiled.deinit();
    const exits = [_]Exit{
        .{ .scene = "Quay", .mark = "Gangway", .to_scene = "Hold", .to_mark = "Hatch", .add_at = .{ .x = 30, .y = 0 } },
        .{ .scene = "Hold", .mark = "Hatch", .to_scene = "Quay", .to_mark = "Gangway" },
    };
    try add_exit_marks(&world, &spatial, &exits);
    // Adding twice adds nothing new.
    const count = spatial.graph.waypoints.items.len;
    try add_exit_marks(&world, &spatial, &exits);
    try testing.expectEqual(count, spatial.graph.waypoints.items.len);
    const quay = world.lookup_entity("Quay").?;
    const hold = world.lookup_entity("Hold").?;
    const gangway = spatial.graph.find_waypoint_in_room(quay, "Gangway").?;

    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    _ = try start_script(&world, &spatial, &vm, &compiled);
    const hero = world.lookup_entity("Hero").?;
    try vm.transition_to_scene(quay);

    var bridge = display_mod.DisplayBridge.init();
    var window = try display_mod.DisplayWindow.init_offscreen(std.testing.io, 320, 180);
    defer window.deinit();
    var session = try Session.init(testing.allocator, &world, &spatial, &vm, &compiled, &bridge, &window);
    defer session.deinit();
    session.exits = &exits;
    session.player = hero;

    // A walk that ends on the gangway takes the player into the hold, onto the hatch.
    try testing.expect(try session.walk_player(gangway));
    var ticks: usize = 0;
    while (vm.current_scene.? != hold and ticks < 40) : (ticks += 1) _ = try session.advance();
    try testing.expectEqual(hold, vm.current_scene.?);
    const hatch = spatial.graph.find_waypoint_in_room(hold, "Hatch").?;
    try testing.expectEqual(hatch, spatial.agents.get(hero).?.current_wp);
    // Placed on the hatch, the player stays: only a walk leaves.
    _ = try session.advance();
    try testing.expectEqual(hold, vm.current_scene.?);
    // A walk asked for while standing on the hatch leaves at once.
    try testing.expect(try session.walk_player(hatch));
    try testing.expectEqual(quay, vm.current_scene.?);
    try testing.expectEqual(gangway, spatial.agents.get(hero).?.current_wp);
}

test "P44-05: a decision fires its cue with the winning option, once per rising trigger" {
    const compiler = @import("compiler.zig");
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    // A cue body cannot read lowercase parameters (D-072), so a handler that needs the option
    // names it as an exact argument. The engine also records `Chose(Decision, Option)`.
    var compiled = try compiler.compile_source(testing.allocator, &world, &spatial,
        \\scene: Table
        \\cast: Maren
        \\marks: Seat
        \\relation Turn(who)
        \\relation SuitLed(suit)
        \\relation Ready(who)
        \\relation Chose(decision, option)
        \\decision LeadAtTable:
        \\  actor Maren
        \\  fires CardPlayed
        \\  requires Turn(Maren)
        \\  option SaltTwo:
        \\    picks 2 when SuitLed(Salt)
        \\  option ReedOne:
        \\    picks 1 when SuitLed(Salt)
        \\on cue CardPlayed(Maren, SaltTwo):
        \\  remember Ready(Maren)
    );
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    const table = world.lookup_entity("Table").?;
    try vm.transition_to_scene(table);
    const maren = world.lookup_entity("Maren").?;
    const decision = world.lookup_entity("LeadAtTable").?;
    const ready = try world.intern_relation("Ready", .set);
    const knows = try world.intern_relation("Knows", .set);
    const turn = try world.intern_relation("Turn", .set);
    const led = try world.intern_relation("SuitLed", .set);
    const salt = world.lookup_entity("Salt").?;
    const salt_two = world.lookup_entity("SaltTwo").?;
    try world.remember(maren, knows, salt_two.to_int(), 0);
    try world.remember(maren, knows, world.lookup_entity("ReedOne").?.to_int(), 0);
    try world.remember(salt, led, 0, 0);
    try world.remember(maren, turn, 0, 0);

    // The choice is recorded when the trigger rises; the handler answers on the next tick.
    _ = try tick(&vm, &compiled);
    try testing.expectEqual(salt_two, decision_mod.chosen(&world, decision).?);
    try testing.expect(!world.has_fact(maren, ready, 0));
    _ = try tick(&vm, &compiled);
    try testing.expect(world.has_fact(maren, ready, 0));

    // The trigger still holds, so the same decision point cannot fire again.
    _ = world.forget(maren, ready, null);
    _ = try tick(&vm, &compiled);
    try testing.expect(!world.has_fact(maren, ready, 0));

    // Falling and rising again re-arms it, and a second tick runs the new handler.
    _ = world.forget(maren, turn, null);
    _ = try tick(&vm, &compiled);
    try testing.expectEqual(@as(?world_mod.EntityId, null), decision_mod.chosen(&world, decision));
    try world.remember(maren, turn, 0, 0);
    _ = try tick(&vm, &compiled);
    try testing.expectEqual(salt_two, decision_mod.chosen(&world, decision).?);
    _ = try tick(&vm, &compiled);
    try testing.expect(world.has_fact(maren, ready, 0));
}
