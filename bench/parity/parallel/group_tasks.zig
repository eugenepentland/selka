//! group_tasks (PARALLEL.md, program 2): eight independent tasks, each summing the work of 512 items.
const std = @import("std");
const common = @import("common.zig");

const tasks = 8;
const per_task = 512;
const rounds = 100000;
const modulus = 1000003;

/// The shared work: t starts at seed mod 1000003, then rounds steps of t = (t * 31 + i) mod 1000003.
fn work(seed: i64, count: i64) i64 {
    var t = @mod(seed, modulus);
    var i: i64 = 0;
    while (i < count) : (i += 1) t = @mod(t * 31 + i, modulus);
    return t;
}

/// The work of items first .. first + count - 1, summed.
fn span(first: usize, count: usize) i64 {
    var total: i64 = 0;
    for (first..first + count) |x| total += work(@intCast(x), rounds);
    return total;
}

const Shared = struct { next: std.atomic.Value(usize), results: [tasks]i64 = std.mem.zeroes([tasks]i64) };

/// Takes tasks until none is left; each task writes its own slot of the results.
fn worker(shared: *Shared) void {
    while (true) {
        const index = shared.next.fetchAdd(1, .monotonic);
        if (index >= tasks) break;
        shared.results[index] = span(index * per_task, per_task);
    }
}

pub fn main(init: std.process.Init) !void {
    const threads = common.threadCount(init.environ_map);
    var shared: Shared = .{ .next = .init(0) };
    var handles: [256]std.Thread = undefined;
    for (0..threads) |i| handles[i] = try std.Thread.spawn(.{}, worker, .{&shared});
    for (0..threads) |i| handles[i].join();
    var checksum: i64 = 0;
    for (shared.results) |value| checksum += value;
    var line: [128]u8 = undefined;
    const text = try std.fmt.bufPrint(&line, "group_tasks {d} {d} {d} checksum {d}\n", .{ tasks, per_task, rounds, checksum });
    try common.emit(init.io, text);
}
