//! The Studio's WebAssembly exports (P47-01, D-192). The page passes each project file in as
//! raw bytes, asks for a check of one script, and reads the result back as JSON. This module is
//! Studio code against the supported `bespoke.compiler` surface; it adds nothing to the
//! engine's own browser module (D-031, D-192 item 4).
const std = @import("std");
const bespoke = @import("bespoke");
const Project = @import("project.zig").Project;

const allocator = std.heap.wasm_allocator;
var project: Project = .{ .allocator = allocator };

/// A buffer the page fills before a call; the page frees it with `studio_free`.
export fn studio_alloc(len: usize) ?[*]u8 {
    const buf = allocator.alloc(u8, len) catch return null;
    return buf.ptr;
}

export fn studio_free(ptr: [*]u8, len: usize) void {
    allocator.free(ptr[0..len]);
}

export fn studio_reset() void {
    project.clear();
}

/// Copies one file into the project table; false for a path the table refuses or no memory.
export fn studio_add_file(path_ptr: [*]const u8, path_len: usize, data_ptr: [*]const u8, data_len: usize) bool {
    project.add(path_ptr[0..path_len], data_ptr[0..data_len]) catch return false;
    return true;
}

export fn studio_file_count() usize {
    return project.files.items.len;
}

/// Checks the script at the given table path. Returns 1 for valid, 0 for a diagnostic, and
/// -1 when the check could not run at all (out of memory), which the page treats as a failed
/// mode and answers with its workspace screen (D-192 item 5).
export fn studio_check(path_ptr: [*]const u8, path_len: usize) i32 {
    const ok = project.check(path_ptr[0..path_len]) catch return -1;
    return if (ok) 1 else 0;
}

export fn studio_result_ptr() [*]const u8 {
    return project.result.items.ptr;
}

export fn studio_result_len() usize {
    return project.result.items.len;
}

/// The engine's 5x7 glyph for code point `cp` (D-192 item 7), packed as five column bytes in
/// bits 0..39, with bit 40 set when the font paints the code point and bit 41 set when it falls
/// back to the placeholder. `tools/build_studio.py` reads every glyph through this export once
/// and bakes the table into the page, so the page draws text before (and without) this module,
/// which the workspace screen needs when the module fails to load (D-192 item 5). `display.font`
/// is an internal engine declaration; reading it here, at build time only, keeps `font.zig` the
/// one source of the face, and `build_studio.py --check` reports a stale page when it changes.
export fn studio_glyph(cp: u32) u64 {
    const font = bespoke.display.font;
    if (cp > 0x10FFFF) return 0;
    const glyph = font.glyph_for(@intCast(cp)) orelse return 0;
    var packed_cols: u64 = 0;
    for (glyph, 0..) |col, i| packed_cols |= @as(u64, col) << @intCast(i * 8);
    const placeholder = font.glyph_for(font.PLACEHOLDER).?;
    const is_placeholder = cp != font.PLACEHOLDER and std.mem.eql(u8, &glyph, &placeholder);
    return packed_cols | (@as(u64, 1) << 40) | (@as(u64, @intFromBool(is_placeholder)) << 41);
}

/// The Studio checks projects as `bespoke check` does, `image X from "<file>.png"` included,
/// so it opts in to the compiler's PNG path on this freestanding build (D-193). A game's
/// browser runtime declares nothing here and keeps D-151: it never decodes PNG.
pub const bespoke_reads_image_files = true;
