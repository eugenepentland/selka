//! What the engine did, per kind (spec §11): how many queries it served, validated, recomputed, cut off early and
//! verified, and the time spent looking records up, validating them and computing. Counters are atomic so queries
//! on many threads add to them without a lock; the report is one JSON line.
const std = @import("std");

/// The most kinds one engine registers.
pub const max_kinds = 32;

/// Something counted per kind.
pub const Counter = enum {
    /// Queries answered from a record without running the kind (verified ones included).
    served,
    /// Records whose reads were walked, served or found stale.
    validated,
    /// Kind bodies run to answer a query (verify runs excluded).
    recomputed,
    /// Recomputations of a dependency whose result digest was unchanged, so its dependents stayed valid.
    early_cutoffs,
    /// Served queries recomputed by verify mode and compared.
    verified,
    /// Verified queries whose recomputed result differed.
    verify_mismatches,
    /// Sampled queries whose kind could not recompute them (it failed), so the record stands unverified.
    unverifiable,
    /// Queries answered from the process-wide memo.
    memo_hits,
    /// Records rewritten with fresh stat tuples after a hash showed their files unchanged.
    refreshed,
    /// Queries answered from a record the per-user shared tier held and the work directory did not.
    shared_hits,
    /// Records published to the shared tier (newly stored or refreshed).
    shared_published,
    /// Publications refused because the shared tier holds another result under the same key.
    shared_mismatches,
    /// Stored objects read because a caller used a served result's payload (or verify mode sampled it): a served query
    /// whose payload nobody asks for opens none.
    object_reads,
    /// Objects found absent or damaged when read, so the query was run again (counted also in `recomputed`).
    object_misses,
};

/// Time spent per kind.
pub const Timer = enum { lookup, validate, compute };

const counter_count = std.enums.values(Counter).len;
const timer_count = std.enums.values(Timer).len;

/// A frozen copy of one kind's numbers.
pub const Snapshot = struct {
    counts: [counter_count]u64,
    nanoseconds: [timer_count]u64,

    /// The number counted for `which`.
    pub fn count(self: Snapshot, which: Counter) u64 {
        return self.counts[@backingInt(which)];
    }

    /// One timer, in nanoseconds.
    pub fn time(self: Snapshot, which: Timer) u64 {
        return self.nanoseconds[@backingInt(which)];
    }
};

const Slot = struct {
    counts: [counter_count]std.atomic.Value(u64) = @splat(.init(0)),
    nanoseconds: [timer_count]std.atomic.Value(u64) = @splat(.init(0)),
};

/// The numbers of every registered kind.
pub const Stats = struct {
    slots: [max_kinds]Slot = @splat(.{}),

    /// Count one `which` for the kind registered at `kind`.
    pub fn add(self: *Stats, kind: usize, which: Counter) void {
        _ = self.slots[kind].counts[@backingInt(which)].fetchAdd(1, .monotonic);
    }

    /// Add `nanoseconds` to the `which` timer of the kind registered at `kind`.
    pub fn addTime(self: *Stats, kind: usize, which: Timer, nanoseconds: u64) void {
        _ = self.slots[kind].nanoseconds[@backingInt(which)].fetchAdd(nanoseconds, .monotonic);
    }

    /// The numbers of the kind registered at `kind`.
    pub fn snapshot(self: *const Stats, kind: usize) Snapshot {
        var out: Snapshot = undefined;
        for (&out.counts, self.slots[kind].counts) |*to, from| to.* = from.load(.monotonic);
        for (&out.nanoseconds, self.slots[kind].nanoseconds) |*to, from| to.* = from.load(.monotonic);
        return out;
    }
};

/// The time on the monotonic clock, for timing a step.
pub fn tick(io: std.Io) i96 {
    return std.Io.Timestamp.now(io, .awake).nanoseconds;
}

/// Write the report line for `names` (the registered kinds, in registration order): `{"engine-report-v1":{"kinds":
/// [{"kind":...,"served":...}]}}` and a newline.
pub fn writeReport(writer: *std.Io.Writer, stats: *const Stats, names: []const []const u8) std.Io.Writer.Error!void {
    try writer.writeAll("{\"engine-report-v1\":{\"kinds\":[");
    for (names, 0..) |name, index| {
        if (index != 0) try writer.writeAll(",");
        const numbers = stats.snapshot(index);
        try writer.print("{{\"kind\":\"{s}\"", .{name});
        for (std.enums.values(Counter)) |which| try writer.print(",\"{s}\":{d}", .{ @tagName(which), numbers.count(which) });
        for (std.enums.values(Timer)) |which| try writer.print(",\"{s}_ns\":{d}", .{ @tagName(which), numbers.time(which) });
        try writer.writeAll("}");
    }
    try writer.writeAll("]}}\n");
}

test "counters and timers add up per kind and snapshot independently" {
    var stats: Stats = .{};
    stats.add(0, .served);
    stats.add(0, .served);
    stats.add(1, .recomputed);
    stats.addTime(1, .compute, 500);
    try std.testing.expectEqual(@as(u64, 2), stats.snapshot(0).count(.served));
    try std.testing.expectEqual(@as(u64, 0), stats.snapshot(0).count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), stats.snapshot(1).count(.recomputed));
    try std.testing.expectEqual(@as(u64, 500), stats.snapshot(1).time(.compute));
}

test "the report is one JSON line naming every kind and every number" {
    var stats: Stats = .{};
    stats.add(0, .served);
    stats.add(1, .early_cutoffs);
    var buffer: [2048]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try writeReport(&writer, &stats, &.{ "test-plan", "test-exec" });
    const line = writer.buffered();
    try std.testing.expect(std.mem.endsWith(u8, line, "\n"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, line, "\n"));
    try std.testing.expect(std.mem.indexOf(u8, line, "\"kind\":\"test-plan\",\"served\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"kind\":\"test-exec\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"early_cutoffs\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"validate_ns\":0") != null);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, line, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.object.get("engine-report-v1").?.object.get("kinds").?.array.items.len);
}
