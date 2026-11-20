//! shared_model (PARALLEL.md, program 3): 4096 items, each reading 1000 entries of one shared list of 2^20 integers, plus its
//! work chain. The list is built once and read by every thread; nothing is copied.
const std = @import("std");
const common = @import("common.zig");

const items = 4096;
const rounds = 100000;
const modulus = 1000003;
const model_size = 1048576;

/// The shared work: t starts at seed mod 1000003, then rounds steps of t = (t * 31 + i) mod 1000003.
fn work(seed: i64, count: i64) i64 {
    var t = @mod(seed, modulus);
    var i: i64 = 0;
    while (i < count) : (i += 1) t = @mod(t * 31 + i, modulus);
    return t;
}

/// The item's value: 1000 model entries summed mod 1000003, plus its work chain.
fn lookup(x: i64, model: []const i64) i64 {
    var s: i64 = 0;
    var j: i64 = 0;
    while (j < 1000) : (j += 1) s += model[@intCast(@mod(x * 7919 + j * 104729, @as(i64, @intCast(model.len))))];
    return @mod(s, modulus) + work(x, rounds);
}

const Shared = struct { next: std.atomic.Value(usize), chunks: usize, model: []const i64, total: std.atomic.Value(i64) };

/// Takes chunks until none is left, and adds each chunk's values to the total.
fn worker(shared: *Shared) void {
    while (true) {
        const index = shared.next.fetchAdd(1, .monotonic);
        if (index >= shared.chunks) break;
        const range = common.chunkRange(items, shared.chunks, index);
        var part: i64 = 0;
        for (range.start..range.start + range.count) |x| part += lookup(@intCast(x), shared.model);
        _ = shared.total.fetchAdd(part, .monotonic);
    }
}

pub fn main(init: std.process.Init) !void {
    const threads = common.threadCount(init.environ_map);
    const allocator = std.heap.page_allocator;
    const model = try allocator.alloc(i64, model_size);
    for (model, 0..) |*entry, k| entry.* = @mod(@as(i64, @intCast(k)) * 2654435761 + 12345, modulus);
    var shared: Shared = .{ .next = .init(0), .chunks = common.chunkCount(items, threads), .model = model, .total = .init(0) };
    var handles: [256]std.Thread = undefined;
    for (0..threads) |i| handles[i] = try std.Thread.spawn(.{}, worker, .{&shared});
    for (0..threads) |i| handles[i].join();
    var line: [128]u8 = undefined;
    const text = try std.fmt.bufPrint(&line, "shared_model {d} {d} checksum {d}\n", .{ items, rounds, shared.total.load(.monotonic) });
    try common.emit(init.io, text);
}
