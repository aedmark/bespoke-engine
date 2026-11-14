const std = @import("std");
const display_mod = @import("../display.zig");
const audio_mod = @import("../audio.zig");
const save_mod = @import("../save.zig");
const hypervisor_mod = @import("../hypervisor.zig");
const vm_mod = @import("../vm.zig");
const dialogue_mod = @import("../dialogue.zig");
const command_mod = @import("../command.zig");
const state_graph = @import("state_graph.zig");
const font = @import("font.zig");
const text_layout = @import("text_layout.zig");
const dialogue_panel = @import("dialogue_panel.zig");
const beats_mod = @import("beats.zig");

pub const TextLayoutResolver = text_layout.TextLayoutResolver;
pub const TextLabel = text_layout.TextLabel;
pub const LabelPlacement = text_layout.LabelPlacement;
pub const LabelCategory = text_layout.LabelCategory;
pub const LabelPriority = text_layout.LabelPriority;

pub fn to_layout(col: Color) text_layout.Color {
    return .{ .r = col.r, .g = col.g, .b = col.b, .a = col.a };
}

pub const SoundEffectKind = audio_mod.SoundEffectKind;
pub const Sound = audio_mod.Sound;
pub const Soundtrack = audio_mod.Soundtrack;
pub const AudioBridge = audio_mod.AudioBridge;
pub const SaveManager = save_mod.SaveManager;
pub const SaveMetadata = save_mod.SaveMetadata;
pub const SaveSlotInfo = save_mod.SaveSlotInfo;

pub const SaveMenuMode = enum(u8) {
    save = 0,
    load = 1,
    /// The state inspector (P27-01, D-058).
    state = 2,

    /// Tab order: Save, Load, State, then Save again.
    pub fn next(self: SaveMenuMode) SaveMenuMode {
        return switch (self) {
            .save => .load,
            .load => .state,
            .state => .save,
        };
    }
};

pub const SaveDrawerTab = enum(u8) {
    save_mode = 0,
    load_mode = 1,
    resume_game = 2,
    quit_game = 3,
    state_mode = 4,
};

const RenderFrame = display_mod.RenderFrame;
const RenderWaypoint = display_mod.RenderWaypoint;
const RenderHotspot = display_mod.RenderHotspot;
const RenderEntity = display_mod.RenderEntity;
const RenderInventoryItem = display_mod.RenderInventoryItem;
const WaypointId = display_mod.WaypointId;
const EntityId = display_mod.EntityId;

pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

fn sdl_audio_callback(userdata: ?*anyopaque, stream: [*c]u8, len: c_int) callconv(.C) void {
    const bridge: *audio_mod.AudioBridge = @ptrCast(@alignCast(userdata orelse return));
    if (len <= 0) return;
    const sample_count = @divExact(@as(usize, @intCast(len)), @sizeOf(i16));
    const samples = @as([*]i16, @ptrCast(@alignCast(stream)))[0..sample_count];
    bridge.render_samples(samples);
}

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const stage_bg = Color{ .r = 18, .g = 20, .b = 26 };
    pub const stage_floor = Color{ .r = 34, .g = 38, .b = 48 };
    pub const stage_border = Color{ .r = 61, .g = 46, .b = 39 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const panel_border = Color{ .r = 61, .g = 46, .b = 39 };
    pub const path_corridor = Color{ .r = 55, .g = 48, .b = 43 };
    pub const path_edge = Color{ .r = 75, .g = 68, .b = 60 };

    pub const wp_normal = Color{ .r = 100, .g = 116, .b = 139 };
    pub const wp_hover = Color{ .r = 251, .g = 191, .b = 36 };
    pub const wp_target = Color{ .r = 56, .g = 189, .b = 248 };

    pub const item_gold = Color{ .r = 250, .g = 204, .b = 21 }; // Gold

    pub const vortex_purple = Color{ .r = 147, .g = 51, .b = 234 }; // Tangent vortex swirling purple
    pub const countdown_warn = Color{ .r = 239, .g = 68, .b = 68 }; // Emergency red countdown

    pub const hud_bg = Color{ .r = 15, .g = 23, .b = 42, .a = 230 };
    pub const hud_text = Color{ .r = 248, .g = 250, .b = 252 };
    pub const hud_subtext = Color{ .r = 148, .g = 163, .b = 184 };
    pub const status_running = Color{ .r = 34, .g = 197, .b = 94 };
    pub const status_paused = Color{ .r = 245, .g = 158, .b = 11 };
    pub const cue_alert = Color{ .r = 244, .g = 63, .b = 94 };
};

pub const Point = struct {
    x: i32,
    y: i32,
};

/// Classic adventure game interaction verbs (P7-02, D-009).
pub const AdventureVerb = enum(u8) {
    walk = 0,
    look_at = 1,
    talk_to = 2,
    pick_up = 3,
    use_with = 4,

    pub fn label(self: AdventureVerb) []const u8 {
        return switch (self) {
            .walk => "WALK",
            .look_at => "LOOK",
            .talk_to => "TALK",
            .pick_up => "TAKE",
            .use_with => "USE",
        };
    }

    pub fn next(self: AdventureVerb) AdventureVerb {
        const val = @intFromEnum(self);
        return @enumFromInt((val + 1) % 5);
    }
};

pub const UserAction = union(enum) {
    none,
    quit,
    walk_player: WaypointId,
    examine_hotspot: usize, // Hotspot index (P7-01, D-009)
    interact_actor: struct {
        verb: AdventureVerb,
        actor_index: usize,
    },
    interact_hotspot: struct {
        verb: AdventureVerb,
        hotspot_index: usize,
    },
    dialogue_choice: u8, // Index of selected dialogue option (P7-04, D-009)
    dismiss_dialogue,
    toggle_pause,
    step_tick,
    speed_slower,
    speed_faster,
    rewind,
    scrub_to_tick: u64, // Interactive time-travel timeline scrubber (P9-02, D-011)
    repl_command: struct {
        buf: [128]u8,
        len: usize,
    }, // Live interactive REPL console command (P9-03, D-011)
    toggle_debug,
    toggle_console,
    /// A line submitted from the command bar (P26-03, D-057); the host interprets it.
    typed_command: struct {
        buf: [128]u8,
        len: usize,
    },
    /// A key the host bound through its `Theme` (P32-02c, D-039); the value is the binding's
    /// `action`, whose meaning only the host knows.
    custom: u16,
    // P11-03: Two-operand inventory combining & in-hand actions (D-008, D-009, D-013)
    combine_inventory_items: struct {
        primary_index: usize,
        secondary_index: usize,
    },
    use_inventory_on_actor: struct {
        item_index: usize,
        actor_index: usize,
    },
    use_inventory_on_hotspot: struct {
        item_index: usize,
        hotspot_index: usize,
    },
    // P17-03: In-engine Save/Load drawer & quick-save/load actions (D-008, D-011, D-020)
    toggle_save_drawer,
    save_slot: u8,
    load_slot: u8,
    quick_save,
    quick_load,
    // P21-01: Multi-character party coordination & item transfer (D-025)
    switch_party_member: usize,
    transfer_inventory_item: struct {
        item_index: usize,
        target_party_index: usize,
    },
    interact_inventory: struct {
        verb: AdventureVerb,
        item_index: usize,
    },
    // P22-02: Distaff note input for musical drafts (D-029). Degree 0 = C .. 6 = B.
    play_note: u8,
    clear_distaff,
};

pub const DEFAULT_WIDTH: i32 = 1280;
pub const DEFAULT_HEIGHT: i32 = 720;

pub const WAYPOINT_SCREEN_RADIUS = 16;
pub const ACTOR_SCREEN_RADIUS = 18;
pub const HOTSPOT_SCREEN_RADIUS = 22;

/// Maps simulation discrete spatial coordinates to screen canvas coordinates.
pub fn world_to_screen(world_x: i32, world_y: i32, screen_w: i32, screen_h: i32) Point {
    // Proportional scaling: 1280x720 gives wide breathing room while preserving 960x540 coordinates
    const center_x = @divTrunc(screen_w, 2);
    const center_y = @divTrunc(screen_h, 2) + 20;
    const scale_x: i32 = if (screen_w >= 1200) 18 else 14;
    const scale_y: i32 = if (screen_h >= 700) 12 else 10;
    const span_x: i32 = if (screen_w >= 1200) 360 else 280;
    return .{
        .x = center_x - span_x + world_x * scale_x,
        .y = center_y + world_y * scale_y,
    };
}

/// Hit-tests screen coordinates against visible waypoint anchors.
pub fn hit_test_waypoint(
    screen_x: i32,
    screen_y: i32,
    waypoints: []const RenderWaypoint,
    screen_w: i32,
    screen_h: i32,
) ?WaypointId {
    for (waypoints) |wp| {
        const pt = world_to_screen(wp.x, wp.y, screen_w, screen_h);
        const dx: i64 = screen_x - pt.x;
        const dy: i64 = screen_y - pt.y;
        const dist_sq = dx * dx + dy * dy;
        const hit_radius: i64 = WAYPOINT_SCREEN_RADIUS + 14;
        if (dist_sq <= hit_radius * hit_radius) {
            return wp.id;
        }
    }
    return null;
}

/// Finds the nearest waypoint in the active scene to a given screen coordinate.
pub fn find_nearest_waypoint(
    screen_x: i32,
    screen_y: i32,
    waypoints: []const RenderWaypoint,
    screen_w: i32,
    screen_h: i32,
) ?WaypointId {
    if (waypoints.len == 0) return null;
    var nearest_id: ?WaypointId = null;
    var min_dist_sq: i64 = std.math.maxInt(i64);

    for (waypoints) |wp| {
        const pt = world_to_screen(wp.x, wp.y, screen_w, screen_h);
        const dx: i64 = screen_x - pt.x;
        const dy: i64 = screen_y - pt.y;
        const dist_sq = dx * dx + dy * dy;
        if (dist_sq < min_dist_sq) {
            min_dist_sq = dist_sq;
            nearest_id = wp.id;
        }
    }
    return nearest_id;
}

pub const EntityScreenLayout = struct {
    pos: Point,
    label_y: i32,
    status_y: i32,
};

/// Computes screen position and non-overlapping label layout for an entity,
/// applying visual standoff separation and vertical staggering when multiple
/// actors occupy the same waypoint or proximity cluster (D-008, D-012).
pub fn get_entity_screen_layout(
    idx: usize,
    entities: []const RenderEntity,
    screen_w: i32,
    screen_h: i32,
) EntityScreenLayout {
    const base = world_to_screen(entities[idx].x, entities[idx].y, screen_w, screen_h);

    var cluster_rank: usize = 0;
    var cluster_total: usize = 0;

    for (entities, 0..) |other, j| {
        const other_base = world_to_screen(other.x, other.y, screen_w, screen_h);
        const dx = base.x - other_base.x;
        const dy = base.y - other_base.y;
        if (dx * dx + dy * dy < 32 * 32) {
            if (j < idx) cluster_rank += 1;
            cluster_total += 1;
        }
    }

    if (cluster_total <= 1) {
        return .{
            .pos = base,
            .label_y = base.y - ACTOR_SCREEN_RADIUS - 16,
            .status_y = base.y + ACTOR_SCREEN_RADIUS + 4,
        };
    }

    // Distribute entities in the cluster with generous spacing and staggered labels
    if (cluster_total == 2) {
        if (cluster_rank == 0) {
            return .{
                .pos = .{ .x = base.x - 30, .y = base.y + 6 },
                .label_y = base.y - ACTOR_SCREEN_RADIUS - 16,
                .status_y = base.y + ACTOR_SCREEN_RADIUS + 4,
            };
        } else {
            return .{
                .pos = .{ .x = base.x + 30, .y = base.y - 12 },
                .label_y = base.y - ACTOR_SCREEN_RADIUS - 32, // Staggered higher
                .status_y = base.y + ACTOR_SCREEN_RADIUS + 18, // Staggered lower
            };
        }
    } else {
        // 3 or more: fan out horizontally and vertically
        const offset: i32 = @as(i32, @intCast(cluster_rank)) * 36 - @as(i32, @intCast(cluster_total - 1)) * 18;
        const y_offset: i32 = if (cluster_rank % 2 == 1) -14 else 6;
        const label_offset: i32 = if (cluster_rank % 2 == 1) -32 else -16;
        const status_offset: i32 = if (cluster_rank % 2 == 1) 18 else 4;
        return .{
            .pos = .{ .x = base.x + offset, .y = base.y + y_offset },
            .label_y = base.y - ACTOR_SCREEN_RADIUS + label_offset,
            .status_y = base.y + ACTOR_SCREEN_RADIUS + status_offset,
        };
    }
}

pub fn get_entity_screen_pos(
    idx: usize,
    entities: []const RenderEntity,
    screen_w: i32,
    screen_h: i32,
) Point {
    return get_entity_screen_layout(idx, entities, screen_w, screen_h).pos;
}

/// Hit-tests screen coordinates against visible actors (P7-02).
pub fn hit_test_actor(
    screen_x: i32,
    screen_y: i32,
    entities: []const RenderEntity,
    screen_w: i32,
    screen_h: i32,
) ?usize {
    for (entities, 0..) |_, idx| {
        const pt = get_entity_screen_pos(idx, entities, screen_w, screen_h);
        const dx: i64 = screen_x - pt.x;
        const dy: i64 = screen_y - pt.y;
        const dist_sq = dx * dx + dy * dy;
        const hit_radius: i64 = ACTOR_SCREEN_RADIUS + 8;
        if (dist_sq <= hit_radius * hit_radius) {
            return idx;
        }
    }
    return null;
}

/// Hit-tests screen coordinates against visible scene hotspots (P7-01, D-009).
pub fn hit_test_hotspot(
    screen_x: i32,
    screen_y: i32,
    hotspots: []const RenderHotspot,
    screen_w: i32,
    screen_h: i32,
) ?usize {
    for (hotspots, 0..) |hs, idx| {
        const pt = world_to_screen(hs.x, hs.y, screen_w, screen_h);
        const dx: i64 = screen_x - pt.x;
        const dy: i64 = screen_y - pt.y;
        const dist_sq = dx * dx + dy * dy;
        const hit_radius: i64 = HOTSPOT_SCREEN_RADIUS + 8;
        if (dist_sq <= hit_radius * hit_radius) {
            return idx;
        }
    }
    return null;
}

/// Hit-tests screen coordinates against the 5 classic adventure verb buttons (P7-02).
pub fn hit_test_verb_button(screen_x: i32, screen_y: i32, screen_h: i32) ?AdventureVerb {
    const y_start = screen_h - 78;
    const btn_h = 26;
    const btn_w = 68;
    const spacing = 6;

    if (screen_y < y_start or screen_y > y_start + btn_h) return null;

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const btn_x = 20 + @as(i32, @intCast(i)) * (btn_w + spacing);
        if (screen_x >= btn_x and screen_x <= btn_x + btn_w) {
            return @enumFromInt(@as(u8, @intCast(i)));
        }
    }
    return null;
}

/// Hit-tests screen coordinates against visible inventory tray items (P7-03, D-007).
pub fn hit_test_inventory_item(screen_x: i32, screen_y: i32, screen_h: i32, inventory: []const RenderInventoryItem) ?usize {
    const bar_y = screen_h - 78;
    if (screen_y < bar_y or screen_y > bar_y + 26) return null;

    var cur_x: i32 = 480;
    for (inventory, 0..) |item, idx| {
        const iname = item.get_name();
        const iw = font.text_width(iname, 2) + 24;
        if (screen_x >= cur_x and screen_x <= cur_x + iw) {
            return idx;
        }
        cur_x += iw + 8;
    }
    return null;
}

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn contains(self: Rect, px: i32, py: i32) bool {
        return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h;
    }
};

// --- Distaff Staff HUD Geometry (P22-02, D-029) ---
// The panel sits above the verb bar on the right, clear of the verb buttons and the
// inventory tray row (both at screen_h - 78), so enabling the distaff never hides them.

pub const DISTAFF_NOTE_NAMES = [7][]const u8{ "C", "D", "E", "F", "G", "A", "B" };
const DISTAFF_PANEL_W: i32 = 336;
const DISTAFF_PANEL_H: i32 = 124;
const DISTAFF_BUTTON_W: i32 = 40;
const DISTAFF_BUTTON_H: i32 = 22;
const DISTAFF_BUTTON_STEP: i32 = 46;
/// Vertical gap between staff positions (one diatonic step) in pixels.
const DISTAFF_STEP_PX: i32 = 4;

pub fn get_distaff_panel_rect(screen_w: i32, screen_h: i32) Rect {
    return .{
        .x = screen_w - DISTAFF_PANEL_W - 14,
        .y = screen_h - 78 - 12 - DISTAFF_PANEL_H,
        .w = DISTAFF_PANEL_W,
        .h = DISTAFF_PANEL_H,
    };
}

pub fn get_distaff_note_button_rect(degree: u8, panel: Rect) Rect {
    return .{
        .x = panel.x + 10 + @as(i32, degree) * DISTAFF_BUTTON_STEP,
        .y = panel.y + panel.h - DISTAFF_BUTTON_H - 8,
        .w = DISTAFF_BUTTON_W,
        .h = DISTAFF_BUTTON_H,
    };
}

/// Y of the staff's bottom line (E4) inside the panel. Treble staff: lines are E G B D F.
fn distaff_staff_bottom(panel: Rect) i32 {
    return panel.y + 58;
}

/// Y of a notehead for a degree: E4 sits on the bottom line, C4 on a ledger line below.
pub fn get_distaff_note_y(degree: u8, panel: Rect) i32 {
    return distaff_staff_bottom(panel) - (@as(i32, degree) - 2) * DISTAFF_STEP_PX;
}

/// Returns the note degree under the cursor, or null. Notes beyond `reach` are not hit.
pub fn hit_test_distaff_note(mouse_x: i32, mouse_y: i32, screen_w: i32, screen_h: i32, reach: u8) ?u8 {
    const panel = get_distaff_panel_rect(screen_w, screen_h);
    if (!panel.contains(mouse_x, mouse_y)) return null;
    var d: u8 = 0;
    while (d < @min(reach, 7)) : (d += 1) {
        if (get_distaff_note_button_rect(d, panel).contains(mouse_x, mouse_y)) return d;
    }
    return null;
}

/// Maps the letter keys C D E F G A B to note degrees while the distaff is active.
/// These letters shadow the global d (debug) and c (console) shortcuts only in that mode;
/// F1 and the backquote remain available for both.
pub fn distaff_key_to_degree(sym: c.SDL_Keycode) ?u8 {
    return switch (sym) {
        c.SDLK_c => 0,
        c.SDLK_d => 1,
        c.SDLK_e => 2,
        c.SDLK_f => 3,
        c.SDLK_g => 4,
        c.SDLK_a => 5,
        c.SDLK_b => 6,
        else => null,
    };
}

/// Computes screen bounding box for a party member portrait button (P21-01, D-025).
pub fn get_party_portrait_rect(idx: usize, party_count: usize, screen_w: i32) Rect {
    const slot_w: i32 = 88;
    const slot_h: i32 = 30;
    const total_w: i32 = @as(i32, @intCast(party_count)) * (slot_w + 8);
    const start_x: i32 = screen_w - 20 - total_w;
    const rx: i32 = start_x + @as(i32, @intCast(idx)) * (slot_w + 8);
    const ry: i32 = 8;
    return .{ .x = rx, .y = ry, .w = slot_w, .h = slot_h };
}

/// Hit-tests mouse coordinates against registered party member portraits (P21-01, D-025).
pub fn hit_test_party_portrait(mouse_x: i32, mouse_y: i32, party_count: usize, screen_w: i32) ?usize {
    if (party_count <= 1) return null;
    for (0..party_count) |i| {
        const r = get_party_portrait_rect(i, party_count, screen_w);
        if (mouse_x >= r.x and mouse_x <= r.x + r.w and mouse_y >= r.y and mouse_y <= r.y + r.h) {
            return i;
        }
    }
    return null;
}

/// Active speech balloon or branching dialogue tree (P7-04, P13-03, D-009, D-015).
pub const SpeechBalloon = struct {
    speaker: EntityId,
    speaker_pos: Point,
    /// The speaker's display name (D-077: `HarbourWarden` is stored as `Harbour Warden`).
    speaker_name: [32]u8,
    speaker_name_len: u8,
    text: [160]u8,
    text_len: u8,
    ticks_remaining: u32,
    choices: [9][160]u8,
    choice_lens: [9]u8,
    choice_count: u8,
    scroll_offset: u8 = 0,

    pub fn get_speaker_name(self: *const SpeechBalloon) []const u8 {
        return self.speaker_name[0..self.speaker_name_len];
    }

    pub fn get_text(self: *const SpeechBalloon) []const u8 {
        return self.text[0..self.text_len];
    }

    pub fn get_choice(self: *const SpeechBalloon, idx: usize) []const u8 {
        if (idx >= self.choice_count) return "";
        return self.choices[idx][0..self.choice_lens[idx]];
    }

    pub fn visible_choice_count(self: *const SpeechBalloon) u8 {
        if (self.choice_count <= 6) return self.choice_count;
        return 6;
    }

    pub fn max_scroll_offset(self: *const SpeechBalloon) u8 {
        if (self.choice_count <= 6) return 0;
        return self.choice_count - 6;
    }
};

/// Where the dialogue panel sits and how its rows fall (D-077, D-084). The panel is centred
/// above the action sentence and verb bar (and the command bar when it shows), as wide as its
/// widest row, and grows upward with its wrapped rows.
pub const DialoguePanel = struct {
    rect: c.SDL_Rect,
    layout: dialogue_panel.Layout,
    /// Width of the scroll bar along the right edge when more than six choices are offered;
    /// 0 otherwise.
    scrollbar_w: i32,
};

/// The scroll bar's width; its thumb shows which of the choices are in view.
pub const SCROLLBAR_W: i32 = 14;

fn centred_panel(l: dialogue_panel.Layout, scrollbar_w: i32, screen_w: i32, screen_h: i32, command_bar: bool) DialoguePanel {
    const w = l.width + scrollbar_w;
    const bottom = screen_h - 110 - (if (command_bar) @as(i32, 28) else 0);
    return .{
        .rect = .{ .x = @divTrunc(screen_w - w, 2), .y = @max(76, bottom - l.height), .w = w, .h = l.height },
        .layout = l,
        .scrollbar_w = scrollbar_w,
    };
}

pub fn get_dialogue_panel(balloon: *const SpeechBalloon, screen_w: i32, screen_h: i32, command_bar: bool) DialoguePanel {
    var metrics = dialogue_panel.Metrics.desktop;
    metrics.width = screen_w - 40;
    var visible: [dialogue_panel.MAX_CHOICES][]const u8 = undefined;
    const count = balloon.visible_choice_count();
    for (0..count) |i| visible[i] = balloon.get_choice(balloon.scroll_offset + i);
    var l = dialogue_panel.layout(metrics, balloon.get_speaker_name(), balloon.get_text(), visible[0..count]);
    // Width from every choice, not only those in view, so scrolling never resizes the panel.
    var all: [dialogue_panel.MAX_CHOICES][]const u8 = undefined;
    for (0..balloon.choice_count) |i| all[i] = balloon.get_choice(i);
    l.width = dialogue_panel.layout(metrics, balloon.get_speaker_name(), balloon.get_text(), all[0..balloon.choice_count]).width;
    return centred_panel(l, if (balloon.choice_count > 6) SCROLLBAR_W else 0, screen_w, screen_h, command_bar);
}

/// Where a click-through message sits (D-080): centred like the dialogue panel, holding the
/// speaker, the text, and the continue hint.
pub fn get_message_panel(beat: *const beats_mod.Beat, screen_w: i32, screen_h: i32, command_bar: bool) DialoguePanel {
    var metrics = dialogue_panel.Metrics.desktop;
    metrics.width = screen_w - 40;
    const l = dialogue_panel.layout_message(metrics, beat.speaker(), beat.text(), beats_mod.HINT);
    return centred_panel(l, 0, screen_w, screen_h, command_bar);
}

