const std = @import("std");
const world_mod = @import("world.zig");
const EntityId = world_mod.EntityId;
const World = world_mod.World;

pub const WaypointId = u16;

pub const Point2D = struct {
    x: i32,
    y: i32,

    pub fn distance_to(self: Point2D, other: Point2D) u32 {
        const dx: u64 = @abs(self.x - other.x);
        const dy: u64 = @abs(self.y - other.y);
        return std.math.sqrt(dx * dx + dy * dy);
    }
};

pub const Waypoint = struct {
    id: WaypointId,
    room: EntityId,
    pos: Point2D,
    name: []const u8,
};

pub const Edge = struct {
    from: WaypointId,
    to: WaypointId,
    cost: u32,
};

pub const SpatialGraph = struct {
    allocator: std.mem.Allocator,
    waypoints: std.ArrayList(Waypoint),
    edges: std.ArrayList(Edge),

    pub fn init(allocator: std.mem.Allocator) SpatialGraph {
        return SpatialGraph{
            .allocator = allocator,
            .waypoints = std.ArrayList(Waypoint).init(allocator),
            .edges = std.ArrayList(Edge).init(allocator),
        };
    }

    pub fn deinit(self: *SpatialGraph) void {
        for (self.waypoints.items) |wp| {
            self.allocator.free(wp.name);
        }
        self.waypoints.deinit();
        self.edges.deinit();
    }

    /// Adds a waypoint in a given room.
    pub fn add_waypoint(self: *SpatialGraph, room: EntityId, x: i32, y: i32, name: []const u8) !WaypointId {
        const id: WaypointId = @intCast(self.waypoints.items.len + 1);
        const owned_name = try self.allocator.dupe(u8, name);
        try self.waypoints.append(.{
            .id = id,
            .room = room,
            .pos = .{ .x = x, .y = y },
            .name = owned_name,
        });
        return id;
    }

    /// Gets waypoint by ID.
    pub fn get_waypoint(self: *const SpatialGraph, id: WaypointId) ?Waypoint {
        if (id == 0 or id > self.waypoints.items.len) return null;
        return self.waypoints.items[id - 1];
    }

    /// Finds a waypoint by name.
    pub fn find_waypoint(self: *const SpatialGraph, name: []const u8) ?WaypointId {
        for (self.waypoints.items) |wp| {
            if (std.mem.eql(u8, wp.name, name)) return wp.id;
        }
        return null;
    }

    /// Counts waypoints in a given room/scene (P12-02, D-014).
    pub fn count_waypoints_in_room(self: *const SpatialGraph, room: EntityId) usize {
        var count: usize = 0;
        for (self.waypoints.items) |wp| {
            if (wp.room == room) count += 1;
        }
        return count;
    }

    /// Finds a waypoint by name within a specific room/scene (P12-02, D-014).
    pub fn find_waypoint_in_room(self: *const SpatialGraph, room: EntityId, name: []const u8) ?WaypointId {
        for (self.waypoints.items) |wp| {
            if (wp.room == room and std.mem.eql(u8, wp.name, name)) return wp.id;
        }
        return null;
    }

    /// Returns the first waypoint registered in a room/scene (P12-02, D-014).
    pub fn get_first_waypoint_in_room(self: *const SpatialGraph, room: EntityId) ?WaypointId {
        for (self.waypoints.items) |wp| {
            if (wp.room == room) return wp.id;
        }
        return null;
    }

    /// Connects two waypoints bidirectionally. If cost is null, uses Euclidean distance.
    pub fn connect(self: *SpatialGraph, a: WaypointId, b: WaypointId, cost: ?u32) !void {
        const wp_a = self.get_waypoint(a) orelse return error.WaypointNotFound;
        const wp_b = self.get_waypoint(b) orelse return error.WaypointNotFound;
        const c = cost orelse wp_a.pos.distance_to(wp_b.pos);

        try self.edges.append(.{ .from = a, .to = b, .cost = c });
        try self.edges.append(.{ .from = b, .to = a, .cost = c });
    }

    /// Finds optimal path between two waypoints using A* pathfinding (P3-01).
    pub fn find_path(
        self: *const SpatialGraph,
        start: WaypointId,
        goal: WaypointId,
        allocator: std.mem.Allocator,
    ) !?[]WaypointId {
        if (start == goal) {
            const result = try allocator.alloc(WaypointId, 1);
            result[0] = start;
            return result;
        }

        const goal_wp = self.get_waypoint(goal) orelse return null;
        const max_id = self.waypoints.items.len + 1;

        var open_set = std.AutoHashMap(WaypointId, void).init(allocator);
        defer open_set.deinit();
        try open_set.put(start, {});

        var came_from = try allocator.alloc(?WaypointId, max_id);
        defer allocator.free(came_from);
        @memset(came_from, null);

        var g_score = try allocator.alloc(u32, max_id);
        defer allocator.free(g_score);
        @memset(g_score, std.math.maxInt(u32));
        g_score[start] = 0;

        var f_score = try allocator.alloc(u32, max_id);
        defer allocator.free(f_score);
        @memset(f_score, std.math.maxInt(u32));
        const start_wp = self.get_waypoint(start) orelse return null;
        f_score[start] = start_wp.pos.distance_to(goal_wp.pos);

        while (open_set.count() > 0) {
            // Find lowest f_score in open_set
            var current: WaypointId = 0;
            var min_f: u32 = std.math.maxInt(u32);
            var it = open_set.keyIterator();
            while (it.next()) |k| {
                if (f_score[k.*] < min_f) {
                    min_f = f_score[k.*];
                    current = k.*;
                }
            }

            if (current == goal) {
                // Reconstruct path
                var path_list = std.ArrayList(WaypointId).init(allocator);
                defer path_list.deinit();
                var curr: ?WaypointId = goal;
                while (curr) |c| {
                    try path_list.append(c);
                    curr = came_from[c];
                }
                // Reverse to get start -> goal order
                std.mem.reverse(WaypointId, path_list.items);
                const slice = try path_list.toOwnedSlice();
                return slice;
            }

            _ = open_set.remove(current);

            // Explore neighbors
            for (self.edges.items) |edge| {
                if (edge.from == current) {
                    const neighbor = edge.to;
                    const tentative_g = g_score[current] + edge.cost;
                    if (tentative_g < g_score[neighbor]) {
                        came_from[neighbor] = current;
                        g_score[neighbor] = tentative_g;
                        const neighbor_wp = self.get_waypoint(neighbor) orelse continue;
                        f_score[neighbor] = tentative_g + neighbor_wp.pos.distance_to(goal_wp.pos);
                        try open_set.put(neighbor, {});
                    }
                }
            }
        }

        return null; // No path found
    }
};

