//! The new core's own native object store and its parallel compiler
//! (docs/design/new-core-s4.md §6). A unit's object is a pure function of the
//! unit's LLVM text, the optimization level, the resolved target and the
//! toolchain, so the store is keyed by exactly those and needs no dependency
//! tracking. A hit spawns no process: Zig's own cache would also reuse an
//! identical `.ll`, but only after starting `zig cc` for it.
//!
//! Every entry is `<key>.o` beside `<key>.sum`, which records the object's size
//! and BLAKE3 digest. A hit reads and hashes the object, so a truncated,
//! overwritten or foreign file is a miss that is rebuilt, never linked.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const target_policy = @import("target.zig");
const retention = @import("selka").native_cache_retention;

/// A BLAKE3 digest: store keys and content identities.
pub const Digest = [32]u8;

/// The version of how an object is produced from a unit's text: the compile
/// command below and the meaning of the text the emitter writes. Bump it when
/// either changes in a way the text itself does not show.
pub const format = "core-unit-object-v2";

/// Why a store or compile operation failed; tool output goes to the caller's log.
pub const Error = error{ ToolFailed, OutOfMemory, WriteFailed };

/// A file the build read, by absolute path, and its content digest; null records
/// that the file was absent.
pub const Dependency = struct { path: []const u8, digest: ?Digest, stamp: ?Stamp = null };

/// File identity captured around a successful content comparison, never before it.
pub const Stamp = struct {
    size: u64,
    inode: u64,
    mtime: i96,
    ctime: i96,

    /// Record the metadata that changes on replacement, rewriting or truncation.
    pub fn from(status: std.Io.File.Stat) Stamp {
        return .{ .size = status.size, .inode = @intCast(status.inode), .mtime = status.mtime.nanoseconds, .ctime = status.ctime.nanoseconds };
    }
};

/// Everything besides a unit's text that decides its object.
pub const Settings = struct {
    /// The toolchain's content identity (`tool_identity.Identity.digest`).
    tool: Digest,
    /// The resolved host CPU and code-generation flags (`tool_identity.nativeTarget`),
    /// so a store copied to another machine cannot serve an object for the wrong CPU.
    cpu: Digest,
    mode: @import("build_mode.zig").Mode = .optimized_debug,
    /// Independent runtime C declaration/layout surface and ABI/code-generation
    /// flags; the exact LLVM also binds each unit's declarations and offsets.
    runtime: Digest,
    /// The target the units compile for: its `zig cc -target` and CPU flags are key fields.
    target: *const target_policy.Target = &target_policy.host,
};

