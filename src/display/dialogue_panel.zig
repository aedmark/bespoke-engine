//! Dialogue panel layout (D-077): the speaker, the spoken line, and numbered choices, word-
//! wrapped into a panel of fixed width along the bottom of the stage. Pure layout over the
//! bitmap font's fixed advance, with no drawing and no SDL, so the desktop window and the
//! browser canvas draw the same rows and the window hit-tests choices against them.

const std = @import("std");
const font = @import("font.zig");

/// Rows one panel may hold. Nine choices of four rows, a speaker, and a prompt of four rows fit.
pub const MAX_ROWS: usize = 48;
/// Choices one panel lays out; matches `dialogue.MAX_CHOICES`.
pub const MAX_CHOICES: usize = 9;

pub const Metrics = struct {
    /// Panel width in pixels, borders included.
    width: i32,
    /// Font scale: 2 on desktop, 1 in the 640x360 browser canvas.
    scale: i32,
    /// Inner padding on every side.
    pad: i32,
    /// Distance from one text row to the next.
    line_h: i32,
    /// Extra space between the prompt and the first choice, and between choices.
    gap: i32,

    pub const desktop = Metrics{ .width = 1240, .scale = 2, .pad = 12, .line_h = 18, .gap = 6 };
    pub const browser = Metrics{ .width = 616, .scale = 1, .pad = 6, .line_h = 10, .gap = 3 };

    fn columns(self: Metrics, indent: i32) usize {
        const usable = self.width - 2 * self.pad - indent;
        return @intCast(@max(1, @divTrunc(usable, font.char_width(self.scale))));
    }
};

pub const RowKind = enum { speaker, prompt, choice };

pub const Row = struct {
    kind: RowKind,
    text: []const u8,
    /// Offsets from the panel's top-left corner.
    x: i32,
    y: i32,
    /// Choice rows: the choice's index into the caller's slice.
    choice: u8 = 0,
    /// The first row of a choice carries its number, drawn as `[n]` in the indent.
    numbered: bool = false,
};

pub const Layout = struct {
    rows: [MAX_ROWS]Row = undefined,
    row_count: usize = 0,
    /// Vertical span of each laid-out choice, from the panel's top.
    choice_top: [MAX_CHOICES]i32 = [_]i32{0} ** MAX_CHOICES,
    choice_bottom: [MAX_CHOICES]i32 = [_]i32{0} ** MAX_CHOICES,
    choice_count: usize = 0,
    height: i32 = 0,
    /// Pixels a choice's text sits right of the panel padding, leaving room for `[n] `.
    indent: i32 = 0,

    pub fn slice(self: *const Layout) []const Row {
        return self.rows[0..self.row_count];
    }

    /// The choice under a point given relative to the panel's top-left corner.
    pub fn hit(self: *const Layout, x: i32, y: i32, width: i32) ?u8 {
        if (x < 0 or x >= width) return null;
        for (0..self.choice_count) |i| {
            if (y >= self.choice_top[i] and y < self.choice_bottom[i]) return @intCast(i);
        }
        return null;
    }

    fn push(self: *Layout, row: Row) void {
        if (self.row_count == MAX_ROWS) return;
        self.rows[self.row_count] = row;
        self.row_count += 1;
    }
};

/// Splits `text` into rows of at most `columns` characters, breaking at spaces and splitting a
/// word only when it alone is longer than a row. Writes slices of `text` to `out`; returns how
/// many it wrote, stopping when `out` is full.
pub fn wrap(text: []const u8, columns: usize, out: [][]const u8) usize {
    const cols = @max(columns, 1);
    var count: usize = 0;
    var rest = std.mem.trim(u8, text, " ");
    while (rest.len > 0 and count < out.len) {
        if (rest.len <= cols) {
            out[count] = rest;
            count += 1;
            break;
        }
        // Break at the last space that keeps the row within `cols`, else split the word.
        var cut: usize = cols;
        if (std.mem.lastIndexOfScalar(u8, rest[0 .. cols + 1], ' ')) |space| {
            if (space > 0) cut = space;
        }
        out[count] = std.mem.trimRight(u8, rest[0..cut], " ");
        count += 1;
        rest = std.mem.trimLeft(u8, rest[cut..], " ");
    }
    return count;
}

/// A display name for an entity name: `HarbourWarden` reads `Harbour Warden`, `Deckhand2` stays
/// `Deckhand2`, and `NPCPorter` reads `NPC Porter`. A space goes before an uppercase letter that
/// follows a lowercase one, or that starts a word after an acronym, so acronyms stay whole. A
/// name with an inner capital (`McAllister`) splits wrongly; give it a space in the script.
/// Names already containing spaces are returned unchanged.
pub fn display_name(name: []const u8, buf: []u8) []const u8 {
    if (std.mem.indexOfScalar(u8, name, ' ') != null) return name;
    var n: usize = 0;
    for (name, 0..) |ch, i| {
        const after_lower = i > 0 and std.ascii.isLower(name[i - 1]);
        const ends_acronym = i > 0 and std.ascii.isUpper(name[i - 1]) and i + 1 < name.len and std.ascii.isLower(name[i + 1]);
        const split = std.ascii.isUpper(ch) and (after_lower or ends_acronym);
        if (split) {
            if (n == buf.len) return name;
            buf[n] = ' ';
            n += 1;
        }
        if (n == buf.len) return name;
        buf[n] = ch;
        n += 1;
    }
    return buf[0..n];
}