/// Tracks active movement along a waypoint path for an entity (P3-02).
pub const MotorAgent = struct {
    entity: EntityId,
    pos: Point2D,
    current_wp: WaypointId,
    target_wp: ?WaypointId,
    path: ?[]WaypointId,
    path_index: usize,
    speed: u32, // units per tick
    is_moving: bool,
    arrived: bool,

    pub fn init(entity: EntityId, start_wp: WaypointId, pos: Point2D, speed: u32) MotorAgent {
        return MotorAgent{
            .entity = entity,
            .pos = pos,
            .current_wp = start_wp,
            .target_wp = null,
            .path = null,
            .path_index = 0,
            .speed = speed,
            .is_moving = false,
            .arrived = false,
        };
    }

    pub fn deinit(self: *MotorAgent, allocator: std.mem.Allocator) void {
        if (self.path) |p| {
            allocator.free(p);
            self.path = null;
        }
    }

    /// Sets a new path for this agent.
    pub fn set_path(self: *MotorAgent, allocator: std.mem.Allocator, path: []WaypointId) void {
        if (self.path) |p| allocator.free(p);
        self.path = path;
        // If first waypoint is current position, start moving toward second waypoint
        if (path.len > 0 and path[0] == self.current_wp) {
            self.path_index = 1;
        } else {
            self.path_index = 0;
        }
        self.is_moving = self.path_index < path.len;
        self.arrived = !self.is_moving;
        if (path.len > 0) {
            self.target_wp = path[path.len - 1];
        }
    }

    /// Advances movement by 1 tick (P3-02).
    pub fn step_tick(self: *MotorAgent, graph: *const SpatialGraph) void {
        if (!self.is_moving or self.path == null) return;
        const path = self.path.?;

        if (self.path_index >= path.len) {
            self.is_moving = false;
            self.arrived = true;
            return;
        }

        const next_wp_id = path[self.path_index];
        const next_wp = graph.get_waypoint(next_wp_id) orelse {
            self.is_moving = false;
            return;
        };

        const dist = self.pos.distance_to(next_wp.pos);
        if (dist <= self.speed) {
            // Reached this waypoint
            self.pos = next_wp.pos;
            self.current_wp = next_wp_id;
            self.path_index += 1;

            if (self.path_index >= path.len) {
                self.is_moving = false;
                self.arrived = true;
            }
        } else {
            // Step speed units toward next waypoint
            const dx = next_wp.pos.x - self.pos.x;
            const dy = next_wp.pos.y - self.pos.y;
            const move_x = @divTrunc(dx * @as(i32, @intCast(self.speed)), @as(i32, @intCast(dist)));
            const move_y = @divTrunc(dy * @as(i32, @intCast(self.speed)), @as(i32, @intCast(dist)));
            self.pos.x += move_x;
            self.pos.y += move_y;
        }
    }
};

