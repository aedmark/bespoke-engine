//! The Studio's view of an opened project (P47-01, D-151, D-192): the files the page read from
//! the author's folder, held as raw bytes, and a check of one script against them with the
//! engine's own compiler. The Studio keeps no project state of its own (D-151 item 6): this
//! table lives only while the page is open, and the page refills it from disk on every open.
const std = @import("std");
const bespoke = @import("bespoke");
const compiler = bespoke.compiler;

const Allocator = std.mem.Allocator;

/// One file of the opened project. `path` is relative to the opened folder, with `/` between
/// parts. Bytes are kept exactly as read; nothing here decodes or rewrites them, which is what
/// lets a save without edits leave every file byte-identical.
pub const File = struct {
    path: []u8,
    bytes: []u8,
};

pub const Project = struct {
    allocator: Allocator,
    files: std.ArrayList(File) = .empty,
    /// The last check, as JSON for the page; see `write_result`.
    result: std.ArrayList(u8) = .empty,
    /// The last built game, as `.bspk` bytes for the play module (P47-06, D-195); empty when
    /// the last build failed.
    package: std.ArrayList(u8) = .empty,

    pub fn init(allocator: Allocator) Project {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Project) void {
        self.clear();
        self.files.deinit(self.allocator);
        self.result.deinit(self.allocator);
        self.package.deinit(self.allocator);
    }

    pub fn clear(self: *Project) void {
        for (self.files.items) |f| {
            self.allocator.free(f.path);
            self.allocator.free(f.bytes);
        }
        self.files.clearRetainingCapacity();
        self.result.clearRetainingCapacity();
        self.package.clearRetainingCapacity();
    }

    /// Copies `path` and `bytes` in. A second file with the same path replaces the first, so
    /// reloading one file from disk needs no separate call.
    pub fn add(self: *Project, path: []const u8, bytes: []const u8) !void {
        if (!is_clean_path(path)) return error.BadPath;
        const p = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(p);
        const b = try self.allocator.dupe(u8, bytes);
        errdefer self.allocator.free(b);
        for (self.files.items) |*f| if (std.mem.eql(u8, f.path, path)) {
            self.allocator.free(f.path);
            self.allocator.free(f.bytes);
            f.* = .{ .path = p, .bytes = b };
            return;
        };
        try self.files.append(self.allocator, .{ .path = p, .bytes = b });
    }

    pub fn find(self: *const Project, path: []const u8) ?[]const u8 {
        for (self.files.items) |f| if (std.mem.eql(u8, f.path, path)) return f.bytes;
        return null;
    }

    /// Checks the script at `main_path` with `compiler.check_source_with`, resolving its
    /// includes and images from this table, and leaves the outcome in `result`. Returns
    /// whether the script is valid. A missing main script is reported in the same shape as a
    /// compiler diagnostic, so the page has one way to show every failure.
    pub fn check(self: *Project, main_path: []const u8) !bool {
        self.result.clearRetainingCapacity();
        const source = self.find(main_path) orelse {
            try self.write_missing(main_path);
            return false;
        };
        var reader = Reader{ .project = self, .dir = parent_of(main_path) };
        const res = compiler.check_source_with(self.allocator, source, reader.source());
        try self.write_result(main_path, &res);
        return res.is_valid;
    }

    /// Builds the script at `main_path` into a package, as `bespoke compile` does, for the
    /// play window (P47-06, D-195). The check runs first and its JSON lands in `result` either
    /// way, so a script that does not compile reports the same diagnostic the project window
    /// shows; only a valid script reaches the compiler. Returns true with `package` filled.
    pub fn build(self: *Project, main_path: []const u8) !bool {
        self.package.clearRetainingCapacity();
        if (!try self.check(main_path)) return false;
        const source = self.find(main_path).?;
        var world = try bespoke.World.init(self.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
        defer world.deinit();
        var spatial = bespoke.SpatialSystem.init(self.allocator);
        defer spatial.deinit();
        var reader = Reader{ .project = self, .dir = parent_of(main_path) };
        var compiled = try compiler.compile_source_with(self.allocator, &world, &spatial, source, reader.source());
        defer compiled.deinit();
        var out: std.Io.Writer.Allocating = .fromArrayList(self.allocator, &self.package);
        defer self.package = out.toArrayList();
        try bespoke.package.save_package(self.allocator, &out.writer, &compiled, &world, &spatial);
        return true;
    }

    fn write_missing(self: *Project, main_path: []const u8) !void {
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        try w.raw("{\"valid\":false,\"main\":");
        try w.string(main_path);
        try w.raw(",\"line\":0,\"column\":0,\"file\":\"\",\"kind\":\"MainScriptMissing\",\"message\":");
        try w.string("the project has no script at this path");
        try w.raw(",\"suggestion\":\"\",\"warnings\":[]}");
    }

    /// Writes `res` as one JSON object. Diagnostic paths are made relative to the opened folder
    /// (the compiler reports an included file from the main script's folder), so the page can
    /// open the file a diagnostic names without knowing that rule.
    fn write_result(self: *Project, main_path: []const u8, res: *const compiler.CheckResult) !void {
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        const dir = parent_of(main_path);
        try w.raw("{\"valid\":");
        try w.raw(if (res.is_valid) "true" else "false");
        try w.raw(",\"main\":");
        try w.string(main_path);
        try w.raw(",\"line\":");
        try w.number(res.line);
        try w.raw(",\"column\":");
        try w.number(res.column);
        try w.raw(",\"file\":");
        try w.path_in(dir, if (res.is_valid) "" else res.file(), main_path);
        try w.raw(",\"kind\":");
        try w.string(res.kind());
        try w.raw(",\"message\":");
        try w.string(res.message());
        try w.raw(",\"suggestion\":");
        try w.string(res.suggestion() orelse "");
        try w.raw(",\"warnings\":[");
        for (res.warnings[0..res.warning_count], 0..) |*warn, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"line\":");
            try w.number(warn.line);
            try w.raw(",\"column\":");
            try w.number(warn.column);
            try w.raw(",\"file\":");
            try w.path_in(dir, warn.file(), main_path);
            try w.raw(",\"message\":");
            try w.string(warn.message());
            try w.raw("}");
        }
        try w.raw("],\"scenes\":");
        try w.number(res.scene_count);
        try w.raw(",\"routines\":");
        try w.number(res.routine_count);
        try w.raw(",\"rules\":");
        try w.number(res.rule_count);
        try w.raw(",\"bytecode\":");
        try w.number(res.bytecode_len);
        try w.raw("}");
    }
};

