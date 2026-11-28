//! The Studio's view of an opened project (P47-01, D-151, D-192): the files the page read from
//! the author's folder, held as raw bytes, and a check of one script against them with the
//! engine's own compiler. The Studio keeps no project state of its own (D-151 item 6): this
//! table lives only while the page is open, and the page refills it from disk on every open.
const std = @import("std");
const bespoke = @import("bespoke");
const compiler = bespoke.compiler;
const png_write = @import("png_write.zig");

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
    /// The pixel editor's last answer (P47-02, D-196): a sheet's RGBA pixels from `pixels`, or
    /// PNG bytes from `encode`. `blob_width` and `blob_height` size a sheet.
    blob: std.ArrayList(u8) = .empty,
    blob_width: u32 = 0,
    blob_height: u32 = 0,

    pub fn init(allocator: Allocator) Project {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Project) void {
        self.clear();
        self.files.deinit(self.allocator);
        self.result.deinit(self.allocator);
        self.package.deinit(self.allocator);
        self.blob.deinit(self.allocator);
    }

    pub fn clear(self: *Project) void {
        for (self.files.items) |f| {
            self.allocator.free(f.path);
            self.allocator.free(f.bytes);
        }
        self.files.clearRetainingCapacity();
        self.result.clearRetainingCapacity();
        self.package.clearRetainingCapacity();
        self.blob.clearRetainingCapacity();
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

    /// Drops `path` from the table; nothing happens when it is not there.
    pub fn remove(self: *Project, path: []const u8) void {
        for (self.files.items, 0..) |f, i| if (std.mem.eql(u8, f.path, path)) {
            self.allocator.free(f.path);
            self.allocator.free(f.bytes);
            _ = self.files.orderedRemove(i);
            return;
        };
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

    /// Lists the art the script at `main_path` declares, as JSON in `result`, for the pixel
    /// editor (P47-02, D-196): each image with the table path of its PNG (empty for inline
    /// rows) and of the script that declares it, its frames, the sprites' and looks' animations,
    /// and the declared palette. A script that does not parse gets the check's JSON instead and
    /// returns false, so the editor shows the same diagnostic the project window does.
    pub fn art(self: *Project, main_path: []const u8) !bool {
        self.result.clearRetainingCapacity();
        const source = self.find(main_path) orelse {
            try self.write_missing(main_path);
            return false;
        };
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var reader = Reader{ .project = self, .dir = parent_of(main_path) };
        const found = compiler.art_sources(arena.allocator(), source, reader.source()) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.check(main_path);
        };
        const dir = parent_of(main_path);
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        var buf: [1024]u8 = undefined;
        try w.raw("{\"valid\":true,\"images\":[");
        for (found.images, 0..) |img, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"name\":");
            try w.string(img.name);
            try w.raw(",\"file\":");
            try w.string(if (img.file.len == 0) "" else join_clean(&buf, dir, img.file) orelse "");
            try w.raw(",\"script\":");
            try w.string(if (img.script.len == 0) main_path else join_clean(&buf, dir, img.script) orelse main_path);
            try w.raw(",\"line\":");
            try w.number(img.line);
            inline for (.{ "width", "height", "frame_width", "frame_height" }) |field| {
                try w.raw(",\"" ++ field ++ "\":");
                try w.number(@field(img, field));
            }
            try w.raw("}");
        }
        try w.raw("],\"animations\":[");
        for (found.animations, 0..) |anim, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"owner\":");
            try w.string(anim.owner);
            try w.raw(if (anim.look) ",\"look\":true" else ",\"look\":false");
            try w.raw(",\"image\":");
            try w.number(anim.image);
            try w.raw(",\"anim\":");
            try w.string(@tagName(anim.anim));
            try w.raw(",\"steps\":[");
            for (anim.steps, 0..) |step, j| {
                if (j > 0) try w.raw(",");
                try w.raw("[");
                try w.number(step.frame);
                try w.raw(",");
                try w.number(step.duration);
                try w.raw("]");
            }
            try w.raw("]}");
        }
        try w.raw("],\"palette\":[");
        for (found.palette, 0..) |c, i| {
            if (i > 0) try w.raw(",");
            try w.raw("[");
            try w.number(c.r);
            try w.raw(",");
            try w.number(c.g);
            try w.raw(",");
            try w.number(c.b);
            try w.raw("]");
        }
        try w.raw("]}");
        return true;
    }

    /// Decodes the PNG at table path `path` with the engine's own reader, the one the compiler
    /// uses, into `blob` as RGBA. False when the table has no such file or it is not a PNG the
    /// engine reads.
    pub fn pixels(self: *Project, path: []const u8) !bool {
        self.blob.clearRetainingCapacity();
        const bytes = self.find(path) orelse return false;
        var rgba = bespoke.png.decode(self.allocator, bytes) catch |err| {
            if (err == error.OutOfMemory) return err;
            return false;
        };
        defer rgba.deinit(self.allocator);
        try self.blob.appendSlice(self.allocator, rgba.pixels);
        self.blob_width = rgba.width;
        self.blob_height = rgba.height;
        return true;
    }

    /// Encodes `rgba` as a PNG into `blob`, read back through the engine's decoder first
    /// (`png_write.encode_checked`). Errors name what was refused.
    pub fn encode(self: *Project, width: u32, height: u32, rgba: []const u8) png_write.Error!void {
        self.blob.clearRetainingCapacity();
        const bytes = try png_write.encode_checked(self.allocator, width, height, rgba);
        defer self.allocator.free(bytes);
        try self.blob.appendSlice(self.allocator, bytes);
    }

    pub const NewImage = struct {
        /// The script that gets the `image` line, a table path.
        script: []const u8,
        /// One word: a letter, then letters, digits, or underscores.
        name: []const u8,
        /// The PNG as the `from` line names it, relative to the main script's folder.
        file: []const u8,
        /// 0 and 0 for a sheet that is one frame.
        frame_width: u32 = 0,
        frame_height: u32 = 0,
        /// The PNG's bytes, kept exactly (an import) or a fresh transparent sheet.
        png: []const u8,
    };

    /// Adds a new image to the project (P47-10, D-197): `img.png` at its table path and one
    /// `image` line in `img.script` after that script's last image declaration, or at its end.
    /// The project is then checked with both; when it does not check, both changes are undone.
    /// `result` holds JSON: `{"added":true,"script":..,"file":..,"line":N}` when kept,
    /// `{"added":false,"refused":".."}` for a request refused before the check, or the check's
    /// own JSON when the compiler refused the result. Returns whether the image was added.
    pub fn add_image(self: *Project, main_path: []const u8, img: NewImage) !bool {
        self.result.clearRetainingCapacity();
        const dir = parent_of(main_path);
        var path_buf: [1024]u8 = undefined;
        const refusal: ?[]const u8 = blk: {
            if (!is_image_word(img.name)) break :blk "an image name is one word: a letter, then letters, digits, or underscores";
            if (!beside_script(img.file) or !std.ascii.endsWithIgnoreCase(img.file, ".png")) break :blk "the file is a .png path inside the project, written with / and no ..";
            if ((img.frame_width == 0) != (img.frame_height == 0)) break :blk "frames need both a width and a height";
            if (self.find(img.script) == null) break :blk "the project has no such script";
            break :blk null;
        };
        if (refusal) |why| return self.refuse(why);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        // Copied out at once: `path_buf` is reused for every join below.
        const png_owned = try a.dupe(u8, join_clean(&path_buf, dir, img.file) orelse return self.refuse("the file's path is too long"));
        if (self.find(png_owned) != null) return self.refuse("a file with that path is already in the project");
        // Names already declared, and where the chosen script's last image ends.
        var reader = Reader{ .project = self, .dir = dir };
        const declared = compiler.art_sources(a, self.find(main_path) orelse return self.refuse("the project has no main script"), reader.source()) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.check(main_path);
        };
        var after: u32 = 0; // the script line the new line follows; 0 means the end
        for (declared.images) |existing| {
            if (std.mem.eql(u8, existing.name, img.name)) return self.refuse("the script already declares an image with that name");
            const in_script = if (existing.script.len == 0) main_path else join_clean(&path_buf, dir, existing.script) orelse "";
            if (!std.mem.eql(u8, in_script, img.script)) continue;
            // An inline image's rows follow its line, one per row.
            const last = existing.line + if (existing.file.len == 0) @as(u32, existing.height) else 0;
            after = @max(after, last);
        }
        const old_script = try self.allocator.dupe(u8, self.find(img.script).?);
        defer self.allocator.free(old_script);
        const line_text = if (img.frame_width == 0)
            try std.fmt.allocPrint(a, "image {s} from \"{s}\"", .{ img.name, img.file })
        else
            try std.fmt.allocPrint(a, "image {s} from \"{s}\" frames {d}x{d}", .{ img.name, img.file, img.frame_width, img.frame_height });
        const spliced = try insert_line(a, old_script, after, line_text);
        try self.add(png_owned, img.png);
        try self.add(img.script, spliced.bytes);
        if (!try self.check(main_path)) {
            self.remove(png_owned);
            try self.add(img.script, old_script);
            return false;
        }
        self.result.clearRetainingCapacity();
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        try w.raw("{\"added\":true,\"script\":");
        try w.string(img.script);
        try w.raw(",\"file\":");
        try w.string(png_owned);
        try w.raw(",\"line\":");
        try w.number(spliced.line);
        try w.raw("}");
        return true;
    }

    /// Lists the scenes of the script at `main_path` for the room editor (P47-03, D-200), as
    /// JSON in `result`: each scene's file and lines, backdrop image, marks and props with their
    /// written and drawn art positions, walkways, exits, areas, grids, and room block, with
    /// whether that block holds a comment. A script that does not parse gets the check's JSON
    /// and returns false.
    pub fn rooms(self: *Project, main_path: []const u8) !bool {
        self.result.clearRetainingCapacity();
        const source = self.find(main_path) orelse {
            try self.write_missing(main_path);
            return false;
        };
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const dir = parent_of(main_path);
        var reader = Reader{ .project = self, .dir = dir };
        const scenes = compiler.room_sources(arena.allocator(), source, reader.source()) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.check(main_path);
        };
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        var buf: [1024]u8 = undefined;
        try w.raw("{\"valid\":true,\"scenes\":[");
        for (scenes, 0..) |sc, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"name\":");
            try w.string(sc.name);
            try w.raw(",\"declared\":");
            try self.json_lines(&w, &buf, main_path, dir, sc.declared);
            try w.raw("}");
            try w.raw(",\"backdrop\":");
            try w.string(sc.backdrop);
            try w.raw(",\"chained\":");
            try w.raw(if (sc.chained) "true" else "false");
            try w.raw(",\"places\":[");
            for (sc.places, 0..) |pl, j| {
                if (j > 0) try w.raw(",");
                try w.raw("{\"name\":");
                try w.string(pl.name);
                try w.raw(if (pl.prop) ",\"prop\":true" else ",\"prop\":false");
                try w.raw(if (pl.placed) ",\"placed\":true" else ",\"placed\":false");
                try w.raw(if (pl.by_grid) ",\"by_grid\":true" else ",\"by_grid\":false");
                inline for (.{ "x", "y", "drawn_x", "drawn_y" }) |f| {
                    try w.raw(",\"" ++ f ++ "\":");
                    try w.number(@field(pl, f));
                }
                try w.raw("}");
            }
            try w.raw("],\"walkways\":[");
            for (sc.walkways, 0..) |wk, j| {
                if (j > 0) try w.raw(",");
                try w.raw("[");
                try w.string(wk.a);
                try w.raw(",");
                try w.string(wk.b);
                try w.raw("]");
            }
            try w.raw("],\"exits\":[");
            for (sc.exits, 0..) |e, j| {
                if (j > 0) try w.raw(",");
                try w.raw("{\"mark\":");
                try w.string(e.mark);
                try w.raw(",\"to_scene\":");
                try w.string(e.to_scene);
                try w.raw(",\"to_mark\":");
                try w.string(e.to_mark);
                try w.raw("}");
            }
            try w.raw("],\"areas\":[");
            for (sc.areas, 0..) |ar, j| {
                if (j > 0) try w.raw(",");
                try w.raw("{\"prop\":");
                try w.string(ar.prop);
                inline for (.{ "x", "y", "w", "h" }) |f| {
                    try w.raw(",\"" ++ f ++ "\":");
                    try w.number(@field(ar, f));
                }
                try w.raw(if (ar.in_block) ",\"in_block\":true}" else ",\"in_block\":false}");
            }
            try w.raw("],\"grids\":[");
            for (sc.grids, 0..) |g, j| {
                if (j > 0) try w.raw(",");
                try w.raw("{\"name\":");
                try w.string(g.name);
                inline for (.{ "width", "height", "cell", "origin_x", "origin_y", "burn", "spread", "dissipate", "flow" }) |f| {
                    try w.raw(",\"" ++ f ++ "\":");
                    try w.number(@field(g, f));
                }
                try w.raw(",\"places\":[");
                for (g.places, 0..) |gp, k| {
                    if (k > 0) try w.raw(",");
                    try w.raw("{\"mark\":");
                    try w.string(gp.mark);
                    try w.raw(",\"x\":");
                    try w.number(gp.x);
                    try w.raw(",\"y\":");
                    try w.number(gp.y);
                    try w.raw("}");
                }
                try w.raw("],\"block\":");
                try self.json_lines(&w, &buf, main_path, dir, g.block);
                const gpath = table_script(&buf, main_path, dir, g.block.script);
                try w.raw(if (has_comment(self.find(gpath) orelse "", g.block.line, g.block.end_line)) ",\"comments\":true}" else ",\"comments\":false}");
                try w.raw(",\"rects\":[");
                for (g.rects, 0..) |r, k| {
                    if (k > 0) try w.raw(",");
                    try w.raw("{\"attribute\":");
                    try w.string(r.attribute);
                    inline for (.{ "x", "y", "width", "height" }) |f| {
                        try w.raw(",\"" ++ f ++ "\":");
                        try w.number(@field(r, f));
                    }
                    try w.raw("}");
                }
                try w.raw("]}");
            }
            try w.raw("],\"block\":");
            if (sc.block) |b| {
                try self.json_lines(&w, &buf, main_path, dir, b);
                const path = table_script(&buf, main_path, dir, b.script);
                // `json_lines` leaves its object open, so the block adds whether it has comments.
                try w.raw(if (has_comment(self.find(path) orelse "", b.line, b.end_line)) ",\"comments\":true}" else ",\"comments\":false}");
            } else try w.raw("null");
            try w.raw("}");
        }
        try w.raw("]}");
        return true;
    }

    /// Writes `lines` as an object without its closing brace, so a caller can add fields.
    fn json_lines(self: *Project, w: *Json, buf: []u8, main_path: []const u8, dir: []const u8, lines: compiler.ScriptLines) !void {
        _ = self;
        try w.raw("{\"script\":");
        try w.string(table_script(buf, main_path, dir, lines.script));
        try w.raw(",\"line\":");
        try w.number(lines.line);
        try w.raw(",\"end_line\":");
        try w.number(lines.end_line);
    }

    /// A layout edit as the page sends it: one record per line, fields split by tabs, which no
    /// name can hold. `scene<TAB>Name` first. A `room` record asks for the room block, followed
    /// by `mark`/`prop<TAB>Name<TAB>x<TAB>y`, `area<TAB>Prop<TAB>x<TAB>y<TAB>w<TAB>h`,
    /// `walkway<TAB>A<TAB>B`, and `exit<TAB>Mark<TAB>Scene<TAB>Mark`, written in that order
    /// (P47-03, D-200). A `grid<TAB>Name` record asks for the grid block, with
    /// `size<TAB>W<TAB>H`, `cell<TAB>N`, `origin<TAB>X<TAB>Y`, `rate<TAB>burn|spread|dissipate|flow<TAB>N`,
    /// `set<TAB>attribute<TAB>x<TAB>y` once per set cell, and `place<TAB>Mark<TAB>x<TAB>y`
    /// (P47-12, D-201). Plain records keep a JSON reader, about 45 KB, out of the module.
    const GRID_ATTRIBUTES = [_][]const u8{ "flammable", "liquid", "blocking", "burning", "smoke" };
    const RATES = [_][]const u8{ "burn", "spread", "dissipate", "flow" };

    const GridEdit = struct {
        name: []const u8,
        width: u32 = 0,
        height: u32 = 0,
        cell: u32 = 0,
        origin_x: i32 = 0,
        origin_y: i32 = 0,
        rates: [4]u32 = .{ 0, 0, 0, 0 },
        cells: std.ArrayList(struct { attribute: usize, x: u32, y: u32 }) = .empty,
        places: std.ArrayList([]const u8) = .empty,
    };

    const RoomEdit = struct {
        scene: []const u8 = "",
        room: bool = false,
        /// The room block's lines after its header, already in the language.
        lines: std.ArrayList([]const u8) = .empty,
        grid: ?GridEdit = null,
    };

    fn parse_room_edit(a: Allocator, text: []const u8) !?RoomEdit {
        var edit = RoomEdit{};
        var records = std.mem.splitScalar(u8, text, '\n');
        while (records.next()) |record| {
            if (record.len == 0) continue;
            var f: [6][]const u8 = undefined;
            var n: usize = 0;
            var fields = std.mem.splitScalar(u8, record, '\t');
            while (fields.next()) |field| {
                if (n == f.len) return null;
                f[n] = field;
                n += 1;
            }
            const kind = f[0];
            const num = struct {
                fn of(t: []const u8) ?u32 {
                    return std.fmt.parseInt(u32, t, 10) catch null;
                }
            }.of;
            const is = struct {
                fn of(k: []const u8, want: []const u8) bool {
                    return std.mem.eql(u8, k, want);
                }
            }.of;
            if (is(kind, "scene") and n == 2) {
                edit.scene = f[1];
            } else if (is(kind, "room") and n == 1) {
                edit.room = true;
            } else if ((is(kind, "mark") or is(kind, "prop")) and n == 4) {
                const x = num(f[2]) orelse return null;
                const y = num(f[3]) orelse return null;
                edit.room = true;
                try edit.lines.append(a, try std.fmt.allocPrint(a, "  {s} {s} at {d} {d}", .{ kind, try room_name(a, f[1]), x, y }));
            } else if (is(kind, "area") and n == 6) {
                var v: [4]u32 = undefined;
                for (&v, f[2..6]) |*out, t| out.* = num(t) orelse return null;
                edit.room = true;
                try edit.lines.append(a, try std.fmt.allocPrint(a, "  area {s}: {d} {d} {d} {d}", .{ try room_name(a, f[1]), v[0], v[1], v[2], v[3] }));
            } else if (is(kind, "walkway") and n == 3) {
                edit.room = true;
                try edit.lines.append(a, try std.fmt.allocPrint(a, "  walkway {s} to {s}", .{ try room_name(a, f[1]), try room_name(a, f[2]) }));
            } else if (is(kind, "exit") and n == 4) {
                edit.room = true;
                try edit.lines.append(a, try std.fmt.allocPrint(a, "  exit {s} to {s} at {s}", .{ try room_name(a, f[1]), try room_name(a, f[2]), try room_name(a, f[3]) }));
            } else if (is(kind, "grid") and n == 2) {
                if (edit.grid != null or !is_image_word(f[1])) return null;
                edit.grid = .{ .name = f[1] };
            } else if (edit.grid) |*g| {
                if (is(kind, "size") and n == 3) {
                    g.width = num(f[1]) orelse return null;
                    g.height = num(f[2]) orelse return null;
                } else if (is(kind, "cell") and n == 2) {
                    g.cell = num(f[1]) orelse return null;
                } else if (is(kind, "origin") and n == 3) {
                    g.origin_x = std.fmt.parseInt(i32, f[1], 10) catch return null;
                    g.origin_y = std.fmt.parseInt(i32, f[2], 10) catch return null;
                } else if (is(kind, "rate") and n == 3) {
                    const i = for (RATES, 0..) |r, k| {
                        if (is(f[1], r)) break k;
                    } else return null;
                    g.rates[i] = num(f[2]) orelse return null;
                } else if (is(kind, "set") and n == 4) {
                    const i = for (GRID_ATTRIBUTES, 0..) |r, k| {
                        if (is(f[1], r)) break k;
                    } else return null;
                    try g.cells.append(a, .{ .attribute = i, .x = num(f[2]) orelse return null, .y = num(f[3]) orelse return null });
                } else if (is(kind, "place") and n == 4) {
                    try g.places.append(a, try std.fmt.allocPrint(a, "  place {s} {d} {d}", .{ try atom_name(a, f[1]), num(f[2]) orelse return null, num(f[3]) orelse return null }));
                } else return null;
            } else return null;
        }
        if (edit.scene.len == 0 or (!edit.room and edit.grid == null)) return null;
        if (edit.grid) |g| if (g.width == 0 or g.height == 0 or g.cell == 0) return null;
        return edit;
    }

    /// The grid block's lines (D-201): geometry, the rates that are set, each attribute's cells
    /// as merged rectangles in a fixed order, then the `place` lines.
    fn grid_lines(a: Allocator, scene: []const u8, g: GridEdit) !std.ArrayList([]const u8) {
        var lines: std.ArrayList([]const u8) = .empty;
        try lines.append(a, try std.fmt.allocPrint(a, "grid {s} in {s}:", .{ g.name, try atom_name(a, scene) }));
        try lines.append(a, try std.fmt.allocPrint(a, "  size {d} {d}", .{ g.width, g.height }));
        try lines.append(a, try std.fmt.allocPrint(a, "  cell {d}", .{g.cell}));
        if (g.origin_x != 0 or g.origin_y != 0) try lines.append(a, try std.fmt.allocPrint(a, "  origin {d} {d}", .{ g.origin_x, g.origin_y }));
        for (RATES, g.rates) |name, v| if (v != 0) try lines.append(a, try std.fmt.allocPrint(a, "  {s} {d}", .{ name, v }));
        const count = @as(usize, g.width) * g.height;
        if (count > 4096) return error.GridTooLarge;
        const set = try a.alloc(bool, count);
        const used = try a.alloc(bool, count);
        for (GRID_ATTRIBUTES, 0..) |name, attribute| {
            @memset(set, false);
            @memset(used, false);
            for (g.cells.items) |c| if (c.attribute == attribute and c.x < g.width and c.y < g.height) {
                set[@as(usize, c.y) * g.width + c.x] = true;
            };
            for (merge_rects(g.width, g.height, set, used, a) catch return error.OutOfMemory) |r| {
                if (r.w == 1 and r.h == 1)
                    try lines.append(a, try std.fmt.allocPrint(a, "  {s} {d} {d}", .{ name, r.x, r.y }))
                else
                    try lines.append(a, try std.fmt.allocPrint(a, "  {s} {d} {d} {d} {d}", .{ name, r.x, r.y, r.w, r.h }));
            }
        }
        try lines.appendSlice(a, g.places.items);
        return lines;
    }

    /// One splice: replace lines `from` to `to`, or insert after line `from` (a blank line
    /// first when `blank`), in the script at table path `path`.
    const Edit = struct { path: []const u8, from: u32, to: u32 = 0, insert: bool, blank: bool = true, order: u8 = 0, lines: []const []const u8 };

    /// Applies `edits` and checks the project once (D-197 item 4): later lines first, so earlier
    /// line numbers still hold, and at one line in `order`. When the project does not check,
    /// every touched script is put back and the check's JSON is left in `result`; otherwise
    /// `result` names the scripts written.
    fn apply_edits(self: *Project, a: Allocator, main_path: []const u8, edits: []Edit) !bool {
        std.mem.sort(Edit, edits, {}, struct {
            fn before(_: void, x: Edit, y: Edit) bool {
                const c = std.mem.order(u8, x.path, y.path);
                if (c != .eq) return c == .lt;
                if (x.from != y.from) return x.from > y.from;
                return x.order < y.order;
            }
        }.before);
        var saved: std.ArrayList(struct { path: []const u8, bytes: []u8 }) = .empty;
        defer for (saved.items) |sv| self.allocator.free(sv.bytes);
        for (edits) |e| {
            const now = self.find(e.path) orelse {
                for (saved.items) |sv| try self.add(sv.path, sv.bytes);
                return self.refuse_room("the script is not in the project");
            };
            const seen = for (saved.items) |sv| {
                if (std.mem.eql(u8, sv.path, e.path)) break true;
            } else false;
            if (!seen) try saved.append(a, .{ .path = e.path, .bytes = try self.allocator.dupe(u8, now) });
            const spliced = if (!e.insert)
                try replace_lines(a, now, e.from, e.to, e.lines)
            else if (e.blank)
                try insert_block(a, now, e.from, e.lines)
            else
                try insert_lines(a, now, e.from, e.lines);
            try self.add(e.path, spliced.bytes);
        }
        if (!try self.check(main_path)) {
            for (saved.items) |sv| try self.add(sv.path, sv.bytes);
            return false;
        }
        self.result.clearRetainingCapacity();
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        try w.raw("{\"written\":true,\"scripts\":[");
        for (saved.items, 0..) |sv, i| {
            if (i > 0) try w.raw(",");
            try w.string(sv.path);
        }
        try w.raw("],\"script\":");
        try w.string(saved.items[0].path);
        try w.raw("}");
        return true;
    }

    /// Writes one scene's room block, grid block, or both from `request` (`RoomEdit`), P47-03,
    /// P47-12, D-200, D-201: each block is rewritten whole where it stands, or a first one goes
    /// after the scene's room block (a grid) or `scene` block, in that file's line endings.
    /// Both are checked together; when the project does not check, every touched script is put
    /// back. `result` holds `{"written":true,"script":..}` naming the last script written,
    /// `{"written":false,"refused":".."}` for a request refused before the check, or the
    /// check's JSON.
    pub fn write_room(self: *Project, main_path: []const u8, request: []const u8) !bool {
        self.result.clearRetainingCapacity();
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const edit = (try parse_room_edit(a, request)) orelse
            return self.refuse_room("the room edit is not one the Studio understands");
        const source = self.find(main_path) orelse return self.refuse_room("the project has no main script");
        const dir = parent_of(main_path);
        var reader = Reader{ .project = self, .dir = dir };
        const scenes = compiler.room_sources(a, source, reader.source()) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.check(main_path);
        };
        const scene = for (scenes) |sc| {
            if (std.mem.eql(u8, sc.name, edit.scene)) break sc;
        } else return self.refuse_room("the script declares no such scene with 'scene <Name>:'");

        var buf: [1024]u8 = undefined;
        var edits: std.ArrayList(Edit) = .empty;
        if (edit.room) {
            const target = scene.block orelse scene.declared;
            const path = try a.dupe(u8, table_script(&buf, main_path, dir, target.script));
            var lines: std.ArrayList([]const u8) = .empty;
            // A block with no lines is no block: every mark is placed by the grid.
            if (edit.lines.items.len > 0) {
                try lines.append(a, try std.fmt.allocPrint(a, "room {s}:", .{try room_name(a, scene.name)}));
                try lines.appendSlice(a, edit.lines.items);
            }
            if (scene.block) |b| {
                try edits.append(a, .{ .path = path, .from = b.line, .to = b.end_line, .insert = false, .order = 1, .lines = lines.items });
            } else if (lines.items.len > 0) {
                try edits.append(a, .{ .path = path, .from = scene.declared.end_line, .to = 0, .insert = true, .order = 1, .lines = lines.items });
            }
        }
        if (edit.grid) |g| {
            const lines = grid_lines(a, scene.name, g) catch |err| switch (err) {
                error.GridTooLarge => return self.refuse_room("a grid holds at most 4096 cells"),
                else => return err,
            };
            if (scene.grids.len > 0) {
                const b = scene.grids[0].block;
                const path = try a.dupe(u8, table_script(&buf, main_path, dir, b.script));
                try edits.append(a, .{ .path = path, .from = b.line, .to = b.end_line, .insert = false, .order = 0, .lines = lines.items });
            } else {
                // After the room block as it stands, else after the scene block; a room block
                // added in this same edit goes in at that point too, so the grid is applied
                // first and the room block lands above it.
                const after = scene.block orelse scene.declared;
                const path = try a.dupe(u8, table_script(&buf, main_path, dir, after.script));
                try edits.append(a, .{ .path = path, .from = after.end_line, .to = 0, .insert = true, .order = 0, .lines = lines.items });
            }
        }
        if (edits.items.len == 0) return self.refuse_room("the edit changes nothing");
        return self.apply_edits(a, main_path, edits.items);
    }

    /// Lists what the cast editor edits (P47-05, D-202) as JSON in `result`: scenes with their
    /// lists, display names, axes, starting values, and each routine and cue handler, every one
    /// with its script and line. A script that does not parse gets the check's JSON and false.
    pub fn cast(self: *Project, main_path: []const u8) !bool {
        self.result.clearRetainingCapacity();
        const source = self.find(main_path) orelse {
            try self.write_missing(main_path);
            return false;
        };
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const dir = parent_of(main_path);
        var reader = Reader{ .project = self, .dir = dir };
        const c = compiler.cast_sources(arena.allocator(), source, reader.source()) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.check(main_path);
        };
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        var buf: [1024]u8 = undefined;
        const at = struct {
            fn write(p: *Project, jw: *Json, b: []u8, m: []const u8, d: []const u8, l: compiler.ScriptLines) !void {
                try p.json_lines(jw, b, m, d, l);
                try jw.raw("}");
            }
        }.write;
        const list = struct {
            fn write(jw: *Json, names: []const []const u8) !void {
                try jw.raw("[");
                for (names, 0..) |n, i| {
                    if (i > 0) try jw.raw(",");
                    try jw.string(n);
                }
                try jw.raw("]");
            }
        }.write;
        try w.raw("{\"valid\":true,\"scenes\":[");
        for (c.scenes, 0..) |sc, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"name\":");
            try w.string(sc.name);
            try w.raw(",\"declared\":");
            try at(self, &w, &buf, main_path, dir, sc.declared);
            try w.raw(",\"cast\":");
            try list(&w, sc.cast);
            try w.raw(",\"props\":");
            try list(&w, sc.props);
            try w.raw(",\"marks\":");
            try list(&w, sc.marks);
            try w.raw(if (sc.room_block != null) ",\"room_block\":true}" else ",\"room_block\":false}");
        }
        try w.raw("],\"names\":[");
        for (c.names, 0..) |n, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"entity\":");
            try w.string(n.entity);
            try w.raw(",\"text\":");
            try w.string(n.text);
            try w.raw(",\"at\":");
            try at(self, &w, &buf, main_path, dir, n.at);
            try w.raw("}");
        }
        try w.raw("],\"axes\":[");
        for (c.axes, 0..) |ax, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"name\":");
            try w.string(ax.name);
            try w.raw(",\"low\":");
            try w.string(ax.low);
            try w.raw(",\"high\":");
            try w.string(ax.high);
            try w.raw(",\"at\":");
            try at(self, &w, &buf, main_path, dir, ax.at);
            try w.raw("}");
        }
        try w.raw("],\"values\":[");
        for (c.values, 0..) |v, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"axis\":");
            try w.string(v.axis);
            try w.raw(",\"character\":");
            try w.string(v.character);
            try w.raw(",\"value\":");
            try w.number(v.value);
            try w.raw(",\"at\":");
            try at(self, &w, &buf, main_path, dir, v.at);
            try w.raw("}");
        }
        try w.raw("],\"code\":[");
        for (c.code, 0..) |k, i| {
            if (i > 0) try w.raw(",");
            try w.raw(if (k.handler) "{\"handler\":true,\"name\":" else "{\"handler\":false,\"name\":");
            try w.string(k.name);
            try w.raw(",\"actor\":");
            try w.string(k.actor);
            try w.raw(",\"at\":");
            try at(self, &w, &buf, main_path, dir, k.at);
            try w.raw("}");
        }
        try w.raw("]}");
        return true;
    }

    /// Writes one cast edit (P47-05, D-202), a single tab-separated record:
    /// `add<TAB>Scene<TAB>cast|props|marks<TAB>Name` adds a list line at the end of the scene's
    /// block (and the name's room-block line at its default spot when the scene has one),
    /// `name<TAB>Thing<TAB>Text` sets a display name (an empty text removes the line),
    /// `axis<TAB>Virtue<TAB>Low<TAB>High` declares an axis or changes its poles, and
    /// `value<TAB>Axis<TAB>Character<TAB>N` sets a starting value. Each changes or adds one line
    /// of a script (two for a placed name), and is checked before it is kept.
    pub fn write_cast(self: *Project, main_path: []const u8, record: []const u8) !bool {
        self.result.clearRetainingCapacity();
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var f: [5][]const u8 = undefined;
        var n: usize = 0;
        var fields = std.mem.splitScalar(u8, std.mem.trimEnd(u8, record, "\n"), '\t');
        while (fields.next()) |field| {
            if (n == f.len) return self.refuse_room("the cast edit is not one the Studio understands");
            f[n] = field;
            n += 1;
        }
        const source = self.find(main_path) orelse return self.refuse_room("the project has no main script");
        const dir = parent_of(main_path);
        var reader = Reader{ .project = self, .dir = dir };
        const c = compiler.cast_sources(a, source, reader.source()) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.check(main_path);
        };
        var buf: [1024]u8 = undefined;
        const path_of = struct {
            fn of(al: Allocator, b: []u8, m: []const u8, d: []const u8, script: []const u8) ![]const u8 {
                return al.dupe(u8, table_script(b, m, d, script));
            }
        }.of;
        var edits: std.ArrayList(Edit) = .empty;
        const kind = if (n > 0) f[0] else "";
        if (std.mem.eql(u8, kind, "add") and n == 4) {
            const sc = for (c.scenes) |x| {
                if (std.mem.eql(u8, x.name, f[1])) break x;
            } else return self.refuse_room("the script declares no such scene with 'scene <Name>:'");
            const list = f[2];
            if (!(std.mem.eql(u8, list, "cast") or std.mem.eql(u8, list, "props") or std.mem.eql(u8, list, "marks")))
                return self.refuse_room("a name goes in a scene's cast, props, or marks");
            const name = std.mem.trim(u8, f[3], " ");
            if (name.len == 0) return self.refuse_room("the name is empty");
            const line = try a.dupe(u8, try std.fmt.allocPrint(a, "  {s}: {s}", .{ list, try room_name(a, name) }));
            try edits.append(a, .{ .path = try path_of(a, &buf, main_path, dir, sc.declared.script), .from = sc.declared.end_line, .insert = true, .blank = false, .lines = try a.dupe([]const u8, &.{line}) });
            // A scene with a room block places everything it lists (D-199 item 4), so a new
            // mark or prop gets its line there, at the spot it would have had without one.
            if (sc.room_block) |rb| if (!std.mem.eql(u8, list, "cast")) {
                const prop = std.mem.eql(u8, list, "props");
                const count = (if (prop) sc.props.len else sc.marks.len) + 1;
                const idx = count - 1;
                const world: bespoke.spatial.Point2D = if (prop)
                    .{ .x = 10 + compiler.codegen.stage_x(idx, count), .y = -6 }
                else
                    .{ .x = compiler.codegen.stage_x(idx, count), .y = 0 };
                const spot = bespoke.spatial.world_to_art(world);
                const room_line = try std.fmt.allocPrint(a, "  {s} {s} at {d} {d}", .{ if (prop) "prop" else "mark", try room_name(a, name), spot.x, spot.y });
                try edits.append(a, .{ .path = try path_of(a, &buf, main_path, dir, rb.script), .from = rb.end_line, .insert = true, .blank = false, .order = 1, .lines = try a.dupe([]const u8, &.{room_line}) });
            };
        } else if (std.mem.eql(u8, kind, "name") and n == 3) {
            const thing = f[1];
            const text = f[2];
            if (std.mem.indexOfScalar(u8, text, '"') != null) return self.refuse_room("a display name cannot hold a double quote");
            const existing = for (c.names) |x| {
                if (std.mem.eql(u8, x.entity, thing)) break x;
            } else null;
            const line = try std.fmt.allocPrint(a, "name {s}: \"{s}\"", .{ try room_name(a, thing), text });
            if (existing) |x| {
                const path = try path_of(a, &buf, main_path, dir, x.at.script);
                const lines: []const []const u8 = if (text.len == 0) &.{} else try a.dupe([]const u8, &.{line});
                try edits.append(a, .{ .path = path, .from = x.at.line, .to = x.at.line, .insert = false, .lines = lines });
            } else {
                if (text.len == 0) return self.refuse_room("the thing has no display name to remove");
                // After the block of the first scene that lists it, else at the main script's end.
                const sc = for (c.scenes) |x| {
                    if (listed(x, thing)) break x;
                } else null;
                if (sc) |x| {
                    try edits.append(a, .{ .path = try path_of(a, &buf, main_path, dir, x.declared.script), .from = x.declared.end_line, .insert = true, .blank = false, .lines = try a.dupe([]const u8, &.{line}) });
                } else try edits.append(a, .{ .path = main_path, .from = line_count(source), .insert = true, .blank = false, .lines = try a.dupe([]const u8, &.{line}) });
            }
        } else if (std.mem.eql(u8, kind, "axis") and n == 4) {
            if (!is_image_word(f[1])) return self.refuse_room("an axis is one word: a letter, then letters, digits, or underscores");
            const line = try std.fmt.allocPrint(a, "axis {s} between {s} and {s}", .{ f[1], try pole_name(a, f[2]), try pole_name(a, f[3]) });
            const existing = for (c.axes) |x| {
                if (std.mem.eql(u8, x.name, f[1])) break x;
            } else null;
            if (existing) |x| {
                // Only the `axis` line: its `drift step` lines below stay as written.
                try edits.append(a, .{ .path = try path_of(a, &buf, main_path, dir, x.at.script), .from = x.at.line, .to = x.at.line, .insert = false, .lines = try a.dupe([]const u8, &.{line}) });
            } else if (c.axes.len > 0) {
                const last = c.axes[c.axes.len - 1];
                try edits.append(a, .{ .path = try path_of(a, &buf, main_path, dir, last.at.script), .from = last.at.end_line, .insert = true, .blank = false, .lines = try a.dupe([]const u8, &.{line}) });
            } else try edits.append(a, .{ .path = main_path, .from = line_count(source), .insert = true, .lines = try a.dupe([]const u8, &.{line}) });
        } else if (std.mem.eql(u8, kind, "value") and n == 4) {
            const v = std.fmt.parseInt(i32, f[3], 10) catch return self.refuse_room("a value is a whole number from -10 to 10");
            if (v < -10 or v > 10) return self.refuse_room("a value is a whole number from -10 to 10");
            const ax = for (c.axes) |x| {
                if (std.mem.eql(u8, x.name, f[1])) break x;
            } else return self.refuse_room("the script declares no such axis");
            const line = try std.fmt.allocPrint(a, "remember {s}({s}, {d})", .{ ax.name, try atom_name(a, f[2]), v });
            const existing = for (c.values) |x| {
                if (std.mem.eql(u8, x.axis, ax.name) and std.mem.eql(u8, x.character, f[2])) break x;
            } else null;
            if (existing) |x| {
                try edits.append(a, .{ .path = try path_of(a, &buf, main_path, dir, x.at.script), .from = x.at.line, .to = x.at.line, .insert = false, .lines = try a.dupe([]const u8, &.{line}) });
            } else try edits.append(a, .{ .path = try path_of(a, &buf, main_path, dir, ax.at.script), .from = ax.at.end_line, .insert = true, .blank = false, .lines = try a.dupe([]const u8, &.{line}) });
        } else return self.refuse_room("the cast edit is not one the Studio understands");
        return self.apply_edits(a, main_path, edits.items);
    }

    /// Lists dilemmas, decisions, and red lines for the dilemma editor (P47-13, D-203), as JSON
    /// in `result`: each dilemma with its preview data and its block's lines as written (the
    /// `dilemma` line left out, indentation trimmed), each decision's actor and options, and
    /// each `red lines` line. A script that does not parse gets the check's JSON and false.
    pub fn dilemmas(self: *Project, main_path: []const u8) !bool {
        self.result.clearRetainingCapacity();
        const source = self.find(main_path) orelse {
            try self.write_missing(main_path);
            return false;
        };
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const dir = parent_of(main_path);
        var reader = Reader{ .project = self, .dir = dir };
        const d = compiler.dilemma_sources(arena.allocator(), source, reader.source()) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.check(main_path);
        };
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        var buf: [1024]u8 = undefined;
        const strings = struct {
            fn write(jw: *Json, names: []const []const u8) !void {
                try jw.raw("[");
                for (names, 0..) |n, i| {
                    if (i > 0) try jw.raw(",");
                    try jw.string(n);
                }
                try jw.raw("]");
            }
        }.write;
        try w.raw("{\"valid\":true,\"dilemmas\":[");
        for (d.dilemmas, 0..) |x, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"name\":");
            try w.string(x.name);
            inline for (.{ "actor", "axis", "counter" }) |f| {
                try w.raw(",\"" ++ f ++ "\":");
                try w.string(@field(x, f));
            }
            try w.raw(",\"strong\":");
            try w.number(x.strong);
            try w.raw(",\"moderate\":");
            try w.number(x.moderate);
            try w.raw(",\"leans\":[");
            for (x.leans, 0..) |l, j| {
                if (j > 0) try w.raw(",");
                try w.raw("{\"points\":");
                try w.number(l.points);
                try w.raw(",\"toward\":");
                try w.string(l.toward);
                try w.raw(if (l.unless) ",\"unless\":true}" else ",\"unless\":false}");
            }
            try w.raw("],\"tiers\":[");
            for (x.tiers, 0..) |t, j| {
                if (j > 0) try w.raw(",");
                try w.raw("{\"text\":");
                try w.string(t.text);
                try w.raw(",\"action\":");
                try w.string(t.action);
                try w.raw("}");
            }
            try w.raw("],\"block\":");
            try self.json_lines(&w, &buf, main_path, dir, x.block);
            const path = table_script(&buf, main_path, dir, x.block.script);
            const text = self.find(path) orelse "";
            try w.raw(if (has_comment(text, x.block.line, x.block.end_line)) ",\"comments\":true}" else ",\"comments\":false}");
            try w.raw(",\"lines\":[");
            var first = true;
            var ln = x.block.line + 1;
            while (ln <= x.block.end_line) : (ln += 1) {
                const body = std.mem.trim(u8, text_of_line(text, ln), " \t\r");
                if (body.len == 0) continue;
                if (!first) try w.raw(",");
                first = false;
                try w.string(body);
            }
            try w.raw("]}");
        }
        try w.raw("],\"decisions\":[");
        for (d.decisions, 0..) |x, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"name\":");
            try w.string(x.name);
            try w.raw(",\"actor\":");
            try w.string(x.actor);
            try w.raw(",\"options\":");
            try strings(&w, x.options);
            try w.raw("}");
        }
        try w.raw("],\"red_lines\":[");
        for (d.red_lines, 0..) |x, i| {
            if (i > 0) try w.raw(",");
            try w.raw("{\"actor\":");
            try w.string(x.actor);
            try w.raw(",\"options\":");
            try strings(&w, x.options);
            try w.raw("}");
        }
        try w.raw("]}");
        return true;
    }

    /// Writes a dilemma block or a `red lines` line (P47-13, D-203). `dilemma<TAB>Name` then one
    /// `line<TAB>text` record per line of the block rewrites the block whole where it stands, or
    /// adds it after the last dilemma, else the last axis, else at the main script's end;
    /// `redlines<TAB>Character<TAB>Option...` rewrites that character's line, adds one after the
    /// last decision, or removes it when no option is given. Checked before it is kept.
    pub fn write_dilemma(self: *Project, main_path: []const u8, request: []const u8) !bool {
        self.result.clearRetainingCapacity();
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const source = self.find(main_path) orelse return self.refuse_room("the project has no main script");
        const dir = parent_of(main_path);
        var reader = Reader{ .project = self, .dir = dir };
        const d = compiler.dilemma_sources(a, source, reader.source()) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.check(main_path);
        };
        var buf: [1024]u8 = undefined;
        var records = std.mem.splitScalar(u8, request, '\n');
        const head = records.next() orelse "";
        var head_fields = std.mem.splitScalar(u8, head, '\t');
        const kind = head_fields.next() orelse "";
        var edits: std.ArrayList(Edit) = .empty;
        if (std.mem.eql(u8, kind, "dilemma")) {
            const name = head_fields.next() orelse "";
            if (!is_image_word(name)) return self.refuse_room("a dilemma's name is one word: a letter, then letters, digits, or underscores");
            var lines: std.ArrayList([]const u8) = .empty;
            try lines.append(a, try std.fmt.allocPrint(a, "dilemma {s}:", .{name}));
            while (records.next()) |record| {
                if (record.len == 0) continue;
                if (!std.mem.startsWith(u8, record, "line\t")) return self.refuse_room("the dilemma edit is not one the Studio understands");
                const text = std.mem.trim(u8, record["line\t".len..], " ");
                if (text.len == 0) continue;
                if (std.mem.indexOfAny(u8, text, "\t\r") != null) return self.refuse_room("a line cannot hold a tab");
                try lines.append(a, try std.fmt.allocPrint(a, "  {s}", .{text}));
            }
            if (lines.items.len == 1) return self.refuse_room("a dilemma needs its lines");
            const existing = for (d.dilemmas) |x| {
                if (std.mem.eql(u8, x.name, name)) break x;
            } else null;
            if (existing) |x| {
                try edits.append(a, .{ .path = try a.dupe(u8, table_script(&buf, main_path, dir, x.block.script)), .from = x.block.line, .to = x.block.end_line, .insert = false, .lines = lines.items });
            } else if (d.dilemmas.len > 0) {
                const last = d.dilemmas[d.dilemmas.len - 1].block;
                try edits.append(a, .{ .path = try a.dupe(u8, table_script(&buf, main_path, dir, last.script)), .from = last.end_line, .insert = true, .lines = lines.items });
            } else {
                const c = compiler.cast_sources(a, source, reader.source()) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    return self.check(main_path);
                };
                if (c.axes.len > 0) {
                    const last = c.axes[c.axes.len - 1].at;
                    try edits.append(a, .{ .path = try a.dupe(u8, table_script(&buf, main_path, dir, last.script)), .from = last.end_line, .insert = true, .lines = lines.items });
                } else try edits.append(a, .{ .path = main_path, .from = line_count(source), .insert = true, .lines = lines.items });
            }
        } else if (std.mem.eql(u8, kind, "redlines")) {
            const actor = head_fields.next() orelse "";
            if (actor.len == 0) return self.refuse_room("red lines need a character");
            var options: std.ArrayList(u8) = .empty;
            var count: usize = 0;
            while (head_fields.next()) |opt| {
                if (opt.len == 0) continue;
                if (count > 0) try options.appendSlice(a, ", ");
                try options.appendSlice(a, try atom_name(a, opt));
                count += 1;
            }
            const line = try std.fmt.allocPrint(a, "red lines {s}: {s}", .{ try room_name(a, actor), options.items });
            const existing = for (d.red_lines) |x| {
                if (std.mem.eql(u8, x.actor, actor)) break x;
            } else null;
            const lines: []const []const u8 = if (count == 0) &.{} else try a.dupe([]const u8, &.{line});
            if (existing) |x| {
                try edits.append(a, .{ .path = try a.dupe(u8, table_script(&buf, main_path, dir, x.at.script)), .from = x.at.line, .to = x.at.line, .insert = false, .lines = lines });
            } else {
                if (count == 0) return self.refuse_room("the character has no red lines to remove");
                if (d.decisions.len == 0) return self.refuse_room("red lines name decision options, and the script declares no decision");
                const last = d.decisions[d.decisions.len - 1].block;
                try edits.append(a, .{ .path = try a.dupe(u8, table_script(&buf, main_path, dir, last.script)), .from = last.end_line, .insert = true, .lines = lines });
            }
        } else return self.refuse_room("the dilemma edit is not one the Studio understands");
        return self.apply_edits(a, main_path, edits.items);
    }

    /// The tier a dilemma lands in (P47-13, D-203) for the actor's values on its two axes and the
    /// `leans` lines that count (bit i of `counting` for line i), with the engine's own
    /// `dilemma.tier_in`, as `{"delta":N,"tier":T,"text":..,"action":..}` in `result`.
    pub fn preview_tier(self: *Project, main_path: []const u8, name: []const u8, axis_value: i32, counter_value: i32, counting: u32) !bool {
        self.result.clearRetainingCapacity();
        const source = self.find(main_path) orelse return self.refuse_room("the project has no main script");
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var reader = Reader{ .project = self, .dir = parent_of(main_path) };
        const d = compiler.dilemma_sources(arena.allocator(), source, reader.source()) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.check(main_path);
        };
        const x = for (d.dilemmas) |y| {
            if (std.mem.eql(u8, y.name, name)) break y;
        } else return self.refuse_room("the script declares no such dilemma");
        var delta: i32 = axis_value - counter_value;
        for (x.leans, 0..) |l, i| {
            if (i >= 32 or counting & (@as(u32, 1) << @intCast(i)) == 0) continue;
            const p: i32 = @intCast(l.points);
            delta += if (std.mem.eql(u8, l.toward, x.axis)) p else -p;
        }
        const tier = bespoke.dilemma.tier_in(delta, x.strong, x.moderate);
        const t = x.tiers[@intFromEnum(tier)];
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        try w.raw("{\"delta\":");
        try w.number(delta);
        try w.raw(",\"tier\":");
        try w.number(@intFromEnum(tier));
        try w.raw(",\"text\":");
        try w.string(t.text);
        try w.raw(",\"action\":");
        try w.string(t.action);
        try w.raw("}");
        return true;
    }

    pub fn refuse_room(self: *Project, why: []const u8) !bool {
        self.result.clearRetainingCapacity();
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        try w.raw("{\"written\":false,\"refused\":");
        try w.string(why);
        try w.raw("}");
        return false;
    }

    fn refuse(self: *Project, why: []const u8) !bool {
        self.result.clearRetainingCapacity();
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        try w.raw("{\"added\":false,\"refused\":");
        try w.string(why);
        try w.raw("}");
        return false;
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

/// The table path of a script a diagnostic or listing names: the main script for an empty
/// name, else the name joined to the main script's folder.
fn table_script(buf: []u8, main_path: []const u8, dir: []const u8, script: []const u8) []const u8 {
    if (script.len == 0) return main_path;
    return join_clean(buf, dir, script) orelse main_path;
}

/// A name as a room line must write it (D-199): bare when the lexer reads it back as the same
/// words with no `to` or `at` among them, quoted otherwise. A name holding a double quote
/// cannot be written at all; the scene could not have declared one.
fn room_name(a: Allocator, name: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, name, '"') != null) return error.UnwritableName;
    var bare = name.len > 0;
    var words = std.mem.splitScalar(u8, name, ' ');
    var first = true;
    while (words.next()) |word| {
        if (word.len == 0 or std.mem.eql(u8, word, "to") or std.mem.eql(u8, word, "at")) bare = false;
        var lex = compiler.lexer.Lexer.init(a, word);
        const tok = lex.next() catch {
            bare = false;
            break;
        };
        const ok = tok.tag == .identifier or (!first and tok.tag == .number);
        if (!ok or tok.slice.len != word.len) bare = false;
        first = false;
    }
    if (bare) return name;
    return std.fmt.allocPrint(a, "\"{s}\"", .{name});
}

