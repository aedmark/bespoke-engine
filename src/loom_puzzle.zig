//! BeSpoke Engine: The Bell Tower, a musical draft vertical slice (P22-03, D-029, D-030).
//!
//! An original scenario built to exercise pitch-based spellcraft end to end. Wren, an
//! apprentice bell-keeper, learns drafts by observing the tower (a guttering lantern, coiling
//! ivy, a humming tuning fork), weaves them on the distaff, and must discover one draft that is
//! never taught: `Loose`, the reverse of `Bind`. The distaff starts with four notes (C to F) and
//! reaches all seven once Wren holds the tuning fork, which gates `Toll`. Tolling the bell weaves
//! `Kindle` on the beacon from inside the handler, which exercises host re-dispatch (D-029).
const std = @import("std");
const bespoke = @import("root.zig");
const draft = bespoke.draft;
const Note = draft.Note;
const Notes = draft.Notes;
const EntityId = bespoke.EntityId;

pub const BELL_TOWER_SCRIPT =
    \\scene: Bell Tower Base
    \\cast: Wren
    \\props: Lantern, Brazier, Ivy, Stairwell
    \\marks: Doorway, BrazierMark, IvyMark, StairFoot
    \\
    \\scene: Bell Tower Belfry
    \\cast: Wren
    \\props: IronChain, TuningFork, GreatBell, Beacon
    \\marks: StairTop, ChainMark, BellMark, BeaconMark
    \\
    \\relation Knows(knower, draft)
    \\relation Carries(holder, item)
    \\property DistaffReach(holder, notes)
    \\
    \\draft Kindle(C, D, E, C) reverse Douse
    \\draft Bind(F, E, D, F) reverse Loose
    \\draft Toll(G, A, B, G) reverse Hush
    \\
    \\remember DistaffReach(Wren, 4)
    \\
    \\on cue LooksAt(Wren, Lantern):
    \\  say Wren: "The lantern flame gutters and flares: C, D, E, C. It sounds like kindling catching."
    \\  remember Knows(Wren, Kindle)
    \\
    \\on cue LooksAt(Wren, Brazier):
    \\  if Brazier is lit:
    \\    say Wren: "The brazier burns steadily. Its light reaches up the stairwell."
    \\  if Brazier is not lit:
    \\    say Wren: "A cold iron brazier heaped with old coals."
    \\
    \\on cue LooksAt(Wren, Ivy):
    \\  say Wren: "The ivy creaks as it coils around the gate: F, E, D, F. A binding sound."
    \\  remember Knows(Wren, Bind)
    \\
    \\on cue LooksAt(Wren, Stairwell):
    \\  if Brazier is lit:
    \\    say Wren: "Firelight shows the worn steps up to the belfry."
    \\  if Brazier is not lit:
    \\    say Wren: "The stairwell is pitch black. I would break my neck."
    \\
    \\on cue Uses(Wren, Stairwell):
    \\  if Brazier is not lit:
    \\    say Wren: "It is too dark to climb."
    \\  if Brazier is lit:
    \\    say Wren: "I climb toward the bells by firelight."
    \\    transition to scene: Bell Tower Belfry
    \\
    \\on cue Weave(Wren, Kindle, Brazier):
    \\  if Brazier is lit:
    \\    say Wren: "The coals are already burning."
    \\  if Brazier is not lit:
    \\    Brazier is lit
    \\    say Wren: "The coals catch. Firelight climbs the stairwell."
    \\
    \\on cue Weave(Wren, Douse, Brazier):
    \\  if Brazier is not lit:
    \\    say Wren: "There is no fire here to douse."
    \\  if Brazier is lit:
    \\    Brazier is not lit
    \\    say Wren: "The flames shrink to nothing. The stairwell goes dark."
    \\
    \\on cue LooksAt(Wren, IronChain):
    \\  if IronChain is loosed:
    \\    say Wren: "The chain lies slack on the boards."
    \\  if IronChain is not loosed:
    \\    say Wren: "A heavy chain binds the bell's clapper, wound tight like the ivy below."
    \\
    \\on cue Weave(Wren, Bind, IronChain):
    \\  say Wren: "The links pull tighter around the clapper. That was the wrong way round."
    \\
    \\on cue Weave(Wren, Loose, IronChain):
    \\  if IronChain is loosed:
    \\    say Wren: "The chain already lies on the floor."
    \\  if IronChain is not loosed:
    \\    IronChain is loosed
    \\    say Wren: "The links slacken and slide away. Something glints where the chain lay."
    \\
    \\on cue LooksAt(Wren, TuningFork):
    \\  if IronChain is not loosed:
    \\    say Wren: "Something glints under the chain, out of reach."
    \\  if IronChain is loosed:
    \\    say Wren: "A bronze tuning fork, green with age."
    \\
    \\on cue PicksUp(Wren, TuningFork):
    \\  if IronChain is not loosed:
    \\    say Wren: "The chain is in the way."
    \\  if IronChain is loosed:
    \\    if not Carries(Wren, TuningFork):
    \\      remember Carries(Wren, TuningFork)
    \\      remember DistaffReach(Wren, 7)
    \\      remember Knows(Wren, Toll)
    \\      say Wren: "The fork hums G, A, B, G as I lift it. My distaff reaches the high notes now."
    \\
    \\on cue LooksAt(Wren, GreatBell):
    \\  if GreatBell is ringing:
    \\    say Wren: "The great bell rolls its voice across the valley."
    \\  if GreatBell is not ringing:
    \\    say Wren: "The great bell hangs silent. Nobody below has heard it in years."
    \\
    \\on cue Weave(Wren, Toll, GreatBell):
    \\  if IronChain is not loosed:
    \\    say Wren: "The bell strains against its chain and stays silent."
    \\  if IronChain is loosed:
    \\    GreatBell is ringing
    \\    say Wren: "The great bell swings and tolls across the valley."
    \\    weave Kindle on Beacon
    \\
    \\on cue Weave(Wren, Hush, GreatBell):
    \\  if GreatBell is not ringing:
    \\    say Wren: "The bell is already still."
    \\  if GreatBell is ringing:
    \\    GreatBell is not ringing
    \\    say Wren: "The bell's voice settles into silence."
    \\
    \\on cue LooksAt(Wren, Beacon):
    \\  if Beacon is lit:
    \\    say Wren: "The beacon blazes. Every village in the valley can see it."
    \\  if Beacon is not lit:
    \\    say Wren: "A beacon basket on the parapet, cold for years."
    \\
    \\on cue Weave(Wren, Kindle, Beacon):
    \\  if Beacon is not lit:
    \\    Beacon is lit
    \\    say Wren: "The bell's tone kindles the beacon. Its light reaches every village below."
    \\
    \\on cue Weave(Wren, Douse, Beacon):
    \\  if Beacon is lit:
    \\    Beacon is not lit
    \\    say Wren: "The beacon gutters out."
