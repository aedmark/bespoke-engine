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
const GK3_MOUSTACHE_SCRIPT = @import("gk3_moustache.zig").GK3_MOUSTACHE_SCRIPT;
const VILLAGE_SCRIPT = @import("village.zig").VILLAGE_SCRIPT;
const GOAT_PUZZLE_SCRIPT = @import("goat_puzzle.zig").GOAT_PUZZLE_SCRIPT;
const DOTT_PUZZLE_SCRIPT = @import("dott_puzzle.zig").DOTT_PUZZLE_SCRIPT;
const GROG_PUZZLE_SCRIPT = @import("grog_puzzle.zig").GROG_PUZZLE_SCRIPT;
const SWORD_FIGHTING_SCRIPT = @import("sword_fighting.zig").SWORD_FIGHTING_SCRIPT;
const atlantis = @import("atlantis_puzzle.zig");
const loom = @import("loom_puzzle.zig");
const art = @import("art.zig");
const darko = @import("darko_puzzle.zig");
const duel_mod = bespoke.duel;

pub const decks = [_]wasm.Deck{
    wasm.script_deck_with("TAVERN HEIST (GUARD, BARD & CAT)", TAVERN_SCRIPT, .{
        .player = "Cat",
        .intro = "Tavern Heist: you are the Cat. Click a mark to walk; [S] plays the solution.",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 28, .g = 21, .b = 18 },
        .catalyst = solver(&TAVERN_SOLUTION),
    }),
    wasm.script_deck_with("BOOTY ISLAND SPITTING CONTEST", SPITTING_CONTEST_SCRIPT, .{
        .player = "Guybrush",
        .intro = "Spitting Contest: TALK, LOOK, or USE on people and props; [S] plays the solution.",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 16, .g = 42, .b = 58 },
        .catalyst = solver(&SPIT_SOLUTION),
    }),
    wasm.script_deck_with("GK3: CAT MOUSTACHE PUZZLE", GK3_MOUSTACHE_SCRIPT, .{
        .player = "Gabriel",
        .intro = "GK3: Gabriel needs a disguise. Use the verbs, or [S] for the next step.",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 32, .g = 52, .b = 34 },
        .setup = gk3_setup,
        .catalyst = solver(&GK3_SOLUTION),
    }),
    wasm.script_deck_with("THE LIVING VILLAGE (EMERGENCE)", VILLAGE_SCRIPT, .{
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 22, .g = 44, .b = 28 },
        .setup = village_setup,
        .catalyst = village_desperation,
        .after_tick = village_after_tick,
    }),
    wasm.script_deck_with("BROKEN SWORD: LOCHMARNE GOAT", GOAT_PUZZLE_SCRIPT, .{
        .player = "George",
        .intro = "Lochmarne: get past the goat into the cellar. [S] plays the next step.",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 38, .g = 48, .b = 40 },
        .setup = goat_setup,
        .catalyst = solver(&GOAT_SOLUTION),
    }),
    wasm.script_deck_with("DAY OF THE TENTACLE TRIO", DOTT_PUZZLE_SCRIPT, .{
        .player = "Bernard",
        .intro = "DOTT: three eras, one toilet. [S] plays the next step of the solution.",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 42, .g = 24, .b = 48 },
        .setup = dott_setup,
        .catalyst = solver(&DOTT_SOLUTION),
    }),
    wasm.script_deck_with("CAUSTIC GROG (CONTAINER DEGRADATION)", GROG_PUZZLE_SCRIPT, .{
        .player = "Mara",
        .intro = "Caustic Grog: press [S] now to run for the lock before the cups fail.",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 20, .g = 42, .b = 40 },
        .catalyst = solver(&GROG_SOLUTION),
    }),
    wasm.script_deck_with("BRACKWATER BARBS", SWORD_FIGHTING_SCRIPT, .{
        .player = "Tamsin",
        .intro = "Brackwater Barbs: [S] starts a duel; answer barbs with the number keys.",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 30, .g = 36, .b = 52 },
        .setup = sword_setup,
        .catalyst = sword_solve,
        .on_choice = sword_choice,
    }),
    wasm.script_deck_with("ALGIERS: THREE PATHS", atlantis.ATLANTIS_PUZZLE_SCRIPT, .{
        .player = "Indy",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 52, .g = 38, .b = 22 },
        .setup = atlantis_setup,
        .catalyst = atlantis_solve,
        .on_choice = atlantis_choice,
        .cues = .{ .talk = "Talk" },
    }),
    wasm.script_deck_with("THE MIDDLESEX ANOMALY (TANGENT WORLDS)", darko.DARKO_PUZZLE_SCRIPT, .{
        .player = "Donnie",
        .intro = "Middlesex: a tangent universe collapses in 280 ticks. [S] plays the next step; I inspects the branch.",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 26, .g = 18, .b = 40 },
        .setup = darko_setup,
        .catalyst = solver(&DARKO_SOLUTION),
        .after_tick = darko_after_tick,
    }),
    wasm.script_deck_with("THE BELL TOWER (MUSICAL DRAFTS)", loom.BELL_TOWER_SCRIPT, .{
        .player = "Wren",
        .intro = "Bell Tower: act on something, then play four notes with C D E F G A B. [S] for the next step.",
        .soundtrack = &art.soundtrack,
        .background = .{ .r = 24, .g = 28, .b = 46 },
        .setup = loom_setup,
        .catalyst = solver(&LOOM_SOLUTION),
        .after_tick = loom_follow_scene,
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
        .settle => |name| {
            const actor = try entity(rt, name);
            var guard: usize = 0;
            while (guard < 40) : (guard += 1) {
                try rt.step_tick();
                if (!rt.spatial.is_moving(actor)) break;
            }
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
        // Facts go to the active world: the tangent branch while one is live, as the desktop
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
    .{ .note = "Guybrush drinks the green drink.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Guybrush", .a = "GreenDrink" } }, .{ .ticks = 2 } } },
    .{ .note = "Guybrush sounds the ship's horn.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Guybrush", .a = "Horn" } }, .{ .ticks = 2 } } },
    .{ .note = "Guybrush moves the flags while nobody watches.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Guybrush", .a = "Flags" } }, .{ .ticks = 2 } } },
    .{ .note = "The wind picks up.", .actions = &.{ .{ .cue = .{ .name = "Gusts", .actor = "Guybrush" } }, .{ .ticks = 1 } } },
    .{ .note = "Guybrush spits.", .actions = &.{ .{ .cue = .{ .name = "Spits", .actor = "Guybrush" } }, .{ .ticks = 1 } } },
};

