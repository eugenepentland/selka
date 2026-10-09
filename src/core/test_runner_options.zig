//! Selection, deterministic trial inputs and bounded worker settings shared by
//! file and directory test runs. One worker budget covers both levels.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const property = @import("test_runner_property.zig");
const budget = @import("memory_budget");

/// Execution settings beyond one file's test selection.
pub const Controls = struct {
    jobs: ?usize = null,
    force: bool = false,
    cases: ?[]const u8 = null,
    timeout_ms: u32 = 60000,
    max_steps: u64 = 1000000,
    ceilings: Ceilings = .{},
    /// `--affected --against REF`: run only the tests that reach a declaration changed
    /// since the git revision REF (NEW-CORE-S5-AFFECTED-1); null runs every selected test.
    against: ?[]const u8 = null,
};

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
};

/// The old core's per-test call-depth default.
pub const default_frames: u32 = 1024;

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

/// Command options; grouped execution settings keep the public type bounded.
pub const Options = struct {
    path: []const u8,
    filter: []const u8 = "",
    json: bool = false,
    build: pipeline.Options,
    seed: ?u64 = null,
    property_runs: u32 = property.default_runs,
    controls: Controls = .{},
};

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
