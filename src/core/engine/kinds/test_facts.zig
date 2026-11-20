//! The `test-facts` kind (spec §17.7, step G4e): the planning facts the test runner records for one lowered function, and the
//! chunks of callee identities a fact too long to hold inline points to.
//!
//! These were the stage store's `core-test-function-facts-v2` and `core-test-function-edges-v1` scopes. The argument is the
//! 32-byte key the runner addresses a record by (`test_runner_facts.factKey`, `chunkKey`): it names the function's raw digest,
//! its places and the declaration catalog it was taken under for a fact, and the bytes of the chunk for a chunk, and it
//! carries the identity of the test-runner stage. The payload is the record's encoded value. Everything the value depends on is in
//! the argument, so the kind reads nothing: a record is valid for as long as it exists, and a chunk is checked against the digest
//! of its bytes by the runner when it loads one.
//!
//! The body does not compute a fact. The runner computes it from the lowering it already has and hands it to the kind through
//! its data (`Source`) when it records one; a query asked when the runner has nothing for it fails and stores nothing, so a miss
//! only loses reuse.
const std = @import("std");
const context = @import("../context.zig");

/// Where the kind gets the value the runner computed: a function over an opaque context, so this file imports none of the
/// runner's code. Null means the runner has no value for the argument.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?[]const u8,
};

/// The value the runner offered for `argument`. A query with no offer fails (`error.Failed`) and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const source = ctx.kindData(Source);
    return source.answer(source.context, argument) orelse error.Failed;
}