/// The store key of one unit: `format`, the mode and the whole `zig cc` argument list it compiles with, the target
/// triple, the CPU flags and the resolved CPU, the toolchain, the runtime ABI and
/// the unit's exact text. Fields are length-delimited.
pub fn key(settings: Settings, text: []const u8) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, format);
    field(&hash, @tagName(settings.mode));
    field(&hash, settings.mode.keyed());
    field(&hash, settings.target.cc_target);
    for (settings.target.cpu_flags) |flag| field(&hash, flag);
    field(&hash, &settings.cpu);
    field(&hash, &settings.tool);
    field(&hash, &settings.runtime);
    field(&hash, text);
    // A bare target compiles its units with its own arguments in place of the mode's (`Bare.compile`, and `Bare.release`
    // in a release build): they are key fields too. A hosted key hashes nothing more.
    switch (settings.target.system.runtime) {
        .hosted => {},
        .bare => |bare| {
            field(&hash, "bare-unit");
            for (bare.compile) |flag| field(&hash, flag);
            if (settings.mode == .release) for (bare.release) |flag| field(&hash, flag);
        },
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// Hash one length-delimited field, so adjacent fields cannot run together.
pub fn field(hash: *fast_blake3.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

/// A verified file: where it is and the digest of its bytes.
pub const Found = struct { path: []const u8, digest: Digest };

/// Hash a file this build wrote (a fresh object it will not publish).
pub fn found(arena: std.mem.Allocator, io: std.Io, path: []const u8) Error!Found {
    const digest = fileDigest(arena, io, path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ReadFailed => return error.WriteFailed,
    } orelse return error.WriteFailed;
    return .{ .path = path, .digest = digest };
}

/// One content-addressed directory of objects (or linked programs).
pub const Store = struct {
    directory: []const u8,

    /// Where the entry for `digest` lives, whether or not it exists.
    pub fn path(self: Store, arena: std.mem.Allocator, digest: Digest, suffix: []const u8) Error![]const u8 {
        const hex = std.fmt.bytesToHex(digest, .lower);
        if (self.sharded()) return std.fmt.allocPrint(arena, "{s}/{s}/{s}{s}", .{ self.directory, hex[0..2], hex, suffix });
        return self.flatPath(arena, digest, suffix);
    }

    fn sharded(self: Store) bool {
        return std.mem.eql(u8, std.fs.path.basename(self.directory), "units-v1");
    }

    fn flatPath(self: Store, arena: std.mem.Allocator, digest: Digest, suffix: []const u8) Error![]const u8 {
        return std.fmt.allocPrint(arena, "{s}/{s}{s}", .{ self.directory, std.fmt.bytesToHex(digest, .lower), suffix });
    }

    /// The entry's path when it exists and its bytes match its recorded size and
    /// digest; anything else (absent, truncated, overwritten, no record) is a miss.
    pub fn lookup(self: Store, arena: std.mem.Allocator, io: std.Io, digest: Digest, suffix: []const u8) Error!?Found {
        const object = try self.path(arena, digest, suffix);
        if (try self.checked(arena, io, object)) |hit| return hit;
        if (!self.sharded()) return null;
        return self.checked(arena, io, try self.flatPath(arena, digest, suffix));
    }

    fn keepFresh(self: Store, arena: std.mem.Allocator, io: std.Io, object: []const u8, sum: Sum, now: Tuple) void {
        const clock: i64 = @truncate(std.Io.Timestamp.now(io, .real).nanoseconds);
        if (clock - now.mtime < touch_interval_ns) return;
        retention.Context.init(arena, io, self.directory, .compiler).touchPath(object);
        refreshSum(arena, io, object, sum, now);
    }

    fn checked(self: Store, arena: std.mem.Allocator, io: std.Io, object: []const u8) Error!?Found {
        const recorded = try readSum(arena, io, try std.fmt.allocPrint(arena, "{s}.sum", .{object})) orelse return null;
        // The writer hashed these bytes and recorded the file's stat tuple beside the digest: a file that still has exactly that tuple
        // (inode, size, mtime, ctime) is the file it hashed, so it is served without reading it. Any other tuple is hashed in full.
        if (recorded.seen) |seen| if (tupleOf(io, object)) |now| if (now.eql(seen) and now.size == recorded.size) {
            if (self.sharded()) self.keepFresh(arena, io, object, recorded, now);
            return .{ .path = object, .digest = recorded.digest };
        };
        const read = (streamed(arena, io, object, recorded.size + 1) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        }) orelse return null;
        if (read.size != recorded.size) return null;
        const actual = read.digest;
        if (!std.mem.eql(u8, &actual, &recorded.digest)) return null;
        if (self.sharded()) retention.Context.init(arena, io, self.directory, .compiler).touchPath(object);
        // Verified in full: record the tuple of the file just hashed, so the next lookup need not hash it again. The record of an object a
        // compiler that did not record tuples published, and of one whose inode, mtime or ctime moved with the bytes unchanged, is
        // refreshed here.
        if (self.sharded()) refreshSum(arena, io, object, .{ .size = recorded.size, .digest = actual }, recorded.seen);
        return .{ .path = object, .digest = actual };
    }

    /// A fresh private name beside the entry for `digest`, on the store's own file
    /// system, for a file `publish` will rename into place.
    pub fn partial(self: Store, arena: std.mem.Allocator, io: std.Io, digest: Digest, suffix: []const u8) Error![]const u8 {
        const object = try self.path(arena, digest, suffix);
        std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(object).?) catch return error.WriteFailed;
        var nonce: [16]u8 = undefined;
        std.Io.random(io, &nonce);
        return std.fmt.allocPrint(arena, "{s}.{s}.partial", .{ object, std.fmt.bytesToHex(nonce, .lower) });
    }

    /// Publish `staged` (this build's private file, on the store's file system) as the entry for `digest`:
    /// write its record, then rename the file and the record into place. A reader
    /// that sees one without the other, or another build's equal copy, either
    /// verifies or misses; it never links an unverified file.
    pub fn publish(self: Store, arena: std.mem.Allocator, io: std.Io, digest: Digest, suffix: []const u8, staged: []const u8) Error!Found {
        const cwd = std.Io.Dir.cwd();
        const object = try self.path(arena, digest, suffix);
        cwd.createDirPath(io, std.fs.path.dirname(object).?) catch return error.WriteFailed;
        // The staged file is read in chunks and hashed as it goes: a linked program is tens of megabytes and is never needed whole.
        const read = (streamed(arena, io, staged, std.math.maxInt(usize)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.WriteFailed;
        }) orelse return error.WriteFailed;
        const actual = read.digest;
        const sum = try std.fmt.allocPrint(arena, "{s}.sum", .{object});
        var nonce: [16]u8 = undefined;
        std.Io.random(io, &nonce);
        const record_partial = try std.fmt.allocPrint(arena, "{s}.{s}.partial", .{ sum, std.fmt.bytesToHex(nonce, .lower) });
        defer removeFile(io, record_partial);
        cwd.rename(staged, cwd, object, io) catch return error.WriteFailed;
        // The tuple is taken after the rename, which changes the file's ctime; a file that cannot be stat-ed is recorded without one.
        const record = try sumText(arena, .{ .size = read.size, .digest = actual }, tupleOf(io, object));
        cwd.writeFile(io, .{ .sub_path = record_partial, .data = record }) catch return error.WriteFailed;
        cwd.rename(record_partial, cwd, sum, io) catch return error.WriteFailed;
        return .{ .path = object, .digest = actual };
    }
};

