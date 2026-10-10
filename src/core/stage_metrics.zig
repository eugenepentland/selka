//! Optional stage reuse and latency reporting, separate from native object counts.
const std = @import("std");
const optimization = @import("optimization_cache.zig");
const emission = @import("emission_cache.zig");
const language = @import("mylang");

/// Wall times include lookup, hashing, decoding, journal publication, and bounded
/// pack sealing for each stage. The final partial flush is reported by Storage.
pub const Times = struct { frontend: u64 = 0, lowering: u64 = 0, optimizer: u64 = 0, emission: u64 = 0, native: u64 = 0, linker: u64 = 0, frontend_phases: []const FrontendPhase = &.{} };
/// Final cache maintenance runs before a successful build's replay receipt.
pub const Storage = struct { flush_nanoseconds: u64, flush_succeeded: bool, compression: []const u8 = "zlib", reads: @import("stage_pack.zig").Statistics };
/// Frontend intervals may nest; inclusive entries must not be added to their children.
pub const FrontendPhase = struct { name: []const u8, nanoseconds: u64, inclusive: bool };
/// Counts reflect work actually restored or computed during this build.
pub const Report = struct {
    version: []const u8 = "stage-report-v3",
    nanoseconds: Times = .{},
    frontend: @import("frontend_reuse.zig").Statistics = .{},
    lowering: struct { reused: usize = 0, lowered: usize = 0, deferred: usize = 0, fallbacks: usize = 0, materialized: usize = 0, unloaded: usize = 0 } = .{},
    optimizer: optimization.Statistics = .{},
    emission: emission.Counts = .{},
    /// Indexed by semantic_cache.MissReason; counts include publication bypasses.
    frontend_misses: language.semantic_cache.MissDetail = .{},
};

/// Preserve opt-in frontend measurements after the checking session ends.
pub fn frontendPhases(a: std.mem.Allocator, profile: *language.timings.Profile) std.mem.Allocator.Error![]const FrontendPhase {
    profile.end();
    const records = profile.records.phases[0..profile.records.len];
    const result = try a.alloc(FrontendPhase, records.len);
    for (records, result) |record, *phase| phase.* = .{
        .name = record.name,
        .nanoseconds = std.math.lossyCast(u64, @max(0, record.duration_ns)),
        .inclusive = record.inclusive,
    };
    return result;
}

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