/// The choice under the mouse, as an index into all of the balloon's choices.
pub fn hit_test_dialogue_panel(mouse_x: i32, mouse_y: i32, balloon: *const SpeechBalloon, panel: *const DialoguePanel) ?u8 {
    if (balloon.choice_count == 0) return null;
    const visible = panel.layout.hit(mouse_x - panel.rect.x, mouse_y - panel.rect.y, panel.rect.w) orelse return null;
    return balloon.scroll_offset + visible;
}

/// Computes screen bounding rectangle for the Pause & Save/Load Drawer modal (P17-03, D-020).
pub fn get_save_drawer_rect(screen_w: i32, screen_h: i32) c.SDL_Rect {
    const w = @min(760, screen_w - 40);
    const h = @min(500, screen_h - 60);
    return c.SDL_Rect{
        .x = @divTrunc(screen_w - w, 2),
        .y = @divTrunc(screen_h - h, 2),
        .w = w,
        .h = h,
    };
}

/// Computes screen bounding rectangle for a specific save slot card (0..8) inside the drawer (P17-03, D-020).
pub fn get_save_slot_rect(slot_id: u8, drawer_rect: c.SDL_Rect) c.SDL_Rect {
    if (slot_id == 0) {
        return c.SDL_Rect{
            .x = drawer_rect.x + 20,
            .y = drawer_rect.y + 82,
            .w = drawer_rect.w - 40,
            .h = 62,
        };
    }
    const idx = slot_id - 1;
    const col: i32 = @intCast(idx % 2);
    const row: i32 = @intCast(idx / 2);
    const card_w = @divTrunc(drawer_rect.w - 52, 2);
    const card_h: i32 = 72;
    return c.SDL_Rect{
        .x = drawer_rect.x + 20 + col * (card_w + 12),
        .y = drawer_rect.y + 154 + row * (card_h + 8),
        .w = card_w,
        .h = card_h,
    };
}

/// Hit-tests mouse coordinates against all 9 save slot cards (Slot 0 Quick-Save and Slots 1..8) (P17-03).
pub fn hit_test_save_slot(mouse_x: i32, mouse_y: i32, drawer_rect: c.SDL_Rect) ?u8 {
    var slot_id: u8 = 0;
    while (slot_id <= save_mod.MAX_SLOTS) : (slot_id += 1) {
        const srect = get_save_slot_rect(slot_id, drawer_rect);
        if (mouse_x >= srect.x and mouse_x <= srect.x + srect.w and
            mouse_y >= srect.y and mouse_y <= srect.y + srect.h)
        {
            return slot_id;
        }
    }
    return null;
}

/// Hit-tests mouse coordinates against the top tab buttons inside the Save/Load drawer (P17-03).
pub fn hit_test_save_drawer_tab(mouse_x: i32, mouse_y: i32, drawer_rect: c.SDL_Rect) ?SaveDrawerTab {
    const tab_y = drawer_rect.y + 42;
    const tab_h: i32 = 28;
    if (mouse_y < tab_y or mouse_y > tab_y + tab_h) return null;

    if (mouse_x >= drawer_rect.x + 20 and mouse_x <= drawer_rect.x + 170) return .save_mode;
    if (mouse_x >= drawer_rect.x + 180 and mouse_x <= drawer_rect.x + 330) return .load_mode;
    if (mouse_x >= drawer_rect.x + 340 and mouse_x <= drawer_rect.x + 470) return .state_mode;
    if (mouse_x >= drawer_rect.x + drawer_rect.w - 270 and mouse_x <= drawer_rect.x + drawer_rect.w - 140) return .resume_game;
    if (mouse_x >= drawer_rect.x + drawer_rect.w - 130 and mouse_x <= drawer_rect.x + drawer_rect.w - 20) return .quit_game;
    return null;
}

/// How many earlier focuses Backspace can return to (D-059); the oldest drops off first.
pub const INSPECTOR_HISTORY: usize = 8;

/// Where the inspector draws inside the drawer. Drawing and mouse hit tests share it, so a
/// click lands on the node the player sees.
const InspectorGeometry = struct {
    area_x: i32,
    top: i32,
    area_w: i32,
    area_h: i32,
    graph_w: i32,
    cx: i32,
    cy: i32,
    rx: i32,
    ry: i32,
};

fn inspector_geometry(drect: c.SDL_Rect) InspectorGeometry {
    const top = drect.y + 82;
    const area_x = drect.x + 16;
    const area_w = drect.w - 32;
    const area_h = drect.y + drect.h - 12 - top;
    const graph_w = @divTrunc(area_w * 62, 100);
    return .{
        .area_x = area_x,
        .top = top,
        .area_w = area_w,
        .area_h = area_h,
        .graph_w = graph_w,
        .cx = area_x + @divTrunc(graph_w, 2),
        .cy = top + @divTrunc(area_h - 20, 2),
        .rx = @divTrunc(graph_w, 2) - 70,
        .ry = @divTrunc(area_h - 20, 2) - 34,
    };
}

/// State inspector colours (D-058 point 3).
const INSPECTOR_ACCENT = Color{ .r = 56, .g = 189, .b = 248 };
const INSPECTOR_BELIEF = Color{ .r = 192, .g = 132, .b = 252 };

fn band_color(b: state_graph.Band) Color {
    return switch (b) {
        .permanent => Color.hud_text,
        .fresh => Color.status_running,
        .waning => Color{ .r = 245, .g = 158, .b = 11 },
        .ending => Color.cue_alert,
        .expired => Color{ .r = 100, .g = 116, .b = 139 },
    };
}

/// The SDL2 peripheral window consumer (D-001, D-008, P6-01 through P6-04).
/// A prop the theme may draw: one hotspot of the frame, where it sits on screen, and the
/// label resolver for any text the theme attaches to it.
pub const PropView = struct {
    hotspot: *const display_mod.RenderHotspot,
    index: usize,
    pos: Point,
    hovered: bool,
    labels: *TextLayoutResolver,
};

/// An actor the theme may draw: one entity of the frame and its screen layout.
pub const ActorView = struct {
    entity: *const display_mod.RenderEntity,
    index: usize,
    layout: EntityScreenLayout,
    labels: *TextLayoutResolver,
};

/// A key a host binds (P32-02c). Pressing it returns `UserAction{ .custom = action }` from
/// `poll_events`, after playing `sfx` if set. Keys are SDL keycodes (`c.SDLK_*`).
pub const KeyBinding = struct {
    key: c.SDL_Keycode,
    action: u16,
    sfx: ?audio_mod.Sound = null,
};

/// One line of key hints for the bottom bar.
pub const FooterHint = struct {
    text: []const u8,
    color: Color = Color.hud_subtext,
};

/// A host's presentation, called by `render_frame` (P32-02b, D-039). Every callback is
/// optional. A drawing callback returns true when it drew the thing; false hands it back to
/// the engine's neutral default (a plain stage, a box for a prop, a labelled disc for an
/// actor, a corridor line for a walkway). The engine names no scene, prop, or character:
/// a game's look lives entirely behind this struct.
pub const Theme = struct {
    backdrop: ?*const fn (*DisplayWindow, *const RenderFrame) bool = null,
    prop: ?*const fn (*DisplayWindow, *const RenderFrame, PropView) bool = null,
    actor: ?*const fn (*DisplayWindow, *const RenderFrame, ActorView) bool = null,
    /// Draws the stretch of walkway between two connected marks.
    walkway: ?*const fn (*DisplayWindow, *const RenderFrame, Point, Point) bool = null,
    /// False hides walkways and mark discs for the frame (a scene without visible paths).
    shows_walkways: ?*const fn (*const RenderFrame) bool = null,
    footer: ?*const fn (*const RenderFrame) ?FooterHint = null,
    /// Draws the host's HUD elements after the top status bar (P32-03b).
    hud: ?*const fn (*DisplayWindow, *const RenderFrame) void = null,
    /// Draws full-window overlays last, above the save drawer (P32-03b).
    overlay: ?*const fn (*DisplayWindow, *const RenderFrame) void = null,
    /// Colours for save-slot thumbnails, given to the window's save manager with the theme.
    thumbnails: ?*const save_mod.ThumbnailPainter = null,
    /// Keys the host handles itself, checked before the engine's own keys.
    keys: []const KeyBinding = &.{},
    /// The game's music and effects, registered with the window's audio when the theme is set.
    soundtrack: ?*const audio_mod.Soundtrack = null,
};