const sum_magic = "core-unit-sum-v1";
const sum_magic_stat = "core-unit-sum-v2";

/// A file's stat tuple: what tells one state of a file from another without reading it.
const Tuple = struct {
    inode: u64,
    size: u64,
    mtime: i64,
    ctime: i64,

    fn eql(self: Tuple, other: Tuple) bool {
        return self.inode == other.inode and self.size == other.size and self.mtime == other.mtime and self.ctime == other.ctime;
    }
};

/// What a `.sum` record holds: the size and digest of the object's bytes, and, when the writer recorded it, the tuple the file had.
const Sum = struct { size: usize, digest: Digest, seen: ?Tuple = null };

fn tupleOf(io: std.Io, path: []const u8) ?Tuple {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    if (stat.inode == 0) return null;
    return .{ .inode = @intCast(stat.inode), .size = stat.size, .mtime = @truncate(stat.mtime.nanoseconds), .ctime = @truncate(stat.ctime.nanoseconds) };
}

fn sumText(arena: std.mem.Allocator, sum: Sum, seen: ?Tuple) std.mem.Allocator.Error![]const u8 {
    const tuple = seen orelse return std.fmt.allocPrint(arena, "{s}\n{d}\n{s}\n", .{ sum_magic, sum.size, std.fmt.bytesToHex(sum.digest, .lower) });
    return std.fmt.allocPrint(arena, "{s}\n{d}\n{s}\n{d} {d} {d} {d}\n", .{ sum_magic_stat, sum.size, std.fmt.bytesToHex(sum.digest, .lower), tuple.inode, tuple.size, tuple.mtime, tuple.ctime });
}

/// How stale an object's mtime may get before a lookup refreshes it. The mtime is the retention policy's record of use, and touching
/// it moves the object's tuple, so a trusted lookup touches an object once an hour at most and records the new tuple then.
const touch_interval_ns: i64 = 3600 * std.time.ns_per_s;

/// Rewrite the record of `object` with the tuple the file has now, when it differs from `was`. A failure leaves the old record, which
/// still verifies by hash.
fn refreshSum(arena: std.mem.Allocator, io: std.Io, object: []const u8, sum: Sum, was: ?Tuple) void {
    const now = tupleOf(io, object) orelse return;
    if (was) |known| if (known.eql(now)) return;
    const text = sumText(arena, sum, now) catch return;
    const path = std.fmt.allocPrint(arena, "{s}.sum", .{object}) catch return;
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const partial = std.fmt.allocPrint(arena, "{s}.{s}.partial", .{ path, std.fmt.bytesToHex(nonce, .lower) }) catch return;
    const cwd = std.Io.Dir.cwd();
    cwd.writeFile(io, .{ .sub_path = partial, .data = text }) catch return;
    cwd.rename(partial, cwd, path, io) catch removeFile(io, partial);
}

fn readSum(arena: std.mem.Allocator, io: std.Io, path: []const u8) Error!?Sum {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(256)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const magic = lines.next() orelse return null;
    const with_tuple = std.mem.eql(u8, magic, sum_magic_stat);
    if (!with_tuple and !std.mem.eql(u8, magic, sum_magic)) return null;
    const size = std.fmt.parseInt(usize, lines.next() orelse return null, 10) catch return null;
    const hex = lines.next() orelse return null;
    if (hex.len != 64) return null;
    var digest: Digest = undefined;
    _ = std.fmt.hexToBytes(&digest, hex) catch return null;
    if (!with_tuple) return if (std.mem.eql(u8, lines.rest(), "")) .{ .size = size, .digest = digest } else null;
    var fields = std.mem.splitScalar(u8, lines.next() orelse return null, ' ');
    const inode = std.fmt.parseInt(u64, fields.next() orelse return null, 10) catch return null;
    const length = std.fmt.parseInt(u64, fields.next() orelse return null, 10) catch return null;
    const mtime = std.fmt.parseInt(i64, fields.next() orelse return null, 10) catch return null;
    const ctime = std.fmt.parseInt(i64, fields.next() orelse return null, 10) catch return null;
    if (fields.next() != null or !std.mem.eql(u8, lines.rest(), "")) return null;
    return .{ .size = size, .digest = digest, .seen = .{ .inode = inode, .size = length, .mtime = mtime, .ctime = ctime } };
}

/// One `zig cc` invocation and its captured diagnostics.
pub const Job = struct {
    argv: []const []const u8,
    /// Bigger jobs start first (longest-processing-time order).
    weight: usize,
    log: std.ArrayList(u8) = .empty,
    ok: bool = false,
    /// Opt-in wall interval around the compiler process and diagnostic capture;
    /// queue waiting, input preparation and cache publication are outside it.
    measure: bool = false,
    compile_ns: ?u64 = null,
};

