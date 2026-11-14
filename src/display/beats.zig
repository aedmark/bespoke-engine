//! Click-through messages (D-080): a short queue of lines, each shown alone in the dialogue
//! panel until the player clicks or presses a key, so a burst of results (a spoken line, who
//! took the round, the score) is read one piece at a time instead of crammed into one banner.
//! While any message waits, the panel's choices stay hidden and unanswerable. The queue holds
//! copies, not slices, so a host may queue text from a scratch buffer, and is pure data with
//! no SDL, so the desktop window and the browser canvas share it.

const std = @import("std");
const dialogue_panel = @import("dialogue_panel.zig");

/// Messages one queue holds. A host queues a few per event; more are dropped, not failed.
pub const CAPACITY: usize = 8;
pub const SPEAKER_LEN: usize = 32;
pub const TEXT_LEN: usize = 256;

/// What the panel's last row says while a message shows.
pub const HINT = "Click or press Enter to continue";

pub const Beat = struct {
    speaker_buf: [SPEAKER_LEN]u8 = undefined,
    speaker_len: usize = 0,
    text_buf: [TEXT_LEN]u8 = undefined,
    text_len: usize = 0,

    /// The speaker's display name; empty for narration.
    pub fn speaker(self: *const Beat) []const u8 {
        return self.speaker_buf[0..self.speaker_len];
    }

    pub fn text(self: *const Beat) []const u8 {
        return self.text_buf[0..self.text_len];
    }
};

pub const Beats = struct {
    items: [CAPACITY]Beat = undefined,
    head: usize = 0,
    count: usize = 0,

    /// Queues one message. `speaker` is an entity name or empty; it is stored as a display name
    /// (`HarbourWarden` reads `Harbour Warden`, D-077). Text longer than `TEXT_LEN` is cut; empty text
    /// and a full queue are ignored, so a host never fails a tick over a message.
    pub fn push(self: *Beats, speaker: []const u8, text: []const u8) void {
        if (text.len == 0 or self.count == CAPACITY) return;
        const slot = &self.items[(self.head + self.count) % CAPACITY];
        slot.* = .{};
        var name_buf: [SPEAKER_LEN]u8 = undefined;
        const shown = dialogue_panel.display_name(speaker, &name_buf);
        slot.speaker_len = @min(shown.len, SPEAKER_LEN);
        @memcpy(slot.speaker_buf[0..slot.speaker_len], shown[0..slot.speaker_len]);
        slot.text_len = @min(text.len, TEXT_LEN);
        @memcpy(slot.text_buf[0..slot.text_len], text[0..slot.text_len]);
        self.count += 1;
    }

    /// The message showing now.
    pub fn front(self: *const Beats) ?*const Beat {
        if (self.count == 0) return null;
        return &self.items[self.head];
    }

    /// Dismisses the message showing now; true if there was one.
    pub fn advance(self: *Beats) bool {
        if (self.count == 0) return false;
        self.head = (self.head + 1) % CAPACITY;
        self.count -= 1;
        return true;
    }

    pub fn pending(self: *const Beats) bool {
        return self.count > 0;
    }

    pub fn clear(self: *Beats) void {
        self.head = 0;
        self.count = 0;
    }
};

test "D-080: messages show one at a time, in order, with display names" {
    const testing = std.testing;
    var q = Beats{};
    try testing.expect(q.front() == null);
    q.push("HarbourWarden", "The tide waits for nobody, least of all you.");
    q.push("", "Their point.");
    q.push("", "");
    q.push("", "Points: you 0, Harbour Warden 1.");
    try testing.expectEqual(@as(usize, 3), q.count);
    try testing.expectEqualStrings("Harbour Warden", q.front().?.speaker());
    try testing.expect(q.advance());
    try testing.expectEqualStrings("", q.front().?.speaker());
    try testing.expectEqualStrings("Their point.", q.front().?.text());
    try testing.expect(q.advance());
    try testing.expectEqualStrings("Points: you 0, Harbour Warden 1.", q.front().?.text());
    try testing.expect(q.advance());
    try testing.expect(!q.advance());
    try testing.expect(!q.pending());
}

test "D-080: a full queue drops further messages and wraps after advancing" {
    const testing = std.testing;
    var q = Beats{};
    for (0..CAPACITY + 2) |_| q.push("", "line");
    try testing.expectEqual(CAPACITY, q.count);
    _ = q.advance();
    q.push("", "last");
    var seen: usize = 0;
    var last: []const u8 = "";
    while (q.front()) |b| : (_ = q.advance()) {
        last = b.text();
        seen += 1;
    }
    try testing.expectEqual(CAPACITY, seen);
    try testing.expectEqualStrings("last", last);
    // Copies, not slices: the source buffer may change after queueing.
    var scratch = [_]u8{ 'a', 'b' };
    q.push("", &scratch);
    scratch[0] = 'z';
    try testing.expectEqualStrings("ab", q.front().?.text());
}
