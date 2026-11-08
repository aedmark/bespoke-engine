const std = @import("std");
const display_mod = @import("../display.zig");
const audio_mod = @import("../audio.zig");
const save_mod = @import("../save.zig");
const font = @import("font.zig");

pub const SoundEffectKind = audio_mod.SoundEffectKind;
pub const MusicTrackKind = audio_mod.MusicTrackKind;
pub const AudioBridge = audio_mod.AudioBridge;
pub const SaveManager = save_mod.SaveManager;
pub const SaveMetadata = save_mod.SaveMetadata;
pub const SaveSlotInfo = save_mod.SaveSlotInfo;

pub const SaveMenuMode = enum(u8) {
    save = 0,
    load = 1,
};

pub const SaveDrawerTab = enum(u8) {
    save_mode = 0,
    load_mode = 1,
    resume_game = 2,
    quit_game = 3,
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
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const tavern_bg = Color{ .r = 22, .g = 18, .b = 16 };
    pub const tavern_room = Color{ .r = 38, .g = 28, .b = 24 };
    pub const tavern_border = Color{ .r = 61, .g = 46, .b = 39 };
    pub const cellar_room = Color{ .r = 24, .g = 30, .b = 41 };
    pub const cellar_border = Color{ .r = 45, .g = 55, .b = 72 };
    pub const path_corridor = Color{ .r = 55, .g = 48, .b = 43 };
    pub const path_edge = Color{ .r = 75, .g = 68, .b = 60 };

    pub const wp_normal = Color{ .r = 100, .g = 116, .b = 139 };
    pub const wp_hover = Color{ .r = 251, .g = 191, .b = 36 };
    pub const wp_target = Color{ .r = 56, .g = 189, .b = 248 };

    pub const cat_color = Color{ .r = 234, .g = 88, .b = 12 }; // Orange
    pub const guard_color = Color{ .r = 37, .g = 99, .b = 235 }; // Steel Blue
    pub const bard_color = Color{ .r = 147, .g = 51, .b = 234 }; // Purple
    pub const cheese_color = Color{ .r = 250, .g = 204, .b = 21 }; // Gold

    // Booty Island Spitting Contest Colors (P10-03, D-012)
    pub const guybrush_coat = Color{ .r = 30, .g = 64, .b = 175 }; // Pirate Blue
    pub const guybrush_hair = Color{ .r = 250, .g = 204, .b = 21 }; // Blonde
    pub const organiser_coat = Color{ .r = 185, .g = 28, .b = 28 }; // Velvet Red
    pub const onlookers_color = Color{ .r = 120, .g = 80, .b = 140 }; // Purple Crowd
    pub const flag_color = Color{ .r = 239, .g = 68, .b = 68 }; // Red flag
    pub const flag_tampered = Color{ .r = 245, .g = 158, .b = 11 }; // Gold flag
    pub const wind_color = Color{ .r = 56, .g = 189, .b = 248 }; // Sky Blue
    pub const spit_color = Color{ .r = 34, .g = 197, .b = 94 }; // Lime Spit
    pub const grass_green = Color{ .r = 30, .g = 68, .b = 38 };
    pub const sand_color = Color{ .r = 180, .g = 160, .b = 110 };
    pub const ocean_blue = Color{ .r = 14, .g = 70, .b = 110 };
    pub const sky_dusk = Color{ .r = 16, .g = 24, .b = 48 };

    // Gabriel Knight 3 Scenario Colors (P14-02, D-016)
    pub const gabriel_coat = Color{ .r = 180, .g = 115, .b = 50 }; // Tan leather trench coat
    pub const gabriel_hair = Color{ .r = 245, .g = 215, .b = 110 }; // Signature blonde hair
    pub const mosely_suit = Color{ .r = 40, .g = 50, .b = 85 }; // Detective navy suit
    pub const buthane_vest = Color{ .r = 190, .g = 45, .b = 60 }; // Crimson shopkeeper vest
    pub const buthane_hair = Color{ .r = 180, .g = 70, .b = 30 }; // Auburn hair
    pub const stray_cat_color = Color{ .r = 25, .g = 25, .b = 30 }; // Black stray cat
    pub const cat_eye_color = Color{ .r = 50, .g = 220, .b = 90 }; // Piercing green eyes
    pub const hotel_wallpaper = Color{ .r = 95, .g = 25, .b = 32 }; // Burgundy damask
    pub const hotel_wainscot = Color{ .r = 45, .g = 22, .b = 15 }; // Dark polished mahogany
    pub const hotel_door = Color{ .r = 65, .g = 35, .b = 20 }; // French room door
    pub const garden_sky = Color{ .r = 140, .g = 185, .b = 225 }; // Southern French sky
    pub const garden_grass = Color{ .r = 55, .g = 115, .b = 50 }; // Courtyard greenery
    pub const garden_fence = Color{ .r = 150, .g = 95, .b = 50 }; // Wooden picket fence
    pub const rental_wall = Color{ .r = 75, .g = 65, .b = 55 }; // French stone plaster
    pub const rental_counter = Color{ .r = 160, .g = 100, .b = 45 }; // Pine shop counter
    pub const motorcycle_red = Color{ .r = 220, .g = 38, .b = 38 }; // Shiny red motorcycle

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
    rewind,
    scrub_to_tick: u64, // Interactive time-travel timeline scrubber (P9-02, D-011)
    repl_command: struct {
        buf: [128]u8,
        len: usize,
    }, // Live interactive REPL console command (P9-03, D-011)
    toggle_debug,
    toggle_console,
    spit_contest_spit,
    sound_horn,
    drink_green_drink,
    tamper_flags,
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
        const hit_radius: i64 = WAYPOINT_SCREEN_RADIUS + 8;
        if (dist_sq <= hit_radius * hit_radius) {
            return wp.id;
        }
    }
    return null;
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