pub const DisplayWindow = struct {
    /// The host's presentation; null draws the engine's neutral defaults. Borrowed: the theme
    /// must outlive the window.
    theme: ?*const Theme = null,
    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,
    /// Set only by `init_offscreen`: the memory surface the software renderer draws into.
    offscreen_surface: ?*c.SDL_Surface = null,
    width: i32,
    height: i32,
    active_verb: AdventureVerb = .walk,
    hovered_wp: ?WaypointId = null,
    hovered_hotspot: ?usize = null,
    hovered_actor: ?usize = null,
    hovered_party_member: ?usize = null,
    target_wp: ?WaypointId = null,
    active_balloon: ?SpeechBalloon = null,
    /// Click-through messages (D-080). While any waits, it covers the dialogue panel and the
    /// panel's choices can be neither seen nor answered.
    messages: beats_mod.Beats = .{},
    balloon_revision: u32 = 0,
    balloon_from_frame: bool = false,
    hovered_choice: ?u8 = null,
    is_headless: bool = false,
    audio_bridge: *audio_mod.AudioBridge,
    audio_device_opened: bool = false,
    cue_banner_text: [256]u8 = undefined,
    cue_banner_len: usize = 0,
    cue_banner_ticks: u32 = 0,
    // Phase 11 Inventory In-Hand Selection & Combining (P11-03, D-013)
    selected_inventory_item: ?usize = null,
    // Phase 9 Debug, Scrubber & REPL (P9-01, P9-02, P9-03, D-011)
    show_debug_overlay: bool = false,
    show_console: bool = false,
    /// The entity the state inspector centres on; null picks the best-connected one (D-058).
    inspector_focus: ?display_mod.EntityId = null,
    /// State inspector navigation (P27-03, D-059): window state only, never World, so moving
    /// around the graph cannot change the simulation or a save. The selected ring index is
    /// clamped against each frame's layout, because a tick or restore can shrink the ring.
    inspector_selected: usize = 0,
    inspector_history: [INSPECTOR_HISTORY]display_mod.EntityId = undefined,
    inspector_history_len: usize = 0,
    inspector_filter: state_graph.Filter = .{},
    /// Typed-command bar (P26-03, D-057). Off unless the host enables it; while focused, every
    /// key is text, so no engine or host binding fires.
    command_bar_enabled: bool = false,
    command_bar_focused: bool = false,
    command_input: [128]u8 = undefined,
    command_len: usize = 0,
    command_history: [8][128]u8 = undefined,
    command_history_lens: [8]usize = [_]usize{0} ** 8,
    command_history_count: usize = 0,
    /// Index into the history while Up/Down browse it; null when editing a fresh line.
    command_history_cursor: ?usize = null,
    /// Words Tab may complete, refreshed by the host from what is in scope.
    command_words: command_mod.WordList = .{},
    console_input: [128]u8 = undefined,
    console_len: usize = 0,
    console_history: [5][128]u8 = undefined,
    console_history_lens: [5]usize = [_]usize{0} ** 5,
    console_history_count: usize = 0,
    // Phase 17 In-Engine Save/Load Drawer & Pause Menu Overlay (P17-03, D-020)
    show_save_drawer: bool = false,
    save_menu_mode: SaveMenuMode = .save,
    hovered_save_slot: ?u8 = null,
    selected_save_slot: u8 = 1,
    owned_save_manager: *save_mod.SaveManager,
    save_manager: *save_mod.SaveManager,
    // Phase 26/D-028 Master Simulation Clock Pacing & Speed Scaling
    current_tick_interval_ms: i64 = vm_mod.DEFAULT_TICK_INTERVAL_MS,

    pub fn init(title: [:0]const u8, width: i32, height: i32) !DisplayWindow {
        const bridge = try std.heap.c_allocator.create(audio_mod.AudioBridge);
        bridge.* = audio_mod.AudioBridge.init();

        const sm = try std.heap.c_allocator.create(save_mod.SaveManager);
        sm.* = try save_mod.SaveManager.init(std.heap.c_allocator, "saves");

        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) != 0) {
            if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
                // Graceful fallback to headless if no display server is available
                return DisplayWindow{
                    .window = null,
                    .renderer = null,
                    .width = width,
                    .height = height,
                    .is_headless = true,
                    .audio_bridge = bridge,
                    .audio_device_opened = false,
                    .owned_save_manager = sm,
                    .save_manager = sm,
                    .current_tick_interval_ms = vm_mod.DEFAULT_TICK_INTERVAL_MS,
                };
            }
        }

        const window = c.SDL_CreateWindow(
            title.ptr,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            width,
            height,
            c.SDL_WINDOW_SHOWN,
        ) orelse {
            c.SDL_Quit();
            return DisplayWindow{
                .window = null,
                .renderer = null,
                .width = width,
                .height = height,
                .is_headless = true,
                .audio_bridge = bridge,
                .audio_device_opened = false,
                .owned_save_manager = sm,
                .save_manager = sm,
            };
        };

        const renderer = c.SDL_CreateRenderer(
            window,
            -1,
            c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
        ) orelse {
            c.SDL_DestroyWindow(window);
            c.SDL_Quit();
            return DisplayWindow{
                .window = null,
                .renderer = null,
                .width = width,
                .height = height,
                .is_headless = true,
                .audio_bridge = bridge,
                .audio_device_opened = false,
                .owned_save_manager = sm,
                .save_manager = sm,
            };
        };

        _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

        var audio_opened = false;
        var desired = std.mem.zeroes(c.SDL_AudioSpec);
        desired.freq = 44100;
        desired.format = c.AUDIO_S16LSB;
        desired.channels = 2;
        desired.samples = 1024;
        desired.callback = sdl_audio_callback;
        desired.userdata = bridge;

        var obtained: c.SDL_AudioSpec = undefined;
        if (c.SDL_OpenAudio(&desired, &obtained) == 0) {
            audio_opened = true;
            bridge.audio_enabled = true;
            c.SDL_PauseAudio(0);
        }

        return DisplayWindow{
            .window = window,
            .renderer = renderer,
            .width = width,
            .height = height,
            .is_headless = false,
            .audio_bridge = bridge,
            .audio_device_opened = audio_opened,
            .owned_save_manager = sm,
            .save_manager = sm,
            .current_tick_interval_ms = vm_mod.DEFAULT_TICK_INTERVAL_MS,
        };
    }

    /// Creates a window that draws into memory with SDL's software rasterizer (P32-02a). It
    /// needs no display server and opens no audio device, and the same frame always produces
    /// the same pixels, which is what lets tests compare `frame_hash` with a committed value.
    pub fn init_offscreen(width: i32, height: i32) !DisplayWindow {
        const bridge = try std.heap.c_allocator.create(audio_mod.AudioBridge);
        errdefer std.heap.c_allocator.destroy(bridge);
        bridge.* = audio_mod.AudioBridge.init();

        const sm = try std.heap.c_allocator.create(save_mod.SaveManager);
        errdefer std.heap.c_allocator.destroy(sm);
        sm.* = try save_mod.SaveManager.init(std.heap.c_allocator, "saves");
        errdefer sm.deinit();

        const surface = c.SDL_CreateRGBSurfaceWithFormat(0, width, height, 32, c.SDL_PIXELFORMAT_ARGB8888) orelse
            return error.OffscreenSurfaceFailed;
        errdefer c.SDL_FreeSurface(surface);
        const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.OffscreenRendererFailed;
        _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

        return DisplayWindow{
            .window = null,
            .renderer = renderer,
            .offscreen_surface = surface,
            .width = width,
            .height = height,
            .is_headless = false,
            .audio_bridge = bridge,
            .audio_device_opened = false,
            .owned_save_manager = sm,
            .save_manager = sm,
            .current_tick_interval_ms = vm_mod.DEFAULT_TICK_INTERVAL_MS,
        };
    }

    /// Hash of the pixels last drawn by `render_frame`, for an offscreen window; null otherwise.
    /// Rows are hashed without their padding, so the value depends only on what was drawn.
    pub fn frame_hash(self: *const DisplayWindow) ?u64 {
        const surface = self.offscreen_surface orelse return null;
        const pixels: [*]const u8 = @ptrCast(surface.*.pixels orelse return null);
        const pitch: usize = @intCast(surface.*.pitch);
        const row_bytes: usize = @as(usize, @intCast(self.width)) * 4;
        var hasher = std.hash.Wyhash.init(0);
        var y: usize = 0;
        while (y < @as(usize, @intCast(self.height))) : (y += 1) {
            hasher.update(pixels[y * pitch ..][0..row_bytes]);
        }
        return hasher.final();
    }

    /// Writes the last offscreen frame as a BMP, for looking at a frame whose hash changed.
    pub fn save_frame_bmp(self: *const DisplayWindow, path: [:0]const u8) !void {
        const surface = self.offscreen_surface orelse return error.NotOffscreen;
        const rw = c.SDL_RWFromFile(path.ptr, "wb") orelse return error.BmpOpenFailed;
        if (c.SDL_SaveBMP_RW(surface, rw, 1) != 0) return error.BmpWriteFailed;
    }

    pub fn deinit(self: *DisplayWindow) void {
        if (self.audio_device_opened) {
            c.SDL_CloseAudio();
            self.audio_device_opened = false;
        }
        std.heap.c_allocator.destroy(self.audio_bridge);
        self.owned_save_manager.deinit();
        std.heap.c_allocator.destroy(self.owned_save_manager);

        if (!self.is_headless) {
            if (self.renderer) |r| c.SDL_DestroyRenderer(r);
            if (self.offscreen_surface) |surface| {
                // An offscreen window never called SDL_Init, so there is nothing to quit.
                c.SDL_FreeSurface(surface);
                return;
            }
            if (self.window) |w| c.SDL_DestroyWindow(w);
            c.SDL_Quit();
        }
    }

    pub fn set_theme(self: *DisplayWindow, theme: ?*const Theme) void {
        self.theme = theme;
        self.audio_bridge.set_soundtrack(if (theme) |t| t.soundtrack else null);
        self.save_manager.thumbnails = if (theme) |t| t.thumbnails else null;
    }

    /// The stage drawn when no theme draws a backdrop: a cleared background and one framed
    /// floor area titled with the scene's name.
    fn render_default_backdrop(self: *DisplayWindow, frame: *const RenderFrame) void {
        self.fill_rect(0, 0, self.width, self.height, Color.stage_bg);
        const x: i32 = 100;
        const y: i32 = 120;
        const w: i32 = self.width - 200;
        const h: i32 = 320;
        self.fill_rect(x, y, w, h, Color.stage_floor);
        self.draw_rect_outline(x, y, w, h, Color.stage_border);
        const scene = frame.get_current_scene();
        if (scene.len > 0) self.draw_text(scene, x + 16, y + 16, 2, Color.hud_subtext);
    }

    /// Attaches an external SaveManager instance to this window (P17-03, D-020).
    pub fn attach_save_manager(self: *DisplayWindow, sm: *save_mod.SaveManager) void {
        self.save_manager = sm;
    }

    /// Executes persistent save/load user actions against the active SaveManager (P17-02, P17-03, D-020).
    pub fn handle_save_action(
        self: *DisplayWindow,
        action: UserAction,
        world: *save_mod.World,
        spatial: *save_mod.SpatialSystem,
        vm: *save_mod.VM,
        display_bridge: *display_mod.DisplayBridge,
        is_paused: *bool,
    ) bool {
        return self.handle_save_action_with_temporal(action, world, spatial, vm, display_bridge, is_paused, null);
    }

    /// Executes save/load actions, carrying the hypervisor envelope when the session has one (P31-04, D-048).
    /// The save drawer needs the hypervisor so a temporal save cannot be restored without its branch.
    pub fn handle_save_action_with_temporal(
        self: *DisplayWindow,
        action: UserAction,
        world: *save_mod.World,
        spatial: *save_mod.SpatialSystem,
        vm: *save_mod.VM,
        display_bridge: *display_mod.DisplayBridge,
        is_paused: *bool,
        temporal: ?*hypervisor_mod.TemporalHypervisor,
    ) bool {
        switch (action) {
            .toggle_save_drawer => {
                if (self.show_save_drawer) {
                    is_paused.* = true;
                }
                return true;
            },
            .quick_save => {
                const saved = if (temporal) |hypervisor|
                    self.save_manager.quick_save_with_temporal(world, spatial, vm, hypervisor)
                else
                    self.save_manager.quick_save(world, spatial, vm);
                if (saved) |meta| {
                    var buf: [128]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "★ Quick-Saved state ({s}, Tick {d}) ★", .{ meta.get_scene_name(), meta.current_tick }) catch "Quick-Saved!";
                    self.set_cue_banner(msg, 120);
                    self.play_sfx(.combine);
                    self.show_save_drawer = false;
                } else |_| {
                    self.set_cue_banner("Failed to Quick-Save state.", 90);
                    self.play_sfx(.click);
                }
                return true;
            },
            .quick_load => {
                const loaded = if (temporal) |hypervisor|
                    self.save_manager.quick_load_with_temporal(world, spatial, vm, hypervisor)
                else
                    self.save_manager.quick_load(world, spatial, vm);
                if (loaded) |res| {
                    is_paused.* = true;
                    display_bridge.capture_frame(world, spatial, vm);
                    display_bridge.swap();
                    var buf: [128]u8 = undefined;
                    const msg = if (res.recovered_from_backup)
                        std.fmt.bufPrint(&buf, "⚠ Primary corrupted! Recovered Quick-Save (.bak) at Tick {d}!", .{res.metadata.current_tick}) catch "Recovered Quick-Save!"
                    else
                        std.fmt.bufPrint(&buf, "<<< Quick-Loaded ({s}, Tick {d}) [PAUSED] <<<", .{ res.metadata.get_scene_name(), res.metadata.current_tick }) catch "Quick-Loaded!";
                    self.set_cue_banner(msg, 120);
                    self.play_sfx(.alert);
                    self.show_save_drawer = false;
                } else |_| {
                    self.set_cue_banner("No valid Quick-Save found to load.", 90);
                    self.play_sfx(.click);
                }
                return true;
            },
            .save_slot => |slot_id| {
                const desc = if (slot_id == 0) "Quick Save" else "Manual Slot Save";
                const saved = if (temporal) |hypervisor|
                    self.save_manager.save_slot_with_temporal(slot_id, world, spatial, vm, hypervisor, desc)
                else
                    self.save_manager.save_slot(slot_id, world, spatial, vm, desc);
                if (saved) |meta| {
                    var buf: [128]u8 = undefined;
                    const msg = if (slot_id == 0)
                        std.fmt.bufPrint(&buf, "★ Saved Quick-Save Slot ({s}, Tick {d}) ★", .{ meta.get_scene_name(), meta.current_tick }) catch "Saved!"
                    else
                        std.fmt.bufPrint(&buf, "★ Saved Slot #{d} ({s}, Tick {d}) ★", .{ slot_id, meta.get_scene_name(), meta.current_tick }) catch "Saved Slot!";
                    self.set_cue_banner(msg, 120);
                    self.play_sfx(.combine);
                    self.show_save_drawer = false;
                } else |_| {
                    self.set_cue_banner("Failed to save slot.", 90);
                    self.play_sfx(.click);
                }
                return true;
            },
            .load_slot => |slot_id| {
                const loaded = if (temporal) |hypervisor|
                    self.save_manager.load_slot_with_temporal(slot_id, world, spatial, vm, hypervisor)
                else
                    self.save_manager.load_slot(slot_id, world, spatial, vm);
                if (loaded) |res| {
                    is_paused.* = true;
                    display_bridge.capture_frame(world, spatial, vm);
                    display_bridge.swap();
                    var buf: [128]u8 = undefined;
                    const msg = if (res.recovered_from_backup)
                        std.fmt.bufPrint(&buf, "⚠ Slot #{d} corrupted! Recovered from .bak at Tick {d}!", .{ slot_id, res.metadata.current_tick }) catch "Recovered from backup!"
                    else if (slot_id == 0)
                        std.fmt.bufPrint(&buf, "<<< Loaded Quick-Save ({s}, Tick {d}) [PAUSED] <<<", .{ res.metadata.get_scene_name(), res.metadata.current_tick }) catch "Loaded!"
                    else
                        std.fmt.bufPrint(&buf, "<<< Loaded Slot #{d} ({s}, Tick {d}) [PAUSED] <<<", .{ slot_id, res.metadata.get_scene_name(), res.metadata.current_tick }) catch "Loaded Slot!";
                    self.set_cue_banner(msg, 120);
                    self.play_sfx(.alert);
                    self.show_save_drawer = false;
                } else |_| {
                    var buf: [96]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "Slot #{d} is empty or unrecoverable.", .{slot_id}) catch "Empty slot.";
                    self.set_cue_banner(msg, 90);
                    self.play_sfx(.click);
                }
                return true;
            },
            else => return false,
        }
    }

    /// Plays a procedural action sound effect asynchronously (P16-02, D-019).
    pub fn play_sfx(self: *DisplayWindow, kind: audio_mod.SoundEffectKind) void {
        self.audio_bridge.enqueue_sfx(kind);
    }

    /// Sets the active background musical accompaniment track (P16-03, D-019).
    /// Plays an engine effect or one from the theme's soundtrack.
    pub fn play_sound(self: *DisplayWindow, sound: audio_mod.Sound) void {
        self.audio_bridge.enqueue_sound(sound);
    }

    /// Plays soundtrack track `track`, or stops the music with null.
    pub fn set_bgm(self: *DisplayWindow, track: ?u8) void {
        self.audio_bridge.set_track(track);
    }

    /// Stops background musical accompaniment.
    pub fn stop_bgm(self: *DisplayWindow) void {
        self.audio_bridge.stop_bgm();
    }

    /// Sets an ephemeral on-screen cue announcement banner.
    pub fn set_cue_banner(self: *DisplayWindow, text: []const u8, duration_ticks: u32) void {
        const len = @min(text.len, self.cue_banner_text.len);
        @memcpy(self.cue_banner_text[0..len], text[0..len]);
        self.cue_banner_len = len;
        self.cue_banner_ticks = duration_ticks;
    }

    /// Decreases simulation clock speed (increases milliseconds per tick) (D-028).
    pub fn speed_slower(self: *DisplayWindow) void {
        self.current_tick_interval_ms = vm_mod.step_tick_interval_slower(self.current_tick_interval_ms);
        self.play_sfx(.click);
        var sbuf: [64]u8 = undefined;
        const msg = if (self.current_tick_interval_ms >= 1000)
            std.fmt.bufPrint(&sbuf, "Speed: {d:.2}s / tick ({d:.1} Hz)", .{
                @as(f32, @floatFromInt(self.current_tick_interval_ms)) / 1000.0,
                1000.0 / @as(f32, @floatFromInt(self.current_tick_interval_ms)),
            }) catch "Speed slowed"
        else
            std.fmt.bufPrint(&sbuf, "Speed: {d}ms / tick ({d:.1} Hz)", .{
                self.current_tick_interval_ms,
                1000.0 / @as(f32, @floatFromInt(self.current_tick_interval_ms)),
            }) catch "Speed slowed";
        self.set_cue_banner(msg, 60);
    }

    /// Increases simulation clock speed (decreases milliseconds per tick) (D-028).
    pub fn speed_faster(self: *DisplayWindow) void {
        self.current_tick_interval_ms = vm_mod.step_tick_interval_faster(self.current_tick_interval_ms);
        self.play_sfx(.click);
        var sbuf: [64]u8 = undefined;
        const msg = if (self.current_tick_interval_ms >= 1000)
            std.fmt.bufPrint(&sbuf, "Speed: {d:.2}s / tick ({d:.1} Hz)", .{
                @as(f32, @floatFromInt(self.current_tick_interval_ms)) / 1000.0,
                1000.0 / @as(f32, @floatFromInt(self.current_tick_interval_ms)),
            }) catch "Speed increased"
        else
            std.fmt.bufPrint(&sbuf, "Speed: {d}ms / tick ({d:.1} Hz)", .{
                self.current_tick_interval_ms,
                1000.0 / @as(f32, @floatFromInt(self.current_tick_interval_ms)),
            }) catch "Speed increased";
        self.set_cue_banner(msg, 60);
    }

    /// Displays an active speech balloon or branching dialogue choice tree (P7-04, P13-03, D-009, D-015).
    pub fn show_dialogue(
        self: *DisplayWindow,
        speaker: EntityId,
        speaker_pos: Point,
        speaker_name: []const u8,
        text: []const u8,
        choices: []const []const u8,
    ) void {
        var sb = SpeechBalloon{
            .speaker = speaker,
            .speaker_pos = speaker_pos,
            .speaker_name = undefined,
            .speaker_name_len = 0,
            .text = undefined,
            .text_len = 0,
            .ticks_remaining = if (choices.len > 0) std.math.maxInt(u32) else 360,
            .choices = undefined,
            .choice_lens = [_]u8{0} ** 9,
            .choice_count = 0,
            .scroll_offset = 0,
        };

        // The panel shows a display name: `HarbourWarden` reads `Harbour Warden` (D-077).
        const shown = dialogue_panel.display_name(speaker_name, &sb.speaker_name);
        const nlen = @min(shown.len, sb.speaker_name.len);
        if (@intFromPtr(shown.ptr) != @intFromPtr(&sb.speaker_name)) @memcpy(sb.speaker_name[0..nlen], shown[0..nlen]);
        sb.speaker_name_len = @intCast(nlen);

        const tlen = @min(text.len, sb.text.len);
        @memcpy(sb.text[0..tlen], text[0..tlen]);
        sb.text_len = @intCast(tlen);

        for (choices, 0..) |c_text, i| {
            if (i >= 9) break;
            const clen = @min(c_text.len, sb.choices[i].len);
            @memcpy(sb.choices[i][0..clen], c_text[0..clen]);
            sb.choice_lens[i] = @intCast(clen);
            sb.choice_count += 1;
        }

        self.active_balloon = sb;
    }

    /// Mirrors the frame's dialogue channel into the balloon overlay (P32-30, D-046). A new
    /// revision replaces the balloon; a closed set dismisses only a balloon this opened.
    fn sync_dialogue_balloon(self: *DisplayWindow, frame: *const RenderFrame) void {
        if (frame.dialogue.active) {
            if (!self.balloon_from_frame or self.balloon_revision != frame.dialogue.revision) {
                var choices: [dialogue_mod.MAX_CHOICES][]const u8 = undefined;
                const count: usize = @intCast(frame.dialogue.choice_count);
                for (0..count) |i| choices[i] = frame.dialogue.get_choice(i);
                const pt = world_to_screen(frame.dialogue.x, frame.dialogue.y, self.width, self.height);
                self.show_dialogue(
                    frame.dialogue.speaker,
                    pt,
                    frame.dialogue.get_speaker_name(),
                    frame.dialogue.get_prompt(),
                    choices[0..count],
                );
                self.balloon_revision = frame.dialogue.revision;
                self.balloon_from_frame = true;
            }
        } else if (self.balloon_from_frame) {
            self.dismiss_dialogue();
            self.balloon_from_frame = false;
        }
    }

    /// The panel geometry for `balloon` in this window, leaving room for the command bar.
    fn dialogue_panel_for(self: *const DisplayWindow, balloon: *const SpeechBalloon) DialoguePanel {
        return get_dialogue_panel(balloon, self.width, self.height, self.command_bar_enabled and !self.show_console);
    }

    /// Queues a click-through message (D-080). `speaker` is an entity name or empty.
    pub fn queue_message(self: *DisplayWindow, speaker: []const u8, text: []const u8) void {
        self.messages.push(speaker, text);
        if (self.messages.pending()) self.hovered_choice = null;
    }

    /// True while a click-through message waits to be dismissed.
    pub fn has_messages(self: *const DisplayWindow) bool {
        return self.messages.pending();
    }

    /// Dismisses active speech balloon.
    pub fn dismiss_dialogue(self: *DisplayWindow) void {
        self.active_balloon = null;
        self.hovered_choice = null;
    }

    /// Appends a line to the REPL console history buffer (P9-03, D-011).
    /// The State tab of the drawer (P27-01, D-058): the focused entity with its neighbours on a
    /// ring and the facts between them as labelled arrows, its value and state facts listed on
    /// the right, coloured by remaining ticks.
    /// Drops a focus the frame no longer mentions (after a rewind or a load) along with the
    /// history built on it, then clamps the selection to the ring (D-059).
    fn inspector_sync(self: *DisplayWindow, facts: []const display_mod.RenderDebugFact) void {
        if (self.inspector_focus) |f| {
            if (!state_graph.mentions(facts, f)) {
                self.inspector_focus = null;
                self.inspector_history_len = 0;
                self.inspector_selected = 0;
            }
        }
    }

    /// The explicit focus, else the best-connected entity under the filter, else the
    /// best-connected entity overall, so a filter with no edges still has a centre.
    fn inspector_resolved_focus(self: *const DisplayWindow, facts: []const display_mod.RenderDebugFact) ?display_mod.EntityId {
        return self.inspector_focus orelse state_graph.default_focus(facts, self.inspector_filter) orelse state_graph.default_focus(facts, .{});
    }

    fn inspector_layout(self: *DisplayWindow, frame: *const RenderFrame) ?state_graph.Layout {
        const facts = frame.debug_facts[0..frame.debug_fact_count];
        self.inspector_sync(facts);
        const focus = self.inspector_resolved_focus(facts) orelse return null;
        const g = inspector_geometry(get_save_drawer_rect(self.width, self.height));
        const layout = state_graph.build(facts, focus, self.inspector_filter, g.cx, g.cy, g.rx, g.ry);
        if (self.inspector_selected >= layout.ring_len) self.inspector_selected = 0;
        return layout;
    }

    /// Centres on `entity`, remembering the old centre for Backspace.
    fn inspector_recentre(self: *DisplayWindow, from: display_mod.EntityId, entity: display_mod.EntityId) void {
        if (self.inspector_history_len == INSPECTOR_HISTORY) {
            std.mem.copyForwards(display_mod.EntityId, self.inspector_history[0 .. INSPECTOR_HISTORY - 1], self.inspector_history[1..INSPECTOR_HISTORY]);
            self.inspector_history_len -= 1;
        }
        self.inspector_history[self.inspector_history_len] = from;
        self.inspector_history_len += 1;
        self.inspector_focus = entity;
        self.inspector_selected = 0;
    }

    /// State tab keys (P27-03, D-059). Returns true when the key was a navigation key.
    fn inspector_key(self: *DisplayWindow, frame: *const RenderFrame, sym: c.SDL_Keycode) bool {
        const facts = frame.debug_facts[0..frame.debug_fact_count];
        const layout = self.inspector_layout(frame);
        const ring_len = if (layout) |l| l.ring_len else 0;
        switch (sym) {
            c.SDLK_RIGHT, c.SDLK_LEFT => {
                if (ring_len == 0) return true;
                self.inspector_selected = if (sym == c.SDLK_RIGHT)
                    (self.inspector_selected + 1) % ring_len
                else
                    (self.inspector_selected + ring_len - 1) % ring_len;
            },
            c.SDLK_RETURN, c.SDLK_KP_ENTER => {
                const l = layout orelse return true;
                if (ring_len == 0) return true;
                self.inspector_recentre(l.center.entity, l.ring[self.inspector_selected].entity);
            },
            c.SDLK_BACKSPACE => {
                if (self.inspector_history_len == 0) return true;
                self.inspector_history_len -= 1;
                self.inspector_focus = self.inspector_history[self.inspector_history_len];
                self.inspector_selected = 0;
            },
            c.SDLK_HOME => {
                self.inspector_focus = null;
                self.inspector_history_len = 0;
                self.inspector_selected = 0;
            },
            c.SDLK_f => {
                self.inspector_filter = state_graph.next_filter(facts, self.inspector_filter);
                self.inspector_selected = 0;
            },
            else => return false,
        }
        self.play_sfx(.click);
        return true;
    }

    /// A click on a ring node recentres on it, as Enter does on the selection.
    fn inspector_click(self: *DisplayWindow, frame: *const RenderFrame, x: i32, y: i32) bool {
        const layout = self.inspector_layout(frame) orelse return false;
        const ring = layout.hit_ring(x, y, 14) orelse return false;
        self.inspector_recentre(layout.center.entity, layout.ring[ring].entity);
        self.play_sfx(.click);
        return true;
    }

    fn draw_state_inspector(self: *DisplayWindow, frame: *const RenderFrame, drect: c.SDL_Rect) void {
        const facts = frame.debug_facts[0..frame.debug_fact_count];
        const g = inspector_geometry(drect);
        const area_x = g.area_x;
        const top = g.top;
        const area_w = g.area_w;
        const area_h = g.area_h;
        self.fill_rect(area_x, top, area_w, area_h, Color{ .r = 9, .g = 14, .b = 26, .a = 250 });
        self.draw_rect_outline(area_x, top, area_w, area_h, Color{ .r = 51, .g = 65, .b = 85 });

        var footer_buf: [160]u8 = undefined;
        const footer = std.fmt.bufPrint(
            &footer_buf,
            "TICK {d} | {d} FACTS | FILTER {s} | ARROWS SELECT, ENTER CENTRE, BKSP BACK, HOME RESET, F FILTER",
            .{ frame.tick, facts.len, self.inspector_filter.label() },
        ) catch "";
        self.draw_text(footer, area_x + 10, top + area_h - 16, 1, Color.hud_subtext);

        const maybe_layout = self.inspector_layout(frame);
        const layout = maybe_layout orelse {
            self.draw_text("No fact links two entities yet.", area_x + 20, top + 20, 2, Color.hud_subtext);
            return;
        };
        const focus = layout.center.entity;
        const graph_w = g.graph_w;
        const cx = g.cx;
        const cy = g.cy;

        for (layout.edges[0..layout.edge_len]) |edge| {
            const f = &facts[edge.fact];
            const node = layout.ring[edge.ring];
            const line_col = if (state_graph.is_belief(f)) INSPECTOR_BELIEF else band_color(state_graph.band(f, frame.tick));
            self.draw_line(cx, cy, node.x, node.y, line_col);
            // The arrowhead sits near the object's end of the edge.
            const tip_x = if (edge.outward) node.x + @divTrunc(cx - node.x, 5) else cx + @divTrunc(node.x - cx, 5);
            const tip_y = if (edge.outward) node.y + @divTrunc(cy - node.y, 5) else cy + @divTrunc(node.y - cy, 5);
            self.fill_circle(tip_x, tip_y, 4, line_col);
            self.draw_text(f.get_relation(), @divTrunc(cx + node.x, 2) - 30, @divTrunc(cy + node.y, 2) - 10, 1, band_color(state_graph.band(f, frame.tick)));
        }
        for (layout.ring_nodes(), 0..) |node, r| {
            if (r == self.inspector_selected) self.draw_circle_outline(node.x, node.y, 16, INSPECTOR_ACCENT);
            self.fill_circle(node.x, node.y, 12, Color{ .r = 51, .g = 65, .b = 85 });
            self.draw_text(state_graph.name_of(facts, node.entity), node.x - 30, node.y + 16, 1, Color.hud_text);
        }
        self.fill_circle(cx, cy, 18, INSPECTOR_ACCENT);
        self.draw_text(state_graph.name_of(facts, focus), cx - 30, cy + 22, 2, Color.white);
        if (layout.hidden_neighbours > 0) {
            var more_buf: [32]u8 = undefined;
            self.draw_text(std.fmt.bufPrint(&more_buf, "+{d} MORE", .{layout.hidden_neighbours}) catch "", area_x + 10, top + 10, 1, Color.hud_subtext);
        }

        const list_x = area_x + graph_w + 10;
        self.draw_line(list_x - 10, top + 8, list_x - 10, top + area_h - 24, Color{ .r = 51, .g = 65, .b = 85 });
        self.draw_text("STATES & VALUES", list_x, top + 10, 1, Color.hud_subtext);
        var y = top + 28;
        const shown_states = @min(layout.listed_len, 4);
        for (layout.listed[0..shown_states]) |i| {
            const f = &facts[i];
            var line_buf: [64]u8 = undefined;
            const line = if (f.object_raw == 0)
                f.get_relation()
            else
                std.fmt.bufPrint(&line_buf, "{s} = {s}", .{ f.get_relation(), f.get_object() }) catch f.get_relation();
            self.draw_text(line, list_x, y, 1, band_color(state_graph.band(f, frame.tick)));
            if (f.expires_at_tick > 0 and !f.recently_expired) {
                var exp_buf: [24]u8 = undefined;
                self.draw_text(std.fmt.bufPrint(&exp_buf, "until {d}", .{f.expires_at_tick}) catch "", list_x + 150, y, 1, Color.hud_subtext);
            }
            y += 14;
        }
        const hidden_states = layout.hidden_listed + layout.listed_len - shown_states;
        if (hidden_states > 0) {
            var more_buf: [32]u8 = undefined;
            self.draw_text(std.fmt.bufPrint(&more_buf, "+{d} MORE", .{hidden_states}) catch "", list_x, y, 1, Color.hud_subtext);
            y += 14;
        }

        y += 8;
        self.draw_line(list_x, y, area_x + area_w - 10, y, Color{ .r = 51, .g = 65, .b = 85 });
        y += 10;
        if (frame.dialogue.active) {
            var dialogue_title_buf: [80]u8 = undefined;
            const dialogue_title = std.fmt.bufPrint(&dialogue_title_buf, "DIALOGUE: {s}", .{frame.dialogue.get_speaker_name()}) catch "DIALOGUE";
            self.draw_text(dialogue_title, list_x, y, 1, Color.hud_subtext);
            y += 15;
            for (frame.dialogue.branches[0..frame.dialogue.branch_count]) |*branch| {
                var branch_buf: [96]u8 = undefined;
                const branch_line = std.fmt.bufPrint(&branch_buf, "{s} {s}", .{ if (branch.active) "+" else "x", branch.get_text() }) catch branch.get_text();
                self.draw_text(branch_line, list_x, y, 1, if (branch.active) Color.status_running else Color.cue_alert);
                y += 11;
                if (!branch.active and branch.failure_len > 0) {
                    var failure_buf: [112]u8 = undefined;
                    const failure_line = std.fmt.bufPrint(&failure_buf, "  {s}", .{branch.get_failure()}) catch branch.get_failure();
                    self.draw_text(failure_line, list_x, y, 1, Color{ .r = 248, .g = 113, .b = 113 });
                    y += 10;
                }
            }
        } else {
            self.draw_text("DIALOGUE: NONE OPEN", list_x, y, 1, Color.hud_subtext);
            y += 15;
        }

        y += 6;
        self.draw_line(list_x, y, area_x + area_w - 10, y, Color{ .r = 51, .g = 65, .b = 85 });
        y += 10;
        self.draw_text("NEXT TO HAPPEN", list_x, y, 1, Color.hud_subtext);
        y += 15;
        const next = state_graph.next_expiring(facts, frame.tick);
        const row_budget: usize = @intCast(@max(0, @divTrunc(top + area_h - 24 - y, 12)));
        const shown_next = @min(next.len, row_budget);
        for (next.facts[0..shown_next]) |i| {
            const f = &facts[i];
            var next_buf: [128]u8 = undefined;
            const line = std.fmt.bufPrint(
                &next_buf,
                "T{d} (+{d}) {s}({s}, {s})",
                .{ f.expires_at_tick, f.expires_at_tick - frame.tick, f.get_relation(), f.get_subject(), f.get_object() },
            ) catch "?";
            self.draw_text(line, list_x, y, 1, band_color(state_graph.band(f, frame.tick)));
            y += 12;
        }
        if (next.len == 0) {
            self.draw_text("No scheduled expirations.", list_x, y, 1, Color.hud_subtext);
        } else if (next.hidden + next.len - shown_next > 0) {
            var more_buf: [32]u8 = undefined;
            self.draw_text(std.fmt.bufPrint(&more_buf, "+{d} LATER", .{next.hidden + next.len - shown_next}) catch "", list_x, y, 1, Color.hud_subtext);
        }
    }

    /// Turns the command bar on or off. Turning it off also unfocuses it.
    pub fn enable_command_bar(self: *DisplayWindow, enabled: bool) void {
        self.command_bar_enabled = enabled;
        if (!enabled) self.command_bar_focused = false;
    }

    fn add_command_history(self: *DisplayWindow, text: []const u8) void {
        if (self.command_history_count == self.command_history.len) {
            var i: usize = 0;
            while (i + 1 < self.command_history.len) : (i += 1) {
                self.command_history[i] = self.command_history[i + 1];
                self.command_history_lens[i] = self.command_history_lens[i + 1];
            }
            self.command_history_count -= 1;
        }
        const idx = self.command_history_count;
        const len = @min(text.len, self.command_history[idx].len);
        @memcpy(self.command_history[idx][0..len], text[0..len]);
        self.command_history_lens[idx] = len;
        self.command_history_count += 1;
    }

    /// Appends typed text to the focused command bar; editing ends any history browsing.
    fn command_bar_text(self: *DisplayWindow, text: []const u8) void {
        for (text) |ch| {
            if (self.command_len == self.command_input.len) break;
            self.command_input[self.command_len] = ch;
            self.command_len += 1;
        }
        self.command_history_cursor = null;
    }

    fn recall_command(self: *DisplayWindow, idx: usize) void {
        const len = self.command_history_lens[idx];
        @memcpy(self.command_input[0..len], self.command_history[idx][0..len]);
        self.command_len = len;
    }

    /// Keys while the command bar is focused. Every key is consumed: text arrives separately
    /// as SDL_TEXTINPUT, and a key that also has a binding must not trigger it.
    fn command_bar_key(self: *DisplayWindow, sym: c.SDL_Keycode) UserAction {
        if (sym == c.SDLK_RETURN or sym == c.SDLK_KP_ENTER) {
            if (self.command_len == 0) return .none;
            const line = self.command_input[0..self.command_len];
            self.add_command_history(line);
            const act = UserAction{ .typed_command = .{ .buf = self.command_input, .len = self.command_len } };
            self.command_len = 0;
            self.command_history_cursor = null;
            return act;
        } else if (sym == c.SDLK_ESCAPE) {
            self.command_bar_focused = false;
            self.command_history_cursor = null;
        } else if (sym == c.SDLK_BACKSPACE) {
            if (self.command_len > 0) self.command_len -= 1;
        } else if (sym == c.SDLK_UP) {
            if (self.command_history_count > 0) {
                const cur = self.command_history_cursor orelse self.command_history_count;
                const next = if (cur > 0) cur - 1 else 0;
                self.command_history_cursor = next;
                self.recall_command(next);
            }
        } else if (sym == c.SDLK_DOWN) {
            if (self.command_history_cursor) |cur| {
                if (cur + 1 < self.command_history_count) {
                    self.command_history_cursor = cur + 1;
                    self.recall_command(cur + 1);
                } else {
                    self.command_history_cursor = null;
                    self.command_len = 0;
                }
            }
        } else if (sym == c.SDLK_TAB) {
            self.command_len = self.command_words.complete(&self.command_input, self.command_len);
        }
        return .none;
    }

    pub fn add_console_history(self: *DisplayWindow, text: []const u8) void {
        if (self.console_history_count < 5) {
            const idx = self.console_history_count;
            const len = @min(text.len, self.console_history[idx].len);
            @memcpy(self.console_history[idx][0..len], text[0..len]);
            self.console_history_lens[idx] = len;
            self.console_history_count += 1;
        } else {
            var i: usize = 0;
            while (i < 4) : (i += 1) {
                self.console_history[i] = self.console_history[i + 1];
                self.console_history_lens[i] = self.console_history_lens[i + 1];
            }
            const len = @min(text.len, self.console_history[4].len);
            @memcpy(self.console_history[4][0..len], text[0..len]);
            self.console_history_lens[4] = len;
        }
    }

    /// Polls peripheral input events and returns high-level simulation intents (P6-01, P6-03).
    pub fn poll_events(self: *DisplayWindow, frame: *const RenderFrame) UserAction {
        if (self.is_headless) return .none;

        var event: c.SDL_Event = undefined;
        var action: UserAction = .none;

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => return .quit,
                c.SDL_MOUSEMOTION => {
                    if (self.show_save_drawer) {
                        const drect = get_save_drawer_rect(self.width, self.height);
                        self.hovered_save_slot = hit_test_save_slot(event.motion.x, event.motion.y, drect);
                        if (self.hovered_save_slot) |hsl| {
                            self.selected_save_slot = hsl;
                        }
                        continue;
                    } else {
                        self.hovered_save_slot = null;
                    }

                    if (self.messages.pending()) {
                        self.hovered_choice = null;
                    } else if (self.active_balloon) |*b| {
                        const panel = self.dialogue_panel_for(b);
                        self.hovered_choice = hit_test_dialogue_panel(event.motion.x, event.motion.y, b, &panel);
                    } else {
                        self.hovered_choice = null;
                    }

                    self.hovered_wp = hit_test_waypoint(
                        event.motion.x,
                        event.motion.y,
                        frame.waypoints[0..frame.waypoint_count],
                        self.width,
                        self.height,
                    );
                    self.hovered_hotspot = hit_test_hotspot(
                        event.motion.x,
                        event.motion.y,
                        frame.hotspots[0..frame.hotspot_count],
                        self.width,
                        self.height,
                    );
                    self.hovered_actor = hit_test_actor(
                        event.motion.x,
                        event.motion.y,
                        frame.entities[0..frame.entity_count],
                        self.width,
                        self.height,
                    );
                    self.hovered_party_member = hit_test_party_portrait(
                        event.motion.x,
                        event.motion.y,
                        frame.party_count,
                        self.width,
                    );
                },
                c.SDL_MOUSEBUTTONDOWN => {
                    if (self.show_save_drawer) {
                        if (event.button.button == c.SDL_BUTTON_LEFT) {
                            const drect = get_save_drawer_rect(self.width, self.height);
                            if (hit_test_save_drawer_tab(event.button.x, event.button.y, drect)) |tab| {
                                self.play_sfx(.click);
                                switch (tab) {
                                    .save_mode => {
                                        self.save_menu_mode = .save;
                                        return .none;
                                    },
                                    .load_mode => {
                                        self.save_menu_mode = .load;
                                        return .none;
                                    },
                                    .state_mode => {
                                        self.save_menu_mode = .state;
                                        return .none;
                                    },
                                    .resume_game => {
                                        self.show_save_drawer = false;
                                        return .toggle_save_drawer;
                                    },
                                    .quit_game => return .quit,
                                }
                            }
                            // The State tab draws over the slot cards; a click there is not a slot.
                            if (self.save_menu_mode == .state and self.inspector_click(frame, event.button.x, event.button.y)) return .none;
                            const slot_hit = if (self.save_menu_mode == .state) null else hit_test_save_slot(event.button.x, event.button.y, drect);
                            if (slot_hit) |slot_id| {
                                self.selected_save_slot = slot_id;
                                return if (self.save_menu_mode == .save)
                                    .{ .save_slot = slot_id }
                                else
                                    .{ .load_slot = slot_id };
                            }
                            if (event.button.x < drect.x or event.button.x > drect.x + drect.w or
                                event.button.y < drect.y or event.button.y > drect.y + drect.h)
                            {
                                self.show_save_drawer = false;
                                self.play_sfx(.click);
                                return .toggle_save_drawer;
                            }
                        } else if (event.button.button == c.SDL_BUTTON_RIGHT) {
                            self.show_save_drawer = false;
                            self.play_sfx(.click);
                            return .toggle_save_drawer;
                        }
                        return .none;
                    }

                    // A waiting message takes any left click as "continue" (D-080).
                    if (self.messages.pending() and event.button.button == c.SDL_BUTTON_LEFT) {
                        _ = self.messages.advance();
                        self.play_sfx(.click);
                        return .none;
                    }

                    if (self.active_balloon) |*b| {
                        const panel = self.dialogue_panel_for(b);
                        if (hit_test_dialogue_panel(event.button.x, event.button.y, b, &panel)) |ch_idx| {
                            self.play_sfx(.dialogue_blip);
                            return .{ .dialogue_choice = ch_idx };
                        } else {
                            self.dismiss_dialogue();
                            self.play_sfx(.click);
                            return .dismiss_dialogue;
                        }
                    }

                    // Distaff note buttons take clicks before the world below them (P22-02, D-029)
                    if (frame.distaff.enabled and event.button.button == c.SDL_BUTTON_LEFT) {
                        const dpanel = get_distaff_panel_rect(self.width, self.height);
                        if (dpanel.contains(event.button.x, event.button.y)) {
                            if (hit_test_distaff_note(event.button.x, event.button.y, self.width, self.height, frame.distaff.reach)) |deg| {
                                self.audio_bridge.enqueue_note(deg);
                                return .{ .play_note = deg };
                            }
                            return .none;
                        }
                    }

                    if (event.button.button == c.SDL_BUTTON_RIGHT) {
                        // Right-click cancels in-hand item selection if active (P11-03, D-013)
                        if (self.selected_inventory_item != null) {
                            self.selected_inventory_item = null;
                            self.set_cue_banner("Action cancelled.", 60);
                            self.play_sfx(.click);
                            return .none;
                        }
                        // Otherwise cycles the active adventure verb (P7-02, D-009)
                        self.active_verb = self.active_verb.next();
                        self.play_sfx(.click);
                    } else if (event.button.button == c.SDL_BUTTON_LEFT) {
                        // 1. Check Timeline Scrubber (P9-02, D-011)
                        const tb_x: i32 = 20;
                        const tb_w: i32 = self.width - 40;
                        if (event.button.y >= 50 and event.button.y <= 74 and
                            event.button.x >= tb_x and event.button.x <= tb_x + tb_w)
                        {
                            if (frame.max_history_tick > 0) {
                                const rel_x: f32 = @as(f32, @floatFromInt(event.button.x - tb_x));
                                const ratio: f32 = rel_x / @as(f32, @floatFromInt(tb_w));
                                const max_t: f32 = @as(f32, @floatFromInt(frame.max_history_tick));
                                const target_tick: u64 = @min(frame.max_history_tick, @as(u64, @intFromFloat(ratio * max_t)));
                                self.play_sfx(.click);
                                return .{ .scrub_to_tick = target_tick };
                            }
                        }

                        // 2. Check Verb Bar buttons
                        const clicked_verb = hit_test_verb_button(event.button.x, event.button.y, self.height);
                        if (clicked_verb) |verb| {
                            if (self.selected_inventory_item != null) {
                                self.selected_inventory_item = null;
                                self.set_cue_banner("Action cancelled.", 60);
                            }
                            self.active_verb = verb;
                            self.play_sfx(.click);
                            return .none;
                        }

                        // 2b. Check Party Member Portraits (P21-01, D-025)
                        const clicked_party_idx = hit_test_party_portrait(event.button.x, event.button.y, frame.party_count, self.width);
                        if (clicked_party_idx) |p_idx| {
                            if (self.selected_inventory_item) |sel_idx| {
                                if (p_idx != frame.active_party_index and self.active_verb == .use_with) {
                                    self.selected_inventory_item = null;
                                    self.play_sfx(.combine);
                                    var buf: [64]u8 = undefined;
                                    const iname = if (sel_idx < frame.inventory_count) frame.inventory[sel_idx].get_name() else "item";
                                    const pname = if (p_idx < frame.party_count) frame.party[p_idx].get_name() else "member";
                                    const banner = std.fmt.bufPrint(&buf, "Giving {s} to {s}...", .{ iname, pname }) catch "Transferring item...";
                                    self.set_cue_banner(banner, 90);
                                    return UserAction{
                                        .transfer_inventory_item = .{
                                            .item_index = sel_idx,
                                            .target_party_index = p_idx,
                                        },
                                    };
                                } else {
                                    self.selected_inventory_item = null;
                                    self.play_sfx(.click);
                                    return UserAction{
                                        .switch_party_member = p_idx,
                                    };
                                }
                            } else {
                                self.play_sfx(.click);
                                return UserAction{
                                    .switch_party_member = p_idx,
                                };
                            }
                        }

                        // 3. Check Inventory items (P11-03, D-013)
                        const clicked_item_idx = hit_test_inventory_item(event.button.x, event.button.y, self.height, frame.inventory[0..frame.inventory_count]);
                        if (clicked_item_idx) |idx| {
                            if (self.active_verb == .look_at) {
                                self.play_sfx(.click);
                                return UserAction{
                                    .interact_inventory = .{
                                        .verb = .look_at,
                                        .item_index = idx,
                                    },
                                };
                            }
                            if (self.selected_inventory_item) |primary_idx| {
                                if (primary_idx == idx) {
                                    // Clicking same selected item deselects it
                                    self.selected_inventory_item = null;
                                    self.set_cue_banner("Item unselected.", 60);
                                    self.play_sfx(.click);
                                    return .none;
                                } else {
                                    // Combining two distinct inventory items
                                    self.selected_inventory_item = null;
                                    var buf: [64]u8 = undefined;
                                    const p_name = if (primary_idx < frame.inventory_count) frame.inventory[primary_idx].get_name() else "item";
                                    const s_name = if (idx < frame.inventory_count) frame.inventory[idx].get_name() else "item";
                                    const banner = std.fmt.bufPrint(&buf, "Using {s} on {s}...", .{ p_name, s_name }) catch "Combining items...";
                                    self.set_cue_banner(banner, 90);
                                    self.play_sfx(.combine);
                                    return .{
                                        .combine_inventory_items = .{
                                            .primary_index = primary_idx,
                                            .secondary_index = idx,
                                        },
                                    };
                                }
                            } else {
                                // Select item into hand
                                self.selected_inventory_item = idx;
                                self.active_verb = .use_with;
                                var buf: [64]u8 = undefined;
                                const iname = if (idx < frame.inventory_count) frame.inventory[idx].get_name() else "item";
                                const banner = std.fmt.bufPrint(&buf, "Use {s} with...", .{iname}) catch "Use item with...";
                                self.set_cue_banner(banner, 180);
                                self.play_sfx(.click);
                                return .none;
                            }
                        }

                        if (self.active_verb == .walk) {
                            if (self.selected_inventory_item != null) {
                                self.selected_inventory_item = null;
                                self.set_cue_banner("Action cancelled.", 60);
                            }

                            // 4a. Check direct Waypoint hit (P3-02, P7-02)
                            const clicked_wp = hit_test_waypoint(
                                event.button.x,
                                event.button.y,
                                frame.waypoints[0..frame.waypoint_count],
                                self.width,
                                self.height,
                            );
                            if (clicked_wp) |wp_id| {
                                self.target_wp = wp_id;
                                self.play_sfx(.footstep);
                                return UserAction{ .walk_player = wp_id };
                            }

                            // 4b. Check Hotspot clicked with WALK -> walk to nearest waypoint to that prop
                            const clicked_hs = hit_test_hotspot(
                                event.button.x,
                                event.button.y,
                                frame.hotspots[0..frame.hotspot_count],
                                self.width,
                                self.height,
                            );
                            if (clicked_hs) |hs_idx| {
                                const hs = frame.hotspots[hs_idx];
                                const hs_pt = world_to_screen(hs.x, hs.y, self.width, self.height);
                                if (find_nearest_waypoint(hs_pt.x, hs_pt.y, frame.waypoints[0..frame.waypoint_count], self.width, self.height)) |wp_id| {
                                    self.target_wp = wp_id;
                                    self.play_sfx(.footstep);
                                    var buf: [64]u8 = undefined;
                                    const banner = std.fmt.bufPrint(&buf, "Walking to {s}...", .{hs.get_name()}) catch "Walking...";
                                    self.set_cue_banner(banner, 60);
                                    return UserAction{ .walk_player = wp_id };
                                }
                            }

                            // 4c. Check Actor clicked with WALK -> walk to nearest waypoint to that actor
                            const clicked_actor = hit_test_actor(
                                event.button.x,
                                event.button.y,
                                frame.entities[0..frame.entity_count],
                                self.width,
                                self.height,
                            );
                            if (clicked_actor) |actor_idx| {
                                const act_ent = frame.entities[actor_idx];
                                const layout = get_entity_screen_layout(actor_idx, frame.entities[0..frame.entity_count], self.width, self.height);
                                if (find_nearest_waypoint(layout.pos.x, layout.pos.y, frame.waypoints[0..frame.waypoint_count], self.width, self.height)) |wp_id| {
                                    self.target_wp = wp_id;
                                    self.play_sfx(.footstep);
                                    var buf: [64]u8 = undefined;
                                    const banner = std.fmt.bufPrint(&buf, "Approaching {s}...", .{act_ent.get_name()}) catch "Walking...";
                                    self.set_cue_banner(banner, 60);
                                    return UserAction{ .walk_player = wp_id };
                                }
                            }

                            // 4d. Open stage/ground click with WALK -> walk to nearest waypoint
                            if (event.button.y >= 72 and event.button.y < self.height - 76) {
                                if (find_nearest_waypoint(event.button.x, event.button.y, frame.waypoints[0..frame.waypoint_count], self.width, self.height)) |wp_id| {
                                    self.target_wp = wp_id;
                                    self.play_sfx(.footstep);
                                    self.set_cue_banner("Walking...", 45);
                                    return UserAction{ .walk_player = wp_id };
                                }
                            }
                        } else {
                            // Active verb is NOT WALK: Check Actors, Hotspots, or direct Waypoint navigation
                            // 4. Check Actors
                            const clicked_actor = hit_test_actor(
                                event.button.x,
                                event.button.y,
                                frame.entities[0..frame.entity_count],
                                self.width,
                                self.height,
                            );
                            if (clicked_actor) |actor_idx| {
                                if (self.selected_inventory_item) |item_idx| {
                                    self.selected_inventory_item = null;
                                    self.play_sfx(.combine);
                                    return .{
                                        .use_inventory_on_actor = .{
                                            .item_index = item_idx,
                                            .actor_index = actor_idx,
                                        },
                                    };
                                } else {
                                    switch (self.active_verb) {
                                        .talk_to => self.play_sfx(.dialogue_blip),
                                        .pick_up => self.play_sfx(.pickup),
                                        else => self.play_sfx(.click),
                                    }
                                    action = .{ .interact_actor = .{ .verb = self.active_verb, .actor_index = actor_idx } };
                                }
                            } else {
                                // 5. Check Hotspots / Props
                                const clicked_hs = hit_test_hotspot(
                                    event.button.x,
                                    event.button.y,
                                    frame.hotspots[0..frame.hotspot_count],
                                    self.width,
                                    self.height,
                                );
                                if (clicked_hs) |hs_idx| {
                                    if (self.selected_inventory_item) |item_idx| {
                                        self.selected_inventory_item = null;
                                        self.play_sfx(.combine);
                                        return .{
                                            .use_inventory_on_hotspot = .{
                                                .item_index = item_idx,
                                                .hotspot_index = hs_idx,
                                            },
                                        };
                                    } else if (self.active_verb == .look_at) {
                                        self.play_sfx(.click);
                                        action = .{ .examine_hotspot = hs_idx };
                                    } else {
                                        switch (self.active_verb) {
                                            .talk_to => self.play_sfx(.dialogue_blip),
                                            .pick_up => self.play_sfx(.pickup),
                                            else => self.play_sfx(.click),
                                        }
                                        action = .{ .interact_hotspot = .{ .verb = self.active_verb, .hotspot_index = hs_idx } };
                                    }
                                } else {
                                    // 6. Direct click on Waypoint with non-walk verb:
                                    // Clicking a waypoint anchor indicates navigation intent -> switch to WALK and move!
                                    const clicked_wp = hit_test_waypoint(
                                        event.button.x,
                                        event.button.y,
                                        frame.waypoints[0..frame.waypoint_count],
                                        self.width,
                                        self.height,
                                    );
                                    if (clicked_wp) |wp_id| {
                                        if (self.selected_inventory_item != null) {
                                            self.selected_inventory_item = null;
                                            self.set_cue_banner("Action cancelled.", 60);
                                        }
                                        self.active_verb = .walk;
                                        self.target_wp = wp_id;
                                        self.play_sfx(.footstep);
                                        action = .{ .walk_player = wp_id };
                                    }
                                }
                            }
                        }
                    }
                },
                c.SDL_TEXTINPUT => {
                    if (self.command_bar_focused and !self.show_console) {
                        self.command_bar_text(std.mem.sliceTo(&event.text.text, 0));
                    } else if (self.show_console) {
                        var i: usize = 0;
                        while (event.text.text[i] != 0 and self.console_len < 127) : (i += 1) {
                            self.console_input[self.console_len] = event.text.text[i];
                            self.console_len += 1;
                        }
                    }
                },
                c.SDL_MOUSEWHEEL => {
                    if (self.active_balloon) |*b| {
                        if (b.choice_count > 6) {
                            if (event.wheel.y > 0) {
                                if (b.scroll_offset > 0) b.scroll_offset -= 1;
                            } else if (event.wheel.y < 0) {
                                if (b.scroll_offset < b.max_scroll_offset()) b.scroll_offset += 1;
                            }
                        }
                    }
                },
                c.SDL_KEYDOWN => {
                    const sym = event.key.keysym.sym;
                    if (self.show_console) {
                        if (sym == c.SDLK_RETURN or sym == c.SDLK_KP_ENTER) {
                            if (self.console_len > 0) {
                                const cmd_text = self.console_input[0..self.console_len];
                                self.add_console_history(cmd_text);
                                const act = UserAction{ .repl_command = .{ .buf = self.console_input, .len = self.console_len } };
                                self.console_len = 0;
                                return act;
                            }
                        } else if (sym == c.SDLK_BACKSPACE) {
                            if (self.console_len > 0) {
                                self.console_len -= 1;
                            }
                        } else if (sym == c.SDLK_ESCAPE or sym == c.SDLK_TAB or sym == c.SDLK_BACKQUOTE) {
                            self.show_console = false;
                            return .toggle_console;
                        }
                        return .none;
                    }

                    if (self.show_save_drawer and self.save_menu_mode == .state) {
                        // The inspector has no slots: Enter, digits, and arrows must not save or
                        // load. Arrows, Enter, Backspace, Home, and F navigate (P27-03, D-059).
                        if (self.inspector_key(frame, sym)) return .none;
                        if (sym == c.SDLK_ESCAPE or sym == c.SDLK_p) {
                            self.show_save_drawer = false;
                            self.play_sfx(.click);
                            return .toggle_save_drawer;
                        } else if (sym == c.SDLK_TAB) {
                            self.save_menu_mode = self.save_menu_mode.next();
                            self.play_sfx(.click);
                        } else if (sym == c.SDLK_q) {
                            return .quit;
                        }
                        return .none;
                    }

                    if (self.show_save_drawer) {
                        if (sym == c.SDLK_ESCAPE or sym == c.SDLK_p) {
                            self.show_save_drawer = false;
                            self.play_sfx(.click);
                            return .toggle_save_drawer;
                        } else if (sym == c.SDLK_TAB) {
                            self.save_menu_mode = self.save_menu_mode.next();
                            self.play_sfx(.click);
                            return .none;
                        } else if (sym == c.SDLK_LEFT or sym == c.SDLK_RIGHT) {
                            self.save_menu_mode = if (self.save_menu_mode == .save) .load else .save;
                            self.play_sfx(.click);
                            return .none;
                        } else if (sym == c.SDLK_UP) {
                            if (self.selected_save_slot > 0) {
                                self.selected_save_slot -= 1;
                                self.play_sfx(.click);
                            }
                            return .none;
                        } else if (sym == c.SDLK_DOWN) {
                            if (self.selected_save_slot < save_mod.MAX_SLOTS) {
                                self.selected_save_slot += 1;
                                self.play_sfx(.click);
                            }
                            return .none;
                        } else if (sym == c.SDLK_RETURN or sym == c.SDLK_KP_ENTER or sym == c.SDLK_SPACE) {
                            return if (self.save_menu_mode == .save)
                                .{ .save_slot = self.selected_save_slot }
                            else
                                .{ .load_slot = self.selected_save_slot };
                        } else if (sym >= c.SDLK_0 and sym <= c.SDLK_8) {
                            const sl: u8 = @intCast(sym - c.SDLK_0);
                            self.selected_save_slot = sl;
                            return if (self.save_menu_mode == .save) .{ .save_slot = sl } else .{ .load_slot = sl };
                        } else if (sym == c.SDLK_F5) {
                            return .quick_save;
                        } else if (sym == c.SDLK_F9) {
                            return .quick_load;
                        } else if (sym == c.SDLK_q) {
                            return .quit;
                        }
                        return .none;
                    }

                    // A waiting message takes Enter or Space as "continue" (D-080), ahead of the
                    // command bar and the pause key; number keys cannot answer hidden choices.
                    if (self.messages.pending()) {
                        if (sym == c.SDLK_RETURN or sym == c.SDLK_KP_ENTER or sym == c.SDLK_SPACE) {
                            _ = self.messages.advance();
                            self.play_sfx(.click);
                            return .none;
                        }
                        if ((sym >= c.SDLK_1 and sym <= c.SDLK_9) or (sym >= c.SDLK_KP_1 and sym <= c.SDLK_KP_9)) return .none;
                    }

                    // Typed-command bar (P26-03): focused, it takes every key; unfocused, Enter
                    // focuses it unless a choice balloon is waiting for an answer.
                    if (self.command_bar_enabled) {
                        if (self.command_bar_focused) return self.command_bar_key(sym);
                        const choices_open = if (self.active_balloon) |b| b.choice_count > 0 else false;
                        if ((sym == c.SDLK_RETURN or sym == c.SDLK_KP_ENTER) and !choices_open) {
                            self.command_bar_focused = true;
                            self.play_sfx(.click);
                            return .none;
                        }
                    }

                    // Handle active dialogue balloon hotkeys and controls (P13-03, D-015)
                    if (self.active_balloon) |*b| {
                        if (b.choice_count > 0) {
                            var hotkey_idx: ?u8 = null;
                            if (sym >= c.SDLK_1 and sym <= c.SDLK_9) {
                                hotkey_idx = @intCast(sym - c.SDLK_1);
                            } else if (sym >= c.SDLK_KP_1 and sym <= c.SDLK_KP_9) {
                                hotkey_idx = @intCast(sym - c.SDLK_KP_1);
                            }

                            if (hotkey_idx) |k_idx| {
                                if (k_idx < b.choice_count) {
                                    self.dismiss_dialogue();
                                    self.play_sfx(.dialogue_blip);
                                    return UserAction{ .dialogue_choice = k_idx };
                                }
                            }

                            if (sym == c.SDLK_UP) {
                                if (b.scroll_offset > 0) {
                                    b.scroll_offset -= 1;
                                    self.play_sfx(.click);
                                    return .none;
                                }
                            } else if (sym == c.SDLK_DOWN) {
                                if (b.scroll_offset < b.max_scroll_offset()) {
                                    b.scroll_offset += 1;
                                    self.play_sfx(.click);
                                    return .none;
                                }
                            }
                        }

                        if (sym == c.SDLK_ESCAPE or sym == c.SDLK_SPACE) {
                            self.dismiss_dialogue();
                            self.play_sfx(.click);
                            return .dismiss_dialogue;
                        }
                    }

                    // Distaff note input (P22-02, D-029): letters play notes while enabled.
                    if (self.active_balloon == null and frame.distaff.enabled) {
                        if (distaff_key_to_degree(sym)) |deg| {
                            if (deg < frame.distaff.reach) {
                                self.audio_bridge.enqueue_note(deg);
                                return .{ .play_note = deg };
                            }
                            self.play_sfx(.click);
                            return .none;
                        }
                        if (sym == c.SDLK_BACKSPACE) {
                            self.play_sfx(.click);
                            return .clear_distaff;
                        }
                    }

                    if (self.active_balloon == null and frame.party_count > 1) {
                        var switch_idx: ?usize = null;
                        if (sym == c.SDLK_1 or sym == c.SDLK_KP_1) {
                            if (frame.party_count >= 1) switch_idx = 0;
                        } else if (sym == c.SDLK_2 or sym == c.SDLK_KP_2) {
                            if (frame.party_count >= 2) switch_idx = 1;
                        } else if (sym == c.SDLK_3 or sym == c.SDLK_KP_3) {
                            if (frame.party_count >= 3) switch_idx = 2;
                        } else if (sym == c.SDLK_4 or sym == c.SDLK_KP_4) {
                            if (frame.party_count >= 4) switch_idx = 3;
                        }
                        if (switch_idx) |s_idx| {
                            self.play_sfx(.click);
                            return UserAction{ .switch_party_member = s_idx };
                        }
                    }

                    // Host key bindings come before the engine's own keys, so a game may take a
                    // letter the engine also uses (the REPL stays on [`] and [Tab]).
                    if (self.theme) |t| {
                        for (t.keys) |binding| {
                            if (binding.key != sym) continue;
                            if (binding.sfx) |sound| self.play_sound(sound);
                            return .{ .custom = binding.action };
                        }
                    }

                    switch (sym) {
                        c.SDLK_SPACE => action = .toggle_pause,
                        c.SDLK_n => action = .step_tick,
                        c.SDLK_MINUS, c.SDLK_KP_MINUS => {
                            self.speed_slower();
                            action = .speed_slower;
                        },
                        c.SDLK_EQUALS, c.SDLK_PLUS, c.SDLK_KP_PLUS => {
                            self.speed_faster();
                            action = .speed_faster;
                        },
                        c.SDLK_r => {
                            self.play_sfx(.alert);
                            action = .rewind;
                        },
                        c.SDLK_LEFT => {
                            self.play_sfx(.click);
                            action = .{ .scrub_to_tick = if (frame.tick > 0) frame.tick - 1 else 0 };
                        },
                        c.SDLK_RIGHT => {
                            self.play_sfx(.click);
                            action = .{ .scrub_to_tick = @min(frame.tick + 1, frame.max_history_tick) };
                        },
                        c.SDLK_F1, c.SDLK_d => {
                            self.show_debug_overlay = !self.show_debug_overlay;
                            return .toggle_debug;
                        },
                        c.SDLK_F2 => {
                            self.show_save_drawer = true;
                            self.save_menu_mode = .save;
                            self.save_manager.refresh_slots();
                            self.play_sfx(.click);
                            return .toggle_save_drawer;
                        },
                        c.SDLK_F3 => {
                            self.show_save_drawer = true;
                            self.save_menu_mode = .load;
                            self.save_manager.refresh_slots();
                            self.play_sfx(.click);
                            return .toggle_save_drawer;
                        },
                        c.SDLK_p => {
                            self.show_save_drawer = !self.show_save_drawer;
                            if (self.show_save_drawer) {
                                self.save_manager.refresh_slots();
                            }
                            self.play_sfx(.click);
                            return .toggle_save_drawer;
                        },
                        c.SDLK_F5 => {
                            return .quick_save;
                        },
                        c.SDLK_F9 => {
                            return .quick_load;
                        },
                        c.SDLK_BACKQUOTE, c.SDLK_TAB, c.SDLK_c => {
                            self.show_console = !self.show_console;
                            return .toggle_console;
                        },
                        c.SDLK_ESCAPE => return .quit,
                        else => {},
                    }
                },
                else => {},
            }
        }

        return action;
    }

    /// Draws the distaff: a treble staff with the phrase in progress as noteheads, the outcome
    /// of the last phrase, and one button per note (dimmed beyond reach) (P22-02, D-029).
    fn render_distaff(self: *DisplayWindow, d: *const display_mod.RenderDistaff) void {
        const panel = get_distaff_panel_rect(self.width, self.height);
        const gold = Color{ .r = 250, .g = 204, .b = 21 };
        const ink = Color{ .r = 203, .g = 213, .b = 225 };
        const dim = Color{ .r = 71, .g = 85, .b = 105 };

        self.fill_rect(panel.x, panel.y, panel.w, panel.h, Color.hud_bg);
        self.draw_rect_outline(panel.x, panel.y, panel.w, panel.h, gold);
        self.draw_text("DISTAFF", panel.x + 10, panel.y + 6, 1, gold);
        var target_buf: [40]u8 = undefined;
        const target_text = if (d.target_len > 0)
            std.fmt.bufPrint(&target_buf, "on: {s}", .{d.get_target()}) catch ""
        else
            "on: (click a target)";
        self.draw_text(target_text, panel.x + 64, panel.y + 6, 1, if (d.target_len > 0) ink else Color.hud_subtext);

        const outcome_text: []const u8 = switch (d.outcome) {
            .none => "[BKSP]: clear",
            .woven => "The draft takes hold.",
            .fizzled => "The draft unravels.",
        };
        const outcome_col = switch (d.outcome) {
            .none => Color.hud_subtext,
            .woven => gold,
            .fizzled => Color.cue_alert,
        };
        self.draw_text(outcome_text, panel.x + panel.w - 10 - font.text_width(outcome_text, 1), panel.y + 6, 1, outcome_col);

        // Five staff lines: E4 G4 B4 D5 F5, two diatonic steps apart.
        const staff_left = panel.x + 10;
        const staff_right = panel.x + panel.w - 10;
        const bottom = distaff_staff_bottom(panel);
        var line: i32 = 0;
        while (line < 5) : (line += 1) {
            const ly = bottom - line * 2 * DISTAFF_STEP_PX;
            self.draw_line(staff_left, ly, staff_right, ly, dim);
        }

        // Phrase slots: noteheads at their pitch, empty slots as faint markers.
        const slot_x0 = panel.x + 70;
        const slot_step: i32 = 62;
        for (0..4) |slot| {
            const sx = slot_x0 + @as(i32, @intCast(slot)) * slot_step;
            if (slot < d.played_len) {
                const deg = d.played[slot];
                const ny = get_distaff_note_y(deg, panel);
                // C4 needs its own ledger line below the staff
                if (deg == 0) self.draw_line(sx - 9, ny, sx + 9, ny, ink);
                self.fill_circle(sx, ny, 5, gold);
                self.draw_text(DISTAFF_NOTE_NAMES[deg], sx + 9, ny - 4, 1, gold);
            } else {
                self.draw_circle_outline(sx, bottom + 2 * DISTAFF_STEP_PX + 4, 3, dim);
            }
        }

        // Note buttons
        for (0..7) |i| {
            const deg: u8 = @intCast(i);
            const r = get_distaff_note_button_rect(deg, panel);
            const reachable = deg < d.reach;
            self.fill_rect(r.x, r.y, r.w, r.h, if (reachable) Color{ .r = 30, .g = 41, .b = 59 } else Color.hud_bg);
            self.draw_rect_outline(r.x, r.y, r.w, r.h, if (reachable) ink else dim);
            const label = DISTAFF_NOTE_NAMES[i];
            const lx = r.x + @divTrunc(r.w - font.text_width(label, 2), 2);
            self.draw_text(label, lx, r.y + 4, 2, if (reachable) Color.hud_text else dim);
        }
    }

    // --- Drawing Primitives ---

    pub fn set_color(self: *DisplayWindow, col: Color) void {
        if (self.renderer) |r| {
            _ = c.SDL_SetRenderDrawColor(r, col.r, col.g, col.b, col.a);
        }
    }

    pub fn fill_rect(self: *DisplayWindow, x: i32, y: i32, w: i32, h: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            const rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
            _ = c.SDL_RenderFillRect(r, &rect);
        }
    }

    pub fn draw_rect_outline(self: *DisplayWindow, x: i32, y: i32, w: i32, h: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            const rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
            _ = c.SDL_RenderDrawRect(r, &rect);
        }
    }

    pub fn draw_line(self: *DisplayWindow, x1: i32, y1: i32, x2: i32, y2: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            _ = c.SDL_RenderDrawLine(r, x1, y1, x2, y2);
        }
    }

    pub fn fill_circle(self: *DisplayWindow, cx: i32, cy: i32, radius: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            var dy: i32 = -radius;
            while (dy <= radius) : (dy += 1) {
                const dx: i32 = @intCast(std.math.sqrt(@as(u64, @intCast(@max(0, radius * radius - dy * dy)))));
                _ = c.SDL_RenderDrawLine(r, cx - dx, cy + dy, cx + dx, cy + dy);
            }
        }
    }

    pub fn draw_circle_outline(self: *DisplayWindow, cx: i32, cy: i32, radius: i32, col: Color) void {
        if (self.renderer) |r| {
            self.set_color(col);
            var x: i32 = radius;
            var y: i32 = 0;
            var err: i32 = 0;

            while (x >= y) {
                _ = c.SDL_RenderDrawPoint(r, cx + x, cy + y);
                _ = c.SDL_RenderDrawPoint(r, cx + y, cy + x);
                _ = c.SDL_RenderDrawPoint(r, cx - y, cy + x);
                _ = c.SDL_RenderDrawPoint(r, cx - x, cy + y);
                _ = c.SDL_RenderDrawPoint(r, cx - x, cy - y);
                _ = c.SDL_RenderDrawPoint(r, cx - y, cy - x);
                _ = c.SDL_RenderDrawPoint(r, cx + y, cy - x);
                _ = c.SDL_RenderDrawPoint(r, cx + x, cy - y);

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
    }

    pub fn draw_text(self: *DisplayWindow, text: []const u8, start_x: i32, start_y: i32, scale: i32, col: Color) void {
        if (self.renderer == null) return;
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

    // --- High-Level 2D Scene Rendering (P6-02, P6-04) ---

    pub fn render_frame(self: *DisplayWindow, frame: *const RenderFrame, is_paused: bool) void {
        if (self.is_headless or self.renderer == null) return;
        self.sync_dialogue_balloon(frame);

        // Trigger procedural music and cue audio reactions (P16-01, P16-03, D-019)
        self.audio_bridge.process_scene_and_cues(frame.get_current_scene(), frame.get_current_score());

        // 1. Backdrop: the host's theme draws its scene; without one, a neutral stage (D-039)
        const backdrop_drawn = if (self.theme) |t| (if (t.backdrop) |draw| draw(self, frame) else false) else false;
        if (!backdrop_drawn) self.render_default_backdrop(frame);
        const walkways_shown = if (self.theme) |t| (if (t.shows_walkways) |ask| ask(frame) else true) else true;

        // 2b. Centralized Text Layout Resolver (D-024)
        var layout_resolver = TextLayoutResolver.init(self.width, self.height);

        // 3. Render Scene Hotspots / Props (P7-01, D-009)
        for (frame.hotspots[0..frame.hotspot_count], 0..) |hs, idx| {
            const pt = world_to_screen(hs.x, hs.y, self.width, self.height);
            const is_hovered = (self.hovered_hotspot != null and self.hovered_hotspot.? == idx);
            const name = hs.get_name();

            const prop_drawn = if (self.theme) |t| (if (t.prop) |draw| draw(self, frame, .{
                .hotspot = &hs,
                .index = idx,
                .pos = pt,
                .hovered = is_hovered,
                .labels = &layout_resolver,
            }) else false) else false;
            if (!prop_drawn) {
                // Default prop
                self.fill_rect(pt.x - 16, pt.y - 16, 32, 32, Color{ .r = 75, .g = 65, .b = 60 });
                self.draw_rect_outline(pt.x - 16, pt.y - 16, 32, 32, Color.panel_border);
            }

            // Hover highlight ring and action prompt
            if (is_hovered) {
                self.draw_circle_outline(pt.x, pt.y, HOTSPOT_SCREEN_RADIUS + 4, Color.wp_hover);
                var prompt_buf: [64]u8 = undefined;
                const prompt = switch (self.active_verb) {
                    .look_at => std.fmt.bufPrint(&prompt_buf, "[Look at {s}]", .{name}) catch "[Look]",
                    .pick_up => std.fmt.bufPrint(&prompt_buf, "[Take {s}]", .{name}) catch "[Take]",
                    .use_with => std.fmt.bufPrint(&prompt_buf, "[Use {s}]", .{name}) catch "[Use]",
                    .talk_to => std.fmt.bufPrint(&prompt_buf, "[Talk to {s}]", .{name}) catch "[Talk]",
                    .walk => std.fmt.bufPrint(&prompt_buf, "[Walk to {s}]", .{name}) catch "[Walk]",
                };
                layout_resolver.submit(TextLabel.init(
                    prompt,
                    pt.x,
                    pt.y,
                    .above,
                    HOTSPOT_SCREEN_RADIUS + 4,
                    2,
                    to_layout(Color.wp_hover),
                    .hotspot_hover,
                    .hover_tooltip,
                ));
            }
        }

        // 4. Render Corridors / Edges between Waypoints
        if (walkways_shown) {
            for (frame.edges[0..frame.edge_count]) |e| {
                var wp_a: ?RenderWaypoint = null;
                var wp_b: ?RenderWaypoint = null;
                for (frame.waypoints[0..frame.waypoint_count]) |wp| {
                    if (wp.id == e.from) wp_a = wp;
                    if (wp.id == e.to) wp_b = wp;
                }
                if (wp_a != null and wp_b != null) {
                    const p1 = world_to_screen(wp_a.?.x, wp_a.?.y, self.width, self.height);
                    const p2 = world_to_screen(wp_b.?.x, wp_b.?.y, self.width, self.height);

                    const walkway_drawn = if (self.theme) |t| (if (t.walkway) |draw| draw(self, frame, p1, p2) else false) else false;
                    if (walkway_drawn) {
                        // The theme drew this stretch in its own style.
                    } else {
                        // Indoor carpet corridor
                        self.draw_line(p1.x, p1.y - 2, p2.x, p2.y - 2, Color.path_edge);
                        self.draw_line(p1.x, p1.y - 1, p2.x, p2.y - 1, Color.path_corridor);
                        self.draw_line(p1.x, p1.y, p2.x, p2.y, Color.path_corridor);
                        self.draw_line(p1.x, p1.y + 1, p2.x, p2.y + 1, Color.path_corridor);
                        self.draw_line(p1.x, p1.y + 2, p2.x, p2.y + 2, Color.path_edge);
                    }
                }
            }
        }

        // 4. Render Waypoint Nodes
        for (frame.waypoints[0..frame.waypoint_count]) |wp| {
            const pt = world_to_screen(wp.x, wp.y, self.width, self.height);
            const is_hovered = (self.hovered_wp == wp.id);
            const is_targeted = (self.target_wp == wp.id);

            // Register waypoint physical footprint as obstacle
            layout_resolver.add_obstacle(
                pt.x - WAYPOINT_SCREEN_RADIUS,
                pt.y - WAYPOINT_SCREEN_RADIUS,
                WAYPOINT_SCREEN_RADIUS * 2,
                WAYPOINT_SCREEN_RADIUS * 2,
            );

            // Halo glow for hovered/target node
            if (is_hovered) {
                self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS + 4, Color.wp_hover);
            }
            if (is_targeted) {
                self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS + 6, Color.wp_target);
            }

            if (walkways_shown) {
                // Waypoint anchor body
                const body_color = if (is_hovered) Color.wp_hover else Color.wp_normal;
                self.fill_circle(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, body_color);
                self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.white);
                self.fill_circle(pt.x, pt.y, 4, Color.white);

                // Waypoint text label
                const name = wp.get_name();
                if (is_hovered or is_targeted) {
                    var buf: [64]u8 = undefined;
                    const prompt = std.fmt.bufPrint(&buf, "[Walk to {s}]", .{name}) catch name;
                    layout_resolver.submit(TextLabel.init(
                        prompt,
                        pt.x,
                        pt.y,
                        .below,
                        WAYPOINT_SCREEN_RADIUS + 6,
                        2,
                        to_layout(Color.wp_hover),
                        .waypoint_hover,
                        .hover_tooltip,
                    ));
                } else {
                    layout_resolver.submit(TextLabel.init(
                        name,
                        pt.x,
                        pt.y,
                        .below,
                        WAYPOINT_SCREEN_RADIUS + 6,
                        1,
                        to_layout(Color.hud_text),
                        .waypoint_idle,
                        .waypoint_idle,
                    ));
                }
            } else {
                // Walkways hidden: marks are drawn as plain stage marks
                if (is_hovered or is_targeted) {
                    self.fill_circle(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.wp_hover);
                    self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.white);
                    const name = wp.get_name();
                    var buf: [64]u8 = undefined;
                    const prompt = std.fmt.bufPrint(&buf, "[Walk to {s}]", .{name}) catch name;
                    layout_resolver.submit(TextLabel.init(
                        prompt,
                        pt.x,
                        pt.y,
                        .below,
                        WAYPOINT_SCREEN_RADIUS + 6,
                        2,
                        to_layout(Color.wp_hover),
                        .waypoint_hover,
                        .hover_tooltip,
                    ));
                } else {
                    // Subtle ground mark anchor
                    self.draw_circle_outline(pt.x, pt.y, 5, Color{ .r = 255, .g = 255, .b = 255, .a = 100 });
                    self.fill_circle(pt.x, pt.y, 2, Color.white);
                }
            }
        }

        // 4b. Render Fourth-Dimensional Pre-Cognitive Vector Conduits (P31-02, D-027)
        for (frame.vector_conduits[0..frame.vector_conduit_count]) |rc| {
            if (rc.point_count < 2) continue;
            const c_r = rc.color_r;
            const c_g = rc.color_g;
            const c_b = rc.color_b;
            const outer_col = Color{ .r = c_r, .g = c_g, .b = c_b, .a = 75 };
            const mid_col = Color{ .r = c_r, .g = c_g, .b = c_b, .a = 160 };
            const core_col = Color{ .r = 240, .g = 250, .b = 255, .a = 230 };

            var i: usize = 0;
            while (i < rc.point_count - 1) : (i += 1) {
                const p1 = world_to_screen(rc.points_x[i], rc.points_y[i], self.width, self.height);
                const p2 = world_to_screen(rc.points_x[i + 1], rc.points_y[i + 1], self.width, self.height);

                // Outer translucent fluid sheath (chest spear water worm effect)
                self.draw_line(p1.x, p1.y - 3, p2.x, p2.y - 3, outer_col);
                self.draw_line(p1.x, p1.y + 3, p2.x, p2.y + 3, outer_col);
                self.draw_line(p1.x - 3, p1.y, p2.x - 3, p2.y, outer_col);
                self.draw_line(p1.x + 3, p1.y, p2.x + 3, p2.y, outer_col);

                // Mid tubular body
                self.draw_line(p1.x, p1.y - 1, p2.x, p2.y - 1, mid_col);
                self.draw_line(p1.x, p1.y + 1, p2.x, p2.y + 1, mid_col);
                self.draw_line(p1.x - 1, p1.y, p2.x - 1, p2.y, mid_col);
                self.draw_line(p1.x + 1, p1.y, p2.x + 1, p2.y, mid_col);

                // Central high-intensity energy spine
                self.draw_line(p1.x, p1.y, p2.x, p2.y, core_col);

                // Fluid meniscus nodes along conduit
                self.fill_circle(p1.x, p1.y, 4, mid_col);
                self.fill_circle(p1.x, p1.y, 2, core_col);
            }

            const p_end = world_to_screen(rc.points_x[rc.point_count - 1], rc.points_y[rc.point_count - 1], self.width, self.height);
            self.draw_circle_outline(p_end.x, p_end.y, 8, mid_col);
            self.draw_circle_outline(p_end.x, p_end.y, 12, outer_col);
        }

        // 5. Render Actors
        for (frame.entities[0..frame.entity_count], 0..) |e, idx| {
            const name = e.get_name();
            const layout = get_entity_screen_layout(idx, frame.entities[0..frame.entity_count], self.width, self.height);
            const pt = layout.pos;
            layout_resolver.add_obstacle(pt.x - ACTOR_SCREEN_RADIUS, pt.y - ACTOR_SCREEN_RADIUS, ACTOR_SCREEN_RADIUS * 2, ACTOR_SCREEN_RADIUS * 2);

            const token_drawn = if (self.theme) |t| (if (t.actor) |draw| draw(self, frame, .{
                .entity = &e,
                .index = idx,
                .layout = layout,
                .labels = &layout_resolver,
            }) else false) else false;
            if (!token_drawn) {
                // Generic actor token
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 70, .g = 80, .b = 95 });
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                layout_resolver.submit(TextLabel.init(
                    name,
                    pt.x,
                    pt.y,
                    .above,
                    ACTOR_SCREEN_RADIUS + 2,
                    2,
                    to_layout(Color.hud_text),
                    .actor_name,
                    .actor_name,
                ));
            }
        }

        // 5b. Resolve and Render all Floating In-World Labels (D-024)
        layout_resolver.resolve();
        for (layout_resolver.get_labels()) |lbl| {
            if (lbl.visible) {
                self.draw_text(
                    lbl.get_text(),
                    lbl.placed_x,
                    lbl.placed_y,
                    lbl.scale,
                    Color{ .r = lbl.color.r, .g = lbl.color.g, .b = lbl.color.b, .a = lbl.color.a },
                );
            }
        }

        // 6. Top Status HUD Bar
        self.fill_rect(0, 0, self.width, 48, Color.hud_bg);
        self.draw_line(0, 48, self.width, 48, Color.panel_border);

        var top_buf: [128]u8 = undefined;
        const top_text = if (is_paused)
            std.fmt.bufPrint(
                &top_buf,
                "BeSpoke Engine | Tick: {d:03} | Facts: {d} | [PAUSED] (Space to run, N to step)",
                .{ frame.tick, frame.fact_count },
            ) catch "BeSpoke Engine"
        else if (self.current_tick_interval_ms >= 1000)
            std.fmt.bufPrint(
                &top_buf,
                "BeSpoke Engine | Tick: {d:03} | Facts: {d} | [RUNNING {d:.1}s] ([-]/[+] speed)",
                .{
                    frame.tick,
                    frame.fact_count,
                    @as(f32, @floatFromInt(self.current_tick_interval_ms)) / 1000.0,
                },
            ) catch "BeSpoke Engine"
        else
            std.fmt.bufPrint(
                &top_buf,
                "BeSpoke Engine | Tick: {d:03} | Facts: {d} | [RUNNING {d}ms] ([-]/[+] speed)",
                .{
                    frame.tick,
                    frame.fact_count,
                    self.current_tick_interval_ms,
                },
            ) catch "BeSpoke Engine";
        const status_col = if (is_paused) Color.status_paused else Color.status_running;
        self.draw_text(top_text, 20, 16, 2, status_col);

        // 6-host. The theme's own HUD elements, above the status bar (D-041)
        if (self.theme) |t| if (t.hud) |draw| draw(self, frame);

        // 6a. Multi-Character Party Member Portraits (P21-01, D-025)
        if (frame.party_count > 1) {
            for (frame.party[0..frame.party_count], 0..) |member, p_idx| {
                const prect = get_party_portrait_rect(p_idx, frame.party_count, self.width);
                const is_active = (p_idx == frame.active_party_index);
                const is_hovered = (self.hovered_party_member != null and self.hovered_party_member.? == p_idx);

                const bg_col = if (is_active)
                    Color{ .r = 30, .g = 58, .b = 138, .a = 240 }
                else if (is_hovered)
                    Color{ .r = 51, .g = 65, .b = 85, .a = 240 }
                else
                    Color{ .r = 20, .g = 30, .b = 45, .a = 220 };

                const border_col = if (is_active)
                    Color{ .r = 250, .g = 204, .b = 21 }
                else if (is_hovered)
                    Color.white
                else
                    Color{ .r = 71, .g = 85, .b = 105 };

                self.fill_rect(prect.x, prect.y, prect.w, prect.h, bg_col);
                self.draw_rect_outline(prect.x, prect.y, prect.w, prect.h, border_col);
                if (is_active) {
                    self.draw_rect_outline(prect.x + 1, prect.y + 1, prect.w - 2, prect.h - 2, Color{ .r = 253, .g = 224, .b = 71 });
                }

                // Member icon token
                self.fill_circle(prect.x + 12, prect.y + 15, 6, border_col);

                // Portrait tag: "[1] <member name>"
                var pbuf: [32]u8 = undefined;
                const ptext = std.fmt.bufPrint(&pbuf, "[{d}] {s}", .{ p_idx + 1, member.get_name() }) catch member.get_name();
                const text_col = if (is_active) Color{ .r = 254, .g = 240, .b = 138 } else Color.hud_text;
                self.draw_text(ptext, prect.x + 22, prect.y + 8, 1, text_col);
            }
        }

        // 6b. Interactive Time-Travel Timeline Scrubber Bar (P9-02, D-011)
        const tb_x: i32 = 20;
        const tb_y: i32 = 50;
        const tb_w: i32 = self.width - 40;
        const tb_h: i32 = 22;

        self.fill_rect(tb_x, tb_y, tb_w, tb_h, Color{ .r = 15, .g = 23, .b = 42, .a = 230 });
        self.draw_rect_outline(tb_x, tb_y, tb_w, tb_h, Color{ .r = 71, .g = 85, .b = 105 });

        if (frame.max_history_tick > 0) {
            const cur_t: f32 = @as(f32, @floatFromInt(frame.tick));
            const max_t: f32 = @as(f32, @floatFromInt(frame.max_history_tick));
            const ratio: f32 = @min(1.0, cur_t / max_t);
            const playhead_x = tb_x + @as(i32, @intFromFloat(ratio * @as(f32, @floatFromInt(tb_w))));

            // Elapsed bar fill
            self.fill_rect(tb_x + 2, tb_y + 3, playhead_x - tb_x, tb_h - 6, Color{ .r = 37, .g = 99, .b = 235, .a = 180 });

            // Playhead indicator
            self.fill_rect(playhead_x - 3, tb_y - 2, 6, tb_h + 4, Color.white);
            self.draw_rect_outline(playhead_x - 3, tb_y - 2, 6, tb_h + 4, Color.cue_alert);
        }

        var tb_text_buf: [80]u8 = undefined;
        const tb_text = std.fmt.bufPrint(&tb_text_buf, "TIMELINE [Tick {d:02}/{d:02}] (Click or [< / >] to Scrub | Space: Pause)", .{ frame.tick, frame.max_history_tick }) catch "TIMELINE";
        self.draw_text(tb_text, tb_x + 8, tb_y + 4, 1, Color.hud_text);

        const bar_y = self.height - 80;

        // 7a. Adventure Action Sentence Line (LucasArts / Sierra Standard)
        var action_sentence_buf: [128]u8 = undefined;
        var action_sentence: ?[]const u8 = null;

        if (self.selected_inventory_item) |sel_idx| {
            if (sel_idx < frame.inventory_count) {
                const sel_name = frame.inventory[sel_idx].get_name();
                if (self.hovered_party_member) |p_idx| {
                    if (p_idx < frame.party_count) {
                        const target_name = frame.party[p_idx].get_name();
                        if (p_idx == frame.active_party_index) {
                            action_sentence = std.fmt.bufPrint(&action_sentence_buf, "[IN HAND: {s}] (Current character)", .{sel_name}) catch null;
                        } else {
                            action_sentence = std.fmt.bufPrint(&action_sentence_buf, "Give {s} to {s}", .{ sel_name, target_name }) catch null;
                        }
                    }
                } else if (self.hovered_actor) |act_idx| {
                    if (act_idx < frame.entity_count) {
                        action_sentence = std.fmt.bufPrint(&action_sentence_buf, "Use {s} on {s}", .{ sel_name, frame.entities[act_idx].get_name() }) catch null;
                    }
                } else if (self.hovered_hotspot) |hs_idx| {
                    if (hs_idx < frame.hotspot_count) {
                        action_sentence = std.fmt.bufPrint(&action_sentence_buf, "Use {s} on {s}", .{ sel_name, frame.hotspots[hs_idx].get_name() }) catch null;
                    }
                } else if (self.hovered_wp) |wp_id| {
                    for (frame.waypoints[0..frame.waypoint_count]) |wp| {
                        if (wp.id == wp_id) {
                            action_sentence = std.fmt.bufPrint(&action_sentence_buf, "Use {s} on {s}", .{ sel_name, wp.get_name() }) catch null;
                            break;
                        }
                    }
                } else {
                    action_sentence = std.fmt.bufPrint(&action_sentence_buf, "[IN HAND: {s}] (Click target/item to use | Right-Click to cancel)", .{sel_name}) catch null;
                }
            }
        } else {
            const verb_word = switch (self.active_verb) {
                .walk => "Walk to",
                .look_at => "Look at",
                .talk_to => "Talk to",
                .pick_up => "Take",
                .use_with => "Use",
            };
            if (self.hovered_party_member) |p_idx| {
                if (p_idx < frame.party_count) {
                    const target_name = frame.party[p_idx].get_name();
                    if (p_idx == frame.active_party_index) {
                        action_sentence = std.fmt.bufPrint(&action_sentence_buf, "{s} (Active Character)", .{target_name}) catch null;
                    } else {
                        action_sentence = std.fmt.bufPrint(&action_sentence_buf, "Switch to {s}", .{target_name}) catch null;
                    }
                }
            } else if (self.hovered_actor) |act_idx| {
                if (act_idx < frame.entity_count) {
                    action_sentence = std.fmt.bufPrint(&action_sentence_buf, "{s} {s}", .{ verb_word, frame.entities[act_idx].get_name() }) catch null;
                }
            } else if (self.hovered_hotspot) |hs_idx| {
                if (hs_idx < frame.hotspot_count) {
                    action_sentence = std.fmt.bufPrint(&action_sentence_buf, "{s} {s}", .{ verb_word, frame.hotspots[hs_idx].get_name() }) catch null;
                }
            } else if (self.hovered_wp) |wp_id| {
                for (frame.waypoints[0..frame.waypoint_count]) |wp| {
                    if (wp.id == wp_id) {
                        action_sentence = std.fmt.bufPrint(&action_sentence_buf, "Walk to {s}", .{wp.get_name()}) catch null;
                        break;
                    }
                }
            }
        }

        if (action_sentence) |sentence| {
            self.draw_text(sentence, 24, bar_y - 24, 2, Color{ .r = 250, .g = 204, .b = 21 });
        }

        // 7b. Adventure Verb Bar & Inventory Tray (P7-02, P7-03, D-009)
        self.fill_rect(0, bar_y - 6, self.width, 42, Color{ .r = 15, .g = 23, .b = 42, .a = 240 });
        self.draw_line(0, bar_y - 6, self.width, bar_y - 6, Color.panel_border);

        // 5 Verb Buttons: WALK, LOOK, TALK, TAKE, USE
        var vi: usize = 0;
        while (vi < 5) : (vi += 1) {
            const verb: AdventureVerb = @enumFromInt(@as(u8, @intCast(vi)));
            const bx = 20 + @as(i32, @intCast(vi)) * 74;
            const is_active = (self.active_verb == verb);

            if (is_active) {
                self.fill_rect(bx, bar_y, 68, 26, Color.wp_hover);
                self.draw_rect_outline(bx, bar_y, 68, 26, Color.white);
                const label = verb.label();
                const lw = font.text_width(label, 2);
                self.draw_text(label, bx + @divTrunc(68 - lw, 2), bar_y + 6, 2, Color.black);
            } else {
                self.fill_rect(bx, bar_y, 68, 26, Color{ .r = 30, .g = 41, .b = 59 });
                self.draw_rect_outline(bx, bar_y, 68, 26, Color{ .r = 71, .g = 85, .b = 105 });
                const label = verb.label();
                const lw = font.text_width(label, 2);
                self.draw_text(label, bx + @divTrunc(68 - lw, 2), bar_y + 6, 2, Color.hud_text);
            }
        }

        // Inventory Tray (P7-03, P11-03)
        self.draw_text("ITEMS:", 400, bar_y + 6, 2, Color.hud_subtext);
        var item_x: i32 = 480;
        if (frame.inventory_count == 0) {
            self.draw_text("(Empty)", item_x, bar_y + 6, 2, Color{ .r = 100, .g = 116, .b = 139 });
        } else {
            for (frame.inventory[0..frame.inventory_count], 0..) |item, idx| {
                const iname = item.get_name();
                const iw = font.text_width(iname, 2) + 24;
                const is_selected = (self.selected_inventory_item != null and self.selected_inventory_item.? == idx);
                const bg_col = if (is_selected) Color{ .r = 85, .g = 65, .b = 25 } else Color{ .r = 45, .g = 35, .b = 20 };
                const border_col = if (is_selected) Color{ .r = 250, .g = 204, .b = 21 } else Color.item_gold;
                const text_col = if (is_selected) Color{ .r = 254, .g = 240, .b = 138 } else Color.item_gold;

                self.fill_rect(item_x, bar_y, iw, 26, bg_col);
                self.draw_rect_outline(item_x, bar_y, iw, 26, border_col);
                if (is_selected) {
                    // Double border for glowing selected highlight
                    self.draw_rect_outline(item_x + 1, bar_y + 1, iw - 2, 24, Color{ .r = 253, .g = 224, .b = 71 });
                }
                self.fill_circle(item_x + 10, bar_y + 13, 5, border_col);
                self.draw_text(iname, item_x + 18, bar_y + 6, 2, text_col);
                item_x += iw + 8;
            }
        }

        // 7c. Distaff Staff HUD (P22-02, D-029)
        if (frame.distaff.enabled) {
            self.render_distaff(&frame.distaff);
        }

        // 8. Bottom Controls HUD Bar
        self.fill_rect(0, self.height - 44, self.width, 44, Color.hud_bg);
        self.draw_line(0, self.height - 44, self.width, self.height - 44, Color.panel_border);
        const theme_footer: ?FooterHint = if (self.theme) |t| (if (t.footer) |ask| ask(frame) else null) else null;
        if (frame.distaff.enabled) {
            // Letter keys play notes in this mode, so advertise the shortcuts that still work
            self.draw_text(
                "[C D E F G A B]: Notes | [Bksp]: Clear | [F1]: Debug | [`]: REPL | [Space]: Pause",
                20,
                self.height - 28,
                2,
                Color{ .r = 250, .g = 204, .b = 21 },
            );
        } else if (theme_footer) |hint| {
            self.draw_text(hint.text, 20, self.height - 28, 2, hint.color);
        } else {
            self.draw_text(
                "[Click]: Act | [Right-Click]: Verb | [-]/[+]: Speed | [Space]: Pause | [P]: Save | [C]: REPL",
                20,
                self.height - 28,
                2,
                Color.hud_subtext,
            );
        }

        // 8. Ephemeral Cue Banner
        if (self.cue_banner_ticks > 0 and self.cue_banner_len > 0) {
            const banner = self.cue_banner_text[0..self.cue_banner_len];
            const scale: i32 = if (font.text_width(banner, 2) + 40 > self.width) 1 else 2;
            const text_w = font.text_width(banner, scale);
            const bw = @min(text_w + 32, self.width - 20);
            const bx = @max(10, @divTrunc(self.width - bw, 2));
            const by: i32 = 60;
            const bh: i32 = if (scale == 2) 36 else 28;
            const text_y = by + @divTrunc(bh - font.FONT_HEIGHT * scale, 2);
            self.fill_rect(bx, by, bw, bh, Color.hud_bg);
            self.draw_rect_outline(bx, by, bw, bh, Color.cue_alert);
            self.draw_text(banner, bx + 16, text_y, scale, Color.cue_alert);
            self.cue_banner_ticks -= 1;
        }

        // 9. Dialogue panel: a waiting click-through message (D-080) covers the speaker, wrapped
        // line, and wrapped numbered choices (D-077) until the player dismisses it.
        if (self.messages.front()) |beat| {
            const panel = get_message_panel(beat, self.width, self.height, self.command_bar_enabled and !self.show_console);
            const r = panel.rect;
            self.fill_rect(r.x, r.y, r.w, r.h, Color{ .r = 254, .g = 243, .b = 199 });
            self.draw_rect_outline(r.x, r.y, r.w, r.h, Color{ .r = 146, .g = 64, .b = 14 });
            self.draw_rect_outline(r.x + 2, r.y + 2, r.w - 4, r.h - 4, Color{ .r = 180, .g = 83, .b = 9 });
            for (panel.layout.slice()) |row| {
                const col = switch (row.kind) {
                    .speaker => Color{ .r = 180, .g = 83, .b = 9 },
                    .hint => Color{ .r = 120, .g = 53, .b = 15 },
                    else => Color{ .r = 28, .g = 25, .b = 23 },
                };
                self.draw_text(row.text, r.x + row.x, r.y + row.y, 2, col);
            }
        } else if (self.active_balloon) |*b| {
            const panel = self.dialogue_panel_for(b);
            const r = panel.rect;
            const ink = Color{ .r = 28, .g = 25, .b = 23 };
            const accent = Color{ .r = 180, .g = 83, .b = 9 };

            self.fill_rect(r.x, r.y, r.w, r.h, Color{ .r = 254, .g = 243, .b = 199 });
            self.draw_rect_outline(r.x, r.y, r.w, r.h, Color{ .r = 146, .g = 64, .b = 14 });
            self.draw_rect_outline(r.x + 2, r.y + 2, r.w - 4, r.h - 4, accent);

            // Choice backgrounds first, so the rows draw over them.
            for (0..panel.layout.choice_count) |slot| {
                const actual_idx = b.scroll_offset + slot;
                const is_hovered = self.hovered_choice != null and self.hovered_choice.? == actual_idx;
                const top = r.y + panel.layout.choice_top[slot];
                const height = panel.layout.choice_bottom[slot] - panel.layout.choice_top[slot];
                const row_w = r.w - 16 - panel.scrollbar_w;
                if (is_hovered) {
                    self.fill_rect(r.x + 8, top, row_w, height, Color.wp_hover);
                    self.draw_rect_outline(r.x + 8, top, row_w, height, Color.white);
                } else {
                    self.fill_rect(r.x + 8, top, row_w, height, Color{ .r = 253, .g = 230, .b = 138 });
                    self.draw_rect_outline(r.x + 8, top, r.w - 16, height, Color{ .r = 217, .g = 119, .b = 6 });
                }
            }

            for (panel.layout.slice()) |row| {
                const x = r.x + row.x;
                const y = r.y + row.y;
                switch (row.kind) {
                    .speaker => self.draw_text(row.text, x, y, 2, accent),
                    .hint => self.draw_text(row.text, x, y, 2, Color{ .r = 120, .g = 53, .b = 15 }),
                    .prompt => self.draw_text(row.text, x, y, 2, ink),
                    .choice => {
                        const actual_idx = b.scroll_offset + row.choice;
                        const is_hovered = self.hovered_choice != null and self.hovered_choice.? == actual_idx;
                        const col = if (is_hovered) Color.black else Color{ .r = 120, .g = 53, .b = 15 };
                        if (row.numbered) {
                            var num_buf: [8]u8 = undefined;
                            const num = std.fmt.bufPrint(&num_buf, "[{d}]", .{actual_idx + 1}) catch "[?]";
                            self.draw_text(num, x - panel.layout.indent, y, 2, col);
                        }
                        self.draw_text(row.text, x, y, 2, col);
                    },
                }
            }

            // A scroll bar along the right edge when choices exceed the visible six (D-084): the
            // track spans the visible choices, and the thumb's size and place show which of all
            // the choices are in view. The wheel and arrow keys scroll.
            if (panel.scrollbar_w > 0 and panel.layout.choice_count > 0) {
                const last = panel.layout.choice_count - 1;
                const track_x = r.x + r.w - panel.scrollbar_w - 4;
                const track_top = r.y + panel.layout.choice_top[0];
                const track_h = panel.layout.choice_bottom[last] - panel.layout.choice_top[0];
                const total: i32 = b.choice_count;
                const shown: i32 = b.visible_choice_count();
                const thumb_h = @max(12, @divTrunc(track_h * shown, total));
                const thumb_y = track_top + @divTrunc((track_h - thumb_h) * @as(i32, b.scroll_offset), @max(1, total - shown));
                self.fill_rect(track_x, track_top, panel.scrollbar_w - 4, track_h, Color{ .r = 253, .g = 230, .b = 138 });
                self.draw_rect_outline(track_x, track_top, panel.scrollbar_w - 4, track_h, Color{ .r = 146, .g = 64, .b = 14 });
                self.fill_rect(track_x + 2, thumb_y + 2, panel.scrollbar_w - 8, thumb_h - 4, accent);
            }
        }

        // 10. In-Engine Debug Inspector Overlay (P9-01, D-011)
        if (self.show_debug_overlay) {
            const dbg_w: i32 = 340;
            const dbg_h: i32 = self.height - 180;
            const dbg_x: i32 = self.width - dbg_w - 20;
            const dbg_y: i32 = 80;

            self.fill_rect(dbg_x, dbg_y, dbg_w, dbg_h, Color{ .r = 10, .g = 15, .b = 30, .a = 240 });
            self.draw_rect_outline(dbg_x, dbg_y, dbg_w, dbg_h, Color.wp_hover);
            self.draw_text("=== RELATIONAL WORLD INSPECTOR (F1/D) ===", dbg_x + 12, dbg_y + 10, 1, Color.wp_hover);

            var cur_y: i32 = dbg_y + 26;
            self.draw_text("ACTIVE FACTS:", dbg_x + 12, cur_y, 1, Color.hud_subtext);
            cur_y += 14;

            var fi: usize = 0;
            while (fi < frame.debug_fact_count and fi < 10) : (fi += 1) {
                const df = &frame.debug_facts[fi];
                var fbuf: [96]u8 = undefined;
                const fstr = if (df.expires_at_tick > 0)
                    std.fmt.bufPrint(&fbuf, " - {s}({s}, {s}) [exp:{d}]", .{ df.get_relation(), df.get_subject(), df.get_object(), df.expires_at_tick }) catch "?"
                else
                    std.fmt.bufPrint(&fbuf, " - {s}({s}, {s})", .{ df.get_relation(), df.get_subject(), df.get_object() }) catch "?";
                self.draw_text(fstr, dbg_x + 12, cur_y, 1, Color.hud_text);
                cur_y += 12;
            }

            cur_y += 6;
            self.draw_line(dbg_x + 10, cur_y, dbg_x + dbg_w - 10, cur_y, Color{ .r = 71, .g = 85, .b = 105 });
            cur_y += 6;

            self.draw_text("ACTIVE FIBERS & STACKS:", dbg_x + 12, cur_y, 1, Color.hud_subtext);
            cur_y += 14;

            var fib_i: usize = 0;
            while (fib_i < frame.debug_fiber_count and fib_i < 5) : (fib_i += 1) {
                const fib = &frame.debug_fibers[fib_i];
                var fib_buf: [96]u8 = undefined;
                const fib_str = std.fmt.bufPrint(&fib_buf, " #{d} [{s}] pc:{d:03} depth:{d} prio:{d} ({s})", .{
                    fib.id, fib.get_owner(), fib.pc, fib.interrupt_depth, fib.priority, fib.get_state(),
                }) catch "?";
                self.draw_text(fib_str, dbg_x + 12, cur_y, 1, Color.hud_text);
                cur_y += 12;
            }

            cur_y += 6;
            self.draw_line(dbg_x + 10, cur_y, dbg_x + dbg_w - 10, cur_y, Color{ .r = 71, .g = 85, .b = 105 });
            cur_y += 6;

            self.draw_text("SPATIAL TOPOLOGY & AGENTS:", dbg_x + 12, cur_y, 1, Color.hud_subtext);
            cur_y += 14;
            for (frame.entities[0..frame.entity_count]) |e| {
                var ent_buf: [64]u8 = undefined;
                const status = if (e.is_moving) "moving" else "idle";
                const ent_str = std.fmt.bufPrint(&ent_buf, " * {s}: ({d}, {d}) [{s}]", .{ e.get_name(), e.x, e.y, status }) catch "?";
                self.draw_text(ent_str, dbg_x + 12, cur_y, 1, Color.white);
                cur_y += 12;
            }
        }

        // 10b. Typed-command bar (P26-03, D-057), above the verb bar.
        if (self.command_bar_enabled and !self.show_console) {
            const cmd_x: i32 = 20;
            const cmd_w: i32 = self.width - 40;
            const cmd_h: i32 = 26;
            const cmd_y: i32 = self.height - 92 - cmd_h;
            const focused = self.command_bar_focused;
            self.fill_rect(cmd_x, cmd_y, cmd_w, cmd_h, Color{ .r = 15, .g = 23, .b = 42, .a = 235 });
            self.draw_rect_outline(cmd_x, cmd_y, cmd_w, cmd_h, if (focused) Color.wp_hover else Color{ .r = 51, .g = 65, .b = 85 });
            var line_buf: [160]u8 = undefined;
            const line = if (focused)
                std.fmt.bufPrint(&line_buf, "> {s}_", .{self.command_input[0..self.command_len]}) catch "> _"
            else
                "[Enter] type a command   (Esc leaves, Up/Down history, Tab completes)";
            self.draw_text(line, cmd_x + 10, cmd_y + 6, if (focused) 2 else 1, if (focused) Color.white else Color.hud_subtext);
        }

        // 11. Live Interactive REPL Console Drawer (P9-03, D-011)
        if (self.show_console) {
            const con_x: i32 = 20;
            const con_w: i32 = self.width - 40;
            const con_h: i32 = 160;
            const con_y: i32 = self.height - con_h - 48;

            self.fill_rect(con_x, con_y, con_w, con_h, Color{ .r = 8, .g = 12, .b = 24, .a = 245 });
            self.draw_rect_outline(con_x, con_y, con_w, con_h, Color{ .r = 245, .g = 158, .b = 11 });
            self.draw_text(">>> BESPOKE LIVE REPL (Tab/C to Close | Type 'help' for commands) <<<", con_x + 14, con_y + 10, 1, Color{ .r = 245, .g = 158, .b = 11 });

            // History log
            var log_y: i32 = con_y + 26;
            var hi: usize = 0;
            while (hi < self.console_history_count) : (hi += 1) {
                const htext = self.console_history[hi][0..self.console_history_lens[hi]];
                self.draw_text(htext, con_x + 14, log_y, 1, Color.hud_subtext);
                log_y += 16;
            }

            // Input prompt line
            self.fill_rect(con_x + 10, con_y + con_h - 32, con_w - 20, 24, Color{ .r = 15, .g = 23, .b = 42 });
            self.draw_rect_outline(con_x + 10, con_y + con_h - 32, con_w - 20, 24, Color{ .r = 71, .g = 85, .b = 105 });

            var prompt_buf: [140]u8 = undefined;
            const cur_input = self.console_input[0..self.console_len];
            const prompt_text = std.fmt.bufPrint(&prompt_buf, "> {s}_", .{cur_input}) catch "> _";
            self.draw_text(prompt_text, con_x + 18, con_y + con_h - 26, 2, Color.white);
        }

        // 12. In-Engine Pause & Save/Load Drawer Overlay (P17-03, D-020)
        if (self.show_save_drawer) {
            self.fill_rect(0, 0, self.width, self.height, Color{ .r = 5, .g = 8, .b = 18, .a = 195 });

            const drect = get_save_drawer_rect(self.width, self.height);
            self.fill_rect(drect.x, drect.y, drect.w, drect.h, Color{ .r = 12, .g = 19, .b = 34, .a = 250 });
            self.draw_rect_outline(drect.x, drect.y, drect.w, drect.h, Color.wp_hover);
            self.draw_rect_outline(drect.x + 2, drect.y + 2, drect.w - 4, drect.h - 4, Color{ .r = 71, .g = 85, .b = 105 });

            // Header Banner
            self.fill_rect(drect.x + 4, drect.y + 4, drect.w - 8, 30, Color{ .r = 22, .g = 32, .b = 54 });
            self.draw_text(
                "=== PAUSE & PERSISTENT SAVE / LOAD MANAGER (P / Esc: Resume | Tab: Mode | 0-8: Slot | F5/F9: Quick) ===",
                drect.x + 16,
                drect.y + 14,
                1,
                Color.wp_hover,
            );

            // Top Tab Bar: [ SAVE MODE ] [ LOAD MODE ] [ RESUME ] [ QUIT ]
            const tab_y = drect.y + 42;
            const is_save_mode = (self.save_menu_mode == .save);

            // Save Mode Tab
            self.fill_rect(drect.x + 20, tab_y, 150, 28, if (is_save_mode) Color.wp_hover else Color{ .r = 30, .g = 41, .b = 59 });
            self.draw_rect_outline(drect.x + 20, tab_y, 150, 28, if (is_save_mode) Color.white else Color{ .r = 71, .g = 85, .b = 105 });
            self.draw_text("SAVE GAME [F2]", drect.x + 32, tab_y + 8, 2, if (is_save_mode) Color.black else Color.hud_text);

            // Load Mode Tab
            const is_load_mode = (self.save_menu_mode == .load);
            self.fill_rect(drect.x + 180, tab_y, 150, 28, if (is_load_mode) Color.wp_target else Color{ .r = 30, .g = 41, .b = 59 });
            self.draw_rect_outline(drect.x + 180, tab_y, 150, 28, if (is_load_mode) Color.white else Color{ .r = 71, .g = 85, .b = 105 });
            self.draw_text("LOAD GAME [F3]", drect.x + 192, tab_y + 8, 2, if (is_load_mode) Color.black else Color.hud_text);

            // State Inspector Tab (P27-01, D-058)
            const is_state_mode = (self.save_menu_mode == .state);
            self.fill_rect(drect.x + 340, tab_y, 130, 28, if (is_state_mode) INSPECTOR_ACCENT else Color{ .r = 30, .g = 41, .b = 59 });
            self.draw_rect_outline(drect.x + 340, tab_y, 130, 28, if (is_state_mode) Color.white else Color{ .r = 71, .g = 85, .b = 105 });
            self.draw_text("STATE", drect.x + 376, tab_y + 8, 2, if (is_state_mode) Color.black else Color.hud_text);

            // Resume Button
            self.fill_rect(drect.x + drect.w - 270, tab_y, 130, 28, Color{ .r = 22, .g = 101, .b = 52 });
            self.draw_rect_outline(drect.x + drect.w - 270, tab_y, 130, 28, Color.status_running);
            self.draw_text("RESUME [Esc]", drect.x + drect.w - 256, tab_y + 8, 2, Color.white);

            // Quit Button
            self.fill_rect(drect.x + drect.w - 130, tab_y, 110, 28, Color{ .r = 127, .g = 29, .b = 29 });
            self.draw_rect_outline(drect.x + drect.w - 130, tab_y, 110, 28, Color.cue_alert);
            self.draw_text("QUIT [Q]", drect.x + drect.w - 108, tab_y + 8, 2, Color.white);

            if (is_state_mode) self.draw_state_inspector(frame, drect);

            // Render Slot Cards (0 = Quick-Save, 1..8 = Numbered Slots)
            var slot_id: u8 = 0;
            while (slot_id <= save_mod.MAX_SLOTS and !is_state_mode) : (slot_id += 1) {
                const srect = get_save_slot_rect(slot_id, drect);
                const sinfo = self.save_manager.get_slot_info(slot_id) orelse SaveSlotInfo{ .slot_id = slot_id };
                const is_sel = (self.selected_save_slot == slot_id) or (self.hovered_save_slot != null and self.hovered_save_slot.? == slot_id);

                const card_bg = if (is_sel)
                    Color{ .r = 35, .g = 48, .b = 74 }
                else if (sinfo.occupied)
                    Color{ .r = 20, .g = 29, .b = 48 }
                else
                    Color{ .r = 15, .g = 21, .b = 34 };

                const card_border = if (is_sel)
                    (if (is_save_mode) Color.wp_hover else Color.wp_target)
                else if (sinfo.corrupted)
                    Color.cue_alert
                else if (sinfo.occupied)
                    Color{ .r = 100, .g = 116, .b = 139 }
                else
                    Color{ .r = 51, .g = 65, .b = 85 };

                self.fill_rect(srect.x, srect.y, srect.w, srect.h, card_bg);
                self.draw_rect_outline(srect.x, srect.y, srect.w, srect.h, card_border);

                // Miniature 16x12 RGB332 Frame Thumbnail (scaled 3x = 48x36)
                const tx = srect.x + 10;
                const ty = srect.y + @divTrunc(srect.h - 36, 2);
                if (sinfo.occupied) {
                    var py: usize = 0;
                    while (py < save_mod.THUMB_HEIGHT) : (py += 1) {
                        var px: usize = 0;
                        while (px < save_mod.THUMB_WIDTH) : (px += 1) {
                            const rgb = save_mod.unpack_rgb332(sinfo.metadata.thumbnail[py * save_mod.THUMB_WIDTH + px]);
                            self.fill_rect(
                                tx + @as(i32, @intCast(px)) * 3,
                                ty + @as(i32, @intCast(py)) * 3,
                                3,
                                3,
                                Color{ .r = rgb.r, .g = rgb.g, .b = rgb.b },
                            );
                        }
                    }
                    self.draw_rect_outline(tx, ty, 48, 36, Color.white);
                } else {
                    self.fill_rect(tx, ty, 48, 36, Color{ .r = 10, .g = 14, .b = 24 });
                    self.draw_rect_outline(tx, ty, 48, 36, Color{ .r = 51, .g = 65, .b = 85 });
                    self.draw_text("EMPTY", tx + 9, ty + 14, 1, Color.hud_subtext);
                }

                // Slot Title & Metadata Text
                const text_x = tx + 58;
                var title_buf: [96]u8 = undefined;
                const status_tag = if (sinfo.corrupted and sinfo.has_backup)
                    "[CORRUPTED - .BAK READY]"
                else if (sinfo.corrupted)
                    "[CORRUPTED]"
                else if (sinfo.occupied)
                    "[SAVED]"
                else
                    "[EMPTY]";

                const slot_title = if (slot_id == 0)
                    std.fmt.bufPrint(&title_buf, "SLOT 0: QUICK-SAVE [F5/F9/0] {s}", .{status_tag}) catch "QUICK-SAVE"
                else
                    std.fmt.bufPrint(&title_buf, "SLOT #{d} [{d}] {s}", .{ slot_id, slot_id, status_tag }) catch "SLOT";

                const title_col = if (sinfo.corrupted)
                    Color.cue_alert
                else if (is_sel)
                    Color.wp_hover
                else if (sinfo.occupied)
                    Color.white
                else
                    Color.hud_subtext;

                self.draw_text(slot_title, text_x, srect.y + 10, 2, title_col);

                if (sinfo.occupied) {
                    var line1_buf: [96]u8 = undefined;
                    const line1 = std.fmt.bufPrint(&line1_buf, "Scene: {s} | Tick: {d} | Facts: {d}", .{
                        sinfo.metadata.get_scene_name(),
                        sinfo.metadata.current_tick,
                        sinfo.metadata.fact_count,
                    }) catch "";
                    self.draw_text(line1, text_x, srect.y + 32, 1, Color.hud_text);

                    var line2_buf: [96]u8 = undefined;
                    const line2 = std.fmt.bufPrint(&line2_buf, "Playtime: {d}s | Actors: {d} | {s}", .{
                        sinfo.metadata.playtime_secs,
                        sinfo.metadata.actor_count,
                        sinfo.metadata.get_description(),
                    }) catch "";
                    self.draw_text(line2, text_x, srect.y + 46, 1, Color.hud_subtext);
                } else {
                    const hint = if (is_save_mode) "Click or press number key to save state here" else "No saved state in this slot";
                    self.draw_text(hint, text_x, srect.y + 34, 1, Color.hud_subtext);
                }
            }
        }

        // 12b. The theme's overlays, above everything else (D-041)
        if (self.theme) |t| if (t.overlay) |draw| draw(self, frame);

        // 13. Present Frame
        if (self.renderer) |r| {
            c.SDL_RenderPresent(r);
        }
    }
};

