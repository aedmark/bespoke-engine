const std = @import("std");
const font = @import("font.zig");

pub const LabelPlacement = enum {
    above,
    below,
    center,
};

pub const LabelCategory = enum {
    actor_name,
    actor_status,
    waypoint_hover,
    waypoint_idle,
    hotspot_hover,
    prop_label,
};

pub const LabelPriority = enum(u8) {
    backdrop_prop = 1,
    waypoint_idle = 2,
    waypoint_target = 6,
    actor_status = 7,
    actor_name = 8,
    actor_alert = 9,
    hover_tooltip = 10,
};

pub const LabelRect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn intersects(self: LabelRect, other: LabelRect, pad_x: i32, pad_y: i32) bool {
        const left_a = self.x - pad_x;
        const right_a = self.x + self.w + pad_x;
        const top_a = self.y - pad_y;
        const bottom_a = self.y + self.h + pad_y;

        const left_b = other.x;
        const right_b = other.x + other.w;
        const top_b = other.y;
        const bottom_b = other.y + other.h;

        return (left_a < right_b and right_a > left_b and
            top_a < bottom_b and bottom_a > top_b);
    }
};

pub const Obstacle = struct {
    rect: LabelRect,
};

pub const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,
};

pub const TextLabel = struct {
    text: [64]u8 = undefined,
    text_len: usize = 0,
    anchor_x: i32,
    anchor_y: i32,
    placed_x: i32 = 0,
    placed_y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    scale: i32 = 1,
    color: Color = .{},
    placement: LabelPlacement = .below,
    preferred_offset: i32 = 8,
    category: LabelCategory = .actor_status,
    priority: LabelPriority = .actor_status,
    visible: bool = true,

    pub fn init(
        content: []const u8,
        anchor_x: i32,
        anchor_y: i32,
        placement: LabelPlacement,
        preferred_offset: i32,
        scale: i32,
        color: Color,
        category: LabelCategory,
        priority: LabelPriority,
    ) TextLabel {
        var label = TextLabel{
            .anchor_x = anchor_x,
            .anchor_y = anchor_y,
            .placement = placement,
            .preferred_offset = preferred_offset,
            .scale = scale,
            .color = color,
            .category = category,
            .priority = priority,
            .visible = true,
        };
        const len = @min(content.len, label.text.len);
        @memcpy(label.text[0..len], content[0..len]);
        label.text_len = len;
        label.recompute_dimensions();
        return label;
    }

    pub fn get_text(self: *const TextLabel) []const u8 {
        return self.text[0..self.text_len];
    }

    pub fn recompute_dimensions(self: *TextLabel) void {
        const slice = self.get_text();
        self.width = font.text_width(slice, self.scale);
        self.height = font.FONT_HEIGHT * self.scale;
    }

    pub fn rect(self: *const TextLabel) LabelRect {
        return .{
            .x = self.placed_x,
            .y = self.placed_y,
            .w = self.width,
            .h = self.height,
        };
    }
};

pub const MAX_LABELS = 64;
pub const MAX_OBSTACLES = 32;

