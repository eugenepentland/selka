//! What `selka-core test` prints: the old runner's per-test lines and summary line, or a
//! JSON report with the same `name`/`status`/`reason` keys as `selka test --json`
//! (`native-tests-v1`), plus the `unsupported` status the old runner has no use for.
const std = @import("std");
const hidden_prefix = @import("selka").project.hidden_segment_prefix;

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
    /// What the verdict explains besides its status: its property evidence and its
    /// trial's work. Grouped so a verdict stays within the seven-field shape.
    details: Details = .{},
    /// Current invocation decision, independent of its eventual test verdict.
    cache: ?Cache = null,
    /// What a test run against providers was accepted under (NATIVE-TEST-5).
    identity: ?Identity = null,
};

/// A verdict's property evidence and trial work (NEW-CORE-TEST-WORK-1).
pub const Details = struct {
    /// The selected ownership rule when Core refuses this trial's construction.
    rule: ?@import("selka").ownership_rules.Rule = null,
    /// Exact property trial and counterexample evidence when this is a property.
    property: ?@import("test_runner_property.zig").Evidence = null,
    /// The trial's work when it ran, or what its receipt recorded: the executed blocks
    /// of program functions and the peak managed bytes.
    counts: ?Counts = null,
    /// The `work:` line this run's comparison produced, if it crossed the threshold.
    /// The runner writes it; it never enters the JSON report.
    work_line: []const u8 = "",
    /// What the author could do about this failure, in a sentence: set for a test that returned `false` (`false_advice`),
    /// empty for any other. Printed on a line of its own after the failure's text, and a field of the JSON report.
    advice: []const u8 = "",
};

/// The advice for a test that returned `false` (FR19, the user's answer on F-18): the runner can say only that the returned
/// expression was false, not which of its facts, while a failing `assert left == right` names both values.
pub const false_advice = "this test returned false from one expression, so the report cannot say which fact failed: write one `assert` " ++
    "for each fact, and a failing `assert left == right` prints both values";

/// One test trial's work: the blocks of program functions it executed (the step
/// ceiling's own count) and the peak managed bytes it held, in the byte ceiling's
/// accounting (`test_work.Counts`). `allocations` is not reported: the ceiling's
/// accounting charges 64 KiB chunks and large blocks, not block events, so counting
/// events would add work to every allocation (docs/tooling/guest-tests.md#work-per-test).
pub const Counts = @import("test_work.zig").Counts;

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

/// Count `verdicts`' execution-tier hits (`cached` with reason `engine-program-hit`)
/// and saves (a pass with an execution key).
pub fn executionCounts(verdicts: []const Verdict) ExecutionCounts {
    var counts: ExecutionCounts = .{};
    for (verdicts) |verdict| {
        const cache = verdict.cache orelse continue;
        const reason = cache.reason;
        const hit = std.mem.eql(u8, reason, "engine-program-hit");
        if (verdict.status == .cached and hit) counts.hits += 1;
        if (verdict.status == .passed and cache.execution_key != null) counts.saves += 1;
    }
    return counts;
}

/// The identities of a provider test's acceptance, as hex digests: the production
/// declarations its providers replace, the providers' sources, and the run's inputs.
pub const Identity = struct { contract: []const u8, provider: []const u8, source: []const u8 };

/// The process exit status for a run: 1 when any test failed or could not be built (`unsupported`: the core is the only back
/// end, so such a test did not run, FX10), 3 when none was selected or every selected test was skipped (not a green run, as
/// the old core), else 0.
pub fn exitStatus(verdicts: []const Verdict) u8 {
    var ran = false;
    for (verdicts) |verdict| {
        if (verdict.status == .failed or verdict.status == .unsupported) return 1;
        ran = ran or verdict.status != .skipped;
    }
    return if (ran) 0 else 3;
}

/// The word `--json`'s `result` gives a run, from the same rule as `exitStatus`: `failed`, `nothing ran` or `passed`.
fn resultWord(verdicts: []const Verdict) []const u8 {
    return switch (exitStatus(verdicts)) {
        1 => "failed",
        3 => "nothing ran",
        else => "passed",
    };
}

fn count(verdicts: []const Verdict, status: Status) usize {
    var total: usize = 0;
    for (verdicts) |verdict| total += @intFromBool(verdict.status == status);
    return total;
}

/// A test's name as a person reads it: a module segment that spells a hidden folder (`__hidden_tmp`) shows as the folder (`.tmp`), so a
/// test file `.tmp/x_test.selka` reports `.tmp.x_test::test_a`, not `__hidden_tmp.x_test::test_a`. The report's JSON keeps the name as is.
const Shown = struct {
    name: []const u8,

    /// Writes the name with each hidden-folder segment spelled as the folder.
    pub fn format(self: Shown, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var at: usize = 0;
        while (at < self.name.len) {
            const starts_segment = at == 0 or self.name[at - 1] == '.';
            const follows = at + hidden_prefix.len;
            const hidden = starts_segment and std.mem.startsWith(u8, self.name[at..], hidden_prefix) and follows < self.name.len and
                (std.ascii.isAlphanumeric(self.name[follows]) or self.name[follows] == '_');
            if (hidden) {
                try writer.writeByte('.');
                at = follows;
                continue;
            }
            try writer.writeByte(self.name[at]);
            at += 1;
        }
    }
};

