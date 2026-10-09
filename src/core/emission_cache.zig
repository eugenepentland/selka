//! Persistent completed LLVM artifacts and bounded emission admission.
const std = @import("std");
const store = @import("stage_store.zig");
const deferred = @import("deferred_facts.zig");

/// Only completed artifacts count as hits; helper seed hits are reported separately.
pub const Counts = struct { units: u32 = 0, reused: u32 = 0, rendered: u32 = 0, seeds_reused: u32 = 0, seeds_rendered: u32 = 0, workers: u32 = 0 };

/// Scratch backing must be thread-safe; the result allocator stays on the coordinator.
pub const Context = struct {
    store: *const store.Store,
    lanes: usize = 1,
    /// Conservative admission estimate: one oversized unit runs alone.
    memory_budget_bytes: usize = 1 << 30,
    counts: ?*Counts = null,
    /// Verified immutable fact payloads; decode only after a completed LLVM miss.
    deferred: ?*const deferred.Table = null,
};

/// Integrity-protected payload; metadata never lives in a separate unchecked file.
pub const Artifact = struct {
    text: []const u8,
    number: bool,
    math: bool,
    counting: bool,
};

/// Estimate the scratch held while planning memory homes and rendering instructions.
pub fn weight(instructions: usize) usize {
    return std.math.mul(usize, @max(1, instructions), 4096) catch std.math.maxInt(usize);
}

/// Admit up to the job and byte budgets; an oversized job can always run alone.
pub fn batch(weights: []const usize, lanes: usize, budget: usize) usize {
    if (weights.len == 0) return 0;
    var total: usize = 0;
    var count: usize = 0;
    for (weights[0..@min(@max(1, lanes), weights.len)]) |bytes| {
        const next = std.math.add(usize, total, bytes) catch break;
        if (count != 0 and next > budget) break;
        total = next;
        count += 1;
    }
    return @max(1, count);
}