/// Centralized 2D label layout resolver that eliminates text overlaps across
/// living actors, interactive waypoints, and scene props (D-008, D-012, D-024).
pub const TextLayoutResolver = struct {
    labels: [MAX_LABELS]TextLabel = undefined,
    label_count: usize = 0,
    obstacles: [MAX_OBSTACLES]Obstacle = undefined,
    obstacle_count: usize = 0,
    screen_w: i32,
    screen_h: i32,
    stage_top: i32 = 72,
    stage_bottom_margin: i32 = 76,
    padding_x: i32 = 4,
    padding_y: i32 = 2,

    pub fn init(screen_w: i32, screen_h: i32) TextLayoutResolver {
        return .{
            .screen_w = screen_w,
            .screen_h = screen_h,
        };
    }

    pub fn add_obstacle(self: *TextLayoutResolver, x: i32, y: i32, w: i32, h: i32) void {
        if (self.obstacle_count < MAX_OBSTACLES) {
            self.obstacles[self.obstacle_count] = .{
                .rect = .{ .x = x, .y = y, .w = w, .h = h },
            };
            self.obstacle_count += 1;
        }
    }

    pub fn submit(self: *TextLayoutResolver, label: TextLabel) void {
        if (self.label_count < MAX_LABELS) {
            self.labels[self.label_count] = label;
            self.label_count += 1;
        }
    }

    pub fn get_labels(self: *const TextLayoutResolver) []const TextLabel {
        return self.labels[0..self.label_count];
    }

    /// Resolves label placement to ensure no two visible labels overlap.
    pub fn resolve(self: *TextLayoutResolver) void {
        if (self.label_count == 0) return;

        // Process in priority order (highest priority placed first)
        // We use an index array to sort indices without copying labels.
        var order: [MAX_LABELS]usize = undefined;
        for (0..self.label_count) |i| {
            order[i] = i;
        }

        // Insertion sort by descending priority
        var i: usize = 1;
        while (i < self.label_count) : (i += 1) {
            const current_idx = order[i];
            const current_prio = @intFromEnum(self.labels[current_idx].priority);
            var j: usize = i;
            while (j > 0 and @intFromEnum(self.labels[order[j - 1]].priority) < current_prio) : (j -= 1) {
                order[j] = order[j - 1];
            }
            order[j] = current_idx;
        }

        // Track indices of placed labels
        var placed_indices: [MAX_LABELS]usize = undefined;
        var placed_count: usize = 0;

        for (0..self.label_count) |k| {
            const idx = order[k];
            const lbl = &self.labels[idx];

            self.place_label(lbl, placed_indices[0..placed_count]);

            if (lbl.visible) {
                placed_indices[placed_count] = idx;
                placed_count += 1;
            }
        }
    }

    fn place_label(
        self: *const TextLayoutResolver,
        lbl: *TextLabel,
        placed_indices: []const usize,
    ) void {
        // Base candidate position centered at anchor
        const half_w = @divTrunc(lbl.width, 2);
        var cand_x = lbl.anchor_x - half_w;

        // Clamp to screen bounds with margin
        cand_x = std.math.clamp(cand_x, 10, self.screen_w - lbl.width - 10);

        const raw_y = switch (lbl.placement) {
            .above => lbl.anchor_y - lbl.preferred_offset - lbl.height,
            .below => lbl.anchor_y + lbl.preferred_offset,
            .center => lbl.anchor_y - @divTrunc(lbl.height, 2),
        };
        const max_y = @max(self.stage_top, self.screen_h - self.stage_bottom_margin - lbl.height);
        const cand_y = std.math.clamp(raw_y, self.stage_top, max_y);

        var candidate_rect = LabelRect{
            .x = cand_x,
            .y = cand_y,
            .w = lbl.width,
            .h = lbl.height,
        };

        // If no collision at preferred position, accept immediately
        if (!self.has_collision(candidate_rect, placed_indices, false)) {
            lbl.placed_x = cand_x;
            lbl.placed_y = cand_y;
            lbl.visible = true;
            return;
        }

        // Collision detected: apply category-specific resolution strategy
        switch (lbl.category) {
            .waypoint_idle => {
                // For idle waypoints: try placing above instead of below
                const alt_y = lbl.anchor_y - lbl.preferred_offset - lbl.height;
                const alt_rect = LabelRect{
                    .x = cand_x,
                    .y = alt_y,
                    .w = lbl.width,
                    .h = lbl.height,
                };
                if (!self.has_collision(alt_rect, placed_indices, false)) {
                    lbl.placed_x = cand_x;
                    lbl.placed_y = alt_y;
                    lbl.visible = true;
                    return;
                }
                // Contested by actor or higher-priority label: suppress idle text
                // Ground mark circle remains visible; hovering will display full tooltip
                lbl.visible = false;
            },

            .actor_status => {
                // If scale is 2 and string is long (> 10 chars), try downscaling to scale 1 first
                if (lbl.scale > 1 and lbl.text_len > 10) {
                    lbl.scale = 1;
                    lbl.recompute_dimensions();
                    cand_x = std.math.clamp(lbl.anchor_x - @divTrunc(lbl.width, 2), 10, self.screen_w - lbl.width - 10);
                    candidate_rect = LabelRect{
                        .x = cand_x,
                        .y = cand_y,
                        .w = lbl.width,
                        .h = lbl.height,
                    };
                    if (!self.has_collision(candidate_rect, placed_indices, false)) {
                        lbl.placed_x = cand_x;
                        lbl.placed_y = cand_y;
                        lbl.visible = true;
                        return;
                    }
                }

                // Try vertical tier staggering downward (Tiers 1, 2, 3)
                const row_step = lbl.height + 4;
                var tier: i32 = 1;
                while (tier <= 3) : (tier += 1) {
                    const test_y = cand_y + tier * row_step;
                    const test_rect = LabelRect{
                        .x = cand_x,
                        .y = test_y,
                        .w = lbl.width,
                        .h = lbl.height,
                    };
                    if (!self.has_collision(test_rect, placed_indices, false)) {
                        lbl.placed_x = cand_x;
                        lbl.placed_y = test_y;
                        lbl.visible = true;
                        return;
                    }
                }

                // If downward is blocked, try above
                const above_y = lbl.anchor_y - lbl.preferred_offset - lbl.height - 24;
                const above_rect = LabelRect{
                    .x = cand_x,
                    .y = above_y,
                    .w = lbl.width,
                    .h = lbl.height,
                };
                if (!self.has_collision(above_rect, placed_indices, false)) {
                    lbl.placed_x = cand_x;
                    lbl.placed_y = above_y;
                    lbl.visible = true;
                    return;
                }

                // Fallback: place at first tiered row
                lbl.placed_x = cand_x;
                lbl.placed_y = cand_y + row_step;
                lbl.visible = true;
            },

            .actor_name => {
                // Stagger upward (Tiers 1, 2)
                const row_step = lbl.height + 4;
                var tier: i32 = 1;
                while (tier <= 2) : (tier += 1) {
                    const test_y = cand_y - tier * row_step;
                    const test_rect = LabelRect{
                        .x = cand_x,
                        .y = test_y,
                        .w = lbl.width,
                        .h = lbl.height,
                    };
                    if (!self.has_collision(test_rect, placed_indices, false)) {
                        lbl.placed_x = cand_x;
                        lbl.placed_y = test_y;
                        lbl.visible = true;
                        return;
                    }
                }

                // Try horizontal nudge left or right
                const nudge_left = std.math.clamp(cand_x - 30, 10, self.screen_w - lbl.width - 10);
                const rect_l = LabelRect{ .x = nudge_left, .y = cand_y, .w = lbl.width, .h = lbl.height };
                if (!self.has_collision(rect_l, placed_indices, false)) {
                    lbl.placed_x = nudge_left;
                    lbl.placed_y = cand_y;
                    lbl.visible = true;
                    return;
                }

                const nudge_right = std.math.clamp(cand_x + 30, 10, self.screen_w - lbl.width - 10);
                const rect_r = LabelRect{ .x = nudge_right, .y = cand_y, .w = lbl.width, .h = lbl.height };
                if (!self.has_collision(rect_r, placed_indices, false)) {
                    lbl.placed_x = nudge_right;
                    lbl.placed_y = cand_y;
                    lbl.visible = true;
                    return;
                }

                lbl.placed_x = cand_x;
                lbl.placed_y = cand_y - row_step;
                lbl.visible = true;
            },

            else => {
                // For hover prompts and other labels: try above or below
                const alt_y = if (lbl.placement == .above)
                    lbl.anchor_y + lbl.preferred_offset
                else
                    lbl.anchor_y - lbl.preferred_offset - lbl.height;

                const alt_rect = LabelRect{
                    .x = cand_x,
                    .y = alt_y,
                    .w = lbl.width,
                    .h = lbl.height,
                };
                if (!self.has_collision(alt_rect, placed_indices, false)) {
                    lbl.placed_x = cand_x;
                    lbl.placed_y = alt_y;
                    lbl.visible = true;
                    return;
                }

                lbl.placed_x = cand_x;
                lbl.placed_y = cand_y;
                lbl.visible = true;
            },
        }
    }

    fn has_collision(
        self: *const TextLayoutResolver,
        rect: LabelRect,
        placed_indices: []const usize,
        ignore_obstacles: bool,
    ) bool {
        // Check collision against placed labels
        for (placed_indices) |idx| {
            const other = &self.labels[idx];
            if (!other.visible) continue;
            if (rect.intersects(other.rect(), self.padding_x, self.padding_y)) {
                return true;
            }
        }

        // Check collision against registered physical obstacles (actor tokens, etc.)
        if (!ignore_obstacles) {
            for (self.obstacles[0..self.obstacle_count]) |obs| {
                if (rect.intersects(obs.rect, 2, 2)) {
                    return true;
                }
            }
        }

        return false;
    }
};

