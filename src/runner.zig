const std = @import("std");
const bespoke = @import("root.zig");

const World = bespoke.World;
const SpatialSystem = bespoke.SpatialSystem;
const VM = bespoke.VM;
const DisplayBridge = bespoke.DisplayBridge;
const Repl = bespoke.Repl;
const CompiledProgram = bespoke.CompiledProgram;

pub const RunConfig = struct {
    ticks: usize = 20,
    is_headless: bool = false,
    verbose: bool = true,
};

/// Validates syntax and semantics of a .bespoke scenario file (P15-03, D-018).
pub fn check_file(allocator: std.mem.Allocator, path: []const u8, stdout: anytype) !bool {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        try stdout.print("{s}: error: cannot open file ({s})\n", .{ path, @errorName(err) });
        return false;
    };
    defer file.close();

    const max_size: usize = 16 * 1024 * 1024;
    const source = file.readToEndAlloc(allocator, max_size) catch |err| {
        try stdout.print("{s}: error: failed to read file ({s})\n", .{ path, @errorName(err) });
        return false;
    };
    defer allocator.free(source);

    const res = bespoke.check_source(allocator, source);
    if (res.is_valid) {
        try stdout.print("[check] '{s}': syntax and semantics valid ({d} scene(s), {d} routine(s), {d} reactive rule(s), {d} bytes bytecode)\n", .{
            path,
            res.scene_count,
            res.routine_count,
            res.rule_count,
            res.bytecode_len,
        });
        return true;
    } else {
        if (res.diagnostic()) |d| {
            try stdout.print("{s}:{d}:{d}: error: {s}\n", .{ path, d.line, d.column, d.message });
        } else {
            try stdout.print("{s}: error: compilation failed\n", .{path});
        }
        return false;
    }
}

/// Compiles a .bespoke source file to a standalone .bspk binary package (P15-02, D-018).
pub fn compile_file(
    allocator: std.mem.Allocator,
    in_path: []const u8,
    out_path: []const u8,
    stdout: anytype,
) !void {
    const file = try std.fs.cwd().openFile(in_path, .{});
    defer file.close();

    const max_size: usize = 16 * 1024 * 1024;
    const source = try file.readToEndAlloc(allocator, max_size);
    defer allocator.free(source);

    var world = try World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = bespoke.compile_source(allocator, &world, &spatial, source) catch |err| {
        const res = bespoke.check_source(allocator, source);
        if (res.diagnostic()) |d| {
            try stdout.print("{s}:{d}:{d}: error: {s}\n", .{ in_path, d.line, d.column, d.message });
        } else {
            try stdout.print("{s}: error: compilation failed ({s})\n", .{ in_path, @errorName(err) });
        }
        return err;
    };
    defer compiled.deinit();

    try bespoke.save_package_file(allocator, out_path, &compiled, &world, &spatial);

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
    path: []const u8,
    config: RunConfig,
    stdout: anytype,
) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const max_size: usize = 32 * 1024 * 1024;
    const data = try file.readToEndAlloc(allocator, max_size);
    defer allocator.free(data);

    var world = try World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = SpatialSystem.init(allocator);
    defer spatial.deinit();

    const is_binary = (data.len >= 4 and std.mem.eql(u8, data[0..4], &bespoke.package.PACKAGE_MAGIC));

    var compiled: CompiledProgram = undefined;
    if (is_binary) {
        if (config.verbose) try stdout.print("[Runner] Loading precompiled binary package '{s}'...\n", .{path});
        var stream = std.io.fixedBufferStream(data);
        compiled = try bespoke.load_package(allocator, stream.reader(), &world, &spatial);
    } else {
        if (config.verbose) try stdout.print("[Runner] Compiling narrative script '{s}'...\n", .{path});
        compiled = bespoke.compile_source(allocator, &world, &spatial, data) catch |err| {
            const res = bespoke.check_source(allocator, data);
            if (res.diagnostic()) |d| {
                try stdout.print("{s}:{d}:{d}: error: {s}\n", .{ path, d.line, d.column, d.message });
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

    // 1. Execute initial top-level declarative statements if compiled
    if (compiled.initial_entry) |init_pc| {
        const root_ent = try world.intern_entity("SimulationRoot");
        const f_init = try vm.spawn_routine(root_ent, init_pc);
        while (f_init <= vm.fibers.items.len and vm.fibers.items[f_init - 1].state != .halted) {
            _ = try bespoke.host.tick(&vm, &compiled);
        }
    }

    // 2. Auto-register spatial actors on marks if waypoints exist
    const default_wp = if (spatial.graph.waypoints.items.len > 0)
        spatial.graph.waypoints.items[0].id
    else
        null;

    // 3. Spawn all defined routines for their declared actors
    var r_it = compiled.routine_entries.iterator();
    while (r_it.next()) |entry| {
        const rname = entry.key_ptr.*;
        const rpc = entry.value_ptr.*;
        const actor_name = compiled.routine_entities.get(rname) orelse "Player";
        const actor_ent = try world.intern_entity(actor_name);

        if (default_wp) |dwp| {
            if (!spatial.agents.contains(actor_ent)) {
                try spatial.register_entity(actor_ent, dwp, 10);
            }
        }

        _ = try vm.spawn_routine(actor_ent, rpc);
    }

    // The window's clicks and typed commands act for one actor, chosen from the script so the
    // choice is the same on every run (P29-02, D-064).
    const player_entity = try world.intern_entity(player_actor(&compiled) orelse "Player");

    var display_bridge = DisplayBridge.init();
    var repl_instance = Repl.init(&world, &spatial, &vm);

    var history_snapshots = std.ArrayList(std.ArrayList(u8)).init(allocator);
    defer {
        for (history_snapshots.items) |*buf| buf.deinit();
        history_snapshots.deinit();
    }

    if (config.is_headless) {
        try stdout.print("\n>>> STARTING SIMULATION CLOCK (Headless Mode, {d} ticks) <<<\n", .{config.ticks});

        // Capture initial frame 0
        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.swap();

        var snap0 = std.ArrayList(u8).init(allocator);
        try world.save_state(snap0.writer());
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

            var snap = std.ArrayList(u8).init(allocator);
            try world.save_state(snap.writer());
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
            var stream = std.io.fixedBufferStream(rewind_snap.items);
            try world.restore_state(stream.reader());
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
            try stdout.print("Rewound Simulation Clock Restored: Tick {d}\n", .{world.current_tick});
        }
    } else {
        var window = try bespoke.display.DisplayWindow.init("BeSpoke Engine - Standalone Scenario Runner", 1280, 720);
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
        var interp = bespoke.command.Interpreter{};

        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.set_max_history_tick(0);
        display_bridge.swap();
        bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);

        var snap0 = std.ArrayList(u8).init(allocator);
        try world.save_state(snap0.writer());
        try history_snapshots.append(snap0);

        var is_paused = false;
        var last_tick_time = std.time.milliTimestamp();

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
                        var stream = std.io.fixedBufferStream(target_snapshot.items);
                        try world.restore_state(stream.reader());
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
                        var stream = std.io.fixedBufferStream(target_snapshot.items);
                        try world.restore_state(stream.reader());
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
                        var snap = std.ArrayList(u8).init(allocator);
                        try world.save_state(snap.writer());
                        try history_snapshots.append(snap);
                    }
                    display_bridge.capture_frame(&world, &spatial, &vm);
                    display_bridge.set_max_history_tick(history_snapshots.items.len - 1);
                    display_bridge.swap();
                },
                else => {},
            }

            const now = std.time.milliTimestamp();
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

                var snap = std.ArrayList(u8).init(allocator);
                try world.save_state(snap.writer());
                try history_snapshots.append(snap);

                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.set_max_history_tick(world.current_tick);
                display_bridge.swap();
                bespoke.host.command_words(&vm, &compiled, player_entity, &window.command_words);
            }

            window.render_frame(display_bridge.get_frame(), is_paused);
            std.time.sleep(16 * std.time.ns_per_ms);
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

