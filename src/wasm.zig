//! BeSpoke Engine: WebAssembly (wasm32-freestanding) Runtime Harness & Browser Event Bridge (Phase 19, D-001, D-008, D-022)
//!
//! Compiles the pure Zig simulation spine (World, SpatialSystem, VM, Compiler, Repl)
//! to `wasm32-freestanding` with zero libc or external dependencies, drawing the desktop
//! window's frame (D-097) into a 1280x720 RGBA8888 linear-memory framebuffer for HTML5 Canvas
//! `ImageData` blitting and bridging DOM mouse, keyboard, and touch events to BeSpoke intents.
//! What is on the stage comes from the host's `Deck` table (P32-04, D-042).

const std = @import("std");
const dice_mod = @import("dice.zig");
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
const command_mod = @import("command.zig");
const draft_mod = @import("draft.zig");
const audio_mod = @import("audio.zig");
const hypervisor_mod = @import("hypervisor.zig");
pub const TemporalHypervisor = hypervisor_mod.TemporalHypervisor;
const display_mod = @import("display.zig");
/// Key codes the page sends for the state inspector's named keys: the DOM's own `keyCode`
/// values, since the runtime's key event carries one byte (D-070). Letters arrive as ASCII.
pub const InspectorKey = struct {
    pub const backspace: u8 = 8;
    pub const enter: u8 = 13;
    pub const home: u8 = 36;
    pub const left: u8 = 37;
    pub const right: u8 = 39;

    /// The desktop key a page key stands for, or null for a key the inspector does not read.
    pub fn desktop(code: u8) ?renderer.Keycode {
        return switch (code) {
            backspace => renderer.Keys.backspace,
            enter => renderer.Keys.enter,
            home => renderer.Keys.home,
            left => renderer.Keys.left,
            right => renderer.Keys.right,
            'f', 'F' => renderer.key('f'),
            else => null,
        };
    }
};
const CompiledProgram = compiler_mod.codegen.CompiledProgram;
const canvas_mod = @import("display/canvas.zig");
const dialogue_panel = @import("display/dialogue_panel.zig");
const phrase_mod = @import("phrase.zig");
const renderer = @import("display/renderer.zig");
const save_mod = @import("save.zig");
const beats_mod = @import("display/beats.zig");

pub const World = world_mod.World;
pub const EntityId = world_mod.EntityId;
pub const RelationKind = world_mod.RelationKind;
pub const SpatialSystem = spatial_mod.SpatialSystem;
pub const WaypointId = spatial_mod.WaypointId;
pub const VM = vm_mod.VM;
pub const Repl = repl_mod.Repl;

/// The browser draws the desktop window's frame at the desktop's size (D-097); the page scales
/// the canvas element to fit.
pub const CANVAS_WIDTH: i32 = 1280;
pub const CANVAS_HEIGHT: i32 = 720;
pub const FRAMEBUFFER_BYTES: usize = @intCast(CANVAS_WIDTH * CANVAS_HEIGHT * 4);
/// The footer the browser shows in place of a proof's desktop keys (D-097).
pub const BROWSER_FOOTER = "[Click]: Act | [Right-Click]: Verb | [S]: Solve | [I]: Inspect | [Space]: Pause | [N]: Step | [R]: Rewind";
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
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CappedAllocator = @ptrCast(@alignCast(ctx));
        if (len > self.limit - self.used) return null;
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.used += len;
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CappedAllocator = @ptrCast(@alignCast(ctx));
        if (new_len > buf.len and new_len - buf.len > self.limit - self.used) return false;
        if (!self.child.rawResize(buf, alignment, new_len, ret_addr)) return false;
        self.used = self.used - buf.len + new_len;
        return true;
    }

    /// Like `resize`, but the child may move the memory; the ceiling counts it the same way.
    fn remap(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CappedAllocator = @ptrCast(@alignCast(ctx));
        if (new_len > buf.len and new_len - buf.len > self.limit - self.used) return null;
        const ptr = self.child.rawRemap(buf, alignment, new_len, ret_addr) orelse return null;
        self.used = self.used - buf.len + new_len;
        return ptr;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CappedAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(buf, alignment, ret_addr);
        self.used -= buf.len;
    }
};

/// The most stereo frames one `wasm_audio_render` call fills (D-071).
pub const AUDIO_MAX_FRAMES: usize = 4096;
pub const SNAPSHOT_SLOT_BYTES: usize = 8192;

/// The shared canvas colour (P36-02); the browser's former names live on it.
pub const RgbaColor = canvas_mod.Color;
pub const Canvas = canvas_mod.Canvas;

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
    /// Runs first when a verb is used on a person or prop; returning true means the deck
    /// handled it and no cue fires (D-086). A deck uses it for host-run mechanics, such as a
    /// duel started by talking to a fencer.
    on_act: ?*const fn (rt: *WasmRuntime, verb: WasmVerb, target: EntityId) anyerror!bool = null,
    /// The cues the verbs fire; a script that answers `Talk` or `PicksUp` names them (D-071).
    cues: VerbCues = .{},
    /// Marks that lead to another scene: arriving on one moves the player there (D-094).
    exits: []const Exit = &.{},
    /// A page's own button for a deck's one-off action, such as spitting (D-095); `id` is the
    /// page's number for it. Runs between ticks, like `[S]`.
    on_action: ?*const fn (rt: *WasmRuntime, id: u8) anyerror!void = null,
    /// The proof's desktop theme (D-097): its scenery, props, people, and HUD, drawn on the
    /// browser frame as on the desktop. Null draws the engine's neutral stage.
    theme: ?*const renderer.Theme = null,
    /// The proof's status capture, which the theme reads from each frame (D-041).
    status_hook: ?display_mod.StatusHook = null,
    /// The desktop's typed-command bar (P26-03, P34-04): Enter focuses it, forwarded
    /// characters fill it, and a submitted line goes to `on_typed`.
    command_bar: bool = false,
    on_typed: ?*const fn (rt: *WasmRuntime, line: []const u8) anyerror!void = null,
};

/// A doorway between scenes, shared with desktop hosts (D-094, D-100).
pub const Exit = host_mod.Exit;

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
    on_act: ?*const fn (rt: *WasmRuntime, verb: WasmVerb, target: EntityId) anyerror!bool = null,
    cues: VerbCues = .{},
    exits: []const Exit = &.{},
    on_action: ?*const fn (rt: *WasmRuntime, id: u8) anyerror!void = null,
    theme: ?*const renderer.Theme = null,
    status_hook: ?display_mod.StatusHook = null,
    command_bar: bool = false,
    on_typed: ?*const fn (rt: *WasmRuntime, line: []const u8) anyerror!void = null,
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
            try host_mod.add_exit_marks(&rt.world, &rt.spatial, options.exits);
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
        .on_act = options.on_act,
        .cues = options.cues,
        .exits = options.exits,
        .on_action = options.on_action,
        .theme = options.theme,
        .status_hook = options.status_hook,
        .command_bar = options.command_bar,
        .on_typed = options.on_typed,
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
    /// A typed character, for the command bar (P34-04); `key_code` holds it.
    char = 7,
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
/// A verb on a person or prop, held while the player walks to `wp` beside it (D-092).
pub const Approach = struct {
    verb: WasmVerb,
    target: EntityId,
    examine: ?[]const u8,
    wp: u16,
    asked_tick: u64,
    seen_moving: bool = false,
    /// The item in hand when the verb was given, used on the target on arrival (D-094).
    item: EntityId = .none,
};

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
    /// A click, Enter, or Space dismissed a click-through message (D-080).
    message_dismissed,
    /// A click on the item tray took an item in hand, or put it away (D-094).
    item_selected,
    /// Enter focused the command bar, or a key or character edited it (P34-04).
    command_edited,
    /// The command bar submitted a line to the deck (P34-04).
    command_typed,
};

// =============================================================================
// 1. Pure Zig RGBA8888 Canvas Framebuffer Renderer (P19-01, D-001, D-022)
// =============================================================================

pub const CanvasPoint = struct { x: i32, y: i32 };