/// The text report: one line per test (`passed NAME`, `failed NAME: REASON`,
/// `unsupported NAME: E_CORE_UNSUPPORTED (REASON) at L:C`), then the old runner's summary
/// line, with `, N unsupported` appended only when some test was refused and
/// `, N exec-receipt hits` only when execution receipts answered some. A test whose
/// work crossed the 2x threshold also gets its `work:` line after its own line.
pub fn text(allocator: std.mem.Allocator, verdicts: []const Verdict) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (verdicts) |verdict| switch (verdict.status) {
        .passed => {
            try out.print(allocator, "passed {f}", .{Shown{ .name = verdict.name }});
            if (verdict.details.property) |evidence| if (evidence.campaign) |campaign|
                try out.print(allocator, " ({d} property ordinals classified, {d} reused)", .{ campaign.fresh_classified, campaign.reused });
            try out.append(allocator, '\n');
        },
        .cached => try out.print(allocator, "cached {f}\n", .{Shown{ .name = verdict.name }}),
        .skipped => try out.print(allocator, "skipped {f}: {s}\n", .{ Shown{ .name = verdict.name }, verdict.reason }),
        .failed => {
            try out.print(allocator, "failed {f}: {s}\n", .{ Shown{ .name = verdict.name }, std.mem.trimEnd(u8, verdict.reason, "\n") });
            if (verdict.details.advice.len != 0) try out.print(allocator, "  advice: {s}\n", .{verdict.details.advice});
        },
        .unsupported => {
            try out.print(allocator, "unsupported {f}: E_CORE_UNSUPPORTED ({s})", .{ Shown{ .name = verdict.name }, verdict.reason });
            if (verdict.at.len != 0) try out.print(allocator, " at {s}", .{verdict.at});
            try out.appendSlice(allocator, "\n");
            if (verdict.details.rule) |rule| try out.print(allocator, "  note: ownership rule {s}\n", .{@tagName(rule)});
        },
    };
    for (verdicts) |verdict| if (verdict.details.work_line.len != 0) try out.print(allocator, "{s}\n", .{verdict.details.work_line});
    try out.print(allocator, "{d} passed, {d} cached, {d} failed, {d} skipped", .{ count(verdicts, .passed), count(verdicts, .cached), count(verdicts, .failed), count(verdicts, .skipped) });
    const refused = count(verdicts, .unsupported);
    if (refused != 0) try out.print(allocator, ", {d} unsupported (not built, so not run: the run fails)", .{refused});
    const executions = executionCounts(verdicts);
    if (executions.hits != 0) try out.print(allocator, ", {d} exec-receipt hits", .{executions.hits});
    try out.appendSlice(allocator, "\n");
    return out.toOwnedSlice(allocator);
}

/// The JSON report: `{"version":"native-tests-v1","tests":[{"name","status","reason","at","steps","peak_bytes"}],"passed":…,"failed":…,"skipped":0,"cached":0,"unsupported":…,"exec_receipts":{"hits":…,"saves":…}}`.
/// `steps` and `peak_bytes` are present when the test's trial ran (or its receipt
/// recorded them) and absent otherwise (NEW-CORE-TEST-WORK-1).
pub fn json(allocator: std.mem.Allocator, verdicts: []const Verdict) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(allocator, "{\"version\":\"native-tests-v1\",\"tests\":[");
    for (verdicts, 0..) |verdict, position| {
        if (position != 0) try out.appendSlice(allocator, ",");
        try out.appendSlice(allocator, "{\"name\":");
        try quoted(allocator, &out, verdict.name);
        try out.print(allocator, ",\"status\":\"{s}\",\"reason\":", .{@tagName(verdict.status)});
        try quoted(allocator, &out, verdict.reason);
        if (verdict.details.advice.len != 0) {
            try out.appendSlice(allocator, ",\"advice\":");
            try quoted(allocator, &out, verdict.details.advice);
        }
        try out.appendSlice(allocator, ",\"at\":");
        try quoted(allocator, &out, verdict.at);
        if (verdict.details.rule) |rule| try out.print(allocator, ",\"rule\":\"{s}\"", .{@tagName(rule)});
        if (verdict.identity) |identity| try out.print(allocator, ",\"contract\":\"{s}\",\"provider\":\"{s}\",\"source\":\"{s}\"", .{ identity.contract, identity.provider, identity.source });
        if (verdict.details.counts) |counts| try out.print(allocator, ",\"steps\":{d},\"peak_bytes\":{d}", .{ counts.steps, counts.peak_bytes });
        if (verdict.cache) |cache| {
            try out.appendSlice(allocator, ",\"cache\":");
            const encoded = try std.json.Stringify.valueAlloc(allocator, cache, .{});
            defer allocator.free(encoded);
            try out.appendSlice(allocator, encoded);
        }
        if (verdict.details.property) |evidence| {
            try out.appendSlice(allocator, ",\"property\":");
            try out.appendSlice(allocator, try std.json.Stringify.valueAlloc(allocator, evidence, .{}));
        }
        try out.appendSlice(allocator, "}");
    }
    const executions = executionCounts(verdicts);
    const counts = .{ count(verdicts, .passed), count(verdicts, .failed), count(verdicts, .skipped), count(verdicts, .cached), count(verdicts, .unsupported), executions.hits, executions.saves };
    try out.print(allocator, "],\"passed\":{d},\"failed\":{d},\"skipped\":{d},\"cached\":{d},\"unsupported\":{d},\"exec_receipts\":{{\"hits\":{d},\"saves\":{d}}}", counts);
    try out.print(allocator, ",\"result\":\"{s}\"}}\n", .{resultWord(verdicts)});
    return out.toOwnedSlice(allocator);
}

