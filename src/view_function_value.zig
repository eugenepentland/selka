//! Signature probes for borrowing function values; Core owns their V4 refusal.
const typed = @import("typed.zig");
const return_borrow = @import("return_borrow.zig");

/// Whether the declared return contract effectively borrows managed storage.
pub fn borrowsResult(records: []const typed.Record, function: typed.Function) bool {
    return return_borrow.effectiveSources(records, function.signature).len != 0;
}
