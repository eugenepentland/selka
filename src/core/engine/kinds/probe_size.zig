//! The second probe kind: only the size of the file the probe kind describes. It reads nothing itself; it queries the
//! probe, so a file edited to other bytes of the same length recomputes the probe and leaves this query served: the
//! early cutoff, through the real filesystem.
const std = @import("std");
const context = @import("../context.zig");

/// The size part of the probe's answer for the file named by `argument`. The kind's data is the probe kind.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const probe: *const context.Kind = ctx.kindData(context.Kind);
    const answer = try ctx.query(probe, argument);
    const text = try answer.payload();
    const space = std.mem.indexOfScalar(u8, text, ' ') orelse return error.Failed;
    return ctx.arena.dupe(u8, text[0..space]);
}
