//! Process-lifetime state of the unit suites' guest runner (`native_execute.zig`,
//! NEW-CORE-S5-UNITS-1): the `selka` executable the build names, the toolchain,
//! the suite cache as an absolute real path and the few variables the compiler and
//! its tools need. Only the process wiring owns mutable global state, so the session
//! lives here and `native_execute.zig` stays an adapter.
const std = @import("std");
const harness = @import("native_test_options");

/// A host failure (a directory, the compiler's path) while opening the session.
pub const Error = error{ OutOfMemory, NativeHostFailed };

/// Where `zig` keeps its global cache and the core its compiled runtime and toolchain
/// identities (under `XDG_CACHE_HOME`). A run's
/// environment is the guest's too, so these are named outright: a test that gives the
/// guest its own `HOME` does not move the compiler's caches.
const zig_cache = "ZIG_GLOBAL_CACHE_DIR";
const runtime_cache = "SELKA_CORE_RUNTIME_CACHE";
const xdg_cache = "XDG_CACHE_HOME";

/// One test process's runner: the compiler, its toolchain and cache, and an arena
/// for what outlives a single run (captured output).
pub const Session = struct {
    arena: std.heap.ArenaAllocator,
    io: std.Io,
    /// The `selka` executable, by absolute path.
    compiler: []const u8,
    zig: []const u8,
    /// The suite cache, as an absolute real path, so trap paths can be mapped back.
    cache: []const u8,
    /// The variables the compiler needs, added to every run's environment.
    base: std.process.Environ.Map,
    /// Distinguishes this process's staging directories.
    staged: u32 = 0,

    /// Allocate values that outlive a single guest execution, such as captured output.
    pub fn allocator(self: *Session) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// The compiler's environment: `guest` (or an empty one), plus what the compiler needs.
    pub fn environment(self: *Session, guest: ?*const std.process.Environ.Map) Error!*std.process.Environ.Map {
        const map = try self.allocator().create(std.process.Environ.Map);
        map.* = if (guest) |given| try given.clone(self.allocator()) else .init(self.allocator());
        var needed = self.base.iterator();
        while (needed.next()) |entry| if (map.get(entry.key_ptr.*) == null) try map.put(entry.key_ptr.*, entry.value_ptr.*);
        return map;
    }
};

var session: ?Session = null;
/// How many guest runs one `native_execute.runAll` keeps going at once.
var batch_lanes: usize = 1;

/// The width of a batch of guest runs (NEW-CORE-S5-UNITS-BATCH-1), set when the
/// session opens: `SELKA_UNIT_JOBS`, else at most eight lanes. Both choices
/// stay within this process's CPU share among `SELKA_UNIT_SHARDS` roots.
pub fn lanes() usize {
    return batch_lanes;
}

/// The batch width cannot exceed the CPU share, even with an explicit override.
/// The build runner separately bounds the number of concurrent root processes.
fn lanesFor(jobs: ?[]const u8, shards: ?[]const u8, cpus: usize) usize {
    return @min(positive(jobs) orelse 8, cpuShare(shards, cpus));
}

fn cpuShare(shards: ?[]const u8, cpus: usize) usize {
    return @max(1, cpus / (positive(shards) orelse 1));
}

/// Each guest compiler gets a fraction of its parent's budget, not the whole
/// affinity mask again. Together, batch lanes and compiler lanes fit the share.
fn compilerLanesFor(jobs: ?[]const u8, batch: usize, shards: ?[]const u8, cpus: usize) usize {
    const share = @max(1, cpuShare(shards, cpus) / @max(1, batch));
    return @min(positive(jobs) orelse share, share);
}

fn positive(text: ?[]const u8) ?usize {
    const value = std.fmt.parseInt(usize, text orelse return null, 10) catch return null;
    return if (value == 0) null else value;
}

