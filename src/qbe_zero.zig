//! Inline clearing of small fixed-size ranges (RC-INLINE-ZERO-1).
//!
//! QBE lowers `call $memset` to a real library call, which costs a call, a
//! size dispatch and a return for the 8- and 16-byte values ownership
//! transfers clear most. A range of at most `inline_stores` naturally aligned
//! stores is cleared with those stores instead; the widths never exceed the
//! range's alignment, so every store is aligned for either backend.
const std = @import("std");

/// Output failures while emitting the clearing stores.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// The most stores a range is cleared with before it falls back to memset.
pub const inline_stores: usize = 8;

/// The store widths clearing `size` bytes at an address aligned to
/// `alignment`, largest first at each offset, or null past `inline_stores`.
pub fn plan(size: u64, alignment: u64) ?[inline_stores]u8 {
    var widths: [inline_stores]u8 = @splat(0);
    const widest: u64 = @min(8, if (alignment == 0) 1 else alignment);
    var offset: u64 = 0;
    var count: usize = 0;
    while (offset < size) {
        if (count == inline_stores) return null;
        var width = widest;
        while (width > size - offset or offset % width != 0) width /= 2;
        widths[count] = @intCast(width);
        count += 1;
        offset += width;
    }
    return widths;
}

/// Clear `size` bytes at `%v{address}` (aligned to `alignment`): inline stores
/// when `plan` admits the range, one memset call otherwise.
pub fn clear(comptime E: type, self: E, address: usize, size: u64, alignment: u64) Error!void {
    const widths = plan(size, alignment) orelse
        return self.print(" call $memset(l %v{d}, w 0, l {d})\n", .{ address, size });
    var offset: u64 = 0;
    for (widths) |width| {
        if (width == 0) break;
        const op = switch (width) {
            8 => "storel",
            4 => "storew",
            2 => "storeh",
            else => "storeb",
        };
        if (offset == 0) try self.print(" {s} 0, %v{d}\n", .{ op, address }) else {
            const at = self.temp();
            try self.print(" %v{d} =l add %v{d}, {d}\n {s} 0, %v{d}\n", .{ at, address, offset, op, at });
        }
        offset += width;
    }
}

test "inline clearing uses aligned stores and falls back to memset past its store budget" {
    // spec: RC-INLINE-ZERO-1
    const eight = plan(16, 8).?;
    try std.testing.expectEqualSlices(u8, &.{ 8, 8, 0 }, eight[0..3]);
    const narrow = plan(12, 4).?;
    try std.testing.expectEqualSlices(u8, &.{ 4, 4, 4, 0 }, narrow[0..4]);
    const odd = plan(13, 8).?;
    try std.testing.expectEqualSlices(u8, &.{ 8, 4, 1, 0 }, odd[0..4]);
    const bytes = plan(3, 1).?;
    try std.testing.expectEqualSlices(u8, &.{ 1, 1, 1, 0 }, bytes[0..4]);
    try std.testing.expect(plan(64, 8) != null);
    try std.testing.expect(plan(72, 8) == null);
    try std.testing.expect(plan(16, 1) == null);
    const empty = plan(0, 8).?;
    try std.testing.expectEqual(@as(u8, 0), empty[0]);
}
