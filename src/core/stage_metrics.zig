//! Optional stage reuse and latency reporting, separate from native object counts.
const std = @import("std");
const optimization = @import("optimization_cache.zig");
const emission = @import("emission_cache.zig");
const language = @import("mylang");

/// Wall times include lookup, hashing, decoding, and publication for each stage.
pub const Times = struct { frontend: u64 = 0, lowering: u64 = 0, optimizer: u64 = 0, emission: u64 = 0, native: u64 = 0, linker: u64 = 0 };
/// Counts reflect work actually restored or computed during this build.
pub const Report = struct {
    version: []const u8 = "stage-report-v1",
    nanoseconds: Times = .{},
    frontend: @import("frontend_reuse.zig").Statistics = .{},
    lowering: struct { reused: usize = 0, lowered: usize = 0, deferred: usize = 0, fallbacks: usize = 0 } = .{},
    optimizer: optimization.Statistics = .{},
    emission: emission.Counts = .{},
    /// Indexed by semantic_cache.MissReason; counts include publication bypasses.
    frontend_misses: language.semantic_cache.MissCounts = @splat(0),
};

/// Monotonic timestamp used by stage measurements.
pub fn now(io: std.Io) std.Io.Timestamp {
    return std.Io.Timestamp.now(io, .awake);
}

/// Elapsed nanoseconds, clamped for clocks that do not advance.
pub fn elapsed(io: std.Io, start: std.Io.Timestamp) u64 {
    return std.math.lossyCast(u64, @max(0, start.durationTo(now(io)).nanoseconds));
}

/// Reserve at most one GiB for concurrent transient work, and at most a quarter
/// of current available memory. An oversized individual unit runs alone.
pub fn workerBudget(io: std.Io) usize {
    const free = @import("memory_budget").available(io) orelse (4 << 30);
    return @intCast(@min(1 << 30, free / 4));
}