test "renderer coordinate conversion and hit testing" {
    const testing = std.testing;

    const pt = world_to_screen(20, 0, 960, 540);
    // Center is (480, 290). With world_x=20: 480 - 280 + 20*14 = 200 + 280 = 480.
    try testing.expectEqual(@as(i32, 480), pt.x);
    try testing.expectEqual(@as(i32, 290), pt.y);

    const waypoints = [_]RenderWaypoint{
        .{
            .id = 1,
            .room = EntityId.from_int(1),
            .x = 0,
            .y = 0,
            .name = undefined,
            .name_len = 0,
        },
        .{
            .id = 2,
            .room = EntityId.from_int(1),
            .x = 20,
            .y = 0,
            .name = undefined,
            .name_len = 0,
        },
    };

    // Hit test exact waypoint 2 coordinates
    const hit_id = hit_test_waypoint(pt.x, pt.y, &waypoints, 960, 540);
    try testing.expectEqual(@as(?WaypointId, 2), hit_id);

    // Hit test off-screen / empty area
    const miss_id = hit_test_waypoint(10, 10, &waypoints, 960, 540);
    try testing.expectEqual(@as(?WaypointId, null), miss_id);

    const hotspots = [_]RenderHotspot{
        .{
            .entity = EntityId.from_int(50),
            .room = EntityId.from_int(1),
            .x = 20,
            .y = 0,
            .radius = 10,
            .name = undefined,
            .name_len = 0,
            .examine_text = undefined,
            .examine_len = 0,
        },
    };

    const hs_hit = hit_test_hotspot(pt.x, pt.y, &hotspots, 960, 540);
    try testing.expectEqual(@as(?usize, 0), hs_hit);

    const hs_miss = hit_test_hotspot(10, 10, &hotspots, 960, 540);
    try testing.expectEqual(@as(?usize, null), hs_miss);

    // Hit test verb buttons
    const btn_look = hit_test_verb_button(100, 540 - 70, 540);
    try testing.expectEqual(@as(?AdventureVerb, .look_at), btn_look);

    const btn_miss = hit_test_verb_button(10, 10, 540);
    try testing.expectEqual(@as(?AdventureVerb, null), btn_miss);

    // Test entity visual standoff for multiple actors at the same position
    const entities = [_]RenderEntity{
        .{
            .entity = EntityId.from_int(10),
            .x = 0,
            .y = 0,
            .current_wp = 1,
            .is_moving = false,
            .name = undefined,
            .name_len = 0,
        },
        .{
            .entity = EntityId.from_int(11),
            .x = 0,
            .y = 0,
            .current_wp = 1,
            .is_moving = false,
            .name = undefined,
            .name_len = 0,
        },
    };
    const e0_layout = get_entity_screen_layout(0, &entities, 960, 540);
    const e1_layout = get_entity_screen_layout(1, &entities, 960, 540);
    // Entity 0 shifted left by 30, entity 1 shifted right by 30 with non-overlapping staggered labels
    try testing.expect(e0_layout.pos.x < e1_layout.pos.x);
    try testing.expectEqual(@as(i32, 200 - 30), e0_layout.pos.x);
    try testing.expectEqual(@as(i32, 200 + 30), e1_layout.pos.x);
    try testing.expect(e0_layout.label_y != e1_layout.label_y);
    try testing.expect(e0_layout.status_y != e1_layout.status_y);

    // Hit test actor coordinates
    const act0_hit = hit_test_actor(e0_layout.pos.x, e0_layout.pos.y, &entities, 960, 540);
    try testing.expectEqual(@as(?usize, 0), act0_hit);

    const act1_hit = hit_test_actor(e1_layout.pos.x, e1_layout.pos.y, &entities, 960, 540);
    try testing.expectEqual(@as(?usize, 1), act1_hit);
}

