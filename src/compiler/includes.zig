//! `include "<path>"`: a game spread over several files (P48-15, D-169, D-185).
//!
//! Includes are expanded before lexing, as if each file were pasted at its include line, so
//! source order after expansion is the order every rule reads (D-160). An include line starts
//! at column 0; a file already included is skipped, which also ends a cycle. Paths are read
//! through the compile's `FileSource`, which keeps them inside the main script's folder, so the
//! rule D-156 sets for PNGs holds for scripts too. The expanded text keeps a map from each of
//! its lines back to a file and a line, so a diagnostic names where its line really is.
const std = @import("std");
const FileSource = @import("parser.zig").FileSource;

/// The total expanded text may not pass the compiler's source limit.
pub const MAX_EXPANDED = 16 * 1024 * 1024;
pub const MAX_FILES = 256;

/// A run of expanded lines that came from one file, in order.
pub const Segment = struct {
    /// First expanded line of the run, counted from 1.
    first: u32,
    /// Lines in the run.
    count: u32,
    /// The file, as its include line wrote it; empty for the main script.
    file: []const u8,
    /// The run's first line in that file.
    file_line: u32,
};

pub const Place = struct { file: []const u8, line: u32 };

pub const Expanded = struct {
    text: []const u8,
    segments: []const Segment,

    /// Where expanded line `line` came from. A line past the end belongs to the last file.
    pub fn locate(self: Expanded, line: u32) Place {
        for (self.segments) |seg| {
            if (line >= seg.first and line < seg.first + seg.count) return .{ .file = seg.file, .line = seg.file_line + (line - seg.first) };
        }
        if (self.segments.len == 0) return .{ .file = "", .line = line };
        const last = self.segments[self.segments.len - 1];
        return .{ .file = last.file, .line = last.file_line + (line -| last.first) };
    }
};

/// Why an expansion stopped, at the include line that caused it.
pub const Failure = struct {
    file: []const u8 = "",
    line: u32 = 0,
    column: u32 = 1,
    message: []const u8 = "",
};

pub const Error = error{ IncludeFailed, OutOfMemory };

/// Expands `source`, whose includes are read from `files`. Without a file source, as in the
/// browser, a script with an include fails like one that reads a PNG. Everything is allocated
/// in `arena`. A script with no include comes back as itself with one segment.
pub fn expand(arena: std.mem.Allocator, source: []const u8, files: ?FileSource, failure: *Failure) Error!Expanded {
    var out = Builder{ .arena = arena, .files = files, .failure = failure };
    try out.add_file(source, "");
    // A main script without a final newline keeps it that way, so an error at its end is
    // reported where it always was.
    if (source.len > 0 and source[source.len - 1] != '\n' and out.text.items.len > 0) out.text.items.len -= 1;
    if (out.segments.items.len == 1 and out.text.items.len == source.len) {
        // Nothing was included: hand back the original bytes, so positions computed from AST
        // slices into the source stay valid for a caller that kept `source`.
        return .{ .text = source, .segments = out.segments.items };
    }
    return .{ .text = out.text.items, .segments = out.segments.items };
}

