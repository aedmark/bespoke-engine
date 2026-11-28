//! The Studio's play module (P47-06, D-195): the engine's own browser runtime with one deck that
//! runs whatever package the page hands it. It is a module apart from the Studio's checker, so a
//! game that crashes or runs out of memory takes down only the play window, never the editor
//! the author fixes it from (D-192 item 5). It carries no compiler work of its own: the Studio
//! module builds the package, and the package already holds every included script and art
//! sheet, so this module reads no files and decodes no PNG (D-151).
const std = @import("std");
const bespoke = @import("bespoke");
const wasm = bespoke.wasm;

const allocator = std.heap.wasm_allocator;

/// The package the page last handed over. It stays until the next hand-over, so the runtime's
/// own reload (`wasm_init` again, as Run does after an edit or to restart) finds it.
var handed: []u8 = &.{};
/// Why the last load failed, as the error's name; empty after a load that worked.
var failure: []const u8 = "";

/// A buffer of `len` bytes for the page to fill with a package; it replaces the last one.
export fn play_alloc(len: usize) ?[*]u8 {
    if (handed.len > 0) allocator.free(handed);
    handed = &.{};
    const buf = allocator.alloc(u8, len) catch return null;
    handed = buf;
    return buf.ptr;
}

/// The name of the error that stopped the last `wasm_init`, for the play window's requester.
export fn play_failure_ptr() [*]const u8 {
    return failure.ptr;
}

export fn play_failure_len() usize {
    return failure.len;
}

/// The running game, for the Facts panel (P47-09, D-205). The deck's `load` gets the runtime,
/// which lives in the module's one global for as long as the game runs; `live` is cleared
/// while a load is under way and set once it succeeds.
var running: ?*wasm.WasmRuntime = null;
var live = false;
var facts_text: std.ArrayList(u8) = .empty;

/// The game's live facts as text in a buffer the page reads (`play_facts_ptr`): one per line,
/// `relation<TAB>subject<TAB>object`, the object a name or a number, empty for a one-place
/// fact. Bookkeeping relations (`#`, D-180) are left out. Returns the length, 0 when no game
/// is running or the buffer cannot grow.
export fn play_facts() usize {
    facts_text.clearRetainingCapacity();
    const rt = running orelse return 0;
    if (!live) return 0;
    const world = rt.active_world();
    var it = world.query(null, null, null);
    while (it.next()) |fact| {
        const meta = world.get_relation_meta(fact.relation) orelse continue;
        if (bespoke.reserved.is_bookkeeping(meta.name)) continue;
        const subject = world.get_entity_name(fact.subject) orelse "?";
        var number: [16]u8 = undefined;
        const object: []const u8 = switch (meta.object_kind) {
            .number => std.fmt.bufPrint(&number, "{d}", .{@as(i32, @bitCast(fact.object_or_value))}) catch "",
            else => if (fact.object_or_value == 0) "" else world.get_entity_name(bespoke.EntityId.from_int(fact.object_or_value)) orelse "",
        };
        facts_text.print(allocator, "{s}\t{s}\t{s}\n", .{ meta.name, subject, object }) catch return 0;
    }
    return facts_text.items.len;
}

export fn play_facts_ptr() [*]const u8 {
    return facts_text.items.ptr;
}

fn load(rt: *wasm.WasmRuntime) anyerror!void {
    live = false;
    running = rt;
    failure = "";
    if (handed.len == 0) {
        failure = "NoPackage";
        return error.NoPackage;
    }
    rt.load_package_bytes(handed) catch |err| {
        failure = @errorName(err);
        return err;
    };
    live = true;
}

// ------------------------------------------------------------ the text page (P47-07, D-207)
//
// An exported game in `bespoke init`'s text shell (D-191) runs deck 1: the handed package with
// the text template's transcript, scene name, and typed-command turn, as `text_web.zig.tmpl`
// writes them, minus that template's starter intro line. The shell reads these exports.

var interpreter: bespoke.command.Interpreter = .{};
var output: [8192]u8 = undefined;
var output_len: usize = 0;
var scene_buf: [128]u8 = undefined;
var scene_len: usize = 0;

export fn game_text_ptr() [*]const u8 {
    return &output;
}
export fn game_text_len() usize {
    return output_len;
}
export fn game_text_clear() void {
    output_len = 0;
}
export fn game_scene_ptr() [*]const u8 {
    return &scene_buf;
}
export fn game_scene_len() usize {
    return scene_len;
}
export fn game_has_picture() u8 {
    return 1;
}

fn append(comptime fmt: []const u8, args: anytype) void {
    const line = std.fmt.bufPrint(output[output_len..], fmt ++ "\n", args) catch return;
    output_len += line.len;
}

fn update_scene(rt: *wasm.WasmRuntime) void {
    const world = rt.active_world();
    const scene = rt.virtual_machine().current_scene orelse {
        scene_len = 0;
        return;
    };
    const text = world.display_text(scene) orelse world.get_entity_name(scene) orelse "";
    scene_len = @min(text.len, scene_buf.len);
    @memcpy(scene_buf[0..scene_len], text[0..scene_len]);
}

fn load_text(rt: *wasm.WasmRuntime) anyerror!void {
    try load(rt);
    interpreter = .{};
    output_len = 0;
    update_scene(rt);
}

fn after_text_tick(rt: *wasm.WasmRuntime) anyerror!void {
    update_scene(rt);
    var lines: [16]bespoke.host.SpeechLine = undefined;
    const count = bespoke.host.speech_lines(rt.active_world(), rt.virtual_machine(), &lines);
    for (lines[0..count]) |line| {
        if (std.mem.eql(u8, line.speaker, "Scene")) {
            append("{s}", .{line.text});
        } else append("{s}: {s}", .{ line.speaker, line.text });
    }
}

fn typed_text(rt: *wasm.WasmRuntime, line: []const u8) anyerror!void {
    const program = rt.compiled_program() orelse return;
    const actor = rt.player() orelse return;
    var reply_buf: [256]u8 = undefined;
    const reply = try bespoke.host.run_command(rt.virtual_machine(), program, &interpreter, actor, line, &reply_buf);
    if (reply.text) |text| {
        append("{s}", .{text});
        rt.set_banner(text);
    }
    if (reply.turn) {
        try rt.step_tick();
        var guard: usize = 0;
        while (rt.spatial_system().is_moving(actor) and guard < 256) : (guard += 1) {
            try rt.step_tick();
        }
    }
    update_scene(rt);
}

comptime {
    wasm.export_runtime(&[_]wasm.Deck{
        // Deck 0, the Play window and the stage page: the command bar as `bespoke init` games
        // have it (D-057), so a typed game plays here too.
        .{ .title = "STUDIO PLAY", .load = load, .command_bar = true },
        // Deck 1, the text page (D-207).
        .{ .title = "STUDIO TEXT", .load = load_text, .after_tick = after_text_tick, .on_typed = typed_text, .keyed = false },
    });
}
