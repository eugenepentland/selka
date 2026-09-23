//! Output helper for the fannkuch, sort, sieve and matmul Zig ports.
//!
//! `print` formats a whole multi-line result into one stack buffer and hands
//! it to fd 1 with a single raw write, the "one bufPrint then a single write"
//! shape SUITE.md allows. It is called once, after the timed work.
const std = @import("std");

/// Formats `args` with `fmt` into a stack buffer and writes the text to standard output in one write.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
    _ = std.os.linux.write(1, text.ptr, text.len);
}
