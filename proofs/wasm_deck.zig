//! The proofs' decks for the browser runtime (P30-05, D-069). Each deck runs its proof's own
//! script through `wasm.script_deck_with`, so the showcase plays the script its viewer shows.
//! What stays here is the host work the desktop proofs do in Zig: who the player is, opening
//! placements, the Living Village's society, and the `[S]` solve key, which plays the desktop
//! proof's solution one beat per press. `proofs/wasm_main.zig` exports these as
//! `bespoke-proofs.wasm`; `proofs/wasm_golden_test.zig` drives them natively.
const std = @import("std");
const bespoke = @import("bespoke");
const society = bespoke.society;
const wasm = bespoke.wasm;
const WasmRuntime = wasm.WasmRuntime;
const EntityId = bespoke.EntityId;

const TAVERN_SCRIPT = @embedFile("tavern_script");
const SPITTING_CONTEST_SCRIPT = @import("spitting_contest.zig").SPITTING_CONTEST_SCRIPT;
const borrowed_beard = @import("borrowed_beard.zig");
const BORROWED_BEARD_SCRIPT = borrowed_beard.BORROWED_BEARD_SCRIPT;
const village = @import("village.zig");
const VILLAGE_SCRIPT = village.VILLAGE_SCRIPT;
const lamp_point = @import("lamp_point.zig");
const LAMP_POINT_SCRIPT = lamp_point.LAMP_POINT_SCRIPT;
const three_tides = @import("three_tides.zig");
const THREE_TIDES_SCRIPT = three_tides.THREE_TIDES_SCRIPT;
const GROG_PUZZLE_SCRIPT = @import("grog_puzzle.zig").GROG_PUZZLE_SCRIPT;
const sword_fighting = @import("sword_fighting.zig");
const SWORD_FIGHTING_SCRIPT = sword_fighting.SWORD_FIGHTING_SCRIPT;
const saltmarket = @import("saltmarket.zig");
const bell_tower = @import("bell_tower.zig");
const art = @import("art.zig");
const weathercock = @import("weathercock.zig");
const grid_puzzle = @import("grid_puzzle.zig");
const observatory = @import("observatory_puzzle.zig");
const valerius = @import("valerius.zig");
const lamplighter = @import("lamplighter.zig");
const long_gallery = @import("long_gallery.zig");
const word_foundry = @import("word_foundry.zig");
const cinder_table = @import("cinder_table.zig");
const tide_beacon = @import("tide_beacon.zig");
const duel_mod = bespoke.duel;

pub const decks = [_]wasm.Deck{
    wasm.script_deck_with("TAVERN HEIST (GUARD, BARD & CAT)", TAVERN_SCRIPT, .{
        .player = "Cat",
        .intro = "Tavern Heist: you are the Cat. Click a mark to walk; [S] plays the solution.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 28, .g = 21, .b = 18 },
        .catalyst = solver(&TAVERN_SOLUTION),
    }),
    wasm.script_deck_with("THE PIP-SPITTING GREEN", SPITTING_CONTEST_SCRIPT, .{
        .player = "Tamsin",
        .intro = "Pip-Spitting Green: TALK, LOOK, or USE on people and props; [S] plays the solution.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 16, .g = 42, .b = 58 },
        .catalyst = solver(&SPIT_SOLUTION),
        .on_act = spit_act,
        .on_choice = spit_choice,
        .on_action = spit_action,
    }),
    wasm.script_deck_with("THE BORROWED BEARD", BORROWED_BEARD_SCRIPT, .{
        .player = "Tamsin",
        .intro = "The Borrowed Beard: Tamsin needs a disguise. Use the verbs, or [S] for the next step.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 32, .g = 52, .b = 34 },
        .setup = beard_setup,
        .catalyst = solver(&BEARD_SOLUTION),
        .exits = &borrowed_beard.EXITS,
    }),
    wasm.script_deck_with("THE LIVING VILLAGE (EMERGENCE)", VILLAGE_SCRIPT, .{
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 22, .g = 44, .b = 28 },
        .setup = village_setup,
        .catalyst = village_desperation,
        .after_tick = village_after_tick,
    }),
    wasm.script_deck_with("THE DONKEY OF LAMP POINT", LAMP_POINT_SCRIPT, .{
        .player = "Tamsin",
        .intro = "Lamp Point: get past Cudgel the donkey to the wreckers' cellar. [S] plays the next step.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 38, .g = 48, .b = 40 },
        .setup = lamp_point_setup,
        .after_tick = lamp_point_after_tick,
        .on_act = lamp_point_on_act,
        .catalyst = solver(&LAMP_POINT_SOLUTION),
    }),
    wasm.script_deck_with("THE WELL OF THREE TIDES", THREE_TIDES_SCRIPT, .{
        .player = "Nell",
        .intro = "Three Tides: three centuries, one well. [S] plays the next step of the solution.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 42, .g = 24, .b = 48 },
        .setup = tides_setup,
        .after_tick = tides_after_tick,
        .on_action = tides_action,
        .catalyst = solver(&TIDES_SOLUTION),
    }),
    wasm.script_deck_with("CAUSTIC GROG (CONTAINER DEGRADATION)", GROG_PUZZLE_SCRIPT, .{
        .player = "Mara",
        .intro = "Caustic Grog: press [S] now to run for the lock before the cups fail.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 20, .g = 42, .b = 40 },
        .catalyst = solver(&GROG_SOLUTION),
    }),
    wasm.script_deck_with("BRACKWATER BARBS", SWORD_FIGHTING_SCRIPT, .{
        .player = "Tamsin",
        .intro = "Brackwater Barbs: TALK to a fencer, or press [S], to duel. Answer with the number keys.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 30, .g = 36, .b = 52 },
        .setup = sword_setup,
        .exits = &sword_fighting.EXITS,
        .catalyst = sword_solve,
        .on_choice = sword_choice,
        .on_act = sword_act,
    }),
    wasm.script_deck_with("THE SALTMARKET: THREE WAYS IN", saltmarket.SALTMARKET_SCRIPT, .{
        .player = "Tamsin",
        .soundtrack = &art.soundtrack,
        .theme = &saltmarket.theme,
        .background = .{ .r = 52, .g = 38, .b = 22 },
        .setup = saltmarket_setup,
        .catalyst = saltmarket_solve,
        .on_choice = saltmarket_choice,
        .on_act = saltmarket_act,
        .cues = .{ .talk = "Talk" },
    }),
    wasm.script_deck_with("THE COPPER WEATHERCOCK (BRANCH WORLDS)", weathercock.WEATHERCOCK_SCRIPT, .{
        .player = "Wren",
        .intro = "Brackwater: a borrowed month folds away in 280 ticks. [S] plays the next step; I inspects the branch.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 26, .g = 18, .b = 40 },
        .setup = weathercock_setup,
        .exits = &weathercock.EXITS,
        .catalyst = solver(&WEATHERCOCK_SOLUTION),
        .after_tick = weathercock_after_tick,
    }),
    wasm.script_deck_with("THE BELL TOWER (MUSICAL DRAFTS)", bell_tower.BELL_TOWER_SCRIPT, .{
        .player = "Maren",
        .intro = "Bell Tower: act on something, then play four notes with C D E F G A B. [S] for the next step.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 24, .g = 28, .b = 46 },
        .setup = bell_tower_setup,
        .catalyst = solver(&BELL_TOWER_SOLUTION),
        .after_tick = bell_tower_follow_scene,
        .cues = .{ .take = "PicksUp" },
    }),
    wasm.script_deck_with("THE CASTLE FIRE ESCAPE (FIRE, SMOKE, WATER)", grid_puzzle.GRID_PUZZLE_SCRIPT, .{
        .player = "Wren",
        .intro = "Hollin Keep: fill the bucket at the trough, light the tapestry at the torch, and save the door. [S] plays the next step.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 20, .g = 16, .b = 14 },
        .setup = keep_setup,
        .catalyst = keep_solve,
        .after_tick = keep_after_tick,
        .on_act = keep_act,
        .on_action = keep_action,
    }),
    wasm.script_deck_with("THE LARKSPUR OBSERVATORY (AGENDAS, TYPED COMMANDS)", observatory.OBSERVATORY_SCRIPT, .{
        .player = "Ines",
        .intro = "Larkspur: press Enter and type, such as \"go to the archive\" or \"take the slip\". [S] types the next step.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 16, .g = 20, .b = 34 },
        .setup = larkspur_setup,
        .catalyst = larkspur_solve,
        .after_tick = larkspur_after_tick,
        .command_bar = true,
        .on_typed = larkspur_typed,
    }),
    wasm.script_deck_with("VALERIUS AND THE BREAD (VALUES, DILEMMAS, APPEALS)", valerius.VALERIUS_SCRIPT, .{
        .player = "Hesper",
        .intro = valerius.INTRO ++ " [S] types the next step.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 18, .g = 16, .b = 20 },
        .setup = greyhold_setup,
        .catalyst = greyhold_solve,
        .after_tick = greyhold_after_tick,
        .command_bar = true,
        .on_typed = greyhold_typed,
    }),
    // P46-05: drawn entirely from PNG art the build imported; the deck loads that package.
    wasm.script_deck_with("THE LAMPLIGHTER'S ROUND (PIXEL ART)", lamplighter.PACKAGE, .{
        .player = "Nell",
        .intro = lamplighter.INTRO ++ " [S] plays the next step.",
        .soundtrack = &art.soundtrack,
        .theme = &lamplighter.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 24, .g = 26, .b = 52 },
        .setup = lamplighter_setup,
        .catalyst = solver(&LAMPLIGHTER_SOLUTION),
        .exits = &lamplighter.EXITS,
    }),
    wasm.script_deck_with("THE LONG GALLERY (WATCH ANOTHER ROOM)", long_gallery.LONG_GALLERY_SCRIPT, .{
        .player = "Audra",
        .intro = "Long Gallery: Audra keeps watch while Corin hunts Pell next door. Press [V] to watch the locked studio, [S] for next step.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 22, .g = 24, .b = 32 },
        .setup = gallery_setup,
        .catalyst = gallery_solve,
        .on_act = gallery_act,
        .on_action = gallery_action,
    }),
    wasm.script_deck_with("THE WORD FOUNDRY (SPELLBOOK VOCABULARIES)", word_foundry.WORD_FOUNDRY_SCRIPT, .{
        .player = "Maren",
        .intro = "Word Foundry: Look at Bellows, ColdHearth, and PatternBook to learn words, then Use the Crucible or press [C] to combine three.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 26, .g = 20, .b = 18 },
        .setup = foundry_setup,
        .catalyst = foundry_solve,
        .after_tick = foundry_after_tick,
        .on_act = foundry_act,
        .on_choice = foundry_choice,
        .on_action = foundry_action,
        .command_bar = true,
        .on_typed = foundry_typed,
    }),
    wasm.script_deck_with("THE CINDER TABLE (PRIVATE HANDS & DECISIONS)", cinder_table.CINDER_TABLE_SCRIPT, .{
        .player = "Maren",
        .intro = "Cinder Table: three seats play four rounds from private hands. Watch each trick play, or press [S] to step.",
        .soundtrack = &art.soundtrack,
        .theme = &art.theme,
        .status_hook = art.capture_status,
        .background = .{ .r = 24, .g = 18, .b = 18 },
        .setup = cinder_setup,
        .catalyst = cinder_solve,
        .after_tick = cinder_after_tick,
        .on_act = cinder_act,
        .on_action = cinder_action,
    }),
    // P49-01 (D-190): four simultaneous palette colour cycles on one static PNG backdrop.
    wasm.script_deck_with("THE TIDE BEACON (COLOUR CYCLING)", tide_beacon.PACKAGE, .{
        .player = "CoveKeeper",
        .intro = tide_beacon.INTRO ++ " [S] plays the next step.",
        .theme = &tide_beacon.theme,
        .background = .{ .r = 11, .g = 14, .b = 30 },
        .setup = tide_beacon_setup,
        .catalyst = solver(&TIDE_BEACON_SOLUTION),
    }),
};

// =============================================================================
// Solve key: the desktop proofs' solutions, one beat per press
// =============================================================================

const Fact = struct {
    subject: []const u8,
    relation: []const u8,
    /// An entity name for the object, or null to use `value`.
    object: ?[]const u8 = null,
    value: u32 = 0,
    /// Lifetime in ticks; 0 is permanent.
    ttl: u64 = 0,
};

/// One host action. Cues are what a player does; the rest is host work the desktop proof does
/// in Zig (walks, scene changes, item transfers, pours) or facts its host sets directly.
const Action = union(enum) {
    cue: struct { name: []const u8, actor: []const u8, a: ?[]const u8 = null, b: ?[]const u8 = null },
    /// Runs ticks; an open dialogue is answered with its first option, as the proofs do.
    ticks: u8,
    /// Ticks until the actor stops walking (at most 40).
    settle: []const u8,
    /// Ticks until the subject no longer holds the relation (at most 80), as a player waits
    /// for someone to move off.
    until_gone: struct { subject: []const u8, relation: []const u8 },
    walk: struct { actor: []const u8, mark: []const u8 },
    scene: struct { scene: []const u8, actor: ?[]const u8 = null, mark: ?[]const u8 = null },
    remember: Fact,
    forget: Fact,
    transfer: struct { item: []const u8, from: []const u8, to: []const u8 },
    /// A container pour; the beat stops with a hint when nothing moves.
    pour: struct { from: []const u8, to: []const u8 },
    /// Moves an actor to a mark without changing the scene on stage.
    place: struct { actor: []const u8, scene: []const u8, mark: []const u8 },
    /// Plays a four-note phrase on the distaff at `target`, through the same path as the keys.
    weave: struct { notes: *const [4]u8, target: []const u8 },
    /// The beat counts only if this fact holds by now; otherwise the next `[S]` tries it again,
    /// as a player would after being refused (D-094).
    require: Fact,
};

const Beat = struct {
    note: []const u8,
    actions: []const Action,
};

/// Progress is a World fact, so rewinding the timeline rewinds the solve key with it.
const PROGRESS_SUBJECT = "SolveKey";
const PROGRESS_RELATION = "SolveBeat";

fn solver(comptime beats: []const Beat) *const fn (rt: *WasmRuntime) anyerror!void {
    return struct {
        fn run(rt: *WasmRuntime) anyerror!void {
            const key = try rt.world.intern_entity(PROGRESS_SUBJECT);
            const progress = try rt.world.intern_relation(PROGRESS_RELATION, .property);
            const done: usize = rt.world.get_property(key, progress) orelse 0;
            if (done >= beats.len) {
                rt.set_banner("Solved. Press [R] to rewind and play it yourself.");
                return;
            }
            const beat = beats[done];
            rt.set_banner(beat.note);
            for (beat.actions) |action| {
                if (!try perform(rt, action)) return;
            }
            try rt.world.remember(key, progress, @intCast(done + 1), 0);
        }
    }.run;
}

fn entity(rt: *WasmRuntime, name: []const u8) !EntityId {
    return rt.world.intern_entity(name);
}

fn relation(rt: *WasmRuntime, name: []const u8) !bespoke.RelationKind {
    return rt.world.lookup_relation(name) orelse rt.world.intern_relation(name, .set);
}

fn fact_object(rt: *WasmRuntime, fact: Fact) !u32 {
    return if (fact.object) |name| (try entity(rt, name)).to_int() else fact.value;
}

fn mark_in_room(rt: *WasmRuntime, actor: EntityId, name: []const u8) ?bespoke.WaypointId {
    if (rt.spatial.get_current_waypoint(actor)) |wp| {
        if (rt.spatial.graph.get_waypoint(wp)) |here| {
            if (rt.spatial.graph.find_waypoint_in_room(here.room, name)) |found| return found;
        }
    }
    return rt.spatial.graph.find_waypoint(name);
}

/// Returns false when the beat cannot go on; the banner then says why.
fn perform(rt: *WasmRuntime, action: Action) !bool {
    switch (action) {
        .cue => |c| {
            const program = if (rt.program) |*p| p else return false;
            const a = if (c.a) |n| try entity(rt, n) else null;
            const b = if (c.b) |n| try entity(rt, n) else null;
            _ = try rt.vm.fire_cue(program, c.name, try entity(rt, c.actor), a, b);
        },
        .ticks => |n| for (0..n) |_| {
            try rt.step_tick();
            if (bespoke.dialogue.view(&rt.world) != null) try rt.answer(0);
        },
        .require => |f| {
            const world = rt.active_world();
            const subject = world.lookup_entity(f.subject) orelse return false;
            const rel = world.lookup_relation(f.relation) orelse return false;
            const object: ?u32 = if (f.object) |n| (world.lookup_entity(n) orelse return false).to_int() else null;
            if (world.find_first(subject, rel, object) == null) return false;
        },
        .settle => |name| {
            const actor = try entity(rt, name);
            var guard: usize = 0;
            while (guard < 40) : (guard += 1) {
                try rt.step_tick();
                if (!rt.spatial.is_moving(actor)) break;
            }
        },
        .until_gone => |g| {
            const subject = try entity(rt, g.subject);
            const rel = try relation(rt, g.relation);
            var guard: usize = 0;
            while (guard < 80 and rt.active_world().has_fact(subject, rel, null)) : (guard += 1) try rt.step_tick();
        },
        .walk => |w| {
            const actor = try entity(rt, w.actor);
            const mark = mark_in_room(rt, actor, w.mark) orelse return false;
            _ = try rt.spatial.walk_to_with_world(&rt.world, actor, mark);
        },
        .scene => |s| {
            const scene = try entity(rt, s.scene);
            try rt.vm.transition_to_scene(scene);
            if (s.actor) |name| {
                const mark = if (s.mark) |m| rt.spatial.graph.find_waypoint_in_room(scene, m) else null;
                _ = try rt.spatial.transition_actor(try entity(rt, name), scene, mark);
            }
        },
        // Facts go to the active world: the branch while one is live, as the desktop
        // host writes to `Session.active_world` (D-049, D-071).
        .remember => |f| try rt.active_world().remember(try entity(rt, f.subject), try relation(rt, f.relation), try fact_object(rt, f), f.ttl),
        .forget => |f| _ = rt.active_world().forget(try entity(rt, f.subject), try relation(rt, f.relation), if (f.object != null or f.value != 0) try fact_object(rt, f) else null),
        .transfer => |t| _ = try rt.active_world().transfer_item(try entity(rt, t.item), try entity(rt, t.from), try entity(rt, t.to)),
        .place => |pl| {
            const scene = try entity(rt, pl.scene);
            _ = try rt.spatial.transition_actor(try entity(rt, pl.actor), scene, rt.spatial.graph.find_waypoint_in_room(scene, pl.mark));
        },
        .weave => |w| {
            rt.distaff.clear();
            rt.distaff.target = try entity(rt, w.target);
            for (w.notes) |n| _ = try rt.play_note(n);
        },
        .pour => |p| {
            const program = if (rt.program) |*prog| prog else return false;
            if (program.degradations.items.len == 0) return false;
            const system = try bespoke.container.ContainerSystem.init(&rt.world, program.degradations.items[0].config);
            const moved = system.pour(&rt.world, try entity(rt, p.from), try entity(rt, p.to)) catch 0;
            if (moved == 0) {
                rt.set_banner("The cup gave out before the pour. Press [R] to rewind, then [S] at once.");
                return false;
            }
        },
    }
    return true;
}