test "P11-03: inventory item hit testing and two-operand combining interaction" {
    const testing = std.testing;

    var inv = [_]RenderInventoryItem{
        .{
            .entity = EntityId.from_int(101),
            .name = undefined,
            .name_len = 0,
        },
        .{
            .entity = EntityId.from_int(102),
            .name = undefined,
            .name_len = 0,
        },
    };
    const name0 = "Syrup";
    @memcpy(inv[0].name[0..name0.len], name0);
    inv[0].name_len = name0.len;

    const name1 = "Tape";
    @memcpy(inv[1].name[0..name1.len], name1);
    inv[1].name_len = name1.len;

    // Hit test item 0 and item 1
    // screen_h = 540, bar_y = 540 - 78 = 462
    const hit_item0 = hit_test_inventory_item(490, 470, 540, &inv);
    try testing.expectEqual(@as(?usize, 0), hit_item0);

    const hit_item1 = hit_test_inventory_item(600, 470, 540, &inv);
    try testing.expectEqual(@as(?usize, 1), hit_item1);

    // Test selection and cancellation state in DisplayWindow
    var win = try DisplayWindow.init("Test Window", 960, 540);
    defer win.deinit();

    try testing.expect(win.selected_inventory_item == null);
    win.selected_inventory_item = 0;
    try testing.expectEqual(@as(?usize, 0), win.selected_inventory_item);

    // Deselect
    win.selected_inventory_item = null;
    try testing.expect(win.selected_inventory_item == null);
}