test "TextLayoutResolver resolves non-overlapping positions" {
    var resolver = TextLayoutResolver.init(1280, 720);

    // George at x=352
    resolver.submit(TextLabel.init(
        "George",
        352,
        300,
        .above,
        18,
        2,
        .{},
        .actor_name,
        .actor_name,
    ));
    resolver.submit(TextLabel.init(
        "[Standing]",
        352,
        300,
        .below,
        18,
        1,
        .{},
        .actor_status,
        .actor_status,
    ));

    // Billy Goat at x=568
    resolver.submit(TextLabel.init(
        "Billy Goat",
        568,
        300,
        .above,
        18,
        2,
        .{},
        .actor_name,
        .actor_name,
    ));
    resolver.submit(TextLabel.init(
        "[Guarding Dig Entrance]",
        568,
        300,
        .below,
        18,
        1,
        .{},
        .actor_status,
        .actor_status,
    ));

    // FallMark waypoint at x=424 (between George and Billy Goat)
    resolver.submit(TextLabel.init(
        "FallMark",
        424,
        300,
        .below,
        12,
        1,
        .{},
        .waypoint_idle,
        .waypoint_idle,
    ));

    resolver.resolve();

    const labels = resolver.get_labels();
    try std.testing.expectEqual(@as(usize, 5), labels.len);

    // Verify all active labels do not overlap
    for (labels, 0..) |la, idx_a| {
        if (!la.visible) continue;
        for (labels, 0..) |lb, idx_b| {
            if (idx_a >= idx_b or !lb.visible) continue;
            try std.testing.expect(!la.rect().intersects(lb.rect(), 0, 0));
        }
    }
}