/// A static interactable scene region / prop (P7-01, D-009).
pub const Hotspot = struct {
    entity: EntityId,
    room: EntityId,
    pos: Point2D,
    radius: u32,
    name: []const u8,
    examine_text: []const u8,
};

/// Manages spatial world navigation, motor intents, and hotspots (P3-01, P3-02, P7-01).
pub const SpatialSystem = struct {
    pub const Portal = struct {
        entity: EntityId,
        room: EntityId,
        waypoint: u16,
    };

    allocator: std.mem.Allocator,
    graph: SpatialGraph,
    agents: std.AutoHashMap(EntityId, MotorAgent),
    hotspots: std.ArrayList(Hotspot),
    portals: std.ArrayList(Portal),

    pub fn init(allocator: std.mem.Allocator) SpatialSystem {
        return SpatialSystem{
            .allocator = allocator,
            .graph = SpatialGraph.init(allocator),
            .agents = std.AutoHashMap(EntityId, MotorAgent).init(allocator),
            .hotspots = std.ArrayList(Hotspot).init(allocator),
            .portals = std.ArrayList(Portal).init(allocator),
        };
    }

    pub fn deinit(self: *SpatialSystem) void {
        var it = self.agents.valueIterator();
        while (it.next()) |agent| {
            agent.deinit(self.allocator);
        }
        self.agents.deinit();
        self.graph.deinit();
        for (self.hotspots.items) |h| {
            self.allocator.free(h.name);
            self.allocator.free(h.examine_text);
        }
        self.hotspots.deinit();
        self.portals.deinit();
    }

    /// Registers a transit portal (e.g. Chron-o-John or teleport pad) located at a waypoint (D-026).
    pub fn register_portal(self: *SpatialSystem, entity: EntityId, room: EntityId, waypoint: u16) !void {
        for (self.portals.items) |*p| {
            if (p.entity == entity) {
                p.room = room;
                p.waypoint = waypoint;
                return;
            }
        }
        try self.portals.append(.{
            .entity = entity,
            .room = room,
            .waypoint = waypoint,
        });
    }

    /// Finds a registered portal located within a room (D-026).
    pub fn get_portal_in_room(self: *const SpatialSystem, room: EntityId) ?Portal {
        for (self.portals.items) |p| {
            if (p.room == room) return p;
        }
        return null;
    }

    /// Registers a static scene hotspot / inspectable prop (P7-01, D-009).
    /// If a hotspot for this entity already exists, updates it in-place to prevent duplication.
    pub fn add_hotspot(
        self: *SpatialSystem,
        entity: EntityId,
        room: EntityId,
        pos: Point2D,
        radius: u32,
        name: []const u8,
        examine_text: []const u8,
    ) !void {
        for (self.hotspots.items) |*h| {
            if (h.entity == entity) {
                self.allocator.free(h.name);
                self.allocator.free(h.examine_text);
                h.room = room;
                h.pos = pos;
                h.radius = radius;
                h.name = try self.allocator.dupe(u8, name);
                h.examine_text = try self.allocator.dupe(u8, examine_text);
                return;
            }
        }
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_examine = try self.allocator.dupe(u8, examine_text);
        try self.hotspots.append(.{
            .entity = entity,
            .room = room,
            .pos = pos,
            .radius = radius,
            .name = owned_name,
            .examine_text = owned_examine,
        });
    }

    /// Finds a hotspot near a spatial position within its radius.
    pub fn find_hotspot_at(self: *const SpatialSystem, pos: Point2D) ?Hotspot {
        for (self.hotspots.items) |h| {
            if (h.pos.distance_to(pos) <= h.radius) {
                return h;
            }
        }
        return null;
    }

    /// Finds a hotspot near a spatial position within a specific room/scene (P12-02, D-014).
    pub fn find_hotspot_at_in_room(self: *const SpatialSystem, room: EntityId, pos: Point2D) ?Hotspot {
        for (self.hotspots.items) |h| {
            if (h.room == room and h.pos.distance_to(pos) <= h.radius) {
                return h;
            }
        }
        return null;
    }

    /// Counts hotspots in a specific room/scene (P12-02, D-014).
    pub fn count_hotspots_in_room(self: *const SpatialSystem, room: EntityId) usize {
        var count: usize = 0;
        for (self.hotspots.items) |h| {
            if (h.room == room) count += 1;
        }
        return count;
    }

    /// Repositions an actor onto an entry waypoint in a target scene/room (P12-02, D-014).
    pub fn transition_actor(self: *SpatialSystem, entity: EntityId, target_room: EntityId, entry_wp: ?WaypointId) !bool {
        const dest_wp_id = entry_wp orelse (self.graph.get_first_waypoint_in_room(target_room) orelse return false);
        const wp = self.graph.get_waypoint(dest_wp_id) orelse return false;

        if (self.agents.getPtr(entity)) |agent| {
            if (agent.path) |p| {
                self.allocator.free(p);
                agent.path = null;
            }
            agent.pos = wp.pos;
            agent.current_wp = dest_wp_id;
            agent.target_wp = null;
            agent.is_moving = false;
            agent.arrived = true;
            return true;
        } else {
            try self.register_entity(entity, dest_wp_id, 2);
            return true;
        }
    }

    /// Registers an entity at a starting waypoint.
    pub fn register_entity(
        self: *SpatialSystem,
        entity: EntityId,
        start_wp: WaypointId,
        speed: u32,
    ) !void {
        const wp = self.graph.get_waypoint(start_wp) orelse return error.WaypointNotFound;
        const agent = MotorAgent.init(entity, start_wp, wp.pos, speed);
        try self.agents.put(entity, agent);
    }

    /// Issues an asynchronous motor intent: walk entity to destination waypoint (P3-02).
    pub fn walk_to(self: *SpatialSystem, entity: EntityId, dest: WaypointId) !bool {
        const agent = self.agents.getPtr(entity) orelse return false;
        if (agent.current_wp == dest) {
            agent.arrived = true;
            return true;
        }

        const path = try self.graph.find_path(agent.current_wp, dest, self.allocator);
        if (path) |p| {
            agent.set_path(self.allocator, p);
            return true;
        }
        return false;
    }

    /// Advances all motor agents by 1 tick (P3-02).
    pub fn step_tick(self: *SpatialSystem) void {
        var it = self.agents.valueIterator();
        while (it.next()) |agent| {
            agent.step_tick(&self.graph);
        }
    }

    /// Policy governing party inventory transfers across entities (P21-01, D-025, D-026).
    pub const TransferPolicy = enum {
        remote,
        colocated,
        portal_anchored,
    };

    /// Evaluates whether two entities can transfer inventory under the given policy (P21-01, D-025, D-026).
    /// Remote transfers always succeed; colocated transfers require both entities to occupy the same room.
    pub fn can_transfer_item(
        self: *const SpatialSystem,
        from: EntityId,
        to: EntityId,
        policy: TransferPolicy,
    ) bool {
        return self.can_transfer_item_with_world(null, from, to, policy);
    }

    /// Evaluates inventory transfer eligibility with optional relational fact constraints (D-025, D-026).
    /// Under .portal_anchored, remote transfer succeeds transparently if both actors are co-located or
    /// both rooms possess registered transit portals and neither actor nor portal is blocked/trapped.
    pub fn can_transfer_item_with_world(
        self: *const SpatialSystem,
        world_opt: ?*const world_mod.World,
        from: EntityId,
        to: EntityId,
        policy: TransferPolicy,
    ) bool {
        switch (policy) {
            .remote => return true,
            .colocated => {
                const agent_from = self.agents.get(from) orelse return false;
                const agent_to = self.agents.get(to) orelse return false;
                const wp_from = self.graph.get_waypoint(agent_from.current_wp) orelse return false;
                const wp_to = self.graph.get_waypoint(agent_to.current_wp) orelse return false;
                return wp_from.room == wp_to.room;
            },
            .portal_anchored => {
                const agent_from = self.agents.get(from) orelse return false;
                const agent_to = self.agents.get(to) orelse return false;
                const wp_from = self.graph.get_waypoint(agent_from.current_wp) orelse return false;
                const wp_to = self.graph.get_waypoint(agent_to.current_wp) orelse return false;

                if (wp_from.room == wp_to.room) return true;

                const portal_from = self.get_portal_in_room(wp_from.room) orelse return false;
                const portal_to = self.get_portal_in_room(wp_to.room) orelse return false;

                if (world_opt) |world| {
                    if (world.lookup_relation("Trapped")) |trapped_rel| {
                        if (world.has_fact(from, trapped_rel, null)) return false;
                        if (world.has_fact(to, trapped_rel, null)) return false;
                    }
                    if (world.lookup_relation("PortalBlocked")) |blocked_rel| {
                        if (world.has_fact(portal_from.entity, blocked_rel, null)) return false;
                        if (world.has_fact(portal_to.entity, blocked_rel, null)) return false;
                    }
                }

                return true;
            },
        }
    }

    /// Checks if an entity is currently moving.
    pub fn is_moving(self: *const SpatialSystem, entity: EntityId) bool {
        if (self.agents.get(entity)) |agent| {
            return agent.is_moving;
        }
        return false;
    }

    /// Checks if an entity has reached its destination.
    pub fn has_arrived(self: *const SpatialSystem, entity: EntityId) bool {
        if (self.agents.get(entity)) |agent| {
            return agent.arrived;
        }
        return false;
    }

    /// Gets current position of an entity.
    pub fn get_position(self: *const SpatialSystem, entity: EntityId) ?Point2D {
        if (self.agents.get(entity)) |agent| {
            return agent.pos;
        }
        return null;
    }

    /// Gets current waypoint of an entity.
    pub fn get_current_waypoint(self: *const SpatialSystem, entity: EntityId) ?WaypointId {
        if (self.agents.get(entity)) |agent| {
            return agent.current_wp;
        }
        return null;
    }
};

