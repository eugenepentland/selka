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
const target_policy = @import("target.zig");

/// A BLAKE3 digest: store keys and content identities.
pub const Digest = [32]u8;

/// The version of how an object is produced from a unit's text: the compile
/// command below and the meaning of the text the emitter writes. Bump it when
/// either changes in a way the text itself does not show.
pub const format = "core-unit-object-v1";

/// Why a store or compile operation failed; tool output goes to the caller's log.
pub const Error = error{ ToolFailed, OutOfMemory, WriteFailed };

/// A file the build read, by absolute path, and its content digest; null records
/// that the file was absent.
pub const Dependency = struct { path: []const u8, digest: ?Digest };

/// Everything besides a unit's text that decides its object.
pub const Settings = struct {
    /// The toolchain's content identity (`tool_identity.Identity.digest`).
    tool: Digest,
    /// The resolved host CPU and code-generation flags (`tool_identity.nativeTarget`),
    /// so a store copied to another machine cannot serve an object for the wrong CPU.
    cpu: Digest,
    mode: @import("build_mode.zig").Mode = .optimized_debug,
    /// The core runtime's ABI, identified by its complete source.
    runtime: Digest,
};

/// The store key of one unit: `format`, the optimization level, the target
/// triple, the CPU flags and the resolved CPU, the toolchain, the runtime ABI and
/// the unit's exact text. Fields are length-delimited.
pub fn key(settings: Settings, text: []const u8) Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, format);
    field(&hash, settings.mode.level());
    field(&hash, target_policy.native_link_target);
    for (target_policy.current.cpu_flags) |flag| field(&hash, flag);
    field(&hash, &settings.cpu);
    field(&hash, &settings.tool);
    field(&hash, &settings.runtime);
    field(&hash, text);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// Hash one length-delimited field, so adjacent fields cannot run together.
pub fn field(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
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
        return std.fmt.allocPrint(arena, "{s}/{s}{s}", .{ self.directory, std.fmt.bytesToHex(digest, .lower), suffix });
    }

    /// The entry's path when it exists and its bytes match its recorded size and
    /// digest; anything else (absent, truncated, overwritten, no record) is a miss.
    pub fn lookup(self: Store, arena: std.mem.Allocator, io: std.Io, digest: Digest, suffix: []const u8) Error!?Found {
        const object = try self.path(arena, digest, suffix);
        const recorded = try readSum(arena, io, try std.fmt.allocPrint(arena, "{s}.sum", .{object})) orelse return null;
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, object, arena, .limited(recorded.size + 1)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        defer arena.free(bytes);
        if (bytes.len != recorded.size) return null;
        var actual: Digest = undefined;
        std.crypto.hash.Blake3.hash(bytes, &actual, .{});
        if (!std.mem.eql(u8, &actual, &recorded.digest)) return null;
        return .{ .path = object, .digest = actual };
    }

    /// A fresh private name beside the entry for `digest`, on the store's own file
    /// system, for a file `publish` will rename into place.
    pub fn partial(self: Store, arena: std.mem.Allocator, io: std.Io, digest: Digest, suffix: []const u8) Error![]const u8 {
        std.Io.Dir.cwd().createDirPath(io, self.directory) catch return error.WriteFailed;
        var nonce: [16]u8 = undefined;
        std.Io.random(io, &nonce);
        return std.fmt.allocPrint(arena, "{s}.{s}.partial", .{ try self.path(arena, digest, suffix), std.fmt.bytesToHex(nonce, .lower) });
    }

    /// Publish `staged` (this build's private file, on the store's file system) as the entry for `digest`:
    /// write its record, then rename the file and the record into place. A reader
    /// that sees one without the other, or another build's equal copy, either
    /// verifies or misses; it never links an unverified file.
    pub fn publish(self: Store, arena: std.mem.Allocator, io: std.Io, digest: Digest, suffix: []const u8, staged: []const u8) Error!Found {
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(io, self.directory) catch return error.WriteFailed;
        const bytes = cwd.readFileAlloc(io, staged, arena, .unlimited) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.WriteFailed;
        };
        defer arena.free(bytes);
        var actual: Digest = undefined;
        std.crypto.hash.Blake3.hash(bytes, &actual, .{});
        const object = try self.path(arena, digest, suffix);
        const sum = try std.fmt.allocPrint(arena, "{s}.sum", .{object});
        var nonce: [16]u8 = undefined;
        std.Io.random(io, &nonce);
        const record_partial = try std.fmt.allocPrint(arena, "{s}.{s}.partial", .{ sum, std.fmt.bytesToHex(nonce, .lower) });
        defer removeFile(io, record_partial);
        const record = try std.fmt.allocPrint(arena, "{s}\n{d}\n{s}\n", .{ sum_magic, bytes.len, std.fmt.bytesToHex(actual, .lower) });
        cwd.writeFile(io, .{ .sub_path = record_partial, .data = record }) catch return error.WriteFailed;
        cwd.rename(staged, cwd, object, io) catch return error.WriteFailed;
        cwd.rename(record_partial, cwd, sum, io) catch return error.WriteFailed;
        return .{ .path = object, .digest = actual };
    }
};

