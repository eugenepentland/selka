//! Verified positive test receipts; missing or damaged entries are cache misses.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const same = @import("native_test_snapshot.zig").equivalent;
/// Filesystem and serialization failures while recording a successful result.
pub const Error = fs.Error || std.Io.Writer.Error || std.Io.Dir.DeleteFileError;
/// The contract and selected-provider identities a receipt now uses, plus the
/// resolved-source identity retained for diagnostics. Reuse is decided by
/// the semantic dependency-closure key in `hit`, not by `source`.
pub const Identity = struct {
    contract: []const u8 = "",
    provider: []const u8 = "",
    /// Diagnostic resolved-source identity; intentionally not an acceptance term.
    source: []const u8 = "",
};
/// Planner reasons and the replacement's identity evidence, grouped so the
/// result keeps its flat wire form without growing one field per identity.
pub const Context = struct { reasons: []const []const u8 = &.{}, identity: Identity = .{} };
/// Reported result and its semantic invalidation evidence.
pub const Result = struct {
    name: []const u8,
    status: []const u8,
    actual: std.json.Value = .null,
    expected: std.json.Value = .null,
    reason: []const u8 = "",
    key: []const u8 = "",
    dependencies: []const []const u8 = &.{},
    cacheable: bool = false,
    steps: u64 = 0,
    context: Context = .{},

    /// Serialize with `reasons` and the three identities flat, preserving the
    /// existing native-tests-v1 wire shape while keeping the struct compact.
    pub fn jsonStringify(self: Result, writer: anytype) !void {
        try writer.write(.{
            .name = self.name,
            .status = self.status,
            .actual = self.actual,
            .expected = self.expected,
            .reason = self.reason,
            .key = self.key,
            .dependencies = self.dependencies,
            .cacheable = self.cacheable,
            .reasons = self.context.reasons,
            .steps = self.steps,
            .contract = self.context.identity.contract,
            .provider = self.context.identity.provider,
            .source = self.context.identity.source,
        });
    }
};
/// A receipt is valid when its semantic dependency-closure key, selected
/// contract and selected-provider identities still match. The resolved-source
/// `source` identity is diagnostic only: unrelated edits intentionally keep a
/// valid closure's result reusable.
pub fn hit(context: fs.Context, filename: []const u8, key: []const u8, name: []const u8, expected: std.json.Value, identity: Identity) bool {
    const bytes = context.read(filename) catch return false;
    const parsed = std.json.parseFromSlice(std.json.Value, context.allocator, bytes, .{}) catch return false;
    const payload = v.text(v.get(parsed.value, "payload"));
    const digest = fs.hash(context.allocator, payload) catch return false;
    if (!std.mem.eql(u8, digest, v.text(v.get(parsed.value, "sha256")))) return false;
    const item = std.json.parseFromSlice(std.json.Value, context.allocator, payload, .{}) catch return false;
    return std.mem.eql(u8, v.text(v.get(item.value, "key")), key) and
        std.mem.eql(u8, v.text(v.get(item.value, "name")), name) and
        std.mem.eql(u8, v.text(v.get(item.value, "status")), "passed") and
        std.mem.eql(u8, v.text(v.get(item.value, "contract")), identity.contract) and
        std.mem.eql(u8, v.text(v.get(item.value, "provider")), identity.provider) and
        same(v.get(item.value, "actual"), expected) and same(v.get(item.value, "expected"), expected);
}
/// A rerun must remove any old success before it can fail or be interrupted.
pub fn invalidate(context: fs.Context, filename: []const u8) Error!void {
    std.Io.Dir.cwd().deleteFile(context.io, filename) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
}
/// One recorded pass-or-fail outcome replayed by the opt-in signature-pure path.
/// A failure keeps its recorded message so a replay never masks it as a pass.
pub const Outcome = struct {
    status: []const u8,
    actual: std.json.Value = .null,
    reason: []const u8 = "",
};
/// Read a recorded pass-or-fail outcome, accepting it only when the integrity
/// envelope verifies and the semantic key, name, contract, provider and expected
/// value still match. A positive-only receipt is a miss for a failure, which is
/// exactly the gap the pure path fills; a corrupt or mismatched entry is a miss.
pub fn outcome(context: fs.Context, filename: []const u8, key: []const u8, name: []const u8, expected: std.json.Value, identity: Identity) ?Outcome {
    const bytes = context.read(filename) catch return null;
    const parsed = std.json.parseFromSlice(std.json.Value, context.allocator, bytes, .{}) catch return null;
    const payload = v.text(v.get(parsed.value, "payload"));
    const digest = fs.hash(context.allocator, payload) catch return null;
    if (!std.mem.eql(u8, digest, v.text(v.get(parsed.value, "sha256")))) return null;
    const item = std.json.parseFromSlice(std.json.Value, context.allocator, payload, .{}) catch return null;
    if (!std.mem.eql(u8, v.text(v.get(item.value, "key")), key)) return null;
    if (!std.mem.eql(u8, v.text(v.get(item.value, "name")), name)) return null;
    if (!std.mem.eql(u8, v.text(v.get(item.value, "contract")), identity.contract)) return null;
    if (!std.mem.eql(u8, v.text(v.get(item.value, "provider")), identity.provider)) return null;
    if (!same(v.get(item.value, "expected"), expected)) return null;
    const status = v.text(v.get(item.value, "status"));
    if (std.mem.eql(u8, status, "passed")) {
        if (!same(v.get(item.value, "actual"), expected)) return null;
        return .{ .status = "passed", .actual = expected };
    }
    if (!std.mem.eql(u8, status, "failed")) return null;
    return .{ .status = "failed", .actual = v.get(item.value, "actual"), .reason = v.text(v.get(item.value, "reason")) };
}
/// Publish only successful deterministic executions, after source integrity checks.
pub fn write(context: fs.Context, directory: []const u8, result: Result) Error!void {
    if (!result.cacheable or !std.mem.eql(u8, result.status, "passed")) return;
    try publish(context, directory, result);
}
/// Publish a pure outcome, pass or fail, so an opt-in replay can report the
/// recorded result without executing. Only `--pure-skip` calls this, and only
/// for a case that is both signature-pure and effect-cacheable.
pub fn writeOutcome(context: fs.Context, directory: []const u8, result: Result) Error!void {
    if (!result.cacheable) return;
    if (!std.mem.eql(u8, result.status, "passed") and !std.mem.eql(u8, result.status, "failed")) return;
    try publish(context, directory, result);
}
/// Write one checksummed outcome envelope at the content-addressed result path.
/// The closure's symbol list is left out: the key already binds the closure,
/// no reader consults the list, and in a large project it made every receipt
/// tens of kilobytes to write, read, parse and checksum.
fn publish(context: fs.Context, directory: []const u8, result: Result) Error!void {
    var stored = result;
    stored.dependencies = &.{};
    const payload = try std.json.Stringify.valueAlloc(context.allocator, stored, .{});
    const bytes = try std.json.Stringify.valueAlloc(context.allocator, .{ .payload = payload, .sha256 = try fs.hash(context.allocator, payload) }, .{});
    try context.atomic(try path(context, directory, result.key), bytes);
}
/// Content-addressed result entry, separate from native object artifacts.
pub fn path(context: fs.Context, directory: []const u8, key: []const u8) Error![]const u8 {
    return std.fs.path.join(context.allocator, &.{ directory, try std.fmt.allocPrint(context.allocator, "{s}.json", .{key}) });
}

