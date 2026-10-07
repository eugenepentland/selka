//! Selection, deterministic trial inputs and bounded worker settings shared by
//! file and directory test runs. One worker budget covers both levels.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const property = @import("test_runner_property.zig");

/// Execution settings beyond one file's test selection.
pub const Controls = struct {
    jobs: ?usize = null,
    force: bool = false,
    cases: ?[]const u8 = null,
    timeout_ms: u32 = 60000,
    max_steps: u64 = 1000000,
    explicit_steps: bool = false,
};

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

/// Resolve one bounded worker width from --jobs, MYLANG_JOBS or available CPUs.
pub fn width(controls: Controls, environment: *const std.process.Environ.Map, count: usize) usize {
    const requested = controls.jobs orelse environmentJobs(environment) orelse (std.Thread.getCpuCount() catch 1);
    return @min(@max(1, requested), @max(1, count));
}

fn environmentJobs(environment: *const std.process.Environ.Map) ?usize {
    const text = environment.get("MYLANG_JOBS") orelse return null;
    const parsed = std.fmt.parseInt(usize, text, 10) catch return null;
    return if (parsed == 0) null else parsed;
}

// spec: NEW-CORE-S4-TEST-1
test "worker settings honor explicit jobs before environment and bound empty or small suites" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_JOBS", "8");
    try std.testing.expectEqual(@as(usize, 2), width(.{ .jobs = 2 }, &environment, 10));
    try std.testing.expectEqual(@as(usize, 8), width(.{}, &environment, 10));
    try std.testing.expectEqual(@as(usize, 3), width(.{}, &environment, 3));
    try std.testing.expectEqual(@as(usize, 1), width(.{}, &environment, 0));
}
