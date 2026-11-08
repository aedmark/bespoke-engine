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
pub const audio = @import("audio.zig");
pub const AudioBridge = audio.AudioBridge;
pub const SoundEffectKind = audio.SoundEffectKind;
pub const MusicTrackKind = audio.MusicTrackKind;
pub const ChiptuneSynth = audio.ChiptuneSynth;

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

/// Physiological drive and status snapshot for a villager in "The Living Village" (P18-01, P18-03, D-021).
pub const RenderVillagerDrive = struct {
    entity: EntityId = .none,
    name: [16]u8 = [_]u8{0} ** 16,
    name_len: u8 = 0,
    hunger: u8 = 0,
    energy: u8 = 0,
    gold: u16 = 0,
    activity: u8 = 0,
    knows_rumor: bool = false,
    is_witness: bool = false,
    is_arrested: bool = false,

    pub fn get_name(self: *const RenderVillagerDrive) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// A directed social or emergence edge for the live Social Graph HUD (P18-02, P18-03, D-021).
pub const RenderSocialEdge = struct {
    from_name: [16]u8 = [_]u8{0} ** 16,
    from_len: u8 = 0,
    to_name: [16]u8 = [_]u8{0} ** 16,
    to_len: u8 = 0,
    /// 0 = Friend, 1 = Grudge/Rival, 2 = KnowsRumor, 3 = WarrantFor, 4 = Arrested
    kind: u8 = 0,

    pub fn get_from(self: *const RenderSocialEdge) []const u8 {
        return self.from_name[0..self.from_len];
    }
    pub fn get_to(self: *const RenderSocialEdge) []const u8 {
        return self.to_name[0..self.to_len];
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
    // Scenario status flags (P10-03, P14-02)
    spit_is_thick: bool = false,
    flags_tampered: bool = false,
    wind_blowing: bool = false,
    organiser_distracted: bool = false,
    fence_taped: bool = false,
    fence_has_hair: bool = false,
    cat_startled: bool = false,
    cat_hair_collected: bool = false,
    gabriel_disguised: bool = false,
    bike_rented: bool = false,
    // Living Village drives & social graph state (P18-01..P18-03, D-021)
    villager_drives: [8]RenderVillagerDrive = [_]RenderVillagerDrive{.{}} ** 8,
    villager_drive_count: usize = 0,
    social_edges: [16]RenderSocialEdge = [_]RenderSocialEdge{.{}} ** 16,
    social_edge_count: usize = 0,
    village_crime_active: bool = false,
    village_warrant_active: bool = false,
    village_arrest_made: bool = false,
    debug_facts: [32]RenderDebugFact,
    debug_fact_count: usize,
    debug_fibers: [8]RenderDebugFiber,
    debug_fiber_count: usize,
    current_scene: [32]u8 = undefined,
    current_scene_len: u8 = 0,
    max_history_tick: u64,

    pub fn get_current_scene(self: *const RenderFrame) []const u8 {
        return self.current_scene[0..self.current_scene_len];
    }
};

/// Double-buffered display bridge separating simulation spine from peripheral consumers (D-001, P5-01).
pub const DisplayBridge = struct {
    front_buffer: RenderFrame,
    back_buffer: RenderFrame,
    audio_bridge: ?*audio.AudioBridge = null,

    pub fn init() DisplayBridge {
        return DisplayBridge{
            .front_buffer = std.mem.zeroes(RenderFrame),
            .back_buffer = std.mem.zeroes(RenderFrame),
            .audio_bridge = null,
        };
    }

    /// Attaches an optional peripheral audio bridge to consume cues (P16-01, D-001).
    pub fn attach_audio_bridge(self: *DisplayBridge, ab: *audio.AudioBridge) void {
        self.audio_bridge = ab;
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
        const active_scene_id = vm.current_scene;

        // 1. Capture entities and positions (scoped to active scene if set)
        var e_count: usize = 0;
        var it = spatial.agents.iterator();
        while (it.next()) |entry| {
            if (e_count >= self.back_buffer.entities.len) break;
            const agent = entry.value_ptr;

            if (active_scene_id) |cur_sc| {
                if (spatial.graph.get_waypoint(agent.current_wp)) |wp| {
                    if (wp.room != cur_sc) continue;
                }
            }

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

        // 2. Capture spatial waypoints (scoped to active scene if set)
        var wp_count: usize = 0;
        for (spatial.graph.waypoints.items) |wp| {
            if (wp_count >= self.back_buffer.waypoints.len) break;
            if (active_scene_id) |cur_sc| {
                if (wp.room != cur_sc) continue;
            }

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

        // 3. Capture spatial edges (scoped to active scene if set)
        var edge_count: usize = 0;
        for (spatial.graph.edges.items) |e| {
            if (edge_count >= self.back_buffer.edges.len) break;
            if (active_scene_id) |cur_sc| {
                const wp_a = spatial.graph.get_waypoint(e.from);
                const wp_b = spatial.graph.get_waypoint(e.to);
                if (wp_a == null or wp_b == null or wp_a.?.room != cur_sc or wp_b.?.room != cur_sc) {
                    continue;
                }
            }

            self.back_buffer.edges[edge_count] = .{
                .from = e.from,
                .to = e.to,
            };
            edge_count += 1;
        }
        self.back_buffer.edge_count = edge_count;

        // 4. Capture spatial hotspots (scoped to active scene if set)
        var hs_count: usize = 0;
        for (spatial.hotspots.items) |hs| {
            if (hs_count >= self.back_buffer.hotspots.len) break;
            if (active_scene_id) |cur_sc| {
                if (hs.room != cur_sc) continue;
            }

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

        // GK3 Cat Moustache scenario status flags (P14-02)
        self.back_buffer.fence_taped = false;
        if (world.lookup_relation("taped") orelse world.lookup_relation("Taped")) |rel| {
            self.back_buffer.fence_taped = world.has_fact(null, rel, null);
        }
        self.back_buffer.fence_has_hair = false;
        if (world.lookup_relation("FenceHasHair")) |rel| {
            self.back_buffer.fence_has_hair = world.has_fact(null, rel, null);
        }
        self.back_buffer.cat_startled = false;
        if (world.lookup_relation("startled") orelse world.lookup_relation("Startled")) |rel| {
            self.back_buffer.cat_startled = world.has_fact(null, rel, null);
        }
        self.back_buffer.cat_hair_collected = false;
        if (world.lookup_relation("Carries")) |c_rel| {
            if (world.lookup_entity("CatHair")) |ch_id| {
                self.back_buffer.cat_hair_collected = world.has_fact(null, c_rel, ch_id.to_int());
            }
        }
        self.back_buffer.gabriel_disguised = false;
        if (world.lookup_relation("disguised") orelse world.lookup_relation("Disguised")) |rel| {
            self.back_buffer.gabriel_disguised = world.has_fact(null, rel, null);
        }
        self.back_buffer.bike_rented = false;
        if (world.lookup_relation("HasBikeKeys") orelse world.lookup_relation("BikeRented")) |rel| {
            self.back_buffer.bike_rented = world.has_fact(null, rel, null);
        }

        // 5c. Capture Living Village drives & social graph relations (P18-01..P18-03, D-021)
        self.back_buffer.villager_drive_count = 0;
        self.back_buffer.social_edge_count = 0;
        self.back_buffer.village_crime_active = false;
        self.back_buffer.village_warrant_active = false;
        self.back_buffer.village_arrest_made = false;

        if (world.lookup_relation("Hunger")) |hunger_rel| {
            const energy_rel = world.lookup_relation("Energy");
            const gold_rel = world.lookup_relation("Gold");
            const act_rel = world.lookup_relation("Activity");
            const rumor_rel = world.lookup_relation("KnowsRumor");
            const wit_rel = world.lookup_relation("Witnessed");
            const arr_rel = world.lookup_relation("Arrested");
            const stolen_rel = world.lookup_relation("StolenFrom");
            const warrant_rel = world.lookup_relation("WarrantFor");

            if (stolen_rel) |sr| self.back_buffer.village_crime_active = world.has_fact(null, sr, null);
            if (warrant_rel) |wr| self.back_buffer.village_warrant_active = world.has_fact(null, wr, null);
            if (arr_rel) |ar| self.back_buffer.village_arrest_made = world.has_fact(null, ar, null);

            var vd_count: usize = 0;
            for (self.back_buffer.entities[0..self.back_buffer.entity_count]) |re| {
                if (vd_count >= self.back_buffer.villager_drives.len) break;
                if (world.get_property(re.entity, hunger_rel)) |h_val| {
                    var vd = RenderVillagerDrive{
                        .entity = re.entity,
                        .hunger = @intCast(@min(100, h_val)),
                        .energy = if (energy_rel) |er| @intCast(@min(100, world.get_property(re.entity, er) orelse 0)) else 0,
                        .gold = if (gold_rel) |gr| @intCast(@min(999, world.get_property(re.entity, gr) orelse 0)) else 0,
                        .activity = if (act_rel) |ar| @intCast(@min(20, world.get_property(re.entity, ar) orelse 0)) else 0,
                        .knows_rumor = if (rumor_rel) |rr| world.has_fact(re.entity, rr, null) else false,
                        .is_witness = if (wit_rel) |wr| world.has_fact(re.entity, wr, null) else false,
                        .is_arrested = if (arr_rel) |ar| world.has_fact(re.entity, ar, null) else false,
                    };
                    const n = re.get_name();
                    const nlen = @min(n.len, vd.name.len);
                    @memcpy(vd.name[0..nlen], n[0..nlen]);
                    vd.name_len = @intCast(nlen);
                    self.back_buffer.villager_drives[vd_count] = vd;
                    vd_count += 1;
                }
            }
            self.back_buffer.villager_drive_count = vd_count;

            // Capture key social and emergence edges for the Social Graph HUD
            const edge_rels = [_]struct { name: []const u8, kind: u8 }{
                .{ .name = "Arrested", .kind = 4 },
                .{ .name = "WarrantFor", .kind = 3 },
                .{ .name = "KnowsRumor", .kind = 2 },
                .{ .name = "Grudge", .kind = 1 },
                .{ .name = "Friend", .kind = 0 },
            };
            var se_count: usize = 0;
            for (edge_rels) |er_info| {
                if (world.lookup_relation(er_info.name)) |rel_id| {
                    var q_it = world.query(null, rel_id, null);
                    while (q_it.next()) |f| {
                        if (se_count >= self.back_buffer.social_edges.len) break;
                        const s_name = world.get_entity_name(f.subject) orelse continue;
                        const o_name = world.get_entity_name(EntityId.from_int(f.object_or_value)) orelse continue;
                        // Avoid duplicate undirected Friend lines
                        if (er_info.kind == 0 and f.subject.to_int() > f.object_or_value) continue;

                        var se = RenderSocialEdge{ .kind = er_info.kind };
                        const slen = @min(s_name.len, se.from_name.len);
                        @memcpy(se.from_name[0..slen], s_name[0..slen]);
                        se.from_len = @intCast(slen);

                        const olen = @min(o_name.len, se.to_name.len);
                        @memcpy(se.to_name[0..olen], o_name[0..olen]);
                        se.to_len = @intCast(olen);

                        self.back_buffer.social_edges[se_count] = se;
                        se_count += 1;
                    }
                }
            }
            self.back_buffer.social_edge_count = se_count;
        }

        // 6. Capture player inventory (P7-03, D-007)
        var inv_count: usize = 0;
        const player_id = world.lookup_entity("Gabriel") orelse world.lookup_entity("Guybrush") orelse world.lookup_entity("Cat");
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

        // 8. Capture active scene (P12-03, D-014)
        if (vm.current_scene) |scene_id| {
            if (world.get_entity_name(scene_id)) |sname| {
                const len = @min(sname.len, self.back_buffer.current_scene.len);
                @memcpy(self.back_buffer.current_scene[0..len], sname[0..len]);
                self.back_buffer.current_scene_len = @intCast(len);
            } else {
                self.back_buffer.current_scene_len = 0;
            }
        } else {
            self.back_buffer.current_scene_len = 0;
        }

        self.back_buffer.max_history_tick = prev_max_history;

        // 9. Forward scene and cues to attached audio bridge (P16-01, P16-03, D-019)
        if (self.audio_bridge) |ab| {
            ab.process_scene_and_cues(self.back_buffer.get_current_scene());
        }
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

test "P12-03: DisplayBridge.capture_frame scopes waypoints, hotspots, and entities to active scene" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, 1024 * 1024);
    defer world.deinit();

    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();

    const room_a = try world.intern_entity("RoomA");
    const room_b = try world.intern_entity("RoomB");

    const wp_a = try spatial.graph.add_waypoint(room_a, 0, 0, "WP_A");
    const wp_b = try spatial.graph.add_waypoint(room_b, 10, 0, "WP_B");

    const prop_a = try world.intern_entity("PropA");
    const prop_b = try world.intern_entity("PropB");
    try spatial.add_hotspot(prop_a, room_a, .{ .x = 0, .y = -5 }, 5, "PropA", "Prop in Room A");
    try spatial.add_hotspot(prop_b, room_b, .{ .x = 10, .y = -5 }, 5, "PropB", "Prop in Room B");

    const actor_a = try world.intern_entity("ActorA");
    const actor_b = try world.intern_entity("ActorB");
    try spatial.register_entity(actor_a, wp_a, 5);
    try spatial.register_entity(actor_b, wp_b, 5);

    var chunk = vm_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();

    var vm = VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();

    var bridge = DisplayBridge.init();

    // 1. Scoped to RoomA
    vm.current_scene = room_a;
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();
    const frame_a = bridge.get_frame();
    try testing.expectEqual(@as(usize, 1), frame_a.waypoint_count);
    try testing.expectEqualStrings("WP_A", frame_a.waypoints[0].get_name());
    try testing.expectEqual(@as(usize, 1), frame_a.hotspot_count);
    try testing.expectEqualStrings("PropA", frame_a.hotspots[0].get_name());
    try testing.expectEqual(@as(usize, 1), frame_a.entity_count);
    try testing.expectEqualStrings("ActorA", frame_a.entities[0].get_name());

    // 2. Scoped to RoomB
    vm.current_scene = room_b;
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();
    const frame_b = bridge.get_frame();
    try testing.expectEqual(@as(usize, 1), frame_b.waypoint_count);
    try testing.expectEqualStrings("WP_B", frame_b.waypoints[0].get_name());
    try testing.expectEqual(@as(usize, 1), frame_b.hotspot_count);
    try testing.expectEqualStrings("PropB", frame_b.hotspots[0].get_name());
    try testing.expectEqual(@as(usize, 1), frame_b.entity_count);
    try testing.expectEqualStrings("ActorB", frame_b.entities[0].get_name());

    // 3. Unscoped (vm.current_scene == null, e.g. Tavern Heist overview)
    vm.current_scene = null;
    bridge.capture_frame(&world, &spatial, &vm);
    bridge.swap();
    const frame_all = bridge.get_frame();
    try testing.expectEqual(@as(usize, 2), frame_all.waypoint_count);
    try testing.expectEqual(@as(usize, 2), frame_all.hotspot_count);
    try testing.expectEqual(@as(usize, 2), frame_all.entity_count);
}

test "P16-01: DisplayBridge attaches AudioBridge and forwards scene context" {
    const testing = std.testing;
    var db = DisplayBridge.init();
    var ab = audio.AudioBridge.init();
    db.attach_audio_bridge(&ab);

    try testing.expect(db.audio_bridge != null);
    try testing.expectEqual(@as(*audio.AudioBridge, &ab), db.audio_bridge.?);
}

test {
    _ = renderer;
    _ = font;
}
