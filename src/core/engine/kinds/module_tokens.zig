//! The `module-tokens` kind (test-loop stage 6, D-TL6-1): a module source as the check reads it. The argument is the
//! source's path as the test runner names it (absolute, like the files of a `test-report` record, which is the kind's one
//! reader); the kind reads the file and returns the digest of its tokens with comments, blank lines, trailing whitespace and
//! line numbers left out (`test_runner_tokens.digest`, which the runner hands the kind as its data, so this file names none
//! of the front end's code). A file the lexer refuses is keyed by its bytes, and an absent one by its absence, so the kind
//! never fails a reader. A report that reads its sources through this kind stays valid across a comment edit or a line
//! shift: the file's read changes, the kind is computed again, and its result does not (the engine's early cutoff).
const std = @import("std");
const context = @import("../context.zig");
const digest_rules = @import("../digest.zig");

/// Where the kind gets the digest of a source's tokens: null when the lexer refuses the bytes.
pub const Source = struct {
    digest: *const fn (a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!?[32]u8,
};

/// `tokens <hex>` for a source the lexer reads, `bytes <hex>` for one it refuses, `absent` for no file. Without the
/// runner's data (a query through `selka engine`) the query fails and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    if (ctx.frame.kind.data == null) return error.Failed;
    const source = ctx.kindData(Source);
    const bytes = (try ctx.file(argument)) orelse return "absent";
    if (try source.digest(ctx.arena, bytes)) |found| return std.fmt.allocPrint(ctx.arena, "tokens {s}", .{digest_rules.hex(found)});
    return std.fmt.allocPrint(ctx.arena, "bytes {s}", .{digest_rules.hex(digest_rules.hash(bytes))});
}
