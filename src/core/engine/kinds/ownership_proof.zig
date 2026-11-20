//! The `ownership-proof` kind (spec §14, §17.2): which functions of one module have passed the ownership check, and under what
//! inputs.
//!
//! The argument names the entry the proofs belong to, the ownership mode and the module (`entry`, a zero byte, `mode`, a zero
//! byte, `module`). Its parts are `proof:<function>@<16 hex digits of the digest>`, a proof for each state of each function of the
//! module that was checked and passed (up to four a function), holding the digest of the inputs the function was checked under, as the front end held them in the run that proved it (its receipt: the
//! key, the dependency context and the region of source for a function the semantic planner stands in for; its body and the
//! declarations it reaches for any other). A function is proven while the front end, holding the same inputs now, computes a
//! digest the record holds. The engine supplies the record and the front end supplies the comparison, so no digest is ever
//! taken from a record to stand for one computed this run (D-48).
//!
//! The kind reads nothing. Its record is a function of its argument and of the code that decides ownership (the kind's
//! identity covers it), and the ownership cache publishes a new record when the parts it computes differ from the parts the record
//! holds. This is interim (G1): once the front end's own queries are on the engine by default (G2g), this kind reads the
//! `module-check` and `module-passes` parts of its module, as spec §17.2 states, instead of carrying digests in its answer.
//!
//! The body returns the answer the ownership cache hands it when it publishes a group (`ownership_proofs.zig`), with no reads. A
//! query asked when the cache has no answer for it fails and stores nothing, which verify mode counts as unverifiable; the cache's
//! own verify mode is the other half of the net: it checks a sample of the functions whose proofs it holds.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");

/// What the front end computed for one module: the payload and the parts, in byte order of their names.
pub const Answer = struct { payload: []const u8, parts: []const record.Part };

/// Where the kind gets the front end's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// The module's proofs as the front end computed them. A module the front end has not described fails the query and stores
/// nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const source = ctx.kindData(Source);
    const answer = source.answer(source.context, argument) orelse return error.Failed;
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}