;

pub const BASE_SCENE = "Bell Tower Base";
pub const BELFRY_SCENE = "Bell Tower Belfry";

/// Entity and waypoint handles resolved once after compilation.
pub const Ids = struct {
    base: EntityId,
    belfry: EntityId,
    wren: EntityId,
    lantern: EntityId,
    brazier: EntityId,
    ivy: EntityId,
    stairwell: EntityId,
    chain: EntityId,
    fork: EntityId,
    bell: EntityId,
    beacon: EntityId,
    reach_rel: bespoke.RelationKind,
    doorway_wp: u16,
    brazier_wp: u16,
    ivy_wp: u16,
    stair_foot_wp: u16,
    stair_top_wp: u16,
    chain_wp: u16,
    bell_wp: u16,
    beacon_wp: u16,
};

fn place(spatial: *bespoke.SpatialSystem, wp_id: u16, x: i32, y: i32) void {
    if (spatial.graph.get_waypoint(wp_id)) |wp| spatial.graph.waypoints.items[wp.id - 1].pos = .{ .x = x, .y = y };
}

/// Lays out both scenes after compilation: waypoint positions, corridors, hotspots, and Wren.
/// Shared by the headless and interactive runs so both exercise one topology.
pub fn configure(world: *bespoke.World, spatial: *bespoke.SpatialSystem) !Ids {
    const base = world.lookup_entity(BASE_SCENE).?;
    const belfry = world.lookup_entity(BELFRY_SCENE).?;
    const ids = Ids{
        .base = base,
        .belfry = belfry,
        .wren = world.lookup_entity("Wren").?,
        .lantern = world.lookup_entity("Lantern").?,
        .brazier = world.lookup_entity("Brazier").?,
        .ivy = world.lookup_entity("Ivy").?,
        .stairwell = world.lookup_entity("Stairwell").?,
        .chain = world.lookup_entity("IronChain").?,
        .fork = world.lookup_entity("TuningFork").?,
        .bell = world.lookup_entity("GreatBell").?,
        .beacon = world.lookup_entity("Beacon").?,
        .reach_rel = world.lookup_relation("DistaffReach").?,
        .doorway_wp = spatial.graph.find_waypoint_in_room(base, "Doorway").?,
        .brazier_wp = spatial.graph.find_waypoint_in_room(base, "BrazierMark").?,
        .ivy_wp = spatial.graph.find_waypoint_in_room(base, "IvyMark").?,
        .stair_foot_wp = spatial.graph.find_waypoint_in_room(base, "StairFoot").?,
        .stair_top_wp = spatial.graph.find_waypoint_in_room(belfry, "StairTop").?,
        .chain_wp = spatial.graph.find_waypoint_in_room(belfry, "ChainMark").?,
        .bell_wp = spatial.graph.find_waypoint_in_room(belfry, "BellMark").?,
        .beacon_wp = spatial.graph.find_waypoint_in_room(belfry, "BeaconMark").?,
    };

    place(spatial, ids.doorway_wp, 2, 6);
    place(spatial, ids.brazier_wp, 13, 6);
    place(spatial, ids.ivy_wp, 24, 6);
    place(spatial, ids.stair_foot_wp, 36, 4);
    place(spatial, ids.stair_top_wp, 2, 6);
    place(spatial, ids.chain_wp, 14, 6);
    place(spatial, ids.bell_wp, 21, 4);
    place(spatial, ids.beacon_wp, 36, 4);

    spatial.graph.edges.clearRetainingCapacity();
    try spatial.graph.connect(ids.doorway_wp, ids.brazier_wp, null);
    try spatial.graph.connect(ids.brazier_wp, ids.ivy_wp, null);
    try spatial.graph.connect(ids.ivy_wp, ids.stair_foot_wp, null);
    try spatial.graph.connect(ids.stair_top_wp, ids.chain_wp, null);
    try spatial.graph.connect(ids.chain_wp, ids.bell_wp, null);
    try spatial.graph.connect(ids.bell_wp, ids.beacon_wp, null);

    try spatial.add_hotspot(ids.lantern, base, .{ .x = 4, .y = -6 }, 6, "Lantern", "An iron lantern hanging by the door, its flame guttering in the draught.");
    try spatial.add_hotspot(ids.brazier, base, .{ .x = 13, .y = -1 }, 7, "Brazier", "An iron brazier heaped with coals.");
    try spatial.add_hotspot(ids.ivy, base, .{ .x = 24, .y = -8 }, 7, "Ivy", "Ivy coiled around the old iron gate.");
    try spatial.add_hotspot(ids.stairwell, base, .{ .x = 36, .y = -6 }, 7, "Stairwell", "A spiral stair up to the belfry.");
    try spatial.add_hotspot(ids.chain, belfry, .{ .x = 16, .y = -2 }, 6, "Iron Chain", "A heavy chain wound around the bell's clapper.");
    try spatial.add_hotspot(ids.fork, belfry, .{ .x = 10, .y = 3 }, 5, "Tuning Fork", "A glint of bronze on the boards.");
    try spatial.add_hotspot(ids.bell, belfry, .{ .x = 21, .y = -10 }, 9, "Great Bell", "The great bronze bell of the tower.");
    try spatial.add_hotspot(ids.beacon, belfry, .{ .x = 36, .y = -8 }, 7, "Beacon", "A beacon basket on the parapet.");

    try spatial.register_entity(ids.wren, ids.doorway_wp, 10);
    return ids;
}