// The Tavern Heist's desktop host charms the Guard and moves the Cheese itself; the script's
// rules make the Guard turn to each.
const TAVERN_SOLUTION = [_]Beat{
    .{ .note = "The Bard's lute charms the Guard.", .actions = &.{
        .{ .remember = .{ .subject = "Guard", .relation = "CharmedBy", .object = "Bard", .ttl = 10 } },
        .{ .ticks = 2 },
    } },
    .{ .note = "While the Guard is charmed, the Cat takes the Cheese.", .actions = &.{
        .{ .forget = .{ .subject = "Guard", .relation = "Carries", .object = "Cheese" } },
        .{ .remember = .{ .subject = "Cat", .relation = "Carries", .object = "Cheese" } },
        .{ .ticks = 2 },
    } },
};

const SPIT_SOLUTION = [_]Beat{
    .{ .note = "Tamsin drinks the treacle cider.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "TreacleCider" } }, .{ .ticks = 2 } } },
    .{ .note = "Tamsin blows the conch.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "Conch" } }, .{ .ticks = 2 } } },
    .{ .note = "Tamsin moves the pegs while nobody watches.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "Pegs" } }, .{ .ticks = 2 } } },
    // A distracted judge marks nothing, so the throw waits until he is back at the chalk line.
    .{ .note = "Tamsin waits for Judge Marrow to turn back from the harbour.", .actions = &.{ .{ .until_gone = .{ .subject = "JudgeMarrow", .relation = "Distracted" } } } },
    .{ .note = "The wind picks up.", .actions = &.{ .{ .cue = .{ .name = "Gusts", .actor = "Tamsin" } }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin spits while the judge watches and the breeze blows.", .actions = &.{ .{ .cue = .{ .name = "Spits", .actor = "Tamsin" } }, .{ .ticks = 1 } } },
};

const BEARD_SOLUTION = [_]Beat{
    .{ .note = "Tamsin searches her washstand.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "WashStand" } }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin waits for Rook to head down the landing, then borrows his sailing papers.", .actions = &.{
        .{ .until_gone = .{ .subject = "CaptainRook", .relation = "AtHisDoor" } },
        .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "RookDoor" } },
        .{ .ticks = 1 },
        // At the start Rook has not reached his door yet, so the wait passes at once and he
        // can arrive in the same tick; the door then refuses, and the beat waits for him again.
        .{ .require = .{ .subject = "Tamsin", .relation = "Carries", .object = "RookPapers" } },
    } },
    .{ .note = "Tamsin draws a beard on Rook's portrait.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "Charcoal", .b = "RookPapers" } }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin heads into the yard and finds the watering can.", .actions = &.{
        .{ .scene = .{ .scene = "Net Loft Yard", .actor = "Tamsin", .mark = "YardPath" } },
        .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "RainBarrel" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "Tamsin tapes the gap under the gate.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "SailTape", .b = "GateGap" } }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin soaks the dog with the watering can.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "WateringCan", .b = "Bramble" } }, .{ .ticks = 8 } } },
    .{ .note = "Tamsin peels the dog fur off the tape.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "GateGap" } }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin makes a beard with the honey.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "DogFur", .b = "HoneyPot" } }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin puts on the beard.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "GreyBeard", .b = "Tamsin" } }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin asks Purser Wick for Rook's berth.", .actions = &.{
        .{ .scene = .{ .scene = "Harbour Office", .actor = "Tamsin", .mark = "OfficeDoor" } },
        .{ .cue = .{ .name = "TalksTo", .actor = "Tamsin", .a = "PurserWick" } },
        .{ .ticks = 4 },
    } },
};

const LAMP_POINT_SOLUTION = [_]Beat{
    .{ .note = "Tamsin heads for the cellar hatch.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "CellarHatch" } }, .{ .settle = "Tamsin" }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin hauls the anchor into Cudgel's rope line.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "OldAnchor" } }, .{ .settle = "Tamsin" }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin tries the hatch again.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Tamsin", .a = "CellarHatch" } }, .{ .settle = "Tamsin" }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin studies the wreckers' chart in the cellar.", .actions = &.{ .{ .cue = .{ .name = "LooksAt", .actor = "Tamsin", .a = "WreckersChart" } }, .{ .ticks = 1 } } },
};

// The Three Tides proof's host passes items through the Tide Wells and sets the
// facts each era's rules react to; the rules' interruptions are the script's.
const TIDES_SOLUTION = [_]Beat{
    .{ .note = "Nell sends the cheap port down the well to 1712.", .actions = &.{
        .{ .transfer = .{ .item = "CheapPort", .from = "Nell", .to = "Ossie" } },
        .{ .scene = .{ .scene = "Charter Yard" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "Ossie seals the port in the cornerstone box; two centuries turn it to vinegar.", .actions = &.{
        .{ .forget = .{ .subject = "Ossie", .relation = "Carries", .object = "CheapPort" } },
        .{ .remember = .{ .subject = "CheapPort", .relation = "SealedInBox", .value = 1 } },
        .{ .remember = .{ .subject = "CheapPort", .relation = "PortAgedIntoVinegar", .value = 1 } },
        .{ .scene = .{ .scene = "Brine's Boarding House" } },
        .{ .remember = .{ .subject = "Nell", .relation = "Carries", .object = "AgedVinegar" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "The vinegar goes back to Ossie, who fills the voltaic jar and charges his well.", .actions = &.{
        .{ .transfer = .{ .item = "AgedVinegar", .from = "Nell", .to = "Ossie" } },
        .{ .forget = .{ .subject = "Ossie", .relation = "Carries", .object = "AgedVinegar" } },
        .{ .forget = .{ .subject = "Ossie", .relation = "Carries", .object = "VoltaicJar" } },
        .{ .remember = .{ .subject = "Ossie", .relation = "Carries", .object = "ChargedJar" } },
        .{ .remember = .{ .subject = "Ossie", .relation = "WellPowered", .value = 1 } },
        .{ .scene = .{ .scene = "Charter Yard" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "Widow Fenn sews a banner from the gull handbill.", .actions = &.{
        .{ .transfer = .{ .item = "GullHandbill", .from = "Nell", .to = "Ossie" } },
        .{ .remember = .{ .subject = "WidowFenn", .relation = "BannerSewn", .value = 1 } },
        .{ .ticks = 2 },
    } },
    .{ .note = "Founder Gale fells the orange tree for the red blight.", .actions = &.{
        .{ .remember = .{ .subject = "FounderGale", .relation = "TreeFelled", .object = "OrangeTree" } },
        .{ .ticks = 2 },
    } },
    .{ .note = "In 2112 the tree is gone, and Juno is free.", .actions = &.{
        .{ .scene = .{ .scene = "Gull Roost" } },
        .{ .remember = .{ .subject = "Juno", .relation = "FreedFromTree", .value = 1 } },
        .{ .forget = .{ .subject = "Juno", .relation = "Trapped", .value = 1 } },
        .{ .ticks = 1 },
    } },
};

// The grog cups give out about nine ticks after the scene opens, so the whole sprint is one
// beat: press [S] at once, or after [R].
const GROG_SOLUTION = [_]Beat{
    .{ .note = "Mara runs for the lock, pouring before each cup fails.", .actions = &.{
        .{ .walk = .{ .actor = "Mara", .mark = "LockMark" } },
        .{ .ticks = 2 },
        .{ .pour = .{ .from = "CupA", .to = "CupB" } },
        .{ .cue = .{ .name = "Pours", .actor = "Mara", .a = "CupA", .b = "CupB" } },
        .{ .ticks = 2 },
        .{ .pour = .{ .from = "CupB", .to = "CupC" } },
        .{ .cue = .{ .name = "Pours", .actor = "Mara", .a = "CupB", .b = "CupC" } },
        .{ .settle = "Mara" },
        .{ .cue = .{ .name = "Dissolves", .actor = "Mara", .a = "CellLock" } },
        .{ .ticks = 1 },
    } },
};

// The Copper Weathercock's desktop solution, inside the borrowed month: follow the current to
// the Customs House, take the crank and open the sluice, follow it up Beacon Hill, deliver the
// note, and carry the weathercock into the fog whirl. The hypervisor closes the loop next tick.
const WEATHERCOCK_SOLUTION = [_]Beat{
    .{ .note = "Pilot Ashe: follow the current.", .actions = &.{ .{ .cue = .{ .name = "TalksTo", .actor = "Wren", .a = "PilotAshe" } }, .{ .ticks = 1 } } },
    .{ .note = "Wren follows the current to the Customs House and takes the sluice crank.", .actions = &.{
        .{ .scene = .{ .scene = "The Customs House", .actor = "Wren", .mark = "SluiceMark" } },
        .{ .remember = .{ .subject = "Wren", .relation = "Carries", .object = "Crank" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "One turn of the crank opens the sluice; the Customs House floods.", .actions = &.{
        .{ .remember = .{ .subject = "Wren", .relation = "SluiceOpened", .object = "SluiceProp" } },
        .{ .remember = .{ .subject = "Wren", .relation = "CustomsFlooded", .value = 1 } },
        .{ .ticks = 1 },
    } },
    .{ .note = "The current leads up Beacon Hill; Wren gives the sealed note to Hester Quill.", .actions = &.{
        .{ .scene = .{ .scene = "Beacon Hill", .actor = "Wren", .mark = "WhirlMark" } },
        .{ .remember = .{ .subject = "Wren", .relation = "Carries", .object = "Note" } },
        .{ .remember = .{ .subject = "Wren", .relation = "NoteDelivered", .object = "HesterQuill" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "Wren carries the weathercock into the fog whirl. The loop closes.", .actions = &.{
        .{ .remember = .{ .subject = "Wren", .relation = "Carries", .object = "WeathercockProp" } },
        .{ .place = .{ .actor = "WeathercockProp", .scene = "Beacon Hill", .mark = "WhirlMark" } },
        .{ .remember = .{ .subject = "Wren", .relation = "KeystoneAtConvergence", .object = "WeathercockProp" } },
        .{ .remember = .{ .subject = "Wren", .relation = "ConvergenceReady", .value = 1 } },
        .{ .ticks = 1 },
    } },
};

// The Bell Tower's desktop solution: watch, kindle, learn, climb, loosen, take the fork, toll.
const BELL_TOWER_SOLUTION = [_]Beat{
    .{ .note = "Maren watches the lantern.", .actions = &.{ .{ .cue = .{ .name = "LooksAt", .actor = "Maren", .a = "Lantern" } }, .{ .ticks = 1 } } },
    .{ .note = "Maren weaves Kindle (C D E C) on the brazier.", .actions = &.{.{ .weave = .{ .notes = "CDEC", .target = "Brazier" } }} },
    .{ .note = "The ivy teaches Bind.", .actions = &.{ .{ .cue = .{ .name = "LooksAt", .actor = "Maren", .a = "Ivy" } }, .{ .ticks = 1 } } },
    .{ .note = "Maren climbs to the belfry by firelight.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Maren", .a = "Stairwell" } }, .{ .ticks = 2 } } },
    .{ .note = "Bind played backwards: Loose (F D E F) frees the chain.", .actions = &.{.{ .weave = .{ .notes = "FDEF", .target = "IronChain" } }} },
    .{ .note = "Maren takes the tuning fork; the distaff reaches all seven notes.", .actions = &.{ .{ .cue = .{ .name = "PicksUp", .actor = "Maren", .a = "TuningFork" } }, .{ .ticks = 1 } } },
    .{ .note = "Maren weaves Toll (G A B G) on the great bell.", .actions = &.{.{ .weave = .{ .notes = "GABG", .target = "GreatBell" } }} },
};

// =============================================================================
// Host setup the desktop proofs do in Zig
// =============================================================================

/// The desktop proof's opening: the three scenes joined into one route, everyone at their
/// marks, and a 280-tick branch forked with the weathercock as its keystone. Every name the
/// solution writes is interned first, so the primary and branch worlds share their ids.
fn weathercock_setup(rt: *WasmRuntime) anyerror!void {
    for ([_][]const u8{ "Crank", "Note" }) |name| _ = try entity(rt, name);
    for ([_][]const u8{ "Carries", "SluiceOpened", "CustomsFlooded", "NoteDelivered", "KeystoneAtConvergence", "ConvergenceReady", "MemoryCarried", "KeystoneMaterialized" }) |name| {
        _ = try rt.world.intern_relation(name, .set);
    }
    const attic = try entity(rt, "Wren's Attic");
    const customs = try entity(rt, "The Customs House");
    const hill = try entity(rt, "Beacon Hill");
    const g = &rt.spatial.graph;
    const route = [_]struct { room: EntityId, mark: []const u8 }{
        .{ .room = attic, .mark = "CotMark" },        .{ .room = attic, .mark = "DeskMark" },
        .{ .room = attic, .mark = "AtticStairs" },    .{ .room = customs, .mark = "LedgerMark" },
        .{ .room = customs, .mark = "CountingFloor" }, .{ .room = customs, .mark = "SluiceMark" },
        .{ .room = hill, .mark = "HillCrest" },       .{ .room = hill, .mark = "PostBoxMark" },
        .{ .room = hill, .mark = "WhirlMark" },
    };
    var previous: ?bespoke.WaypointId = null;
    for (route) |stop| {
        const wp = g.find_waypoint_in_room(stop.room, stop.mark) orelse return error.UnknownMark;
        if (previous) |p| try g.connect(p, wp, null);
        previous = wp;
    }
    try bespoke.host.add_exit_marks(&rt.world, &rt.spatial, &weathercock.EXITS);
    const places = [_]struct { who: []const u8, room: EntityId, mark: []const u8 }{
        .{ .who = "Wren", .room = attic, .mark = "CotMark" },
        .{ .who = "PilotAshe", .room = attic, .mark = "DeskMark" },
        .{ .who = "Pell", .room = customs, .mark = "LedgerMark" },
        .{ .who = "HesterQuill", .room = hill, .mark = "PostBoxMark" },
        .{ .who = "WeathercockProp", .room = attic, .mark = "CotMark" },
    };
    for (places) |pl| try rt.spatial.register_entity(try entity(rt, pl.who), g.find_waypoint_in_room(pl.room, pl.mark).?, 8);
    try rt.vm.transition_to_scene(attic);

    const hv = try rt.attach_hypervisor();
    _ = try hv.fork_branch(280, try entity(rt, "Wren"), try entity(rt, "WeathercockProp"));
    hv.set_convergence_target(g.find_waypoint_in_room(hill, "WhirlMark").?);
    try hv.add_dream_residue(.{ .subject = try entity(rt, "Wren"), .relation = try relation(rt, "MemoryCarried"), .object_or_value = 1 });
    art.show_branch(rt.frame_bridge, hv);
    rt.bind();
}

/// The desktop proof's tick: step the hypervisor after the VM, and when the loop resolves carry
/// the flood and the note into the primary world before the branch is gone.
fn weathercock_after_tick(rt: *WasmRuntime) anyerror!void {
    const hv = rt.hypervisor orelse return;
    defer art.show_branch(rt.frame_bridge, hv);
    if (!hv.branch_active) return;
    const branch = rt.active_world();
    const wren = try entity(rt, "Wren");
    const flood = try relation(rt, "CustomsFlooded");
    const note = try relation(rt, "NoteDelivered");
    const flooded = branch.has_fact(wren, flood, null);
    const delivered = branch.has_fact(wren, note, null);
    // A script cannot move a prop, so the host carries the weathercock to the whirl once the
    // script says it went in; loop closure checks where the keystone stands.
    const keystone = try entity(rt, "WeathercockProp");
    if (branch.has_fact(wren, try relation(rt, "KeystoneAtConvergence"), keystone.to_int())) {
        const hill = try entity(rt, "Beacon Hill");
        const whirl = rt.spatial.graph.find_waypoint_in_room(hill, "WhirlMark") orelse return error.UnknownMark;
        const here = if (rt.spatial.agents.get(keystone)) |a| a.current_wp else null;
        if (here != whirl) _ = try rt.spatial.transition_actor(keystone, hill, whirl);
    }
    switch (try hv.step_tick(&rt.spatial)) {
        .loop_resolved => {
            if (flooded) try rt.world.remember(wren, flood, 1, 0);
            if (delivered) try rt.world.remember(wren, note, (try entity(rt, "HesterQuill")).to_int(), 0);
            rt.set_banner(if (weathercock.evaluate_weathercock_solved(&rt.world)) "The borrowed month folds back cleanly. The loop is closed." else "The borrowed month folds back.");
        },
        .budget_expired => rt.set_banner("The borrowed month tears away. Press [R] to rewind."),
        else => {},
    }
    rt.bind();
}

/// The desktop proof's tower layout, with Maren at the doorway of the base.
fn bell_tower_setup(rt: *WasmRuntime) anyerror!void {
    const ids = try bell_tower.configure(&rt.world, &rt.spatial);
    try rt.vm.transition_to_scene(ids.base);
    bell_tower_scene = ids.base;
}

/// The scene the Bell Tower deck last showed. The script changes scenes itself; as on desktop,
/// Maren follows to the stair at the other end.
var bell_tower_scene: EntityId = .none;

fn bell_tower_follow_scene(rt: *WasmRuntime) anyerror!void {
    const now = rt.vm.current_scene orelse return;
    if (now == bell_tower_scene) return;
    bell_tower_scene = now;
    const maren = try entity(rt, "Maren");
    const mark = if (std.mem.eql(u8, rt.world.get_entity_name(now) orelse "", bell_tower.BELFRY_SCENE)) "StairTop" else "StairFoot";
    _ = try rt.spatial.transition_actor(maren, now, rt.spatial.graph.find_waypoint_in_room(now, mark));
}

fn beard_setup(rt: *WasmRuntime) anyerror!void {
    // The desktop's mark layout, cast places, and office lane (D-100).
    try borrowed_beard.stage(&rt.world, &rt.spatial, true);
    try rt.vm.transition_to_scene(try entity(rt, "Inn Landing"));
}


// The Pip-Spitting Green: talking to Judge Marrow offers the spit, as the desktop window does.
const SPIT_NOW: u32 = 1;
const SPIT_RULES: u32 = 2;
const SPIT_LEAVE: u32 = 3;
const SPIT_CHOICES = [_]bespoke.dialogue.Choice{
    .{ .text = "I'm ready to spit!", .action = SPIT_NOW },
    .{ .text = "What are the rules again?", .action = SPIT_RULES },
    .{ .text = "Never mind.", .action = SPIT_LEAVE },
};

fn spit_act(rt: *WasmRuntime, verb: wasm.WasmVerb, target: EntityId) anyerror!bool {
    if (verb != .talk_to or bespoke.dialogue.view(&rt.world) != null) return false;
    const name = rt.world.get_entity_name(target) orelse return false;
    if (!std.mem.eql(u8, name, "JudgeMarrow")) return false;
    _ = try rt.vm.open_generated_dialogue(target, "Toe the chalk, love, and mind my boots.", &SPIT_CHOICES);
    return true;
}

fn spit_choice(rt: *WasmRuntime, action: u32) anyerror!void {
    switch (action) {
        SPIT_NOW => try spit_now(rt),
        SPIT_RULES => rt.queue_message("JudgeMarrow", "Spit past the last peg to win! Thick spit, a sea breeze, and my eyes on the throw!"),
        else => rt.set_banner("Tamsin steps back."),
    }
}

/// Tamsin spits from where she stands; the script's `Spits` handler judges it that tick.
fn spit_now(rt: *WasmRuntime) anyerror!void {
    const program = if (rt.program) |*p| p else return;
    _ = try rt.vm.fire_cue(program, "Spits", try entity(rt, "Tamsin"), null, null);
    try rt.step_tick();
}

/// The page's Spit button (D-095), as the desktop window's spit key: spits at once, closing the
/// judge's offer if it is open, so the breeze is not lost to a walk and a dialogue.
const SPIT_ACTION: u8 = 1;
fn spit_action(rt: *WasmRuntime, id: u8) anyerror!void {
    if (id != SPIT_ACTION) return;
    if (bespoke.dialogue.view(&rt.world)) |open| try bespoke.dialogue.clear_open(&rt.world, open.speaker);
    try spit_now(rt);
}

/// The desktop's layout, hotspots, and cast places (D-100): Cudgel waits at his post, and
/// Tamsin starts on the path up the Point.
fn lamp_point_setup(rt: *WasmRuntime) anyerror!void {
    const stage = try lamp_point.Stage.init(&rt.world, &rt.spatial, true);
    try rt.vm.transition_to_scene(stage.point_scene);
}

/// USE on the hatch or the anchor is a walk to its mark, as in the desktop window: the walk
/// that brings Tamsin over (D-092) ends on the mark, and the script's arrival rule does the
/// rest. Firing the script's `Uses` cue after that walk would walk her there a second time and
/// fire the arrival rule twice (Cudgel shoved her twice on one click).
fn lamp_point_on_act(rt: *WasmRuntime, verb: wasm.WasmVerb, target: bespoke.EntityId) anyerror!bool {
    if (verb != .use_with) return false;
    const name = rt.world.get_entity_name(target) orelse return false;
    return std.mem.eql(u8, name, "CellarHatch") or std.mem.eql(u8, name, "OldAnchor");
}

/// The script's room changes move Tamsin with them, as in the desktop window. The walk that
/// took her there is over, so its held action goes too; otherwise the page would report that
/// she never reached the hatch she just went down through.
fn lamp_point_after_tick(rt: *WasmRuntime) anyerror!void {
    if (try lamp_point.follow_into_scene(&rt.world, &rt.spatial, &rt.vm)) rt.approach = null;
}

/// The opening the desktop proof's host sets: Juno trapped and guarded, the port and the
/// handbill with Nell, the red lead and the voltaic jar with Ossie, and 1912 on stage.
fn tides_setup(rt: *WasmRuntime) anyerror!void {
    const facts = [_]Fact{
        .{ .subject = "Juno", .relation = "Trapped", .value = 1 },
        .{ .subject = "Juno", .relation = "Guarded", .value = 1 },
        .{ .subject = "Nell", .relation = "Carries", .object = "CheapPort" },
        .{ .subject = "Nell", .relation = "Carries", .object = "GullHandbill" },
        .{ .subject = "Ossie", .relation = "Carries", .object = "RedLeadPaint" },
        .{ .subject = "Ossie", .relation = "Carries", .object = "VoltaicJar" },
    };
    for (facts) |f| try rt.world.remember(try entity(rt, f.subject), try relation(rt, f.relation), try fact_object(rt, f), 0);
    try rt.vm.transition_to_scene(try entity(rt, "Brine's Boarding House"));
    // Fastened after the script starts, which stands the cast on each scene's first mark, the
    // niche between the well and the box. The window, the render golden, and this page seat
    // Fenn on her sewing bench through the same function (P43-01, D-100, D-124).
    try three_tides.place_fenn(&rt.world, &rt.spatial);
}

/// The page's party buttons (D-095): each makes one of the three the player, in their own era.
pub const TIDES_OSSIE: u8 = 1;
pub const TIDES_NELL: u8 = 2;
pub const TIDES_JUNO: u8 = 3;
const TidesMember = struct { who: []const u8, scene: []const u8 };
const TIDES_PARTY = [_]TidesMember{
    .{ .who = "Ossie", .scene = "Charter Yard" },
    .{ .who = "Nell", .scene = "Brine's Boarding House" },
    .{ .who = "Juno", .scene = "Gull Roost" },
};

fn tides_action(rt: *WasmRuntime, id: u8) anyerror!void {
    if (id < TIDES_OSSIE or id > TIDES_JUNO) return;
    const member = TIDES_PARTY[id - 1];
    // A held item or a walk belongs to the player who was playing.
    rt.selected_item = .none;
    rt.approach = null;
    rt.player_entity = try entity(rt, member.who);
    try rt.vm.transition_to_scene(try entity(rt, member.scene));
    var buf: [64]u8 = undefined;
    rt.set_banner(std.fmt.bufPrint(&buf, "Playing {s}.", .{member.who}) catch member.who);
}

/// The host's half of the cascade, shared with the desktop window (D-100): once the tree is
/// felled in 1712, Juno is no longer trapped in 2112 and stands on the roof; when every piece
/// is in place, the page says the puzzle is solved.
fn tides_after_tick(rt: *WasmRuntime) anyerror!void {
    _ = try three_tides.free_juno_if_felled(&rt.world, &rt.spatial);
    if (three_tides.evaluate_tides_solved(&rt.world) and !holds(rt, "Juno", "TidesSolved", null)) {
        try rt.world.remember(try entity(rt, "Juno"), try relation(rt, "TidesSolved"), 1, 0);
        rt.set_banner("VICTORY ACHIEVED! The Well of Three Tides temporal puzzle solved!");
    }
}

// =============================================================================
// The Living Village: the engine's society, configured by the script
// =============================================================================

/// The village's society. The browser runs one runtime at a time, and the deck's setup
/// re-initialises this on every load. Held `undefined` with a flag, not as an initialised
/// optional, so the module carries no zero data for it (D-067).
var village_society: society.Society = undefined;
var village_ready = false;
const VILLAGE_HUNGER: usize = 0;

fn village_setup(rt: *WasmRuntime) anyerror!void {
    village_ready = false;
    const program = if (rt.program) |*p| p else return error.NoProgram;
    if (program.societies.items.len != 1) return error.MissingVillageSociety;
    village_society = try society.Society.init(&rt.world, program.societies.items[0].config);
    // The desktop's settlement layout and starting places (D-100).
    const village_scene = try entity(rt, "Living Village");
    _ = try village.lay_out_settlement(&rt.world, &rt.spatial, village_scene);
    for (village.STARTS) |start| {
        const wp = rt.spatial.graph.find_waypoint_in_room(village_scene, start.mark) orelse return error.MissingVillageMark;
        _ = try rt.spatial.transition_actor(try entity(rt, start.who), village_scene, wp);
    }
    village_ready = true;
    rt.set_banner("Living Village: six villagers run their own day. [S] starves the Drifter.");
}

fn village_after_tick(rt: *WasmRuntime) anyerror!void {
    if (!village_ready) return;
    try village_society.step(&rt.world, &rt.spatial, &rt.vm);
}

/// The desktop proof's desperation catalyst: the Drifter is starving and penniless, and heads
/// for the bakery. What follows (theft, witnesses, rumour, arrest) is the society's own doing.
fn village_desperation(rt: *WasmRuntime) anyerror!void {
    if (!village_ready) return;
    const r = village_society.rel;
    const drifter = try entity(rt, "Drifter");
    _ = rt.world.forget(drifter, r.arrested, null);
    _ = rt.world.forget(drifter, r.stolen_from, null);
    try village_society.set_need(&rt.world, drifter, VILLAGE_HUNGER, 88);
    try village_society.set_gold(&rt.world, drifter, 0);
    try village_society.set_activity(&rt.world, drifter, .stealing);
    if (rt.spatial.graph.find_waypoint("Bakery")) |bakery| {
        _ = try society.Society.walk_to(&rt.world, &rt.spatial, drifter, bakery);
    }
    rt.set_banner("The Drifter is starving and has no money. Watch the village react.");
}

// =============================================================================
// Brackwater Barbs: the engine duel, configured by the script
// =============================================================================

/// The duel and the bout in progress. The round is World facts, as on desktop, so a rewind
/// restores it with the generated choice set (D-046); the desktop proof's `Bout` runs the turns
/// (D-078), so both play the same duel.
var sword_duel: duel_mod.Duel = undefined;
var sword_bout: sword_fighting.Bout = undefined;
var sword_ready = false;

/// The bout, pointed at the live World. `Duel` and `Bout` keep the World they were initialised
/// with, and the runtime is moved after setup (`WasmRuntime.bind`), so every use re-points them.
fn sword(rt: *WasmRuntime) ?*sword_fighting.Bout {
    if (!sword_ready) return null;
    sword_duel.world = &rt.world;
    sword_bout.world = &rt.world;
    sword_bout.duel = &sword_duel;
    return &sword_bout;
}

const DECK_SWORD_SEED: u64 = 0x5EA5_1DE;

fn sword_setup(rt: *WasmRuntime) anyerror!void {
    sword_ready = false;
    const program = if (rt.program) |*p| p else return error.NoProgram;
    if (program.duels.items.len != 1) return error.MissingSwordDuel;
    const decl = &program.duels.items[0];
    sword_duel = try duel_mod.Duel.init(&rt.world, decl.config);
    try decl.apply_tiers(&sword_duel);
    sword_bout = try sword_fighting.Bout.init(&rt.world, &sword_duel, try entity(rt, "Tamsin"));
    // The desktop deals the fencers' knowledge afresh each launch; the deck uses one fixed
    // seed so its golden frames stay stable (D-082).
    var fencers: [sword_fighting.FENCERS.len]EntityId = undefined;
    for (sword_fighting.FENCERS, 0..) |name, i| fencers[i] = try entity(rt, name);
    try sword_fighting.deal_knowledge(&sword_duel, &fencers, DECK_SWORD_SEED);
    try sword_bout.set_seed(@truncate(DECK_SWORD_SEED));
    sword_ready = true;
    try sword_fighting.place_cast(&rt.world, &rt.spatial, true);
    try rt.vm.transition_to_scene(try entity(rt, "Tidewalk"));
}

fn sword_start(rt: *WasmRuntime, opponent_name: []const u8, opening: EntityId) !void {
    const bout = sword(rt) orelse return;
    try bout.start(&rt.vm, try entity(rt, opponent_name), opening);
    try bout.open(&rt.vm);
    rt.render_frame();
    var name_buf: [48]u8 = undefined;
    const shown = bespoke.display.dialogue_panel.named(rt.active_world(), opponent_name, &name_buf);
    var buf: [96]u8 = undefined;
    rt.set_banner(std.fmt.bufPrint(&buf, "{s} draws. Answer with the number keys, or [S].", .{shown}) catch opponent_name);
}

/// Every fencer in the order `[S]` duels them: the three on the Tidewalk, then Mistress Vell.
const SWORD_ROTATION = sword_fighting.FENCERS ++ [_][]const u8{"Vell"};

/// Starts a duel with `name`, walking Tamsin into the fencer's scene first: Vell's yard, or
/// the Tidewalk for the others.
fn sword_duel_with(rt: *WasmRuntime, name: []const u8) !void {
    const tamsin = try entity(rt, "Tamsin");
    const vell = std.mem.eql(u8, name, "Vell");
    const scene = try entity(rt, if (vell) "Fencing Yard" else "Tidewalk");
    if (rt.vm.current_scene == null or rt.vm.current_scene.? != scene) {
        try rt.vm.transition_to_scene(scene);
        const mark = rt.spatial.graph.find_waypoint_in_room(scene, if (vell) "YardCircle" else "TidewalkMid");
        _ = try rt.spatial.transition_actor(tamsin, scene, mark);
    }
    return sword_start(rt, name, .none);
}

/// `[S]`: with a round open, plays the first choice; otherwise duels the next fencer in
/// `SWORD_ROTATION`, counted by the duels already decided.
fn sword_solve(rt: *WasmRuntime) anyerror!void {
    _ = sword(rt) orelse return;
    if (bespoke.dialogue.view(&rt.world) != null) return rt.answer(0);
    var decided: u32 = sword_duel.wins(try entity(rt, "Tamsin"));
    for (SWORD_ROTATION) |name| decided += sword_duel.wins(try entity(rt, name));
    return sword_duel_with(rt, SWORD_ROTATION[decided % SWORD_ROTATION.len]);
}

/// TALK on a fencer starts a duel with it (D-086); anything else falls through to the script.
fn sword_act(rt: *WasmRuntime, verb: wasm.WasmVerb, target: EntityId) anyerror!bool {
    _ = sword(rt) orelse return false;
    if (verb != .talk_to or bespoke.dialogue.view(&rt.world) != null) return false;
    const name = rt.world.get_entity_name(target) orelse return false;
    for (SWORD_ROTATION) |fencer| {
        if (std.mem.eql(u8, fencer, name)) {
            try sword_duel_with(rt, fencer);
            return true;
        }
    }
    return false;
}

/// Plays the chosen barb or comeback through the desktop's `Bout`. When the duel ends, the
/// script's `WinsDuel` handler speaks, and the next tick puts the line in the banner.
fn sword_choice(rt: *WasmRuntime, action: u32) anyerror!void {
    const bout = sword(rt) orelse return;
    var buf: [320]u8 = undefined;
    const result = try bout.choose(&rt.vm, action, &buf);
    // Each line waits for a click (D-080); the next round's choices show once all are read.
    for (result.slice()) |line| rt.queue_message(line.speaker, line.text);
    if (result.winner) |winner| {
        const program = if (rt.program) |*p| p else return;
        _ = try rt.vm.fire_cue(program, "WinsDuel", winner, result.loser, null);
        try rt.step_tick();
        var spoken: [4]bespoke.host.SpeechLine = undefined;
        const n = bespoke.host.speech_lines(rt.active_world(), &rt.vm, &spoken);
        for (spoken[0..n]) |line| rt.queue_message(line.speaker, line.text);
        return;
    }
    try bout.open(&rt.vm);
}

// =============================================================================
// The Saltmarket: three stageplay paths, chosen from a generated selector
// =============================================================================

const SALTMARKET_SELECTOR = [_]bespoke.dialogue.Choice{
    .{ .text = "Cunning: read the tally book", .action = 1 },
    .{ .text = "Muscle: force the stall", .action = 2 },
    .{ .text = "Crew: recruit the net-menders", .action = 3 },
};

/// The desktop proof's own market layout and gates, then the path selector.
fn saltmarket_setup(rt: *WasmRuntime) anyerror!void {
    const ids = try saltmarket.configure(&rt.world, &rt.spatial);
    try rt.vm.transition_to_scene(ids.scene);
    _ = try rt.vm.open_generated_dialogue(ids.quince, "Choose your approach, Tamsin.", &SALTMARKET_SELECTOR);
    rt.set_banner("Saltmarket: choose [1] Cunning, [2] Muscle, or [3] Crew. [S] plays the next step.");
}

fn saltmarket_active(rt: *WasmRuntime) ?saltmarket.PathSpec {
    const active = rt.world.lookup_relation("PathActive") orelse return null;
    for (saltmarket.paths) |spec| {
        const route = rt.world.lookup_entity(spec.name) orelse continue;
        if (rt.world.has_fact(route, active, null)) return spec;
    }
    return null;
}

fn saltmarket_choice(rt: *WasmRuntime, action: u32) anyerror!void {
    if (action == 0 or action > saltmarket.paths.len) return;
    const spec = saltmarket.paths[action - 1];
    const program = if (rt.program) |*p| p else return;
    _ = (try rt.vm.select_path(program, spec.name)) orelse return;
    try rt.step_tick();
    rt.set_banner(spec.banner);
}

/// TAKE or USE on the logbook, once Tamsin has walked over to it (D-092), runs the chosen
/// path's solution routine, as `[S]` does at the end of its run; the script owns the routine.
fn saltmarket_act(rt: *WasmRuntime, verb: wasm.WasmVerb, target: EntityId) anyerror!bool {
    if (verb != .pick_up and verb != .use_with) return false;
    if (target != try entity(rt, "Logbook")) return false;
    const spec = saltmarket_active(rt) orelse {
        rt.set_banner("Choose a way in first.");
        return true;
    };
    if (holds(rt, "Tamsin", "Acquired", "Logbook")) {
        rt.set_banner("The logbook is Tamsin's. Press [R] to rewind and try another way.");
        return true;
    }
    const program = if (rt.program) |*p| p else return false;
    const entry = program.routine_entries.get(spec.routine) orelse return false;
    _ = try rt.vm.spawn_routine(try entity(rt, "Tamsin"), entry);
    try rt.step_tick();
    return true;
}

/// `[S]`: the desktop proof's path run: choose Cunning if no path is chosen, walk through the
/// path's gate to the logbook, talk to Quince, then run the path's own solution routine.
fn saltmarket_solve(rt: *WasmRuntime) anyerror!void {
    const program = if (rt.program) |*p| p else return;
    const tamsin = try entity(rt, "Tamsin");
    const spec = saltmarket_active(rt) orelse {
        if (bespoke.dialogue.view(&rt.world) != null) return rt.answer(0);
        return;
    };
    if (holds(rt, "Tamsin", "Acquired", "Logbook")) {
        rt.set_banner("The logbook is Tamsin's. Press [R] to rewind and try another way.");
        return;
    }
    const scene = try entity(rt, "Saltmarket");
    const logbook_wp = rt.spatial.graph.find_waypoint_in_room(scene, "LogbookMark") orelse return;
    if (rt.spatial.get_current_waypoint(tamsin) != logbook_wp) {
        rt.set_banner("Tamsin heads through the open gate to the logbook.");
        _ = try rt.spatial.walk_to_with_world(&rt.world, tamsin, logbook_wp);
        _ = try perform(rt, .{ .settle = "Tamsin" });
        return;
    }
    if (bespoke.dialogue.view(&rt.world) != null) return rt.answer(0);
    const chosen = rt.world.lookup_relation("SolveTalked");
    if (chosen == null or !rt.world.has_fact(tamsin, chosen.?, null)) {
        try rt.vm.set_dialogue_speaker(tamsin, try entity(rt, "BrokerQuince"));
        _ = try rt.vm.fire_cue(program, "Talk", tamsin, try entity(rt, "BrokerQuince"), null);
        try rt.step_tick();
        try rt.world.remember(tamsin, try rt.world.intern_relation("SolveTalked", .property), 1, 0);
        return;
    }
    const entry = program.routine_entries.get(spec.routine) orelse return;
    _ = try rt.vm.spawn_routine(tamsin, entry);
    try rt.step_tick();
    try rt.step_tick();
}

// =============================================================================
// The Castle Fire Escape: the grid steps in `host.tick`; the deck adds the proof's door rules
// after each tick and its three actions (P34-03).
// =============================================================================

/// The proof's handles, kept for the after-tick rules and the actions. One deck, one copy.
var keep_ids: ?grid_puzzle.Ids = null;

/// Page buttons for Wren's actions (D-095), numbered as the desktop keys 1, 2, 3.
pub const KEEP_FILL: u8 = 1;
pub const KEEP_LIGHT: u8 = 2;
pub const KEEP_THROW: u8 = 3;

fn keep_setup(rt: *WasmRuntime) anyerror!void {
    keep_ids = try grid_puzzle.configure(&rt.world, &rt.spatial);
    try rt.vm.transition_to_scene(keep_ids.?.scene);
    rt.bind();
}

fn keep_after_tick(rt: *WasmRuntime) anyerror!void {
    const program = if (rt.program) |*p| p else return;
    try grid_puzzle.after_tick(&rt.world, &rt.vm, program, keep_ids orelse return);
}

/// Runs one of Wren's actions and the tick that answers it, or says why it cannot happen.
fn keep_do(rt: *WasmRuntime, which: grid_puzzle.Act) !void {
    const program = if (rt.program) |*p| p else return;
    if (try grid_puzzle.act(&rt.world, &rt.spatial, &rt.vm, program, keep_ids orelse return, which)) |refusal| {
        rt.set_banner(refusal);
        return;
    }
    try rt.step_tick();
}

/// USE on the trough fills the bucket and USE on the torch or the tapestry lights it, once
/// Wren has walked over (D-092).
fn keep_act(rt: *WasmRuntime, verb: wasm.WasmVerb, target: EntityId) anyerror!bool {
    if (verb != .use_with) return false;
    const ids = keep_ids orelse return false;
    if (target == ids.trough) {
        try keep_do(rt, .fill);
        return true;
    }
    if (target == ids.torch or target == ids.tapestry) {
        // Lighting is done from the torch, wherever the click was.
        if (rt.spatial.get_current_waypoint(ids.wren) != ids.torch_wp) {
            _ = try rt.spatial.walk_to_with_world(rt.active_world(), ids.wren, ids.torch_wp);
            rt.set_banner("Wren heads for the torch. Use it again when she gets there.");
            return true;
        }
        try keep_do(rt, .light);
        return true;
    }
    return false;
}

fn keep_action(rt: *WasmRuntime, id: u8) anyerror!void {
    switch (id) {
        KEEP_FILL => try keep_do(rt, .fill),
        KEEP_LIGHT => try keep_do(rt, .light),
        KEEP_THROW => try keep_do(rt, .throw),
        else => {},
    }
}

/// `[S]`: the desktop proof's solution, one step per press: fill the bucket at the trough,
/// light the tapestry from the torch, wait for the door, throw the water on it, wait for the
/// fire to die, and walk out.
fn keep_solve(rt: *WasmRuntime) anyerror!void {
    const program = if (rt.program) |*p| p else return;
    const ids = keep_ids orelse return;
    const decl = program.grids.items[0];
    const wren = ids.wren;
    const here = rt.spatial.get_current_waypoint(wren);
    const moving = rt.spatial.is_moving(wren);
    const cell = struct {
        fn at(i: u16) bespoke.grid.Cell {
            return .{ .x = i, .y = 0 };
        }
    }.at;
    const tapestry_lit = !bespoke.grid.has_attribute(&rt.world, decl.grid, cell(grid_puzzle.TAPESTRY_EAST_CELL), .flammable) or
        bespoke.grid.has_attribute(&rt.world, decl.grid, cell(grid_puzzle.TAPESTRY_FIRST_CELL), .burning);
    const door_wet = bespoke.grid.has_attribute(&rt.world, decl.grid, cell(grid_puzzle.DOOR_CELL), .liquid);
    if (moving) return rt.step_tick();
    if (!bespoke.host.has_state(&rt.world, ids.bucket, "Full") and !door_wet) {
        if (here != ids.trough_wp) {
            _ = try rt.spatial.walk_to_with_world(&rt.world, wren, ids.trough_wp);
            return perform_settle(rt);
        }
        return keep_do(rt, .fill);
    }
    if (!tapestry_lit) {
        if (here != ids.torch_wp) {
            _ = try rt.spatial.walk_to_with_world(&rt.world, wren, ids.torch_wp);
            return perform_settle(rt);
        }
        return keep_do(rt, .light);
    }
    const door_mark = try entity(rt, "DoorMark");
    if (rt.world.has_fact(door_mark, try relation(rt, "WaypointBlocked"), null)) {
        // Wait for the fire to reach the end of the tapestry and show the door.
        for (0..12) |_| {
            if (!rt.world.has_fact(door_mark, try relation(rt, "WaypointBlocked"), null)) break;
            try rt.step_tick();
        }
        return;
    }
    if (!door_wet) return keep_do(rt, .throw);
    var burning = false;
    var i: u16 = 0;
    while (i < decl.grid.width) : (i += 1) burning = burning or bespoke.grid.has_attribute(&rt.world, decl.grid, cell(i), .burning);
    if (burning) {
        for (0..12) |_| try rt.step_tick();
        return;
    }
    if (here != ids.door_wp) {
        _ = try rt.spatial.walk_to_with_world(&rt.world, wren, ids.door_wp);
        return perform_settle(rt);
    }
}

fn perform_settle(rt: *WasmRuntime) !void {
    _ = try perform(rt, .{ .settle = "Wren" });
}

// =============================================================================
// The Larkspur Observatory: the staff society steps after each tick, and typed lines go
// through the desktop proof's own interpreter and where-Ines-stands rules (P34-04).
// =============================================================================

var larkspur_ids: ?observatory.Ids = null;
var larkspur_staff: bespoke.society.Society = undefined;
var larkspur_interp: bespoke.command.Interpreter = .{};

fn larkspur_setup(rt: *WasmRuntime) anyerror!void {
    const program = if (rt.program) |*p| p else return error.NoProgram;
    larkspur_ids = try observatory.configure(&rt.world, &rt.spatial);
    larkspur_staff = try observatory.staff(&rt.world, program);
    larkspur_interp = .{};
    try rt.vm.transition_to_scene(larkspur_ids.?.scene);
    rt.bind();
    larkspur_words(rt);
}

fn larkspur_after_tick(rt: *WasmRuntime) anyerror!void {
    if (larkspur_ids == null) return;
    try larkspur_staff.step(&rt.world, &rt.spatial, &rt.vm);
    larkspur_words(rt);
}

/// The words Tab completes, from what Ines can name now, as the desktop refreshes them.
fn larkspur_words(rt: *WasmRuntime) void {
    const program = if (rt.program) |*p| p else return;
    const ids = larkspur_ids orelse return;
    bespoke.host.command_words(&rt.vm, program, ids.ines, &rt.window.command_words);
}

/// A typed line: the reply on the banner, and the tick that answers a fired cue.
fn larkspur_typed(rt: *WasmRuntime, line: []const u8) anyerror!void {
    const program = if (rt.program) |*p| p else return;
    const ids = larkspur_ids orelse return;
    var buf: [160]u8 = undefined;
    const result = try observatory.type_line(&rt.vm, program, &larkspur_interp, &rt.spatial, ids, line, &buf);
    if (result.text) |text| rt.set_banner(text);
    if (result.fired) try rt.step_tick();
}

/// `[S]`: the desktop proof's typed playthrough, one line per press: go to the archive, take
/// the slip, wait for Pell, and confront him with it.
fn larkspur_solve(rt: *WasmRuntime) anyerror!void {
    const ids = larkspur_ids orelse return;
    if (rt.spatial.is_moving(ids.ines)) return rt.step_tick();
    if (bespoke.host.has_state(&rt.world, ids.pell, "Cornered")) return;
    const slip = rt.world.has_fact(ids.ines, try relation(rt, "Carries"), ids.slip.to_int());
    if (!slip) {
        if (rt.spatial.get_current_waypoint(ids.ines) != ids.archive_wp) return larkspur_typed(rt, "go to the archive");
        return larkspur_typed(rt, "pick up the exposure slip");
    }
    if (!observatory.within_reach(&rt.spatial, ids.ines, ids.pell)) {
        rt.set_banner("Ines waits for Pell to come within reach.");
        for (0..10) |_| {
            if (observatory.within_reach(&rt.spatial, ids.ines, ids.pell)) break;
            try rt.step_tick();
        }
        return;
    }
    return larkspur_typed(rt, "present the slip to the rival");
}

// =============================================================================
// Valerius and the Bread: typed lines go through the desktop proof's own interpreter, and the
// cast follows the script into spring (P45-06).
// =============================================================================

var greyhold_ids: ?valerius.Ids = null;
var greyhold_interp: bespoke.command.Interpreter = .{};

fn greyhold_setup(rt: *WasmRuntime) anyerror!void {
    greyhold_ids = try valerius.configure(&rt.world, &rt.spatial);
    greyhold_interp = .{};
    try rt.vm.transition_to_scene(greyhold_ids.?.store);
    rt.bind();
    greyhold_words(rt);
}

fn greyhold_after_tick(rt: *WasmRuntime) anyerror!void {
    if (greyhold_ids == null) return;
    _ = try valerius.follow_into_spring(&rt.world, &rt.spatial, &rt.vm);
    greyhold_words(rt);
}

fn greyhold_words(rt: *WasmRuntime) void {
    const program = if (rt.program) |*p| p else return;
    const ids = greyhold_ids orelse return;
    bespoke.host.command_words(&rt.vm, program, ids.hesper, &rt.window.command_words);
}

fn greyhold_typed(rt: *WasmRuntime, line: []const u8) anyerror!void {
    const program = if (rt.program) |*p| p else return;
    const ids = greyhold_ids orelse return;
    var buf: [160]u8 = undefined;
    const reply = try valerius.type_line(&rt.vm, program, &greyhold_interp, ids, line, &buf);
    if (reply.text) |text| rt.set_banner(text);
    if (reply.fired) try rt.step_tick();
}

/// `[S]`: the appeal to Mercy, one typed line per press: learn the value, appeal to it, and
/// wait for spring. Before the hearing opens, a press steps the clock.
fn greyhold_solve(rt: *WasmRuntime) anyerror!void {
    const ids = greyhold_ids orelse return;
    if (rt.world.has_fact(ids.tam, try relation(rt, "Settled"), null)) return;
    if (rt.world.has_fact(ids.tam, try relation(rt, "Recruit"), null)) return rt.step_tick();
    if (rt.world.has_fact(ids.tam, try relation(rt, "Sentenced"), null)) return greyhold_typed(rt, "wait for spring");
    if (!rt.world.has_fact(ids.tam, try relation(rt, "Hearing"), null)) return rt.step_tick();
    // Judged but not yet answered: the judgement's handler runs on the next tick.
    if (rt.world.lookup_entity("StolenLoaf")) |loaf| {
        if (bespoke.host.dilemma(&rt.world, loaf).stage == .done) return rt.step_tick();
    }
    if (rt.world.lookup_entity("Mercy")) |mercy| {
        if (!bespoke.host.known_value(&rt.world, ids.hesper, ids.valerius, mercy).known) return greyhold_typed(rt, "ask valerius about mercy");
    } else return;
    return greyhold_typed(rt, "appeal to mercy");
}

// =============================================================================
// Tests: every deck's solve key reaches its proof's ending
// =============================================================================

const testing = std.testing;

fn load(index: u8) !*WasmRuntime {
    const rt = try testing.allocator.create(WasmRuntime);
    errdefer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, index);
    return rt;
}

fn unload(rt: *WasmRuntime) void {
    rt.deinit();
    testing.allocator.destroy(rt);
}

fn solve(rt: *WasmRuntime) !void {
    for (0..16) |_| try rt.trigger_catalyst();
}

/// Whether the fact holds in the world the player acts in: the branch while one is live.
fn holds(rt: *WasmRuntime, subject: []const u8, rel: []const u8, object: ?[]const u8) bool {
    const w = rt.active_world();
    const s = w.lookup_entity(subject) orelse return false;
    const r = w.lookup_relation(rel) orelse return false;
    const o: ?u32 = if (object) |n| (w.lookup_entity(n) orelse return false).to_int() else null;
    return w.find_first(s, r, o) != null;
}

test "P30-05: each deck runs its proof's script with its own player" {
    const players = [_][]const u8{ "Cat", "Tamsin", "Tamsin", "Player", "Tamsin", "Nell", "Mara", "Tamsin", "Tamsin", "Wren", "Maren", "Wren", "Ines", "Hesper", "Nell", "Audra", "Maren", "Maren", "CoveKeeper" };
    for (0..decks.len) |i| {
        const rt = try load(@intCast(i));
        defer unload(rt);
        try testing.expect(rt.program != null);
        try testing.expectEqualStrings(players[i], rt.world.get_entity_name(rt.player_entity).?);
        for (0..5) |_| try rt.step_tick();
    }
}

test "P30-05: the solve key plays each puzzle proof to its ending" {
    {
        const rt = try load(0);
        defer unload(rt);
        try solve(rt);
        try testing.expect(holds(rt, "Cat", "Carries", "Cheese"));
    }
    {
        const rt = try load(1);
        defer unload(rt);
        try solve(rt);
        try testing.expect(holds(rt, "Tamsin", "Placed", "FirstPlace"));
    }
    {
        const rt = try load(2);
        defer unload(rt);
        try solve(rt);
        try testing.expect(holds(rt, "Tamsin", "HasBerthTicket", null));
    }
    {
        const rt = try load(4);
        defer unload(rt);
        try solve(rt);
        try testing.expectEqualStrings("Wreckers Cellar", rt.world.get_entity_name(rt.vm.current_scene.?).?);
    }
    {
        const rt = try load(5);
        defer unload(rt);
        try solve(rt);
        try testing.expect(holds(rt, "Juno", "FreedFromTree", null));
        try testing.expect(holds(rt, "Ossie", "Carries", "ChargedJar"));
    }
    {
        const rt = try load(6);
        defer unload(rt);
        try solve(rt);
        try testing.expect(holds(rt, "CellLock", "Dissolved", null));
        try testing.expectEqualStrings("Solved. Press [R] to rewind and play it yourself.", rt.get_banner());
    }
}

test "P30-01: the sword deck duels with generated replies until someone wins" {
    const rt = try load(7);
    defer unload(rt);
    const tamsin = rt.world.lookup_entity("Tamsin").?;
    const pike = rt.world.lookup_entity("BosunPike").?;
    const challenge_rel = rt.world.lookup_relation("ActiveDuelChallenge").?;
    // Each prompt is a barb from Pike's dealt repertoire (D-082), and after a lost round he
    // presses on with a different one; repeating one barb let a single learned comeback win
    // every round.
    try rt.trigger_catalyst();
    var previous: u32 = 0;
    for (0..3) |round| {
        const open = bespoke.dialogue.view(&rt.world).?;
        const barb = rt.world.get_property(tamsin, challenge_rel).?;
        try testing.expect(barb != previous);
        try testing.expect(rt.world.has_fact(pike, sword_duel.heard_rel, barb));
        try testing.expectEqualStrings(sword_duel.challenge_text(EntityId.from_int(barb)).?, open.prompt);
        previous = barb;
        // The first choice is a joke, since she knows no comeback; the third fumble ends the
        // duel and the script's WinsDuel handler speaks Pike's line.
        try rt.trigger_catalyst();
        if (round < 2) try testing.expect(bespoke.dialogue.view(&rt.world) != null);
    }
    try testing.expect(bespoke.dialogue.view(&rt.world) == null);
    try testing.expectEqual(@as(u32, 1), sword_duel.wins(pike));
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Go back to your mop") != null);
    // A lost round teaches only the barb (D-078).
    try testing.expect(holds(rt, "Tamsin", "HeardBarb", null));
    try testing.expect(!holds(rt, "Tamsin", "MasteredComeback", null));
}

test "D-086: talking to a fencer duels it, and [S] rotates through all four" {
    const rt = try load(7);
    defer unload(rt);
    // The hooks are called directly here, so point the VM at this runtime's world first, as
    // the runtime does before it calls them.
    rt.bind();
    const dory = rt.world.lookup_entity("DoryQuill").?;
    try testing.expect(try sword_act(rt, .talk_to, dory));
    try testing.expectEqual(dory, sword_bout.opponent().?);
    // Other verbs, and talking mid-duel, fall through.
    try testing.expect(!(try sword_act(rt, .look_at, dory)));
    try testing.expect(!(try sword_act(rt, .talk_to, rt.world.lookup_entity("BosunPike").?)));
    sword_bout.clear();

    // With no duel decided, [S] duels Pike; each decided duel moves the rotation on, ending in
    // Vell's yard.
    for (SWORD_ROTATION, 0..) |name, i| {
        try sword_solve(rt);
        try testing.expectEqual(rt.world.lookup_entity(name).?, sword_bout.opponent().?);
        sword_bout.clear();
        try rt.world.remember(rt.world.lookup_entity(name).?, sword_duel.wins_rel, @intCast(1), 0);
        _ = i;
    }
    try testing.expectEqualStrings("Fencing Yard", rt.world.get_entity_name(rt.vm.current_scene.?).?);
}

test "P30-01: the Bell Tower deck weaves drafts from note keys and tolls the bell" {
    const rt = try load(10);
    defer unload(rt);
    // A note before choosing a target asks for one.
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'C' });
    try testing.expectEqual(@as(u8, 1), rt.distaff.len);
    rt.distaff.clear();
    try solve(rt);
    try testing.expect(bespoke.host.has_state(&rt.world, rt.world.lookup_entity("GreatBell").?, "Ringing"));
    try testing.expect(bespoke.host.has_state(&rt.world, rt.world.lookup_entity("Beacon").?, "Lit"));
    try testing.expectEqualStrings(bell_tower.BELFRY_SCENE, rt.world.get_entity_name(rt.vm.current_scene.?).?);
}

test "P30-01: the Copper Weathercock deck runs a branch world and closes its loop" {
    const rt = try load(9);
    defer unload(rt);
    const hv = rt.hypervisor.?;
    try testing.expect(hv.branch_active);
    // The branch is what the player acts in, and what the inspector and story read.
    try testing.expect(rt.active_world() != &rt.world);
    try testing.expect(rt.vm.world == rt.active_world());
    // The clock never runs backwards, including on the tick the branch collapses (D-071).
    var latest: u64 = 0;
    for (0..16) |_| {
        try rt.trigger_catalyst();
        try testing.expect(rt.clock() >= latest);
        latest = rt.clock();
    }
    try testing.expect(!hv.branch_active);
    try testing.expectEqual(bespoke.hypervisor.BranchCollapseState.resolved_and_merged, hv.collapse_state);
    try testing.expect(weathercock.evaluate_weathercock_solved(&rt.world));
    try testing.expect(rt.vm.world == &rt.world);
}

test "P30-01: a rewind restores the branch the timeline recorded" {
    const rt = try load(9);
    defer unload(rt);
    for (0..3) |_| try rt.step_tick();
    const branch_tick = rt.active_world().current_tick;
    try solve(rt);
    try testing.expect(!rt.hypervisor.?.branch_active);
    // Back to tick 2: the branch comes back, with its own clock and the countdown it had.
    rt.scrub_to_tick(2);
    const hv = rt.hypervisor.?;
    try testing.expect(hv.branch_active);
    try testing.expect(rt.active_world() != &rt.world);
    try testing.expect(rt.active_world().current_tick <= branch_tick);
    try testing.expect(hv.ticks_remaining() > 0);
    try testing.expect(!weathercock.evaluate_weathercock_solved(&rt.world));
}

test "P30-01: the Saltmarket deck picks a way in from the selector and takes the logbook" {
    const rt = try load(8);
    defer unload(rt);
    // Number key 2 answers the generated selector: Muscle.
    try testing.expectEqual(wasm.BrowserActionTag.dialogue_answered, try rt.dispatch_event(.{ .kind = .key_down, .key_code = '2' }));
    try testing.expect(holds(rt, "Muscle", "PathActive", null));
    try testing.expect(holds(rt, "CunningGate", "WaypointBlocked", null));
    try solve(rt);
    try testing.expect(holds(rt, "Tamsin", "Acquired", "Logbook"));
    try testing.expect(holds(rt, "Tamsin", "Solved", "Muscle"));
}

test "P30-05: the village's society reacts to the desperation catalyst" {
    const rt = try load(3);
    defer unload(rt);
    try rt.trigger_catalyst();
    var stole = false;
    for (0..120) |_| {
        try rt.step_tick();
        if (holds(rt, "Drifter", "StolenFrom", null) or holds(rt, "Drifter", "Arrested", null)) stole = true;
    }
    try testing.expect(stole);
}

test "P30-05: a verb on a prop fires the script's cue" {
    const rt = try load(6);
    defer unload(rt);
    rt.active_verb = .look_at;
    const proj = rt.projection();
    for (rt.spatial.hotspots.items) |hs| {
        if (!std.mem.eql(u8, hs.name, "GrogBarrel")) continue;
        const pt = proj.point(hs.pos.x, hs.pos.y);
        try testing.expectEqual(wasm.BrowserActionTag.cue_fired, try rt.dispatch_event(.{ .kind = .pointer_down, .x = pt.x, .y = pt.y }));
    }
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "strong enough to etch iron") != null);
}

fn energy(rt: *WasmRuntime) u64 {
    var samples: [2 * 4096]i16 = undefined;
    rt.audio.render_samples(&samples);
    var total: u64 = 0;
    for (samples) |v| total += @abs(v);
    return total;
}

fn energy_over(rt: *WasmRuntime, buffers: usize) u64 {
    var total: u64 = 0;
    for (0..buffers) |_| total += energy(rt);
    return total;
}

test "P30-01: decks play the engine synthesizer: the proof soundtrack and distaff notes" {
    {
        // The Tavern script declares no scores, so the deck plays the desktop soundtrack.
        const rt = try load(0);
        defer unload(rt);
        for (0..3) |_| try rt.step_tick();
        // The synthesizer fades music in, so several buffers are measured.
        try testing.expect(energy_over(rt, 6) > 0);
    }
    {
        const rt = try load(10);
        defer unload(rt);
        rt.audio.set_soundtrack(null);
        _ = energy_over(rt, 6);
        const quiet = energy_over(rt, 3);
        _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'C' });
        try testing.expect(energy_over(rt, 3) > quiet);
    }
}

test "each proof deck starts on its own unique arrangement" {
    var seen: [decks.len]u8 = undefined;
    for (0..decks.len) |i| {
        const rt = try load(@intCast(i));
        defer unload(rt);
        _ = energy_over(rt, 1);
        if (rt.audio.soundtrack != &art.soundtrack) {
            // Script-scored decks (such as The Tide Beacon) carry their own MML soundtrack.
            try testing.expect(rt.script_music != null and rt.script_music.?.has_scores());
            seen[i] = 255;
            continue;
        }
        const track = rt.audio.synth.current_track orelse return error.MissingTrack;
        seen[i] = track;
        for (0..i) |prev| {
            if (seen[prev] == track) {
                std.debug.print("\ndecks {d} and {d} share track {d}\n", .{ prev, i, track });
                return error.DuplicateDeckTrack;
            }
        }
    }
}

// =============================================================================
// Tests: the Pip-Spitting Green and the Borrowed Beard play by hand, with clicks only (D-094)
// =============================================================================

fn press(rt: *WasmRuntime, x: i32, y: i32) !wasm.BrowserActionTag {
    return rt.dispatch_event(.{ .kind = .pointer_down, .x = x, .y = y });
}

fn pick_verb(rt: *WasmRuntime, verb: wasm.WasmVerb) !void {
    // The desktop verb bar (D-097): buttons 68 wide, 74 apart, on the row 78 above the bottom.
    _ = try press(rt, 20 + @as(i32, @intFromEnum(verb)) * 74 + 30, wasm.CANVAS_HEIGHT - 68);
    try testing.expectEqual(verb, rt.active_verb);
}

/// Clicks where a person, prop, or mark named `name` is drawn on the stage.
fn click_on(rt: *WasmRuntime, name: []const u8) !wasm.BrowserActionTag {
    const proj = rt.projection();
    var slots: [WasmRuntime.MAX_ACTOR_SLOTS]WasmRuntime.ActorSlot = undefined;
    for (slots[0..rt.actor_slots(proj, &slots)]) |slot| {
        if (std.mem.eql(u8, rt.world.get_entity_name(slot.entity) orelse "", name)) return press(rt, slot.x, slot.y);
    }
    for (rt.spatial.hotspots.items) |hs| {
        if (!proj.shows(hs.room) or !std.mem.eql(u8, rt.world.get_entity_name(hs.entity) orelse "", name)) continue;
        const pt = proj.point(hs.pos.x, hs.pos.y);
        return press(rt, pt.x, pt.y);
    }
    for (rt.spatial.graph.waypoints.items) |wp| {
        if (!proj.shows(wp.room) or !std.mem.eql(u8, wp.name, name)) continue;
        const pt = proj.point(wp.pos.x, wp.pos.y);
        return press(rt, pt.x, pt.y);
    }
    std.debug.print("nothing named {s} is on stage; people drawn:", .{name});
    for (slots[0..rt.actor_slots(proj, &slots)]) |slot| std.debug.print(" {s}", .{rt.world.get_entity_name(slot.entity) orelse "?"});
    std.debug.print("\n", .{});
    return error.NotOnStage;
}

/// Clicks the item named `name` in the tray.
fn click_item(rt: *WasmRuntime, name: []const u8) !wasm.BrowserActionTag {
    var slots: [8]WasmRuntime.TraySlot = undefined;
    for (rt.tray_slots(&slots)) |slot| {
        if (std.mem.eql(u8, rt.world.get_entity_name(slot.item) orelse "", name)) return press(rt, slot.x + 2, slot.y + 2);
    }
    std.debug.print("{s} is not in the tray\n", .{name});
    return error.NotCarried;
}

/// Ticks until the fact holds, at most `limit` ticks, as a player waits for something to happen.
fn tick_until(rt: *WasmRuntime, subject: []const u8, rel: []const u8, object: ?[]const u8, limit: usize) !void {
    var n: usize = 0;
    while (!holds(rt, subject, rel, object)) : (n += 1) {
        if (n >= limit) {
            std.debug.print("{s} {s} {?s} never held; banner: {s}\n", .{ subject, rel, object, rt.get_banner() });
            return error.NeverHappened;
        }
        try rt.step_tick();
    }
}

fn tick_until_scene(rt: *WasmRuntime, scene: []const u8, limit: usize) !void {
    for (0..limit) |_| {
        if (std.mem.eql(u8, rt.world.get_entity_name(rt.vm.current_scene.?) orelse "", scene)) return;
        try rt.step_tick();
    }
    std.debug.print("never reached {s}; banner: {s}\n", .{ scene, rt.get_banner() });
    return error.NeverArrived;
}

test "D-094: the Borrowed Beard plays to the berth ticket with clicks alone" {
    const rt = try load(2);
    defer unload(rt);

    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "WashStand");
    try tick_until(rt, "Tamsin", "Carries", "HoneyPot", 30);

    // Wait for Rook to leave his door, then borrow the papers.
    for (0..90) |_| {
        if (!holds(rt, "CaptainRook", "AtHisDoor", null)) break;
        try rt.step_tick();
    }
    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "RookDoor");
    try tick_until(rt, "Tamsin", "Carries", "RookPapers", 30);

    // Charcoal has no use on its own, so a click takes it in hand; a click on the papers draws.
    try testing.expectEqual(wasm.BrowserActionTag.item_selected, try click_item(rt, "Charcoal"));
    try testing.expectEqual(wasm.WasmVerb.use_with, rt.active_verb);
    _ = try click_item(rt, "RookPapers");
    try tick_until(rt, "Tamsin", "PapersMarked", null, 3);

    // Down the stairs into the yard.
    try pick_verb(rt, .walk);
    _ = try click_on(rt, "Stairs");
    try tick_until_scene(rt, "Net Loft Yard", 40);

    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "RainBarrel");
    try tick_until(rt, "Tamsin", "Carries", "WateringCan", 30);

    try testing.expectEqual(wasm.BrowserActionTag.item_selected, try click_item(rt, "SailTape"));
    _ = try click_on(rt, "GateGap");
    for (0..30) |_| {
        if (rt.approach == null) break;
        try rt.step_tick();
    }
    try rt.step_tick();

    try testing.expectEqual(wasm.BrowserActionTag.item_selected, try click_item(rt, "WateringCan"));
    _ = try click_on(rt, "Bramble");
    try tick_until(rt, "GateGap", "GapHasFur", null, 30);

    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "GateGap");
    try tick_until(rt, "Tamsin", "Carries", "DogFur", 30);

    // The fur and the honey make the beard and leave the tray, in whichever order they are clicked.
    try testing.expectEqual(wasm.BrowserActionTag.item_selected, try click_item(rt, "HoneyPot"));
    _ = try click_item(rt, "DogFur");
    try tick_until(rt, "Tamsin", "Carries", "GreyBeard", 3);
    try testing.expect(!holds(rt, "Tamsin", "Carries", "DogFur"));
    try testing.expect(!holds(rt, "Tamsin", "Carries", "HoneyPot"));

    // The beard goes on Tamsin herself.
    try testing.expectEqual(wasm.BrowserActionTag.item_selected, try click_item(rt, "GreyBeard"));
    _ = try click_on(rt, "Tamsin");
    try tick_until(rt, "Tamsin", "Disguised", null, 3);

    // Out across the yard to the Harbour Office.
    try pick_verb(rt, .walk);
    _ = try click_on(rt, borrowed_beard.OFFICE_LANE);
    try tick_until_scene(rt, "Harbour Office", 60);

    try pick_verb(rt, .talk_to);
    _ = try click_on(rt, "PurserWick");
    for (0..30) |_| {
        if (bespoke.dialogue.view(rt.active_world()) != null) break;
        try rt.step_tick();
    }
    try testing.expect(bespoke.dialogue.view(rt.active_world()) != null);
    // Disguised, the first offered line is the claim to Rook's berth.
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = '1' });
    try tick_until(rt, "Tamsin", "HasBerthTicket", null, 5);

    // And back out of the office into the yard.
    try pick_verb(rt, .walk);
    _ = try click_on(rt, "OfficeDoor");
    try tick_until_scene(rt, "Net Loft Yard", 60);
}

test "D-094: the Pip-Spitting Green wins first place with clicks alone" {
    const rt = try load(1);
    defer unload(rt);

    // The cider and the conch each have a use of their own, so one click uses them.
    try testing.expectEqual(wasm.BrowserActionTag.cue_fired, try click_item(rt, "TreacleCider"));
    try testing.expectEqual(wasm.BrowserActionTag.cue_fired, try click_item(rt, "Conch"));
    try tick_until(rt, "JudgeMarrow", "Distracted", null, 3);

    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "Pegs");
    for (0..30) |_| {
        if (rt.approach == null) break;
        try rt.step_tick();
    }
    try rt.step_tick();

    // He has to be back at the chalk line to mark the throw, and the breeze has to be up.
    for (0..90) |_| {
        if (!holds(rt, "JudgeMarrow", "Distracted", null)) break;
        try rt.step_tick();
    }
    try testing.expect(!holds(rt, "JudgeMarrow", "Distracted", null));
    try tick_until(rt, "Wind", "Blowing", null, 80);

    // Then talk to the judge and spit.
    try pick_verb(rt, .talk_to);
    _ = try click_on(rt, "JudgeMarrow");
    for (0..30) |_| {
        if (bespoke.dialogue.view(rt.active_world()) != null) break;
        try rt.step_tick();
    }
    try testing.expect(bespoke.dialogue.view(rt.active_world()) != null);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = '1' });
    try tick_until(rt, "Tamsin", "Placed", "FirstPlace", 3);
}