/// Open, or reuse, this process's runner session.
pub fn acquire() Error!*Session {
    if (session) |*existing| return existing;
    // The session outlives every individual test, so it cannot be charged to a
    // test allocator that verifies release at the end of each one. // allocator-ok
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = arena.allocator();
    const io = std.testing.io;
    const relative = try std.fs.path.join(a, &.{ harness.cache_directory, "core" });
    std.Io.Dir.cwd().createDirPath(io, relative) catch return error.NativeHostFailed;
    const cache = std.Io.Dir.cwd().realPathFileAlloc(io, relative, a) catch return error.NativeHostFailed;
    const compiler = std.Io.Dir.cwd().realPathFileAlloc(io, @import("test_paths").corePath(), a) catch return error.NativeHostFailed;
    const zig = std.Io.Dir.cwd().realPathFileAlloc(io, harness.zig_path, a) catch harness.zig_path;
    var base: std.process.Environ.Map = .init(a);
    const process = std.testing.environ.createMap(a) catch return error.NativeHostFailed;
    // Tools keep their caches where the user's do; the scratch directory is the caller's.
    // The core keeps its toolchain identities under the user's cache directory too.
    try base.put(xdg_cache, try userCache(a, &process, xdg_cache, "", cache));
    try base.put(zig_cache, try userCache(a, &process, zig_cache, "zig", cache));
    try base.put(runtime_cache, try userCache(a, &process, runtime_cache, "selka/core-runtime", cache));
    try inheritSharedStores(&base, &process);
    if (process.get("TMPDIR")) |scratch| try base.put("TMPDIR", scratch);
    const cpus = std.Thread.getCpuCount() catch 1;
    const shards = process.get("SELKA_UNIT_SHARDS");
    batch_lanes = lanesFor(process.get("SELKA_UNIT_JOBS"), shards, cpus);
    // `environment` constructs a fresh map rather than inheriting the process.
    // Without this entry, each child silently sizes its compiler for all CPUs.
    try base.put("SELKA_JOBS", try std.fmt.allocPrint(a, "{d}", .{compilerLanesFor(process.get("SELKA_JOBS"), batch_lanes, shards, cpus)}));
    session = .{ .arena = arena, .io = io, .compiler = compiler, .zig = zig, .cache = cache, .base = base };
    return &session.?;
}

/// Preserve explicit shared-store selection, including an empty value that
/// disables sharing. An unset compiler-artifact or test-receipt selector keeps the
/// compiler's ordinary default. An unset stage-store selector means no stage store:
/// its default is the user's own `~/.cache/selka/stage-artifacts`, and a unit
/// suite's 1,100 guest builds would fill it (round 13).
fn inheritSharedStores(base: *std.process.Environ.Map, process: *const std.process.Environ.Map) error{OutOfMemory}!void {
    for ([_][]const u8{ "SELKA_COMPILER_SHARED_CACHE", "SELKA_TEST_SHARED_CACHE" }) |name| {
        if (process.get(name)) |value| try base.put(name, value);
    }
    try base.put("SELKA_STAGE_SHARED_CACHE", process.get("SELKA_STAGE_SHARED_CACHE") orelse "");
}

// spec-case: NEW-CORE-S5-UNITS-1
test "native fixture children retain explicit shared stores and disabled sharing" {
    var selected: std.process.Environ.Map = .init(std.testing.allocator);
    defer selected.deinit();
    var inherited: std.process.Environ.Map = .init(std.testing.allocator);
    defer inherited.deinit();
    try inheritSharedStores(&inherited, &selected);
    try std.testing.expect(inherited.get("SELKA_COMPILER_SHARED_CACHE") == null);
    try std.testing.expect(inherited.get("SELKA_TEST_SHARED_CACHE") == null);
    try std.testing.expectEqualStrings("", inherited.get("SELKA_STAGE_SHARED_CACHE").?);
    try selected.put("SELKA_COMPILER_SHARED_CACHE", "selected-compiler-store");
    try selected.put("SELKA_TEST_SHARED_CACHE", "");
    try selected.put("SELKA_STAGE_SHARED_CACHE", "selected-stage-store");
    try inheritSharedStores(&inherited, &selected);
    try std.testing.expectEqualStrings("selected-compiler-store", inherited.get("SELKA_COMPILER_SHARED_CACHE").?);
    try std.testing.expectEqualStrings("", inherited.get("SELKA_TEST_SHARED_CACHE").?);
    try std.testing.expectEqualStrings("selected-stage-store", inherited.get("SELKA_STAGE_SHARED_CACHE").?);
}

