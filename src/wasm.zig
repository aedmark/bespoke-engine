//! BeSpoke Engine: WebAssembly (wasm32-freestanding) Runtime Harness & Browser Event Bridge (Phase 19, D-001, D-008, D-022)
//!
//! Compiles the pure Zig simulation spine (World, SpatialSystem, VM, Compiler, Repl)
//! to `wasm32-freestanding` with zero libc or external dependencies, rendering directly
//! into a 640x360 RGBA8888 linear-memory framebuffer (`WasmCanvas`) for HTML5 Canvas
//! `ImageData` blitting and bridging DOM mouse, keyboard, and touch events to BeSpoke intents.

const std = @import("std");
const builtin = @import("builtin");
const world_mod = @import("world.zig");
const bytecode_mod = @import("bytecode.zig");
const vm_mod = @import("vm.zig");
const spatial_mod = @import("spatial.zig");
const compiler_mod = @import("compiler.zig");
const repl_mod = @import("repl.zig");
const font = @import("display/font.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const SpatialSystem = spatial_mod.SpatialSystem;
pub const WaypointId = spatial_mod.WaypointId;
pub const VM = vm_mod.VM;
pub const Repl = repl_mod.Repl;

pub const CANVAS_WIDTH: i32 = 640;
pub const CANVAS_HEIGHT: i32 = 360;
pub const FRAMEBUFFER_BYTES: usize = @intCast(CANVAS_WIDTH * CANVAS_HEIGHT * 4);
pub const MAX_WASM_SNAPSHOTS: usize = 32;
pub const SNAPSHOT_SLOT_BYTES: usize = 8192;

pub const RgbaColor = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = RgbaColor{ .r = 255, .g = 255, .b = 255 };
    pub const black = RgbaColor{ .r = 0, .g = 0, .b = 0 };
    pub const hud_bg = RgbaColor{ .r = 15, .g = 23, .b = 42 };
    pub const hud_border = RgbaColor{ .r = 71, .g = 85, .b = 105 };
    pub const gold = RgbaColor{ .r = 250, .g = 204, .b = 21 };
    pub const sky_blue = RgbaColor{ .r = 56, .g = 189, .b = 248 };
    pub const emerald = RgbaColor{ .r = 34, .g = 197, .b = 94 };
    pub const crimson = RgbaColor{ .r = 244, .g = 63, .b = 94 };
    pub const amber = RgbaColor{ .r = 245, .g = 158, .b = 11 };
    pub const slate = RgbaColor{ .r = 148, .g = 163, .b = 184 };
};

/// Built-in vertical slice scenarios playable in the WebAssembly / HTML5 Canvas runtime (P19-01, P19-03).
pub const WasmScenario = enum(u8) {
    tavern_heist = 0,
    spitting_contest = 1,
    gk3_moustache = 2,
    living_village = 3,

    pub fn title(self: WasmScenario) []const u8 {
        return switch (self) {
            .tavern_heist => "TAVERN HEIST (GUARD, BARD & CAT)",
            .spitting_contest => "BOOTY ISLAND SPITTING CONTEST",
            .gk3_moustache => "GK3: CAT MOUSTACHE PUZZLE",
            .living_village => "THE LIVING VILLAGE (EMERGENCE)",
        };
    }

    pub fn from_int(val: u8) WasmScenario {
        return switch (val) {
            0 => .tavern_heist,
            1 => .spitting_contest,
            2 => .gk3_moustache,
            3 => .living_village,
            else => .tavern_heist,
        };
    }
};

/// Adventure verbs selectable via mouse click, right-click cycle, or touch tap (P19-02, D-008).
pub const WasmVerb = enum(u8) {
    walk = 0,
    look_at = 1,
    talk_to = 2,
    pick_up = 3,
    use_with = 4,

    pub fn label(self: WasmVerb) []const u8 {
        return switch (self) {
            .walk => "WALK",
            .look_at => "LOOK",
            .talk_to => "TALK",
            .pick_up => "TAKE",
            .use_with => "USE",
        };
    }

    pub fn next(self: WasmVerb) WasmVerb {
        return @enumFromInt((@intFromEnum(self) + 1) % 5);
    }
};

/// Browser DOM event categories mapped by the BeSpoke Browser Event Bridge (P19-02, D-008).
pub const BrowserEventKind = enum(u8) {
    pointer_down = 0,
    pointer_move = 1,
    right_click = 2,
    key_down = 3,
    touch_start = 4,
    touch_move = 5,
    touch_end = 6,
};

/// Normalized browser input event passed from HTML5 Canvas JS listeners into Zig (P19-02).
pub const BrowserInputEvent = struct {
    kind: BrowserEventKind,
    x: i32 = 0,
    y: i32 = 0,
    key_code: u8 = 0,
    touch_points: u8 = 1,
};

/// Result of dispatching a browser input event against the simulation spine (P19-02).
pub const BrowserActionTag = enum(u8) {
    none = 0,
    hover_updated,
    verb_changed,
    walk_issued,
    hotspot_inspected,
    actor_interacted,
    timeline_scrubbed,
    pause_toggled,
    tick_stepped,
    rewound,
    scenario_switched,
    catalyst_triggered,
};

// =============================================================================
// 1. Pure Zig RGBA8888 Canvas Framebuffer Renderer (P19-01, D-001, D-022)
// =============================================================================