/// Where the stage is drawn (D-097): the desktop window's mapping (`renderer.world_to_screen`)
/// and only the current scene, as the desktop frame captures it.
pub const Projection = struct {
    room: ?EntityId = null,

    pub fn point(_: Projection, x: i32, y: i32) CanvasPoint {
        const p = renderer.world_to_screen(x, y, CANVAS_WIDTH, CANVAS_HEIGHT);
        return .{ .x = p.x, .y = p.y };
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
    /// A verb held while the player walks to its target (D-092); released by `step_tick`.
    approach: ?Approach = null,
    /// The item in hand from the tray (D-094): the next USE click uses it on what is clicked.
    /// Peripheral input like the active verb, so it is never saved or rewound; it drops when
    /// the player no longer carries the item.
    selected_item: EntityId = .none,
    /// The compiled script of a script deck; null for decks built in Zig (D-066).
    program: ?CompiledProgram = null,
    /// The state inspector overlay (D-070). Its navigation is not World state.
    /// The state inspector overlay is open (D-070). Its focus, selection, history, and filter
    /// live on the window, as the desktop State tab's do (D-059, D-097): never World state.
    inspector_open: bool = false,
    /// The run state to restore when the inspector closes.
    inspector_was_paused: bool = false,
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

    /// Long enough for a spoken line with its speaker; drawn wrapped over two rows (D-077).
    banner_buf: [512]u8 = @as([512]u8, @splat(0)),
    banner_len: usize = 0,
    /// The open dialogue's speaker as a display name; the panel's rows slice into it.
    panel_name_buf: [48]u8 = undefined,
    /// Click-through messages (D-080). While any waits, it covers the dialogue panel and the
    /// number keys cannot answer the choices beneath it.
    messages: beats_mod.Beats = .{},
    max_history_tick: u64 = 0,

    // Fixed ring buffer of binary World snapshots for instant browser timeline scrubbing
    snapshot_bufs: [MAX_WASM_SNAPSHOTS][SNAPSHOT_SLOT_BYTES]u8 = undefined,
    snapshot_lens: [MAX_WASM_SNAPSHOTS]usize = @as([MAX_WASM_SNAPSHOTS]usize, @splat(0)),
    snapshot_ticks: [MAX_WASM_SNAPSHOTS]u64 = @as([MAX_WASM_SNAPSHOTS]u64, @splat(0)),
    snapshot_count: usize = 0,

    /// The frame the page shows: 1280x720 RGBA8888 (D-097). Borrowed from the host in the
    /// browser build; allocated by `init` otherwise.
    framebuffer: []u8 = &.{},
    owns_framebuffer: bool = false,
    /// The desktop frame capture, the window that draws it, and the window's (empty) save
    /// list. Heap-allocated, because the runtime is moved after `init`; the window's pointers
    /// into the runtime are re-pointed before each use (`screen`).
    frame_bridge: *display_mod.DisplayBridge = undefined,
    /// Typed-command state for decks whose bar has no handler of their own (P34-04).
    command_interp: command_mod.Interpreter = .{},
    window: *renderer.DisplayWindow = undefined,
    saves: *save_mod.SaveManager = undefined,
    /// The run's seed (D-184): 42 unless the page passes one to `wasm_init`. Every deck the
    /// runtime loads starts its dice from it.
    seed: u64 = dice_mod.DEFAULT_SEED,

    /// Starts on deck `initial` of `decks`; an index past the end starts on the first deck.
    pub fn init(allocator: std.mem.Allocator, decks: []const Deck, initial: u8) !WasmRuntime {
        const pixels = try allocator.alloc(u8, FRAMEBUFFER_BYTES);
        errdefer allocator.free(pixels);
        var rt = try init_with_framebuffer(allocator, decks, initial, pixels);
        rt.owns_framebuffer = true;
        return rt;
    }

    /// As `init`, drawing into `pixels` (at least `FRAMEBUFFER_BYTES`), which the caller keeps.
    pub fn init_with_framebuffer(allocator: std.mem.Allocator, decks: []const Deck, initial: u8, pixels: []u8) !WasmRuntime {
        return init_seeded(allocator, decks, initial, pixels, dice_mod.DEFAULT_SEED);
    }

    /// As `init_with_framebuffer`, rolling from `seed` (D-184).
    pub fn init_seeded(allocator: std.mem.Allocator, decks: []const Deck, initial: u8, pixels: []u8, seed: u64) !WasmRuntime {
        const bridge = try allocator.create(display_mod.DisplayBridge);
        errdefer allocator.destroy(bridge);
        bridge.* = display_mod.DisplayBridge.init();
        const saves = try allocator.create(save_mod.SaveManager);
        errdefer allocator.destroy(saves);
        // A save list with no directory: the browser never opens the save drawer. Its `Io` is
        // `std.Io.failing`, so a file operation that reached it would fail rather than act.
        saves.* = .{ .allocator = allocator, .io = std.Io.failing, .save_dir = "", .slots = undefined, .session_start_ms = 0, .accumulated_playtime_secs = 0 };
        for (0..save_mod.MAX_SLOTS + 1) |i| saves.slots[i] = .{ .slot_id = @intCast(i) };
        const window = try allocator.create(renderer.DisplayWindow);
        errdefer allocator.destroy(window);
        var rt = WasmRuntime{
            .allocator = allocator,
            .world = try World.init(allocator, 256 * 1024),
            .spatial = SpatialSystem.init(allocator),
            .chunk = bytecode_mod.BytecodeChunk.init(allocator),
            .vm = undefined,
            .decks = decks,
            .framebuffer = pixels[0..FRAMEBUFFER_BYTES],
            .frame_bridge = bridge,
            .saves = saves,
            .window = window,
            .seed = seed,
        };
        window.* = renderer.DisplayWindow.init_canvas(rt.framebuffer, CANVAS_WIDTH, CANVAS_HEIGHT, &rt.audio, saves);
        rt.vm = VM.init(allocator, &rt.world, &rt.chunk);
        rt.vm.spatial = &rt.spatial;
        try rt.load_deck(initial);
        return rt;
    }

    pub fn deinit(self: *WasmRuntime) void {
        self.allocator.destroy(self.window);
        self.allocator.destroy(self.saves);
        self.allocator.destroy(self.frame_bridge);
        if (self.owns_framebuffer) self.allocator.free(self.framebuffer);
        // Declarations borrow World text, so the program goes before the World.
        self.drop_program();
        self.vm.deinit();
        self.chunk.deinit();
        self.spatial.deinit();
        self.world.deinit();
    }

    /// Shows a line: the newest in the window's message log under the stage (D-099), and the
    /// runtime's own copy, which tests and the golden read.
    pub fn set_banner(self: *WasmRuntime, msg: []const u8) void {
        const len = @min(msg.len, self.banner_buf.len);
        @memcpy(self.banner_buf[0..len], msg[0..len]);
        self.banner_len = len;
        self.window.set_cue_banner(msg[0..len], 0);
    }

    pub fn get_banner(self: *const WasmRuntime) []const u8 {
        return self.banner_buf[0..self.banner_len];
    }

    /// Supported callback access to the runtime's spatial state (P38-03, D-107). Deck callbacks
    /// use methods instead of depending on `WasmRuntime` field layout.
    pub fn spatial_system(self: *WasmRuntime) *SpatialSystem {
        return &self.spatial;
    }

    /// Supported callback access to the runtime's VM (P38-03, D-107).
    pub fn virtual_machine(self: *WasmRuntime) *VM {
        return &self.vm;
    }

    /// The loaded script program, or null for a deck built directly in Zig.
    pub fn compiled_program(self: *const WasmRuntime) ?*const CompiledProgram {
        return if (self.program) |*program| program else null;
    }

    /// The actor browser actions control. A callback may replace it after loading a script.
    pub fn player(self: *const WasmRuntime) ?EntityId {
        return if (self.player_entity == .none) null else self.player_entity;
    }

    pub fn set_player(self: *WasmRuntime, entity: EntityId) void {
        self.player_entity = entity;
    }

    /// Resets the spine and loads deck `index` (the first deck if out of range).
    pub fn load_deck(self: *WasmRuntime, index: u8) !void {
        self.messages.clear();
        self.window.clear_log();
        self.banner_len = 0;
        self.approach = null;
        self.selected_item = .none;
        // The names belong to the program about to be dropped too (D-179).
        dialogue_panel.clear_display_names();
        // The art is borrowed from the program about to be dropped.
        self.window.set_art(null);
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
        self.vm.set_seed(self.seed);

        self.deck_index = if (index < self.decks.len) index else 0;
        self.window.enable_command_bar(self.decks.len > 0 and self.decks[self.deck_index].command_bar);
        self.window.command_len = 0;
        self.command_interp = .{};
        self.inspector_open = false;
        self.window.inspector_focus = null;
        self.window.inspector_history_len = 0;
        self.window.inspector_selected = 0;
        self.window.inspector_filter = .{};
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
    /// do (`host.start_script`). Called from a deck's `load`. A deck's program is embedded, so
    /// the choice between source and package is made at compile time: a module whose decks
    /// all carry source, such as `bespoke-proofs.wasm`, never links the package loader, which
    /// was about 176 KB of that module (D-147, D-141). A `-Dbundle` deck embeds a package and
    /// keeps the loader.
    pub fn load_program(self: *WasmRuntime, comptime data: []const u8) !void {
        const is_package = comptime data.len >= 4 and std.mem.eql(u8, data[0..4], &package_mod.PACKAGE_MAGIC);
        if (is_package) {
            var stream: std.Io.Reader = .fixed(data);
            self.program = try package_mod.load_package(self.allocator, &stream, &self.world, &self.spatial);
        } else {
            self.program = try compiler_mod.compile_source(self.allocator, &self.world, &self.spatial, data);
        }
        const program = &self.program.?;
        // The script's art draws on the browser frame as on the desktop (P46-03, D-097).
        self.window.set_art(&program.art);
        // Browser saves name this build too (P48-08, D-162).
        self.saves.program = program.identity();
        // Names on screen read the script's `name` lines (P48-09, D-179).
        dialogue_panel.use_display_names(&self.world);
        self.vm.deinit();
        self.vm = VM.init(self.allocator, &self.world, &program.chunk);
        self.vm.spatial = &self.spatial;
        self.vm.set_seed(self.seed);
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

    /// The room on stage (D-069): the VM's current scene, as the desktop frame captures it.
    /// Without a scene every room shows, as on the desktop.
    pub fn projection(self: *const WasmRuntime) Projection {
        return .{ .room = self.vm.current_scene };
    }

    /// The room an agent stands in: the room of the mark it last reached.
    fn agent_room(self: *const WasmRuntime, entity: EntityId) ?EntityId {
        const wp = self.spatial.get_current_waypoint(entity) orelse return null;
        return (self.spatial.graph.get_waypoint(wp) orelse return null).room;
    }

    /// Where a person on stage is drawn: the desktop's place for it (D-097), which fans out
    /// people who share a spot as the browser's own layout did (D-088).
    pub const ActorSlot = struct { entity: EntityId, x: i32, y: i32 };
    pub const MAX_ACTOR_SLOTS: usize = 64;

    /// Every person in the desktop frame, where the desktop draws them.
    pub fn actor_slots(self: *WasmRuntime, proj: Projection, out: *[MAX_ACTOR_SLOTS]ActorSlot) usize {
        _ = proj;
        const frame = self.capture();
        const people = frame.entities[0..frame.entity_count];
        for (people, 0..) |e, i| {
            const pt = renderer.get_entity_screen_pos(i, people, CANVAS_WIDTH, CANVAS_HEIGHT);
            out[i] = .{ .entity = e.entity, .x = pt.x, .y = pt.y };
        }
        return people.len;
    }

    /// The person drawn under a canvas point, by the desktop's hit test.
    pub fn actor_at(self: *WasmRuntime, proj: Projection, x: i32, y: i32) ?ActorSlot {
        _ = proj;
        const frame = self.capture();
        const people = frame.entities[0..frame.entity_count];
        const i = renderer.hit_test_actor(x, y, people, CANVAS_WIDTH, CANVAS_HEIGHT, self.window.art) orelse return null;
        const pt = renderer.get_entity_screen_pos(i, people, CANVAS_WIDTH, CANVAS_HEIGHT);
        return .{ .entity = people[i].entity, .x = pt.x, .y = pt.y };
    }

    /// A verb on a person or prop in a script deck fires the script's cue for the player and
    /// runs the tick that answers it (D-069). Without a handler the banner says so; LOOK at a
    /// prop then falls back to its examine text.
    fn act_on(self: *WasmRuntime, target: EntityId, examine: ?[]const u8) anyerror!?BrowserActionTag {
        if (self.program == null) return null;
        // An item in hand goes with a USE click, and leaves the hand once given (D-094).
        const item: EntityId = if (self.active_verb == .use_with) self.selected_item else .none;
        self.selected_item = .none;
        // Walk to the person or prop first (D-092); LOOK acts from where the player stands.
        if (self.active_verb != .look_at and self.player_entity != .none and target != self.player_entity) {
            if (self.reach_mark(target)) |wp| {
                const at = self.spatial.agents.get(self.player_entity);
                const there = if (at) |a| a.current_wp == wp and !self.spatial.is_moving(self.player_entity) else true;
                if (!there and try self.plan_walk(wp)) {
                    self.approach = .{ .verb = self.active_verb, .target = target, .examine = examine, .wp = wp, .asked_tick = self.clock(), .item = item };
                    var name_buf: [48]u8 = undefined;
                    const name = dialogue_panel.entity_name(&self.world, target, &name_buf) orelse phrase_mod.text(&self.world, .thing_fallback);
                    var buf: [80]u8 = undefined;
                    self.set_banner(phrase_mod.render(&self.world, .walking_to, &.{.{ .slot = "mark", .value = name }}, &buf) catch "Walking...");
                    return .walk_issued;
                }
            }
        }
        return self.act_now(target, examine, item, true);
    }

    /// Plans the player's walk around marks the world blocks (`WaypointBlocked`, blocking grid
    /// cells), as the desktop hosts that lock routes do (P24-02, D-054); with no such facts it is
    /// a plain walk. Plans in the active world, the branch while one is live.
    fn plan_walk(self: *WasmRuntime, wp: u16) !bool {
        return self.spatial.walk_to_with_world(self.active_world(), self.player_entity, wp);
    }

    /// A typed line for a deck with no handler of its own: the script's commands, read for the
    /// player as the stock hosts read them (D-057), the reply on the banner, and the tick that
    /// answers a fired cue.
    fn default_typed(self: *WasmRuntime, line: []const u8) !void {
        const program = if (self.program) |*p| p else return;
        if (self.player_entity == .none) return;
        var buf: [160]u8 = undefined;
        switch (host_mod.interpret_command(&self.vm, program, &self.command_interp, self.player_entity, line, &buf)) {
            .reply => |text| if (text) |t| self.set_banner(t),
            .command => |command| {
                const reply = try host_mod.dispatch_command(&self.vm, program, self.player_entity, command);
                if (reply.text) |text| self.set_banner(text);
                if (reply.fired) try self.step_tick();
            },
        }
    }

    fn command_bar_on(self: *const WasmRuntime) bool {
        return self.decks.len > 0 and self.decks[self.deck_index].command_bar;
    }

    fn choices_open(self: *WasmRuntime) bool {
        return self.choice_count() > 0;
    }

    /// How many choices the open dialogue offers; zero when none is open.
    fn choice_count(self: *WasmRuntime) usize {
        const view = dialogue_mod.view(self.active_world()) orelse return 0;
        return view.count;
    }

    /// A key while the command bar is focused, with the page's key code turned into the window's
    /// (the DOM numbers arrows 38 and 40). A submitted line goes to the deck's `on_typed`.
    fn command_key(self: *WasmRuntime, code: u8) !BrowserActionTag {
        const sym: renderer.Keycode = switch (code) {
            13 => renderer.Keys.enter,
            8 => renderer.Keys.backspace,
            27 => renderer.Keys.escape,
            9 => renderer.Keys.tab,
            38 => renderer.Keys.up,
            40 => renderer.Keys.down,
            else => return .command_edited,
        };
        switch (self.window.command_bar_key(sym)) {
            .typed_command => |t| {
                self.bind();
                if (self.decks[self.deck_index].on_typed) |hook| {
                    try hook(self, t.buf[0..t.len]);
                } else try self.default_typed(t.buf[0..t.len]);
                self.record_snapshot();
                return .command_typed;
            },
            else => return .command_edited,
        }
    }

    /// The mark beside a target: where a person stands, else the mark nearest a prop in its room.
    fn reach_mark(self: *const WasmRuntime, target: EntityId) ?u16 {
        if (self.spatial.agents.get(target)) |agent| return agent.current_wp;
        for (self.spatial.hotspots.items) |hs| {
            if (hs.entity != target) continue;
            // A prop with an area is reached from its area's foot, measured on screen as the
            // desktop does (D-158).
            if (self.window.art) |a| if (a.area_for(target)) |area| {
                const r = renderer.area_rect(area);
                const foot_x = r.x + @divTrunc(r.w, 2);
                const foot_y = r.y + r.h;
                var near: ?u16 = null;
                var near_d: i64 = std.math.maxInt(i64);
                for (self.spatial.graph.waypoints.items) |wp| {
                    if (wp.room != hs.room) continue;
                    const pt = renderer.world_to_screen(wp.pos.x, wp.pos.y, CANVAS_WIDTH, CANVAS_HEIGHT);
                    const dx: i64 = pt.x - foot_x;
                    const dy: i64 = pt.y - foot_y;
                    if (dx * dx + dy * dy < near_d) {
                        near_d = dx * dx + dy * dy;
                        near = wp.id;
                    }
                }
                return near;
            };
            var best: ?u16 = null;
            var best_d: i64 = std.math.maxInt(i64);
            for (self.spatial.graph.waypoints.items) |wp| {
                if (wp.room != hs.room) continue;
                const dx: i64 = wp.pos.x - hs.pos.x;
                const dy: i64 = wp.pos.y - hs.pos.y;
                if (dx * dx + dy * dy < best_d) {
                    best_d = dx * dx + dy * dy;
                    best = wp.id;
                }
            }
            return best;
        }
        return null;
    }

    /// Runs a held action once the player has arrived (D-092): called at the start of a tick,
    /// so the tick answers the cue. A walk that stopped elsewhere drops it; a player that never
    /// started walking acts where it stands after a grace of two ticks.
    fn release_approach(self: *WasmRuntime) anyerror!void {
        const a = &(self.approach orelse return);
        const moving = self.spatial.is_moving(self.player_entity);
        if (moving) {
            a.seen_moving = true;
            return;
        }
        const wp = if (self.spatial.agents.get(self.player_entity)) |agent| agent.current_wp else a.wp;
        if (wp == a.wp or (!a.seen_moving and self.clock() >= a.asked_tick + 2)) {
            const held = a.*;
            self.approach = null;
            const verb = self.active_verb;
            self.active_verb = held.verb;
            defer self.active_verb = verb;
            _ = try self.act_now(held.target, held.examine, held.item, false);
        } else if (a.seen_moving) {
            self.approach = null;
            self.set_banner("You can't get there from here.");
        }
    }

    /// Acts on a target now. `run_tick` runs the tick that answers the cue; a held action
    /// released inside a tick leaves that to the tick already running.
    fn act_now(self: *WasmRuntime, target: EntityId, examine: ?[]const u8, item: EntityId, run_tick: bool) anyerror!?BrowserActionTag {
        const program = if (self.program) |*p| p else return null;
        if (item != .none) {
            // An item used on a person or prop: `Uses(player, item, target)` (D-094).
            const cues: VerbCues = if (self.decks.len > 0) self.decks[self.deck_index].cues else .{};
            if (self.player_entity == .none) return null;
            self.bind();
            if ((try self.vm.fire_cue(program, cues.use, self.player_entity, item, target)) != null) {
                self.narrate(.use_with, item, target);
                self.audio.enqueue_sfx(.click);
                if (run_tick) try self.step_tick();
                return .cue_fired;
            }
            self.set_banner(phrase_mod.text(&self.world, .nothing_happens));
            return .cue_fired;
        }
        if (self.decks.len > 0) if (self.decks[self.deck_index].on_act) |hook| {
            self.bind();
            if (try hook(self, self.active_verb, target)) {
                self.record_snapshot();
                return .actor_interacted;
            }
        };
        const cues: VerbCues = if (self.decks.len > 0) self.decks[self.deck_index].cues else .{};
        const cue = cues.of(self.active_verb) orelse return null;
        // In a deck with drafts, whatever the player acts on becomes the weave target (D-071).
        self.distaff.target = target;
        if (self.player_entity == .none) return null;
        self.bind();
        if ((try self.vm.fire_cue(program, cue, self.player_entity, target, null)) != null) {
            self.narrate(self.active_verb, .none, target);
            self.audio.enqueue_sfx(.click);
            if (run_tick) try self.step_tick();
            return .cue_fired;
        }
        if (self.active_verb == .look_at) {
            if (examine) |text| {
                // A prop with no description of its own reads as its name, in words.
                var ex_buf: [48]u8 = undefined;
                const name = self.world.get_entity_name(target) orelse "";
                self.set_banner(if (std.mem.eql(u8, text, name)) dialogue_panel.display_name(name, &ex_buf) else text);
                return .hotspot_inspected;
            }
        }
        self.set_banner(phrase_mod.text(&self.world, .nothing_happens));
        return .cue_fired;
    }

    /// The item tray (D-094): one box per item the player carries (`Carries` or `InInventory`,
    /// D-007), laid out and drawn by the desktop window (D-097).
    pub const MAX_TRAY: usize = 8;
    pub const TraySlot = struct { item: EntityId, x: i32, y: i32, w: i32, h: i32, label_buf: [32]u8 = undefined, label_len: usize = 0 };

    /// What the player carries, at most eight, in the order the items were first named, so
    /// the tray keeps its order when facts are forgotten and the arena reorders.
    pub fn carried(self: *WasmRuntime, out: *[MAX_TRAY]EntityId) usize {
        if (self.player_entity == .none) return 0;
        const world = self.active_world();
        var n: usize = 0;
        for ([_][]const u8{ "InInventory", "Carries" }) |rel_name| {
            const rel = world.lookup_relation(rel_name) orelse continue;
            var it = world.query(self.player_entity, rel, null);
            while (it.next()) |f| {
                if (n >= MAX_TRAY) break;
                out[n] = EntityId.from_int(f.object_or_value);
                n += 1;
            }
        }
        std.mem.sort(EntityId, out[0..n], {}, struct {
            fn less(_: void, a: EntityId, b: EntityId) bool {
                return a.to_int() < b.to_int();
            }
        }.less);
        return n;
    }

    /// The tray's boxes where the desktop draws them (`renderer.inventory_layout`).
    pub fn tray_slots(self: *WasmRuntime, out: *[MAX_TRAY]TraySlot) []TraySlot {
        const frame = self.capture();
        var boxes: [MAX_TRAY]renderer.InventorySlot = undefined;
        const laid = renderer.inventory_layout(CANVAS_WIDTH, frame.inventory[0..frame.inventory_count], &boxes);
        for (laid, 0..) |box, i| {
            out[i] = .{ .item = frame.inventory[i].entity, .x = box.x, .y = renderer.bar_band_top(CANVAS_HEIGHT), .w = box.w, .h = renderer.BAR_BAND_H };
            const len = @min(box.label.len, out[i].label_buf.len);
            @memcpy(out[i].label_buf[0..len], box.label[0..len]);
            out[i].label_len = len;
        }
        return out[0..laid.len];
    }

    fn tray_hit(self: *WasmRuntime, x: i32, y: i32) ?EntityId {
        const frame = self.capture();
        const i = renderer.hit_test_inventory_item(x, y, CANVAS_WIDTH, CANVAS_HEIGHT, frame.inventory[0..frame.inventory_count]) orelse return null;
        return frame.inventory[i].entity;
    }

    /// Says what the player just did, such as "Hero uses Rope on Mooring Post.", before the
    /// cue's tick runs; a line the script says that tick replaces it. Without it, a handler that
    /// only changes state or animates gives no sign the click did anything (D-094).
    fn narrate(self: *WasmRuntime, verb: WasmVerb, item: EntityId, target: EntityId) void {
        var names: [3][48]u8 = undefined;
        const w = &self.world;
        const who = dialogue_panel.entity_name(w, self.player_entity, &names[0]) orelse phrase_mod.text(w, .player_fallback);
        const what = if (item != .none) dialogue_panel.entity_name(w, item, &names[1]) orelse phrase_mod.text(w, .thing_fallback) else "";
        const on = if (target != .none) dialogue_panel.entity_name(w, target, &names[2]) orelse phrase_mod.text(w, .thing_fallback) else "";
        // One whole sentence per verb, so a translation controls its word order (D-179).
        const key: phrase_mod.Key = switch (verb) {
            .walk => .narrate_walk,
            .look_at => .narrate_look,
            .talk_to => .narrate_talk,
            .pick_up => .narrate_take,
            .use_with => .narrate_use,
        };
        var buf: [160]u8 = undefined;
        const line = if (item != .none and target != .none)
            phrase_mod.render(w, .narrate_use_on, &.{ .{ .slot = "actor", .value = who }, .{ .slot = "thing", .value = what }, .{ .slot = "target", .value = on } }, &buf)
        else
            phrase_mod.render(w, key, &.{ .{ .slot = "actor", .value = who }, .{ .slot = "target", .value = if (item != .none) what else on } }, &buf);
        self.set_banner(line catch return);
    }

    /// A click on a carried item (D-094). LOOK fires the look cue on it, or reads its name.
    /// Any other verb uses it: an item the script answers on its own (`Uses(player, item)`)
    /// is used at once; any other is taken in hand for the next click. With an item already in
    /// hand, a second item is combined with it (`Uses(player, held, clicked)`, then the other
    /// order, since a script names the pair one way round), and the same item is put away.
    fn click_item(self: *WasmRuntime, item: EntityId) anyerror!BrowserActionTag {
        const program = if (self.program) |*p| p else return .none;
        const cues: VerbCues = if (self.decks.len > 0) self.decks[self.deck_index].cues else .{};
        var name_buf: [48]u8 = undefined;
        const name = dialogue_panel.entity_name(&self.world, item, &name_buf) orelse phrase_mod.text(&self.world, .thing_fallback);
        var buf: [96]u8 = undefined;
        self.bind();
        if (self.active_verb == .look_at) {
            if ((try self.vm.fire_cue(program, cues.look, self.player_entity, item, null)) != null) {
                self.narrate(.look_at, .none, item);
                try self.step_tick();
                return .cue_fired;
            }
            self.set_banner(std.fmt.bufPrint(&buf, "It's the {s}.", .{name}) catch name);
            return .hotspot_inspected;
        }
        const held = self.selected_item;
        if (held == item) {
            self.selected_item = .none;
            self.set_banner(std.fmt.bufPrint(&buf, "Put the {s} away.", .{name}) catch "Put away.");
            return .item_selected;
        }
        if (held != .none) {
            self.selected_item = .none;
            const fired = (try self.vm.fire_cue(program, cues.use, self.player_entity, held, item)) != null or
                (try self.vm.fire_cue(program, cues.use, self.player_entity, item, held)) != null;
            if (fired) {
                self.narrate(.use_with, held, item);
                self.audio.enqueue_sfx(.click);
                try self.step_tick();
            } else self.set_banner("Those don't go together.");
            return .cue_fired;
        }
        if ((try self.vm.fire_cue(program, cues.use, self.player_entity, item, null)) != null) {
            self.narrate(.use_with, item, .none);
            self.audio.enqueue_sfx(.click);
            try self.step_tick();
            return .cue_fired;
        }
        self.selected_item = item;
        self.active_verb = .use_with;
        self.set_banner(std.fmt.bufPrint(&buf, "Use the {s} on what? Right-click to put it away.", .{name}) catch "Use it on what?");
        return .item_selected;
    }

    /// Moves the player through an exit whose mark its walk ended on this tick (D-094).
    /// `walking_before` is whether the player was walking when the tick began. A walk to act
    /// on something (D-092) never exits, though the mark beside a prop may be an exit mark:
    /// the player went there for the prop, not to leave.
    fn take_exit(self: *WasmRuntime, walking_before: bool) !void {
        if (self.player_entity == .none or self.decks.len == 0) return;
        if (!walking_before or self.approach != null or self.spatial.is_moving(self.player_entity)) return;
        _ = try self.exit_here();
    }

    /// Takes the exit on the mark the player stands on, if there is one; true if it did.
    fn exit_here(self: *WasmRuntime) !bool {
        if (self.player_entity == .none or self.decks.len == 0) return false;
        const exit = (try host_mod.take_exit_here(&self.world, &self.spatial, &self.vm, self.decks[self.deck_index].exits, self.player_entity)) orelse return false;
        self.approach = null;
        var name_buf: [48]u8 = undefined;
        var buf: [80]u8 = undefined;
        self.set_banner(phrase_mod.render(&self.world, .arrive_scene, &.{.{ .slot = "scene", .value = dialogue_panel.named(&self.world, exit.to_scene, &name_buf) }}, &buf) catch exit.to_scene);
        return true;
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

    /// Puts this tick's speech in the banner. Offered choices are drawn in the dialogue panel
    /// (D-077), so the banner keeps the last line said or the last round's result.
    fn show_story(self: *WasmRuntime) void {
        var buf: [512]u8 = undefined;
        if (host_mod.speech_this_tick(self.active_world(), &self.vm, &buf)) |line| self.set_banner(line);
    }

    /// Queues a click-through message (D-080). `speaker` is an entity name or empty.
    pub fn queue_message(self: *WasmRuntime, speaker: []const u8, text: []const u8) void {
        self.messages.push(speaker, text);
    }

    /// Records the whole run into the next slot: the world, then the walking agents and the
    /// VM with its dice in the save's own form, then the branch (D-184), so a scrub restores
    /// routines and rolls as they were.
    pub fn record_snapshot(self: *WasmRuntime) void {
        const slot = self.snapshot_count % MAX_WASM_SNAPSHOTS;
        var writer: std.Io.Writer = .fixed(&self.snapshot_bufs[slot]);
        self.world.save_state(&writer) catch return;
        save_mod.write_spatial_state(&writer, &self.spatial) catch return;
        save_mod.write_vm_state(&writer, &self.vm, save_mod.SAVE_VERSION) catch return;
        if (self.hypervisor) |hv| write_temporal(hv, &writer) catch return;
        self.snapshot_lens[slot] = writer.end;
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
        if (hv.branch_world != null) try (hv.branch_dice orelse return error.InvalidSnapshot).write(writer);
    }

    fn read_temporal(self: *WasmRuntime, hv: *TemporalHypervisor, reader: anytype) !void {
        const had_branch = (try reader.takeByte()) != 0;
        if (had_branch) {
            // A rewind to before a collapse brings the branch back: clone a world to restore over.
            if (hv.branch_world == null) hv.branch_world = try self.world.clone(self.allocator);
            try hv.branch_world.?.restore_state(reader);
        } else if (hv.branch_world) |*branch| {
            branch.deinit();
            hv.branch_world = null;
        }
        hv.branch_active = had_branch;
        hv.ticks_elapsed = try reader.takeInt(u64, .little);
        hv.collapse_state = std.enums.fromInt(hypervisor_mod.BranchCollapseState, try reader.takeByte()) orelse return error.InvalidSnapshot;
        hv.branch_dice = if (had_branch) try dice_mod.Dice.read(reader) else null;
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
            // A held action belongs to the timeline being left.
            self.approach = null;
            var fbs: std.Io.Reader = .fixed(self.snapshot_bufs[slot][0..self.snapshot_lens[slot]]);
            // `rewinds reroll` keeps the run's dice going through a scrub (D-184).
            const reroll = if (self.compiled_program()) |program| program.rewinds_reroll else false;
            const dice = self.vm.dice;
            self.world.restore_state(&fbs) catch return;
            save_mod.read_spatial_state(&fbs, &self.spatial) catch return;
            save_mod.read_vm_state(&fbs, &self.vm, save_mod.SAVE_VERSION) catch return;
            if (reroll) self.vm.dice = dice;
            if (self.hypervisor) |hv| self.read_temporal(hv, &fbs) catch {
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
        hv.run_seed = self.seed;
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
        self.vm.branch_dice = if (self.hypervisor) |hv| hv.active_dice() else null;
        self.vm.spatial = &self.spatial;
        self.vm.chunk = if (self.program) |*program| &program.chunk else &self.chunk;
    }

    /// Steps one discrete simulation tick across the active scenario spine.
    pub fn step_tick(self: *WasmRuntime) anyerror!void {
        self.bind();
        try self.release_approach();
        if (self.program) |*program| {
            const walking_before = self.player_entity != .none and self.spatial.is_moving(self.player_entity);
            _ = try host_mod.tick(&self.vm, program);
            self.show_story();
            try self.take_exit(walking_before);
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

    /// Runs the deck's page action `id` (D-095); a deck without one ignores it.
    pub fn deck_action(self: *WasmRuntime, id: u8) !void {
        if (self.decks.len == 0) return;
        const run = self.decks[self.deck_index].on_action orelse return;
        self.bind();
        try run(self, id);
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
                // A right-click puts an item in hand away before it cycles the verb (D-094).
                if (self.selected_item != .none) {
                    self.selected_item = .none;
                    self.set_banner("Put it away.");
                    return .item_selected;
                }
                self.active_verb = self.active_verb.next();
                var buf: [48]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Active verb: {s}", .{self.active_verb.label()}) catch "Verb changed";
                self.set_banner(msg);
                return .verb_changed;
            },
            .touch_start, .pointer_down => {
                self.hovered_x = ev.x;
                self.hovered_y = ev.y;
                // Every place below is where the desktop window draws it (D-097).
                const frame = self.capture();
                const w = self.screen(frame);

                // While the inspector is open, the stage belongs to it; the timeline still scrubs.
                const on_timeline = renderer.on_timeline(ev.x, ev.y, CANVAS_WIDTH);
                if (self.inspector_open and !on_timeline) {
                    return if (w.inspector_click(frame, ev.x, ev.y)) .inspector_navigated else .none;
                }

                // Two-finger touch tap cycles the active adventure verb
                if (ev.kind == .touch_start and ev.touch_points >= 2) {
                    self.active_verb = self.active_verb.next();
                    return .verb_changed;
                }

                // 1. The timeline bar scrubs.
                if (renderer.hit_test_timeline(ev.x, ev.y, CANVAS_WIDTH, self.max_history_tick)) |target_tick| {
                    self.scrub_to_tick(target_tick);
                    return .timeline_scrubbed;
                }

                // A waiting message takes any other click as "continue" (D-080).
                if (self.messages.advance()) return .message_dismissed;

                // A click on an offered choice answers it (D-077); elsewhere on the panel does
                // nothing.
                if (w.active_balloon) |*b| {
                    const panel = w.dialogue_panel_for(b);
                    if (renderer.hit_test_dialogue_panel(ev.x, ev.y, b, &panel)) |index| {
                        try self.answer(index);
                        return .dialogue_answered;
                    }
                    if (panel.rect.contains(ev.x, ev.y)) return .none;
                }

                // The distaff's note buttons (D-071) take clicks before the world below them.
                if (frame.distaff.enabled) {
                    const dpanel = renderer.get_distaff_panel_rect(CANVAS_WIDTH, CANVAS_HEIGHT);
                    if (dpanel.contains(ev.x, ev.y)) {
                        if (renderer.hit_test_distaff_note(ev.x, ev.y, CANVAS_WIDTH, CANVAS_HEIGHT, frame.distaff.reach)) |deg| {
                            return try self.play_note("CDEFGAB"[deg]);
                        }
                        return .none;
                    }
                }

                // 2. The verb bar, then the item tray.
                if (renderer.hit_test_verb_button(ev.x, ev.y, CANVAS_HEIGHT)) |verb| {
                    self.active_verb = @enumFromInt(@intFromEnum(verb));
                    self.selected_item = .none;
                    return .verb_changed;
                }
                if (self.tray_hit(ev.x, ev.y)) |item| return try self.click_item(item);

                const marks = frame.waypoints[0..frame.waypoint_count];

                // 3. With WALK, marks come first.
                if (self.active_verb == .walk) {
                    if (renderer.hit_test_waypoint(ev.x, ev.y, marks, CANVAS_WIDTH, CANVAS_HEIGHT)) |wp_id| {
                        if (self.player_entity != .none) {
                            self.approach = null;
                            const planned = try self.plan_walk(wp_id);
                            // Already standing on an exit mark: a click on it leaves (D-094).
                            if (!self.spatial.is_moving(self.player_entity) and try self.exit_here()) {
                                self.record_snapshot();
                                return .walk_issued;
                            }
                            if (planned or !self.spatial.waypoint_blocked(self.active_world(), wp_id)) self.walk_banner(wp_id) else self.set_banner("That way is blocked.");
                            return .walk_issued;
                        }
                    }
                }

                // 4. People, where the desktop draws them (D-088, D-097).
                const people = frame.entities[0..frame.entity_count];
                if (renderer.hit_test_actor(ev.x, ev.y, people, CANVAS_WIDTH, CANVAS_HEIGHT, self.window.art)) |i| {
                    const who = people[i].entity;
                    // The player can be clicked to use an item in hand on themself (D-094).
                    const on_self = who == self.player_entity and self.selected_item != .none and self.active_verb == .use_with;
                    if (who != self.player_entity or on_self) {
                        if (try self.act_on(who, null)) |tag| return tag;
                    }
                    var name_buf: [48]u8 = undefined;
                    const name = dialogue_panel.entity_name(&self.world, who, &name_buf) orelse phrase_mod.text(&self.world, .someone);
                    var buf: [80]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "[{s}] {s}", .{ self.active_verb.label(), name }) catch name;
                    self.set_banner(msg);
                    return .actor_interacted;
                }

                // 5. Props.
                if (renderer.hit_test_hotspot(ev.x, ev.y, frame.hotspots[0..frame.hotspot_count], CANVAS_WIDTH, CANVAS_HEIGHT, self.window.art)) |i| {
                    const target = frame.hotspots[i].entity;
                    for (self.spatial.hotspots.items) |hs| {
                        if (hs.entity != target) continue;
                        if (try self.act_on(hs.entity, hs.examine_text)) |tag| return tag;
                        // A prop with no description of its own reads as its name, in words.
                        var ex_buf: [48]u8 = undefined;
                        self.set_banner(if (std.mem.eql(u8, hs.examine_text, hs.name)) dialogue_panel.display_name(hs.name, &ex_buf) else hs.examine_text);
                        return .hotspot_inspected;
                    }
                }

                // 6. Marks with any other verb: a walk.
                if (renderer.hit_test_waypoint(ev.x, ev.y, marks, CANVAS_WIDTH, CANVAS_HEIGHT)) |wp_id| {
                    if (self.player_entity != .none) {
                        if ((try self.plan_walk(wp_id)) or !self.spatial.waypoint_blocked(self.active_world(), wp_id)) self.walk_banner(wp_id) else self.set_banner("That way is blocked.");
                        return .walk_issued;
                    }
                }
                return .none;
            },
            .key_down => {
                // The command bar comes first (P34-04): focused, it takes every key, so no
                // shortcut fires while typing; unfocused, Enter focuses it unless a message or a
                // choice is waiting, as on desktop.
                if (self.command_bar_on()) {
                    if (self.window.command_bar_focused) return try self.command_key(ev.key_code);
                    if (ev.key_code == 13 and !self.messages.pending() and !self.choices_open()) {
                        self.window.command_bar_focused = true;
                        return .command_edited;
                    }
                }
                // Opening the inspector pauses the clock so the state holds still; closing
                // restores the earlier run state.
                if (ev.key_code == 'i' or ev.key_code == 'I') {
                    if (self.inspector_open) {
                        self.inspector_open = false;
                        self.is_paused = self.inspector_was_paused;
                    } else {
                        self.inspector_open = true;
                        self.inspector_was_paused = self.is_paused;
                        self.is_paused = true;
                    }
                    return .inspector_toggled;
                }
                // While the inspector is open its keys come first, the timeline keys still work,
                // and the clock, deck, and solve keys wait until it closes. The keys are the
                // desktop State tab's (D-059), handled by the same window code.
                if (self.inspector_open) {
                    if (InspectorKey.desktop(ev.key_code)) |code| {
                        const frame = self.capture();
                        if (self.screen(frame).inspector_key(frame, code)) return .inspector_navigated;
                    }
                    if (ev.key_code != 'r' and ev.key_code != 'R') return .none;
                }
                // A waiting message takes Enter, Space, or the solve key as "continue" (D-080);
                // the number keys cannot answer the choices it hides.
                if (self.messages.pending()) switch (ev.key_code) {
                    13, ' ', 's', 'S' => {
                        _ = self.messages.advance();
                        return .message_dismissed;
                    },
                    '1'...'9' => return .none,
                    else => {},
                };
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
            .char => {
                // Printable characters fill the focused command bar (P34-04); otherwise a page's
                // key_down for the same key has already done whatever the key does.
                if (!self.command_bar_on() or !self.window.command_bar_focused) return .none;
                if (ev.key_code < 32 or ev.key_code > 126) return .none;
                // An empty bar lets a number answer the open choices, as on desktop (D-142).
                if (self.program != null and self.window.command_bar_yields_digit(self.choice_count(), ev.key_code)) {
                    try self.answer(ev.key_code - '1');
                    return .dialogue_answered;
                }
                self.window.command_bar_text(&[_]u8{ev.key_code});
                return .command_edited;
            },
        }
    }

    /// "Walking to <mark>...", and the mark's ring as the walk's target (D-093).
    fn walk_banner(self: *WasmRuntime, wp_id: WaypointId) void {
        self.window.target_wp = wp_id;
        const wp = self.spatial.graph.get_waypoint(wp_id) orelse return;
        var buf: [64]u8 = undefined;
        var name_buf: [48]u8 = undefined;
        const msg = phrase_mod.render(&self.world, .walking_to, &.{.{ .slot = "mark", .value = dialogue_panel.display_name(wp.name, &name_buf) }}, &buf) catch "Walking...";
        self.set_banner(msg);
    }

    /// The desktop frame for the current state (D-097), captured as the desktop hosts capture
    /// it, with the deck's status hook, the browser's timeline, and the tray in the browser's
    /// order (D-094). The pointer is valid until the next capture.
    pub fn capture(self: *WasmRuntime) *const display_mod.RenderFrame {
        const b = self.frame_bridge;
        b.set_status_hook(if (self.decks.len > 0) self.decks[self.deck_index].status_hook else null);
        b.active_player_character = if (self.player_entity != .none) self.player_entity else null;
        b.distaff = if (self.has_drafts()) &self.distaff else null;
        self.bind();
        b.capture_frame(self.active_world(), &self.spatial, &self.vm);
        b.back_buffer.tick = self.clock();
        b.back_buffer.max_history_tick = self.max_history_tick;
        var items: [MAX_TRAY]EntityId = undefined;
        const n = self.carried(&items);
        for (items[0..n], 0..) |item, i| {
            var slot = &b.back_buffer.inventory[i];
            slot.entity = item;
            const name = self.active_world().get_entity_name(item) orelse "?";
            const len = @min(name.len, slot.name.len);
            @memcpy(slot.name[0..len], name[0..len]);
            slot.name_len = @intCast(len);
        }
        b.back_buffer.inventory_count = n;
        b.swap();
        return b.get_frame();
    }

    /// The desktop window that draws the browser's frame, with the browser's state put into it:
    /// the verb, the item in hand, waiting messages, the open dialogue, what is under the pointer,
    /// and the banner. The window is re-pointed at the runtime first, which moves after `init`.
    pub fn screen(self: *WasmRuntime, frame: *const display_mod.RenderFrame) *renderer.DisplayWindow {
        const w = self.window;
        w.audio_bridge = &self.audio;
        w.canvas = renderer.Canvas.init(self.framebuffer, CANVAS_WIDTH, CANVAS_HEIGHT);
        w.theme = if (self.decks.len > 0) self.decks[self.deck_index].theme else null;
        w.backdrop_color = if (self.decks.len > 0) self.decks[self.deck_index].background else NO_DECK_BACKGROUND;
        w.footer_text = BROWSER_FOOTER;
        w.active_verb = @enumFromInt(@intFromEnum(self.active_verb));
        w.selected_inventory_item = null;
        if (self.selected_item != .none) {
            for (frame.inventory[0..frame.inventory_count], 0..) |item, i| {
                if (item.entity == self.selected_item) w.selected_inventory_item = i;
            }
        }
        w.messages = self.messages;
        w.sync_dialogue_balloon(frame);

        if (self.inspector_open) {
            w.hovered_choice = null;
            w.hovered_wp = null;
            w.hovered_hotspot = null;
            w.hovered_actor = null;
            w.hovered_party_member = null;
        } else w.update_hover(frame, self.hovered_x, self.hovered_y);

        return w;
    }

    /// The recorders a golden test lends the window's canvas for one drawn beat, so the frame
    /// can be measured against the message band (P43-05). The browser lends none.
    pub const CanvasProbes = struct {
        text: *canvas_mod.TextProbe,
        rect: *canvas_mod.RectProbe,
    };

    /// Draws the desktop window's frame into the framebuffer (D-097), and the state inspector
    /// over it while it is open (D-070), both by the window.
    pub fn render_frame(self: *WasmRuntime) void {
        self.render_frame_probed(null);
    }

    /// The same draw, recording what it paints when `probes` are lent (P43-05). `screen` makes
    /// the canvas, so the probes are set after it and before the window draws.
    pub fn render_frame_probed(self: *WasmRuntime, probes: ?CanvasProbes) void {
        if (self.has_drafts()) self.distaff.set_reach_from(self.active_world(), self.player_entity, "DistaffReach", 7);
        const frame = self.capture();
        const w = self.screen(frame);
        if (probes) |p| if (w.canvas) |*cv| {
            cv.text_probe = p.text;
            cv.rect_probe = p.rect;
        };
        w.render_frame(frame, self.is_paused);
        if (self.inspector_open) w.render_state_overlay(frame);
    }

    /// A pixel of the last frame drawn.
    pub fn pixel(self: *const WasmRuntime, x: i32, y: i32) RgbaColor {
        const v = renderer.Canvas.init(self.framebuffer, CANVAS_WIDTH, CANVAS_HEIGHT);
        return v.get_pixel(x, y);
    }

    /// The open dialogue's panel where the desktop draws it, or null.
    pub fn dialogue_panel_now(self: *WasmRuntime) ?renderer.DialoguePanel {
        const w = self.screen(self.capture());
        const b = &(w.active_balloon orelse return null);
        return w.dialogue_panel_for(b);
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
        // The 1280x720 frame (D-097), uninitialised like the runtime so it costs no download.
        var framebuffer: [FRAMEBUFFER_BYTES]u8 = undefined;

        fn runtime() ?*WasmRuntime {
            return if (runtime_ready) &global_runtime else null;
        }

        /// The page passes its seed as two 32-bit halves (D-184); a page that passes only the
        /// scenario sends zeros, which mean the default seed, so older pages are unchanged.
        fn wasm_init(scenario_id: u8, seed_low: u32, seed_high: u32) callconv(.c) void {
            if (runtime_ready) global_runtime.deinit();
            runtime_ready = false;
            const given = @as(u64, seed_high) << 32 | seed_low;
            const seed = if (given == 0) dice_mod.DEFAULT_SEED else given;
            global_runtime = WasmRuntime.init_seeded(global_heap.allocator(), decks, scenario_id, &framebuffer, seed) catch return;
            runtime_ready = true;
        }

        fn wasm_load_scenario(scenario_id: u8) callconv(.c) void {
            const seed = if (runtime_ready) global_runtime.seed else dice_mod.DEFAULT_SEED;
            wasm_init(scenario_id, @truncate(seed), @truncate(seed >> 32));
        }

        fn wasm_step_tick() callconv(.c) void {
            if (runtime()) |rt| {
                if (!rt.is_paused) {
                    rt.step_tick() catch {};
                    rt.render_frame();
                }
            }
        }

        fn wasm_render_frame() callconv(.c) void {
            if (runtime()) |rt| {
                rt.render_frame();
            }
        }

        /// Sets the animation clock to the 60 Hz display frames shown since the page started
        /// (P46-03, D-152). The page derives it from elapsed time, so a fast monitor or a
        /// redraw on input does not speed animations up.
        fn wasm_set_animation_clock(frames: u32) callconv(.c) void {
            if (runtime()) |rt| rt.window.animation_clock = frames;
        }

        fn wasm_framebuffer_ptr() callconv(.c) [*]const u8 {
            // Valid memory of the right length before a runtime exists, so the page can read it
            // without a check.
            return &framebuffer;
        }

        fn wasm_framebuffer_len() callconv(.c) usize {
            return FRAMEBUFFER_BYTES;
        }

        fn wasm_on_pointer_down(x: i32, y: i32) callconv(.c) u8 {
            if (runtime()) |rt| {
                const tag = rt.dispatch_event(.{ .kind = .pointer_down, .x = x, .y = y }) catch .none;
                rt.render_frame();
                return @intFromEnum(tag);
            }
            return 0;
        }

        fn wasm_on_pointer_move(x: i32, y: i32) callconv(.c) u8 {
            if (runtime()) |rt| {
                const tag = rt.dispatch_event(.{ .kind = .pointer_move, .x = x, .y = y }) catch .none;
                return @intFromEnum(tag);
            }
            return 0;
        }

        fn wasm_on_right_click(x: i32, y: i32) callconv(.c) u8 {
            if (runtime()) |rt| {
                const tag = rt.dispatch_event(.{ .kind = .right_click, .x = x, .y = y }) catch .none;
                rt.render_frame();
                return @intFromEnum(tag);
            }
            return 0;
        }

        fn wasm_on_key_down(key_code: u8) callconv(.c) u8 {
            if (runtime()) |rt| {
                const tag = rt.dispatch_event(.{ .kind = .key_down, .key_code = key_code }) catch .none;
                rt.render_frame();
                return @intFromEnum(tag);
            }
            return 0;
        }

        /// A typed character (the page sends `event.key` when it is one character), for the
        /// command bar of a deck that has one (P34-04).
        fn wasm_on_char(code: u8) callconv(.c) u8 {
            if (runtime()) |rt| {
                const tag = rt.dispatch_event(.{ .kind = .char, .key_code = code }) catch .none;
                rt.render_frame();
                return @intFromEnum(tag);
            }
            return 0;
        }

        /// True while a command bar has the keyboard, so a page holds back its own shortcuts.
        fn wasm_command_bar_focused() callconv(.c) u8 {
            if (runtime()) |rt| return @intFromBool(rt.command_bar_on() and rt.window.command_bar_focused);
            return 0;
        }

        fn wasm_on_touch(kind_id: u8, x: i32, y: i32, points: u8) callconv(.c) u8 {
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

        fn wasm_scrub_to_tick(target_tick: u32) callconv(.c) void {
            if (runtime()) |rt| {
                rt.scrub_to_tick(target_tick);
                rt.render_frame();
            }
        }

        fn wasm_get_tick() callconv(.c) u32 {
            if (runtime()) |rt| {
                return @intCast(rt.clock());
            }
            return 0;
        }

        /// 1 while a script deck's dialogue is open, so a page can send number keys to it
        /// instead of switching decks (D-069).
        fn wasm_message_pending() callconv(.c) u8 {
            if (runtime()) |rt| return @intFromBool(rt.messages.pending());
            return 0;
        }

        fn wasm_dialogue_open() callconv(.c) u8 {
            if (runtime()) |rt| return @intFromBool(dialogue_mod.view(&rt.world) != null);
            return 0;
        }

        var audio_samples: [2 * AUDIO_MAX_FRAMES]i16 = undefined;

        /// Renders `frames` stereo frames (at most 4096) of the engine synthesizer at
        /// `wasm_audio_sample_rate` into a buffer and returns it; the page plays it through Web
        /// Audio (D-071). Silence before a runtime exists.
        fn wasm_audio_render(frames: u32) callconv(.c) [*]const i16 {
            const n: usize = @min(frames, AUDIO_MAX_FRAMES);
            if (runtime()) |rt| {
                rt.audio.render_samples(audio_samples[0 .. 2 * n]);
            } else {
                @memset(audio_samples[0 .. 2 * n], 0);
            }
            return &audio_samples;
        }

        fn wasm_audio_sample_rate() callconv(.c) u32 {
            return audio_mod.SAMPLE_RATE;
        }

        /// 1 while the state inspector is open (D-070); the clock is paused then.
        fn wasm_inspector_open() callconv(.c) u8 {
            if (runtime()) |rt| return @intFromBool(rt.inspector_open);
            return 0;
        }

        /// Runs the deck's page action `id`, for a page's own button (D-095).
        fn wasm_deck_action(id: u8) callconv(.c) void {
            if (runtime()) |rt| {
                rt.deck_action(id) catch {};
                rt.render_frame();
            }
        }

        /// The active verb's index (WALK 0 to USE 4), so a page's own verb buttons can follow
        /// the canvas, which changes the verb when an item is taken in hand (D-094).
        fn wasm_active_verb() callconv(.c) u8 {
            if (runtime()) |rt| return @intFromEnum(rt.active_verb);
            return 0;
        }

        /// Selects verb `index` (WALK 0 to USE 4) and puts away an item in hand, as a click on
        /// the canvas verb bar does, so a page's own buttons need not know where that bar is.
        fn wasm_set_verb(index: u8) callconv(.c) void {
            if (runtime()) |rt| {
                if (index > 4) return;
                rt.active_verb = @enumFromInt(index);
                rt.selected_item = .none;
                rt.render_frame();
            }
        }

        fn wasm_get_fact_count() callconv(.c) u32 {
            if (runtime()) |rt| {
                return @intCast(rt.world.fact_count());
            }
            return 0;
        }
    };
    @export(&Exports.wasm_init, .{ .name = "wasm_init" });
    @export(&Exports.wasm_dialogue_open, .{ .name = "wasm_dialogue_open" });
    @export(&Exports.wasm_message_pending, .{ .name = "wasm_message_pending" });
    @export(&Exports.wasm_inspector_open, .{ .name = "wasm_inspector_open" });
    @export(&Exports.wasm_active_verb, .{ .name = "wasm_active_verb" });
    @export(&Exports.wasm_set_verb, .{ .name = "wasm_set_verb" });
    @export(&Exports.wasm_deck_action, .{ .name = "wasm_deck_action" });
    @export(&Exports.wasm_audio_render, .{ .name = "wasm_audio_render" });
    @export(&Exports.wasm_audio_sample_rate, .{ .name = "wasm_audio_sample_rate" });
    @export(&Exports.wasm_load_scenario, .{ .name = "wasm_load_scenario" });
    @export(&Exports.wasm_step_tick, .{ .name = "wasm_step_tick" });
    @export(&Exports.wasm_render_frame, .{ .name = "wasm_render_frame" });
    @export(&Exports.wasm_set_animation_clock, .{ .name = "wasm_set_animation_clock" });
    @export(&Exports.wasm_framebuffer_ptr, .{ .name = "wasm_framebuffer_ptr" });
    @export(&Exports.wasm_framebuffer_len, .{ .name = "wasm_framebuffer_len" });
    @export(&Exports.wasm_on_pointer_down, .{ .name = "wasm_on_pointer_down" });
    @export(&Exports.wasm_on_pointer_move, .{ .name = "wasm_on_pointer_move" });
    @export(&Exports.wasm_on_right_click, .{ .name = "wasm_on_right_click" });
    @export(&Exports.wasm_on_key_down, .{ .name = "wasm_on_key_down" });
    @export(&Exports.wasm_on_char, .{ .name = "wasm_on_char" });
    @export(&Exports.wasm_command_bar_focused, .{ .name = "wasm_command_bar_focused" });
    @export(&Exports.wasm_on_touch, .{ .name = "wasm_on_touch" });
    @export(&Exports.wasm_scrub_to_tick, .{ .name = "wasm_scrub_to_tick" });
    @export(&Exports.wasm_get_tick, .{ .name = "wasm_get_tick" });
    @export(&Exports.wasm_get_fact_count, .{ .name = "wasm_get_fact_count" });
}

// =============================================================================
// 4. Unit Tests (Phase 19: P19-01, P19-02, D-022)
// =============================================================================

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
    const bg = rt.pixel(4, 300);
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

    // 1. Click verb button 1 (LOOK) on the desktop verb bar (D-097)
    const verb_res = try rt.dispatch_event(.{ .kind = .pointer_down, .x = 104, .y = CANVAS_HEIGHT - 68 });
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

    // 4. Click the Well waypoint at world (40, 0), where the desktop draws it: a walk
    const well = rt.projection().point(40, 0);
    const walk_res = try rt.dispatch_event(.{ .kind = .pointer_down, .x = well.x, .y = well.y });
    try testing.expectEqual(BrowserActionTag.walk_issued, walk_res);

    // 5. Keyboard 'n' steps tick, 's' triggers catalyst, and timeline click scrubs back to Tick 0
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'n' });
    try testing.expectEqual(@as(u64, 1), rt.world.current_tick);

    const cat_res = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 's' });
    try testing.expectEqual(BrowserActionTag.catalyst_triggered, cat_res);

    const scrub_res = try rt.dispatch_event(.{ .kind = .pointer_down, .x = 22, .y = 60 });
    try testing.expectEqual(BrowserActionTag.timeline_scrubbed, scrub_res);
    try testing.expectEqual(@as(u64, 0), rt.world.current_tick);
}

test "D-088: people sharing a mark fan out, and a click lands on the one drawn there" {
    const testing = std.testing;
    const script =
        \\scene Quay:
        \\  cast: Hero, Pilot, Bosun
        \\  marks: Steps, Pier
        \\
        \\routine Idle(Hero):
        \\  wait 1 ticks
        \\
        \\on cue TalksTo(Hero, Pilot):
        \\  say Pilot: "Ahoy."
        \\
        \\on cue TalksTo(Hero, Bosun):
        \\  say Bosun: "Aye."
    ;
    const decks = [_]Deck{script_deck_with("QUAY", script, .{ .player = "Hero" })};
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, 0);
    defer rt.deinit();

    const proj = rt.projection();
    var slots: [WasmRuntime.MAX_ACTOR_SLOTS]WasmRuntime.ActorSlot = undefined;
    const n = rt.actor_slots(proj, &slots);
    try testing.expectEqual(@as(usize, 3), n);
    // All three stand on Steps: each is drawn apart from the others.
    for (slots[0..n], 0..) |a, i| for (slots[0..n], 0..) |b, j| {
        if (i == j) continue;
        try testing.expect(a.x != b.x);
    };
    // A click on each drawn circle finds that person, and TALK on the Bosun runs his line.
    for (slots[0..n]) |slot| try testing.expectEqual(slot.entity, rt.actor_at(proj, slot.x + 3, slot.y - 2).?.entity);
    const bosun = rt.world.lookup_entity("Bosun").?;
    var bosun_slot: WasmRuntime.ActorSlot = undefined;
    for (slots[0..n]) |slot| {
        if (slot.entity == bosun) bosun_slot = slot;
    }
    rt.active_verb = .talk_to;
    try testing.expectEqual(BrowserActionTag.cue_fired, try rt.dispatch_event(.{ .kind = .pointer_down, .x = bosun_slot.x, .y = bosun_slot.y }));
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Aye.") != null);
}

