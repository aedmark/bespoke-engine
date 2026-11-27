const std = @import("std");
const ListWriter = @import("list_writer.zig").ListWriter;
const bespoke = @import("root.zig");

const World = bespoke.World;
const SpatialSystem = bespoke.SpatialSystem;
const VM = bespoke.VM;
const DisplayBridge = bespoke.DisplayBridge;
const Repl = bespoke.Repl;
const CompiledProgram = bespoke.CompiledProgram;

/// Reads the files a script names, such as `image X from "lamp.png"`, from beside the script
/// (P46-04, D-156). A script is untrusted, so a path must be relative, use `/`, and have no `..`
/// part: a script cannot reach outside its own folder. A file is read up to the PNG limit.
pub const ScriptFiles = struct {
    io: std.Io,
    dir: []const u8,

    pub fn for_script(io: std.Io, script_path: []const u8) ScriptFiles {
        return .{ .io = io, .dir = std.fs.path.dirname(script_path) orelse "." };
    }

    pub fn source(self: *ScriptFiles) bespoke.compiler.FileSource {
        return .{ .context = self, .read = read };
    }

    fn read(context: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8 {
        const self: *ScriptFiles = @ptrCast(@alignCast(context));
        if (!beside_script(path)) return error.PathOutsideScriptFolder;
        const full = try std.fs.path.join(allocator, &.{ self.dir, path });
        defer allocator.free(full);
        const base_real = try std.Io.Dir.cwd().realPathFileAlloc(self.io, self.dir, allocator);
        defer allocator.free(base_real);
        const target_real = try std.Io.Dir.cwd().realPathFileAlloc(self.io, full, allocator);
        defer allocator.free(target_real);
        const inside = if (std.mem.endsWith(u8, base_real, "/"))
            std.mem.startsWith(u8, target_real, base_real)
        else
            std.mem.startsWith(u8, target_real, base_real) and target_real.len > base_real.len and target_real[base_real.len] == '/';
        if (!inside) return error.PathOutsideScriptFolder;
        return std.Io.Dir.cwd().readFileAlloc(self.io, target_real, allocator, .limited(bespoke.png.MAX_FILE));
    }
};

fn beside_script(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, '\\') != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| if (std.mem.eql(u8, part, "..")) return false;
    return true;
}

pub const ImportOptions = struct {
    /// The `image` name written into the block.
    name: []const u8,
    /// `frames WxH`; null makes the whole PNG one frame.
    frames: ?[2]u16 = null,
    /// A script whose palette the image joins: its codes are kept and new colours get unused
    /// ones. Without one, a whole palette block is written.
    script: ?[]const u8 = null,
};

/// `bespoke import`: converts a PNG into an inline `image` block, with the palette lines it
/// needs, written to `out` (P46-04, D-156). Returns false after printing a refusal to `out`.
pub fn import_art(allocator: std.mem.Allocator, io: std.Io, png_path: []const u8, options: ImportOptions, out: *std.Io.Writer) !bool {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const image = bespoke.image;

    image.validate_name(options.name) catch {
        try out.print("error: an image name is 1 to {d} printable characters\n", .{image.MAX_NAME});
        return false;
    };
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, png_path, arena, .limited(bespoke.png.MAX_FILE)) catch |err| {
        try out.print("error: cannot read '{s}' ({s})\n", .{ png_path, @errorName(err) });
        return false;
    };
    const rgba = bespoke.png.decode(arena, bytes) catch |err| {
        try out.print("error: '{s}' cannot be imported ({s})\n", .{ png_path, @errorName(err) });
        return false;
    };
    const fw: u16 = if (options.frames) |f| f[0] else rgba.width;
    const fh: u16 = if (options.frames) |f| f[1] else rgba.height;
    image.validate_size(rgba.width, rgba.height, fw, fh) catch {
        try out.print("error: '{s}' is {d}x{d}; frames of {d}x{d} must tile it, and a frame is at most {d}x{d}\n", .{ png_path, rgba.width, rgba.height, fw, fh, image.ART_WIDTH, image.ART_HEIGHT });
        return false;
    };

    var existing: bespoke.compiler.ScriptPalette = .{ .colours = &.{}, .codes = &.{} };
    if (options.script) |script_path| {
        const source = std.Io.Dir.cwd().readFileAlloc(io, script_path, arena, .limited(bespoke.compiler.MAX_SOURCE_SIZE)) catch |err| {
            try out.print("error: cannot read '{s}' ({s})\n", .{ script_path, @errorName(err) });
            return false;
        };
        var files = ScriptFiles.for_script(io, script_path);
        existing = bespoke.compiler.script_palette(arena, source, files.source()) catch {
            try out.print("error: '{s}' does not compile; run 'bespoke check {s}' first\n", .{ script_path, script_path });
            return false;
        };
    }

    var palette = std.ArrayListUnmanaged(image.Colour).empty;
    try palette.appendSlice(arena, existing.colours);
    if (palette.items.len == 0) try palette.append(arena, .{ .r = 0, .g = 0, .b = 0 });
    var where = bespoke.art_import.Where{};
    const pixels = bespoke.art_import.map(arena, rgba, &palette, &where) catch |err| {
        switch (err) {
            error.PartialTransparency => try out.print("error: pixel ({d}, {d}) of '{s}' is partly transparent; art pixels are opaque or fully transparent\n", .{ where.x, where.y, png_path }),
            error.TooManyColours => try out.print("error: '{s}' brings the palette past {d} colours at pixel ({d}, {d})\n", .{ png_path, image.MAX_COLOURS, where.x, where.y }),
            error.OutOfMemory => return error.OutOfMemory,
        }
        return false;
    };

    const width: usize = if (existing.codes.len > 0) existing.codes[0].len else if (palette.items.len <= bespoke.art_import.MAX_ONE_CHAR_COLOURS) 1 else 2;
    const codes = bespoke.art_import.assign_codes(arena, existing.codes, palette.items.len, width) catch |err| switch (err) {
        error.OutOfCodes => {
            try out.print("error: the palette's {d}-character codes run out; use two-character codes\n", .{width});
            return false;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };

    if (options.script == null) {
        try out.writeAll("palette:\n");
        try bespoke.art_import.write_palette_lines(out, palette.items, codes, 0);
        try out.writeAll("\n");
    } else if (palette.items.len > existing.codes.len) {
        try out.writeAll("# Add these lines to the script's palette:\n");
        try bespoke.art_import.write_palette_lines(out, palette.items, codes, existing.codes.len);
        try out.writeAll("\n");
    }
    try bespoke.art_import.write_image_block(out, options.name, options.frames, rgba.width, rgba.height, pixels, codes);
    return true;
}

pub const RunConfig = struct {
    ticks: usize = 20,
    is_headless: bool = false,
    verbose: bool = true,
    /// Headless only (P48-18, D-173): lines of `<tick> <typed command>`, each typed for the
    /// player once that many ticks have run, as the window's command bar would. Lines starting
    /// with `#` and blank lines are skipped.
    input: []const u8 = "",
    /// Headless only (P48-18): print the world's facts, sorted, when the clock stops and before
    /// the rewind demonstration, so a run can be compared with what it should have left.
    print_facts: bool = false,
    /// The run's seed (P48-14, D-184). Null keeps 42 for a headless run and takes one from the
    /// clock for a game in the window.
    seed: ?u64 = null,
};

pub const CheckOptions = struct {
    /// Also print the error's kind (`kind: UnboundVariable`), the part of a diagnostic the 1.0
    /// promise covers with its position (D-173).
    kind: bool = false,
};

/// Validates syntax and semantics of a .bespoke scenario file (P15-03, D-018).
pub fn check_file(allocator: std.mem.Allocator, io: std.Io, path: []const u8, stdout: anytype) !bool {
    return check_file_with(allocator, io, path, stdout, .{});
}