/// Active speech balloon or branching dialogue tree (P7-04, P13-03, D-009, D-015).
pub const SpeechBalloon = struct {
    speaker: EntityId,
    speaker_pos: Point,
    speaker_name: [32]u8,
    speaker_name_len: u8,
    text: [160]u8,
    text_len: u8,
    ticks_remaining: u32,
    choices: [9][80]u8,
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

/// Computes screen bounding rectangle for speech balloon (P7-04, P13-03, D-015).
pub fn get_balloon_rect(balloon: *const SpeechBalloon, screen_w: i32) c.SDL_Rect {
    const text_w = font.text_width(balloon.get_text(), 2);
    const title_w = font.text_width(balloon.get_speaker_name(), 2) + 40;
    var max_w = @max(text_w, title_w);
    var i: usize = 0;
    while (i < balloon.choice_count) : (i += 1) {
        max_w = @max(max_w, font.text_width(balloon.get_choice(i), 2) + 54);
    }
    const bw = @min(screen_w - 40, @max(280, max_w + 32));
    const visible_count = balloon.visible_choice_count();
    const has_scroll = balloon.choice_count > 6;
    const scroll_h: i32 = if (has_scroll) 18 else 0;
    const bh: i32 = 48 + @as(i32, @intCast(visible_count)) * 26 + scroll_h;

    const bx = @max(20, @min(screen_w - bw - 20, balloon.speaker_pos.x - @divTrunc(bw, 2)));
    const by = @max(76, balloon.speaker_pos.y - bh - 24);

    return c.SDL_Rect{ .x = bx, .y = by, .w = bw, .h = bh };
}

/// Hit-tests mouse coordinates against dialogue choice options (P7-04, P13-03, D-015).
pub fn hit_test_balloon_choice(mouse_x: i32, mouse_y: i32, balloon: *const SpeechBalloon, rect: c.SDL_Rect) ?u8 {
    if (balloon.choice_count == 0) return null;
    const choices_start_y = rect.y + 42;
    const visible_count = balloon.visible_choice_count();
    var vi: usize = 0;
    while (vi < visible_count) : (vi += 1) {
        const actual_idx: u8 = balloon.scroll_offset + @as(u8, @intCast(vi));
        if (actual_idx >= balloon.choice_count) break;

        const cy = choices_start_y + @as(i32, @intCast(vi)) * 26;
        if (mouse_x >= rect.x + 12 and mouse_x <= rect.x + rect.w - 12 and
            mouse_y >= cy and mouse_y <= cy + 22)
        {
            return actual_idx;
        }
    }
    return null;
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
    if (mouse_x >= drawer_rect.x + drawer_rect.w - 270 and mouse_x <= drawer_rect.x + drawer_rect.w - 140) return .resume_game;
    if (mouse_x >= drawer_rect.x + drawer_rect.w - 130 and mouse_x <= drawer_rect.x + drawer_rect.w - 20) return .quit_game;
    return null;
}

/// The SDL2 peripheral window consumer (D-001, D-008, P6-01 through P6-04).
pub const DisplayWindow = struct {
    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,
    width: i32,
    height: i32,
    active_verb: AdventureVerb = .walk,
    hovered_wp: ?WaypointId = null,
    hovered_hotspot: ?usize = null,
    hovered_actor: ?usize = null,
    target_wp: ?WaypointId = null,
    active_balloon: ?SpeechBalloon = null,
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
        };
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
            if (self.window) |w| c.SDL_DestroyWindow(w);
            c.SDL_Quit();
        }
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
        switch (action) {
            .toggle_save_drawer => {
                if (self.show_save_drawer) {
                    is_paused.* = true;
                }
                return true;
            },
            .quick_save => {
                if (self.save_manager.quick_save(world, spatial, vm)) |meta| {
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
                if (self.save_manager.quick_load(world, spatial, vm)) |res| {
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
                if (self.save_manager.save_slot(slot_id, world, spatial, vm, desc)) |meta| {
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
                if (self.save_manager.load_slot(slot_id, world, spatial, vm)) |res| {
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
    pub fn set_bgm(self: *DisplayWindow, track: audio_mod.MusicTrackKind) void {
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
            .ticks_remaining = 360,
            .choices = undefined,
            .choice_lens = [_]u8{0} ** 9,
            .choice_count = 0,
            .scroll_offset = 0,
        };

        const nlen = @min(speaker_name.len, sb.speaker_name.len);
        @memcpy(sb.speaker_name[0..nlen], speaker_name[0..nlen]);
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

    /// Dismisses active speech balloon.
    pub fn dismiss_dialogue(self: *DisplayWindow) void {
        self.active_balloon = null;
        self.hovered_choice = null;
    }

    /// Appends a line to the REPL console history buffer (P9-03, D-011).
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

                    if (self.active_balloon) |*b| {
                        const brect = get_balloon_rect(b, self.width);
                        self.hovered_choice = hit_test_balloon_choice(event.motion.x, event.motion.y, b, brect);
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
                                    .resume_game => {
                                        self.show_save_drawer = false;
                                        return .toggle_save_drawer;
                                    },
                                    .quit_game => return .quit,
                                }
                            }
                            if (hit_test_save_slot(event.button.x, event.button.y, drect)) |slot_id| {
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

                    if (self.active_balloon) |*b| {
                        const brect = get_balloon_rect(b, self.width);
                        if (hit_test_balloon_choice(event.button.x, event.button.y, b, brect)) |ch_idx| {
                            self.play_sfx(.dialogue_blip);
                            return .{ .dialogue_choice = ch_idx };
                        } else {
                            self.dismiss_dialogue();
                            self.play_sfx(.click);
                            return .dismiss_dialogue;
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

                        // 3. Check Inventory items (P11-03, D-013)
                        const clicked_item_idx = hit_test_inventory_item(event.button.x, event.button.y, self.height, frame.inventory[0..frame.inventory_count]);
                        if (clicked_item_idx) |idx| {
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
                                // 6. Check Waypoints
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
                                    if (self.active_verb == .walk) {
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
                    if (self.show_console) {
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

                    if (self.show_save_drawer) {
                        if (sym == c.SDLK_ESCAPE or sym == c.SDLK_p) {
                            self.show_save_drawer = false;
                            self.play_sfx(.click);
                            return .toggle_save_drawer;
                        } else if (sym == c.SDLK_TAB or sym == c.SDLK_LEFT or sym == c.SDLK_RIGHT) {
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

                    switch (sym) {
                        c.SDLK_s => {
                            self.play_sfx(.whistle);
                            action = .spit_contest_spit;
                        },
                        c.SDLK_h => {
                            self.play_sfx(.horn);
                            action = .sound_horn;
                        },
                        c.SDLK_g => {
                            self.play_sfx(.pickup);
                            action = .drink_green_drink;
                        },
                        c.SDLK_f => {
                            self.play_sfx(.combine);
                            action = .tamper_flags;
                        },
                        c.SDLK_SPACE => action = .toggle_pause,
                        c.SDLK_n => action = .step_tick,
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

        // Trigger procedural music and cue audio reactions (P16-01, P16-03, D-019)
        self.audio_bridge.process_scene_and_cues(frame.get_current_scene());

        // Detect active scene theme (P12-03, P14-02, D-014, D-016)
        const cur_scene = frame.get_current_scene();
        var is_spitting_scene = false;
        var is_wine_cellar_scene = false;
        var is_tavern_scene = false;
        var is_hotel_scene = false;
        var is_garden_scene = false;
        var is_bike_rental_scene = false;
        var is_high_road_scene = false;
        var is_sanctuary_scene = false;
        var is_scumm_bar_scene = false;

        if (cur_scene.len > 0) {
            if (std.mem.indexOf(u8, cur_scene, "High Road") != null or
                std.mem.indexOf(u8, cur_scene, "Road") != null)
            {
                is_high_road_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Sanctuary") != null or
                       std.mem.indexOf(u8, cur_scene, "Sword Master") != null)
            {
                is_sanctuary_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Scumm") != null or
                       std.mem.indexOf(u8, cur_scene, "Scumm Bar") != null)
            {
                is_scumm_bar_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Spit") != null or
                std.mem.indexOf(u8, cur_scene, "Booty") != null)
            {
                is_spitting_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Cellar") != null) {
                is_wine_cellar_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Tavern") != null or
                       std.mem.indexOf(u8, cur_scene, "Common") != null)
            {
                is_tavern_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Garden") != null or
                       std.mem.indexOf(u8, cur_scene, "Courtyard") != null)
            {
                is_garden_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Corridor") != null or
                       std.mem.eql(u8, cur_scene, "Hotel Corridor"))
            {
                is_hotel_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Bike") != null or
                       std.mem.indexOf(u8, cur_scene, "Rental") != null or
                       std.mem.indexOf(u8, cur_scene, "Shop") != null)
            {
                is_bike_rental_scene = true;
            } else if (std.mem.indexOf(u8, cur_scene, "Hotel") != null) {
                is_hotel_scene = true;
            }
        }

        // Fallback detection if current_scene wasn't explicitly set
        if (!is_spitting_scene and !is_wine_cellar_scene and !is_tavern_scene and
            !is_hotel_scene and !is_garden_scene and !is_bike_rental_scene and
            !is_high_road_scene and !is_sanctuary_scene and !is_scumm_bar_scene)
        {
            for (frame.waypoints[0..frame.waypoint_count]) |wp| {
                if (std.mem.indexOf(u8, wp.get_name(), "Road") != null) {
                    is_high_road_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, wp.get_name(), "Sanctuary") != null) {
                    is_sanctuary_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, wp.get_name(), "BarEntrance") != null) {
                    is_scumm_bar_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, wp.get_name(), "Starting Line") != null or
                    std.mem.indexOf(u8, wp.get_name(), "Offstage") != null)
                {
                    is_spitting_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, wp.get_name(), "Fence") != null or
                           std.mem.indexOf(u8, wp.get_name(), "CatLounge") != null or
                           std.mem.indexOf(u8, wp.get_name(), "Garden") != null)
                {
                    is_garden_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, wp.get_name(), "Room25") != null or
                           std.mem.indexOf(u8, wp.get_name(), "Room33") != null or
                           std.mem.indexOf(u8, wp.get_name(), "Corridor") != null)
                {
                    is_hotel_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, wp.get_name(), "Counter") != null or
                           std.mem.indexOf(u8, wp.get_name(), "BikeMark") != null or
                           std.mem.indexOf(u8, wp.get_name(), "ShopEntrance") != null)
                {
                    is_bike_rental_scene = true;
                    break;
                }
            }
            if (!is_spitting_scene and !is_hotel_scene and !is_garden_scene and !is_bike_rental_scene and
                !is_high_road_scene and !is_sanctuary_scene and !is_scumm_bar_scene)
            {
                for (frame.entities[0..frame.entity_count]) |e| {
                    const ename = e.get_name();
                    if (std.mem.eql(u8, ename, "PirateBob") or std.mem.eql(u8, ename, "PiratePegleg")) {
                        is_high_road_scene = true;
                        break;
                    } else if (std.mem.eql(u8, ename, "Carla")) {
                        is_sanctuary_scene = true;
                        break;
                    } else if (std.mem.eql(u8, ename, "Barkeep") or std.mem.eql(u8, ename, "Citizen")) {
                        is_scumm_bar_scene = true;
                        break;
                    } else if (std.mem.eql(u8, ename, "Organiser") or
                               std.mem.eql(u8, ename, "Onlookers"))
                    {
                        is_spitting_scene = true;
                        break;
                    } else if (std.mem.eql(u8, ename, "StrayCat")) {
                        is_garden_scene = true;
                        break;
                    } else if (std.mem.eql(u8, ename, "Buthane")) {
                        is_bike_rental_scene = true;
                        break;
                    } else if (std.mem.eql(u8, ename, "Gabriel") or std.mem.eql(u8, ename, "Mosely")) {
                        is_hotel_scene = true;
                        break;
                    }
                }
            }
            if (!is_spitting_scene and !is_hotel_scene and !is_garden_scene and !is_bike_rental_scene) {
                for (frame.hotspots[0..frame.hotspot_count]) |hs| {
                    if (std.mem.indexOf(u8, hs.get_name(), "Flag") != null) {
                        is_spitting_scene = true;
                        break;
                    } else if (std.mem.indexOf(u8, hs.get_name(), "Fence") != null or
                               std.mem.indexOf(u8, hs.get_name(), "Shrub") != null)
                    {
                        is_garden_scene = true;
                        break;
                    } else if (std.mem.indexOf(u8, hs.get_name(), "Motorcycle") != null or
                               std.mem.indexOf(u8, hs.get_name(), "Rental") != null)
                    {
                        is_bike_rental_scene = true;
                        break;
                    } else if (std.mem.indexOf(u8, hs.get_name(), "Door") != null or
                               std.mem.indexOf(u8, hs.get_name(), "Desk") != null)
                    {
                        is_hotel_scene = true;
                        break;
                    }
                }
            }
        }

        if (is_spitting_scene) {
            // Sky
            self.fill_rect(0, 0, self.width, self.height, Color.sky_dusk);

            // Grassy Contest Field & Ocean
            const field_x: i32 = 40;
            const field_y: i32 = 110;
            const field_w: i32 = self.width - 80;
            const field_h: i32 = 320;

            // Green grass field
            self.fill_rect(field_x, field_y, field_w - 180, field_h, Color.grass_green);
            self.draw_rect_outline(field_x, field_y, field_w - 180, field_h, Color{ .r = 45, .g = 95, .b = 55 });

            // Caribbean Ocean / Looking Offstage
            const ocean_x = field_x + field_w - 180;
            self.fill_rect(ocean_x, field_y, 180, field_h, Color.ocean_blue);
            self.draw_rect_outline(ocean_x, field_y, 180, field_h, Color{ .r = 56, .g = 189, .b = 248 });
            // Sandy shoreline edge
            self.fill_rect(ocean_x - 12, field_y, 12, field_h, Color.sand_color);

            // Ocean label
            self.draw_text("CARIBBEAN SEA", ocean_x + 16, field_y + 16, 2, Color{ .r = 56, .g = 189, .b = 248 });
            self.draw_text("(LOOKING OFFSTAGE)", ocean_x + 16, field_y + 36, 1, Color.white);

            // Field Title Header
            self.draw_text("BOOTY ISLAND - SPITTING COMPETITION", field_x + 16, field_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });

            // Ground distance track lines
            // Starting Line at x=200 (world_x = 0)
            self.draw_line(200, field_y + 60, 200, field_y + field_h - 20, Color.white);
            self.draw_text("START LINE", 165, field_y + field_h - 16, 1, Color.white);

            // 3rd Place Line at x=340 (world_x = 10)
            self.draw_line(340, field_y + 70, 340, field_y + field_h - 30, Color.hud_subtext);
            self.draw_text("3RD PLACE", 315, field_y + field_h - 26, 1, Color.hud_subtext);

            // 2nd Place Line at x=508 (world_x = 22, where Flags stand)
            self.draw_line(508, field_y + 70, 508, field_y + field_h - 30, Color{ .r = 245, .g = 158, .b = 11 });
            self.draw_text("2ND PLACE", 483, field_y + field_h - 26, 1, Color{ .r = 245, .g = 158, .b = 11 });

            // 1st Place Champion Line at x=676 (world_x = 34)
            self.draw_line(676, field_y + 60, 676, field_y + field_h - 20, Color{ .r = 250, .g = 204, .b = 21 });
            self.draw_text("CHAMPION LINE (1ST PLACE)", 600, field_y + field_h - 16, 1, Color{ .r = 250, .g = 204, .b = 21 });

            // Wind Indicator
            if (frame.wind_blowing) {
                self.draw_text(">>> WIND GUST: STRONG TAILWIND (BLOWING EAST TOWARD TARGET!) >>>", field_x + 16, field_y + 44, 2, Color.wind_color);
                self.draw_line(260, field_y + 140, 680, field_y + 140, Color.wind_color);
                self.draw_line(280, field_y + 190, 710, field_y + 190, Color.wind_color);
                self.draw_line(250, field_y + 240, 690, field_y + 240, Color.wind_color);
            } else {
                self.draw_text("WIND: CALM (Wait for tailwind gust)", field_x + 16, field_y + 44, 2, Color.hud_subtext);
            }
        } else if (is_wine_cellar_scene) {
            // Subterranean Stone Vault Theme (P12-03, D-014)
            self.fill_rect(0, 0, self.width, self.height, Color{ .r = 15, .g = 18, .b = 26 });

            const cellar_x: i32 = 40;
            const cellar_y: i32 = 110;
            const cellar_w: i32 = self.width - 80;
            const cellar_h: i32 = 320;

            // Vault chamber floor and stone wall
            self.fill_rect(cellar_x, cellar_y, cellar_w, cellar_h, Color.cellar_room);
            self.draw_rect_outline(cellar_x, cellar_y, cellar_w, cellar_h, Color.cellar_border);

            // Archway stone pillars on left and right borders
            self.fill_rect(cellar_x, cellar_y, 48, cellar_h, Color{ .r = 25, .g = 32, .b = 48 });
            self.draw_rect_outline(cellar_x, cellar_y, 48, cellar_h, Color{ .r = 45, .g = 55, .b = 75 });
            self.fill_rect(cellar_x + cellar_w - 48, cellar_y, 48, cellar_h, Color{ .r = 25, .g = 32, .b = 48 });
            self.draw_rect_outline(cellar_x + cellar_w - 48, cellar_y, 48, cellar_h, Color{ .r = 45, .g = 55, .b = 75 });

            // Stone flagstone grid lines across floor
            var row_y = cellar_y + 80;
            while (row_y < cellar_y + cellar_h) : (row_y += 60) {
                self.draw_line(cellar_x + 48, row_y, cellar_x + cellar_w - 48, row_y, Color{ .r = 35, .g = 42, .b = 58 });
            }

            // Cellar Vault Title Header
            self.draw_text("WINE CELLAR - SUBTERRANEAN VAULT", cellar_x + 60, cellar_y + 16, 2, Color{ .r = 192, .g = 132, .b = 252 });
            self.draw_text("(COOL, DAMP AIR WITH OAK & MUSTY BOUQUET)", cellar_x + 60, cellar_y + 36, 1, Color.hud_subtext);

            // Cellar torchlight sconces on stone pillars
            self.fill_circle(cellar_x + 24, cellar_y + 60, 6, Color{ .r = 245, .g = 158, .b = 11 });
            self.fill_circle(cellar_x + 24, cellar_y + 58, 3, Color{ .r = 254, .g = 240, .b = 138 });
            self.fill_circle(cellar_x + cellar_w - 24, cellar_y + 60, 6, Color{ .r = 245, .g = 158, .b = 11 });
            self.fill_circle(cellar_x + cellar_w - 24, cellar_y + 58, 3, Color{ .r = 254, .g = 240, .b = 138 });
        } else if (is_tavern_scene) {
            // Dedicated Warm Wooden Tavern Common Room Theme (P12-03, D-014)
            self.fill_rect(0, 0, self.width, self.height, Color.tavern_bg);

            const tavern_x: i32 = 40;
            const tavern_y: i32 = 110;
            const tavern_w: i32 = self.width - 80;
            const tavern_h: i32 = 320;

            self.fill_rect(tavern_x, tavern_y, tavern_w, tavern_h, Color.tavern_room);
            self.draw_rect_outline(tavern_x, tavern_y, tavern_w, tavern_h, Color.tavern_border);

            // Timber ceiling beams
            self.fill_rect(tavern_x, tavern_y + 50, tavern_w, 8, Color{ .r = 30, .g = 20, .b = 15 });
            self.fill_rect(tavern_x, tavern_y + 100, tavern_w, 6, Color{ .r = 30, .g = 20, .b = 15 });

            // Title Header
            self.draw_text("TAVERN - COMMON ROOM", tavern_x + 16, tavern_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
            self.draw_text("(WARM FIREPLACE, CLINKING TANKARDS)", tavern_x + 16, tavern_y + 36, 1, Color.hud_subtext);
        } else if (is_hotel_scene) {
            // Hotel des Couronnes Corridor (P14-02, D-016)
            self.fill_rect(0, 0, self.width, self.height, Color{ .r = 20, .g = 12, .b = 15 });

            const hotel_x: i32 = 40;
            const hotel_y: i32 = 110;
            const hotel_w: i32 = self.width - 80;
            const hotel_h: i32 = self.height - 210;

            // Burgundy wallpaper
            self.fill_rect(hotel_x, hotel_y, hotel_w, hotel_h, Color.hotel_wallpaper);
            self.draw_rect_outline(hotel_x, hotel_y, hotel_w, hotel_h, Color{ .r = 140, .g = 40, .b = 45 });

            // Dark mahogany wainscoting
            self.fill_rect(hotel_x, hotel_y + hotel_h - 120, hotel_w, 120, Color.hotel_wainscot);
            self.draw_line(hotel_x, hotel_y + hotel_h - 120, hotel_x + hotel_w, hotel_y + hotel_h - 120, Color{ .r = 180, .g = 120, .b = 50 });

            // Calculate door positions aligned with world coordinates (Room 25: x=0, Room 33: x=16)
            const pt_r25 = world_to_screen(0, 0, self.width, self.height);
            const pt_r33 = world_to_screen(16, 0, self.width, self.height);

            // Door 25 (Gabriel's room)
            const d25_x = pt_r25.x - 35;
            self.fill_rect(d25_x, hotel_y + hotel_h - 260, 70, 140, Color.hotel_door);
            self.draw_rect_outline(d25_x, hotel_y + hotel_h - 260, 70, 140, Color{ .r = 180, .g = 120, .b = 50 });
            self.draw_text("25", d25_x + 24, hotel_y + hotel_h - 250, 2, Color.wp_hover);

            // Door 33 (Mosely's room)
            const d33_x = pt_r33.x - 35;
            self.fill_rect(d33_x, hotel_y + hotel_h - 260, 70, 140, Color.hotel_door);
            self.draw_rect_outline(d33_x, hotel_y + hotel_h - 260, 70, 140, Color{ .r = 180, .g = 120, .b = 50 });
            self.draw_text("33", d33_x + 24, hotel_y + hotel_h - 250, 2, Color.wp_hover);

            // Corridor Exit / Garden Archway (aligned with CorridorExit mark world_x = 32)
            const pt_exit = world_to_screen(32, 0, self.width, self.height);
            const ex_x = pt_exit.x - 35;
            self.fill_rect(ex_x, hotel_y + hotel_h - 260, 70, 140, Color{ .r = 45, .g = 25, .b = 15 });
            self.draw_rect_outline(ex_x, hotel_y + hotel_h - 260, 70, 140, Color{ .r = 180, .g = 120, .b = 50 });
            self.fill_circle(ex_x + 35, hotel_y + hotel_h - 260, 35, Color{ .r = 45, .g = 25, .b = 15 });
            self.draw_circle_outline(ex_x + 35, hotel_y + hotel_h - 260, 35, Color{ .r = 180, .g = 120, .b = 50 });
            // Sunlit daylight pouring in from courtyard garden
            self.fill_rect(ex_x + 8, hotel_y + hotel_h - 250, 54, 120, Color{ .r = 160, .g = 210, .b = 245, .a = 180 });
            self.draw_text("GARDEN", ex_x + 10, hotel_y + hotel_h - 280, 1, Color{ .r = 254, .g = 240, .b = 138 });
            self.draw_text("EXIT", ex_x + 18, hotel_y + hotel_h - 268, 1, Color{ .r = 254, .g = 240, .b = 138 });

            // Brass sconces
            self.fill_circle(hotel_x + 40, hotel_y + 90, 6, Color.wp_hover);
            self.fill_circle(hotel_x + hotel_w - 40, hotel_y + 90, 6, Color.wp_hover);

            // Title
            self.draw_text("HOTEL DES COURONNES - CORRIDOR", hotel_x + 16, hotel_y + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
            self.draw_text("(FRENCH DAMASK WALLS * ROOM 25 & ROOM 33)", hotel_x + 16, hotel_y + 36, 1, Color.hud_subtext);
        } else if (is_garden_scene) {
            // Hotel Courtyard Garden (P14-02, D-016)
            // 1. Sky & Sun
            self.fill_rect(0, 0, self.width, self.height, Color.garden_sky);

            const garden_x: i32 = 40;
            const garden_y: i32 = 110;
            const garden_w: i32 = self.width - 80;
            const garden_h: i32 = self.height - 210;

            // Sky gradient bands & clouds
            self.fill_rect(garden_x, garden_y, garden_w, 40, Color{ .r = 110, .g = 175, .b = 230 });
            self.fill_rect(garden_x, garden_y + 40, garden_w, 40, Color{ .r = 135, .g = 195, .b = 240 });
            self.fill_rect(garden_x, garden_y + 80, garden_w, 40, Color{ .r = 165, .g = 210, .b = 245 });

            // Warm afternoon sun (top right)
            const sun_cx = garden_x + garden_w - 180;
            const sun_cy = garden_y + 45;
            self.fill_circle(sun_cx, sun_cy, 24, Color{ .r = 254, .g = 240, .b = 138 });
            self.draw_circle_outline(sun_cx, sun_cy, 28, Color{ .r = 253, .g = 224, .b = 71 });
            self.draw_circle_outline(sun_cx, sun_cy, 34, Color{ .r = 250, .g = 204, .b = 21, .a = 140 });

            // White fluffy clouds
            self.fill_circle(garden_x + 460, garden_y + 35, 18, Color{ .r = 255, .g = 255, .b = 255, .a = 210 });
            self.fill_circle(garden_x + 485, garden_y + 30, 24, Color{ .r = 255, .g = 255, .b = 255, .a = 230 });
            self.fill_circle(garden_x + 510, garden_y + 35, 18, Color{ .r = 255, .g = 255, .b = 255, .a = 210 });

            self.fill_circle(garden_x + 780, garden_y + 50, 14, Color{ .r = 255, .g = 255, .b = 255, .a = 180 });
            self.fill_circle(garden_x + 800, garden_y + 45, 20, Color{ .r = 255, .g = 255, .b = 255, .a = 200 });
            self.fill_circle(garden_x + 820, garden_y + 50, 14, Color{ .r = 255, .g = 255, .b = 255, .a = 180 });

            // Distant Pyrenean / Languedoc rolling foothills
            self.fill_circle(garden_x + 600, garden_y + 140, 180, Color{ .r = 115, .g = 150, .b = 130 });
            self.fill_circle(garden_x + 850, garden_y + 150, 200, Color{ .r = 100, .g = 140, .b = 120 });
            self.fill_circle(garden_x + 1100, garden_y + 160, 220, Color{ .r = 90, .g = 130, .b = 110 });

            // Courtyard grass lawn (Right of terrace, from x=320 to garden_w)
            self.fill_rect(garden_x + 320, garden_y + 130, garden_w - 320, garden_h - 130, Color.garden_grass);
            self.draw_rect_outline(garden_x, garden_y, garden_w, garden_h, Color{ .r = 40, .g = 90, .b = 40 });

            // Trimmed boxwood hedge along rear fence
            self.fill_rect(garden_x + 320, garden_y + 118, garden_w - 320, 26, Color{ .r = 30, .g = 85, .b = 35 });
            var hi: i32 = garden_x + 320;
            while (hi < garden_x + garden_w - 20) : (hi += 32) {
                self.fill_circle(hi + 16, garden_y + 122, 14, Color{ .r = 38, .g = 100, .b = 42 });
            }

            // 2. Hotel des Couronnes Exterior Wing (Left side: garden_x to garden_x + 320)
            const wing_w: i32 = 320;
            self.fill_rect(garden_x, garden_y, wing_w, garden_h, Color{ .r = 215, .g = 195, .b = 160 }); // French limestone
            self.draw_rect_outline(garden_x, garden_y, wing_w, garden_h, Color{ .r = 150, .g = 130, .b = 100 });

            // Limestone masonry block seams
            var my: i32 = garden_y + 30;
            var row_even = true;
            while (my < garden_y + garden_h) : (my += 28) {
                self.draw_line(garden_x, my, garden_x + wing_w, my, Color{ .r = 185, .g = 165, .b = 130 });
                const offset: i32 = if (row_even) 0 else 30;
                var mx: i32 = garden_x + offset;
                while (mx < garden_x + wing_w) : (mx += 60) {
                    self.draw_line(mx, my, mx, my + 28, Color{ .r = 185, .g = 165, .b = 130 });
                }
                row_even = !row_even;
            }

            // Ivy vines creeping up hotel wall
            self.fill_circle(garden_x + 30, garden_y + 90, 20, Color{ .r = 35, .g = 100, .b = 40 });
            self.fill_circle(garden_x + 45, garden_y + 130, 24, Color{ .r = 45, .g = 120, .b = 50 });
            self.fill_circle(garden_x + 25, garden_y + 180, 22, Color{ .r = 35, .g = 95, .b = 38 });
            self.fill_circle(garden_x + 40, garden_y + 230, 26, Color{ .r = 50, .g = 130, .b = 55 });
            self.fill_circle(garden_x + 300, garden_y + 110, 18, Color{ .r = 35, .g = 100, .b = 40 });
            self.fill_circle(garden_x + 310, garden_y + 160, 22, Color{ .r = 45, .g = 120, .b = 50 });

            // Upper-floor French window with dark green shutters
            const win_x = garden_x + 110;
            const win_y = garden_y + 40;
            self.fill_rect(win_x, win_y, 80, 100, Color{ .r = 25, .g = 35, .b = 50 }); // Window glass
            self.draw_rect_outline(win_x, win_y, 80, 100, Color{ .r = 140, .g = 120, .b = 90 });
            // Window panes
            self.draw_line(win_x + 40, win_y, win_x + 40, win_y + 100, Color.white);
            self.draw_line(win_x, win_y + 50, win_x + 80, win_y + 50, Color.white);
            // Left & right wooden shutters (olive green)
            self.fill_rect(win_x - 30, win_y, 28, 100, Color{ .r = 45, .g = 80, .b = 55 });
            self.draw_rect_outline(win_x - 30, win_y, 28, 100, Color{ .r = 30, .g = 55, .b = 38 });
            self.fill_rect(win_x + 82, win_y, 28, 100, Color{ .r = 45, .g = 80, .b = 55 });
            self.draw_rect_outline(win_x + 82, win_y, 28, 100, Color{ .r = 30, .g = 55, .b = 38 });
            // Window sill with red geranium flower box
            self.fill_rect(win_x - 10, win_y + 98, 100, 14, Color{ .r = 160, .g = 75, .b = 45 });
            self.fill_circle(win_x + 10, win_y + 94, 6, Color{ .r = 239, .g = 68, .b = 68 });
            self.fill_circle(win_x + 35, win_y + 94, 6, Color{ .r = 244, .g = 63, .b = 94 });
            self.fill_circle(win_x + 60, win_y + 94, 6, Color{ .r = 239, .g = 68, .b = 68 });

            // Ground floor arched entrance door (aligned with GardenPath world_x = 0)
            const pt_path = world_to_screen(0, 0, self.width, self.height);
            const door_x = pt_path.x - 45;
            const door_y = garden_y + garden_h - 220;
            self.fill_rect(door_x, door_y, 90, 140, Color{ .r = 45, .g = 25, .b = 15 }); // Dark carved oak
            self.draw_rect_outline(door_x, door_y, 90, 140, Color{ .r = 180, .g = 130, .b = 70 });
            // Arch top
            self.fill_circle(door_x + 45, door_y, 45, Color{ .r = 45, .g = 25, .b = 15 });
            self.draw_circle_outline(door_x + 45, door_y, 45, Color{ .r = 180, .g = 130, .b = 70 });
            // Glass window panels with warm hallway interior light
            self.fill_rect(door_x + 10, door_y + 10, 30, 50, Color{ .r = 254, .g = 240, .b = 138, .a = 200 });
            self.fill_rect(door_x + 50, door_y + 10, 30, 50, Color{ .r = 254, .g = 240, .b = 138, .a = 200 });
            self.draw_rect_outline(door_x + 10, door_y + 10, 30, 50, Color{ .r = 180, .g = 130, .b = 70 });
            self.draw_rect_outline(door_x + 50, door_y + 10, 30, 50, Color{ .r = 180, .g = 130, .b = 70 });
            // Brass handle
            self.fill_circle(door_x + 78, door_y + 75, 4, Color{ .r = 250, .g = 204, .b = 21 });
            // Hotel Doorway Header
            self.fill_rect(door_x - 10, door_y - 24, 110, 18, Color{ .r = 30, .g = 20, .b = 15 });
            self.draw_rect_outline(door_x - 10, door_y - 24, 110, 18, Color{ .r = 250, .g = 204, .b = 21 });
            self.draw_text("HOTEL EXIT", door_x - 2, door_y - 20, 1, Color{ .r = 254, .g = 240, .b = 138 });

            // 3. Terracotta Patio Terrace (near hotel, left foreground)
            const terrace_w: i32 = 320;
            self.fill_rect(garden_x, garden_y + garden_h - 100, terrace_w, 100, Color{ .r = 185, .g = 95, .b = 65 }); // Terracotta
            // Grout tiles
            var ty: i32 = garden_y + garden_h - 100;
            while (ty < garden_y + garden_h) : (ty += 25) {
                self.draw_line(garden_x, ty, garden_x + terrace_w, ty, Color{ .r = 145, .g = 70, .b = 45 });
            }
            var tx: i32 = garden_x;
            while (tx < garden_x + terrace_w) : (tx += 30) {
                self.draw_line(tx, garden_y + garden_h - 100, tx, garden_y + garden_h, Color{ .r = 145, .g = 70, .b = 45 });
            }

            // 4. Centerpiece: Stone Tiered Birdbath / Fountain (between terrace and fence)
            const fountain_x = garden_x + 400;
            const fountain_y = garden_y + garden_h - 80;
            // Stone base & pillar
            self.fill_rect(fountain_x - 14, fountain_y + 10, 28, 36, Color{ .r = 160, .g = 150, .b = 140 });
            self.draw_rect_outline(fountain_x - 14, fountain_y + 10, 28, 36, Color{ .r = 110, .g = 100, .b = 95 });
            // Lower bowl
            self.fill_circle(fountain_x, fountain_y + 10, 32, Color{ .r = 175, .g = 165, .b = 155 });
            self.draw_circle_outline(fountain_x, fountain_y + 10, 32, Color{ .r = 120, .g = 110, .b = 105 });
            self.fill_circle(fountain_x, fountain_y + 10, 26, Color{ .r = 56, .g = 189, .b = 248, .a = 210 }); // Water
            // Upper pillar & small bowl
            self.fill_rect(fountain_x - 7, fountain_y - 18, 14, 26, Color{ .r = 160, .g = 150, .b = 140 });
            self.fill_circle(fountain_x, fountain_y - 18, 16, Color{ .r = 175, .g = 165, .b = 155 });
            self.fill_circle(fountain_x, fountain_y - 18, 12, Color{ .r = 56, .g = 189, .b = 248, .a = 210 });

            // 5. Wooden Picket Fence (x = 360 to garden_w)
            const fence_start_x = garden_x + 340;
            const fence_w = garden_w - 340;
            const fence_y = garden_y + garden_h - 180;
            // Fence horizontal support rails
            self.fill_rect(fence_start_x, fence_y - 8, fence_w, 10, Color{ .r = 135, .g = 85, .b = 40 });
            self.fill_rect(fence_start_x, fence_y + 34, fence_w, 10, Color{ .r = 135, .g = 85, .b = 40 });

            // Vertical pickets
            var p_i: i32 = fence_start_x;
            while (p_i < garden_x + garden_w - 60) : (p_i += 22) {
                // Skip pickets where the hole is located (around pt_fence.x = 604)
                if (p_i >= 580 and p_i <= 630) {
                    p_i += 22;
                    continue;
                }

                // Pointed tip
                self.draw_line(p_i + 5, fence_y - 32, p_i, fence_y - 22, Color{ .r = 100, .g = 60, .b = 28 });
                self.draw_line(p_i + 5, fence_y - 32, p_i + 10, fence_y - 22, Color{ .r = 100, .g = 60, .b = 28 });
                self.fill_rect(p_i, fence_y - 22, 11, 74, Color.garden_fence);
                self.draw_rect_outline(p_i, fence_y - 22, 11, 74, Color{ .r = 100, .g = 60, .b = 28 });
            }

            // 6. Fence Hole (Hotspot at world_x = 18, screen x ≈ 604)
            const pt_fence = world_to_screen(18, 0, self.width, self.height);
            const hole_x = pt_fence.x - 30;
            const hole_y = fence_y + 8;
            const hole_w: i32 = 60;
            const hole_h: i32 = 46;

            // Broken jagged pickets above hole
            self.fill_rect(hole_x + 4, fence_y - 22, 11, 28, Color.garden_fence);
            self.fill_rect(hole_x + 24, fence_y - 22, 11, 22, Color.garden_fence);
            self.fill_rect(hole_x + 44, fence_y - 22, 11, 26, Color.garden_fence);

            // The escape opening through to priest's property
            self.fill_rect(hole_x, hole_y, hole_w, hole_h, Color{ .r = 20, .g = 30, .b = 18 });
            self.draw_rect_outline(hole_x, hole_y, hole_w, hole_h, Color{ .r = 120, .g = 70, .b = 30 });
            self.draw_text("FENCE GAP", hole_x + 4, hole_y - 12, 1, Color{ .r = 250, .g = 204, .b = 21 });

            // Masking tape indicator if taped
            if (frame.fence_taped) {
                // Wide tape band stretched taut across hole
                self.fill_rect(hole_x - 8, hole_y + 16, hole_w + 16, 12, Color{ .r = 254, .g = 243, .b = 199 });
                self.draw_rect_outline(hole_x - 8, hole_y + 16, hole_w + 16, 12, Color{ .r = 217, .g = 119, .b = 6 });

                if (frame.fence_has_hair) {
                    // Thick tuft of black cat hair stuck to the tape!
                    self.fill_rect(hole_x + 14, hole_y + 13, 32, 18, Color.black);
                    self.draw_rect_outline(hole_x + 14, hole_y + 13, 32, 18, Color{ .r = 250, .g = 204, .b = 21 });
                    self.draw_text("★ BLACK CAT FUR STUCK TO TAPE ★", hole_x - 45, hole_y - 28, 1, Color{ .r = 250, .g = 204, .b = 21 });
                } else {
                    self.draw_text("[STICKY MASKING TAPE READY]", hole_x - 30, hole_y - 28, 1, Color.wp_hover);
                }
            }

            // 7. Lavender Shrub & Stray Cat Lounge (world_x = 34, screen x ≈ 892)
            const pt_cat = world_to_screen(34, 0, self.width, self.height);
            const shrub_x = pt_cat.x;
            const shrub_y = pt_cat.y - 48;

            // Wooden Potting Bench with garden supplies
            self.fill_rect(shrub_x - 70, shrub_y + 20, 60, 24, Color{ .r = 115, .g = 75, .b = 40 });
            self.draw_rect_outline(shrub_x - 70, shrub_y + 20, 60, 24, Color{ .r = 75, .g = 45, .b = 22 });
            self.fill_rect(shrub_x - 68, shrub_y + 44, 8, 30, Color{ .r = 85, .g = 50, .b = 25 });
            self.fill_rect(shrub_x - 22, shrub_y + 44, 8, 30, Color{ .r = 85, .g = 50, .b = 25 });
            // Terracotta pot on bench
            self.fill_rect(shrub_x - 62, shrub_y + 8, 16, 12, Color{ .r = 190, .g = 90, .b = 55 });
            // Garden spray bottle sitting on bench
            self.fill_rect(shrub_x - 40, shrub_y + 4, 12, 16, Color{ .r = 56, .g = 189, .b = 248 });
            self.fill_rect(shrub_x - 38, shrub_y - 2, 8, 6, Color.white);

            // Fragrant blooming lavender bush clusters
            self.fill_circle(shrub_x + 10, shrub_y - 5, 26, Color{ .r = 40, .g = 135, .b = 60 });
            self.fill_circle(shrub_x + 35, shrub_y + 5, 24, Color{ .r = 30, .g = 115, .b = 48 });
            self.fill_circle(shrub_x - 5, shrub_y + 10, 22, Color{ .r = 50, .g = 150, .b = 70 });
            // Purple lavender flower specks
            self.fill_circle(shrub_x + 10, shrub_y - 18, 10, Color{ .r = 168, .g = 85, .b = 247 });
            self.fill_circle(shrub_x + 28, shrub_y - 8, 12, Color{ .r = 192, .g = 132, .b = 252 });
            self.fill_circle(shrub_x - 2, shrub_y - 4, 11, Color{ .r = 168, .g = 85, .b = 247 });
            self.fill_circle(shrub_x + 20, shrub_y + 12, 10, Color{ .r = 147, .g = 51, .b = 234 });

            // 8. Far Right: Stone Arch / Village Gate (leading toward Bike Shop)
            const gate_x = garden_x + garden_w - 75;
            const gate_y = garden_y + garden_h - 220;
            self.fill_rect(gate_x, gate_y, 65, 140, Color{ .r = 140, .g = 130, .b = 115 });
            self.draw_rect_outline(gate_x, gate_y, 65, 140, Color{ .r = 95, .g = 85, .b = 75 });
            self.fill_circle(gate_x + 32, gate_y, 32, Color{ .r = 140, .g = 130, .b = 115 });
            // Iron gate bars
            self.fill_rect(gate_x + 10, gate_y, 45, 130, Color{ .r = 18, .g = 22, .b = 30 });
            self.draw_line(gate_x + 20, gate_y, gate_x + 20, gate_y + 130, Color{ .r = 80, .g = 90, .b = 100 });
            self.draw_line(gate_x + 32, gate_y, gate_x + 32, gate_y + 130, Color{ .r = 80, .g = 90, .b = 100 });
            self.draw_line(gate_x + 44, gate_y, gate_x + 44, gate_y + 130, Color{ .r = 80, .g = 90, .b = 100 });
            self.draw_text("VILLAGE", gate_x + 6, gate_y - 18, 1, Color{ .r = 250, .g = 204, .b = 21 });
            self.draw_text("-> SHOP", gate_x + 6, gate_y - 6, 1, Color{ .r = 250, .g = 204, .b = 21 });

            // 9. Scene Title & Header
            self.draw_text("HOTEL COURTYARD - GARDEN FENCE", garden_x + 16, garden_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
            self.draw_text("(SUNNY PROVENCAL COURTYARD * WOODEN PICKET FENCE * ESCAPE GAP)", garden_x + 16, garden_y + 36, 1, Color.hud_subtext);
        } else if (is_bike_rental_scene) {
            // Madame Buthane's Bike Rental Shop (P14-02, D-016)
            self.fill_rect(0, 0, self.width, self.height, Color{ .r = 25, .g = 20, .b = 20 });

            const shop_x: i32 = 40;
            const shop_y: i32 = 110;
            const shop_w: i32 = self.width - 80;
            const shop_h: i32 = self.height - 210;

            self.fill_rect(shop_x, shop_y, shop_w, shop_h, Color.rental_wall);
            self.draw_rect_outline(shop_x, shop_y, shop_w, shop_h, Color{ .r = 110, .g = 95, .b = 85 });

            // Stone floor
            self.fill_rect(shop_x, shop_y + shop_h - 100, shop_w, 100, Color{ .r = 45, .g = 40, .b = 38 });

            // Road touring map of Languedoc on the wall
            const map_x = shop_x + 60;
            self.fill_rect(map_x, shop_y + 55, 140, 90, Color{ .r = 254, .g = 243, .b = 199 });
            self.draw_rect_outline(map_x, shop_y + 55, 140, 90, Color{ .r = 180, .g = 83, .b = 9 });
            self.draw_text("MAP OF LANGUEDOC", map_x + 8, shop_y + 65, 1, Color{ .r = 120, .g = 53, .b = 15 });
            self.draw_text("RENNES-LE-CHATEAU", map_x + 8, shop_y + 80, 1, Color{ .r = 180, .g = 83, .b = 9 });

            // Pine rental counter (aligned with CounterMark world_x = 16)
            const pt_counter = world_to_screen(16, 0, self.width, self.height);
            const cnt_x = pt_counter.x - 110;
            self.fill_rect(cnt_x, shop_y + shop_h - 180, 220, 80, Color.rental_counter);
            self.draw_rect_outline(cnt_x, shop_y + shop_h - 180, 220, 80, Color{ .r = 217, .g = 119, .b = 6 });
            self.draw_text("RENTAL COUNTER", cnt_x + 20, shop_y + shop_h - 165, 2, Color{ .r = 60, .g = 35, .b = 15 });

            // Red Motorcycle display (aligned with BikeMark world_x = 32)
            const pt_bike = world_to_screen(32, 0, self.width, self.height);
            const mc_x = pt_bike.x - 65;
            self.fill_circle(mc_x + 25, shop_y + shop_h - 110, 20, Color.black);
            self.fill_circle(mc_x + 105, shop_y + shop_h - 110, 20, Color.black);
            self.draw_circle_outline(mc_x + 25, shop_y + shop_h - 110, 20, Color{ .r = 200, .g = 200, .b = 200 });
            self.draw_circle_outline(mc_x + 105, shop_y + shop_h - 110, 20, Color{ .r = 200, .g = 200, .b = 200 });
            self.fill_rect(mc_x + 25, shop_y + shop_h - 140, 80, 25, Color.motorcycle_red);
            self.draw_line(mc_x + 35, shop_y + shop_h - 155, mc_x + 60, shop_y + shop_h - 140, Color.white);

            if (frame.bike_rented) {
                self.draw_text("[RENTED TO MOSELY!]", mc_x + 10, shop_y + shop_h - 170, 2, Color.status_running);
            } else {
                self.draw_text("[RESERVED: MOSELY]", mc_x + 10, shop_y + shop_h - 170, 2, Color.cue_alert);
            }

            // Title
            self.draw_text("RENNES-LE-CHATEAU - BIKE RENTAL SHOP", shop_x + 16, shop_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
            self.draw_text("(VINTAGE MOTORCYCLE * MADAME BUTHANE AT THE DESK)", shop_x + 16, shop_y + 36, 1, Color.hud_subtext);
        } else if (is_high_road_scene) {
            // Melee Island High Road (P15-02)
            self.fill_rect(0, 0, self.width, self.height, Color{ .r = 10, .g = 15, .b = 30 }); // Deep night sky

            const road_x: i32 = 40;
            const road_y: i32 = 110;
            const road_w: i32 = self.width - 80;
            const road_h: i32 = self.height - 210;

            // Pine tree silhouettes and mountain ridges
            self.fill_rect(road_x, road_y + 40, road_w, road_h - 40, Color{ .r = 15, .g = 22, .b = 38 });
            // Yellow crescent moon
            self.fill_circle(road_x + road_w - 120, road_y + 60, 24, Color{ .r = 254, .g = 240, .b = 138 });
            self.fill_circle(road_x + road_w - 112, road_y + 54, 20, Color{ .r = 10, .g = 15, .b = 30 });

            // Dark cobblestone pirate road
            self.fill_rect(road_x, road_y + road_h - 130, road_w, 130, Color{ .r = 30, .g = 35, .b = 45 });
            self.draw_rect_outline(road_x, road_y + road_h - 130, road_w, 130, Color{ .r = 60, .g = 70, .b = 85 });

            // Roadside iron lantern
            self.fill_rect(road_x + 80, road_y + road_h - 190, 6, 60, Color.black);
            self.fill_circle(road_x + 83, road_y + road_h - 195, 10, Color{ .r = 245, .g = 158, .b = 11, .a = 220 });

            // Header
            self.draw_text("MELEE ISLAND - THE HIGH ROAD", road_x + 16, road_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
            self.draw_text("(ROAMING PIRATES * INSULT DUELS * COMBINATORIAL MEMORY)", road_x + 16, road_y + 36, 1, Color.hud_subtext);
        } else if (is_sanctuary_scene) {
            // Carla's Sword Master Sanctuary
            self.fill_rect(0, 0, self.width, self.height, Color{ .r = 12, .g = 25, .b = 18 });

            const s_x: i32 = 40;
            const s_y: i32 = 110;
            const s_w: i32 = self.width - 80;
            const s_h: i32 = self.height - 210;

            self.fill_rect(s_x, s_y, s_w, s_h, Color{ .r = 20, .g = 45, .b = 30 });
            self.draw_rect_outline(s_x, s_y, s_w, s_h, Color{ .r = 34, .g = 80, .b = 50 });

            // Training circle
            const center_x = s_x + @divTrunc(s_w, 2);
            self.draw_circle_outline(center_x, s_y + s_h - 80, 70, Color{ .r = 250, .g = 204, .b = 21 });

            // Bamboo fence & gate
            self.fill_rect(s_x + 60, s_y + s_h - 160, 140, 15, Color{ .r = 160, .g = 120, .b = 60 });

            // Target dummy
            self.fill_circle(s_x + s_w - 140, s_y + s_h - 120, 16, Color{ .r = 217, .g = 119, .b = 6 });
            self.fill_rect(s_x + s_w - 144, s_y + s_h - 104, 8, 30, Color{ .r = 120, .g = 70, .b = 30 });

            // Header
            self.draw_text("CARLA'S SWORD MASTER SANCTUARY", s_x + 16, s_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
            self.draw_text("(MASTER VARIANTS * ELEVATED RETORTS * TARGET VALIDATION)", s_x + 16, s_y + 36, 1, Color.hud_subtext);
        } else if (is_scumm_bar_scene) {
            // The Scumm Bar
            self.fill_rect(0, 0, self.width, self.height, Color{ .r = 30, .g = 18, .b = 12 });

            const b_x: i32 = 40;
            const b_y: i32 = 110;
            const b_w: i32 = self.width - 80;
            const b_h: i32 = self.height - 210;

            self.fill_rect(b_x, b_y, b_w, b_h, Color{ .r = 55, .g = 32, .b = 20 });
            self.draw_rect_outline(b_x, b_y, b_w, b_h, Color{ .r = 120, .g = 75, .b = 40 });

            // Oak bar counter
            self.fill_rect(b_x + 80, b_y + b_h - 140, 260, 60, Color{ .r = 90, .g = 50, .b = 28 });
            self.draw_rect_outline(b_x + 80, b_y + b_h - 140, 260, 60, Color{ .r = 160, .g = 95, .b = 45 });
            self.draw_text("GROG BAR", b_x + 100, b_y + b_h - 125, 2, Color{ .r = 254, .g = 240, .b = 138 });

            // Grog Barrel with skull
            self.fill_circle(b_x + b_w - 160, b_y + b_h - 100, 30, Color{ .r = 40, .g = 25, .b = 18 });
            self.draw_circle_outline(b_x + b_w - 160, b_y + b_h - 100, 30, Color{ .r = 180, .g = 120, .b = 50 });
            self.draw_text("GROG", b_x + b_w - 180, b_y + b_h - 106, 2, Color{ .r = 239, .g = 68, .b = 68 });

            // Header
            self.draw_text("THE SCUMM BAR - MELEE ISLAND", b_x + 16, b_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
            self.draw_text("(BARKEEP AT THE TAPS * CONVERSATIONAL REPETITION FATIGUE)", b_x + 16, b_y + 36, 1, Color.hud_subtext);
        } else {
            // 1. Clear background
            self.fill_rect(0, 0, self.width, self.height, Color.tavern_bg);

            // 2. Render Rooms (Tavern Hall & Wine Cellar side-by-side)
            const tavern_rect_x = 100;
            const tavern_rect_y = 120;
            const tavern_rect_w = 480;
            const tavern_rect_h = 320;
            self.fill_rect(tavern_rect_x, tavern_rect_y, tavern_rect_w, tavern_rect_h, Color.tavern_room);
            self.draw_rect_outline(tavern_rect_x, tavern_rect_y, tavern_rect_w, tavern_rect_h, Color.tavern_border);
            self.draw_text("TAVERN - COMMON ROOM", tavern_rect_x + 16, tavern_rect_y + 16, 2, Color.hud_subtext);

            const cellar_rect_x = 600;
            const cellar_rect_y = 120;
            const cellar_rect_w = 260;
            const cellar_rect_h = 320;
            self.fill_rect(cellar_rect_x, cellar_rect_y, cellar_rect_w, cellar_rect_h, Color.cellar_room);
            self.draw_rect_outline(cellar_rect_x, cellar_rect_y, cellar_rect_w, cellar_rect_h, Color.cellar_border);
            self.draw_text("WINE CELLAR", cellar_rect_x + 16, cellar_rect_y + 16, 2, Color.hud_subtext);
        }

        // 3. Render Scene Hotspots / Props (P7-01, D-009)
        for (frame.hotspots[0..frame.hotspot_count], 0..) |hs, idx| {
            const pt = world_to_screen(hs.x, hs.y, self.width, self.height);
            const is_hovered = (self.hovered_hotspot != null and self.hovered_hotspot.? == idx);
            const name = hs.get_name();

            if (std.mem.indexOf(u8, name, "Fire") != null or std.mem.indexOf(u8, name, "Hearth") != null) {
                // Stone fireplace & fire glow
                self.fill_rect(pt.x - 22, pt.y - 24, 44, 48, Color{ .r = 55, .g = 45, .b = 40 });
                self.draw_rect_outline(pt.x - 22, pt.y - 24, 44, 48, Color{ .r = 85, .g = 70, .b = 60 });
                self.fill_rect(pt.x - 14, pt.y - 10, 28, 30, Color{ .r = 25, .g = 18, .b = 16 });
                self.fill_circle(pt.x, pt.y + 4, 10, Color{ .r = 239, .g = 68, .b = 68 });
                self.fill_circle(pt.x, pt.y + 2, 6, Color{ .r = 245, .g = 158, .b = 11 });
            } else if (std.mem.indexOf(u8, name, "Bar") != null or std.mem.indexOf(u8, name, "Counter") != null) {
                // Polished tavern counter
                self.fill_rect(pt.x - 28, pt.y - 14, 56, 28, Color{ .r = 110, .g = 50, .b = 18 });
                self.draw_rect_outline(pt.x - 28, pt.y - 14, 56, 28, Color{ .r = 145, .g = 75, .b = 30 });
                self.fill_rect(pt.x - 26, pt.y - 12, 52, 4, Color{ .r = 180, .g = 83, .b = 9 });
            } else if (std.mem.indexOf(u8, name, "Cask") != null or std.mem.indexOf(u8, name, "Barrel") != null) {
                // Vintage wine cask
                self.fill_rect(pt.x - 18, pt.y - 22, 36, 44, Color{ .r = 69, .g = 26, .b = 3 });
                self.draw_rect_outline(pt.x - 18, pt.y - 22, 36, 44, Color{ .r = 120, .g = 53, .b = 15 });
                self.draw_line(pt.x - 18, pt.y - 10, pt.x + 18, pt.y - 10, Color{ .r = 140, .g = 140, .b = 150 });
                self.draw_line(pt.x - 18, pt.y + 10, pt.x + 18, pt.y + 10, Color{ .r = 140, .g = 140, .b = 150 });
            } else if (std.mem.indexOf(u8, name, "Flag") != null) {
                // Spitting Competition Distance Flags (P10-03, D-012)
                const flag_x = if (frame.flags_tampered) pt.x - 70 else pt.x;
                self.fill_rect(flag_x - 2, pt.y - 32, 4, 40, Color{ .r = 217, .g = 119, .b = 6 });
                const fcol = if (frame.flags_tampered) Color.flag_tampered else Color.flag_color;
                self.fill_rect(flag_x + 2, pt.y - 32, 28, 18, fcol);
                self.draw_line(flag_x + 2, pt.y - 14, flag_x + 30, pt.y - 32, Color.white);

                if (frame.flags_tampered) {
                    self.draw_rect_outline(pt.x - 1, pt.y - 30, 2, 38, Color.hud_subtext);
                    self.draw_text("[MOVED!]", flag_x - 20, pt.y + 14, 2, Color.flag_tampered);
                } else {
                    self.draw_text("Flags", flag_x - 14, pt.y + 14, 2, Color.hud_text);
                }
            } else if (std.mem.indexOf(u8, name, "Fence") != null or std.mem.indexOf(u8, name, "Hole") != null) {
                // Garden Fence Hole (P14-02, D-016)
                self.fill_rect(pt.x - 20, pt.y - 16, 40, 32, Color.garden_fence);
                self.fill_rect(pt.x - 12, pt.y - 4, 24, 20, Color.black);
                if (frame.fence_taped) {
                    self.fill_rect(pt.x - 14, pt.y + 4, 28, 6, Color{ .r = 254, .g = 243, .b = 199 });
                }
            } else if (std.mem.indexOf(u8, name, "Door") != null) {
                // Mosely's Door (P14-02, D-016)
                self.fill_rect(pt.x - 16, pt.y - 24, 32, 48, Color.hotel_door);
                self.draw_rect_outline(pt.x - 16, pt.y - 24, 32, 48, Color{ .r = 180, .g = 120, .b = 50 });
            } else if (std.mem.indexOf(u8, name, "Desk") != null) {
                // Hotel Room Desk (P14-02, D-016)
                self.fill_rect(pt.x - 22, pt.y - 12, 44, 24, Color.hotel_wainscot);
                self.draw_rect_outline(pt.x - 22, pt.y - 12, 44, 24, Color{ .r = 140, .g = 80, .b = 40 });
            } else if (std.mem.indexOf(u8, name, "Shrub") != null or std.mem.indexOf(u8, name, "Bench") != null) {
                // Garden Lavender Shrub & Potting Bench (P14-02, D-016)
                self.fill_circle(pt.x - 8, pt.y - 4, 14, Color{ .r = 34, .g = 197, .b = 94 });
                self.fill_circle(pt.x + 8, pt.y - 6, 12, Color{ .r = 74, .g = 222, .b = 128 });
                self.fill_circle(pt.x, pt.y - 12, 10, Color{ .r = 168, .g = 85, .b = 247 }); // Lavender blossom
                self.fill_rect(pt.x - 18, pt.y + 6, 36, 10, Color{ .r = 120, .g = 80, .b = 50 }); // Potting bench
            } else if (std.mem.indexOf(u8, name, "Motorcycle") != null) {
                // Motorcycle prop (P14-02, D-016)
                self.fill_rect(pt.x - 20, pt.y - 12, 40, 24, Color.motorcycle_red);
                self.fill_circle(pt.x - 14, pt.y + 12, 8, Color.black);
                self.fill_circle(pt.x + 14, pt.y + 12, 8, Color.black);
            } else {
                // Default prop
                self.fill_rect(pt.x - 16, pt.y - 16, 32, 32, Color{ .r = 75, .g = 65, .b = 60 });
                self.draw_rect_outline(pt.x - 16, pt.y - 16, 32, 32, Color.tavern_border);
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
                const tw = font.text_width(prompt, 2);
                self.draw_text(prompt, pt.x - @divTrunc(tw, 2), pt.y - HOTSPOT_SCREEN_RADIUS - 18, 2, Color.wp_hover);
            }
        }

        // 4. Render Corridors / Edges between Waypoints
        if (!is_spitting_scene) {
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

                    if (is_garden_scene) {
                        // In Garden: Stone flagstone garden path
                        self.draw_line(p1.x, p1.y - 2, p2.x, p2.y - 2, Color{ .r = 135, .g = 120, .b = 100 });
                        self.draw_line(p1.x, p1.y - 1, p2.x, p2.y - 1, Color{ .r = 195, .g = 180, .b = 155 });
                        self.draw_line(p1.x, p1.y, p2.x, p2.y, Color{ .r = 195, .g = 180, .b = 155 });
                        self.draw_line(p1.x, p1.y + 1, p2.x, p2.y + 1, Color{ .r = 195, .g = 180, .b = 155 });
                        self.draw_line(p1.x, p1.y + 2, p2.x, p2.y + 2, Color{ .r = 135, .g = 120, .b = 100 });
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

            // Halo glow for hovered/target node
            if (is_hovered) {
                self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS + 4, Color.wp_hover);
            }
            if (is_targeted) {
                self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS + 6, Color.wp_target);
            }

            if (!is_spitting_scene) {
                // Waypoint anchor body
                const body_color = if (is_hovered) Color.wp_hover else Color.wp_normal;
                self.fill_circle(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, body_color);
                self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.white);
                self.fill_circle(pt.x, pt.y, 4, Color.white);

                // Check if actors are stationed at this waypoint coordinate
                var has_actors = false;
                for (frame.entities[0..frame.entity_count]) |ent| {
                    if (ent.x == wp.x and ent.y == wp.y) {
                        has_actors = true;
                        break;
                    }
                }

                // Waypoint text label: only draw if NO actor is stationed here, or when hovered
                const name = wp.get_name();
                if (is_hovered or is_targeted) {
                    var buf: [64]u8 = undefined;
                    const prompt = std.fmt.bufPrint(&buf, "[Walk to {s}]", .{name}) catch name;
                    const text_w = font.text_width(prompt, 2);
                    const prompt_y = if (has_actors)
                        pt.y + WAYPOINT_SCREEN_RADIUS + 34
                    else
                        pt.y + WAYPOINT_SCREEN_RADIUS + 8;
                    self.draw_text(prompt, pt.x - @divTrunc(text_w, 2), prompt_y, 2, Color.wp_hover);
                } else if (!has_actors) {
                    const text_w = font.text_width(name, 2);
                    self.draw_text(name, pt.x - @divTrunc(text_w, 2), pt.y + WAYPOINT_SCREEN_RADIUS + 8, 2, Color.hud_text);
                }
            } else {
                // In Spitting Contest: Stage marks
                if (is_hovered or is_targeted) {
                    self.fill_circle(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.wp_hover);
                    self.draw_circle_outline(pt.x, pt.y, WAYPOINT_SCREEN_RADIUS, Color.white);
                    const name = wp.get_name();
                    var buf: [64]u8 = undefined;
                    const prompt = std.fmt.bufPrint(&buf, "[Walk to {s}]", .{name}) catch name;
                    const text_w = font.text_width(prompt, 2);

                    // Check if actors are stationed at this waypoint coordinate
                    var has_actors = false;
                    for (frame.entities[0..frame.entity_count]) |ent| {
                        if (ent.x == wp.x and ent.y == wp.y) {
                            has_actors = true;
                            break;
                        }
                    }
                    const prompt_y = if (has_actors)
                        pt.y + WAYPOINT_SCREEN_RADIUS + 34
                    else
                        pt.y + WAYPOINT_SCREEN_RADIUS + 8;
                    self.draw_text(prompt, pt.x - @divTrunc(text_w, 2), prompt_y, 2, Color.wp_hover);
                } else {
                    // Subtle ground mark anchor
                    self.draw_circle_outline(pt.x, pt.y, 5, Color{ .r = 255, .g = 255, .b = 255, .a = 100 });
                    self.fill_circle(pt.x, pt.y, 2, Color.white);
                }
            }
        }

        // 5. Render Actors
        for (frame.entities[0..frame.entity_count], 0..) |e, idx| {
            const name = e.get_name();
            const layout = get_entity_screen_layout(idx, frame.entities[0..frame.entity_count], self.width, self.height);
            const pt = layout.pos;

            if (std.mem.eql(u8, name, "Cat")) {
                // Cat (Player): Orange token with cat ears
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.cat_color);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Ears
                self.fill_rect(pt.x - 12, pt.y - ACTOR_SCREEN_RADIUS - 4, 6, 6, Color.cat_color);
                self.fill_rect(pt.x + 6, pt.y - ACTOR_SCREEN_RADIUS - 4, 6, 6, Color.cat_color);

                // Label
                self.draw_text("Cat (Player)", pt.x - 36, layout.label_y, 2, Color.cat_color);

                // Carried Cheese
                if (frame.cheese_holder == e.entity) {
                    self.fill_circle(pt.x + 14, pt.y - 10, 8, Color.cheese_color);
                    self.draw_circle_outline(pt.x + 14, pt.y - 10, 8, Color.white);
                    self.draw_text("Cheese", pt.x + 24, pt.y - 14, 2, Color.cheese_color);
                }
            } else if (std.mem.eql(u8, name, "Guard")) {
                // Guard: Steel Blue token
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.guard_color);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Shield visor
                self.fill_rect(pt.x - 8, pt.y - 4, 16, 6, Color.white);

                // Label
                self.draw_text("Guard", pt.x - 16, layout.label_y, 2, Color.guard_color);

                // Carried Cheese
                if (frame.cheese_holder == e.entity) {
                    self.fill_circle(pt.x + 14, pt.y - 10, 8, Color.cheese_color);
                    self.draw_circle_outline(pt.x + 14, pt.y - 10, 8, Color.white);
                    self.draw_text("Cheese", pt.x + 24, pt.y - 14, 2, Color.cheese_color);
                }

                // Charmed status
                if (frame.charmed_target == e.entity) {
                    self.draw_text("[Charmed!]", pt.x - 28, layout.status_y, 2, Color.cue_alert);
                }
            } else if (std.mem.eql(u8, name, "Bard")) {
                // Bard: Purple token
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.bard_color);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Feather cap / lute indicator
                self.fill_rect(pt.x - 2, pt.y - ACTOR_SCREEN_RADIUS - 6, 4, 8, Color.white);

                // Label
                self.draw_text("Bard", pt.x - 12, layout.label_y, 2, Color.bard_color);
            } else if (std.mem.eql(u8, name, "Guybrush")) {
                // Guybrush (Player): Blonde hair, pirate blue coat
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.guybrush_coat);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Blonde hair
                self.fill_circle(pt.x, pt.y - 8, 8, Color.guybrush_hair);

                // Label
                const nw = font.text_width("Guybrush", 2);
                self.draw_text("Guybrush", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color.guybrush_hair);

                // Spit Status
                const spit_str = if (frame.spit_is_thick) "[Thick Spit Ready!]" else "[Spit: Thin]";
                const spit_col = if (frame.spit_is_thick) Color.spit_color else Color.hud_subtext;
                const sw = font.text_width(spit_str, 2);
                self.draw_text(spit_str, pt.x - @divTrunc(sw, 2), layout.status_y, 2, spit_col);
            } else if (std.mem.eql(u8, name, "Organiser")) {
                // Organiser: Velvet red coat, fancy hat
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.organiser_coat);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Cocked hat / feather
                self.fill_rect(pt.x - 8, pt.y - ACTOR_SCREEN_RADIUS - 4, 16, 5, Color.black);
                self.fill_rect(pt.x - 2, pt.y - ACTOR_SCREEN_RADIUS - 8, 4, 6, Color.guybrush_hair);

                // Label
                const nw = font.text_width("Organiser", 2);
                self.draw_text("Organiser", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color.organiser_coat);

                // Distracted / watching status
                const org_str = if (frame.organiser_distracted) "[DISTRACTED!]" else "[Watching]";
                const org_col = if (frame.organiser_distracted) Color.cue_alert else Color.status_running;
                const sw = font.text_width(org_str, 2);
                self.draw_text(org_str, pt.x - @divTrunc(sw, 2), layout.status_y, 2, org_col);
            } else if (std.mem.eql(u8, name, "Onlookers")) {
                // Onlookers: Crowd of spectator circles
                self.fill_circle(pt.x - 8, pt.y, ACTOR_SCREEN_RADIUS - 2, Color.onlookers_color);
                self.fill_circle(pt.x + 8, pt.y, ACTOR_SCREEN_RADIUS - 2, Color.onlookers_color);
                self.fill_circle(pt.x, pt.y - 6, ACTOR_SCREEN_RADIUS - 2, Color{ .r = 140, .g = 100, .b = 160 });
                self.draw_circle_outline(pt.x, pt.y - 6, ACTOR_SCREEN_RADIUS - 2, Color.white);

                // Label
                const nw = font.text_width("Onlookers", 2);
                self.draw_text("Onlookers", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color.onlookers_color);
                if (frame.organiser_distracted) {
                    const sw = font.text_width("[Looking Offstage]", 2);
                    self.draw_text("[Looking Offstage]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.cue_alert);
                }
            } else if (std.mem.eql(u8, name, "Gabriel")) {
                // Gabriel Knight: Leather trench coat, signature blonde hair, dark shades (P14-02, D-016)
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.gabriel_coat);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Blonde hair
                self.fill_circle(pt.x, pt.y - 8, 8, Color.gabriel_hair);

                // Dark sunglasses
                self.fill_rect(pt.x - 7, pt.y - 4, 14, 4, Color.black);

                // Cat-hair moustache if disguised
                if (frame.gabriel_disguised) {
                    self.fill_rect(pt.x - 6, pt.y + 2, 12, 4, Color.black);
                    self.draw_rect_outline(pt.x - 6, pt.y + 2, 12, 4, Color{ .r = 250, .g = 204, .b = 21 });
                }

                // Label
                const nw = font.text_width("Gabriel", 2);
                self.draw_text("Gabriel", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color.gabriel_hair);

                // Status
                if (frame.gabriel_disguised) {
                    const d_str = "[DISGUISED AS MOSELY!]";
                    const sw = font.text_width(d_str, 2);
                    self.draw_text(d_str, pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.status_running);
                } else {
                    const u_str = "[Undisguised]";
                    const sw = font.text_width(u_str, 2);
                    self.draw_text(u_str, pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.hud_subtext);
                }
            } else if (std.mem.eql(u8, name, "Mosely")) {
                // Detective Franklin Mosely: Navy suit, genuine moustache (P14-02, D-016)
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.mosely_suit);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Brown hair & real moustache
                self.fill_circle(pt.x, pt.y - 8, 8, Color{ .r = 90, .g = 55, .b = 30 });
                self.fill_rect(pt.x - 6, pt.y + 2, 12, 4, Color.black);

                // Label
                const nw = font.text_width("Mosely", 2);
                self.draw_text("Mosely", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color{ .r = 147, .g = 197, .b = 253 });
                const sw = font.text_width("[Detective]", 2);
                self.draw_text("[Detective]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.hud_subtext);
            } else if (std.mem.eql(u8, name, "Buthane")) {
                // Madame Buthane: Crimson vest, auburn hair (P14-02, D-016)
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.buthane_vest);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Auburn hair
                self.fill_circle(pt.x, pt.y - 8, 8, Color.buthane_hair);

                // Label
                const nw = font.text_width("Madame Buthane", 2);
                self.draw_text("Madame Buthane", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color{ .r = 252, .g = 165, .b = 165 });
                const sw = font.text_width("[Rental Desk]", 2);
                self.draw_text("[Rental Desk]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.hud_subtext);
            } else if (std.mem.eql(u8, name, "StrayCat")) {
                // Stray Cat: Black cat token with green eyes & ears (P14-02, D-016)
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS - 2, Color.stray_cat_color);
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS - 2, Color.white);

                // Ears
                self.fill_rect(pt.x - 8, pt.y - ACTOR_SCREEN_RADIUS - 4, 4, 6, Color.stray_cat_color);
                self.fill_rect(pt.x + 4, pt.y - ACTOR_SCREEN_RADIUS - 4, 4, 6, Color.stray_cat_color);

                // Green eyes
                self.fill_rect(pt.x - 5, pt.y - 3, 3, 3, Color.cat_eye_color);
                self.fill_rect(pt.x + 2, pt.y - 3, 3, 3, Color.cat_eye_color);

                // Label
                const nw = font.text_width("Stray Cat", 2);
                self.draw_text("Stray Cat", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color.hud_text);

                if (frame.cat_startled) {
                    const sw = font.text_width("[STARTLED!]", 2);
                    self.draw_text("[STARTLED!]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.cue_alert);
                } else {
                    const sw = font.text_width("[Napping]", 2);
                    self.draw_text("[Napping]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.hud_subtext);
                }
            } else if (std.mem.eql(u8, name, "PirateBob") or std.mem.eql(u8, name, "PiratePegleg")) {
                // Pirate Bob / Pegleg: Crimson vest, tricorn hat, eye patch
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 185, .g = 28, .b = 28 });
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Tricorn hat
                self.fill_rect(pt.x - 10, pt.y - ACTOR_SCREEN_RADIUS - 4, 20, 6, Color.black);
                // Eye patch
                self.fill_rect(pt.x + 1, pt.y - 4, 6, 6, Color.black);
                self.draw_line(pt.x - 6, pt.y - 7, pt.x + 8, pt.y - 1, Color.black);

                // Label
                const nw = font.text_width(name, 2);
                self.draw_text(name, pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color{ .r = 252, .g = 165, .b = 165 });
                const sw = font.text_width("[Swashbuckler]", 2);
                self.draw_text("[Swashbuckler]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.hud_subtext);
            } else if (std.mem.eql(u8, name, "Carla")) {
                // Carla: Sword Master of Melee Island. Crimson sash, fencing stance
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 225, .g = 29, .b = 72 });
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 250, .g = 204, .b = 21 });

                // Crimson headband
                self.fill_rect(pt.x - 8, pt.y - 10, 16, 5, Color{ .r = 244, .g = 63, .b = 94 });

                // Label
                const nw = font.text_width("Carla", 2);
                self.draw_text("Carla", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color{ .r = 254, .g = 205, .b = 211 });
                const sw = font.text_width("[Sword Master]", 2);
                self.draw_text("[Sword Master]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color{ .r = 250, .g = 204, .b = 21 });
            } else if (std.mem.eql(u8, name, "Barkeep")) {
                // Barkeep: Brown vest, white apron
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 120, .g = 70, .b = 40 });
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Apron
                self.fill_rect(pt.x - 6, pt.y - 2, 12, 10, Color.white);

                // Label
                const nw = font.text_width("Barkeep", 2);
                self.draw_text("Barkeep", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color{ .r = 253, .g = 230, .b = 138 });
                const sw = font.text_width("[Scumm Bar]", 2);
                self.draw_text("[Scumm Bar]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.hud_subtext);
            } else if (std.mem.eql(u8, name, "Citizen")) {
                // Citizen of Melee: Green coat
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 16, .g = 120, .b = 70 });
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

                // Label
                const nw = font.text_width("Citizen", 2);
                self.draw_text("Citizen", pt.x - @divTrunc(nw, 2), layout.label_y, 2, Color{ .r = 167, .g = 243, .b = 208 });
                const sw = font.text_width("[Melee Citizen]", 2);
                self.draw_text("[Melee Citizen]", pt.x - @divTrunc(sw, 2), layout.status_y, 2, Color.hud_subtext);
            } else {
                // Generic actor token
                self.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 70, .g = 80, .b = 95 });
                self.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
                const tw = font.text_width(name, 2);
                self.draw_text(name, pt.x - @divTrunc(tw, 2), layout.label_y, 2, Color.hud_text);
            }
        }

        // 6. Top Status HUD Bar
        self.fill_rect(0, 0, self.width, 48, Color.hud_bg);
        self.draw_line(0, 48, self.width, 48, Color.tavern_border);

        var top_buf: [128]u8 = undefined;
        const status_str = if (is_paused) "PAUSED" else "RUNNING";
        const top_text = std.fmt.bufPrint(
            &top_buf,
            "BeSpoke Engine | Tick: {d:03} | Facts: {d} | State: {s}",
            .{ frame.tick, frame.fact_count, status_str },
        ) catch "BeSpoke Engine";
        const status_col = if (is_paused) Color.status_paused else Color.status_running;
        self.draw_text(top_text, 20, 16, 2, status_col);

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
                if (self.hovered_actor) |act_idx| {
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
            if (self.hovered_actor) |act_idx| {
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
        self.draw_line(0, bar_y - 6, self.width, bar_y - 6, Color.tavern_border);

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
                const border_col = if (is_selected) Color{ .r = 250, .g = 204, .b = 21 } else Color.cheese_color;
                const text_col = if (is_selected) Color{ .r = 254, .g = 240, .b = 138 } else Color.cheese_color;

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

        // 8. Bottom Controls HUD Bar
        self.fill_rect(0, self.height - 44, self.width, 44, Color.hud_bg);
        self.draw_line(0, self.height - 44, self.width, self.height - 44, Color.tavern_border);
        if (is_spitting_scene) {
            self.draw_text(
                "[S]: Spit! | [H]: Horn | [G]: GreenDrink | [F]: Move Flags | [Space]: Pause | [< / >]: Scrub",
                20,
                self.height - 28,
                2,
                Color.hud_subtext,
            );
        } else if (is_hotel_scene or is_garden_scene or is_bike_rental_scene) {
            self.draw_text(
                "[H]: Hotel | [G]: Garden | [B]: Bike Shop | [Click]: Act | [Right-Click]: Verb | [0-8]: Steps",
                20,
                self.height - 28,
                2,
                Color{ .r = 250, .g = 204, .b = 21 },
            );
        } else {
            self.draw_text(
                "[Click]: Act | [Right-Click]: Verb | [P/F2/F3]: Save/Load | [F5/F9]: QuickSave | [F1]: Debug | [C]: REPL",
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

        // 9. Speech Balloon & Branching Dialogue (P7-04, D-009)
        if (self.active_balloon) |*b| {
            const brect = get_balloon_rect(b, self.width);

            // Balloon parchment body
            self.fill_rect(brect.x, brect.y, brect.w, brect.h, Color{ .r = 254, .g = 243, .b = 199 });
            self.draw_rect_outline(brect.x, brect.y, brect.w, brect.h, Color{ .r = 146, .g = 64, .b = 14 });
            self.draw_rect_outline(brect.x + 2, brect.y + 2, brect.w - 4, brect.h - 4, Color{ .r = 180, .g = 83, .b = 9 });

            // Speech tail pointing down to speaker
            const tail_x = b.speaker_pos.x;
            self.draw_line(tail_x - 6, brect.y + brect.h, tail_x, brect.y + brect.h + 10, Color{ .r = 146, .g = 64, .b = 14 });
            self.draw_line(tail_x + 6, brect.y + brect.h, tail_x, brect.y + brect.h + 10, Color{ .r = 146, .g = 64, .b = 14 });

            // Speaker title & dialog text
            var title_buf: [48]u8 = undefined;
            const title_text = std.fmt.bufPrint(&title_buf, "{s}:", .{b.get_speaker_name()}) catch "Speaker:";
            self.draw_text(title_text, brect.x + 14, brect.y + 10, 2, Color{ .r = 180, .g = 83, .b = 9 });
            const title_offset = font.text_width(title_text, 2) + 12;
            self.draw_text(b.get_text(), brect.x + 14 + title_offset, brect.y + 10, 2, Color{ .r = 28, .g = 25, .b = 23 });

            // Branching dialogue choices (P13-03, D-015)
            const choices_start_y = brect.y + 42;
            const visible_count = b.visible_choice_count();
            var c_vi: usize = 0;
            while (c_vi < visible_count) : (c_vi += 1) {
                const actual_idx: usize = b.scroll_offset + c_vi;
                if (actual_idx >= b.choice_count) break;

                const cy = choices_start_y + @as(i32, @intCast(c_vi)) * 26;
                const is_hovered = (self.hovered_choice != null and self.hovered_choice.? == actual_idx);
                const c_text = b.get_choice(actual_idx);

                var c_buf: [128]u8 = undefined;
                const numbered_text = std.fmt.bufPrint(&c_buf, "[{d}] {s}", .{ actual_idx + 1, c_text }) catch c_text;

                if (is_hovered) {
                    self.fill_rect(brect.x + 12, cy, brect.w - 24, 22, Color.wp_hover);
                    self.draw_rect_outline(brect.x + 12, cy, brect.w - 24, 22, Color.white);
                    self.draw_text(numbered_text, brect.x + 20, cy + 4, 2, Color.black);
                } else {
                    self.fill_rect(brect.x + 12, cy, brect.w - 24, 22, Color{ .r = 253, .g = 230, .b = 138 });
                    self.draw_rect_outline(brect.x + 12, cy, brect.w - 24, 22, Color{ .r = 217, .g = 119, .b = 6 });
                    self.draw_text(numbered_text, brect.x + 20, cy + 4, 2, Color{ .r = 120, .g = 53, .b = 15 });
                }
            }

            // Scroll indicator if choices exceed visible count (P13-03, D-015)
            if (b.choice_count > 6) {
                const scroll_y = choices_start_y + @as(i32, @intCast(visible_count)) * 26 + 2;
                var sbuf: [64]u8 = undefined;
                const scroll_str = std.fmt.bufPrint(&sbuf, "(Scroll: {d}-{d} of {d} | Wheel/Arrows)", .{
                    b.scroll_offset + 1,
                    @min(b.choice_count, b.scroll_offset + visible_count),
                    b.choice_count,
                }) catch "";
                self.draw_text(scroll_str, brect.x + 16, scroll_y, 1, Color{ .r = 180, .g = 83, .b = 9 });
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
            self.fill_rect(drect.x + 180, tab_y, 150, 28, if (!is_save_mode) Color.wp_target else Color{ .r = 30, .g = 41, .b = 59 });
            self.draw_rect_outline(drect.x + 180, tab_y, 150, 28, if (!is_save_mode) Color.white else Color{ .r = 71, .g = 85, .b = 105 });
            self.draw_text("LOAD GAME [F3]", drect.x + 192, tab_y + 8, 2, if (!is_save_mode) Color.black else Color.hud_text);

            // Resume Button
            self.fill_rect(drect.x + drect.w - 270, tab_y, 130, 28, Color{ .r = 22, .g = 101, .b = 52 });
            self.draw_rect_outline(drect.x + drect.w - 270, tab_y, 130, 28, Color.status_running);
            self.draw_text("RESUME [Esc]", drect.x + drect.w - 256, tab_y + 8, 2, Color.white);

            // Quit Button
            self.fill_rect(drect.x + drect.w - 130, tab_y, 110, 28, Color{ .r = 127, .g = 29, .b = 29 });
            self.draw_rect_outline(drect.x + drect.w - 130, tab_y, 110, 28, Color.cue_alert);
            self.draw_text("QUIT [Q]", drect.x + drect.w - 108, tab_y + 8, 2, Color.white);

            // Render Slot Cards (0 = Quick-Save, 1..8 = Numbered Slots)
            var slot_id: u8 = 0;
            while (slot_id <= save_mod.MAX_SLOTS) : (slot_id += 1) {
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

test "P13-03: display renderer dynamic balloon sizing, scrolling, and choice selection" {
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

    const brect = get_balloon_rect(balloon, 960);
    // Height: 48 + 6 * 26 + 18 (scroll bar) = 222
    try testing.expectEqual(@as(i32, 222), brect.h);
    try testing.expect(brect.y >= 76);

    // 2. Hit-testing at scroll_offset == 0
    // Slot 0 (first visible choice) -> choice 0 ("Ask about the cat")
    const hit_slot0 = hit_test_balloon_choice(brect.x + 20, brect.y + 42 + 10, balloon, brect);
    try testing.expectEqual(@as(?u8, 0), hit_slot0);

    // Slot 1 (second visible choice) -> choice 1 ("Rent motorcycle")
    const hit_slot1 = hit_test_balloon_choice(brect.x + 20, brect.y + 42 + 26 + 10, balloon, brect);
    try testing.expectEqual(@as(?u8, 1), hit_slot1);

    // 3. Scroll offset == 2
    win.active_balloon.?.scroll_offset = 2;
    const balloon_scrolled = &win.active_balloon.?;

    // Slot 0 now corresponds to choice 2 ("Inquire about the templar church")
    const hit_scrolled0 = hit_test_balloon_choice(brect.x + 20, brect.y + 42 + 10, balloon_scrolled, brect);
    try testing.expectEqual(@as(?u8, 2), hit_scrolled0);

    // Slot 5 corresponds to choice 7 ("Say goodbye and leave")
    const hit_scrolled5 = hit_test_balloon_choice(brect.x + 20, brect.y + 42 + 5 * 26 + 10, balloon_scrolled, brect);
    try testing.expectEqual(@as(?u8, 7), hit_scrolled5);

    // Miss outside balloon bounds
    const hit_miss = hit_test_balloon_choice(10, 10, balloon_scrolled, brect);
    try testing.expectEqual(@as(?u8, null), hit_miss);

    // 4. Dismiss dialogue
    win.dismiss_dialogue();
    try testing.expect(win.active_balloon == null);
}

test "P14-02: display renderer dynamically recognizes Gabriel Knight 3 scene themes and actors" {
    const testing = std.testing;

    var frame = std.mem.zeroes(RenderFrame);

    // 1. Hotel corridor theme
    const hotel_scene = "Hotel Corridor";
    @memcpy(frame.current_scene[0..hotel_scene.len], hotel_scene);
    frame.current_scene_len = hotel_scene.len;
    try testing.expectEqualStrings("Hotel Corridor", frame.get_current_scene());

    // 2. Garden fence theme
    const garden_scene = "Hotel Garden";
    @memcpy(frame.current_scene[0..garden_scene.len], garden_scene);
    frame.current_scene_len = garden_scene.len;
    try testing.expectEqualStrings("Hotel Garden", frame.get_current_scene());

    // 3. Bike rental theme
    const shop_scene = "Bike Rental Shop";
    @memcpy(frame.current_scene[0..shop_scene.len], shop_scene);
    frame.current_scene_len = shop_scene.len;
    try testing.expectEqualStrings("Bike Rental Shop", frame.get_current_scene());

    // 4. Add GK3 actors and props to frame
    frame.entity_count = 4;
    const gabriel_name = "Gabriel";
    @memcpy(frame.entities[0].name[0..gabriel_name.len], gabriel_name);
    frame.entities[0].name_len = gabriel_name.len;
    frame.entities[0].entity = EntityId.from_int(10);

    const mosely_name = "Mosely";
    @memcpy(frame.entities[1].name[0..mosely_name.len], mosely_name);
    frame.entities[1].name_len = mosely_name.len;
    frame.entities[1].entity = EntityId.from_int(11);

    const buthane_name = "Buthane";
    @memcpy(frame.entities[2].name[0..buthane_name.len], buthane_name);
    frame.entities[2].name_len = buthane_name.len;
    frame.entities[2].entity = EntityId.from_int(12);

    const cat_name = "StrayCat";
    @memcpy(frame.entities[3].name[0..cat_name.len], cat_name);
    frame.entities[3].name_len = cat_name.len;
    frame.entities[3].entity = EntityId.from_int(13);

    frame.gabriel_disguised = true;
    frame.fence_taped = true;
    frame.bike_rented = true;

    // Verify headless window can render the frame without issue
    var win = try DisplayWindow.init("GK3 Test", 960, 540);
    defer win.deinit();

    win.render_frame(&frame, false);
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

test "P14-02: render_frame renders Hotel Garden with unique courtyard backdrop and fur tape indicators" {
    const testing = std.testing;

    var frame = std.mem.zeroes(RenderFrame);
    const garden_name = "Hotel Garden";
    @memcpy(frame.current_scene[0..garden_name.len], garden_name);
    frame.current_scene_len = garden_name.len;

    const cat_name = "StrayCat";
    @memcpy(frame.entities[0].name[0..cat_name.len], cat_name);
    frame.entities[0].name_len = cat_name.len;
    frame.entities[0].entity = EntityId.from_int(10);
    frame.entities[0].x = 34;
    frame.entities[0].y = 0;
    frame.entity_count = 1;

    frame.fence_taped = true;
    frame.fence_has_hair = true;
    frame.cat_startled = true;

    var win = try DisplayWindow.init("Garden Test", 1280, 720);
    defer win.deinit();

    win.render_frame(&frame, false);
    try testing.expect(frame.fence_taped);
    try testing.expect(frame.fence_has_hair);
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