/// A name as a grid line takes it (`take_atom`): one word bare, anything else quoted.
fn atom_name(a: Allocator, name: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, name, '"') != null) return error.UnwritableName;
    if (is_image_word(name) and !std.mem.eql(u8, name, "to") and !std.mem.eql(u8, name, "at")) return name;
    return std.fmt.allocPrint(a, "\"{s}\"", .{name});
}

const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

/// The rectangles covering every `set` cell (D-201 item 2): from each unused set cell in row
/// order, as wide as the row allows, then as tall as full rows of that width allow.
fn merge_rects(width: u32, height: u32, set: []const bool, used: []bool, a: Allocator) ![]Rect {
    var out: std.ArrayList(Rect) = .empty;
    for (0..height) |yy| for (0..width) |xx| {
        const at = yy * width + xx;
        if (!set[at] or used[at]) continue;
        var w: usize = 1;
        while (xx + w < width and set[at + w] and !used[at + w]) w += 1;
        var h: usize = 1;
        grow: while (yy + h < height) : (h += 1) {
            for (0..w) |k| {
                const c = (yy + h) * width + xx + k;
                if (!set[c] or used[c]) break :grow;
            }
        }
        for (0..h) |r| for (0..w) |k| {
            used[(yy + r) * width + xx + k] = true;
        };
        try out.append(a, .{ .x = @intCast(xx), .y = @intCast(yy), .w = @intCast(w), .h = @intCast(h) });
    };
    return out.items;
}