/// `check_file` with output options (P48-18).
pub fn check_file_with(allocator: std.mem.Allocator, io: std.Io, path: []const u8, stdout: anytype, options: CheckOptions) !bool {
    const max_size = bespoke.compiler.MAX_SOURCE_SIZE;
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_size)) catch |err| {
        try write_diagnostic_text(stdout, path);
        const what = switch (err) {
            error.FileNotFound => "cannot open file",
            error.StreamTooLong => "script exceeds the 16 MiB source limit",
            else => "failed to read file",
        };
        try stdout.print(": error: {s} ({s})\n", .{ what, @errorName(err) });
        return false;
    };
    defer allocator.free(source);

    var files = ScriptFiles.for_script(io, path);
    const res = bespoke.compiler.check_source_with(allocator, source, files.source());
    // Warnings never stop a script (P48-10, D-180); they print in the diagnostic's shape.
    for (res.warnings[0..res.warning_count]) |*w| {
        if (w.file().len > 0) {
            try write_diagnostic_text(stdout, std.fs.path.dirname(path) orelse ".");
            try stdout.print("/", .{});
            try write_diagnostic_text(stdout, w.file());
        } else try write_diagnostic_text(stdout, path);
        try stdout.print(":{d}:{d}: warning: ", .{ w.line, w.column });
        try write_diagnostic_text(stdout, w.message());
        try stdout.print("\n", .{});
    }
    if (res.is_valid) {
        try stdout.print("[check] '", .{});
        try write_diagnostic_text(stdout, path);
        try stdout.print("': syntax and semantics valid ({d} scene(s), {d} routine(s), {d} reactive rule(s), {d} bytes bytecode)\n", .{
            res.scene_count,
            res.routine_count,
            res.rule_count,
            res.bytecode_len,
        });
        return true;
    } else {
        try write_check_failure(stdout, allocator, files.source(), path, source, &res);
        if (options.kind) try stdout.print("kind: {s}\n", .{res.kind()});
        return false;
    }
}

/// Types each input line due after `ticks` ticks for the player (P48-18). A line is
/// `<tick> <command>`; the echo and any reply print as `[Tick N] > command` and `[Tick N] < reply`.
fn type_inputs(
    vm: *VM,
    compiled: *const CompiledProgram,
    interp: *bespoke.command.Interpreter,
    player: bespoke.EntityId,
    input: []const u8,
    ticks: usize,
    stdout: anytype,
) !void {
    var lines = std.mem.splitScalar(u8, input, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const space = std.mem.indexOfScalar(u8, line, ' ') orelse return error.InvalidInputLine;
        const due = std.fmt.parseInt(usize, line[0..space], 10) catch return error.InvalidInputLine;
        if (due != ticks) continue;
        const command = std.mem.trim(u8, line[space + 1 ..], " \t");
        try stdout.print("[Tick {d:>3}] > ", .{vm.world.current_tick});
        try write_diagnostic_text(stdout, command);
        try stdout.print("\n", .{});
        var buf: [256]u8 = undefined;
        const reply = try bespoke.host.run_command(vm, compiled, interp, player, command, &buf);
        if (reply.text) |text| {
            try stdout.print("[Tick {d:>3}] < ", .{vm.world.current_tick});
            try write_diagnostic_text(stdout, text);
            try stdout.print("\n", .{});
        }
    }
}

/// Types input lines for the player, in order, until one takes a turn (D-188). Returns false
/// when the lines run out first. A line's leading number is the realtime schedule and is not
/// read here: in a turn game, time is the lines themselves.
fn type_next_turn(
    vm: *VM,
    compiled: *const CompiledProgram,
    interp: *bespoke.command.Interpreter,
    player: bespoke.EntityId,
    lines: *std.mem.SplitIterator(u8, .scalar),
    stdout: anytype,
) !bool {
    if (player == .none) return false;
    const actor = player;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const space = std.mem.indexOfScalar(u8, line, ' ') orelse return error.InvalidInputLine;
        _ = std.fmt.parseInt(usize, line[0..space], 10) catch return error.InvalidInputLine;
        const command = std.mem.trim(u8, line[space + 1 ..], " \t");
        try stdout.print("[Tick {d:>3}] > ", .{vm.world.current_tick});
        try write_diagnostic_text(stdout, command);
        try stdout.print("\n", .{});
        var buf: [256]u8 = undefined;
        const reply = try bespoke.host.run_command(vm, compiled, interp, actor, command, &buf);
        if (reply.text) |text| {
            try stdout.print("[Tick {d:>3}] < ", .{vm.world.current_tick});
            try write_diagnostic_text(stdout, text);
            try stdout.print("\n", .{});
        }
        if (reply.turn) return true;
    }
    return false;
}

/// Prints every fact as `fact Relation(Subject)` or `fact Relation(Subject, Object)`, sorted,
/// so the output does not depend on table order (P48-18). A number relation's object prints as
/// its number and an entity relation's as the entity's name (D-178); a relation of unknown kind
/// prints a name when the object names an entity.
fn print_facts(allocator: std.mem.Allocator, world: *const World, stdout: anytype) !void {
    var lines = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit();
    }
    const slice = world.facts.slice();
    for (0..world.facts.len) |i| {
        const subject = world.get_entity_name(slice.items(.subject)[i]) orelse "?";
        const meta = world.get_relation_meta(slice.items(.relation)[i]);
        const relation = if (meta) |m| m.name else "?";
        const is_number = if (meta) |m| m.object_kind == .number else false;
        const object = slice.items(.object_or_value)[i];
        const line = if (object == 0 and !is_number)
            try std.fmt.allocPrint(allocator, "fact {s}({s})", .{ relation, subject })
        else if (is_number)
            try std.fmt.allocPrint(allocator, "fact {s}({s}, {d})", .{ relation, subject, object })
        else if (world.get_entity_name(bespoke.EntityId.from_int(object))) |name|
            try std.fmt.allocPrint(allocator, "fact {s}({s}, {s})", .{ relation, subject, name })
        else
            try std.fmt.allocPrint(allocator, "fact {s}({s}, {d})", .{ relation, subject, object });
        try lines.append(line);
    }
    std.mem.sort([]u8, lines.items, {}, struct {
        fn less(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    try stdout.print("facts: {d}\n", .{lines.items.len});
    for (lines.items) |line| {
        try write_diagnostic_text(stdout, line);
        try stdout.print("\n", .{});
    }
}

// Script and path bytes are untrusted terminal input. Escape control and non-ASCII bytes
// consistently, so an excerpt and its caret use the same width even for malformed UTF-8.
fn write_diagnostic_text(out: anytype, bytes: []const u8) !void {
    var start: usize = 0;
    for (bytes, 0..) |byte, i| {
        if (byte >= ' ' and byte <= '~') continue;
        try out.print("{s}\\x{x:0>2}", .{ bytes[start..i], byte });
        start = i + 1;
    }
    if (start < bytes.len) try out.print("{s}", .{bytes[start..]});
}

/// Writes a check failure, naming the included file it is in when it is not the main script
/// (P48-15, D-185): that file's path beside the main script, and an excerpt from it.
fn write_check_failure(out: anytype, allocator: std.mem.Allocator, files: ?bespoke.compiler.FileSource, path: []const u8, source: []const u8, res: *const bespoke.compiler.CheckResult) !void {
    const included = res.file();
    if (included.len == 0) return write_script_diagnostic(out, path, source, res);
    const shown = try std.fs.path.join(allocator, &.{ std.fs.path.dirname(path) orelse ".", included });
    defer allocator.free(shown);
    const fs = files orelse return write_script_diagnostic(out, shown, "", res);
    const bytes = fs.read(fs.context, allocator, included) catch return write_script_diagnostic(out, shown, "", res);
    defer allocator.free(bytes);
    try write_script_diagnostic(out, shown, bytes, res);
}

fn write_script_diagnostic(out: anytype, path: []const u8, source: []const u8, res: *const bespoke.compiler.CheckResult) !void {
    const d = res.diagnostic() orelse return;
    try write_diagnostic_text(out, path);
    try out.print(":{d}:{d}: error: ", .{ d.line, d.column });
    try write_diagnostic_text(out, d.message);
    try out.print("\n", .{});

    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (line_no < d.line) : (line_no += 1) {
        if (lines.next() == null) break;
    }
    if (lines.next()) |raw_line| {
        const line = if (std.mem.endsWith(u8, raw_line, "\r")) raw_line[0 .. raw_line.len - 1] else raw_line;
        const caret = @min(d.column -| 1, line.len);
        // Center long excerpts near the fault and bound terminal output by bytes.
        const before = if (line.len > 120) @min(caret -| 40, line.len - 120) else 0;
        const after = @min(before + 120, line.len);
        try out.print("{s}", .{if (before == 0) "  " else "  ..."});
        try write_diagnostic_text(out, line[before..after]);
        if (after < line.len) try out.print("...", .{});
        var pad: usize = if (before == 0) 2 else 5;
        for (line[before..caret]) |byte| {
            pad += if (byte >= ' ' and byte <= '~') @as(usize, 1) else 4;
        }
        try out.print("\n{s: >[1]}^\n", .{ "", pad });
    }
    if (res.suggestion()) |hint| {
        try out.print("  help: did you mean '", .{});
        try write_diagnostic_text(out, hint);
        try out.print("'?\n", .{});
    }
}

test "P40-01: check_file prints the diagnostic excerpt, caret, and suggestion" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "invalid.bespoke",
        .data = "routine Patrol(Guard):\r\n  wiat 1 ticks\r\n",
    });
    const path = try tmp.dir.realPathFileAlloc(testing.io, "invalid.bespoke", testing.allocator);
    defer testing.allocator.free(path);

    var storage: [1024]u8 = undefined;
    var out: std.Io.Writer = .fixed(&storage);
    // Runner hosts could already supply a writer exposing only print.
    const PrintOnly = struct {
        writer: *std.Io.Writer,
        pub fn print(self: @This(), comptime fmt: []const u8, args: anytype) !void {
            try self.writer.print(fmt, args);
        }
    };
    try testing.expect(!try check_file(testing.allocator, testing.io, path, PrintOnly{ .writer = &out }));
    const tail = "invalid.bespoke:2:3: error: unexpected statement 'wiat 1'\n" ++
        "    wiat 1 ticks\n    ^\n  help: did you mean 'wait'?\n";
    try testing.expect(std.mem.endsWith(u8, out.buffered(), tail));
}

