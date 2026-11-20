//! The probe kind: the size and digest of one file, `<bytes> <hex digest>`. It is the engine's own smallest real query:
//! one read through the context, so `selka engine query engine-probe PATH` shows a record, a served answer and a
//! changed read through the real filesystem.
const std = @import("std");
const context = @import("../context.zig");
const digest_rules = @import("../digest.zig");

/// The size and BLAKE3 digest of the file named by `argument`; the query fails when there is no such file.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const bytes = (try ctx.file(argument)) orelse return error.Failed;
    return std.fmt.allocPrint(ctx.arena, "{d} {s}", .{ bytes.len, digest_rules.hex(digest_rules.hash(bytes)) });
}