/// Line `n` of `text`, without its line ending.
fn text_of_line(text: []const u8, n: u32) []const u8 {
    const start = line_start(text, n);
    const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
    return std.mem.trimEnd(u8, text[start..end], "\r");
}

fn listed(sc: compiler.CastScene, thing: []const u8) bool {
    for ([_][]const []const u8{ sc.cast, sc.props, sc.marks }) |names| {
        for (names) |name| if (std.mem.eql(u8, name, thing)) return true;
    }
    return false;
}

fn line_count(text: []const u8) u32 {
    if (text.len == 0) return 0;
    const n: u32 = @intCast(std.mem.count(u8, text, "\n"));
    return if (text[text.len - 1] == '\n') n else n + 1;
}

/// A pole as an `axis` line takes it: bare when it is one word the lexer reads back, quoted
/// otherwise, so a pole of several words never runs into `and`.
fn pole_name(a: Allocator, name: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, name, '"') != null) return error.UnwritableName;
    if (std.mem.indexOfScalar(u8, name, ' ') == null) {
        const bare = try room_name(a, name);
        if (bare.ptr == name.ptr) return name;
    }
    return std.fmt.allocPrint(a, "\"{s}\"", .{name});
}

/// `text` with `lines` inserted after line `after`, with no blank line, in the file's own line
/// ending; a file that ends without a newline still does (D-202 item 5).
fn insert_lines(a: Allocator, text: []const u8, after: u32, lines: []const []const u8) !Spliced {
    const eol = line_ending(text);
    const at = line_start(text, after + 1);
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, text[0..at]);
    const open_end = at == text.len and text.len > 0 and text[text.len - 1] != '\n';
    if (open_end) try out.appendSlice(a, eol);
    for (lines, 0..) |l, i| {
        try out.appendSlice(a, l);
        if (!open_end or i + 1 < lines.len) try out.appendSlice(a, eol);
    }
    try out.appendSlice(a, text[at..]);
    return .{ .bytes = out.items, .line = after + 1 };
}