/// What every job of a `compileAll` shares.
pub const Resources = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    /// Reclaiming thread-safe backing; absent callers execute serially.
    backing: ?std.mem.Allocator = null,
    /// Admission budget for estimated child memory, independent of job count
    /// (the driver passes `stage_metrics.workerBudget`: at most one GiB, a quarter of free memory).
    memory_budget_bytes: usize = 1 << 30,
};

/// How many compiles run at once: `SELKA_JOBS`, else the CPUs this process may
/// use (its affinity mask, so a build slot's CPU set is respected), at most
/// `count` and at least one.
pub fn width(environment: *const std.process.Environ.Map, count: usize) usize {
    const requested = blk: {
        const text = environment.get("SELKA_JOBS") orelse break :blk null;
        const parsed = std.fmt.parseInt(usize, text, 10) catch break :blk null;
        break :blk if (parsed == 0) null else parsed;
    } orelse (std.Thread.getCpuCount() catch 1);
    return @min(@max(1, requested), @max(1, count));
}

/// Run every job, up to `lanes` at a time, longest first. Each job records its
/// own success and stderr; the caller decides what a failure means. A job starts as
/// soon as its estimated memory fits beside the jobs already running (or when none
/// runs), so a compile never waits for a whole batch to finish.
pub fn compileAll(resources: Resources, jobs: []Job, lanes: usize) Error!void {
    if (jobs.len == 0) return;
    const order = try resources.arena.alloc(usize, jobs.len);
    for (order, 0..) |*slot, index| slot.* = index;
    std.mem.sort(usize, order, jobs, heavier);
    if (resources.backing == null) {
        for (order) |index| try runJob(resources, &jobs[index]);
        return;
    }
    const threads = try resources.arena.alloc(std.Thread, @max(1, @min(lanes, jobs.len)) - 1);
    var queue: Queue = .{ .resources = resources, .jobs = jobs, .order = order };
    var started: usize = 0;
    for (threads) |*thread| {
        thread.* = std.Thread.spawn(.{}, Queue.drain, .{&queue}) catch break;
        started += 1;
    }
    queue.drain();
    for (threads[0..started]) |thread| thread.join();
    try collectLogs(resources, jobs, order);
    if (queue.exhausted.load(.acquire)) return error.OutOfMemory;
}

/// The memory a job reserves while it runs: a baseline per clang plus an estimate
/// proportional to its LLVM input.
pub fn estimate(weight: usize) usize {
    return (64 << 20) +| (weight *| 64);
}

/// Whether a job reserving `bytes` may start beside `running` jobs that reserve
/// `reserved` bytes of `budget`. A job always starts when nothing runs, so one
/// unusually large unit still makes progress, alone.
pub fn mayStart(running: usize, reserved: usize, bytes: usize, budget: usize) bool {
    return running == 0 or reserved +| bytes <= budget;
}

/// Move each job's backing-allocated log into the arena once every worker has
/// joined, in deterministic order, so no worker ever touches the coordinator's arena.
fn collectLogs(resources: Resources, jobs: []Job, order: []const usize) error{OutOfMemory}!void {
    const backing = resources.backing.?;
    const copied = capture: {
        defer for (order) |index| {
            jobs[index].log.deinit(backing);
            jobs[index].log = .empty;
        };
        const logs = try resources.arena.alloc(std.ArrayList(u8), order.len);
        for (order, logs) |index, *log| {
            const bytes = try resources.arena.dupe(u8, jobs[index].log.items);
            log.* = .fromOwnedSlice(bytes);
        }
        break :capture logs;
    };
    for (order, copied) |index, log| jobs[index].log = log;
}

fn heavier(jobs: []Job, left: usize, right: usize) bool {
    if (jobs[left].weight != jobs[right].weight) return jobs[left].weight > jobs[right].weight;
    return left < right;
}

/// The admission state every worker shares: the next job in order and the memory
/// its running jobs reserve. Guarded by `lock`; `freed` wakes a waiting worker when a
/// job ends.
const Gate = struct {
    lock: std.Io.Mutex = .init,
    freed: std.Io.Condition = .init,
    next: usize = 0,
    running: usize = 0,
    reserved: usize = 0,
};

const Queue = struct {
    resources: Resources,
    jobs: []Job,
    order: []const usize,
    gate: Gate = .{},
    exhausted: std.atomic.Value(bool) = .init(false),

    fn drain(self: *Queue) void {
        const io = self.resources.io;
        const budget = self.resources.memory_budget_bytes;
        self.gate.lock.lockUncancelable(io);
        while (self.gate.next < self.order.len and !self.exhausted.load(.acquire)) {
            const job = &self.jobs[self.order[self.gate.next]];
            const bytes = estimate(job.weight);
            if (!mayStart(self.gate.running, self.gate.reserved, bytes, budget)) {
                self.gate.freed.waitUncancelable(io, &self.gate.lock);
                continue;
            }
            self.gate.next += 1;
            self.gate.running += 1;
            self.gate.reserved += bytes;
            self.gate.lock.unlock(io);
            // Only allocation failure ends the queue; a tool failure is the job's verdict.
            runIsolated(self.resources, job) catch self.exhausted.store(true, .release);
            self.gate.lock.lockUncancelable(io);
            self.gate.running -= 1;
            self.gate.reserved -= bytes;
            self.gate.freed.broadcast(io);
        }
        self.gate.lock.unlock(io);
    }
};

