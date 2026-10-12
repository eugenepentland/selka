//! What `mylang-core test` prints: the old runner's per-test lines and summary line, or a
//! JSON report with the same `name`/`status`/`reason` keys as `mylang test --json`
//! (`native-tests-v1`), plus the `unsupported` status the old runner has no use for.
const std = @import("std");

/// How one test ended.
pub const Status = enum {
    passed,
    cached,
    skipped,
    failed,
    /// The new core refuses a feature the test uses (`E_CORE_UNSUPPORTED`): neither a pass nor a failure.
    unsupported,
};

/// One test's verdict.
pub const Verdict = struct {
    /// `module::test_x`.
    name: []const u8,
    status: Status,
    /// Why it failed or is unsupported; failure reasons may span several lines (a trap's frames).
    reason: []const u8 = "",
    /// `line:column` of the refused construct, for an unsupported test.
    at: []const u8 = "",
    /// Exact property trial and counterexample evidence when this is a property.
    property: ?@import("test_runner_property.zig").Evidence = null,
    /// Current invocation decision, independent of its eventual test verdict.
    cache: ?Cache = null,
    /// What a test run against providers was accepted under (NATIVE-TEST-5).
    identity: ?Identity = null,
};

/// Reuse evidence is disposable and authorizes only a completed deterministic success.
pub const Cache = struct {
    action: []const u8,
    reason: []const u8,
    key: ?[]const u8 = null,
    component: []const u8,
    key_method: []const u8 = "reachable-ir",
    work: ?*const @import("test_runner_work.zig").Work = null,
    /// The test's execution-tier key (EXEC-RECEIPT-1) when that tier was consulted:
    /// the key it hit, or the key a pass saved.
    execution_key: ?[]const u8 = null,
};

/// The execution tier's work in one report: tests it answered without a trial, and
/// passes that saved an execution receipt.
pub const ExecutionCounts = struct { hits: usize = 0, saves: usize = 0 };

/// Count `verdicts`' execution-receipt hits (`cached` with reason `exec-receipt-hit`
/// or `whole-exec-receipt-hit`) and saves (a pass with an execution key).
pub fn executionCounts(verdicts: []const Verdict) ExecutionCounts {
    var counts: ExecutionCounts = .{};
    for (verdicts) |verdict| {
        const cache = verdict.cache orelse continue;
        const reason = cache.reason;
        const hit = std.mem.eql(u8, reason, "exec-receipt-hit") or std.mem.eql(u8, reason, "whole-exec-receipt-hit");
        if (verdict.status == .cached and hit) counts.hits += 1;
        if (verdict.status == .passed and cache.execution_key != null) counts.saves += 1;
    }
    return counts;
}

/// The identities of a provider test's acceptance, as hex digests: the production
/// declarations its providers replace, the providers' sources, and the run's inputs.
pub const Identity = struct { contract: []const u8, provider: []const u8, source: []const u8 };

/// The process exit status for a run: 1 when any test failed, 3 when none was selected
/// or every selected test was skipped (not a green run, as the old core), else 0.
pub fn exitStatus(verdicts: []const Verdict) u8 {
    var ran = false;
    for (verdicts) |verdict| {
        if (verdict.status == .failed) return 1;
        ran = ran or verdict.status != .skipped;
    }
    return if (ran) 0 else 3;
}

fn count(verdicts: []const Verdict, status: Status) usize {
    var total: usize = 0;
    for (verdicts) |verdict| total += @intFromBool(verdict.status == status);
    return total;
}

/// The text report: one line per test (`passed NAME`, `failed NAME: REASON`,
/// `unsupported NAME: E_CORE_UNSUPPORTED (REASON) at L:C`), then the old runner's summary
/// line, with `, N unsupported` appended only when some test was refused and
/// `, N exec-receipt hits` only when execution receipts answered some.
pub fn text(allocator: std.mem.Allocator, verdicts: []const Verdict) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (verdicts) |verdict| switch (verdict.status) {
        .passed => {
            try out.print(allocator, "passed {s}", .{verdict.name});
            if (verdict.property) |evidence| if (evidence.campaign) |campaign|
                try out.print(allocator, " ({d} property ordinals classified, {d} reused)", .{ campaign.fresh_classified, campaign.reused });
            try out.append(allocator, '\n');
        },
        .cached => try out.print(allocator, "cached {s}\n", .{verdict.name}),
        .skipped => try out.print(allocator, "skipped {s}: {s}\n", .{ verdict.name, verdict.reason }),
        .failed => try out.print(allocator, "failed {s}: {s}\n", .{ verdict.name, std.mem.trimEnd(u8, verdict.reason, "\n") }),
        .unsupported => {
            try out.print(allocator, "unsupported {s}: E_CORE_UNSUPPORTED ({s})", .{ verdict.name, verdict.reason });
            if (verdict.at.len != 0) try out.print(allocator, " at {s}", .{verdict.at});
            try out.appendSlice(allocator, "\n");
        },
    };
    try out.print(allocator, "{d} passed, {d} cached, {d} failed, {d} skipped", .{ count(verdicts, .passed), count(verdicts, .cached), count(verdicts, .failed), count(verdicts, .skipped) });
    const refused = count(verdicts, .unsupported);
    if (refused != 0) try out.print(allocator, ", {d} unsupported", .{refused});
    const executions = executionCounts(verdicts);
    if (executions.hits != 0) try out.print(allocator, ", {d} exec-receipt hits", .{executions.hits});
    try out.appendSlice(allocator, "\n");
    return out.toOwnedSlice(allocator);
}