test "P12-03: display renderer dynamically recognizes scene themes from RenderFrame" {
    const testing = std.testing;

    var frame = std.mem.zeroes(RenderFrame);

    // 1. Spitting competition theme
    const spit_scene = "Spitting Competition";
    @memcpy(frame.current_scene[0..spit_scene.len], spit_scene);
    frame.current_scene_len = spit_scene.len;
    try testing.expectEqualStrings("Spitting Competition", frame.get_current_scene());

    // 2. Wine cellar theme
    const cellar_scene = "Wine Cellar";
    @memcpy(frame.current_scene[0..cellar_scene.len], cellar_scene);
    frame.current_scene_len = cellar_scene.len;
    try testing.expectEqualStrings("Wine Cellar", frame.get_current_scene());

    // 3. Tavern theme
    const tavern_scene = "Tavern";
    @memcpy(frame.current_scene[0..tavern_scene.len], tavern_scene);
    frame.current_scene_len = tavern_scene.len;
    try testing.expectEqualStrings("Tavern", frame.get_current_scene());

    // Verify headless window can render all frames without panic
    var win = try DisplayWindow.init("Scene Switcher Test", 960, 540);
    defer win.deinit();

    win.render_frame(&frame, false);
}

test "P13-03/D-077: the dialogue panel wraps, scrolls, and selects choices" {
    const testing = std.testing;

    var win = try DisplayWindow.init("Dialogue Test", 960, 600);
    defer win.deinit();

    const choices = [_][]const u8{
        "Ask about the cat",
        "Rent motorcycle",
        "Inquire about the templar church",
        "Ask about Rennes-le-Château",
        "Buy bottled spring water",
        "Examine tourist postcards",
        "Ask about the rector",
        "Say goodbye and leave",
    };

    // Show dialogue with 8 choices
    win.show_dialogue(
        EntityId.from_int(1),
        Point{ .x = 400, .y = 350 },
        "Madame Buthane",
        "Bonjour! Can I help you with something?",
        &choices,
    );

    try testing.expect(win.active_balloon != null);
    const balloon = &win.active_balloon.?;

    // 1. Verify capacity and sizing
    try testing.expectEqual(@as(u8, 8), balloon.choice_count);
    try testing.expectEqual(@as(u8, 6), balloon.visible_choice_count());
    try testing.expectEqual(@as(u8, 2), balloon.max_scroll_offset());
    try testing.expectEqual(@as(u8, 0), balloon.scroll_offset);

    // The panel is centred above the verb bar, as wide as its rows plus a scroll bar, and
    // holds six visible choices (D-077, D-084).
    const panel = get_dialogue_panel(balloon, 960, 540, false);
    try testing.expectEqual(panel.layout.width + SCROLLBAR_W, panel.rect.w);
    try testing.expect(panel.rect.w < 920);
    try testing.expectEqual(@divTrunc(960 - panel.rect.w, 2), panel.rect.x);
    try testing.expect(panel.rect.y >= 76);
    try testing.expect(panel.rect.y + panel.rect.h <= 540 - 110);
    try testing.expectEqual(@as(usize, 6), panel.layout.choice_count);
    try testing.expectEqual(SCROLLBAR_W, panel.scrollbar_w);
    // Scrolling never changes the panel's width.
    balloon.scroll_offset = balloon.max_scroll_offset();
    try testing.expectEqual(panel.rect.w, get_dialogue_panel(balloon, 960, 540, false).rect.w);
    balloon.scroll_offset = 0;
    try testing.expectEqualStrings("Madame Buthane", balloon.get_speaker_name());

    const mid_x = panel.rect.x + 40;
    const row_y = struct {
        fn of(p: *const DialoguePanel, slot: usize) i32 {
            return p.rect.y + p.layout.choice_top[slot] + 4;
        }
    }.of;

    // 2. Hit-testing at scroll_offset == 0
    try testing.expectEqual(@as(?u8, 0), hit_test_dialogue_panel(mid_x, row_y(&panel, 0), balloon, &panel));
    try testing.expectEqual(@as(?u8, 1), hit_test_dialogue_panel(mid_x, row_y(&panel, 1), balloon, &panel));

    // 3. Scroll offset == 2: slot 0 is choice 2 and slot 5 is choice 7.
    win.active_balloon.?.scroll_offset = 2;
    const balloon_scrolled = &win.active_balloon.?;
    const scrolled = get_dialogue_panel(balloon_scrolled, 960, 540, false);
    try testing.expectEqual(@as(?u8, 2), hit_test_dialogue_panel(mid_x, row_y(&scrolled, 0), balloon_scrolled, &scrolled));
    try testing.expectEqual(@as(?u8, 7), hit_test_dialogue_panel(mid_x, row_y(&scrolled, 5), balloon_scrolled, &scrolled));

    // Miss outside the panel, and on the prompt row above the choices.
    try testing.expectEqual(@as(?u8, null), hit_test_dialogue_panel(10, 10, balloon_scrolled, &scrolled));
    try testing.expectEqual(@as(?u8, null), hit_test_dialogue_panel(mid_x, scrolled.rect.y + 4, balloon_scrolled, &scrolled));

    // A long line wraps inside the panel instead of running past its edge, and the speaker's
    // entity name is shown as a display name.
    win.show_dialogue(EntityId.from_int(2), Point{ .x = 0, .y = 0 }, "HarbourWarden", "You wield that sword like a mop handle! " ** 3, &[_][]const u8{"Unfortunately for you, they'll be too busy picking apart your reputation."});
    const long = &win.active_balloon.?;
    try testing.expectEqualStrings("Harbour Warden", long.get_speaker_name());
    const narrow = get_dialogue_panel(long, 640, 540, false);
    var rows: usize = 0;
    for (narrow.layout.slice()) |row| {
        try testing.expect(row.x + font.text_width(row.text, 2) <= narrow.rect.w - 12);
        rows += 1;
    }
    try testing.expect(rows >= 6);

    // 4. Dismiss dialogue
    win.dismiss_dialogue();
    try testing.expect(win.active_balloon == null);
}