const Builder = struct {
    arena: std.mem.Allocator,
    files: ?FileSource,
    failure: *Failure,
    text: std.ArrayListUnmanaged(u8) = .empty,
    segments: std.ArrayListUnmanaged(Segment) = .empty,
    seen: std.ArrayListUnmanaged([]const u8) = .empty,
    /// Expanded lines written so far.
    lines: u32 = 0,

    fn fail(self: *Builder, file: []const u8, line: u32, column: u32, comptime fmt: []const u8, args: anytype) Error {
        self.failure.* = .{
            .file = file,
            .line = line,
            .column = column,
            .message = std.fmt.allocPrint(self.arena, fmt, args) catch "include failed",
        };
        return Error.IncludeFailed;
    }

    /// Appends one line of `file` (its `file_line`) to the text and the map.
    fn emit(self: *Builder, line_text: []const u8, file: []const u8, file_line: u32) Error!void {
        if (self.text.items.len + line_text.len + 1 > MAX_EXPANDED) return self.fail(file, file_line, 1, "the script and its includes pass the 16 MiB source limit", .{});
        try self.text.appendSlice(self.arena, line_text);
        try self.text.append(self.arena, '\n');
        self.lines += 1;
        if (self.segments.items.len > 0) {
            const last = &self.segments.items[self.segments.items.len - 1];
            if (std.mem.eql(u8, last.file, file) and last.file_line + last.count == file_line and last.first + last.count == self.lines) {
                last.count += 1;
                return;
            }
        }
        try self.segments.append(self.arena, .{ .first = self.lines, .count = 1, .file = file, .file_line = file_line });
    }

    fn add_file(self: *Builder, source: []const u8, file: []const u8) Error!void {
        var it = std.mem.splitScalar(u8, source, '\n');
        var line_no: u32 = 0;
        while (it.next()) |raw| {
            line_no += 1;
            // A final newline leaves an empty piece that is not a line of its own.
            if (it.index == null and raw.len == 0) break;
            const line_text = std.mem.trimEnd(u8, raw, "\r");
            const trimmed = std.mem.trimStart(u8, line_text, " \t");
            if (!is_include(trimmed)) {
                try self.emit(line_text, file, line_no);
                continue;
            }
            const indent: u32 = @intCast(line_text.len - trimmed.len);
            if (indent > 0) return self.fail(file, line_no, indent + 1, "an include goes at the top level, at the start of its line, not inside a block", .{});
            const path = parse_path(trimmed) orelse return self.fail(file, line_no, 1, "include needs one quoted path, such as include \"acts/one.bespoke\"", .{});
            // The include line itself becomes a blank line, so the lines around it keep their
            // numbers in the map and a block before it ends here.
            try self.emit("", file, line_no);
            const key = normalize(path);
            const already = for (self.seen.items) |prior| {
                if (std.mem.eql(u8, prior, key)) break true;
            } else false;
            if (already) continue;
            if (self.seen.items.len == MAX_FILES) return self.fail(file, line_no, 9, "a game includes at most {d} files", .{MAX_FILES});
            try self.seen.append(self.arena, key);
            const source_files = self.files orelse return self.fail(file, line_no, 9, "include \"{s}\" reads a file, which only a compile from the command line can do", .{path});
            const bytes = source_files.read(source_files.context, self.arena, path) catch |err| return switch (err) {
                error.OutOfMemory => Error.OutOfMemory,
                else => self.fail(file, line_no, 9, "include cannot read \"{s}\" ({s})", .{ path, @errorName(err) }),
            };
            try self.add_file(bytes, key);
        }
    }
};

/// `include` followed by a space or a quote: the word alone or inside a longer name is not one.
fn is_include(trimmed: []const u8) bool {
    if (!std.mem.startsWith(u8, trimmed, "include")) return false;
    if (trimmed.len == "include".len) return true;
    const next = trimmed["include".len];
    return next == ' ' or next == '\t' or next == '"';
}

/// The quoted path of an include line, allowing a trailing comment.
fn parse_path(trimmed: []const u8) ?[]const u8 {
    const rest = std.mem.trimStart(u8, trimmed["include".len..], " \t");
    if (rest.len < 2 or rest[0] != '"') return null;
    const close = std.mem.indexOfScalarPos(u8, rest, 1, '"') orelse return null;
    const path = rest[1..close];
    if (path.len == 0) return null;
    const after = std.mem.trim(u8, rest[close + 1 ..], " \t");
    if (after.len > 0 and after[0] != '#') return null;
    return path;
}

/// `./acts/one.bespoke` and `acts/one.bespoke` are one file.
fn normalize(path: []const u8) []const u8 {
    var p = path;
    while (std.mem.startsWith(u8, p, "./")) p = p[2..];
    return p;
}

const testing = std.testing;