fn runIsolated(resources: Resources, job: *Job) error{OutOfMemory}!void {
    const backing = resources.backing.?;
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    var local: Job = .{ .argv = job.argv, .weight = job.weight, .measure = job.measure };
    var private = resources;
    private.arena = scratch.allocator();
    try runJob(private, &local);
    const bytes = try backing.dupe(u8, local.log.items);
    job.log = .fromOwnedSlice(bytes);
    job.ok = local.ok;
    job.compile_ns = local.compile_ns;
}

fn runJob(resources: Resources, job: *Job) error{OutOfMemory}!void {
    const started = if (job.measure) std.Io.Timestamp.now(resources.io, .awake) else std.Io.Timestamp.zero;
    defer if (job.measure) {
        job.compile_ns = std.math.lossyCast(u64, @max(0, started.durationTo(std.Io.Timestamp.now(resources.io, .awake)).nanoseconds));
    };
    const result = @import("process_spawn.zig").run(resources.arena, resources.io, .{ .argv = job.argv, .environment = .{ .map = resources.environment }, .die_with_parent = true }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try job.log.print(resources.arena, "error: cannot run {s}: {s}\n", .{ job.argv[0], @errorName(err) });
        return;
    };
    job.ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    // The hint leads: a test verdict keeps only the first line of the log.
    if (!job.ok) if (@import("memory_budget").toolExhausted(resources.environment, result.term, result.stderr)) |hint| try job.log.appendSlice(resources.arena, hint);
    try job.log.appendSlice(resources.arena, result.stderr);
}

/// The prerequisites a Make-format depfile (`-MMD -MF`) lists, without its target.
/// Backslash-newline continues a line and a backslash escapes a space.
pub fn depfileInputs(arena: std.mem.Allocator, bytes: []const u8) Error![]const []const u8 {
    var inputs: std.ArrayList([]const u8) = .empty;
    var word: std.ArrayList(u8) = .empty;
    var seen_target = false;
    var index: usize = 0;
    while (index <= bytes.len) : (index += 1) {
        const char: u8 = if (index < bytes.len) bytes[index] else '\n';
        if (char == '\\' and index + 1 < bytes.len and (bytes[index + 1] == '\n' or bytes[index + 1] == ' ')) {
            index += 1;
            if (bytes[index] == ' ') try word.append(arena, ' ') else try finishWord(arena, &word, &inputs, &seen_target);
            continue;
        }
        if (char == ' ' or char == '\t' or char == '\n' or char == '\r') {
            try finishWord(arena, &word, &inputs, &seen_target);
            continue;
        }
        try word.append(arena, char);
    }
    return inputs.items;
}

fn finishWord(arena: std.mem.Allocator, word: *std.ArrayList(u8), inputs: *std.ArrayList([]const u8), seen_target: *bool) Error!void {
    if (word.items.len == 0) return;
    defer word.clearRetainingCapacity();
    if (!seen_target.*) {
        if (word.items[word.items.len - 1] == ':') seen_target.* = true;
        return;
    }
    try inputs.append(arena, try arena.dupe(u8, word.items));
}

// twin-drift-ok: test_runner_receipt.readDigest bounds test inputs at 64 MiB; this
// one hashes objects and programs, which may be larger.
/// The digest of a file's bytes, or null when it does not exist.
pub fn fileDigest(arena: std.mem.Allocator, io: std.Io, path: []const u8) error{ OutOfMemory, ReadFailed }!?Digest {
    const read = (try streamed(arena, io, path, 256 << 20)) orelse return null;
    return read.digest;
}

/// The length and BLAKE3 digest of a file's bytes.
const Streamed = struct { size: usize, digest: Digest };

/// How much of a file `streamed` reads at a time.
const stream_chunk = 256 * 1024;

/// Hash the file at `path` in chunks, so a program is never held whole in memory. Null when the file does not exist; a file longer than
/// `limit` bytes is a read failure.
fn streamed(arena: std.mem.Allocator, io: std.Io, path: []const u8, limit: usize) error{ OutOfMemory, ReadFailed }!?Streamed {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return error.ReadFailed;
    };
    defer file.close(io);
    const buffer = try arena.alloc(u8, stream_chunk);
    defer arena.free(buffer);
    var hash = fast_blake3.Blake3.init(.{});
    var length: usize = 0;
    while (true) {
        const count = file.readPositionalAll(io, buffer, length) catch return error.ReadFailed;
        hash.update(buffer[0..count]);
        length += count;
        if (length > limit) return error.ReadFailed;
        if (count < buffer.len) break;
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return .{ .size = length, .digest = digest };
}