// --- Unit Tests (P3-01, P3-02) ---

test "P3-01: spatial graph topology and A* pathfinding" {
    const testing = std.testing;
    var graph = SpatialGraph.init(testing.allocator);
    defer graph.deinit();

    const tavern = EntityId.from_int(1);
    const cellar = EntityId.from_int(2);

    // Create tavern waypoints
    const hearth = try graph.add_waypoint(tavern, 0, 0, "Hearth");
    const bar = try graph.add_waypoint(tavern, 50, 0, "Bar");
    const stairs = try graph.add_waypoint(tavern, 100, 0, "CellarStairs");

    // Create cellar waypoint
    const cellar_landing = try graph.add_waypoint(cellar, 100, 50, "CellarLanding");

    // Connect waypoints: Hearth <-> Bar <-> CellarStairs <-> CellarLanding
    try graph.connect(hearth, bar, null);
    try graph.connect(bar, stairs, null);
    try graph.connect(stairs, cellar_landing, null);

    // Find path: Hearth -> CellarLanding
    const path = (try graph.find_path(hearth, cellar_landing, testing.allocator)).?;
    defer testing.allocator.free(path);

    try testing.expectEqual(@as(usize, 4), path.len);
    try testing.expectEqual(hearth, path[0]);
    try testing.expectEqual(bar, path[1]);
    try testing.expectEqual(stairs, path[2]);
    try testing.expectEqual(cellar_landing, path[3]);
}