test "D-086: a deck's on_act hook runs before the verb's cue and can take it over" {
    const testing = std.testing;
    const script =
        \\scene Quay:
        \\  cast: Hero, Pilot
        \\  marks: Steps, Pier
        \\
        \\routine Idle(Hero):
        \\  wait 1 ticks
        \\
        \\on cue TalksTo(Hero, Pilot):
        \\  say Pilot: "Ahoy."
    ;
    const Hook = struct {
        var calls: usize = 0;
        fn act(rt: *WasmRuntime, verb: WasmVerb, target: EntityId) anyerror!bool {
            _ = rt;
            _ = target;
            calls += 1;
            return verb == .talk_to;
        }
    };
    const decks = [_]Deck{script_deck_with("QUAY", script, .{ .player = "Hero", .on_act = Hook.act })};
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, 0);
    defer rt.deinit();
    const pilot = rt.world.lookup_entity("Pilot").?;

    // TALK: the hook takes it, so the script's cue never fires.
    rt.active_verb = .talk_to;
    try testing.expectEqual(BrowserActionTag.actor_interacted, (try rt.act_on(pilot, null)).?);
    try testing.expectEqual(@as(usize, 1), Hook.calls);
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Ahoy.") == null);
    // LOOK: the hook declines, and the verb's cue runs as before (no handler, so nothing happens).
    rt.active_verb = .look_at;
    try testing.expectEqual(BrowserActionTag.cue_fired, (try rt.act_on(pilot, null)).?);
    try testing.expectEqual(@as(usize, 2), Hook.calls);
}