const sum_magic = "core-unit-sum-v1";
const Sum = struct { size: usize, digest: Digest };

fn readSum(arena: std.mem.Allocator, io: std.Io, path: []const u8) Error!?Sum {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(256)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    if (!std.mem.eql(u8, lines.next() orelse return null, sum_magic)) return null;
    const size = std.fmt.parseInt(usize, lines.next() orelse return null, 10) catch return null;
    const hex = lines.next() orelse return null;
    if (hex.len != 64 or !std.mem.eql(u8, lines.rest(), "")) return null;
    var digest: Digest = undefined;
    _ = std.fmt.hexToBytes(&digest, hex) catch return null;
    return .{ .size = size, .digest = digest };
}

/// One `zig cc` invocation and its captured diagnostics.
pub const Job = struct {
    argv: []const []const u8,
    /// Bigger jobs start first (longest-processing-time order).
    weight: usize,
    log: std.ArrayList(u8) = .empty,
    ok: bool = false,
};

/// What every job of a `compileAll` shares.
pub const Resources = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    /// Reclaiming thread-safe backing; absent callers execute serially.
    backing: ?std.mem.Allocator = null,
    /// Admission budget for estimated child memory, independent of job count.
    memory_budget_bytes: usize = 1 << 30,
};

/// How many compiles run at once: `MYLANG_JOBS`, else the CPUs this process may
/// use (its affinity mask, so a build slot's CPU set is respected), at most
/// `count` and at least one.
pub fn width(environment: *const std.process.Environ.Map, count: usize) usize {
    const requested = blk: {
        const text = environment.get("MYLANG_JOBS") orelse break :blk null;
        const parsed = std.fmt.parseInt(usize, text, 10) catch break :blk null;
        break :blk if (parsed == 0) null else parsed;
    } orelse (std.Thread.getCpuCount() catch 1);
    return @min(@max(1, requested), @max(1, count));
}

/// Run every job, up to `lanes` at a time, biggest first. Each job records its
/// own success and stderr; the caller decides what a failure means.
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
    var start: usize = 0;
    while (start < order.len) {
        const count = admitted(jobs, order[start..], lanes, resources.memory_budget_bytes);
        try compileBatch(resources, jobs, order[start..][0..count], threads);
        start += count;
    }
}

/// Reserve a baseline per clang plus an estimate proportional to its LLVM input.
/// One unusually large unit still makes progress, alone.
pub fn admitted(jobs: []const Job, order: []const usize, lanes: usize, budget: usize) usize {
    if (order.len == 0) return 0;
    var total: usize = 0;
    var count: usize = 0;
    for (order[0..@min(@max(1, lanes), order.len)]) |index| {
        const estimate = (64 << 20) +| (jobs[index].weight *| 64);
        const next = total +| estimate;
        if (count != 0 and next > budget) break;
        total = next;
        count += 1;
    }
    return @max(1, count);
}

fn compileBatch(resources: Resources, jobs: []Job, order: []const usize, threads: []std.Thread) Error!void {
    var queue: Queue = .{ .resources = resources, .jobs = jobs, .order = order };
    var started: usize = 0;
    for (threads[0..@min(threads.len, order.len - 1)]) |*thread| {
        thread.* = std.Thread.spawn(.{}, Queue.drain, .{&queue}) catch break;
        started += 1;
    }
    queue.drain();
    for (threads[0..started]) |thread| thread.join();
    // Workers own only backing-allocated logs. Copy them in deterministic order
    // after joining, so no worker ever touches the coordinator's arena.
    const copied = capture: {
        defer for (order) |index| {
            jobs[index].log.deinit(resources.backing.?);
            jobs[index].log = .empty;
        };
        const logs = try resources.arena.alloc(std.ArrayList(u8), order.len);
        for (order, logs) |index, *log| {
            const bytes = try resources.arena.dupe(u8, jobs[index].log.items);
            log.* = .{ .items = bytes, .capacity = bytes.len };
        }
        break :capture logs;
    };
    for (order, copied) |index, log| jobs[index].log = log;
    if (queue.exhausted.load(.acquire)) return error.OutOfMemory;
}

fn heavier(jobs: []Job, left: usize, right: usize) bool {
    if (jobs[left].weight != jobs[right].weight) return jobs[left].weight > jobs[right].weight;
    return left < right;
}

const Queue = struct {
    resources: Resources,
    jobs: []Job,
    order: []const usize,
    next: std.atomic.Value(usize) = .init(0),
    exhausted: std.atomic.Value(bool) = .init(false),

    fn drain(self: *Queue) void {
        while (true) {
            const at = self.next.fetchAdd(1, .monotonic);
            if (at >= self.order.len) return;
            const job = &self.jobs[self.order[at]];
            // Only allocation failure ends the queue; a tool failure is the job's verdict.
            runIsolated(self.resources, job) catch {
                self.exhausted.store(true, .release);
                return;
            };
        }
    }
};