test "D-129: the Green's [S] solution waits for the judge and wins first place" {
    const rt = try load(1);
    defer unload(rt);
    try solve(rt);
    try testing.expect(holds(rt, "Tamsin", "Placed", "FirstPlace"));
}

test "D-094: the Donkey of Lamp Point reaches the wreckers' chart with clicks alone" {
    const rt = try load(4);
    defer unload(rt);

    // Heading for the hatch while Cudgel's rope is free gets Tamsin shoved, and opens the window.
    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "CellarHatch");
    try tick_until(rt, "Cudgel", "DonkeyRetreating", null, 40);
    const retreating = rt.world.lookup_relation("DonkeyRetreating").?;
    const first_window = rt.world.find_first(try entity(rt, "Cudgel"), retreating, null).?.expires_at_tick;
    // The shove lands her on FallMark; a click before then is overridden by the shove.
    const fall = rt.spatial.graph.find_waypoint_in_room(try entity(rt, "Lamp Point"), "FallMark").?;
    for (0..20) |_| {
        if (rt.spatial.agents.get(rt.player_entity).?.current_wp == fall and !rt.spatial.is_moving(rt.player_entity)) break;
        try rt.step_tick();
    }

    // One click, one shove: the retreat window is still the first one, not renewed by a second.
    try testing.expectEqual(first_window, rt.world.find_first(try entity(rt, "Cudgel"), retreating, null).?.expires_at_tick);

    // While he ambles back to his post, haul the anchor into his rope line.
    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "OldAnchor");
    try tick_until(rt, "Cudgel", "TangledWith", "OldAnchor", 40);

    // With the rope caught, the hatch leads down to the cellar.
    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "CellarHatch");
    try tick_until_scene(rt, "Wreckers Cellar", 40);
    for (0..3) |_| try rt.step_tick();
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "can't get there") == null);

    // Tamsin stands in the cellar as soon as the room changes, so a LOOK straight away answers.
    try testing.expect(rt.spatial.graph.get_waypoint(rt.spatial.agents.get(rt.player_entity).?.current_wp).?.room == rt.vm.current_scene.?);
    try pick_verb(rt, .look_at);
    _ = try click_on(rt, "WreckersChart");
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "every reef on the Point") != null);

    // And back up the steps.
    try pick_verb(rt, .walk);
    _ = try click_on(rt, "CellarSteps");
    try tick_until_scene(rt, "Lamp Point", 40);
}

