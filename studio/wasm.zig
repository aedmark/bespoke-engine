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

/// Builds the script at the given table path into a `.bspk` package for the play window
/// (P47-06, D-195). Returns 1 with the package ready, 0 for a diagnostic (the check's JSON is
/// in the result buffer, as after `studio_check`), and -1 when the build could not run.
export fn studio_build(path_ptr: [*]const u8, path_len: usize) i32 {
    const ok = project.build(path_ptr[0..path_len]) catch return -1;
    return if (ok) 1 else 0;
}

export fn studio_package_ptr() [*]const u8 {
    return project.package.items.ptr;
}

export fn studio_package_len() usize {
    return project.package.items.len;
}

/// Lists the art of the script at the given path as JSON in the result buffer (P47-02,
/// D-196). 1 listed, 0 the script does not parse (the check's JSON is there instead), -1 out
/// of memory.
export fn studio_art(path_ptr: [*]const u8, path_len: usize) i32 {
    const ok = project.art(path_ptr[0..path_len]) catch return -1;
    return if (ok) 1 else 0;
}

/// Decodes the project PNG at the given path with the engine's reader into the blob as RGBA.
/// 1 decoded, 0 missing or unreadable, -1 out of memory.
export fn studio_pixels(path_ptr: [*]const u8, path_len: usize) i32 {
    const ok = project.pixels(path_ptr[0..path_len]) catch return -1;
    return if (ok) 1 else 0;
}

/// Encodes `width` x `height` RGBA pixels as a PNG into the blob, checked through the engine's
/// decoder. 1 encoded; 0 refused, with the reason's name in the result buffer.
export fn studio_encode(width: u32, height: u32, ptr: [*]const u8, len: usize) i32 {
    project.encode(width, height, ptr[0..len]) catch |err| {
        project.result.clearRetainingCapacity();
        project.result.appendSlice(allocator, @errorName(err)) catch {};
        return 0;
    };
    return 1;
}

/// Adds a new image to the project (P47-10, D-197): the PNG at `file` (relative to the main
/// script's folder) and one `image` line in `script`, checked together. 1 added, 0 refused
/// (JSON in the result buffer says why), -1 out of memory.
export fn studio_add_image(
    main_ptr: [*]const u8,
    main_len: usize,
    script_ptr: [*]const u8,
    script_len: usize,
    name_ptr: [*]const u8,
    name_len: usize,
    file_ptr: [*]const u8,
    file_len: usize,
    frame_width: u32,
    frame_height: u32,
    png_ptr: [*]const u8,
    png_len: usize,
) i32 {
    const ok = project.add_image(main_ptr[0..main_len], .{
        .script = script_ptr[0..script_len],
        .name = name_ptr[0..name_len],
        .file = file_ptr[0..file_len],
        .frame_width = frame_width,
        .frame_height = frame_height,
        .png = png_ptr[0..png_len],
    }) catch return -1;
    return if (ok) 1 else 0;
}

/// Lists the main script's scenes and room blocks as JSON in the result buffer (P47-03,
/// D-200). 1 listed, 0 the script does not parse (the check's JSON instead), -1 out of memory.
export fn studio_rooms(main_ptr: [*]const u8, main_len: usize) i32 {
    const ok = project.rooms(main_ptr[0..main_len]) catch return -1;
    return if (ok) 1 else 0;
}

/// Writes one scene's room block from a JSON edit and checks the project. 1 written, 0
/// refused (JSON in the result buffer says why), -1 out of memory.
export fn studio_write_room(main_ptr: [*]const u8, main_len: usize, edit_ptr: [*]const u8, edit_len: usize) i32 {
    const ok = project.write_room(main_ptr[0..main_len], edit_ptr[0..edit_len]) catch |err| switch (err) {
        error.UnwritableName => {
            _ = project.refuse_room("a name holds a double quote, which a room line cannot write") catch return -1;
            return 0;
        },
        else => return -1,
    };
    return if (ok) 1 else 0;
}

/// Lists the main script's cast, display names, axes, starting values, and code as JSON in the
/// result buffer (P47-05, D-202). 1 listed, 0 the check's JSON instead, -1 out of memory.
export fn studio_cast(main_ptr: [*]const u8, main_len: usize) i32 {
    const ok = project.cast(main_ptr[0..main_len]) catch return -1;
    return if (ok) 1 else 0;
}

/// Writes one cast edit record and checks the project. 1 written, 0 refused (JSON says why),
/// -1 out of memory.
export fn studio_write_cast(main_ptr: [*]const u8, main_len: usize, edit_ptr: [*]const u8, edit_len: usize) i32 {
    const ok = project.write_cast(main_ptr[0..main_len], edit_ptr[0..edit_len]) catch |err| switch (err) {
        error.UnwritableName => {
            _ = project.refuse_room("a name holds a double quote, which a script line cannot write") catch return -1;
            return 0;
        },
        else => return -1,
    };
    return if (ok) 1 else 0;
}

/// Copies the table's bytes for `path` into the blob, so the page reads back a script the
/// module edited. 1 found, 0 not in the table.
export fn studio_file(path_ptr: [*]const u8, path_len: usize) i32 {
    const bytes = project.find(path_ptr[0..path_len]) orelse return 0;
    project.blob.clearRetainingCapacity();
    project.blob.appendSlice(allocator, bytes) catch return -1;
    return 1;
}

export fn studio_blob_ptr() [*]const u8 {
    return project.blob.items.ptr;
}

export fn studio_blob_len() usize {
    return project.blob.items.len;
}

export fn studio_blob_width() u32 {
    return project.blob_width;
}

export fn studio_blob_height() u32 {
    return project.blob_height;
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
