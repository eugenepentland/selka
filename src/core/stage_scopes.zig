//! The route of every stage-record scope: `shared` records live in the per-user stage store (`stage-artifacts-v1`), and
//! `private` records stay in the work directory. A scope the table does not list is private, so a new scope is never
//! shared by accident. Each shared scope had equal bytes under equal keys in two work directories built from one commit
//! (lane M, M0). `stage_scopes_test.zig` checks that every scope literal of `src/core` is listed here.
const std = @import("std");

/// Where the records of one scope are stored.
pub const Route = enum { shared, private };

/// The route of a scope name. A scope absent from the table is private.
pub const table = std.StaticStringMap(Route).initComptime(.{
    // Lowering receipts and the bodies they restore (L1 row 1). `demand-raw-*` stays private until a build saves one.
    .{ "lowering-receipt-v7", .shared },
    .{ "lowering-module-receipts-v1", .shared },
    .{ "lowered-function-v15", .shared },
    .{ "lowered-function-v16", .shared },
    .{ "lowered-body-refs-v4", .shared },
    .{ "lowered-header-source-v10", .shared },
    .{ "demand-raw-v2", .private },
    .{ "demand-raw-source-v3", .private },
    .{ "demand-raw-external-v2", .private },
    // Optimizer records (L1 rows 2 and 3). `first_facts` and `debug` are stage names no build saved in M0.
    .{ "optimizer-chunk-v3", .shared },
    .{ "optimizer-head-v3", .shared },
    .{ "optimizer-joins-v1", .shared },
    .{ "optimizer-latest-v1", .shared },
    .{ "optimizer-fusion-v1", .shared },
    .{ "inline_leaf", .shared },
    .{ "inline_cfg", .shared },
    .{ "unswitch", .shared },
    .{ "parameter_inline", .shared },
    .{ "final", .shared },
    .{ "final-facts", .shared },
    .{ "first_facts", .private },
    .{ "debug", .private },
    // Emission and native receipts (L1 row 4; Q2 cleared them by M0).
    .{ "llvm-unit-v1", .shared },
    .{ "llvm-helper-seed-v1", .shared },
    .{ "llvm-compact-receipt-v2", .shared },
    .{ "native-unit-receipt-v1", .shared },
    // Last-writer and per-tree state (L1 rows 6, 8, 9).
    .{ "optimizer-manifest-v10", .private },
    .{ "optimizer-shortcut-v2", .private },
    // The key of the assembly record's file (`lowering_assembly.zig`); the record is a file of the work directory, not a stage record.
    .{ "lowering-assembly-v1", .private },
    // Not part of a build's records; private by design.
    .{ "static-cost-function-v1", .private },
    // Test-runner planning records, in the test runner's own private store.
    .{ "core-test-function-facts-v3", .private },
    .{ "core-test-function-edges-v1", .private },
    .{ "core-test-function-fact-group-v1", .private },
    .{ "test-graph-head-v1", .private },
    .{ "test-graph-nodes-v1", .private },
    .{ "test-graph-tests-v1", .private },
    .{ "test-graph-indexes-v1", .private },
    // The driver's remark record, keyed by the query store (not the stage store); listed so the scan is complete.
    .{ "llvm-optimization-record-v1:cc-c-Wno-override-module-fsave-optimization-record", .private },
    // Test-only scope literals inside `src/core` (their tests save them in private stores).
    .{ "roots-test", .private },
    .{ "bounded-test", .private },
    .{ "maintain-test", .private },
});

/// The route of `scope`: shared only when the table lists it as shared.
pub fn routeOf(scope: []const u8) Route {
    return table.get(scope) orelse .private;
}

