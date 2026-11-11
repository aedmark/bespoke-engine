//! The state inspector's graph: which facts become nodes, edges, and listed values, and where
//! each node is drawn (P27-01, D-058). Pure functions over a frame's captured facts, so the
//! layout is testable without a window and every redraw of the same state is identical.

const std = @import("std");
const display = @import("../display.zig");
const world_mod = @import("../world.zig");

pub const EntityId = world_mod.EntityId;
pub const RenderDebugFact = display.RenderDebugFact;

pub const MAX_RING: usize = 16;
pub const MAX_EDGES: usize = 64;
pub const MAX_LISTED: usize = 14;
pub const MAX_NEXT: usize = 6;

pub const BELIEF_RELATIONS = [_][]const u8{ "Believes", "Knows", "Rejects" };

pub fn is_belief(fact: *const RenderDebugFact) bool {
    for (BELIEF_RELATIONS) |b| if (std.mem.eql(u8, b, fact.get_relation())) return true;
    return false;
}

/// How long a fact has left, for colouring (D-058 point 3).
pub const Band = enum { permanent, fresh, waning, ending, expired };

pub fn band(fact: *const RenderDebugFact, now: u64) Band {
    if (fact.recently_expired) return .expired;
    if (fact.expires_at_tick == 0) return .permanent;
    const left = fact.expires_at_tick -| now;
    if (left >= 60) return .fresh;
    if (left >= 20) return .waning;
    return .ending;
}

fn is_edge(fact: *const RenderDebugFact) bool {
    // Dialogue branch entities are an inspector persistence detail. Their human-readable text
    // belongs in the dialogue panel, not as extra nodes that can steal the graph's default focus.
    if (std.mem.eql(u8, fact.get_relation(), "DialogueBranchText") or
        std.mem.eql(u8, fact.get_relation(), "DialogueBranchFailure")) return false;
    return fact.object_is_entity and EntityId.from_int(fact.object_raw) != fact.subject;
}

/// The entity with the most edges, lowest id on ties; null when no fact links two entities.
pub fn default_focus(facts: []const RenderDebugFact) ?EntityId {
    var best: ?EntityId = null;
    var best_degree: usize = 0;
    for (facts) |*candidate_fact| {
        if (!is_edge(candidate_fact)) continue;
        for ([_]EntityId{ candidate_fact.subject, EntityId.from_int(candidate_fact.object_raw) }) |entity| {
            var degree: usize = 0;
            for (facts) |*f| {
                if (!is_edge(f)) continue;
                if (f.subject == entity or EntityId.from_int(f.object_raw) == entity) degree += 1;
            }
            const better = degree > best_degree or (degree == best_degree and best != null and entity.to_int() < best.?.to_int());
            if (best == null or better) {
                best = entity;
                best_degree = degree;
            }
        }
    }
    return best;
}

/// The name a frame knows for an entity, from any fact that mentions it.
pub fn name_of(facts: []const RenderDebugFact, entity: EntityId) []const u8 {
    for (facts) |*f| {
        if (f.subject == entity and f.subject_len > 0) return f.get_subject();
        if (f.object_is_entity and EntityId.from_int(f.object_raw) == entity) return f.get_object();
    }
    return "?";
}

pub const Node = struct {
    entity: EntityId,
    x: i32,
    y: i32,
};

pub const Edge = struct {
    /// Ring index of the other end; the centre is always one end.
    ring: usize,
    /// Index into the frame's facts.
    fact: usize,
    /// True when the centre is the subject (the arrow points outward).
    outward: bool,
};

pub const Layout = struct {
    center: Node,
    ring: [MAX_RING]Node = undefined,
    ring_len: usize = 0,
    /// Neighbours that did not fit on the ring.
    hidden_neighbours: usize = 0,
    edges: [MAX_EDGES]Edge = undefined,
    edge_len: usize = 0,
    /// Facts about the centre whose object is a value or nothing (a state).
    listed: [MAX_LISTED]usize = undefined,
    listed_len: usize = 0,
    hidden_listed: usize = 0,

    pub fn ring_nodes(self: *const Layout) []const Node {
        return self.ring[0..self.ring_len];
    }
};

