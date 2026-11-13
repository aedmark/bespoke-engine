//! BeSpoke Engine: WebAssembly (wasm32-freestanding) Runtime Harness & Browser Event Bridge (Phase 19, D-001, D-008, D-022)
//!
//! Compiles the pure Zig simulation spine (World, SpatialSystem, VM, Compiler, Repl)
//! to `wasm32-freestanding` with zero libc or external dependencies, rendering directly
//! into a 640x360 RGBA8888 linear-memory framebuffer (`WasmCanvas`) for HTML5 Canvas
//! `ImageData` blitting and bridging DOM mouse, keyboard, and touch events to BeSpoke intents.
//! What is on the stage comes from the host's `Deck` table (P32-04, D-042).

const std = @import("std");
const builtin = @import("builtin");
const world_mod = @import("world.zig");
const bytecode_mod = @import("bytecode.zig");
const vm_mod = @import("vm.zig");
const spatial_mod = @import("spatial.zig");
const compiler_mod = @import("compiler.zig");
const repl_mod = @import("repl.zig");
const host_mod = @import("host.zig");
const package_mod = @import("package.zig");
const dialogue_mod = @import("dialogue.zig");
const inspector_mod = @import("wasm_inspector.zig");
const draft_mod = @import("draft.zig");
const audio_mod = @import("audio.zig");
const hypervisor_mod = @import("hypervisor.zig");
pub const TemporalHypervisor = hypervisor_mod.TemporalHypervisor;
const display_mod = @import("display.zig");
pub const Inspector = inspector_mod.Inspector;
pub const InspectorKey = inspector_mod.Key;
const CompiledProgram = compiler_mod.codegen.CompiledProgram;
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
/// The ceiling on the browser runtime's heap (D-071). The previous fixed 2 MiB buffer could not
/// reuse freed memory; a tangent world forked again after a rewind would have leaked 256 KiB.
pub const WASM_HEAP_LIMIT: usize = 16 * 1024 * 1024;

/// Fails any allocation that would take the heap past `limit`, and otherwise passes it to
/// `child`. Freed and shrunk memory is counted back, so the ceiling bounds live memory.
pub const CappedAllocator = struct {
    child: std.mem.Allocator,
    limit: usize,
    used: usize = 0,

    pub fn allocator(self: *CappedAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .free = free } };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *CappedAllocator = @ptrCast(@alignCast(ctx));
        if (len > self.limit - self.used) return null;
        const ptr = self.child.rawAlloc(len, ptr_align, ret_addr) orelse return null;
        self.used += len;
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *CappedAllocator = @ptrCast(@alignCast(ctx));
        if (new_len > buf.len and new_len - buf.len > self.limit - self.used) return false;
        if (!self.child.rawResize(buf, buf_align, new_len, ret_addr)) return false;
        self.used = self.used - buf.len + new_len;
        return true;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *CappedAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(buf, buf_align, ret_addr);
        self.used -= buf.len;
    }
};

/// The most stereo frames one `wasm_audio_render` call fills (D-071).
pub const AUDIO_MAX_FRAMES: usize = 4096;
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

/// One playable scene of the browser runtime, supplied by the host (P32-04, D-042). `load`
/// builds the stage on a freshly reset world, spatial graph, and VM; `after_tick` runs after
/// every tick; `catalyst` answers the `[S]`, `[F]`, and `[G]` keys. Decks are numbered in
/// table order, and the `[1]` to `[9]` keys switch between them.
const NO_DECK_BACKGROUND = RgbaColor{ .r = 28, .g = 32, .b = 40 };

pub const Deck = struct {
    title: []const u8,
    background: RgbaColor = RgbaColor{ .r = 28, .g = 32, .b = 40 },
    load: *const fn (rt: *WasmRuntime) anyerror!void,
    after_tick: ?*const fn (rt: *WasmRuntime) anyerror!void = null,
    catalyst: ?*const fn (rt: *WasmRuntime) anyerror!void = null,
    /// Resolves a choice from a host-generated dialogue: the selection's action id. Scripted
    /// choices need no hook; their fiber resumes (D-046, D-071).
    on_choice: ?*const fn (rt: *WasmRuntime, action: u32) anyerror!void = null,
    /// The cues the verbs fire; a script that answers `Talk` or `PicksUp` names them (D-071).
    cues: VerbCues = .{},
};

/// The cue each verb fires on a person or prop in a script deck (D-069, D-071).
pub const VerbCues = struct {
    look: []const u8 = "LooksAt",
    talk: []const u8 = "TalksTo",
    take: []const u8 = "Takes",
    use: []const u8 = "Uses",

    pub fn of(self: VerbCues, verb: WasmVerb) ?[]const u8 {
        return switch (verb) {
            .walk => null,
            .look_at => self.look,
            .talk_to => self.talk,
            .pick_up => self.take,
            .use_with => self.use,
        };
    }
};

/// A deck that runs a game's own script (P29-03, D-066). `program` is a `.bspk` package or
/// `.bespoke` source, usually embedded with `@embedFile`; a package needs no compiler work in
/// the browser. The deck ticks through `host.tick`, shows speech in the banner, and answers an
/// open dialogue with the number keys.
pub fn script_deck(comptime title: []const u8, comptime program: []const u8) Deck {
    return script_deck_with(title, program, .{});
}

/// What a script deck adds to its script (P30-05, D-069). `player` names the actor clicks and
/// verbs act for, when the script's first routine is not the protagonist. `setup` runs after the
/// script has started, for host work the desktop proof does in Zig (placing an actor, choosing
/// the opening scene). `catalyst` answers the `[S]` key; `after_tick` runs after every tick.
pub const ScriptDeckOptions = struct {
    player: ?[]const u8 = null,
    /// The banner shown when the deck loads, unless the script speaks first.
    intro: ?[]const u8 = null,
    background: RgbaColor = NO_DECK_BACKGROUND,
    setup: ?*const fn (rt: *WasmRuntime) anyerror!void = null,
    catalyst: ?*const fn (rt: *WasmRuntime) anyerror!void = null,
    after_tick: ?*const fn (rt: *WasmRuntime) anyerror!void = null,
    on_choice: ?*const fn (rt: *WasmRuntime, action: u32) anyerror!void = null,
    cues: VerbCues = .{},
    /// Music for a script that declares no scores, such as a proof's desktop soundtrack (D-071).
    soundtrack: ?*const audio_mod.Soundtrack = null,
};

