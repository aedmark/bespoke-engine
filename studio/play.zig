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

comptime {
    // The command bar as `bespoke init` games have it (D-057), so a typed game plays here too.
    wasm.export_runtime(&[_]wasm.Deck{.{ .title = "STUDIO PLAY", .load = load, .command_bar = true }});
}