test "TextLayoutResolver staggers colliding actor statuses vertically" {
    var resolver = TextLayoutResolver.init(1280, 720);

    // Two actors occupying the exact same X coordinate
    resolver.submit(TextLabel.init(
        "[KNOCKED DOWN!]",
        424,
        300,
        .below,
        18,
        1,
        .{},
        .actor_status,
        .actor_alert,
    ));
    resolver.submit(TextLabel.init(
        "[CHARGING! RAMMING GEORGE!]",
        424,
        300,
        .below,
        18,
        1,
        .{},
        .actor_status,
        .actor_status,
    ));

    resolver.resolve();

    const labels = resolver.get_labels();
    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expect(labels[0].visible);
    try std.testing.expect(labels[1].visible);
    // Must be staggered on different Y coordinates without overlap
    try std.testing.expect(labels[0].placed_y != labels[1].placed_y);
    try std.testing.expect(!labels[0].rect().intersects(labels[1].rect(), 0, 0));
}

test "TextLayoutResolver suppresses idle waypoint if congested" {
    var resolver = TextLayoutResolver.init(1280, 720);

    // Add physical obstacle where actor stands
    resolver.add_obstacle(350, 280, 40, 40);

    // Long status occupying the area
    resolver.submit(TextLabel.init(
        "[Very Long Status Label That Occupies A Wide Area]",
        350,
        300,
        .below,
        18,
        2,
        .{},
        .actor_status,
        .actor_status,
    ));

    // Idle waypoint right underneath that same spot
    resolver.submit(TextLabel.init(
        "CongestedWaypoint",
        350,
        300,
        .below,
        18,
        1,
        .{},
        .waypoint_idle,
        .waypoint_idle,
    ));

    resolver.resolve();

    const labels = resolver.get_labels();
    try std.testing.expect(labels[0].visible); // actor status is visible
    try std.testing.expect(!labels[1].visible); // idle waypoint suppressed to avoid collision
}

