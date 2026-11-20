//! Shared helpers for the parallel scaling ports (PARALLEL.md): the thread count from SELKA_THREADS, the chunking the
//! Selka runtime uses for parallel.map, and the one output line written to fd 1.
const std = @import("std");

/// The number of task threads: SELKA_THREADS, or one when it is unset (the programs always set it).
pub fn threadCount(environ: *const std.process.Environ.Map) usize {
    const text = environ.get("SELKA_THREADS") orelse return 1;
    return std.fmt.parseInt(usize, text, 10) catch 1;
}

/// The number of map chunks for `items` items on `threads` threads: one chunk on one thread, otherwise four per thread,
/// and never more chunks than items. This is `myl_core_map_chunks` in the Selka runtime.
pub fn chunkCount(items: usize, threads: usize) usize {
    if (items == 0) return 0;
    const chunks = if (threads == 1) 1 else threads * 4;
    return @min(items, chunks);
}

/// The first item and the item count of chunk `index` of `chunks` over `items` items: the quotient goes to every chunk and
/// the remainder adds one item to the first chunks, as the Selka runtime splits them.
pub fn chunkRange(items: usize, chunks: usize, index: usize) struct { start: usize, count: usize } {
    const quotient = items / chunks;
    const remainder = items % chunks;
    const start = index * quotient + @min(index, remainder);
    return .{ .start = start, .count = quotient + @intFromBool(index < remainder) };
}

/// Writes one line to standard output with a single write.
pub fn emit(io: std.Io, line: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, line);
}