pub const WasmCanvas = struct {
    pixels: [FRAMEBUFFER_BYTES]u8 = [_]u8{0} ** FRAMEBUFFER_BYTES,

    pub fn clear(self: *WasmCanvas, col: RgbaColor) void {
        var i: usize = 0;
        while (i < FRAMEBUFFER_BYTES) : (i += 4) {
            self.pixels[i] = col.r;
            self.pixels[i + 1] = col.g;
            self.pixels[i + 2] = col.b;
            self.pixels[i + 3] = col.a;
        }
    }

    pub inline fn set_pixel(self: *WasmCanvas, x: i32, y: i32, col: RgbaColor) void {
        if (x < 0 or x >= CANVAS_WIDTH or y < 0 or y >= CANVAS_HEIGHT) return;
        const idx: usize = @intCast((y * CANVAS_WIDTH + x) * 4);
        self.pixels[idx] = col.r;
        self.pixels[idx + 1] = col.g;
        self.pixels[idx + 2] = col.b;
        self.pixels[idx + 3] = col.a;
    }

    pub fn get_pixel(self: *const WasmCanvas, x: i32, y: i32) RgbaColor {
        if (x < 0 or x >= CANVAS_WIDTH or y < 0 or y >= CANVAS_HEIGHT) return RgbaColor.black;
        const idx: usize = @intCast((y * CANVAS_WIDTH + x) * 4);
        return .{
            .r = self.pixels[idx],
            .g = self.pixels[idx + 1],
            .b = self.pixels[idx + 2],
            .a = self.pixels[idx + 3],
        };
    }

    pub fn fill_rect(self: *WasmCanvas, x: i32, y: i32, w: i32, h: i32, col: RgbaColor) void {
        const x0 = @max(0, x);
        const y0 = @max(0, y);
        const x1 = @min(CANVAS_WIDTH, x + w);
        const y1 = @min(CANVAS_HEIGHT, y + h);
        if (x0 >= x1 or y0 >= y1) return;

        var py = y0;
        while (py < y1) : (py += 1) {
            var px = x0;
            while (px < x1) : (px += 1) {
                self.set_pixel(px, py, col);
            }
        }
    }

    pub fn draw_rect_outline(self: *WasmCanvas, x: i32, y: i32, w: i32, h: i32, col: RgbaColor) void {
        if (w <= 0 or h <= 0) return;
        self.draw_line(x, y, x + w - 1, y, col);
        self.draw_line(x, y + h - 1, x + w - 1, y + h - 1, col);
        self.draw_line(x, y, x, y + h - 1, col);
        self.draw_line(x + w - 1, y, x + w - 1, y + h - 1, col);
    }

    pub fn draw_line(self: *WasmCanvas, x0_in: i32, y0_in: i32, x1_in: i32, y1_in: i32, col: RgbaColor) void {
        var x0 = x0_in;
        var y0 = y0_in;
        const x1 = x1_in;
        const y1 = y1_in;

        const dx: i32 = @intCast(@abs(x1 - x0));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err: i32 = dx + dy;

        while (true) {
            self.set_pixel(x0, y0, col);
            if (x0 == x1 and y0 == y1) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                x0 += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    pub fn fill_circle(self: *WasmCanvas, cx: i32, cy: i32, radius: i32, col: RgbaColor) void {
        if (radius <= 0) return;
        var dy: i32 = -radius;
        while (dy <= radius) : (dy += 1) {
            const dx: i32 = @intCast(std.math.sqrt(@as(u64, @intCast(@max(0, radius * radius - dy * dy)))));
            var px = cx - dx;
            while (px <= cx + dx) : (px += 1) {
                self.set_pixel(px, cy + dy, col);
            }
        }
    }

    pub fn draw_circle_outline(self: *WasmCanvas, cx: i32, cy: i32, radius: i32, col: RgbaColor) void {
        if (radius <= 0) return;
        var x: i32 = radius;
        var y: i32 = 0;
        var err: i32 = 0;

        while (x >= y) {
            self.set_pixel(cx + x, cy + y, col);
            self.set_pixel(cx + y, cy + x, col);
            self.set_pixel(cx - y, cy + x, col);
            self.set_pixel(cx - x, cy + y, col);
            self.set_pixel(cx - x, cy - y, col);
            self.set_pixel(cx - y, cy - x, col);
            self.set_pixel(cx + y, cy - x, col);
            self.set_pixel(cx + x, cy - y, col);

            if (err <= 0) {
                y += 1;
                err += 2 * y + 1;
            }
            if (err > 0) {
                x -= 1;
                err -= 2 * x + 1;
            }
        }
    }

    pub fn draw_text(self: *WasmCanvas, text: []const u8, start_x: i32, start_y: i32, scale: i32, col: RgbaColor) void {
        var cur_x = start_x;
        for (text) |ch| {
            if (ch < 32 or ch > 126) {
                cur_x += font.char_width(scale);
                continue;
            }
            const glyph = font.FONT5X7[ch - 32];
            for (glyph, 0..) |col_byte, col_idx| {
                var row: usize = 0;
                while (row < 7) : (row += 1) {
                    if ((col_byte >> @intCast(row)) & 1 != 0) {
                        self.fill_rect(
                            cur_x + @as(i32, @intCast(col_idx)) * scale,
                            start_y + @as(i32, @intCast(row)) * scale,
                            scale,
                            scale,
                            col,
                        );
                    }
                }
            }
            cur_x += font.char_width(scale);
        }
    }
};

/// Maps discrete world coordinates `(-5..45, -15..15)` into `640x360` canvas coordinates.
pub fn world_to_canvas(world_x: i32, world_y: i32) struct { x: i32, y: i32 } {
    return .{
        .x = 120 + world_x * 10,
        .y = 185 + world_y * 7,
    };
}

// =============================================================================
// 2. WebAssembly Runtime & Browser Event Bridge (P19-01, P19-02, D-001, D-008)
// =============================================================================

pub const WasmRuntime = struct {
    allocator: std.mem.Allocator,
    world: World,
    spatial: SpatialSystem,
    chunk: bytecode_mod.BytecodeChunk,
    vm: VM,
    scenario: WasmScenario = .tavern_heist,
    active_verb: WasmVerb = .walk,
    is_paused: bool = false,
    hovered_x: i32 = 0,
    hovered_y: i32 = 0,
    player_entity: EntityId = .none,

    banner_buf: [96]u8 = [_]u8{0} ** 96,
    banner_len: usize = 0,
    max_history_tick: u64 = 0,

    // Fixed ring buffer of binary World snapshots for instant browser timeline scrubbing
    snapshot_bufs: [MAX_WASM_SNAPSHOTS][SNAPSHOT_SLOT_BYTES]u8 = undefined,
    snapshot_lens: [MAX_WASM_SNAPSHOTS]usize = [_]usize{0} ** MAX_WASM_SNAPSHOTS,
    snapshot_ticks: [MAX_WASM_SNAPSHOTS]u64 = [_]u64{0} ** MAX_WASM_SNAPSHOTS,
    snapshot_count: usize = 0,

    canvas: WasmCanvas = .{},

    pub fn init(allocator: std.mem.Allocator, initial_scenario: WasmScenario) !WasmRuntime {
        var rt = WasmRuntime{
            .allocator = allocator,
            .world = try World.init(allocator, 256 * 1024),
            .spatial = SpatialSystem.init(allocator),
            .chunk = bytecode_mod.BytecodeChunk.init(allocator),
            .vm = undefined,
            .scenario = initial_scenario,
        };
        rt.vm = VM.init(allocator, &rt.world, &rt.chunk);
        rt.vm.spatial = &rt.spatial;
        try rt.load_scenario(initial_scenario);
        return rt;
    }

    pub fn deinit(self: *WasmRuntime) void {
        self.vm.deinit();
        self.chunk.deinit();
        self.spatial.deinit();
        self.world.deinit();
    }

    pub fn set_banner(self: *WasmRuntime, msg: []const u8) void {
        const len = @min(msg.len, self.banner_buf.len);
        @memcpy(self.banner_buf[0..len], msg[0..len]);
        self.banner_len = len;
    }

    pub fn get_banner(self: *const WasmRuntime) []const u8 {
        return self.banner_buf[0..self.banner_len];
    }

    /// Loads one of the 4 vertical slice scenarios into the WebAssembly runtime spine.
    pub fn load_scenario(self: *WasmRuntime, scen: WasmScenario) !void {
        self.vm.deinit();
        self.chunk.deinit();
        self.spatial.deinit();
        self.world.deinit();

        self.world = try World.init(self.allocator, 256 * 1024);
        self.spatial = SpatialSystem.init(self.allocator);
        self.chunk = bytecode_mod.BytecodeChunk.init(self.allocator);
        _ = try self.chunk.emit_op(.halt);
        self.vm = VM.init(self.allocator, &self.world, &self.chunk);
        self.vm.spatial = &self.spatial;

        self.scenario = scen;
        self.active_verb = .walk;
        self.is_paused = false;
        self.max_history_tick = 0;
        self.snapshot_count = 0;

        switch (scen) {
            .tavern_heist => {
                const room = try self.world.intern_entity("Tavern");
                const cat = try self.world.intern_entity("Cat");
                const guard = try self.world.intern_entity("Guard");
                const bard = try self.world.intern_entity("Bard");
                const cheese = try self.world.intern_entity("Cheese");
                const carries = try self.world.intern_relation("Carries", .set);

                const hearth_wp = try self.spatial.graph.add_waypoint(room, 0, 0, "Hearth");
                const bar_wp = try self.spatial.graph.add_waypoint(room, 20, 0, "Bar");
                const cellar_wp = try self.spatial.graph.add_waypoint(room, 40, 0, "Cellar");
                try self.spatial.graph.connect(hearth_wp, bar_wp, null);
                try self.spatial.graph.connect(bar_wp, cellar_wp, null);

                const fire_ent = try self.world.intern_entity("Fireplace");
                const cask_ent = try self.world.intern_entity("WineCask");
                try self.spatial.add_hotspot(fire_ent, room, .{ .x = 0, .y = -8 }, 6, "Fireplace", "Warm stone tavern hearth.");
                try self.spatial.add_hotspot(cask_ent, room, .{ .x = 40, .y = -8 }, 6, "WineCask", "Oak wine cask in the cellar.");

                try self.spatial.register_entity(cat, hearth_wp, 10);
                try self.spatial.register_entity(guard, bar_wp, 8);
                try self.spatial.register_entity(bard, hearth_wp, 8);
                try self.world.remember(guard, carries, cheese.to_int(), 0);
                self.player_entity = cat;
                self.set_banner("Tavern Heist: Click waypoints to move Cat or press [S] to charm Guard!");
            },
            .spitting_contest => {
                const room = try self.world.intern_entity("Booty Island");
                const guybrush = try self.world.intern_entity("Guybrush");
                const organiser = try self.world.intern_entity("Organiser");
                const onlookers = try self.world.intern_entity("Onlookers");
                const thick_rel = try self.world.intern_relation("thick", .property);
                const wind_rel = try self.world.intern_relation("blowing", .property);

                const start_wp = try self.spatial.graph.add_waypoint(room, 4, 2, "Starting Line");
                const track_wp = try self.spatial.graph.add_waypoint(room, 22, 2, "Flag Marker");
                const dock_wp = try self.spatial.graph.add_waypoint(room, 38, 2, "Lookout Dock");
                try self.spatial.graph.connect(start_wp, track_wp, null);
                try self.spatial.graph.connect(track_wp, dock_wp, null);

                const flags_ent = try self.world.intern_entity("DistanceFlags");
                try self.spatial.add_hotspot(flags_ent, room, .{ .x = 22, .y = -6 }, 6, "DistanceFlags", "Contest distance flags on the lawn.");

                try self.spatial.register_entity(guybrush, start_wp, 10);
                try self.spatial.register_entity(organiser, start_wp, 8);
                try self.spatial.register_entity(onlookers, track_wp, 8);
                try self.world.remember(guybrush, thick_rel, 0, 0);
                try self.world.remember(room, wind_rel, 1, 0);
                self.player_entity = guybrush;
                self.set_banner("Spitting Contest: Press [G] GreenDrink, [F] Move Flags, [S] Spit!");
            },
            .gk3_moustache => {
                const room = try self.world.intern_entity("Hotel Garden");
                const gabriel = try self.world.intern_entity("Gabriel");
                const mosely = try self.world.intern_entity("Mosely");
                const stray_cat = try self.world.intern_entity("StrayCat");
                const buthane = try self.world.intern_entity("Buthane");

                const corr_wp = try self.spatial.graph.add_waypoint(room, 0, 2, "HotelCorridor");
                const fence_wp = try self.spatial.graph.add_waypoint(room, 20, 2, "FenceGap");
                const shop_wp = try self.spatial.graph.add_waypoint(room, 38, 2, "BikeShop");
                try self.spatial.graph.connect(corr_wp, fence_wp, null);
                try self.spatial.graph.connect(fence_wp, shop_wp, null);

                const hole_ent = try self.world.intern_entity("FenceHole");
                try self.spatial.add_hotspot(hole_ent, room, .{ .x = 20, .y = -7 }, 6, "FenceHole", "Broken picket fence gap.");

                try self.spatial.register_entity(gabriel, corr_wp, 10);
                try self.spatial.register_entity(mosely, corr_wp, 8);
                try self.spatial.register_entity(stray_cat, fence_wp, 12);
                try self.spatial.register_entity(buthane, shop_wp, 8);
                self.player_entity = gabriel;
                self.set_banner("GK3 Cat Moustache: Click FenceHole or press [S] to craft disguise!");
            },
            .living_village => {
                const room = try self.world.intern_entity("Living Village");
                const sheriff = try self.world.intern_entity("Sheriff");
                const baker = try self.world.intern_entity("Baker");
                const farmer = try self.world.intern_entity("Farmer");
                const gossip = try self.world.intern_entity("Gossip");
                const drifter = try self.world.intern_entity("Drifter");

                const hunger_rel = try self.world.intern_relation("Hunger", .property);
                const gold_rel = try self.world.intern_relation("Gold", .property);
                const friend_rel = try self.world.intern_relation("Friend", .set);

                const bakery_wp = try self.spatial.graph.add_waypoint(room, 2, -8, "Bakery");
                const farm_wp = try self.spatial.graph.add_waypoint(room, 2, 6, "Farm");
                const sq_wp = try self.spatial.graph.add_waypoint(room, 20, -1, "TownSquare");
                const jail_wp = try self.spatial.graph.add_waypoint(room, 38, 6, "SheriffsPost");
                try self.spatial.graph.connect(bakery_wp, sq_wp, null);
                try self.spatial.graph.connect(farm_wp, sq_wp, null);
                try self.spatial.graph.connect(sq_wp, jail_wp, null);

                const oven_ent = try self.world.intern_entity("BakeryOven");
                try self.spatial.add_hotspot(oven_ent, room, .{ .x = 2, .y = -12 }, 6, "BakeryOven", "Warm sourdough brick oven.");

                try self.spatial.register_entity(sheriff, jail_wp, 12);
                try self.spatial.register_entity(baker, bakery_wp, 10);
                try self.spatial.register_entity(farmer, farm_wp, 10);
                try self.spatial.register_entity(gossip, sq_wp, 12);
                try self.spatial.register_entity(drifter, sq_wp, 11);

                try self.world.remember(sheriff, hunger_rel, 20, 0);
                try self.world.remember(baker, hunger_rel, 25, 0);
                try self.world.remember(farmer, hunger_rel, 45, 0);
                try self.world.remember(drifter, hunger_rel, 70, 0);
                try self.world.remember(drifter, gold_rel, 0, 0);
                try self.world.remember(baker, friend_rel, gossip.to_int(), 0);
                try self.world.remember(gossip, friend_rel, sheriff.to_int(), 0);

                self.player_entity = sheriff;
                self.set_banner("Living Village: Watch autonomous drives or press [S] for Theft Catalyst!");
            },
        }

        self.record_snapshot();
        self.render_frame();
    }

    pub fn record_snapshot(self: *WasmRuntime) void {
        const slot = self.snapshot_count % MAX_WASM_SNAPSHOTS;
        var fbs = std.io.fixedBufferStream(&self.snapshot_bufs[slot]);
        self.world.save_state(fbs.writer()) catch return;
        self.snapshot_lens[slot] = fbs.pos;
        self.snapshot_ticks[slot] = self.world.current_tick;
        if (self.snapshot_count < MAX_WASM_SNAPSHOTS) {
            self.snapshot_count += 1;
        }
        if (self.world.current_tick > self.max_history_tick) {
            self.max_history_tick = self.world.current_tick;
        }
    }

    pub fn scrub_to_tick(self: *WasmRuntime, target_tick: u64) void {
        var best_slot: ?usize = null;
        var best_diff: u64 = std.math.maxInt(u64);
        var i: usize = 0;
        while (i < self.snapshot_count) : (i += 1) {
            const t = self.snapshot_ticks[i];
            const diff = if (t >= target_tick) t - target_tick else target_tick - t;
            if (diff < best_diff) {
                best_diff = diff;
                best_slot = i;
            }
        }
        if (best_slot) |slot| {
            var fbs = std.io.fixedBufferStream(self.snapshot_bufs[slot][0..self.snapshot_lens[slot]]);
            self.world.restore_state(fbs.reader()) catch return;
            self.is_paused = true;
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Scrubbed timeline to Tick {d}.", .{self.world.current_tick}) catch "Scrubbed timeline.";
            self.set_banner(msg);
        }
    }

    /// Steps one discrete simulation tick across the active scenario spine.
    pub fn step_tick(self: *WasmRuntime) !void {
        self.vm.world = &self.world;
        self.vm.chunk = &self.chunk;
        self.vm.spatial = &self.spatial;
        try self.vm.step_tick();

        if (self.scenario == .living_village) {
            if (self.world.lookup_entity("Drifter")) |drifter| {
                const hunger_rel = try self.world.intern_relation("Hunger", .property);
                const stolen_rel = try self.world.intern_relation("StolenFrom", .set);
                const rumor_rel = try self.world.intern_relation("KnowsRumor", .set);
                const arrested_rel = try self.world.intern_relation("Arrested", .set);
                const baker = self.world.lookup_entity("Baker") orelse .none;
                const sheriff = self.world.lookup_entity("Sheriff") orelse .none;

                if (!self.world.has_fact(drifter, arrested_rel, null)) {
                    const h = @min(100, (self.world.get_property(drifter, hunger_rel) orelse 50) + 5);
                    try self.world.remember(drifter, hunger_rel, h, 0);

                    if (h >= 80 and !self.world.has_fact(drifter, stolen_rel, null)) {
                        try self.world.remember(drifter, stolen_rel, baker.to_int(), 0);
                        try self.world.remember(baker, rumor_rel, drifter.to_int(), 0);
                        self.set_banner("[CRIME] Starving Drifter stole BreadLoaf from Baker!");
                    } else if (self.world.has_fact(baker, rumor_rel, drifter.to_int()) and
                        !self.world.has_fact(sheriff, rumor_rel, drifter.to_int()))
                    {
                        try self.world.remember(sheriff, rumor_rel, drifter.to_int(), 0);
                        self.set_banner("[RUMOR] Baker & Gossip spread theft rumor to Sheriff!");
                    } else if (self.world.has_fact(sheriff, rumor_rel, drifter.to_int())) {
                        try self.world.remember(drifter, arrested_rel, sheriff.to_int(), 0);
                        self.set_banner("[ARREST] Sheriff apprehended Drifter and restored order!");
                    }
                }
            }
        }

        self.record_snapshot();
    }

    /// Triggers scenario-specific emergent or puzzle catalysts (`[S]`, `[F]`, `[G]`).
    pub fn trigger_catalyst(self: *WasmRuntime) !void {
        switch (self.scenario) {
            .tavern_heist => {
                const guard = try self.world.intern_entity("Guard");
                const bard = try self.world.intern_entity("Bard");
                const cat = try self.world.intern_entity("Cat");
                const cheese = try self.world.intern_entity("Cheese");
                const charmed = try self.world.intern_relation("CharmedBy", .set);
                const carries = try self.world.intern_relation("Carries", .set);

                try self.world.remember(guard, charmed, bard.to_int(), self.world.current_tick + 10);
                _ = self.world.forget(guard, carries, cheese.to_int());
                try self.world.remember(cat, carries, cheese.to_int(), 0);
                self.set_banner("Bard charmed Guard! Cat snatched the Cheese!");
            },
            .spitting_contest => {
                const guybrush = try self.world.intern_entity("Guybrush");
                const champion = try self.world.intern_relation("SpitChampion", .property);
                try self.world.remember(guybrush, champion, 1, 0);
                self.set_banner("Guybrush spits across the tailwind! 1st Place Champion!");
            },
            .gk3_moustache => {
                const gabriel = try self.world.intern_entity("Gabriel");
                const disguised = try self.world.intern_relation("Disguised", .property);
                const keys = try self.world.intern_relation("HasBikeKeys", .property);
                try self.world.remember(gabriel, disguised, 1, 0);
                try self.world.remember(gabriel, keys, 1, 0);
                self.set_banner("Gabriel crafts the cat-hair moustache and rents Mosely's bike!");
            },
            .living_village => {
                const drifter = try self.world.intern_entity("Drifter");
                const hunger_rel = try self.world.intern_relation("Hunger", .property);
                const arrested_rel = try self.world.intern_relation("Arrested", .set);
                const stolen_rel = try self.world.intern_relation("StolenFrom", .set);
                _ = self.world.forget(drifter, arrested_rel, null);
                _ = self.world.forget(drifter, stolen_rel, null);
                try self.world.remember(drifter, hunger_rel, 85, 0);
                try self.step_tick();
            },
        }
        self.record_snapshot();
    }

    /// Dispatches a normalized browser mouse, keyboard, or touch event (P19-02, D-008, D-022).
    pub fn dispatch_event(self: *WasmRuntime, ev: BrowserInputEvent) !BrowserActionTag {
        switch (ev.kind) {
            .pointer_move, .touch_move => {
                self.hovered_x = ev.x;
                self.hovered_y = ev.y;
                return .hover_updated;
            },
            .right_click => {
                self.active_verb = self.active_verb.next();
                var buf: [48]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Active verb: {s}", .{self.active_verb.label()}) catch "Verb changed";
                self.set_banner(msg);
                return .verb_changed;
            },
            .touch_start, .pointer_down => {
                self.hovered_x = ev.x;
                self.hovered_y = ev.y;

                // Two-finger touch tap cycles the active adventure verb
                if (ev.kind == .touch_start and ev.touch_points >= 2) {
                    self.active_verb = self.active_verb.next();
                    return .verb_changed;
                }

                // 1. Timeline Scrubber Bar hit test (y in 22..38, x in 12..628)
                if (ev.y >= 22 and ev.y <= 38 and ev.x >= 12 and ev.x <= 628) {
                    if (self.max_history_tick > 0) {
                        const rel_x: u64 = @intCast(@max(0, ev.x - 12));
                        const target_tick = (rel_x * self.max_history_tick) / 616;
                        self.scrub_to_tick(target_tick);
                        return .timeline_scrubbed;
                    }
                }

                // 2. Bottom 5-Verb Bar hit test (y >= 324)
                if (ev.y >= 324 and ev.y <= 354) {
                    var vi: u8 = 0;
                    while (vi < 5) : (vi += 1) {
                        const bx: i32 = 12 + @as(i32, vi) * 58;
                        if (ev.x >= bx and ev.x <= bx + 52) {
                            self.active_verb = @enumFromInt(vi);
                            return .verb_changed;
                        }
                    }
                }

                // 3. When active_verb is WALK, prioritize Waypoint navigation first
                if (self.active_verb == .walk) {
                    for (self.spatial.graph.waypoints.items) |wp| {
                        const pt = world_to_canvas(wp.pos.x, wp.pos.y);
                        const dx = ev.x - pt.x;
                        const dy = ev.y - pt.y;
                        if (dx * dx + dy * dy <= 18 * 18) {
                            if (self.player_entity != .none) {
                                _ = try self.spatial.walk_to(self.player_entity, wp.id);
                                var buf: [64]u8 = undefined;
                                const msg = std.fmt.bufPrint(&buf, "Walking to {s}...", .{wp.name}) catch "Walking...";
                                self.set_banner(msg);
                                return .walk_issued;
                            }
                        }
                    }
                }

                // 4. Actors hit test
                var it = self.spatial.agents.iterator();
                while (it.next()) |entry| {
                    const agent = entry.value_ptr;
                    const pt = world_to_canvas(agent.pos.x, agent.pos.y);
                    const dx = ev.x - pt.x;
                    const dy = ev.y - pt.y;
                    if (dx * dx + dy * dy <= 16 * 16) {
                        const name = self.world.get_entity_name(agent.entity) orelse "Actor";
                        var buf: [80]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "[{s}] {s} at ({d}, {d})", .{
                            self.active_verb.label(),
                            name,
                            agent.pos.x,
                            agent.pos.y,
                        }) catch name;
                        self.set_banner(msg);
                        return .actor_interacted;
                    }
                }

                // 5. Hotspots hit test
                for (self.spatial.hotspots.items) |hs| {
                    const pt = world_to_canvas(hs.pos.x, hs.pos.y);
                    const dx = ev.x - pt.x;
                    const dy = ev.y - pt.y;
                    if (dx * dx + dy * dy <= 18 * 18) {
                        self.set_banner(hs.examine_text);
                        return .hotspot_inspected;
                    }
                }

                // 6. Fallback Waypoints hit test (walk_to motor intent)
                for (self.spatial.graph.waypoints.items) |wp| {
                    const pt = world_to_canvas(wp.pos.x, wp.pos.y);
                    const dx = ev.x - pt.x;
                    const dy = ev.y - pt.y;
                    if (dx * dx + dy * dy <= 18 * 18) {
                        if (self.player_entity != .none) {
                            _ = try self.spatial.walk_to(self.player_entity, wp.id);
                            var buf: [64]u8 = undefined;
                            const msg = std.fmt.bufPrint(&buf, "Walking to {s}...", .{wp.name}) catch "Walking...";
                            self.set_banner(msg);
                            return .walk_issued;
                        }
                    }
                }
                return .none;
            },
            .key_down => {
                switch (ev.key_code) {
                    ' ' => {
                        self.is_paused = !self.is_paused;
                        return .pause_toggled;
                    },
                    'n', 'N' => {
                        try self.step_tick();
                        return .tick_stepped;
                    },
                    'r', 'R' => {
                        self.scrub_to_tick(0);
                        return .rewound;
                    },
                    's', 'S', 'f', 'F', 'g', 'G' => {
                        try self.trigger_catalyst();
                        return .catalyst_triggered;
                    },
                    '1', '2', '3', '4' => {
                        const idx: u8 = ev.key_code - '1';
                        try self.load_scenario(WasmScenario.from_int(idx));
                        return .scenario_switched;
                    },
                    else => return .none,
                }
            },
            .touch_end => return .none,
        }
    }

    /// Renders the current simulation frame into the 640x360 RGBA8888 `WasmCanvas` framebuffer (P19-01).
    pub fn render_frame(self: *WasmRuntime) void {
        // 1. Background theme per vertical slice
        const bg_col = switch (self.scenario) {
            .tavern_heist => RgbaColor{ .r = 28, .g = 21, .b = 18 },
            .spitting_contest => RgbaColor{ .r = 16, .g = 42, .b = 58 },
            .gk3_moustache => RgbaColor{ .r = 32, .g = 52, .b = 34 },
            .living_village => RgbaColor{ .r = 22, .g = 44, .b = 28 },
        };
        self.canvas.clear(bg_col);

        // Stage Arena Box
        self.canvas.fill_rect(12, 44, CANVAS_WIDTH - 24, 248, RgbaColor{ .r = 36, .g = 44, .b = 56 });
        self.canvas.draw_rect_outline(12, 44, CANVAS_WIDTH - 24, 248, RgbaColor.hud_border);
        self.canvas.draw_text(self.scenario.title(), 22, 52, 1, RgbaColor.gold);

        // 2. Spatial Edges
        for (self.spatial.graph.edges.items) |e| {
            const wp_a = self.spatial.graph.get_waypoint(e.from);
            const wp_b = self.spatial.graph.get_waypoint(e.to);
            if (wp_a != null and wp_b != null) {
                const p1 = world_to_canvas(wp_a.?.pos.x, wp_a.?.pos.y);
                const p2 = world_to_canvas(wp_b.?.pos.x, wp_b.?.pos.y);
                self.canvas.draw_line(p1.x, p1.y, p2.x, p2.y, RgbaColor.slate);
            }
        }

        // 3. Hotspots
        for (self.spatial.hotspots.items) |hs| {
            const pt = world_to_canvas(hs.pos.x, hs.pos.y);
            self.canvas.fill_rect(pt.x - 10, pt.y - 10, 20, 20, RgbaColor.amber);
            self.canvas.draw_rect_outline(pt.x - 10, pt.y - 10, 20, 20, RgbaColor.white);
            self.canvas.draw_text(hs.name, pt.x - 18, pt.y - 20, 1, RgbaColor.gold);
        }

        // 4. Waypoints
        for (self.spatial.graph.waypoints.items) |wp| {
            const pt = world_to_canvas(wp.pos.x, wp.pos.y);
            self.canvas.fill_circle(pt.x, pt.y, 9, RgbaColor{ .r = 71, .g = 85, .b = 105 });
            self.canvas.draw_circle_outline(pt.x, pt.y, 9, RgbaColor.white);
            self.canvas.draw_text(wp.name, pt.x - 18, pt.y + 12, 1, RgbaColor.slate);
        }

        // 5. Actors
        var rank: i32 = 0;
        var it = self.spatial.agents.iterator();
        while (it.next()) |entry| {
            const agent = entry.value_ptr;
            const base = world_to_canvas(agent.pos.x, agent.pos.y);
            const px = base.x + @mod(rank, 3) * 14 - 14;
            const py = base.y - @divTrunc(rank, 3) * 16;
            rank += 1;

            const name = self.world.get_entity_name(agent.entity) orelse "Actor";
            const col = if (agent.entity == self.player_entity)
                RgbaColor.sky_blue
            else
                RgbaColor.emerald;

            self.canvas.fill_circle(px, py, 10, col);
            self.canvas.draw_circle_outline(px, py, 10, RgbaColor.white);
            self.canvas.draw_text(name, px - 14, py - 20, 1, RgbaColor.white);
        }

        // 6. Top Status & Timeline Scrubber Bar
        self.canvas.fill_rect(0, 0, CANVAS_WIDTH, 20, RgbaColor.hud_bg);
        var hdr_buf: [80]u8 = undefined;
        const hdr = std.fmt.bufPrint(&hdr_buf, "BeSpoke Wasm32 | Tick: {d:02} | Facts: {d} | {s}", .{
            self.world.current_tick,
            self.world.fact_count(),
            if (self.is_paused) "PAUSED" else "RUNNING",
        }) catch "BeSpoke Wasm32";
        self.canvas.draw_text(hdr, 12, 6, 1, RgbaColor.emerald);

        // Timeline Scrubber (y = 22..38)
        self.canvas.fill_rect(12, 22, CANVAS_WIDTH - 24, 16, RgbaColor.hud_bg);
        self.canvas.draw_rect_outline(12, 22, CANVAS_WIDTH - 24, 16, RgbaColor.hud_border);
        if (self.max_history_tick > 0) {
            const fill_w: i32 = @intCast((self.world.current_tick * 612) / self.max_history_tick);
            self.canvas.fill_rect(14, 24, fill_w, 12, RgbaColor.sky_blue);
        }
        self.canvas.draw_text("TIMELINE SCRUBBER (Click to Rewind/Scrub)", 20, 26, 1, RgbaColor.white);

        // 7. Banner & Bottom 5-Verb Bar
        if (self.banner_len > 0) {
            self.canvas.fill_rect(12, 296, CANVAS_WIDTH - 24, 22, RgbaColor.hud_bg);
            self.canvas.draw_rect_outline(12, 296, CANVAS_WIDTH - 24, 22, RgbaColor.gold);
            self.canvas.draw_text(self.get_banner(), 18, 303, 1, RgbaColor.gold);
        }

        self.canvas.fill_rect(0, 322, CANVAS_WIDTH, 38, RgbaColor.hud_bg);
        var vi: u8 = 0;
        while (vi < 5) : (vi += 1) {
            const v: WasmVerb = @enumFromInt(vi);
            const bx: i32 = 12 + @as(i32, vi) * 58;
            const is_sel = (self.active_verb == v);
            self.canvas.fill_rect(bx, 326, 52, 24, if (is_sel) RgbaColor.gold else RgbaColor{ .r = 30, .g = 41, .b = 59 });
            self.canvas.draw_rect_outline(bx, 326, 52, 24, RgbaColor.white);
            self.canvas.draw_text(v.label(), bx + 12, 334, 1, if (is_sel) RgbaColor.black else RgbaColor.white);
        }
        self.canvas.draw_text("[1-4]:Slice [S]:Catalyst [Space]:Pause [R]:Rewind", 310, 334, 1, RgbaColor.slate);
    }
};

// =============================================================================
// 3. Freestanding WebAssembly Global State & C-ABI Exports (P19-01, P19-02)
// =============================================================================

var global_wasm_heap: [2 * 1024 * 1024]u8 = undefined;
var global_fba = std.heap.FixedBufferAllocator.init(&global_wasm_heap);
var global_runtime: ?WasmRuntime = null;

pub export fn wasm_init(scenario_id: u8) void {
    global_fba.reset();
    global_runtime = WasmRuntime.init(
        global_fba.allocator(),
        WasmScenario.from_int(scenario_id),
    ) catch null;
}

pub export fn wasm_load_scenario(scenario_id: u8) void {
    wasm_init(scenario_id);
}

pub export fn wasm_step_tick() void {
    if (global_runtime) |*rt| {
        if (!rt.is_paused) {
            rt.step_tick() catch {};
            rt.render_frame();
        }
    }
}

pub export fn wasm_render_frame() void {
    if (global_runtime) |*rt| {
        rt.render_frame();
    }
}

pub export fn wasm_framebuffer_ptr() [*]const u8 {
    if (global_runtime) |*rt| {
        return &rt.canvas.pixels;
    }
    return &global_wasm_heap;
}

pub export fn wasm_framebuffer_len() usize {
    return FRAMEBUFFER_BYTES;
}

pub export fn wasm_on_pointer_down(x: i32, y: i32) u8 {
    if (global_runtime) |*rt| {
        const tag = rt.dispatch_event(.{ .kind = .pointer_down, .x = x, .y = y }) catch .none;
        rt.render_frame();
        return @intFromEnum(tag);
    }
    return 0;
}

pub export fn wasm_on_pointer_move(x: i32, y: i32) u8 {
    if (global_runtime) |*rt| {
        const tag = rt.dispatch_event(.{ .kind = .pointer_move, .x = x, .y = y }) catch .none;
        return @intFromEnum(tag);
    }
    return 0;
}

pub export fn wasm_on_right_click(x: i32, y: i32) u8 {
    if (global_runtime) |*rt| {
        const tag = rt.dispatch_event(.{ .kind = .right_click, .x = x, .y = y }) catch .none;
        rt.render_frame();
        return @intFromEnum(tag);
    }
    return 0;
}

pub export fn wasm_on_key_down(key_code: u8) u8 {
    if (global_runtime) |*rt| {
        const tag = rt.dispatch_event(.{ .kind = .key_down, .key_code = key_code }) catch .none;
        rt.render_frame();
        return @intFromEnum(tag);
    }
    return 0;
}

pub export fn wasm_on_touch(kind_id: u8, x: i32, y: i32, points: u8) u8 {
    if (global_runtime) |*rt| {
        const kind: BrowserEventKind = switch (kind_id) {
            0 => .touch_start,
            1 => .touch_move,
            else => .touch_end,
        };
        const tag = rt.dispatch_event(.{ .kind = kind, .x = x, .y = y, .touch_points = points }) catch .none;
        rt.render_frame();
        return @intFromEnum(tag);
    }
    return 0;
}

pub export fn wasm_scrub_to_tick(target_tick: u32) void {
    if (global_runtime) |*rt| {
        rt.scrub_to_tick(target_tick);
        rt.render_frame();
    }
}

pub export fn wasm_get_tick() u32 {
    if (global_runtime) |*rt| {
        return @intCast(rt.world.current_tick);
    }
    return 0;
}

pub export fn wasm_get_fact_count() u32 {
    if (global_runtime) |*rt| {
        return @intCast(rt.world.fact_count());
    }
    return 0;
}

// =============================================================================
// 4. Unit Tests (Phase 19: P19-01, P19-02, D-022)
// =============================================================================

test "P19-01: WasmCanvas RGBA8888 framebuffer drawing primitives and bitmap font" {
    const testing = std.testing;
    var canvas = WasmCanvas{};
    canvas.clear(RgbaColor.hud_bg);

    const p0 = canvas.get_pixel(10, 10);
    try testing.expectEqual(RgbaColor.hud_bg.r, p0.r);
    try testing.expectEqual(RgbaColor.hud_bg.g, p0.g);
    try testing.expectEqual(RgbaColor.hud_bg.b, p0.b);

    canvas.fill_rect(20, 20, 40, 30, RgbaColor.gold);
    const p1 = canvas.get_pixel(30, 30);
    try testing.expectEqual(RgbaColor.gold.r, p1.r);
    try testing.expectEqual(RgbaColor.gold.g, p1.g);

    canvas.fill_circle(100, 100, 12, RgbaColor.emerald);
    const p2 = canvas.get_pixel(100, 100);
    try testing.expectEqual(RgbaColor.emerald.r, p2.r);

    canvas.draw_text("BESPOKE", 50, 50, 2, RgbaColor.white);
}

test "P19-01: WasmRuntime initializes all 4 vertical slices, steps ticks, and renders RGBA8888 frames" {
    const testing = std.testing;
    var rt = try WasmRuntime.init(testing.allocator, .tavern_heist);
    defer rt.deinit();

    try testing.expectEqual(@as(u64, 0), rt.world.current_tick);
    try testing.expect(rt.world.fact_count() > 0);

    try rt.step_tick();
    try testing.expectEqual(@as(u64, 1), rt.world.current_tick);

    // Switch across all 4 vertical slice scenarios
    try rt.load_scenario(.spitting_contest);
    try testing.expectEqual(WasmScenario.spitting_contest, rt.scenario);

    try rt.load_scenario(.gk3_moustache);
    try testing.expectEqual(WasmScenario.gk3_moustache, rt.scenario);

    try rt.load_scenario(.living_village);
    try testing.expectEqual(WasmScenario.living_village, rt.scenario);

    // Step Living Village through emergent theft, rumor, and arrest
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try rt.step_tick();
    }
    rt.render_frame();
    const drifter = rt.world.lookup_entity("Drifter").?;
    const arrested = rt.world.lookup_relation("Arrested").?;
    try testing.expect(rt.world.has_fact(drifter, arrested, null));
}

