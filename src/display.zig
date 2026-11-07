const std = @import("std");
const world_mod = @import("world.zig");
const spatial_mod = @import("spatial.zig");
const vm_mod = @import("vm.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const SpatialSystem = spatial_mod.SpatialSystem;
pub const WaypointId = spatial_mod.WaypointId;
pub const VM = vm_mod.VM;
pub const EmittedCue = vm_mod.EmittedCue;

pub const font = @import("display/font.zig");
pub const renderer = @import("display/renderer.zig");
pub const DisplayWindow = renderer.DisplayWindow;
pub const UserAction = renderer.UserAction;

/// A lightweight, read-only representation of an entity for display peripherals (D-001, P5-01).
pub const RenderEntity = struct {
    entity: EntityId,
    name: [32]u8,
    name_len: u8,
    x: i32,
    y: i32,
    current_wp: WaypointId,
    is_moving: bool,

    pub fn get_name(self: *const RenderEntity) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// A read-only representation of a waypoint node for peripheral rendering (D-001, D-005, P6-02).
pub const RenderWaypoint = struct {
    id: WaypointId,
    room: EntityId,
    x: i32,
    y: i32,
    name: [32]u8,
    name_len: u8,

    pub fn get_name(self: *const RenderWaypoint) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// A read-only representation of a corridor/edge between waypoints (D-001, D-005, P6-02).
pub const RenderEdge = struct {
    from: WaypointId,
    to: WaypointId,
};

/// A read-only representation of a scene hotspot / inspectable prop (P7-01, D-009).
pub const RenderHotspot = struct {
    entity: EntityId,
    room: EntityId,
    x: i32,
    y: i32,
    radius: u32,
    name: [32]u8,
    name_len: u8,
    examine_text: [128]u8,
    examine_len: u8,

    pub fn get_name(self: *const RenderHotspot) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn get_examine_text(self: *const RenderHotspot) []const u8 {
        return self.examine_text[0..self.examine_len];
    }
};

/// An external visual/audio cue emitted during a simulation tick (D-001).
pub const RenderCue = struct {
    cue_id: u16,
    args: [4]u32,
    arg_count: u8,
};

/// An inventory item held by the player (P7-03, D-007).
pub const RenderInventoryItem = struct {
    entity: EntityId,
    name: [32]u8,
    name_len: u8,

    pub fn get_name(self: *const RenderInventoryItem) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// Debug information for an active relational fact (P9-01, D-011).
pub const RenderDebugFact = struct {
    subject_name: [24]u8,
    subject_len: u8,
    relation_name: [24]u8,
    relation_len: u8,
    object_name: [24]u8,
    object_len: u8,
    expires_at_tick: u64,

    pub fn get_subject(self: *const RenderDebugFact) []const u8 {
        return self.subject_name[0..self.subject_len];
    }
    pub fn get_relation(self: *const RenderDebugFact) []const u8 {
        return self.relation_name[0..self.relation_len];
    }
    pub fn get_object(self: *const RenderDebugFact) []const u8 {
        return self.object_name[0..self.object_len];
    }
};

/// Debug information for an active fiber and its call/interrupt stack (P9-01, D-011).
pub const RenderDebugFiber = struct {
    id: u32,
    owner_name: [24]u8,
    owner_len: u8,
    pc: usize,
    sp: usize,
    interrupt_depth: usize,
    priority: u16,
    state_name: [24]u8,
    state_len: u8,

    pub fn get_owner(self: *const RenderDebugFiber) []const u8 {
        return self.owner_name[0..self.owner_len];
    }
    pub fn get_state(self: *const RenderDebugFiber) []const u8 {
        return self.state_name[0..self.state_len];
    }
};

/// A double-buffered render state slice captured at a discrete simulation tick (D-001, P5-01, P6-02).
pub const RenderFrame = struct {
    tick: u64,
    entities: [64]RenderEntity,
    entity_count: usize,
    waypoints: [32]RenderWaypoint,
    waypoint_count: usize,
    edges: [64]RenderEdge,
    edge_count: usize,
    hotspots: [16]RenderHotspot,
    hotspot_count: usize,
    inventory: [8]RenderInventoryItem,
    inventory_count: usize,
    cues: [16]RenderCue,
    cue_count: usize,
    fact_count: usize,
    cheese_holder: EntityId,
    charmed_target: EntityId,
    // Scenario status flags (P10-03)
    spit_is_thick: bool = false,
    flags_tampered: bool = false,
    wind_blowing: bool = false,
    organiser_distracted: bool = false,
    debug_facts: [32]RenderDebugFact,
    debug_fact_count: usize,
    debug_fibers: [8]RenderDebugFiber,
    debug_fiber_count: usize,
    max_history_tick: u64,
};

/// Double-buffered display bridge separating simulation spine from peripheral consumers (D-001, P5-01).
pub const DisplayBridge = struct {
    front_buffer: RenderFrame,
    back_buffer: RenderFrame,

    pub fn init() DisplayBridge {
        return DisplayBridge{
            .front_buffer = std.mem.zeroes(RenderFrame),
            .back_buffer = std.mem.zeroes(RenderFrame),
        };
    }

    /// Sets the maximum simulation tick reached in recorded history for the timeline scrubber (P9-02, D-011).
    pub fn set_max_history_tick(self: *DisplayBridge, max_tick: u64) void {
        self.back_buffer.max_history_tick = max_tick;
        self.front_buffer.max_history_tick = max_tick;
    }

    /// Captures a read-only snapshot of simulation state into the back buffer (D-001, P6-02).
    pub fn capture_frame(
        self: *DisplayBridge,
        world: *const World,
        spatial: *const SpatialSystem,
        vm: *const VM,
    ) void {
        const prev_max_history = self.back_buffer.max_history_tick;
        self.back_buffer.tick = world.current_tick;
        self.back_buffer.fact_count = world.fact_count();

        // 1. Capture entities and positions
        var e_count: usize = 0;
        var it = spatial.agents.iterator();
        while (it.next()) |entry| {
            if (e_count >= self.back_buffer.entities.len) break;
            const agent = entry.value_ptr;
            var re = RenderEntity{
                .entity = agent.entity,
                .name = undefined,
                .name_len = 0,
                .x = agent.pos.x,
                .y = agent.pos.y,
                .current_wp = agent.current_wp,
                .is_moving = agent.is_moving,
            };
            if (world.get_entity_name(agent.entity)) |n| {
                const len = @min(n.len, re.name.len);
                @memcpy(re.name[0..len], n[0..len]);
                re.name_len = @intCast(len);
            }
            self.back_buffer.entities[e_count] = re;
            e_count += 1;
        }
        self.back_buffer.entity_count = e_count;

        // 2. Capture spatial waypoints
        var wp_count: usize = 0;
        for (spatial.graph.waypoints.items) |wp| {
            if (wp_count >= self.back_buffer.waypoints.len) break;
            var rw = RenderWaypoint{
                .id = wp.id,
                .room = wp.room,
                .x = wp.pos.x,
                .y = wp.pos.y,
                .name = undefined,
                .name_len = 0,
            };
            const len = @min(wp.name.len, rw.name.len);
            @memcpy(rw.name[0..len], wp.name[0..len]);
            rw.name_len = @intCast(len);
            self.back_buffer.waypoints[wp_count] = rw;
            wp_count += 1;
        }
        self.back_buffer.waypoint_count = wp_count;

        // 3. Capture spatial edges
        var edge_count: usize = 0;
        for (spatial.graph.edges.items) |e| {
            if (edge_count >= self.back_buffer.edges.len) break;
            self.back_buffer.edges[edge_count] = .{
                .from = e.from,
                .to = e.to,
            };
            edge_count += 1;
        }
        self.back_buffer.edge_count = edge_count;

        // 4. Capture spatial hotspots (P7-01, D-009)
        var hs_count: usize = 0;
        for (spatial.hotspots.items) |hs| {
            if (hs_count >= self.back_buffer.hotspots.len) break;
            var rh = RenderHotspot{
                .entity = hs.entity,
                .room = hs.room,
                .x = hs.pos.x,
                .y = hs.pos.y,
                .radius = hs.radius,
                .name = undefined,
                .name_len = 0,
                .examine_text = undefined,
                .examine_len = 0,
            };
            const n_len = @min(hs.name.len, rh.name.len);
            @memcpy(rh.name[0..n_len], hs.name[0..n_len]);
            rh.name_len = @intCast(n_len);

            const e_len = @min(hs.examine_text.len, rh.examine_text.len);
            @memcpy(rh.examine_text[0..e_len], hs.examine_text[0..e_len]);
            rh.examine_len = @intCast(e_len);

            self.back_buffer.hotspots[hs_count] = rh;
            hs_count += 1;
        }
        self.back_buffer.hotspot_count = hs_count;

        // 5. Capture emitted cues
        var c_count: usize = 0;
        for (vm.emitted_cues.items) |cue| {
            if (c_count >= self.back_buffer.cues.len) break;
            self.back_buffer.cues[c_count] = .{
                .cue_id = cue.cue_id,
                .args = cue.args,
                .arg_count = cue.arg_count,
            };
            c_count += 1;
        }
        self.back_buffer.cue_count = c_count;

        // 5. Query relational facts for status indicators
        self.back_buffer.cheese_holder = .none;
        self.back_buffer.charmed_target = .none;
        if (world.lookup_entity("Cheese")) |cheese_id| {
            if (world.lookup_relation("Carries")) |carries_rel| {
                if (world.find_first(null, carries_rel, @intFromEnum(cheese_id))) |f| {
                    self.back_buffer.cheese_holder = f.subject;
                }
            }
        }
        if (world.lookup_relation("CharmedBy")) |charmed_rel| {
            if (world.find_first(null, charmed_rel, null)) |f| {
                self.back_buffer.charmed_target = f.subject;
            }
        }

        // 5b. Capture Spitting Contest facts (P10-03, D-012)
        self.back_buffer.spit_is_thick = false;
        if (world.lookup_relation("thick")) |rel| {
            self.back_buffer.spit_is_thick = world.has_fact(null, rel, null);
        }
        self.back_buffer.flags_tampered = false;
        if (world.lookup_relation("tampered")) |rel| {
            self.back_buffer.flags_tampered = world.has_fact(null, rel, null);
        }
        self.back_buffer.wind_blowing = false;
        if (world.lookup_relation("blowing")) |rel| {
            self.back_buffer.wind_blowing = world.has_fact(null, rel, null);
        }
        self.back_buffer.organiser_distracted = false;
        if (world.lookup_relation("Distracted")) |rel| {
            self.back_buffer.organiser_distracted = world.has_fact(null, rel, null);
        }

        // 6. Capture player inventory (P7-03, D-007)
        var inv_count: usize = 0;
        const player_id = world.lookup_entity("Guybrush") orelse world.lookup_entity("Cat");
        if (player_id) |pid| {
            if (world.lookup_relation("InInventory")) |inv_rel| {
                var it_inv = world.query(pid, inv_rel, null);
                while (it_inv.next()) |f| {
                    if (inv_count >= self.back_buffer.inventory.len) break;
                    var item = RenderInventoryItem{
                        .entity = EntityId.from_int(f.object_or_value),
                        .name = undefined,
                        .name_len = 0,
                    };
                    if (world.get_entity_name(item.entity)) |n| {
                        const len = @min(n.len, item.name.len);
                        @memcpy(item.name[0..len], n[0..len]);
                        item.name_len = @intCast(len);
                    }
                    self.back_buffer.inventory[inv_count] = item;
                    inv_count += 1;
                }
            }
            if (world.lookup_relation("Carries")) |carries_rel| {
                var it_carr = world.query(pid, carries_rel, null);
                while (it_carr.next()) |f| {
                    if (inv_count >= self.back_buffer.inventory.len) break;
                    var item = RenderInventoryItem{
                        .entity = EntityId.from_int(f.object_or_value),
                        .name = undefined,
                        .name_len = 0,
                    };
                    if (world.get_entity_name(item.entity)) |n| {
                        const len = @min(n.len, item.name.len);
                        @memcpy(item.name[0..len], n[0..len]);
                        item.name_len = @intCast(len);
                    }
                    self.back_buffer.inventory[inv_count] = item;
                    inv_count += 1;
                }
            }
        }
        self.back_buffer.inventory_count = inv_count;

        // 7. Capture active relational facts for debug inspector (P9-01, D-011)
        var df_count: usize = 0;
        const slice = world.facts.slice();
        const subjects = slice.items(.subject);
        const relations = slice.items(.relation);
        const objects = slice.items(.object_or_value);
        const expirations = slice.items(.expires_at_tick);

        var fi: usize = 0;
        while (fi < world.facts.len and df_count < self.back_buffer.debug_facts.len) : (fi += 1) {
            var df = RenderDebugFact{
                .subject_name = undefined,
                .subject_len = 0,
                .relation_name = undefined,
                .relation_len = 0,
                .object_name = undefined,
                .object_len = 0,
                .expires_at_tick = expirations[fi],
            };

            if (world.get_entity_name(subjects[fi])) |sn| {
                const len = @min(sn.len, df.subject_name.len);
                @memcpy(df.subject_name[0..len], sn[0..len]);
                df.subject_len = @intCast(len);
            }

            if (world.get_relation_meta(relations[fi])) |rm| {
                const len = @min(rm.name.len, df.relation_name.len);
                @memcpy(df.relation_name[0..len], rm.name[0..len]);
                df.relation_len = @intCast(len);
            }

            if (world.get_entity_name(EntityId.from_int(objects[fi]))) |on| {
                const len = @min(on.len, df.object_name.len);
                @memcpy(df.object_name[0..len], on[0..len]);
                df.object_len = @intCast(len);
            } else {
                var num_buf: [16]u8 = undefined;
                const formatted = std.fmt.bufPrint(&num_buf, "{d}", .{objects[fi]}) catch "?";
                const len = @min(formatted.len, df.object_name.len);
                @memcpy(df.object_name[0..len], formatted[0..len]);
                df.object_len = @intCast(len);
            }

            self.back_buffer.debug_facts[df_count] = df;
            df_count += 1;
        }
        self.back_buffer.debug_fact_count = df_count;

        // 8. Capture active fibers for debug inspector (P9-01, D-011)
        var fib_count: usize = 0;
        for (vm.fibers.items) |f| {
            if (fib_count >= self.back_buffer.debug_fibers.len) break;
            var dfib = RenderDebugFiber{
                .id = f.id,
                .owner_name = undefined,
                .owner_len = 0,
                .pc = f.pc,
                .sp = f.sp,
                .interrupt_depth = f.interrupt_stack.items.len,
                .priority = f.active_priority,
                .state_name = undefined,
                .state_len = 0,
            };

            if (world.get_entity_name(f.owner)) |on| {
                const len = @min(on.len, dfib.owner_name.len);
                @memcpy(dfib.owner_name[0..len], on[0..len]);
                dfib.owner_len = @intCast(len);
            }

            const s_tag = std.meta.activeTag(f.state);
            const s_str = @tagName(s_tag);
            const slen = @min(s_str.len, dfib.state_name.len);
            @memcpy(dfib.state_name[0..slen], s_str[0..slen]);
            dfib.state_len = @intCast(slen);

            self.back_buffer.debug_fibers[fib_count] = dfib;
            fib_count += 1;
        }
        self.back_buffer.debug_fiber_count = fib_count;
        self.back_buffer.max_history_tick = prev_max_history;
    }

    /// Swaps front and back buffers so display consumer reads the latest completed tick (D-001).
    pub fn swap(self: *DisplayBridge) void {
        const temp = self.front_buffer;
        self.front_buffer = self.back_buffer;
        self.back_buffer = temp;
    }

    /// Gets read-only reference to current display frame.
    pub fn get_frame(self: *const DisplayBridge) *const RenderFrame {
        return &self.front_buffer;
    }

    /// Built-in text/terminal renderer displaying tavern waypoints and actor positions (P5-01).
    pub fn render_terminal(self: *const DisplayBridge, writer: anytype) !void {
        const f = &self.front_buffer;
        try writer.print("+-------------------------------------------------------------------+\n", .{});
        try writer.print("| [Tick {d:03}] Active Facts: {d:<3}                                           |\n", .{ f.tick, f.fact_count });
        try writer.print("+-------------------------------------------------------------------+\n", .{});
        try writer.print("| Hearth (0,0)  <===========>  Bar (20,0)  <===========>  Cellar (40,0) |\n", .{});
        try writer.print("|                                                                   |\n", .{});

        for (f.entities[0..f.entity_count]) |e| {
            const name = e.get_name();
            const status = if (e.is_moving) "in transit" else "at waypoint";
            try writer.print("| Actor: {s:<10} Pos: ({d:>2}, {d:>2}) | Status: {s:<14}            |\n", .{
                name,
                e.x,
                e.y,
                status,
            });
        }

        if (f.cue_count > 0) {
            try writer.print("| Cues Emitted: {d} cue event(s)                                      |\n", .{f.cue_count});
        }
        try writer.print("+-------------------------------------------------------------------+\n", .{});
    }
};

test "P5-01: display bridge captures double-buffered render frames" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const tavern = EntityId.from_int(1);
    const guard = try world.intern_entity("Guard");
    const wp1 = try spatial.graph.add_waypoint(tavern, 0, 0, "Hearth");
    try spatial.register_entity(guard, wp1, 5);

    var chunk = vm_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    var bridge = DisplayBridge.init();

    // Capture initial frame
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();

    const frame = bridge.get_frame();
    try testing.expectEqual(@as(u64, 0), frame.tick);
    try testing.expectEqual(@as(usize, 1), frame.entity_count);
    try testing.expectEqualStrings("Guard", frame.entities[0].get_name());
    try testing.expectEqual(@as(i32, 0), frame.entities[0].x);
    try testing.expectEqual(@as(usize, 1), frame.waypoint_count);
    try testing.expectEqualStrings("Hearth", frame.waypoints[0].get_name());
}

test {
    _ = renderer;
    _ = font;
}