/// The file's line ending: CRLF when its first line ends so, else LF (D-197 item 1).
fn line_ending(text: []const u8) []const u8 {
    const nl = std.mem.indexOfScalar(u8, text, '\n') orelse return "\n";
    return if (nl > 0 and text[nl - 1] == '\r') "\r\n" else "\n";
}

/// Byte offset where 1-based line `n` starts; `text.len` past the last line.
fn line_start(text: []const u8, n: u32) usize {
    if (n <= 1) return 0;
    var count: u32 = 1;
    for (text, 0..) |c, i| if (c == '\n') {
        count += 1;
        if (count == n) return i + 1;
    };
    return text.len;
}

const Spliced = struct { bytes: []u8, line: u32 };

/// `text` with lines `from` to `to` replaced by `lines`, in the file's own line ending; a last
/// line without a newline stays without one.
fn replace_lines(a: Allocator, text: []const u8, from: u32, to: u32, lines: []const []const u8) !Spliced {
    const eol = line_ending(text);
    const start = line_start(text, from);
    const end = line_start(text, to + 1);
    const open_end = end == text.len and text.len > 0 and text[text.len - 1] != '\n';
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, text[0..start]);
    for (lines, 0..) |l, i| {
        try out.appendSlice(a, l);
        if (i + 1 < lines.len or !open_end) try out.appendSlice(a, eol);
    }
    try out.appendSlice(a, text[end..]);
    return .{ .bytes = out.items, .line = from };
}