test "P34-04: a deck's command bar takes typed characters, keeps shortcuts quiet, and runs the line" {
    const testing = std.testing;
    const script =
        \\scene Quay:
        \\  cast: Hero
        \\  props: Rope
        \\  marks: Steps, Pier
        \\
        \\command Takes: "take <thing>"
        \\
        \\routine Idle(Hero):
        \\  wait 1 ticks
        \\
        \\on cue Takes(Hero, Rope):
        \\  remember Carries(Hero, Rope)
        \\  say Hero: "Got the rope."
    ;
    const decks = [_]Deck{script_deck_with("QUAY", script, .{ .player = "Hero", .command_bar = true })};
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, 0);
    defer rt.deinit();

    // Characters do nothing until Enter focuses the bar.
    try testing.expectEqual(BrowserActionTag.none, try rt.dispatch_event(.{ .kind = .char, .key_code = 'x' }));
    try testing.expectEqual(BrowserActionTag.command_edited, try rt.dispatch_event(.{ .kind = .key_down, .key_code = 13 }));
    for ("take the rope") |ch| {
        // The key itself is swallowed: space would pause and N would step if it reached them.
        try testing.expectEqual(BrowserActionTag.command_edited, try rt.dispatch_event(.{ .kind = .key_down, .key_code = std.ascii.toUpper(ch) }));
        try testing.expectEqual(BrowserActionTag.command_edited, try rt.dispatch_event(.{ .kind = .char, .key_code = ch }));
    }
    try testing.expect(!rt.is_paused);
    try testing.expectEqualStrings("take the rope", rt.window.command_input[0..rt.window.command_len]);
    // Backspace edits; Enter submits to the script's commands for the player.
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 8 });
    _ = try rt.dispatch_event(.{ .kind = .char, .key_code = 'e' });
    try testing.expectEqual(BrowserActionTag.command_typed, try rt.dispatch_event(.{ .kind = .key_down, .key_code = 13 }));
    const hero = rt.world.lookup_entity("Hero").?;
    const rope = rt.world.lookup_entity("Rope").?;
    try testing.expect(rt.world.has_fact(hero, rt.world.lookup_relation("Carries").?, rope.to_int()));
    // Escape leaves the bar; a deck without one never focuses it.
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 27 });
    try testing.expect(!rt.window.command_bar_focused);
}