test "P40-01: diagnostic excerpts bound long lines and escape terminal controls" {
    const testing = std.testing;
    const script = "entity " ++ @as([240]u8, @splat(' ')) ++ "\x1b\t:";
    const check = bespoke.check_source(testing.allocator, script);
    var storage: [512]u8 = undefined;
    var out: std.Io.Writer = .fixed(&storage);
    try write_script_diagnostic(&out, "bad\nfile", script, &check);
    const expected = "bad\\x0afile:1:250: error: expected a name, found ':'\n" ++
        "  ..." ++ @as([117]u8, @splat(' ')) ++ "\\x1b\\x09:\n" ++ @as([130]u8, @splat(' ')) ++ "^\n";
    try testing.expectEqualStrings(expected, out.buffered());
}

/// Compiles a .bespoke source file to a standalone .bspk binary package (P15-02, D-018).
pub fn compile_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    in_path: []const u8,
    out_path: []const u8,
    stdout: anytype,
) !void {
    return compile_file_with(allocator, io, in_path, out_path, stdout, .{});
}

/// Options for `compile_file_with` (P49-06, D-194).
pub const CompileOptions = struct {
    /// When set, a Make-style dependency file is written here after a successful compile:
    /// `<out_path>: <script> <every included script and image the compile read>`. A build
    /// system that reads it (Zig's `addDepFileOutputArg2`, as `bespoke init` projects do)
    /// rebuilds the package when any of those files changes, without listing them itself.
    deps: ?[]const u8 = null,
};

/// Every path a compile read through its `FileSource`, as the script's folder joined with the
/// path the script wrote, in first-read order. Only successful reads are kept: a failed read
/// fails the compile, and a failed compile writes no dependency file.
const ReadRecorder = struct {
    inner: bespoke.compiler.FileSource,
    dir: []const u8,
    allocator: std.mem.Allocator,
    paths: std.ArrayList([]const u8) = .empty,

    fn source(self: *ReadRecorder) bespoke.compiler.FileSource {
        return .{ .context = self, .read = read };
    }

    fn read(context: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8 {
        const self: *ReadRecorder = @ptrCast(@alignCast(context));
        const bytes = try self.inner.read(self.inner.context, allocator, path);
        errdefer allocator.free(bytes);
        const full = try std.fs.path.join(self.allocator, &.{ self.dir, path });
        for (self.paths.items) |seen| if (std.mem.eql(u8, seen, full)) {
            self.allocator.free(full);
            return bytes;
        };
        try self.paths.append(self.allocator, full);
        return bytes;
    }

    fn deinit(self: *ReadRecorder) void {
        for (self.paths.items) |p| self.allocator.free(p);
        self.paths.deinit(self.allocator);
    }
};

/// One Make rule: `target: dep dep ...`. Spaces, `#`, and `\` are escaped with a backslash and
/// `$` is doubled, as Make and Zig's dependency tokenizer read them.
fn write_dep_rule(writer: anytype, target: []const u8, deps: []const []const u8) !void {
    try write_dep_path(writer, target);
    try writer.writeAll(":");
    for (deps) |dep| {
        try writer.writeAll(" \\\n  ");
        try write_dep_path(writer, dep);
    }
    try writer.writeAll("\n");
}

fn write_dep_path(writer: anytype, path: []const u8) !void {
    for (path) |c| switch (c) {
        ' ', '#', '\\' => {
            try writer.writeByte('\\');
            try writer.writeByte(c);
        },
        '$' => try writer.writeAll("$$"),
        else => try writer.writeByte(c),
    };
}

pub fn compile_file_with(
    allocator: std.mem.Allocator,
    io: std.Io,
    in_path: []const u8,
    out_path: []const u8,
    stdout: anytype,
    options: CompileOptions,
) !void {
    const max_size = bespoke.compiler.MAX_SOURCE_SIZE;
    const source = try std.Io.Dir.cwd().readFileAlloc(io, in_path, allocator, .limited(max_size));
    defer allocator.free(source);

    var world = try World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = SpatialSystem.init(allocator);
    defer spatial.deinit();

    var files = ScriptFiles.for_script(io, in_path);
    var recorder = ReadRecorder{ .inner = files.source(), .dir = files.dir, .allocator = allocator };
    defer recorder.deinit();
    var compiled = bespoke.compiler.compile_source_with(allocator, &world, &spatial, source, recorder.source()) catch |err| {
        const res = bespoke.compiler.check_source_with(allocator, source, files.source());
        if (!res.is_valid) {
            try write_check_failure(stdout, allocator, files.source(), in_path, source, &res);
        } else {
            try stdout.print("{s}: error: compilation failed ({s})\n", .{ in_path, @errorName(err) });
        }
        return err;
    };
    defer compiled.deinit();

    try bespoke.save_package_file(allocator, io, out_path, &compiled, &world, &spatial);

    if (options.deps) |deps_path| {
        var list: std.ArrayList([]const u8) = .empty;
        defer list.deinit(allocator);
        try list.append(allocator, in_path);
        try list.appendSlice(allocator, recorder.paths.items);
        var text: std.Io.Writer.Allocating = .init(allocator);
        defer text.deinit();
        try write_dep_rule(&text.writer, out_path, list.items);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = deps_path, .data = text.written() });
    }

    const bytecode_bytes = compiled.chunk.count();
    const entity_count = world.entity_names.items.len;
    const routine_count = compiled.routine_entries.count();
    const rule_count = compiled.reactive_rules.items.len;

    try stdout.print("[compile] Successfully compiled '{s}' -> '{s}' ({d} bytes bytecode, {d} entities, {d} routines, {d} rules)\n", .{
        in_path,
        out_path,
        bytecode_bytes,
        entity_count,
        routine_count,
        rule_count,
    });
}

/// Executes a .bespoke text scenario or .bspk binary package from disk (P15-01, D-018).
pub fn run_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    config: RunConfig,
    stdout: anytype,
) !void {
    try run_file_with_presenter(true, allocator, io, path, config, stdout);
}

/// The static CLI instantiates only the headless path, so it needs no SDL import or linkage.
pub fn run_file_with_presenter(
    comptime desktop: bool,
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    config: RunConfig,
    stdout: anytype,
) !void {
    const max_size: usize = 32 * 1024 * 1024;
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_size));
    defer allocator.free(data);
    var files = ScriptFiles.for_script(io, path);
    try run_bytes_with_presenter(desktop, allocator, io, path, data, config, files.source(), stdout);
}

/// Executes a script or `.bspk` package already in memory; `name` labels messages. A game that
/// embeds its compiled package runs through this (P29-03, D-066).
pub fn run_bytes(
    allocator: std.mem.Allocator,
    io: std.Io,
    name: []const u8,
    data: []const u8,
    config: RunConfig,
    stdout: anytype,
) !void {
    // Bytes in memory have no folder, so a script among them cannot name a file.
    try run_bytes_with_presenter(true, allocator, io, name, data, config, null, stdout);
}

