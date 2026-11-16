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
    .{ .note = "The wind picks up.", .actions = &.{ .{ .cue = .{ .name = "Gusts", .actor = "Tamsin" } }, .{ .ticks = 1 } } },
    .{ .note = "Tamsin spits.", .actions = &.{ .{ .cue = .{ .name = "Spits", .actor = "Tamsin" } }, .{ .ticks = 1 } } },
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
        SPIT_RULES => rt.queue_message("JudgeMarrow", "Spit past the last peg to win! Thick spit and a sea breeze will do it!"),
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
    const shown = bespoke.display.dialogue_panel.display_name(opponent_name, &name_buf);
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
    const players = [_][]const u8{ "Cat", "Tamsin", "Tamsin", "Player", "Tamsin", "Nell", "Mara", "Tamsin", "Tamsin", "Wren", "Maren" };
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
        try testing.expect(holds(rt, "CellLock", "dissolved", null));
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
    try testing.expect(bespoke.host.has_state(&rt.world, rt.world.lookup_entity("GreatBell").?, "ringing"));
    try testing.expect(bespoke.host.has_state(&rt.world, rt.world.lookup_entity("Beacon").?, "lit"));
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

    // Wait for the breeze, then talk to the judge and spit.
    try tick_until(rt, "Wind", "blowing", null, 80);
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
    try tick_until(rt, "Wind", "blowing", null, 80);
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
        var desk = try bespoke.display.DisplayWindow.init_offscreen(wasm.CANVAS_WIDTH, wasm.CANVAS_HEIGHT);
        defer desk.deinit();
        const frame = rt.capture();
        const shown = rt.screen(frame);
        desk.theme = shown.theme;
        desk.footer_text = shown.footer_text;
        desk.backdrop_color = shown.backdrop_color;
        desk.active_verb = shown.active_verb;
        desk.messages = shown.messages;
        desk.cue_banner_text = shown.cue_banner_text;
        desk.cue_banner_len = shown.cue_banner_len;
        desk.log_text = shown.log_text;
        desk.log_len = shown.log_len;
        desk.log_count = shown.log_count;
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
