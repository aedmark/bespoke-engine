//! The message band rule (D-124, D-127): the rows the message log covers, and what a drawn
//! frame may put in them. One owner, so the desktop render golden and the browser deck golden
//! measure a frame the same way (P43-05).
//!
//! Prop art, marks, people, and every stage string stay out of the band. Backdrop scenery and
//! walkways may reach it (D-124), as may the window's own chrome and overlays: the log writes
//! its lines in the band by design, and the dialogue panel is lifted clear of those lines and
//! drawn over the band's air (D-127). Text records the layer it was drawn on, so the window's
//! own rows are told from the stage's without a separate exemption.

const std = @import("std");
const canvas = @import("canvas.zig");

/// The log's rows (D-099): four scale-2 rows over the command bar, which the rule counts whether
/// or not a window shows one.
pub const LOG_ROWS: usize = 4;
pub const LOG_ROW: i32 = 18;

/// The band's top row at a window height: 504 pixels at 1280x720.
pub fn top(screen_h: i32) i32 {
    return screen_h - 80 - 30 - 28 - (@as(i32, LOG_ROWS) * LOG_ROW + 6);
}

/// The band's bottom row: where the command bar starts, 582 pixels at 1280x720.
pub fn bottom(screen_h: i32) i32 {
    return screen_h - 80 - 30 - 28;
}

/// How many offenders a check keeps. A frame that breaks the rule usually does so once, and the
/// cap keeps a mangled layout from growing the record without bound.
pub const CAP = 8;

/// How many frames this process has measured (P43-06). Each golden compares the growth of this
/// count with the frames it records, so a deleted check fails the run even though every hash is
/// unchanged.
var measured_frames: usize = 0;

/// The number of frames measured so far, for the goldens' tamper check.
pub fn measured() usize {
    return measured_frames;
}

pub const Verdict = enum { clear, overflow, art, text };

pub const Check = struct {
    band_top: i32,
    band_bottom: i32,
    verdict: Verdict = .clear,
    art: [CAP]canvas.RectDraw = undefined,
    art_count: usize = 0,
    text: [CAP]canvas.TextDraw = undefined,
    text_count: usize = 0,

    /// Reads the probes of one drawn frame at `height`. Every prop, mark, person, and stage
    /// string that overlaps the band is kept, so a caller can name all of them before it
    /// stops. A frame the shape probe could not hold is a failed measurement, not a clean one.
    pub fn measure(height: i32, text: *const canvas.TextProbe, rect: *const canvas.RectProbe) Check {
        measured_frames += 1;
        var check = Check{
            .band_top = top(height),
            .band_bottom = bottom(height),
        };
        if (rect.overflowed) {
            check.verdict = .overflow;
            return check;
        }
        for (rect.draws[0..rect.count]) |d| {
            switch (d.kind) {
                .prop, .mark, .actor => {},
                .backdrop, .walkway, .chrome, .overlay => continue,
            }
            if (!check.reaches(d.y, d.h)) continue;
            if (check.art_count < CAP) {
                check.art[check.art_count] = d;
                check.art_count += 1;
            }
            check.verdict = .art;
        }
        for (text.draws[0..text.count]) |d| {
            switch (d.kind) {
                // The window's own rows: the log, the bars, and the dialogue panel (D-127).
                .chrome, .overlay => continue,
                else => {},
            }
            if (!check.reaches(d.y, d.h)) continue;
            if (check.text_count < CAP) {
                check.text[check.text_count] = d;
                check.text_count += 1;
            }
            if (check.verdict == .clear) check.verdict = .text;
        }
        return check;
    }

    /// True when a shape of `h` rows at `y` overlaps the band. A shape that ends on the band's
    /// top row is clear, as D-124's arithmetic has it.
    fn reaches(self: *const Check, y: i32, h: i32) bool {
        return y < self.band_bottom and y + h > self.band_top;
    }

    /// Writes one line per offender, naming the frame as `label`, so a run lists everything a
    /// layout change put in the band rather than the first thing found.
    pub fn report(self: *const Check, label: []const u8) void {
        if (self.verdict == .overflow) std.debug.print(
            "\n'{s}': the frame drew more shapes than the probe holds ({d})\n",
            .{ label, canvas.RectProbe.cap },
        );
        for (self.art[0..self.art_count]) |d| std.debug.print(
            "\n'{s}': art \"{s}\" at ({d}, {d}) size {d}x{d} reaches the message band's rows {d} to {d}\n",
            .{ label, if (d.get_name().len > 0) d.get_name() else "shape", d.x, d.y, d.w, d.h, self.band_top, self.band_bottom },
        );
        for (self.text[0..self.text_count]) |d| std.debug.print(
            "\n'{s}': text \"{s}\" at ({d}, {d}) reaches the message band's rows {d} to {d}\n",
            .{ label, d.get_text(), d.x, d.y, self.band_top, self.band_bottom },
        );
    }
};

test "P43-05: the band check measures stage layers and skips the window's own" {
    const testing = std.testing;
    var text = canvas.TextProbe{};
    var rect = canvas.RectProbe{};
    const band_top = top(720);
    const band_bottom = bottom(720);
    try testing.expectEqual(@as(i32, 504), band_top);
    try testing.expectEqual(@as(i32, 582), band_bottom);

    // A mark and a person in the band fail; backdrop scenery and a walkway there do not.
    rect.record(.mark, "Cottages", 40, band_top - 4, 33, 33);
    try testing.expectEqual(Verdict.art, Check.measure(720, &text, &rect).verdict);
    rect.count = 0;
    rect.record(.backdrop, "roof", 0, band_top, 600, 200);
    rect.record(.walkway, "path", 0, band_top, 1280, 78);
    rect.record(.chrome, "log", 0, band_top, 1280, 78);
    try testing.expectEqual(Verdict.clear, Check.measure(720, &text, &rect).verdict);
    rect.count = 0;

    // A stage string in the band fails, on any stage layer; the log's own rows and a panel do
    // not. A string that ends on the band's top row is clear.
    text.record(.prop, "STEPS UP", 40, band_top + 2, 1);
    try testing.expectEqual(Verdict.text, Check.measure(720, &text, &rect).verdict);
    text.count = 0;
    text.record(.backdrop, "REEF CHART", 40, band_top + 2, 1);
    try testing.expectEqual(Verdict.text, Check.measure(720, &text, &rect).verdict);
    text.count = 0;
    text.record(.chrome, "Tide turns.", 24, band_top + 18, 2);
    text.record(.overlay, "modal", 40, band_top, 1);
    try testing.expectEqual(Verdict.clear, Check.measure(720, &text, &rect).verdict);
    text.count = 0;
    text.record(.mark, "Berth", 40, band_top - 7, 1);
    try testing.expectEqual(Verdict.clear, Check.measure(720, &text, &rect).verdict);

    // Art outranks a string, and an overfull probe outranks both.
    text.record(.prop, "STEPS UP", 40, band_top + 2, 1);
    rect.record(.actor, "Innkeeper", 40, band_top - 14, 37, 37);
    const both = Check.measure(720, &text, &rect);
    try testing.expectEqual(Verdict.art, both.verdict);
    try testing.expectEqual(@as(usize, 1), both.art_count);
    try testing.expectEqual(@as(usize, 1), both.text_count);
    rect.overflowed = true;
    try testing.expectEqual(Verdict.overflow, Check.measure(720, &text, &rect).verdict);

    // P43-06: every measure is counted, so a golden can tie its checks to the lines it records.
    const before = measured();
    _ = Check.measure(720, &text, &rect);
    try testing.expectEqual(before + 1, measured());
}