/// Whether every dependency still has its recorded bytes (or is still absent).
pub fn unchanged(arena: std.mem.Allocator, io: std.Io, dependencies: []const Dependency) error{OutOfMemory}!bool {
    for (dependencies) |dependency| {
        if (!(try checkDependency(arena, io, dependency)).same) return false;
    }
    return true;
}

const Checked = struct { same: bool, hashed: bool, stamp: ?Stamp = null };

fn checkDependency(arena: std.mem.Allocator, io: std.Io, dependency: Dependency) error{OutOfMemory}!Checked {
    const before = std.Io.Dir.cwd().statFile(io, dependency.path, .{}) catch |err| {
        return .{ .same = err == error.FileNotFound and dependency.digest == null, .hashed = false };
    };
    if (dependency.digest == null) return .{ .same = false, .hashed = false };
    const status = Stamp.from(before);
    if (dependency.stamp) |recorded| {
        if (std.meta.eql(recorded, status)) return .{ .same = true, .hashed = false, .stamp = status };
    }
    const current = fileDigest(arena, io, dependency.path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .same = false, .hashed = true };
    } orelse return .{ .same = false, .hashed = true };
    if (!std.mem.eql(u8, &current, &dependency.digest.?)) return .{ .same = false, .hashed = true };
    const after = std.Io.Dir.cwd().statFile(io, dependency.path, .{}) catch return .{ .same = false, .hashed = true };
    return .{ .same = std.meta.eql(status, Stamp.from(after)), .hashed = true, .stamp = status };
}

/// Whether the file at `path` exists with exactly the status `stamp` records (its size, inode, modification and change times).
pub fn statusIs(io: std.Io, path: []const u8, stamp: Stamp) bool {
    const status = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return std.meta.eql(Stamp.from(status), stamp);
}

/// Pin fresh file metadata only after full hashing matches the captured bytes and
/// the file status remains unchanged around that read. Null means it changed.
pub fn observed(arena: std.mem.Allocator, io: std.Io, dependency: Dependency) error{OutOfMemory}!?Dependency {
    var fresh = dependency;
    fresh.stamp = null;
    const checked = try checkDependency(arena, io, fresh);
    if (!checked.same) return null;
    fresh.stamp = checked.stamp;
    return fresh;
}