/// `text` with a blank line and `lines` inserted after line `after`, in the file's own line
/// ending (D-200 item 1).
fn insert_block(a: Allocator, text: []const u8, after: u32, lines: []const []const u8) !Spliced {
    const eol = line_ending(text);
    const at = line_start(text, after + 1);
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, text[0..at]);
    if (at == text.len and text.len > 0 and text[text.len - 1] != '\n') try out.appendSlice(a, eol);
    try out.appendSlice(a, eol);
    for (lines) |l| {
        try out.appendSlice(a, l);
        try out.appendSlice(a, eol);
    }
    // A blank line after the block too, unless the next line is already blank.
    const rest = text[at..];
    if (rest.len > 0 and rest[0] != '\n' and !std.mem.startsWith(u8, rest, "\r\n")) try out.appendSlice(a, eol);
    try out.appendSlice(a, rest);
    return .{ .bytes = out.items, .line = after + 2 };
}

/// Whether lines `from` to `to` of `text` hold a `#` comment outside a quoted string.
fn has_comment(text: []const u8, from: u32, to: u32) bool {
    const body = text[line_start(text, from)..line_start(text, to + 1)];
    var quoted = false;
    for (body) |c| switch (c) {
        '"' => quoted = !quoted,
        '\n' => quoted = false,
        '#' => if (!quoted) return true,
        else => {},
    };
    return false;
}