test "D-142: an empty focused command bar lets a number answer the open choices" {
    const testing = std.testing;
    const script =
        \\scene Quay:
        \\  cast: Hero, Pilot
        \\  marks: Steps, Pier
        \\
        \\relation Said(who, what)
        \\entity Yes
        \\entity No
        \\
        \\routine Idle(Hero):
        \\  wait 1 ticks
        \\
        \\on cue TalksTo(Hero, Pilot):
        \\  say Pilot: "Crossing tonight?"
        \\  choice "Yes.":
        \\    remember Said(Hero, Yes)
        \\  choice "No.":
        \\    remember Said(Hero, No)
    ;
    const decks = [_]Deck{script_deck_with("QUAY", script, .{ .player = "Hero", .command_bar = true })};
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, 0);
    defer rt.deinit();

    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 13 });
    for ("talk to pilot") |ch| _ = try rt.dispatch_event(.{ .kind = .char, .key_code = ch });
    try testing.expectEqual(BrowserActionTag.command_typed, try rt.dispatch_event(.{ .kind = .key_down, .key_code = 13 }));
    var ticks: usize = 0;
    while (rt.choice_count() == 0 and ticks < 5) : (ticks += 1) try rt.step_tick();
    try testing.expectEqual(@as(usize, 2), rt.choice_count());
    try testing.expect(rt.window.command_bar_focused);

    // A digit past the last option is text; with text in the bar, a valid digit is text too.
    try testing.expectEqual(BrowserActionTag.command_edited, try rt.dispatch_event(.{ .kind = .char, .key_code = '7' }));
    try testing.expectEqual(BrowserActionTag.command_edited, try rt.dispatch_event(.{ .kind = .char, .key_code = '2' }));
    try testing.expectEqualStrings("72", rt.window.command_input[0..rt.window.command_len]);
    try testing.expectEqual(@as(usize, 2), rt.choice_count());

    // Emptied, the bar lets the digit answer, and the chosen body runs.
    rt.window.command_len = 0;
    try testing.expectEqual(BrowserActionTag.dialogue_answered, try rt.dispatch_event(.{ .kind = .char, .key_code = '2' }));
    const hero = rt.world.lookup_entity("Hero").?;
    const no = rt.world.lookup_entity("No").?;
    try testing.expect(rt.world.has_fact(hero, rt.world.lookup_relation("Said").?, no.to_int()));
    try testing.expectEqual(@as(usize, 0), rt.window.command_len);
    try testing.expect(rt.window.command_bar_focused);
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
    // The choices are in the dialogue panel, with the speaker's name; the banner keeps the
    // last line said (D-077).
    const panel = rt.dialogue_panel_now().?;
    try testing.expectEqual(@as(usize, 2), panel.layout.choice_count);
    // The panel names the dialogue's display speaker, as the desktop does; for a choice in the
    // player's own cue handler that is the player.
    try testing.expectEqualStrings("Hero", panel.layout.slice()[0].text);
    try testing.expect(panel.rect.y + panel.rect.h <= CANVAS_HEIGHT - 80);
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "[1]") == null);

    // A waiting message (D-080) covers the panel: number keys wait, a click on a choice's place
    // dismisses the message instead of answering, and Enter dismisses the next.
    rt.queue_message("Pilot", "Choose carefully.");
    rt.queue_message("", "The tide is turning.");
    try testing.expectEqual(BrowserActionTag.none, try rt.dispatch_event(.{ .kind = .key_down, .key_code = '1' }));
    const choice_y = panel.rect.y + panel.layout.choice_top[0] + 2;
    try testing.expectEqual(BrowserActionTag.message_dismissed, try rt.dispatch_event(.{ .kind = .pointer_down, .x = panel.rect.x + 40, .y = choice_y }));
    try testing.expectEqual(BrowserActionTag.message_dismissed, try rt.dispatch_event(.{ .kind = .key_down, .key_code = 13 }));
    try testing.expect(!rt.messages.pending());
    try testing.expect(rt.dialogue_panel_now() != null);
    // An open dialogue takes the number keys from deck switching.
    try testing.expectEqual(BrowserActionTag.dialogue_answered, try rt.dispatch_event(.{ .kind = .key_down, .key_code = '1' }));
    try testing.expectEqualStrings("Pilot: \"Over the water.\"", rt.get_banner());
    try testing.expect(dialogue_mod.view(&rt.world) == null);

    // A click on a choice's row answers it too.
    _ = (try rt.vm.fire_cue(program, "TalksTo", rt.player_entity, rt.world.lookup_entity("Pilot").?, null)).?;
    try rt.step_tick();
    const again = rt.dialogue_panel_now().?;
    const leave_y = again.rect.y + again.layout.choice_top[1] + 3;
    try testing.expectEqual(BrowserActionTag.dialogue_answered, try rt.dispatch_event(.{ .kind = .pointer_down, .x = again.rect.x + 40, .y = leave_y }));
    try testing.expectEqualStrings("Pilot: \"Goodbye.\"", rt.get_banner());
    try testing.expect(dialogue_mod.view(&rt.world) == null);

    // Reloading the deck releases the program and starts again.
    try rt.load_deck(0);
    try testing.expectEqual(@as(u64, 0), rt.world.current_tick);
}

