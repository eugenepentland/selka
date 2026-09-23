//! Buffered multi-line standard output for the Zig ports that print more
//! than one or two values (binary_trees, nbody, mandelbrot).
//!
//! `Lines` formats into a fixed in-memory buffer and `flush` hands the whole
//! buffer to the raw Linux write syscall, so, as in `common.zig`, no std.Io
//! plumbing appears in the program and the output reaches fd 1 in one write.
const std = @import("std");

/// Collects formatted output in a fixed buffer and writes it to fd 1 on `flush`.
pub const Lines = struct {
    buffer: [4096]u8 = undefined,
    len: usize = 0,

    /// Appends formatted text; panics if these few lines ever outgrow the buffer.
    pub fn print(self: *Lines, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.bufPrint(self.buffer[self.len..], fmt, args) catch @panic("output buffer full");
        self.len += text.len;
    }

    /// Writes every buffered byte to standard output and empties the buffer.
    pub fn flush(self: *Lines) void {
        var rest: []const u8 = self.buffer[0..self.len];
        while (rest.len > 0) {
            const rc = std.os.linux.write(1, rest.ptr, rest.len);
            switch (std.os.linux.errno(rc)) {
                .SUCCESS => rest = rest[rc..],
                .INTR => {},
                else => @panic("write to stdout failed"),
            }
        }
        self.len = 0;
    }
};
