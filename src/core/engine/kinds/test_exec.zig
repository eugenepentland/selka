//! The `test-exec` kind (spec section 13): whether a test passed, under what the test ran with.
//!
//! The argument is `tag || basis || inputs || environment || name`, three 32-byte digests between a one-byte tag and the
//! test's name:
//!
//! - `tag` is `p` when the basis is the digest of the linked program (`driver.Outcome.program_key`: the digest of the linked
//!   bytes, so no read of the binary by path is needed and no key names a path), and `i` when it is the receipts' per-test IR
//!   key (`Selected.identity`), which a test has whether or not its program was linked;
//! - `inputs` digests the run's execution settings, the cases, the configuration and the policy;
//! - `environment` digests the keyed environment, so each environment state has a record of its own and two states can
//!   never overwrite one another's.
//!
//! Everything the verdict depends on is in the argument, so the kind reads nothing: a record is valid for as long as it
//! exists, and its key is what makes it safe (it changes with the program, the settings or the environment). Only a pass is
//! ever recorded and served, as the receipts do; a failing test always runs again. Its code identity is the closure of the
//! runner's verdict code (`build_identity_rules.test_exec_covers`), which replaces the hand-kept runner file list.
//!
//! The body does not run the test: the runner builds and runs a selection's tests in processes of its own, in batches, so
//! it decides before running (it asks the engine whether a valid record serves the argument, `Engine.peek`) and hands the
//! verdict it found to the kind through its data (`Source`) when it records one. The kind's job is the record: the
//! argument, the code identity, and the payload.
//!
//! The payload is the verdict word `passed`, then the test's work when the run reported it (`steps` and `peak_bytes`, one
//! per line), so a reused test reports the numbers of the run that proved it. The result digest covers the verdict word
//! alone: a rerun that reports other numbers is the same result.
const std = @import("std");
const context = @import("../context.zig");
const digest_rules = @import("../digest.zig");

/// Where the kind gets the answer the runner computed: a function over an opaque context, so this file imports none of the
/// runner's code. The answer is the payload `passed`; null means the runner did not run the test.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?[]const u8,
};

/// The verdict the runner found for `argument`. A test the runner did not run, or that failed, fails the query
/// (`error.Failed`) and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const source = ctx.kindData(Source);
    return source.answer(source.context, argument) orelse error.Failed;
}

/// The payload of a test that passed: the only verdict a record holds, because only a pass is ever reused.
pub const passed = "passed";

/// What a test's run reported as its work: executed blocks and the peak of the byte ceiling's accounting.
pub const Work = struct { steps: u64, peak_bytes: u64 };

/// The payload of a pass that reported `work`: the verdict word, then `steps N` and `peak_bytes M` lines.
pub fn payloadOf(a: std.mem.Allocator, work: ?Work) std.mem.Allocator.Error![]const u8 {
    const reported = work orelse return passed;
    return std.fmt.allocPrint(a, "{s}\nsteps {d}\npeak_bytes {d}\n", .{ passed, reported.steps, reported.peak_bytes });
}

/// Whether `payload` records a pass: the verdict word alone, or followed by a line break and the work.
pub fn isPass(payload: []const u8) bool {
    if (!std.mem.startsWith(u8, payload, passed)) return false;
    return payload.len == passed.len or payload[passed.len] == '\n';
}

/// The work a pass payload holds, or null when it holds none or malformed lines.
pub fn workOf(payload: []const u8) ?Work {
    if (!isPass(payload)) return null;
    var steps: ?u64 = null;
    var peak: ?u64 = null;
    var lines = std.mem.splitScalar(u8, payload, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        const name = fields.next() orelse continue;
        const value = std.fmt.parseInt(u64, fields.next() orelse continue, 10) catch continue;
        if (std.mem.eql(u8, name, "steps")) steps = value;
        if (std.mem.eql(u8, name, "peak_bytes")) peak = value;
    }
    return .{ .steps = steps orelse return null, .peak_bytes = peak orelse return null };
}

/// The result digest of a payload: the digest of the verdict word for a pass, whatever work it holds, and of the payload
/// itself otherwise.
pub fn resultDigest(payload: []const u8) digest_rules.Digest {
    return digest_rules.hash(if (isPass(payload)) passed else payload);
}

test "a pass carries its work, and the result digest ignores the numbers" {
    const a = std.testing.allocator;
    const bare = try payloadOf(a, null);
    const counted = try payloadOf(a, .{ .steps = 12, .peak_bytes = 65536 });
    defer a.free(counted);
    try std.testing.expectEqualStrings("passed", bare);
    try std.testing.expectEqualStrings("passed\nsteps 12\npeak_bytes 65536\n", counted);
    try std.testing.expect(isPass(bare) and isPass(counted));
    try std.testing.expectEqual(@as(?Work, null), workOf(bare));
    try std.testing.expectEqual(@as(u64, 65536), workOf(counted).?.peak_bytes);
    try std.testing.expectEqualSlices(u8, &resultDigest(bare), &resultDigest(counted));
    try std.testing.expect(!isPass("passed-not") and !isPass("failed") and !isPass(""));
    try std.testing.expect(!std.mem.eql(u8, &resultDigest("failed"), &resultDigest(bare)));
    try std.testing.expectEqual(@as(?Work, null), workOf("passed\nsteps 3\n"));
}