/// Uses carried `item` on `target`, the way a player does: a click on the item takes it in
/// hand, a click on the target walks over and uses it.
fn use_item_on(rt: *WasmRuntime, item: []const u8, target: []const u8) !void {
    try testing.expectEqual(wasm.BrowserActionTag.item_selected, try click_item(rt, item));
    _ = try click_on(rt, target);
    for (0..40) |_| {
        if (rt.approach == null) break;
        try rt.step_tick();
    }
    try rt.step_tick();
}

/// Talks to `who` and takes the first line offered, as a player picks it with the 1 key.
fn talk_and_choose_first(rt: *WasmRuntime, who: []const u8) !void {
    try pick_verb(rt, .talk_to);
    _ = try click_on(rt, who);
    for (0..40) |_| {
        if (bespoke.dialogue.view(rt.active_world()) != null) break;
        try rt.step_tick();
    }
    try testing.expect(bespoke.dialogue.view(rt.active_world()) != null);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = '1' });
    try rt.step_tick();
}

test "D-094: the Well of Three Tides plays to the end with clicks and the party buttons alone" {
    const rt = try load(5);
    defer unload(rt);
    try testing.expectEqualStrings("Nell", rt.world.get_entity_name(rt.player_entity).?);

    // 1912: the port goes down the well to Ossie, and the page says where it went.
    try use_item_on(rt, "CheapPort", "TideWell1912");
    try testing.expect(holds(rt, "Ossie", "Carries", "CheapPort"));
    try testing.expect(std.mem.indexOf(u8, rt.window.log_line(rt.window.log_count - 1), "Ossie's bucket in 1712") != null or
        std.mem.indexOf(u8, rt.window.log_line(rt.window.log_count - 2), "Ossie's bucket in 1712") != null);

    // 1712: Ossie seals it in the cornerstone box.
    try rt.deck_action(TIDES_OSSIE);
    try testing.expectEqualStrings("Charter Yard", rt.world.get_entity_name(rt.vm.current_scene.?).?);
    try use_item_on(rt, "CheapPort", "CornerstoneBox1712");
    try testing.expect(holds(rt, "CheapPort", "PortAgedIntoVinegar", null));

    // 1912: two centuries later the box gives up vinegar; it and the handbill go down the well.
    try rt.deck_action(TIDES_NELL);
    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "CornerstoneBox1912");
    try tick_until(rt, "Nell", "Carries", "AgedVinegar", 40);
    try use_item_on(rt, "AgedVinegar", "TideWell1912");
    try use_item_on(rt, "GullHandbill", "TideWell1912");
    try testing.expect(holds(rt, "Ossie", "Carries", "AgedVinegar"));
    try testing.expect(holds(rt, "Ossie", "Carries", "GullHandbill"));

    // 1712: charge the well, persuade Widow Fenn and Founder Gale.
    try rt.deck_action(TIDES_OSSIE);
    try testing.expectEqual(wasm.BrowserActionTag.item_selected, try click_item(rt, "AgedVinegar"));
    _ = try click_item(rt, "VoltaicJar");
    try tick_until(rt, "Ossie", "Carries", "ChargedJar", 3);
    try use_item_on(rt, "ChargedJar", "TideWell1712");
    try testing.expect(holds(rt, "Ossie", "WellPowered", null));
    try use_item_on(rt, "GullHandbill", "WidowFenn");
    try talk_and_choose_first(rt, "WidowFenn");
    try tick_until(rt, "WidowFenn", "BannerSewn", null, 5);
    try use_item_on(rt, "RedLeadPaint", "OrangeTree");
    try talk_and_choose_first(rt, "FounderGale");
    try tick_until(rt, "FounderGale", "TreeFelled", "OrangeTree", 5);

    // 2112: Juno is down from the tree; she gets leave to feed the gulls, takes the banner,
    // and wears it.
    try rt.deck_action(TIDES_JUNO);
    try tick_until(rt, "Juno", "FreedFromTree", null, 3);
    try testing.expect(!holds(rt, "Juno", "Trapped", null));
    try talk_and_choose_first(rt, "AdmiralSquall");
    try tick_until(rt, "Juno", "InYard", null, 5);
    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "GullBannerProp");
    try tick_until(rt, "Juno", "Carries", "GullBanner", 40);
    try testing.expectEqual(wasm.BrowserActionTag.item_selected, try click_item(rt, "GullBanner"));
    _ = try click_on(rt, "Juno");
    try tick_until(rt, "Juno", "TidesSolved", null, 5);
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "VICTORY") != null);
}