test "positive receipts reject corruption mismatched expectations and failures" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const result: Result = .{ .name = "test_ok", .status = "passed", .actual = .{ .bool = true }, .expected = .{ .bool = true }, .key = "abc", .cacheable = true };
    const filename = try path(context, directory, result.key);
    try std.testing.expect(!hit(context, filename, "abc", result.name, result.expected, .{}));
    try write(context, directory, result);
    try std.testing.expect(hit(context, filename, "abc", result.name, result.expected, .{}));
    try std.testing.expect(!hit(context, filename, "abc", result.name, .{ .bool = false }, .{}));
    try context.write(filename, "{\"payload\":\"bad\",\"sha256\":\"bad\"}");
    try std.testing.expect(!hit(context, filename, "abc", result.name, result.expected, .{}));
    try write(context, directory, result);
    try invalidate(context, filename);
    var failed = result;
    failed.status = "failed";
    try write(context, directory, failed);
    try std.testing.expect(!hit(context, filename, "abc", result.name, result.expected, .{}));
}

// spec-case: NATIVE-TEST-3
test "receipt identity binds its semantic key contract and provider, not the whole snapshot" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const identity: Identity = .{ .contract = "contract-a", .provider = "provider-a", .source = "snapshot-a" };
    const result: Result = .{
        .name = "test_ok",
        .status = "passed",
        .actual = .{ .bool = true },
        .expected = .{ .bool = true },
        .key = "identity-key",
        .cacheable = true,
        .context = .{ .identity = identity },
    };
    const filename = try path(context, directory, result.key);
    try write(context, directory, result);
    try std.testing.expect(hit(context, filename, result.key, result.name, result.expected, identity));
    // An unrelated source edit keeps the selected closure and contracts valid.
    try std.testing.expect(hit(context, filename, result.key, result.name, result.expected, .{ .contract = identity.contract, .provider = identity.provider, .source = "snapshot-b" }));
    // A changed closure, contract or provider no longer matches the receipt.
    try std.testing.expect(!hit(context, filename, "other-key", result.name, result.expected, identity));
    try std.testing.expect(!hit(context, filename, result.key, result.name, result.expected, .{ .contract = "contract-b", .provider = identity.provider, .source = identity.source }));
    try std.testing.expect(!hit(context, filename, result.key, result.name, result.expected, .{ .contract = identity.contract, .provider = "provider-b", .source = identity.source }));
}

