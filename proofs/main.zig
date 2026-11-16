//! `bespoke-proofs`: launcher for the engine's proofs of concept (D-031).
//!
//! Each proof is an empirical demonstration that an engine feature exists and works as
//! advertised. Proofs consume the engine only through the `bespoke` module; the engine never
//! imports a proof (the compiler enforces this: `proofs/` lies outside the module's path).
const std = @import("std");

pub const tavern_heist = @import("tavern_heist.zig");
pub const spitting_contest = @import("spitting_contest.zig");
pub const borrowed_beard = @import("borrowed_beard.zig");
pub const sword_fighting = @import("sword_fighting.zig");
pub const village = @import("village.zig");
pub const lamp_point = @import("lamp_point.zig");
pub const three_tides = @import("three_tides.zig");
pub const weathercock = @import("weathercock.zig");
pub const bell_tower = @import("bell_tower.zig");
pub const grog_puzzle = @import("grog_puzzle.zig");
pub const saltmarket = @import("saltmarket.zig");
pub const grid_puzzle = @import("grid_puzzle.zig");
pub const observatory_puzzle = @import("observatory_puzzle.zig");

const Proof = enum {
    tavern,
    spitting_contest,
    borrowed_beard,
    sword_fighting,
    village,
    lamp_point,
    three_tides,
    weathercock,
    bell_tower,
    grog,
    saltmarket,
    grid,
    observatory,
};

/// Flag spellings carried over from the pre-D-031 `bespoke` CLI, so existing commands keep working
/// with the binary name changed.
const aliases = [_]struct { name: []const u8, proof: Proof }{
    .{ .name = "tavern", .proof = .tavern },
    .{ .name = "tavern-heist", .proof = .tavern },
    .{ .name = "spitting-contest", .proof = .spitting_contest },
    .{ .name = "spit", .proof = .spitting_contest },
    .{ .name = "borrowed-beard", .proof = .borrowed_beard },
    .{ .name = "beard", .proof = .borrowed_beard },
    .{ .name = "cat-moustache", .proof = .borrowed_beard },
    .{ .name = "sword-fighting", .proof = .sword_fighting },
    .{ .name = "barbs", .proof = .sword_fighting },
    .{ .name = "insults", .proof = .sword_fighting },
    .{ .name = "sword", .proof = .sword_fighting },
    .{ .name = "village", .proof = .village },
    .{ .name = "living-village", .proof = .village },
    .{ .name = "lamp-point", .proof = .lamp_point },
    .{ .name = "donkey", .proof = .lamp_point },
    .{ .name = "goat", .proof = .lamp_point },
    .{ .name = "goat-puzzle", .proof = .lamp_point },
    .{ .name = "broken-sword", .proof = .lamp_point },
    .{ .name = "three-tides", .proof = .three_tides },
    .{ .name = "tides", .proof = .three_tides },
    .{ .name = "tentacle", .proof = .three_tides },
    .{ .name = "chrono-mansion", .proof = .three_tides },
    .{ .name = "weathercock", .proof = .weathercock },
    .{ .name = "bell-tower", .proof = .bell_tower },
    .{ .name = "drafts", .proof = .bell_tower },
    .{ .name = "grog", .proof = .grog },
    .{ .name = "caustic-grog", .proof = .grog },
    .{ .name = "saltmarket", .proof = .saltmarket },
    .{ .name = "algiers", .proof = .saltmarket },
    .{ .name = "grid", .proof = .grid },
    .{ .name = "castle-fire", .proof = .grid },
    .{ .name = "fire-escape", .proof = .grid },
    .{ .name = "observatory", .proof = .observatory },
    .{ .name = "larkspur", .proof = .observatory },
};

fn lookup(name: []const u8) ?Proof {
    for (aliases) |a| {
        if (std.mem.eql(u8, a.name, name)) return a.proof;
    }
    return null;
}

const usage =
    \\bespoke-proofs: proofs of concept for the BeSpoke Engine
    \\
    \\Usage:
    \\  bespoke-proofs [--<proof> | --scenario <proof>] [--headless]
    \\
    \\Proofs (default: --tavern):
    \\  --tavern             The Tavern Heist (relational spine, fibers, interrupts, rewind)
    \\  --spitting-contest   The Pip-Spitting Green (stageplay DSL, TTL triggers)
    \\  --borrowed-beard     The Borrowed Beard (crafting, multi-scene)
    \\  --sword-fighting     Brackwater Barbs (learned comebacks, mood decay)
    \\  --village            The Living Village (emergent drives, rumors, justice)
    \\  --lamp-point         The Donkey of Lamp Point (threat radius, retreat window)
    \\  --three-tides        The Well of Three Tides (party, item transfer, causality)
    \\  --weathercock        The Copper Weathercock (temporal hypervisor, conduits)
    \\  --bell-tower         The Bell Tower (musical drafts, distaff)
    \\  --grog               Caustic Grog (container degradation, pours, spill)
    \\  --saltmarket         The Saltmarket (three paths, route locks)
    \\  --grid               The Castle Fire Escape (grid fire, smoke, water, hazards)
    \\  --observatory        The Larkspur Observatory (agendas, pursuit, interception)
    \\