test "D-094: The Copper Weathercock plays to the end with clicks alone, through its doorways" {
    const rt = try load(9);
    defer unload(rt);
    try testing.expectEqualStrings("Wren", rt.world.get_entity_name(rt.player_entity).?);

    // The attic: take the weathercock, then down the stairs to the Customs House.
    try pick_verb(rt, .pick_up);
    _ = try click_on(rt, "WeathercockProp");
    try tick_until(rt, "Wren", "Carries", "Weathercock", 40);
    try pick_verb(rt, .walk);
    _ = try click_on(rt, "AtticStairs");
    try tick_until_scene(rt, "The Customs House", 40);

    // The Customs House: take the crank and open the sluice.
    try pick_verb(rt, .pick_up);
    _ = try click_on(rt, "CrankProp");
    try tick_until(rt, "Wren", "Carries", "Crank", 40);
    try use_item_on(rt, "Crank", "SluiceProp");
    try tick_until(rt, "Wren", "CustomsFlooded", null, 5);

    // Up the hill road to Beacon Hill. Offering the note before taking it delivers nothing.
    try pick_verb(rt, .walk);
    _ = try click_on(rt, "HillRoad");
    try tick_until_scene(rt, "Beacon Hill", 40);
    try talk_and_choose_first(rt, "HesterQuill");
    for (0..3) |_| try rt.step_tick();
    try testing.expect(!holds(rt, "Wren", "NoteDelivered", "HesterQuill"));

    // With the note from the post box in hand, Hester Quill takes it.
    try pick_verb(rt, .pick_up);
    _ = try click_on(rt, "NoteProp");
    try tick_until(rt, "Wren", "Carries", "Note", 40);
    try talk_and_choose_first(rt, "HesterQuill");
    try tick_until(rt, "Wren", "NoteDelivered", "HesterQuill", 5);
    try testing.expect(!holds(rt, "Wren", "Carries", "Note"));

    // The weathercock goes into the whirl, and the borrowed month folds back.
    try use_item_on(rt, "Weathercock", "FogWhirlProp");
    for (0..5) |_| {
        if (!rt.hypervisor.?.branch_active) break;
        try rt.step_tick();
    }
    try testing.expect(!rt.hypervisor.?.branch_active);
    try testing.expect(weathercock.evaluate_weathercock_solved(&rt.world));
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "folds back cleanly") != null);
}