test "P14-02: set_cue_banner supports long examine descriptions up to 256 bytes without truncation" {
    const testing = std.testing;

    var win = try DisplayWindow.init("Banner Test", 1280, 720);
    defer win.deinit();

    const long_msg = "Room Desk: A wooden desk with a black marker, masking tape, and breakfast syrup.";
    win.set_cue_banner(long_msg, 120);

    try testing.expectEqual(long_msg.len, win.cue_banner_len);
    try testing.expectEqualStrings(long_msg, win.cue_banner_text[0..win.cue_banner_len]);
    try testing.expectEqual(@as(u32, 120), win.cue_banner_ticks);
}

test "P17-03: save/load drawer layout, slot and tab hit testing, and handle_save_action" {
    const testing = std.testing;
    const bytecode_mod = @import("../bytecode.zig");

    const drect = get_save_drawer_rect(1280, 720);
    try testing.expectEqual(@as(i32, 760), drect.w);
    try testing.expectEqual(@as(i32, 500), drect.h);

    // Hit test tabs
    try testing.expectEqual(@as(?SaveDrawerTab, .save_mode), hit_test_save_drawer_tab(drect.x + 50, drect.y + 50, drect));
    try testing.expectEqual(@as(?SaveDrawerTab, .load_mode), hit_test_save_drawer_tab(drect.x + 200, drect.y + 50, drect));
    try testing.expectEqual(@as(?SaveDrawerTab, .resume_game), hit_test_save_drawer_tab(drect.x + drect.w - 200, drect.y + 50, drect));
    try testing.expectEqual(@as(?SaveDrawerTab, .quit_game), hit_test_save_drawer_tab(drect.x + drect.w - 60, drect.y + 50, drect));

    // Hit test Slot 0 (Quick-Save) and Slots 1..8
    const s0 = get_save_slot_rect(0, drect);
    try testing.expectEqual(@as(?u8, 0), hit_test_save_slot(s0.x + 10, s0.y + 10, drect));

    var sl: u8 = 1;
    while (sl <= 8) : (sl += 1) {
        const sr = get_save_slot_rect(sl, drect);
        try testing.expectEqual(@as(?u8, sl), hit_test_save_slot(sr.x + 10, sr.y + 10, drect));
    }

    // Test handle_save_action with temporary directory
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const base_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(base_path);

    var sm = try save_mod.SaveManager.init(testing.allocator, base_path);
    defer sm.deinit();

    var win = try DisplayWindow.init("Save Drawer Test", 1280, 720);
    defer win.deinit();
    win.attach_save_manager(&sm);
    win.show_save_drawer = true;

    var world = try save_mod.World.init(testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = save_mod.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var chunk = bytecode_mod.BytecodeChunk.init(testing.allocator);
    defer chunk.deinit();
    _ = try chunk.emit_op(.halt);
    var vm = save_mod.VM.init(testing.allocator, &world, &chunk);
    defer vm.deinit();
    var bridge = display_mod.DisplayBridge.init();

    _ = world.step_tick();
    _ = world.step_tick();
    var is_paused = false;

    // Render with save drawer open
    var frame = std.mem.zeroes(RenderFrame);
    win.render_frame(&frame, is_paused);

    // Save to Slot 2 via handle_save_action
    try testing.expect(win.handle_save_action(.{ .save_slot = 2 }, &world, &spatial, &vm, &bridge, &is_paused));
    try testing.expect(!win.show_save_drawer);
    try testing.expect(sm.get_slot_info(2).?.occupied);

    // Advance tick to 4, then Load Slot 2 via handle_save_action
    _ = world.step_tick();
    _ = world.step_tick();
    try testing.expectEqual(@as(u64, 4), world.current_tick);

    try testing.expect(win.handle_save_action(.{ .load_slot = 2 }, &world, &spatial, &vm, &bridge, &is_paused));
    try testing.expectEqual(@as(u64, 2), world.current_tick);
    try testing.expect(is_paused);
}

test "P21-01: party portrait layout and hit-testing" {
    const testing = std.testing;
    const screen_w: i32 = 1280;
    const party_count: usize = 3;

    // Single party member has no interactive portrait HUD
    try testing.expectEqual(@as(?usize, null), hit_test_party_portrait(1000, 15, 1, screen_w));

    // 3 party members: rects calculated from right margin
    const r0 = get_party_portrait_rect(0, party_count, screen_w);
    const r1 = get_party_portrait_rect(1, party_count, screen_w);
    const r2 = get_party_portrait_rect(2, party_count, screen_w);

    try testing.expect(r0.x < r1.x);
    try testing.expect(r1.x < r2.x);
    try testing.expectEqual(r0.y, r1.y);
    try testing.expectEqual(r0.w, r1.w);
    try testing.expectEqual(r0.h, r1.h);

    // Hit testing inside bounds
    try testing.expectEqual(@as(?usize, 0), hit_test_party_portrait(r0.x + 10, r0.y + 10, party_count, screen_w));
    try testing.expectEqual(@as(?usize, 1), hit_test_party_portrait(r1.x + 10, r1.y + 10, party_count, screen_w));
    try testing.expectEqual(@as(?usize, 2), hit_test_party_portrait(r2.x + 10, r2.y + 10, party_count, screen_w));

    // Hit testing outside bounds
    try testing.expectEqual(@as(?usize, null), hit_test_party_portrait(r0.x - 5, r0.y, party_count, screen_w));
    try testing.expectEqual(@as(?usize, null), hit_test_party_portrait(r0.x, r0.y + 50, party_count, screen_w));
}

test "P22-02: distaff panel geometry, note hit-testing, and reach limits" {
    const testing = std.testing;
    const w = DEFAULT_WIDTH;
    const h = DEFAULT_HEIGHT;
    const panel = get_distaff_panel_rect(w, h);

    // Panel stays on screen and above the verb/inventory row.
    try testing.expect(panel.x >= 0 and panel.x + panel.w <= w);
    try testing.expect(panel.y + panel.h <= h - 78);

    // Buttons stay inside the panel and do not overlap.
    var d: u8 = 0;
    while (d < 7) : (d += 1) {
        const r = get_distaff_note_button_rect(d, panel);
        try testing.expect(r.x >= panel.x and r.x + r.w <= panel.x + panel.w);
        if (d > 0) try testing.expect(r.x >= get_distaff_note_button_rect(d - 1, panel).x + DISTAFF_BUTTON_W);
        const cx = r.x + @divTrunc(r.w, 2);
        const cy = r.y + @divTrunc(r.h, 2);
        try testing.expectEqual(@as(?u8, d), hit_test_distaff_note(cx, cy, w, h, 7));
    }

    // Beyond reach, a note button does not respond.
    const b_rect = get_distaff_note_button_rect(6, panel);
    try testing.expectEqual(@as(?u8, null), hit_test_distaff_note(b_rect.x + 2, b_rect.y + 2, w, h, 3));
    try testing.expectEqual(@as(?u8, null), hit_test_distaff_note(5, 5, w, h, 7));

    // Pitch maps upward; E4 sits on the bottom staff line, and noteheads stay in the panel.
    try testing.expectEqual(distaff_staff_bottom(panel), get_distaff_note_y(2, panel));
    try testing.expect(get_distaff_note_y(6, panel) < get_distaff_note_y(0, panel));
    try testing.expect(get_distaff_note_y(0, panel) + 5 < get_distaff_note_button_rect(0, panel).y);
    try testing.expect(get_distaff_note_y(6, panel) - 5 > panel.y + 14);

    try testing.expectEqual(@as(?u8, 0), distaff_key_to_degree(c.SDLK_c));
    try testing.expectEqual(@as(?u8, 5), distaff_key_to_degree(c.SDLK_a));
    try testing.expectEqual(@as(?u8, null), distaff_key_to_degree(c.SDLK_h));
}

test "P32-02a: an offscreen window draws deterministically and hashes what it drew" {
    const testing = std.testing;
    var window = try DisplayWindow.init_offscreen(640, 360);
    defer window.deinit();
    try testing.expect(!window.is_headless);

    var frame = std.mem.zeroes(RenderFrame);
    window.render_frame(&frame, true);
    const paused = window.frame_hash().?;
    window.render_frame(&frame, true);
    try testing.expectEqual(paused, window.frame_hash().?);

    // A different frame gives different pixels.
    window.render_frame(&frame, false);
    try testing.expect(window.frame_hash().? != paused);

    // Only an offscreen window has a frame to hash.
    const headless = DisplayWindow{
        .window = null,
        .renderer = null,
        .width = 640,
        .height = 360,
        .is_headless = true,
        .audio_bridge = window.audio_bridge,
        .owned_save_manager = window.owned_save_manager,
        .save_manager = window.save_manager,
    };
    try testing.expectEqual(@as(?u64, null), headless.frame_hash());
}

const ThemeProbe = struct {
    var props: usize = 0;
    var actors: usize = 0;
    var walkways: usize = 0;

    fn reset() void {
        props = 0;
        actors = 0;
        walkways = 0;
    }
    fn decline_backdrop(_: *DisplayWindow, _: *const RenderFrame) bool {
        return false;
    }
    fn paint_backdrop(w: *DisplayWindow, _: *const RenderFrame) bool {
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 10, .g = 90, .b = 60 });
        return true;
    }
    fn count_prop(_: *DisplayWindow, _: *const RenderFrame, view: PropView) bool {
        props += 1;
        return view.index == 0; // draws nothing for the first prop, declines the second
    }
    fn count_actor(_: *DisplayWindow, _: *const RenderFrame, _: ActorView) bool {
        actors += 1;
        return false;
    }
    fn count_walkway(_: *DisplayWindow, _: *const RenderFrame, _: Point, _: Point) bool {
        walkways += 1;
        return false;
    }
    fn hide(_: *const RenderFrame) bool {
        return false;
    }
    fn hint(_: *const RenderFrame) ?FooterHint {
        return .{ .text = "[X]: Probe" };
    }
};

