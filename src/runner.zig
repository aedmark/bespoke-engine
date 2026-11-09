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
        if (res.diagnostic) |d| {
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
        if (res.diagnostic) |d| {
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
            if (res.diagnostic) |d| {
                try stdout.print("{s}:{d}:{d}: error: {s}\n", .{ path, d.line, d.column, d.message });
            } else {
                try stdout.print("{s}: error: compilation failed ({s})\n", .{ path, @errorName(err) });
            }
            return err;
        };
    }
    defer compiled.deinit();

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
            try vm.step_tick();
            _ = try vm.dispatch_pending_weaves(&compiled);
        }
    }

    // 2. Auto-register spatial actors on marks if waypoints exist
    const default_wp = if (spatial.graph.waypoints.items.len > 0)
        spatial.graph.waypoints.items[0].id
    else
        null;

    var player_entity: ?bespoke.EntityId = null;

    // 3. Spawn all defined routines for their declared actors
    var r_it = compiled.routine_entries.iterator();
    while (r_it.next()) |entry| {
        const rname = entry.key_ptr.*;
        const rpc = entry.value_ptr.*;
        const actor_name = compiled.routine_entities.get(rname) orelse "Player";
        const actor_ent = try world.intern_entity(actor_name);

        if (player_entity == null) {
            player_entity = actor_ent;
        }

        if (default_wp) |dwp| {
            if (!spatial.agents.contains(actor_ent)) {
                try spatial.register_entity(actor_ent, dwp, 10);
            }
        }

        _ = try vm.spawn_routine(actor_ent, rpc);
    }

    if (player_entity == null) {
        player_entity = try world.intern_entity("Player");
    }

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

        var tick_count: usize = 0;
        while (tick_count < config.ticks) : (tick_count += 1) {
            try vm.step_tick();
            _ = try vm.dispatch_pending_weaves(&compiled);

            var snap = std.ArrayList(u8).init(allocator);
            try world.save_state(snap.writer());
            try history_snapshots.append(snap);

            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();

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

        try stdout.print("\n>>> OPENED GRAPHICAL DISPLAY WINDOW (1280x720) <<<\n", .{});
        try stdout.print("   - [Left Click Waypoint]: Direct actor to walk\n", .{});
        try stdout.print("   - [Left Click Prop]:     Examine scene hotspot\n", .{});
        try stdout.print("   - [Space]:               Pause / Resume Simulation\n", .{});
        try stdout.print("   - [N]:                   Single-step Simulation Tick\n", .{});
        try stdout.print("   - [F1 / D]:              Toggle Debug Inspector\n", .{});
        try stdout.print("   - [Tab / ` / C]:         Toggle Live REPL Console Drawer\n", .{});
        try stdout.print("   - [Esc / Close]:         Exit\n\n", .{});

        display_bridge.capture_frame(&world, &spatial, &vm);
        display_bridge.set_max_history_tick(0);
        display_bridge.swap();

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
                    if (player_entity) |p_ent| {
                        _ = spatial.walk_to(p_ent, wp_id) catch {};
                        window.set_cue_banner("Directing actor to mark", 60);
                    }
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
                try vm.step_tick();
                _ = try vm.dispatch_pending_weaves(&compiled);

                var snap = std.ArrayList(u8).init(allocator);
                try world.save_state(snap.writer());
                try history_snapshots.append(snap);

                display_bridge.capture_frame(&world, &spatial, &vm);
                display_bridge.set_max_history_tick(world.current_tick);
                display_bridge.swap();
            }

            window.render_frame(display_bridge.get_frame(), is_paused);
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }
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