fn run_bytes_with_presenter(
    comptime desktop: bool,
    allocator: std.mem.Allocator,
    io: std.Io,
    name: []const u8,
    data: []const u8,
    config: RunConfig,
    files: ?bespoke.compiler.FileSource,
    stdout: anytype,
) !void {
    const path = name;
    var world = try World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = SpatialSystem.init(allocator);
    defer spatial.deinit();

    const is_binary = (data.len >= 4 and std.mem.eql(u8, data[0..4], &bespoke.package.PACKAGE_MAGIC)) or bespoke.package.is_pre_1_0(data);

    var compiled: CompiledProgram = undefined;
    if (is_binary) {
        if (config.verbose) try stdout.print("[Runner] Loading precompiled binary package '{s}'...\n", .{path});
        var stream: std.Io.Reader = .fixed(data);
        compiled = bespoke.load_package(allocator, &stream, &world, &spatial) catch |err| {
            if (err == error.UnsupportedPackageVersion) {
                var message_buf: [128]u8 = undefined;
                const found = bespoke.package.version_from_bytes(data) orelse 0;
                try stdout.print("{s}: error: {s}\n", .{ path, bespoke.package.format_unsupported_version(&message_buf, found) });
            }
            if (err == error.PackageFromBeforeOne) try stdout.print("{s}: error: {s}\n", .{ path, bespoke.package.PRE_1_0_MESSAGE });
            return err;
        };
    } else {
        if (config.verbose) try stdout.print("[Runner] Compiling narrative script '{s}'...\n", .{path});
        compiled = bespoke.compiler.compile_source_with(allocator, &world, &spatial, data, files) catch |err| {
            const res = bespoke.compiler.check_source_with(allocator, data, files);
            if (!res.is_valid) {
                try write_check_failure(stdout, allocator, files, path, data, &res);
            } else {
                try stdout.print("{s}: error: compilation failed ({s})\n", .{ path, @errorName(err) });
            }
            return err;
        };
    }
    defer compiled.deinit();

    try bespoke.host.initialize_subsystems(&world, &compiled);

    // Script scores become the window's soundtrack (P28-03, D-062). Declared after `compiled`
    // so it is released first; the window's bridge stops reading it when the window closes.
    var script_music = try bespoke.host.ScriptSoundtrack.init(allocator, &compiled);
    defer script_music.deinit();

    // Initialize Virtual Machine
    var vm = VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    // The run's dice are seeded before the script's first statement can roll (D-184).
    const windowed = desktop and !config.is_headless;
    vm.set_seed(config.seed orelse if (windowed) @truncate(@as(u96, @bitCast(std.Io.Timestamp.now(io, .real).toNanoseconds()))) else bespoke.dice.DEFAULT_SEED);

    // Top-level statements, the cast in its scenes, then every routine (P29-03, D-066). The
    // window's clicks and typed commands act for the returned player (D-064).
    const player_entity = try bespoke.host.start_script(&world, &spatial, &vm, &compiled);

    var display_bridge = DisplayBridge.init();
    var repl_instance = Repl.init(&world, &spatial, &vm);

    // Every snapshot is the whole run, so a rewind restores routines and dice too (D-184).
    var timeline = bespoke.host.Timeline.init(allocator);
    defer timeline.deinit();

    if (!desktop or config.is_headless) {
        try stdout.print("\n>>> STARTING SIMULATION CLOCK (Headless Mode, {d} ticks) <<<\n", .{config.ticks});

        // Capture initial frame 0
        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.swap();

        try timeline.record_run(&world, &spatial, &vm, null);

        // Headless runs report each change of script music, so a score's triggers can be
        // checked without an audio device. Scripts without scores print nothing.
        var last_score_buf: [32]u8 = undefined;
        var last_score: []const u8 = "";
        {
            const first = display_bridge.get_frame().get_current_score();
            if (first.len > 0) try stdout.print("[Tick {d:>3}] Music: {s}\n", .{ world.current_tick, first });
            @memcpy(last_score_buf[0..first.len], first);
            last_score = last_score_buf[0..first.len];
        }

        // Speech, scene changes, and offered choices are printed as they happen, so a script
        // can be read from a headless run (P29-02, D-064).
        var story = StoryReport{};
        try story.report(&world, &vm, stdout);

        var interp = bespoke.command.Interpreter{};
        // A turn game (D-188) runs its input lines in order: the clock moves one tick for each
        // line that takes a turn, and on while the player walks, and stops when the lines are
        // spent. `--ticks` still bounds the run.
        var turn_lines = std.mem.splitScalar(u8, config.input, '\n');
        var tick_count: usize = 0;
        while (tick_count < config.ticks) : (tick_count += 1) {
            if (compiled.turn_clock) {
                const walking = player_entity != .none and spatial.is_moving(player_entity);
                if (!walking and !try type_next_turn(&vm, &compiled, &interp, player_entity, &turn_lines, stdout)) break;
            } else {
                try type_inputs(&vm, &compiled, &interp, player_entity, config.input, tick_count, stdout);
            }
            _ = try bespoke.host.tick(&vm, &compiled);
            try story.report(&world, &vm, stdout);

            try timeline.record_run(&world, &spatial, &vm, null);

            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();

            const score_now = display_bridge.get_frame().get_current_score();
            if (!std.mem.eql(u8, score_now, last_score)) {
                try stdout.print("[Tick {d:>3}] Music: {s}\n", .{ world.current_tick, if (score_now.len > 0) score_now else "none" });
                @memcpy(last_score_buf[0..score_now.len], score_now);
                last_score = last_score_buf[0..score_now.len];
            }

            if (config.verbose and (tick_count % 5 == 0 or tick_count == config.ticks - 1)) {
                try stdout.print("[Tick {d:>3}] Active Facts: {d}, Active Fibers: {d}\n", .{
                    world.current_tick,
                    world.fact_count(),
                    vm.fibers.items.len,
                });
            }
        }

        if (config.print_facts) try print_facts(allocator, &world, stdout);

        try stdout.print("\n===================================================================\n", .{});
        try stdout.print("Simulation Finished at Tick {d}:\n", .{world.current_tick});
        try stdout.print("   - Total Facts Stored:  {d}\n", .{world.fact_count()});
        try stdout.print("   - Active Fibers:       {d}\n", .{vm.fibers.items.len});
        try stdout.print("===================================================================\n\n", .{});

        // Time-travel rewind verification
        if (timeline.len() > 2) {
            try stdout.print(">>> DEMONSTRATING TIME-TRAVEL REWIND: REWINDING TO TICK 2 <<<\n", .{});
            _ = try timeline.restore_run(&world, &spatial, &vm, null, 2, compiled.rewinds_reroll);
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
            try stdout.print("Rewound Simulation Clock Restored: Tick {d}\n", .{world.current_tick});
        }
    } else {
        var window = try bespoke.display.DisplayWindow.init(io, "BeSpoke Engine - Standalone Scenario Runner", 1280, 720);
        defer window.deinit();

        display_bridge.attach_audio_bridge(window.audio_bridge);
        if (script_music.has_scores()) window.audio_bridge.set_soundtrack(&script_music.soundtrack);

        try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
        try stdout.print("   - [Left Click Waypoint]: Direct actor to walk\n", .{});
        try stdout.print("   - [Left Click Prop]:     Examine scene hotspot\n", .{});
        try stdout.print("   - [Space]:               Pause / Resume Simulation\n", .{});
        try stdout.print("   - [N]:                   Single-step Simulation Tick\n", .{});
        try stdout.print("   - [F1 / D]:              Toggle Debug Inspector\n", .{});
        try stdout.print("   - [Tab / ` / C]:         Toggle Live REPL Console Drawer\n", .{});
        try stdout.print("   - [Esc / Close]:         Exit\n\n", .{});

        // Typed commands fire cues for the player (P29-02, D-064); Enter focuses the bar.
        window.enable_command_bar(true);
        // Declared backdrops and sprites draw in the stock window (P46-03, D-155).
        window.set_art(&compiled.art);
        // Saves from this window name this build, and loads refuse another's (P48-08, D-162).
        window.save_manager.program = compiled.identity();
        // Names on screen read the script's `name` lines (P48-09, D-179).
        bespoke.display.dialogue_panel.use_display_names(&world);
        defer bespoke.display.dialogue_panel.clear_display_names_for(&world);
        var interp = bespoke.command.Interpreter{};

        if (player_entity != .none) display_bridge.set_active_character(player_entity);
        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.set_max_history_tick(0);
        display_bridge.swap();
        bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);

        try timeline.record_run(&world, &spatial, &vm, null);
        // The snapshot on screen; ticking from an earlier one discards the later ones first.
        var cursor: usize = 0;

        var is_paused = false;
        var last_tick_time = std.Io.Timestamp.now(io, .awake).toMilliseconds();

        if (vm.current_scene) |sc| {
            var sname_buf: [48]u8 = undefined;
            var arrive_buf: [96]u8 = undefined;
            const sname = bespoke.display.dialogue_panel.entity_name(&world, sc, &sname_buf) orelse "";
            if (sname.len > 0) {
                const msg = bespoke.phrase.render(&world, .arrive_scene, &.{.{ .slot = "scene", .value = sname }}, &arrive_buf) catch sname;
                window.set_cue_banner(msg, 90);
            }
        }

        while (true) {
            const action = window.poll_events(display_bridge.get_frame());
            var should_step_now = false;
            var pending_narration_buf: [160]u8 = undefined;
            var pending_narration_len: usize = 0;

            if (window.handle_save_action(action, &world, &spatial, &vm, &display_bridge, &is_paused)) {
                const loading = action == .quick_load or action == .load_slot;
                if (loading and window.save_manager.last_load_succeeded) {
                    vm.sync_dialogue();
                    // A save from another build kept its facts but no routine (D-162).
                    if (window.save_manager.last_load_restarted_routines) try bespoke.host.restart_routines(&world, &spatial, &vm, &compiled);
                    // A loaded save has no timeline; start one from it, so a rewind cannot
                    // reach the future the load replaced.
                    timeline.reset();
                    try timeline.record_run(&world, &spatial, &vm, null);
                    cursor = 0;
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.set_max_history_tick(timeline.last_index());
                    display_bridge.swap();
                    bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);
                }
            }
            switch (action) {
                .quit => break,
                .toggle_pause => {
                    is_paused = !is_paused;
                },
                .step_tick => {
                    should_step_now = true;
                },
                .walk_player => |wp_id| {
                    const planned = spatial.walk_to_with_world(&world, player_entity, wp_id) catch false;
                    if (compiled.turn_clock and player_entity != .none and spatial.is_moving(player_entity)) is_paused = false;
                    var msg_buf: [96]u8 = undefined;
                    if (planned or !spatial.waypoint_blocked(&world, wp_id)) {
                        if (spatial.graph.get_waypoint(wp_id)) |wp| {
                            var nbuf: [48]u8 = undefined;
                            const mname = bespoke.display.dialogue_panel.named(&world, wp.name, &nbuf);
                            const msg = bespoke.phrase.render(&world, .walking_to, &.{.{ .slot = "mark", .value = mname }}, &msg_buf) catch "Walking...";
                            window.set_cue_banner(msg, 60);
                        }
                    } else {
                        window.set_cue_banner(bespoke.phrase.text(&world, .cannot_get_there), 90);
                    }
                },
                // A click or number key answers the open dialogue. A scripted choice resumes its
                // fiber, so the chosen body runs on the tick that follows at once.
                .dialogue_choice => |index| {
                    if (try answer_dialogue(&vm, index)) should_step_now = true;
                },
                .typed_command => |typed| {
                    var reply_buf: [160]u8 = undefined;
                    const reply = try bespoke.host.run_command(&vm, &compiled, &interp, player_entity, typed.buf[0..typed.len], &reply_buf);
                    if (reply.text) |text| window.set_cue_banner(text, 180);
                    // Under a turn clock every resolved command is a turn (D-188).
                    if (if (compiled.turn_clock) reply.turn else reply.fired) should_step_now = true;
                    bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);
                },
                .examine_hotspot => |hs_idx| {
                    const frame = display_bridge.get_frame();
                    if (hs_idx < frame.hotspot_count) {
                        const hs = frame.hotspots[hs_idx];
                        var fallback_buf: [256]u8 = undefined;
                        const res = try runner_act(&world, &vm, &compiled, player_entity, .look_at, hs.entity, hs.get_examine_text(), bespoke.EntityId.none, &pending_narration_buf, &fallback_buf);
                        if (res.fired) {
                            should_step_now = true;
                            if (res.text) |t| pending_narration_len = t.len;
                        } else {
                            if (res.text) |t| window.set_cue_banner(t, 120);
                            // A click that resolves to an action is a turn, as `look` would be.
                            if (compiled.turn_clock) should_step_now = true;
                        }
                    }
                },
                .interact_hotspot => |act| {
                    const frame = display_bridge.get_frame();
                    if (act.hotspot_index < frame.hotspot_count) {
                        const hs = frame.hotspots[act.hotspot_index];
                        var fallback_buf: [256]u8 = undefined;
                        const res = try runner_act(&world, &vm, &compiled, player_entity, act.verb, hs.entity, hs.get_examine_text(), bespoke.EntityId.none, &pending_narration_buf, &fallback_buf);
                        if (res.fired) {
                            should_step_now = true;
                            if (res.text) |t| pending_narration_len = t.len;
                        } else if (res.text) |t| {
                            window.set_cue_banner(t, 120);
                        }
                    }
                },
                .interact_actor => |act| {
                    const frame = display_bridge.get_frame();
                    if (act.actor_index < frame.entity_count) {
                        const target = frame.entities[act.actor_index].entity;
                        var fallback_buf: [256]u8 = undefined;
                        const res = try runner_act(&world, &vm, &compiled, player_entity, act.verb, target, null, bespoke.EntityId.none, &pending_narration_buf, &fallback_buf);
                        if (res.fired) {
                            should_step_now = true;
                            if (res.text) |t| pending_narration_len = t.len;
                        } else if (res.text) |t| {
                            window.set_cue_banner(t, 120);
                        }
                    }
                },
                .use_inventory_on_hotspot => |u| {
                    const frame = display_bridge.get_frame();
                    if (u.item_index < frame.inventory_count and u.hotspot_index < frame.hotspot_count) {
                        var fallback_buf: [256]u8 = undefined;
                        const res = try runner_act(&world, &vm, &compiled, player_entity, .use_with, frame.hotspots[u.hotspot_index].entity, null, frame.inventory[u.item_index].entity, &pending_narration_buf, &fallback_buf);
                        if (res.fired) {
                            should_step_now = true;
                            if (res.text) |t| pending_narration_len = t.len;
                        } else if (res.text) |t| {
                            window.set_cue_banner(t, 120);
                        }
                    }
                },
                .use_inventory_on_actor => |u| {
                    const frame = display_bridge.get_frame();
                    if (u.item_index < frame.inventory_count and u.actor_index < frame.entity_count) {
                        var fallback_buf: [256]u8 = undefined;
                        const res = try runner_act(&world, &vm, &compiled, player_entity, .use_with, frame.entities[u.actor_index].entity, null, frame.inventory[u.item_index].entity, &pending_narration_buf, &fallback_buf);
                        if (res.fired) {
                            should_step_now = true;
                            if (res.text) |t| pending_narration_len = t.len;
                        } else if (res.text) |t| {
                            window.set_cue_banner(t, 120);
                        }
                    }
                },
                .combine_inventory_items => |c| {
                    const frame = display_bridge.get_frame();
                    if (c.primary_index < frame.inventory_count and c.secondary_index < frame.inventory_count) {
                        var fallback_buf: [256]u8 = undefined;
                        const res = try runner_act(&world, &vm, &compiled, player_entity, .use_with, frame.inventory[c.secondary_index].entity, null, frame.inventory[c.primary_index].entity, &pending_narration_buf, &fallback_buf);
                        if (res.fired) {
                            should_step_now = true;
                            if (res.text) |t| pending_narration_len = t.len;
                        } else if (res.text) |t| {
                            window.set_cue_banner(t, 120);
                        }
                    }
                },
                .rewind => {
                    if (timeline.len() > 2) {
                        is_paused = true;
                        cursor = (try timeline.restore_run(&world, &spatial, &vm, null, 2, compiled.rewinds_reroll)).?;
                        vm.sync_dialogue();
                        display_bridge.capture_frame(&world, &spatial, &vm);
                        display_bridge.set_max_history_tick(timeline.last_index());
                        display_bridge.swap();
                        bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);
                        window.set_cue_banner("Rewound to tick 2 (paused).", 90);
                    }
                },
                .scrub_to_tick => |target_tick| {
                    if (timeline.len() > 0) {
                        is_paused = true;
                        cursor = (try timeline.restore_run(&world, &spatial, &vm, null, target_tick, compiled.rewinds_reroll)).?;
                        vm.sync_dialogue();
                        display_bridge.capture_frame(&world, &spatial, &vm);
                        display_bridge.set_max_history_tick(timeline.last_index());
                        display_bridge.swap();
                        bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);

                        var banner_buf: [96]u8 = undefined;
                        const text = std.fmt.bufPrint(&banner_buf, "Scrubbed to tick {d} (paused).", .{world.current_tick}) catch "Scrubbed";
                        window.set_cue_banner(text, 90);
                    }
                },
                .repl_command => |cmd| {
                    const line = cmd.buf[0..cmd.len];
                    const res = repl_instance.execute(line);
                    window.add_console_history(res.get_text());
                    if (res.output_len > 0) {
                        window.set_cue_banner(res.get_text(), 120);
                    }
                    // A console command changes the run between ticks; record it as now.
                    timeline.discard_after(cursor);
                    try timeline.record_run(&world, &spatial, &vm, null);
                    cursor = timeline.last_index();
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.set_max_history_tick(timeline.last_index());
                    display_bridge.swap();
                },
                else => {},
            }

            const now = std.Io.Timestamp.now(io, .awake).toMilliseconds();
            // A turn clock runs on its own only while the player walks, so a walk passes time
            // and stops with the player (D-188).
            const clock_runs = !compiled.turn_clock or (player_entity != .none and spatial.is_moving(player_entity));
            if (!is_paused and clock_runs and (now - last_tick_time >= window.current_tick_interval_ms)) {
                should_step_now = true;
                last_tick_time = now;
            }

            if (should_step_now) {
                _ = try bespoke.host.tick(&vm, &compiled);
                if (compiled.turn_clock and player_entity != .none and spatial.is_moving(player_entity)) is_paused = false;
                // The window draws script speech only from a banner, so each tick's `say`
                // lines are passed to it here (P29-02, D-064).
                var speech_buf: [256]u8 = undefined;
                if (bespoke.host.speech_this_tick(&world, &vm, &speech_buf)) |line| {
                    window.set_cue_banner(line, 160);
                } else if (pending_narration_len > 0) {
                    window.set_cue_banner(pending_narration_buf[0..pending_narration_len], 120);
                }

                timeline.discard_after(cursor);
                try timeline.record_run(&world, &spatial, &vm, null);
                cursor = timeline.last_index();

                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.set_max_history_tick(timeline.last_index());
                display_bridge.swap();
                bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);
            }

            window.render_frame(display_bridge.get_frame(), is_paused);
            io.sleep(.fromMilliseconds(16), .awake) catch {};
        }
    }
}

