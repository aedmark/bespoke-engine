//! The last line of every proof's headless transcript (P34-01): the final fact table's size
//! and digest (`bespoke.host.fact_digest`), so a golden catches a changed fact that no other
//! line prints.
const std = @import("std");
const bespoke = @import("bespoke");

/// Test seam for the golden test: when set, it changes the world just before the digest is
/// taken, so the test can show that one altered fact fails the golden. Null outside that test.
pub var tamper: ?*const fn (world: *bespoke.World) anyerror!void = null;

pub fn final_facts(allocator: std.mem.Allocator, writer: anytype, world: *bespoke.World) !void {
    if (tamper) |alter| try alter(world);
    const digest = try bespoke.host.fact_digest(allocator, world);
    try writer.print("final facts: {d}, digest {x:0>16}\n", .{ world.fact_count(), digest });
}
