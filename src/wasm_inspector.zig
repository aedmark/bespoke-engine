//! The browser's state inspector (P30-04, D-070): the desktop State tab (D-058, D-059) drawn
//! into the wasm canvas. It reads the same 128-fact capture (`display.capture_debug_facts`) and
//! the same pure layout, filter, and expiry functions (`display/state_graph.zig`), so both
//! inspectors show one picture of the World. `I` toggles it and pauses the clock while open.
//! Navigation state belongs to the inspector, not the World: it is never saved or rewound.
const std = @import("std");
const display = @import("display.zig");
const state_graph = @import("display/state_graph.zig");
const dialogue_mod = @import("dialogue.zig");
const world_mod = @import("world.zig");
const font = @import("display/font.zig");
const wasm = @import("wasm.zig");

const World = world_mod.World;
const EntityId = world_mod.EntityId;
const RgbaColor = wasm.RgbaColor;
const WasmCanvas = wasm.WasmCanvas;
const RenderDebugFact = display.RenderDebugFact;

pub const HISTORY: usize = 8;

/// Key codes the browser sends for the inspector's named keys: the DOM's own `keyCode` values,
/// since the runtime's key event carries one byte. Letters arrive as their ASCII codes.
pub const Key = struct {
    pub const backspace: u8 = 8;
    pub const enter: u8 = 13;
    pub const home: u8 = 36;
    pub const left: u8 = 37;
    pub const right: u8 = 39;
};

/// The overlay's layout inside the 640x360 canvas: the graph on the left of the stage box, the
/// lists on the right, a key line along the bottom of the stage.
const STAGE_X: i32 = 12;
const STAGE_Y: i32 = 44;
const STAGE_W: i32 = 616;
const STAGE_H: i32 = 248;
const GRAPH_CX: i32 = 196;
const GRAPH_CY: i32 = 160;
const GRAPH_RX: i32 = 150;
const GRAPH_RY: i32 = 88;
const LIST_X: i32 = 392;
const NODE_R: i32 = 9;

const BELIEF = RgbaColor{ .r = 192, .g = 132, .b = 252 };
const PANEL = RgbaColor{ .r = 9, .g = 14, .b = 26 };
const DIM = RgbaColor{ .r = 100, .g = 116, .b = 139 };