/// Prints what a headless run's story did on the most recent tick: each `say` line, a change of
/// scene, and a newly offered set of choices. A headless run cannot answer a choice, so the
/// speaker's fiber stays suspended; tests and hosts answer with `VM.choose`.
pub const StoryReport = struct {
    scene: ?bespoke.EntityId = null,
    dialogue_revision: ?u32 = null,

    pub fn report(self: *StoryReport, world: *const World, vm: *const VM, out: anytype) !void {
        const tick = world.current_tick;
        if (vm.current_scene) |scene| if (self.scene == null or self.scene.? != scene) {
            try out.print("[Tick {d:>3}] Scene: {s}\n", .{ tick, world.get_entity_name(scene) orelse "?" });
            self.scene = scene;
        };
        for (vm.emitted_cues.items) |cue| {
            if (cue.cue_id != bespoke.host.SAY_CUE_ID or cue.arg_count < 2) continue;
            // A declared `name` reads as written (D-179); otherwise the transcript keeps the raw
            // identifier, as it always has.
            const speaker = bespoke.EntityId.from_int(cue.args[0]);
            const name = world.display_text(speaker) orelse world.get_entity_name(speaker) orelse "Someone";
            const text = world.get_entity_name(bespoke.EntityId.from_int(cue.args[1])) orelse "";
            try out.print("[Tick {d:>3}] {s}: \"{s}\"\n", .{ tick, name, text });
        }
        if (bespoke.dialogue.view(world)) |open| {
            if (self.dialogue_revision == null or self.dialogue_revision.? != open.revision) {
                try out.print("[Tick {d:>3}] Choices for {s}:", .{ tick, world.get_entity_name(open.display_speaker) orelse "?" });
                for (0..open.count) |i| try out.print(" {d}. {s}", .{ i + 1, open.text(i) });
                try out.writeAll("\n");
                self.dialogue_revision = open.revision;
            }
        } else self.dialogue_revision = null;
    }
};