fn is_image_word(name: []const u8) bool {
    if (name.len == 0 or name.len > bespoke.image.MAX_NAME or !std.ascii.isAlphabetic(name[0])) return false;
    for (name) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    return true;
}

/// `text` with `line` inserted after its line `after` (1-based), or at its end when `after`
/// is 0 or past the end. Every other byte stays: the new line takes the file's own line
/// ending (CRLF when its first line ends so), a byte-order mark stays first, and a file that
/// does not end with a newline still does not (D-197 item 1). Returns the new text and the
/// new line's number.
fn insert_line(allocator: Allocator, text: []const u8, after: u32, line: []const u8) !struct { bytes: []u8, line: u32 } {
    const first_nl = std.mem.indexOfScalar(u8, text, '\n');
    const eol: []const u8 = if (first_nl) |i| (if (i > 0 and text[i - 1] == '\r') "\r\n" else "\n") else "\n";
    // Byte offset where line `after + 1` starts.
    var at: ?usize = null;
    var count: u32 = 1;
    if (after > 0) {
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            if (text[i] != '\n') continue;
            if (count == after) {
                at = i + 1;
                break;
            }
            count += 1;
        }
    }
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    if (at) |pos| {
        try out.appendSlice(allocator, text[0..pos]);
        try out.appendSlice(allocator, line);
        try out.appendSlice(allocator, eol);
        try out.appendSlice(allocator, text[pos..]);
        return .{ .bytes = try out.toOwnedSlice(allocator), .line = after + 1 };
    }
    // At the end: after the last newline, or after a last line that has none.
    try out.appendSlice(allocator, text);
    const ends_open = text.len > 0 and text[text.len - 1] != '\n';
    if (ends_open) try out.appendSlice(allocator, eol);
    try out.appendSlice(allocator, line);
    if (!ends_open) try out.appendSlice(allocator, eol);
    const lines: u32 = @intCast(std.mem.count(u8, out.items, "\n") + @intFromBool(ends_open));
    return .{ .bytes = try out.toOwnedSlice(allocator), .line = lines };
}

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

test {
    _ = @import("png_write.zig");
}

