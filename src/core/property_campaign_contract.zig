//! Versioned indexed property generation and completed-prefix progress contracts.
const std = @import("std");

/// Legacy generation retains its requested-budget schedule; indexed-v1 has a fixed schedule.
pub const Policy = enum {
    legacy,
    indexed_v1,

    /// Accept only explicitly versioned public policy spellings.
    pub fn parse(text: []const u8) ?Policy {
        if (std.mem.eql(u8, text, "legacy")) return .legacy;
        if (std.mem.eql(u8, text, "indexed-v1")) return .indexed_v1;
        return null;
    }

    /// Canonical CLI and receipt policy name.
    pub fn name(self: Policy) []const u8 {
        return switch (self) {
            .legacy => "legacy",
            .indexed_v1 => "indexed-v1",
        };
    }
};

/// Fixed size-schedule period, independent of the requested passing-run budget.
pub const indexed_period = 100;
/// Indexed searches checkpoint only whole, bounded batches.
pub const chunk_limit = 128;
pub const maximum_clauses = 4096;
/// The CLI permits at most one million passes and ten times as many discards.
pub const maximum_ordinal = 11_000_000;

/// Named preconditions in first-occurrence order, preserving exhaustion tie behavior.
pub const Clause = struct { message: []const u8, count: u64 };
/// Only classified passing/discarded inputs advance this contiguous prefix.
pub const Progress = struct {
    next_ordinal: u64 = 0,
    passed: u64 = 0,
    discarded: u64 = 0,
    clauses: []const Clause = &.{},

    /// Reject malformed accounting before it can restore search state.
    pub fn valid(self: Progress, a: std.mem.Allocator) error{OutOfMemory}!bool {
        if (self.next_ordinal > maximum_ordinal or self.clauses.len > maximum_clauses) return false;
        const total = std.math.add(u64, self.passed, self.discarded) catch return false;
        if (total != self.next_ordinal) return false;
        var messages: std.StringHashMapUnmanaged(void) = .empty;
        defer messages.deinit(a);
        var discarded: u64 = 0;
        for (self.clauses) |clause| {
            if (clause.count == 0) return false;
            const entry = try messages.getOrPut(a, clause.message);
            if (entry.found_existing) return false;
            discarded = std.math.add(u64, discarded, clause.count) catch return false;
        }
        return discarded == self.discarded;
    }
};

/// Publication guards abort the search; unavailable cache writes may simply lose reuse.
pub const CommitError = error{ OutOfMemory, ReadFailed, WriteFailed, ComponentUnavailable, SourceChanged };
/// Validate inputs and publish a safe prefix, or abort without reporting campaign success.
pub const Callback = struct {
    context: *anyopaque,
    commit: *const fn (*anyopaque, Progress) CommitError!void,
};
/// A verified prior prefix and its optional guarded checkpoint publisher.
pub const Campaign = struct { restored: Progress = .{}, callback: ?Callback = null };