fn runIsolated(resources: Resources, job: *Job) error{OutOfMemory}!void {
    const backing = resources.backing.?;
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    var local: Job = .{ .argv = job.argv, .weight = job.weight };
    var private = resources;
    private.arena = scratch.allocator();
    try runJob(private, &local);
    const bytes = try backing.dupe(u8, local.log.items);
    job.log = .{ .items = bytes, .capacity = bytes.len };
    job.ok = local.ok;
}

fn runJob(resources: Resources, job: *Job) error{OutOfMemory}!void {
    const result = @import("process_spawn.zig").run(resources.arena, resources.io, .{ .argv = job.argv, .environment = .{ .map = resources.environment } }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try job.log.print(resources.arena, "error: cannot run {s}: {s}\n", .{ job.argv[0], @errorName(err) });
        return;
    };
    try job.log.appendSlice(resources.arena, result.stderr);
    job.ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
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
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(256 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (err == error.FileNotFound) return null;
        return error.ReadFailed;
    };
    defer arena.free(bytes);
    var digest: Digest = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return digest;
}

/// Whether every dependency still has its recorded bytes (or is still absent).
pub fn unchanged(arena: std.mem.Allocator, io: std.Io, dependencies: []const Dependency) error{OutOfMemory}!bool {
    for (dependencies) |dependency| {
        const current = fileDigest(arena, io, dependency.path) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return false;
        };
        if ((current == null) != (dependency.digest == null)) return false;
        if (current) |digest| if (!std.mem.eql(u8, &digest, &dependency.digest.?)) return false;
    }
    return true;
}

fn removeFile(io: std.Io, path: []const u8) void {
    // A published partial already moved away; otherwise discard this build's file.
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

// spec: NEW-CORE-S4-CACHE-1
test "unit keys cover the text, level, toolchain, CPU and runtime, and fields cannot run together" {
    const base: Settings = .{ .tool = @splat(1), .cpu = @splat(2), .mode = .debug, .runtime = @splat(3) };
    const original = key(base, "define i32 @f()");
    try std.testing.expectEqual(original, key(base, "define i32 @f()"));
    try std.testing.expect(!std.mem.eql(u8, &original, &key(base, "define i32 @g()")));
    var changed = base;
    changed.mode = .release;
    try std.testing.expect(!std.mem.eql(u8, &original, &key(changed, "define i32 @f()")));
    const release_key = key(changed, "define i32 @f()");
    changed = base;
    changed.mode = .optimized_debug;
    try std.testing.expectEqualStrings("-O2", changed.mode.level());
    try std.testing.expect(!std.mem.eql(u8, &original, &key(changed, "define i32 @f()")));
    try std.testing.expect(!std.mem.eql(u8, &release_key, &key(changed, "define i32 @f()")));
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
    const store: Store = .{ .directory = try std.fs.path.join(a, &.{ root, "units" }) };
    const digest: Digest = @splat(5);
    try std.testing.expectEqual(@as(?Found, null), try store.lookup(a, std.testing.io, digest, ".o"));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "staged.o", .data = "object bytes" });
    const entry = try store.publish(a, std.testing.io, digest, ".o", try std.fs.path.join(a, &.{ root, "staged.o" }));
    const published = entry.path;
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
    var job: Job = .{ .argv = &.{"/nonexistent/mylang-core-test/zig"}, .weight = 1 };
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
test "compile width follows MYLANG_JOBS, else the CPUs, and never exceeds the work" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_JOBS", "3");
    try std.testing.expectEqual(@as(usize, 3), width(&environment, 10));
    try std.testing.expectEqual(@as(usize, 2), width(&environment, 2));
    try std.testing.expectEqual(@as(usize, 1), width(&environment, 0));
    try environment.put("MYLANG_JOBS", "0");
    try std.testing.expect(width(&environment, 1000) >= 1);
}

// spec: NEW-CORE-STAGE-CACHE-6
test "native stage admission bounds simultaneous memory and isolated workers preserve diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try std.testing.environ.createMap(a);
    var jobs = [_]Job{
        .{ .argv = &.{ "/bin/sh", "-c", "echo first >&2" }, .weight = 1024 },
        .{ .argv = &.{ "/bin/sh", "-c", "echo second >&2; exit 7" }, .weight = 1024 },
        .{ .argv = &.{"/nonexistent/stage-worker"}, .weight = 1024 },
    };
    try std.testing.expectEqual(@as(usize, 1), admitted(&jobs, &.{ 0, 1, 2 }, 3, 1));
    try std.testing.expectEqual(@as(usize, 2), admitted(&jobs, &.{ 0, 1, 2 }, 3, 150 << 20));
    try std.testing.expectEqual(@as(usize, 1), admitted(&jobs, &.{ 0, 1, 2 }, 1, 1 << 30));
    try compileAll(.{ .arena = a, .backing = std.testing.allocator, .io = std.testing.io, .environment = &environment }, &jobs, 3);
    try std.testing.expect(jobs[0].ok);
    try std.testing.expect(!jobs[1].ok and !jobs[2].ok);
    try std.testing.expectEqualStrings("first\n", jobs[0].log.items);
    try std.testing.expectEqualStrings("second\n", jobs[1].log.items);
    try std.testing.expect(std.mem.indexOf(u8, jobs[2].log.items, "cannot run") != null);
}