/// Runs the script's top-level statements (the starting distaff reach) to completion.
fn run_initial_statements(world: *bespoke.World, vm: *bespoke.VM, compiled: *const bespoke.CompiledProgram) !void {
    const init_pc = compiled.initial_entry orelse return;
    const root_ent = try world.intern_entity("SimulationRoot");
    const fid = try vm.spawn_routine(root_ent, init_pc);
    var guard: usize = 0;
    while (vm.fibers.items[fid - 1].state != .halted and guard < 16) : (guard += 1) {
        try vm.step_tick();
    }
}

/// Copies the script's `DistaffReach(Wren, n)` fact into the host-side phrase buffer (D-030).
pub fn sync_reach(world: *const bespoke.World, ids: Ids, input: *draft.DistaffInput) void {
    const reach = world.get_property(ids.wren, ids.reach_rel) orelse 4;
    input.set_reach(@intCast(@min(reach, 7)));
}

pub fn knows(world: *const bespoke.World, ids: Ids, draft_name: []const u8) bool {
    const rel = world.lookup_relation("Knows") orelse return false;
    const d = world.lookup_entity(draft_name) orelse return false;
    return world.has_fact(ids.wren, rel, d.to_int());
}

pub fn has_state(world: *const bespoke.World, subject: EntityId, state: []const u8) bool {
    const rel = world.lookup_relation(state) orelse return false;
    return world.has_fact(subject, rel, null);
}