test "P3-02: motor agent stepping and walk intent arrival" {
    const testing = std.testing;
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const tavern = EntityId.from_int(1);
    const guard = EntityId.from_int(10);

    const wp1 = try spatial.graph.add_waypoint(tavern, 0, 0, "WP1");
    const wp2 = try spatial.graph.add_waypoint(tavern, 10, 0, "WP2");
    const wp3 = try spatial.graph.add_waypoint(tavern, 20, 0, "WP3");

    try spatial.graph.connect(wp1, wp2, null);
    try spatial.graph.connect(wp2, wp3, null);

    // Guard starts at WP1 with speed 5 units/tick
    try spatial.register_entity(guard, wp1, 5);
    try testing.expectEqual(wp1, spatial.get_current_waypoint(guard).?);
    try testing.expectEqual(@as(i32, 0), spatial.get_position(guard).?.x);

    // Command: walk Guard to WP3
    try testing.expect(try spatial.walk_to(guard, wp3));
    try testing.expect(spatial.is_moving(guard));

    // Tick 1: move 5 units toward WP2 (pos: x=5)
    spatial.step_tick();
    try testing.expectEqual(@as(i32, 5), spatial.get_position(guard).?.x);

    // Tick 2: move 5 units, reaches WP2 (pos: x=10)
    spatial.step_tick();
    try testing.expectEqual(@as(i32, 10), spatial.get_position(guard).?.x);
    try testing.expectEqual(wp2, spatial.get_current_waypoint(guard).?);

    // Tick 3: move 5 units toward WP3 (pos: x=15)
    spatial.step_tick();
    try testing.expectEqual(@as(i32, 15), spatial.get_position(guard).?.x);

    // Tick 4: reaches WP3 (pos: x=20), arrival complete!
    spatial.step_tick();
    try testing.expectEqual(@as(i32, 20), spatial.get_position(guard).?.x);
    try testing.expectEqual(wp3, spatial.get_current_waypoint(guard).?);
    try testing.expect(!spatial.is_moving(guard));
    try testing.expect(spatial.has_arrived(guard));
}