pub fn script_deck_with(comptime title: []const u8, comptime program: []const u8, comptime options: ScriptDeckOptions) Deck {
    const Loader = struct {
        fn load(rt: *WasmRuntime) anyerror!void {
            try rt.load_program(program);
            if (options.player) |name| rt.player_entity = try rt.world.intern_entity(name);
            if (options.soundtrack) |music| {
                const scored = if (rt.script_music) |m| m.has_scores() else false;
                if (!scored) rt.audio.set_soundtrack(music);
            }
            if (options.intro) |text| {
                if (rt.banner_len == 0) rt.set_banner(text);
            }
            if (options.setup) |setup| try setup(rt);
            rt.sync_audio();
        }
    };
    return .{
        .title = title,
        .background = options.background,
        .load = Loader.load,
        .catalyst = options.catalyst,
        .after_tick = options.after_tick,
        .on_choice = options.on_choice,
        .cues = options.cues,
    };
}

/// The cue a verb fires on a clicked person or prop in a script deck (D-069); WALK fires none.
pub fn verb_cue(verb: WasmVerb) ?[]const u8 {
    return (VerbCues{}).of(verb);
}

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
    /// A number key answered the open dialogue of a script deck (P29-03, D-066).
    dialogue_answered,
    /// A verb on a person or prop fired the script's cue (P30-05, D-069).
    cue_fired,
    /// `I` opened or closed the state inspector (P30-04, D-070).
    inspector_toggled,
    /// A note key added to the distaff, or wove its phrase (D-071).
    note_played,
    /// A key or click moved the inspector's selection, focus, or filter.
    inspector_navigated,
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

pub const CanvasPoint = struct { x: i32, y: i32 };

/// How the stage is drawn (P30-05, D-069): only the shown room, fitted into the stage box. The
/// room is the VM's current scene, else the room of the first mark. Marks and props of that
/// room set the bounds; the scale never exceeds the old fixed 10 by 7 pixels per unit, so small
/// stages keep their look, and wide or tall ones shrink to fit. Integer arithmetic only.
pub const Projection = struct {
    room: ?EntityId = null,
    /// Twice the bounds' centre, so odd spans need no rounding.
    centre2_x: i32 = 0,
    centre2_y: i32 = 0,
    /// Pixels per world unit, times 100.
    scale_x: i32 = 1000,
    scale_y: i32 = 700,
    fixed: bool = true,

    const STAGE_CENTRE_X: i32 = 320;
    const STAGE_CENTRE_Y: i32 = 170;
    const STAGE_HALF_W: i32 = 260;
    const STAGE_HALF_H: i32 = 90;

    pub fn point(self: Projection, x: i32, y: i32) CanvasPoint {
        if (self.fixed) {
            const p = world_to_canvas(x, y);
            return .{ .x = p.x, .y = p.y };
        }
        return .{
            .x = STAGE_CENTRE_X + @divTrunc((2 * x - self.centre2_x) * self.scale_x, 200),
            .y = STAGE_CENTRE_Y + @divTrunc((2 * y - self.centre2_y) * self.scale_y, 200),
        };
    }

    pub fn shows(self: Projection, room: EntityId) bool {
        return self.room == null or self.room.? == room;
    }
};

// =============================================================================
// 2. WebAssembly Runtime & Browser Event Bridge (P19-01, P19-02, D-001, D-008)
// =============================================================================

