//! Selection, deterministic trial inputs and bounded worker settings shared by
//! file and directory test runs. One worker budget covers both levels.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const property = @import("test_runner_property.zig");
const campaign_contract = @import("property_campaign_contract.zig");
const budget = @import("memory_budget");
const policy = @import("selka").shared_cache_policy;
const shared_store = @import("test_shared_store.zig");

/// Execution settings beyond one file's test selection.
pub const Controls = struct {
    jobs: ?usize = null,
    force: bool = false,
    cases: ?[]const u8 = null,
    timeout_ms: u32 = 60000,
    max_steps: u64 = default_steps,
    ceilings: Ceilings = .{},
    /// Which of the discovered tests the run selects besides the filter.
    scope: Scope = .{},
};

/// Which discovered tests a run selects besides `--filter`.
pub const Scope = struct {
    /// `--affected --against REF`: run only the tests that reach a declaration changed
    /// since the git revision REF (NEW-CORE-S5-AFFECTED-1); null runs every selected test.
    against: ?[]const u8 = null,
    /// The modules (paths relative to the entry's root) whose tests another root of a directory run owns
    /// (`--skip-test-modules`, D-TL2-3): this root runs none of their tests but those its own cases file names. Null (or
    /// nothing to skip) runs every test the entry's closure declares, as a single-file run does.
    skipped: ?[]const []const u8 = null,
    /// `--allow-host`: a test that declares `host: Host` receives the live Host, so it can call C (D-FFI-7). Without it
    /// such a test fails before it is built. A test with a live Host never stores or serves a recorded result.
    allow_host: bool = false,
    /// `--import-root DIR`: DIR is the import root of the entry, which a directory run gave it because its own folder cannot
    /// serve its imports and no `selka.json` governs it (`project_entry.resolveUnder`). Null leaves the entry's own root.
    under: ?[]const u8 = null,
    /// The same, for every root of a directory run in this process: entry path to import root. Null in a single-file run.
    placed: ?*const Placed = null,

    /// The import root a directory run gave the entry at `path`, or null when the entry keeps its own.
    pub fn importRoot(self: Scope, path: []const u8) ?[]const u8 {
        if (self.under) |directory| return directory;
        const map = self.placed orelse return null;
        return map.get(path);
    }
};

/// The import root a directory run gave each root whose own folder cannot serve its imports, by the root's path.
pub const Placed = std.StringHashMapUnmanaged([]const u8);

/// A test child's call-depth and byte ceilings, with the old core's defaults and
/// meaning (docs/tooling/runtime-budgets.md), and which ceilings the command line named
/// (`Controls.max_steps` included). A command-line value is explicit and outranks
/// `SELKA_MEMORY_LIMIT` and the project's `limits.test`; `resolve` fills in the rest.
pub const Ceilings = struct {
    /// Nested calls of original program functions one trial may make (`--max-frames`).
    frames: u32 = default_frames,
    /// Bytes the trial's managed heap may hold (`--max-memory`); zero removes the ceiling.
    memory: u64 = budget.test_default,
    explicit_frames: bool = false,
    explicit_memory: bool = false,
    /// `--max-steps` was given, so the project's `limits.test.max_steps` does not apply.
    explicit_steps: bool = false,
    /// `--threads N`: the task threads each test child runs (E1c); null runs one thread. Not part of any receipt key.
    threads: ?u64 = null,
};

/// The environment a test child runs in (E1c): the caller's, with `SELKA_THREADS` set to the `--threads` count, or to 1, so a
/// test child runs one task thread unless the command line asks for more.
pub fn childEnvironment(a: std.mem.Allocator, environment: *const std.process.Environ.Map, threads: ?u64) std.mem.Allocator.Error!std.process.Environ.Map {
    var child = try environment.clone(a);
    // A test process reads `TMPDIR` and the cache variables as the caller set them, not as the project's `stores` did.
    @import("selka").store_settings.guestEnvironment(&child);
    try child.put("SELKA_THREADS", try std.fmt.allocPrint(a, "{d}", .{threads orelse 1}));
    return child;
}

/// The old core's per-test call-depth default.
pub const default_frames: u32 = 1024;

/// The old core's per-test step default.
pub const default_steps: u64 = 1000000;

/// The budgets a run's test processes got because nothing named them: a flag, `SELKA_*` or the project's `limits.test` that set a
/// budget leaves its field zero, so a trap of it keeps the runtime's advice (`property_execute.Defaults`).
pub fn unnamedBudgets(controls: Controls) @import("property_execute.zig").Defaults {
    const ceilings = controls.ceilings;
    return .{
        .steps = if (ceilings.explicit_steps or controls.max_steps != default_steps) 0 else default_steps,
        .frames = if (ceilings.explicit_frames or ceilings.frames != default_frames) 0 else default_frames,
    };
}