test "P7-01: spatial system registers and hit-tests scene hotspots" {
    const testing = std.testing;
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const tavern = EntityId.from_int(1);
    const fireplace = EntityId.from_int(50);

    try spatial.add_hotspot(
        fireplace,
        tavern,
        .{ .x = 0, .y = -5 },
        10,
        "Fireplace",
        "A roaring stone hearth.",
    );

    try testing.expectEqual(@as(usize, 1), spatial.hotspots.items.len);

    // Hit test within radius
    const hit = spatial.find_hotspot_at(.{ .x = 2, .y = -3 });
    try testing.expect(hit != null);
    try testing.expectEqual(fireplace, hit.?.entity);
    try testing.expectEqualStrings("Fireplace", hit.?.name);
    try testing.expectEqualStrings("A roaring stone hearth.", hit.?.examine_text);

    // Hit test outside radius
    const miss = spatial.find_hotspot_at(.{ .x = 50, .y = 50 });
    try testing.expect(miss == null);
}

test "P12-02: spatial graph room partitioning and actor transition between scenes" {
    const testing = std.testing;
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const tavern = EntityId.from_int(10);
    const cellar = EntityId.from_int(20);
    const guybrush = EntityId.from_int(100);

    // Add waypoints in tavern
    const hearth_wp = try spatial.graph.add_waypoint(tavern, 0, 0, "Hearth");
    const bar_wp = try spatial.graph.add_waypoint(tavern, 20, 0, "Bar");
    try spatial.graph.connect(hearth_wp, bar_wp, null);

    // Add waypoints in cellar
    const cellar_entry_wp = try spatial.graph.add_waypoint(cellar, 100, 50, "Cellar Entry");
    const casks_wp = try spatial.graph.add_waypoint(cellar, 120, 50, "Wine Casks");
    try spatial.graph.connect(cellar_entry_wp, casks_wp, null);

    // Add hotspots in each room
    try spatial.add_hotspot(EntityId.from_int(201), tavern, .{ .x = 0, .y = -5 }, 10, "Fireplace", "Warm flames.");
    try spatial.add_hotspot(EntityId.from_int(202), cellar, .{ .x = 120, .y = 45 }, 10, "Cask", "Old oak cask.");

    // Verify room partitioning counts and queries
    try testing.expectEqual(@as(usize, 2), spatial.graph.count_waypoints_in_room(tavern));
    try testing.expectEqual(@as(usize, 2), spatial.graph.count_waypoints_in_room(cellar));
    try testing.expectEqual(hearth_wp, spatial.graph.find_waypoint_in_room(tavern, "Hearth").?);
    try testing.expectEqual(casks_wp, spatial.graph.find_waypoint_in_room(cellar, "Wine Casks").?);
    try testing.expect(spatial.graph.find_waypoint_in_room(tavern, "Wine Casks") == null);

    try testing.expectEqual(@as(usize, 1), spatial.count_hotspots_in_room(tavern));
    try testing.expectEqual(@as(usize, 1), spatial.count_hotspots_in_room(cellar));
    try testing.expect(spatial.find_hotspot_at_in_room(tavern, .{ .x = 120, .y = 45 }) == null);
    try testing.expect(spatial.find_hotspot_at_in_room(cellar, .{ .x = 120, .y = 45 }) != null);

    // Register Guybrush in Tavern at Hearth
    try spatial.register_entity(guybrush, hearth_wp, 5);
    try testing.expectEqual(hearth_wp, spatial.get_current_waypoint(guybrush).?);

    // Transition Guybrush from Tavern to Cellar
    const ok = try spatial.transition_actor(guybrush, cellar, null);
    try testing.expect(ok);
    try testing.expectEqual(cellar_entry_wp, spatial.get_current_waypoint(guybrush).?);
    try testing.expectEqual(@as(i32, 100), spatial.get_position(guybrush).?.x);
    try testing.expectEqual(@as(i32, 50), spatial.get_position(guybrush).?.y);
    try testing.expect(spatial.has_arrived(guybrush));
}