fn removeFile(io: std.Io, path: []const u8) void {
    // A published partial already moved away; otherwise discard this build's file.
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

// spec: NEW-CORE-S4-CACHE-1
test "unit keys cover the text, compile flags, toolchain, CPU and runtime, and fields cannot run together" {
    const base: Settings = .{ .tool = @splat(1), .cpu = @splat(2), .mode = .debug, .runtime = @splat(3) };
    const original = key(base, "define i32 @f()");
    try std.testing.expectEqual(original, key(base, "define i32 @f()"));
    try std.testing.expect(!std.mem.eql(u8, &original, &key(base, "define i32 @g()")));
    var changed = base;
    changed.mode = .release;
    try std.testing.expect(!std.mem.eql(u8, &original, &key(changed, "define i32 @f()")));
    const release_key = key(changed, "define i32 @f()");
    changed = base;
    changed.mode = .optimized_o2;
    try std.testing.expectEqualStrings("-O2", changed.mode.level());
    try std.testing.expect(!std.mem.eql(u8, &original, &key(changed, "define i32 @f()")));
    try std.testing.expect(!std.mem.eql(u8, &release_key, &key(changed, "define i32 @f()")));
    // The lean build compiles the same text with other flags, so it never shares an -O0 object, with or without Core's passes.
    changed = base;
    changed.mode = .lean_debug;
    const lean_key = key(changed, "define i32 @f()");
    changed.mode = .optimized_debug;
    try std.testing.expect(!std.mem.eql(u8, &lean_key, &key(changed, "define i32 @f()")));
    try std.testing.expect(!std.mem.eql(u8, &lean_key, &original));
    changed = base;
    changed.tool = @splat(9);
    try std.testing.expect(!std.mem.eql(u8, &original, &key(changed, "define i32 @f()")));
    changed = base;
    changed.cpu = @splat(9);
    try std.testing.expect(!std.mem.eql(u8, &original, &key(changed, "define i32 @f()")));
    changed = base;
    changed.runtime = @splat(9);
    try std.testing.expect(!std.mem.eql(u8, &original, &key(changed, "define i32 @f()")));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "a store entry is served only while its bytes match their record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const store: Store = .{ .directory = try std.fs.path.join(a, &.{ root, "units-v1" }) };
    const digest: Digest = @splat(5);
    try std.testing.expectEqual(@as(?Found, null), try store.lookup(a, std.testing.io, digest, ".o"));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "staged.o", .data = "object bytes" });
    const entry = try store.publish(a, std.testing.io, digest, ".o", try std.fs.path.join(a, &.{ root, "staged.o" }));
    const published = entry.path;
    try std.testing.expect(std.mem.indexOf(u8, published, "/units-v1/05/") != null);
    try std.testing.expectEqualStrings(published, (try store.lookup(a, std.testing.io, digest, ".o")).?.path);
    try std.testing.expectEqual(entry.digest, (try store.lookup(a, std.testing.io, digest, ".o")).?.digest);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = published, .data = "object bytez" });
    try std.testing.expectEqual(@as(?Found, null), try store.lookup(a, std.testing.io, digest, ".o"));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = published, .data = "object" });
    try std.testing.expectEqual(@as(?Found, null), try store.lookup(a, std.testing.io, digest, ".o"));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = published, .data = "object bytes" });
    try std.testing.expect((try store.lookup(a, std.testing.io, digest, ".o")) != null);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}.sum", .{published}), .data = "core-unit-sum-v1\n12\nnot hex\n" });
    try std.testing.expectEqual(@as(?Found, null), try store.lookup(a, std.testing.io, digest, ".o"));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "unit store reads flat legacy pairs while every new path is sharded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const store: Store = .{ .directory = try std.fs.path.join(a, &.{ root, "units-v1" }) };
    const digest: Digest = @splat(10);
    const partial_path = try store.partial(a, std.testing.io, digest, ".o");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = partial_path, .data = "legacy object" });
    const entry = try store.publish(a, std.testing.io, digest, ".o", partial_path);
    const flat = try store.flatPath(a, digest, ".o");
    try std.Io.Dir.cwd().rename(entry.path, std.Io.Dir.cwd(), flat, std.testing.io);
    try std.Io.Dir.cwd().rename(try std.fmt.allocPrint(a, "{s}.sum", .{entry.path}), std.Io.Dir.cwd(), try std.fmt.allocPrint(a, "{s}.sum", .{flat}), std.testing.io);
    try std.testing.expectEqualStrings(flat, (try store.lookup(a, std.testing.io, digest, ".o")).?.path);
    try std.testing.expect(!std.mem.eql(u8, flat, try store.path(a, digest, ".o")));
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "replay dependency stamps avoid hashing and any status change rechecks bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "source", .data = "original" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "source", a);
    const input: Dependency = .{ .path = path, .digest = try fileDigest(a, std.testing.io, path) };
    const pinned = (try observed(a, std.testing.io, input)).?;
    try std.testing.expect(pinned.stamp != null);
    try std.testing.expect(!(try checkDependency(a, std.testing.io, pinned)).hashed);
    try std.testing.expect(try unchanged(a, std.testing.io, &.{pinned}));
    var metadata_changed = pinned;
    metadata_changed.stamp.?.inode +%= 1;
    try std.testing.expect((try checkDependency(a, std.testing.io, metadata_changed)).hashed);
    try std.testing.expect(try unchanged(a, std.testing.io, &.{metadata_changed}));
    metadata_changed = pinned;
    metadata_changed.stamp.?.size +%= 1;
    try std.testing.expect((try checkDependency(a, std.testing.io, metadata_changed)).hashed);
    metadata_changed = pinned;
    metadata_changed.stamp.?.mtime +%= 1;
    try std.testing.expect((try checkDependency(a, std.testing.io, metadata_changed)).hashed);
    metadata_changed = pinned;
    metadata_changed.stamp.?.ctime +%= 1;
    try std.testing.expect((try checkDependency(a, std.testing.io, metadata_changed)).hashed);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "source", .data = "modified" });
    try std.testing.expect(!try unchanged(a, std.testing.io, &.{pinned}));
    try std.testing.expectEqual(@as(?Dependency, null), try observed(a, std.testing.io, input));
    try dir.dir.deleteFile(std.testing.io, "source");
    try std.testing.expect(!try unchanged(a, std.testing.io, &.{pinned}));
    try std.testing.expect(try unchanged(a, std.testing.io, &.{.{ .path = path, .digest = null }}));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "readSum refuses missing and malformed records and runJob records a tool that cannot start" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try std.testing.expectEqual(@as(?Sum, null), try readSum(a, std.testing.io, try std.fs.path.join(a, &.{ root, "absent.sum" })));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "short.sum", .data = "core-unit-sum-v1\n12\n" });
    try std.testing.expectEqual(@as(?Sum, null), try readSum(a, std.testing.io, try std.fs.path.join(a, &.{ root, "short.sum" })));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "good.sum", .data = "core-unit-sum-v1\n3\n" ++ "abababababababababababababababababababababababababababababababab" ++ "\n" });
    try std.testing.expectEqual(@as(usize, 3), (try readSum(a, std.testing.io, try std.fs.path.join(a, &.{ root, "good.sum" }))).?.size);
    var environment: std.process.Environ.Map = .init(a);
    var job: Job = .{ .argv = &.{"/nonexistent/selka-core-test/zig"}, .weight = 1 };
    try runJob(.{ .arena = a, .io = std.testing.io, .environment = &environment }, &job);
    try std.testing.expect(!job.ok);
    try std.testing.expect(std.mem.indexOf(u8, job.log.items, "cannot run") != null);
    var jobs = [_]Job{ job, .{ .argv = &.{"/nonexistent/other"}, .weight = 2 } };
    try compileAll(.{ .arena = a, .io = std.testing.io, .environment = &environment }, &jobs, 2);
    try std.testing.expect(!jobs[0].ok and !jobs[1].ok);
}