/// The JSON report: `{"version":"native-tests-v1","tests":[{"name","status","reason","at"}],"passed":…,"failed":…,"skipped":0,"cached":0,"unsupported":…,"exec_receipts":{"hits":…,"saves":…}}`.
pub fn json(allocator: std.mem.Allocator, verdicts: []const Verdict) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(allocator, "{\"version\":\"native-tests-v1\",\"tests\":[");
    for (verdicts, 0..) |verdict, position| {
        if (position != 0) try out.appendSlice(allocator, ",");
        try out.appendSlice(allocator, "{\"name\":");
        try quoted(allocator, &out, verdict.name);
        try out.print(allocator, ",\"status\":\"{s}\",\"reason\":", .{@tagName(verdict.status)});
        try quoted(allocator, &out, verdict.reason);
        try out.appendSlice(allocator, ",\"at\":");
        try quoted(allocator, &out, verdict.at);
        if (verdict.identity) |identity| try out.print(allocator, ",\"contract\":\"{s}\",\"provider\":\"{s}\",\"source\":\"{s}\"", .{ identity.contract, identity.provider, identity.source });
        if (verdict.cache) |cache| {
            try out.appendSlice(allocator, ",\"cache\":");
            const encoded = try std.json.Stringify.valueAlloc(allocator, cache, .{});
            defer allocator.free(encoded);
            try out.appendSlice(allocator, encoded);
        }
        if (verdict.property) |evidence| {
            try out.appendSlice(allocator, ",\"property\":");
            try out.appendSlice(allocator, try std.json.Stringify.valueAlloc(allocator, evidence, .{}));
        }
        try out.appendSlice(allocator, "}");
    }
    const executions = executionCounts(verdicts);
    const counts = .{ count(verdicts, .passed), count(verdicts, .failed), count(verdicts, .skipped), count(verdicts, .cached), count(verdicts, .unsupported), executions.hits, executions.saves };
    try out.print(allocator, "],\"passed\":{d},\"failed\":{d},\"skipped\":{d},\"cached\":{d},\"unsupported\":{d},\"exec_receipts\":{{\"hits\":{d},\"saves\":{d}}}}}\n", counts);
    return out.toOwnedSlice(allocator);
}

// spec-case: EXEC-RECEIPT-1
test "reports count execution-receipt hits and saves in JSON and name hits in the summary line" {
    const a = std.testing.allocator;
    const verdicts = [_]Verdict{
        .{ .name = "app::test_hit", .status = .cached, .cache = .{ .action = "reuse", .reason = "exec-receipt-hit", .component = "", .execution_key = "11" } },
        .{ .name = "app::test_whole", .status = .cached, .cache = .{ .action = "reuse", .reason = "whole-exec-receipt-hit", .component = "", .execution_key = "22" } },
        .{ .name = "app::test_saved", .status = .passed, .cache = .{ .action = "execute", .reason = "no-success-receipt", .component = "", .execution_key = "33" } },
        .{ .name = "app::test_ir", .status = .cached, .cache = .{ .action = "reuse", .reason = "receipt-hit", .component = "" } },
    };
    const encoded = try json(a, &verdicts);
    defer a.free(encoded);
    try std.testing.expect(std.mem.endsWith(u8, encoded, ",\"exec_receipts\":{\"hits\":2,\"saves\":1}}\n"));
    const parsed = try std.json.parseFromSlice(std.json.Value, a, encoded, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 3), parsed.value.object.get("cached").?.integer);
    const rendered = try text(a, &verdicts);
    defer a.free(rendered);
    try std.testing.expect(std.mem.endsWith(u8, rendered, "1 passed, 3 cached, 0 failed, 0 skipped, 2 exec-receipt hits\n"));
    const plain = try text(a, verdicts[2..3]);
    defer a.free(plain);
    try std.testing.expect(std.mem.endsWith(u8, plain, "1 passed, 0 cached, 0 failed, 0 skipped\n"));
}

/// Add the checked source inventory used to account for directory test programs.
pub fn jsonSources(allocator: std.mem.Allocator, verdicts: []const Verdict, sources: []const []const u8) std.mem.Allocator.Error![]u8 {
    const basic = try json(allocator, verdicts);
    defer allocator.free(basic);
    const encoded = try std.json.Stringify.valueAlloc(allocator, sources, .{});
    defer allocator.free(encoded);
    return std.fmt.allocPrint(allocator, "{s},\"sources\":{s}}}\n", .{ basic[0 .. basic.len - 2], encoded });
}

fn quoted(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) std.mem.Allocator.Error!void {
    try out.append(allocator, '"');
    for (value) |byte| switch (byte) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        0...8, 11, 12, 14...31 => try out.print(allocator, "\\u{x:0>4}", .{byte}),
        else => try out.append(allocator, byte),
    };
    try out.append(allocator, '"');
}