/// The actor the stock window acts for (D-064); see `host.player_actor`.
pub const player_actor = bespoke.host.player_actor;

/// Answers the open dialogue with option `index`. Returns true when a scripted body must run,
/// which takes one tick; an index past the offered options changes nothing.
pub fn answer_dialogue(vm: *VM, index: usize) !bool {
    const selection = (try vm.choose(index)) orelse return false;
    return selection.is_scripted();
}

// =========================================================================
// Unit Tests (P15-01, P15-02, P15-03)
// =========================================================================

test "P15-01: runner checks and compiles external scenario file" {
    const testing = std.testing;

    const script_content =
        \\scene Courtyard:
        \\  cast: Guard, Cat
        \\  props: Fountain
        \\  marks: Gate, FountainMark
        \\
        \\relation Carries(holder, item)
        \\
        \\routine Patrol(Guard):
        \\  walk Guard to FountainMark
        \\  wait 2 ticks
        \\  walk Guard to Gate
    ;

    // A private directory per run: the library and CLI test binaries run this test at the same
    // time, and with fixed /tmp paths one deleted the other's files mid-test.
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(dir_path);
    const tmp_script = try std.fs.path.join(testing.allocator, &.{ dir_path, "test_runner_script.bespoke" });
    defer testing.allocator.free(tmp_script);
    const tmp_pkg = try std.fs.path.join(testing.allocator, &.{ dir_path, "test_runner_script.bspk" });
    defer testing.allocator.free(tmp_pkg);

    // Write source file
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = tmp_script, .data = script_content });

    var discard_buf: [256]u8 = undefined;
    var discarding: std.Io.Writer.Discarding = .init(&discard_buf);
    const null_writer = &discarding.writer;

    // Test check_file
    const is_valid = try check_file(testing.allocator, testing.io, tmp_script, null_writer);
    try testing.expect(is_valid);

    // Test compile_file
    try compile_file(testing.allocator, testing.io, tmp_script, tmp_pkg, null_writer);

    // Verify .bspk exists and has valid magic
    var magic_buf: [4]u8 = undefined;
    const head = try std.Io.Dir.cwd().readFile(testing.io, tmp_pkg, &magic_buf);
    try testing.expectEqualStrings("BSP1", head);

    // Test run_file on source in headless mode
    try run_file(testing.allocator, testing.io, tmp_script, .{ .ticks = 5, .is_headless = true, .verbose = false }, null_writer);

    // Test run_file on compiled binary package in headless mode
    try run_file(testing.allocator, testing.io, tmp_pkg, .{ .ticks = 5, .is_headless = true, .verbose = false }, null_writer);
}

test "P48-17: runner names a package format it cannot read, and one from before 1.0" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, null, "entity Hero\nroutine Idle(Hero):\n  wait 1 ticks\n");
    defer compiled.deinit();
    var bytes = std.array_list.Managed(u8).init(testing.allocator);
    defer bytes.deinit();
    var lw = bespoke.ListWriter.init(&bytes);
    try bespoke.package.save_package(testing.allocator, &lw.writer, &compiled, &world, null);
    std.mem.writeInt(u32, bytes.items[4..8], bespoke.package.PACKAGE_FORMAT + 1, .little);

    var output_buf: [256]u8 = undefined;
    var output: std.Io.Writer = .fixed(&output_buf);
    const config = RunConfig{ .ticks = 0, .is_headless = true, .verbose = false };
    try testing.expectError(error.UnsupportedPackageVersion, run_bytes(testing.allocator, testing.io, "future.bspk", bytes.items, config, &output));
    try testing.expectEqualStrings("future.bspk: error: unsupported .bspk format 2; this engine reads format 1\n", output.buffered());

    // A package written before 1.0 is named as such (D-174).
    @memcpy(bytes.items[0..4], &bespoke.package.PRE_1_0_MAGIC);
    output = .fixed(&output_buf);
    try testing.expectError(error.PackageFromBeforeOne, run_bytes(testing.allocator, testing.io, "old.bspk", bytes.items, config, &output));
    try testing.expectEqualStrings("old.bspk: error: " ++ bespoke.package.PRE_1_0_MESSAGE ++ "\n", output.buffered());
}

test "P29-02: the window acts for the first routine's actor and answers scripted dialogue" {
    const testing = std.testing;
    const source =
        \\scene Hall:
        \\  cast: Zed, Amy, Hero
        \\  marks: Door, Stair
        \\
        \\relation Asked(who)
        \\
        \\routine Zwander(Zed):
        \\  wait 1 ticks
        \\routine Hero(Hero):
        \\  wait 1 ticks
        \\routine Amble(Amy):
        \\  wait 1 ticks
        \\
        \\on cue TalksTo(Hero, Amy):
        \\  choice "Ask the way.":
        \\    remember Asked(Hero)
        \\  choice "Leave.":
        \\    say Amy: "Goodbye."
    ;
    var world = try World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, source);
    defer compiled.deinit();
    // Hash order would not give Zed reliably; source order does.
    try testing.expectEqualStrings("Zed", player_actor(&compiled).?);

    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    const hero = world.lookup_entity("Hero").?;
    const amy = world.lookup_entity("Amy").?;
    _ = (try vm.fire_cue(&compiled, "TalksTo", hero, amy, null)).?;
    _ = try bespoke.host.tick(&vm, &compiled);
    try testing.expect(bespoke.dialogue.view(&world) != null);

    try testing.expect(!try answer_dialogue(&vm, 5));
    try testing.expect(try answer_dialogue(&vm, 0));
    _ = try bespoke.host.tick(&vm, &compiled);
    try testing.expect(world.find_first(hero, world.lookup_relation("Asked").?, null) != null);
    try testing.expect(bespoke.dialogue.view(&world) == null);
}

