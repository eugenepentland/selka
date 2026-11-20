//! The `test-graph` kind (spec §17.7, step G4e): the logical call graph the test runner records for one test entry, and the
//! immutable chunks of its nodes, tests and indexes that the entry's manifest points to.
//!
//! These were the stage store's `test-graph-head-v1`, `-nodes-v1`, `-tests-v1` and `-indexes-v1` scopes. The argument is the
//! 32-byte key the runner addresses a record by (`test_runner_graph`): the head's names the entry's source path, a chunk's is
//! the digest of its encoded bytes, and both carry the identity of the test-runner stage. The payload is the record's encoded
//! value. A chunk is immutable and checked against its key when it loads; the head is replaced as a whole by a newer generation
//! (the runner publishes the chunks first and the manifest last), so a reader sees a complete generation or none.
//!
//! The kind reads nothing and does not compute: the runner hands it the value it built through its data (`Source`) when it
//! records one, and a query with no offer fails and stores nothing, so a miss only loses reuse.
const std = @import("std");
const context = @import("../context.zig");

/// Where the kind gets the value the runner computed (see `test_facts.Source`).
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?[]const u8,
};

/// The value the runner offered for `argument`. A query with no offer fails (`error.Failed`) and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const source = ctx.kindData(Source);
    return source.answer(source.context, argument) orelse error.Failed;
}