pub const WasmRuntime = struct {
    allocator: std.mem.Allocator,
    world: World,
    spatial: SpatialSystem,
    chunk: bytecode_mod.BytecodeChunk,
    vm: VM,
    decks: []const Deck,
    deck_index: u8 = 0,
    active_verb: WasmVerb = .walk,
    is_paused: bool = false,
    hovered_x: i32 = 0,
    hovered_y: i32 = 0,
    player_entity: EntityId = .none,
    /// The compiled script of a script deck; null for decks built in Zig (D-066).
    program: ?CompiledProgram = null,
    /// The state inspector overlay (D-070). Its navigation is not World state.
    inspector: Inspector = .{},
    /// The phrase being played on the distaff, in decks whose script declares drafts (D-071).
    /// Peripheral input like a half-typed line: never saved or rewound (D-029).
    distaff: draft_mod.DistaffInput = .{},
    /// The engine synthesizer (D-071): the page pulls its samples with `wasm_audio_render`.
    audio: audio_mod.AudioBridge = .{},
    /// The script's scores as the bridge's soundtrack. Heap-allocated, because the bridge keeps
    /// a pointer to it and the runtime itself is moved after `init`.
    script_music: ?*host_mod.ScriptSoundtrack = null,
    /// A temporal hypervisor a deck attaches (D-071). While a branch is live the VM, the story,
    /// the inspector, and the audio follow the branch world; the timeline stays on the primary.
    /// Heap-allocated: it keeps a pointer to the primary World, re-pointed by `bind`.
    hypervisor: ?*TemporalHypervisor = null,

    banner_buf: [96]u8 = [_]u8{0} ** 96,
    banner_len: usize = 0,
    max_history_tick: u64 = 0,

    // Fixed ring buffer of binary World snapshots for instant browser timeline scrubbing
    snapshot_bufs: [MAX_WASM_SNAPSHOTS][SNAPSHOT_SLOT_BYTES]u8 = undefined,
    snapshot_lens: [MAX_WASM_SNAPSHOTS]usize = [_]usize{0} ** MAX_WASM_SNAPSHOTS,
    snapshot_ticks: [MAX_WASM_SNAPSHOTS]u64 = [_]u64{0} ** MAX_WASM_SNAPSHOTS,
    snapshot_count: usize = 0,

    canvas: WasmCanvas = .{},

    /// Starts on deck `initial` of `decks`; an index past the end starts on the first deck.
    pub fn init(allocator: std.mem.Allocator, decks: []const Deck, initial: u8) !WasmRuntime {
        var rt = WasmRuntime{
            .allocator = allocator,
            .world = try World.init(allocator, 256 * 1024),
            .spatial = SpatialSystem.init(allocator),
            .chunk = bytecode_mod.BytecodeChunk.init(allocator),
            .vm = undefined,
            .decks = decks,
        };
        rt.vm = VM.init(allocator, &rt.world, &rt.chunk);
        rt.vm.spatial = &rt.spatial;
        try rt.load_deck(initial);
        return rt;
    }

    pub fn deinit(self: *WasmRuntime) void {
        // Declarations borrow World text, so the program goes before the World.
        self.drop_program();
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

    /// Resets the spine and loads deck `index` (the first deck if out of range).
    pub fn load_deck(self: *WasmRuntime, index: u8) !void {
        self.drop_program();
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

        self.deck_index = if (index < self.decks.len) index else 0;
        self.inspector = .{};
        self.distaff = .{};
        self.active_verb = .walk;
        self.is_paused = false;
        self.max_history_tick = 0;
        self.snapshot_count = 0;

        if (self.decks.len > 0) try self.decks[self.deck_index].load(self);
        self.record_snapshot();
        self.render_frame();
    }

    fn drop_program(self: *WasmRuntime) void {
        if (self.hypervisor) |hv| {
            hv.deinit();
            self.allocator.destroy(hv);
            self.hypervisor = null;
        }
        if (self.script_music) |music| {
            self.audio.set_soundtrack(null);
            music.deinit();
            self.allocator.destroy(music);
            self.script_music = null;
        }
        if (self.program) |*program| program.deinit();
        self.program = null;
    }

    /// Tells the synthesizer the scene and the script's chosen score, as the desktop frame does
    /// (D-062); it changes track only when either changes.
    pub fn sync_audio(self: *WasmRuntime) void {
        const world = self.active_world();
        const scene_name = if (self.vm.current_scene) |s| world.get_entity_name(s) orelse "" else "";
        const score = display_mod.current_score_entity(world, self.vm.current_scene);
        const score_name = if (score) |id| world.get_entity_name(id) orelse "" else "";
        self.audio.process_scene_and_cues(scene_name, score_name);
    }

    /// Loads a script or package into the freshly reset spine and starts it as the stock hosts
    /// do (`host.start_script`). Called from a deck's `load`.
    pub fn load_program(self: *WasmRuntime, data: []const u8) !void {
        const is_package = data.len >= 4 and std.mem.eql(u8, data[0..4], &package_mod.PACKAGE_MAGIC);
        if (is_package) {
            var stream = std.io.fixedBufferStream(data);
            self.program = try package_mod.load_package(self.allocator, stream.reader(), &self.world, &self.spatial);
        } else {
            self.program = try compiler_mod.compile_source(self.allocator, &self.world, &self.spatial, data);
        }
        const program = &self.program.?;
        self.vm.deinit();
        self.vm = VM.init(self.allocator, &self.world, &program.chunk);
        self.vm.spatial = &self.spatial;
        try host_mod.initialize_subsystems(&self.world, program);
        try self.vm.load_compiled_rules(program);
        self.player_entity = try host_mod.start_script(&self.world, &self.spatial, &self.vm, program);
        // A script that never names its opening scene starts in its first mark's room, the room
        // the stage shows anyway, so music and scene rules have a scene (D-071).
        if (self.vm.current_scene == null and self.spatial.graph.waypoints.items.len > 0) {
            try self.vm.transition_to_scene(self.spatial.graph.waypoints.items[0].room);
        }
        const music = try self.allocator.create(host_mod.ScriptSoundtrack);
        errdefer self.allocator.destroy(music);
        music.* = try host_mod.ScriptSoundtrack.init(self.allocator, program);
        self.script_music = music;
        if (music.has_scores()) self.audio.set_soundtrack(&music.soundtrack);
        self.sync_audio();
        self.show_story();
    }

    /// The room on stage and how to fit it into the canvas (D-069). Decks without marks keep
    /// the fixed mapping.
    pub fn projection(self: *const WasmRuntime) Projection {
        const waypoints = self.spatial.graph.waypoints.items;
        if (waypoints.len == 0) return .{};
        var room = waypoints[0].room;
        if (self.vm.current_scene) |scene| {
            for (waypoints) |wp| if (wp.room == scene) {
                room = scene;
                break;
            };
        }
        var min_x: i32 = std.math.maxInt(i32);
        var max_x: i32 = std.math.minInt(i32);
        var min_y: i32 = std.math.maxInt(i32);
        var max_y: i32 = std.math.minInt(i32);
        for (waypoints) |wp| if (wp.room == room) {
            min_x = @min(min_x, wp.pos.x);
            max_x = @max(max_x, wp.pos.x);
            min_y = @min(min_y, wp.pos.y);
            max_y = @max(max_y, wp.pos.y);
        };
        for (self.spatial.hotspots.items) |hs| if (hs.room == room) {
            min_x = @min(min_x, hs.pos.x);
            max_x = @max(max_x, hs.pos.x);
            min_y = @min(min_y, hs.pos.y);
            max_y = @max(max_y, hs.pos.y);
        };
        var scale_x: i32 = 1000;
        if (max_x > min_x) scale_x = @min(scale_x, @divTrunc(Projection.STAGE_HALF_W * 2 * 100, max_x - min_x));
        var scale_y: i32 = @divTrunc(scale_x * 7, 10);
        if (max_y > min_y) scale_y = @min(scale_y, @divTrunc(Projection.STAGE_HALF_H * 2 * 100, max_y - min_y));
        return .{
            .room = room,
            .centre2_x = min_x + max_x,
            .centre2_y = min_y + max_y,
            .scale_x = scale_x,
            .scale_y = scale_y,
            .fixed = false,
        };
    }

    /// The room an agent stands in: the room of the mark it last reached.
    fn agent_room(self: *const WasmRuntime, entity: EntityId) ?EntityId {
        const wp = self.spatial.get_current_waypoint(entity) orelse return null;
        return (self.spatial.graph.get_waypoint(wp) orelse return null).room;
    }

    /// A verb on a person or prop in a script deck fires the script's cue for the player and
    /// runs the tick that answers it (D-069). Without a handler the banner says so; LOOK at a
    /// prop then falls back to its examine text.
    fn act_on(self: *WasmRuntime, target: EntityId, examine: ?[]const u8) !?BrowserActionTag {
        const program = if (self.program) |*p| p else return null;
        const cues: VerbCues = if (self.decks.len > 0) self.decks[self.deck_index].cues else .{};
        const cue = cues.of(self.active_verb) orelse return null;
        // In a deck with drafts, whatever the player acts on becomes the weave target (D-071).
        self.distaff.target = target;
        if (self.player_entity == .none) return null;
        self.bind();
        if ((try self.vm.fire_cue(program, cue, self.player_entity, target, null)) != null) {
            self.audio.enqueue_sfx(.click);
            try self.step_tick();
            return .cue_fired;
        }
        if (self.active_verb == .look_at) {
            if (examine) |text| {
                self.set_banner(text);
                return .hotspot_inspected;
            }
        }
        self.set_banner("Nothing happens.");
        return .cue_fired;
    }

    fn has_drafts(self: *const WasmRuntime) bool {
        return if (self.program) |*p| p.drafts.items.len > 0 else false;
    }

    /// A note key in a deck with drafts (D-071): adds the note within the reach the script grants
    /// (`DistaffReach` on the player, else all seven), and weaves the fourth note's phrase on the
    /// last person or prop acted on. Two ticks run, so a weave queued by the handler dispatches
    /// and its own handler speaks, as on desktop (D-029).
    pub fn play_note(self: *WasmRuntime, key_code: u8) !BrowserActionTag {
        if (!self.has_drafts() or self.player_entity == .none) return .none;
        const note: draft_mod.Note = switch (std.ascii.toUpper(key_code)) {
            'C' => .C,
            'D' => .D,
            'E' => .E,
            'F' => .F,
            'G' => .G,
            'A' => .A,
            'B' => .B,
            else => return .none,
        };
        self.distaff.set_reach_from(self.active_world(), self.player_entity, "DistaffReach", 7);
        if (!self.distaff.can_play(note)) {
            self.distaff.clear();
            self.set_banner("That note is beyond the distaff's reach.");
            return .note_played;
        }
        self.audio.enqueue_note(@intFromEnum(note));
        const phrase = self.distaff.press(note) orelse return .note_played;
        if (self.distaff.target == .none) {
            self.set_banner("Act on something first: it becomes what the draft is woven on.");
            return .note_played;
        }
        self.bind();
        const program = &self.program.?;
        const fiber = try self.vm.weave_notes(program, self.player_entity, phrase, self.distaff.target);
        self.distaff.outcome = if (fiber != null) .woven else .fizzled;
        self.audio.enqueue_sfx(if (fiber != null) .weave_success else .weave_fizzle);
        try self.step_tick();
        try self.step_tick();
        if (fiber == null) self.set_banner("The draft unravels.");
        return .note_played;
    }

    /// Answers the open dialogue with option `index` (D-046): a scripted choice resumes its
    /// fiber and ticks so the body runs; a host-generated choice goes to the deck's `on_choice`
    /// with its action id (D-071). An index past the offered options does nothing.
    pub fn answer(self: *WasmRuntime, index: usize) !void {
        self.bind();
        const selection = (try self.vm.choose(index)) orelse return;
        self.audio.enqueue_sfx(.dialogue_blip);
        if (selection.is_scripted()) {
            try self.step_tick();
        } else if (self.decks.len > 0) {
            if (self.decks[self.deck_index].on_choice) |resolve| try resolve(self, selection.action);
            self.record_snapshot();
        }
    }

    /// Puts this tick's speech, else a newly offered set of choices, in the banner.
    fn show_story(self: *WasmRuntime) void {
        var buf: [256]u8 = undefined;
        if (host_mod.speech_this_tick(self.active_world(), &self.vm, &buf)) |line| self.set_banner(line);
        if (dialogue_mod.view(self.active_world())) |open| {
            var fbs = std.io.fixedBufferStream(&buf);
            const w = fbs.writer();
            for (0..open.count) |i| w.print("{s}[{d}] {s}", .{ if (i == 0) "" else "  ", i + 1, open.text(i) }) catch break;
            self.set_banner(fbs.getWritten());
        }
    }

    pub fn record_snapshot(self: *WasmRuntime) void {
        const slot = self.snapshot_count % MAX_WASM_SNAPSHOTS;
        var fbs = std.io.fixedBufferStream(&self.snapshot_bufs[slot]);
        self.world.save_state(fbs.writer()) catch return;
        if (self.hypervisor) |hv| write_temporal(hv, fbs.writer()) catch return;
        self.snapshot_lens[slot] = fbs.pos;
        self.snapshot_ticks[slot] = self.clock();
        if (self.snapshot_count < MAX_WASM_SNAPSHOTS) {
            self.snapshot_count += 1;
        }
        if (self.clock() > self.max_history_tick) {
            self.max_history_tick = self.clock();
        }
    }

    /// The hypervisor's part of a snapshot (D-071): whether a branch is live, its world, and the
    /// countdown and collapse state. The browser keeps its own compact form, because its slots
    /// are small and its branch is restored in place rather than re-read into a new World.
    fn write_temporal(hv: *TemporalHypervisor, writer: anytype) !void {
        try writer.writeByte(@intFromBool(hv.branch_world != null));
        if (hv.branch_world) |*branch| try branch.save_state(writer);
        try writer.writeInt(u64, hv.ticks_elapsed, .little);
        try writer.writeByte(@intFromEnum(hv.collapse_state));
    }

    fn read_temporal(self: *WasmRuntime, hv: *TemporalHypervisor, reader: anytype) !void {
        const had_branch = (try reader.readByte()) != 0;
        if (had_branch) {
            // A rewind to before a collapse brings the branch back: clone a world to restore over.
            if (hv.branch_world == null) hv.branch_world = try self.world.clone(self.allocator);
            try hv.branch_world.?.restore_state(reader);
        } else if (hv.branch_world) |*branch| {
            branch.deinit();
            hv.branch_world = null;
        }
        hv.branch_active = had_branch;
        hv.tangent_active = had_branch;
        hv.ticks_elapsed = try reader.readInt(u64, .little);
        hv.collapse_state = std.meta.intToEnum(hypervisor_mod.BranchCollapseState, try reader.readByte()) catch return error.InvalidSnapshot;
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
            if (self.hypervisor) |hv| self.read_temporal(hv, fbs.reader()) catch {
                self.set_banner("Could not restore the tangent world here.");
                return;
            };
            self.bind();
            self.is_paused = true;
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Scrubbed timeline to Tick {d}.", .{self.clock()}) catch "Scrubbed timeline.";
            self.set_banner(msg);
        }
    }

    /// Creates the deck's temporal hypervisor over the primary world (D-071).
    pub fn attach_hypervisor(self: *WasmRuntime) !*TemporalHypervisor {
        if (self.hypervisor) |hv| return hv;
        const hv = try self.allocator.create(TemporalHypervisor);
        hv.* = TemporalHypervisor.init(self.allocator, &self.world);
        self.hypervisor = hv;
        return hv;
    }

    /// The runtime's clock, which the timeline, header, and page read: the active world's tick
    /// (D-071). A branch is forked from the primary with its tick and runs on from it.
    pub fn clock(self: *WasmRuntime) u64 {
        return self.active_world().current_tick;
    }

    /// The world the player is in: the live branch, else the primary world.
    pub fn active_world(self: *WasmRuntime) *World {
        if (self.hypervisor) |hv| {
            hv.primary_world = &self.world;
            return hv.active_world();
        }
        return &self.world;
    }

    /// Points the VM at this runtime's active World, SpatialSystem, and chunk. The runtime is
    /// returned by value from `init`, so every entry point that reaches the VM calls this first.
    pub fn bind(self: *WasmRuntime) void {
        self.vm.world = self.active_world();
        self.vm.spatial = &self.spatial;
        self.vm.chunk = if (self.program) |*program| &program.chunk else &self.chunk;
    }

    /// Steps one discrete simulation tick across the active scenario spine.
    pub fn step_tick(self: *WasmRuntime) !void {
        self.bind();
        if (self.program) |*program| {
            _ = try host_mod.tick(&self.vm, program);
            self.show_story();
            self.sync_audio();
        } else {
            try self.vm.step_tick();
        }

        const before = self.clock();
        if (self.decks.len > 0) {
            if (self.decks[self.deck_index].after_tick) |rule| try rule(self);
        }
        // A branch that collapsed this tick hands the clock back to the primary world, which sat
        // still while the branch ran. The primary takes up the branch's tick so the timeline
        // never runs backwards (D-071).
        if (self.clock() < before) self.world.current_tick = before;
        self.bind();

        self.record_snapshot();
    }

    /// Triggers scenario-specific emergent or puzzle catalysts (`[S]`, `[F]`, `[G]`).
    pub fn trigger_catalyst(self: *WasmRuntime) !void {
        self.bind();
        const catalyst = if (self.decks.len > 0) self.decks[self.deck_index].catalyst else null;
        if (catalyst) |run| {
            try run(self);
        } else {
            self.set_banner("This deck has no catalyst.");
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

                // While the inspector is open, the stage belongs to it; the timeline still scrubs.
                const on_timeline = ev.y >= 22 and ev.y <= 38 and ev.x >= 12 and ev.x <= 628;
                if (self.inspector.open and !on_timeline) {
                    self.inspector.capture(self.active_world());
                    return if (self.inspector.click(ev.x, ev.y)) .inspector_navigated else .none;
                }

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

                const proj = self.projection();

                // 3. When active_verb is WALK, prioritize Waypoint navigation first
                if (self.active_verb == .walk) {
                    for (self.spatial.graph.waypoints.items) |wp| {
                        if (!proj.shows(wp.room)) continue;
                        const pt = proj.point(wp.pos.x, wp.pos.y);
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
                    if (self.agent_room(agent.entity)) |room| if (!proj.shows(room)) continue;
                    const pt = proj.point(agent.pos.x, agent.pos.y);
                    const dx = ev.x - pt.x;
                    const dy = ev.y - pt.y;
                    if (dx * dx + dy * dy <= 16 * 16) {
                        if (agent.entity != self.player_entity) {
                            if (try self.act_on(agent.entity, null)) |tag| return tag;
                        }
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
                    if (!proj.shows(hs.room)) continue;
                    const pt = proj.point(hs.pos.x, hs.pos.y);
                    const dx = ev.x - pt.x;
                    const dy = ev.y - pt.y;
                    if (dx * dx + dy * dy <= 18 * 18) {
                        if (try self.act_on(hs.entity, hs.examine_text)) |tag| return tag;
                        self.set_banner(hs.examine_text);
                        return .hotspot_inspected;
                    }
                }

                // 6. Fallback Waypoints hit test (walk_to motor intent)
                for (self.spatial.graph.waypoints.items) |wp| {
                    if (!proj.shows(wp.room)) continue;
                    const pt = proj.point(wp.pos.x, wp.pos.y);
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
                if (ev.key_code == 'i' or ev.key_code == 'I') {
                    self.inspector.toggle(&self.is_paused);
                    return .inspector_toggled;
                }
                // While the inspector is open its keys come first, the timeline keys still work,
                // and the clock, deck, and solve keys wait until it closes.
                if (self.inspector.open) {
                    self.inspector.capture(self.active_world());
                    if (self.inspector.key(ev.key_code)) return .inspector_navigated;
                    if (ev.key_code != 'r' and ev.key_code != 'R') return .none;
                }
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
                    'c', 'C', 'd', 'D', 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A', 'b', 'B' => {
                        return try self.play_note(ev.key_code);
                    },
                    's', 'S' => {
                        try self.trigger_catalyst();
                        return .catalyst_triggered;
                    },
                    '1'...'9' => {
                        const idx: u8 = ev.key_code - '1';
                        // While a script deck's dialogue is open, the number keys answer it;
                        // a scripted choice ticks at once so its body runs.
                        if (self.program != null and dialogue_mod.view(self.active_world()) != null) {
                            try self.answer(idx);
                            return .dialogue_answered;
                        }
                        if (idx >= self.decks.len) return .none;
                        try self.load_deck(idx);
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
        const deck: ?Deck = if (self.decks.len > 0) self.decks[self.deck_index] else null;
        const bg_col = if (deck) |d| d.background else NO_DECK_BACKGROUND;
        self.canvas.clear(bg_col);

        // Stage Arena Box
        self.canvas.fill_rect(12, 44, CANVAS_WIDTH - 24, 248, RgbaColor{ .r = 36, .g = 44, .b = 56 });
        self.canvas.draw_rect_outline(12, 44, CANVAS_WIDTH - 24, 248, RgbaColor.hud_border);
        self.canvas.draw_text(if (deck) |d| d.title else "NO DECK", 22, 52, 1, RgbaColor.gold);

        const proj = self.projection();

        // 2. Spatial Edges
        for (self.spatial.graph.edges.items) |e| {
            const wp_a = self.spatial.graph.get_waypoint(e.from);
            const wp_b = self.spatial.graph.get_waypoint(e.to);
            if (wp_a != null and wp_b != null and proj.shows(wp_a.?.room) and proj.shows(wp_b.?.room)) {
                const p1 = proj.point(wp_a.?.pos.x, wp_a.?.pos.y);
                const p2 = proj.point(wp_b.?.pos.x, wp_b.?.pos.y);
                self.canvas.draw_line(p1.x, p1.y, p2.x, p2.y, RgbaColor.slate);
            }
        }

        // 3. Hotspots
        for (self.spatial.hotspots.items) |hs| {
            if (!proj.shows(hs.room)) continue;
            const pt = proj.point(hs.pos.x, hs.pos.y);
            self.canvas.fill_rect(pt.x - 10, pt.y - 10, 20, 20, RgbaColor.amber);
            self.canvas.draw_rect_outline(pt.x - 10, pt.y - 10, 20, 20, RgbaColor.white);
            self.canvas.draw_text(hs.name, pt.x - 18, pt.y - 20, 1, RgbaColor.gold);
        }

        // 4. Waypoints
        for (self.spatial.graph.waypoints.items) |wp| {
            if (!proj.shows(wp.room)) continue;
            const pt = proj.point(wp.pos.x, wp.pos.y);
            self.canvas.fill_circle(pt.x, pt.y, 9, RgbaColor{ .r = 71, .g = 85, .b = 105 });
            self.canvas.draw_circle_outline(pt.x, pt.y, 9, RgbaColor.white);
            self.canvas.draw_text(wp.name, pt.x - 18, pt.y + 12, 1, RgbaColor.slate);
        }

        // 5. Actors
        var rank: i32 = 0;
        var it = self.spatial.agents.iterator();
        while (it.next()) |entry| {
            const agent = entry.value_ptr;
            if (self.agent_room(agent.entity)) |room| if (!proj.shows(room)) continue;
            const base = proj.point(agent.pos.x, agent.pos.y);
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

        // The distaff in decks with drafts (D-071): the notes played so far, the reach, and the
        // weave target.
        if (self.has_drafts()) {
            self.distaff.set_reach_from(self.active_world(), self.player_entity, "DistaffReach", 7);
            var line_buf: [96]u8 = undefined;
            var notes_buf: [8]u8 = "_ _ _ _ ".*;
            for (self.distaff.played[0..self.distaff.len], 0..) |n, i| notes_buf[i * 2] = "CDEFGAB"[@intFromEnum(n)];
            const target_name = if (self.distaff.target == .none) "nothing yet" else (self.world.get_entity_name(self.distaff.target) orelse "?");
            const line = std.fmt.bufPrint(&line_buf, "DISTAFF {s}| REACH {s} | ON {s}", .{ notes_buf[0..], "CDEFGAB"[0..self.distaff.reach], target_name }) catch "DISTAFF";
            self.canvas.draw_text(line, 22, 276, 1, RgbaColor.sky_blue);
        }

        // The inspector draws over the stage; the HUD, timeline, and verb bar stay visible.
        if (self.inspector.open) {
            self.inspector.capture(self.active_world());
            self.inspector.draw(&self.canvas, self.active_world());
        }

        // 6. Top Status & Timeline Scrubber Bar
        self.canvas.fill_rect(0, 0, CANVAS_WIDTH, 20, RgbaColor.hud_bg);
        var hdr_buf: [80]u8 = undefined;
        const hdr = std.fmt.bufPrint(&hdr_buf, "BeSpoke Wasm32 | Tick: {d:02} | Facts: {d} | {s}", .{
            self.clock(),
            self.active_world().fact_count(),
            if (self.is_paused) "PAUSED" else "RUNNING",
        }) catch "BeSpoke Wasm32";
        self.canvas.draw_text(hdr, 12, 6, 1, RgbaColor.emerald);

        // Timeline Scrubber (y = 22..38)
        self.canvas.fill_rect(12, 22, CANVAS_WIDTH - 24, 16, RgbaColor.hud_bg);
        self.canvas.draw_rect_outline(12, 22, CANVAS_WIDTH - 24, 16, RgbaColor.hud_border);
        if (self.max_history_tick > 0) {
            const fill_w: i32 = @intCast((self.clock() * 612) / self.max_history_tick);
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
        self.canvas.draw_text("[S]:Solve [I]:Inspect [Spc]:Pause [R]:Rewind", 310, 334, 1, RgbaColor.slate);
    }
};

// =============================================================================
// 3. Freestanding WebAssembly Global State & C-ABI Exports (P19-01, P19-02, P32-04)
// =============================================================================

/// Emits the `wasm_*` C-ABI exports for a build whose decks are `decks` (P32-04, D-042).
/// Call it from a `comptime` block in the wasm build's root file; the engine's own module
/// (`src/wasm_engine.zig`) and the proofs' (`proofs/wasm_main.zig`) differ only in their decks.
pub fn export_runtime(comptime decks: []const Deck) void {
    const Exports = struct {
        // A general-purpose allocator under a fixed ceiling (D-071): freed memory is reused, so a
        // tangent world dropped and re-forked across rewinds does not leak, and allocation still
        // fails at `WASM_HEAP_LIMIT` rather than growing without bound.
        var global_heap = CappedAllocator{ .child = std.heap.wasm_allocator, .limit = WASM_HEAP_LIMIT };
        // The runtime is about 1.2 MB. Held as `?WasmRuntime = null` it was an initialised
        // global, so the module carried 1.2 MB of zero bytes in its data section; `undefined`
        // plus a flag leaves it uninitialised memory that costs nothing to download (P30-02,
        // D-067).
        var global_runtime: WasmRuntime = undefined;
        var runtime_ready: bool = false;

        fn runtime() ?*WasmRuntime {
            return if (runtime_ready) &global_runtime else null;
        }

        fn wasm_init(scenario_id: u8) callconv(.C) void {
            if (runtime_ready) global_runtime.deinit();
            runtime_ready = false;
            global_runtime = WasmRuntime.init(global_heap.allocator(), decks, scenario_id) catch return;
            runtime_ready = true;
        }

        fn wasm_load_scenario(scenario_id: u8) callconv(.C) void {
            wasm_init(scenario_id);
        }

        fn wasm_step_tick() callconv(.C) void {
            if (runtime()) |rt| {
                if (!rt.is_paused) {
                    rt.step_tick() catch {};
                    rt.render_frame();
                }
            }
        }

        fn wasm_render_frame() callconv(.C) void {
            if (runtime()) |rt| {
                rt.render_frame();
            }
        }

        fn wasm_framebuffer_ptr() callconv(.C) [*]const u8 {
            // Before a runtime exists this is the uninitialised global's canvas: valid memory of
            // the right length, so the page can read it without a check.
            return &global_runtime.canvas.pixels;
        }

        fn wasm_framebuffer_len() callconv(.C) usize {
            return FRAMEBUFFER_BYTES;
        }

        fn wasm_on_pointer_down(x: i32, y: i32) callconv(.C) u8 {
            if (runtime()) |rt| {
                const tag = rt.dispatch_event(.{ .kind = .pointer_down, .x = x, .y = y }) catch .none;
                rt.render_frame();
                return @intFromEnum(tag);
            }
            return 0;
        }

        fn wasm_on_pointer_move(x: i32, y: i32) callconv(.C) u8 {
            if (runtime()) |rt| {
                const tag = rt.dispatch_event(.{ .kind = .pointer_move, .x = x, .y = y }) catch .none;
                return @intFromEnum(tag);
            }
            return 0;
        }

        fn wasm_on_right_click(x: i32, y: i32) callconv(.C) u8 {
            if (runtime()) |rt| {
                const tag = rt.dispatch_event(.{ .kind = .right_click, .x = x, .y = y }) catch .none;
                rt.render_frame();
                return @intFromEnum(tag);
            }
            return 0;
        }

        fn wasm_on_key_down(key_code: u8) callconv(.C) u8 {
            if (runtime()) |rt| {
                const tag = rt.dispatch_event(.{ .kind = .key_down, .key_code = key_code }) catch .none;
                rt.render_frame();
                return @intFromEnum(tag);
            }
            return 0;
        }

        fn wasm_on_touch(kind_id: u8, x: i32, y: i32, points: u8) callconv(.C) u8 {
            if (runtime()) |rt| {
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

        fn wasm_scrub_to_tick(target_tick: u32) callconv(.C) void {
            if (runtime()) |rt| {
                rt.scrub_to_tick(target_tick);
                rt.render_frame();
            }
        }

        fn wasm_get_tick() callconv(.C) u32 {
            if (runtime()) |rt| {
                return @intCast(rt.clock());
            }
            return 0;
        }

        /// 1 while a script deck's dialogue is open, so a page can send number keys to it
        /// instead of switching decks (D-069).
        fn wasm_dialogue_open() callconv(.C) u8 {
            if (runtime()) |rt| return @intFromBool(dialogue_mod.view(&rt.world) != null);
            return 0;
        }

        var audio_samples: [2 * AUDIO_MAX_FRAMES]i16 = undefined;

        /// Renders `frames` stereo frames (at most 4096) of the engine synthesizer at
        /// `wasm_audio_sample_rate` into a buffer and returns it; the page plays it through Web
        /// Audio (D-071). Silence before a runtime exists.
        fn wasm_audio_render(frames: u32) callconv(.C) [*]const i16 {
            const n: usize = @min(frames, AUDIO_MAX_FRAMES);
            if (runtime()) |rt| {
                rt.audio.render_samples(audio_samples[0 .. 2 * n]);
            } else {
                @memset(audio_samples[0 .. 2 * n], 0);
            }
            return &audio_samples;
        }

        fn wasm_audio_sample_rate() callconv(.C) u32 {
            return audio_mod.SAMPLE_RATE;
        }

        /// 1 while the state inspector is open (D-070); the clock is paused then.
        fn wasm_inspector_open() callconv(.C) u8 {
            if (runtime()) |rt| return @intFromBool(rt.inspector.open);
            return 0;
        }

        fn wasm_get_fact_count() callconv(.C) u32 {
            if (runtime()) |rt| {
                return @intCast(rt.world.fact_count());
            }
            return 0;
        }
    };
    @export(Exports.wasm_init, .{ .name = "wasm_init" });
    @export(Exports.wasm_dialogue_open, .{ .name = "wasm_dialogue_open" });
    @export(Exports.wasm_inspector_open, .{ .name = "wasm_inspector_open" });
    @export(Exports.wasm_audio_render, .{ .name = "wasm_audio_render" });
    @export(Exports.wasm_audio_sample_rate, .{ .name = "wasm_audio_sample_rate" });
    @export(Exports.wasm_load_scenario, .{ .name = "wasm_load_scenario" });
    @export(Exports.wasm_step_tick, .{ .name = "wasm_step_tick" });
    @export(Exports.wasm_render_frame, .{ .name = "wasm_render_frame" });
    @export(Exports.wasm_framebuffer_ptr, .{ .name = "wasm_framebuffer_ptr" });
    @export(Exports.wasm_framebuffer_len, .{ .name = "wasm_framebuffer_len" });
    @export(Exports.wasm_on_pointer_down, .{ .name = "wasm_on_pointer_down" });
    @export(Exports.wasm_on_pointer_move, .{ .name = "wasm_on_pointer_move" });
    @export(Exports.wasm_on_right_click, .{ .name = "wasm_on_right_click" });
    @export(Exports.wasm_on_key_down, .{ .name = "wasm_on_key_down" });
    @export(Exports.wasm_on_touch, .{ .name = "wasm_on_touch" });
    @export(Exports.wasm_scrub_to_tick, .{ .name = "wasm_scrub_to_tick" });
    @export(Exports.wasm_get_tick, .{ .name = "wasm_get_tick" });
    @export(Exports.wasm_get_fact_count, .{ .name = "wasm_get_fact_count" });
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

/// Two decks for these tests, unrelated to any proof.
const TestDecks = struct {
    fn load_yard(rt: *WasmRuntime) anyerror!void {
        const yard = try rt.world.intern_entity("Yard");
        const walker = try rt.world.intern_entity("Walker");
        const gate = try rt.spatial.graph.add_waypoint(yard, 0, 0, "Gate");
        const well = try rt.spatial.graph.add_waypoint(yard, 40, 0, "Well");
        try rt.spatial.graph.connect(gate, well, null);
        try rt.spatial.add_hotspot(try rt.world.intern_entity("Signpost"), yard, .{ .x = 20, .y = -8 }, 6, "Signpost", "Points both ways.");
        try rt.spatial.register_entity(walker, gate, 10);
        try rt.world.remember(walker, try rt.world.intern_relation("Rested", .set), 1, 0);
        rt.player_entity = walker;
        rt.set_banner("Yard deck");
    }
    fn ring_bell(rt: *WasmRuntime) anyerror!void {
        try rt.world.remember(rt.player_entity, try rt.world.intern_relation("RangBell", .set), 1, 0);
        rt.set_banner("Bell rung");
    }
    fn count_ticks(rt: *WasmRuntime) anyerror!void {
        const rel = try rt.world.intern_relation("TicksSeen", .property);
        const n = rt.world.get_property(rt.player_entity, rel) orelse 0;
        try rt.world.remember(rt.player_entity, rel, n + 1, 0);
    }
    fn load_empty(rt: *WasmRuntime) anyerror!void {
        rt.set_banner("Empty deck");
    }
    const decks = [_]Deck{
        .{ .title = "YARD", .background = .{ .r = 10, .g = 60, .b = 30 }, .load = load_yard, .catalyst = ring_bell, .after_tick = count_ticks },
        .{ .title = "EMPTY", .load = load_empty },
    };
};

test "P32-04: the runtime loads, ticks, and switches host decks and runs their rules" {
    const testing = std.testing;
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &TestDecks.decks, 0);
    defer rt.deinit();

    try testing.expectEqual(@as(u8, 0), rt.deck_index);
    try testing.expectEqualStrings("Yard deck", rt.get_banner());
    try testing.expectEqual(@as(u64, 0), rt.world.current_tick);
    try testing.expect(rt.world.fact_count() > 0);

    try rt.step_tick();
    try rt.step_tick();
    try testing.expectEqual(@as(u64, 2), rt.world.current_tick);
    try testing.expectEqual(@as(?u32, 2), rt.world.get_property(rt.player_entity, rt.world.lookup_relation("TicksSeen").?));

    try rt.trigger_catalyst();
    try testing.expect(rt.world.has_fact(rt.player_entity, rt.world.lookup_relation("RangBell").?, null));

    // The deck's background and title reach the canvas.
    rt.render_frame();
    const bg = rt.canvas.get_pixel(4, 300);
    try testing.expectEqual(@as(u8, 60), bg.g);

    // Key [2] switches deck; a deck without a catalyst says so; keys past the table do nothing.
    try testing.expectEqual(BrowserActionTag.scenario_switched, try rt.dispatch_event(.{ .kind = .key_down, .key_code = '2' }));
    try testing.expectEqual(@as(u8, 1), rt.deck_index);
    try testing.expectEqual(@as(usize, 0), rt.world.fact_count());
    try rt.trigger_catalyst();
    try testing.expectEqualStrings("This deck has no catalyst.", rt.get_banner());
    try testing.expectEqual(BrowserActionTag.none, try rt.dispatch_event(.{ .kind = .key_down, .key_code = '9' }));
    try rt.step_tick();

    // An index past the table starts on the first deck.
    try rt.load_deck(7);
    try testing.expectEqual(@as(u8, 0), rt.deck_index);
}

test "P19-02: Browser event bridge maps mouse, keyboard, and touch events to BeSpoke intents" {
    const testing = std.testing;
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &TestDecks.decks, 0);
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

    // 4. Click the Well waypoint at world (40, 0) -> canvas (520, 185) issues walk_to motor intent
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

test "D-066: a script deck compiles its script, speaks in the banner, and answers with number keys" {
    const testing = std.testing;
    const script =
        \\scene Quay:
        \\  cast: Hero, Pilot
        \\  marks: Steps, Pier
        \\
        \\relation Arrived(who)
        \\
        \\routine Walk(Hero):
        \\  walk Hero to Pier
        \\  remember Arrived(Hero)
        \\
        \\when Arrived(Hero):
        \\  say Pilot: "Mind the gap."
        \\
        \\on cue TalksTo(Hero, Pilot):
        \\  choice "Ask the way.":
        \\    say Pilot: "Over the water."
        \\  choice "Leave.":
        \\    say Pilot: "Goodbye."
    ;
    const decks = [_]Deck{script_deck("QUAY", script)};
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, 0);
    defer rt.deinit();

    // The first routine's actor is the player, and the Pilot stands in the scene with no routine.
    try testing.expectEqualStrings("Hero", rt.world.get_entity_name(rt.player_entity).?);
    try testing.expect(rt.spatial.agents.contains(rt.world.lookup_entity("Pilot").?));

    var heard = false;
    for (0..12) |_| {
        try rt.step_tick();
        if (std.mem.indexOf(u8, rt.get_banner(), "Mind the gap.") != null) heard = true;
    }
    try testing.expect(heard);

    const program = &rt.program.?;
    _ = (try rt.vm.fire_cue(program, "TalksTo", rt.player_entity, rt.world.lookup_entity("Pilot").?, null)).?;
    try rt.step_tick();
    try testing.expectEqualStrings("[1] Ask the way.  [2] Leave.", rt.get_banner());
    // An open dialogue takes the number keys from deck switching.
    try testing.expectEqual(BrowserActionTag.dialogue_answered, try rt.dispatch_event(.{ .kind = .key_down, .key_code = '1' }));
    try testing.expectEqualStrings("Pilot: \"Over the water.\"", rt.get_banner());
    try testing.expect(dialogue_mod.view(&rt.world) == null);

    // Reloading the deck releases the program and starts again.
    try rt.load_deck(0);
    try testing.expectEqual(@as(u64, 0), rt.world.current_tick);
}

test "D-070: the inspector pauses, navigates like the desktop's, and draws over the stage" {
    const testing = std.testing;
    const script =
        \\scene Quay:
        \\  cast: Hero, Pilot, Keeper
        \\  props: Lamp
        \\  marks: Steps, Pier
        \\
        \\relation Knows(who, whom)
        \\relation Owes(who, whom)
        \\relation Lit(lamp)
        \\
        \\remember Knows(Hero, Pilot)
        \\remember Owes(Hero, Keeper)
        \\remember Knows(Pilot, Keeper)
        \\remember Lit(Lamp) for 40 ticks
        \\
        \\routine Wait(Hero):
        \\  wait 1 ticks
    ;
    const decks = [_]Deck{script_deck("QUAY", script)};
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, 0);
    defer rt.deinit();

    // Opening pauses the clock, and closing restores the run state it found.
    try testing.expectEqual(BrowserActionTag.inspector_toggled, try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'I' }));
    try testing.expect(rt.inspector.open and rt.is_paused);
    const tick = rt.world.current_tick;
    // Clock and deck keys wait while it is open.
    try testing.expectEqual(BrowserActionTag.none, try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'N' }));
    try testing.expectEqual(tick, rt.world.current_tick);

    // The capture is the desktop's: the same function, the same facts.
    rt.render_frame();
    const display = @import("display.zig");
    var desktop: [display.MAX_DEBUG_FACTS]display.RenderDebugFact = undefined;
    try testing.expectEqual(display.capture_debug_facts(&rt.world, &desktop), rt.inspector.fact_count);

    // Hero has the most edges, so it is the default focus; Right then Enter recentres.
    const hero = rt.world.lookup_entity("Hero").?;
    const first = rt.inspector.layout().?;
    try testing.expectEqual(hero, first.center.entity);
    try testing.expectEqual(@as(usize, 2), first.ring_len);
    try testing.expectEqual(BrowserActionTag.inspector_navigated, try rt.dispatch_event(.{ .kind = .key_down, .key_code = InspectorKey.right }));
    try testing.expectEqual(@as(usize, 1), rt.inspector.selected);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = InspectorKey.enter });
    try testing.expectEqual(first.ring[1].entity, rt.inspector.focus.?);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = InspectorKey.backspace });
    try testing.expectEqual(hero, rt.inspector.focus.?);

    // A click on a ring node recentres on it, as on desktop.
    const ring0 = rt.inspector.layout().?.ring[0];
    try testing.expectEqual(BrowserActionTag.inspector_navigated, try rt.dispatch_event(.{ .kind = .pointer_down, .x = ring0.x, .y = ring0.y }));
    try testing.expectEqual(ring0.entity, rt.inspector.focus.?);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = InspectorKey.home });
    try testing.expect(rt.inspector.focus == null);

    // F cycles the filter: all, beliefs (Knows), then each relation.
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'F' });
    try testing.expectEqualStrings("BELIEFS", rt.inspector.filter.label());

    // The overlay replaces the stage: its panel colour fills the stage box.
    rt.render_frame();
    const px = rt.canvas.get_pixel(300, 100);
    try testing.expectEqual(@as(u8, 9), px.r);

    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'i' });
    try testing.expect(!rt.inspector.open and !rt.is_paused);
    try rt.step_tick();
    try testing.expect(rt.world.current_tick > tick);
}

test "D-071: the capped allocator refuses past its limit and counts frees back" {
    const testing = std.testing;
    var capped = CappedAllocator{ .child = testing.allocator, .limit = 1000 };
    const a = capped.allocator();
    const first = try a.alloc(u8, 600);
    try testing.expectError(error.OutOfMemory, a.alloc(u8, 600));
    a.free(first);
    try testing.expectEqual(@as(usize, 0), capped.used);
    const second = try a.alloc(u8, 900);
    defer a.free(second);
    try testing.expectEqual(@as(usize, 900), capped.used);
}