pub fn is_solved(world: *const bespoke.World, ids: Ids) bool {
    return has_state(world, ids.bell, "ringing") and has_state(world, ids.beacon, "lit");
}

/// Collects the `say` lines (cue id 2, D-009) a tick produced into one banner-sized string.
/// `VM.step_tick` clears `emitted_cues` at the start of every tick, so speech must be read
/// after each tick; an index taken before the tick is meaningless afterwards.
const SayLog = struct {
    stream: std.io.FixedBufferStream([]u8),
    count: usize = 0,

    fn init(buf: []u8) SayLog {
        return .{ .stream = std.io.fixedBufferStream(buf) };
    }

    fn collect(self: *SayLog, world: *const bespoke.World, vm: *const bespoke.VM) void {
        for (vm.emitted_cues.items) |cue| {
            if (cue.cue_id != 2 or cue.arg_count < 2) continue;
            const speaker = world.get_entity_name(EntityId.from_int(cue.args[0])) orelse "Someone";
            const text = world.get_entity_name(EntityId.from_int(cue.args[1])) orelse "";
            const w = self.stream.writer();
            if (self.count > 0) w.writeAll("  ") catch return;
            if (self.count == 0) w.print("{s}: ", .{speaker}) catch return;
            w.print("\"{s}\"", .{text}) catch return;
            self.count += 1;
        }
    }

    fn message(self: *SayLog) ?[]const u8 {
        return if (self.count > 0) self.stream.getWritten() else null;
    }
};

/// One host tick: step the VM, then re-dispatch in-script weaves, as D-029 requires.
/// Returns how many in-script weaves were re-dispatched.
pub fn tick(vm: *bespoke.VM, compiled: *const bespoke.CompiledProgram) !usize {
    try vm.step_tick();
    return try vm.dispatch_pending_weaves(compiled);
}

/// Fires a verb cue and runs it to completion. Returns the spoken reply, if any.
pub fn act(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    verb: []const u8,
    actor: EntityId,
    target: EntityId,
    buf: []u8,
) !?[]const u8 {
    var log = SayLog.init(buf);
    _ = try vm.fire_cue(compiled, verb, actor, target, null);
    _ = try tick(vm, compiled);
    log.collect(world, vm);
    return log.message();
}

pub const PhraseResult = struct {
    outcome: draft.WeaveOutcome,
    message: ?[]const u8,
    /// In-script weaves the host re-dispatched while this phrase resolved (D-029).
    redispatched: usize = 0,
};

/// Plays a phrase note by note through `DistaffInput`, exactly as the keyboard does, then weaves
/// it on `target`. Runs two ticks so a weave queued by the handler (the bell lighting the beacon)
/// is dispatched and its own handler runs before returning.
pub fn play_phrase(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    ids: Ids,
    input: *draft.DistaffInput,
    notes: []const Note,
    target: EntityId,
    buf: []u8,
) !PhraseResult {
    var phrase: ?Notes = null;
    for (notes) |n| {
        if (!input.can_play(n)) {
            input.clear();
            input.outcome = .fizzled;
            return .{ .outcome = .fizzled, .message = "That note is beyond the distaff's reach." };
        }
        phrase = input.press(n);
    }
    const full = phrase orelse return .{ .outcome = .none, .message = null };
    return weave_phrase(world, vm, compiled, ids, input, full, target, buf);
}

pub fn weave_phrase(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: *const bespoke.CompiledProgram,
    ids: Ids,
    input: *draft.DistaffInput,
    phrase: Notes,
    target: EntityId,
    buf: []u8,
) !PhraseResult {
    var log = SayLog.init(buf);
    const fiber = try vm.weave_notes(compiled, ids.wren, phrase, target);
    input.outcome = if (fiber != null) .woven else .fizzled;
    var redispatched = try tick(vm, compiled); // handler runs; in-script weaves dispatch after it
    log.collect(world, vm);
    redispatched += try tick(vm, compiled); // re-dispatched handlers run
    log.collect(world, vm);
    sync_reach(world, ids, input);
    const msg = log.message() orelse
        (if (fiber == null) @as(?[]const u8, "The draft unravels.") else null);
    return .{ .outcome = input.outcome, .message = msg, .redispatched = redispatched };
}