test "the art listing names each PNG by its table path, and an edit round-trips through it" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    // A 2x1 sheet written by the Studio's own encoder, then named by a script in a subfolder.
    try p.encode(2, 1, &.{ 200, 10, 10, 255, 0, 0, 0, 0 });
    const sheet = try std.testing.allocator.dupe(u8, p.blob.items);
    defer std.testing.allocator.free(sheet);
    try p.add("game/art/lamp.png", sheet);
    try p.add("game/main.bespoke", "scene Room:\n  props: Lantern\n  marks: Door\n\ninclude \"art.bespoke\"\n");
    try p.add("game/art.bespoke", "image Lamp from \"art/lamp.png\" frames 1x1\n\nsprite Lantern: Lamp\n  idle: 0 for 10, 1 for 20\n");
    try std.testing.expect(try p.art("game/main.bespoke"));
    try std.testing.expect(result_has(&p, "\"file\":\"game/art/lamp.png\""));
    try std.testing.expect(result_has(&p, "\"script\":\"game/art.bespoke\""));
    try std.testing.expect(result_has(&p, "\"line\":1"));
    try std.testing.expect(result_has(&p, "\"frame_width\":1"));
    try std.testing.expect(result_has(&p, "\"anim\":\"idle\",\"steps\":[[0,10],[1,20]]"));
    try std.testing.expect(result_has(&p, "\"palette\":[]"));

    // The editor reads the pixels the compiler reads, paints one, and the project still builds.
    try std.testing.expect(try p.pixels("game/art/lamp.png"));
    try std.testing.expectEqual(@as(u32, 2), p.blob_width);
    var edited = try std.testing.allocator.dupe(u8, p.blob.items);
    defer std.testing.allocator.free(edited);
    edited[4..8].* = .{ 1, 2, 3, 255 };
    try p.encode(2, 1, edited);
    const written = try std.testing.allocator.dupe(u8, p.blob.items);
    defer std.testing.allocator.free(written);
    try p.add("game/art/lamp.png", written);
    try std.testing.expect(try p.build("game/main.bespoke"));
    try std.testing.expect(try p.pixels("game/art/lamp.png"));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 255 }, p.blob.items[4..8]);
}

test "a script that does not parse lists no art and reports the check" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    try p.add("main.bespoke", "scene Yard:\n  cast: Walker\n\nroutine Stroll(Walker):\n  walk Walker to\n");
    try std.testing.expect(!try p.art("main.bespoke"));
    try std.testing.expect(result_has(&p, "\"valid\":false"));
    try std.testing.expect(!try p.pixels("nope.png"));
}

test "a new image line goes after the script's last image, in the file's own line endings" {
    const a = std.testing.allocator;
    const r1 = try insert_line(a, "\xef\xbb\xbfone\r\ntwo\r\nthree\r\n", 2, "NEW");
    defer a.free(r1.bytes);
    try std.testing.expectEqualStrings("\xef\xbb\xbfone\r\ntwo\r\nNEW\r\nthree\r\n", r1.bytes);
    try std.testing.expectEqual(@as(u32, 3), r1.line);
    const r2 = try insert_line(a, "one\ntwo", 0, "NEW");
    defer a.free(r2.bytes);
    try std.testing.expectEqualStrings("one\ntwo\nNEW", r2.bytes);
    try std.testing.expectEqual(@as(u32, 3), r2.line);
    const r3 = try insert_line(a, "one\n", 0, "NEW");
    defer a.free(r3.bytes);
    try std.testing.expectEqualStrings("one\nNEW\n", r3.bytes);
    try std.testing.expectEqual(@as(u32, 2), r3.line);
}

test "add_image declares a new sheet after the last image and checks the project" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    try p.encode(2, 1, &.{ 200, 10, 10, 255, 0, 0, 0, 0 });
    const lamp = try std.testing.allocator.dupe(u8, p.blob.items);
    defer std.testing.allocator.free(lamp);
    try p.add("g/art/lamp.png", lamp);
    try p.add("g/main.bespoke", "scene Room:\n  props: Lantern\n  marks: Door\n\ninclude \"art.bespoke\"\n");
    const art_before = "image Lamp from \"art/lamp.png\"\n\nsprite Lantern: Lamp\n";
    try p.add("g/art.bespoke", art_before);
    const zeros: [32]u8 = @splat(0);
    try p.encode(4, 2, &zeros);
    const blank = try std.testing.allocator.dupe(u8, p.blob.items);
    defer std.testing.allocator.free(blank);

    try std.testing.expect(try p.add_image("g/main.bespoke", .{ .script = "g/art.bespoke", .name = "Door", .file = "art/door.png", .frame_width = 2, .frame_height = 2, .png = blank }));
    try std.testing.expect(result_has(&p, "\"line\":2"));
    try std.testing.expectEqualStrings("image Lamp from \"art/lamp.png\"\nimage Door from \"art/door.png\" frames 2x2\n\nsprite Lantern: Lamp\n", p.find("g/art.bespoke").?);
    try std.testing.expectEqualSlices(u8, blank, p.find("g/art/door.png").?);

    // Refused before the check: a taken name, a taken file, an outside path.
    try std.testing.expect(!try p.add_image("g/main.bespoke", .{ .script = "g/art.bespoke", .name = "Door", .file = "art/x.png", .png = blank }));
    try std.testing.expect(result_has(&p, "already declares"));
    try std.testing.expect(!try p.add_image("g/main.bespoke", .{ .script = "g/art.bespoke", .name = "Gate", .file = "art/door.png", .png = blank }));
    try std.testing.expect(result_has(&p, "already in the project"));
    try std.testing.expect(!try p.add_image("g/main.bespoke", .{ .script = "g/art.bespoke", .name = "Gate", .file = "../gate.png", .png = blank }));

    // Refused by the compiler: frames that do not tile. Both changes are undone.
    const script_now = try std.testing.allocator.dupe(u8, p.find("g/art.bespoke").?);
    defer std.testing.allocator.free(script_now);
    try std.testing.expect(!try p.add_image("g/main.bespoke", .{ .script = "g/art.bespoke", .name = "Gate", .file = "art/gate.png", .frame_width = 3, .frame_height = 2, .png = blank }));
    try std.testing.expect(result_has(&p, "\"valid\":false"));
    try std.testing.expect(result_has(&p, "do not tile"));
    try std.testing.expectEqualStrings(script_now, p.find("g/art.bespoke").?);
    try std.testing.expect(p.find("g/art/gate.png") == null);
}

test "an import the compiler would refuse adds nothing" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    try p.add("main.bespoke", "scene Room:\n  marks: Door\n\npalette:\n  \".\" transparent\n  \"b\" 176 128 56\n");
    try p.encode(1, 1, &.{ 1, 2, 3, 255 });
    const off = try std.testing.allocator.dupe(u8, p.blob.items);
    defer std.testing.allocator.free(off);
    try std.testing.expect(!try p.add_image("main.bespoke", .{ .script = "main.bespoke", .name = "Odd", .file = "art/odd.png", .png = off }));
    try std.testing.expect(result_has(&p, "palette"));
    try std.testing.expect(result_has(&p, "(0, 0)"));
    try std.testing.expect(p.find("art/odd.png") == null);
    try std.testing.expect(std.mem.indexOf(u8, p.find("main.bespoke").?, "Odd") == null);
}

test "the room editor writes a first room block after its scene, then rewrites it in place" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    const before = "scene Yard:\r\n  cast: Hero\r\n  marks: Gate, Well\r\n\r\nscene Hall:\r\n  marks: Door\r\n\r\nroutine Stroll(Hero):\r\n  walk Hero to Well\r\n";
    try p.add("main.bespoke", before);
    try std.testing.expect(try p.rooms("main.bespoke"));
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, p.result.items, .{});
    parsed.deinit();
    try std.testing.expect(result_has(&p, "\"name\":\"Yard\""));
    try std.testing.expect(result_has(&p, "\"block\":null"));
    try std.testing.expect(result_has(&p, "\"placed\":false"));

    const first = "scene\tYard\nmark\tGate\t40\t120\nmark\tWell\t200\t132\nwalkway\tGate\tWell\nexit\tWell\tHall\tDoor\n";
    try std.testing.expect(try p.write_room("main.bespoke", first));
    try std.testing.expectEqualStrings("scene Yard:\r\n  cast: Hero\r\n  marks: Gate, Well\r\n\r\nroom Yard:\r\n  mark Gate at 40 120\r\n  mark Well at 200 132\r\n  walkway Gate to Well\r\n  exit Well to Hall at Door\r\n\r\nscene Hall:\r\n  marks: Door\r\n\r\nroutine Stroll(Hero):\r\n  walk Hero to Well\r\n", p.find("main.bespoke").?);

    // A second edit replaces the block where it stands and nothing else.
    const second = "scene\tYard\nmark\tGate\t41\t121\nmark\tWell\t200\t132\n";
    try std.testing.expect(try p.write_room("main.bespoke", second));
    try std.testing.expectEqualStrings("scene Yard:\r\n  cast: Hero\r\n  marks: Gate, Well\r\n\r\nroom Yard:\r\n  mark Gate at 41 121\r\n  mark Well at 200 132\r\n\r\nscene Hall:\r\n  marks: Door\r\n\r\nroutine Stroll(Hero):\r\n  walk Hero to Well\r\n", p.find("main.bespoke").?);
    try std.testing.expect(try p.rooms("main.bespoke"));
    const again = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, p.result.items, .{});
    again.deinit();
    try std.testing.expect(result_has(&p, "\"comments\":false"));
}

test "a room edit the compiler refuses puts the script back" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    const before = "scene Yard:\n  marks: Gate, Well\n";
    try p.add("main.bespoke", before);
    // Well is not placed.
    try std.testing.expect(!try p.write_room("main.bespoke", "scene\tYard\nmark\tGate\t1\t1\n"));
    try std.testing.expect(result_has(&p, "does not place mark 'Well'"));
    try std.testing.expectEqualStrings(before, p.find("main.bespoke").?);
    try std.testing.expect(!try p.write_room("main.bespoke", "scene\tCellar\nroom\n"));
    try std.testing.expect(result_has(&p, "no such scene"));
    try std.testing.expect(!try p.write_room("main.bespoke", "scene\tYard\nmark\tGate\tx\t1\n"));
    try std.testing.expect(result_has(&p, "not one the Studio understands"));
}