/// Lays out a panel: the speaker on its own row, the prompt wrapped below it, then each choice
/// wrapped with its continuation rows indented under its text. `speaker` should already be a
/// display name. The caller draws each choice's number, so a scrolled set can start above 1.
pub fn layout(m: Metrics, speaker: []const u8, prompt: []const u8, choices: []const []const u8) Layout {
    var out = Layout{};
    const cw = font.char_width(m.scale);
    // "[9] " is four characters; numbers never exceed one digit (MAX_CHOICES is 9).
    out.indent = 4 * cw;
    var y: i32 = m.pad;

    if (speaker.len > 0) {
        out.push(.{ .kind = .speaker, .text = speaker, .x = m.pad, .y = y });
        y += m.line_h;
    }

    var parts: [8][]const u8 = undefined;
    const prompt_rows = wrap(prompt, m.columns(0), &parts);
    for (parts[0..prompt_rows]) |part| {
        out.push(.{ .kind = .prompt, .text = part, .x = m.pad, .y = y });
        y += m.line_h;
    }

    const count = @min(choices.len, MAX_CHOICES);
    if (count > 0 and (speaker.len > 0 or prompt_rows > 0)) y += m.gap;
    for (choices[0..count], 0..) |text, i| {
        out.choice_top[i] = y - @divTrunc(m.gap, 2);
        const rows = wrap(text, m.columns(out.indent), &parts);
        for (parts[0..@max(rows, 1)], 0..) |part, r| {
            out.push(.{
                .kind = .choice,
                .text = if (rows == 0) "" else part,
                .x = m.pad + out.indent,
                .y = y,
                .choice = @intCast(i),
                .numbered = r == 0,
            });
            y += m.line_h;
        }
        out.choice_bottom[i] = y + @divTrunc(m.gap, 2);
        y += m.gap;
    }
    out.choice_count = count;
    out.height = y + m.pad - (if (count > 0) m.gap else 0);
    return out;
}

test "D-077: wrap breaks at spaces, splits only overlong words, and trims" {
    const testing = std.testing;
    var rows: [8][]const u8 = undefined;
    var n = wrap("You wield that sword like a mop handle!", 16, &rows);
    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqualStrings("You wield that", rows[0]);
    try testing.expectEqualStrings("sword like a mop", rows[1]);
    try testing.expectEqualStrings("handle!", rows[2]);

    n = wrap("Supercalifragilistic", 8, &rows);
    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqualStrings("Supercal", rows[0]);
    try testing.expectEqualStrings("ifragili", rows[1]);

    try testing.expectEqual(@as(usize, 1), wrap("  short  ", 40, &rows));
    try testing.expectEqualStrings("short", rows[0]);
    try testing.expectEqual(@as(usize, 0), wrap("   ", 40, &rows));
    // Output is capped at the caller's buffer.
    try testing.expectEqual(@as(usize, 2), wrap("a b c d e f", 1, rows[0..2]));
}

test "D-077: display names split CamelCase and keep acronyms and spaced names" {
    const testing = std.testing;
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("Harbour Warden", display_name("HarbourWarden", &buf));
    try testing.expectEqualStrings("Tamsin", display_name("Tamsin", &buf));
    try testing.expectEqualStrings("NPC Porter", display_name("NPCPorter", &buf));
    try testing.expectEqualStrings("Mira Holt", display_name("Mira Holt", &buf));
    var tiny: [4]u8 = undefined;
    try testing.expectEqualStrings("HarbourWarden", display_name("HarbourWarden", &tiny));
}

test "D-077: a panel wraps the prompt and choices and hit-tests every row of a choice" {
    const testing = std.testing;
    const m = Metrics{ .width = 300, .scale = 1, .pad = 6, .line_h = 10, .gap = 3 };
    const choices = [_][]const u8{
        "Unfortunately for you, they'll be too busy picking apart your reputation.",
        "Er... is that the time?",
    };
    const l = layout(m, "Harbour Warden", "You'll be feeding the gulls by sundown!", &choices);
    try testing.expectEqual(@as(usize, 2), l.choice_count);
    // Every row fits inside the panel.
    for (l.slice()) |row| {
        try testing.expect(row.x + font.text_width(row.text, m.scale) <= m.width - m.pad);
        try testing.expect(row.y + m.line_h <= l.height);
    }
    // The long choice takes several rows; a click on its last row selects it.
    var last_row_y: i32 = 0;
    var first_rows: usize = 0;
    for (l.slice()) |row| if (row.kind == .choice and row.choice == 0) {
        last_row_y = row.y;
        first_rows += 1;
    };
    try testing.expect(first_rows >= 2);
    try testing.expectEqual(@as(?u8, 0), l.hit(50, last_row_y + 2, m.width));
    try testing.expectEqual(@as(?u8, 1), l.hit(50, l.choice_top[1] + 4, m.width));
    try testing.expectEqual(@as(?u8, null), l.hit(50, 2, m.width));
    try testing.expectEqual(@as(?u8, null), l.hit(m.width + 1, l.choice_top[1] + 4, m.width));
}