test "P48-09: the browser shows a script's display names and phrases" {
    const testing = std.testing;
    const script =
        \\scene Quay:
        \\  cast: Hero, Pilot
        \\  marks: Steps, Pier
        \\name Pilot: "Old Mara"
        \\phrase NothingHappens: "Rien ne se passe."
        \\
        \\routine Walk(Hero):
        \\  walk Hero to Pier
        \\  remember Arrived(Hero)
        \\
        \\when Arrived(Hero):
        \\  say Pilot: "Mind the gap."
    ;
    const decks = [_]Deck{script_deck("QUAY", script)};
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, 0);
    defer rt.deinit();
    var heard = false;
    for (0..12) |_| {
        try rt.step_tick();
        if (std.mem.indexOf(u8, rt.get_banner(), "Old Mara") != null) heard = true;
    }
    try testing.expect(heard);
    try testing.expectEqualStrings("Rien ne se passe.", phrase_mod.text(&rt.world, .nothing_happens));
    var buf: [48]u8 = undefined;
    try testing.expectEqualStrings("Old Mara", dialogue_panel.display_name("Pilot", &buf));
}

test "D-070: the inspector pauses, takes the desktop State tab's keys and clicks, and draws in the drawer's place" {
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
    try testing.expect(rt.inspector_open and rt.is_paused);
    const tick = rt.world.current_tick;
    // Clock and deck keys wait while it is open.
    try testing.expectEqual(BrowserActionTag.none, try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'N' }));
    try testing.expectEqual(tick, rt.world.current_tick);

    // The capture is the desktop's: the same function, the same facts.
    const display = @import("display.zig");
    var desktop: [display.MAX_DEBUG_FACTS]display.RenderDebugFact = undefined;
    try testing.expectEqual(display.capture_debug_facts(&rt.world, &desktop), rt.capture().debug_fact_count);

    // The page's keys reach the desktop State tab's navigation (D-059, D-097), which its own
    // tests cover in full: Hero has the most edges, so it is the default focus; Right selects,
    // Enter recentres, Backspace goes back.
    const w = rt.window;
    const hero = rt.world.lookup_entity("Hero").?;
    const first = w.inspector_layout(rt.capture()).?;
    try testing.expectEqual(hero, first.center.entity);
    try testing.expectEqual(BrowserActionTag.inspector_navigated, try rt.dispatch_event(.{ .kind = .key_down, .key_code = InspectorKey.right }));
    try testing.expectEqual(@as(usize, 1), w.inspector_selected);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = InspectorKey.enter });
    try testing.expectEqual(first.ring[1].entity, w.inspector_focus.?);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = InspectorKey.backspace });
    try testing.expectEqual(hero, w.inspector_focus.?);

    // A click on a ring node recentres on it, where the desktop draws it.
    const ring0 = w.inspector_layout(rt.capture()).?.ring[0];
    try testing.expectEqual(BrowserActionTag.inspector_navigated, try rt.dispatch_event(.{ .kind = .pointer_down, .x = ring0.x, .y = ring0.y }));
    try testing.expectEqual(ring0.entity, w.inspector_focus.?);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = InspectorKey.home });
    try testing.expect(w.inspector_focus == null);
    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'F' });
    try testing.expectEqualStrings("BELIEFS", w.inspector_filter.label());

    // The overlay is drawn in the save drawer's place: its header bar fills the drawer's top.
    rt.render_frame();
    const drect = renderer.get_save_drawer_rect(CANVAS_WIDTH, CANVAS_HEIGHT);
    try testing.expectEqual(RgbaColor{ .r = 22, .g = 32, .b = 54 }, rt.pixel(drect.x + 6, drect.y + 6));

    _ = try rt.dispatch_event(.{ .kind = .key_down, .key_code = 'i' });
    try testing.expect(!rt.inspector_open and !rt.is_paused);
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