/// Serves `include` and `image ... from` reads out of the project table. The rule for which
/// paths a script may name is the command line's (`runner.ScriptFiles`): relative, no `..`, no
/// backslash, inside the main script's folder. Keeping one rule means a project the Studio
/// accepts is one `bespoke check` accepts.
const Reader = struct {
    project: *Project,
    dir: []const u8,

    fn source(self: *Reader) compiler.FileSource {
        return .{ .context = self, .read = read };
    }

    fn read(context: *anyopaque, allocator: Allocator, path: []const u8) anyerror![]const u8 {
        const self: *Reader = @ptrCast(@alignCast(context));
        if (!beside_script(path)) return error.PathOutsideScriptFolder;
        var buf: [1024]u8 = undefined;
        const full = join_clean(&buf, self.dir, path) orelse return error.NameTooLong;
        const bytes = self.project.find(full) orelse return error.FileNotFound;
        if (bytes.len > bespoke.png.MAX_FILE) return error.StreamTooLong;
        return allocator.dupe(u8, bytes);
    }
};

fn beside_script(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or std.mem.indexOfScalar(u8, path, '\\') != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| if (std.mem.eql(u8, part, "..")) return false;
    return true;
}

/// A table path: relative, `/`-separated, no empty, `.`, or `..` part. The page builds paths
/// from directory handles, so anything else is a page bug, refused rather than guessed at.
fn is_clean_path(path: []const u8) bool {
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, '\\') != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