test "P29-02: a script with no routine has no player actor" {
    const testing = std.testing;
    var world = try World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, "entity Lamp\n");
    defer compiled.deinit();
    try testing.expect(player_actor(&compiled) == null);
}

test "P46-04: a script compiled from its file reads the PNGs beside it in their own colours" {
    const testing = std.testing;
    const path = "tests/fixtures/png/gallery.bespoke";
    const source = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(64 * 1024));
    defer testing.allocator.free(source);
    var files = ScriptFiles.for_script(testing.io, path);
    var world = try World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var compiled = try bespoke.compiler.compile_source_with(testing.allocator, &world, null, source, files.source());
    defer compiled.deinit();
    const art = compiled.art;
    // Each pixel keeps the PNG's colour: the badge's red border, then yellow and blue inside.
    const Pixel = bespoke.image.Pixel;
    const red = Pixel{ .r = 200, .g = 40, .b = 40, .a = 255 };
    const badge = art.find("BadgeSheet").?.pixels;
    try testing.expectEqualSlices(Pixel, &.{ bespoke.image.TRANSPARENT, red, red, red, red, bespoke.image.TRANSPARENT }, badge[0..6]);
    try testing.expectEqual(Pixel{ .r = 240, .g = 220, .b = 60, .a = 255 }, badge[7]);
    try testing.expectEqual(@as(u32, 2), art.find("LampSheet").?.frame_count());
    try testing.expectEqual(@as(u16, 1), art.sprite_for(world.lookup_entity("Curator").?).?.frame_at(.idle, 10));

    // Without the command line's file source, the same script is told where it can be read.
    const check = bespoke.check_source(testing.allocator, source);
    try testing.expect(!check.is_valid);
    try testing.expectEqualStrings("image 'BadgeSheet' reads \"rgba.png\", which only a compile from the command line can do; 'bespoke import' writes its rows into the script instead", check.message());
    try testing.expectEqual(@as(u32, 8), check.line);
}

test "P46-04: a script cannot read a file outside its folder, and a missing or bad file is named" {
    const testing = std.testing;
    var files = ScriptFiles.for_script(testing.io, "tests/fixtures/png/gallery.bespoke");
    const Case = struct { file: []const u8, message: []const u8 };
    const cases = [_]Case{
        .{ .file = "../compat/format-1-package.bspk", .message = "image 'Art' cannot read \"../compat/format-1-package.bspk\" (PathOutsideScriptFolder)" },
        .{ .file = "/etc/hostname", .message = "image 'Art' cannot read \"/etc/hostname\" (PathOutsideScriptFolder)" },
        .{ .file = "missing.png", .message = "image 'Art' cannot read \"missing.png\" (FileNotFound)" },
        .{ .file = "interlaced.png", .message = "image 'Art' cannot use \"interlaced.png\": it is interlaced; save it without interlacing" },
        .{ .file = "partial_alpha.png", .message = "image 'Art': pixel (1, 0) of \"partial_alpha.png\" is partly transparent; art pixels are opaque or fully transparent (D-166)" },
        .{ .file = "gallery.bespoke", .message = "image 'Art' cannot use \"gallery.bespoke\": it is not a PNG" },
    };
    for (cases) |case| {
        var buf: [128]u8 = undefined;
        const source = try std.fmt.bufPrint(&buf, "image Art from \"{s}\"\n", .{case.file});
        const result = bespoke.compiler.check_source_with(testing.allocator, source, files.source());
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings(case.message, result.message());
    }
}

test "P46-04: import writes an indexed and a true-colour PNG as inline blocks, joining a script's palette" {
    const testing = std.testing;
    var out = std.Io.Writer.Allocating.init(testing.allocator);
    defer out.deinit();
    try testing.expect(try import_art(testing.allocator, testing.io, "tests/fixtures/png/indexed.png", .{ .name = "Lamp", .frames = .{ 4, 4 } }, &out.writer));
    try testing.expectEqualStrings(
        \\palette:
        \\  "." transparent
        \\  "a" 34 32 52
        \\  "b" 217 160 102
        \\  "c" 251 242 54
        \\
        \\image Lamp frames 4x4:
        \\  ".aa..aa."
        \\  "abbaacca"
        \\  "abbaacca"
        \\  ".aa..aa."
        \\
    , out.written());

    // Against a script, its codes are kept and only new colours are listed, with unused codes.
    out.clearRetainingCapacity();
    try testing.expect(try import_art(testing.allocator, testing.io, "tests/fixtures/png/rgba.png", .{ .name = "Badge", .script = "tests/fixtures/png/palette.bespoke" }, &out.writer));
    try testing.expect(std.mem.startsWith(u8, out.written(), "# Add these lines to the script's palette:\n  \"a\" 240 220 60\n  \"b\" 30 30 90\n"));
    try testing.expect(std.mem.endsWith(u8, out.written(), "image Badge:\n  \".rrrr.\"\n  \"rabbar\"\n  \"raaaar\"\n  \".rrrr.\"\n"));

    // The written block compiles back to the same pixels.
    out.clearRetainingCapacity();
    try testing.expect(try import_art(testing.allocator, testing.io, "tests/fixtures/png/rgba.png", .{ .name = "Badge" }, &out.writer));
    var world = try World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, null, out.written());
    defer compiled.deinit();
    var files_for_png = ScriptFiles.for_script(testing.io, "tests/fixtures/png/gallery.bespoke");
    var direct = try bespoke.compiler.compile_source_with(testing.allocator, &world, null, "image Badge from \"rgba.png\"\n", files_for_png.source());
    defer direct.deinit();
    try testing.expectEqualSlices(bespoke.image.Pixel, direct.art.find("Badge").?.pixels, compiled.art.find("Badge").?.pixels);

    // A declared palette is a rule the PNG must follow (D-166): the badge's yellow is not in it.
    const ruled = bespoke.compiler.check_source_with(testing.allocator, "palette:\n  \".\" transparent\n  \"r\" 200 40 40\nimage Badge from \"rgba.png\"\n", files_for_png.source());
    try testing.expect(!ruled.is_valid);
    try testing.expectEqualStrings("image 'Badge': pixel (1, 1) of \"rgba.png\" is 240 220 60, which the script's 'palette:' does not hold; add it or recolour the pixel (D-166)", ruled.message());

    // More colours than the palette holds is refused, by name.
    out.clearRetainingCapacity();
    try testing.expect(!try import_art(testing.allocator, testing.io, "tests/fixtures/png/too_many_colours.png", .{ .name = "Swatch" }, &out.writer));
    try testing.expectEqualStrings("error: 'tests/fixtures/png/too_many_colours.png' brings the palette past 256 colours at pixel (0, 15)\n", out.written());
}

test "P48-24: symlink escaping script folder is rejected by ScriptFiles" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "game");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "outside.bespoke", .data = "entity Secret\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "game/main.bespoke", .data = "include \"escape.bespoke\"\n" });
    const tmp_real = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(tmp_real);
    const outside_abs = try std.fs.path.join(testing.allocator, &.{ tmp_real, "outside.bespoke" });
    defer testing.allocator.free(outside_abs);
    var game_dir = try tmp.dir.openDir(testing.io, "game", .{});
    defer game_dir.close(testing.io);
    try game_dir.symLink(testing.io, outside_abs, "escape.bespoke", .{});

    const main_path = try std.fs.path.join(testing.allocator, &.{ tmp_real, "game", "main.bespoke" });
    defer testing.allocator.free(main_path);
    var files = ScriptFiles.for_script(testing.io, main_path);
    const fs = files.source();
    try testing.expectError(error.PathOutsideScriptFolder, fs.read(fs.context, testing.allocator, "escape.bespoke"));
}

const RunnerActOutcome = struct {
    fired: bool = false,
    text: ?[]const u8 = null,
};

fn runner_verb_cue(verb: bespoke.display.renderer.AdventureVerb) []const u8 {
    return switch (verb) {
        .walk => "WalksTo",
        .look_at => "LooksAt",
        .talk_to => "TalksTo",
        .pick_up => "Takes",
        .use_with => "Uses",
    };
}