// spec-case: NEW-CORE-S4-CACHE-1
test "depfile inputs skip the target and honor continuations and escaped spaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const inputs = try depfileInputs(arena.allocator(), "out.o: sub/value.c sub/value.h \\\n  /abs/with\\ space.h\n");
    try std.testing.expectEqual(@as(usize, 3), inputs.len);
    try std.testing.expectEqualStrings("sub/value.c", inputs[0]);
    try std.testing.expectEqualStrings("sub/value.h", inputs[1]);
    try std.testing.expectEqualStrings("/abs/with space.h", inputs[2]);
    try std.testing.expectEqual(@as(usize, 0), (try depfileInputs(arena.allocator(), "")).len);
}

// spec-case: NEW-CORE-S4-CACHE-1
test "compile width follows SELKA_JOBS, else the CPUs, and never exceeds the work" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_JOBS", "3");
    try std.testing.expectEqual(@as(usize, 3), width(&environment, 10));
    try std.testing.expectEqual(@as(usize, 2), width(&environment, 2));
    try std.testing.expectEqual(@as(usize, 1), width(&environment, 0));
    try environment.put("SELKA_JOBS", "0");
    try std.testing.expect(width(&environment, 1000) >= 1);
}

// spec: NEW-CORE-STAGE-CACHE-6
test "the compile budget defaults to one GiB and admits a typical unit beside many others" {
    const defaults: Resources = .{ .arena = std.testing.allocator, .io = std.testing.io, .environment = undefined };
    try std.testing.expectEqual(@as(usize, 1 << 30), defaults.memory_budget_bytes);
    // A 100 kB unit estimates about 73.5 MB: fourteen of them fit in one GiB, and the fifteenth waits.
    const typical = estimate(100_000);
    try std.testing.expect(mayStart(13, 13 * typical, typical, defaults.memory_budget_bytes));
    try std.testing.expect(!mayStart(14, 14 * typical, typical, defaults.memory_budget_bytes));
}

test "native stage admission bounds simultaneous memory and isolated workers preserve diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try std.testing.environ.createMap(a);
    var jobs = [_]Job{
        .{ .argv = &.{ "/bin/sh", "-c", "echo first >&2" }, .weight = 1024, .measure = true },
        .{ .argv = &.{ "/bin/sh", "-c", "echo second >&2; exit 7" }, .weight = 1024, .measure = true },
        .{ .argv = &.{"/nonexistent/stage-worker"}, .weight = 1024 },
    };
    try std.testing.expect(mayStart(0, 0, estimate(1024), 1));
    try std.testing.expect(!mayStart(1, estimate(1024), estimate(1024), 1));
    try std.testing.expect(mayStart(1, estimate(1024), estimate(1024), 150 << 20));
    try std.testing.expect(!mayStart(2, 2 * estimate(1024), estimate(1024), 150 << 20));
    try compileAll(.{ .arena = a, .backing = std.testing.allocator, .io = std.testing.io, .environment = &environment }, &jobs, 3);
    try std.testing.expect(jobs[0].ok);
    try std.testing.expect(jobs[0].compile_ns != null and jobs[1].compile_ns != null);
    try std.testing.expect(jobs[2].compile_ns == null);
    try std.testing.expect(!jobs[1].ok and !jobs[2].ok);
    try std.testing.expectEqualStrings("first\n", jobs[0].log.items);
    try std.testing.expectEqualStrings("second\n", jobs[1].log.items);
    try std.testing.expect(std.mem.indexOf(u8, jobs[2].log.items, "cannot run") != null);
    // A budget of one byte admits one job at a time: the same three jobs, in order, still report.
    var serial = [_]Job{
        .{ .argv = &.{ "/bin/sh", "-c", "echo first >&2" }, .weight = 1024 },
        .{ .argv = &.{ "/bin/sh", "-c", "echo second >&2; exit 7" }, .weight = 1024 },
        .{ .argv = &.{"/nonexistent/stage-worker"}, .weight = 1024 },
    };
    try compileAll(.{ .arena = a, .backing = std.testing.allocator, .io = std.testing.io, .environment = &environment, .memory_budget_bytes = 1 }, &serial, 3);
    try std.testing.expect(serial[0].ok and !serial[1].ok and !serial[2].ok);
    try std.testing.expectEqualStrings("first\n", serial[0].log.items);
    try std.testing.expectEqualStrings("second\n", serial[1].log.items);
    try std.testing.expect(std.mem.indexOf(u8, serial[2].log.items, "cannot run") != null);
}