;

pub fn main() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var headless = false;
    var proof: Proof = .tavern;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--headless")) {
            headless = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "help")) {
            try stdout.writeAll(usage);
            return;
        } else if (std.mem.eql(u8, arg, "--scenario")) {
            const name = args.next() orelse {
                try stdout.writeAll("error: --scenario requires a proof name\n\n" ++ usage);
                std.process.exit(1);
            };
            proof = lookup(name) orelse {
                try stdout.print("error: unknown proof '{s}'\n\n" ++ usage, .{name});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, arg, "--") and lookup(arg[2..]) != null) {
            proof = lookup(arg[2..]).?;
        } else {
            try stdout.print("error: unknown argument '{s}'\n\n" ++ usage, .{arg});
            std.process.exit(1);
        }
    }

    switch (proof) {
        .tavern => try tavern_heist.run(allocator, stdout, headless),
        .spitting_contest => if (headless) try spitting_contest.run_headless(allocator, stdout) else try spitting_contest.run_gui(allocator, stdout),
        .borrowed_beard => if (headless) try borrowed_beard.run_headless(allocator, stdout) else try borrowed_beard.run_interactive(allocator, stdout),
        .sword_fighting => if (headless) try sword_fighting.run_headless(allocator, stdout) else try sword_fighting.run_interactive(allocator, stdout),
        .village => if (headless) try village.run_headless(allocator, stdout) else try village.run_interactive(allocator, stdout),
        .lamp_point => if (headless) try lamp_point.run_headless(allocator, stdout) else try lamp_point.run_interactive(allocator, stdout),
        .three_tides => if (headless) try three_tides.run_headless(allocator, stdout) else try three_tides.run_interactive(allocator),
        .weathercock => if (headless) try weathercock.run_headless(allocator, stdout) else try weathercock.run_interactive(allocator),
        .bell_tower => if (headless) try bell_tower.run_headless(allocator, stdout) else try bell_tower.run_interactive(allocator, stdout),
        .grog => if (headless) try grog_puzzle.run_headless(allocator, stdout) else try grog_puzzle.run_interactive(allocator, stdout),
        .saltmarket => if (headless) try saltmarket.run_headless(allocator, stdout) else try saltmarket.run_interactive(allocator, stdout),
        .grid => if (headless) try grid_puzzle.run_headless(allocator, stdout) else try grid_puzzle.run_interactive(allocator, stdout),
        .observatory => if (headless) try observatory_puzzle.run_headless(allocator, stdout) else try observatory_puzzle.run_interactive(allocator, stdout),
    }
}

test "proofs: every proof module compiles and its tests run" {
    _ = tavern_heist;
    _ = spitting_contest;
    _ = borrowed_beard;
    _ = sword_fighting;
    _ = village;
    _ = lamp_point;
    _ = three_tides;
    _ = weathercock;
    _ = bell_tower;
    _ = grog_puzzle;
    _ = saltmarket;
    _ = grid_puzzle;
    _ = observatory_puzzle;
    std.testing.refAllDecls(@This());
}

test {
    // Characterization goldens (P32-07). Referenced only from a test block, so the
    // bespoke-proofs executable never needs the test-only `golden_options` module.
    _ = @import("golden_test.zig");
    _ = @import("render_golden_test.zig");
    _ = @import("audio_golden_test.zig");
    _ = @import("wasm_golden_test.zig");
    _ = @import("music.zig");
}

test "proofs: legacy flag spellings resolve to the same proofs" {
    try std.testing.expectEqual(Proof.three_tides, lookup("tentacle").?);
    try std.testing.expectEqual(Proof.bell_tower, lookup("drafts").?);
    try std.testing.expectEqual(Proof.saltmarket, lookup("algiers").?);
    try std.testing.expectEqual(Proof.lamp_point, lookup("broken-sword").?);
    try std.testing.expectEqual(Proof.lamp_point, lookup("goat").?);
    try std.testing.expect(lookup("headless") == null);
}