const GK3_SOLUTION = [_]Beat{
    .{ .note = "Gabriel searches his desk.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Gabriel", .a = "RoomDesk" } }, .{ .ticks = 1 } } },
    .{ .note = "Gabriel takes Mosely's passport.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Gabriel", .a = "MoselyDoor" } }, .{ .ticks = 1 } } },
    .{ .note = "Gabriel draws a moustache on the passport.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Gabriel", .a = "Marker", .b = "MoselyPassport" } }, .{ .ticks = 1 } } },
    .{ .note = "Gabriel heads into the garden and finds the spray bottle.", .actions = &.{
        .{ .scene = .{ .scene = "Hotel Garden", .actor = "Gabriel", .mark = "GardenPath" } },
        .{ .cue = .{ .name = "Uses", .actor = "Gabriel", .a = "GardenShrub" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "Gabriel tapes the hole in the fence.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Gabriel", .a = "MaskingTape", .b = "FenceHole" } }, .{ .ticks = 1 } } },
    .{ .note = "Gabriel sprays the cat through the fence.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Gabriel", .a = "SprayBottle", .b = "StrayCat" } }, .{ .ticks = 8 } } },
    .{ .note = "Gabriel collects the cat hair from the tape.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Gabriel", .a = "FenceHole" } }, .{ .ticks = 1 } } },
    .{ .note = "Gabriel makes a moustache with the syrup.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Gabriel", .a = "CatHair", .b = "Syrup" } }, .{ .ticks = 1 } } },
    .{ .note = "Gabriel puts on the moustache.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Gabriel", .a = "CatMoustache", .b = "Gabriel" } }, .{ .ticks = 1 } } },
    .{ .note = "Gabriel asks Madame Buthane for Mosely's motorcycle.", .actions = &.{
        .{ .scene = .{ .scene = "Bike Rental Shop", .actor = "Gabriel", .mark = "ShopEntrance" } },
        .{ .cue = .{ .name = "TalksTo", .actor = "Gabriel", .a = "Buthane" } },
        .{ .ticks = 4 },
    } },
};