/// Why ceilings cannot be resolved: malformed `SELKA_MEMORY_LIMIT` text.
pub const CeilingError = budget.Error;

/// Fill in the ceilings the command line left open: frames from the project's
/// `max_frames`, else the default; memory from `SELKA_MEMORY_LIMIT`, else the
/// project's `max_memory`, else the 512 MiB test default.
pub fn resolve(ceilings: Ceilings, environment: *const std.process.Environ.Map, configured_frames: ?u64, configured_memory: ?u64) CeilingError!Ceilings {
    var resolved = ceilings;
    if (!ceilings.explicit_frames) resolved.frames = if (configured_frames) |frames| @intCast(@min(frames, std.math.maxInt(u32))) else default_frames;
    if (!ceilings.explicit_memory) resolved.memory = try budget.resolve(null, environment, budget.variable, configured_memory orelse budget.test_default);
    return resolved;
}

/// The refusal for a frame budget whose stack (32 KiB per frame plus 8 MiB) the
/// byte ceiling cannot back, judged as the old core judges it, or null when it fits.
pub fn frameRefusal(a: std.mem.Allocator, environment: *const std.process.Environ.Map, ceilings: Ceilings) std.mem.Allocator.Error!?[]u8 {
    return budget.frameRefusalUnder(a, .{ .command = "test", .who = "a test" }, ceilings.frames, ceilings.memory, budget.guestAddressSpaceLimit(environment));
}

/// Generated-property policy and deterministic input budget.
pub const PropertyOptions = struct {
    seed: ?u64 = null,
    runs: u32 = property.default_runs,
    policy: campaign_contract.Policy = .legacy,
};

/// Command options; grouped execution settings keep the public type bounded.
pub const Options = struct {
    path: []const u8,
    filter: []const u8 = "",
    json: bool = false,
    build: pipeline.Options,
    properties: PropertyOptions = .{},
    controls: Controls = .{},
    /// Opt-in shared test receipts; empty explicitly disables environment selection.
    shared_cache: ?[]const u8 = null,
};

/// Environment opt-in for compatible project test receipts, separate from build caches.
pub const shared_cache_variable = "SELKA_TEST_SHARED_CACHE";

/// Resolve explicit placement before the environment; empty text disables sharing.
pub fn sharedCache(requested: ?[]const u8, environment: *const std.process.Environ.Map) ?[]const u8 {
    const directory = requested orelse environment.get(shared_cache_variable) orelse return null;
    return if (directory.len == 0) null else directory;
}

/// Resolve the receipt store once per command. An explicit flag or variable is
/// returned unchanged (an unusable one fails later, as before); an unset one takes
/// the per-user default only while `default_sharing` is on, and an unusable
/// default disables sharing (""), after one warning when the store exists.
pub fn resolveShared(init: std.process.Init, requested: ?[]const u8) error{OutOfMemory}!?[]const u8 {
    return resolveSharedWith(init, requested, policy.default_sharing);
}

fn resolveSharedWith(init: std.process.Init, requested: ?[]const u8, sharing: bool) error{OutOfMemory}!?[]const u8 {
    const a = init.arena.allocator();
    const selection = try policy.resolveWith(a, init.environ_map, .tests, requested, sharing) orelse return requested;
    if (selection.origin == .explicit) return requested;
    _ = shared_store.Store.open(a, init.io, selection.path) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        @import("selka").native_cache_retention.warnUnusable(a, init.io, selection.path, .tests, err);
        return "";
    };
    return selection.path;
}

// spec-case: SHARED-STORE-4
test "a test child runs one thread unless --threads names more (E1c)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    try environment.put("SELKA_THREADS", "8");
    var one = try childEnvironment(a, &environment, null);
    try std.testing.expectEqualStrings("1", one.get("SELKA_THREADS").?);
    var four = try childEnvironment(a, &environment, 4);
    try std.testing.expectEqualStrings("4", four.get("SELKA_THREADS").?);
    try std.testing.expectEqualStrings("8", environment.get("SELKA_THREADS").?);
}