test "D-094: The Saltmarket plays by clicks, walking only through the chosen gate" {
    const rt = try load(8);
    defer unload(rt);
    try testing.expectEqualStrings("Tamsin", rt.world.get_entity_name(rt.player_entity).?);
    // Number key 3 answers the selector: Crew locks the Cunning and Muscle gates.
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = '3' });
    try testing.expect(holds(rt, "Crew", "PathActive", null));
    try testing.expect(holds(rt, "MuscleGate", "WaypointBlocked", null));

    // Taking the logbook walks there through the Crew gate, the one left open.
    const scene = try entity(rt, "Saltmarket");
    const crew_gate = rt.spatial.graph.find_waypoint_in_room(scene, "CrewGate").?;
    const muscle_gate = rt.spatial.graph.find_waypoint_in_room(scene, "MuscleGate").?;
    try pick_verb(rt, .pick_up);
    _ = try click_on(rt, "Logbook");
    var through_crew = false;
    var through_muscle = false;
    for (0..40) |_| {
        const here = rt.spatial.get_current_waypoint(rt.player_entity).?;
        if (here == crew_gate) through_crew = true;
        if (here == muscle_gate) through_muscle = true;
        if (holds(rt, "Tamsin", "Acquired", "Logbook")) break;
        try rt.step_tick();
    }
    try testing.expect(through_crew and !through_muscle);
    try testing.expect(holds(rt, "Tamsin", "Solved", "Crew"));

    // A walk to a locked gate is refused and says so.
    try pick_verb(rt, .walk);
    _ = try click_on(rt, "CunningGate");
    try testing.expectEqualStrings("That way is blocked.", rt.get_banner());
}

test "P34-03: the Castle Fire Escape deck burns the tapestry, saves the door, and gets Wren out with [S]" {
    const rt = try load(11);
    defer unload(rt);
    try testing.expectEqualStrings("Wren", rt.world.get_entity_name(rt.player_entity).?);
    const wren = rt.player_entity;
    var presses: usize = 0;
    while (!bespoke.host.has_state(&rt.world, wren, "Escaped") and presses < 40) : (presses += 1) try rt.trigger_catalyst();
    for (0..20) |_| {
        if (bespoke.host.has_state(&rt.world, wren, "Escaped")) break;
        try rt.step_tick();
    }
    try testing.expect(bespoke.host.has_state(&rt.world, wren, "Escaped"));
    try testing.expect(!bespoke.host.has_state(&rt.world, wren, "Scorched"));
    try testing.expect(!bespoke.host.has_state(&rt.world, try entity(rt, "HiddenDoor"), "Burned"));
}

test "P34-03: the Castle Fire Escape plays by verbs and the page's buttons" {
    const rt = try load(11);
    defer unload(rt);
    const wren = rt.player_entity;
    // USE on the trough walks Wren there and fills the bucket.
    try pick_verb(rt, .use_with);
    _ = try click_on(rt, "Trough");
    for (0..20) |_| {
        if (bespoke.host.has_state(&rt.world, try entity(rt, "Bucket"), "Full")) break;
        try rt.step_tick();
    }
    try testing.expect(bespoke.host.has_state(&rt.world, try entity(rt, "Bucket"), "Full"));
    // The light button refuses away from the torch and says why.
    try rt.deck_action(KEEP_LIGHT);
    try testing.expectEqualStrings("Wren must stand at the torch.", rt.get_banner());
    // USE on the torch walks there; a second USE lights the tapestry.
    _ = try click_on(rt, "WallTorch");
    for (0..20) |_| {
        if (!rt.spatial.is_moving(wren)) break;
        try rt.step_tick();
    }
    _ = try click_on(rt, "WallTorch");
    for (0..20) |_| {
        if (!holds(rt, "DoorMark", "WaypointBlocked", null)) break;
        try rt.step_tick();
    }
    try testing.expect(!holds(rt, "DoorMark", "WaypointBlocked", null));
    // Throw the water on the door, let the fire die, and walk out.
    try rt.deck_action(KEEP_THROW);
    for (0..20) |_| try rt.step_tick();
    try pick_verb(rt, .walk);
    _ = try click_on(rt, "DoorMark");
    for (0..30) |_| {
        if (bespoke.host.has_state(&rt.world, wren, "Escaped")) break;
        try rt.step_tick();
    }
    try testing.expect(bespoke.host.has_state(&rt.world, wren, "Escaped"));
    try testing.expect(!bespoke.host.has_state(&rt.world, try entity(rt, "HiddenDoor"), "Burned"));
}

/// Types a line into the runtime the way a visitor does: Enter focuses the bar, each character
/// arrives as the page forwards it (after the key itself), and Enter submits; Escape then
/// leaves the bar, so the next line starts with Enter, as on desktop.
fn type_into(rt: *WasmRuntime, line: []const u8) !void {
    try testing.expectEqual(wasm.BrowserActionTag.command_edited, try rt.dispatch_event(.{ .kind = .key_down, .key_code = 13 }));
    for (line) |ch| {
        _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = std.ascii.toUpper(ch) });
        try testing.expectEqual(wasm.BrowserActionTag.command_edited, try rt.dispatch_event(.{ .kind = .char, .key_code = ch }));
    }
    try testing.expectEqual(wasm.BrowserActionTag.command_typed, try rt.dispatch_event(.{ .kind = .key_down, .key_code = 13 }));
    try testing.expectEqual(@as(usize, 0), rt.window.command_len);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 27 });
    try testing.expect(!rt.window.command_bar_focused);
}

fn larkspur_settle(rt: *WasmRuntime) !void {
    for (0..60) |_| {
        if (!rt.spatial.is_moving(rt.player_entity)) break;
        try rt.step_tick();
    }
}

test "P34-04: the Larkspur Observatory reaches its ending from typed commands" {
    const rt = try load(12);
    defer unload(rt);
    try testing.expectEqualStrings("Ines", rt.world.get_entity_name(rt.player_entity).?);
    const pell = try entity(rt, "Pell");
    const tick_before = rt.clock();

    // An ambiguous noun asks which; the answer is typed too.
    try type_into(rt, "examine the telescope");
    try testing.expect(std.mem.startsWith(u8, rt.get_banner(), "Which do you mean"));
    try type_into(rt, "log");
    // Taking the slip from afar is refused by where Ines stands.
    try type_into(rt, "take the slip");
    try testing.expectEqualStrings("The slip is in the Archive.", rt.get_banner());
    // The letters typed never reached the shortcuts: "s" did not solve, "n" did not step, and
    // space did not pause, so only the answered "log" moved the clock.
    try testing.expect(!rt.is_paused);
    try testing.expect(rt.clock() <= tick_before + 2);

    try type_into(rt, "go to the archive");
    try larkspur_settle(rt);
    try type_into(rt, "pick up the exposure slip");
    for (0..80) |_| {
        if (!rt.spatial.is_moving(rt.player_entity) and observatory.within_reach(&rt.spatial, rt.player_entity, pell)) break;
        try rt.step_tick();
    }
    try type_into(rt, "present the slip to the rival");
    for (0..3) |_| try rt.step_tick();
    try testing.expect(bespoke.host.has_state(&rt.world, pell, "Cornered"));
}

test "P34-04: the Larkspur Observatory's [S] types the playthrough to the end" {
    const rt = try load(12);
    defer unload(rt);
    const pell = try entity(rt, "Pell");
    var presses: usize = 0;
    while (!bespoke.host.has_state(&rt.world, pell, "Cornered") and presses < 60) : (presses += 1) try rt.trigger_catalyst();
    for (0..3) |_| try rt.step_tick();
    try testing.expect(bespoke.host.has_state(&rt.world, pell, "Cornered"));
}

test "D-094: the Borrowed Beard's [S] borrows the papers even when pressed before Rook reaches his door" {
    const rt = try load(2);
    defer unload(rt);
    try rt.trigger_catalyst(); // the wash stand
    var presses: usize = 0;
    while (!holds(rt, "Tamsin", "Carries", "RookPapers") and presses < 4) : (presses += 1) try rt.trigger_catalyst();
    try testing.expect(holds(rt, "Tamsin", "Carries", "RookPapers"));
}

test "D-095: the Pip-Spitting Green's spit action spits at once and closes the judge's offer" {
    const rt = try load(1);
    defer unload(rt);
    rt.bind();
    try testing.expect(try spit_act(rt, .talk_to, rt.world.lookup_entity("JudgeMarrow").?));
    try testing.expect(bespoke.dialogue.view(&rt.world) != null);
    try rt.deck_action(SPIT_ACTION);
    try testing.expect(bespoke.dialogue.view(&rt.world) == null);
    // Plain spit: a dribble.
    try testing.expect(holds(rt, "Tamsin", "Placed", "Dribble"));
}

test "D-096: the Pip-Spitting Green draws its wind sign, calm and blowing" {
    const rt = try load(1);
    defer unload(rt);
    rt.bind();
    // The desktop theme's sign (D-097): a streak across the field while the breeze blows.
    const streak = .{ 300, 250 };
    rt.render_frame();
    try testing.expect(!std.meta.eql(rt.pixel(streak[0], streak[1]), wasm.RgbaColor.sky_blue));
    try tick_until(rt, "Wind", "Blowing", null, 80);
    rt.render_frame();
    try testing.expect(std.meta.eql(rt.pixel(streak[0], streak[1]), wasm.RgbaColor.sky_blue));
}

test "P36-05: every browser deck draws the frame the desktop window draws for the same state" {
    for (0..decks.len) |i| {
        const rt = try load(@intCast(i));
        defer unload(rt);
        try rt.step_tick();
        try rt.step_tick();
        rt.render_frame();
        const browser = std.hash.Wyhash.hash(0, rt.framebuffer);

        // A desktop window drawing offscreen, given the deck's theme and the browser's view
        // state, must produce the same pixels from the same captured frame.
        var desk = try bespoke.display.DisplayWindow.init_offscreen(std.testing.io, wasm.CANVAS_WIDTH, wasm.CANVAS_HEIGHT);
        defer desk.deinit();
        const frame = rt.capture();
        const shown = rt.screen(frame);
        desk.theme = shown.theme;
        // Declared art and its clock are window state too (P46-03).
        desk.art = shown.art;
        desk.animation_clock = shown.animation_clock;
        desk.footer_text = shown.footer_text;
        desk.backdrop_color = shown.backdrop_color;
        desk.active_verb = shown.active_verb;
        desk.messages = shown.messages;
        desk.cue_banner_text = shown.cue_banner_text;
        desk.cue_banner_len = shown.cue_banner_len;
        desk.log_text = shown.log_text;
        desk.log_len = shown.log_len;
        desk.log_count = shown.log_count;
        desk.command_bar_enabled = shown.command_bar_enabled;
        desk.command_bar_focused = shown.command_bar_focused;
        desk.command_input = shown.command_input;
        desk.command_len = shown.command_len;
        desk.render_frame(frame, rt.is_paused);
        if (desk.frame_hash().? != browser) {
            std.debug.print("deck {d} draws differently in the browser\n", .{i});
            return error.FramesDiffer;
        }
    }
}

test "D-100: Brackwater Barbs walks to Vell's yard and the Drowned Lantern through their doorways" {
    const rt = try load(7);
    defer unload(rt);
    // The fencers start spread along the Tidewalk, as on desktop, not all on one mark.
    const tamsin_wp = rt.spatial.agents.get(try entity(rt, "Tamsin")).?.current_wp;
    try testing.expect(rt.spatial.agents.get(try entity(rt, "DoryQuill")).?.current_wp != tamsin_wp);
    try testing.expect(rt.spatial.agents.get(try entity(rt, "BosunPike")).?.current_wp != tamsin_wp);

    try pick_verb(rt, .walk);
    _ = try click_on(rt, "ToFencingYard");
    try tick_until_scene(rt, "Fencing Yard", 60);
    // The yard gate leads back.
    _ = try click_on(rt, "YardGate");
    try tick_until_scene(rt, "Tidewalk", 60);
    _ = try click_on(rt, "ToDrownedLantern");
    try tick_until_scene(rt, "Drowned Lantern", 60);
}

test "D-100: every mark of every deck is drawn on the stage, where a click can reach it" {
    var off: usize = 0;
    defer testing.expect(off == 0) catch @panic("marks off the stage");
    for (0..decks.len) |i| {
        const rt = try load(@intCast(i));
        defer unload(rt);
        for (rt.spatial.graph.waypoints.items) |wp| {
            const pt = rt.projection().point(wp.pos.x, wp.pos.y);
            if (pt.x < 20 or pt.x > wasm.CANVAS_WIDTH - 20) {
                std.debug.print("deck {d}: mark {s} is off the stage at x {d}\n", .{ i, wp.name, pt.x });
                off += 1;
            }
        }
    }
}

/// Deck indices the per-proof tests load by name, so a deck added after them moves nothing.
const VALERIUS_DECK: u8 = 13;
const LAMPLIGHTER_DECK: u8 = 14;

test "P46-05: the Lamplighter's [S] lights both lamps from the imported art's package" {
    const rt = try load(LAMPLIGHTER_DECK);
    defer unload(rt);
    try testing.expectEqualStrings("Nell", rt.world.get_entity_name(rt.player_entity).?);
    const program = &rt.program.?;
    try testing.expectEqual(@as(usize, 2), program.art.backdrops.len);
    const nell = try entity(rt, "Nell");
    var presses: usize = 0;
    while (!rt.world.has_fact(nell, try relation(rt, "RoundDone"), null) and presses < 20) : (presses += 1) try rt.trigger_catalyst();
    try testing.expect(rt.world.has_fact(nell, try relation(rt, "RoundDone"), null));
    try testing.expectEqualStrings(lamplighter.STEPS, rt.world.get_entity_name(rt.vm.current_scene.?).?);
}

test "P45-06: Valerius and the Bread's [S] types the appeal to Mercy through to spring" {
    const rt = try load(VALERIUS_DECK);
    defer unload(rt);
    try testing.expectEqualStrings("Hesper", rt.world.get_entity_name(rt.player_entity).?);
    const tam = try entity(rt, "Tam");
    var presses: usize = 0;
    while (!rt.world.has_fact(tam, try relation(rt, "Settled"), null) and presses < 40) : (presses += 1) try rt.trigger_catalyst();
    try testing.expect(rt.world.has_fact(tam, try relation(rt, "Settled"), null));
    try testing.expectEqualStrings("Greyhold Gate", rt.world.get_entity_name(rt.vm.current_scene.?).?);
    // The cast followed the script into spring.
    const wp = rt.spatial.get_current_waypoint(try entity(rt, "Valerius")).?;
    try testing.expectEqual(rt.vm.current_scene.?, rt.spatial.graph.get_waypoint(wp).?.room);
}

test "P45-06: an appeal Hesper has not earned is refused in the browser too" {
    const rt = try load(VALERIUS_DECK);
    defer unload(rt);
    for (0..3) |_| try rt.step_tick();
    try type_into(rt, "appeal to loyalty");
    try testing.expectEqualStrings("You don't know what moves them.", rt.get_banner());
}

// The Lamplighter's Round (P46-05): the desktop's layout. The lamps draw from the package's
// looks (D-181).
fn lamplighter_setup(rt: *WasmRuntime) anyerror!void {
    try lamplighter.configure(&rt.world, &rt.spatial, true);
    try rt.vm.transition_to_scene(try entity(rt, lamplighter.LANE));
    rt.bind();
}

const LAMPLIGHTER_SOLUTION = [_]Beat{
    .{ .note = "Nell asks Hobb for a taper before touching his oil.", .actions = &.{
        .{ .walk = .{ .actor = "Nell", .mark = "Doorstep" } }, .{ .settle = "Nell" },
        .{ .cue = .{ .name = "TalksTo", .actor = "Nell", .a = "Hobb" } }, .{ .ticks = 1 },
    } },
    .{ .note = "Nell fills her can at the oil cask.", .actions = &.{
        .{ .cue = .{ .name = "Uses", .actor = "Nell", .a = "OilCask" } }, .{ .ticks = 1 },
    } },
    .{ .note = "Nell lights the Tallow Lane lamp.", .actions = &.{
        .{ .walk = .{ .actor = "Nell", .mark = "LanePost" } }, .{ .settle = "Nell" },
        .{ .cue = .{ .name = "Uses", .actor = "Nell", .a = "LaneLamp" } }, .{ .ticks = 1 },
    } },
    .{ .note = "One fill lights one lamp, so Nell fills the can again.", .actions = &.{
        .{ .walk = .{ .actor = "Nell", .mark = "Doorstep" } }, .{ .settle = "Nell" },
        .{ .cue = .{ .name = "Uses", .actor = "Nell", .a = "OilCask" } }, .{ .ticks = 1 },
    } },
    .{ .note = "Nell goes through the archway to Market Steps.", .actions = &.{
        .{ .walk = .{ .actor = "Nell", .mark = "LaneEnd" } }, .{ .settle = "Nell" },
        .{ .scene = .{ .scene = lamplighter.STEPS, .actor = "Nell", .mark = "StepsFoot" } },
    } },
    .{ .note = "A jackdaw is nesting in the market lamp.", .actions = &.{
        .{ .walk = .{ .actor = "Nell", .mark = "StepsPost" } }, .{ .settle = "Nell" },
        .{ .cue = .{ .name = "Uses", .actor = "Nell", .a = "StepsLamp" } }, .{ .ticks = 1 },
    } },
    .{ .note = "Pike knows the jackdaw: only something shiny will shift her.", .actions = &.{
        .{ .walk = .{ .actor = "Nell", .mark = "FountainSide" } }, .{ .settle = "Nell" },
        .{ .cue = .{ .name = "TalksTo", .actor = "Nell", .a = "Pike" } }, .{ .ticks = 1 },
    } },
    .{ .note = "Back to Hobb, who parts with a brass thimble.", .actions = &.{
        .{ .scene = .{ .scene = lamplighter.LANE, .actor = "Nell", .mark = "LaneEnd" } },
        .{ .walk = .{ .actor = "Nell", .mark = "Doorstep" } }, .{ .settle = "Nell" },
        .{ .cue = .{ .name = "TalksTo", .actor = "Nell", .a = "Hobb" } }, .{ .ticks = 1 },
    } },
    .{ .note = "Nell offers Mrs Jessop the thimble.", .actions = &.{
        .{ .walk = .{ .actor = "Nell", .mark = "LaneEnd" } }, .{ .settle = "Nell" },
        .{ .scene = .{ .scene = lamplighter.STEPS, .actor = "Nell", .mark = "StepsFoot" } },
        .{ .walk = .{ .actor = "Nell", .mark = "StepsPost" } }, .{ .settle = "Nell" },
        .{ .cue = .{ .name = "Uses", .actor = "Nell", .a = "StepsLamp" } }, .{ .ticks = 1 },
    } },
    .{ .note = "Nell lights the market lamp, and Pike walks his round.", .actions = &.{
        .{ .cue = .{ .name = "Uses", .actor = "Nell", .a = "StepsLamp" } }, .{ .ticks = 3 },
        .{ .require = .{ .subject = "Nell", .relation = "RoundDone" } },
    } },
};

