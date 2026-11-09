//! `bespoke-proofs`: launcher for the engine's proofs of concept (D-031).
//!
//! Each proof is an empirical demonstration that an engine feature exists and works as
//! advertised. Proofs consume the engine only through the `bespoke` module; the engine never
//! imports a proof (the compiler enforces this: `proofs/` lies outside the module's path).
const std = @import("std");

pub const tavern_heist = @import("tavern_heist.zig");
pub const spitting_contest = @import("spitting_contest.zig");
pub const gk3_moustache = @import("gk3_moustache.zig");
pub const sword_fighting = @import("sword_fighting.zig");
pub const village = @import("village.zig");
pub const goat_puzzle = @import("goat_puzzle.zig");
pub const dott_puzzle = @import("dott_puzzle.zig");
pub const darko_puzzle = @import("darko_puzzle.zig");
pub const loom_puzzle = @import("loom_puzzle.zig");

const Proof = enum {
    tavern,
    spitting_contest,
    gk3,
    sword_fighting,
    village,
    goat,
    dott,
    darko,
    loom,
};

/// Flag spellings carried over from the pre-D-031 `bespoke` CLI, so existing commands keep working
/// with the binary name changed.
const aliases = [_]struct { name: []const u8, proof: Proof }{
    .{ .name = "tavern", .proof = .tavern },
    .{ .name = "tavern-heist", .proof = .tavern },
    .{ .name = "spitting-contest", .proof = .spitting_contest },
    .{ .name = "spit", .proof = .spitting_contest },
    .{ .name = "gk3", .proof = .gk3 },
    .{ .name = "cat-moustache", .proof = .gk3 },
    .{ .name = "sword-fighting", .proof = .sword_fighting },
    .{ .name = "insults", .proof = .sword_fighting },
    .{ .name = "sword", .proof = .sword_fighting },
    .{ .name = "village", .proof = .village },
    .{ .name = "living-village", .proof = .village },
    .{ .name = "goat", .proof = .goat },
    .{ .name = "goat-puzzle", .proof = .goat },
    .{ .name = "broken-sword", .proof = .goat },
    .{ .name = "dott", .proof = .dott },
    .{ .name = "tentacle", .proof = .dott },
    .{ .name = "chrono-mansion", .proof = .dott },
    .{ .name = "darko", .proof = .darko },
    .{ .name = "donnie-darko", .proof = .darko },
    .{ .name = "middlesex", .proof = .darko },
    .{ .name = "loom", .proof = .loom },
    .{ .name = "bell-tower", .proof = .loom },
    .{ .name = "drafts", .proof = .loom },
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
    \\  --spitting-contest   Booty Island Spitting Contest (stageplay DSL, TTL triggers)
    \\  --gk3                Gabriel Knight 3 Cat Moustache (crafting, multi-scene)
    \\  --sword-fighting     Insult Sword Fighting (epistemic dialogue, mood decay)
    \\  --village            The Living Village (emergent drives, rumors, justice)
    \\  --goat               Broken Sword Lochmarne Goat (threat radius, retreat window)
    \\  --dott               Day of the Tentacle Trio (party, item transfer, causality)
    \\  --darko              The Middlesex Anomaly (temporal hypervisor, conduits)
    \\  --loom               The Bell Tower (musical drafts, distaff)
    \\
;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
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
        .gk3 => if (headless) try gk3_moustache.run_headless(allocator, stdout) else try gk3_moustache.run_interactive(allocator, stdout),
        .sword_fighting => if (headless) try sword_fighting.run_headless(allocator, stdout) else try sword_fighting.run_interactive(allocator, stdout),
        .village => if (headless) try village.run_headless(allocator, stdout) else try village.run_interactive(allocator, stdout),
        .goat => if (headless) try goat_puzzle.run_headless(allocator, stdout) else try goat_puzzle.run_interactive(allocator, stdout),
        .dott => if (headless) try dott_puzzle.run_headless(allocator, stdout) else try dott_puzzle.run_interactive(allocator),
        .darko => if (headless) try darko_puzzle.run_headless(allocator, stdout) else try darko_puzzle.run_interactive(allocator),
        .loom => if (headless) try loom_puzzle.run_headless(allocator, stdout) else try loom_puzzle.run_interactive(allocator, stdout),
    }
}

test "proofs: every proof module compiles and its tests run" {
    _ = tavern_heist;
    _ = spitting_contest;
    _ = gk3_moustache;
    _ = sword_fighting;
    _ = village;
    _ = goat_puzzle;
    _ = dott_puzzle;
    _ = darko_puzzle;
    _ = loom_puzzle;
    std.testing.refAllDecls(@This());
}

test "proofs: legacy flag spellings resolve to the same proofs" {
    try std.testing.expectEqual(Proof.dott, lookup("tentacle").?);
    try std.testing.expectEqual(Proof.loom, lookup("bell-tower").?);
    try std.testing.expectEqual(Proof.goat, lookup("broken-sword").?);
    try std.testing.expect(lookup("headless") == null);
}