test "an unusable default receipt store disables sharing while explicit settings pass through" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = ".cache", .data = "a file where the cache directory belongs" });
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put("HOME", root);
    const init: std.process.Init = .{
        .minimal = .{ .environ = .empty, .args = .{ .vector = &.{} } },
        .arena = &arena,
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .environ_map = &environment,
        .preopens = .empty,
    };
    try std.testing.expectEqual(@as(?[]const u8, null), try resolveSharedWith(init, null, false));
    try std.testing.expectEqualStrings("", (try resolveSharedWith(init, null, true)).?);
    try std.testing.expectEqualStrings("explicit-store", (try resolveSharedWith(init, "explicit-store", true)).?);
    try std.testing.expectEqualStrings("", (try resolveSharedWith(init, "", true)).?);
    try temporary.dir.deleteFile(std.testing.io, ".cache");
    const expected = try std.fs.path.join(a, &.{ root, ".cache", "selka", "native-tests" });
    try std.testing.expectEqualStrings(expected, (try resolveSharedWith(init, null, true)).?);
    try environment.put(shared_cache_variable, "");
    try std.testing.expectEqual(@as(?[]const u8, null), try resolveSharedWith(init, null, true));
    try std.testing.expectEqualStrings(policy.Tier.tests.variable(), shared_cache_variable);
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "shared test cache placement honors explicit override and empty suppression before environment" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try std.testing.expectEqual(@as(?[]const u8, null), sharedCache(null, &environment));
    try environment.put(shared_cache_variable, "environment-store");
    try std.testing.expectEqualStrings("environment-store", sharedCache(null, &environment).?);
    try std.testing.expectEqualStrings("explicit-store", sharedCache("explicit-store", &environment).?);
    try std.testing.expectEqual(@as(?[]const u8, null), sharedCache("", &environment));
    try environment.put(shared_cache_variable, "");
    try std.testing.expectEqual(@as(?[]const u8, null), sharedCache(null, &environment));
}

/// Resolve one bounded worker width: --jobs or SELKA_JOBS when given, else the
/// available CPUs capped by how many test ceilings (each plus the address-space
/// headroom) `free` bytes hold, as the old runner sized it from `MemAvailable`
/// (NEW-CORE-S5-FANOUT-1); never more than `count` and at least one.
pub fn width(controls: Controls, environment: *const std.process.Environ.Map, count: usize, free: ?u64) usize {
    return budget.workers(.{
        .jobs = controls.jobs orelse environmentJobs(environment),
        .programs = count,
        .cores = std.Thread.getCpuCount() catch 1,
        .free = free,
        .ceiling = controls.ceilings.memory,
    });
}

fn environmentJobs(environment: *const std.process.Environ.Map) ?usize {
    const text = environment.get("SELKA_JOBS") orelse return null;
    const parsed = std.fmt.parseInt(usize, text, 10) catch return null;
    return if (parsed == 0) null else parsed;
}

// spec: NEW-CORE-S4-TEST-1
test "worker settings honor explicit jobs before environment and bound empty or small suites" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_JOBS", "8");
    try std.testing.expectEqual(@as(usize, 2), width(.{ .jobs = 2 }, &environment, 10, null));
    try std.testing.expectEqual(@as(usize, 8), width(.{}, &environment, 10, null));
    try std.testing.expectEqual(@as(usize, 3), width(.{}, &environment, 3, null));
    try std.testing.expectEqual(@as(usize, 1), width(.{}, &environment, 0, null));
}

// spec: NEW-CORE-S5-FANOUT-1
test "without an explicit width, workers are capped by how many test ceilings free memory holds" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const per_test = budget.test_default + budget.headroom;
    const cores = std.Thread.getCpuCount() catch 1;
    // Free memory for one 512 MiB test (plus headroom) runs one at a time; none still runs one.
    try std.testing.expectEqual(@as(usize, 1), width(.{}, &environment, 64, per_test));
    try std.testing.expectEqual(@as(usize, 1), width(.{}, &environment, 64, 0));
    try std.testing.expectEqual(@min(cores, 2), width(.{}, &environment, 64, 2 * per_test + 1));
    // A smaller per-test ceiling fits more tests in the same memory.
    var small: Controls = .{};
    small.ceilings.memory = 0;
    try std.testing.expectEqual(@min(cores, 6), width(small, &environment, 64, 6 * budget.headroom));
    // An unreadable MemAvailable leaves the CPU count; an explicit width is not capped.
    try std.testing.expectEqual(@min(cores, 64), width(.{}, &environment, 64, null));
    try std.testing.expectEqual(@as(usize, 5), width(.{ .jobs = 5 }, &environment, 64, 0));
    try environment.put("SELKA_JOBS", "4");
    try std.testing.expectEqual(@as(usize, 4), width(.{}, &environment, 64, 0));
}
