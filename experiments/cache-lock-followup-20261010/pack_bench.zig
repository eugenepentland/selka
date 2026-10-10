//! Same-source microbenchmark of catalog refresh and independent pack publishers.
const std = @import("std");
const pack = @import("pack");
const a = std.heap.c_allocator;
const identity: [32]u8 = @splat(71);
const Timespec = extern struct { seconds: isize, nanoseconds: isize };
extern "c" fn clock_gettime(c_int, *Timespec) c_int;
const Work = struct {
    filename_lookups: u64 = 0,
    refreshes: u64 = 0,
    packs_prepared: u64 = 0,
    pack_bytes_prepared: u64 = 0,
    save_bytes_prepared: u64 = 0,
    sequence_locks: u64 = 0,
};
const Measurement = struct { work_ns: u64, publication: ?Work = null };

fn publication(states: []const *pack.State) ?Work {
    if (!@hasField(pack.Statistics, "publication")) return null;
    var result: Work = .{};
    for (states) |state| {
        const current = state.statistics().publication;
        inline for (comptime std.meta.fieldNames(Work)) |name| @field(result, name) += @field(current, name);
    }
    return result;
}

fn now() u64 {
    var value: Timespec = undefined;
    std.debug.assert(clock_gettime(1, &value) == 0);
    return @as(u64, @intCast(value.seconds)) * 1_000_000_000 + @as(u64, @intCast(value.nanoseconds));
}

fn key(space: u64, index: u64) [32]u8 {
    var result: [32]u8 = @splat(0);
    std.mem.writeInt(u64, result[0..8], space, .little);
    std.mem.writeInt(u64, result[8..16], index, .little);
    return result;
}

fn opened(io: std.Io, root: []const u8) !*pack.State {
    return pack.State.init(a, io, root, identity, .zlib);
}

fn require(saved: bool) !void {
    if (!saved) return error.CacheWriteFailed;
}

fn verify(state: *pack.State, id: [32]u8, expected: []const u8) !void {
    const value = try state.load(a, id, null) orelse return error.CacheMiss;
    defer a.free(value);
    if (!std.mem.eql(u8, value, expected)) return error.IncorrectPayload;
}

fn seed(io: std.Io, root: []const u8, count: usize) !Measurement {
    const state = try opened(io, root);
    defer state.deinit();
    const started = now();
    for (0..count) |index| {
        try require(try state.save(key(0, index), "retained baseline record"));
        try require(try state.flush());
    }
    return .{ .work_ns = now() - started, .publication = publication(&.{state}) };
}

fn refresh(io: std.Io, root: []const u8, iterations: usize) !Measurement {
    const reader = try opened(io, root);
    defer reader.deinit();
    const writer = try opened(io, root);
    defer writer.deinit();
    try verify(reader, key(0, 0), "retained baseline record");
    try verify(writer, key(0, 0), "retained baseline record");
    const started = now();
    for (0..iterations) |index| {
        try require(try writer.save(key(1, index), "new externally published record"));
        try verify(reader, key(1, index), "new externally published record");
    }
    return .{ .work_ns = now() - started, .publication = publication(&.{ reader, writer }) };
}

const Worker = struct {
    state: *pack.State,
    id: usize,
    iterations: usize,
    ready: *std.atomic.Value(bool),
    failed: bool = false,

    fn run(self: *Worker) void {
        while (!self.ready.load(.acquire)) std.atomic.spinLoopHint();
        self.publish() catch {
            self.failed = true;
        };
    }

    fn publish(self: *Worker) !void {
        var payload: [32768]u8 = undefined;
        // Deterministic, compressible blocks with nonuniform content.
        for (&payload, 0..) |*byte, index| byte.* = @intCast((index *% 17 + self.id) % 251);
        for (0..self.iterations) |index| {
            try require(try self.state.save(key(10 + self.id, index), &payload));
            if (index % 16 == 15) try require(try self.state.flush());
        }
        try require(try self.state.flush());
    }
};

fn contend(io: std.Io, root: []const u8, iterations: usize) !Measurement {
    var ready = std.atomic.Value(bool).init(false);
    var workers: [4]Worker = undefined;
    var threads: [4]std.Thread = undefined;
    var initialized: usize = 0;
    defer for (workers[0..initialized]) |worker| worker.state.deinit();
    for (&workers, 0..) |*worker, index| {
        worker.* = .{ .state = try opened(io, root), .id = index, .iterations = iterations, .ready = &ready };
        initialized += 1;
        try verify(worker.state, key(0, 0), "retained baseline record");
    }
    var spawned: usize = 0;
    errdefer {
        ready.store(true, .release);
        for (threads[0..spawned]) |thread| thread.join();
    }
    for (&threads, &workers) |*thread, *worker| {
        thread.* = try std.Thread.spawn(.{}, Worker.run, .{worker});
        spawned += 1;
    }
    const started = now();
    ready.store(true, .release);
    for (threads) |thread| thread.join();
    spawned = 0;
    const elapsed = now() - started;
    for (workers) |worker| if (worker.failed) return error.WorkerFailed;
    const reader = try opened(io, root);
    defer reader.deinit();
    for (workers) |worker| {
        var payload: [32768]u8 = undefined;
        for (&payload, 0..) |*byte, index| byte.* = @intCast((index *% 17 + worker.id) % 251);
        for (0..iterations) |index| try verify(reader, key(10 + worker.id, index), &payload);
    }
    return .{ .work_ns = elapsed, .publication = publication(&.{ workers[0].state, workers[1].state, workers[2].state, workers[3].state }) };
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const args = try init.minimal.args.toSlice(arena.allocator());
    if (args.len != 4) return error.ExpectedModeDirectoryCount;
    const count = try std.fmt.parseInt(usize, args[3], 10);
    const measurement = if (std.mem.eql(u8, args[1], "seed")) try seed(init.io, args[2], count) else if (std.mem.eql(u8, args[1], "refresh")) try refresh(init.io, args[2], count) else if (std.mem.eql(u8, args[1], "contend")) try contend(init.io, args[2], count) else return error.UnknownMode;
    var buffer: [1024]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    const result = .{ .mode = args[1], .count = count, .work_ns = measurement.work_ns, .publication = measurement.publication, .verified = true };
    const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), result, .{});
    try out.interface.print("{s}\n", .{bytes});
    try out.interface.flush();
}