test "P32-02b: a theme draws what it claims and the engine draws the rest" {
    const testing = std.testing;
    var window = try DisplayWindow.init_offscreen(640, 360);
    defer window.deinit();

    var frame = std.mem.zeroes(RenderFrame);
    frame.hotspot_count = 2;
    frame.hotspots[1].x = 10;
    frame.entity_count = 1;
    frame.waypoint_count = 2;
    frame.waypoints[0].id = 1;
    frame.waypoints[1].id = 2;
    frame.waypoints[1].x = 20;
    frame.edge_count = 1;
    frame.edges[0] = .{ .from = 1, .to = 2 };

    window.render_frame(&frame, true);
    const plain = window.frame_hash().?;

    // A theme that declines everything changes nothing, and is asked about every element.
    ThemeProbe.reset();
    const declining = Theme{
        .backdrop = ThemeProbe.decline_backdrop,
        .actor = ThemeProbe.count_actor,
        .walkway = ThemeProbe.count_walkway,
    };
    window.set_theme(&declining);
    window.render_frame(&frame, true);
    try testing.expectEqual(plain, window.frame_hash().?);
    try testing.expectEqual(@as(usize, 1), ThemeProbe.actors);
    try testing.expectEqual(@as(usize, 1), ThemeProbe.walkways);

    // Each claimed element changes the picture: a backdrop, a prop the theme takes over,
    // hidden walkways, a footer hint.
    const cases = [_]Theme{
        .{ .backdrop = ThemeProbe.paint_backdrop },
        .{ .prop = ThemeProbe.count_prop },
        .{ .shows_walkways = ThemeProbe.hide },
        .{ .footer = ThemeProbe.hint },
    };
    var seen: [cases.len]u64 = undefined;
    for (&cases, 0..) |*theme, i| {
        ThemeProbe.reset();
        window.set_theme(theme);
        window.render_frame(&frame, true);
        seen[i] = window.frame_hash().?;
        try testing.expect(seen[i] != plain);
        for (seen[0..i]) |earlier| try testing.expect(seen[i] != earlier);
        if (theme.prop != null) try testing.expectEqual(@as(usize, 2), ThemeProbe.props);
    }

    // Removing the theme restores the neutral picture.
    window.set_theme(null);
    window.render_frame(&frame, true);
    try testing.expectEqual(plain, window.frame_hash().?);
}

test "P32-02c: a host key binding returns its action before the engine's own key" {
    const testing = std.testing;
    if (c.SDL_InitSubSystem(c.SDL_INIT_EVENTS) != 0) return error.SkipZigTest;
    defer c.SDL_QuitSubSystem(c.SDL_INIT_EVENTS);

    var window = try DisplayWindow.init_offscreen(640, 360);
    defer window.deinit();
    const frame = std.mem.zeroes(RenderFrame);

    const Press = struct {
        fn key(w: *DisplayWindow, f: *const RenderFrame, sym: c.SDL_Keycode) UserAction {
            // A poll that returned early leaves SDL's poll sentinel queued, and the next poll
            // would stop at it before reaching this key (the key would arrive a frame later).
            c.SDL_FlushEvents(c.SDL_FIRSTEVENT, c.SDL_LASTEVENT);
            var ev = std.mem.zeroes(c.SDL_Event);
            ev.type = c.SDL_KEYDOWN;
            ev.key.keysym.sym = sym;
            _ = c.SDL_PushEvent(&ev);
            return w.poll_events(f);
        }
    };

    // Without a theme, an unbound letter does nothing and the engine keeps its own keys.
    try testing.expectEqual(UserAction.none, Press.key(&window, &frame, c.SDLK_s));
    try testing.expectEqual(UserAction.step_tick, Press.key(&window, &frame, c.SDLK_n));

    const theme = Theme{ .keys = &.{
        .{ .key = c.SDLK_s, .action = 7 },
        .{ .key = c.SDLK_c, .action = 9 },
    } };
    window.set_theme(&theme);
    try testing.expectEqual(UserAction{ .custom = 7 }, Press.key(&window, &frame, c.SDLK_s));
    // The binding wins over the engine's REPL letter; the console stays closed.
    try testing.expectEqual(UserAction{ .custom = 9 }, Press.key(&window, &frame, c.SDLK_c));
    try testing.expect(!window.show_console);
    try testing.expectEqual(UserAction.step_tick, Press.key(&window, &frame, c.SDLK_n));
}

test "P26-03: the command bar takes every key while focused and submits typed lines" {
    const testing = std.testing;
    if (c.SDL_InitSubSystem(c.SDL_INIT_EVENTS) != 0) return error.SkipZigTest;
    defer c.SDL_QuitSubSystem(c.SDL_INIT_EVENTS);

    var window = try DisplayWindow.init_offscreen(640, 360);
    defer window.deinit();
    const frame = std.mem.zeroes(RenderFrame);
    const keys = [_]KeyBinding{.{ .key = c.SDLK_t, .action = 7 }};
    const theme = Theme{ .keys = &keys };
    window.set_theme(&theme);

    const Input = struct {
        fn key(w: *DisplayWindow, f: *const RenderFrame, sym: c.SDL_Keycode) UserAction {
            c.SDL_FlushEvents(c.SDL_FIRSTEVENT, c.SDL_LASTEVENT);
            var ev = std.mem.zeroes(c.SDL_Event);
            ev.type = c.SDL_KEYDOWN;
            ev.key.keysym.sym = sym;
            _ = c.SDL_PushEvent(&ev);
            return w.poll_events(f);
        }
        // A synthetic SDL_TEXTINPUT crashes inside the SDL2-on-SDL3 compatibility layer, so text
        // goes straight to the handler the event calls; keys still travel through SDL.
        fn text(w: *DisplayWindow, f: *const RenderFrame, s: []const u8) void {
            _ = f;
            w.command_bar_text(s);
        }
    };

    // Disabled: Enter does nothing special, and bindings work.
    try testing.expectEqual(UserAction{ .custom = 7 }, Input.key(&window, &frame, c.SDLK_t));
    window.enable_command_bar(true);
    try testing.expectEqual(UserAction.none, Input.key(&window, &frame, c.SDLK_RETURN));
    try testing.expect(window.command_bar_focused);

    // Focused: the bound letter and the step key are text, not actions.
    try testing.expectEqual(UserAction.none, Input.key(&window, &frame, c.SDLK_t));
    try testing.expectEqual(UserAction.none, Input.key(&window, &frame, c.SDLK_n));
    Input.text(&window, &frame, "take sl");
    window.command_words.add("slip");
    window.command_words.add("take");
    _ = Input.key(&window, &frame, c.SDLK_TAB);
    try testing.expectEqualStrings("take slip ", window.command_input[0..window.command_len]);
    _ = Input.key(&window, &frame, c.SDLK_BACKSPACE);
    const submitted = Input.key(&window, &frame, c.SDLK_RETURN);
    try testing.expectEqualStrings("take slip", submitted.typed_command.buf[0..submitted.typed_command.len]);
    try testing.expectEqual(@as(usize, 0), window.command_len);

    // History: Up recalls the last line, Down past the end clears it.
    Input.text(&window, &frame, "read log");
    _ = Input.key(&window, &frame, c.SDLK_RETURN);
    _ = Input.key(&window, &frame, c.SDLK_UP);
    try testing.expectEqualStrings("read log", window.command_input[0..window.command_len]);
    _ = Input.key(&window, &frame, c.SDLK_UP);
    try testing.expectEqualStrings("take slip", window.command_input[0..window.command_len]);
    _ = Input.key(&window, &frame, c.SDLK_DOWN);
    _ = Input.key(&window, &frame, c.SDLK_DOWN);
    try testing.expectEqual(@as(usize, 0), window.command_len);

    // Esc leaves the bar; keys act again.
    _ = Input.key(&window, &frame, c.SDLK_ESCAPE);
    try testing.expect(!window.command_bar_focused);
    try testing.expectEqual(UserAction{ .custom = 7 }, Input.key(&window, &frame, c.SDLK_t));
    try testing.expectEqual(UserAction.step_tick, Input.key(&window, &frame, c.SDLK_n));
}

test "P27-01: the State tab cycles in with Tab and never saves or loads" {
    const testing = std.testing;
    if (c.SDL_InitSubSystem(c.SDL_INIT_EVENTS) != 0) return error.SkipZigTest;
    defer c.SDL_QuitSubSystem(c.SDL_INIT_EVENTS);
    var window = try DisplayWindow.init_offscreen(640, 360);
    defer window.deinit();
    const frame = std.mem.zeroes(RenderFrame);
    const Press = struct {
        fn key(w: *DisplayWindow, f: *const RenderFrame, sym: c.SDL_Keycode) UserAction {
            c.SDL_FlushEvents(c.SDL_FIRSTEVENT, c.SDL_LASTEVENT);
            var ev = std.mem.zeroes(c.SDL_Event);
            ev.type = c.SDL_KEYDOWN;
            ev.key.keysym.sym = sym;
            _ = c.SDL_PushEvent(&ev);
            return w.poll_events(f);
        }
    };
    window.show_save_drawer = true;
    try testing.expectEqual(SaveMenuMode.save, window.save_menu_mode);
    _ = Press.key(&window, &frame, c.SDLK_TAB);
    _ = Press.key(&window, &frame, c.SDLK_TAB);
    try testing.expectEqual(SaveMenuMode.state, window.save_menu_mode);
    try testing.expectEqual(UserAction.none, Press.key(&window, &frame, c.SDLK_RETURN));
    try testing.expectEqual(UserAction.none, Press.key(&window, &frame, c.SDLK_3));
    try testing.expectEqual(UserAction.none, Press.key(&window, &frame, c.SDLK_SPACE));
    _ = Press.key(&window, &frame, c.SDLK_TAB);
    try testing.expectEqual(SaveMenuMode.save, window.save_menu_mode);
    _ = Press.key(&window, &frame, c.SDLK_TAB);
    _ = Press.key(&window, &frame, c.SDLK_TAB);
    try testing.expectEqual(UserAction.toggle_save_drawer, Press.key(&window, &frame, c.SDLK_ESCAPE));
    try testing.expect(!window.show_save_drawer);
}

test "P27-03: State tab keys select, recentre, go back, reset, filter, and click without saving" {
    const testing = std.testing;
    if (c.SDL_InitSubSystem(c.SDL_INIT_EVENTS) != 0) return error.SkipZigTest;
    defer c.SDL_QuitSubSystem(c.SDL_INIT_EVENTS);
    var window = try DisplayWindow.init_offscreen(640, 360);
    defer window.deinit();
    const Fact = struct {
        fn make(subject: u32, subject_name: []const u8, relation: []const u8, object: u32, object_name: []const u8) display_mod.RenderDebugFact {
            var f = std.mem.zeroes(display_mod.RenderDebugFact);
            @memcpy(f.subject_name[0..subject_name.len], subject_name);
            f.subject_len = @intCast(subject_name.len);
            @memcpy(f.relation_name[0..relation.len], relation);
            f.relation_len = @intCast(relation.len);
            @memcpy(f.object_name[0..object_name.len], object_name);
            f.object_len = @intCast(object_name.len);
            f.subject = display_mod.EntityId.from_int(subject);
            f.object_raw = object;
            f.object_is_entity = true;
            return f;
        }
    };
    var frame = std.mem.zeroes(RenderFrame);
    const facts = [_]display_mod.RenderDebugFact{
        Fact.make(5, "Ines", "Carries", 9, "Slip"),
        Fact.make(5, "Ines", "Believes", 12, "PellAlibi"),
        Fact.make(8, "Halloran", "Warned", 5, "Ines"),
        Fact.make(9, "Slip", "LyingIn", 11, "Archive"),
    };
    @memcpy(frame.debug_facts[0..facts.len], &facts);
    frame.debug_fact_count = facts.len;
    const Press = struct {
        fn key(w: *DisplayWindow, f: *const RenderFrame, sym: c.SDL_Keycode) UserAction {
            c.SDL_FlushEvents(c.SDL_FIRSTEVENT, c.SDL_LASTEVENT);
            var ev = std.mem.zeroes(c.SDL_Event);
            ev.type = c.SDL_KEYDOWN;
            ev.key.keysym.sym = sym;
            _ = c.SDL_PushEvent(&ev);
            return w.poll_events(f);
        }
        fn click(w: *DisplayWindow, f: *const RenderFrame, x: i32, y: i32) UserAction {
            c.SDL_FlushEvents(c.SDL_FIRSTEVENT, c.SDL_LASTEVENT);
            var ev = std.mem.zeroes(c.SDL_Event);
            ev.type = c.SDL_MOUSEBUTTONDOWN;
            ev.button.button = c.SDL_BUTTON_LEFT;
            ev.button.x = x;
            ev.button.y = y;
            _ = c.SDL_PushEvent(&ev);
            return w.poll_events(f);
        }
    };
    window.show_save_drawer = true;
    window.save_menu_mode = .state;
    const id = display_mod.EntityId.from_int;

    // Ines (5) is the default centre; her ring is Halloran (8), Slip (9), PellAlibi (12).
    try testing.expectEqual(UserAction.none, Press.key(&window, &frame, c.SDLK_RIGHT));
    try testing.expectEqual(@as(usize, 1), window.inspector_selected);
    _ = Press.key(&window, &frame, c.SDLK_LEFT);
    _ = Press.key(&window, &frame, c.SDLK_LEFT);
    try testing.expectEqual(@as(usize, 2), window.inspector_selected);
    _ = Press.key(&window, &frame, c.SDLK_RIGHT);
    _ = Press.key(&window, &frame, c.SDLK_RIGHT);
    // Enter centres on Slip and remembers Ines; Slip's ring is Ines (5), Archive (11).
    try testing.expectEqual(UserAction.none, Press.key(&window, &frame, c.SDLK_RETURN));
    try testing.expectEqual(@as(?display_mod.EntityId, id(9)), window.inspector_focus);
    try testing.expectEqual(@as(usize, 1), window.inspector_history_len);
    try testing.expectEqual(@as(usize, 0), window.inspector_selected);
    _ = Press.key(&window, &frame, c.SDLK_BACKSPACE);
    try testing.expectEqual(@as(?display_mod.EntityId, id(5)), window.inspector_focus);
    try testing.expectEqual(@as(usize, 0), window.inspector_history_len);
    // Backspace with no history and Home both leave the default centre.
    _ = Press.key(&window, &frame, c.SDLK_BACKSPACE);
    try testing.expectEqual(@as(?display_mod.EntityId, id(5)), window.inspector_focus);
    _ = Press.key(&window, &frame, c.SDLK_HOME);
    try testing.expectEqual(@as(?display_mod.EntityId, null), window.inspector_focus);

    // F cycles the filter: beliefs leave Ines one neighbour, so Right stays on it.
    _ = Press.key(&window, &frame, c.SDLK_f);
    try testing.expectEqual(state_graph.Filter.Kind.beliefs, window.inspector_filter.kind);
    _ = Press.key(&window, &frame, c.SDLK_RIGHT);
    try testing.expectEqual(@as(usize, 0), window.inspector_selected);
    _ = Press.key(&window, &frame, c.SDLK_f);
    try testing.expectEqualStrings("Believes", window.inspector_filter.relation());
    for (0..4) |_| _ = Press.key(&window, &frame, c.SDLK_f);
    try testing.expectEqual(state_graph.Filter.Kind.all, window.inspector_filter.kind);

    // A click on a ring node recentres; the drawer stays open and nothing saves or loads.
    const layout = window.inspector_layout(&frame).?;
    const halloran = layout.ring[0];
    try testing.expectEqual(id(8), halloran.entity);
    try testing.expectEqual(UserAction.none, Press.click(&window, &frame, halloran.x, halloran.y));
    try testing.expectEqual(@as(?display_mod.EntityId, id(8)), window.inspector_focus);
    try testing.expect(window.show_save_drawer);

    // A focus the frame no longer mentions falls back to the default and drops the history.
    frame.debug_fact_count = 1;
    try testing.expectEqual(UserAction.none, Press.key(&window, &frame, c.SDLK_RIGHT));
    try testing.expectEqual(@as(?display_mod.EntityId, null), window.inspector_focus);
    try testing.expectEqual(@as(usize, 0), window.inspector_history_len);
    try testing.expectEqual(UserAction.toggle_save_drawer, Press.key(&window, &frame, c.SDLK_ESCAPE));
}

test "D-080: click-through messages hide the choices until each is dismissed" {
    const testing = std.testing;
    if (c.SDL_InitSubSystem(c.SDL_INIT_EVENTS) != 0) return error.SkipZigTest;
    defer c.SDL_QuitSubSystem(c.SDL_INIT_EVENTS);
    var window = try DisplayWindow.init_offscreen(1280, 720);
    defer window.deinit();
    const frame = std.mem.zeroes(RenderFrame);
    const Input = struct {
        fn key(w: *DisplayWindow, f: *const RenderFrame, sym: c.SDL_Keycode) UserAction {
            c.SDL_FlushEvents(c.SDL_FIRSTEVENT, c.SDL_LASTEVENT);
            var ev = std.mem.zeroes(c.SDL_Event);
            ev.type = c.SDL_KEYDOWN;
            ev.key.keysym.sym = sym;
            _ = c.SDL_PushEvent(&ev);
            return w.poll_events(f);
        }
        fn click(w: *DisplayWindow, f: *const RenderFrame, x: i32, y: i32) UserAction {
            c.SDL_FlushEvents(c.SDL_FIRSTEVENT, c.SDL_LASTEVENT);
            var ev = std.mem.zeroes(c.SDL_Event);
            ev.type = c.SDL_MOUSEBUTTONDOWN;
            ev.button.button = c.SDL_BUTTON_LEFT;
            ev.button.x = x;
            ev.button.y = y;
            _ = c.SDL_PushEvent(&ev);
            return w.poll_events(f);
        }
    };

    const choices = [_][]const u8{ "First answer", "Second answer" };
    window.show_dialogue(.none, .{ .x = 0, .y = 0 }, "HarbourWarden", "A question?", &choices);
    window.queue_message("HarbourWarden", "A line said aloud.");
    window.queue_message("", "Their point.");
    try testing.expect(window.has_messages());
    try testing.expectEqualStrings("Harbour Warden", window.messages.front().?.speaker());

    // Number keys cannot answer the hidden choices; Enter dismisses one message.
    try testing.expectEqual(UserAction.none, Input.key(&window, &frame, c.SDLK_1));
    try testing.expectEqual(UserAction.none, Input.key(&window, &frame, c.SDLK_RETURN));
    try testing.expectEqualStrings("Their point.", window.messages.front().?.text());

    // A click on the first choice's place dismisses the last message instead of answering.
    const panel = window.dialogue_panel_for(&window.active_balloon.?);
    const choice_y = panel.rect.y + panel.layout.choice_top[0] + 4;
    try testing.expectEqual(UserAction.none, Input.click(&window, &frame, panel.rect.x + 80, choice_y));
    try testing.expect(!window.has_messages());

    // With every message read, the choices answer again.
    try testing.expectEqual(UserAction{ .dialogue_choice = 0 }, Input.click(&window, &frame, panel.rect.x + 80, choice_y));
}
