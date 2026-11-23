//! The run's source of chance (P48-14, D-168, D-184).
//!
//! `roll` draws from one generator per run. Scripts never seed it: a run starts from a seed the
//! host chooses (42 unless a host, `bespoke run --seed`, or a windowed game's clock says
//! otherwise), and a save or rewind snapshot records the seed and the generator's state, so a
//! load continues the same run and a rewind replays the same rolls. A branch world rolls from a
//! generator of its own whose seed is mixed from the run's seed and the tick it opens, so the
//! branch draws nothing from the present.
const std = @import("std");

pub const DEFAULT_SEED: u64 = 42;

/// Bytes `write` emits: the seed and the generator's four words.
pub const ENCODED_LEN = 8 + 4 * 8;

pub const Dice = struct {
    seed: u64,
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) Dice {
        return .{ .seed = seed, .prng = std.Random.DefaultPrng.init(seed) };
    }

    /// One die of `sides`, from 1 to `sides`. The arithmetic is the one `roll` has always
    /// used, so seed 42 reproduces every transcript written before saves kept the generator.
    pub fn roll(self: *Dice, sides: u32) u32 {
        return (self.prng.random().int(u32) % sides) + 1;
    }

    pub fn write(self: Dice, writer: anytype) !void {
        try writer.writeInt(u64, self.seed, .little);
        for (self.prng.s) |word| try writer.writeInt(u64, word, .little);
    }

    /// Untrusted input. Any seed is valid; an all-zero state is the one state the generator
    /// never leaves, so it is refused rather than rolling ones forever.
    pub fn read(reader: anytype) !Dice {
        var dice = Dice{ .seed = try reader.takeInt(u64, .little), .prng = undefined };
        for (&dice.prng.s) |*word| word.* = try reader.takeInt(u64, .little);
        if (std.mem.allEqual(u64, &dice.prng.s, 0)) return error.InvalidDice;
        return dice;
    }
};

/// A branch's seed: the run's seed and the tick the branch opens, mixed so nearby ticks give
/// unrelated sequences (D-184). Opening a branch draws nothing from the present's generator.
pub fn branch_seed(run_seed: u64, tick: u64) u64 {
    var x = run_seed ^ (tick +% 0x9E37_79B9_7F4A_7C15);
    x = (x ^ (x >> 30)) *% 0xBF58_476D_1CE4_E5B9;
    x = (x ^ (x >> 27)) *% 0x94D0_49BB_1331_11EB;
    return x ^ (x >> 31);
}

test "P48-14: dice restored from their bytes roll on exactly as the originals" {
    var dice = Dice.init(DEFAULT_SEED);
    _ = dice.roll(6);
    var buf: [ENCODED_LEN]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try dice.write(&w);
    var r: std.Io.Reader = .fixed(&buf);
    var copy = try Dice.read(&r);
    for (0..20) |_| try std.testing.expectEqual(dice.roll(20), copy.roll(20));
    try std.testing.expectEqual(DEFAULT_SEED, copy.seed);

    var zero: [ENCODED_LEN]u8 = @splat(0);
    var zr: std.Io.Reader = .fixed(&zero);
    try std.testing.expectError(error.InvalidDice, Dice.read(&zr));
    try std.testing.expect(branch_seed(42, 10) != branch_seed(42, 11));
    try std.testing.expectEqual(branch_seed(7, 3), branch_seed(7, 3));
}
