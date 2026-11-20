//! The third probe kind: whether the file the probe describes is small or large. It queries the size, which queries the
//! probe, so an edit that changes a file's bytes but not its size recomputes the probe and the size and leaves this
//! query served, and an edit that changes the size but not the class leaves only this one cut off.
const std = @import("std");
const context = @import("../context.zig");

/// The largest size, in bytes, that is still "small".
pub const small_limit = 1024;

/// `small` or `large` by the size the size query gives for the file named by `argument`. The kind's data is the
/// size kind.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const size_kind: *const context.Kind = ctx.kindData(context.Kind);
    const answer = try ctx.query(size_kind, argument);
    const size = std.fmt.parseInt(u64, try answer.payload(), 10) catch return error.Failed;
    return if (size <= small_limit) "small" else "large";
}