fn parent_of(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return "";
    return path[0..slash];
}

/// `dir` joined with `path`, dropping empty and `.` parts, into `buf`.
fn join_clean(buf: []u8, dir: []const u8, path: []const u8) ?[]const u8 {
    var len: usize = 0;
    for ([_][]const u8{ dir, path }) |piece| {
        var parts = std.mem.splitScalar(u8, piece, '/');
        while (parts.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
            const need = part.len + @as(usize, if (len > 0) 1 else 0);
            if (len + need > buf.len) return null;
            if (len > 0) {
                buf[len] = '/';
                len += 1;
            }
            @memcpy(buf[len .. len + part.len], part);
            len += part.len;
        }
    }
    return buf[0..len];
}

const Json = struct {
    list: *std.ArrayList(u8),
    allocator: Allocator,

    fn raw(self: *Json, text: []const u8) !void {
        try self.list.appendSlice(self.allocator, text);
    }

    fn number(self: *Json, n: anytype) !void {
        var buf: [24]u8 = undefined;
        try self.raw(try std.fmt.bufPrint(&buf, "{d}", .{n}));
    }

    /// A JSON string. Control bytes are escaped; other bytes pass through, and the page decodes
    /// the whole result as UTF-8 with replacement, so a stray byte from a script shows as one
    /// replacement mark instead of breaking the parse.
    fn string(self: *Json, text: []const u8) !void {
        try self.raw("\"");
        for (text) |c| switch (c) {
            '"' => try self.raw("\\\""),
            '\\' => try self.raw("\\\\"),
            '\n' => try self.raw("\\n"),
            '\r' => try self.raw("\\r"),
            '\t' => try self.raw("\\t"),
            0...8, 11, 12, 14...31, 127 => {
                var buf: [6]u8 = undefined;
                try self.raw(try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}));
            },
            else => try self.list.append(self.allocator, c),
        };
        try self.raw("\"");
    }

    /// A diagnostic's file as a table path: the main script when `file` is empty, otherwise
    /// `file` joined to the main script's folder.
    fn path_in(self: *Json, dir: []const u8, file: []const u8, main_path: []const u8) !void {
        if (file.len == 0) return self.string(if (main_path.len > 0) main_path else "");
        var buf: [1024]u8 = undefined;
        try self.string(join_clean(&buf, dir, file) orelse file);
    }
};

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

fn result_has(p: *const Project, needle: []const u8) bool {
    return std.mem.indexOf(u8, p.result.items, needle) != null;
}

test "a valid project checks and reports its counts" {
    var p = Project.init(testing.allocator);
    defer p.deinit();
    try p.add("scripts/main.bespoke",
        \\scene Yard:
        \\  cast: Walker
        \\  marks: Gate, Well
        \\
        \\routine Stroll(Walker):
        \\  walk Walker to Well
        \\
    );
    try testing.expect(try p.check("scripts/main.bespoke"));
    try testing.expect(result_has(&p, "\"valid\":true"));
    try testing.expect(result_has(&p, "\"scenes\":1"));
    try testing.expect(result_has(&p, "\"routines\":1"));
}

test "a broken script reports its line, kind, and main file" {
    var p = Project.init(testing.allocator);
    defer p.deinit();
    try p.add("main.bespoke", "scene Yard:\n  cast: Walker\n\nroutine Stroll(Walker):\n  walk Walker to\n");
    try testing.expect(!try p.check("main.bespoke"));
    try testing.expect(result_has(&p, "\"valid\":false"));
    try testing.expect(result_has(&p, "\"file\":\"main.bespoke\""));
    try testing.expect(!result_has(&p, "\"kind\":\"\""));
    try testing.expect(!result_has(&p, "\"line\":0"));
}