test "P19-02: Browser event bridge maps mouse, keyboard, and touch events to BeSpoke intents" {
    const testing = std.testing;
    var rt = try WasmRuntime.init(testing.allocator, .tavern_heist);
    defer rt.deinit();

    // 1. Click verb button 1 (LOOK) on bottom verb bar (x=75, y=335)
    const verb_res = try rt.dispatch_event(.{ .kind = .pointer_down, .x = 75, .y = 335 });
    try testing.expectEqual(BrowserActionTag.verb_changed, verb_res);
    try testing.expectEqual(WasmVerb.look_at, rt.active_verb);

    // 2. Right-click cycles verb to TALK
    const rc_res = try rt.dispatch_event(.{ .kind = .right_click, .x = 100, .y = 100 });
    try testing.expectEqual(BrowserActionTag.verb_changed, rc_res);
    try testing.expectEqual(WasmVerb.talk_to, rt.active_verb);

    // 3. Two-finger touch tap cycles verb to TAKE
    const touch_res = try rt.dispatch_event(.{ .kind = .touch_start, .x = 100, .y = 100, .touch_points = 2 });
    try testing.expectEqual(BrowserActionTag.verb_changed, touch_res);
    try testing.expectEqual(WasmVerb.pick_up, rt.active_verb);

    // 4. Click Cellar waypoint at world (40, 0) -> canvas (520, 185) issues walk_to motor intent
    const walk_res = try rt.dispatch_event(.{ .kind = .pointer_down, .x = 520, .y = 185 });
    try testing.expectEqual(BrowserActionTag.walk_issued, walk_res);

    // 5. Keyboard 'n' steps tick, 's' triggers catalyst, and timeline click scrubs back to Tick 0
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'n' });
    try testing.expectEqual(@as(u64, 1), rt.world.current_tick);

    const cat_res = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 's' });
    try testing.expectEqual(BrowserActionTag.catalyst_triggered, cat_res);

    const scrub_res = try rt.dispatch_event(.{ .kind = .pointer_down, .x = 14, .y = 28 });
    try testing.expectEqual(BrowserActionTag.timeline_scrubbed, scrub_res);
    try testing.expectEqual(@as(u64, 0), rt.world.current_tick);
}
