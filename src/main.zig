const std = @import("std");
const bespoke = @import("root.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== BeSpoke Engine v0.1.0-dev (Engine-as-Spine) ===\n\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    try stdout.print("1. Initialized World arena ({d} KB pre-allocated)\n", .{bespoke.world.DEFAULT_ARENA_SIZE / 1024});

    // 1. Intern Entities and Relations
    const guard = try world.intern_entity("Guard");
    const cheese = try world.intern_entity("Cheese");
    const bard = try world.intern_entity("Bard");
    const carries = try world.intern_relation("Carries", .set);
    const alertness = try world.intern_relation("Alertness", .property);
    const charmed = try world.intern_relation("CharmedBy", .set);

    try stdout.print("   - Entities: Guard ({d}), Cheese ({d}), Bard ({d})\n", .{
        guard.to_int(),
        cheese.to_int(),
        bard.to_int(),
    });
    try stdout.print("   - Relations: Carries (set), Alertness (property), CharmedBy (set)\n\n", .{});

    // 2. Declarative Mutations (P1-02, D-003, D-007)
    try world.remember(guard, carries, cheese.to_int(), 0); // Permanent
    try world.remember(guard, alertness, 100, 0); // Property
    try world.remember(guard, charmed, bard.to_int(), 3); // Expires in 3 ticks

    try stdout.print("2. Mutated Relational World (Active facts: {d})\n", .{world.fact_count()});
    try stdout.print("   - Guard carries Cheese (permanent)\n", .{});
    try stdout.print("   - Guard alertness: {d}%\n", .{world.get_property(guard, alertness).?});
    try stdout.print("   - Guard charmed by Bard for 3 ticks\n\n", .{});

    // 3. Pattern Matching Query (P1-03, D-006)
    try stdout.print("3. Querying Relational State:\n", .{});
    if (world.find_first(guard, carries, null)) |match| {
        try stdout.print("   - Pattern query: Carries(Guard, _) -> Found item {d} ({s})\n", .{
            match.object_or_value,
            world.get_entity_name(bespoke.EntityId.from_int(match.object_or_value)).?,
        });
    }

    // 4. Deterministic Save Snapshot (P1-04, D-001)
    var snapshot_buf = std.ArrayList(u8).init(allocator);
    defer snapshot_buf.deinit();
    try world.save_state(snapshot_buf.writer());
    try stdout.print("4. Saved state snapshot at tick {d} ({d} bytes)\n\n", .{
        world.current_tick,
        snapshot_buf.items.len,
    });

    // 5. Advance Simulation Clock and TTL Decay
    try stdout.print("5. Stepping simulation ticks:\n", .{});
    for (1..5) |t| {
        const pruned = world.step_tick();
        try stdout.print("   - Tick {d}: Guard charmed? {s} (pruned {d} expired facts)\n", .{
            t,
            if (world.has_fact(guard, charmed, bard.to_int())) "YES" else "NO (expired)",
            pruned,
        });
    }
    try stdout.print("   - Post-decay active facts: {d}\n\n", .{world.fact_count()});

    // 6. Time-Travel Restore from Snapshot (D-001)
    var read_stream = std.io.fixedBufferStream(snapshot_buf.items);
    try world.restore_state(read_stream.reader());
    try stdout.print("6. Rewound world to snapshot at tick {d}!\n", .{world.current_tick});
    try stdout.print("   - Restored active facts: {d}\n", .{world.fact_count()});
    try stdout.print("   - Guard charmed? {s}\n", .{
        if (world.has_fact(guard, charmed, bard.to_int())) "YES" else "NO",
    });
}
