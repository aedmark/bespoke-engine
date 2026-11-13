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

pub const decks = [_]wasm.Deck{
    wasm.script_deck_with("TAVERN HEIST (GUARD, BARD & CAT)", TAVERN_SCRIPT, .{
        .player = "Cat",
        .intro = "Tavern Heist: you are the Cat. Click a mark to walk; [S] plays the solution.",
        .background = .{ .r = 28, .g = 21, .b = 18 },
        .catalyst = solver(&TAVERN_SOLUTION),
    }),
    wasm.script_deck_with("BOOTY ISLAND SPITTING CONTEST", SPITTING_CONTEST_SCRIPT, .{
        .player = "Guybrush",
        .intro = "Spitting Contest: TALK, LOOK, or USE on people and props; [S] plays the solution.",
        .background = .{ .r = 16, .g = 42, .b = 58 },
        .catalyst = solver(&SPIT_SOLUTION),
    }),
    wasm.script_deck_with("GK3: CAT MOUSTACHE PUZZLE", GK3_MOUSTACHE_SCRIPT, .{
        .player = "Gabriel",
        .intro = "GK3: Gabriel needs a disguise. Use the verbs, or [S] for the next step.",
        .background = .{ .r = 32, .g = 52, .b = 34 },
        .setup = gk3_setup,
        .catalyst = solver(&GK3_SOLUTION),
    }),
    wasm.script_deck_with("THE LIVING VILLAGE (EMERGENCE)", VILLAGE_SCRIPT, .{
        .background = .{ .r = 22, .g = 44, .b = 28 },
        .setup = village_setup,
        .catalyst = village_desperation,
        .after_tick = village_after_tick,
    }),
    wasm.script_deck_with("BROKEN SWORD: LOCHMARNE GOAT", GOAT_PUZZLE_SCRIPT, .{
        .player = "George",
        .intro = "Lochmarne: get past the goat into the cellar. [S] plays the next step.",
        .background = .{ .r = 38, .g = 48, .b = 40 },
        .setup = goat_setup,
        .catalyst = solver(&GOAT_SOLUTION),
    }),
    wasm.script_deck_with("DAY OF THE TENTACLE TRIO", DOTT_PUZZLE_SCRIPT, .{
        .player = "Bernard",
        .intro = "DOTT: three eras, one toilet. [S] plays the next step of the solution.",
        .background = .{ .r = 42, .g = 24, .b = 48 },
        .setup = dott_setup,
        .catalyst = solver(&DOTT_SOLUTION),
    }),
    wasm.script_deck_with("CAUSTIC GROG (CONTAINER DEGRADATION)", GROG_PUZZLE_SCRIPT, .{
        .player = "Mara",
        .intro = "Caustic Grog: press [S] now to run for the lock before the cups fail.",
        .background = .{ .r = 20, .g = 42, .b = 40 },
        .catalyst = solver(&GROG_SOLUTION),
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
            if (bespoke.dialogue.view(&rt.world) != null) {
                if ((try rt.vm.choose(0)) != null) try rt.step_tick();
            }
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
        .remember => |f| try rt.world.remember(try entity(rt, f.subject), try relation(rt, f.relation), try fact_object(rt, f), f.ttl),
        .forget => |f| _ = rt.world.forget(try entity(rt, f.subject), try relation(rt, f.relation), if (f.object != null or f.value != 0) try fact_object(rt, f) else null),
        .transfer => |t| _ = try rt.world.transfer_item(try entity(rt, t.item), try entity(rt, t.from), try entity(rt, t.to)),
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

// =============================================================================
// Host setup the desktop proofs do in Zig
// =============================================================================

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
    const players = [_][]const u8{ "Cat", "Guybrush", "Gabriel", "Player", "George", "Bernard", "Mara" };
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