test "P21-01: can_transfer_item respects remote and colocated policies" {
    const testing = std.testing;
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const room_past = EntityId.from_int(10);
    const room_present = EntityId.from_int(20);

    const wp_hoagie = try spatial.graph.add_waypoint(room_past, 0, 0, "ColonialDesk");
    const wp_bernard = try spatial.graph.add_waypoint(room_present, 100, 0, "MotelDesk");
    const wp_clerk = try spatial.graph.add_waypoint(room_present, 110, 0, "MotelLobby");

    const hoagie = EntityId.from_int(1);
    const bernard = EntityId.from_int(2);
    const clerk = EntityId.from_int(3);

    try spatial.register_entity(hoagie, wp_hoagie, 2);
    try spatial.register_entity(bernard, wp_bernard, 2);
    try spatial.register_entity(clerk, wp_clerk, 2);

    // Remote policy: can transfer across different rooms/eras (e.g. Chron-o-John)
    try testing.expect(spatial.can_transfer_item(hoagie, bernard, .remote));
    try testing.expect(spatial.can_transfer_item(bernard, hoagie, .remote));

    // Colocated policy: hoagie and bernard are in different rooms -> fails
    try testing.expect(!spatial.can_transfer_item(hoagie, bernard, .colocated));

    // Colocated policy: bernard and clerk are both in room_present -> succeeds
    try testing.expect(spatial.can_transfer_item(bernard, clerk, .colocated));
}