/// Whether a different payload under one key of `scope` replaces the stored record instead of being a mismatch. A lowering
/// receipt's key names its function and its inputs, not its source proofs, and a receipt is validated against the proofs
/// on every use: a newer value under the same key is the current one. A module's record of receipts (G2p) is keyed by the
/// module's signature and file and holds the receipts of its functions, so a build that lowers one it did not hold replaces it.
/// The optimizer's latest-state pointer (`optimizer_chunks.Latest`) is keyed by a project, which no edit moves, and holds the
/// state some tree published last: the newer one replaces the older, and a reader treats it as a hint it checks.
/// Every other shared record is pure in its key.
pub fn replaces(scope: []const u8) bool {
    return std.mem.eql(u8, scope, "lowering-receipt-v7") or std.mem.eql(u8, scope, "lowering-module-receipts-v1") or std.mem.eql(u8, scope, "optimizer-latest-v1");
}

/// Whether a scope's records depend on more than their key: the artifact of a lowered function is replayed into the module the
/// build is making, and what it says about the types the function touches depends on which of them lowering found there and
/// which it made, so two programs that lower the same function (one key) in another order store another artifact. The shared
/// store keeps the first (`packs.State.unseen`); a build whose own artifact it refused keeps that one in its work directory,
/// and reads the work directory's before the shared store's (`stage_store.Store.loadFound`). Every other shared record is
/// the same bytes under one key.
pub fn privateFirst(scope: []const u8) bool {
    return std.mem.eql(u8, scope, "lowered-function-v15") or std.mem.eql(u8, scope, "lowered-function-v16") or std.mem.eql(u8, scope, "lowered-header-source-v10");
}

/// The stage whose code produces a scope's records, and whose identity keys them (`stage_store.Store.key`). A scope
/// absent from this table is keyed by the whole compiler identity, which is always safe: a new scope never inherits a
/// narrower identity by accident. `test_runner` is the test runner's planning stage (`build_identity_rules.stage_names`).
pub const Stage = enum { front, lower, opt, emit, test_runner, whole };

/// The number of stages, `whole` included.
pub const stage_count = std.enums.values(Stage).len;

/// The stage of each scope the table lists. Ownership proofs stay whole (the M1 design, §4). The test runner's facts and
/// graph records are keyed by the test-runner stage: their bytes come from lowered bodies, and a graph's per-test keys
/// carry the whole identity as data (`base`), which validates them on load (E6, `test_runner_graph.zig`).
pub const stage_table = std.StaticStringMap(Stage).initComptime(.{
    .{ "lowering-receipt-v7", .lower },
    .{ "lowering-module-receipts-v1", .lower },
    .{ "lowered-function-v15", .lower },
    .{ "lowered-function-v16", .lower },
    .{ "lowered-body-refs-v4", .lower },
    .{ "lowered-header-source-v10", .lower },
    .{ "demand-raw-v2", .lower },
    .{ "demand-raw-source-v3", .lower },
    .{ "demand-raw-external-v2", .lower },
    .{ "optimizer-chunk-v3", .opt },
    .{ "optimizer-head-v3", .opt },
    .{ "optimizer-joins-v1", .opt },
    .{ "optimizer-latest-v1", .opt },
    .{ "optimizer-manifest-v10", .opt },
    .{ "optimizer-shortcut-v2", .opt },
    .{ "optimizer-fusion-v1", .opt },
    .{ "inline_leaf", .opt },
    .{ "inline_cfg", .opt },
    .{ "unswitch", .opt },
    .{ "parameter_inline", .opt },
    .{ "final", .opt },
    .{ "final-facts", .opt },
    .{ "first_facts", .opt },
    .{ "debug", .opt },
    .{ "core-test-function-facts-v3", .test_runner },
    .{ "core-test-function-fact-group-v1", .test_runner },
    .{ "test-graph-head-v1", .test_runner },
    .{ "test-graph-nodes-v1", .test_runner },
    .{ "test-graph-tests-v1", .test_runner },
    .{ "test-graph-indexes-v1", .test_runner },
    .{ "llvm-unit-v1", .emit },
    .{ "llvm-helper-seed-v1", .emit },
    .{ "llvm-compact-receipt-v2", .emit },
    .{ "native-unit-receipt-v1", .emit },
});