const MemFiles = struct {
    names: []const []const u8,
    bodies: []const []const u8,

    fn source(self: *MemFiles) FileSource {
        return .{ .context = self, .read = read };
    }

    fn read(context: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8 {
        const self: *MemFiles = @ptrCast(@alignCast(context));
        if (std.mem.indexOf(u8, path, "..") != null) return error.PathOutsideScriptFolder;
        for (self.names, self.bodies) |n, b| if (std.mem.eql(u8, n, normalize(path))) return allocator.dupe(u8, b);
        return error.FileNotFound;
    }
};

test "P48-15: includes expand in place, once, and every line maps back to its file" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var mem = MemFiles{
        .names = &.{ "a.bespoke", "b.bespoke" },
        .bodies = &.{ "entity A\ninclude \"b.bespoke\"\nentity A2\n", "entity B\ninclude \"./a.bespoke\"\n" },
    };
    var failure = Failure{};
    const main = "entity Main\ninclude \"a.bespoke\"\ninclude \"b.bespoke\"\nentity End\n";
    const out = try expand(arena, main, mem.source(), &failure);
    // Main, [a: A, [b: B, (a again: skipped)], A2], (b again: skipped), End.
    try testing.expectEqualStrings("entity Main\n\nentity A\n\nentity B\n\nentity A2\n\nentity End\n", out.text);
    try testing.expectEqual(Place{ .file = "", .line = 1 }, out.locate(1));
    try testing.expectEqualStrings("a.bespoke", out.locate(3).file);
    try testing.expectEqual(@as(u32, 1), out.locate(3).line);
    try testing.expectEqualStrings("b.bespoke", out.locate(5).file);
    try testing.expectEqual(@as(u32, 3), out.locate(7).line);
    try testing.expectEqual(Place{ .file = "", .line = 4 }, out.locate(9));

    // A script with no include is itself.
    const plain = "entity Main\n";
    try testing.expectEqual(plain.ptr, (try expand(arena, plain, null, &failure)).text.ptr);
}

test "P48-15: an include that is indented, unreadable, outside the folder, or browser-only is refused at its line" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var mem = MemFiles{ .names = &.{"inner.bespoke"}, .bodies = &.{"entity Inner\ninclude \"gone.bespoke\"\n"} };
    const Case = struct { source: []const u8, files: bool, file: []const u8, line: u32, column: u32, message: []const u8 };
    const cases = [_]Case{
        .{ .source = "routine R(A):\n  include \"inner.bespoke\"\n", .files = true, .file = "", .line = 2, .column = 3, .message = "an include goes at the top level, at the start of its line, not inside a block" },
        .{ .source = "include inner.bespoke\n", .files = true, .file = "", .line = 1, .column = 1, .message = "include needs one quoted path, such as include \"acts/one.bespoke\"" },
        .{ .source = "include \"../secret.bespoke\"\n", .files = true, .file = "", .line = 1, .column = 9, .message = "include cannot read \"../secret.bespoke\" (PathOutsideScriptFolder)" },
        .{ .source = "entity X\ninclude \"inner.bespoke\"\n", .files = true, .file = "inner.bespoke", .line = 2, .column = 9, .message = "include cannot read \"gone.bespoke\" (FileNotFound)" },
        .{ .source = "include \"inner.bespoke\"\n", .files = false, .file = "", .line = 1, .column = 9, .message = "include \"inner.bespoke\" reads a file, which only a compile from the command line can do" },
    };
    for (cases) |case| {
        var failure = Failure{};
        try testing.expectError(Error.IncludeFailed, expand(arena, case.source, if (case.files) mem.source() else null, &failure));
        try testing.expectEqualStrings(case.file, failure.file);
        try testing.expectEqual(case.line, failure.line);
        try testing.expectEqual(case.column, failure.column);
        try testing.expectEqualStrings(case.message, failure.message);
    }
    // A name that only starts with the word is not an include.
    var failure = Failure{};
    const out = try expand(arena, "includes_nothing\n", null, &failure);
    try testing.expectEqualStrings("includes_nothing\n", out.text);
}