test "includes resolve from the main script's folder and name the included file" {
    var p = Project.init(testing.allocator);
    defer p.deinit();
    try p.add("scripts/main.bespoke", "include \"rooms/yard.bespoke\"\n");
    try p.add("scripts/rooms/yard.bespoke", "scene Yard:\n  cast: Walker\n\nroutine Stroll(Walker):\n  walk Walker to\n");
    try testing.expect(!try p.check("scripts/main.bespoke"));
    try testing.expect(result_has(&p, "\"file\":\"scripts/rooms/yard.bespoke\""));

    try p.add("scripts/rooms/yard.bespoke", "scene Yard:\n  cast: Walker\n  marks: Gate\n");
    try testing.expect(try p.check("scripts/main.bespoke"));
}

test "a script cannot read outside its folder, as on the command line" {
    var p = Project.init(testing.allocator);
    defer p.deinit();
    try p.add("scripts/main.bespoke", "include \"../secret.bespoke\"\n");
    try p.add("secret.bespoke", "scene Vault:\n  cast: Thief\n");
    try testing.expect(!try p.check("scripts/main.bespoke"));
    try testing.expect(result_has(&p, "\"valid\":false"));
}

test "a missing main script is a diagnostic, not a failure" {
    var p = Project.init(testing.allocator);
    defer p.deinit();
    try testing.expect(!try p.check("scripts/main.bespoke"));
    try testing.expect(result_has(&p, "\"kind\":\"MainScriptMissing\""));
}

test "bytes are kept exactly and a re-add replaces" {
    var p = Project.init(testing.allocator);
    defer p.deinit();
    const odd = "\xef\xbb\xbfscene A:\r\n  cast: B\r\n\xff";
    try p.add("main.bespoke", odd);
    try testing.expectEqualSlices(u8, odd, p.find("main.bespoke").?);
    try p.add("main.bespoke", "x");
    try testing.expectEqual(@as(usize, 1), p.files.items.len);
    try testing.expectEqualSlices(u8, "x", p.find("main.bespoke").?);
}

test "table paths must be clean" {
    var p = Project.init(testing.allocator);
    defer p.deinit();
    for ([_][]const u8{ "", "/abs", "a//b", "./a", "a/../b", "a\\b", "a/" }) |bad| {
        try testing.expectError(error.BadPath, p.add(bad, "x"));
    }
}

test "json strings escape quotes and control bytes" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(testing.allocator);
    var w = Json{ .list = &list, .allocator = testing.allocator };
    try w.string("a\"b\\c\n\x01");
    try testing.expectEqualStrings("\"a\\\"b\\\\c\\n\\u0001\"", list.items);
}

test "a valid project builds to a package the runtime loader reads back" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    try p.add("game/main.bespoke", "include \"rooms.bespoke\"\n\nroutine Walk(Hero):\n  walk Hero to Pier\n");
    try p.add("game/rooms.bespoke", "scene Quay:\n  cast: Hero\n  marks: Steps, Pier\n");
    try std.testing.expect(try p.build("game/main.bespoke"));
    try std.testing.expect(std.mem.startsWith(u8, p.package.items, &bespoke.package.PACKAGE_MAGIC));

    var world = try bespoke.World.init(std.testing.allocator, 256 * 1024);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(std.testing.allocator);
    defer spatial.deinit();
    var stream: std.Io.Reader = .fixed(p.package.items);
    var loaded = try bespoke.package.load_package(std.testing.allocator, &stream, &world, &spatial);
    defer loaded.deinit();
    try std.testing.expect(world.lookup_entity("Pier") != null);
}

test "a broken project builds nothing and reports the check's diagnostic" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    try p.add("main.bespoke", "scene Yard:\n  cast: Walker\n\nroutine Stroll(Walker):\n  walk Walker to\n");
    try std.testing.expect(!try p.build("main.bespoke"));
    try std.testing.expectEqual(@as(usize, 0), p.package.items.len);
    try std.testing.expect(result_has(&p, "\"valid\":false"));
}