test "D-026: can_transfer_item respects portal_anchored policy and relational constraints" {
    const testing = std.testing;
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    const room_1790 = EntityId.from_int(10);
    const room_1993 = EntityId.from_int(20);
    const room_2193 = EntityId.from_int(30);
    const room_void = EntityId.from_int(40);

    const wp_hoagie = try spatial.graph.add_waypoint(room_1790, 0, 0, "ColonialWp");
    const wp_toilet_1790 = try spatial.graph.add_waypoint(room_1790, 10, 0, "Toilet1790");
    const wp_bernard = try spatial.graph.add_waypoint(room_1993, 100, 0, "MotelDesk");
    const wp_toilet_1993 = try spatial.graph.add_waypoint(room_1993, 110, 0, "Toilet1993");
    const wp_laverne = try spatial.graph.add_waypoint(room_2193, 200, 0, "GuardPost");
    const wp_toilet_2193 = try spatial.graph.add_waypoint(room_2193, 210, 0, "Toilet2193");
    const wp_drifter = try spatial.graph.add_waypoint(room_void, 300, 0, "VoidSpot");

    const hoagie = EntityId.from_int(1);
    const bernard = EntityId.from_int(2);
    const laverne = EntityId.from_int(3);
    const drifter = EntityId.from_int(4);

    try spatial.register_entity(hoagie, wp_hoagie, 2);
    try spatial.register_entity(bernard, wp_bernard, 2);
    try spatial.register_entity(laverne, wp_laverne, 2);
    try spatial.register_entity(drifter, wp_drifter, 2);

    const portal_1790 = EntityId.from_int(101);
    const portal_1993 = EntityId.from_int(102);
    const portal_2193 = EntityId.from_int(103);

    try spatial.register_portal(portal_1790, room_1790, wp_toilet_1790);
    try spatial.register_portal(portal_1993, room_1993, wp_toilet_1993);
    try spatial.register_portal(portal_2193, room_2193, wp_toilet_2193);

    // 1. Both Hoagie and Bernard have portals in their respective rooms -> succeeds
    try testing.expect(spatial.can_transfer_item_with_world(&world, hoagie, bernard, .portal_anchored));
    try testing.expect(spatial.can_transfer_item_with_world(&world, bernard, hoagie, .portal_anchored));

    // 2. Drifter is in room_void without a portal -> transfer fails under portal_anchored
    try testing.expect(!spatial.can_transfer_item_with_world(&world, bernard, drifter, .portal_anchored));
    try testing.expect(!spatial.can_transfer_item_with_world(&world, drifter, bernard, .portal_anchored));

    // 3. Relational constraint: Laverne is trapped in tree -> transfer fails
    const trapped_rel = try world.intern_relation("Trapped", .set);
    _ = try world.remember(laverne, trapped_rel, 1, 0);
    try testing.expect(!spatial.can_transfer_item_with_world(&world, bernard, laverne, .portal_anchored));
    try testing.expect(!spatial.can_transfer_item_with_world(&world, laverne, bernard, .portal_anchored));

    // 4. Laverne freed from tree -> transfer succeeds
    _ = world.forget(laverne, trapped_rel, 1);
    try testing.expect(spatial.can_transfer_item_with_world(&world, bernard, laverne, .portal_anchored));

    // 5. Relational constraint: 1790 portal blocked/unpowered -> transfer fails
    const blocked_rel = try world.intern_relation("PortalBlocked", .set);
    _ = try world.remember(portal_1790, blocked_rel, 1, 0);
    try testing.expect(!spatial.can_transfer_item_with_world(&world, hoagie, bernard, .portal_anchored));

    // Unblock 1790 portal -> succeeds again
    _ = world.forget(portal_1790, blocked_rel, 1);
    try testing.expect(spatial.can_transfer_item_with_world(&world, hoagie, bernard, .portal_anchored));
}
