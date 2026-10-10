//! Current-invocation key derivation work; report once per provider group.
const wire = @import("mylang").cache_plan_adapter.incremental_protocol;

/// Canonical computations, admitted facts, internal misses, and decoded records.
pub const Facts = struct { fresh: usize = 0, reused: usize = 0, fallback: usize = 0, decoded: usize = 0 };
/// Complete prior revision admission and current graph/key candidate work.
pub const Graph = struct { nodes_read: usize = 0, nodes_unchanged: usize = 0, changed_nodes: usize = 0, candidate_tests: usize = 0, shards_read: usize = 0, shards_written: usize = 0 };

/// Actual producer computations and deferred raw body restores.
pub const Producer = struct { facts: Facts = .{}, lowering: struct { fresh: usize = 0, reused: usize = 0, materialized: usize = 0 } = .{} };
/// Inclusive total and disjoint host intervals, all in monotonic wall nanoseconds.
pub const Times = struct { lowering: u64 = 0, facts: u64 = 0, graph: u64 = 0, planner: u64 = 0, keys: u64 = 0, publication: u64 = 0, total: u64 = 0 };
/// Diagnostic work is attached to only the first verdict of each provider group.
/// Whole-report replay constructs fresh cache explanations and carries no historic work.
pub const Work = struct {
    scope: []const u8,
    producer: Producer = .{},
    graph: Graph = .{},
    planner: wire.Work = .{},
    storage: @import("stage_pack.zig").Statistics = .{},
    nanoseconds: Times = .{},
    transport: wire.Transport = .{},
};
