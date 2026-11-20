//! Current-invocation key derivation work; report once per provider group.
const std = @import("std");
const wire = @import("selka").cache_plan_adapter.incremental_protocol;

/// Canonical computations, admitted facts, internal misses, decoded records, and the groups whose one record gave every member
/// its fact (`test_runner_facts.groups`).
pub const Facts = struct { fresh: usize = 0, reused: usize = 0, fallback: usize = 0, decoded: usize = 0, groups: usize = 0 };
/// Complete prior revision admission and current graph/key candidate work.
pub const Graph = struct { nodes_read: usize = 0, nodes_unchanged: usize = 0, changed_nodes: usize = 0, candidate_tests: usize = 0, shards_read: usize = 0, shards_written: usize = 0 };

/// Actual producer computations and deferred raw body restores, and why the stored-facts path gave way to a complete lowering
/// when it did (the error's name, empty when it did not): every entry that reports one pays a whole lowering per run.
/// `lowering.by_part` counts the functions keyed by the engine's `module-check` part instead of their trees (stage 4).
pub const Producer = struct { facts: Facts = .{}, lowering: struct { fresh: usize = 0, reused: usize = 0, materialized: usize = 0, by_part: usize = 0 } = .{}, refused: []const u8 = "" };
/// Inclusive total and disjoint host intervals, all in monotonic wall nanoseconds.
pub const Times = struct { lowering: u64 = 0, facts: u64 = 0, graph: u64 = 0, planner: u64 = 0, keys: u64 = 0, publication: u64 = 0, total: u64 = 0 };
/// What the shared tier's portability rule (`test_runner_portable.zig`) did for one entry's run: `evaluations` runs of the
/// tier's rule (`test_runner_eligibility.Table.decide` deciding an argument), `paths` paths it resolved and took the real
/// path of (`Paths.relative`), and `proofs` walks of a test's call tree by the receipt proof (`portable.refusal`), wherever
/// the runner or the rule made one.
pub const Rule = struct { evaluations: usize = 0, paths: usize = 0, proofs: usize = 0 };

/// `Rule` while the entry runs: counted from whichever thread decides a record, read once the entry has published.
pub const RuleCounters = struct {
    evaluations: std.atomic.Value(usize) = .init(0),
    paths: std.atomic.Value(usize) = .init(0),
    proofs: std.atomic.Value(usize) = .init(0),

    /// Add one run of the tier's rule.
    pub fn evaluated(self: *RuleCounters) void {
        _ = self.evaluations.fetchAdd(1, .monotonic);
    }

    /// Add one resolved path.
    pub fn resolved(self: *RuleCounters) void {
        _ = self.paths.fetchAdd(1, .monotonic);
    }

    /// Add one walk of a test's call tree.
    pub fn proved(self: *RuleCounters) void {
        _ = self.proofs.fetchAdd(1, .monotonic);
    }

    /// The counts so far.
    pub fn snapshot(self: *const RuleCounters) Rule {
        return .{ .evaluations = self.evaluations.load(.monotonic), .paths = self.paths.load(.monotonic), .proofs = self.proofs.load(.monotonic) };
    }
};

/// Diagnostic work is attached to only the first verdict of each provider group; `rule` is the entry's, on its first group.
/// Whole-report replay constructs fresh cache explanations and carries no historic work.
pub const Work = struct {
    scope: []const u8,
    producer: Producer = .{},
    graph: Graph = .{},
    planner: wire.Work = .{},
    storage: @import("stage_pack.zig").Statistics = .{},
    nanoseconds: Times = .{},
    transport: wire.Transport = .{},
    rule: Rule = .{},
};
