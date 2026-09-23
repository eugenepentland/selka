//! Output helper for the multi-line Zig ports (knucleotide, raytrace, text_ops).
//!
//! A port formats its whole output into one `std.ArrayList(u8)` with the
//! list's own `print`, then hands the bytes to `writeStdout` once at the end,
//! so no `std.Io` plumbing appears inside a timed region — the same shape as
//! `common.emit1`, generalized to any number of lines.
const std = @import("std");

/// Writes every byte of `bytes` to standard output with the raw Linux write
/// syscall, retrying after a partial write and giving up on an error.
pub fn writeStdout(bytes: []const u8) void {
    var rest = bytes;
    while (rest.len > 0) {
        const rc = std.os.linux.write(1, rest.ptr, rest.len);
        if (std.os.linux.errno(rc) != .SUCCESS) return;
        rest = rest[rc..];
    }
}