/// Every scope the stage table names, so a test can check each one against the route table.
pub const stage_scope_names = [_][]const u8{
    "lowering-receipt-v7", "lowering-module-receipts-v1", "lowered-function-v15",    "lowered-function-v16",             "lowered-body-refs-v4",        "lowered-header-source-v10",
    "demand-raw-v2",       "demand-raw-source-v3",        "demand-raw-external-v2",  "optimizer-chunk-v3",               "optimizer-head-v3",           "optimizer-joins-v1",
    "optimizer-latest-v1", "optimizer-manifest-v10",      "optimizer-shortcut-v2",   "optimizer-fusion-v1",              "inline_leaf",                 "inline_cfg",
    "unswitch",            "parameter_inline",            "final",                   "final-facts",                      "first_facts",                 "debug",
    "llvm-unit-v1",        "llvm-helper-seed-v1",         "llvm-compact-receipt-v2", "native-unit-receipt-v1",           "core-test-function-facts-v3", "test-graph-head-v1",
    "test-graph-nodes-v1", "test-graph-tests-v1",         "test-graph-indexes-v1",   "core-test-function-fact-group-v1",
};

/// The stage of `scope`: the table's stage, or `whole` for an unlisted scope.
pub fn stageOf(scope: []const u8) Stage {
    return stage_table.get(scope) orelse .whole;
}

test "G2p a module's record of receipts is shared, replaces its predecessor under one key, and is keyed by the lowering stage" {
    try std.testing.expectEqual(Route.shared, routeOf("lowering-module-receipts-v1"));
    try std.testing.expect(replaces("lowering-module-receipts-v1"));
    try std.testing.expect(replaces("lowering-receipt-v7"));
    try std.testing.expect(!replaces("lowered-function-v16"));
    try std.testing.expectEqual(Stage.lower, stageOf("lowering-module-receipts-v1"));
}

test "F54 the scopes of a lowered function's artifact and header are read from the work directory first, and no other scope is" {
    try std.testing.expect(privateFirst("lowered-function-v16"));
    try std.testing.expect(privateFirst("lowered-function-v15"));
    try std.testing.expect(privateFirst("lowered-header-source-v10"));
    try std.testing.expect(!privateFirst("lowered-body-refs-v4"));
    try std.testing.expect(!privateFirst("optimizer-chunk-v3"));
    try std.testing.expect(!privateFirst("lowering-receipt-v7"));
    try std.testing.expectEqual(Route.shared, routeOf("lowered-function-v16"));
}

test "a scope is shared only when the table names it so, and an unlisted scope is private" {
    try std.testing.expectEqual(Route.shared, routeOf("lowering-receipt-v7"));
    try std.testing.expectEqual(Route.shared, routeOf("lowered-function-v16"));
    try std.testing.expectEqual(Stage.lower, stageOf("lowered-function-v16"));
    try std.testing.expectEqual(Route.private, routeOf("optimizer-shortcut-v2"));
    try std.testing.expectEqual(Route.private, routeOf("a-scope-nobody-listed"));
    try std.testing.expectEqual(Route.private, routeOf("demand-raw-source-v3"));
}

test "the optimizer's manifest, whose refs carry the unmixed lowering key, is private and retained with the optimizer's records" {
    try std.testing.expectEqual(Route.private, routeOf("optimizer-manifest-v10"));
    try std.testing.expectEqual(Stage.opt, stageOf("optimizer-manifest-v10"));
    try std.testing.expectEqual(Route.private, routeOf("optimizer-manifest-v7"));
    try std.testing.expectEqual(Stage.opt, stageOf("optimizer-chunk-v3"));
    try std.testing.expectEqual(Route.shared, routeOf("optimizer-chunk-v3"));
}