test "P39-02: the browser heap cap admits its last byte and refuses the next" {
    const testing = std.testing;
    var capped = CappedAllocator{ .child = testing.allocator, .limit = WASM_HEAP_LIMIT };
    const allocator = capped.allocator();
    const full = try allocator.alloc(u8, WASM_HEAP_LIMIT);
    defer allocator.free(full);
    try testing.expectError(error.OutOfMemory, allocator.alloc(u8, 1));
    try testing.expectEqual(WASM_HEAP_LIMIT, capped.used);
}

test "D-092: a verb on someone across the room walks the player over first, then acts" {
    const testing = std.testing;
    const script =
        \\scene Quay:
        \\  cast: Hero, Pilot
        \\  marks: Steps, Pier
        \\
        \\on cue TalksTo(Hero, Pilot):
        \\  say Pilot: "Ahoy."
    ;
    const decks = [_]Deck{script_deck_with("QUAY", script, .{ .player = "Hero" })};
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, 0);
    defer rt.deinit();
    rt.bind();
    const pilot = rt.world.lookup_entity("Pilot").?;
    const quay = rt.world.lookup_entity("Quay").?;
    const pier = rt.spatial.graph.find_waypoint_in_room(quay, "Pier").?;
    _ = try rt.spatial.transition_actor(pilot, quay, pier);

    // TALK from the steps: Hero sets off, and nothing is said yet.
    rt.active_verb = .talk_to;
    try testing.expectEqual(BrowserActionTag.walk_issued, (try rt.act_on(pilot, null)).?);
    try testing.expect(rt.approach != null);
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Ahoy.") == null);

    // Ticks walk him over; on arrival the held TALK fires and the Pilot answers.
    var guard: usize = 0;
    while (rt.approach != null and guard < 20) : (guard += 1) try rt.step_tick();
    try testing.expect(rt.approach == null);
    try testing.expectEqual(pier, rt.spatial.agents.get(rt.player_entity).?.current_wp);
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Ahoy.") != null);

    // LOOK acts from where the player stands, with no walk.
    _ = try rt.spatial.transition_actor(rt.player_entity, quay, rt.spatial.graph.find_waypoint_in_room(quay, "Steps").?);
    rt.active_verb = .look_at;
    try testing.expect((try rt.act_on(pilot, null)).? != .walk_issued);
    try testing.expect(rt.approach == null);
}

