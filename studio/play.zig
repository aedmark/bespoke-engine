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

fn load(rt: *wasm.WasmRuntime) anyerror!void {
    failure = "";
    if (handed.len == 0) {
        failure = "NoPackage";
        return error.NoPackage;
    }
    rt.load_package_bytes(handed) catch |err| {
        failure = @errorName(err);
        return err;
    };
}

comptime {
    // The command bar as `bespoke init` games have it (D-057), so a typed game plays here too.
    wasm.export_runtime(&[_]wasm.Deck{.{ .title = "STUDIO PLAY", .load = load, .command_bar = true }});
}