// =============================================================================
// The Long Gallery: watch Locked Studio read-only while Audra stays in Long Gallery
// =============================================================================

pub const GALLERY_DECK: u8 = 15;
pub const GALLERY_WATCH: u8 = 1;
var gallery_ids: ?long_gallery.Ids = null;

fn gallery_setup(rt: *WasmRuntime) anyerror!void {
    const ids = try long_gallery.configure(&rt.world, &rt.spatial);
    gallery_ids = ids;
    bespoke.host.place_waypoint(&rt.spatial, ids.window_wp, 8, 0);
    if (rt.spatial.graph.find_waypoint_in_room(ids.gallery, "Bench")) |bench| {
        bespoke.host.place_waypoint(&rt.spatial, bench, 22, 0);
    }
    bespoke.host.place_waypoint(&rt.spatial, ids.easel_wp, 4, 0);
    bespoke.host.place_waypoint(&rt.spatial, ids.corner_wp, 36, 0);
    _ = try rt.spatial.transition_actor(ids.audra, ids.gallery, ids.window_wp);
    _ = try rt.spatial.transition_actor(ids.corin, ids.studio, ids.easel_wp);
    _ = try rt.spatial.transition_actor(ids.pell, ids.studio, ids.corner_wp);
    if (rt.spatial.agents.getPtr(ids.corin)) |corin| corin.speed = 2;
    const rope = rt.world.lookup_entity("VelvetRope") orelse .none;
    const easel = rt.world.lookup_entity("EaselBoard") orelse .none;
    for (rt.spatial.hotspots.items) |*hs| {
        if (hs.entity == rope) hs.pos = .{ .x = 32, .y = -5 };
        if (hs.entity == easel) hs.pos = .{ .x = 8, .y = -5 };
    }
    try rt.vm.transition_to_scene(ids.gallery);
    rt.bind();
}

fn gallery_action(rt: *WasmRuntime, id: u8) anyerror!void {
    if (id != GALLERY_WATCH) return;
    const ids = gallery_ids orelse return;
    if (rt.watch_scene != null and rt.watch_scene.? == ids.studio) {
        rt.watch_scene = null;
        rt.set_banner("Back in the Long Gallery.");
    } else {
        rt.watch_scene = ids.studio;
        rt.set_banner("Watching the Locked Studio (read-only).");
    }
}

fn gallery_act(rt: *WasmRuntime, verb: wasm.WasmVerb, target: EntityId) anyerror!bool {
    const ids = gallery_ids orelse return false;
    const rope = rt.world.lookup_entity("VelvetRope") orelse .none;
    if (target == rope and verb != .look_at) {
        rt.set_banner("The velvet rope blocks the studio arch. Press [V] to watch through the transom.");
        return true;
    }
    if (target == ids.audra) {
        const found = rt.world.lookup_relation("Found");
        const caught = if (found) |f| rt.world.has_fact(ids.pell, f, null) else false;
        rt.set_banner(if (caught) "Audra listens at the arch: quiet next door now that Corin caught Pell." else "Audra hears footsteps crossing the Locked Studio. Press [V] to look.");
        return true;
    }
    return false;
}

fn gallery_solve(rt: *WasmRuntime) anyerror!void {
    const ids = gallery_ids orelse return;
    const found = rt.world.lookup_relation("Found") orelse try rt.world.intern_relation("Found", .set);
    if (!rt.world.has_fact(ids.pell, found, null)) {
        if (rt.watch_scene == null) {
            rt.watch_scene = ids.studio;
            rt.set_banner("Audra looks through the transom into the Locked Studio.");
            return;
        }
        var ticks: usize = 0;
        while (!rt.world.has_fact(ids.pell, found, null) and ticks < 25) : (ticks += 1) {
            try rt.step_tick();
        }
        rt.set_banner("Corin catches Pell at the easel while Audra stays next door.");
        return;
    }
    if (rt.watch_scene != null) {
        rt.watch_scene = null;
        rt.set_banner("Back in the Long Gallery. Press [V] to watch again, or [R] to rewind.");
        return;
    }
    rt.set_banner("Solved. Press [V] to watch the Locked Studio again, or [R] to rewind.");
}

// =============================================================================
// The Word Foundry: discover words from props and cast or test spell triples
// =============================================================================

pub const FOUNDRY_DECK: u8 = 16;
pub const FOUNDRY_COMBINE: u8 = 1;
pub const FOUNDRY_WORDS: u8 = 2;
var foundry_ids: ?word_foundry.Ids = null;

fn foundry_setup(rt: *WasmRuntime) anyerror!void {
    const ids = try word_foundry.configure(&rt.world, &rt.spatial);
    foundry_ids = ids;
    bespoke.host.place_waypoint(&rt.spatial, ids.bench_wp, 10, 0);
    if (rt.spatial.graph.find_waypoint_in_room(ids.scene, "Anvil")) |anvil| {
        bespoke.host.place_waypoint(&rt.spatial, anvil, 30, 0);
    }
    _ = try rt.spatial.transition_actor(ids.maren, ids.scene, ids.bench_wp);
    try rt.spatial.add_hotspot(ids.bellows, ids.scene, .{ .x = 6, .y = -6 }, 10, "Bellows", "Cracked leather bellows beside the forge mouth.");
    try rt.spatial.add_hotspot(ids.hearth, ids.scene, .{ .x = 15, .y = -6 }, 10, "ColdHearth", "Cold grate with grey ash and an iron kettle.");
    try rt.spatial.add_hotspot(ids.pattern_book, ids.scene, .{ .x = 24, .y = -6 }, 10, "PatternBook", "An open pattern book on an iron lectern.");
    try rt.spatial.add_hotspot(ids.crucible, ids.scene, .{ .x = 33, .y = -6 }, 10, "Crucible", "Heavy crucible bowl waiting for a three-word phrase.");
    try rt.vm.transition_to_scene(ids.scene);
    rt.bind();
    foundry_words_complete(rt);
}

fn foundry_after_tick(rt: *WasmRuntime) anyerror!void {
    if (foundry_ids == null) return;
    foundry_words_complete(rt);
}

fn foundry_words_complete(rt: *WasmRuntime) void {
    const program = if (rt.program) |*p| p else return;
    const ids = foundry_ids orelse return;
    bespoke.host.command_words(&rt.vm, program, ids.maren, &rt.window.command_words);
    const extras = [_][]const u8{
        "look", "combine", "cast", "words",
        "spark", "forge", "ember", "water", "bolt", "ward",
        "kindle", "quench", "bellows", "coldhearth", "patternbook", "crucible",
    };
    for (extras) |w| rt.window.command_words.add(w);
}

fn foundry_report_known(rt: *WasmRuntime, ids: word_foundry.Ids) void {
    const words = [_]struct { id: EntityId, label: []const u8 }{
        .{ .id = ids.spark, .label = "Spark" },
        .{ .id = ids.forge, .label = "Forge" },
        .{ .id = ids.ember, .label = "Ember" },
        .{ .id = ids.water, .label = "Water" },
        .{ .id = ids.bolt, .label = "Bolt" },
        .{ .id = ids.ward, .label = "Ward" },
    };
    var buf: [220]u8 = undefined;
    var list_buf: [96]u8 = undefined;
    var list_len: usize = 0;
    var count: usize = 0;
    for (words) |entry| {
        if (!bespoke.spell.knows(rt.active_world(), ids.maren, entry.id)) continue;
        if (count > 0 and list_len + 2 <= list_buf.len) {
            @memcpy(list_buf[list_len .. list_len + 2], ", ");
            list_len += 2;
        }
        if (list_len + entry.label.len <= list_buf.len) {
            @memcpy(list_buf[list_len .. list_len + entry.label.len], entry.label);
            list_len += entry.label.len;
        }
        count += 1;
    }
    const crucible_state: []const u8 = if (bespoke.host.has_state(rt.active_world(), ids.crucible, "Tempered"))
        "tempered"
    else if (bespoke.host.has_state(rt.active_world(), ids.crucible, "Glowing"))
        "glowing"
    else
        "cold";
    if (count == 0) {
        const msg = std.fmt.bufPrint(&buf, "Crucible is {s}. Look at Bellows, ColdHearth, and PatternBook to learn words.", .{crucible_state}) catch "No words yet.";
        rt.set_banner(msg);
    } else {
        const msg = std.fmt.bufPrint(&buf, "Crucible: {s}. Known ({d}/6): {s}. Use Crucible or [C] to combine.", .{ crucible_state, count, list_buf[0..list_len] }) catch "Known words listed.";
        rt.set_banner(msg);
    }
}

fn foundry_power_word(ids: word_foundry.Ids, code: u32) ?EntityId {
    return switch (code) {
        1 => ids.spark,
        2 => ids.forge,
        else => null,
    };
}

fn foundry_element_word(ids: word_foundry.Ids, code: u32) ?EntityId {
    return switch (code) {
        1 => ids.ember,
        2 => ids.water,
        else => null,
    };
}

fn foundry_form_word(ids: word_foundry.Ids, code: u32) ?EntityId {
    return switch (code) {
        1 => ids.bolt,
        2 => ids.ward,
        else => null,
    };
}

fn foundry_open_combiner(rt: *WasmRuntime) anyerror!void {
    const ids = foundry_ids orelse return;
    if (bespoke.dialogue.view(&rt.world) != null) return;
    const world = rt.active_world();
    var choices: [3]bespoke.dialogue.Choice = undefined;
    var n: usize = 0;
    if (bespoke.spell.knows(world, ids.maren, ids.spark)) {
        choices[n] = .{ .text = "Power: Spark", .action = 0x101 };
        n += 1;
    }
    if (bespoke.spell.knows(world, ids.maren, ids.forge)) {
        choices[n] = .{ .text = "Power: Forge", .action = 0x102 };
        n += 1;
    }
    if (n == 0) {
        rt.set_banner("No Power words learned yet. Look at the Bellows first.");
        return;
    }
    choices[n] = .{ .text = "Step back.", .action = 0 };
    n += 1;
    _ = try rt.vm.open_generated_dialogue(ids.crucible, "1/3 Choose a Power word to speak:", choices[0..n]);
}

fn foundry_choice(rt: *WasmRuntime, action: u32) anyerror!void {
    const ids = foundry_ids orelse return;
    const world = rt.active_world();
    if (action == 0) {
        rt.set_banner("Maren steps back from the crucible.");
        return;
    }
    const stage = action & 0xF00;
    if (stage == 0x100) {
        const p = action & 0xF;
        const pname = if (p == 1) "Spark" else "Forge";
        var choices: [3]bespoke.dialogue.Choice = undefined;
        var n: usize = 0;
        if (bespoke.spell.knows(world, ids.maren, ids.ember)) {
            choices[n] = .{ .text = "Element: Ember", .action = 0x200 | (p << 4) | 1 };
            n += 1;
        }
        if (bespoke.spell.knows(world, ids.maren, ids.water)) {
            choices[n] = .{ .text = "Element: Water", .action = 0x200 | (p << 4) | 2 };
            n += 1;
        }
        if (n == 0) {
            rt.set_banner("No Element words learned yet. Look at the ColdHearth first.");
            return;
        }
        choices[n] = .{ .text = "Cancel.", .action = 0 };
        n += 1;
        var pbuf: [64]u8 = undefined;
        const prompt = std.fmt.bufPrint(&pbuf, "2/3 Pair {s} with an Element:", .{pname}) catch "2/3 Choose an Element:";
        _ = try rt.vm.open_generated_dialogue(ids.crucible, prompt, choices[0..n]);
        return;
    }
    if (stage == 0x200) {
        const p = (action >> 4) & 0xF;
        const e = action & 0xF;
        const pname = if (p == 1) "Spark" else "Forge";
        const ename = if (e == 1) "Ember" else "Water";
        var choices: [3]bespoke.dialogue.Choice = undefined;
        var n: usize = 0;
        if (bespoke.spell.knows(world, ids.maren, ids.bolt)) {
            choices[n] = .{ .text = "Form: Bolt", .action = 0x300 | (p << 8) | (e << 4) | 1 };
            n += 1;
        }
        if (bespoke.spell.knows(world, ids.maren, ids.ward)) {
            choices[n] = .{ .text = "Form: Ward", .action = 0x300 | (p << 8) | (e << 4) | 2 };
            n += 1;
        }
        if (n == 0) {
            rt.set_banner("No Form words learned yet. Look at the PatternBook first.");
            return;
        }
        choices[n] = .{ .text = "Cancel.", .action = 0 };
        n += 1;
        var pbuf: [64]u8 = undefined;
        const prompt = std.fmt.bufPrint(&pbuf, "3/3 Shape {s} + {s} with a Form:", .{ pname, ename }) catch "3/3 Choose a Form:";
        _ = try rt.vm.open_generated_dialogue(ids.crucible, prompt, choices[0..n]);
        return;
    }
    if (stage == 0x300) {
        const p = foundry_power_word(ids, (action >> 8) & 0xF) orelse return;
        const e = foundry_element_word(ids, (action >> 4) & 0xF) orelse return;
        const f = foundry_form_word(ids, action & 0xF) orelse return;
        try foundry_cast_triple(rt, p, e, f);
    }
}

fn foundry_act(rt: *WasmRuntime, verb: wasm.WasmVerb, target: EntityId) anyerror!bool {
    const program = if (rt.program) |*p| p else return false;
    const ids = foundry_ids orelse return false;
    if (target == ids.crucible) {
        if (verb == .look_at) {
            foundry_report_known(rt, ids);
            return true;
        }
        if (verb == .use_with or verb == .talk_to) {
            try foundry_open_combiner(rt);
            return true;
        }
        return false;
    }
    if (verb == .use_with or verb == .talk_to) {
        if (target == ids.bellows or target == ids.hearth or target == ids.pattern_book) {
            _ = try rt.vm.fire_cue(program, "LooksAt", ids.maren, target, null);
            try rt.step_tick();
            return true;
        }
    }
    return false;
}

fn foundry_cast_triple(rt: *WasmRuntime, p: EntityId, e: EntityId, f: EntityId) anyerror!void {
    const program = if (rt.program) |*prog| prog else return;
    const ids = foundry_ids orelse return;
    const outcome = try bespoke.host.combine(&rt.vm, program, ids.maren, p, e, f, ids.crucible);
    switch (outcome) {
        .cast => try rt.step_tick(),
        .refused => |why| {
            const world = rt.active_world();
            const p_name = world.get_entity_name(p) orelse "?";
            const e_name = world.get_entity_name(e) orelse "?";
            const f_name = world.get_entity_name(f) orelse "?";
            const crucible_state: []const u8 = if (bespoke.host.has_state(world, ids.crucible, "Tempered"))
                "tempered"
            else if (bespoke.host.has_state(world, ids.crucible, "Glowing"))
                "glowing"
            else
                "cold";
            var buf: [192]u8 = undefined;
            const msg = switch (why) {
                .no_such_spell => std.fmt.bufPrint(&buf, "Fizzle: no spell joins {s}, {s}, {s}. The crucible stays {s}.", .{ p_name, e_name, f_name, crucible_state }),
                else => std.fmt.bufPrint(&buf, "Fizzle ({s}) on {s}, {s}, {s}. The crucible stays {s}.", .{ why.label(), p_name, e_name, f_name, crucible_state }),
            } catch "Fizzle: crucible unchanged.";
            rt.set_banner(msg);
        },
    }
}

fn foundry_cast_name(rt: *WasmRuntime, name: []const u8) anyerror!void {
    const program = if (rt.program) |*prog| prog else return;
    const ids = foundry_ids orelse return;
    const outcome = try bespoke.host.cast(&rt.vm, program, ids.maren, name, ids.crucible);
    switch (outcome) {
        .cast => try rt.step_tick(),
        .refused => |why| {
            var buf: [160]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Fizzle ({s}): crucible unchanged ({d} facts).", .{ why.label(), rt.world.fact_count() }) catch "Fizzle: crucible unchanged.";
            rt.set_banner(msg);
        },
    }
}

fn foundry_action(rt: *WasmRuntime, id: u8) anyerror!void {
    const ids = foundry_ids orelse return;
    switch (id) {
        FOUNDRY_COMBINE => try foundry_open_combiner(rt),
        FOUNDRY_WORDS => foundry_report_known(rt, ids),
        else => {},
    }
}

fn foundry_lookup_word(ids: word_foundry.Ids, token: []const u8) ?EntityId {
    if (std.ascii.eqlIgnoreCase(token, "spark")) return ids.spark;
    if (std.ascii.eqlIgnoreCase(token, "forge")) return ids.forge;
    if (std.ascii.eqlIgnoreCase(token, "ember")) return ids.ember;
    if (std.ascii.eqlIgnoreCase(token, "water")) return ids.water;
    if (std.ascii.eqlIgnoreCase(token, "bolt")) return ids.bolt;
    if (std.ascii.eqlIgnoreCase(token, "ward")) return ids.ward;
    return null;
}

fn foundry_word_tier(ids: word_foundry.Ids, w: EntityId) u2 {
    if (w == ids.spark or w == ids.forge) return 0; // Power
    if (w == ids.ember or w == ids.water) return 1; // Element
    return 2; // Form
}