/// The directory `variable` names, else `NAME` under the user's cache directory
/// (`XDG_CACHE_HOME`, else `HOME/.cache`), else under the suite cache.
fn userCache(a: std.mem.Allocator, process: *const std.process.Environ.Map, variable: []const u8, name: []const u8, fallback: []const u8) Error![]const u8 {
    if (process.get(variable)) |explicit| return explicit;
    if (process.get(xdg_cache)) |base| if (std.fs.path.isAbsolute(base)) return std.fs.path.join(a, &.{ base, name });
    if (process.get("HOME")) |home| return std.fs.path.join(a, &.{ home, ".cache", name });
    return std.fs.path.join(a, &.{ fallback, name });
}

// spec-case: NEW-CORE-S5-UNITS-1
test "the runner session resolves the compiler and an absolute suite cache once" {
    const first = try acquire();
    const second = try acquire();
    try std.testing.expectEqual(first, second);
    try std.testing.expect(std.fs.path.isAbsolute(first.compiler));
    try std.testing.expect(std.fs.path.isAbsolute(first.cache));
    try std.testing.expect(std.mem.endsWith(u8, first.cache, "/core"));
    // A run's environment keeps what the test gave it and adds only what is missing.
    var given: std.process.Environ.Map = .init(std.testing.allocator);
    defer given.deinit();
    try given.put("TMPDIR", "/given");
    const merged = try first.environment(&given);
    try std.testing.expectEqualStrings("/given", merged.get("TMPDIR").?);
    try std.testing.expect(std.fs.path.isAbsolute(merged.get(zig_cache).?));
    try std.testing.expect(std.fs.path.isAbsolute(merged.get(runtime_cache).?));
    try std.testing.expect(positive(merged.get("SELKA_JOBS")) != null);
    // The guest's own HOME stays the guest's; the compiler's caches do not follow it.
    try given.put("HOME", "/nonexistent-home");
    const moved = try first.environment(&given);
    try std.testing.expectEqualStrings(merged.get(zig_cache).?, moved.get(zig_cache).?);
    try std.testing.expectEqualStrings(merged.get(xdg_cache).?, moved.get(xdg_cache).?);
}

// spec-case: NEW-CORE-S5-UNITS-BATCH-1
test "batch and guest compiler lanes share the admitted CPUs even with explicit overrides" {
    try std.testing.expectEqual(@as(usize, 8), lanesFor(null, null, 20));
    try std.testing.expectEqual(@as(usize, 4), lanesFor(null, null, 4));
    try std.testing.expectEqual(@as(usize, 1), lanesFor(null, "12", 20));
    try std.testing.expectEqual(@as(usize, 4), lanesFor(null, "4", 16));
    try std.testing.expectEqual(@as(usize, 1), lanesFor("3", "12", 20));
    try std.testing.expectEqual(@as(usize, 2), lanesFor("999", "4", 8));
    try std.testing.expectEqual(@as(usize, 8), lanesFor("0", "zero", 16));
    try std.testing.expectEqual(@as(usize, 1), lanesFor(null, "26", 1));
    try std.testing.expectEqual(@as(usize, 1), lanesFor("999", null, 0));
    try std.testing.expectEqual(@as(usize, 1), compilerLanesFor("999", 4, "4", 16));
    try std.testing.expectEqual(@as(usize, 2), compilerLanesFor(null, 2, "4", 16));
    try std.testing.expectEqual(@as(usize, 1), compilerLanesFor("1", 1, null, 20));
    try std.testing.expectEqual(@as(usize, 1), compilerLanesFor(null, 1, "26", 20));
    for (1..33) |cpus| {
        for (1..cpus + 1) |roots| {
            var buffer: [20]u8 = undefined;
            const count = try std.fmt.bufPrint(&buffer, "{d}", .{roots});
            const batch = lanesFor("999", count, cpus);
            try std.testing.expect(roots * batch * compilerLanesFor("999", batch, count, cpus) <= cpus);
        }
    }
    try std.testing.expect(lanes() >= 1);
}