/// Lays out `focus` and its neighbours (D-058 point 4): the focus at (cx, cy), neighbours on an
/// ellipse of radii (rx, ry) in entity-id order, starting at the top and going clockwise.
pub fn build(facts: []const RenderDebugFact, focus: EntityId, cx: i32, cy: i32, rx: i32, ry: i32) Layout {
    var layout = Layout{ .center = .{ .entity = focus, .x = cx, .y = cy } };

    // Neighbours in id order, so the picture does not depend on fact-table order.
    var neighbours: [MAX_EDGES]EntityId = undefined;
    var n: usize = 0;
    for (facts) |*f| {
        if (!is_edge(f)) continue;
        const other = if (f.subject == focus) EntityId.from_int(f.object_raw) else if (EntityId.from_int(f.object_raw) == focus) f.subject else continue;
        if (std.mem.indexOfScalar(EntityId, neighbours[0..n], other) != null) continue;
        if (n == neighbours.len) break;
        neighbours[n] = other;
        n += 1;
    }
    std.mem.sort(EntityId, neighbours[0..n], {}, struct {
        fn lt(_: void, a: EntityId, b: EntityId) bool {
            return a.to_int() < b.to_int();
        }
    }.lt);
    layout.ring_len = @min(n, MAX_RING);
    layout.hidden_neighbours = n - layout.ring_len;
    for (neighbours[0..layout.ring_len], 0..) |entity, i| {
        const angle = -std.math.pi / 2.0 + 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(layout.ring_len));
        layout.ring[i] = .{
            .entity = entity,
            .x = cx + @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(rx)) * @cos(angle)))),
            .y = cy + @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(ry)) * @sin(angle)))),
        };
    }

    for (facts, 0..) |*f, i| {
        if (is_edge(f)) {
            const outward = f.subject == focus;
            const other = if (outward) EntityId.from_int(f.object_raw) else if (EntityId.from_int(f.object_raw) == focus) f.subject else continue;
            for (layout.ring_nodes(), 0..) |node, r| {
                if (node.entity != other) continue;
                if (layout.edge_len < MAX_EDGES) {
                    layout.edges[layout.edge_len] = .{ .ring = r, .fact = i, .outward = outward };
                    layout.edge_len += 1;
                }
                break;
            }
        } else if (f.subject == focus) {
            if (layout.listed_len < MAX_LISTED) {
                layout.listed[layout.listed_len] = i;
                layout.listed_len += 1;
            } else layout.hidden_listed += 1;
        }
    }
    return layout;
}

pub const ExpiryList = struct {
    facts: [MAX_NEXT]usize = undefined,
    len: usize = 0,
    hidden: usize = 0,
};

fn expires_before(facts: []const RenderDebugFact, a: usize, b: usize) bool {
    const left = facts[a];
    const right = facts[b];
    if (left.expires_at_tick != right.expires_at_tick) return left.expires_at_tick < right.expires_at_tick;
    if (left.subject != right.subject) return left.subject.to_int() < right.subject.to_int();
    const rel_order = std.mem.order(u8, left.get_relation(), right.get_relation());
    if (rel_order != .eq) return rel_order == .lt;
    return left.object_raw < right.object_raw;
}

/// The next live fact expirations in deterministic order (D-058 point 5). This projects only
/// deadlines already present in World state; it never speculatively executes a future tick.
pub fn next_expiring(facts: []const RenderDebugFact, now: u64) ExpiryList {
    var candidates: [display.MAX_DEBUG_FACTS]usize = undefined;
    var count: usize = 0;
    for (facts, 0..) |fact, i| {
        if (fact.recently_expired or fact.expires_at_tick == 0 or fact.expires_at_tick <= now) continue;
        candidates[count] = i;
        count += 1;
    }

    // The frame is capped at 128 facts, so insertion sort is small and keeps this helper
    // allocation-free for the renderer.
    var i: usize = 1;
    while (i < count) : (i += 1) {
        const candidate = candidates[i];
        var j = i;
        while (j > 0 and expires_before(facts, candidate, candidates[j - 1])) : (j -= 1) {
            candidates[j] = candidates[j - 1];
        }
        candidates[j] = candidate;
    }

    var out = ExpiryList{};
    out.len = @min(count, MAX_NEXT);
    out.hidden = count - out.len;
    @memcpy(out.facts[0..out.len], candidates[0..out.len]);
    return out;
}

const testing = std.testing;

fn test_fact(subject: u32, subject_name: []const u8, relation: []const u8, object: u32, object_name: ?[]const u8, expires: u64) RenderDebugFact {
    var f = RenderDebugFact{
        .subject_name = undefined,
        .subject_len = @intCast(subject_name.len),
        .relation_name = undefined,
        .relation_len = @intCast(relation.len),
        .object_name = undefined,
        .object_len = 0,
        .expires_at_tick = expires,
        .subject = EntityId.from_int(subject),
        .object_raw = object,
        .object_is_entity = object_name != null,
    };
    @memcpy(f.subject_name[0..subject_name.len], subject_name);
    @memcpy(f.relation_name[0..relation.len], relation);
    if (object_name) |on| {
        @memcpy(f.object_name[0..on.len], on);
        f.object_len = @intCast(on.len);
    }
    return f;
}

