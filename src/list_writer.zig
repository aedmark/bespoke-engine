//! An `std.Io.Writer` that appends to a managed byte list (P37-01).
//!
//! Zig 0.16 removed `std.array_list.Managed(u8).writer()`. The engine serializes worlds, saves,
//! packages, and snapshots into managed byte lists and reads `items` afterwards, so this keeps
//! those call sites as they were: `var lw = ListWriter.init(&bytes); try world.save_state(&lw.writer);`.
//! The writer has no buffer of its own; every write lands in the list at once, so nothing needs
//! flushing and `items` is current after each call.
const std = @import("std");

pub const ListWriter = struct {
    list: *std.array_list.Managed(u8),
    /// Pass `&lw.writer`. It finds its `ListWriter` by field address, so the `ListWriter` must
    /// stay where it was declared while the writer is in use.
    writer: std.Io.Writer,

    pub fn init(list: *std.array_list.Managed(u8)) ListWriter {
        return .{ .list = list, .writer = .{ .vtable = &.{ .drain = drain }, .buffer = &.{} } };
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *ListWriter = @alignCast(@fieldParentPtr("writer", w));
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            self.list.appendSlice(bytes) catch return error.WriteFailed;
            n += bytes.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| {
            self.list.appendSlice(last) catch return error.WriteFailed;
            n += last.len;
        }
        return n;
    }
};

test "P37-01: ListWriter appends prints, integers, and repeated bytes to its list" {
    var bytes = std.array_list.Managed(u8).init(std.testing.allocator);
    defer bytes.deinit();
    var lw = ListWriter.init(&bytes);
    try lw.writer.print("tick {d}:", .{7});
    try lw.writer.writeInt(u16, 0x0102, .little);
    try lw.writer.splatByteAll('.', 3);
    try std.testing.expectEqualSlices(u8, "tick 7:\x02\x01...", bytes.items);
}
