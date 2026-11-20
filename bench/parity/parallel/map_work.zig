//! map_work (PARALLEL.md, program 1): 4096 items, each a chain of 100000 modular steps, split into chunks as parallel.map does.
const std = @import("std");
const common = @import("common.zig");

const items = 4096;
const rounds = 100000;
const modulus = 1000003;

/// The shared work: t starts at seed mod 1000003, then rounds steps of t = (t * 31 + i) mod 1000003.
fn work(seed: i64, count: i64) i64 {
    var t = @mod(seed, modulus);
    var i: i64 = 0;
    while (i < count) : (i += 1) t = @mod(t * 31 + i, modulus);
    return t;
}

const Shared = struct { next: std.atomic.Value(usize), chunks: usize, total: std.atomic.Value(i64) };

/// Takes chunks until none is left, and adds each chunk's work to the total.
fn worker(shared: *Shared) void {
    while (true) {
        const index = shared.next.fetchAdd(1, .monotonic);
        if (index >= shared.chunks) break;
        const range = common.chunkRange(items, shared.chunks, index);
        var part: i64 = 0;
        for (range.start..range.start + range.count) |x| part += work(@intCast(x), rounds);
        _ = shared.total.fetchAdd(part, .monotonic);
    }
}

pub fn main(init: std.process.Init) !void {
    const threads = common.threadCount(init.environ_map);
    var shared: Shared = .{ .next = .init(0), .chunks = common.chunkCount(items, threads), .total = .init(0) };
    var handles: [256]std.Thread = undefined;
    for (0..threads) |i| handles[i] = try std.Thread.spawn(.{}, worker, .{&shared});
    for (0..threads) |i| handles[i].join();
    var line: [128]u8 = undefined;
    const text = try std.fmt.bufPrint(&line, "map_work {d} {d} checksum {d}\n", .{ items, rounds, shared.total.load(.monotonic) });
    try common.emit(init.io, text);
}