// spec-case: PURE-SKIP-1
test "a recorded pure failure replays with its message and rejects changed identity" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const identity: Identity = .{ .contract = "contract-a", .provider = "provider-a", .source = "snapshot-a" };
    const failure: Result = .{
        .name = "test_bad",
        .status = "failed",
        .actual = .{ .bool = false },
        .expected = .{ .bool = true },
        .reason = "expected true, got false",
        .key = "pure-key",
        .cacheable = true,
        .context = .{ .identity = identity },
    };
    const filename = try path(context, directory, failure.key);
    try std.testing.expect(outcome(context, filename, failure.key, failure.name, failure.expected, identity) == null);
    try writeOutcome(context, directory, failure);
    const recorded = outcome(context, filename, failure.key, failure.name, failure.expected, identity).?;
    try std.testing.expectEqualStrings("failed", recorded.status);
    try std.testing.expectEqualStrings("expected true, got false", recorded.reason);
    try std.testing.expect(!recorded.actual.bool);
    // A changed key, name, contract, provider or expected value is a miss.
    try std.testing.expect(outcome(context, filename, "other-key", failure.name, failure.expected, identity) == null);
    try std.testing.expect(outcome(context, filename, failure.key, "other-name", failure.expected, identity) == null);
    try std.testing.expect(outcome(context, filename, failure.key, failure.name, failure.expected, .{ .contract = "contract-b", .provider = identity.provider, .source = identity.source }) == null);
    try std.testing.expect(outcome(context, filename, failure.key, failure.name, failure.expected, .{ .contract = identity.contract, .provider = "provider-b", .source = identity.source }) == null);
    try std.testing.expect(outcome(context, filename, failure.key, failure.name, .{ .bool = false }, identity) == null);
    // A recorded pass still reads as a pass and is never confused with a failure.
    const pass: Result = .{
        .name = "test_ok",
        .status = "passed",
        .actual = .{ .bool = true },
        .expected = .{ .bool = true },
        .key = "pass-key",
        .cacheable = true,
        .context = .{ .identity = identity },
    };
    try writeOutcome(context, directory, pass);
    const passed = outcome(context, try path(context, directory, pass.key), pass.key, pass.name, pass.expected, identity).?;
    try std.testing.expectEqualStrings("passed", passed.status);
    try std.testing.expect(passed.actual.bool);
}

// spec-case: NATIVE-TEST-PLAN-2
test "a published receipt leaves out the closure's symbol list and is still accepted by its key" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const closure = [_][]const u8{ "myl_f_one", "myl_f_two" };
    const result: Result = .{ .name = "main::test_ok", .status = "passed", .actual = .{ .bool = true }, .expected = .{ .bool = true }, .key = "closure-key", .dependencies = &closure, .cacheable = true };
    try write(context, directory, result);
    const filename = try path(context, directory, result.key);
    const stored = try context.read(filename);
    try std.testing.expect(std.mem.indexOf(u8, stored, "myl_f_one") == null);
    try std.testing.expect(hit(context, filename, result.key, result.name, result.expected, .{}));
}
