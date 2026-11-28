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
                inline for (.{ "width", "height", "cell", "origin_x", "origin_y" }) |f| {
                    try w.raw(",\"" ++ f ++ "\":");
                    try w.number(@field(g, f));
                }
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

    /// A room edit as the page sends it: one record per line, fields split by tabs, which no
    /// name can hold. `scene<TAB>Name` first, then `mark`/`prop<TAB>Name<TAB>x<TAB>y`,
    /// `area<TAB>Prop<TAB>x<TAB>y<TAB>w<TAB>h`, `walkway<TAB>A<TAB>B`, and
    /// `exit<TAB>Mark<TAB>Scene<TAB>Mark`, in the order they are to be written. Plain records
    /// keep a JSON reader, about 60 KB, out of the module.
    const RoomEdit = struct {
        scene: []const u8 = "",
        /// The block's lines after its header, already in the language.
        lines: std.ArrayList([]const u8) = .empty,
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
            if (std.mem.eql(u8, kind, "scene") and n == 2) {
                edit.scene = f[1];
            } else if ((std.mem.eql(u8, kind, "mark") or std.mem.eql(u8, kind, "prop")) and n == 4) {
                const x = num(f[2]) orelse return null;
                const y = num(f[3]) orelse return null;
                try edit.lines.append(a, try std.fmt.allocPrint(a, "  {s} {s} at {d} {d}", .{ kind, try room_name(a, f[1]), x, y }));
            } else if (std.mem.eql(u8, kind, "area") and n == 6) {
                var v: [4]u32 = undefined;
                for (&v, f[2..6]) |*out, t| out.* = num(t) orelse return null;
                try edit.lines.append(a, try std.fmt.allocPrint(a, "  area {s}: {d} {d} {d} {d}", .{ try room_name(a, f[1]), v[0], v[1], v[2], v[3] }));
            } else if (std.mem.eql(u8, kind, "walkway") and n == 3) {
                try edit.lines.append(a, try std.fmt.allocPrint(a, "  walkway {s} to {s}", .{ try room_name(a, f[1]), try room_name(a, f[2]) }));
            } else if (std.mem.eql(u8, kind, "exit") and n == 4) {
                try edit.lines.append(a, try std.fmt.allocPrint(a, "  exit {s} to {s} at {s}", .{ try room_name(a, f[1]), try room_name(a, f[2]), try room_name(a, f[3]) }));
            } else return null;
        }
        if (edit.scene.len == 0) return null;
        return edit;
    }

    /// Writes one scene's room block from `request` (a `RoomEdit`), P47-03, D-200: the
    /// block is rewritten whole where it stands, or a first block goes after the scene's own
    /// `scene` block, in that file's line endings. The project is then checked; when it does
    /// not check, the script is put back. `result` holds `{"written":true,"script":..,"line":N}`
    /// when kept, `{"written":false,"refused":".."}` for a request refused before the check,
    /// or the check's JSON.
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

        // The block's lines, names written as the language reads them.
        var lines: std.ArrayList([]const u8) = .empty;
        try lines.append(a, try std.fmt.allocPrint(a, "room {s}:", .{try room_name(a, scene.name)}));
        try lines.appendSlice(a, edit.lines.items);

        var buf: [1024]u8 = undefined;
        const target = scene.block orelse scene.declared;
        const path = try a.dupe(u8, table_script(&buf, main_path, dir, target.script));
        const old = try self.allocator.dupe(u8, self.find(path) orelse return self.refuse_room("the scene's script is not in the project"));
        defer self.allocator.free(old);
        const spliced = if (scene.block) |b|
            try replace_lines(a, old, b.line, b.end_line, lines.items)
        else
            try insert_block(a, old, scene.declared.end_line, lines.items);
        try self.add(path, spliced.bytes);
        if (!try self.check(main_path)) {
            try self.add(path, old);
            return false;
        }
        self.result.clearRetainingCapacity();
        var w = Json{ .list = &self.result, .allocator = self.allocator };
        try w.raw("{\"written\":true,\"script\":");
        try w.string(path);
        try w.raw(",\"line\":");
        try w.number(spliced.line);
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
    try out.appendSlice(a, text[at..]);
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
    try std.testing.expect(!try p.write_room("main.bespoke", "scene\tCellar\n"));
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