fn runner_narrate(
    world: *const World,
    actor: bespoke.EntityId,
    verb: bespoke.display.renderer.AdventureVerb,
    item: bespoke.EntityId,
    target: bespoke.EntityId,
    out_buf: *[160]u8,
) ?[]const u8 {
    var names: [3][48]u8 = undefined;
    const who = bespoke.display.dialogue_panel.entity_name(world, actor, &names[0]) orelse bespoke.phrase.text(world, .player_fallback);
    const what = if (item != .none) bespoke.display.dialogue_panel.entity_name(world, item, &names[1]) orelse bespoke.phrase.text(world, .thing_fallback) else "";
    const on = if (target != .none) bespoke.display.dialogue_panel.entity_name(world, target, &names[2]) orelse bespoke.phrase.text(world, .thing_fallback) else "";
    const key: bespoke.phrase.Key = switch (verb) {
        .walk => .narrate_walk,
        .look_at => .narrate_look,
        .talk_to => .narrate_talk,
        .pick_up => .narrate_take,
        .use_with => .narrate_use,
    };
    return (if (item != .none and target != .none)
        bespoke.phrase.render(world, .narrate_use_on, &.{ .{ .slot = "actor", .value = who }, .{ .slot = "thing", .value = what }, .{ .slot = "target", .value = on } }, out_buf)
    else
        bespoke.phrase.render(world, key, &.{ .{ .slot = "actor", .value = who }, .{ .slot = "target", .value = if (item != .none) what else on } }, out_buf)) catch null;
}

/// Dispatches one desktop verb action through the script's cue handlers, producing either
/// fallback narration (`{actor} uses {target}.`) for silent handlers, custom examine text on
/// unhandled LOOK clicks, or the engine's "Nothing happens." phrase (`D-179`).
fn runner_act(
    world: *World,
    vm: *VM,
    compiled: *const CompiledProgram,
    actor: bespoke.EntityId,
    verb: bespoke.display.renderer.AdventureVerb,
    target: bespoke.EntityId,
    examine_text: ?[]const u8,
    item: bespoke.EntityId,
    narration_buf: *[160]u8,
    fallback_buf: *[256]u8,
) !RunnerActOutcome {
    if (actor == .none) return .{};
    if (item != .none) {
        if ((try vm.fire_cue(compiled, "Uses", actor, item, target)) != null) {
            return .{ .fired = true, .text = runner_narrate(world, actor, .use_with, item, target, narration_buf) };
        }
        return .{ .fired = false, .text = bespoke.phrase.text(world, .nothing_happens) };
    }
    if ((try vm.fire_cue(compiled, runner_verb_cue(verb), actor, target, null)) != null) {
        return .{ .fired = true, .text = runner_narrate(world, actor, verb, .none, target, narration_buf) };
    }
    if (verb == .look_at) {
        if (examine_text) |et| {
            const tname = world.get_entity_name(target) orelse "";
            if (et.len > 0 and !std.mem.eql(u8, et, tname)) {
                var nbuf: [48]u8 = undefined;
                const dname = bespoke.display.dialogue_panel.entity_name(world, target, &nbuf) orelse tname;
                const msg = std.fmt.bufPrint(fallback_buf, "{s}: \"{s}\"", .{ dname, et }) catch et;
                return .{ .fired = false, .text = msg };
            }
        }
    }
    return .{ .fired = false, .text = bespoke.phrase.text(world, .nothing_happens) };
}

test "P48-05: runner verb helper fires handlers, falls back to examine text or Nothing happens, and narrates silent handlers" {
    const testing = std.testing;
    const script =
        \\scene: Meadow
        \\cast: Courier
        \\props: BrassHorn, OakChest
        \\marks: Milestone
        \\
        \\relation Polished(thing)
        \\
        \\routine Idle(Courier):
        \\  wait 10 ticks
        \\
        \\on cue LooksAt(Courier, BrassHorn):
        \\  say Courier: "Gleaming brass."
        \\
        \\on cue Uses(Courier, BrassHorn):
        \\  remember Polished(BrassHorn)
        \\
    ;
    var world = try World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, script);
    defer compiled.deinit();
    var vm = VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    const courier = world.lookup_entity("Courier").?;
    const horn = world.lookup_entity("BrassHorn").?;
    const chest = world.lookup_entity("OakChest").?;
    var narration_buf: [160]u8 = undefined;
    var fallback_buf: [256]u8 = undefined;

    // 1. Speech handler fires and tick captures the spoken line.
    const look_res = try runner_act(&world, &vm, &compiled, courier, .look_at, horn, "BrassHorn", bespoke.EntityId.none, &narration_buf, &fallback_buf);
    try testing.expect(look_res.fired);
    _ = try bespoke.host.tick(&vm, &compiled);
    var speech_buf: [256]u8 = undefined;
    try testing.expectEqualStrings("Courier: \"Gleaming brass.\"", bespoke.host.speech_this_tick(&world, &vm, &speech_buf).?);

    // 2. Silent handler returns consistent narration phrase when the tick speaks nothing.
    const use_res = try runner_act(&world, &vm, &compiled, courier, .use_with, horn, null, bespoke.EntityId.none, &narration_buf, &fallback_buf);
    try testing.expect(use_res.fired);
    try testing.expectEqualStrings("Courier uses Brass Horn.", use_res.text.?);
    _ = try bespoke.host.tick(&vm, &compiled);
    try testing.expect(bespoke.host.speech_this_tick(&world, &vm, &speech_buf) == null);

    // 3. Unhandled LOOK with only the default entity name shows "Nothing happens.", not redundant "OakChest: OakChest".
    const default_look = try runner_act(&world, &vm, &compiled, courier, .look_at, chest, "OakChest", bespoke.EntityId.none, &narration_buf, &fallback_buf);
    try testing.expect(!default_look.fired);
    try testing.expectEqualStrings("Nothing happens.", default_look.text.?);

    // 4. Unhandled LOOK with distinct custom examine text displays it.
    const custom_look = try runner_act(&world, &vm, &compiled, courier, .look_at, chest, "An iron-bound travelling chest.", bespoke.EntityId.none, &narration_buf, &fallback_buf);
    try testing.expect(!custom_look.fired);
    try testing.expectEqualStrings("Oak Chest: \"An iron-bound travelling chest.\"", custom_look.text.?);

    // 5. Unhandled TAKE falls back cleanly to "Nothing happens."
    const unhandled_take = try runner_act(&world, &vm, &compiled, courier, .pick_up, chest, null, bespoke.EntityId.none, &narration_buf, &fallback_buf);
    try testing.expect(!unhandled_take.fired);
    try testing.expectEqualStrings("Nothing happens.", unhandled_take.text.?);
}

test "P49-06: compile --deps lists the script, its includes, and its images, escaping spaces" {
    const testing = std.testing;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    // A folder with a space in its name: Make and Zig's dependency reader split on spaces.
    try tmp.dir.createDirPath(testing.io, "my game/rooms");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "my game/main.bespoke", .data = "include \"rooms/yard.bespoke\"\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "my game/rooms/yard.bespoke", .data = "scene Yard:\n  cast: Walker\n  marks: Gate\n" });
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const script = try std.fs.path.join(testing.allocator, &.{ root, "my game", "main.bespoke" });
    defer testing.allocator.free(script);
    const package = try std.fs.path.join(testing.allocator, &.{ root, "game.bspk" });
    defer testing.allocator.free(package);
    const deps = try std.fs.path.join(testing.allocator, &.{ root, "game.d" });
    defer testing.allocator.free(deps);

    var discard_buf: [256]u8 = undefined;
    var discarding: std.Io.Writer.Discarding = .init(&discard_buf);
    try compile_file_with(testing.allocator, testing.io, script, package, &discarding.writer, .{ .deps = deps });

    const text = try tmp.dir.readFileAlloc(testing.io, "game.d", testing.allocator, .limited(4096));
    defer testing.allocator.free(text);
    const expected = try std.fmt.allocPrint(testing.allocator, "{s}/game.bspk: \\\n  {s}/my\\ game/main.bespoke \\\n  {s}/my\\ game/rooms/yard.bespoke\n", .{ root, root, root });
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, text);

    // Without --deps nothing is written.
    try tmp.dir.deleteFile(testing.io, "game.d");
    try compile_file(testing.allocator, testing.io, script, package, &discarding.writer);
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "game.d", .{}));
}

test "P49-06: dependency paths escape the characters Make reads specially" {
    const testing = std.testing;
    var storage: [128]u8 = undefined;
    var out: std.Io.Writer = .fixed(&storage);
    try write_dep_rule(&out, "out.bspk", &.{ "a b#c\\d$e.png" });
    try testing.expectEqualStrings("out.bspk: \\\n  a\\ b\\#c\\\\d$$e.png\n", out.buffered());
}