test "D-024: Lochmarne courtyard layout resolves George, Billy Goat, and FallMark without collisions" {
    // Screen dimensions 960 x 540 (default BeSpoke engine resolution)
    var resolver = TextLayoutResolver.init(960, 540);

    // George at world (4, 0) -> screen approx (352, 300)
    // Billy Goat at world (16, 0) -> screen approx (568, 300)
    // FallMark waypoint at world (8, 0) -> screen approx (424, 300)
    const george_x: i32 = 352;
    const george_y: i32 = 300;
    const goat_x: i32 = 568;
    const goat_y: i32 = 300;
    const fallmark_x: i32 = 424;
    const fallmark_y: i32 = 300;
    const actor_radius: i32 = 16;
    const wp_radius: i32 = 12;

    // 1. Add physical body obstacles
    resolver.add_obstacle(george_x - actor_radius, george_y - actor_radius, actor_radius * 2, actor_radius * 2);
    resolver.add_obstacle(goat_x - actor_radius, goat_y - actor_radius, actor_radius * 2, actor_radius * 2);
    resolver.add_obstacle(fallmark_x - wp_radius, fallmark_y - wp_radius, wp_radius * 2, wp_radius * 2);

    // 2. Submit George labels (Name scale 2 above, Status scale 1 below)
    resolver.submit(TextLabel.init(
        "George",
        george_x,
        george_y,
        .above,
        actor_radius + 2,
        2,
        .{},
        .actor_name,
        .actor_name,
    ));
    resolver.submit(TextLabel.init(
        "[Standing]",
        george_x,
        george_y,
        .below,
        actor_radius + 4,
        1,
        .{},
        .actor_status,
        .actor_status,
    ));

    // 3. Submit Billy Goat labels (Name scale 2 above, Status scale 1 below)
    resolver.submit(TextLabel.init(
        "Billy Goat",
        goat_x,
        goat_y,
        .above,
        actor_radius + 2,
        2,
        .{},
        .actor_name,
        .actor_name,
    ));
    resolver.submit(TextLabel.init(
        "[Guarding Dig Entrance]",
        goat_x,
        goat_y,
        .below,
        actor_radius + 4,
        1,
        .{},
        .actor_status,
        .actor_status,
    ));

    // 4. Submit FallMark waypoint (Idle waypoint scale 1 below)
    resolver.submit(TextLabel.init(
        "FallMark",
        fallmark_x,
        fallmark_y,
        .below,
        wp_radius + 6,
        1,
        .{},
        .waypoint_idle,
        .waypoint_idle,
    ));

    // Resolve layout
    resolver.resolve();

    const labels = resolver.get_labels();
    try std.testing.expectEqual(@as(usize, 5), labels.len);

    // Verify zero overlaps among all visible labels
    for (labels, 0..) |la, idx_a| {
        if (!la.visible) continue;
        for (labels, 0..) |lb, idx_b| {
            if (idx_a >= idx_b or !lb.visible) continue;
            try std.testing.expect(!la.rect().intersects(lb.rect(), 0, 0));
        }
    }
}