pub const Inspector = struct {
    open: bool = false,
    /// The run state to restore on close.
    was_paused: bool = false,
    focus: ?EntityId = null,
    selected: usize = 0,
    history: [HISTORY]EntityId = undefined,
    history_len: usize = 0,
    filter: state_graph.Filter = .{},
    facts: [display.MAX_DEBUG_FACTS]RenderDebugFact = undefined,
    fact_count: usize = 0,

    /// Opening pauses the clock so the state holds still; closing restores the earlier state.
    pub fn toggle(self: *Inspector, is_paused: *bool) void {
        if (self.open) {
            self.open = false;
            is_paused.* = self.was_paused;
        } else {
            self.open = true;
            self.was_paused = is_paused.*;
            is_paused.* = true;
        }
    }

    pub fn capture(self: *Inspector, world: *const World) void {
        self.fact_count = display.capture_debug_facts(world, &self.facts);
        // A focus the World no longer mentions (after a scrub or a deck change) is dropped with
        // the history built on it, as the desktop inspector does (D-059).
        if (self.focus) |f| {
            if (!state_graph.mentions(self.captured(), f)) self.reset();
        }
    }

    pub fn captured(self: *const Inspector) []const RenderDebugFact {
        return self.facts[0..self.fact_count];
    }

    fn reset(self: *Inspector) void {
        self.focus = null;
        self.history_len = 0;
        self.selected = 0;
    }

    fn resolved_focus(self: *const Inspector) ?EntityId {
        const facts = self.captured();
        return self.focus orelse state_graph.default_focus(facts, self.filter) orelse state_graph.default_focus(facts, .{});
    }

    pub fn layout(self: *Inspector) ?state_graph.Layout {
        const focus = self.resolved_focus() orelse return null;
        const l = state_graph.build(self.captured(), focus, self.filter, GRAPH_CX, GRAPH_CY, GRAPH_RX, GRAPH_RY);
        if (self.selected >= l.ring_len) self.selected = 0;
        return l;
    }

    fn recentre(self: *Inspector, from: EntityId, entity: EntityId) void {
        if (self.history_len == HISTORY) {
            std.mem.copyForwards(EntityId, self.history[0 .. HISTORY - 1], self.history[1..HISTORY]);
            self.history_len -= 1;
        }
        self.history[self.history_len] = from;
        self.history_len += 1;
        self.focus = entity;
        self.selected = 0;
    }

    /// The desktop's keys (D-059). Returns true when the key belonged to the inspector.
    pub fn key(self: *Inspector, code: u8) bool {
        const l = self.layout();
        const ring_len = if (l) |x| x.ring_len else 0;
        switch (code) {
            Key.right, Key.left => {
                if (ring_len == 0) return true;
                self.selected = if (code == Key.right) (self.selected + 1) % ring_len else (self.selected + ring_len - 1) % ring_len;
            },
            Key.enter => {
                const x = l orelse return true;
                if (ring_len == 0) return true;
                self.recentre(x.center.entity, x.ring[self.selected].entity);
            },
            Key.backspace => {
                if (self.history_len == 0) return true;
                self.history_len -= 1;
                self.focus = self.history[self.history_len];
                self.selected = 0;
            },
            Key.home => self.reset(),
            'f', 'F' => {
                self.filter = state_graph.next_filter(self.captured(), self.filter);
                self.selected = 0;
            },
            else => return false,
        }
        return true;
    }

    /// A click on a ring node recentres on it. Returns true when the click hit one.
    pub fn click(self: *Inspector, x: i32, y: i32) bool {
        const l = self.layout() orelse return false;
        const ring = l.hit_ring(x, y, NODE_R + 4) orelse return false;
        self.recentre(l.center.entity, l.ring[ring].entity);
        return true;
    }

    pub fn draw(self: *Inspector, canvas: *WasmCanvas, world: *const World) void {
        const now = world.current_tick;
        const facts = self.captured();
        // The panel spans the canvas width, so stage labels that run past the stage box do not
        // show through at its edges.
        canvas.fill_rect(0, STAGE_Y, wasm.CANVAS_WIDTH, STAGE_H, PANEL);
        canvas.draw_rect_outline(STAGE_X, STAGE_Y, STAGE_W, STAGE_H, RgbaColor.sky_blue);
        var title_buf: [96]u8 = undefined;
        const title = std.fmt.bufPrint(&title_buf, "STATE INSPECTOR | TICK {d} | {d} FACTS | FILTER {s}", .{ now, facts.len, self.filter.label() }) catch "STATE INSPECTOR";
        canvas.draw_text(title, STAGE_X + 8, STAGE_Y + 6, 1, RgbaColor.gold);
        canvas.draw_text("<- -> SELECT  ENTER CENTRE  BKSP BACK  HOME RESET  F FILTER  I CLOSE", STAGE_X + 8, STAGE_Y + STAGE_H - 12, 1, DIM);

        var list_y: i32 = STAGE_Y + 22;
        if (self.layout()) |l| {
            // Edges first, so nodes draw over them; each is labelled with its relation. Several
            // facts between the same two entities share one line, so their labels stack.
            var stacked = [_]i32{0} ** state_graph.MAX_RING;
            for (l.edges[0..l.edge_len]) |edge| {
                const node = l.ring[edge.ring];
                const fact = &facts[edge.fact];
                const col = fact_colour(fact, now);
                canvas.draw_line(l.center.x, l.center.y, node.x, node.y, col);
                const mx = @divTrunc(l.center.x + node.x, 2);
                const my = @divTrunc(l.center.y + node.y, 2);
                canvas.draw_text(clip(fact.get_relation(), 12), mx - 18, my - 4 + stacked[edge.ring] * 9, 1, col);
                stacked[edge.ring] += 1;
            }
            for (l.ring_nodes(), 0..) |node, i| {
                const selected = i == self.selected;
                canvas.fill_circle(node.x, node.y, NODE_R, if (selected) RgbaColor.gold else RgbaColor.emerald);
                canvas.draw_circle_outline(node.x, node.y, NODE_R, RgbaColor.white);
                canvas.draw_text(clip(state_graph.name_of(facts, node.entity), 12), node.x - 18, node.y + NODE_R + 3, 1, RgbaColor.white);
            }
            canvas.fill_circle(l.center.x, l.center.y, NODE_R + 3, RgbaColor.sky_blue);
            canvas.draw_circle_outline(l.center.x, l.center.y, NODE_R + 3, RgbaColor.white);
            canvas.draw_text(clip(state_graph.name_of(facts, l.center.entity), 16), l.center.x - 24, l.center.y + NODE_R + 6, 1, RgbaColor.gold);
            if (l.hidden_neighbours > 0) {
                var more_buf: [32]u8 = undefined;
                canvas.draw_text(std.fmt.bufPrint(&more_buf, "+{d} more", .{l.hidden_neighbours}) catch "", STAGE_X + 8, STAGE_Y + STAGE_H - 26, 1, DIM);
            }

            // Values and states of the focus.
            canvas.draw_text("VALUES & STATES", LIST_X, list_y, 1, RgbaColor.sky_blue);
            list_y += 11;
            for (l.listed[0..l.listed_len]) |fi| {
                if (list_y > STAGE_Y + 118) break;
                const fact = &facts[fi];
                var row_buf: [64]u8 = undefined;
                const row = if (fact.object_len > 0)
                    std.fmt.bufPrint(&row_buf, "{s} {s}", .{ clip(fact.get_relation(), 16), clip(fact.get_object(), 14) }) catch ""
                else
                    std.fmt.bufPrint(&row_buf, "{s}", .{clip(fact.get_relation(), 28)}) catch "";
                canvas.draw_text(row, LIST_X + 4, list_y, 1, fact_colour(fact, now));
                list_y += 10;
            }
        } else {
            canvas.draw_text("No facts yet.", GRAPH_CX - 36, GRAPH_CY, 1, DIM);
        }

        // The open dialogue's branches, pruned ones with their first failed guard (D-058).
        list_y = @max(list_y + 4, STAGE_Y + 128);
        if (dialogue_mod.view(world)) |open| {
            canvas.draw_text("DIALOGUE", LIST_X, list_y, 1, RgbaColor.sky_blue);
            list_y += 11;
            const count = if (open.branch_count > 0) open.branch_count else open.count;
            for (0..count) |i| {
                if (list_y > STAGE_Y + 176) break;
                var row_buf: [64]u8 = undefined;
                if (open.branch_count > 0) {
                    const b = open.branch(i);
                    const row = std.fmt.bufPrint(&row_buf, "{s} {s}", .{ if (b.active) "+" else "x", clip(b.text, 26) }) catch "";
                    canvas.draw_text(row, LIST_X + 4, list_y, 1, if (b.active) RgbaColor.emerald else RgbaColor.crimson);
                } else {
                    const row = std.fmt.bufPrint(&row_buf, "+ {s}", .{clip(open.text(i), 26)}) catch "";
                    canvas.draw_text(row, LIST_X + 4, list_y, 1, RgbaColor.emerald);
                }
                list_y += 10;
            }
        }

        // The next deadlines already in the World; nothing is simulated ahead (D-058).
        list_y = @max(list_y + 4, STAGE_Y + 182);
        canvas.draw_text("NEXT TO HAPPEN", LIST_X, list_y, 1, RgbaColor.sky_blue);
        list_y += 11;
        const next = state_graph.next_expiring(facts, now);
        if (next.len == 0) canvas.draw_text("nothing expires", LIST_X + 4, list_y, 1, DIM);
        for (next.facts[0..next.len]) |fi| {
            if (list_y > STAGE_Y + STAGE_H - 24) break;
            const fact = &facts[fi];
            var row_buf: [64]u8 = undefined;
            const row = std.fmt.bufPrint(&row_buf, "T{d} {s} {s}", .{ fact.expires_at_tick, clip(fact.get_subject(), 10), clip(fact.get_relation(), 12) }) catch "";
            canvas.draw_text(row, LIST_X + 4, list_y, 1, fact_colour(fact, now));
            list_y += 10;
        }
    }
};

fn clip(text: []const u8, max: usize) []const u8 {
    return text[0..@min(text.len, max)];
}

/// The desktop's colours (D-058): white permanent, then green, amber, and red as a fact runs
/// out, grey just expired, and purple for beliefs.
fn fact_colour(fact: *const RenderDebugFact, now: u64) RgbaColor {
    if (state_graph.is_belief(fact) and !fact.recently_expired) return BELIEF;
    return switch (state_graph.band(fact, now)) {
        .permanent => RgbaColor.white,
        .fresh => RgbaColor.emerald,
        .waning => RgbaColor.amber,
        .ending => RgbaColor.crimson,
        .expired => DIM,
    };
}

comptime {
    // The overlay's text is sized for the 6-pixel font at scale 1.
    std.debug.assert(font.char_width(1) == 6);
}
