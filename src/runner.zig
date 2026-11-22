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
        return std.Io.Dir.cwd().readFileAlloc(self.io, full, allocator, .limited(bespoke.png.MAX_FILE));
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

    const width: usize = if (existing.codes.len > 0) existing.codes[0].len else if (palette.items.len <= 94) 1 else 2;
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
};

/// Validates syntax and semantics of a .bespoke scenario file (P15-03, D-018).
pub fn check_file(allocator: std.mem.Allocator, io: std.Io, path: []const u8, stdout: anytype) !bool {
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
        try write_script_diagnostic(stdout, path, source, &res);
        return false;
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
    const max_size = bespoke.compiler.MAX_SOURCE_SIZE;
    const source = try std.Io.Dir.cwd().readFileAlloc(io, in_path, allocator, .limited(max_size));
    defer allocator.free(source);

    var world = try World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = SpatialSystem.init(allocator);
    defer spatial.deinit();

    var files = ScriptFiles.for_script(io, in_path);
    var compiled = bespoke.compiler.compile_source_with(allocator, &world, &spatial, source, files.source()) catch |err| {
        const res = bespoke.compiler.check_source_with(allocator, source, files.source());
        if (!res.is_valid) {
            try write_script_diagnostic(stdout, in_path, source, &res);
        } else {
            try stdout.print("{s}: error: compilation failed ({s})\n", .{ in_path, @errorName(err) });
        }
        return err;
    };
    defer compiled.deinit();

    try bespoke.save_package_file(allocator, io, out_path, &compiled, &world, &spatial);

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

    const is_binary = (data.len >= 4 and std.mem.eql(u8, data[0..4], &bespoke.package.PACKAGE_MAGIC));

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
            return err;
        };
    } else {
        if (config.verbose) try stdout.print("[Runner] Compiling narrative script '{s}'...\n", .{path});
        compiled = bespoke.compiler.compile_source_with(allocator, &world, &spatial, data, files) catch |err| {
            const res = bespoke.compiler.check_source_with(allocator, data, files);
            if (!res.is_valid) {
                try write_script_diagnostic(stdout, path, data, &res);
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

    // Top-level statements, the cast in its scenes, then every routine (P29-03, D-066). The
    // window's clicks and typed commands act for the returned player (D-064).
    const player_entity = try bespoke.host.start_script(&world, &spatial, &vm, &compiled);

    var display_bridge = DisplayBridge.init();
    var repl_instance = Repl.init(&world, &spatial, &vm);

    var history_snapshots = std.array_list.Managed(std.array_list.Managed(u8)).init(allocator);
    defer {
        for (history_snapshots.items) |*buf| buf.deinit();
        history_snapshots.deinit();
    }

    if (!desktop or config.is_headless) {
        try stdout.print("\n>>> STARTING SIMULATION CLOCK (Headless Mode, {d} ticks) <<<\n", .{config.ticks});

        // Capture initial frame 0
        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.swap();

        var snap0 = std.array_list.Managed(u8).init(allocator);
        var lw1 = ListWriter.init(&snap0);
        try world.save_state(&lw1.writer);
        try history_snapshots.append(snap0);

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

        var tick_count: usize = 0;
        while (tick_count < config.ticks) : (tick_count += 1) {
            _ = try bespoke.host.tick(&vm, &compiled);
            try story.report(&world, &vm, stdout);

            var snap = std.array_list.Managed(u8).init(allocator);
            var lw2 = ListWriter.init(&snap);
            try world.save_state(&lw2.writer);
            try history_snapshots.append(snap);

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

        try stdout.print("\n===================================================================\n", .{});
        try stdout.print("Simulation Finished at Tick {d}:\n", .{world.current_tick});
        try stdout.print("   - Total Facts Stored:  {d}\n", .{world.fact_count()});
        try stdout.print("   - Active Fibers:       {d}\n", .{vm.fibers.items.len});
        try stdout.print("===================================================================\n\n", .{});

        // Time-travel rewind verification
        if (history_snapshots.items.len > 2) {
            try stdout.print(">>> DEMONSTRATING TIME-TRAVEL REWIND: REWINDING TO TICK 2 <<<\n", .{});
            const rewind_snap = history_snapshots.items[2];
            var stream: std.Io.Reader = .fixed(rewind_snap.items);
            try world.restore_state(&stream);
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
        var interp = bespoke.command.Interpreter{};

        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.set_max_history_tick(0);
        display_bridge.swap();
        bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);

        var snap0 = std.array_list.Managed(u8).init(allocator);
        var lw3 = ListWriter.init(&snap0);
        try world.save_state(&lw3.writer);
        try history_snapshots.append(snap0);

        var is_paused = false;
        var last_tick_time = std.Io.Timestamp.now(io, .awake).toMilliseconds();

        window.set_cue_banner("BeSpoke Engine: Scenario Loaded. Left-click waypoints to navigate.", 90);

        while (true) {
            const action = window.poll_events(display_bridge.get_frame());
            var should_step_now = false;

            _ = window.handle_save_action(action, &world, &spatial, &vm, &display_bridge, &is_paused);
            switch (action) {
                .quit => break,
                .toggle_pause => {
                    is_paused = !is_paused;
                },
                .step_tick => {
                    should_step_now = true;
                },
                .walk_player => |wp_id| {
                    _ = spatial.walk_to(player_entity, wp_id) catch {};
                    window.set_cue_banner("Directing actor to mark", 60);
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
                    if (reply.fired) should_step_now = true;
                    bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);
                },
                .examine_hotspot => |hs_idx| {
                    const frame = display_bridge.get_frame();
                    if (hs_idx < frame.hotspot_count) {
                        const hs = frame.hotspots[hs_idx];
                        var banner_buf: [256]u8 = undefined;
                        const text = std.fmt.bufPrint(&banner_buf, "{s}: \"{s}\"", .{ hs.get_name(), hs.get_examine_text() }) catch "Examined";
                        window.set_cue_banner(text, 120);
                    }
                },
                .rewind => {
                    if (history_snapshots.items.len > 2) {
                        is_paused = true;
                        const target_snapshot = history_snapshots.items[2];
                        var stream: std.Io.Reader = .fixed(target_snapshot.items);
                        try world.restore_state(&stream);
                        display_bridge.capture_frame(&world, &spatial, &vm);
                        display_bridge.set_max_history_tick(history_snapshots.items.len - 1);
                        display_bridge.swap();
                        window.set_cue_banner("<<< REWOUND TO TICK 2 (PAUSED) <<<", 90);
                    }
                },
                .scrub_to_tick => |target_tick| {
                    if (history_snapshots.items.len > 0) {
                        const clamped = @min(target_tick, history_snapshots.items.len - 1);
                        is_paused = true;
                        const target_snapshot = history_snapshots.items[clamped];
                        var stream: std.Io.Reader = .fixed(target_snapshot.items);
                        try world.restore_state(&stream);
                        display_bridge.capture_frame(&world, &spatial, &vm);
                        display_bridge.set_max_history_tick(history_snapshots.items.len - 1);
                        display_bridge.swap();

                        var banner_buf: [96]u8 = undefined;
                        const text = std.fmt.bufPrint(&banner_buf, "<<< TIME-TRAVEL: SCRUBBED TO TICK {d} (PAUSED) <<<", .{world.current_tick}) catch "Scrubbed";
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
                    if (world.current_tick >= history_snapshots.items.len) {
                        var snap = std.array_list.Managed(u8).init(allocator);
                        var lw4 = ListWriter.init(&snap);
                        try world.save_state(&lw4.writer);
                        try history_snapshots.append(snap);
                    }
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.set_max_history_tick(history_snapshots.items.len - 1);
                    display_bridge.swap();
                },
                else => {},
            }

            const now = std.Io.Timestamp.now(io, .awake).toMilliseconds();
            if (!is_paused and (now - last_tick_time >= window.current_tick_interval_ms)) {
                should_step_now = true;
                last_tick_time = now;
            }

            if (should_step_now) {
                _ = try bespoke.host.tick(&vm, &compiled);
                // The window draws script speech only from a banner, so each tick's `say`
                // lines are passed to it here (P29-02, D-064).
                var speech_buf: [256]u8 = undefined;
                if (bespoke.host.speech_this_tick(&world, &vm, &speech_buf)) |line| window.set_cue_banner(line, 160);

                var snap = std.array_list.Managed(u8).init(allocator);
                var lw5 = ListWriter.init(&snap);
                try world.save_state(&lw5.writer);
                try history_snapshots.append(snap);

                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.set_max_history_tick(world.current_tick);
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
            const name = world.get_entity_name(bespoke.EntityId.from_int(cue.args[0])) orelse "Someone";
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
    try testing.expectEqualStrings("BSPB", head);

    // Test run_file on source in headless mode
    try run_file(testing.allocator, testing.io, tmp_script, .{ .ticks = 5, .is_headless = true, .verbose = false }, null_writer);

    // Test run_file on compiled binary package in headless mode
    try run_file(testing.allocator, testing.io, tmp_pkg, .{ .ticks = 5, .is_headless = true, .verbose = false }, null_writer);
}

test "P38-02: runner reports the package version and supported range" {
    const testing = std.testing;
    const unsupported = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "tests/fixtures/compat/v0.1.0-package-v14.bspk",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(unsupported);
    std.mem.writeInt(u32, unsupported[4..8], bespoke.package.PACKAGE_VERSION + 1, .little);

    var output_buf: [256]u8 = undefined;
    var output: std.Io.Writer = .fixed(&output_buf);
    try testing.expectError(
        error.UnsupportedPackageVersion,
        run_bytes(testing.allocator, testing.io, "future.bspk", unsupported, .{
            .ticks = 0,
            .is_headless = true,
            .verbose = false,
        }, &output),
    );
    try testing.expectEqualStrings(
        "future.bspk: error: unsupported .bspk format version 26; this engine supports versions 1 through 25\n",
        output.buffered(),
    );
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

test "P46-04: a script compiled from its file reads the PNGs beside it onto its palette" {
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
    // The declared red is reused; the badge adds yellow and blue, the lamp three more.
    try testing.expectEqual(@as(usize, 7), art.palette.len);
    try testing.expectEqual(bespoke.image.Colour{ .r = 240, .g = 220, .b = 60 }, art.palette[2]);
    try testing.expectEqualSlices(u8, &.{ 0, 1, 1, 1, 1, 0 }, art.find("BadgeSheet").?.pixels[0..6]);
    try testing.expectEqual(@as(u32, 2), art.find("LampSheet").?.frame_count());
    try testing.expectEqual(@as(u16, 1), art.sprite_for(world.lookup_entity("Curator").?).?.frame_at(.idle, 10));

    // Without the command line's file source, the same script is told where it can be read.
    const check = bespoke.check_source(testing.allocator, source);
    try testing.expect(!check.is_valid);
    try testing.expectEqualStrings("image 'BadgeSheet' reads \"rgba.png\", which only a compile from the command line can do; 'bespoke import' writes its rows into the script instead", check.message());
    try testing.expectEqual(@as(u32, 11), check.line);
}

test "P46-04: a script cannot read a file outside its folder, and a missing or bad file is named" {
    const testing = std.testing;
    var files = ScriptFiles.for_script(testing.io, "tests/fixtures/png/gallery.bespoke");
    const Case = struct { file: []const u8, message: []const u8 };
    const cases = [_]Case{
        .{ .file = "../compat/v0.4.0-package-v24.bspk", .message = "image 'Art' cannot read \"../compat/v0.4.0-package-v24.bspk\" (PathOutsideScriptFolder)" },
        .{ .file = "/etc/hostname", .message = "image 'Art' cannot read \"/etc/hostname\" (PathOutsideScriptFolder)" },
        .{ .file = "missing.png", .message = "image 'Art' cannot read \"missing.png\" (FileNotFound)" },
        .{ .file = "interlaced.png", .message = "image 'Art' cannot use \"interlaced.png\": it is interlaced; save it without interlacing" },
        .{ .file = "partial_alpha.png", .message = "image 'Art': pixel (1, 0) of \"partial_alpha.png\" is partly transparent; art pixels are opaque or fully transparent (D-152)" },
        .{ .file = "too_many_colours.png", .message = "image 'Art': \"too_many_colours.png\" brings the palette past 256 colours at pixel (0, 15) (D-152)" },
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
    try testing.expect(try import_art(testing.allocator, testing.io, "tests/fixtures/png/rgba.png", .{ .name = "Badge", .script = "tests/fixtures/png/gallery.bespoke" }, &out.writer));
    try testing.expect(std.mem.startsWith(u8, out.written(), "# Add these lines to the script's palette:\n  \"a\" 240 220 60\n  \"b\" 30 30 90\n"));
    try testing.expect(std.mem.endsWith(u8, out.written(), "image Badge:\n  \".rrrr.\"\n  \"rabbar\"\n  \"raaaar\"\n  \".rrrr.\"\n"));

    // The written block compiles back to the same pixels.
    out.clearRetainingCapacity();
    try testing.expect(try import_art(testing.allocator, testing.io, "tests/fixtures/png/rgba.png", .{ .name = "Badge" }, &out.writer));
    var world = try World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, null, out.written());
    defer compiled.deinit();
    try testing.expectEqualSlices(u8, &.{ 0, 1, 1, 1, 1, 0, 1, 2, 3, 3, 2, 1 }, compiled.art.find("Badge").?.pixels[0..12]);

    // More colours than the palette holds is refused, by name.
    out.clearRetainingCapacity();
    try testing.expect(!try import_art(testing.allocator, testing.io, "tests/fixtures/png/too_many_colours.png", .{ .name = "Swatch" }, &out.writer));
    try testing.expectEqualStrings("error: 'tests/fixtures/png/too_many_colours.png' brings the palette past 256 colours at pixel (0, 15)\n", out.written());
}