fn expect_true(cond: bool, err: anyerror) !void {
    if (!cond) return err;
}

/// Executes the full scenario headless: observation, inversion, reach gating, in-script weave,
/// fizzles, and rewind (P22-03).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("          BeSpoke Engine: The Bell Tower (Musical Drafts)          \n", .{});
    try writer.print("    (Observation * Reversed Drafts * Distaff Reach * Re-Dispatch)  \n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Compiling Bell Tower script with drafts Kindle, Bind, Toll...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, BELL_TOWER_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.base);
    try run_initial_statements(&world, &vm, &compiled);

    var input = draft.DistaffInput{};
    sync_reach(&world, ids, &input);
    var buf: [256]u8 = undefined;

    var snapshot_0 = std.ArrayList(u8).init(allocator);
    defer snapshot_0.deinit();
    try world.save_state(snapshot_0.writer());

    try writer.print("\n[Step 1] Observation: Wren watches the lantern.\n", .{});
    if (try act(&world, &vm, &compiled, "LooksAt", ids.wren, ids.lantern, &buf)) |m| try writer.print("  -> {s}\n", .{m});
    try expect_true(knows(&world, ids, "Kindle"), error.KindleNotLearned);
    try writer.print("  -> Distaff reach: {d} notes (C to F)\n", .{input.reach});
    try expect_true(input.reach == 4, error.WrongStartingReach);

    try writer.print("\n[Step 2] The stairwell is dark.\n", .{});
    if (try act(&world, &vm, &compiled, "Uses", ids.wren, ids.stairwell, &buf)) |m| try writer.print("  -> {s}\n", .{m});
    try expect_true(vm.current_scene.? == ids.base, error.ClimbedInTheDark);

    try writer.print("\n[Step 3] A misplayed phrase fizzles (C, C, D, D).\n", .{});
    var r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .C, .C, .D, .D }, ids.brazier, &buf);
    try writer.print("  -> {s} ({s})\n", .{ r.message orelse "", @tagName(r.outcome) });
    try expect_true(r.outcome == .fizzled, error.ExpectedFizzle);

    try writer.print("\n[Step 4] Weave Kindle (C, D, E, C) on the brazier.\n", .{});
    r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .C, .D, .E, .C }, ids.brazier, &buf);
    try writer.print("  -> {s}\n", .{r.message orelse ""});
    try expect_true(has_state(&world, ids.brazier, "lit"), error.BrazierNotLit);

    try writer.print("\n[Step 5] Reversed: Douse (C, E, D, C) puts it out; Kindle relights it.\n", .{});
    r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .C, .E, .D, .C }, ids.brazier, &buf);
    try writer.print("  -> {s}\n", .{r.message orelse ""});
    try expect_true(!has_state(&world, ids.brazier, "lit"), error.DouseFailed);
    r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .C, .D, .E, .C }, ids.brazier, &buf);
    try writer.print("  -> {s}\n", .{r.message orelse ""});
    try expect_true(has_state(&world, ids.brazier, "lit"), error.BrazierNotLit);

    try writer.print("\n[Step 6] Observation: the ivy teaches Bind (F, E, D, F).\n", .{});
    if (try act(&world, &vm, &compiled, "LooksAt", ids.wren, ids.ivy, &buf)) |m| try writer.print("  -> {s}\n", .{m});
    try expect_true(knows(&world, ids, "Bind"), error.BindNotLearned);

    try writer.print("\n[Step 7] Climb to the belfry by firelight.\n", .{});
    if (try act(&world, &vm, &compiled, "Uses", ids.wren, ids.stairwell, &buf)) |m| try writer.print("  -> {s}\n", .{m});
    try expect_true(vm.current_scene.? == ids.belfry, error.ClimbFailed);
    _ = try spatial.transition_actor(ids.wren, ids.belfry, ids.stair_top_wp);

    try writer.print("\n[Step 8] Toll is out of reach: the B note is refused at reach 4.\n", .{});
    r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .G, .A, .B, .G }, ids.bell, &buf);
    try writer.print("  -> {s}\n", .{r.message orelse ""});
    try expect_true(r.outcome == .fizzled and !has_state(&world, ids.bell, "ringing"), error.ReachNotEnforced);

    try writer.print("\n[Step 9] Bind on the chain only tightens it.\n", .{});
    r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .F, .E, .D, .F }, ids.chain, &buf);
    try writer.print("  -> {s}\n", .{r.message orelse ""});
    try expect_true(!has_state(&world, ids.chain, "loosed"), error.BindLoosedChain);

    try writer.print("\n[Step 10] Inversion: Bind played backwards is Loose (F, D, E, F).\n", .{});
    try expect_true(!knows(&world, ids, "Loose"), error.LooseWasTaught);
    r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .F, .D, .E, .F }, ids.chain, &buf);
    try writer.print("  -> {s}\n", .{r.message orelse ""});
    try expect_true(has_state(&world, ids.chain, "loosed"), error.ChainNotLoosed);

    try writer.print("\n[Step 11] Take the tuning fork: the distaff reaches all seven notes.\n", .{});
    if (try act(&world, &vm, &compiled, "PicksUp", ids.wren, ids.fork, &buf)) |m| try writer.print("  -> {s}\n", .{m});
    sync_reach(&world, ids, &input);
    try writer.print("  -> Distaff reach: {d} notes\n", .{input.reach});
    try expect_true(input.reach == 7 and knows(&world, ids, "Toll"), error.ForkDidNotExtendReach);

    try writer.print("\n[Step 12] Weave Toll (G, A, B, G) on the great bell.\n", .{});
    r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .G, .A, .B, .G }, ids.bell, &buf);
    try writer.print("  -> {s}\n", .{r.message orelse ""});
    try writer.print("  -> In-script weaves re-dispatched by the host: {d} (`weave Kindle on Beacon`)\n", .{r.redispatched});
    try expect_true(r.redispatched == 1 and vm.pending_weaves.items.len == 0, error.WeaveNotRedispatched);
    try expect_true(is_solved(&world, ids), error.BellTowerNotSolved);

    try writer.print("\n[Step 13] Time-travel rewind to tick 0.\n", .{});
    var stream = std.io.fixedBufferStream(snapshot_0.items);
    try world.restore_state(stream.reader());
    vm.current_scene = ids.base;
    _ = try spatial.transition_actor(ids.wren, ids.base, ids.doorway_wp);
    sync_reach(&world, ids, &input);
    try writer.print("  -> Bell ringing: {any}, brazier lit: {any}, reach: {d} (expected false, false, 4)\n", .{
        has_state(&world, ids.bell, "ringing"),
        has_state(&world, ids.brazier, "lit"),
        input.reach,
    });
    try expect_true(!is_solved(&world, ids) and !has_state(&world, ids.brazier, "lit") and input.reach == 4, error.RewindFailed);

    try writer.print("\n===================================================================\n", .{});
    try writer.print("  VERIFICATION COMPLETE: The Bell Tower rings. 100% deterministic.  \n", .{});
    try writer.print("===================================================================\n\n", .{});
}