test "room names are written bare when the lexer reads them back, quoted otherwise" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("Old Gate", try room_name(a, "Old Gate"));
    try std.testing.expectEqualStrings("\"Way to Town\"", try room_name(a, "Way to Town"));
    try std.testing.expectEqualStrings("\"Keeper's Lodge\"", try room_name(a, "Keeper's Lodge"));
    try std.testing.expect(has_comment("a\n  # note\nb\n", 1, 3));
    try std.testing.expect(!has_comment("a \"#1\"\nb\n", 1, 2));
}

test "the grid editor writes merged rectangles and places, beside the room block, checked together" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    const before = "scene Yard:\n  marks: Gate, Well\n\nroom Yard:\n  mark Gate at 40 120\n  mark Well at 200 132\n\nroutine Idle(Gate):\n  wait 1 ticks\n";
    try p.add("main.bespoke", before);
    // Moving Well onto the grid takes it out of the room block in the same edit.
    const edit = "scene\tYard\nroom\nmark\tGate\t40\t120\ngrid\tFloor\nsize\t4\t3\ncell\t10\norigin\t-10\t-20\nrate\tburn\t6\n" ++
        "set\tflammable\t0\t0\nset\tflammable\t1\t0\nset\tflammable\t0\t1\nset\tflammable\t1\t1\nset\tblocking\t3\t2\nplace\tWell\t2\t1\n";
    try std.testing.expect(try p.write_room("main.bespoke", edit));
    try std.testing.expectEqualStrings("scene Yard:\n  marks: Gate, Well\n\nroom Yard:\n  mark Gate at 40 120\n\ngrid Floor in Yard:\n  size 4 3\n  cell 10\n  origin -10 -20\n  burn 6\n  flammable 0 0 2 2\n  blocking 3 2\n  place Well 2 1\n\nroutine Idle(Gate):\n  wait 1 ticks\n", p.find("main.bespoke").?);
    try std.testing.expect(try p.rooms("main.bespoke"));
    try std.testing.expect(result_has(&p, "\"by_grid\":true"));
    try std.testing.expect(result_has(&p, "\"places\":[{\"mark\":\"Well\",\"x\":2,\"y\":1}]"));
    const grid_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, p.result.items, .{});
    grid_json.deinit();

    // Rewritten in place; a mark in both the room block and the grid is refused, and put back.
    const now = try std.testing.allocator.dupe(u8, p.find("main.bespoke").?);
    defer std.testing.allocator.free(now);
    try std.testing.expect(!try p.write_room("main.bespoke", "scene\tYard\nroom\nmark\tGate\t40\t120\nmark\tWell\t1\t1\n"));
    try std.testing.expect(result_has(&p, "placed twice"));
    try std.testing.expectEqualStrings(now, p.find("main.bespoke").?);
}

test "a first room and grid block in one edit land in order after the scene" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    try p.add("main.bespoke", "scene Yard:\n  marks: Gate\n");
    try std.testing.expect(try p.write_room("main.bespoke", "scene\tYard\nroom\nmark\tGate\t40\t120\ngrid\tFloor\nsize\t2\t2\ncell\t10\n"));
    try std.testing.expectEqualStrings("scene Yard:\n  marks: Gate\n\nroom Yard:\n  mark Gate at 40 120\n\ngrid Floor in Yard:\n  size 2 2\n  cell 10\n", p.find("main.bespoke").?);
}

test "the cast editor adds a name, sets a display name, an axis, and a starting value as single lines" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    const before = "scene Court:\r\n  cast: Valerius\r\n  marks: Bench\r\n\r\nroom Court:\r\n  mark Bench at 100 120\r\n\r\naxis Mercy between Vengeance and \"Condoning Harm\"\r\n  drift step 4\r\nremember Mercy(Valerius, -3)\r\n\r\nroutine Sit(Valerius):\r\n  wait 1 ticks\r\n";
    try p.add("main.bespoke", before);
    try std.testing.expect(try p.cast("main.bespoke"));
    const cast_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, p.result.items, .{});
    cast_json.deinit();
    try std.testing.expect(result_has(&p, "\"room_block\":true"));

    // A mark in a scene with a room block: the list line and its room line, in one edit.
    try std.testing.expect(try p.write_cast("main.bespoke", "add\tCourt\tmarks\tDock"));
    try std.testing.expect(try p.write_cast("main.bespoke", "value\tMercy\tValerius\t5"));
    try std.testing.expect(try p.write_cast("main.bespoke", "name\tValerius\tJudge Valerius"));
    try std.testing.expect(try p.write_cast("main.bespoke", "axis\tJustice\tCruelty\tLeniency"));
    try std.testing.expect(try p.write_cast("main.bespoke", "value\tJustice\tValerius\t8"));
    try std.testing.expectEqualStrings("scene Court:\r\n  cast: Valerius\r\n  marks: Bench\r\n  marks: Dock\r\nname Valerius: \"Judge Valerius\"\r\n\r\nroom Court:\r\n  mark Bench at 100 120\r\n  mark Dock at 159 94\r\n\r\naxis Mercy between Vengeance and \"Condoning Harm\"\r\n  drift step 4\r\naxis Justice between Cruelty and Leniency\r\nremember Justice(Valerius, 8)\r\nremember Mercy(Valerius, 5)\r\n\r\nroutine Sit(Valerius):\r\n  wait 1 ticks\r\n", p.find("main.bespoke").?);

    // Refusals leave the script alone.
    const now = try std.testing.allocator.dupe(u8, p.find("main.bespoke").?);
    defer std.testing.allocator.free(now);
    try std.testing.expect(!try p.write_cast("main.bespoke", "value\tMercy\tValerius\t11"));
    try std.testing.expect(!try p.write_cast("main.bespoke", "value\tPride\tValerius\t1"));
    try std.testing.expect(!try p.write_cast("main.bespoke", "add\tCourt\tmarks\tBench"));
    try std.testing.expectEqualStrings(now, p.find("main.bespoke").?);
}

test "the dilemma editor writes a block and red lines, and previews tiers with the engine's arithmetic" {
    var p = Project.init(std.testing.allocator);
    defer p.deinit();
    const before =
        \\scene Court:
        \\  cast: Valerius, Thief
        \\
        \\relation Accused(who)
        \\relation Criminal(who)
        \\axis Justice between Cruelty and Leniency
        \\axis Mercy between Vengeance and "Condoning Harm"
        \\remember Justice(Valerius, 4)
        \\
        \\decision Sentence:
        \\  actor Valerius
        \\  fires Sentenced
        \\  requires Accused(Thief)
        \\  option Execute:
        \\    picks 1 when Criminal(Thief)
        \\  option Pardon:
        \\    picks 1 when Accused(Thief)
        \\
    ;
    try p.add("main.bespoke", before);
    const block = "dilemma\tStolenBread\nline\tactor Valerius\nline\tfires Judged\nline\trequires Accused(Thief)\nline\tweighs Justice against Mercy\n" ++
        "line\tleans 3 toward Justice when Criminal(Thief)\nline\tstrong Justice: \"The law is the law.\" -> Hang\nline\tmoderate Justice: \"A night in the cells.\" -> Jail\n" ++
        "line\tneutral: \"Show me why.\" -> Wait\nline\tmoderate Mercy: \"Pay for the loaf.\" -> Fine\nline\tstrong Mercy: \"Let him go.\" -> Free\n";
    try std.testing.expect(try p.write_dilemma("main.bespoke", block));
    try std.testing.expect(std.mem.indexOf(u8, p.find("main.bespoke").?, "axis Mercy between Vengeance and \"Condoning Harm\"\n\ndilemma StolenBread:\n  actor Valerius\n  fires Judged\n  requires Accused(Thief)\n  weighs Justice against Mercy\n  leans 3 toward Justice when Criminal(Thief)\n  strong Justice: \"The law is the law.\" -> Hang\n  moderate Justice: \"A night in the cells.\" -> Jail\n  neutral: \"Show me why.\" -> Wait\n  moderate Mercy: \"Pay for the loaf.\" -> Fine\n  strong Mercy: \"Let him go.\" -> Free\n\nremember Justice(Valerius, 4)\n") != null);
    try std.testing.expect(try p.dilemmas("main.bespoke"));
    const listing = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, p.result.items, .{});
    listing.deinit();
    try std.testing.expect(result_has(&p, "\"lines\":[\"actor Valerius\""));

    // The preview: 4 - 0 + 3 = 7 is strong toward Justice; without the lean, 4 is moderate.
    const engine = bespoke.dilemma;
    for ([_]struct { lean: u32, delta: i32 }{ .{ .lean = 1, .delta = 7 }, .{ .lean = 0, .delta = 4 } }) |case| {
        try std.testing.expect(try p.preview_tier("main.bespoke", "StolenBread", 4, 0, case.lean));
        var want_buf: [32]u8 = undefined;
        const want = try std.fmt.bufPrint(&want_buf, "\"tier\":{d}", .{@intFromEnum(engine.tier_in(case.delta, engine.DEFAULT_STRONG_AT, engine.DEFAULT_MODERATE_AT))});
        try std.testing.expect(result_has(&p, want));
    }

    // Red lines: added after the last decision, rewritten, then removed; Free is a tier action,
    // so marking Pardon is fine, and a decision left with no option is refused.
    try std.testing.expect(try p.write_dilemma("main.bespoke", "redlines\tValerius\tExecute"));
    try std.testing.expect(std.mem.endsWith(u8, p.find("main.bespoke").?, "    picks 1 when Accused(Thief)\n\nred lines Valerius: Execute\n"));
    try std.testing.expect(!try p.write_dilemma("main.bespoke", "redlines\tValerius\tExecute\tPardon"));
    try std.testing.expect(try p.write_dilemma("main.bespoke", "redlines\tValerius"));
    try std.testing.expect(std.mem.endsWith(u8, p.find("main.bespoke").?, "    picks 1 when Accused(Thief)\n\n"));
}