test "D-094: the item tray keeps its order, fits the canvas, and uses items alone, in hand, and in pairs" {
    const testing = std.testing;
    const script =
        \\scene Quay:
        \\  cast: Hero, Pilot
        \\  marks: Steps, Pier
        \\
        \\remember: Carries(Hero, Lantern)
        \\remember: Carries(Hero, Rope)
        \\remember: Carries(Hero, Hook)
        \\
        \\on cue Uses(Hero, Lantern):
        \\  say Hero: "Light."
        \\
        \\on cue Uses(Hero, Hook, Rope):
        \\  forget Carries(Hero, Hook)
        \\  forget Carries(Hero, Rope)
        \\  remember Carries(Hero, Grapnel)
        \\
        \\on cue Uses(Hero, Grapnel, Pilot):
        \\  say Pilot: "Mind my hat."
    ;
    const decks = [_]Deck{script_deck_with("QUAY", script, .{ .player = "Hero" })};
    const rt = try testing.allocator.create(WasmRuntime);
    defer testing.allocator.destroy(rt);
    rt.* = try WasmRuntime.init(testing.allocator, &decks, 0);
    defer rt.deinit();
    rt.bind();
    const name = struct {
        fn of(r: *WasmRuntime, slot: WasmRuntime.TraySlot) []const u8 {
            return r.world.get_entity_name(slot.item).?;
        }
    }.of;

    var slots: [WasmRuntime.MAX_TRAY]WasmRuntime.TraySlot = undefined;
    var laid = rt.tray_slots(&slots);
    try testing.expectEqual(@as(usize, 3), laid.len);
    try testing.expectEqualStrings("Lantern", name(rt, laid[0]));

    // An item the script answers on its own is used at once.
    try testing.expectEqual(BrowserActionTag.cue_fired, try rt.click_item(laid[0].item));
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Light.") != null);

    // An item with no use alone goes in hand; a second item combines with it in either order.
    const rope = laid[1].item;
    const hook = laid[2].item;
    try testing.expectEqual(BrowserActionTag.item_selected, try rt.click_item(rope));
    try testing.expectEqual(rope, rt.selected_item);
    try testing.expectEqual(WasmVerb.use_with, rt.active_verb);
    try testing.expectEqual(BrowserActionTag.cue_fired, try rt.click_item(hook));
    try testing.expectEqual(EntityId.none, rt.selected_item);
    laid = rt.tray_slots(&slots);
    try testing.expectEqual(@as(usize, 2), laid.len);
    // Lantern stays first: the order is the order items were named, not the fact arena's.
    try testing.expectEqualStrings("Lantern", name(rt, laid[0]));
    try testing.expectEqualStrings("Grapnel", name(rt, laid[1]));

    // An item in hand used on a person fires Uses(player, item, person).
    try testing.expectEqual(BrowserActionTag.item_selected, try rt.click_item(laid[1].item));
    rt.active_verb = .use_with;
    const pilot = rt.world.lookup_entity("Pilot").?;
    _ = try rt.act_now(pilot, null, rt.selected_item, true);
    try testing.expect(std.mem.indexOf(u8, rt.get_banner(), "Mind my hat.") != null);

    // A full tray of long names fits the desktop's tray (D-097), every box clickable.
    const carries = rt.world.lookup_relation("Carries").?;
    const hero = rt.world.lookup_entity("Hero").?;
    for ([_][]const u8{ "SignalLamp", "LedgerPages", "CopperWire", "BrassKeyRing", "TideChartRoll", "SpareLantern" }) |n| {
        try rt.world.remember(hero, carries, (try rt.world.intern_entity(n)).to_int(), 0);
    }
    laid = rt.tray_slots(&slots);
    try testing.expectEqual(@as(usize, 8), laid.len);
    for (laid) |slot| {
        try testing.expect(slot.x >= renderer.INVENTORY_X and slot.x + slot.w <= CANVAS_WIDTH);
        try testing.expectEqual(slot.item, rt.tray_hit(slot.x + 1, slot.y + 1).?);
    }
}
