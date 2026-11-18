const std = @import("std");

pub const Diagnostic = struct {
    line: u32,
    column: u32,
    message: []const u8,
};

/// A suggestion needs a unique candidate within one edit, including adjacent swaps.
/// Bound comparisons and copied hints independently of script-controlled token length.
pub const Suggestions = struct {
    pub const max_len = 64;
    name: ?[]const u8 = null,
    ambiguous: bool = false,

    pub fn consider(self: *Suggestions, input: []const u8, candidate: []const u8) void {
        if (input.len < 3 or input.len > max_len or candidate.len > max_len) return;
        if (!one_edit(input, candidate)) return;
        if (self.name) |prior| {
            if (!std.mem.eql(u8, prior, candidate)) self.ambiguous = true;
        } else self.name = candidate;
    }

    pub fn result(self: Suggestions) ?[]const u8 {
        return if (self.ambiguous) null else self.name;
    }
};

fn one_edit(a: []const u8, b: []const u8) bool {
    const shorter, const longer = if (a.len <= b.len) .{ a, b } else .{ b, a };
    if (longer.len - shorter.len > 1) return false;
    var i: usize = 0;
    while (i < shorter.len and shorter[i] == longer[i]) : (i += 1) {}
    if (shorter.len != longer.len) return std.mem.eql(u8, shorter[i..], longer[i + 1 ..]);
    if (i == a.len) return false;
    if (std.mem.eql(u8, a[i + 1 ..], b[i + 1 ..])) return true;
    return i + 1 < a.len and a[i] == b[i + 1] and a[i + 1] == b[i] and
        std.mem.eql(u8, a[i + 2 ..], b[i + 2 ..]);
}
