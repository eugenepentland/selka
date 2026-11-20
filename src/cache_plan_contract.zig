//! Wave 1 admits pure disposable success evidence; durable contracts fail closed.
/// Declared computation behavior.
pub const Computation = enum { pure, completed_exploration, measurement, live_effect, recorded_effect };
/// Storage retention guarantee.
pub const Retention = enum { disposable, durable };
/// Recovery commit guarantee.
pub const Commit = enum { cache_publication, durable_checkpoint };
/// Retry behavior for unfinished work.
pub const Retry = enum { pure_recompute, recorded_replay, idempotent_effect, reconcile_effect };
/// Future run and stable step occurrence identity, distinct from content identity.
pub const Execution = struct { run: []const u8, step: []const u8 };
/// Explicit policy; defaults describe only the current compiler cache.
pub const Policy = struct {
    computation: Computation = .pure,
    retention: Retention = .disposable,
    commit: Commit = .cache_publication,
    retry: Retry = .pure_recompute,
    execution: ?Execution = null,
    success_only: bool = true,
    /// Reject unsupported recovery/effect contracts rather than weaken guarantees.
    pub fn validate(self: Policy) error{UnsupportedCacheContract}!void {
        if (self.computation != .pure or self.retention != .disposable) return error.UnsupportedCacheContract;
        if (self.commit != .cache_publication or self.retry != .pure_recompute) return error.UnsupportedCacheContract;
        if (self.execution != null or !self.success_only) return error.UnsupportedCacheContract;
    }
};