test "a test file under a hidden folder reports the folder, not the reserved module spelling, and the JSON keeps the name" {
    const a = std.testing.allocator;
    const verdicts = [_]Verdict{
        .{ .name = "__hidden_tmp.deep.x_test::test_a", .status = .passed },
        .{ .name = "app.__hidden_.y::test_b", .status = .cached },
        .{ .name = "rows.more_test::test_c", .status = .failed, .reason = "no" },
        .{ .name = "__hidden_tmp.z_test::test_d", .status = .unsupported, .reason = "borrowed storage", .at = "4:5" },
    };
    const rendered = try text(a, &verdicts);
    defer a.free(rendered);
    try std.testing.expect(std.mem.startsWith(u8, rendered, "passed .tmp.deep.x_test::test_a\ncached app.__hidden_.y::test_b\nfailed rows.more_test::test_c: no\n"));
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\nunsupported .tmp.z_test::test_d: E_CORE_UNSUPPORTED (borrowed storage) at 4:5\n") != null);
    const encoded = try json(a, &verdicts);
    defer a.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"name\":\"__hidden_tmp.deep.x_test::test_a\"") != null);
}

// spec-case: EXEC-RECEIPT-1
test "reports count execution-receipt hits and saves in JSON and name hits in the summary line" {
    const a = std.testing.allocator;
    const verdicts = [_]Verdict{
        .{ .name = "app::test_hit", .status = .cached, .cache = .{ .action = "reuse", .reason = "engine-program-hit", .component = "", .execution_key = "11" } },
        .{ .name = "app::test_again", .status = .cached, .cache = .{ .action = "reuse", .reason = "engine-program-hit", .component = "", .execution_key = "22" } },
        .{ .name = "app::test_saved", .status = .passed, .cache = .{ .action = "execute", .reason = "no-success-receipt", .component = "", .execution_key = "33" } },
        .{ .name = "app::test_ir", .status = .cached, .cache = .{ .action = "reuse", .reason = "engine-hit", .component = "" } },
    };
    const encoded = try json(a, &verdicts);
    defer a.free(encoded);
    try std.testing.expect(std.mem.endsWith(u8, encoded, ",\"exec_receipts\":{\"hits\":2,\"saves\":1},\"result\":\"passed\"}\n"));
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

test "ownership unsupported verdict names its rule once and ordinary verdict bytes stay unchanged" {
    const a = std.testing.allocator;
    const owned: Verdict = .{ .name = "m::test_owned", .status = .unsupported, .reason = "borrowed storage", .at = "2:3", .details = .{ .rule = .Z3 } };
    const rendered = try text(a, &.{owned});
    defer a.free(rendered);
    try std.testing.expectEqualStrings("unsupported m::test_owned: E_CORE_UNSUPPORTED (borrowed storage) at 2:3\n  note: ownership rule Z3\n" ++
        "0 passed, 0 cached, 0 failed, 0 skipped, 1 unsupported (not built, so not run: the run fails)\n", rendered);
    const encoded = try json(a, &.{owned});
    defer a.free(encoded);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, encoded, "\"rule\":\"Z3\""));
    var plain = owned;
    plain.details.rule = null;
    const ordinary = try json(a, &.{plain});
    defer a.free(ordinary);
    try std.testing.expectEqualStrings("{\"version\":\"native-tests-v1\",\"tests\":[{\"name\":\"m::test_owned\",\"status\":\"unsupported\"," ++
        "\"reason\":\"borrowed storage\",\"at\":\"2:3\"}],\"passed\":0,\"failed\":0,\"skipped\":0,\"cached\":0," ++
        "\"unsupported\":1,\"exec_receipts\":{\"hits\":0,\"saves\":0},\"result\":\"failed\"}\n", ordinary);
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