/// Waypoint Wren walks to when interacting with a hotspot, so actions read as diegetic.
fn approach_wp(ids: Ids, entity: EntityId) ?u16 {
    if (entity == ids.lantern) return ids.doorway_wp;
    if (entity == ids.brazier) return ids.brazier_wp;
    if (entity == ids.ivy) return ids.ivy_wp;
    if (entity == ids.stairwell) return ids.stair_foot_wp;
    if (entity == ids.chain or entity == ids.fork) return ids.chain_wp;
    if (entity == ids.bell) return ids.bell_wp;
    if (entity == ids.beacon) return ids.beacon_wp;
    return null;
}

/// Moves Wren's body when a cue handler changed scene (the stairwell climb).
fn follow_scene(vm: *const bespoke.VM, spatial: *bespoke.SpatialSystem, ids: Ids, before: ?EntityId) !void {
    const now = vm.current_scene orelse return;
    if (before != null and before.? == now) return;
    if (now == ids.belfry) {
        _ = try spatial.transition_actor(ids.wren, ids.belfry, ids.stair_top_wp);
    } else if (now == ids.base) {
        _ = try spatial.transition_actor(ids.wren, ids.base, ids.stair_foot_wp);
    }
}

/// Executes the interactive Bell Tower with the distaff HUD (P22-03, D-030).
pub fn run_interactive(allocator: std.mem.Allocator, stdout: anytype) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, BELL_TOWER_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.base);
    try run_initial_statements(&world, &vm, &compiled);

    var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Bell Tower", 1280, 720);
    defer window.deinit();
    if (window.is_headless) {
        try stdout.print("Warning: Graphical display unavailable (headless fallback). Running console simulation.\n", .{});
        try run_headless(allocator, stdout);
        return;
    }

    try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
    try stdout.print("The Bell Tower Controls:\n", .{});
    try stdout.print("   - [Click]:               Act on a hotspot with the active verb; it becomes the weave target\n", .{});
    try stdout.print("   - [C D E F G A B]:       Play distaff notes (four notes weave a draft)\n", .{});
    try stdout.print("   - [Backspace]:           Clear the phrase in progress\n", .{});
    try stdout.print("   - [Right-Click]:         Cycle verb (WALK, LOOK, TALK, TAKE, USE)\n", .{});
    try stdout.print("   - [Space] / [N]:         Pause / single-step the clock\n", .{});
    try stdout.print("   - [R] / [< >]:           Rewind / scrub the timeline\n", .{});
    try stdout.print("   - [F1] / [`]:            Debug overlay / REPL console\n", .{});
    try stdout.print("   - [Esc]:                 Exit\n\n", .{});

    var input = draft.DistaffInput{};
    sync_reach(&world, ids, &input);

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.attach_audio_bridge(window.audio_bridge);
    display_bridge.attach_distaff(&input);
    display_bridge.set_active_character(ids.wren); // inventory tray shows Wren's Carries facts
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.set_max_history_tick(0);
    display_bridge.swap();

    var history = std.ArrayList(std.ArrayList(u8)).init(allocator);
    defer {
        for (history.items) |*h| h.deinit();
        history.deinit();
    }
    var snap0 = std.ArrayList(u8).init(allocator);
    try world.save_state(snap0.writer());
    try history.append(snap0);

    var is_paused = false;
    var last_tick_time = std.time.milliTimestamp();
    var announced_solved = false;
    var buf: [256]u8 = undefined;

    window.set_cue_banner("The bell has been silent for years. Watch the tower, then weave on the distaff.", 200);

    while (true) {
        const action = window.poll_events(display_bridge.get_frame());
        var should_step_now = false;
        const scene_before = vm.current_scene;

        _ = window.handle_save_action(action, &world, &spatial, &vm, &display_bridge, &is_paused);
        switch (action) {
            .quit => break,
            .toggle_pause => is_paused = !is_paused,
            .step_tick => should_step_now = true,
            .walk_player => |wp_id| {
                _ = try spatial.walk_to(ids.wren, wp_id);
                if (vm.current_scene == ids.belfry and wp_id == ids.stair_top_wp) {
                    try vm.transition_to_scene(ids.base);
                    window.set_cue_banner("Wren climbs back down to the tower base.", 90);
                }
            },
            .examine_hotspot, .interact_hotspot => {
                const frame = display_bridge.get_frame();
                const idx: usize, const verb: bespoke.display.renderer.AdventureVerb = switch (action) {
                    .examine_hotspot => |i| .{ i, .look_at },
                    .interact_hotspot => |h| .{ h.hotspot_index, h.verb },
                    else => unreachable,
                };
                if (idx < frame.hotspot_count) {
                    const target = frame.hotspots[idx].entity;
                    input.target = target;
                    if (approach_wp(ids, target)) |wp| _ = try spatial.walk_to(ids.wren, wp);
                    const cue_name: ?[]const u8 = switch (verb) {
                        .look_at => "LooksAt",
                        .use_with => "Uses",
                        .pick_up => "PicksUp",
                        else => null,
                    };
                    if (cue_name) |cn| {
                        if (try act(&world, &vm, &compiled, cn, ids.wren, target, &buf)) |msg| {
                            window.set_cue_banner(msg, 200);
                        } else {
                            window.set_cue_banner("Nothing happens.", 60);
                        }
                        sync_reach(&world, ids, &input);
                    } else {
                        window.set_cue_banner("Wren turns toward it. Play a draft to weave on it.", 90);
                    }
                }
            },
            .interact_actor => {
                window.set_cue_banner("Wren: \"Apprentice bell-keeper. The distaff was my teacher's.\"", 120);
            },
            .play_note => |deg| {
                const note = Note.from_int(deg) orelse continue;
                if (input.press(note)) |phrase| {
                    if (input.target == .none) {
                        input.outcome = .fizzled;
                        window.play_sfx(.weave_fizzle);
                        window.set_cue_banner("Choose something to weave on first: click it.", 120);
                    } else {
                        const r = try weave_phrase(&world, &vm, &compiled, ids, &input, phrase, input.target, &buf);
                        window.play_sfx(if (r.outcome == .woven) .weave_success else .weave_fizzle);
                        window.set_cue_banner(r.message orelse "The threads hold.", 200);
                        var snap = std.ArrayList(u8).init(allocator);
                        try world.save_state(snap.writer());
                        try history.append(snap);
                        display_bridge.set_max_history_tick(world.current_tick);
                    }
                }
            },
            .clear_distaff => input.clear(),
            .scrub_to_tick => |target_tick| {
                if (target_tick < history.items.len) {
                    var stream = std.io.fixedBufferStream(history.items[target_tick].items);
                    world.restore_state(stream.reader()) catch {};
                    while (history.items.len > target_tick + 1) {
                        var popped = history.pop();
                        popped.deinit();
                    }
                    input.clear();
                    sync_reach(&world, ids, &input);
                    display_bridge.set_max_history_tick(target_tick);
                    window.set_cue_banner("Time-travel rewound.", 90);
                }
            },
            .rewind => {
                if (history.items.len > 1) {
                    var last = history.pop();
                    last.deinit();
                    var stream = std.io.fixedBufferStream(history.items[history.items.len - 1].items);
                    world.restore_state(stream.reader()) catch {};
                    input.clear();
                    sync_reach(&world, ids, &input);
                    display_bridge.set_max_history_tick(history.items.len - 1);
                    window.set_cue_banner("Stepped back one snapshot.", 60);
                }
            },
            else => {},
        }

        try follow_scene(&vm, &spatial, ids, scene_before);

        if (!announced_solved and is_solved(&world, ids)) {
            announced_solved = true;
            window.set_cue_banner("The bell tolls and the beacon burns. The valley wakes.", 300);
        }

        if (action != .none and action != .toggle_pause and action != .step_tick and action != .quit) {
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        const now_ms = std.time.milliTimestamp();
        if ((!is_paused and now_ms - last_tick_time >= window.current_tick_interval_ms) or should_step_now) {
            last_tick_time = now_ms;
            _ = try tick(&vm, &compiled);
            try follow_scene(&vm, &spatial, ids, scene_before);
            sync_reach(&world, ids, &input);

            var snap = std.ArrayList(u8).init(allocator);
            try world.save_state(snap.writer());
            try history.append(snap);
            display_bridge.set_max_history_tick(world.current_tick);
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        window.render_frame(display_bridge.get_frame(), is_paused);
        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P22-03: headless Bell Tower run solves the scenario and rewinds" {
    try run_headless(std.testing.allocator, std.io.null_writer);
}

test "P22-03: drafts weave only where the script allows" {
    const allocator = std.testing.allocator;
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, BELL_TOWER_SCRIPT);
    defer compiled.deinit();
    const ids = try configure(&world, &spatial);
    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.transition_to_scene(ids.base);
    try run_initial_statements(&world, &vm, &compiled);

    var input = draft.DistaffInput{};
    sync_reach(&world, ids, &input);
    var buf: [256]u8 = undefined;

    // Kindle on a target with no Weave handler fizzles and changes nothing.
    var r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .C, .D, .E, .C }, ids.ivy, &buf);
    try std.testing.expectEqual(draft.WeaveOutcome.fizzled, r.outcome);
    try std.testing.expect(!has_state(&world, ids.ivy, "lit"));

    // Toll would ring the bell, but the chain still holds it even with full reach.
    input.set_reach(7);
    r = try play_phrase(&world, &vm, &compiled, ids, &input, &.{ .G, .A, .B, .G }, ids.bell, &buf);
    try std.testing.expectEqual(draft.WeaveOutcome.woven, r.outcome);
    try std.testing.expect(!has_state(&world, ids.bell, "ringing"));
    try std.testing.expect(!has_state(&world, ids.beacon, "lit"));

    // The fork cannot be taken while the chain lies on it.
    _ = try act(&world, &vm, &compiled, "PicksUp", ids.wren, ids.fork, &buf);
    sync_reach(&world, ids, &input);
    try std.testing.expectEqual(@as(u8, 4), input.reach);
}