/// The actor the stock window acts for: the actor of the first top-level routine in source
/// order (P29-02, D-064). Routines compile in source order, so the lowest entry wins; this holds
/// for packages too, which keep entry addresses. Path initializers are skipped; path routines
/// compile after every top-level routine, so they are chosen only when no top-level routine
/// exists. Null when the script declares no routine.
pub fn player_actor(compiled: *const CompiledProgram) ?[]const u8 {
    var best_pc: usize = std.math.maxInt(usize);
    var best: ?[]const u8 = null;
    var it = compiled.routine_entries.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        if (std.mem.startsWith(u8, name, bespoke.compiler.codegen.PATH_ROUTINE_PREFIX)) continue;
        if (entry.value_ptr.* >= best_pc) continue;
        best_pc = entry.value_ptr.*;
        best = compiled.routine_entities.get(name);
    }
    return best;
}

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

    const tmp_script = "/tmp/test_runner_script.bespoke";
    const tmp_pkg = "/tmp/test_runner_script.bspk";
    defer {
        std.fs.cwd().deleteFile(tmp_script) catch {};
        std.fs.cwd().deleteFile(tmp_pkg) catch {};
    }

    // Write source file
    {
        const f = try std.fs.cwd().createFile(tmp_script, .{});
        defer f.close();
        try f.writeAll(script_content);
    }

    // Test check_file
    const null_writer = std.io.null_writer;
    const is_valid = try check_file(testing.allocator, tmp_script, null_writer);
    try testing.expect(is_valid);

    // Test compile_file
    try compile_file(testing.allocator, tmp_script, tmp_pkg, null_writer);

    // Verify .bspk exists and has valid magic
    const pkg_file = try std.fs.cwd().openFile(tmp_pkg, .{});
    defer pkg_file.close();
    var magic_buf: [4]u8 = undefined;
    _ = try pkg_file.readAll(&magic_buf);
    try testing.expectEqualStrings("BSPB", &magic_buf);

    // Test run_file on source in headless mode
    try run_file(testing.allocator, tmp_script, .{ .ticks = 5, .is_headless = true, .verbose = false }, null_writer);

    // Test run_file on compiled binary package in headless mode
    try run_file(testing.allocator, tmp_pkg, .{ .ticks = 5, .is_headless = true, .verbose = false }, null_writer);
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