const GOAT_SOLUTION = [_]Beat{
    .{ .note = "George heads for the cellar.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "George", .a = "CellarEntrance" } }, .{ .settle = "George" }, .{ .ticks = 1 } } },
    .{ .note = "George hauls the plough into the goat's path.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "George", .a = "FarmPlough" } }, .{ .settle = "George" }, .{ .ticks = 1 } } },
    .{ .note = "George tries the cellar again.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "George", .a = "CellarEntrance" } }, .{ .settle = "George" }, .{ .ticks = 1 } } },
    .{ .note = "George studies the mural in the crypt.", .actions = &.{ .{ .cue = .{ .name = "LooksAt", .actor = "George", .a = "CarvedMural" } }, .{ .ticks = 1 } } },
};

// The Day of the Tentacle proof's host passes items through the Chron-o-Johns and sets the
// facts each era's rules react to; the rules' interruptions are the script's.
const DOTT_SOLUTION = [_]Beat{
    .{ .note = "Bernard flushes the vintage wine back to 1790.", .actions = &.{
        .{ .transfer = .{ .item = "VintageWine", .from = "Bernard", .to = "Hoagie" } },
        .{ .scene = .{ .scene = "Colonial Workshop" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "Hoagie seals the wine in the time capsule; two centuries turn it to vinegar.", .actions = &.{
        .{ .forget = .{ .subject = "Hoagie", .relation = "Carries", .object = "VintageWine" } },
        .{ .remember = .{ .subject = "VintageWine", .relation = "SealedInCapsule", .value = 1 } },
        .{ .remember = .{ .subject = "VintageWine", .relation = "WineAgedIntoVinegar", .value = 1 } },
        .{ .scene = .{ .scene = "Motel Lobby" } },
        .{ .remember = .{ .subject = "Bernard", .relation = "Carries", .object = "Vinegar200Years" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "The vinegar goes back to Hoagie, who builds a super battery for the toilet.", .actions = &.{
        .{ .transfer = .{ .item = "Vinegar200Years", .from = "Bernard", .to = "Hoagie" } },
        .{ .forget = .{ .subject = "Hoagie", .relation = "Carries", .object = "Vinegar200Years" } },
        .{ .forget = .{ .subject = "Hoagie", .relation = "Carries", .object = "BatteryCasing" } },
        .{ .remember = .{ .subject = "Hoagie", .relation = "Carries", .object = "SuperBattery" } },
        .{ .remember = .{ .subject = "Hoagie", .relation = "ToiletPowered", .value = 1 } },
        .{ .scene = .{ .scene = "Colonial Workshop" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "Betsy Ross sews a flag from the tentacle flyer.", .actions = &.{
        .{ .transfer = .{ .item = "TentacleFlyer", .from = "Bernard", .to = "Hoagie" } },
        .{ .remember = .{ .subject = "BetsyRoss", .relation = "TentacleFlagSewn", .value = 1 } },
        .{ .ticks = 2 },
    } },
    .{ .note = "Washington chops down the painted kumquat tree.", .actions = &.{
        .{ .remember = .{ .subject = "Washington", .relation = "TreeChoppedDown", .object = "KumquatTree" } },
        .{ .ticks = 2 },
    } },
    .{ .note = "In 2193 the tree is gone, and Laverne is free.", .actions = &.{
        .{ .scene = .{ .scene = "Dystopian Guard Post" } },
        .{ .remember = .{ .subject = "Laverne", .relation = "FreedFromTree", .value = 1 } },
        .{ .forget = .{ .subject = "Laverne", .relation = "Trapped", .value = 1 } },
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

// The Middlesex Anomaly's desktop solution, inside the tangent universe: follow the conduit to
// the school, take the axe and flood it, follow it to the ridge, deliver the letter, and guide
// the jet engine into the vortex. The hypervisor closes the loop on the next tick.
const DARKO_SOLUTION = [_]Beat{
    .{ .note = "Frank: follow the vector conduits.", .actions = &.{ .{ .cue = .{ .name = "TalksTo", .actor = "Donnie", .a = "Frank" } }, .{ .ticks = 1 } } },
    .{ .note = "Donnie follows the conduit to the high school and takes the fire axe.", .actions = &.{
        .{ .scene = .{ .scene = "Middlesex High School", .actor = "Donnie", .mark = "WaterPipeMark" } },
        .{ .remember = .{ .subject = "Donnie", .relation = "Carries", .object = "Axe" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "One swing ruptures the water main; the school floods.", .actions = &.{
        .{ .remember = .{ .subject = "Donnie", .relation = "WaterPipeRuptured", .object = "WaterPipeProp" } },
        .{ .remember = .{ .subject = "Donnie", .relation = "SchoolFlooded", .value = 1 } },
        .{ .ticks = 1 },
    } },
    .{ .note = "The conduit leads to the ridge; Donnie delivers 'Cellar Door' to Roberta Sparrow.", .actions = &.{
        .{ .scene = .{ .scene = "Tangent Vortex Ridge", .actor = "Donnie", .mark = "VortexMark" } },
        .{ .remember = .{ .subject = "Donnie", .relation = "Carries", .object = "Envelope" } },
        .{ .remember = .{ .subject = "Donnie", .relation = "LetterDelivered", .object = "RobertaSparrow" } },
        .{ .ticks = 1 },
    } },
    .{ .note = "Donnie guides the jet engine into the vortex. The loop closes.", .actions = &.{
        .{ .remember = .{ .subject = "Donnie", .relation = "Carries", .object = "JetEngineProp" } },
        .{ .place = .{ .actor = "JetEngineProp", .scene = "Tangent Vortex Ridge", .mark = "VortexMark" } },
        .{ .remember = .{ .subject = "Donnie", .relation = "ArtifactAtVortex", .object = "JetEngineProp" } },
        .{ .remember = .{ .subject = "Donnie", .relation = "LoopClosed", .value = 1 } },
        .{ .ticks = 1 },
    } },
};

// The Bell Tower's desktop solution: watch, kindle, learn, climb, loosen, take the fork, toll.
const LOOM_SOLUTION = [_]Beat{
    .{ .note = "Wren watches the lantern.", .actions = &.{ .{ .cue = .{ .name = "LooksAt", .actor = "Wren", .a = "Lantern" } }, .{ .ticks = 1 } } },
    .{ .note = "Wren weaves Kindle (C D E C) on the brazier.", .actions = &.{.{ .weave = .{ .notes = "CDEC", .target = "Brazier" } }} },
    .{ .note = "The ivy teaches Bind.", .actions = &.{ .{ .cue = .{ .name = "LooksAt", .actor = "Wren", .a = "Ivy" } }, .{ .ticks = 1 } } },
    .{ .note = "Wren climbs to the belfry by firelight.", .actions = &.{ .{ .cue = .{ .name = "Uses", .actor = "Wren", .a = "Stairwell" } }, .{ .ticks = 2 } } },
    .{ .note = "Bind played backwards: Loose (F D E F) frees the chain.", .actions = &.{.{ .weave = .{ .notes = "FDEF", .target = "IronChain" } }} },
    .{ .note = "Wren takes the tuning fork; the distaff reaches all seven notes.", .actions = &.{ .{ .cue = .{ .name = "PicksUp", .actor = "Wren", .a = "TuningFork" } }, .{ .ticks = 1 } } },
    .{ .note = "Wren weaves Toll (G A B G) on the great bell.", .actions = &.{.{ .weave = .{ .notes = "GABG", .target = "GreatBell" } }} },
};

// =============================================================================
// Host setup the desktop proofs do in Zig
// =============================================================================

/// The desktop proof's opening: the three scenes joined into one route, everyone at their
/// marks, and a 280-tick tangent universe forked with the jet engine as its artifact. Every name
/// the solution writes is interned first, so the primary and branch worlds share their ids.
fn darko_setup(rt: *WasmRuntime) anyerror!void {
    for ([_][]const u8{ "Axe", "Envelope" }) |name| _ = try entity(rt, name);
    for ([_][]const u8{ "Carries", "WaterPipeRuptured", "SchoolFlooded", "LetterDelivered", "ArtifactAtVortex", "LoopClosed", "DreamResidueTransferred", "ArtifactMaterialized" }) |name| {
        _ = try rt.world.intern_relation(name, .set);
    }
    const bedroom = try entity(rt, "Suburban Bedroom");
    const school = try entity(rt, "Middlesex High School");
    const ridge = try entity(rt, "Tangent Vortex Ridge");
    const g = &rt.spatial.graph;
    const route = [_]struct { room: EntityId, mark: []const u8 }{
        .{ .room = bedroom, .mark = "BedMark" },     .{ .room = bedroom, .mark = "DeskMark" },
        .{ .room = bedroom, .mark = "BedroomDoor" }, .{ .room = school, .mark = "LockersMark" },
        .{ .room = school, .mark = "HallwayCenter" }, .{ .room = school, .mark = "WaterPipeMark" },
        .{ .room = ridge, .mark = "RidgePeak" },     .{ .room = ridge, .mark = "MailboxMark" },
        .{ .room = ridge, .mark = "VortexMark" },
    };
    var previous: ?bespoke.WaypointId = null;
    for (route) |stop| {
        const wp = g.find_waypoint_in_room(stop.room, stop.mark) orelse return error.UnknownMark;
        if (previous) |p| try g.connect(p, wp, null);
        previous = wp;
    }
    const places = [_]struct { who: []const u8, room: EntityId, mark: []const u8 }{
        .{ .who = "Donnie", .room = bedroom, .mark = "BedMark" },
        .{ .who = "Frank", .room = bedroom, .mark = "DeskMark" },
        .{ .who = "Gretchen", .room = school, .mark = "LockersMark" },
        .{ .who = "RobertaSparrow", .room = ridge, .mark = "MailboxMark" },
        .{ .who = "JetEngineProp", .room = bedroom, .mark = "BedMark" },
    };
    for (places) |pl| try rt.spatial.register_entity(try entity(rt, pl.who), g.find_waypoint_in_room(pl.room, pl.mark).?, 8);
    try rt.vm.transition_to_scene(bedroom);

    const hv = try rt.attach_hypervisor();
    _ = try hv.fork_tangent(280, try entity(rt, "Donnie"), try entity(rt, "JetEngineProp"));
    hv.set_vortex_target(g.find_waypoint_in_room(ridge, "VortexMark").?);
    try hv.add_dream_residue(.{ .subject = try entity(rt, "Donnie"), .relation = try relation(rt, "DreamResidueTransferred"), .object_or_value = 1 });
    rt.bind();
}

/// The desktop proof's tick: step the hypervisor after the VM, and when the loop resolves carry
/// the flood and the letter into the primary world before the branch is gone.
fn darko_after_tick(rt: *WasmRuntime) anyerror!void {
    const hv = rt.hypervisor orelse return;
    if (!hv.branch_active) return;
    const branch = rt.active_world();
    const donnie = try entity(rt, "Donnie");
    const flood = try relation(rt, "SchoolFlooded");
    const letter = try relation(rt, "LetterDelivered");
    const flooded = branch.has_fact(donnie, flood, null);
    const delivered = branch.has_fact(donnie, letter, null);
    switch (try hv.step_tick(&rt.spatial)) {
        .loop_resolved => {
            if (flooded) try rt.world.remember(donnie, flood, 1, 0);
            if (delivered) try rt.world.remember(donnie, letter, (try entity(rt, "RobertaSparrow")).to_int(), 0);
            rt.set_banner(if (darko.evaluate_darko_solved(&rt.world)) "The tangent universe collapses safely. The loop is closed." else "The tangent universe collapses.");
        },
        .budget_expired => rt.set_banner("The countdown ran out and the tangent universe collapsed. Press [R] to rewind."),
        else => {},
    }
    rt.bind();
}

/// The desktop proof's tower layout, with Wren at the doorway of the base.
fn loom_setup(rt: *WasmRuntime) anyerror!void {
    const ids = try loom.configure(&rt.world, &rt.spatial);
    try rt.vm.transition_to_scene(ids.base);
    loom_scene = ids.base;
}

/// The scene the Bell Tower deck last showed. The script changes scenes itself; as on desktop,
/// Wren follows to the stair at the other end.
var loom_scene: EntityId = .none;

fn loom_follow_scene(rt: *WasmRuntime) anyerror!void {
    const now = rt.vm.current_scene orelse return;
    if (now == loom_scene) return;
    loom_scene = now;
    const wren = try entity(rt, "Wren");
    const mark = if (std.mem.eql(u8, rt.world.get_entity_name(now) orelse "", loom.BELFRY_SCENE)) "StairTop" else "StairFoot";
    _ = try rt.spatial.transition_actor(wren, now, rt.spatial.graph.find_waypoint_in_room(now, mark));
}

fn gk3_setup(rt: *WasmRuntime) anyerror!void {
    try rt.vm.transition_to_scene(try entity(rt, "Hotel Corridor"));
}

/// The goat waits at its tether; George starts at the courtyard entrance.
fn goat_setup(rt: *WasmRuntime) anyerror!void {
    const courtyard = try entity(rt, "Lochmarne Castle Courtyard");
    try rt.vm.transition_to_scene(courtyard);
    if (rt.spatial.graph.find_waypoint_in_room(courtyard, "TetherCenter")) |tether| {
        _ = try rt.spatial.transition_actor(try entity(rt, "BillyGoat"), courtyard, tether);
    }
}

/// The opening the desktop proof's host sets: Laverne trapped and guarded, the wine and the
/// flyer with Bernard, the paint and the battery casing with Hoagie, and the present on stage.
fn dott_setup(rt: *WasmRuntime) anyerror!void {
    const facts = [_]Fact{
        .{ .subject = "Laverne", .relation = "Trapped", .value = 1 },
        .{ .subject = "Laverne", .relation = "Guarded", .value = 1 },
        .{ .subject = "Bernard", .relation = "Carries", .object = "VintageWine" },
        .{ .subject = "Bernard", .relation = "Carries", .object = "TentacleFlyer" },
        .{ .subject = "Hoagie", .relation = "Carries", .object = "RedPaintBucket" },
        .{ .subject = "Hoagie", .relation = "Carries", .object = "BatteryCasing" },
    };
    for (facts) |f| try rt.world.remember(try entity(rt, f.subject), try relation(rt, f.relation), try fact_object(rt, f), 0);
    try rt.vm.transition_to_scene(try entity(rt, "Motel Lobby"));
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

/// The duel and its active round. The round is World facts, as on desktop, so a rewind
/// restores it with the generated reply set (D-046); the `Duel` itself holds configuration.
var sword_duel: duel_mod.Duel = undefined;
var sword_ready = false;

/// The duel, pointed at the live World. `Duel` keeps the World it was initialised with, and the
/// runtime is moved after setup (`WasmRuntime.bind`), so every use re-points it first.
fn sword(rt: *WasmRuntime) ?*duel_mod.Duel {
    if (!sword_ready) return null;
    sword_duel.world = &rt.world;
    return &sword_duel;
}

fn sword_relation(rt: *WasmRuntime, name: []const u8) !bespoke.RelationKind {
    return rt.world.intern_relation(name, .property);
}

fn sword_setup(rt: *WasmRuntime) anyerror!void {
    sword_ready = false;
    const program = if (rt.program) |*p| p else return error.NoProgram;
    if (program.duels.items.len != 1) return error.MissingSwordDuel;
    const decl = &program.duels.items[0];
    sword_duel = try duel_mod.Duel.init(&rt.world, decl.config);
    try decl.apply_tiers(&sword_duel);
    sword_ready = true;
    try rt.vm.transition_to_scene(try entity(rt, "Tidewalk"));
}

/// Offers the comebacks Tamsin has mastered against the active challenge, as the desktop's
/// generated choice set; each action id is the reply entity.
fn sword_open_round(rt: *WasmRuntime) !void {
    _ = sword(rt) orelse return;
    const tamsin = try entity(rt, "Tamsin");
    const opponent = rt.world.get_property(tamsin, try sword_relation(rt, "ActiveDuelOpponent")) orelse return;
    const challenge = rt.world.get_property(tamsin, try sword_relation(rt, "ActiveDuelChallenge")) orelse return;
    var candidates: [9]duel_mod.Candidate = undefined;
    const count = sword_duel.replies(&rt.vm, tamsin, EntityId.from_int(challenge), &candidates);
    if (count == 0) return;
    var choices: [9]bespoke.dialogue.Choice = undefined;
    for (0..count) |i| choices[i] = .{ .text = candidates[i].text, .action = candidates[i].entity.to_int() };
    _ = try rt.vm.open_generated_dialogue(EntityId.from_int(opponent), rt.world.get_entity_name(EntityId.from_int(challenge)) orelse "", choices[0..count]);
    rt.render_frame();
}

fn sword_start(rt: *WasmRuntime, opponent_name: []const u8, challenge: EntityId) !void {
    _ = sword(rt) orelse return;
    const tamsin = try entity(rt, "Tamsin");
    const opponent = try entity(rt, opponent_name);
    try rt.world.remember(tamsin, try sword_relation(rt, "ActiveDuelOpponent"), opponent.to_int(), 0);
    try rt.world.remember(tamsin, try sword_relation(rt, "ActiveDuelChallenge"), challenge.to_int(), 0);
    try rt.world.remember(tamsin, sword_duel.advantage_rel, 0, 0);
    try rt.world.remember(opponent, sword_duel.advantage_rel, 0, 0);
    try sword_open_round(rt);
    var buf: [96]u8 = undefined;
    rt.set_banner(std.fmt.bufPrint(&buf, "{s} draws. Answer with the number keys, or [S].", .{opponent_name}) catch opponent_name);
}

/// `[S]`: with a round open, answers with the first reply; otherwise starts the desktop
/// proof's next duel, Bosun Pike on the Tidewalk and then Mistress Vell in her fencing yard.
fn sword_solve(rt: *WasmRuntime) anyerror!void {
    _ = sword(rt) orelse return;
    if (bespoke.dialogue.view(&rt.world) != null) return rt.answer(0);
    const tamsin = try entity(rt, "Tamsin");
    if (sword_duel.wins(tamsin) == 0) return sword_start(rt, "BosunPike", sword_duel.challenge(0, 0));
    if (rt.world.lookup_entity("Vell")) |vell| {
        if (sword_duel.wins(tamsin) < 2 and sword_duel.wins(vell) == 0) {
            const yard = try entity(rt, "Fencing Yard");
            try rt.vm.transition_to_scene(yard);
            _ = try rt.spatial.transition_actor(tamsin, yard, rt.spatial.graph.find_waypoint_in_room(yard, "YardCircle"));
            return sword_start(rt, "Vell", sword_duel.challenge(4, 1));
        }
    }
    rt.set_banner("Both duels are fought. Press [R] to rewind and duel again.");
}

/// The desktop's round resolution: a parry gains advantage, a miss teaches the counter.
fn sword_choice(rt: *WasmRuntime, action: u32) anyerror!void {
    _ = sword(rt) orelse return;
    const tamsin = try entity(rt, "Tamsin");
    const opponent_rel = try sword_relation(rt, "ActiveDuelOpponent");
    const challenge_rel = try sword_relation(rt, "ActiveDuelChallenge");
    const opponent = EntityId.from_int(rt.world.get_property(tamsin, opponent_rel) orelse return);
    const challenge = EntityId.from_int(rt.world.get_property(tamsin, challenge_rel) orelse return);
    const reply = if (action == 0) EntityId.none else EntityId.from_int(action);
    const round = try sword_duel.resolve_round(opponent, tamsin, challenge, reply);
    const name = rt.world.get_entity_name(opponent) orelse "The opponent";
    var buf: [96]u8 = undefined;
    if (round.winner) |winner| {
        _ = rt.world.forget(tamsin, opponent_rel, null);
        _ = rt.world.forget(tamsin, challenge_rel, null);
        rt.set_banner(if (winner == tamsin)
            std.fmt.bufPrint(&buf, "Victory! {s} yields. Duels won: {d}.", .{ name, sword_duel.wins(tamsin) }) catch "Victory!"
        else
            std.fmt.bufPrint(&buf, "Defeat. {s} wins this duel. [S] to try again.", .{name}) catch "Defeat.");
        return;
    }
    rt.set_banner(std.fmt.bufPrint(&buf, "{s} Advantage: Tamsin {d}, {s} {d}.", .{
        if (round.parried) "Parried!" else "Missed! The counter is learned.",
        sword_duel.advantage(tamsin),
        name,
        sword_duel.advantage(opponent),
    }) catch "Round resolved.");
    try sword_open_round(rt);
}

// =============================================================================
// Algiers: three stageplay paths, chosen from a generated selector
// =============================================================================

const ATLANTIS_SELECTOR = [_]bespoke.dialogue.Choice{
    .{ .text = "Wits: follow the ledger", .action = 1 },
    .{ .text = "Fists: force the stall", .action = 2 },
    .{ .text = "Team: recruit the diggers", .action = 3 },
};

/// The desktop proof's own bazaar layout and gates, then the path selector.
fn atlantis_setup(rt: *WasmRuntime) anyerror!void {
    const ids = try atlantis.configure(&rt.world, &rt.spatial);
    try rt.vm.transition_to_scene(ids.scene);
    _ = try rt.vm.open_generated_dialogue(ids.omar, "Choose your approach, Indy.", &ATLANTIS_SELECTOR);
    rt.set_banner("Algiers: choose [1] Wits, [2] Fists, or [3] Team. [S] plays the next step.");
}

fn atlantis_active(rt: *WasmRuntime) ?atlantis.PathSpec {
    const active = rt.world.lookup_relation("PathActive") orelse return null;
    for (atlantis.paths) |spec| {
        const route = rt.world.lookup_entity(spec.name) orelse continue;
        if (rt.world.has_fact(route, active, null)) return spec;
    }
    return null;
}

fn atlantis_choice(rt: *WasmRuntime, action: u32) anyerror!void {
    if (action == 0 or action > atlantis.paths.len) return;
    const spec = atlantis.paths[action - 1];
    const program = if (rt.program) |*p| p else return;
    _ = (try rt.vm.select_path(program, spec.name)) orelse return;
    try rt.step_tick();
    rt.set_banner(spec.banner);
}

/// `[S]`: the desktop proof's path run: choose Wits if no path is chosen, walk through the
/// path's gate to the manuscript, talk to Omar, then run the path's own solution routine.
fn atlantis_solve(rt: *WasmRuntime) anyerror!void {
    const program = if (rt.program) |*p| p else return;
    const indy = try entity(rt, "Indy");
    const spec = atlantis_active(rt) orelse {
        if (bespoke.dialogue.view(&rt.world) != null) return rt.answer(0);
        return;
    };
    if (holds(rt, "Indy", "Acquired", "Manuscript")) {
        rt.set_banner("The manuscript is Indy's. Press [R] to rewind and try another path.");
        return;
    }
    const scene = try entity(rt, "Algiers Bazaar");
    const manuscript_wp = rt.spatial.graph.find_waypoint_in_room(scene, "ManuscriptMark") orelse return;
    if (rt.spatial.get_current_waypoint(indy) != manuscript_wp) {
        rt.set_banner("Indy heads through the open gate to the manuscript.");
        _ = try rt.spatial.walk_to_with_world(&rt.world, indy, manuscript_wp);
        _ = try perform(rt, .{ .settle = "Indy" });
        return;
    }
    if (bespoke.dialogue.view(&rt.world) != null) return rt.answer(0);
    const chosen = rt.world.lookup_relation("SolveTalked");
    if (chosen == null or !rt.world.has_fact(indy, chosen.?, null)) {
        try rt.vm.set_dialogue_speaker(indy, try entity(rt, "Omar"));
        _ = try rt.vm.fire_cue(program, "Talk", indy, try entity(rt, "Omar"), null);
        try rt.step_tick();
        try rt.world.remember(indy, try rt.world.intern_relation("SolveTalked", .property), 1, 0);
        return;
    }
    const entry = program.routine_entries.get(spec.routine) orelse return;
    _ = try rt.vm.spawn_routine(indy, entry);
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

fn holds(rt: *WasmRuntime, subject: []const u8, rel: []const u8, object: ?[]const u8) bool {
    const s = rt.world.lookup_entity(subject) orelse return false;
    const r = rt.world.lookup_relation(rel) orelse return false;
    const o: ?u32 = if (object) |n| (rt.world.lookup_entity(n) orelse return false).to_int() else null;
    return rt.world.find_first(s, r, o) != null;
}

test "P30-05: each deck runs its proof's script with its own player" {
    const players = [_][]const u8{ "Cat", "Guybrush", "Gabriel", "Player", "George", "Bernard", "Mara", "Tamsin", "Indy", "Donnie", "Wren" };
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
        try testing.expect(holds(rt, "Guybrush", "Placed", "FirstPlace"));
    }
    {
        const rt = try load(2);
        defer unload(rt);
        try solve(rt);
        try testing.expect(holds(rt, "Gabriel", "HasBikeKeys", null));
    }
    {
        const rt = try load(4);
        defer unload(rt);
        try solve(rt);
        try testing.expectEqualStrings("Templar Crypt", rt.world.get_entity_name(rt.vm.current_scene.?).?);
    }
    {
        const rt = try load(5);
        defer unload(rt);
        try solve(rt);
        try testing.expect(holds(rt, "Laverne", "FreedFromTree", null));
        try testing.expect(holds(rt, "Hoagie", "Carries", "SuperBattery"));
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
    try rt.trigger_catalyst();
    try testing.expect(bespoke.dialogue.view(&rt.world) != null);
    var decided = false;
    for (0..60) |_| {
        try rt.trigger_catalyst();
        if (std.mem.startsWith(u8, rt.get_banner(), "Victory!") or std.mem.startsWith(u8, rt.get_banner(), "Defeat.")) decided = true;
        if (decided) break;
    }
    try testing.expect(decided);
    // A miss teaches the counter, as on desktop.
    try testing.expect(holds(rt, "Tamsin", "MasteredComeback", null) or holds(rt, "Tamsin", "HeardBarb", null));
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
    try testing.expectEqualStrings(loom.BELFRY_SCENE, rt.world.get_entity_name(rt.vm.current_scene.?).?);
}

test "P30-01: the Middlesex deck runs a tangent universe and closes its loop" {
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
    try testing.expect(darko.evaluate_darko_solved(&rt.world));
    try testing.expect(rt.vm.world == &rt.world);
}

test "P30-01: a rewind restores the tangent branch the timeline recorded" {
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
    try testing.expect(!darko.evaluate_darko_solved(&rt.world));
}

test "P30-01: the Algiers deck picks a path from the selector and takes the manuscript" {
    const rt = try load(8);
    defer unload(rt);
    // Number key 2 answers the generated selector: Fists.
    try testing.expectEqual(wasm.BrowserActionTag.dialogue_answered, try rt.dispatch_event(.{ .kind = .key_down, .key_code = '2' }));
    try testing.expect(holds(rt, "Fists", "PathActive", null));
    try testing.expect(holds(rt, "WitsGate", "WaypointBlocked", null));
    try solve(rt);
    try testing.expect(holds(rt, "Indy", "Acquired", "Manuscript"));
    try testing.expect(holds(rt, "Indy", "Solved", "Fists"));
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