test "P27-01: the default focus is the best-connected entity and the layout is deterministic" {
    const facts = [_]RenderDebugFact{
        test_fact(5, "Ines", "Carries", 9, "Slip", 0),
        test_fact(5, "Ines", "Believes", 12, "PellAlibi", 0),
        test_fact(7, "Pell", "Pursuing", 0, null, 0),
        test_fact(8, "Halloran", "Warned", 5, "Ines", 30),
        test_fact(5, "Ines", "Volume", 3, null, 0),
        test_fact(9, "Slip", "LyingIn", 11, "Archive", 0),
    };
    const focus = default_focus(&facts).?;
    try testing.expectEqual(EntityId.from_int(5), focus);
    try testing.expectEqualStrings("Ines", name_of(&facts, focus));
    try testing.expectEqualStrings("Archive", name_of(&facts, EntityId.from_int(11)));

    const a = build(&facts, focus, 400, 300, 200, 140);
    // Three neighbours in id order: Halloran (8), Slip (9), PellAlibi (12); the first at the top.
    try testing.expectEqual(@as(usize, 3), a.ring_len);
    try testing.expectEqual(EntityId.from_int(8), a.ring[0].entity);
    try testing.expectEqual(@as(i32, 400), a.ring[0].x);
    try testing.expectEqual(@as(i32, 160), a.ring[0].y);
    try testing.expectEqual(EntityId.from_int(12), a.ring[2].entity);
    // Three edges touch the centre; Halloran's points inward. Slip's own edge is not drawn.
    try testing.expectEqual(@as(usize, 3), a.edge_len);
    for (a.edges[0..a.edge_len]) |e| {
        if (a.ring[e.ring].entity == EntityId.from_int(8)) try testing.expect(!e.outward);
    }
    // The value fact about Ines is listed, not drawn as an edge.
    try testing.expectEqual(@as(usize, 1), a.listed_len);
    try testing.expectEqualStrings("Volume", facts[a.listed[0]].get_relation());

    // The same facts in another order give the same picture.
    const shuffled = [_]RenderDebugFact{ facts[5], facts[3], facts[1], facts[4], facts[0], facts[2] };
    const b = build(&shuffled, focus, 400, 300, 200, 140);
    for (a.ring_nodes(), b.ring_nodes()) |na, nb| try testing.expectEqual(na, nb);
}

test "P27-01: facts are banded by remaining ticks and beliefs are recognised" {
    var f = test_fact(1, "A", "Believes", 2, "B", 0);
    try testing.expectEqual(Band.permanent, band(&f, 10));
    try testing.expect(is_belief(&f));
    f.expires_at_tick = 100;
    try testing.expectEqual(Band.fresh, band(&f, 40));
    try testing.expectEqual(Band.waning, band(&f, 41));
    try testing.expectEqual(Band.ending, band(&f, 81));
    f.recently_expired = true;
    try testing.expectEqual(Band.expired, band(&f, 81));
    const carries = test_fact(1, "A", "Carries", 2, "B", 0);
    try testing.expect(!is_belief(&carries));
}

test "P27-02: next-to-happen facts are ordered by expiry then stable fact identity" {
    var expired = test_fact(9, "Old", "Gone", 0, null, 2);
    expired.recently_expired = true;
    const facts = [_]RenderDebugFact{
        test_fact(3, "C", "Later", 0, null, 30),
        test_fact(2, "B", "SameTick", 0, null, 12),
        test_fact(1, "A", "Soon", 0, null, 8),
        test_fact(1, "A", "SameTick", 0, null, 12),
        test_fact(4, "D", "Permanent", 0, null, 0),
        expired,
    };
    const next = next_expiring(&facts, 5);
    try testing.expectEqual(@as(usize, 4), next.len);
    try testing.expectEqualStrings("Soon", facts[next.facts[0]].get_relation());
    try testing.expectEqual(EntityId.from_int(1), facts[next.facts[1]].subject);
    try testing.expectEqual(EntityId.from_int(2), facts[next.facts[2]].subject);
    try testing.expectEqualStrings("Later", facts[next.facts[3]].get_relation());
}

test "P27-02: persisted dialogue branch metadata never steals graph focus" {
    const facts = [_]RenderDebugFact{
        test_fact(1, "Actor", "Carries", 2, "Key", 0),
        test_fact(50, "Actor~0", "DialogueBranchText", 60, "Ask about the key", 0),
        test_fact(50, "Actor~0", "DialogueBranchFailure", 61, "missing Carries", 0),
    };
    try testing.expectEqual(EntityId.from_int(1), default_focus(&facts).?);
}