fn foundry_typed(rt: *WasmRuntime, line: []const u8) anyerror!void {
    const program = if (rt.program) |*p| p else return;
    const ids = foundry_ids orelse return;
    var tokens: [6][]const u8 = undefined;
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, line, " \t,.:;");
    while (it.next()) |tok| {
        if (n == tokens.len) break;
        tokens[n] = tok;
        n += 1;
    }
    if (n == 0) {
        foundry_report_known(rt, ids);
        return;
    }
    if (n == 1 and (std.ascii.eqlIgnoreCase(tokens[0], "words") or std.ascii.eqlIgnoreCase(tokens[0], "known"))) {
        foundry_report_known(rt, ids);
        return;
    }
    for (tokens[0..n]) |tok| {
        if (std.ascii.eqlIgnoreCase(tok, "bellows")) {
            _ = try rt.vm.fire_cue(program, "LooksAt", ids.maren, ids.bellows, null);
            try rt.step_tick();
            return;
        }
        if (std.ascii.eqlIgnoreCase(tok, "coldhearth") or std.ascii.eqlIgnoreCase(tok, "hearth")) {
            _ = try rt.vm.fire_cue(program, "LooksAt", ids.maren, ids.hearth, null);
            try rt.step_tick();
            return;
        }
        if (std.ascii.eqlIgnoreCase(tok, "patternbook") or std.ascii.eqlIgnoreCase(tok, "book") or std.ascii.eqlIgnoreCase(tok, "pattern")) {
            _ = try rt.vm.fire_cue(program, "LooksAt", ids.maren, ids.pattern_book, null);
            try rt.step_tick();
            return;
        }
        if (std.ascii.eqlIgnoreCase(tok, "crucible")) {
            foundry_report_known(rt, ids);
            return;
        }
    }
    var start: usize = 0;
    if (std.ascii.eqlIgnoreCase(tokens[0], "combine") or std.ascii.eqlIgnoreCase(tokens[0], "cast")) start = 1;
    const args = tokens[start..n];
    if (args.len == 1) {
        if (std.ascii.eqlIgnoreCase(args[0], "kindle") or std.ascii.eqlIgnoreCase(args[0], "quench")) {
            return foundry_cast_name(rt, args[0]);
        }
        if (foundry_lookup_word(ids, args[0])) |w| {
            const tier_name = switch (foundry_word_tier(ids, w)) {
                0 => "Power",
                1 => "Element",
                else => "Form",
            };
            var buf: [160]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{s} is a {s} word. Combine Power + Element + Form (e.g. type 3 words or press [C]).", .{ rt.active_world().get_entity_name(w) orelse args[0], tier_name }) catch "Combine three words.";
            rt.set_banner(msg);
            return;
        }
    }
    if (args.len == 2) {
        if (foundry_lookup_word(ids, args[0])) |w0| {
            if (foundry_lookup_word(ids, args[1])) |w1| {
                const t0 = foundry_word_tier(ids, w0);
                const t1 = foundry_word_tier(ids, w1);
                var missing: []const u8 = "third";
                if (t0 != 0 and t1 != 0) missing = "Power (Spark or Forge)";
                if (t0 != 1 and t1 != 1) missing = "Element (Ember or Water)";
                if (t0 != 2 and t1 != 2) missing = "Form (Bolt or Ward)";
                var buf: [176]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "{s} + {s} still needs a {s} word. Type all three words or press [C].", .{
                    rt.active_world().get_entity_name(w0) orelse args[0],
                    rt.active_world().get_entity_name(w1) orelse args[1],
                    missing,
                }) catch "A spell needs Power, Element, and Form.";
                rt.set_banner(msg);
                return;
            }
        }
    }
    if (args.len == 3) {
        if (foundry_lookup_word(ids, args[0])) |w0| {
            if (foundry_lookup_word(ids, args[1])) |w1| {
                if (foundry_lookup_word(ids, args[2])) |w2| {
                    return foundry_cast_triple(rt, w0, w1, w2);
                }
            }
        }
    }
    rt.set_banner("Try: look bellows, words, combine forge ember bolt, or press [C].");
}

fn foundry_solve(rt: *WasmRuntime) anyerror!void {
    const program = if (rt.program) |*p| p else return;
    const ids = foundry_ids orelse return;
    if (!bespoke.spell.knows(rt.active_world(), ids.maren, ids.spark)) {
        _ = try rt.vm.fire_cue(program, "LooksAt", ids.maren, ids.bellows, null);
        try rt.step_tick();
        return;
    }
    if (!bespoke.spell.knows(rt.active_world(), ids.maren, ids.ember)) {
        _ = try rt.vm.fire_cue(program, "LooksAt", ids.maren, ids.hearth, null);
        try rt.step_tick();
        return;
    }
    if (!bespoke.spell.knows(rt.active_world(), ids.maren, ids.bolt)) {
        _ = try rt.vm.fire_cue(program, "LooksAt", ids.maren, ids.pattern_book, null);
        try rt.step_tick();
        return;
    }
    if (!bespoke.host.has_state(rt.active_world(), ids.crucible, "Glowing")) {
        return foundry_cast_triple(rt, ids.forge, ids.ember, ids.bolt);
    }
    if (!bespoke.host.has_state(rt.active_world(), ids.crucible, "Tempered")) {
        return foundry_cast_triple(rt, ids.spark, ids.water, ids.ward);
    }
    rt.set_banner("Solved: Kindle and Quench both fired. Press [C] to test any triple or [R] to rewind.");
}

// =============================================================================
// The Cinder Table: private hands and scored plays over 4 rounds (12 cards)
// =============================================================================

pub const CINDER_DECK: u8 = 17;
pub const CINDER_NEXT_ROUND: u8 = 1;
var cinder_ids: ?cinder_table.Ids = null;
var cinder_last_count: usize = 0;

fn cinder_setup(rt: *WasmRuntime) anyerror!void {
    const ids = try cinder_table.configure(&rt.world, &rt.spatial);
    cinder_ids = ids;
    cinder_last_count = 0;
    bespoke.host.place_waypoint(&rt.spatial, ids.bench_wp, 10, 0);
    if (rt.spatial.graph.find_waypoint_in_room(ids.scene, "Stove")) |stove| {
        bespoke.host.place_waypoint(&rt.spatial, stove, 30, 0);
        _ = try rt.spatial.transition_actor(ids.ines, ids.scene, stove);
    }
    const center_wp = try rt.spatial.graph.add_waypoint(ids.scene, 20, 0, "TableSeat");
    _ = rt.spatial.graph.connect(ids.bench_wp, center_wp, null) catch {};
    _ = try rt.spatial.transition_actor(ids.maren, ids.scene, ids.bench_wp);
    _ = try rt.spatial.transition_actor(ids.ossic, ids.scene, center_wp);
    const tally = rt.world.lookup_entity("TallyBoard") orelse .none;
    const tokens = rt.world.lookup_entity("Tokens") orelse .none;
    if (tally != .none) try rt.spatial.add_hotspot(tally, ids.scene, .{ .x = 4, .y = -6 }, 10, "TallyBoard", "Scored trick tally and public void declarations.");
    if (tokens != .none) try rt.spatial.add_hotspot(tokens, ids.scene, .{ .x = 36, .y = -6 }, 10, "Tokens", "Private hand counters for Maren, Ossic, and Ines.");
    try rt.vm.transition_to_scene(ids.scene);
    rt.bind();
}

const PlayedSummary = struct {
    count: usize = 0,
    last_actor: EntityId = .none,
    last_card: EntityId = .none,
};

fn cinder_card_label(raw: []const u8) []const u8 {
    const table = [_]struct { raw: []const u8, label: []const u8 }{
        .{ .raw = "SaltOne", .label = "Salt 1" },
        .{ .raw = "SaltTwo", .label = "Salt 2" },
        .{ .raw = "SaltThree", .label = "Salt 3" },
        .{ .raw = "SaltFour", .label = "Salt 4" },
        .{ .raw = "ReedOne", .label = "Reed 1" },
        .{ .raw = "ReedTwo", .label = "Reed 2" },
        .{ .raw = "ReedThree", .label = "Reed 3" },
        .{ .raw = "ReedFour", .label = "Reed 4" },
        .{ .raw = "CinderOne", .label = "Cinder 1" },
        .{ .raw = "CinderTwo", .label = "Cinder 2" },
        .{ .raw = "CinderThree", .label = "Cinder 3" },
        .{ .raw = "CinderFour", .label = "Cinder 4" },
    };
    for (table) |entry| {
        if (std.mem.eql(u8, entry.raw, raw)) return entry.label;
    }
    return raw;
}

fn cinder_play_note(raw: []const u8) []const u8 {
    if (std.mem.eql(u8, raw, "SaltOne")) return " (opening lead, score 6)";
    if (std.mem.eql(u8, raw, "ReedOne")) return " (no Cinder left; Void in Cinder declared)";
    if (std.mem.eql(u8, raw, "CinderTwo")) return " (score raised 4 -> 6 by Ossic's void)";
    return "";
}

fn cinder_played_summary(world: *const bespoke.World) PlayedSummary {
    const played_rel = world.lookup_relation("Played") orelse return .{};
    const slice = world.facts.slice();
    const subjects = slice.items(.subject);
    const relations = slice.items(.relation);
    const objects = slice.items(.object_or_value);
    var out = PlayedSummary{};
    for (0..world.facts.len) |i| {
        if (relations[i] != played_rel) continue;
        out.count += 1;
        out.last_actor = subjects[i];
        out.last_card = EntityId.from_int(objects[i]);
    }
    return out;
}

fn cinder_after_tick(rt: *WasmRuntime) anyerror!void {
    const ids = cinder_ids orelse return;
    _ = ids;
    const summary = cinder_played_summary(rt.active_world());
    if (summary.count <= cinder_last_count) {
        cinder_last_count = summary.count;
        return;
    }
    cinder_last_count = summary.count;
    if (summary.last_actor == .none or summary.last_card == .none) return;
    const world = rt.active_world();
    const actor = world.get_entity_name(summary.last_actor) orelse "?";
    const card_raw = world.get_entity_name(summary.last_card) orelse "?";
    const card = cinder_card_label(card_raw);
    const round = (summary.count + 2) / 3;
    var buf: [200]u8 = undefined;
    const msg = if (summary.count >= cinder_table.TOTAL_PLAYS)
        std.fmt.bufPrint(&buf, "Round {d}: {s} plays {s}. Table finished (12/12 cards played).", .{ round, actor, card }) catch "Table finished."
    else
        std.fmt.bufPrint(&buf, "Round {d}: {s} plays {s}{s}.", .{ round, actor, card, cinder_play_note(card_raw) }) catch "Card played.";
    rt.set_banner(msg);
}

fn cinder_action(rt: *WasmRuntime, id: u8) anyerror!void {
    if (id != CINDER_NEXT_ROUND) return;
    const before = cinder_played_summary(rt.active_world()).count;
    if (before >= cinder_table.TOTAL_PLAYS) {
        rt.set_banner("All 4 rounds complete (12 cards played). Press [R] to rewind.");
        return;
    }
    const turn_rel = rt.active_world().lookup_relation("Turn");
    const maren = if (cinder_ids) |ids| ids.maren else EntityId.none;
    for (0..3) |step_i| {
        if (cinder_played_summary(rt.active_world()).count >= cinder_table.TOTAL_PLAYS) break;
        if (step_i > 0 and turn_rel != null and maren != .none and rt.active_world().has_fact(maren, turn_rel.?, null)) break;
        try rt.step_tick();
    }
}

fn cinder_seat_hand_banner(rt: *WasmRuntime, seat: EntityId, seat_name: []const u8) void {
    const world = rt.active_world();
    const knows_rel = world.lookup_relation("Knows") orelse return;
    const sl = world.facts.slice();
    const subj = sl.items(.subject);
    const rel = sl.items(.relation);
    const obj = sl.items(.object_or_value);
    var list_buf: [96]u8 = undefined;
    var list_len: usize = 0;
    var count: usize = 0;
    for (0..world.facts.len) |i| {
        if (rel[i] != knows_rel or subj[i] != seat) continue;
        const card = cinder_card_label(world.get_entity_name(EntityId.from_int(obj[i])) orelse "?");
        if (count > 0 and list_len + 2 <= list_buf.len) {
            @memcpy(list_buf[list_len .. list_len + 2], ", ");
            list_len += 2;
        }
        if (list_len + card.len <= list_buf.len) {
            @memcpy(list_buf[list_len .. list_len + card.len], card);
            list_len += card.len;
        }
        count += 1;
    }
    var buf: [192]u8 = undefined;
    const msg = if (count == 0)
        std.fmt.bufPrint(&buf, "{s}'s private hand is empty.", .{seat_name}) catch "Hand empty."
    else
        std.fmt.bufPrint(&buf, "{s}'s private hand ({d}): {s}.", .{ seat_name, count, list_buf[0..list_len] }) catch "Hand shown.";
    rt.set_banner(msg);
}

fn cinder_act(rt: *WasmRuntime, verb: wasm.WasmVerb, target: EntityId) anyerror!bool {
    _ = verb;
    const world = rt.active_world();
    const tally = world.lookup_entity("TallyBoard") orelse .none;
    const tokens = world.lookup_entity("Tokens") orelse .none;
    const ids = cinder_ids orelse return false;
    var buf: [192]u8 = undefined;
    if (target == ids.maren or target == ids.ossic or target == ids.ines) {
        const sname = world.get_entity_name(target) orelse "?";
        cinder_seat_hand_banner(rt, target, sname);
        return true;
    }
    if (target == tally) {
        const played = cinder_played_summary(world).count;
        const void_rel = world.lookup_relation("Void");
        const cinder = world.lookup_entity("Cinder");
        const ossic_void = if (void_rel != null and cinder != null) world.has_fact(ids.ossic, void_rel.?, cinder.?.to_int()) else false;
        const msg = std.fmt.bufPrint(&buf, "Tally: {d}/{d} cards played. {s}", .{
            played,
            cinder_table.TOTAL_PLAYS,
            if (ossic_void) "Ossic is void in Cinder." else "No public voids yet.",
        }) catch "Tally read.";
        rt.set_banner(msg);
        return true;
    }
    if (target == tokens) {
        const knows_rel = world.lookup_relation("Knows") orelse return false;
        const count_hand = struct {
            fn of(w: *const bespoke.World, r: bespoke.RelationKind, who: EntityId) usize {
                var n: usize = 0;
                const sl = w.facts.slice();
                const subj = sl.items(.subject);
                const rel = sl.items(.relation);
                for (0..w.facts.len) |i| {
                    if (rel[i] == r and subj[i] == who) n += 1;
                }
                return n;
            }
        }.of;
        const msg = std.fmt.bufPrint(&buf, "Private cards remaining: Maren {d}, Ossic {d}, Ines {d}.", .{
            count_hand(world, knows_rel, ids.maren),
            count_hand(world, knows_rel, ids.ossic),
            count_hand(world, knows_rel, ids.ines),
        }) catch "Private hands counted.";
        rt.set_banner(msg);
        return true;
    }
    return false;
}

fn cinder_solve(rt: *WasmRuntime) anyerror!void {
    if (cinder_played_summary(rt.active_world()).count >= cinder_table.TOTAL_PLAYS) {
        rt.set_banner("All 4 rounds complete (12 cards played). Press [R] to rewind.");
        return;
    }
    try rt.step_tick();
}

test "P44-06: Long Gallery toggles Locked Studio read-only in the browser" {
    const rt = try load(GALLERY_DECK);
    defer unload(rt);
    try testing.expectEqualStrings("Long Gallery", rt.capture().current_scene[0..rt.capture().current_scene_len]);
    try rt.deck_action(GALLERY_WATCH);
    try testing.expectEqualStrings("Locked Studio", rt.capture().current_scene[0..rt.capture().current_scene_len]);
    try rt.trigger_catalyst();
    try testing.expect(holds(rt, "Pell", "Found", null));
    try rt.deck_action(GALLERY_WATCH);
    try testing.expectEqualStrings("Long Gallery", rt.capture().current_scene[0..rt.capture().current_scene_len]);
}

test "P44-04: Word Foundry discovers words, refuses an unknown triple, and casts Kindle and Quench" {
    const rt = try load(FOUNDRY_DECK);
    defer unload(rt);
    const before = rt.world.fact_count();
    try rt.deck_action(FOUNDRY_COMBINE);
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Bellows") != null);
    try testing.expectEqual(before, rt.world.fact_count());

    try type_into(rt, "spark ember");
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Form") != null);

    var step: usize = 0;
    while (!holds(rt, "Crucible", "Tempered", null) and step < 10) : (step += 1) try rt.trigger_catalyst();
    try testing.expect(holds(rt, "Crucible", "Glowing", null));
    try testing.expect(holds(rt, "Crucible", "Tempered", null));

    const settled = rt.world.fact_count();
    try type_into(rt, "combine spark ember bolt");
    try testing.expectEqual(settled, rt.world.fact_count());
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Fizzle") != null);

    // Three-step interactive crucible chooser opens and resolves cleanly without adding spell state.
    try rt.deck_action(FOUNDRY_COMBINE);
    try testing.expect(bespoke.dialogue.view(rt.active_world()) != null);
    try rt.answer(0); // Spark
    try rt.answer(0); // Ember
    try rt.answer(0); // Bolt (Fizzle)
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Fizzle") != null);
    const after_first_dialog = rt.world.fact_count();
    try rt.deck_action(FOUNDRY_COMBINE);
    try rt.answer(0);
    try rt.answer(0);
    try rt.answer(0);
    try testing.expectEqual(after_first_dialog, rt.world.fact_count());
}

test "P44-05: Cinder Table plays all 12 cards across 4 rounds in the browser" {
    const rt = try load(CINDER_DECK);
    defer unload(rt);
    try rt.trigger_catalyst();
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Salt 1") != null);
    var step: usize = 0;
    while (cinder_played_summary(rt.active_world()).count < cinder_table.TOTAL_PLAYS and step < 20) : (step += 1) {
        try rt.trigger_catalyst();
    }
    try testing.expectEqual(cinder_table.TOTAL_PLAYS, cinder_played_summary(rt.active_world()).count);
    try testing.expect(holds(rt, "Ossic", "Void", "Cinder"));
}

// =============================================================================
// The Tide Beacon: four palette colour cycles on one static PNG backdrop
// =============================================================================

const TIDE_BEACON_DECK: u8 = 18;

fn tide_beacon_setup(rt: *WasmRuntime) anyerror!void {
    try tide_beacon.configure(&rt.world, &rt.spatial, true);
    try rt.vm.transition_to_scene(try entity(rt, tide_beacon.SCENE));
    rt.bind();
}

const TIDE_BEACON_SOLUTION = [_]Beat{
    .{ .note = "The waterfall churns down the basalt cliff.", .actions = &.{
        .{ .cue = .{ .name = "LooksAt", .actor = "CoveKeeper", .a = "Waterfall" } }, .{ .ticks = 1 },
    } },
    .{ .note = "Moonlight shivers across the tide pool.", .actions = &.{
        .{ .cue = .{ .name = "LooksAt", .actor = "CoveKeeper", .a = "TidePool" } }, .{ .ticks = 1 },
    } },
    .{ .note = "CoveKeeper walks to the rocky ledge to check the brazier from afar.", .actions = &.{
        .{ .walk = .{ .actor = "CoveKeeper", .mark = "Ledge" } }, .{ .settle = "CoveKeeper" },
        .{ .cue = .{ .name = "LooksAt", .actor = "CoveKeeper", .a = "Brazier" } }, .{ .ticks = 1 },
    } },
    .{ .note = "CoveKeeper returns to the pier and stokes the signal brazier.", .actions = &.{
        .{ .walk = .{ .actor = "CoveKeeper", .mark = "Pier" } }, .{ .settle = "CoveKeeper" },
        .{ .cue = .{ .name = "Uses", .actor = "CoveKeeper", .a = "Brazier" } }, .{ .ticks = 1 },
        .{ .require = .{ .subject = "Brazier", .relation = "Stoked" } },
    } },
};

test "P49-01: The Tide Beacon deck runs [S] and animates pixels with animation_clock" {
    const rt = try load(TIDE_BEACON_DECK);
    defer unload(rt);
    try testing.expectEqualStrings("CoveKeeper", rt.world.get_entity_name(rt.player_entity).?);
    try testing.expectEqual(@as(usize, 4), rt.program.?.art.cycles.len);

    const facts_before = rt.world.fact_count();
    rt.window.animation_clock = 0;
    rt.render_frame();
    const h0 = std.hash.Wyhash.hash(0, rt.framebuffer);
    rt.window.animation_clock = 12;
    rt.render_frame();
    const h12 = std.hash.Wyhash.hash(0, rt.framebuffer);
    try testing.expect(h0 != h12);
    try testing.expectEqual(facts_before, rt.world.fact_count());

    var presses: usize = 0;
    while (!holds(rt, "Brazier", "Stoked", null) and presses < 10) : (presses += 1) {
        try rt.trigger_catalyst();
    }
    try testing.expect(holds(rt, "Brazier", "Stoked", null));
}
